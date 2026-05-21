-- @noindex
-- Reflex distant-send core module.
-- Installs SEND.distant section and collapsed-card renderers.

ReflexInstallSendDistantCore = function(deps)
    local r = deps.r
    local ctx = deps.ctx
    local C = deps.colors

-- Draw a collapsed spanning distant-send card. Caller owns expansion state.
DrawDistantSendCollapsedCard = function(dentry, di, dl, cx, cy, w, h, content_h)
    local rcx, rcy = math.floor(cx), math.floor(cy)
    local rcx2, rcy2 = math.floor(cx + w), math.floor(cy + h)
    local btn_h = S(UI.btn_h)
    local col_r = opt_card_boxes and S(UI.card_r) or S(UI.corner_r)
    local d_hov = r.ImGui_IsMouseHoveringRect(ctx, rcx, rcy, rcx2, rcy2)
    if d_hov then
        r.ImGui_DrawList_AddRectFilled(dl, rcx, rcy, rcx2, rcy2, C.bg, col_r)
    else
        r.ImGui_DrawList_AddRectFilled(dl, rcx, rcy, rcx2, rcy2, 0x202227FF, col_r)
    end

    local dtrack = dentry and dentry.track or nil
    if dtrack and r.ValidatePtr(dtrack, "MediaTrack*") then
        local _, dname = r.GetTrackName(dtrack)
        local dnum = math.floor(r.GetMediaTrackInfo_Value(dtrack, "IP_TRACKNUMBER"))
        local dnum_label = ((dnum == 0) and "M" or tostring(dnum)) .. ":"
        local dcolor_raw = r.GetTrackColor(dtrack)
        local dnum_col = dcolor_raw ~= 0 and TrackColorToImGui(dcolor_raw) or C.text_muted
        local d_pad_x = S(UI.card_pad)
        local content_y = rcy + Round((h - content_h) / 2)
        local tx = rcx + d_pad_x

        -- SC square button (blue bg, faded when collapsed+not hovered)
        local name_right = rcx2 - d_pad_x
        if dentry.is_sidechain then
            local sc_base_bg = 0x2775DEFF
            local sc_sz = btn_h
            local sc_x = rcx2 - d_pad_x - sc_sz
            local sc_y = content_y + Round((content_h - sc_sz) / 2)
            local sc_bg_col, sc_txt_col
            if d_hov then
                sc_bg_col = sc_base_bg
                sc_txt_col = 0xFFFFFFFF
            else
                -- Fade 40%
                sc_bg_col = (sc_base_bg & 0xFFFFFF00) | math.floor((sc_base_bg & 0xFF) * 0.4)
                sc_txt_col = (0xFFFFFFFF & 0xFFFFFF00) | math.floor(0xFF * 0.4)
            end
            r.ImGui_DrawList_AddRectFilled(dl, sc_x, sc_y,
                sc_x + sc_sz, sc_y + sc_sz, sc_bg_col, S(UI.corner_r))
            local sc_tw = r.ImGui_CalcTextSize(ctx, "SC")
            local sc_th_local = r.ImGui_GetTextLineHeight(ctx)
            r.ImGui_DrawList_AddText(dl,
                sc_x + Round((sc_sz - sc_tw) / 2),
                sc_y + Round((sc_sz - sc_th_local) / 2),
                sc_txt_col, "SC")
            name_right = sc_x - S(4)
        end

        -- Number + name (TitleLink for locate gesture)
        local title_font = GetSteppedFont(UI.font_send_title)
        if title_font then r.ImGui_PushFont(ctx, title_font) end
        local title_h = r.ImGui_GetTextLineHeight(ctx)
        local dnum_tw = r.ImGui_CalcTextSize(ctx, dnum_label)
        local ty = content_y + Round((content_h - title_h) / 2)
        local name_avail = name_right - tx - dnum_tw - S(4)
        local display_name = dname
        local name_tw = r.ImGui_CalcTextSize(ctx, display_name)
        if name_tw > name_avail then
            local ellipsis = "\xE2\x80\xA6"
            local ew = r.ImGui_CalcTextSize(ctx, ellipsis)
            while name_tw + ew > name_avail and #display_name > 0 do
                display_name = Utf8DropLast(display_name)
                name_tw = r.ImGui_CalcTextSize(ctx, display_name)
            end
            display_name = display_name .. ellipsis
        end
        r.ImGui_DrawList_AddText(dl, tx, ty, dnum_col, dnum_label)
        r.ImGui_DrawList_AddText(dl, tx + dnum_tw + S(4), ty, C.text, display_name)
        if title_font then r.ImGui_PopFont(ctx) end

        -- TitleLink claims the text region for locate; card button below
        -- remains additive for expand unless the gesture was Opt-peek.
        local d_link_w = math.min(dnum_tw + S(4) + name_tw, name_right - tx)
        local d_th_local = TitleLink(
            "##dtitlelink" .. di, tx, content_y, d_link_w, content_h, dtrack, {})
        if d_th_local then
            local d_underline_y = ty + r.ImGui_GetTextLineHeight(ctx)
            r.ImGui_DrawList_AddLine(dl, tx, d_underline_y, tx + d_link_w, d_underline_y, C.text, 1)
        end
    end

    r.ImGui_SetCursorScreenPos(ctx, cx, cy)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
    local dclk = r.ImGui_Button(ctx, "##dist_card", w, h)
    r.ImGui_PopStyleColor(ctx, 3)
    return dclk and not nav_title_peek_consumed
end

SendsDrawDistantSection = function(bw, dl, sends_base_sx, title_h, btn_h, row_gap,
                                   knob_d, knob_unit, est_arrow_w, est_fx_btn_w,
                                   est_addfx_w, est_route_w, col_pad_top, col_pad_bot,
                                   title_gap, fx_h, fx_gap_v)
    if #sends_view_distant == 0 then return end

    local dist_gap = S(UI.edge_pad) - 2 + S(UI.bg_label_gap_above)
    r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + dist_gap)
    r.ImGui_SetCursorPosX(ctx, sends_base_sx)

    local dist_lx, dist_ly = r.ImGui_GetCursorScreenPos(ctx)
    local dist_th = r.ImGui_GetTextLineHeight(ctx)
    r.ImGui_DrawList_AddText(dl, dist_lx, dist_ly, C.bg_label, "Distant Sends")
    r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + dist_th + S(UI.bg_label_gap_below))

    local d_count = #sends_view_distant
    local d_pad_v = S(UI.card_pad_top)
    local d_content_h = math.max(title_h, btn_h)
    local collapsed_h = d_pad_v + d_content_h + d_pad_v
    local d_gap = S(UI.edge_pad) - 2

    -- Expanded height vars for full-width distant cards
    local d_inner_w = bw - S(UI.card_pad) * 2
    local d_knobs_wrap = d_inner_w < (knob_d * 2 + row_gap)
    local d_knob_pair_h = d_knobs_wrap and (knob_unit * 2 + row_gap) or knob_unit
    local d_ctrl_wrap = (est_arrow_w + est_fx_btn_w + est_addfx_w + row_gap + est_route_w) > d_inner_w
    local d_ctrl_h = btn_h + (d_ctrl_wrap and (row_gap + btn_h) or 0)

    for di, dentry in ipairs(sends_view_distant) do
        r.ImGui_SetCursorPosX(ctx, sends_base_sx)
        local dtrack = dentry.track
        local is_exp = sends_distant_expanded[di] == true

        r.ImGui_PushID(ctx, di + 9000)

        -- Refresh FX cache before height computation
        if is_exp and dtrack and r.ValidatePtr(dtrack, "MediaTrack*") then
            SendsEnsureFxNameCache(dtrack)
        end

        local d_col_h = collapsed_h
        local d_fx_max = 0
        if is_exp and dtrack and r.ValidatePtr(dtrack, "MediaTrack*") then
            -- SND section: always fully expanded for distant sends (two-state: open/closed)
            local d_snd_hdr_h = btn_h + row_gap
            local d_knob_row_h = d_knobs_wrap
                and (knob_unit + row_gap + btn_h + row_gap + knob_unit + row_gap)
                or (knob_unit + row_gap)
            local mode_w = r.ImGui_CalcTextSize(ctx, "PreFX") + S(16)
            local env_w = math.floor(InspCtrlW("ENV") * 1.2)
            local mode_env_wrap = (mode_w + row_gap + env_w) > d_inner_w
            local mode_h = btn_h + row_gap + (mode_env_wrap and (btn_h + row_gap) or 0)
            local sep_gap = S(UI.edge_pad) + 1
            local sep_h = (sep_gap - row_gap) + math.max(S(2), Round(S(2.5))) + sep_gap
            local d_snd_body_h = d_knob_row_h + mode_h + sep_h

            local d_fx_not_collapsed = not (insp_fx_collapsed[dtrack] == true)
            if d_fx_not_collapsed then
                d_fx_max = SendsFxCachedCount(dtrack)
            end
            -- v20.420: trailing add-FX row removed (entry now in compound +).
            local d_fx_slots = d_fx_not_collapsed and d_fx_max or 0
            local d_fx_area_h = d_fx_slots > 0 and (d_fx_slots * fx_h + (d_fx_slots - 1) * fx_gap_v) or 0
            d_col_h = col_pad_top
                     + d_snd_hdr_h + d_snd_body_h
                     + title_h + title_gap + 3
                     + d_ctrl_h + row_gap
                     + d_fx_area_h
                     + S(UI.section_gap) + 2
                     + d_knob_pair_h
                     + (S(UI.section_gap) + btn_h)
                     + col_pad_bot
        end

        local d_sy = r.ImGui_GetCursorPosY(ctx)
        local d_cx, d_cy = r.ImGui_GetCursorScreenPos(ctx)

        if is_exp and dtrack and r.ValidatePtr(dtrack, "MediaTrack*") then
            -- Expanded: full send module card spanning full width.
            -- Force SND expanded (distant sends have only two states: fully open or closed).
            sends_snd_expanded[dentry.send_idx] = true
            sends_distant_rendering = true
            sends_distant_collapse_request = false
            local d_ct_clicked = DrawCompactTrackColumn(dtrack, r.ImGui_GetWindowDrawList(ctx), d_cx, d_cy, bw, d_col_h, d_fx_max,
                sends_view_source, dentry.send_idx)
            local snd_collapse_req = sends_distant_collapse_request
            sends_distant_collapse_request = false
            sends_distant_rendering = false

            -- Collapse on title click, SND header click, OR on blank-area click.
            local d_blank_click = r.ImGui_IsMouseHoveringRect(ctx, d_cx, d_cy, d_cx + bw, d_cy + d_col_h)
                                  and r.ImGui_IsMouseClicked(ctx, 0)
                                  and not r.ImGui_IsAnyItemActive(ctx)
            if d_ct_clicked or d_blank_click or snd_collapse_req then
                sends_distant_expanded = {}
            end
        else
            -- Title-link locate is additive; Opt-peek is suppressed by the collapsed-card helper.
            local dclk = DrawDistantSendCollapsedCard(dentry, di, dl, d_cx, d_cy, bw, d_col_h, d_content_h)
            if dclk then
                if sends_distant_expanded[di] then
                    sends_distant_expanded = {}
                else
                    sends_distant_expanded = { [di] = true }
                    sends_expand_scroll_cy = d_sy
                end
            end
        end

        r.ImGui_PopID(ctx)

        r.ImGui_SetCursorPosY(ctx, d_sy + d_col_h)
        r.ImGui_SetCursorPosX(ctx, sends_base_sx)

        if di < d_count then
            r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + d_gap)
        end
    end
end

end

return ReflexInstallSendDistantCore
