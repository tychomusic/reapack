-- @noindex
-- Reflex track utility core module.
-- Installs folder child/collapse/visibility helpers.

ReflexInstallTrackUtilCore = function(deps)
    local r = deps.r
    local setTrackVis = deps.set_track_vis

    GetChildren = function(ft, fi)
        local ch = {}
        local nt = r.CountTracks(0)
        if r.GetMediaTrackInfo_Value(ft, "I_FOLDERDEPTH") ~= 1 then return ch end
        local d, i = 1, fi + 1
        while i < nt and d > 0 do
            local c = r.GetTrack(0, i)
            ch[#ch + 1] = c
            d = d + r.GetMediaTrackInfo_Value(c, "I_FOLDERDEPTH")
            i = i + 1
        end
        return ch
    end

    SetFolderCollapsed = function(entry, collapsed)
        if r.GetMediaTrackInfo_Value(entry.track, "I_FOLDERDEPTH") ~= 1 then return end
        r.SetMediaTrackInfo_Value(entry.track, "I_FOLDERCOMPACT", collapsed and 2 or 0)
    end

    ExpandChildFolders = function(ft, fi)
        local nt = r.CountTracks(0)
        local d, i = 1, fi + 1
        while i < nt and d > 0 do
            local c = r.GetTrack(0, i)
            local cfd = r.GetMediaTrackInfo_Value(c, "I_FOLDERDEPTH")
            if d == 1 and cfd == 1 then r.SetMediaTrackInfo_Value(c, "I_FOLDERCOMPACT", 0) end
            d = d + cfd
            i = i + 1
        end
    end

    CollapseChildFolders = function(ft, fi)
        local nt = r.CountTracks(0)
        local d, i = 1, fi + 1
        while i < nt and d > 0 do
            local c = r.GetTrack(0, i)
            local cfd = r.GetMediaTrackInfo_Value(c, "I_FOLDERDEPTH")
            if d == 1 and cfd == 1 then r.SetMediaTrackInfo_Value(c, "I_FOLDERCOMPACT", 2) end
            d = d + cfd
            i = i + 1
        end
    end

    ExpandAllChildFolders = function(ft, fi)
        local nt = r.CountTracks(0)
        local d, i = 1, fi + 1
        while i < nt and d > 0 do
            local c = r.GetTrack(0, i)
            local cfd = r.GetMediaTrackInfo_Value(c, "I_FOLDERDEPTH")
            if cfd == 1 then r.SetMediaTrackInfo_Value(c, "I_FOLDERCOMPACT", 0) end
            d = d + cfd
            i = i + 1
        end
    end

    SetFolderVisible = function(entry, visible, opts)
        local allow_ignored = opts and opts.allow_ignored
        local fd = r.GetMediaTrackInfo_Value(entry.track, "I_FOLDERDEPTH")
        if visible and not allow_ignored
           and NavTrackAutoIgnored and NavTrackAutoIgnored(entry.track) then
            return
        end
        if not visible then
            if fd == 1 then
                r.SetMediaTrackInfo_Value(entry.track, "I_FOLDERCOMPACT", 2)
                for _, c in ipairs(GetChildren(entry.track, entry.idx)) do
                    setTrackVis(c, false)
                end
            end
            setTrackVis(entry.track, false)
        else
            setTrackVis(entry.track, true)
            if fd == 1 then
                for _, c in ipairs(GetChildren(entry.track, entry.idx)) do
                    if allow_ignored
                       or not (NavTrackAutoIgnored and NavTrackAutoIgnored(c)) then
                        setTrackVis(c, true)
                    end
                end
            end
        end
    end

    IsFolderVisible = function(entry)
        return entry.track
           and r.ValidatePtr(entry.track, "MediaTrack*")
           and r.GetMediaTrackInfo_Value(entry.track, "B_SHOWINTCP") == 1
    end

    NavTrackActuallyVisible = function(track)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
        if r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") ~= 1 then return false end
        local parent = r.GetParentTrack(track)
        while parent and r.ValidatePtr(parent, "MediaTrack*") do
            if r.GetMediaTrackInfo_Value(parent, "B_SHOWINTCP") ~= 1 then return false end
            if r.GetMediaTrackInfo_Value(parent, "I_FOLDERCOMPACT") == 2 then return false end
            parent = r.GetParentTrack(parent)
        end
        return true
    end

    IsItemVisible = function(item)
        if item and item.custom then return NavTrackActuallyVisible(item.track) end
        return IsFolderVisible(item)
    end
end

return ReflexInstallTrackUtilCore
