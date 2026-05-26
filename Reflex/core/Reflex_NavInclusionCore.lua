-- @noindex
-- Reflex nav inclusion core module.
-- Installs custom Navigator item persistence and selected-track include helpers.

ReflexInstallNavInclusionCore = function(deps)
    local r = deps.r
    local canIncludeTrack = deps.can_include_track or function() return true end
    local treeExpandEnabled = deps.tree_expand_enabled or function() return opt_nav_tlt_expand ~= false end
    local expandParentChain = deps.expand_parent_chain or function(track)
        if NavTreeExpandParentChain then return NavTreeExpandParentChain(track) end
        return false
    end
    local markDirty = deps.mark_dirty or function() end
    local _include_last_proj = nil

    local function NavCurrentProjectKey()
        local proj = r.EnumProjects and r.EnumProjects(-1, "") or nil
        local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
        return tostring(proj or "0") .. "|" .. tostring(master or "")
    end

    -- Custom NAV items: GUID-keyed and persisted per-project.
    nav_included = {}  -- nav_included[guid] = true
    nav_custom_set = {} -- nav_custom_set[guid] = true

    LoadNavIncluded = function()
        nav_included = {}
        local _, v = r.GetProjExtState(0, "reflex", "nav_included")
        if v ~= "" then
            for guid in v:gmatch("([^|]+)") do nav_included[guid] = true end
        end
        nav_custom_set = {}
        local _, cv = r.GetProjExtState(0, "reflex", "nav_custom_set")
        if cv ~= "" then
            for guid in cv:gmatch("([^|]+)") do nav_custom_set[guid] = true end
        end
        _include_last_proj = NavCurrentProjectKey()
    end

    SaveNavIncluded = function()
        local parts = {}
        for guid in pairs(nav_included) do parts[#parts + 1] = guid end
        table.sort(parts)
        r.SetProjExtState(0, "reflex", "nav_included", table.concat(parts, "|"))
    end

    SaveNavCustomSet = function()
        local parts = {}
        for guid in pairs(nav_custom_set) do parts[#parts + 1] = guid end
        table.sort(parts)
        r.SetProjExtState(0, "reflex", "nav_custom_set", table.concat(parts, "|"))
    end

    MaybeReloadNavIncluded = function()
        local cur = NavCurrentProjectKey()
        if cur ~= _include_last_proj then LoadNavIncluded() end
    end

    NavCanIncludeTrack = function(track)
        return track and r.ValidatePtr(track, "MediaTrack*") and canIncludeTrack(track) == true
    end

    NavIncludedTrack = function(track)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
        return nav_included[r.GetTrackGUID(track)] == true
    end

    NavCustomSetTrack = function(track)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
        return nav_custom_set[r.GetTrackGUID(track)] == true
    end

    NavCustomSetHasEntries = function()
        for _ in pairs(nav_custom_set or {}) do return true end
        return false
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

    NavSetTrackCustomSet = function(track, included)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
        if included and not NavCanIncludeTrack(track) then return false end
        local guid = r.GetTrackGUID(track)
        if included then nav_custom_set[guid] = true
        else nav_custom_set[guid] = nil end
        SaveNavCustomSet()
        markDirty()
        return true
    end

    NavRemoveCustomSetGuid = function(guid)
        if not guid or guid == "" or not nav_custom_set[guid] then return false end
        nav_custom_set[guid] = nil
        SaveNavCustomSet()
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

    NavResetCustomSetTracks = function()
        local changed = false
        for _ in pairs(nav_custom_set) do changed = true; break end
        if not changed then return false end
        nav_custom_set = {}
        SaveNavCustomSet()
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
        for guid in pairs(nav_custom_set) do
            if not live[guid] then
                nav_custom_set[guid] = nil
                changed = true
            end
        end
        if changed then SaveNavIncluded() end
        if changed then SaveNavCustomSet() end
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

    NavCustomSetEntries = function(opts)
        opts = opts or {}
        NavPruneIncluded()
        local entries = {}
        local nt = r.CountTracks(0)
        for i = 0, nt - 1 do
            local track = r.GetTrack(0, i)
            local guid = r.GetTrackGUID(track)
            if nav_custom_set[guid] then
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
        local included_changed = false
        local tree_changed = false
        local added = 0
        local skipped = 0
        for i = 0, r.CountSelectedTracks(0) - 1 do
            local track = r.GetSelectedTrack(0, i)
            if NavCanIncludeTrack(track) then
                if treeExpandEnabled() and expandParentChain(track) then
                    tree_changed = true
                end
                local guid = r.GetTrackGUID(track)
                if not nav_included[guid] then
                    nav_included[guid] = true
                    included_changed = true
                    added = added + 1
                end
            else
                skipped = skipped + 1
            end
        end
        if included_changed then
            SaveNavIncluded()
            markDirty()
        elseif tree_changed then
            markDirty()
        end
        return added, skipped
    end

    NavAddSelectedTracksToCustomSet = function()
        local changed = false
        local added = 0
        local skipped = 0
        for i = 0, r.CountSelectedTracks(0) - 1 do
            local track = r.GetSelectedTrack(0, i)
            if NavCanIncludeTrack(track) then
                local guid = r.GetTrackGUID(track)
                if not nav_custom_set[guid] then
                    nav_custom_set[guid] = true
                    changed = true
                    added = added + 1
                end
            else
                skipped = skipped + 1
            end
        end
        if changed then
            SaveNavCustomSet()
            markDirty()
        end
        return added, skipped
    end
end

return ReflexInstallNavInclusionCore
