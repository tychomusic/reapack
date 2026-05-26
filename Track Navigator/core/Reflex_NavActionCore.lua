-- @noindex
-- Reflex shared Navigator action core.
-- Installs TLT/SONGS visibility handlers and utility actions used by Reflex and Navigator.

ReflexInstallNavActionCore = function(deps)
    local r = deps.r
    local markDirty = deps.mark_dirty or function() end

    local function NavSetTrackValueIfNeeded(track, parm, value)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
        if r.GetMediaTrackInfo_Value(track, parm) == value then return false end
        r.SetMediaTrackInfo_Value(track, parm, value)
        return true
    end

    local function NavEnsureTrackVisible(track)
        local changed = false
        changed = NavSetTrackValueIfNeeded(track, "B_SHOWINTCP", 1) or changed
        changed = NavSetTrackValueIfNeeded(track, "B_SHOWINMIXER", 1) or changed
        return changed
    end

    local function NavCaptureTrackSelection()
        local selected = {}
        local count = r.CountSelectedTracks and r.CountSelectedTracks(0) or 0
        for i = 0, count - 1 do
            local track = r.GetSelectedTrack(0, i)
            if track then selected[#selected + 1] = track end
        end
        return selected
    end

    local function NavRestoreTrackSelection(selected)
        if type(selected) ~= "table" then return end
        local nt = r.CountTracks(0)
        for i = 0, nt - 1 do
            local track = r.GetTrack(0, i)
            if track then r.SetTrackSelected(track, false) end
        end
        for _, track in ipairs(selected) do
            if track and r.ValidatePtr(track, "MediaTrack*") then
                r.SetTrackSelected(track, true)
            end
        end
    end

    local function NavCaptureTcpScroll()
        if not (r.JS_Window_FindChildByID and r.JS_Window_GetScrollInfo) then return nil end
        local tcp = r.JS_Window_FindChildByID(r.GetMainHwnd(), 1000)
        if not tcp then return nil end
        local ok, pos = r.JS_Window_GetScrollInfo(tcp, "v")
        if ok and type(pos) == "number" then return pos end
        return nil
    end

    local function NavRestoreTcpScroll(pos)
        if type(pos) ~= "number" or not (r.JS_Window_FindChildByID and r.JS_Window_SetScrollPos) then return end
        local tcp = r.JS_Window_FindChildByID(r.GetMainHwnd(), 1000)
        if tcp then
            r.JS_Window_SetScrollPos(tcp, "v", math.max(0, math.floor(pos + 0.5)))
        end
    end

    local function NavClearListFilters()
        local changed = false
        if opt_nav_custom_set_mode == true then
            opt_nav_custom_set_mode = false
            if SavePref then SavePref("nav_custom_set_mode", false) end
            changed = true
        end
        if (nav_tlt_search_text or "") ~= "" or (nav_tlt_search_effective_query or "") ~= "" then
            nav_tlt_search_text = ""
            nav_tlt_search_effective_query = ""
            nav_tlt_search_hide_clear = true
            nav_tlt_search_recent_clear_frames = 8
            nav_tlt_search_focus_requested_frames = 0
            nav_tlt_search_window_focus_requested_frames = 0
            changed = true
        end
        if changed then markDirty() end
        return changed
    end

    EnsurePinnedVisible = function()
        if next(pinned_folders) == nil then return false end
        local changed = false
        local pending_pins = {}
        local pending_count = 0
        for guid in pairs(pinned_folders) do
            pending_pins[guid] = true
            pending_count = pending_count + 1
        end
        for _, entry in ipairs(top_folders) do
            local guid = r.GetTrackGUID(entry.track)
            if pending_pins[guid] and PinnedTrack(entry.track) then
                pending_pins[guid] = nil
                pending_count = pending_count - 1
                changed = NavEnsureTrackVisible(entry.track) or changed
            end
        end
        if pending_count <= 0 then return changed end
        local nt = r.CountTracks(0)
        for i = 0, nt - 1 do
            local track = r.GetTrack(0, i)
            local guid = r.GetTrackGUID(track)
            if pending_pins[guid]
               and not (NavTrackAutoIgnored and NavTrackAutoIgnored(track))
               and not (NavTrackInHiddenSubtree and NavTrackInHiddenSubtree(track)) then
                pending_pins[guid] = nil
                pending_count = pending_count - 1
                changed = (NavRevealParentChain(track) == true) or changed
                changed = NavEnsureTrackVisible(track) or changed
                if pending_count <= 0 then break end
            end
        end
        return changed
    end

    ScrollTrackToCenter = function(track)
        r.Undo_BeginBlock()
        r.SetOnlyTrackSelected(track)
        if r.JS_Window_FindChildByID then
            local tcp = r.JS_Window_FindChildByID(r.GetMainHwnd(), 1000)
            if tcp then
                -- Apply any pending visibility/expand changes first.
                r.TrackList_AdjustWindows(false)
                -- JS_Window_GetClientSize returns (retval, w, h).
                local _, _, th = r.JS_Window_GetClientSize(tcp)
                local ty = r.GetMediaTrackInfo_Value(track, "I_TCPY")
                local tkh = r.GetMediaTrackInfo_Value(track, "I_TCPH")
                local ok, sp = r.JS_Window_GetScrollInfo(tcp, "v")
                if ok then
                    -- I_TCPY is the track's Y relative to the top of the visible TCP
                    -- area (i.e. relative to current scroll position). Absolute Y
                    -- within the scrollable content = sp + ty. Target scroll = that
                    -- absolute Y minus half the viewport height, plus half the track
                    -- height (so the track's vertical center lands at viewport center).
                    local target = math.max(0, math.floor(sp + ty + tkh/2 - th/2))
                    r.JS_Window_SetScrollPos(tcp, "v", target)
                end
                r.Undo_EndBlock("Track Navigator: Scroll to track", 0)
                return
            end
        end
        -- Fallback when JS_ReaScriptAPI isn't available: REAPER's built-in
        -- "vertical scroll selected tracks into view" lands tracks in the
        -- bottom third, but it's the best we can do without JS_Window APIs.
        r.Main_OnCommand(40913, 0)
        r.Undo_EndBlock("Track Navigator: Scroll to track", 0)
    end

    -- =========================================================================
    -- HELPERS
    -- =========================================================================

    local function NavItemSubGroup(item)
        if not item or item.kind ~= "folder" then return nil end
        if item.sub_group then return item.sub_group end
        if (item.tree_depth or 0) == 0 and not item.ghost_parent and item.entry then
            return sub_group_by_name[item.entry.name]
        end
        return nil
    end

    local function NavItemTrack(item)
        if not item then return nil end
        return item.track or (item.entry and item.entry.track) or nil
    end

    local function NavItemGuid(item)
        local track = NavItemTrack(item)
        if track and r.ValidatePtr(track, "MediaTrack*") then
            return r.GetTrackGUID(track)
        end
        return nil
    end

    local function NavSetTracksRangeAnchor(item)
        tracks_last_click = item and item.label or nil
        tracks_range_anchor_guid = NavItemGuid(item)
    end

    local function NavResolveTracksRangeAnchor()
        if tracks_range_anchor_guid then
            for j, item in ipairs(render_list) do
                if NavItemGuid(item) == tracks_range_anchor_guid then return j end
            end
        end
        if tracks_last_click then
            for j, item in ipairs(render_list) do
                if item.label == tracks_last_click then return j end
            end
        end
        return nil
    end

    HideEverything = function()
        ViewHistoryPush()
        for _, entry in ipairs(top_folders) do
            if not (NavTrackAutoIgnored and NavTrackAutoIgnored(entry.track)) then
                SetFolderVisible(entry, false)
            end
        end
        for _, sg in ipairs(sub_groups) do for _, e in ipairs(sg.entries) do sg.selected[e.display_name] = false end end
        for _, e in ipairs(songs_sub.entries) do songs_sub.selected[e.display_name] = false end
        songs_follow_active = false; songs_section_mode = false
    end

    local function NavHideEverythingWithoutHistory()
        for _, entry in ipairs(top_folders) do
            if not (NavTrackAutoIgnored and NavTrackAutoIgnored(entry.track)) then
                SetFolderVisible(entry, false)
            end
        end
        for _, sg in ipairs(sub_groups) do for _, e in ipairs(sg.entries) do sg.selected[e.display_name] = false end end
        for _, e in ipairs(songs_sub.entries) do songs_sub.selected[e.display_name] = false end
        songs_follow_active = false; songs_section_mode = false
    end

    ShowFolderItem = function(item, expand_all)
        if item and item.entry and item.entry.track then
            NavRevealParentChain(item.entry.track)
        end
        local sg = NavItemSubGroup(item)
        if sg and sg.is_song_sub then
            ShowSongsForCurrentSong(item.entry, expand_all or opt_expand_children)
            -- Mark all song sections selected, exit section mode
            for _, e in ipairs(songs_sub.entries) do songs_sub.selected[e.display_name] = true end
            songs_section_mode = false
        elseif sg then
            -- Show ALL children (not just whitelisted), mark all selected
            SetFolderVisible(item.entry, true)
            for _, e in ipairs(sg.entries) do sg.selected[e.display_name] = true end
        else SetFolderVisible(item.entry, true) end
        SetFolderCollapsed(item.entry, false)
        if expand_all then
            ExpandAllChildFolders(item.entry.track, item.entry.idx)
        elseif opt_expand_children then
            ExpandChildFolders(item.entry.track, item.entry.idx)
        end
        -- When neither: children retain their I_FOLDERCOMPACT (collapse state recall)
    end

    EnsureSongsParentVisible = function()
        if not opt_live_mode then return end
        if songs_entry_ref then
            SetTrackVis(songs_entry_ref.track, true)
            r.SetMediaTrackInfo_Value(songs_entry_ref.track, "I_FOLDERCOMPACT", 0)
        end
    end

    NavTrackIndex = function(track)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return -1 end
        return math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) - 1
    end

    NavRevealParentChain = function(track)
        local parents = {}
        local parent = r.GetParentTrack(track)
        while parent and r.ValidatePtr(parent, "MediaTrack*") do
            parents[#parents + 1] = parent
            parent = r.GetParentTrack(parent)
        end
        local changed = false
        for i = #parents, 1, -1 do
            changed = NavEnsureTrackVisible(parents[i]) or changed
            changed = NavSetTrackValueIfNeeded(parents[i], "I_FOLDERCOMPACT", 0) or changed
        end
        return changed
    end

    NavShowCustomItem = function(item, expand_all)
        if not item or not item.track or not r.ValidatePtr(item.track, "MediaTrack*") then return end
        NavRevealParentChain(item.track)
        local idx = NavTrackIndex(item.track)
        local entry = {
            track = item.track,
            name = item.label,
            color = item.color,
            idx = idx,
        }
        if item.is_folder then
            SetFolderVisible(entry, true)
            SetFolderCollapsed(entry, false)
            if expand_all then ExpandAllChildFolders(item.track, idx)
            elseif opt_expand_children then ExpandChildFolders(item.track, idx) end
        else
            SetTrackVis(item.track, true)
        end
    end

    NavHideCustomItem = function(item)
        if not item or not item.track or not r.ValidatePtr(item.track, "MediaTrack*") then return end
        local idx = NavTrackIndex(item.track)
        local entry = {
            track = item.track,
            name = item.label,
            color = item.color,
            idx = idx,
        }
        if item.is_folder then SetFolderVisible(entry, false)
        else SetTrackVis(item.track, false) end
    end

    local function NavShowRangeItem(item)
        local track = NavItemTrack(item)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
        NavRevealParentChain(track)
        SetTrackVis(track, true)
        if item.kind == "sub_child" and item.sub_group then
            item.sub_group.selected[item.label] = true
        end
    end

    local function NavTrackSubtreeEnd(track, idx)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return idx end
        if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") ~= 1 then return idx end
        local nt = r.CountTracks(0)
        local depth, i = 1, idx + 1
        while i < nt and depth > 0 do
            depth = depth + r.GetMediaTrackInfo_Value(r.GetTrack(0, i), "I_FOLDERDEPTH")
            i = i + 1
        end
        return i - 1
    end

    local function NavTopRootEntry(track)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
        local root = track
        local parent = r.GetParentTrack(root)
        while parent and r.ValidatePtr(parent, "MediaTrack*") do
            root = parent
            parent = r.GetParentTrack(root)
        end
        local idx = NavTrackIndex(root)
        if idx < 0 then return nil end
        local _, name = r.GetTrackName(root)
        return { track = root, name = name, idx = idx }
    end

    local function NavItemSoloWithinRoot(item, root_entry)
        if not item or not item.track or not root_entry then return false end
        if not IsFolderVisible(root_entry) or not IsItemVisible(item) then return false end
        local target_idx = NavTrackIndex(item.track)
        if target_idx < 0 then return false end
        if root_entry.track == item.track then
            return not item.is_folder or FolderSubtreeFullyShown({ track = item.track, idx = target_idx })
        end

        local ancestor_guid = {}
        local parent = r.GetParentTrack(item.track)
        while parent and r.ValidatePtr(parent, "MediaTrack*") and parent ~= root_entry.track do
            ancestor_guid[r.GetTrackGUID(parent)] = true
            parent = r.GetParentTrack(parent)
        end
        if parent ~= root_entry.track then return false end

        local target_end = NavTrackSubtreeEnd(item.track, target_idx)
        local root_end = NavTrackSubtreeEnd(root_entry.track, root_entry.idx)
        for i = root_entry.idx + 1, root_end do
            if i < target_idx or i > target_end then
                local track = r.GetTrack(0, i)
                local guid = r.GetTrackGUID(track)
                if not ancestor_guid[guid]
                   and not (NavTrackAutoIgnored and NavTrackAutoIgnored(track))
                   and r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") == 1 then
                    return false
                end
            end
        end
        return not item.is_folder or FolderSubtreeFullyShown({ track = item.track, idx = target_idx })
    end

    IsAloneVisible = function(item)
        local uses_root_solo_scope = item.custom
            or item.tree_search_result
            or (item.kind == "folder" and (item.tree_depth or 0) > 0)
        local root_entry = item.ghost_parent
            or (uses_root_solo_scope and NavTopRootEntry(item.track))
            or nil
        local vt = 0
        local item_name = root_entry and root_entry.name
            or item.kind == "folder" and item.entry.name
            or (item.kind == "sub_child" and item.sub_group.parent_name or nil)
        for _, entry in ipairs(top_folders) do
            if not (NavTrackAutoIgnored and NavTrackAutoIgnored(entry.track))
               and IsFolderVisible(entry) then
                -- Don't count pinned folders (unless it's the item we're checking)
                if not PinnedTrack(entry.track) or entry.name == item_name then
                    vt = vt + 1
                end
            end
        end
        if uses_root_solo_scope then
            return vt == 1
                and NavItemSoloWithinRoot(item, root_entry)
        end
        if item.ghost_parent then
            return vt == 1
                and NavItemSoloWithinRoot(item, item.ghost_parent)
        end
        if item.kind == "folder" then
            if vt ~= 1 or not IsFolderVisible(item.entry) then return false end
            local sg = NavItemSubGroup(item)
            -- SONGS in section mode: always re-show full song on click
            if sg and sg.is_song_sub and songs_section_mode then return false end
            if item.is_folder and not FolderSubtreeFullyShown(item.entry) then return false end
            -- Sub-group parent: only "alone" when all whitelisted children are visible
            if sg and #sg.entries > 0 then
                for _, e in ipairs(sg.entries) do
                    if r.GetMediaTrackInfo_Value(e.track, "B_SHOWINTCP") ~= 1 then return false end
                end
            end
            return true
        elseif item.kind == "sub_child" then
            if vt ~= 1 then return false end
            local vs = 0
            for _, e in ipairs(item.sub_group.entries) do
                if r.GetMediaTrackInfo_Value(e.track, "B_SHOWINTCP") == 1 then vs = vs + 1 end
            end
            if vs ~= 1 then return false end
            return not item.is_folder or FolderSubtreeFullyShown(item.entry)
        end
        return false
    end

    -- =========================================================================
    -- TRACKS: CLICK HANDLERS
    -- =========================================================================

    HandleTracksSolo = function(ri, is_alt)
        local item = render_list[ri]; local vis = IsItemVisible(item)
        if item.custom then
            if vis and IsAloneVisible(item) then
                if item.is_folder then
                    if is_alt then
                        r.SetMediaTrackInfo_Value(item.track, "I_FOLDERCOMPACT", 0)
                        ExpandAllChildFolders(item.track, item.idx)
                    else
                        local exp = r.GetMediaTrackInfo_Value(item.track, "I_FOLDERCOMPACT") == 0
                        r.SetMediaTrackInfo_Value(item.track, "I_FOLDERCOMPACT", exp and 2 or 0)
                        if not exp and opt_expand_children then ExpandChildFolders(item.track, item.idx) end
                    end
                end
                return false
            end
            HideEverything()
            NavShowCustomItem(item, is_alt)
            return true
        end
        if vis and IsAloneVisible(item) then
            if item.is_folder then
                if is_alt then
                    -- Opt+click alone: ensure expanded, recursively expand all children
                    r.SetMediaTrackInfo_Value(item.track, "I_FOLDERCOMPACT", 0)
                    ExpandAllChildFolders(item.track, item.idx)
                else
                    local exp = r.GetMediaTrackInfo_Value(item.track, "I_FOLDERCOMPACT") == 0
                    r.SetMediaTrackInfo_Value(item.track, "I_FOLDERCOMPACT", exp and 2 or 0)
                    if not exp then
                        if opt_expand_children then ExpandChildFolders(item.track, item.idx) end
                    end
                end
            end
            return false
        end
        HideEverything()
        if item.kind == "folder" then ShowFolderItem(item, is_alt)
        elseif item.kind == "sub_child" then
            if item.sub_group.is_song_sub then
                -- Song section: show only this section within current song
                songs_sub.selected[item.label] = true
                ShowSongSectionsSelected(is_alt or opt_expand_children)
            else
                item.sub_group.selected[item.label] = true; ShowSubGroupSelected(item.sub_group)
            end
            if item.is_folder then
                r.SetMediaTrackInfo_Value(item.track, "I_FOLDERCOMPACT", 0)
                if is_alt then ExpandAllChildFolders(item.track, item.idx)
                elseif opt_expand_children then ExpandChildFolders(item.track, item.idx) end
            end
        end
        return true
    end

    HandleTracksCmd = function(ri, is_alt)
        local item = render_list[ri]
        if item.custom then
            if IsItemVisible(item) then NavHideCustomItem(item)
            else NavShowCustomItem(item, is_alt) end
            return
        end
        if item.kind == "folder" then
            local sg = NavItemSubGroup(item)
            if IsItemVisible(item) then
                if sg then SaveSubGroupState(sg) end
                if sg and sg.is_song_sub then songs_follow_active = false end
                SetFolderVisible(item.entry, false)
            else
                -- Re-show: sub-groups restore saved selection, others show normally
                if sg and sg.is_song_sub then
                    if songs_section_mode then
                        ShowSongSectionsSelected(is_alt or opt_expand_children)
                    else
                        ShowSongsForCurrentSong(item.entry, is_alt or opt_expand_children)
                        for _, e in ipairs(songs_sub.entries) do songs_sub.selected[e.display_name] = true end
                    end
                elseif sg then
                    ShowSubGroupSelected(sg)
                    if is_alt then ExpandAllChildFolders(item.entry.track, item.entry.idx) end
                else
                    NavRevealParentChain(item.entry.track)
                    SetFolderVisible(item.entry, true)
                    SetFolderCollapsed(item.entry, false)
                    if is_alt then ExpandAllChildFolders(item.entry.track, item.entry.idx)
                    elseif opt_expand_children then ExpandChildFolders(item.entry.track, item.entry.idx) end
                end
            end
        elseif item.kind == "sub_child" then
            local sg = item.sub_group
            if sg.is_song_sub then
                -- Song section CMD+click
                if not songs_entry_ref or not IsFolderVisible(songs_entry_ref) then
                    for _, e in ipairs(sg.entries) do sg.selected[e.display_name] = false end
                end
                sg.selected[item.label] = not sg.selected[item.label]
                ShowSongSectionsSelected(is_alt or opt_expand_children)
            else
                if not IsFolderVisible(sg.entry_ref) then
                    for _, e in ipairs(sg.entries) do sg.selected[e.display_name] = false end
                end
                sg.selected[item.label] = not sg.selected[item.label]
                if sg.selected[item.label] and not IsFolderVisible(sg.entry_ref) then
                    SetTrackVis(sg.entry_ref.track, true)
                    r.SetMediaTrackInfo_Value(sg.entry_ref.track, "I_FOLDERCOMPACT", 0)
                end
                ApplySubGroupSelection(sg)
            end
        end
    end

    HandleTracksShift = function(ri)
        if not tracks_last_click and not tracks_range_anchor_guid then HandleTracksSolo(ri); return false end
        local anchor = NavResolveTracksRangeAnchor()
        if not anchor then HandleTracksSolo(ri); return false end
        local lo, hi = math.min(anchor, ri), math.max(anchor, ri)
        HideEverything()
        for j = lo, hi do
            local item = render_list[j]
            NavShowRangeItem(item)
        end
        return true
    end

    HandleTracksClick = function(ri, is_cmd, is_shift, is_alt, is_ctrl)
        ExitSpecialViews()
        ViewHistoryPushTlf()
        local item = render_list[ri]
        local preserve_tcp_state = is_cmd == true and is_shift ~= true and is_ctrl ~= true
        local selected_before = preserve_tcp_state and NavCaptureTrackSelection() or nil
        local tcp_scroll_before = preserve_tcp_state and NavCaptureTcpScroll() or nil
        r.Undo_BeginBlock(); r.PreventUIRefresh(1)
        local do_scroll = true
        local used_range_anchor = false
        if is_shift then used_range_anchor = HandleTracksShift(ri) == true
        elseif is_cmd then
            HandleTracksCmd(ri, is_alt)
            do_scroll = false
        elseif is_ctrl and not is_cmd then
            -- Child-expand chord: expand/collapse folder and all children.
            if item.custom and item.is_folder then
                local is_collapsed = r.GetMediaTrackInfo_Value(item.track, "I_FOLDERCOMPACT") ~= 0
                if is_collapsed then
                    if not IsItemVisible(item) then NavShowCustomItem(item, true) end
                    r.SetMediaTrackInfo_Value(item.track, "I_FOLDERCOMPACT", 0)
                    ExpandAllChildFolders(item.track, item.idx)
                else
                    CollapseChildFolders(item.track, item.idx)
                    r.SetMediaTrackInfo_Value(item.track, "I_FOLDERCOMPACT", 2)
                end
            elseif item.kind == "folder" then
                local is_collapsed = r.GetMediaTrackInfo_Value(item.entry.track, "I_FOLDERCOMPACT") ~= 0
                if is_collapsed then
                    if not IsFolderVisible(item.entry) then ShowFolderItem(item, true) end
                    SetFolderCollapsed(item.entry, false)
                    ExpandAllChildFolders(item.entry.track, item.entry.idx)
                else
                    CollapseChildFolders(item.entry.track, item.entry.idx)
                    SetFolderCollapsed(item.entry, true)
                end
            end
        elseif is_alt and not is_cmd then
            -- Opt+click: toggle pin state for folders, toggle selection for sub_children
            if item.kind == "folder" then
                local track = (item.entry and item.entry.track) or item.track
                local guid = track and r.GetTrackGUID(track) or nil
                if not guid then
                    do_scroll = false
                elseif pinned_folders[guid] then
                    pinned_folders[guid] = nil
                    SavePinnedFolders()
                    markDirty()
                    do_scroll = false
                else
                    pinned_folders[guid] = true
                    SavePinnedFolders()
                    markDirty()
                    do_scroll = false
                end
            elseif item.kind == "sub_child" then
                if item.sub_group.is_song_sub then
                    songs_sub.selected[item.label] = not songs_sub.selected[item.label]
                    ShowSongSectionsSelected(true)
                else
                    item.sub_group.selected[item.label] = not item.sub_group.selected[item.label]
                    if item.sub_group.selected[item.label] and not IsFolderVisible(item.sub_group.entry_ref) then
                        SetTrackVis(item.sub_group.entry_ref.track, true)
                        r.SetMediaTrackInfo_Value(item.sub_group.entry_ref.track, "B_SHOWINMIXER", 1)
                        r.SetMediaTrackInfo_Value(item.sub_group.entry_ref.track, "I_FOLDERCOMPACT", 0)
                    end
                    ApplySubGroupSelection(item.sub_group)
                end
            end
        else do_scroll = HandleTracksSolo(ri, false) end
        SyncGhostVisibility()
        EnsurePinnedVisible()
        r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
        if preserve_tcp_state then
            NavRestoreTrackSelection(selected_before)
            NavRestoreTcpScroll(tcp_scroll_before)
        end
        if (is_shift and not used_range_anchor)
           or (not is_shift and (is_cmd or (not is_alt and not is_ctrl))) then
            NavSetTracksRangeAnchor(item)
        end
        if do_scroll then local st = item.track; r.defer(function() ScrollTrackToCenter(st) end) end
        r.Undo_EndBlock("Track Navigator: " .. item.label, 0)
    end

    local function NavCurrentSearchMatchItems()
        local items = {}
        local seen = {}
        for _, item in ipairs(render_list or {}) do
            if item.tree_search_match == true then
                local track = NavItemTrack(item)
                if track and r.ValidatePtr(track, "MediaTrack*") then
                    local guid = r.GetTrackGUID(track)
                    if guid and not seen[guid] then
                        seen[guid] = true
                        items[#items + 1] = item
                    end
                end
            end
        end
        return items
    end

    ShowTltSearchResults = function()
        local items = NavCurrentSearchMatchItems()
        if #items == 0 then return 0 end
        ExitSpecialViews()
        ViewHistoryPush()
        r.Undo_BeginBlock(); r.PreventUIRefresh(1)
        NavHideEverythingWithoutHistory()
        for _, item in ipairs(items) do
            if item.kind == "folder" then
                ShowFolderItem(item, false)
            end
        end
        SyncGhostVisibility()
        EnsurePinnedVisible()
        r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
        r.Undo_EndBlock("Track Navigator: Show Search Results", 0)
        return #items
    end

    -- =========================================================================
    -- SONGS: CLICK HANDLERS
    -- =========================================================================

    HandleSongsSolo = function(filtered, fi, is_alt)
        local song = filtered[fi]
        local vis = r.GetMediaTrackInfo_Value(song.track, "B_SHOWINTCP") == 1
        if vis then
            local vis_songs = 0
            for _, s in ipairs(song_entries) do
                if r.GetMediaTrackInfo_Value(s.track, "B_SHOWINTCP") == 1 then vis_songs = vis_songs + 1 end
            end
            if vis_songs == 1 and song.is_folder and FolderSubtreeFullyShown(song) then
                if is_alt then
                    r.SetMediaTrackInfo_Value(song.track, "I_FOLDERCOMPACT", 0)
                    ExpandAllChildFolders(song.track, song.idx)
                else
                    local exp = r.GetMediaTrackInfo_Value(song.track, "I_FOLDERCOMPACT") == 0
                    r.SetMediaTrackInfo_Value(song.track, "I_FOLDERCOMPACT", exp and 2 or 0)
                    if not exp and opt_songs_expand then ExpandChildFolders(song.track, song.idx) end
                end
                return false
            end
            if vis_songs == 1 then return false end
        end
        for _, s in ipairs(song_entries) do SetFolderVisible(s, false) end
        SetFolderVisible(song, true); SetFolderCollapsed(song, false)
        if is_alt and song.is_folder then ExpandAllChildFolders(song.track, song.idx)
        elseif opt_songs_expand and song.is_folder then ExpandChildFolders(song.track, song.idx) end
        EnsureSongsParentVisible()
        return true
    end

    HandleSongsCmd = function(filtered, fi, is_alt)
        local song = filtered[fi]
        local vis = r.GetMediaTrackInfo_Value(song.track, "B_SHOWINTCP") == 1
        if vis then SetFolderVisible(song, false)
        else
            SetFolderVisible(song, true); SetFolderCollapsed(song, false)
            if is_alt and song.is_folder then ExpandAllChildFolders(song.track, song.idx)
            elseif opt_songs_expand and song.is_folder then ExpandChildFolders(song.track, song.idx) end
            EnsureSongsParentVisible()
        end
    end

    HandleSongsShift = function(filtered, fi)
        if not songs_last_click then HandleSongsSolo(filtered, fi, false); return end
        local lo, hi = math.min(songs_last_click, fi), math.max(songs_last_click, fi)
        for _, s in ipairs(song_entries) do SetFolderVisible(s, false) end
        for j = lo, hi do
            if j >= 1 and j <= #filtered then
                local s = filtered[j]
                SetFolderVisible(s, true); SetFolderCollapsed(s, false)
                if opt_songs_expand and s.is_folder then ExpandChildFolders(s.track, s.idx) end
            end
        end
        EnsureSongsParentVisible()
    end

    HandleSongsClick = function(filtered, fi, is_cmd, is_shift, is_alt)
        ExitSpecialViews()
        ViewHistoryPushTlf()
        local song = filtered[fi]
        r.Undo_BeginBlock(); r.PreventUIRefresh(1)
        local do_scroll = true
        if is_shift then HandleSongsShift(filtered, fi)
        elseif is_cmd then HandleSongsCmd(filtered, fi, is_alt)
        else do_scroll = HandleSongsSolo(filtered, fi, is_alt) end
        r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
        songs_last_click = fi
        if do_scroll then local st = song.track; r.defer(function() ScrollTrackToCenter(st) end) end
        r.Undo_EndBlock("Track Navigator: " .. song.name, 0)
    end

    -- =========================================================================
    -- UTILITY ACTIONS
    -- =========================================================================

    -- Show all TLTs, retaining each track's current collapsed/expanded state.
    ShowAllTLFs = function()
        ExitSpecialViews()
        ViewHistoryPush()
        NavClearListFilters()
        r.Undo_BeginBlock(); r.PreventUIRefresh(1)
        for _, sg in ipairs(sub_groups) do for _, e in ipairs(sg.entries) do sg.selected[e.display_name] = true end end
        for _, entry in ipairs(top_folders) do
            if not (NavTrackAutoIgnored and NavTrackAutoIgnored(entry.track)) then
                -- SetFolderVisible does not touch I_FOLDERCOMPACT, so collapsed/expanded state is preserved.
                SetFolderVisible(entry, true)
            end
        end
        songs_section_mode = false
        for _, e in ipairs(songs_sub.entries) do songs_sub.selected[e.display_name] = true end
        SyncGhostVisibility()
        r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
        r.Undo_EndBlock("Track Navigator: Show All TLTs", 0)
    end

    HideAllTLFs = function()
        ViewHistoryPush()
        r.Undo_BeginBlock(); r.PreventUIRefresh(1); HideEverything()
        SyncGhostVisibility()
        r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
        r.Undo_EndBlock("Track Navigator: Hide All", 0)
    end

    ShowAllTracks = function()
        ExitSpecialViews()
        ViewHistoryPush()
        NavClearListFilters()
        r.Undo_BeginBlock(); r.PreventUIRefresh(1)
        local nt = r.CountTracks(0)
        for i = 0, nt - 1 do
            local t = r.GetTrack(0, i)
            if not (NavTrackAutoIgnored and NavTrackAutoIgnored(t)) then
                r.SetMediaTrackInfo_Value(t, "B_SHOWINTCP", 1)
                r.SetMediaTrackInfo_Value(t, "B_SHOWINMIXER", 1)
            end
        end
        -- Expand all visible top-level tracks (except auto-ignored tracks such as ARCHIVE)
        for _, entry in ipairs(top_folders) do
            if not (NavTrackAutoIgnored and NavTrackAutoIgnored(entry.track)) then
                SetFolderCollapsed(entry, false)
            end
        end
        for _, sg in ipairs(sub_groups) do for _, e in ipairs(sg.entries) do sg.selected[e.display_name] = true end end
        for _, e in ipairs(songs_sub.entries) do songs_sub.selected[e.display_name] = true end
        songs_follow_active = false; songs_section_mode = false
        SyncGhostVisibility()
        r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
        r.Undo_EndBlock("Track Navigator: Show All Tracks", 0)
    end

    TrackNavigatorTltRenderIndexByOrdinal = function(ordinal)
        ordinal = math.floor(tonumber(ordinal) or 0)
        if ordinal < 1 then return nil end
        local pos = 0
        for ri, item in ipairs(render_list) do
            if item.kind == "folder"
                and item.entry
                and not item.custom
                and not item.ghost_parent
                and (item.tree_depth or 0) == 0
                and not (NavTrackAutoIgnored and NavTrackAutoIgnored(item.entry.track)) then
                pos = pos + 1
                if pos == ordinal then return ri end
            end
        end
        return nil
    end

    TrackNavigatorShowOnlyTltOrdinal = function(ordinal)
        local ri = TrackNavigatorTltRenderIndexByOrdinal(ordinal)
        if not ri then return false end
        HandleTracksClick(ri, false, false, false, false)
        return true
    end

    -- Show all songs, retaining each song folder's current collapsed/expanded state.
    ShowAllSongsKeep = function()
        ExitSpecialViews()
        ViewHistoryPush()
        r.Undo_BeginBlock(); r.PreventUIRefresh(1)
        for _, s in ipairs(song_entries) do
            SetFolderVisible(s, true)  -- preserves I_FOLDERCOMPACT
        end
        EnsureSongsParentVisible()
        r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
        r.Undo_EndBlock("Track Navigator: Show All Songs", 0)
    end

    HideAllSongs = function()
        ViewHistoryPush()
        r.Undo_BeginBlock(); r.PreventUIRefresh(1)
        for _, s in ipairs(song_entries) do SetFolderVisible(s, false) end
        r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
        r.Undo_EndBlock("Track Navigator: Hide All Songs", 0)
    end

    ToggleCollapseAll = function()
        ExitSpecialViews()
        r.Undo_BeginBlock(); r.PreventUIRefresh(1)
        -- Iterate render_list folders: includes promoted children, excludes ghost parents
        local all_c = true
        for _, item in ipairs(render_list) do
            if item.kind == "folder" and IsFolderVisible(item)
               and r.GetMediaTrackInfo_Value(item.track, "I_FOLDERDEPTH") == 1
               and r.GetMediaTrackInfo_Value(item.track, "I_FOLDERCOMPACT") == 0 then
                all_c = false; break
            end
        end
        for _, item in ipairs(render_list) do
            if item.kind == "folder" and IsFolderVisible(item) then
                SetFolderCollapsed(item, not all_c)
            end
        end
        SyncGhostVisibility()
        r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
        r.Undo_EndBlock("Track Navigator: Toggle Collapse", 0)
    end

    ExpandAllTracks = function()
        ViewHistoryPush()
        r.Undo_BeginBlock(); r.PreventUIRefresh(1)
        for _, entry in ipairs(top_folders) do if IsFolderVisible(entry) then SetFolderCollapsed(entry, false) end end
        SyncGhostVisibility()
        r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
        r.Undo_EndBlock("Track Navigator: Expand All", 0)
    end

    ExpandAllSongs = function()
        ViewHistoryPush()
        r.Undo_BeginBlock(); r.PreventUIRefresh(1)
        for _, s in ipairs(song_entries) do
            if r.GetMediaTrackInfo_Value(s.track, "B_SHOWINTCP") == 1 then SetFolderCollapsed(s, false) end
        end
        r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
        r.Undo_EndBlock("Track Navigator: Expand All Songs", 0)
    end
end

return ReflexInstallNavActionCore
