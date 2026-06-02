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
        if is_offline or not is_enabled then
            bg = rgb(0x22252A); hover = rgb(0x282B30); active = rgb(0x282B30); txt = rgb(0x43464A)
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
