-- @noindex
-- Reflex track scan core module.
-- Installs top-level-track, subgroup, song-section, render-list, and song-list scanners.

ReflexInstallTrackScanCore = function(deps)
    local r = deps.r
    local SONG_SECTIONS = deps.song_sections
    local getRealistCurrentSong = deps.get_realist_current_song
    local excludedTrack = deps.excluded_track
    local hiddenTrack = deps.hidden_track or function() return false end
    local hiddenSubtree = deps.hidden_subtree or function() return false end
    local liveMode = deps.live_mode or function() return opt_live_mode == true end
    local trackAutoIgnored = deps.track_auto_ignored or function() return false end
    local getIncludedEntries = deps.get_included_entries or function() return {} end
    local getSubGroups = deps.get_sub_groups
    local getSubGroupByName = deps.get_sub_group_by_name
    local getSongsSub = deps.get_songs_sub
    local getTopFolders = deps.get_top_folders
    local setTopFolders = deps.set_top_folders
    local setArchiveEntry = deps.set_archive_entry
    local getSongsEntryRef = deps.get_songs_entry_ref
    local setSongsEntryRef = deps.set_songs_entry_ref
    local setNeedsRescan = deps.set_needs_rescan
    local setRenderList = deps.set_render_list
    local setSongEntries = deps.set_song_entries
    local setNeedsSongRescan = deps.set_needs_song_rescan
    local setSongsLastClick = deps.set_songs_last_click

    ScanTopFolders = function()
        local top_folders = {}
        local songs_entry_ref = nil
        local archive_entry = nil
        local nt = r.CountTracks(0)
        local i = 0
        while i < nt do
            local track = r.GetTrack(0, i)
            local fd = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            if fd == 1 then
                local _, name = r.GetTrackName(track)
                local entry = { track = track, name = name, color = r.GetTrackColor(track), idx = i }
                top_folders[#top_folders + 1] = entry
                if liveMode() and name == "SONGS" then songs_entry_ref = entry end
                if name:lower() == "archive" then archive_entry = entry end
                local depth = 1
                i = i + 1
                while i < nt and depth > 0 do
                    depth = depth + r.GetMediaTrackInfo_Value(r.GetTrack(0, i), "I_FOLDERDEPTH")
                    i = i + 1
                end
            elseif r.GetTrackDepth(track) == 0 then
                local _, name = r.GetTrackName(track)
                top_folders[#top_folders + 1] = {
                    track = track,
                    name = name,
                    color = r.GetTrackColor(track),
                    idx = i,
                }
                i = i + 1
            else
                i = i + 1
            end
        end
        setTopFolders(top_folders)
        setSongsEntryRef(songs_entry_ref)
        setArchiveEntry(archive_entry)
        setNeedsRescan(false)
    end

    ScanSubGroups = function()
        local sub_groups = getSubGroups()
        local top_folders = getTopFolders()
        for _, sg in ipairs(sub_groups) do
            sg.entry_ref = nil
            sg.entries = {}
            for _, entry in ipairs(top_folders) do
                if entry.name == sg.parent_name then sg.entry_ref = entry; break end
            end
            if not sg.entry_ref then goto next_sg end
            local nt = r.CountTracks(0)
            local depth, i = 1, sg.entry_ref.idx + 1
            while i < nt and depth > 0 do
                local child = r.GetTrack(0, i)
                local cfd = r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
                if depth == 1 then
                    local _, name = r.GetTrackName(child)
                    local display = sg.filter_fn(name)
                    if display then
                        sg.entries[#sg.entries + 1] = {
                            track = child,
                            name = name,
                            display_name = display,
                            idx = i,
                            is_folder = (cfd == 1),
                            color = r.GetTrackColor(child),
                        }
                        if sg.selected[display] == nil then
                            sg.selected[display] = r.GetMediaTrackInfo_Value(child, "B_SHOWINTCP") == 1
                        end
                    end
                end
                depth = depth + cfd
                i = i + 1
            end
            ::next_sg::
        end
    end

    ScanSongSections = function()
        local songs_sub = getSongsSub()
        local songs_entry_ref = getSongsEntryRef()
        songs_sub.entry_ref = songs_entry_ref
        local cs = liveMode() and getRealistCurrentSong() or nil
        if not cs or not songs_entry_ref then
            songs_sub.entries = {}
            songs_sub.song_name = ""
            songs_sub.song_track = nil
            return
        end
        if cs == songs_sub.song_name and #songs_sub.entries > 0 then return end
        songs_sub.entries = {}
        songs_sub.song_name = cs
        songs_sub.song_track = nil
        songs_sub.song_idx = -1

        local nt = r.CountTracks(0)
        local depth, i = 1, songs_entry_ref.idx + 1
        while i < nt and depth > 0 do
            local child = r.GetTrack(0, i)
            local cfd = r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
            if depth == 1 then
                local _, nm = r.GetTrackName(child)
                local sn = nm:match("^SONG:%s*(.+)") or nm:match("^UTIL:%s*(.+)")
                if sn == cs then songs_sub.song_track = child; songs_sub.song_idx = i; break end
            end
            depth = depth + cfd
            i = i + 1
        end
        if not songs_sub.song_track then songs_sub.song_name = ""; return end

        depth = 1
        i = songs_sub.song_idx + 1
        while i < nt and depth > 0 do
            local child = r.GetTrack(0, i)
            local cfd = r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
            if depth == 1 then
                local _, nm = r.GetTrackName(child)
                if SONG_SECTIONS[nm] then
                    songs_sub.entries[#songs_sub.entries + 1] = {
                        track = child,
                        name = nm,
                        display_name = nm,
                        idx = i,
                        is_folder = (cfd == 1),
                        color = r.GetTrackColor(child),
                    }
                    if songs_sub.selected[nm] == nil then songs_sub.selected[nm] = true end
                end
            end
            depth = depth + cfd
            i = i + 1
        end
    end

    BuildRenderList = function()
        local render_list = {}
        local represented = {}
        ScanSongSections()
        local top_folders = getTopFolders()
        local sub_group_by_name = getSubGroupByName()
        local songs_sub = getSongsSub()
        local included_entries = getIncludedEntries()
        local add_custom = function(entry)
            if not entry or not entry.track or not r.ValidatePtr(entry.track, "MediaTrack*") then return end
            local guid = r.GetTrackGUID(entry.track)
            if not represented[guid]
               and not excludedTrack(entry.track)
               and not hiddenSubtree(entry.track)
               and not trackAutoIgnored(entry.track) then
                render_list[#render_list + 1] = {
                    kind = "folder",
                    label = entry.name,
                    color = entry.color,
                    track = entry.track,
                    idx = entry.idx,
                    entry = entry,
                    is_folder = entry.is_folder,
                    custom = true,
                }
                represented[guid] = true
            end
        end
        local add_custom_range = function(first_idx, last_idx)
            if last_idx < first_idx then return end
            for _, entry in ipairs(included_entries) do
                if entry.idx >= first_idx and entry.idx <= last_idx then
                    add_custom(entry)
                end
            end
        end
        local track_end_idx = function(entry)
            if r.GetMediaTrackInfo_Value(entry.track, "I_FOLDERDEPTH") ~= 1 then return entry.idx end
            local nt = r.CountTracks(0)
            local depth, i = 1, entry.idx + 1
            while i < nt and depth > 0 do
                depth = depth + r.GetMediaTrackInfo_Value(r.GetTrack(0, i), "I_FOLDERDEPTH")
                i = i + 1
            end
            return i - 1
        end
        local add_sub_group_items = function(sg, first_idx, last_idx)
            local last_emit_idx = first_idx - 1
            for _, child in ipairs(sg.entries) do
                if not hiddenSubtree(child.track) and not trackAutoIgnored(child.track) then
                    add_custom_range(last_emit_idx + 1, child.idx - 1)
                    render_list[#render_list + 1] = {
                        kind = "sub_child",
                        label = child.display_name,
                        color = child.color,
                        track = child.track,
                        idx = child.idx,
                        entry = child,
                        is_folder = child.is_folder,
                        sub_group = sg,
                    }
                    represented[r.GetTrackGUID(child.track)] = true
                    last_emit_idx = child.idx
                end
            end
            add_custom_range(last_emit_idx + 1, last_idx)
        end
        for _, entry in ipairs(top_folders) do
            if not hiddenTrack(entry.track) and not trackAutoIgnored(entry.track) then
                local entry_guid = r.GetTrackGUID(entry.track)
                local entry_fd = r.GetMediaTrackInfo_Value(entry.track, "I_FOLDERDEPTH")
                local entry_end = track_end_idx(entry)
                local sg = sub_group_by_name[entry.name]
                if liveMode() and entry.name == "SONGS" and #songs_sub.entries > 0 then sg = songs_sub end

                -- Excluded TLTs: hide the parent row; folders promote direct children.
                if excludedTrack(entry.track) then
                    represented[entry_guid] = true
                    if entry_fd == 1 then
                        local nt = r.CountTracks(0)
                        local depth, i = 1, entry.idx + 1
                        local last_emit_idx = entry.idx
                        while i < nt and depth > 0 do
                            local child = r.GetTrack(0, i)
                            local cfd = r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
                            if depth == 1 and not hiddenSubtree(child) and not trackAutoIgnored(child) then
                                add_custom_range(last_emit_idx + 1, i - 1)
                                local _, cname = r.GetTrackName(child)
                                local ccol = r.GetTrackColor(child)
                                if ccol == 0 then ccol = entry.color end
                                local child_guid = r.GetTrackGUID(child)
                                if not excludedTrack(child) and not hiddenTrack(child) then
                                    render_list[#render_list + 1] = {
                                        kind = "folder",
                                        label = cname,
                                        color = ccol,
                                        track = child,
                                        idx = i,
                                        entry = { track = child, name = cname, color = ccol, idx = i },
                                        is_folder = (cfd == 1),
                                        ghost_parent = entry,
                                    }
                                end
                                represented[child_guid] = true
                                last_emit_idx = i
                            end
                            depth = depth + cfd
                            i = i + 1
                        end
                        add_custom_range(last_emit_idx + 1, entry_end)
                    end
                else
                    render_list[#render_list + 1] = {
                        kind = "folder",
                        label = entry.name,
                        color = entry.color,
                        track = entry.track,
                        idx = entry.idx,
                        entry = entry,
                        is_folder = (entry_fd == 1),
                        sub_group = sg,
                    }
                    represented[entry_guid] = true
                    if sg and sg.ui_expanded then
                        add_sub_group_items(sg, entry.idx + 1, entry_end)
                    else
                        add_custom_range(entry.idx + 1, entry_end)
                    end
                end
            end
        end
        setRenderList(render_list)
    end

    ScanSongs = function()
        local song_entries = {}
        if not liveMode() then
            setSongEntries(song_entries)
            setNeedsSongRescan(false)
            setSongsLastClick(nil)
            return
        end
        local nt = r.CountTracks(0)
        for i = 0, nt - 1 do
            local track = r.GetTrack(0, i)
            local _, name = r.GetTrackName(track)
            local sn = name:match("^SONG:%s*(.+)")
            if sn then
                song_entries[#song_entries + 1] = {
                    track = track,
                    name = sn,
                    full_name = name,
                    idx = i,
                    is_folder = (r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1),
                }
            end
        end
        table.sort(song_entries, function(a, b) return a.name:lower() < b.name:lower() end)
        setSongEntries(song_entries)
        setNeedsSongRescan(false)
        setSongsLastClick(nil)
    end
end

return ReflexInstallTrackScanCore
