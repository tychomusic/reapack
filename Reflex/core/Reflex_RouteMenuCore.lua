-- @noindex
-- Reflex route menu core module.
-- Installs ROUTE section add-menu/header helpers and sorted send/receive list builder.

ReflexInstallRouteMenuCore = function(deps)
    local r = deps.r
    local ctx = deps.ctx
    local C = deps.colors
    local getScreenH = deps.get_screen_h

    local route_addmenu_scroll = {}  -- popup_id -> { prev_y, fade, y, max, child_h }
    local route_addmenu = {
        popup = nil,
        filter = "",
        sel = 0,
        focus_search = false,
        scroll_to_sel = false,
        reset_scroll = false,
        input_mode = "mouse",
        last_size_by_popup = {},
    }

-- Multi-word AND substring matcher used by routing Add-menus. Both args lowercased.
RouteFilterMatch = function(haystack_lower, needle_lower)
    if needle_lower == "" then return true end
    for w in needle_lower:gmatch("%S+") do
        if not haystack_lower:find(w, 1, true) then return false end
    end
    return true
end

-- Filterable list with keyboard nav, used inside Add-menu popups.
-- items: array of { label, label_lower, payload }
-- on_commit: function(payload) called when user clicks/Enters an item (popup auto-closes).
RouteAddMenuList = function(items, on_commit)
    -- Esc closes the popup. Handled before InputText renders so even when
    -- InputText has focus, IsKeyPressed sees the Escape press.
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
        r.ImGui_CloseCurrentPopup(ctx)
        return
    end

    -- Mouse motion flips input_mode to "mouse" (suppresses kbd-sel highlight,
    -- enables hover bg). Arrow press flips it back to "kbd" further down.
    local mdx, mdy = r.ImGui_GetMouseDelta(ctx)
    if mdx ~= 0 or mdy ~= 0 then
        route_addmenu.input_mode = "mouse"
    end

    -- Clip overly long labels so popup doesn't get pushed wide by one outlier.
    local MAX_LABEL = 45
    local function clip_label(s)
        if #s > MAX_LABEL then return s:sub(1, MAX_LABEL - 1) .. "…" end
        return s
    end

    -- Width based on longest (clipped) label so popup doesn't jank on first frame.
    local max_w = 0
    for _, it in ipairs(items) do
        local tw = r.ImGui_CalcTextSize(ctx, clip_label(it.label))
        if tw > max_w then max_w = tw end
    end
    local input_w = math.max(max_w + S(20), S(140))

    -- Sharp 2px border + interior matching popup bg, drawn via double-AddRectFilled
    -- BEFORE the InputText so the InputText (with transparent FrameBg) overlays cleanly.
    -- AddRect's anti-aliased stroke produces a gradient look at line edges; double-fill avoids that.
    local cur_x, cur_y = r.ImGui_GetCursorScreenPos(ctx)
    cur_x = math.floor(cur_x); cur_y = math.floor(cur_y)
    local input_h = r.ImGui_GetFrameHeight(ctx)
    local ix2 = cur_x + input_w
    local iy2 = cur_y + input_h
    local sw_input = 2
    local rd_input = S(3)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRectFilled(dl, cur_x, cur_y, ix2, iy2, 0x383C46FF, rd_input)
    r.ImGui_DrawList_AddRectFilled(dl, cur_x + sw_input, cur_y + sw_input, ix2 - sw_input, iy2 - sw_input, C.bg, math.max(0, rd_input - sw_input))

    -- InputText: transparent bg, no built-in border (we drew our own above).
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x00000000)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
    r.ImGui_SetNextItemWidth(ctx, input_w)
    if route_addmenu.focus_search then
        r.ImGui_SetKeyboardFocusHere(ctx)
        route_addmenu.focus_search = false
    end
    local rv, new_filter = r.ImGui_InputTextWithHint(ctx, "##addsearch", "Filter…", route_addmenu.filter, 0)
    r.ImGui_PopStyleVar(ctx, 1)
    r.ImGui_PopStyleColor(ctx, 3)
    if rv then
        route_addmenu.filter = new_filter
        route_addmenu.sel = 0  -- typing clears any kbd selection
    end

    -- Filter (kept against full label; display label is clipped).
    local filter_lower = route_addmenu.filter:lower()
    local filtered = {}
    local filtered_display = {}
    for _, it in ipairs(items) do
        if RouteFilterMatch(it.label_lower, filter_lower) then
            filtered[#filtered + 1] = it
            filtered_display[#filtered_display + 1] = clip_label(it.label)
        end
    end
    local n = #filtered
    if route_addmenu.sel > n then route_addmenu.sel = n end
    if route_addmenu.sel < 0 then route_addmenu.sel = 0 end

    -- Keyboard nav. sel == 0 means "no selection"; first DownArrow engages at row 1.
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_DownArrow()) and n > 0 then
        route_addmenu.sel = (route_addmenu.sel == 0) and 1 or math.min(n, route_addmenu.sel + 1)
        route_addmenu.input_mode = "kbd"
        route_addmenu.scroll_to_sel = true
    elseif r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_UpArrow()) and n > 0 and route_addmenu.sel > 0 then
        route_addmenu.sel = math.max(1, route_addmenu.sel - 1)
        route_addmenu.input_mode = "kbd"
        route_addmenu.scroll_to_sel = true
    end
    local commit = false
    local enter_pressed = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter())
                       or r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_KeypadEnter())
    if enter_pressed and route_addmenu.sel > 0 then
        commit = true
    end

    -- Vertical sizing: use as much script-window height as possible.
    -- ImGui auto-flips popup upward when there's not enough room below.
    local row_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
    local script_h = (getScreenH and getScreenH()) or S(500)
    local max_list_h = math.max(S(120), script_h - S(200))
    local natural_h = math.max(1, n) * row_h + S(4)
    local list_h = math.min(natural_h, max_list_h)

    -- Style the list: kbd mode suppresses mouse-hover bg so kbd-sel is the only
    -- visible highlight. No ImGui scrollbar (NoScrollbar flag below) - we draw
    -- a thin indicator after EndChild matching the rest of the script.
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), C.fx_ctrl_hover)
    local kbd_active = (route_addmenu.input_mode == "kbd")
    if kbd_active then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x00000000)
    else
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), C.fx_ctrl_hover)
    end

    if r.ImGui_BeginChild(ctx, "##addlist", input_w, list_h, 0, r.ImGui_WindowFlags_NoScrollbar()) then
        if route_addmenu.reset_scroll then
            r.ImGui_SetScrollY(ctx, 0)
            route_addmenu.reset_scroll = false
        end
        if n == 0 then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text_muted)
            r.ImGui_Text(ctx, "(no matches)")
            r.ImGui_PopStyleColor(ctx, 1)
        else
            for i, it in ipairs(filtered) do
                local is_sel = kbd_active and (i == route_addmenu.sel) and (route_addmenu.sel > 0)
                if r.ImGui_Selectable(ctx, filtered_display[i], is_sel) then
                    commit = true
                    route_addmenu.sel = i
                end
                if is_sel and route_addmenu.scroll_to_sel then
                    r.ImGui_SetScrollHereY(ctx, 0.5)
                end
            end
        end
        -- Capture scroll metrics before EndChild for the indicator
        local _alsy = r.ImGui_GetScrollY(ctx)
        local _alsm = r.ImGui_GetScrollMaxY(ctx)
        local _alch = select(2, r.ImGui_GetWindowSize(ctx))
        local _popup_id = route_addmenu.popup or "##addlist_default"
        local st = route_addmenu_scroll[_popup_id]
        if not st then
            st = { prev_y = -1, fade = 0, y = 0, max = 0, child_h = 0 }
            route_addmenu_scroll[_popup_id] = st
        end
        if _alsy ~= st.prev_y then st.fade = 1.8 end
        st.prev_y = _alsy; st.y = _alsy; st.max = _alsm; st.child_h = _alch
        r.ImGui_EndChild(ctx)
        -- Draw thin indicator inside the child's right margin.
        do
            local _ix1, _iy1 = r.ImGui_GetItemRectMin(ctx)
            local _ix2, _iy2 = r.ImGui_GetItemRectMax(ctx)
            -- Local fade decay (ImGui DeltaTime gives a frame-precise dt)
            local _dt = r.ImGui_GetDeltaTime(ctx) or 0
            if st.fade > 0 then st.fade = math.max(0, st.fade - _dt * 2.5) end
            local _ind_x = _ix2 - S(3) - S(3)  -- 3px indicator + 3px right inset
            local _popup_dl = r.ImGui_GetWindowDrawList(ctx)
            DrawScrollIndicator(_popup_dl, _iy1, _iy2, st.y, st.max, st.child_h, st.fade, _ind_x)
        end
    end
    r.ImGui_PopStyleColor(ctx, 2)
    route_addmenu.scroll_to_sel = false

    if commit and filtered[route_addmenu.sel] then
        on_commit(filtered[route_addmenu.sel].payload)
        r.ImGui_CloseCurrentPopup(ctx)
    end
end

RouteSectionHeader = function(add_btn_id, popup_id, title, section_col, trk_sx, row_h, dl, popup_contents_fn, full_hit, bw)
    r.ImGui_SetCursorPos(ctx, trk_sx, r.ImGui_GetCursorPosY(ctx))
    local sec_sx, sec_ssy = r.ImGui_GetCursorScreenPos(ctx)
    local title_font = GetScaledFont and GetScaledFont()
    local title_size = r.ImGui_GetFontSize and r.ImGui_GetFontSize(ctx) * 1.17 or nil
    if title_font and title_size then r.ImGui_PushFont(ctx, title_font, title_size) end
    local sec_th = r.ImGui_GetTextLineHeight(ctx)
    local title_w = r.ImGui_CalcTextSize(ctx, title)
    local dot_r = S(5)
    local segment_gap = 11 * 0.5
    local plus_arm = row_h * 0.22
    local plus_w = plus_arm * 2
    local add_w = segment_gap + plus_w + segment_gap + dot_r * 2 + segment_gap
    local header_w = bw or (row_h + S(14 / 1.44) + title_w + add_w)
    local add_x = sec_sx + header_w - add_w
    local dd_clk = false
    local header_hov = false
    local header_active = false
    local active_col = (section_col & 0xFFFFFF00) | 0xCC

    r.ImGui_SetCursorScreenPos(ctx, add_x, sec_ssy)
    r.ImGui_InvisibleButton(ctx, add_btn_id, add_w, row_h)
    header_hov = r.ImGui_IsItemHovered(ctx)
    header_active = r.ImGui_IsItemActive(ctx)
    dd_clk = r.ImGui_IsItemClicked(ctx, 0)
    local add_bg = header_active and active_col or (header_hov and section_col or C.fx_ctrl_bg)
    local add_fg = (header_hov or header_active) and 0xFFFFFFFF or C.text_dim
    local add_dot_col = (header_hov or header_active) and 0xFFFFFFFF or section_col
    r.ImGui_DrawList_AddRectFilled(dl, add_x, sec_ssy, add_x + add_w, sec_ssy + row_h, add_bg, S(3))
    DrawIcon(dl, add_x + segment_gap + plus_w * 0.5, sec_ssy + row_h * 0.5, row_h, "+", add_fg)
    r.ImGui_DrawList_AddCircleFilled(dl, add_x + segment_gap + plus_w + segment_gap + dot_r,
        sec_ssy + row_h * 0.5, dot_r, add_dot_col, 24)

    local title_col = C.text
    r.ImGui_DrawList_AddText(dl, sec_sx,
        sec_ssy + Round((row_h - sec_th) / 2), title_col, title)
    if title_font and title_size then r.ImGui_PopFont(ctx) end
    if dd_clk then r.ImGui_OpenPopup(ctx, popup_id) end
    -- Detect closed→open transition for this popup so the Add-menu state resets.
    local now_open = r.ImGui_IsPopupOpen(ctx, popup_id)
    if now_open and route_addmenu.popup ~= popup_id then
        route_addmenu.popup = popup_id
        route_addmenu.filter = ""
        route_addmenu.sel = 0
        route_addmenu.focus_search = true
        route_addmenu.input_mode = "mouse"
        route_addmenu.scroll_to_sel = false
        route_addmenu.reset_scroll = true
    elseif not now_open and route_addmenu.popup == popup_id then
        route_addmenu.popup = nil
    end
    PushPopupStyle()
    -- Suppress ImGui's anti-aliased gradient border + bg fill; we draw both via double-fill.
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), 0x00000000)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
    if r.ImGui_BeginPopup(ctx, popup_id) then
        -- Sharp bg + 2px stroke around the whole popup, sized from last frame's
        -- captured size (per-popup so sends/recvs/HW each remember their own).
        do
            local wpx, wpy = r.ImGui_GetWindowPos(ctx)
            local cached = route_addmenu.last_size_by_popup[popup_id]
            local pw = (cached and cached.w) or S(220)
            local ph = (cached and cached.h) or S(60)
            wpx = math.floor(wpx); wpy = math.floor(wpy)
            local px2 = math.floor(wpx + pw)
            local py2 = math.floor(wpy + ph)
            local sw_pop = 2
            local rd_pop = S(6)
            local pdl = r.ImGui_GetWindowDrawList(ctx)
            r.ImGui_DrawList_AddRectFilled(pdl, wpx, wpy, px2, py2, 0x383C46FF, rd_pop)
            r.ImGui_DrawList_AddRectFilled(pdl, wpx + sw_pop, wpy + sw_pop, px2 - sw_pop, py2 - sw_pop, C.bg, math.max(0, rd_pop - sw_pop))
        end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), C.fx_ctrl_hover)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
        popup_contents_fn()
        -- Capture popup size for next frame's bg+stroke draw.
        do
            local cww, cwh = r.ImGui_GetWindowSize(ctx)
            route_addmenu.last_size_by_popup[popup_id] = { w = cww, h = cwh }
        end
        r.ImGui_PopStyleColor(ctx, 2)
        r.ImGui_EndPopup(ctx)
    end
    r.ImGui_PopStyleVar(ctx, 1)
    r.ImGui_PopStyleColor(ctx, 1)
    PopPopupStyle()
end

-- Build a sorted list of send/receive entries for the routing panel.
-- category: 0 = sends (wanted = 1, resolves destination), -1 = receives (wanted = 0, resolves source).
-- Returns array of { idx, name, num, nchan } sorted by track number.
-- `nchan` is the resolved (other-side) track's channel count — caller binds it
-- to the appropriate src/dst slot on DrawRouteRow.
RouteBuildSortedTrackList = function(track, category)
    local has_br = r.BR_GetMediaTrackSendInfo_Track ~= nil
    local count = r.GetTrackNumSends(track, category)
    local wanted = (category == 0) and 1 or 0
    local list = {}
    for i = 0, count - 1 do
        local other_name = "?"
        local other_nchan = 2
        local other_num = 99999
        if has_br then
            local other = r.BR_GetMediaTrackSendInfo_Track(track, category, i, wanted)
            if other and r.ValidatePtr(other, "MediaTrack*") then
                local _, tn = r.GetTrackName(other); other_name = tn
                other_nchan = math.floor(r.GetMediaTrackInfo_Value(other, "I_NCHAN"))
                other_num = math.floor(r.GetMediaTrackInfo_Value(other, "IP_TRACKNUMBER"))
            end
        end
        list[#list + 1] = { idx = i, name = other_name, num = other_num, nchan = other_nchan }
    end
    table.sort(list, function(a, b) return a.num < b.num end)
    return list
end

end

return ReflexInstallRouteMenuCore
