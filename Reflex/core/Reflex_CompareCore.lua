-- @noindex
-- Reflex compare core module.
-- Installs A/B compare backend helpers.

ReflexInstallCompareCore = function(deps)
    local r = deps.r
    local CMP_EXT_SECTION = deps.cmp_ext_section
    local cmpKey = deps.cmp_key
    local getInspTrack = deps.get_insp_track
    local getFxList = deps.get_fx_list
    local getCmpCheckTime = deps.get_cmp_check_time
    local setCmpCheckTime = deps.set_cmp_check_time
    local setCmpHasAny = deps.set_cmp_has_any
    local setCmpCount = deps.set_cmp_count

    InspCmpClearAll = function()
        -- Reset all assigned FX to neutral before clearing.
        if InspCmpResetAssigned then InspCmpResetAssigned() end
        local function clearTrack(track)
            for f = 0, r.TrackFX_GetCount(track) - 1 do
                local cmp_key = cmpKey(track, f)
                if cmp_key ~= "" then r.SetProjExtState(0, CMP_EXT_SECTION, cmp_key, "") end
            end
        end
        clearTrack(r.GetMasterTrack(0))
        for i = 0, r.CountTracks(0) - 1 do
            clearTrack(r.GetTrack(0, i))
        end
        r.SetProjExtState(0, CMP_EXT_SECTION, "_active", "")
        setCmpHasAny(false)
    end

    InspCmpCheckGlobal = function()
        local now = r.time_precise()
        if now - getCmpCheckTime() < 2.0 then return end
        setCmpCheckTime(now)
        local count = 0
        local function countTrack(track)
            for f = 0, r.TrackFX_GetCount(track) - 1 do
                local cmp_key = cmpKey(track, f)
                if cmp_key ~= "" then
                    local _, val = r.GetProjExtState(0, CMP_EXT_SECTION, cmp_key)
                    if val ~= "" and (val:sub(1, 1) == "A" or val:sub(1, 1) == "B") then
                        count = count + 1
                    end
                end
            end
        end
        countTrack(r.GetMasterTrack(0))
        for i = 0, r.CountTracks(0) - 1 do countTrack(r.GetTrack(0, i)) end
        setCmpCount(count)
        setCmpHasAny(count > 0)
    end

    -- Parse A/B assignment: "A|1|0.75" -> group, was_enabled, was_wet.
    -- Legacy values "A" or "B" assume enabled=true, wet=1.0.
    InspCmpParseAssignment = function(val)
        if not val or val == "" then return nil, true, 1.0 end
        local grp, en, wet = val:match("^([AB])|(%-?%d+)|([%d%.]+)$")
        if grp then return grp, tonumber(en) == 1, tonumber(wet) or 1.0 end
        if val == "A" or val == "B" then return val, true, 1.0 end
        return nil, true, 1.0
    end

    -- Build assignment string capturing current FX state.
    InspCmpBuildAssignment = function(group, track, fx_idx)
        local en = r.TrackFX_GetEnabled(track, fx_idx) and 1 or 0
        local wet = 1.0
        local wetparam = r.TrackFX_GetParamFromIdent(track, fx_idx, ":wet")
        if wetparam >= 0 then wet = r.TrackFX_GetParam(track, fx_idx, wetparam) end
        return string.format("%s|%d|%.4f", group, en, wet)
    end

    -- Reset all A/B assigned FX to their pre-compare state.
    InspCmpResetAssigned = function()
        local function resetTrack(track)
            for f = 0, r.TrackFX_GetCount(track) - 1 do
                local cmp_key = cmpKey(track, f)
                if cmp_key ~= "" then
                    local _, val = r.GetProjExtState(0, CMP_EXT_SECTION, cmp_key)
                    local grp, was_en, was_wet = InspCmpParseAssignment(val)
                    if grp then
                        r.TrackFX_SetEnabled(track, f, was_en)
                        local wetparam = r.TrackFX_GetParamFromIdent(track, f, ":wet")
                        if wetparam >= 0 then r.TrackFX_SetParam(track, f, wetparam, was_wet) end
                    end
                end
            end
        end
        resetTrack(r.GetMasterTrack(0))
        for i = 0, r.CountTracks(0) - 1 do resetTrack(r.GetTrack(0, i)) end
    end

    -- Apply the current phase using the current mode (call after reset).
    InspCmpApplyPhase = function(phase)
        if phase ~= "A" and phase ~= "B" then return end
        local _, mode_val = r.GetProjExtState(0, CMP_EXT_SECTION, "_mode")
        local is_drywet = mode_val == "drywet"
        local function applyTrack(track)
            for f = 0, r.TrackFX_GetCount(track) - 1 do
                local cmp_key = cmpKey(track, f)
                if cmp_key ~= "" then
                    local _, val = r.GetProjExtState(0, CMP_EXT_SECTION, cmp_key)
                    local grp = InspCmpParseAssignment(val)
                    if grp then
                        local active = grp == phase
                        if is_drywet then
                            local wetparam = r.TrackFX_GetParamFromIdent(track, f, ":wet")
                            if wetparam >= 0 then
                                r.TrackFX_SetParam(track, f, wetparam, active and 1.0 or 0.0)
                            end
                        else
                            r.TrackFX_SetEnabled(track, f, active)
                        end
                    end
                end
            end
        end
        applyTrack(r.GetMasterTrack(0))
        for i = 0, r.CountTracks(0) - 1 do applyTrack(r.GetTrack(0, i)) end
    end

    -- Single-pass reset-to-neutral then apply phase (avoids two full-project iterations).
    InspCmpResetAndApply = function(phase, mode_override)
        local _, mode_val = r.GetProjExtState(0, CMP_EXT_SECTION, "_mode")
        if mode_override then mode_val = mode_override end
        local is_drywet = mode_val == "drywet"
        local do_apply = phase == "A" or phase == "B"
        local function processTrack(track)
            for f = 0, r.TrackFX_GetCount(track) - 1 do
                local cmp_key = cmpKey(track, f)
                if cmp_key ~= "" then
                    local _, val = r.GetProjExtState(0, CMP_EXT_SECTION, cmp_key)
                    local grp, was_en, was_wet = InspCmpParseAssignment(val)
                    if grp then
                        -- Reset to pre-compare state first.
                        r.TrackFX_SetEnabled(track, f, was_en)
                        local wetparam = r.TrackFX_GetParamFromIdent(track, f, ":wet")
                        if wetparam >= 0 then r.TrackFX_SetParam(track, f, wetparam, was_wet) end
                        -- Apply phase if active.
                        if do_apply then
                            local active = grp == phase
                            if is_drywet then
                                if wetparam >= 0 then
                                    r.TrackFX_SetParam(track, f, wetparam, active and 1.0 or 0.0)
                                end
                            else
                                r.TrackFX_SetEnabled(track, f, active)
                            end
                        end
                    end
                end
            end
        end
        processTrack(r.GetMasterTrack(0))
        for i = 0, r.CountTracks(0) - 1 do processTrack(r.GetTrack(0, i)) end
    end

    InspCmpTogglePhase = function()
        local _, cur = r.GetProjExtState(0, CMP_EXT_SECTION, "_phase")
        local new_phase = (cur == "B") and "A" or "B"
        r.SetProjExtState(0, CMP_EXT_SECTION, "_phase", new_phase)
        r.Undo_BeginBlock()
        InspCmpResetAndApply(new_phase)
        r.Undo_EndBlock("Reflex: Compare " .. new_phase, -1)
    end

    -- Switch compare mode: reset all FX to neutral, change mode, re-apply current phase.
    InspCmpSwitchMode = function()
        local _, mode_val = r.GetProjExtState(0, CMP_EXT_SECTION, "_mode")
        local new_mode = (mode_val == "drywet") and "bypass" or "drywet"
        local _, phase = r.GetProjExtState(0, CMP_EXT_SECTION, "_phase")
        r.Undo_BeginBlock()
        r.SetProjExtState(0, CMP_EXT_SECTION, "_mode", new_mode)
        InspCmpResetAndApply(phase, new_mode)
        r.Undo_EndBlock("Reflex: Compare mode " .. new_mode, -1)
    end

    InspCmpFloatAll = function()
        local function toggleTrack(track)
            for f = 0, r.TrackFX_GetCount(track) - 1 do
                local cmp_key = cmpKey(track, f)
                if cmp_key ~= "" then
                    local _, val = r.GetProjExtState(0, CMP_EXT_SECTION, cmp_key)
                    if val ~= "" and (val:sub(1, 1) == "A" or val:sub(1, 1) == "B") then
                        local hwnd = r.TrackFX_GetFloatingWindow(track, f)
                        if hwnd then r.TrackFX_Show(track, f, 2)
                        else r.TrackFX_Show(track, f, 3) end
                    end
                end
            end
        end
        toggleTrack(r.GetMasterTrack(0))
        for i = 0, r.CountTracks(0) - 1 do toggleTrack(r.GetTrack(0, i)) end
    end

    -- Check if any compare-assigned FX on inspected track have floating windows.
    InspCmpAnyFloating = function()
        -- v20.434 Stage C: cmp state is per-inspected-track only.
        for _, fx in ipairs(getFxList(getInspTrack())) do
            if fx.cmp_key ~= "" then
                local _, val = r.GetProjExtState(0, CMP_EXT_SECTION, fx.cmp_key)
                if val ~= "" and (val:sub(1, 1) == "A" or val:sub(1, 1) == "B") then
                    if r.TrackFX_GetFloatingWindow(fx.track, fx.fx_idx) then return true end
                end
            end
        end
        return false
    end
end

return ReflexInstallCompareCore
