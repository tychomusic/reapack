-- @noindex
-- Reflex nav exclusion core module.
-- Installs excluded-TLT persistence and ghost-parent visibility sync helpers.

ReflexInstallNavExclusionCore = function(deps)
    local r = deps.r
    local PREF = deps.PREF
    local getTopFolders = deps.get_top_folders
    local setTrackVis = deps.set_track_vis
    local markDirty = deps.mark_dirty or function() end
    local _exclude_last_proj = nil

    -- Excluded top-level NAV roots: hide the root button and promote any
    -- direct children. A current leaf may later become a folder, so this is
    -- intentionally root-level behavior, not "hide this current button shape."
    -- v20.501: GUID-keyed and persisted per-project to survive TLT renames and
    -- avoid same-name collisions across project tabs.
    nav_excluded = {}  -- nav_excluded[guid] = true

    -- Hidden top-level NAV roots: hide the root and its whole subtree from NAV.
    -- This is the normal "remove this TLT area from Navigator" rule; it wins
    -- over promote-children and manually shown track shortcuts.
    nav_hidden = {}  -- nav_hidden[guid] = true

    NavTrackNameIsArchive = function(name)
        return type(name) == "string" and name:lower() == "archive"
    end

    NavLiveSpecialName = function(name)
        if not opt_live_mode then return false end
        return name == "MONITORS" or name == "I/O" or name == "SONGS"
    end

    NavTrackAutoIgnored = function(track)
        if not opt_nav_ignore_archive then return false end
        local t = track
        while t and r.ValidatePtr(t, "MediaTrack*") do
            local _, name = r.GetTrackName(t)
            if NavTrackNameIsArchive(name) then return true end
            t = r.GetParentTrack(t)
        end
        return false
    end

    NavTrackInLiveSpecialArea = function(track)
        if not opt_live_mode then return false end
        local t = track
        while t and r.ValidatePtr(t, "MediaTrack*") do
            local _, name = r.GetTrackName(t)
            if NavLiveSpecialName(name) then return true end
            t = r.GetParentTrack(t)
        end
        return false
    end

    LoadNavExcluded = function()
        if r.HasExtState(PREF, "nav_excluded") then
            r.DeleteExtState(PREF, "nav_excluded", true)
        end
        nav_excluded = {}
        local _, v = r.GetProjExtState(0, "reflex", "nav_excluded")
        if v ~= "" then
            for guid in v:gmatch("([^|]+)") do nav_excluded[guid] = true end
        end
        nav_hidden = {}
        local _, hv = r.GetProjExtState(0, "reflex", "nav_hidden")
        if hv ~= "" then
            for guid in hv:gmatch("([^|]+)") do nav_hidden[guid] = true end
        end
        _exclude_last_proj = r.EnumProjects(-1)
    end

    SaveNavExcluded = function()
        local parts = {}
        for guid in pairs(nav_excluded) do parts[#parts + 1] = guid end
        r.SetProjExtState(0, "reflex", "nav_excluded", table.concat(parts, "|"))
    end

    SaveNavHidden = function()
        local parts = {}
        for guid in pairs(nav_hidden) do parts[#parts + 1] = guid end
        r.SetProjExtState(0, "reflex", "nav_hidden", table.concat(parts, "|"))
    end

    MaybeReloadNavExcluded = function()
        local cur = r.EnumProjects(-1)
        if cur ~= _exclude_last_proj then LoadNavExcluded() end
    end

    ExcludedTrack = function(track)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
        return nav_excluded[r.GetTrackGUID(track)] == true
    end

    HiddenTrack = function(track)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
        return nav_hidden[r.GetTrackGUID(track)] == true
    end

    NavTrackInHiddenSubtree = function(track)
        local t = track
        while t and r.ValidatePtr(t, "MediaTrack*") do
            if nav_hidden[r.GetTrackGUID(t)] then return true end
            t = r.GetParentTrack(t)
        end
        return false
    end

    NavCanExcludeTrack = function(track, name, has_sub_group)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
        if NavTrackAutoIgnored(track) then return false end
        if r.GetParentTrack(track) then return false end
        if NavLiveSpecialName(name) then return false end
        return true
    end

    NavSetTrackExcluded = function(track, excluded)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
        local guid = r.GetTrackGUID(track)
        if excluded then
            nav_excluded[guid] = true
            nav_hidden[guid] = nil
        else nav_excluded[guid] = nil end
        SaveNavExcluded()
        SaveNavHidden()
        markDirty()
        SyncGhostVisibility()
    end

    NavSetTrackHidden = function(track, hidden)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
        local guid = r.GetTrackGUID(track)
        if hidden then
            nav_hidden[guid] = true
            nav_excluded[guid] = nil
        else nav_hidden[guid] = nil end
        SaveNavHidden()
        SaveNavExcluded()
        markDirty()
    end

    NavResetExcludedTracks = function()
        local changed = false
        for _ in pairs(nav_excluded) do changed = true; break end
        for _ in pairs(nav_hidden) do changed = true; break end
        if not changed then return false end
        nav_excluded = {}
        nav_hidden = {}
        SaveNavExcluded()
        SaveNavHidden()
        markDirty()
        return true
    end

    NavResetPromotedTracks = function()
        local changed = false
        for _ in pairs(nav_excluded) do changed = true; break end
        if not changed then return false end
        nav_excluded = {}
        SaveNavExcluded()
        markDirty()
        return true
    end

    NavResetHiddenTracks = function()
        local changed = false
        for _ in pairs(nav_hidden) do changed = true; break end
        if not changed then return false end
        nav_hidden = {}
        SaveNavHidden()
        markDirty()
        return true
    end

    NavPruneExcludedTracks = function()
        local live = {}
        local nt = r.CountTracks(0)
        for i = 0, nt - 1 do
            local track = r.GetTrack(0, i)
            live[r.GetTrackGUID(track)] = true
        end
        local changed = false
        for guid in pairs(nav_excluded) do
            if not live[guid] then
                nav_excluded[guid] = nil
                changed = true
            end
        end
        for guid in pairs(nav_hidden) do
            if not live[guid] then
                nav_hidden[guid] = nil
                changed = true
            end
        end
        if changed then
            SaveNavExcluded()
            SaveNavHidden()
            markDirty()
        end
        return changed
    end

    -- After any visibility change, sync ghost parents:
    -- show+expand if any child is visible, hide if all children are hidden.
    SyncGhostVisibility = function()
        local any_excluded = false
        for _ in pairs(nav_excluded) do any_excluded = true; break end
        if not any_excluded then return end

        local top_folders = getTopFolders()
        for _, entry in ipairs(top_folders) do
            if ExcludedTrack(entry.track)
               and r.GetMediaTrackInfo_Value(entry.track, "I_FOLDERDEPTH") == 1 then
                local any_vis = false
                local nt = r.CountTracks(0)
                local depth, i = 1, entry.idx + 1
                while i < nt and depth > 0 do
                    local child = r.GetTrack(0, i)
                    local cfd = r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
                    if depth == 1 and r.GetMediaTrackInfo_Value(child, "B_SHOWINTCP") == 1 then
                        any_vis = true
                        break
                    end
                    depth = depth + cfd
                    i = i + 1
                end
                if any_vis then
                    setTrackVis(entry.track, true)
                    r.SetMediaTrackInfo_Value(entry.track, "I_FOLDERCOMPACT", 0)
                else
                    setTrackVis(entry.track, false)
                end
            end
        end
    end
end

return ReflexInstallNavExclusionCore
