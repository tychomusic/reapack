-- @noindex
-- Reflex I/O Manager window module.
-- Installs the floating I/O Manager panel UI. Shared device/persistence helpers
-- live in Reflex_IOCore.lua so HDR.input and standalone manager surfaces agree.

ReflexInstallIOManagerCore = function(deps)
    local r = deps.r
    local ctx = deps.ctx
    local C = deps.colors
    local nav_screen_rect = deps.nav_screen_rect

RecordIOFilterRows = function(rows)
    local q = (io_manager_filter or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if q == "" then return rows end
    local out = {}
    for _, row in ipairs(rows or {}) do
        local hit = true
        for word in q:gmatch("%S+") do
            if not (row.search or ""):find(word, 1, true) then
                hit = false
                break
            end
        end
        if hit then out[#out + 1] = row end
    end
    return out
end

RecordIOMidiFilterRows = function(rows)
    if not io_manager_midi_hide_unavailable then return rows end
    local out = {}
    for _, row in ipairs(rows or {}) do
        -- Checked state means only usable MIDI endpoints remain visible.
        if row.status == "Present" or row.status == "Built-in" then out[#out + 1] = row end
    end
    return out
end

RecordIODrawHeaderText = function(dl, x, y, row_h, text, col)
    local th = r.ImGui_GetTextLineHeight(ctx)
    r.ImGui_DrawList_AddText(dl, x, y + Round((row_h - th) / 2), col or C.text_dim, text)
end

RecordIOTableFlags = function()
    local flags = r.ImGui_TableFlags_Resizable()
        | r.ImGui_TableFlags_Sortable()
        | r.ImGui_TableFlags_ScrollY()
        | r.ImGui_TableFlags_NoSavedSettings()
        | r.ImGui_TableFlags_SizingStretchProp()
    if r.ImGui_TableFlags_BordersInnerV then flags = flags | r.ImGui_TableFlags_BordersInnerV() end
    return flags
end

RecordIOFixedColumnFlags = function(default_sort)
    local flags = r.ImGui_TableColumnFlags_WidthFixed()
    if default_sort then flags = flags | r.ImGui_TableColumnFlags_DefaultSort() end
    return flags
end

RecordIOStretchColumnFlags = function(default_sort)
    local flags = r.ImGui_TableColumnFlags_WidthStretch()
    if default_sort then flags = flags | r.ImGui_TableColumnFlags_DefaultSort() end
    return flags
end

RecordIOBoolSort = function(value)
    return value and 1 or 0
end

RecordIOStatusSort = function(status)
    if status == "Present" or status == "Built-in" then return 0 end
    if status == "Enabled" then return 0 end
    if status == "Live" or status == "Native" then return 0 end
    if status == "Written" then return 1 end
    if status == "Pending" then return 2 end
    if status == "Disabled" then return 1 end
    if status == "Ignored" then return 2 end
    if status == "Missing" then return 3 end
    return 4
end

RecordIOPrepareSortRows = function(rows, page, kind)
    for i, row in ipairs(rows or {}) do
        row._sort_index = i
        if kind == "audio" then
            row._sort_fav_mono = RecordIOBoolSort(RecordIOFavoriteHas(page, "mono:" .. tostring(row.channel)))
            if row.stereo_valid then
                row._sort_fav_stereo = RecordIOBoolSort(RecordIOFavoriteHas(page,
                    "stereo:" .. tostring(row.channel)))
            else
                row._sort_fav_stereo = -1
            end
            row._sort_num = row.channel or 0
            row._sort_alias = ((row.alias ~= "" and row.alias) or row.exposed or ""):lower()
            row._sort_status = RecordIOStatusSort(row.status)
            row._sort_hw = row.channel or 0
            row._sort_hw_name = (row.hw or ""):lower()
        else
            if row.device ~= nil then
                row._sort_fav_midi = RecordIOBoolSort(RecordIOFavoriteHas(page,
                    "midi:" .. tostring(row.device) .. ":0"))
            else
                row._sort_fav_midi = -1
            end
            row._sort_name = (row.name or ""):lower()
            row._sort_status = RecordIOStatusSort(row.status)
            row._sort_id = row.device ~= nil and row.device or 100000
        end
    end
end

RecordIOSortValue = function(row, col_id)
    if col_id == 101 then return row._sort_fav_mono end
    if col_id == 102 then return row._sort_fav_stereo end
    if col_id == 103 then return row._sort_num end
    if col_id == 104 then return row._sort_alias end
    if col_id == 105 then return row._sort_status end
    if col_id == 106 then return row._sort_hw end
    if col_id == 107 then return row._sort_hw_name end
    if col_id == 201 then return row._sort_fav_midi end
    if col_id == 202 then return row._sort_name end
    if col_id == 203 then return row._sort_status end
    if col_id == 207 then return row._sort_id end
    return row._sort_index or 0
end

RecordIOCompareSortValues = function(a, b)
    if type(a) == "number" and type(b) == "number" then
        if a < b then return -1 end
        if a > b then return 1 end
        return 0
    end
    local as = tostring(a or ""):lower()
    local bs = tostring(b or ""):lower()
    local ai = 1
    local bi = 1
    while ai <= #as and bi <= #bs do
        local ans, ane = as:find("%d+", ai)
        local bns, bne = bs:find("%d+", bi)
        if ans == ai and bns == bi then
            local an = as:sub(ans, ane)
            local bn = bs:sub(bns, bne)
            local av = tonumber(an) or 0
            local bv = tonumber(bn) or 0
            if av < bv then return -1 end
            if av > bv then return 1 end
            ai = ai + #an
            bi = bi + #bn
        else
            local ac = as:sub(ai, ai)
            local bc = bs:sub(bi, bi)
            if ac < bc then return -1 end
            if ac > bc then return 1 end
            ai = ai + 1
            bi = bi + 1
        end
    end
    if ai <= #as then return 1 end
    if bi <= #bs then return -1 end
    return 0
end

RecordIOSortAscending = function(sort_direction)
    local asc = r.ImGui_SortDirection_Ascending
    if type(asc) == "function" then return sort_direction == asc() end
    if type(asc) == "number" then return sort_direction == asc end
    return true
end

RecordIOCollectSortSpecs = function()
    local specs = {}
    if not r.ImGui_TableGetColumnSortSpecs then return specs end
    local next_id = 0
    while true do
        local ok, a, b, c, d =
            r.ImGui_TableGetColumnSortSpecs(ctx, next_id)
        if not ok then break end
        local col_user_id = d ~= nil and a or b
        local sort_direction = d ~= nil and d or c
        specs[#specs + 1] = {
            col_user_id = col_user_id,
            ascending = RecordIOSortAscending(sort_direction),
        }
        next_id = next_id + 1
    end
    return specs
end

RecordIOApplyTableSort = function(rows, page, kind)
    RecordIOPrepareSortRows(rows, page, kind)
    if r.ImGui_TableNeedSort then r.ImGui_TableNeedSort(ctx) end
    local specs = RecordIOCollectSortSpecs()
    if #specs == 0 then return end
    table.sort(rows, function(a, b)
        for _, spec in ipairs(specs) do
            local cmp = RecordIOCompareSortValues(
                RecordIOSortValue(a, spec.col_user_id),
                RecordIOSortValue(b, spec.col_user_id))
            if cmp ~= 0 then
                if spec.ascending then return cmp < 0 end
                return cmp > 0
            end
        end
        return (a._sort_index or 0) < (b._sort_index or 0)
    end)
end

RecordIOConsumeScrollKey = function(rows, row_h)
    if not io_manager_scroll_key then return end
    for i, row in ipairs(rows or {}) do
        if row.key == io_manager_scroll_key then
            r.ImGui_SetScrollY(ctx, math.max(0, (i - 2) * row_h))
            io_manager_scroll_key = nil
            return
        end
    end
end

RecordIOCellWidth = function(min_w)
    local w = select(1, r.ImGui_GetContentRegionAvail(ctx))
    if w and w > 1 then return w end
    return min_w or S(16)
end

RecordIODrawTableText = function(text, row_h, col, pad_x)
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local w = RecordIOCellWidth(S(16))
    local pad = pad_x or S(6)
    local fp = PushFont(GetSteppedFont(UI.font_fx))
    local th = r.ImGui_GetTextLineHeight(ctx)
    local clipped = RecordInputClipLabel(tostring(text or ""), math.max(1, w - pad * 2))
    r.ImGui_Dummy(ctx, w, row_h)
    r.ImGui_DrawList_AddText(r.ImGui_GetWindowDrawList(ctx), x + pad,
        y + Round((row_h - th) / 2), col or C.text_dim, clipped)
    PopFont(fp)
end

RecordIODrawTableRowBg = function(row_n)
    if (row_n % 2) ~= 1 or not r.ImGui_TableSetBgColor or not r.ImGui_TableBgTarget_RowBg0 then return end
    r.ImGui_TableSetBgColor(ctx, r.ImGui_TableBgTarget_RowBg0(), 0xFFFFFF08)
end

RecordIODrawFavorite = function(page, key, id, w, h)
    local on = RecordIOFavoriteHas(page, key)
    local txt = on and "\xE2\x98\x85" or "\xE2\x98\x86"
    r.ImGui_InvisibleButton(ctx, id, w, h)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local x, y = r.ImGui_GetItemRectMin(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local col = (on or hovered) and C.amber or C.text_muted
    local tw, th = r.ImGui_CalcTextSize(ctx, txt)
    r.ImGui_DrawList_AddText(dl, x + Round((w - tw) / 2), y + Round((h - th) / 2), col, txt)
    if clicked then RecordIOFavoriteToggle(page, key) end
    Tip(on and "Remove favorite" or "Add favorite")
end

RecordIODrawToggle = function(id, value, enabled, commit, tip)
    local label = value and "\xE2\x9C\x93" or ""
    local col = value and C.cmp_b or C.text_muted
    r.ImGui_BeginDisabled(ctx, enabled == false)
    local _, clicked = NavSquare(id, S(28), S(UI.btn_h), label, {
        bg = C.fx_ctrl_bg,
        hov = C.fx_ctrl_hover,
        active = C.fx_ctrl_active,
        fg = col,
        fg_hov = value and C.cmp_b or C.text,
        fg_active = C.cmp_b,
    })
    r.ImGui_EndDisabled(ctx)
    if clicked and enabled ~= false and commit then commit(not value) end
    if tip then Tip(tip) end
end

RecordIODrawAliasCell = function(cell_key, w, row_h, value, fallback, commit)
    local editing = io_manager_edit and io_manager_edit.key == cell_key
    local seed_value = (value and value ~= "") and value or (fallback or "")
    local seed_from_fallback = not (value and value ~= "")
    if io_manager_focus_key == cell_key and not editing then
        RecordIOStartEdit(cell_key, seed_value, commit, { seeded = seed_from_fallback })
        io_manager_focus_key = nil
        editing = true
    end

    if editing then
        local edit = io_manager_edit
        edit.frames = (edit.frames or 0) + 1
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.fx_ctrl_bg)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), S(UI.corner_r))
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), S(6), Round((row_h - r.ImGui_GetTextLineHeight(ctx)) / 2))
        r.ImGui_SetNextItemWidth(ctx, w)
        if not edit.focus then
            r.ImGui_SetKeyboardFocusHere(ctx)
            edit.focus = true
        end
        local flags = r.ImGui_InputTextFlags_EnterReturnsTrue() | r.ImGui_InputTextFlags_AutoSelectAll()
        local entered
        entered, edit.buf = r.ImGui_InputText(ctx, "##" .. cell_key, edit.buf or "", flags)
        local esc = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape())
        local deactivated = r.ImGui_IsItemDeactivated(ctx)
        local edited_deactivated = r.ImGui_IsItemDeactivatedAfterEdit
            and r.ImGui_IsItemDeactivatedAfterEdit(ctx)
        r.ImGui_PopStyleVar(ctx, 2)
        r.ImGui_PopStyleColor(ctx, 2)
        if esc then
            io_manager_esc_consumed = true
            RecordIOCancelEdit()
        elseif entered or edited_deactivated then
            RecordIOCommitEdit()
        elseif deactivated and edit.frames > 2 and (edit.buf or "") ~= (edit.orig or "") then
            RecordIOCommitEdit()
        elseif deactivated and edit.frames > 2 then
            RecordIOCancelEdit()
        end
        return
    end

    r.ImGui_InvisibleButton(ctx, "##" .. cell_key, w, row_h)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2 = x1 + w
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local pad = S(7)
    local display = fallback or ""
    local col = C.text_dim
    if value and value ~= "" then
        display = value
        col = C.text
    end
    if hovered then col = C.text end
    local fp = PushFont(GetSteppedFont(UI.font_fx))
    local th = r.ImGui_GetTextLineHeight(ctx)
    local clipped = RecordInputClipLabel(display, math.max(1, x2 - x1 - pad * 2))
    r.ImGui_DrawList_AddText(dl, x1 + pad, y1 + Round((row_h - th) / 2), col, clipped)
    PopFont(fp)
    if clicked then RecordIOStartEdit(cell_key, seed_value, commit, { seeded = seed_from_fallback }) end
    Tip("Edit alias")
end

RecordIODrawLabelCell = function(id, w, row_h, label, col)
    local x1, y1 = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_Dummy(ctx, w, row_h)
    local pad = S(7)
    local fp = PushFont(GetSteppedFont(UI.font_fx))
    local th = r.ImGui_GetTextLineHeight(ctx)
    local clipped = RecordInputClipLabel(label or "", math.max(1, w - pad * 2))
    r.ImGui_DrawList_AddText(r.ImGui_GetWindowDrawList(ctx), x1 + pad,
        y1 + Round((row_h - th) / 2), col or C.text_dim, clipped)
    PopFont(fp)
end

RecordIODrawMidiOptionsPopup = function(page)
    local popup_id = "##io_midi_options_" .. tostring(page or "")
    PushPopupStyle()
    if r.ImGui_BeginPopup(ctx, popup_id) then
        if r.ImGui_MenuItem(ctx, "Hide unavailable, ignored, and disabled devices", "",
            io_manager_midi_hide_unavailable)
        then
            io_manager_midi_hide_unavailable = not io_manager_midi_hide_unavailable
            SavePref("io_manager_midi_hide_unavailable", io_manager_midi_hide_unavailable)
        end
        r.ImGui_EndPopup(ctx)
    end
    PopPopupStyle()
end

RecordIODrawAudioRows = function(page, rows, row_w, row_h)
    local direction = RecordIOPageDirection(page)
    local _, avail_h = r.ImGui_GetContentRegionAvail(ctx)
    local table_h = math.max(S(120), (avail_h or S(200)) - S(UI.btn_h + 24))
    local table_id = "##io_audio_table_" .. page
    if r.ImGui_BeginTable(ctx, table_id, 7, RecordIOTableFlags(), row_w, table_h, 0.0) then
        r.ImGui_TableSetupColumn(ctx, "\xE2\x98\x85", RecordIOFixedColumnFlags(false), S(30), 101)
        r.ImGui_TableSetupColumn(ctx, "ST", RecordIOFixedColumnFlags(false), S(34), 102)
        r.ImGui_TableSetupColumn(ctx, "#", RecordIOFixedColumnFlags(true), S(42), 103)
        r.ImGui_TableSetupColumn(ctx, "Aliased Name", RecordIOStretchColumnFlags(false), 0.42, 104)
        r.ImGui_TableSetupColumn(ctx, "State", RecordIOFixedColumnFlags(false), S(74), 105)
        r.ImGui_TableSetupColumn(ctx, "HW#", RecordIOFixedColumnFlags(false), S(48), 106)
        r.ImGui_TableSetupColumn(ctx, "HW Name", RecordIOStretchColumnFlags(false), 0.58, 107)
        r.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
        r.ImGui_TableHeadersRow(ctx)
        RecordIOApplyTableSort(rows, page, "audio")
        RecordIOConsumeScrollKey(rows, row_h)

        local clipper = r.ImGui_CreateListClipper(ctx)
        r.ImGui_ListClipper_Begin(clipper, #rows)
        while r.ImGui_ListClipper_Step(clipper) do
            local display_start, display_end = r.ImGui_ListClipper_GetDisplayRange(clipper)
            for row_n = display_start, display_end - 1 do
                local row = rows[row_n + 1]
                r.ImGui_PushID(ctx, row.key)
                r.ImGui_TableNextRow(ctx, 0, row_h)
                RecordIODrawTableRowBg(row_n)
                r.ImGui_TableNextColumn(ctx)
                RecordIODrawFavorite(page, "mono:" .. tostring(row.channel), "##fav_mono",
                    RecordIOCellWidth(S(30)), row_h)
                r.ImGui_TableNextColumn(ctx)
                if row.stereo_valid then
                    RecordIODrawFavorite(page, "stereo:" .. tostring(row.channel), "##fav_stereo",
                        RecordIOCellWidth(S(30)), row_h)
                else
                    r.ImGui_Dummy(ctx, RecordIOCellWidth(S(30)), row_h)
                end
                r.ImGui_TableNextColumn(ctx)
                RecordIODrawTableText(tostring(row.channel + 1), row_h, C.text_dim)
                r.ImGui_TableNextColumn(ctx)
                RecordIODrawAliasCell(row.key .. ":alias", RecordIOCellWidth(S(120)), row_h,
                    row.alias, row.exposed, function(alias)
                        RecordIOSetAudioAlias(direction, row.channel, alias)
                    end)
                r.ImGui_TableNextColumn(ctx)
                RecordIODrawTableText(row.status, row_h, row.status_col)
                if r.ImGui_IsItemHovered(ctx) then Tip(row.status_tip) end
                r.ImGui_TableNextColumn(ctx)
                RecordIODrawTableText(tostring(row.channel + 1), row_h, C.text_dim)
                r.ImGui_TableNextColumn(ctx)
                RecordIODrawTableText(row.hw, row_h, C.text_dim)
                r.ImGui_PopID(ctx)
            end
        end
        r.ImGui_EndTable(ctx)
    end
end

RecordIODrawMidiRows = function(page, rows, row_w, row_h)
    local direction = RecordIOPageDirection(page)
    local _, avail_h = r.ImGui_GetContentRegionAvail(ctx)
    local table_h = math.max(S(120), (avail_h or S(200)) - S(UI.btn_h + 24))
    local table_id = "##io_midi_table_" .. page
    if r.ImGui_BeginTable(ctx, table_id, 4, RecordIOTableFlags(), row_w, table_h, 0.0) then
        r.ImGui_TableSetupColumn(ctx, "\xE2\x98\x85", RecordIOFixedColumnFlags(false), S(30), 201)
        r.ImGui_TableSetupColumn(ctx, "Device / Alias", RecordIOStretchColumnFlags(false), 1.0, 202)
        r.ImGui_TableSetupColumn(ctx, "Status", RecordIOFixedColumnFlags(false), S(84), 203)
        r.ImGui_TableSetupColumn(ctx, "ID", RecordIOFixedColumnFlags(true), S(46), 207)
        r.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
        r.ImGui_TableHeadersRow(ctx)
        RecordIOApplyTableSort(rows, page, "midi")
        RecordIOConsumeScrollKey(rows, row_h)

        local open_options = r.ImGui_IsWindowHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1)
        local clipper = r.ImGui_CreateListClipper(ctx)
        r.ImGui_ListClipper_Begin(clipper, #rows)
        while r.ImGui_ListClipper_Step(clipper) do
            local display_start, display_end = r.ImGui_ListClipper_GetDisplayRange(clipper)
            for row_n = display_start, display_end - 1 do
                local row = rows[row_n + 1]
                r.ImGui_PushID(ctx, row.key)
                r.ImGui_TableNextRow(ctx, 0, row_h)
                RecordIODrawTableRowBg(row_n)
                r.ImGui_TableNextColumn(ctx)
                if row.device ~= nil then
                    RecordIODrawFavorite(page, "midi:" .. tostring(row.device) .. ":0", "##fav_midi",
                        RecordIOCellWidth(S(30)), row_h)
                else
                    r.ImGui_Dummy(ctx, RecordIOCellWidth(S(30)), row_h)
                end
                r.ImGui_TableNextColumn(ctx)
                if row.device ~= nil then
                    RecordIODrawAliasCell(row.key .. ":alias", RecordIOCellWidth(S(150)), row_h,
                        row.alias, row.name, function(alias)
                            RecordIOSetMidiAlias(direction, row.device, alias)
                        end)
                else
                    RecordIODrawLabelCell(row.key .. ":label", RecordIOCellWidth(S(150)), row_h,
                        row.name, C.text_dim)
                end
                r.ImGui_TableNextColumn(ctx)
                local status_col = C.text_dim
                if row.status == "Present" or row.status == "Built-in" then status_col = C.green
                elseif row.status == "Ignored" then status_col = C.amber
                elseif row.status == "Missing" or row.status == "Disabled" then status_col = C.text_muted end
                RecordIODrawTableText(row.status, row_h, status_col)
                r.ImGui_TableNextColumn(ctx)
                RecordIODrawTableText(row.device_label or tostring(row.device), row_h, C.text_dim)
                r.ImGui_PopID(ctx)
            end
        end
        r.ImGui_EndTable(ctx)
        if open_options then r.ImGui_OpenPopup(ctx, "##io_midi_options_" .. page) end
        RecordIODrawMidiOptionsPopup(page)
    end
end

RecordIODrawPageButton = function(page, label, x, y, w, h)
    r.ImGui_SetCursorScreenPos(ctx, x, y)
    local active = io_manager_page == page
    local _, clicked = NavRect("##io_page_" .. page, w, h, label, {
        bg = active and C.cmp_b or C.fx_ctrl_bg,
        hov = active and C.cmp_b or C.fx_ctrl_hover,
        active = active and C.cmp_b or C.fx_ctrl_active,
        fg = active and C.text or C.text_dim,
        fg_hov = C.text,
        fg_active = C.text,
        rounding = S(UI.corner_r),
    })
    if clicked then
        io_manager_page = page
        io_manager_edit = nil
        io_manager_scroll_key = nil
        io_manager_focus_key = nil
    end
end

RecordIODrawManager = function()
    if not io_manager_open then return end
    io_manager_esc_consumed = false

    local work_x = nav_screen_rect and nav_screen_rect.x or 0
    local work_y = nav_screen_rect and nav_screen_rect.y or 0
    local work_w = nav_screen_rect and nav_screen_rect.w or S(980)
    local work_h = nav_screen_rect and nav_screen_rect.h or S(720)
    if r.ImGui_GetMainViewport and r.ImGui_Viewport_GetWorkPos and r.ImGui_Viewport_GetWorkSize then
        local vp = r.ImGui_GetMainViewport(ctx)
        if vp then
            work_x, work_y = r.ImGui_Viewport_GetWorkPos(vp)
            work_w, work_h = r.ImGui_Viewport_GetWorkSize(vp)
        end
    end

    local max_w = math.max(S(560), work_w - S(40))
    local max_h = math.max(S(420), work_h - S(40))
    local base_w = math.max(S(560), math.min(S(980),
        (nav_screen_rect and nav_screen_rect.w or S(620)) + S(300), max_w))
    local base_h = math.max(S(420), math.min(math.floor(work_h * 0.75), max_h))
    if io_manager_first_open then
        local x = (nav_screen_rect and nav_screen_rect.x or 120) + S(22)
        local y = (nav_screen_rect and nav_screen_rect.y or 120) + S(22)
        x = math.max(work_x + S(12), math.min(x, work_x + work_w - base_w - S(12)))
        y = math.max(work_y + S(12), math.min(y, work_y + work_h - base_h - S(12)))
        r.ImGui_SetNextWindowPos(ctx, x, y, r.ImGui_Cond_Always())
        r.ImGui_SetNextWindowSize(ctx, base_w, base_h, r.ImGui_Cond_Always())
        io_manager_first_open = false
    end
    r.ImGui_SetNextWindowSizeConstraints(ctx, S(520), S(360), max_w, max_h)

    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), S(UI.corner_r))
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), S(1))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), C.bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), C.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarBg(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrab(), C.fx_ctrl_active)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrabHovered(), C.fx_ctrl_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrabActive(), C.cmp_b)

    local flags = r.ImGui_WindowFlags_NoCollapse()
        | r.ImGui_WindowFlags_NoDocking()
        | r.ImGui_WindowFlags_NoTitleBar()
    local visible, open = r.ImGui_Begin(ctx, "I/O Manager###io_manager", true, flags)
    if visible then
        local wx, wy = r.ImGui_GetWindowPos(ctx)
        local ww, wh = r.ImGui_GetWindowSize(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local pad = S(12)
        local header_h = S(42)
        local cr = S(UI.corner_r)
        local close_sz = header_h
        local close_x = wx + ww - close_sz

        r.ImGui_DrawList_AddRectFilled(dl, wx, wy, wx + ww, wy + header_h,
            0x20252CFF, cr, r.ImGui_DrawFlags_RoundCornersTop())
        r.ImGui_DrawList_AddLine(dl, wx, wy + header_h - 1, wx + ww, wy + header_h - 1,
            C.border, S(1))
        local title_font = GetSteppedFont(2)
        if title_font then r.ImGui_PushFont(ctx, title_font) end
        local title = "I/O Manager"
        local title_w, title_h = r.ImGui_CalcTextSize(ctx, title)
        r.ImGui_DrawList_AddText(dl, wx + pad, wy + Round((header_h - title_h) / 2), C.text, title)
        if title_font then r.ImGui_PopFont(ctx) end

        if RecordInputNoticeActive() then
            local notice_x = wx + pad + title_w + S(16)
            local notice_right = close_x - S(12)
            if notice_right > notice_x then
                local fp = PushFont(GetSteppedFont(UI.font_fx))
                local _, notice_h = r.ImGui_CalcTextSize(ctx, record_input_notice_text)
                local notice = RecordInputClipLabel(record_input_notice_text, notice_right - notice_x)
                r.ImGui_DrawList_AddText(dl, notice_x, wy + Round((header_h - notice_h) / 2),
                    C.amber, notice)
                PopFont(fp)
            end
        end

        local mx, my = r.ImGui_GetMousePos(ctx)
        local close_hov = mx >= close_x and mx <= close_x + close_sz and my >= wy and my <= wy + header_h
        if close_hov then
            r.ImGui_DrawList_AddRectFilled(dl, close_x, wy, close_x + close_sz, wy + header_h,
                C.fx_ctrl_hover, cr, r.ImGui_DrawFlags_RoundCornersTopRight())
        end
        local xsz = S(5)
        local xcx = close_x + close_sz / 2
        local xcy = wy + header_h / 2
        local xcol = close_hov and C.text or C.text_dim
        r.ImGui_DrawList_AddLine(dl, xcx - xsz, xcy - xsz, xcx + xsz, xcy + xsz, xcol, S(1.5))
        r.ImGui_DrawList_AddLine(dl, xcx + xsz, xcy - xsz, xcx - xsz, xcy + xsz, xcol, S(1.5))
        if close_hov and r.ImGui_IsMouseClicked(ctx, 0) then io_manager_open = false end

        r.ImGui_SetCursorScreenPos(ctx, wx + pad, wy + header_h + pad)
        local body_w = ww - pad * 2
        local tab_h = S(UI.btn_h)
        local tab_gap = S(6)
        local tab_w = math.floor((body_w - tab_gap * 3) / 4)
        local tab_x, tab_y = r.ImGui_GetCursorScreenPos(ctx)
        RecordIODrawPageButton("audio_in", "Audio In", tab_x, tab_y, tab_w, tab_h)
        RecordIODrawPageButton("audio_out", "Audio Out", tab_x + (tab_w + tab_gap), tab_y, tab_w, tab_h)
        RecordIODrawPageButton("midi_in", "MIDI In", tab_x + (tab_w + tab_gap) * 2, tab_y, tab_w, tab_h)
        RecordIODrawPageButton("midi_out", "MIDI Out", tab_x + (tab_w + tab_gap) * 3, tab_y, tab_w, tab_h)
        r.ImGui_SetCursorScreenPos(ctx, wx + pad, tab_y + tab_h + S(12))

        local rows
        local audio_page = io_manager_page == "audio_in" or io_manager_page == "audio_out"
        if audio_page then
            rows = RecordIOFilterRows(RecordIOAudioRows(io_manager_page))
            RecordIODrawAudioRows(io_manager_page, rows, body_w, S(30))
        else
            rows = RecordIOFilterRows(RecordIOMidiFilterRows(RecordIOMidiRows(io_manager_page)))
            RecordIODrawMidiRows(io_manager_page, rows, body_w, S(30))
        end

        local bottom_h = S(UI.btn_h)
        local bottom_y = wy + wh - pad - bottom_h
        local close_w = S(82)
        local restart_w = audio_page and S(118) or 0
        local restart_gap = audio_page and S(8) or 0
        local filter_w = math.max(S(160), body_w - close_w - restart_w - restart_gap - S(8))
        r.ImGui_SetCursorScreenPos(ctx, wx + pad, bottom_y)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.fx_ctrl_bg)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), S(UI.corner_r))
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), S(8), Round((bottom_h - r.ImGui_GetTextLineHeight(ctx)) / 2))
        r.ImGui_SetNextItemWidth(ctx, filter_w)
        local changed
        changed, io_manager_filter = r.ImGui_InputTextWithHint(ctx, "##io_filter", "Filter", io_manager_filter or "")
        r.ImGui_PopStyleVar(ctx, 2)
        r.ImGui_PopStyleColor(ctx, 2)
        local action_x = wx + pad + filter_w + S(8)
        if audio_page then
            r.ImGui_SetCursorScreenPos(ctx, action_x, bottom_y)
            local _, restart_clicked = NavRect("##io_restart_audio", restart_w, bottom_h, "Restart Audio", {
                bg = C.fx_ctrl_bg,
                hov = C.fx_ctrl_hover,
                active = C.fx_ctrl_active,
                fg = C.text_dim,
                fg_hov = C.text,
                fg_active = C.text,
            })
            Tip("Restart audio device")
            if restart_clicked then RecordIORestartAudio() end
            action_x = action_x + restart_w + restart_gap
        end
        r.ImGui_SetCursorScreenPos(ctx, action_x, bottom_y)
        local _, close_clicked = NavRect("##io_close", close_w, bottom_h, "Close", {
            bg = C.fx_ctrl_bg,
            hov = C.fx_ctrl_hover,
            active = C.fx_ctrl_active,
            fg = C.text_dim,
            fg_hov = C.text,
            fg_active = C.text,
        })
        if close_clicked then io_manager_open = false end

        if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape())
            and not io_manager_edit and not io_manager_esc_consumed
        then
            io_manager_open = false
        end
    end
    r.ImGui_End(ctx)
    if not open then io_manager_open = false end

    r.ImGui_PopStyleColor(ctx, 7)
    r.ImGui_PopStyleVar(ctx, 3)
end


end

return ReflexInstallIOManagerCore
