-- @noindex
-- Reflex color core module.
-- Installs shared color conversion and FX state color helpers.

ReflexInstallColorCore = function(deps)
    local r = deps.r
    local C = deps.colors

    TrackColorToImGui = function(nc)
        if nc == 0 then return C.btn_bg end
        local rv, gv, bv = r.ColorFromNative(nc)
        return (rv << 24) | (gv << 16) | (bv << 8) | 0xFF
    end

    ScaleColor = function(rgba, f)
        local rv = math.min(255, math.floor(((rgba >> 24) & 0xFF) * f))
        local gv = math.min(255, math.floor(((rgba >> 16) & 0xFF) * f))
        local bv = math.min(255, math.floor(((rgba >> 8) & 0xFF) * f))
        return (rv << 24) | (gv << 16) | (bv << 8) | (rgba & 0xFF)
    end

    -- FX row state colors: returns bg, hover, active, txt based on FX state flags.
    -- Centralizes the color logic shared by InspDrawFXRow and DrawCompactTrackColumn.
    FxStateColors = function(is_cont, is_instr, is_offline, is_enabled, is_dry, has_bypass_env, wet_val)
        local bg, hover, active, txt
        if is_cont then
            if is_offline then
                bg = ScaleColor(C.pan_color, 0.2); hover = ScaleColor(C.pan_color, 0.25); active = ScaleColor(C.pan_color, 0.3)
            elseif not is_enabled or has_bypass_env then
                bg = ScaleColor(C.pan_color, 0.25); hover = ScaleColor(C.pan_color, 0.3); active = ScaleColor(C.pan_color, 0.35)
            elseif wet_val < 0.995 then
                bg = ScaleColor(C.pan_color, 0.5); hover = ScaleColor(C.pan_color, 0.6); active = ScaleColor(C.pan_color, 0.7)
            else
                bg = C.pan_color; hover = ScaleColor(C.pan_color, 1.2); active = ScaleColor(C.pan_color, 1.35)
            end
            txt = 0xFFFFFFFF
        elseif is_instr then
            if is_offline then
                bg = ScaleColor(C.fx_instr_txt, 0.2); hover = ScaleColor(C.fx_instr_txt, 0.25); active = ScaleColor(C.fx_instr_txt, 0.3)
                txt = 0xFFFFFF50
            elseif not is_enabled then
                bg = ScaleColor(C.fx_instr_txt, 0.25); hover = ScaleColor(C.fx_instr_txt, 0.3); active = ScaleColor(C.fx_instr_txt, 0.35)
                txt = 0xFFFFFF70
            elseif is_dry then
                bg = ScaleColor(C.fx_instr_txt, 0.5); hover = ScaleColor(C.fx_instr_txt, 0.6); active = ScaleColor(C.fx_instr_txt, 0.7)
                txt = 0xFFFFFF90
            else
                bg = C.fx_instr_txt; hover = ScaleColor(C.fx_instr_txt, 1.2); active = ScaleColor(C.fx_instr_txt, 1.35)
                txt = C.text
            end
        elseif is_offline then
            bg = C.btn_bg; hover = C.btn_hover; active = C.btn_active; txt = C.fx_offline_txt
        elseif not is_enabled then
            bg = C.btn_bg; hover = C.btn_hover; active = C.btn_active
            txt = has_bypass_env and C.fx_bypass_env or C.fx_bypassed_txt
        elseif is_dry then
            bg = C.btn_hover; hover = C.btn_active; active = C.fx_row_active; txt = C.fx_drywet_txt
        elseif has_bypass_env then
            bg = C.btn_hover; hover = C.btn_active; active = C.fx_row_active; txt = C.fx_bypass_env
        else
            bg = C.btn_hover; hover = C.btn_active; active = C.fx_row_active; txt = C.text
        end
        return bg, hover, active, txt
    end
end

return ReflexInstallColorCore
