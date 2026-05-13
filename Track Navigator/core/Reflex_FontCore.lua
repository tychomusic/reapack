-- @noindex
-- Reflex font core module.
-- Installs scaled font lookup and push/pop helpers.

ReflexInstallFontCore = function(deps)
    local r = deps.r
    local ctx = deps.ctx
    local scaled_fonts = deps.scaled_fonts
    local scaled_fonts_italic = deps.scaled_fonts_italic
    local scaled_fonts_regular = deps.scaled_fonts_regular
    local getUiScale = deps.get_ui_scale

    -- Font step computation: base step from effective scale + offset, clamped 5..20.
    GetFontStep = function(offset)
        local step = math.floor(getUiScale() * 0.8 * 10 + 0.5) + (offset or 0)
        return math.max(5, math.min(20, step))
    end

    -- Get scaled font handle by offset and style.
    -- style: nil or "bold" -> scaled_fonts, "italic" -> scaled_fonts_italic, "regular" -> scaled_fonts_regular
    GetSteppedFont = function(offset, style)
        local step = GetFontStep(offset)
        if style == "italic" then return scaled_fonts_italic[step]
        elseif style == "regular" then return scaled_fonts_regular[step]
        else return scaled_fonts[step] end
    end

    GetScaledFont = function() return GetSteppedFont(0) end
    GetScaledItalicFont = function() return GetSteppedFont(0, "italic") end
    GetScaledRegularFont = function() return GetSteppedFont(0, "regular") end

    PushFont = function(f)
        if f then r.ImGui_PushFont(ctx, f); return true end
        return false
    end

    PopFont = function(pushed)
        if pushed then r.ImGui_PopFont(ctx) end
    end
end

return ReflexInstallFontCore
