-- @noindex
-- Reflex route controls core module.
-- Installs shared ROUTE.row / SEND.col send-control widgets.

ReflexInstallRouteControlsCore = function(deps)
    local r = deps.r
    local ctx = deps.ctx
    local C = deps.colors

    local routeSliderBefore = nil
    local routeSliderMoved = false

    local function DrawRouteArrowIcon(dl, cx, cy, size, col)
        size = math.max(1, size or S(10))
        local shaft = size * 0.45
        local head_w = size * 0.32
        local head_h = size * 0.34
        local thick = math.max(1, size * 0.11)
        r.ImGui_DrawList_AddLine(dl, cx - shaft, cy, cx + shaft - head_w, cy, col, thick)
        r.ImGui_DrawList_AddTriangleFilled(dl,
            cx + shaft, cy,
            cx + shaft - head_w, cy - head_h,
            cx + shaft - head_w, cy + head_h,
            col)
    end

-- Mode labels for send mode dropdown
RouteSendModeLabels = { [0] = "Post", [1] = "Pre", [3] = "PreFX" }
RouteSendModeFullLabels = { [0] = "Post-Fader", [1] = "Pre-Fade / Post-FX", [3] = "Pre-Fade / Pre-FX" }

-- Route row volume value button (draggable, opt+click reset)
RouteVolValue = function(id, dl, track, category, send_idx, x, y, w, h, opt_bg, opt_hov, opt_act)
    local vol = r.GetTrackSendInfo_Value(track, category, send_idx, "D_VOL")
    local vol_str = InspFormatVol(vol)
    r.ImGui_SetCursorScreenPos(ctx, x, y)
    r.ImGui_InvisibleButton(ctx, id, w, h)
    local hov = r.ImGui_IsItemHovered(ctx)
    local act = r.ImGui_IsItemActive(ctx)
    -- Always-on bg, brighter on hover/active
    local bg = act and (opt_act or C.fx_ctrl_active) or (hov and (opt_hov or C.fx_ctrl_hover) or (opt_bg or C.fx_ctrl_bg))
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, S(3))
    local is_this = route_slider_drag_id == id
    if r.ImGui_IsItemClicked(ctx, 0) then
        if IsAlt(r.ImGui_GetKeyMods(ctx)) then
            r.Undo_BeginBlock()
            r.SetTrackSendInfo_Value(track, category, send_idx, "D_VOL", 1.0)
            r.Undo_EndBlock("Reflex: Reset send volume", -1)
        else
            route_slider_drag_id = id
            routeSliderBefore = r.GetTrackSendInfo_Value(track, category, send_idx, "D_VOL")
            routeSliderMoved = false
        end
    end
    if act and is_this then
        local _, mouse_dy = r.ImGui_GetMouseDelta(ctx)
        if mouse_dy ~= 0 then
            local db = vol < 0.00001 and -100 or 20 * math.log(vol, 10)
            db = db - mouse_dy * 0.15
            db = math.max(-100, math.min(12, db))
            local new_vol = db <= -100 and 0 or 10 ^ (db / 20)
            if math.abs(db) < 0.3 then new_vol = 1.0 end
            r.SetTrackSendInfo_Value(track, category, send_idx, "D_VOL", new_vol)
            routeSliderMoved = true
        end
    end
    if r.ImGui_IsItemDeactivated(ctx) and is_this then
        route_slider_drag_id = nil
        if routeSliderMoved and routeSliderBefore ~= nil then
            local final = r.GetTrackSendInfo_Value(track, category, send_idx, "D_VOL")
            r.SetTrackSendInfo_Value(track, category, send_idx, "D_VOL", routeSliderBefore)
            r.Undo_BeginBlock()
            r.SetTrackSendInfo_Value(track, category, send_idx, "D_VOL", final)
            r.Undo_EndBlock("Reflex: Adjust send volume", -1)
        end
        routeSliderBefore = nil; routeSliderMoved = false
    end
    -- Text
    local text_col = vol_str == "-inf" and C.text_muted or C.vol_slider_fill
    local tw = r.ImGui_CalcTextSize(ctx, vol_str)
    r.ImGui_DrawList_AddText(dl, x + Round((w - tw) / 2), y + Round((h - r.ImGui_GetTextLineHeight(ctx)) / 2), text_col, vol_str)
end

-- Route row pan value button (draggable, opt+click reset)
RoutePanValue = function(id, dl, track, category, send_idx, x, y, w, h, opt_bg, opt_hov, opt_act)
    local pan = r.GetTrackSendInfo_Value(track, category, send_idx, "D_PAN")
    local pan_str = InspFormatPan(pan)
    r.ImGui_SetCursorScreenPos(ctx, x, y)
    r.ImGui_InvisibleButton(ctx, id, w, h)
    local hov = r.ImGui_IsItemHovered(ctx)
    local act = r.ImGui_IsItemActive(ctx)
    -- Always-on bg
    local bg = act and (opt_act or C.fx_ctrl_active) or (hov and (opt_hov or C.fx_ctrl_hover) or (opt_bg or C.fx_ctrl_bg))
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, S(3))
    local is_this = route_slider_drag_id == id
    if r.ImGui_IsItemClicked(ctx, 0) then
        if IsAlt(r.ImGui_GetKeyMods(ctx)) then
            r.Undo_BeginBlock()
            r.SetTrackSendInfo_Value(track, category, send_idx, "D_PAN", 0)
            r.Undo_EndBlock("Reflex: Reset send pan", -1)
        else
            route_slider_drag_id = id
            routeSliderBefore = r.GetTrackSendInfo_Value(track, category, send_idx, "D_PAN")
            routeSliderMoved = false
        end
    end
    if act and is_this then
        local _, mouse_dy = r.ImGui_GetMouseDelta(ctx)
        if mouse_dy ~= 0 then
            local new_pan = pan - mouse_dy * 0.005
            new_pan = math.max(-1, math.min(1, new_pan))
            if math.abs(new_pan) < 0.015 then new_pan = 0 end
            r.SetTrackSendInfo_Value(track, category, send_idx, "D_PAN", new_pan)
            routeSliderMoved = true
        end
    end
    if r.ImGui_IsItemDeactivated(ctx) and is_this then
        route_slider_drag_id = nil
        if routeSliderMoved and routeSliderBefore ~= nil then
            local final = r.GetTrackSendInfo_Value(track, category, send_idx, "D_PAN")
            r.SetTrackSendInfo_Value(track, category, send_idx, "D_PAN", routeSliderBefore)
            r.Undo_BeginBlock()
            r.SetTrackSendInfo_Value(track, category, send_idx, "D_PAN", final)
            r.Undo_EndBlock("Reflex: Adjust send pan", -1)
        end
        routeSliderBefore = nil; routeSliderMoved = false
    end
    -- Always white text
    local tw = r.ImGui_CalcTextSize(ctx, pan_str)
    r.ImGui_DrawList_AddText(dl, x + Round((w - tw) / 2), y + Round((h - r.ImGui_GetTextLineHeight(ctx)) / 2), C.text, pan_str)
end

-- Route row MIDI channel dropdown (None/All/1-16)
RouteMidiDropdown = function(id, dl, track, category, send_idx, x, y, w, h, show_chrome)
    local flags = math.floor(r.GetTrackSendInfo_Value(track, category, send_idx, "I_MIDIFLAGS"))
    local src_ch = flags & 0x1F
    local midi_val
    if src_ch == 31 then midi_val = "None"
    elseif src_ch == 0 then midi_val = "All"
    else midi_val = tostring(src_ch) end
    local display = "M:" .. midi_val
    r.ImGui_SetCursorScreenPos(ctx, x, y)
    r.ImGui_InvisibleButton(ctx, id, w, h)
    local hov = r.ImGui_IsItemHovered(ctx)
    local clk = r.ImGui_IsItemClicked(ctx, 0)
    local txt_col = hov and 0xFFFFFFFF or C.text_dim
    local tw = r.ImGui_CalcTextSize(ctx, display)
    r.ImGui_DrawList_AddText(dl, x + w - tw, y + Round((h - r.ImGui_GetTextLineHeight(ctx)) / 2), txt_col, display)
    if clk then r.ImGui_OpenPopup(ctx, id .. "_p") end
    PushPopupStyle()
    if r.ImGui_BeginPopup(ctx, id .. "_p") then
        r.ImGui_TextColored(ctx, C.text_muted, "MIDI:")
        r.ImGui_Spacing(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
        local dest_bits = flags & (~0x1F)
        local is_none = src_ch == 31
        if r.ImGui_MenuItem(ctx, (is_none and "\xE2\x9C\x93 " or "") .. "None") then
            r.Undo_BeginBlock()
            r.SetTrackSendInfo_Value(track, category, send_idx, "I_MIDIFLAGS", dest_bits | 31)
            r.Undo_EndBlock("Reflex: Set MIDI channel", -1)
        end
        local is_all = src_ch == 0
        if r.ImGui_MenuItem(ctx, (is_all and "\xE2\x9C\x93 " or "") .. "All") then
            r.Undo_BeginBlock()
            r.SetTrackSendInfo_Value(track, category, send_idx, "I_MIDIFLAGS", dest_bits | 0)
            r.Undo_EndBlock("Reflex: Set MIDI channel", -1)
        end
        for ch = 1, 16 do
            local is_sel = src_ch == ch
            if r.ImGui_MenuItem(ctx, (is_sel and "\xE2\x9C\x93 " or "") .. tostring(ch)) then
                r.Undo_BeginBlock()
                r.SetTrackSendInfo_Value(track, category, send_idx, "I_MIDIFLAGS", dest_bits | ch)
                r.Undo_EndBlock("Reflex: Set MIDI channel", -1)
            end
        end
        r.ImGui_PopStyleColor(ctx, 1)
        r.ImGui_EndPopup(ctx)
    end
    PopPopupStyle()
end

-- Draw send mode dropdown for a routing row.
DrawRouteModeDD = function(id, dl, track, category, send_idx, x, y, w, h, opt_bg, opt_hov, opt_act)
    local cur_mode = math.floor(r.GetTrackSendInfo_Value(track, category, send_idx, "I_SENDMODE"))
    local label = RouteSendModeLabels[cur_mode] or "?"
    r.ImGui_SetCursorScreenPos(ctx, x, y)
    local dd_hov, dd_clk = NavRect(id, w, h, nil, {
        bg = opt_bg or C.fx_ctrl_bg, hov = opt_hov or C.fx_ctrl_hover, active = opt_act or C.fx_ctrl_active,
    })
    -- Draw label centered
    local tw = r.ImGui_CalcTextSize(ctx, label)
    r.ImGui_DrawList_AddText(dl, x + Round((w - tw) / 2), y + Round((h - r.ImGui_GetTextLineHeight(ctx)) / 2), C.text_dim, label)
    -- Popup
    local popup_id = id .. "_pop"
    if dd_clk then r.ImGui_OpenPopup(ctx, popup_id) end
    PushPopupStyle()
    if r.ImGui_BeginPopup(ctx, popup_id) then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
        for _, mode in ipairs({0, 1, 3}) do
            local ml = RouteSendModeFullLabels[mode]
            local is_sel = cur_mode == mode
            if is_sel then ml = "\xE2\x9C\x93 " .. ml end
            if r.ImGui_MenuItem(ctx, ml) then
                r.Undo_BeginBlock()
                r.SetTrackSendInfo_Value(track, category, send_idx, "I_SENDMODE", mode)
                r.Undo_EndBlock("Reflex: Set send mode", -1)
            end
        end
        r.ImGui_PopStyleColor(ctx, 1)
        r.ImGui_EndPopup(ctx)
    end
    PopPopupStyle()
end

-- Channel dropdown for routing panel rows (send/receive/hw output)
-- sx, sy = screen position; w, h = size; show_new = "New channels" submenu.
RouteChannelDropdown = function(id, dl, track, category, idx, param, max_chans, sx, sy, w, h, show_new, is_src)
    r.ImGui_SetCursorScreenPos(ctx, sx, sy)
    r.ImGui_InvisibleButton(ctx, id, w, h)
    local dd_hov = r.ImGui_IsItemHovered(ctx)
    local dd_clk = r.ImGui_IsItemClicked(ctx, 0)
    local val = math.floor(r.GetTrackSendInfo_Value(track, category, idx, param))
    local first_ch = (val & 0x3FF)
    local num_ch = math.floor(val / 1024)
    if num_ch < 1 then num_ch = 2 end
    local display
    if num_ch == 1 then display = tostring(first_ch + 1)
    else display = (first_ch + 1) .. "/" .. (first_ch + num_ch) end
    local dtw = r.ImGui_CalcTextSize(ctx, display)
    local txt_col = dd_hov and 0xFFFFFFFF or C.text_dim
    local tx
    if is_src then
        tx = sx + w - dtw - S(2)  -- right-align src
    else
        tx = sx + S(2)  -- left-align dst
    end
    r.ImGui_DrawList_AddText(dl, tx, sy + Round((h - r.ImGui_GetTextLineHeight(ctx)) / 2), txt_col, display)
    if dd_clk then r.ImGui_OpenPopup(ctx, id .. "_p") end
    local is_hw_dst = category == 1 and param == "I_DSTCHAN"
    PushPopupStyle()
    if r.ImGui_BeginPopup(ctx, id .. "_p") then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), C.fx_ctrl_hover)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
        -- Stereo pairs
        for ch = 0, max_chans - 2, 2 do
            local label = (ch + 1) .. "/" .. (ch + 2)
            local is_sel = first_ch == ch and num_ch == 2
            if is_sel then label = "\xE2\x9C\x93 " .. label end
            if r.ImGui_MenuItem(ctx, label) then
                local write_val = is_hw_dst and ch or (ch + (2 * 1024))
                r.Undo_BeginBlock()
                r.SetTrackSendInfo_Value(track, category, idx, param, write_val)
                r.Undo_EndBlock("Reflex: Set send channel", -1)
            end
        end
        -- New channels on receiving track (dest only, not for HW outputs)
        if show_new and not is_hw_dst then
            r.ImGui_Separator(ctx)
            if r.ImGui_BeginMenu(ctx, "New channels on receiving track") then
                for ch = max_chans, max_chans + 6, 2 do
                    local label = (ch + 1) .. "/" .. (ch + 2)
                    if r.ImGui_MenuItem(ctx, label) then
                        r.Undo_BeginBlock()
                        r.SetTrackSendInfo_Value(track, category, idx, param, ch + (2 * 1024))
                        r.Undo_EndBlock("Reflex: Set send channel", -1)
                    end
                end
                r.ImGui_EndMenu(ctx)
            end
        end
        r.ImGui_PopStyleColor(ctx, 2)
        r.ImGui_EndPopup(ctx)
    end
    PopPopupStyle()
end

-- Draw a complete routing item row (2-line layout)
-- Row 1: Name [src_ch]→[dst_ch] [MIDI]
-- Row 2: [VOL] [PAN] [mode][M][X]
DrawRouteRow = function(prefix, idx, dl, track, category, name, name_col, src_nchan, dest_nchan, bw, trk_sx, hover_col)
    local sc = 0.95  -- scale factor for content inside row card
    local btn_h = Round(S(UI.btn_h) * sc)
    local btn_gap = Round(S(UI.pad_sm) * sc)
    local dd_w = Round(S(30) * sc)
    local dd_gap = Round(S(4) * sc)
    local th = r.ImGui_GetTextLineHeight(ctx)
    -- Visual gap from name text bottom to vol button top should be ~8px.
    -- Row 1 name text is centered in btn_h, leaving (btn_h - th)/2 of padding below.
    -- Subtract that padding so net visible gap = 8px.
    local row_gap_inner = math.max(Round(S(2) * sc), Round(S(10) * sc) - Round((btn_h - th) / 2))
    local row_h = btn_h + row_gap_inner + btn_h  -- both rows use full button height

    -- Card padding and sizing (14px retina = S(8.75) uniform visual)
    local card_pad = S(8.75)
    local text_inset = Round((btn_h - th) / 2)  -- text centering adds this above row 1
    local card_px = card_pad
    local card_py_top = math.max(0, card_pad - text_inset) + S(1.25)  -- +2px retina for button room
    local card_py_bot = card_pad
    local card_r = S(UI.corner_r)
    local card_total_h = row_h + card_py_top + card_py_bot
    local inner_bw = bw - 2 * card_px  -- content width inside card

    local ry = r.ImGui_GetCursorPosY(ctx)
    r.ImGui_SetCursorPos(ctx, trk_sx, ry)
    local rx, rsy = r.ImGui_GetCursorScreenPos(ctx)

    -- Draw card background
    r.ImGui_DrawList_AddRectFilled(dl, rx, rsy, rx + bw, rsy + card_total_h, C.route_row_bg, card_r)

    -- Content origin (inset by card padding)
    local cx = rx + card_px
    local cy = rsy + card_py_top

    -- Row 2 Y positions (for mode/M/X)
    local r2y = cy + btn_h + row_gap_inner

    -- Mode width: accommodate longest label with padding
    local mode_pad = Round(S(16) * sc)
    local mode_w = math.max(
        r.ImGui_CalcTextSize(ctx, "Post") + mode_pad,
        r.ImGui_CalcTextSize(ctx, "Pre") + mode_pad,
        r.ImGui_CalcTextSize(ctx, "PreFX") + mode_pad
    )
    local del_x_off = inner_bw - btn_h
    local mute_x_off = del_x_off - btn_gap - btn_h
    local mode_x_off = mute_x_off - btn_gap - mode_w

    -- Row 1: Name [src_ch]→[dst_ch] [MIDI]
    local midi_w = Round(S(50) * sc)
    local arrow_w = r.ImGui_CalcTextSize(ctx, "\xE2\x86\x92")
    local arrow_gap = Round(S(3) * sc)
    local dd_w2 = Round(S(36) * sc)

    -- Name (left-aligned), clipped before the channel group
    local r1_cx = math.floor(cx + inner_bw)
    r1_cx = r1_cx - midi_w  -- reserve MIDI
    local midi_x = r1_cx
    r1_cx = r1_cx - btn_gap - dd_w2
    local dst_x = r1_cx
    r1_cx = r1_cx - arrow_gap - arrow_w
    local arrow_x = r1_cx
    r1_cx = r1_cx - arrow_gap - dd_w2
    local src_x = r1_cx

    local name_right = src_x - btn_gap
    -- Row hover: check mouse in full card area for color change
    -- Suppress hover on other rows during route slider drag
    local row_hov = false
    if hover_col then
        local dragging_other = route_slider_drag_id and not (
            route_slider_drag_id == (prefix .. "vol" .. idx) or
            route_slider_drag_id == (prefix .. "pan" .. idx))
        if not dragging_other then
            local mx, my = r.ImGui_GetMousePos(ctx)
            row_hov = mx >= rx and mx <= rx + bw and my >= rsy and my <= rsy + card_total_h
        end
        -- Force hover on when dragging this row's controls
        if route_slider_drag_id == (prefix .. "vol" .. idx) or
           route_slider_drag_id == (prefix .. "pan" .. idx) then
            row_hov = true
        end
        -- Track hovered send for sends view highlight
        if row_hov and category == 0 and sends_view_active then
            route_hovered_send_idx = idx
        end
    end
    -- Hover: brighten card bg instead of changing name color
    if row_hov then
        r.ImGui_DrawList_AddRectFilled(dl, rx, rsy, rx + bw, rsy + card_total_h, C.route_row_bg_hov, card_r)
    end
    local draw_name_col = name_col
    r.ImGui_DrawList_PushClipRect(dl, cx, cy, name_right, cy + btn_h, true)
    r.ImGui_DrawList_AddText(dl, cx, cy + Round((btn_h - th) / 2), draw_name_col, name)
    r.ImGui_DrawList_PopClipRect(dl)
    -- v20.486: track-name link follows global locate convention — hand cursor +
    -- underline on hover, hyperlink-tight hit area (text width only, not the full
    -- pre-channel-group region). LocateInREAPER selects + reveals + scrolls; Opt+
    -- click peek without state change (consistent with other TitleLink call sites).
    -- HW sends have no "other end" track, so plain text only — no link affordance.
    if category ~= 1 and r.BR_GetMediaTrackSendInfo_Track then
        local _ref_idx = (category == -1) and 0 or 1
        local _other = r.BR_GetMediaTrackSendInfo_Track(track, category, idx, _ref_idx)
        if _other and r.ValidatePtr(_other, "MediaTrack*") then
            local _name_tw = r.ImGui_CalcTextSize(ctx, name)
            local _link_w = math.min(_name_tw, math.max(1, name_right - cx))
            local _link_y = cy + Round((btn_h - th) / 2)
            local _link_hov = TitleLink(prefix .. "namelink" .. idx, cx, _link_y, _link_w, th, _other, {})
            if _link_hov then
                r.ImGui_DrawList_AddLine(dl, cx, _link_y + th, cx + _link_w, _link_y + th, draw_name_col, 1)
            end
        end
    end

    -- src_ch, arrow, dst_ch, MIDI on Row 1
    RouteChannelDropdown(prefix .. "sch" .. idx, dl, track, category, idx, "I_SRCCHAN", src_nchan,
        src_x, cy, dd_w2, btn_h, false, true)
    DrawRouteArrowIcon(dl, arrow_x + S(5), cy + btn_h * 0.5, S(10), C.text_muted)
    RouteChannelDropdown(prefix .. "dch" .. idx, dl, track, category, idx, "I_DSTCHAN", dest_nchan,
        dst_x, cy, dd_w2, btn_h, true, false)
    RouteMidiDropdown(prefix .. "midi" .. idx, dl, track, category, idx, midi_x, cy, midi_w, btn_h, false)

    -- Row 2: [VOL] [PAN] ... [mode][M][X]
    local vol_val_w = math.max(btn_h, r.ImGui_CalcTextSize(ctx, "-00.0") + Round(S(24) * sc))
    local pan_val_w = math.max(btn_h, r.ImGui_CalcTextSize(ctx, "100R") + Round(S(16) * sc))
    local vol_pan_gap = Round(S(UI.pad_sm) * sc)

    -- Route row button colors
    local rr_bg = C.route_row_btn
    local rr_hov = C.route_row_btn_hov
    local rr_act = C.route_row_btn_act

    -- Left-aligned: [VOL] [PAN]
    RouteVolValue(prefix .. "vol" .. idx, dl, track, category, idx, cx, r2y, vol_val_w, btn_h, rr_bg, rr_hov, rr_act)
    RoutePanValue(prefix .. "pan" .. idx, dl, track, category, idx, cx + vol_val_w + vol_pan_gap, r2y, pan_val_w, btn_h, rr_bg, rr_hov, rr_act)

    -- Right-aligned: [mode][M][X]
    DrawRouteModeDD(prefix .. "mode" .. idx, dl, track, category, idx, cx + mode_x_off, r2y, mode_w, btn_h, rr_bg, rr_hov, rr_act)

    -- Mute
    local is_muted = r.GetTrackSendInfo_Value(track, category, idx, "B_MUTE") == 1
    local m_opts
    if is_muted then
        m_opts = MuteOpts(true)
    else
        m_opts = {
            bg = rr_bg, hov = rr_hov, active = rr_act,
            fg = (C.text_dim & 0xFFFFFF00) | math.floor((C.text_dim & 0xFF) * 0.4),
            fg_hov = C.text_dim,
        }
    end
    r.ImGui_SetCursorScreenPos(ctx, cx + mute_x_off, r2y)
    local _, m_clk = NavSquare(prefix .. "mute" .. idx, btn_h, btn_h, "M", m_opts)
    if m_clk then
        r.Undo_BeginBlock()
        r.SetTrackSendInfo_Value(track, category, idx, "B_MUTE", is_muted and 0 or 1)
        r.Undo_EndBlock("Reflex: Send mute", -1)
    end

    -- Delete
    r.ImGui_SetCursorScreenPos(ctx, cx + del_x_off, r2y)
    local _, x_clk = NavSquare(prefix .. "del" .. idx, btn_h, btn_h, "x", {
        bg = rr_bg, fg = C.text_muted,
        hov = C.fx_offline_txt, fg_hov = 0xFFFFFFFF,
    })
    if x_clk then
        r.Undo_BeginBlock(); r.RemoveTrackSend(track, category, idx)
        r.Undo_EndBlock("Reflex: Delete " .. (category == 0 and "send" or category == -1 and "receive" or "hw output"), -1)
    end

    -- v20.486: per-row right-click → Copy/Paste menu. ANY area of the row
    -- (including sub-widgets like vol/pan/mute/X — none of them have their
    -- own right-click handlers) opens this menu. Hover-rect-bounded so
    -- right-clicks on neighboring rows don't fire here. Sets
    -- `nav_rclick_consumed` so the inspector card's catch-all skips opening
    -- trknamectx for the same click.
    do
        local row_ctx_id = prefix .. "row_ctx" .. idx
        if r.ImGui_IsMouseClicked(ctx, 1)
           and r.ImGui_IsMouseHoveringRect(ctx, rx, rsy, rx + bw, rsy + card_total_h) then
            r.ImGui_OpenPopup(ctx, row_ctx_id)
            nav_rclick_consumed = true
        end
        if r.ImGui_BeginPopup(ctx, row_ctx_id) then
            local rfp = PushFont(GetScaledFont())
            local copy_label = (category == 0 and "Copy send")
                            or (category == -1 and "Copy receive")
                            or "Copy HW send"
            if r.ImGui_MenuItem(ctx, copy_label) then
                RoutingClipboardCopyOne(track, category, idx)
            end
            local _plbl = RoutingClipboardPasteLabel()
            if _plbl then
                r.ImGui_Separator(ctx)
                if r.ImGui_MenuItem(ctx, _plbl) then
                    RoutingClipboardPaste(track)
                end
            end
            PopFont(rfp)
            r.ImGui_EndPopup(ctx)
        end
    end

    -- Advance cursor past card
    r.ImGui_SetCursorPos(ctx, trk_sx, ry + card_total_h)
end

end

return ReflexInstallRouteControlsCore
