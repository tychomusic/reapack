-- @noindex
-- Reflex send grid core module.
-- Installs the SEND section/side-column wrappers, blank-cell renderers, measurements, and grouped renderers.

ReflexInstallSendGridCore = function(deps)
    local r = deps.r
    local ctx = deps.ctx
    local C = deps.colors

DrawSendAddCard = function(dl, x, y, w, h, target, target_folder, button_id, popup_id)
    local rcx, rcy = math.floor(x), math.floor(y)
    local rcx2, rcy2 = math.floor(x + w), math.floor(y + h)
    local card_r = opt_card_boxes and S(UI.card_r) or S(UI.corner_r)
    r.ImGui_DrawList_AddRectFilled(dl, rcx, rcy, rcx2, rcy2, C.placeholder_bg, card_r)

    r.ImGui_SetCursorScreenPos(ctx, rcx, rcy)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
    local clicked = r.ImGui_Button(ctx, button_id, rcx2 - rcx, rcy2 - rcy)
    r.ImGui_PopStyleColor(ctx, 3)

    local hovered = r.ImGui_IsItemHovered(ctx)
    Tip("Create send to new track" .. (target_folder and " (inside folder)" or "") .. "\nRight-click for options")
    if clicked and target then
        RoutingAddSendTrack(target, nil, target_folder)
    end
    if popup_id then
        if r.ImGui_IsItemClicked(ctx, 1) then
            r.ImGui_OpenPopup(ctx, popup_id)
        end
        AddSendModePopup(popup_id, target, target_folder)
    end

    local plus_d = S(UI.btn_h)
    local pcx = rcx + math.floor((rcx2 - rcx) / 2)
    local pcy = rcy + math.floor((rcy2 - rcy) / 2)
    if hovered then
        r.ImGui_DrawList_AddCircleFilled(dl, pcx, pcy, plus_d / 2, C.fx_ctrl_hover, 0)
    end
    DrawIcon(dl, pcx, pcy, plus_d, "+",
        hovered and C.text or ((C.text_dim & 0xFFFFFF00) | math.floor((C.text_dim & 0xFF) * 0.35)))

    return clicked, hovered
end

DrawSendDimPlaceholder = function(dl, x, y, w, h)
    local rcx, rcy = math.floor(x), math.floor(y)
    local rcx2, rcy2 = math.floor(x + w), math.floor(y + h)
    local card_r = opt_card_boxes and S(UI.card_r) or S(UI.corner_r)
    local dim_bg = (C.placeholder_bg & 0xFFFFFF00) | math.floor((C.placeholder_bg & 0xFF) * 0.45)
    r.ImGui_DrawList_AddRectFilled(dl, rcx, rcy, rcx2, rcy2, dim_bg, card_r)
end

SendsDrawSpanningAddRow = function(groups, bw, dl, sends_base_sx)
    -- Find last conforming group's folder for targeting.
    local span_folder = nil
    for ggi = #groups, 1, -1 do
        if not groups[ggi].is_ungrouped and #groups[ggi].folder_chain > 0 then
            span_folder = groups[ggi].folder_chain[1]
            break
        end
    end
    -- Skip spanning add-send row when no conforming groups exist (ungrouped-only sessions).
    if not span_folder then return end

    local span_gap = S(UI.edge_pad) - 2
    r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + span_gap)
    r.ImGui_SetCursorPosX(ctx, sends_base_sx)
    local span_h = S(UI.btn_h) + S(UI.card_pad_top) + S(UI.card_pad_bot)
    local span_cx, span_cy = r.ImGui_GetCursorScreenPos(ctx)
    local span_target = sends_view_source
    if not (span_target and r.ValidatePtr(span_target, "MediaTrack*")) then
        span_target = NavRoutingTargetTrack()
    end
    DrawSendAddCard(dl, span_cx, span_cy, bw, span_h, span_target, span_folder,
        "##addsend_span", "##addsend_mode_span")
end

SendsMeasureGrid = function(bw, cols, col_gap)
    local total_gap = col_gap * (cols - 1)
    local col_w = math.floor((bw - total_gap) / cols)
    local col_pad_top = S(UI.send_pad_top)
    local col_pad_bot = S(UI.send_pad_bot)

    local title_font = GetSteppedFont(UI.font_send_title)
    if title_font then r.ImGui_PushFont(ctx, title_font) end
    local title_h = r.ImGui_GetTextLineHeight(ctx)
    if title_font then r.ImGui_PopFont(ctx) end

    local btn_h = S(UI.btn_h)
    local row_gap = S(UI.pad_sm)
    local title_gap = S(UI.section_gap)
    local fx_h = S(UI.btn_h)
    local fx_gap_v = S(UI.fx_gap)
    local knob_d = Round(btn_h * 1.5)
    local body_text_h = r.ImGui_GetTextLineHeight(ctx)
    local est_inner_w = col_w - S(UI.card_pad) * 2
    local knobs_wrap = est_inner_w < (knob_d * 2 + row_gap)
    local knob_unit = knob_d + S(2) + body_text_h
    local knob_pair_h = knobs_wrap and (knob_unit * 2 + row_gap) or knob_unit
    local est_fx_btn_w = math.floor(InspCtrlW("FX") * 1.4)
    local est_arrow_w = btn_h + math.floor(row_gap / 2)
    local est_route_w = S(10) * 2 + S(4) * 6 + S(7) * 2
    -- v20.425: include + button width (added to compound in v20.420). Without
    -- this, parent under-estimates compound width at certain card widths,
    -- predicting no-wrap while the child renders wrap — card height is then
    -- short by (row_gap + btn_h), pushing M/S off the bottom edge.
    local est_addfx_w = btn_h
    local ctrl_wrap = (est_arrow_w + est_fx_btn_w + est_addfx_w + row_gap + est_route_w) > est_inner_w
    local ctrl_h = btn_h + (ctrl_wrap and (row_gap + btn_h) or 0)
    local ms_row_h = S(UI.section_gap) + btn_h

    return col_w, col_pad_top, col_pad_bot, title_h, btn_h, row_gap, title_gap,
           fx_h, fx_gap_v, knob_d, knob_unit, knob_pair_h, knobs_wrap, est_inner_w,
           est_fx_btn_w, est_arrow_w, est_route_w, est_addfx_w, ctrl_h, ms_row_h
end

SendsDrawGroupColumns = function(group, gi, cols, col_w, col_gap, dl, sends_base_sx,
                                title_h, title_gap, btn_h, row_gap, knob_unit,
                                knob_pair_h, knobs_wrap, est_inner_w, ctrl_h,
                                col_pad_top, col_pad_bot, fx_h, fx_gap_v, ms_row_h,
                                last_conforming_last_row_full)
    local is_ungrouped = group.is_ungrouped == true
    local group_folder = (not is_ungrouped and group.folder_chain and #group.folder_chain > 0) and group.folder_chain[1] or nil
    local g_indices = group.indices
    if not g_indices then return last_conforming_last_row_full end

    local g_count = #g_indices
    local g_row_start = 1
    while g_row_start <= g_count do
        local g_row_end = math.min(g_row_start + cols - 1, g_count)
        local is_last_row_of_group = (g_row_end >= g_count)

        -- Max FX count in this row for uniform height.
        local max_fx = 0
        local any_fx_expanded = false
        for ri = g_row_start, g_row_end do
            local ti = g_indices[ri]
            local t = sends_view_tracks[ti]
            if t and r.ValidatePtr(t, "MediaTrack*") then
                if not (insp_fx_collapsed[t] == true) then
                    any_fx_expanded = true
                    local fc = SendsFxCachedCount(t)
                    if fc > max_fx then max_fx = fc end
                end
            end
        end
        -- v20.420: trailing add-FX row removed (entry now in compound +).
        local fx_slots = any_fx_expanded and max_fx or 0
        local fx_area_h = fx_slots > 0 and (fx_slots * fx_h + (fx_slots - 1) * fx_gap_v) or 0

        -- SND section height: check if any send in row is expanded.
        local any_snd_expanded = false
        for ri = g_row_start, g_row_end do
            local ti = g_indices[ri]
            local si = sends_view_send_indices[ti]
            if si and sends_snd_expanded[si] then any_snd_expanded = true; break end
        end
        local snd_hdr_h = btn_h + row_gap
        local snd_body_h = 0
        if any_snd_expanded then
            local knob_row_h = knobs_wrap
                and (knob_unit + row_gap + btn_h + row_gap + knob_unit + row_gap)
                or (knob_unit + row_gap)
            local mode_w = r.ImGui_CalcTextSize(ctx, "PreFX") + S(16)
            local env_w = math.floor(InspCtrlW("ENV") * 1.2)
            local mode_env_wrap = (mode_w + row_gap + env_w) > est_inner_w
            local mode_h = btn_h + row_gap + (mode_env_wrap and (btn_h + row_gap) or 0)
            local sep_gap = S(UI.edge_pad) + 1
            local sep_h = (sep_gap - row_gap) + math.max(S(2), Round(S(2.5))) + sep_gap
            snd_body_h = knob_row_h + mode_h + sep_h
        end

        local col_h = col_pad_top
                     + snd_hdr_h + snd_body_h
                     + title_h + title_gap + 3
                     + ctrl_h + row_gap
                     + fx_area_h
                     + S(UI.section_gap) + 2
                     + knob_pair_h
                     + ms_row_h
                     + col_pad_bot

        local row_sy = r.ImGui_GetCursorPosY(ctx)
        r.ImGui_SetCursorPosX(ctx, sends_base_sx)
        local row_cx, row_cy = r.ImGui_GetCursorScreenPos(ctx)

        for ci = 0, (g_row_end - g_row_start) do
            local ri = g_row_start + ci
            local ti = g_indices[ri]
            local track = sends_view_tracks[ti]
            if not track or not r.ValidatePtr(track, "MediaTrack*") then break end

            local ccx = row_cx + ci * (col_w + col_gap)

            r.ImGui_PushID(ctx, ti + 1000)

            -- Update FX name cache for this track.
            SendsEnsureFxNameCache(track)

            DrawCompactTrackColumn(track, r.ImGui_GetWindowDrawList(ctx), ccx, row_cy, col_w, col_h, max_fx,
                sends_view_source, sends_view_send_indices[ti])
            r.ImGui_PopID(ctx)
        end

        -- Empty cell handling:
        -- Conforming groups: add-send cards on last row (targeting group folder),
        -- dim placeholders on non-last rows. Ungrouped groups leave blanks empty.
        local actual_cols = g_row_end - g_row_start + 1
        if is_ungrouped then
            -- No cards, no placeholders.
        elseif is_last_row_of_group and actual_cols < cols then
            last_conforming_last_row_full = false
            local add_target = sends_view_source
            if not (add_target and r.ValidatePtr(add_target, "MediaTrack*")) then
                add_target = NavRoutingTargetTrack()
            end
            for ci = actual_cols, cols - 1 do
                local ccx = row_cx + ci * (col_w + col_gap)
                r.ImGui_PushID(ctx, ci + 8000 + gi * 100)
                DrawSendAddCard(dl, ccx, row_cy, col_w, col_h, add_target, group_folder,
                    "##addsend_blank", "##addsend_mode_blank" .. gi .. "_" .. ci)
                r.ImGui_PopID(ctx)
            end
        elseif not is_last_row_of_group and actual_cols < cols then
            -- Non-final row: dim empty placeholders to fill the grid visually.
            for ci = actual_cols, cols - 1 do
                local ccx = row_cx + ci * (col_w + col_gap)
                DrawSendDimPlaceholder(dl, ccx, row_cy, col_w, col_h)
            end
        elseif is_last_row_of_group and not is_ungrouped then
            last_conforming_last_row_full = true
        end

        r.ImGui_SetCursorPosY(ctx, row_sy + col_h)
        r.ImGui_SetCursorPosX(ctx, sends_base_sx)

        g_row_start = g_row_end + 1

        -- Gap between rows within same group.
        if g_row_start <= g_count then
            r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + S(UI.edge_pad) - 2)
        end
    end

    return last_conforming_last_row_full
end

SendsDrawGroups = function(groups, bw, dl, sends_base_sx, cols, col_w, col_gap,
                           title_h, title_gap, btn_h, row_gap, knob_d, knob_unit,
                           knob_pair_h, knobs_wrap, est_inner_w, est_arrow_w,
                           est_fx_btn_w, est_addfx_w, est_route_w, ctrl_h,
                           col_pad_top, col_pad_bot, fx_h, fx_gap_v, ms_row_h)
    local last_conforming_last_row_full = true

    for gi, group in ipairs(groups) do
        local is_ungrouped = group.is_ungrouped == true

        -- Section label for ungrouped sends.
        if is_ungrouped then
            local ug_gap = S(UI.edge_pad) - 2 + S(16)
            r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + ug_gap)
            r.ImGui_SetCursorPosX(ctx, sends_base_sx)
            local ug_lx, ug_ly = r.ImGui_GetCursorScreenPos(ctx)
            r.ImGui_DrawList_AddText(dl, ug_lx, ug_ly, 0x5C5C5CFF, "Ungrouped")
            r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + r.ImGui_GetTextLineHeight(ctx) + S(12))
        end

        -- Draw folder cards for this group (outermost first) — skip for ungrouped.
        SendsDrawFolderChain(group, gi, bw, dl, sends_base_sx, title_h, title_gap,
            btn_h, row_gap, knob_d, knob_unit, est_arrow_w, est_fx_btn_w,
            est_addfx_w, est_route_w, col_pad_top, col_pad_bot, fx_h, fx_gap_v,
            ms_row_h)

        -- Draw this group's send columns in rows.
        last_conforming_last_row_full = SendsDrawGroupColumns(group, gi, cols, col_w, col_gap, dl,
            sends_base_sx, title_h, title_gap, btn_h, row_gap, knob_unit,
            knob_pair_h, knobs_wrap, est_inner_w, ctrl_h, col_pad_top, col_pad_bot,
            fx_h, fx_gap_v, ms_row_h, last_conforming_last_row_full)

        -- Gap between groups.
        if gi < #groups then
            r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + S(UI.edge_pad) - 2)
        end
    end

    return last_conforming_last_row_full
end

SendsDrawSection = function(bw, skip_top_margin)
    -- Check refresh first (may activate/deactivate sends view)
    SendsViewCheckRefresh()
    if not sends_view_active or #sends_view_tracks == 0 then return end

    local cols = math.max(1, math.min(6, sends_view_cols))
    local col_gap = S(UI.edge_pad) - 2

    -- Handle scroll-to on activation
    if sends_view_scroll_pending then
        r.ImGui_SetScrollHereY(ctx, 0.0)
        sends_view_scroll_pending = false
    end

    -- Top-margin: SENDS owns gap above (skip when rendering side-by-side)
    if not skip_top_margin then
        r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + S(UI.edge_pad) - 2)
    end

    local gfg = r.ImGui_GetWindowDrawList(ctx)
    local sends_base_sx = r.ImGui_GetCursorPosX(ctx)  -- save initial X for row resets

    -- Use groups if available, else single flat group. Remote-only topologies
    -- intentionally leave groups empty so SEND.distant can render by itself.
    local groups = sends_view_groups or {}
    if #groups == 0 and #sends_view_distant == 0 then
        local all = {}
        for i = 1, #sends_view_tracks do all[#all + 1] = i end
        groups = { { folder_chain = {}, indices = all } }
    end

    local col_w, col_pad_top, col_pad_bot, title_h, btn_h, row_gap, title_gap,
          fx_h, fx_gap_v, knob_d, knob_unit, knob_pair_h, knobs_wrap, est_inner_w,
          est_fx_btn_w, est_arrow_w, est_route_w, est_addfx_w, ctrl_h, ms_row_h =
        SendsMeasureGrid(bw, cols, col_gap)

    local last_conforming_last_row_full = SendsDrawGroups(groups, bw, gfg, sends_base_sx,
        cols, col_w, col_gap, title_h, title_gap, btn_h, row_gap, knob_d, knob_unit,
        knob_pair_h, knobs_wrap, est_inner_w, est_arrow_w, est_fx_btn_w, est_addfx_w,
        est_route_w, ctrl_h, col_pad_top, col_pad_bot, fx_h, fx_gap_v, ms_row_h)

    -- Spanning add-send row (only when last conforming group's last row was full)
    -- Targets the last conforming group's folder if available
    if last_conforming_last_row_full then
        SendsDrawSpanningAddRow(groups, bw, gfg, sends_base_sx)
    end

    -- Distant sends section (remote contexts — spanning rows, collapsible cards)
    SendsDrawDistantSection(bw, gfg, sends_base_sx, title_h, btn_h, row_gap,
        knob_d, knob_unit, est_arrow_w, est_fx_btn_w, est_addfx_w, est_route_w,
        col_pad_top, col_pad_bot, title_gap, fx_h, fx_gap_v)
end

-- Render the sends column content (shared by InspDrawInspector and loop-level split).
DrawSendsColumn = function(col_bw)
    SendsViewCheckRefresh()
    if sends_view_active and #sends_view_tracks > 0 then
        local saved_cols = sends_view_cols
        local scmw_btn = S(UI.btn_h)
        local scmw_gap = S(UI.pad_sm)
        local scmw_vol = math.max(scmw_btn, r.ImGui_CalcTextSize(ctx, "-00.0") + S(24))
        local scmw = scmw_btn * 2 + scmw_gap + scmw_gap + scmw_vol + S(UI.card_pad) * 2
        local side_col_gap = S(UI.edge_pad) - 2
        local side_cols = math.max(1, math.floor((col_bw + side_col_gap) / (scmw + side_col_gap)))
        side_cols = math.min(side_cols, sends_view_cols)
        sends_view_cols = side_cols
        SendsDrawSection(col_bw, true)
        sends_view_cols = saved_cols
    else
        local ph_w = col_bw
        local ph_h = S(UI.btn_h) + S(UI.card_pad_top) + S(UI.card_pad_bot)
        local ph_cx, ph_cy = r.ImGui_GetCursorScreenPos(ctx)
        local ph_dl = r.ImGui_GetWindowDrawList(ctx)
        local ph_r = opt_card_boxes and S(UI.card_r) or S(UI.corner_r)
        r.ImGui_DrawList_AddRectFilled(ph_dl, ph_cx, ph_cy, ph_cx + ph_w, ph_cy + ph_h, C.placeholder_bg, ph_r)
        -- Transparent Button (not InvisibleButton) for reliable click in child windows
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
        local ph_clicked = r.ImGui_Button(ctx, "##addsend_ph", ph_w, ph_h)
        r.ImGui_PopStyleColor(ctx, 3)
        local ph_hov = r.ImGui_IsItemHovered(ctx)
        Tip("Create send to new track\nRight-click for options")
        if ph_clicked then
            local target = NavRoutingTargetTrack()
            if target then RoutingAddSendTrack(target) end
        end
        if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##addsend_mode_ph") end
        AddSendModePopup("##addsend_mode_ph", NavRoutingTargetTrack())
        local plus_d = S(UI.btn_h)
        local plus_cx = ph_cx + math.floor(ph_w / 2)
        local plus_cy = ph_cy + math.floor(ph_h / 2)
        local plus_r = plus_d / 2
        if ph_hov then
            r.ImGui_DrawList_AddCircleFilled(ph_dl, plus_cx, plus_cy, plus_r, C.fx_ctrl_hover, 0)
        end
        DrawIcon(ph_dl, plus_cx, plus_cy, plus_d, "+", ph_hov and C.text or ((C.text_dim & 0xFFFFFF00) | math.floor((C.text_dim & 0xFF) * 0.35)))
    end
end

end

return ReflexInstallSendGridCore
