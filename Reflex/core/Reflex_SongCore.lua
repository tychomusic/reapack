-- @noindex
-- Reflex song core module.
-- Installs current-song visibility and song-section selection helpers.

ReflexInstallSongCore = function(deps)
    local r = deps.r
    local SONG_SECTIONS = deps.song_sections
    local getRealistCurrentSong = deps.get_realist_current_song
    local setTrackVis = deps.set_track_vis
    local getChildren = deps.get_children
    local expandChildFolders = deps.expand_child_folders
    local getSongsEntryRef = deps.get_songs_entry_ref
    local getSongsSub = deps.get_songs_sub
    local setSongsFollowActive = deps.set_songs_follow_active
    local setSongsFollowLast = deps.set_songs_follow_last
    local setSongsSectionMode = deps.set_songs_section_mode

    ShowSongsForCurrentSong = function(entry, expand_ch)
        local cs = getRealistCurrentSong()
        setTrackVis(entry.track, true)
        r.SetMediaTrackInfo_Value(entry.track, "I_FOLDERCOMPACT", 0)
        if not cs then
            for _, c in ipairs(getChildren(entry.track, entry.idx)) do
                setTrackVis(c, true)
            end
            setSongsFollowActive(false)
            return
        end
        local nt = r.CountTracks(0)
        local depth, i, ic = 1, entry.idx + 1, false
        while i < nt and depth > 0 do
            local child = r.GetTrack(0, i)
            local cfd = r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
            if depth == 1 then
                local _, nm = r.GetTrackName(child)
                local sn = nm:match("^SONG:%s*(.+)") or nm:match("^UTIL:%s*(.+)")
                ic = (sn ~= nil and sn == cs)
                setTrackVis(child, ic)
                if cfd == 1 then
                    r.SetMediaTrackInfo_Value(child, "I_FOLDERCOMPACT", ic and 0 or 2)
                    if ic and expand_ch then expandChildFolders(child, i) end
                end
            else
                setTrackVis(child, ic)
            end
            depth = depth + cfd
            i = i + 1
        end
        setSongsFollowActive(true)
        setSongsFollowLast(cs)
    end

    ApplySongSectionSelection = function()
        local songs_sub = getSongsSub()
        if not songs_sub.song_track then return end
        local nt = r.CountTracks(0)
        local depth, i, show = 1, songs_sub.song_idx + 1, false
        while i < nt and depth > 0 do
            local child = r.GetTrack(0, i)
            local cfd = r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
            if depth == 1 then
                local _, nm = r.GetTrackName(child)
                show = SONG_SECTIONS[nm] and songs_sub.selected[nm] == true
                setTrackVis(child, show)
                if cfd == 1 then r.SetMediaTrackInfo_Value(child, "I_FOLDERCOMPACT", show and 0 or 2) end
            else
                setTrackVis(child, show)
            end
            depth = depth + cfd
            i = i + 1
        end
    end

    ShowSongSectionsSelected = function(expand_ch)
        local songs_entry_ref = getSongsEntryRef()
        local songs_sub = getSongsSub()
        if not songs_entry_ref or not songs_sub.song_track then return end
        -- Show SONGS + current song, hide other songs.
        ShowSongsForCurrentSong(songs_entry_ref, false)
        -- Filter within current song to selected sections only.
        ApplySongSectionSelection()
        -- Expand selected sections.
        for _, e in ipairs(songs_sub.entries) do
            if songs_sub.selected[e.display_name] and e.is_folder then
                r.SetMediaTrackInfo_Value(e.track, "I_FOLDERCOMPACT", 0)
                if expand_ch then expandChildFolders(e.track, e.idx) end
            end
        end
        setSongsSectionMode(true)
    end
end

return ReflexInstallSongCore
