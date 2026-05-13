-- @noindex
-- Reflex pin core module.
-- Installs GUID-keyed, per-project TLT pin persistence helpers.

ReflexInstallPinCore = function(deps)
    local r = deps.r
    local PREF = deps.PREF
    local _pin_last_proj = nil

    -- Pinned TLTs (always visible). v20.480: GUID-keyed and persisted
    -- per-project via ProjExtState. Previously was label-keyed and stored in
    -- global ExtState, which produced two bugs: (a) pins followed same-named
    -- tracks across project tabs, and (b) deleting a pinned track transferred
    -- the pin to whichever neighboring track inherited a similar fallback name
    -- after the renumber. GUIDs are stable and unique within a project, so both
    -- bugs disappear. Clean break - existing label-based pins are NOT migrated;
    -- the legacy global ExtState entry is deleted on first load.
    pinned_folders = {}    -- pinned_folders[guid] = true

    LoadPinnedFolders = function()
        if r.HasExtState(PREF, "pinned_folders") then
            r.DeleteExtState(PREF, "pinned_folders", true)
        end
        pinned_folders = {}
        local _, v = r.GetProjExtState(0, "reflex", "pinned_folders")
        if v and v ~= "" then
            for guid in v:gmatch("([^|]+)") do pinned_folders[guid] = true end
        end
        _pin_last_proj = r.EnumProjects(-1)
    end

    SavePinnedFolders = function()
        local parts = {}
        for guid in pairs(pinned_folders) do parts[#parts + 1] = guid end
        r.SetProjExtState(0, "reflex", "pinned_folders", table.concat(parts, "|"))
    end

    MaybeReloadPins = function()
        -- Project tab switch: ProjExtState scopes per-project automatically, so
        -- our in-memory cache needs to refresh when the active project pointer
        -- changes. Called once per frame from Loop.
        local cur = r.EnumProjects(-1)
        if cur ~= _pin_last_proj then LoadPinnedFolders() end
    end

    PinnedTrack = function(track)
        -- O(1) check: caller passes a MediaTrack*, we resolve to GUID and check
        -- the set. ValidatePtr guard so we never crash on a stale pointer (e.g.
        -- track deleted mid-frame).
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
        return pinned_folders[r.GetTrackGUID(track)] == true
    end
end

return ReflexInstallPinCore
