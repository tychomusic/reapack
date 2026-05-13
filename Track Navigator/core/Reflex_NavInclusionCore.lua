-- @noindex
-- Reflex nav inclusion core module.
-- Installs custom Navigator item persistence and selected-track include helpers.

ReflexInstallNavInclusionCore = function(deps)
    local r = deps.r
    local canIncludeTrack = deps.can_include_track or function() return true end
    local markDirty = deps.mark_dirty or function() end
    local _include_last_proj = nil

    -- Custom NAV items: GUID-keyed and persisted per-project.
    nav_included = {}  -- nav_included[guid] = true

    LoadNavIncluded = function()
        nav_included = {}
        local _, v = r.GetProjExtState(0, "reflex", "nav_included")
        if v ~= "" then
            for guid in v:gmatch("([^|]+)") do nav_included[guid] = true end
        end
        _include_last_proj = r.EnumProjects(-1)
    end

    SaveNavIncluded = function()
        local parts = {}
        for guid in pairs(nav_included) do parts[#parts + 1] = guid end
        table.sort(parts)
        r.SetProjExtState(0, "reflex", "nav_included", table.concat(parts, "|"))
    end

    MaybeReloadNavIncluded = function()
        local cur = r.EnumProjects(-1)
        if cur ~= _include_last_proj then LoadNavIncluded() end
    end

    NavCanIncludeTrack = function(track)
        return track and r.ValidatePtr(track, "MediaTrack*") and canIncludeTrack(track) == true
    end

    NavIncludedTrack = function(track)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
        return nav_included[r.GetTrackGUID(track)] == true
    end

    NavSetTrackIncluded = function(track, included)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
        if included and not NavCanIncludeTrack(track) then return false end
        local guid = r.GetTrackGUID(track)
        if included then nav_included[guid] = true
        else nav_included[guid] = nil end
        SaveNavIncluded()
        markDirty()
        return true
    end

    NavRemoveIncludedGuid = function(guid)
        if not guid or guid == "" or not nav_included[guid] then return false end
        nav_included[guid] = nil
        SaveNavIncluded()
        markDirty()
        return true
    end

    NavResetIncludedTracks = function()
        local changed = false
        for _ in pairs(nav_included) do changed = true; break end
        if not changed then return false end
        nav_included = {}
        SaveNavIncluded()
        markDirty()
        return true
    end

    NavPruneIncluded = function()
        local live = {}
        local nt = r.CountTracks(0)
        for i = 0, nt - 1 do
            local track = r.GetTrack(0, i)
            live[r.GetTrackGUID(track)] = true
        end
        local changed = false
        for guid in pairs(nav_included) do
            if not live[guid] then
                nav_included[guid] = nil
                changed = true
            end
        end
        if changed then SaveNavIncluded() end
        return changed
    end

    NavIncludedEntries = function(opts)
        opts = opts or {}
        NavPruneIncluded()
        local entries = {}
        local nt = r.CountTracks(0)
        for i = 0, nt - 1 do
            local track = r.GetTrack(0, i)
            local guid = r.GetTrackGUID(track)
            if nav_included[guid] then
                local allowed = NavCanIncludeTrack(track)
                if allowed or opts.include_blocked then
                    local _, name = r.GetTrackName(track)
                    entries[#entries + 1] = {
                        track = track,
                        guid = guid,
                        name = name,
                        color = r.GetTrackColor(track),
                        idx = i,
                        is_folder = (r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1),
                        blocked = not allowed,
                    }
                end
            end
        end
        return entries
    end

    NavIncludeSelectedTracks = function()
        local changed = false
        local added = 0
        local skipped = 0
        for i = 0, r.CountSelectedTracks(0) - 1 do
            local track = r.GetSelectedTrack(0, i)
            if NavCanIncludeTrack(track) then
                local guid = r.GetTrackGUID(track)
                if not nav_included[guid] then
                    nav_included[guid] = true
                    changed = true
                    added = added + 1
                end
            else
                skipped = skipped + 1
            end
        end
        if changed then
            SaveNavIncluded()
            markDirty()
        end
        return added, skipped
    end
end

return ReflexInstallNavInclusionCore
