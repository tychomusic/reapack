-- @noindex
-- Shared Reflex popup, menu, and tooltip styling.

ReflexInstallStyleCore = function(deps)
    local r = deps.r
    local ctx = deps.ctx
    local C = deps.colors

    local function popupHover()
        return C.popup_hover or C.fx_ctrl_hover or C.btn_hover or C.border
    end

    local function popupActive()
        return C.popup_active or C.fx_ctrl_active or C.btn_active or popupHover()
    end

    local function popupBg()
        return C.popup_bg or C.bg
    end

    local function popupText()
        return C.popup_text or C.text_dim
    end

    local function popupTextHover()
        return C.popup_text_hover or C.text
    end

    local function popupBorder()
        return C.popup_border or C.window_outline or C.border or popupText()
    end

    local function popupSeparator()
        return C.popup_separator or 0x262930FF
    end

    local function popupGap()
        return S(4)
    end

    local function popupOuterGap()
        return S(10)
    end

    local popup_style_stack = {}

    local function snap(v)
        if Round then return Round(v) end
        return math.floor(v + 0.5)
    end

    PushPopupStyle = function(opts)
        opts = opts or {}
        local var_count = 0
        local pad = opts.padding or (popupOuterGap() * (opts.padding_scale or 1))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), popupBg())
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), popupBorder())
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), popupText())
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), popupHover())
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), popupHover())
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), popupActive())
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarBg(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrab(), 0x5A5A5EFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrabHovered(), 0x6E6E74FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrabActive(), 0x7E7E84FF)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), S(10))
        var_count = var_count + 1
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), pad, pad)
        var_count = var_count + 1
        if opts.solid_outline and r.ImGui_StyleVar_WindowBorderSize then
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
            var_count = var_count + 1
        end
        if opts.solid_outline and r.ImGui_StyleVar_PopupBorderSize then
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupBorderSize(), 0)
            var_count = var_count + 1
        end
        popup_style_stack[#popup_style_stack + 1] = var_count
    end

    PopPopupStyle = function()
        local var_count = popup_style_stack[#popup_style_stack] or 2
        popup_style_stack[#popup_style_stack] = nil
        r.ImGui_PopStyleColor(ctx, 10)
        r.ImGui_PopStyleVar(ctx, var_count)
    end

    ReflexDrawSolidPopupOutline = function(rounding, col)
        local x, y = r.ImGui_GetWindowPos(ctx)
        local w, h = r.ImGui_GetWindowSize(ctx)
        local dl = r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(ctx) or r.ImGui_GetWindowDrawList(ctx)
        col = col or popupBorder()
        rounding = rounding or S(10)
        if DrawTrackNavigatorWindowOutline then
            DrawTrackNavigatorWindowOutline(dl, x, y, w, h, rounding, col)
        else
            r.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, col, rounding, 0, 1)
        end
    end

    PushTooltipStyle = function()
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), popupBg())
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.tooltip_text or C.text)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), S(5), S(3))
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), S(4))
    end

    PopTooltipStyle = function()
        r.ImGui_PopStyleColor(ctx, 2)
        r.ImGui_PopStyleVar(ctx, 2)
    end

    Tip = function(text)
        if not opt_tooltips or not text then return end
        if r.ImGui_IsItemHovered(ctx) then
            PushTooltipStyle()
            r.ImGui_SetTooltip(ctx, text)
            PopTooltipStyle()
        end
    end

    TipDirect = function(text)
        if not opt_tooltips or not text then return end
        PushTooltipStyle()
        r.ImGui_SetTooltip(ctx, text)
        PopTooltipStyle()
    end

    ShowModKeyTip = function()
        if not opt_tooltips then return end
        if opt_helper_tooltips == false then return end
        local os = r.GetOS and r.GetOS() or ""
        local is_mac = os:find("OSX", 1, true) ~= nil
            or os:find("macOS", 1, true) ~= nil
            or os:find("Mac", 1, true) ~= nil
        local primary = is_mac and "Cmd" or "Ctrl"
        local alt = is_mac and "Opt" or "Alt"
        PushTooltipStyle()
        r.ImGui_BeginTooltip(ctx)
        r.ImGui_Text(ctx, "Click: toggle navigator")
        r.ImGui_Text(ctx, primary .. ": show all TLTs")
        r.ImGui_Text(ctx, alt .. "+Shift: show custom set")
        r.ImGui_Text(ctx, alt .. ": expand all visible tracks")
        r.ImGui_Text(ctx, "Shift: toggle collapse TLTs")
        r.ImGui_Text(ctx, primary .. "+Shift: show all tracks")
        r.ImGui_EndTooltip(ctx)
        PopTooltipStyle()
    end

    ReflexMenuItem = function(label, opts)
        opts = opts or {}
        local enabled = opts.enabled ~= false
        local id = opts.id or label
        local text_col = opts.text_col or popupText()
        local hover_text_col = opts.hover_text_col or popupTextHover()
        local disabled_col = opts.disabled_col or C.text_muted or text_col
        local alpha_text_col = enabled and text_col or disabled_col
        local pad_x = opts.pad_x or S(8)
        local pad_y = opts.pad_y or popupGap()
        local text_w, text_h = r.ImGui_CalcTextSize(ctx, label)
        text_h = text_h or r.ImGui_GetTextLineHeight(ctx)
        local row_w = math.max(opts.min_w or 0, text_w + pad_x * 2)
        local row_h = math.max(opts.min_h or 0, text_h + pad_y * 2)
        local rounding = opts.rounding or S(4)
        local selectable_flags = 0
        if opts.no_auto_close then
            local no_auto_close = r.ImGui_SelectableFlags_NoAutoClosePopups
                and r.ImGui_SelectableFlags_NoAutoClosePopups()
                or 1
            selectable_flags = selectable_flags | no_auto_close
        end

        r.ImGui_PushID(ctx, id)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x00000000)
        if not enabled then r.ImGui_BeginDisabled(ctx, true) end
        local clicked = r.ImGui_Selectable(ctx, "##item", false, selectable_flags, row_w, row_h)
        if not enabled then r.ImGui_EndDisabled(ctx) end
        r.ImGui_PopStyleColor(ctx, 4)
        local hovered = enabled and r.ImGui_IsItemHovered(ctx)
        local x1, y1 = r.ImGui_GetItemRectMin(ctx)
        local x2, y2 = r.ImGui_GetItemRectMax(ctx)
        local tx = x1 + pad_x
        local ty = y1 + snap((row_h - text_h) / 2)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        if hovered or (enabled and r.ImGui_IsItemActive(ctx)) then
            local fill = r.ImGui_IsItemActive(ctx) and popupActive() or popupHover()
            r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, fill, rounding)
        end
        r.ImGui_DrawList_AddText(dl, tx, ty, hovered and hover_text_col or alpha_text_col, label)
        r.ImGui_PopID(ctx)
        return enabled and clicked, hovered
    end

    ReflexPushPopupLayout = function()
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 0, 0)
    end

    ReflexPopPopupLayout = function()
        r.ImGui_PopStyleVar(ctx, 1)
    end

    ReflexPopupGap = function(h)
        if h and h > 0 then r.ImGui_Dummy(ctx, 1, h) end
    end

    ReflexPopupStackGap = function(h)
        r.ImGui_Dummy(ctx, 1, h or popupOuterGap())
    end

    ReflexPopupLabel = function(label, opts)
        opts = opts or {}
        local pad_x = opts.pad_x or 0
        local pad_y = opts.pad_y or 0
        local text_w, text_h = r.ImGui_CalcTextSize(ctx, label)
        text_h = text_h or r.ImGui_GetTextLineHeight(ctx)
        local row_w = math.max(opts.min_w or 0, text_w + pad_x * 2)
        local row_h = math.max(opts.min_h or 0, text_h + pad_y * 2)
        local x, y = r.ImGui_GetCursorScreenPos(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        r.ImGui_DrawList_AddText(dl, x + pad_x, y + snap((row_h - text_h) / 2), opts.col or popupText(), label)
        r.ImGui_Dummy(ctx, row_w, row_h)
    end

    ReflexPopupSeparator = function(w, opts)
        opts = opts or {}
        local gap = opts.gap or popupGap()
        local line_h = opts.line_h or math.max(1, S(1))
        local x, y = r.ImGui_GetCursorScreenPos(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local yy = y + gap
        r.ImGui_DrawList_AddRectFilled(dl, x, yy, x + (w or S(140)), yy + line_h, opts.col or popupSeparator())
        r.ImGui_Dummy(ctx, w or S(140), gap * 2 + line_h)
    end

    ReflexPopupRule = function(w, opts)
        opts = opts or {}
        local line_h = opts.line_h or math.max(1, S(1))
        local x, y = r.ImGui_GetCursorScreenPos(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local x2 = x + (w or S(140))
        if opts.full_width ~= false then
            local wx, _ = r.ImGui_GetWindowPos(ctx)
            local ww, _ = r.ImGui_GetWindowSize(ctx)
            local inset = opts.inset or 1
            x = snap(wx + inset)
            x2 = snap(wx + ww - inset)
        end
        r.ImGui_DrawList_AddRectFilled(dl, x, y, x2, y + line_h, opts.col or popupSeparator())
        r.ImGui_Dummy(ctx, w or S(140), line_h)
    end

    ReflexConfigureKeyboardPassthrough = function()
        if not (r.ImGui_SetConfigVar and r.ImGui_ConfigVar_NavCaptureKeyboard) then return end
        local ok_var, nav_capture = pcall(r.ImGui_ConfigVar_NavCaptureKeyboard)
        if ok_var and type(nav_capture) == "number" then
            pcall(r.ImGui_SetConfigVar, ctx, nav_capture, 0)
        end
    end

    ReflexApplyKeyboardPassthrough = function()
        local active = r.ImGui_IsAnyItemActive and r.ImGui_IsAnyItemActive(ctx) or false
        if r.ImGui_SetNextFrameWantCaptureKeyboard then
            pcall(r.ImGui_SetNextFrameWantCaptureKeyboard, ctx, active)
        end
        return active
    end

    ReflexConfigureKeyboardPassthrough()

end

return ReflexInstallStyleCore
