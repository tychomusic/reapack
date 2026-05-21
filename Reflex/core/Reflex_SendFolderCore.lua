-- @noindex
-- Reflex send folder core module.
-- Installs SEND.folder card and folder-chain renderers.

ReflexInstallSendFolderCore = function(deps)
    local r = deps.r
    local ctx = deps.ctx
    local C = deps.colors

-- Draw a horizontal spanning folder card for the sends topology view.
-- Layout: Title row, then [M][S] left-aligned with vol/pan knobs right-aligned on same row.
-- When too narrow, knobs drop to a row between title and M/S.
-- cx/cy: screen-space top-left. w: card width. Returns height consumed.
DrawSendFolderCard = function(track, dl, cx, cy, w, id_suffix)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return 0 end

    local pad_x = S(UI.card_pad)
    local pad_top = S(UI.send_pad_top)
    local pad_bot = S(UI.send_folder_pad_bot)
    local gap = S(UI.pad_sm)
    local btn_h = S(UI.btn_h)
    local knob_d = Round(btn_h * 1.5)
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    local knob_unit_h = knob_d + S(2) + text_h
    local inner_w = w - pad_x * 2
    if inner_w < S(20) then return 0 end

    -- Layout decision: can knobs fit on the M/S row?
    local ms_w = btn_h + gap + btn_h
    local knobs_w = knob_d + gap + knob_d
    local knobs_on_ms_row = (ms_w + gap * 2 + knobs_w) <= inner_w

    -- Compute card height
    local title_row_h = btn_h  -- title row height (text centered in btn_h)
    local knob_row_h = knob_unit_h  -- standalone knob row
    local ms_row_h
    if knobs_on_ms_row then
        ms_row_h = knob_unit_h  -- row height = taller of knobs vs buttons
    else
        ms_row_h = btn_h
    end
    local card_h = pad_top + title_row_h + gap
    if not knobs_on_ms_row then
        card_h = card_h + knob_row_h + gap
    end
    card_h = card_h + ms_row_h
    -- v20.441: arrow row removed (inspect arrow no longer drawn).
    card_h = card_h + pad_bot

    -- Card background (white stroke in flow mode, plain fill otherwise)
    local col_r = opt_card_boxes and S(UI.card_r) or S(UI.corner_r)
    local rx1, ry1, rx2, ry2 = math.floor(cx), math.floor(cy), math.floor(cx + w), math.floor(cy + card_h)
    r.ImGui_DrawList_AddRectFilled(dl, rx1, ry1, rx2, ry2, C.bg, col_r)

    local x = cx + pad_x
    local y = cy + pad_top

    -- Track info
    local _, track_name = r.GetTrackName(track)
    local track_num = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
    local num_str = (track_num == 0) and "M" or tostring(track_num)
    local num_label = num_str .. ":"
    local track_color_raw = r.GetTrackColor(track)
    local num_col = track_color_raw ~= 0 and TrackColorToImGui(track_color_raw) or C.text_muted
    local is_muted = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
    local is_solo = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0

    -- Row 1: Title (full width, left-aligned)
    local title_cy = y + Round((btn_h - text_h) / 2)
    local title_font = GetSteppedFont(UI.font_send_title)
    if title_font then r.ImGui_PushFont(ctx, title_font) end
    local title_h = r.ImGui_GetTextLineHeight(ctx)
    local num_tw = r.ImGui_CalcTextSize(ctx, num_label)
    local num_gap = S(4)
    local name_tw_raw = r.ImGui_CalcTextSize(ctx, track_name)
    r.ImGui_DrawList_PushClipRect(dl, x, title_cy, x + inner_w, title_cy + title_h + 2, true)
    r.ImGui_DrawList_AddText(dl, x, title_cy, num_col, num_label)
    r.ImGui_DrawList_AddText(dl, x + num_tw + num_gap, title_cy, C.text, track_name)
    r.ImGui_DrawList_PopClipRect(dl)
    if title_font then r.ImGui_PopFont(ctx) end

    -- v20.441: TitleLink over the actual text bounds. Manual hit-test
    -- claims the title-text region for locate; the broader ##fctitle
    -- button below covers the rest of the row for caller-side expand.
    local fc_title_link_w = math.min(num_tw + num_gap + name_tw_raw, inner_w)
    local fc_title_link_hov, fc_title_link_clk = TitleLink(
        "##fctitlelink" .. (id_suffix or ""), x, title_cy, fc_title_link_w, title_h, track, {})
    local dl_outer = r.ImGui_GetWindowDrawList(ctx)
    if fc_title_link_hov then
        r.ImGui_DrawList_AddLine(dl_outer, x, title_cy + title_h, x + fc_title_link_w, title_cy + title_h, C.text, 1)
    end

    local title_btn_w = math.max(1, inner_w)
    r.ImGui_SetCursorScreenPos(ctx, x, title_cy)
    r.ImGui_InvisibleButton(ctx, "##fctitle" .. (id_suffix or ""), title_btn_w, title_h)
    -- v20.441: title-link locate is ADDITIVE — fc_title_clicked still fires
    -- on title-link click so the caller's expand-on-title-click behavior is
    -- preserved. Locate + expand both happen on the same click.
    -- v20.442: but peek (Opt+click) is light-touch — suppress fall-through.
    local fc_title_clicked = r.ImGui_IsItemClicked(ctx, 0) and not nav_title_peek_consumed
    y = y + title_row_h + gap

    -- Row 2 (narrow only): Vol + Pan knobs centered
    if not knobs_on_ms_row then
        local knobs_total = knobs_w
        local knobs_start = x + Round((inner_w - knobs_total) / 2)
        local vkx = knobs_start
        local pkx = knobs_start + knob_d + gap

        NavParamKnob(dl, "##fcvol" .. (id_suffix or ""), vkx, y, knob_d, "vol",
                     track, nil, fcvol_state, "Reflex: Folder volume", "Volume")

        NavParamKnob(dl, "##fcpan" .. (id_suffix or ""), pkx, y, knob_d, "pan",
                     track, nil, fcpan_state, "Reflex: Folder pan", "Pan")

        y = y + knob_row_h + gap
    end

    -- Final row: [M][S] left-aligned, knobs right-aligned (wide) or M/S only (narrow)
    -- When knobs on same row: M/S top-aligned with knob tops (not centered)
    local btn_cy = y

    -- M button
    r.ImGui_SetCursorScreenPos(ctx, x, btn_cy)
    local _, cm_clk = NavRect("M##fcm" .. (id_suffix or ""), btn_h, btn_h, "M", MuteOpts(is_muted))
    Tip("Mute")
    if cm_clk then
        r.Undo_BeginBlock()
        r.SetMediaTrackInfo_Value(track, "B_MUTE", is_muted and 0 or 1)
        r.Undo_EndBlock("Reflex: Mute", -1)
    end

    -- S button
    r.ImGui_SetCursorScreenPos(ctx, x + btn_h + gap, btn_cy)
    local _, cs_clk = NavRect("S##fcs" .. (id_suffix or ""), btn_h, btn_h, "S", SoloOpts(is_solo))
    Tip("Solo")
    if cs_clk then
        r.Undo_BeginBlock()
        r.SetMediaTrackInfo_Value(track, "I_SOLO", is_solo and 0 or 2)
        r.Undo_EndBlock("Reflex: Solo", -1)
    end

    -- v20.441: inspect arrow removed (locate via title click instead).
    -- Card hover is no longer needed for the arrow's visibility.

    -- Vol/Pan knobs right-aligned on M/S row (wide only)
    if knobs_on_ms_row then
        local pan_kx = x + inner_w - knob_d
        local vol_kx = pan_kx - gap - knob_d

        NavParamKnob(dl, "##fcvol" .. (id_suffix or ""), vol_kx, y, knob_d, "vol",
                     track, nil, fcvol_state, "Reflex: Folder volume", "Volume")

        NavParamKnob(dl, "##fcpan" .. (id_suffix or ""), pan_kx, y, knob_d, "pan",
                     track, nil, fcpan_state, "Reflex: Folder pan", "Pan")
    end

    return card_h, fc_title_clicked
end

SendsDrawFolderChain = function(group, gi, bw, dl, sends_base_sx, title_h, title_gap,
                                btn_h, row_gap, knob_d, knob_unit, est_arrow_w,
                                est_fx_btn_w, est_addfx_w, est_route_w, col_pad_top,
                                col_pad_bot, fx_h, fx_gap_v, ms_row_h)
    if not group or group.is_ungrouped or not group.folder_chain then return end

    for fi, folder in ipairs(group.folder_chain) do
        if r.ValidatePtr(folder, "MediaTrack*") then
            r.ImGui_SetCursorPosX(ctx, sends_base_sx)
            local fc_cy_before = r.ImGui_GetCursorPosY(ctx)
            local fc_sx, fc_sy = r.ImGui_GetCursorScreenPos(ctx)
            r.ImGui_PushID(ctx, gi * 100 + fi + 5000)

            if sends_folder_expanded[folder] then
                -- Expanded: full track column view.
                local fc_fx_count = 0
                local fc_fx_cache = SendsEnsureFxNameCache(folder)
                local fc_fx_not_collapsed = not (insp_fx_collapsed[folder] == true)
                if fc_fx_not_collapsed then
                    fc_fx_count = fc_fx_cache and fc_fx_cache.count or 0
                end
                -- v20.420: trailing add-FX row removed from sends columns
                -- (entry now in compound + button). Slots count = real FX only.
                local fc_fx_slots = fc_fx_not_collapsed and fc_fx_count or 0
                local fc_fx_area_h = fc_fx_slots > 0 and (fc_fx_slots * fx_h + (fc_fx_slots - 1) * fx_gap_v) or 0
                -- Folder column height: no SND, no +3.
                local fc_knobs_wrap_f = bw - S(UI.card_pad) * 2 < (knob_d * 2 + row_gap)
                local fc_knob_pair = fc_knobs_wrap_f and (knob_unit * 2 + row_gap) or knob_unit
                local fc_ctrl_wrap_f = (est_arrow_w + est_fx_btn_w + est_addfx_w + row_gap + est_route_w) > (bw - S(UI.card_pad) * 2)
                local fc_ctrl_h_f = btn_h + (fc_ctrl_wrap_f and (row_gap + btn_h) or 0)
                local fc_h = col_pad_top
                    + title_h + title_gap
                    + fc_ctrl_h_f + row_gap
                    + fc_fx_area_h
                    + S(UI.section_gap) + 2
                    + fc_knob_pair
                    + ms_row_h
                    + col_pad_bot
                local fc_exp_title_clk = DrawCompactTrackColumn(folder, dl, fc_sx, fc_sy, bw, fc_h, fc_fx_count, nil, nil)
                -- Click on blank space OR title to collapse.
                local fc_blank_clk = r.ImGui_IsMouseHoveringRect(ctx, fc_sx, fc_sy, fc_sx + bw, fc_sy + fc_h)
                   and not r.ImGui_IsAnyItemHovered(ctx)
                   and r.ImGui_IsMouseClicked(ctx, 0)
                if fc_blank_clk or fc_exp_title_clk then
                    sends_folder_expanded[folder] = nil
                end
                r.ImGui_SetCursorPosY(ctx, fc_cy_before + fc_h)
            else
                -- Collapsed: normal folder card.
                local fc_h, fc_title_clk = DrawSendFolderCard(folder, dl, fc_sx, fc_sy, bw, tostring(gi) .. "_" .. tostring(fi))
                -- Click on blank space OR title to expand.
                local fc_blank_clk = r.ImGui_IsMouseHoveringRect(ctx, fc_sx, fc_sy, fc_sx + bw, fc_sy + fc_h)
                   and not r.ImGui_IsAnyItemHovered(ctx)
                   and r.ImGui_IsMouseClicked(ctx, 0)
                if fc_blank_clk or fc_title_clk then
                    sends_folder_expanded[folder] = true
                    sends_expand_scroll_cy = fc_cy_before
                end
                r.ImGui_SetCursorPosY(ctx, fc_cy_before + fc_h)
            end

            r.ImGui_PopID(ctx)
            r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + S(UI.card_gap) - 2)
            r.ImGui_SetCursorPosX(ctx, sends_base_sx)
        end
    end
end

end

return ReflexInstallSendFolderCore
