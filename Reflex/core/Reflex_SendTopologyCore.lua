-- @noindex
-- Reflex send topology core module.
-- Installs SEND topology analysis, list/group build, and refresh helpers.

ReflexInstallSendTopologyCore = function(deps)
    local r = deps.r

-- Analyze send topology for a source track.
-- For each send, traces the destination's parent chain upward until it
-- intersects the source's parent chain. The intersection is the "merge point"
-- where the send signal recombines with the dry signal.
--
-- Returns a table of entries (one per send):
--   { dest       = MediaTrack*,      -- send destination track
--     send_idx   = int,              -- send index (category 0)
--     merge      = MediaTrack*|nil,  -- merge point track (nil = master bus)
--     depth      = int,              -- levels from source to merge (1=parent, 2=grandparent...)
--     path       = {track, ...},     -- dest → intermediate folders → merge (inclusive)
--     vol        = number,           -- send volume (D_VOL)
--     pan        = number,           -- send pan (D_PAN)
--     mode       = int,              -- send mode (0=Post, 1=Pre, 3=PreFX)
--     muted      = bool }            -- send muted
--
-- depth interpretation:
--   1 = dest is sibling (dest's parent == source's parent)
--   2 = dest is cousin (merge is grandparent of source)
--   3+ = distant
--
-- Requires SWS BR_GetMediaTrackSendInfo_Track for destination resolution.
AnalyzeSendTopology = function(source_track)
    if not source_track or not r.ValidatePtr(source_track, "MediaTrack*") then return {} end
    if not r.BR_GetMediaTrackSendInfo_Track then return {} end

    local MAX_DEPTH = 8

    -- Build source parent chain: ordered list + lookup set
    local src_chain = {}      -- [1]=source, [2]=parent, [3]=grandparent...
    local src_set = {}        -- track → depth index in src_chain
    src_chain[1] = source_track
    src_set[source_track] = 1
    local p = r.GetParentTrack(source_track)
    local d = 2
    while p and d <= MAX_DEPTH do
        src_chain[d] = p
        src_set[p] = d
        p = r.GetParentTrack(p)
        d = d + 1
    end

    local results = {}
    local num_sends = r.GetTrackNumSends(source_track, 0)

    for si = 0, num_sends - 1 do
        local dest = r.BR_GetMediaTrackSendInfo_Track(source_track, 0, si, 1)
        if dest and r.ValidatePtr(dest, "MediaTrack*") then

            -- Walk dest's parent chain upward, building path, until we hit src_set
            local path = { dest }
            local merge = nil
            local merge_depth = MAX_DEPTH

            -- Check if dest itself is in source chain (send to own parent/ancestor)
            if src_set[dest] then
                merge = dest
                merge_depth = src_set[dest] - 1  -- 0 if dest==source (shouldn't happen)
                if merge_depth < 1 then merge_depth = 1 end
            else
                -- Walk upward from dest
                local cur = r.GetParentTrack(dest)
                local steps = 0
                while cur and steps < MAX_DEPTH do
                    path[#path + 1] = cur
                    if src_set[cur] then
                        merge = cur
                        -- depth = how far up the source chain the merge is
                        -- src_set[cur] gives index: 1=source, 2=parent, 3=grandparent
                        -- so merge at parent = depth 1, at grandparent = depth 2
                        merge_depth = src_set[cur] - 1
                        if merge_depth < 1 then merge_depth = 1 end
                        break
                    end
                    cur = r.GetParentTrack(cur)
                    steps = steps + 1
                end

                -- If no intersection found, use effective top-level merge
                if not merge then
                    -- Both chains eventually reach master (no parent = top level)
                    -- merge is effectively the topmost track in source chain
                    merge = src_chain[#src_chain] or source_track
                    merge_depth = #src_chain
                end
            end

            results[#results + 1] = {
                dest      = dest,
                send_idx  = si,
                merge     = merge,
                depth     = merge_depth,
                path      = path,
                vol       = r.GetTrackSendInfo_Value(source_track, 0, si, "D_VOL"),
                pan       = r.GetTrackSendInfo_Value(source_track, 0, si, "D_PAN"),
                mode      = math.floor(r.GetTrackSendInfo_Value(source_track, 0, si, "I_SENDMODE")),
                muted     = r.GetTrackSendInfo_Value(source_track, 0, si, "B_MUTE") == 1,
            }
        end
    end

    -- Sort by depth (local sends first), then by send index
    table.sort(results, function(a, b)
        if a.depth ~= b.depth then return a.depth < b.depth end
        return a.send_idx < b.send_idx
    end)

    return results
end

-- Debug: dump topology analysis to REAPER console for the selected track.
-- Call from console: DebugSendTopology()
DebugSendTopology = function()
    local track = insp_track or r.GetSelectedTrack(0, 0)
    if not track then r.ShowConsoleMsg("No track selected\n"); return end
    local _, name = r.GetTrackName(track)
    local num = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
    r.ShowConsoleMsg("\n=== Send Topology: " .. num .. ": " .. name .. " ===\n")
    local results = AnalyzeSendTopology(track)
    if #results == 0 then r.ShowConsoleMsg("  (no sends)\n"); return end
    for i, e in ipairs(results) do
        local _, dn = r.GetTrackName(e.dest)
        local dnum = math.floor(r.GetMediaTrackInfo_Value(e.dest, "IP_TRACKNUMBER"))
        local mn = "MASTER"
        if e.merge then _, mn = r.GetTrackName(e.merge) end
        local mode_lbl = ({[0]="Post",[1]="Pre",[3]="PreFX"})[e.mode] or "?"
        r.ShowConsoleMsg(string.format("  [%d] → %d: %s  depth=%d  merge=%s  mode=%s%s\n",
            e.send_idx, dnum, dn, e.depth, mn, mode_lbl,
            e.muted and "  MUTED" or ""))
        if #e.path > 1 then
            r.ShowConsoleMsg("       path: ")
            for pi, pt in ipairs(e.path) do
                local _, pn = r.GetTrackName(pt)
                if pi > 1 then r.ShowConsoleMsg(" → ") end
                r.ShowConsoleMsg(pn)
            end
            r.ShowConsoleMsg("\n")
        end
    end
    r.ShowConsoleMsg("=== end ===\n")

    -- Dump current sends_view_groups
    r.ShowConsoleMsg("\n--- sends_view_groups (" .. #sends_view_groups .. " groups) ---\n")
    for gi, g in ipairs(sends_view_groups) do
        local fc_names = {}
        for _, ft in ipairs(g.folder_chain) do
            if r.ValidatePtr(ft, "MediaTrack*") then
                local _, fn = r.GetTrackName(ft)
                fc_names[#fc_names + 1] = fn
            else
                fc_names[#fc_names + 1] = "(invalid)"
            end
        end
        r.ShowConsoleMsg(string.format("  Group %d: folders=[%s]  sends=%d [%s]\n",
            gi, table.concat(fc_names, " > "), #g.indices,
            table.concat(g.indices, ",")))
    end
    r.ShowConsoleMsg("--- end groups ---\n")
end

-- Authoritative track for routing operations (Create send, Add receive, etc.).
-- v20.411: when pinned, the pinned track is the "active" context regardless of
-- what sends_view_source cached at activate-time or what's currently selected
-- (a secondary card showing a different track must not capture routing actions
-- intended for the pinned track). When unpinned, fall back to sends_view_source
-- if set (sends view shown for some source) or the current inspected track.
NavRoutingTargetTrack = function()
    if insp_pinned and insp_track and r.ValidatePtr(insp_track, "MediaTrack*") then
        return insp_track
    end
    local t = sends_view_source or insp_track
    if t and r.ValidatePtr(t, "MediaTrack*") then return t end
    return r.GetSelectedTrack(0, 0)
end

SendsViewToggle = function()
    if sends_view_active then
        sends_view_active = false
        sends_view_tracks = {}
        sends_view_send_indices = {}
        sends_view_groups = {}
        sends_view_distant = {}
        sends_view_source = nil
        sends_view_last_send_count = -1
        sends_fx_cache = {}
        return
    end
    local source = insp_pinned and insp_track or (r.GetSelectedTrack(0, 0) or insp_track)
    if not source or not r.ValidatePtr(source, "MediaTrack*") then return end
    sends_view_active = true
    sends_view_source = source
    sends_view_tracks, sends_view_send_indices = SendsViewBuildList(source)
    sends_view_groups = SendsViewBuildGroups(source)
    sends_view_last_send_count = r.GetTrackNumSends(source, 0)
    sends_view_scroll_pending = #sends_view_tracks > 0
end

SendsViewBuildList = function(source)
    local list = {}
    local indices = {}
    if not source or not r.ValidatePtr(source, "MediaTrack*") then return list, indices end
    if not r.BR_GetMediaTrackSendInfo_Track then return list, indices end
    local ns = r.GetTrackNumSends(source, 0)
    for si = 0, ns - 1 do
        local dest = r.BR_GetMediaTrackSendInfo_Track(source, 0, si, 1)
        if dest and r.ValidatePtr(dest, "MediaTrack*") then
            local tn = r.GetMediaTrackInfo_Value(dest, "IP_TRACKNUMBER")
            if tn ~= -1 then
                list[#list + 1] = dest
                indices[#indices + 1] = si
            end
        end
    end
    return list, indices
end

-- Build grouped sends structure from topology analysis.
-- Groups depth-1 sends by their sibling folder (the dest's ancestor that is a direct
-- child of the merge point). Up to 2 folder levels shown per group.
-- Returns ordered list of { folder_chain={track...}, indices={int...} }.
SendsViewBuildGroups = function(source)
    sends_view_distant = {}  -- reset
    if not source or not r.ValidatePtr(source, "MediaTrack*") then return {} end
    local topo = AnalyzeSendTopology(source)
    if #topo == 0 then
        -- No topology data: single ungrouped group with all sends
        local all = {}
        for i = 1, #sends_view_tracks do all[#all + 1] = i end
        if #all == 0 then return {} end
        return { { folder_chain = {}, indices = all } }
    end

    -- Build send_idx → sends_view index lookup
    local si_to_svi = {}
    for svi = 1, #sends_view_send_indices do
        si_to_svi[sends_view_send_indices[svi]] = svi
    end

    -- Map for grouping: outermost_folder_track → group
    local folder_to_group = {}
    local group_order = {}   -- ordered list of outermost folder tracks (first-seen)
    local ungrouped = {}     -- indices for depth-1 sends without folders
    local distant = {}       -- remote/distant sends (rendered as compact cards)
    local classified = {}    -- dedup guard: svi → true

    for _, entry in ipairs(topo) do
        local svi = si_to_svi[entry.send_idx]
        if not svi then goto continue end
        if classified[svi] then goto continue end  -- dedup guard

        local dest_parent = r.GetParentTrack(entry.dest)
        if IsConformingReturnsFolderForSource(source, dest_parent) then
            -- Tight conforming rule: the return must live directly inside a
            -- sibling folder named Returns*. Only these folders get SEND.folder.
            if not folder_to_group[dest_parent] then
                folder_to_group[dest_parent] = { folder_chain = { dest_parent }, indices = {} }
                group_order[#group_order + 1] = dest_parent
            end
            local grp = folder_to_group[dest_parent]
            grp.indices[#grp.indices + 1] = svi
            classified[svi] = true
        elseif entry.depth > 1
            or (#entry.path > 1 and entry.path[#entry.path] ~= entry.merge) then
            -- Remote/nonlocal routing context: deeper merge, or top-level source
            -- sending into an unrelated folder. Same-branch nonconforming
            -- folders stay normal SEND.col, just without SEND.folder.
            local dst_ch = math.floor(r.GetTrackSendInfo_Value(source, 0, entry.send_idx, "I_DSTCHAN"))
            distant[#distant + 1] = {
                svi = svi,
                track = sends_view_tracks[svi],
                send_idx = entry.send_idx,
                is_sidechain = (dst_ch ~= 0),
            }
            classified[svi] = true
        else
            ungrouped[#ungrouped + 1] = svi
            classified[svi] = true
        end

        ::continue::
    end

    -- Safety: any sends_view entries not covered by topology go to ungrouped
    for i = 1, #sends_view_tracks do
        if not classified[i] then ungrouped[#ungrouped + 1] = i; classified[i] = true end
    end

    -- Build final ordered groups list.
    -- Conforming groups (sends inside sibling folders) get folder spanners.
    -- Ungrouped local sends get their own section with no spanners and no add-send cards.
    -- Distant sends are always separate (rendered externally).
    local groups = {}
    for _, folder in ipairs(group_order) do
        groups[#groups + 1] = folder_to_group[folder]
    end
    if #ungrouped > 0 then
        groups[#groups + 1] = { folder_chain = {}, indices = ungrouped, is_ungrouped = (#group_order > 0) }
    end

    -- Sort: non-sidechain first, sidechain at bottom
    table.sort(distant, function(a, b)
        if a.is_sidechain ~= b.is_sidechain then
            if a.is_sidechain then return false end
            return true
        end
        return a.send_idx < b.send_idx
    end)
    sends_view_distant = distant

    return groups
end

SendsViewRefresh = function()
    if not sends_view_active then return end
    local source = insp_pinned and insp_track or (r.GetSelectedTrack(0, 0) or insp_track)
    if not source or not r.ValidatePtr(source, "MediaTrack*") then
        sends_view_tracks = {}; sends_view_send_indices = {}; sends_view_groups = {}; sends_view_distant = {}
        sends_view_source = nil; sends_view_last_send_count = -1; sends_fx_cache = {}
        return
    end
    sends_view_source = source
    sends_view_last_send_count = r.GetTrackNumSends(source, 0)
    sends_view_tracks, sends_view_send_indices = SendsViewBuildList(source)
    sends_view_groups = SendsViewBuildGroups(source)
    -- Clear FX cache for tracks no longer in sends
    local new_set = {}
    for _, t in ipairs(sends_view_tracks) do new_set[t] = true end
    for t in pairs(sends_fx_cache) do
        if not new_set[t] then sends_fx_cache[t] = nil end
    end
end

-- Check if sends need refresh (called each frame, cheap — only counts sends)
-- Also auto-activates/deactivates based on opt_show_sends
SendsViewCheckRefresh = function()
    local source = insp_pinned and insp_track or (r.GetSelectedTrack(0, 0) or insp_track)
    if not source or not r.ValidatePtr(source, "MediaTrack*") then
        if sends_view_active then
            sends_view_active = false; sends_view_tracks = {}; sends_view_send_indices = {}
            sends_view_groups = {}; sends_view_distant = {}
            sends_view_source = nil; sends_view_last_send_count = -1; sends_fx_cache = {}
        end
        return
    end
    local cur_count = r.GetTrackNumSends(source, 0)
    local should_be_active = opt_show_sends and cur_count > 0
    if should_be_active and not sends_view_active then
        sends_view_active = true
        sends_view_source = source
        sends_view_tracks, sends_view_send_indices = SendsViewBuildList(source)
        sends_view_groups = SendsViewBuildGroups(source)
        sends_view_last_send_count = cur_count
        return
    elseif not should_be_active and sends_view_active then
        sends_view_active = false; sends_view_tracks = {}; sends_view_send_indices = {}
        sends_view_groups = {}; sends_view_distant = {}
        sends_view_source = nil; sends_view_last_send_count = -1; sends_fx_cache = {}
        return
    end
    if not sends_view_active then return end
    if source ~= sends_view_source then
        SendsViewRefresh(); return
    end
    if cur_count ~= sends_view_last_send_count then
        SendsViewRefresh(); return
    end
    -- Destination change detection: compare current send dest pointers to cached list.
    -- Catches reroutes that preserve count (swap send target to different track).
    for si = 0, cur_count - 1 do
        local dest = r.BR_GetMediaTrackSendInfo_Track(source, 0, si, 1)
        if dest ~= sends_view_tracks[si + 1] then
            SendsViewRefresh()
            return
        end
    end

    -- Distant SC badge/sort freshness: destination-channel changes preserve
    -- send count and destination pointer, but flip cached `is_sidechain`.
    for _, dentry in ipairs(sends_view_distant) do
        local dst_ch = math.floor(r.GetTrackSendInfo_Value(source, 0, dentry.send_idx, "I_DSTCHAN"))
        if (dst_ch ~= 0) ~= dentry.is_sidechain then
            SendsViewRefresh()
            return
        end
    end
end

end

return ReflexInstallSendTopologyCore
