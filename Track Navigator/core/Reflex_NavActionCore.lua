-- @noindex
-- Reflex shared Navigator action core.
-- Installs TLT/SONGS visibility handlers and utility actions used by Reflex and Navigator.

ReflexInstallNavActionCore = function(deps)
    local r = deps.r

    EnsurePinnedVisible = function()
        if next(pinned_folders) == nil then return end
        for _, entry in ipairs(top_folders) do
            if PinnedTrack(entry.track) then
                local was_hidden = r.GetMediaTrackInfo_Value(entry.track, "B_SHOWINTCP") ~= 1
                -- Show folder and all descendants
                SetFolderVisible(entry, true)
                if was_hidden then
                    -- Uncollapse and expand only when re-showing from hidden
                    SetFolderCollapsed(entry, false)
                    if opt_expand_children then ExpandChildFolders(entry.track, entry.idx) end
                end
                -- Restore sub-group selection (all children selected)
                local sg = sub_group_by_name[entry.name]
                if sg and #sg.entries > 0 then
                    for _, e in ipairs(sg.entries) do sg.selected[e.display_name] = true end
                end
            end
        end
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

    ShowFolderItem = function(item, expand_all)
        local sg = sub_group_by_name[item.entry.name]
        if opt_live_mode and item.entry.name == "SONGS" then
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
        for i = #parents, 1, -1 do
            SetTrackVis(parents[i], true)
            r.SetMediaTrackInfo_Value(parents[i], "I_FOLDERCOMPACT", 0)
        end
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

    IsAloneVisible = function(item)
        local vt = 0
        local item_name = item.kind == "folder" and item.entry.name
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
        if item.custom then return vt == 1 and IsItemVisible(item) end
        if item.kind == "folder" then
            if vt ~= 1 or not IsFolderVisible(item.entry) then return false end
            -- SONGS in section mode: always re-show full song on click
            if opt_live_mode and item.entry.name == "SONGS" and songs_section_mode then return false end
            -- Sub-group parent: only "alone" when all whitelisted children are visible
            local sg = item.sub_group
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
            return vs == 1
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
            local sg = sub_group_by_name[item.entry.name]
            if IsFolderVisible(item.entry) then
                if sg then SaveSubGroupState(sg) end
                if opt_live_mode and item.entry.name == "SONGS" then songs_follow_active = false end
                SetFolderVisible(item.entry, false)
            else
                -- Re-show: sub-groups restore saved selection, others show normally
                if opt_live_mode and item.entry.name == "SONGS" then
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
        if not tracks_last_click then HandleTracksSolo(ri); return end
        -- Resolve stored label back to current render_list index
        local anchor = nil
        for j, item in ipairs(render_list) do
            if item.label == tracks_last_click then anchor = j; break end
        end
        if not anchor then HandleTracksSolo(ri); return end
        local lo, hi = math.min(anchor, ri), math.max(anchor, ri)
        HideEverything()
        local active_sgs, parent_sgs = {}, {}
        local has_song_sections = false
        for j = lo, hi do
            local item = render_list[j]
            if item.custom then
                NavShowCustomItem(item, false)
            elseif item.kind == "folder" then
                local sg = sub_group_by_name[item.entry.name]
                if opt_live_mode and item.entry.name == "SONGS" then
                    ShowSongsForCurrentSong(item.entry, opt_expand_children); SetFolderCollapsed(item.entry, false)
                    for _, e in ipairs(songs_sub.entries) do songs_sub.selected[e.display_name] = true end
                    songs_section_mode = false
                elseif sg then parent_sgs[sg.parent_name] = sg; active_sgs[sg.parent_name] = sg
                else
                    SetFolderVisible(item.entry, true); SetFolderCollapsed(item.entry, false)
                    if opt_expand_children then ExpandChildFolders(item.entry.track, item.entry.idx) end
                end
            elseif item.kind == "sub_child" then
                if item.sub_group.is_song_sub then
                    songs_sub.selected[item.label] = true; has_song_sections = true
                else
                    item.sub_group.selected[item.label] = true; active_sgs[item.sub_group.parent_name] = item.sub_group
                end
            end
        end
        for _, sg in pairs(parent_sgs) do for _, e in ipairs(sg.entries) do sg.selected[e.display_name] = true end end
        for _, sg in pairs(active_sgs) do ShowSubGroupSelected(sg) end
        if has_song_sections then ShowSongSectionsSelected(opt_expand_children) end
    end

    HandleTracksClick = function(ri, is_cmd, is_shift, is_alt, is_ctrl)
        ExitSpecialViews()
        ViewHistoryPushTlf()
        local item = render_list[ri]
        r.Undo_BeginBlock(); r.PreventUIRefresh(1)
        local do_scroll = true
        if is_shift then HandleTracksShift(ri)
        elseif is_cmd then HandleTracksCmd(ri, is_alt)
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
            if item.custom then
                do_scroll = HandleTracksSolo(ri, true)
            elseif item.kind == "folder" then
                local guid = r.GetTrackGUID(item.entry.track)
                if pinned_folders[guid] then
                    pinned_folders[guid] = nil
                else
                    pinned_folders[guid] = true
                end
                SavePinnedFolders()
                do_scroll = false
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
        tracks_last_click = item.label
        if do_scroll then local st = item.track; r.defer(function() ScrollTrackToCenter(st) end) end
        r.Undo_EndBlock("Track Navigator: " .. item.label, 0)
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
            if vis_songs == 1 and song.is_folder then
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
