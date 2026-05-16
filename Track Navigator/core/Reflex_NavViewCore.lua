-- @noindex
-- Reflex shared Navigator view renderer.
-- Installs NavDrawSection, the single drawing path for NAV.arr, NAV.dot, NAV.pill, and NAV A/S/R.

ReflexInstallNavViewCore = function(deps)
    local r = deps.r
    local ctx = deps.ctx
    local C = deps.colors
    local scaled_fonts = deps.scaled_fonts
    local font_sizes = deps.font_sizes or {}
    local track_color_overrides = deps.track_color_overrides or {}
    local getNavScale = deps.get_nav_scale
    local setNavScale = deps.set_nav_scale
    local script_dir = deps.script_dir or ""
    local nav_version = deps.version or TRACK_NAVIGATOR_VERSION or REFLEX_VERSION or "?"
    local nav_menu_context = deps.menu_context or "reflex"
    local markDirty = deps.mark_dirty or function() end
    local openIoManager = deps.open_io_manager
    local debugEvent = deps.debug_event
    local getDockID = deps.get_dock_id
    local requestDock = deps.request_dock
    local requestQuit = deps.request_quit
    local notePopupActive = deps.note_popup_active or function() end

    local function NavDebugEvent(source, opts)
        if debugEvent then debugEvent(source, opts or {}) end
    end

    local function NavFrameKeyMods()
        if not r.ImGui_GetKeyMods then return 0 end
        local ok, mods = pcall(r.ImGui_GetKeyMods, ctx)
        if ok and type(mods) == "number" then return mods end
        return 0
    end

    local function NavClickMods()
        return NavFrameKeyMods()
    end

    local function NavPushFont(font)
        if not font then return false end
        local size = font_sizes[font]
        if not size then return false end
        r.ImGui_PushFont(ctx, font, size)
        return true
    end

    local function NavPopFont(pushed)
        if pushed then r.ImGui_PopFont(ctx) end
    end

    local AR_LABEL_TEXT_FALLBACK_NUDGE = {
        A = { x = 0.5, y = 0.0 },
        S = { x = 0.0, y = 0.0 },
        R = { x = 1.0, y = 0.0 },
    }
    local AR_LABEL_IMAGE_FILES = {
        A = "Nav.Active.A.png",
        S = "Nav.Select.S.png",
        R = "Nav.Route.R.png",
    }
    local TYCHO_DOTS_FILE = "Tycho-Logo-dots.png"
    local TYCHO_DOTS_SCALE = 0.2175
    local ar_label_images = {}
    local tycho_dots_image = nil
    local nav_reset_confirm = false
    local nav_help_manual_close_requested = false
    local nav_help_manual_hovered = false
    local nav_last_dock_id = nil
    local nav_open_global_menu = false
    local nav_global_menu_open = false
    local nav_global_menu_pos_x = nil
    local nav_global_menu_pos_y = nil
    local nav_global_menu_pos_pending = false
    local nav_tlt_hover_suppress_guid = nil

    local function NavGetArLabelImage(which)
        if ar_label_images[which] ~= nil then
            return ar_label_images[which] or nil
        end
        local filename = AR_LABEL_IMAGE_FILES[which]
        if not filename or script_dir == "" then
            ar_label_images[which] = false
            return nil
        end
        local path = script_dir .. "icons/" .. filename
        local f = io.open(path, "rb")
        if f then
            f:close()
            local ok, img = pcall(r.ImGui_CreateImage, path)
            if ok and img then
                r.ImGui_Attach(ctx, img)
                ar_label_images[which] = img
                return img
            end
        end
        ar_label_images[which] = false
        return nil
    end

    local function NavGetTychoDotsImage()
        if tycho_dots_image ~= nil then
            return tycho_dots_image or nil
        end
        if script_dir == "" then
            tycho_dots_image = false
            return nil
        end
        local path = script_dir .. "icons/" .. TYCHO_DOTS_FILE
        local f = io.open(path, "rb")
        if f then
            f:close()
            local ok, img = pcall(r.ImGui_CreateImage, path)
            if ok and img then
                r.ImGui_Attach(ctx, img)
                tycho_dots_image = img
                return img
            end
        end
        tycho_dots_image = false
        return nil
    end

    local function NavScaledImageSize(img)
        if not img then return nil, nil end
        local iw, ih = r.ImGui_Image_GetSize(img)
        if not iw or not ih or iw < 1 or ih < 1 then return nil, nil end
        local scale = getNavScale and getNavScale() or 1.0
        return (iw * TYCHO_DOTS_SCALE) * scale, (ih * TYCHO_DOTS_SCALE) * scale
    end

    local function NavTychoDotsSize()
        return NavScaledImageSize(NavGetTychoDotsImage())
    end

    local function NavDrawArLabelImage(dl, cx, cy, which, col, box)
        local img = NavGetArLabelImage(which)
        if not img then return false end
        local iw, ih = r.ImGui_Image_GetSize(img)
        if not iw or not ih or iw < 1 or ih < 1 then return false end
        box = box or S(34) -- Match A/S/R circle diameter; source PNGs are 64px @2x.
        local w, h
        if iw >= ih then
            w = box
            h = box * (ih / iw)
        else
            h = box
            w = box * (iw / ih)
        end
        local x = cx - w / 2
        local y = cy - h / 2
        r.ImGui_DrawList_AddImage(dl, img, x, y, x + w, y + h, 0, 0, 1, 1, col)
        return true
    end

    local function NavTlfItemTrack(item)
        if not item then return nil end
        return item.track or (item.entry and item.entry.track) or nil
    end

    local function NavTlfItemGuid(item)
        local track = NavTlfItemTrack(item)
        if track and r.ValidatePtr(track, "MediaTrack*") then
            return r.GetTrackGUID(track)
        end
        return nil
    end

    local function NavTlfVisible(item)
        if not item then return false end
        local sg = item and item.kind == "folder" and item.sub_group or nil
        if sg and #sg.entries > 0 then
            for _, e in ipairs(sg.entries) do
                if r.GetMediaTrackInfo_Value(e.track, "B_SHOWINTCP") ~= 1 then return false end
            end
            return true
        end
        return IsItemVisible(item)
    end

    local function NavTlfHover(item, hovered)
        local guid = NavTlfItemGuid(item)
        if guid and nav_tlt_hover_suppress_guid == guid then
            if hovered then return false end
            nav_tlt_hover_suppress_guid = nil
        end
        return hovered
    end

    local function NavMaybeSuppressTlfHover(item, was_visible, show_all, primary)
        if show_all or not primary or not was_visible or NavTlfVisible(item) then return end
        nav_tlt_hover_suppress_guid = NavTlfItemGuid(item)
    end

    local function NavOpenGlobalMenuAtMouse()
        local mx, my = r.ImGui_GetMousePos(ctx)
        nav_global_menu_open = true
        nav_global_menu_pos_x = mx or nav_global_menu_pos_x or 0
        nav_global_menu_pos_y = my or nav_global_menu_pos_y or 0
        nav_global_menu_pos_pending = true
        nav_help_manual_close_requested = false
    end

    local function NavCloseGlobalMenu()
        nav_global_menu_open = false
        nav_global_menu_pos_pending = false
        nav_help_manual_close_requested = false
        nav_reset_confirm = false
    end

    local function NavViewportWorkRect()
        if r.ImGui_GetMainViewport and r.ImGui_Viewport_GetWorkPos and r.ImGui_Viewport_GetWorkSize then
            local ok_vp, viewport = pcall(r.ImGui_GetMainViewport, ctx)
            if ok_vp and viewport then
                local ok_pos, wx, wy = pcall(r.ImGui_Viewport_GetWorkPos, viewport)
                local ok_size, ww, wh = pcall(r.ImGui_Viewport_GetWorkSize, viewport)
                if ok_pos and ok_size and type(wx) == "number" and type(wy) == "number"
                    and type(ww) == "number" and type(wh) == "number" and ww > 0 and wh > 0 then
                    return wx, wy, wx + ww, wy + wh
                end
            end
        end
        if r.ImGui_GetMainViewport and r.ImGui_Viewport_GetPos and r.ImGui_Viewport_GetSize then
            local ok_vp, viewport = pcall(r.ImGui_GetMainViewport, ctx)
            if ok_vp and viewport then
                local ok_pos, wx, wy = pcall(r.ImGui_Viewport_GetPos, viewport)
                local ok_size, ww, wh = pcall(r.ImGui_Viewport_GetSize, viewport)
                if ok_pos and ok_size and type(wx) == "number" and type(wy) == "number"
                    and type(ww) == "number" and type(wh) == "number" and ww > 0 and wh > 0 then
                    return wx, wy, wx + ww, wy + wh
                end
            end
        end
        return nil
    end

    local function NavClampRectToViewport(x, y, w, h)
        local vx1, vy1, vx2, vy2 = NavViewportWorkRect()
        if not vx1 then return x, y end
        local margin = S(4)
        local max_x = vx2 - margin - math.max(0, w or 0)
        local max_y = vy2 - margin - math.max(0, h or 0)
        local min_x = vx1 + margin
        local min_y = vy1 + margin
        if max_x < min_x then max_x = min_x end
        if max_y < min_y then max_y = min_y end
        return math.max(min_x, math.min(x, max_x)), math.max(min_y, math.min(y, max_y))
    end

    local function NavGlobalMenuPivot(x, y)
        local vx1, vy1, vx2, vy2 = NavViewportWorkRect()
        if not vx1 then return 0, 0 end
        return x > (vx1 + vx2) * 0.5 and 1 or 0,
            y > (vy1 + vy2) * 0.5 and 1 or 0
    end

    local function NavRoundScale(v)
        return math.floor(v * 100 + 0.5) / 100
    end

    local function NavWithAlpha(col, alpha)
        return (col & 0xFFFFFF00) | alpha
    end

    local function NavIsMacOS()
        local os = r.GetOS and r.GetOS() or ""
        return os:find("OSX", 1, true) ~= nil
            or os:find("macOS", 1, true) ~= nil
            or os:find("Mac", 1, true) ~= nil
    end

    local function NavPrimaryLabel()
        return NavIsMacOS() and "Cmd" or "Ctrl"
    end

    local function NavPinLabel()
        return NavIsMacOS() and "Opt" or "Alt"
    end

    local function NavChildExpandLabel()
        return NavIsMacOS() and "Opt+CMD" or "Alt+Ctrl"
    end

    local function NavRawModState(mods)
        if type(TrackNavigatorModState) == "function" then
            local state = TrackNavigatorModState(mods)
            if type(state) == "table" then return state end
        end
        mods = tonumber(mods) or 0
        return {
            raw = mods,
            cmd = IsCmd(mods),
            shift = IsShift(mods),
            alt = IsAlt(mods),
            ctrl = IsCtrl(mods),
        }
    end

    local function NavMods(mods)
        local raw = NavRawModState(mods)
        local is_mac = NavIsMacOS()
        local primary, child_expand
        if is_mac then
            child_expand = raw.cmd == true and raw.alt == true
            primary = raw.cmd == true and child_expand ~= true
        else
            child_expand = raw.ctrl == true and raw.alt == true
            primary = raw.ctrl == true and child_expand ~= true
        end
        return {
            raw = raw.raw or mods or 0,
            shift = raw.shift == true,
            primary = primary == true,
            pin = raw.alt == true and child_expand ~= true,
            child_expand = child_expand == true,
            show_all = primary == true and raw.shift == true,
        }
    end

    local function NavTrackClickMods(mods)
        local m = NavMods(mods)
        local primary = m.primary
        local pin = m.pin
        return m.show_all, primary, m.shift, pin, m.child_expand
    end

    local function NavUtf8CharCount(s)
        s = s or ""
        local len = #s
        local i = 1
        local count = 0
        while i <= len do
            local b = s:byte(i)
            if not b then break end
            if b < 0x80 then
                i = i + 1
            elseif b < 0xE0 then
                i = i + 2
            elseif b < 0xF0 then
                i = i + 3
            else
                i = i + 4
            end
            count = count + 1
        end
        return count
    end

    local function NavUtf8Prefix(s, max_chars)
        s = s or ""
        max_chars = math.max(0, max_chars or 0)
        if max_chars == 0 then return "" end
        local len = #s
        local i = 1
        local count = 0
        local last = 0
        while i <= len and count < max_chars do
            local b = s:byte(i)
            if not b then break end
            local next_i
            if b < 0x80 then
                next_i = i + 1
            elseif b < 0xE0 then
                next_i = i + 2
            elseif b < 0xF0 then
                next_i = i + 3
            else
                next_i = i + 4
            end
            last = math.min(len, next_i - 1)
            i = next_i
            count = count + 1
        end
        return s:sub(1, last)
    end

    local function NavTlfNameTooltipNeeded(display_label, clipped)
        return clipped == true and NavUtf8CharCount(display_label) <= 2
    end

    local function NavClipMenuTrackName(name)
        name = name or ""
        if NavUtf8CharCount(name) <= 16 then return name, false end
        return NavUtf8Prefix(name, 16) .. "...", true
    end

    local function NavTrackMenuLabel(verb, entry)
        local track_num = type(entry.idx) == "number" and tostring(entry.idx + 1) or "?"
        local clipped_name = NavClipMenuTrackName(entry.name)
        return verb .. " T" .. track_num .. ": " .. clipped_name
    end

    local function NavIncludedMenuLabel(entry)
        local label = NavTrackMenuLabel("Hide", entry)
        if entry.blocked then label = label .. " (ignored)" end
        return label
    end

    local function NavHiddenMenuLabel(entry)
        return NavTrackMenuLabel("Show", entry)
    end

    local function NavPromotedMenuLabel(entry)
        return NavTrackMenuLabel("Show parent", entry)
    end

    local function NavBrightenColor(col, amount)
        amount = math.max(0, math.min(1, amount or 0))
        local rr = (col >> 24) & 0xFF
        local gg = (col >> 16) & 0xFF
        local bb = (col >> 8) & 0xFF
        rr = math.floor(rr + (0xFF - rr) * amount + 0.5)
        gg = math.floor(gg + (0xFF - gg) * amount + 0.5)
        bb = math.floor(bb + (0xFF - bb) * amount + 0.5)
        return (rr << 24) | (gg << 16) | (bb << 8) | (col & 0xFF)
    end

    local function NavActiveFlashAmount()
        local flash_t = active_view_flash_time or 0
        if flash_t <= 0 then return 0 end
        local age = r.time_precise() - flash_t
        local dur = 0.32
        if age < 0 or age > dur then return 0 end
        local pulse = math.sin((age / dur) * math.pi * 4)
        if pulse < 0 then pulse = 0 end
        return pulse * 0.45
    end

    local COL_AR_REST_BG = rgb(0x171B21)
    local COL_AR_ACTIVE_RED = rgb(0xDA6449)
    local COL_AR_SELECTED_GREEN = rgb(0x42A66B)
    local COL_AR_ROUTING_BLUE = rgb(0x1185E0)
    local COL_AR_HOVER_BG = COL_AR_REST_BG
    local COL_AR_TEXT_REST = rgb(0x919394)
    local COL_AR_TEXT_ACTIVE = 0xFFFFFFFF
    local AR_DISABLED_ALPHA = 0x66
    local AR_DISABLED_BG = NavWithAlpha(COL_AR_REST_BG, AR_DISABLED_ALPHA)
    local AR_DISABLED_FG = NavWithAlpha(COL_AR_TEXT_REST, AR_DISABLED_ALPHA)
    local COL_NAV_ADD = C.green or 0x3FB950FF
    local COL_NAV_REMOVE = C.danger or C.fx_remove or C.warn or 0xE35B4FFF

    local function NavArTooltip(primary, secondary)
        if not opt_tooltips then return end
        PushTooltipStyle()
        r.ImGui_BeginTooltip(ctx)
        r.ImGui_Text(ctx, primary)
        if secondary then
            r.ImGui_TextColored(ctx, C.text_dim, secondary)
        end
        r.ImGui_EndTooltip(ctx)
        PopTooltipStyle()
    end

    local function NavDrawScaleControls(menu_w)
        if not getNavScale or not setNavScale then return end
        local scale = getNavScale()
        local row_h = S(UI.btn_h or 26)
        local pad_x = 0
        local pad_y = 0
        local btn_sz = row_h
        local label = string.format("%d%%", math.floor(scale * 100 + 0.5))
        local label_w = r.ImGui_CalcTextSize(ctx, label) + S(14)
        local controls_w = btn_sz + S(2) + label_w + S(2) + btn_sz
        local sx, sy = r.ImGui_GetCursorScreenPos(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local cx = sx + math.max(0, menu_w - controls_w)

        r.ImGui_SetCursorScreenPos(ctx, cx + pad_x, sy + pad_y)
        local _, minus_clk = NavSquare("##nav_scale_minus", btn_sz, btn_sz, "-", {
            bg = C.fx_ctrl_bg, hov = C.fx_ctrl_hover, active = C.fx_ctrl_active,
            fg = C.text_dim, fg_hov = C.text,
        })
        if minus_clk then
            setNavScale(math.max(0.5, NavRoundScale(scale - 0.10)))
        end

        r.ImGui_SameLine(ctx, 0, S(2))
        local _, _ = NavRect("##nav_scale_val", label_w, row_h, nil, {
            bg = C.fx_ctrl_bg, hov = C.fx_ctrl_bg, no_press = true,
        })
        local vx, vy = r.ImGui_GetItemRectMin(ctx)
        local vtw, vth = r.ImGui_CalcTextSize(ctx, label)
        vth = vth or r.ImGui_GetTextLineHeight(ctx)
        r.ImGui_DrawList_AddText(dl, vx + Round((label_w - vtw) / 2), vy + Round((row_h - vth) / 2), C.text, label)

        r.ImGui_SameLine(ctx, 0, S(2))
        local _, plus_clk = NavSquare("##nav_scale_plus", btn_sz, btn_sz, "+", {
            bg = C.fx_ctrl_bg, hov = C.fx_ctrl_hover, active = C.fx_ctrl_active,
            fg = C.text_dim, fg_hov = C.text,
        })
        if plus_clk then
            setNavScale(math.min(2.5, NavRoundScale(scale + 0.10)))
        end
        r.ImGui_SetCursorScreenPos(ctx, sx, sy + row_h + pad_y * 2)
    end

    local function NavDrawSizeRow(menu_w, label)
        local row_h = S(UI.btn_h or 26)
        local _, text_h = r.ImGui_CalcTextSize(ctx, label)
        text_h = text_h or r.ImGui_GetTextLineHeight(ctx)
        local x, y = r.ImGui_GetCursorScreenPos(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        r.ImGui_DrawList_AddText(dl, x, y + Round((row_h - text_h) / 2), C.text, label)
        if not getNavScale or not setNavScale then
            r.ImGui_Dummy(ctx, menu_w, row_h)
            return
        end
        NavDrawScaleControls(menu_w)
    end

    local function NavPopupSectionBreak(menu_w)
        ReflexPopupStackGap()
        ReflexPopupRule(menu_w)
        ReflexPopupStackGap()
    end

    local function NavDockSectionGap()
        local line_h = math.max(1, S(1))
        local gap_h = math.max(0, (S(10) * 2 + line_h) - S(5))
        ReflexPopupGap(gap_h)
    end

    local function NavDrawVersionRow(menu_w)
        local version = "v" .. tostring(nav_version)
        local version_w, version_h = r.ImGui_CalcTextSize(ctx, version)
        version_h = version_h or r.ImGui_GetTextLineHeight(ctx)
        local dots_img = NavGetTychoDotsImage()
        local dots_w, dots_h = NavTychoDotsSize()
        local row_h = math.max(version_h, dots_h or 0)
        local x, y = r.ImGui_GetCursorScreenPos(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        if dots_img and dots_w and dots_w > 0 and dots_h and dots_h > 0 then
            local _, ih = r.ImGui_Image_GetSize(dots_img)
            local uv_y2 = (ih and ih > 2) and ((ih - 1) / ih) or 1
            local dots_y = y + Round((row_h - dots_h) / 2)
            r.ImGui_DrawList_AddImage(dl, dots_img, x, dots_y, x + dots_w, dots_y + dots_h, 0, 0, 1, uv_y2, 0xFFFFFFFF)
        end
        r.ImGui_DrawList_AddText(dl,
            x + math.max(0, menu_w - version_w),
            y + Round((row_h - version_h) / 2),
            C.text_dim,
            version)
        r.ImGui_Dummy(ctx, menu_w, row_h)
    end

    local function NavDrawStandaloneTitle(menu_w)
        local header_h = S(22)
        local close_sz = S(20)
        local header_x, header_y = r.ImGui_GetCursorScreenPos(ctx)
        local header_dl = r.ImGui_GetWindowDrawList(ctx)
        local header_label = "Track Navigator"
        local _, header_text_h = r.ImGui_CalcTextSize(ctx, header_label)
        header_text_h = header_text_h or r.ImGui_GetTextLineHeight(ctx)
        r.ImGui_DrawList_AddText(header_dl,
            header_x,
            header_y + Round((header_h - header_text_h) / 2),
            C.text,
            header_label)
        r.ImGui_SetCursorScreenPos(ctx,
            header_x + menu_w - close_sz,
            header_y + Round((header_h - close_sz) / 2))
        local _, close_clicked = NavSquare("##nav_options_close", close_sz, close_sz, "X", {
            bg = C.fx_ctrl_bg,
            hov = C.fx_ctrl_hover,
            active = C.fx_ctrl_active,
            fg = C.text_dim,
            fg_hov = C.text,
        })
        r.ImGui_SetCursorScreenPos(ctx, header_x, header_y)
        r.ImGui_Dummy(ctx, menu_w, header_h)
        if close_clicked then NavCloseGlobalMenu() end
        ReflexPopupGap(S(28))
        NavDrawVersionRow(menu_w)
    end

    local function NavArchiveTip()
        if not opt_tooltips then return end
        PushTooltipStyle()
        r.ImGui_BeginTooltip(ctx)
        r.ImGui_Text(ctx, 'Any track named "ARCHIVE"')
        r.ImGui_Text(ctx, "and all of its children")
        r.ImGui_Text(ctx, "will be excluded from Track Navigator")
        r.ImGui_EndTooltip(ctx)
        PopTooltipStyle()
    end

    local function NavPopupTip(lines)
        if not opt_tooltips then return end
        PushTooltipStyle()
        r.ImGui_BeginTooltip(ctx)
        for i, line in ipairs(lines) do
            if i == 1 then
                r.ImGui_Text(ctx, line)
            else
                r.ImGui_TextColored(ctx, C.text_dim, line)
            end
        end
        r.ImGui_EndTooltip(ctx)
        PopTooltipStyle()
    end

    local function NavCurrentDockID()
        if getDockID then
            local dock_id = getDockID()
            if type(dock_id) == "number" then return dock_id end
        end
        if not r.ImGui_GetWindowDockID then return 0 end
        local ok, dock_id = pcall(r.ImGui_GetWindowDockID, ctx)
        if ok and type(dock_id) == "number" then return dock_id end
        return 0
    end

    local DOCK_FALLBACK_DOCKER_BY_POS = {
        [1] = 1,
        [3] = 3,
    }

    local function NavDockIDForDocker(docker)
        return type(docker) == "number" and ~docker or nil
    end

    local function NavDockerForPosition(pos)
        if r.DockGetPosition then
            for docker = 0, 15 do
                local ok, dock_pos = pcall(r.DockGetPosition, docker)
                if ok and dock_pos == pos then return docker end
            end
        end
        return nil
    end

    local function NavDockIDForPosition(pos)
        return NavDockIDForDocker(NavDockerForPosition(pos))
    end

    local function NavDockIDHasPosition(dock_id, pos)
        if type(dock_id) ~= "number" or dock_id >= 0 or not r.DockGetPosition then return false end
        local ok, dock_pos = pcall(r.DockGetPosition, ~dock_id)
        return ok and dock_pos == pos
    end

    local function NavCanProvisionSideDocker()
        return r.DockGetPosition ~= nil
            and r.SNM_GetIntConfigVar ~= nil
            and r.SNM_SetIntConfigVar ~= nil
    end

    local function NavProvisionSideDocker(pos)
        if not NavCanProvisionSideDocker() then return nil end
        local docker = DOCK_FALLBACK_DOCKER_BY_POS[pos]
        if type(docker) ~= "number" then return nil end

        local existing = NavDockIDForPosition(pos)
        if existing then return existing end

        local key = "dockermode" .. tostring(docker)
        local ok_get, old_mode = pcall(r.SNM_GetIntConfigVar, key, 0)
        old_mode = ok_get and type(old_mode) == "number" and math.floor(old_mode) or 0
        local new_mode = (old_mode & ~0xF) | pos
        local ok_set, did_set = pcall(r.SNM_SetIntConfigVar, key, new_mode)
        if ok_set and did_set ~= false then
            if r.DockWindowRefresh then pcall(r.DockWindowRefresh) end
            if NavDockIDHasPosition(~docker, pos) then return ~docker end
        end

        return nil
    end

    local function NavProspectiveDockIDForPosition(pos)
        return NavDockIDForPosition(pos)
            or (NavCanProvisionSideDocker() and NavDockIDForDocker(DOCK_FALLBACK_DOCKER_BY_POS[pos]) or nil)
    end

    local function NavResolveDockIDForPosition(pos)
        return NavDockIDForPosition(pos) or NavProvisionSideDocker(pos)
    end

    local function NavIsSideDockID(dock_id)
        if type(dock_id) ~= "number" or dock_id == 0 then return false end
        return NavDockIDHasPosition(dock_id, 1) or NavDockIDHasPosition(dock_id, 3)
    end

    local function NavRequestDock(dock_id)
        if type(dock_id) ~= "number" then return end
        if requestDock then requestDock(dock_id) end
    end

    local function NavDrawDockArrowIcon(dl, x, y, btn_sz, direction, col)
        local cx = x + btn_sz * 0.5
        local cy = y + btn_sz * 0.5
        local half_w = math.max(S(4), Round(btn_sz * 0.2))
        local half_h = math.max(S(5), Round(btn_sz * 0.28))
        if direction == "left" then
            r.ImGui_DrawList_AddTriangleFilled(dl,
                cx - half_w, cy,
                cx + half_w, cy - half_h,
                cx + half_w, cy + half_h,
                col)
        else
            r.ImGui_DrawList_AddTriangleFilled(dl,
                cx + half_w, cy,
                cx - half_w, cy - half_h,
                cx - half_w, cy + half_h,
                col)
        end
    end

    local function NavDockArrowButton(id, direction, tooltip, pos, current_dock_id, x, y, btn_sz)
        local dock_id = NavProspectiveDockIDForPosition(pos)
        local enabled = requestDock ~= nil
            and type(dock_id) == "number"
            and not NavDockIDHasPosition(current_dock_id, pos)
        r.ImGui_SetCursorScreenPos(ctx, x, y)
        r.ImGui_InvisibleButton(ctx, id, btn_sz, btn_sz)
        local hovered = r.ImGui_IsItemHovered(ctx)
        local active = r.ImGui_IsItemActive(ctx)
        local clicked = r.ImGui_IsItemClicked(ctx, 0)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local bg = C.fx_ctrl_bg
        local fg = C.text_dim
        if not enabled then
            bg = NavWithAlpha(C.fx_ctrl_bg, 0x66)
            fg = NavWithAlpha(C.text_dim, 0x66)
        elseif active then
            bg = C.fx_ctrl_active
            fg = C.text
        elseif hovered then
            bg = C.fx_ctrl_hover
            fg = C.text
        end
        r.ImGui_DrawList_AddRectFilled(dl, x, y, x + btn_sz, y + btn_sz, bg, S(4))
        NavDrawDockArrowIcon(dl, x, y, btn_sz, direction, fg)
        if hovered then
            TipDirect(enabled and tooltip or (tooltip .. " unavailable"))
        end
        if enabled and clicked then
            NavRequestDock(NavResolveDockIDForPosition(pos))
        end
    end

    local function NavDrawDockPad(menu_w)
        local current_dock_id = NavCurrentDockID()
        if NavIsSideDockID(current_dock_id) then
            nav_last_dock_id = current_dock_id
        end
        local docked = current_dock_id ~= 0
        local btn_sz = S(UI.btn_h or 26)
        local gap = S(2)
        local label = docked and "Undock" or "Dock"
        local label_w = math.max(btn_sz, menu_w - btn_sz * 2 - gap * 2)
        local pad_h = btn_sz
        local sx, sy = r.ImGui_GetCursorScreenPos(ctx)
        local x = sx
        local center_x = x + btn_sz + gap
        local center_enabled = docked or NavIsSideDockID(nav_last_dock_id) or NavProspectiveDockIDForPosition(1) ~= nil

        NavDockArrowButton("##dock_left", "left", "Dock left",
            1, current_dock_id, x, sy, btn_sz)

        r.ImGui_SetCursorScreenPos(ctx, center_x, sy)
        local _, dock_clicked = NavRect("##dock_center", label_w, btn_sz, label, {
            bg = center_enabled and C.fx_ctrl_bg or NavWithAlpha(C.fx_ctrl_bg, 0x66),
            hov = center_enabled and C.fx_ctrl_hover or NavWithAlpha(C.fx_ctrl_bg, 0x66),
            active = center_enabled and C.fx_ctrl_active or NavWithAlpha(C.fx_ctrl_bg, 0x66),
            fg = center_enabled and C.text or NavWithAlpha(C.text_dim, 0x66),
            fg_hov = center_enabled and C.text or NavWithAlpha(C.text_dim, 0x66),
        })
        if r.ImGui_IsItemHovered(ctx) and not center_enabled then
            TipDirect("Dock unavailable")
        end
        if center_enabled and dock_clicked and requestDock then
            if docked then
                NavRequestDock(0)
            else
                local preferred_dock_id = nav_last_dock_id
                if not NavIsSideDockID(preferred_dock_id) then
                    preferred_dock_id = NavResolveDockIDForPosition(1)
                end
                NavRequestDock(preferred_dock_id)
            end
        end

        NavDockArrowButton("##dock_right", "right", "Dock right",
            3, current_dock_id, sx + menu_w - btn_sz, sy, btn_sz)

        r.ImGui_SetCursorScreenPos(ctx, sx, sy)
        r.ImGui_Dummy(ctx, menu_w, pad_h)
    end

    local function NavDrawStandaloneWindowOptions(menu_w)
        if nav_menu_context ~= "standalone" then return end
        NavDrawDockPad(menu_w)
    end

    local function NavDrawStandaloneQuit(menu_w)
        if nav_menu_context ~= "standalone" then return end
        if requestQuit then
            local clicked = ReflexMenuItem("Quit", {
                id = "quit_track_navigator",
                min_w = menu_w,
                hover_text_col = COL_NAV_REMOVE,
            })
            if clicked then
                requestQuit()
                NavCloseGlobalMenu()
            end
        end
    end

    local function NavHelpLine(text, manual_w, col)
        ReflexPopupLabel(text, { col = col or C.text_dim, min_w = manual_w })
    end

    local function NavHelpSection(title, manual_w, first)
        if not first then ReflexPopupStackGap(S(18)) end
        ReflexPopupRule(manual_w)
        ReflexPopupStackGap(S(8))
        local section_font = GetSteppedFont and GetSteppedFont(1) or nil
        local section_font_pushed = NavPushFont(section_font)
        ReflexPopupLabel(string.upper(title), { col = C.text, min_w = manual_w })
        NavPopFont(section_font_pushed)
        ReflexPopupStackGap(S(14))
    end

    local function NavHelpInfoBlock(title, lines, manual_w)
        ReflexPopupLabel(title, { col = C.text, min_w = manual_w })
        ReflexPopupGap(S(2))
        for _, line in ipairs(lines) do
            NavHelpLine(line, manual_w)
        end
    end

    local function NavDrawHelpManualPopup()
        if r.ImGui_BeginPopup(ctx, "##nav_help_manual") then
            notePopupActive()
            if ReflexDrawSolidPopupOutline then
                ReflexDrawSolidPopupOutline(S(10), C.popup_border or C.window_outline)
            end
            ReflexPushPopupLayout()
            local manual_w = S(460)
            nav_help_manual_hovered = r.ImGui_IsWindowHovered(ctx, r.ImGui_HoveredFlags_RootAndChildWindows())
            if nav_help_manual_close_requested
               or r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
                nav_help_manual_close_requested = false
                nav_help_manual_hovered = false
                r.ImGui_CloseCurrentPopup(ctx)
                ReflexPopPopupLayout()
                r.ImGui_EndPopup(ctx)
                return
            end

            local is_mac = NavIsMacOS()
            local primary_click = is_mac and "Cmd-click" or "Ctrl-click"
            local pin_click = is_mac and "Opt-click" or "Alt-click"
            local child_click = is_mac and "Opt+CMD-click" or "Alt+Ctrl-click"

            local header_h = S(22)
            local close_sz = S(20)
            local header_x, header_y = r.ImGui_GetCursorScreenPos(ctx)
            local header_dl = r.ImGui_GetWindowDrawList(ctx)
            local header_label = "Help / Manual"
            local _, header_text_h = r.ImGui_CalcTextSize(ctx, header_label)
            header_text_h = header_text_h or r.ImGui_GetTextLineHeight(ctx)
            r.ImGui_DrawList_AddText(header_dl,
                header_x,
                header_y + Round((header_h - header_text_h) / 2),
                C.text_dim,
                header_label)
            r.ImGui_SetCursorScreenPos(ctx,
                header_x + manual_w - close_sz,
                header_y + Round((header_h - close_sz) / 2))
            local _, close_clicked = NavSquare("##nav_help_close", close_sz, close_sz, "X", {
                bg = C.fx_ctrl_bg,
                hov = C.fx_ctrl_hover,
                active = C.fx_ctrl_active,
                fg = C.text_dim,
                fg_hov = C.text,
            })
            r.ImGui_SetCursorScreenPos(ctx, header_x, header_y)
            r.ImGui_Dummy(ctx, manual_w, header_h)
            if close_clicked then
                nav_help_manual_close_requested = false
                nav_help_manual_hovered = false
                r.ImGui_CloseCurrentPopup(ctx)
                ReflexPopPopupLayout()
                r.ImGui_EndPopup(ctx)
                return
            end
            ReflexPopupStackGap(S(12))

            NavHelpLine("Track Navigator lets you quickly build custom track views so you can", manual_w)
            NavHelpLine("focus on specific parts of your session. If you get lost,", manual_w)
            if is_mac then
                NavHelpLine("Cmd+Shift-click anywhere or click Show all tracks", manual_w)
            else
                NavHelpLine("Ctrl+Shift-click anywhere or click Show all tracks", manual_w)
            end
            NavHelpLine("in the global menu.", manual_w)

            ReflexPopupStackGap(S(16))
            NavHelpInfoBlock("A - Active Tracks View Button", {
                "Shows tracks whose signal exceeded -60 dB recently.",
                "Also includes parent folders and forward send destinations",
                "Click again to restore the previous view.",
                pin_click .. " while active recalculates the view",
            }, manual_w)
            ReflexPopupStackGap(S(12))
            NavHelpInfoBlock("S - Selected Tracks View Button", {
                "Shows only the currently selected tracks.",
                "Click again to restore the previous view.",
                pin_click .. " while active rebuilds from current selection",
            }, manual_w)
            ReflexPopupStackGap(S(12))
            NavHelpInfoBlock("R - Routing View Button", {
                "Builds a view from the selected track or tracks.",
                "Shows upstream sources and downstream send destinations.",
                "Receive-source parent folders are excluded unless routed in.",
                pin_click .. " while active rebuilds from current selection",
            }, manual_w)

            NavHelpSection("Top Level Track (TLT) Buttons", manual_w)
            NavHelpInfoBlock("Click", {
                "Show only this TLT, subsequent clicks expand / collapse",
                "if track is a folder",
            }, manual_w)
            ReflexPopupStackGap(S(9))
            NavHelpInfoBlock(primary_click, {
                "Add or remove this TLT from the visible set",
            }, manual_w)
            ReflexPopupStackGap(S(9))
            NavHelpInfoBlock(pin_click, {
                "Pin or unpin this TLT. Pinned TLT's visibility persists",
                "even when other TLTs are clicked",
            }, manual_w)
            ReflexPopupStackGap(S(9))
            NavHelpInfoBlock(child_click, {
                "Expand or collapse this TLT and its children",
                "(if track is a folder) without affecting visibility",
                "of other TLTs",
            }, manual_w)
            ReflexPopupStackGap(S(9))
            NavHelpInfoBlock("Shift-click", {
                "Range-select TLTs",
            }, manual_w)
            ReflexPopupStackGap(S(9))
            NavHelpInfoBlock("Right-click", {
                "Pin, hide, or customize this TLT",
            }, manual_w)

            NavHelpSection("Custom Visibility", manual_w)
            NavHelpInfoBlock("Show selected tracks", {
                "Adds selected REAPER tracks manually as TLT buttons",
            }, manual_w)
            ReflexPopupStackGap(S(9))
            NavHelpInfoBlock("Hide selected tracks", {
                "Hides selected TLTs and all of their descendants",
                "from Track Navigator",
            }, manual_w)
            ReflexPopupStackGap(S(9))
            NavHelpInfoBlock("Hide selected & show descendants", {
                "Hides selected parent buttons and promotes",
                "their direct children as TLT buttons",
            }, manual_w)
            ReflexPopupStackGap(S(9))
            NavHelpInfoBlock("Reset", {
                "Clears manually shown tracks, hidden tracks,",
                "and show-descendants rules",
            }, manual_w)

            NavHelpSection("Options", manual_w)
            NavHelpInfoBlock("Ignore ARCHIVE", {
                "Hides any folder named ARCHIVE and its children",
            }, manual_w)
            ReflexPopupStackGap(S(9))
            NavHelpInfoBlock("Mirror TLT buttons", {
                "Mirrors TLT button layout",
            }, manual_w)
            ReflexPopupStackGap(S(9))
            NavHelpInfoBlock("Recall arrange view", {
                "Restores horizontal arrange scroll and zoom",
                "when leaving A/S/R view modes",
            }, manual_w)
            ReflexPopupStackGap(S(9))
            NavHelpInfoBlock("Modifier key tooltips", {
                "Shows shortcut helper text on NAV arrows and TLT pills",
            }, manual_w)
            ReflexPopupStackGap(S(9))
            NavHelpInfoBlock("All tooltips", {
                "Enables or disables every Track Navigator tooltip",
            }, manual_w)
            if nav_menu_context == "standalone" then
                ReflexPopupStackGap(S(9))
                NavHelpInfoBlock("Dock", {
                    "Moves Track Navigator into a REAPER docker",
                }, manual_w)
                ReflexPopupStackGap(S(9))
                NavHelpInfoBlock("Quit", {
                    "Stops the standalone script, useful while docked",
                }, manual_w)
            end

            ReflexPopPopupLayout()
            r.ImGui_EndPopup(ctx)
        else
            nav_help_manual_close_requested = false
            nav_help_manual_hovered = false
        end
    end

    local function NavGlobalMenuWidth()
        local scale = getNavScale and getNavScale() or 1.0
        local row_h = S(UI.btn_h or 26)
        local label = string.format("%d%%", math.floor(scale * 100 + 0.5))
        local label_w = r.ImGui_CalcTextSize(ctx, label) + S(14)
        local controls_w = row_h + S(2) + label_w + S(2) + row_h
        local title_w = 0
        if nav_menu_context == "standalone" then
            title_w = r.ImGui_CalcTextSize(ctx, "Track Navigator")
        end
        local size_label = nav_menu_context == "standalone" and "UI size" or "Navigator size"
        local ui_w = r.ImGui_CalcTextSize(ctx, size_label)
        local size_row_w = ui_w + S(12) + controls_w
        local check_w = r.ImGui_CalcTextSize(ctx, "\xE2\x9C\x93")
        local ignore_archive_w = r.ImGui_CalcTextSize(ctx, "Ignore ARCHIVE") + check_w + S(30)
        local mirror_w = r.ImGui_CalcTextSize(ctx, "Mirror TLT buttons") + check_w + S(30)
        local arrange_recall_w = r.ImGui_CalcTextSize(ctx, "Recall arrange view") + check_w + S(30)
        local helper_w = r.ImGui_CalcTextSize(ctx, "Modifier key tooltips") + check_w + S(30)
        local tooltips_w = r.ImGui_CalcTextSize(ctx, "All tooltips") + check_w + S(30)
        local esc_close_w = 0
        if nav_menu_context == "standalone" then
            esc_close_w = r.ImGui_CalcTextSize(ctx, "Esc key to close") + check_w + S(30)
        end
        local show_all_w = r.ImGui_CalcTextSize(ctx, "Show all tracks") + S(16)
        local help_w = r.ImGui_CalcTextSize(ctx, "Help / Manual") + S(42)
        local include_w = r.ImGui_CalcTextSize(ctx, "Show selected tracks") + S(16)
        local hide_selected_w = r.ImGui_CalcTextSize(ctx, "Hide selected tracks") + S(16)
        local promote_selected_w = r.ImGui_CalcTextSize(ctx, "Hide selected & show descendants") + S(16)
        local window_w = 0
        if nav_menu_context == "standalone" then
            local dock_label_w = math.max(row_h, r.ImGui_CalcTextSize(ctx, "Undock") + S(12))
            local dock_pad_w = row_h + S(2) + dock_label_w + S(2) + row_h
            window_w = math.max(
                dock_pad_w,
                r.ImGui_CalcTextSize(ctx, "Quit") + S(16)
            )
        end
        include_w = math.max(include_w, r.ImGui_CalcTextSize(ctx, "No tracks selected") + S(16))
        local custom_w = r.ImGui_CalcTextSize(ctx, "Manually shown tracks") + S(20) + S(24)
        local hidden_w = r.ImGui_CalcTextSize(ctx, "Hidden tracks") + S(20) + S(24)
        local promoted_w = r.ImGui_CalcTextSize(ctx, "Showing descendants instead") + S(20) + S(24)
        local reset_w = r.ImGui_CalcTextSize(ctx, "Reset custom visibility") + S(16)
        local confirm_w = 0
        if nav_reset_confirm then
            confirm_w = math.max(
                r.ImGui_CalcTextSize(ctx, "Reset custom visibility?") + S(16),
                r.ImGui_CalcTextSize(ctx, "Clear manually shown tracks and") + S(16),
                r.ImGui_CalcTextSize(ctx, "hidden/show-descendants rules.") + S(16)
            )
        end
        if NavIncludedEntries then
            for _, entry in ipairs(NavIncludedEntries({ include_blocked = true })) do
                local label = NavIncludedMenuLabel(entry)
                custom_w = math.max(custom_w, r.ImGui_CalcTextSize(ctx, label) + S(16))
            end
        end
        if top_folders then
            for _, entry in ipairs(top_folders) do
                local track = entry.track
                if track and r.ValidatePtr(track, "MediaTrack*") then
                    local guid = r.GetTrackGUID(track)
                    if nav_hidden and nav_hidden[guid] then
                        local label = NavHiddenMenuLabel(entry)
                        hidden_w = math.max(hidden_w, r.ImGui_CalcTextSize(ctx, label) + S(16))
                    elseif nav_excluded and nav_excluded[guid] then
                        local label = NavPromotedMenuLabel(entry)
                        promoted_w = math.max(promoted_w, r.ImGui_CalcTextSize(ctx, label) + S(16))
                    end
                end
            end
        end
        return math.max(S(180), size_row_w, title_w, ignore_archive_w, mirror_w, arrange_recall_w, helper_w, tooltips_w, esc_close_w, show_all_w,
            help_w, include_w, hide_selected_w, promote_selected_w, custom_w, hidden_w, promoted_w, reset_w, confirm_w, window_w)
    end

    local function NavTlfMenuWidth(pin_label, ignore_label, ghost_parent, custom_item)
        if custom_item then
            return math.max(
                r.ImGui_CalcTextSize(ctx, "Hide in Track Navigator") + S(16),
                r.ImGui_CalcTextSize(ctx, "Options") + S(16)
            )
        end
        local w = math.max(
            r.ImGui_CalcTextSize(ctx, pin_label) + S(16),
            r.ImGui_CalcTextSize(ctx, "Unpin all") + S(16),
            r.ImGui_CalcTextSize(ctx, "Options") + S(16)
        )
        if ignore_label then w = math.max(w, r.ImGui_CalcTextSize(ctx, ignore_label) + S(16)) end
        if ghost_parent then w = math.max(w, r.ImGui_CalcTextSize(ctx, "Show parent in Track Navigator") + S(16)) end
        return w
    end

    local function NavDrawClearableSectionHeader(menu_w, label, clear_id, clear_tip, clear_fn)
        local row_h = S(UI.btn_h or 26)
        local close_sz = S(20)
        local x, y = r.ImGui_GetCursorScreenPos(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local _, text_h = r.ImGui_CalcTextSize(ctx, label)
        text_h = text_h or r.ImGui_GetTextLineHeight(ctx)
        r.ImGui_DrawList_AddText(dl, x, y + Round((row_h - text_h) / 2), C.text, label)
        r.ImGui_SetCursorScreenPos(ctx,
            x + menu_w - close_sz,
            y + Round((row_h - close_sz) / 2))
        local _, clear_clicked = NavSquare(clear_id, close_sz, close_sz, "X", {
            bg = C.fx_ctrl_bg,
            hov = C.fx_ctrl_hover,
            active = C.fx_ctrl_active,
            fg = C.text_dim,
            fg_hov = COL_NAV_REMOVE,
            fg_active = COL_NAV_REMOVE,
        })
        if clear_tip and r.ImGui_IsItemHovered(ctx) then
            NavPopupTip(clear_tip)
        end
        r.ImGui_SetCursorScreenPos(ctx, x, y)
        r.ImGui_Dummy(ctx, menu_w, row_h)
        if clear_clicked and clear_fn then
            return clear_fn() == true
        end
        return false
    end

    local function NavDrawIgnoredFolders(menu_w)
        if not top_folders then return end
        if NavPruneExcludedTracks then NavPruneExcludedTracks() end
        local hidden = {}
        local promoted = {}
        for _, entry in ipairs(top_folders) do
            local track = entry.track
            if track and r.ValidatePtr(track, "MediaTrack*") then
                local guid = r.GetTrackGUID(track)
                if nav_hidden and nav_hidden[guid] then
                    hidden[#hidden + 1] = entry
                elseif nav_excluded and nav_excluded[guid] then
                    promoted[#promoted + 1] = entry
                end
            end
        end

        if #hidden > 0 then
            NavPopupSectionBreak(menu_w)
            if NavDrawClearableSectionHeader(menu_w, "Hidden tracks", "##clear_hidden_tracks", {
                "Show all hidden tracks in Track Navigator",
                "Manually shown tracks and show-descendants rules stay unchanged.",
            }, NavResetHiddenTracks) then return end
            ReflexPopupGap(S(4))
            for _, entry in ipairs(hidden) do
                local guid = r.GetTrackGUID(entry.track)
                local clicked, hovered = ReflexMenuItem(NavHiddenMenuLabel(entry), {
                    id = "hidden_" .. guid,
                    min_w = menu_w,
                    no_auto_close = true,
                    hover_text_col = COL_NAV_REMOVE,
                })
                if hovered then
                    NavPopupTip({
                        "Remove this full-hide rule",
                        "The TLT and all descendants return",
                        "to Track Navigator as normal.",
                    })
                end
                if clicked then
                    NavSetTrackHidden(entry.track, false)
                end
            end
        end

        if #promoted > 0 then
            NavPopupSectionBreak(menu_w)
            if NavDrawClearableSectionHeader(menu_w, "Showing descendants instead", "##clear_promoted_tracks", {
                "Show all promoted parent tracks in Track Navigator",
                "Manually shown tracks and hidden tracks stay unchanged.",
            }, NavResetPromotedTracks) then return end
            ReflexPopupGap(S(4))
            for _, entry in ipairs(promoted) do
                local guid = r.GetTrackGUID(entry.track)
                local clicked, hovered = ReflexMenuItem(NavPromotedMenuLabel(entry), {
                    id = "promoted_" .. guid,
                    min_w = menu_w,
                    no_auto_close = true,
                    hover_text_col = COL_NAV_REMOVE,
                })
                if hovered then
                    NavPopupTip({
                        "Remove this show-descendants rule",
                        "The TLT returns to Track Navigator;",
                        "its direct children stop being promoted.",
                    })
                end
                if clicked then
                    NavSetTrackExcluded(entry.track, false)
                end
            end
        end
    end

    local function NavMenuCheckItem(label, checked, id, menu_w)
        local row_h = S(UI.btn_h or 26)
        local pad_x = S(8)
        local pad_y = S(4)
        local flags = r.ImGui_SelectableFlags_NoAutoClosePopups
            and r.ImGui_SelectableFlags_NoAutoClosePopups()
            or 1
        local text_w, text_h = r.ImGui_CalcTextSize(ctx, label)
        text_h = text_h or r.ImGui_GetTextLineHeight(ctx)
        local check = "\xE2\x9C\x93"
        local check_w, check_h = r.ImGui_CalcTextSize(ctx, check)
        check_h = check_h or text_h
        local row_w = math.max(menu_w, text_w + check_w + pad_x * 3)
        local row_h_calc = math.max(row_h, text_h + pad_y * 2)

        r.ImGui_PushID(ctx, id)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x00000000)
        local clicked = r.ImGui_Selectable(ctx, "##item", false, flags, row_w, row_h_calc)
        r.ImGui_PopStyleColor(ctx, 4)
        local hovered = r.ImGui_IsItemHovered(ctx)
        local active = r.ImGui_IsItemActive(ctx)
        local x1, y1 = r.ImGui_GetItemRectMin(ctx)
        local x2, y2 = r.ImGui_GetItemRectMax(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        if hovered or active then
            r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2,
                active and (C.popup_active or C.fx_ctrl_active) or (C.popup_hover or C.fx_ctrl_hover), S(4))
        end
        r.ImGui_DrawList_AddText(dl, x1 + pad_x, y1 + Round((row_h_calc - text_h) / 2),
            hovered and C.text or C.text_dim, label)
        if checked then
            r.ImGui_DrawList_AddText(dl, x2 - pad_x - check_w, y1 + Round((row_h_calc - check_h) / 2),
                hovered and C.text or C.text_dim, check)
        end
        r.ImGui_PopID(ctx)
        return clicked, hovered
    end

    local function NavDrawGlobalOptions(menu_w)
        local archive_clicked, archive_hov = NavMenuCheckItem("Ignore ARCHIVE", opt_nav_ignore_archive, "ignore_archive", menu_w)
        if archive_hov then NavArchiveTip() end
        if archive_clicked then
            opt_nav_ignore_archive = not opt_nav_ignore_archive
            SavePref("nav_ignore_archive", opt_nav_ignore_archive)
            markDirty()
        end
        if NavMenuCheckItem("Mirror TLT buttons", nav_mirror, "mirror_tlf_buttons", menu_w) then
            nav_mirror = not nav_mirror
            SavePref("nav_mirror", nav_mirror)
        end
        local arrange_clicked, arrange_hov = NavMenuCheckItem("Recall arrange view", opt_view_mode_restore_arrange, "view_mode_restore_arrange", menu_w)
        if arrange_hov then
            NavPopupTip({
                "Restore horizontal arrange scroll and zoom",
                "when leaving A/S/R view modes.",
            })
        end
        if arrange_clicked then
            opt_view_mode_restore_arrange = not opt_view_mode_restore_arrange
            SavePref("view_mode_restore_arrange", opt_view_mode_restore_arrange)
        end
        if nav_menu_context == "standalone" then
            if NavMenuCheckItem("Esc key to close", opt_esc_key_to_close, "esc_key_to_close", menu_w) then
                opt_esc_key_to_close = not opt_esc_key_to_close
                SavePref("esc_key_to_close", opt_esc_key_to_close)
            end
        end
    end

    local function NavDrawHelperTooltipOption(menu_w)
        local helper_tips_enabled = opt_helper_tooltips ~= false
        if NavMenuCheckItem("Modifier key tooltips", helper_tips_enabled, "helper_tooltips", menu_w) then
            opt_helper_tooltips = not helper_tips_enabled
            SavePref("helper_tooltips", opt_helper_tooltips)
        end
        local tooltips_enabled = opt_tooltips ~= false
        if NavMenuCheckItem("All tooltips", tooltips_enabled, "track_navigator_tooltips", menu_w) then
            opt_tooltips = not tooltips_enabled
            SavePref("track_navigator_tooltips", opt_tooltips)
        end
    end

    local function NavDrawRecoveryOptions(menu_w)
        local show_clicked, show_hov = ReflexMenuItem("Show all tracks", {
            id = "show_all_tracks",
            min_w = menu_w,
            no_auto_close = true,
        })
        if show_hov then
            NavPopupTip({
                "Restore all tracks to Track Navigator",
                "visibility in TCP and Mixer.",
            })
        end
        if show_clicked then
            ShowAllTracks()
        end
    end

    local function NavDrawHelpRow(menu_w)
        local row_h = S(UI.btn_h or 26)
        local label = "Help / Manual"
        local pad_x = S(8)
        local flags = r.ImGui_SelectableFlags_NoAutoClosePopups
            and r.ImGui_SelectableFlags_NoAutoClosePopups()
            or 1
        r.ImGui_PushID(ctx, "nav_help_manual_row")
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x00000000)
        local clicked = r.ImGui_Selectable(ctx, "##item", false, flags, menu_w, row_h)
        r.ImGui_PopStyleColor(ctx, 4)
        local hovered = r.ImGui_IsItemHovered(ctx)
        local active = r.ImGui_IsItemActive(ctx)
        local x1, y1 = r.ImGui_GetItemRectMin(ctx)
        local x2, y2 = r.ImGui_GetItemRectMax(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        if hovered or active then
            r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, active and (C.popup_active or C.fx_ctrl_active) or (C.popup_hover or C.fx_ctrl_hover), S(4))
        end
        local _, text_h = r.ImGui_CalcTextSize(ctx, label)
        text_h = text_h or r.ImGui_GetTextLineHeight(ctx)
        r.ImGui_DrawList_AddText(dl, x1 + pad_x, y1 + Round((row_h - text_h) / 2), hovered and C.text or C.text_dim, label)
        r.ImGui_PopID(ctx)
        if clicked then r.ImGui_OpenPopup(ctx, "##nav_help_manual") end
    end

    local function NavSelectedTltCandidates()
        local entries = {}
        local seen = {}
        if not NavCanExcludeTrack then return entries end
        for i = 0, r.CountSelectedTracks(0) - 1 do
            local track = r.GetSelectedTrack(0, i)
            if track and r.ValidatePtr(track, "MediaTrack*") then
                local guid = r.GetTrackGUID(track)
                if not seen[guid] then
                    local _, name = r.GetTrackName(track)
                    if NavCanExcludeTrack(track, name, false) then
                        seen[guid] = true
                        entries[#entries + 1] = {
                            track = track,
                            guid = guid,
                            name = name,
                        }
                    end
                end
            end
        end
        return entries
    end

    local function NavApplySelectedTltVisibility(mode)
        local changed = 0
        for _, entry in ipairs(NavSelectedTltCandidates()) do
            if mode == "hidden" then
                if NavSetTrackHidden then
                    NavSetTrackHidden(entry.track, true)
                    changed = changed + 1
                end
            elseif NavSetTrackExcluded then
                NavSetTrackExcluded(entry.track, true)
                changed = changed + 1
            end
        end
        return changed
    end

    local function NavDrawCustomItems(menu_w)
        if openIoManager then
            local io_clicked, io_hov = ReflexMenuItem("I/O Manager", {
                id = "io_manager",
                min_w = menu_w,
                hover_text_col = C.cmp_b or C.fx_send_text,
                no_auto_close = true,
            })
            if io_hov then
                NavPopupTip({
                    "Edit audio/MIDI aliases, favorites,",
                    "and MIDI device enable state.",
                })
            end
            if io_clicked then
                openIoManager()
            end
            ReflexPopupStackGap(S(4))
        end

        local sel_count = r.CountSelectedTracks(0)
        local selected_tlts = NavSelectedTltCandidates()
        local include_label = sel_count > 0 and "Show selected tracks" or "No tracks selected"
        local include_clicked, include_hov = ReflexMenuItem(include_label, {
            id = "include_selected_tracks",
            min_w = menu_w,
            enabled = sel_count > 0,
            hover_text_col = COL_NAV_ADD,
            no_auto_close = true,
        })
        if include_hov and sel_count > 0 then
            NavPopupTip({
                "Add selected tracks as manual NAV buttons",
                "They appear in project order near their context.",
                "Hidden TLT subtrees and ARCHIVE are still ignored.",
            })
        end
        if include_clicked then
            if NavIncludeSelectedTracks then NavIncludeSelectedTracks() end
        end
        local hide_clicked, hide_hov = ReflexMenuItem("Hide selected tracks", {
            id = "hide_selected_tracks",
            min_w = menu_w,
            enabled = #selected_tlts > 0,
            hover_text_col = COL_NAV_REMOVE,
            no_auto_close = true,
        })
        if hide_hov then
            NavPopupTip({
                "Hide selected TLTs and everything inside them",
                "No descendant tracks are promoted.",
            })
        end
        if hide_clicked then
            NavApplySelectedTltVisibility("hidden")
        end
        local promote_clicked, promote_hov = ReflexMenuItem("Hide selected & show descendants", {
            id = "promote_selected_tracks",
            min_w = menu_w,
            enabled = #selected_tlts > 0,
            hover_text_col = COL_NAV_REMOVE,
            no_auto_close = true,
        })
        if promote_hov then
            NavPopupTip({
                "Hide selected parent TLT buttons",
                "Direct children appear as NAV buttons instead.",
                "Future direct children will be promoted too.",
            })
        end
        if promote_clicked then
            NavApplySelectedTltVisibility("promoted")
        end

        local included = NavIncludedEntries and NavIncludedEntries({ include_blocked = true }) or {}
        if #included == 0 then return end

        NavPopupSectionBreak(menu_w)
        if NavDrawClearableSectionHeader(menu_w, "Manually shown tracks", "##clear_included_tracks", {
            "Remove all manually shown tracks",
            "Hidden tracks and show-descendants rules stay unchanged.",
        }, NavResetIncludedTracks) then return end
        ReflexPopupStackGap(S(4))
        for _, entry in ipairs(included) do
            local label = NavIncludedMenuLabel(entry)
            if ReflexMenuItem(label, {
                id = "included_" .. entry.guid,
                min_w = menu_w,
                hover_text_col = COL_NAV_REMOVE,
                no_auto_close = true,
            }) then
                if NavSetTrackIncluded then NavSetTrackIncluded(entry.track, false) end
            end
        end
    end

    local function NavHasNavigatorCustomizations()
        if NavPruneExcludedTracks then NavPruneExcludedTracks() end
        if nav_excluded then
            for _ in pairs(nav_excluded) do return true end
        end
        if nav_hidden then
            for _ in pairs(nav_hidden) do return true end
        end
        if nav_included then
            for _ in pairs(nav_included) do return true end
        end
        return false
    end

    local function NavResetNavigatorCustomizations()
        local changed = false
        if NavResetIncludedTracks then changed = NavResetIncludedTracks() or changed end
        if NavResetExcludedTracks then changed = NavResetExcludedTracks() or changed end
        if changed then markDirty() end
        return changed
    end

    local function NavDrawResetCustomizations(menu_w)
        NavPopupSectionBreak(menu_w)
        if nav_reset_confirm then
            ReflexPopupLabel("Reset custom visibility?", { col = C.text, min_w = menu_w })
            ReflexPopupStackGap(S(6))
            ReflexPopupLabel("Clear manually shown tracks and", { col = C.text_dim, min_w = menu_w })
            ReflexPopupLabel("hidden/show-descendants rules.", { col = C.text_dim, min_w = menu_w })
            ReflexPopupStackGap()
            local btn_gap = S(6)
            local btn_w = math.floor((menu_w - btn_gap) / 2)
            local row_h = S(UI.btn_h or 26)
            local _, cancel_clk = NavRect("##reset_nav_cancel", btn_w, row_h, "Cancel", {
                bg = C.fx_ctrl_bg, hov = C.fx_ctrl_hover, active = C.fx_ctrl_active,
                fg = C.text_dim, fg_hov = C.text,
            })
            r.ImGui_SameLine(ctx, 0, btn_gap)
            local _, reset_clk = NavRect("##reset_nav_confirm", btn_w, row_h, "Reset", {
                bg = C.fx_ctrl_bg, hov = C.fx_ctrl_hover, active = C.fx_ctrl_active,
                fg = COL_NAV_REMOVE, fg_hov = COL_NAV_REMOVE, fg_active = COL_NAV_REMOVE,
            })
            if cancel_clk then
                nav_reset_confirm = false
            end
            if reset_clk then
                NavResetNavigatorCustomizations()
                nav_reset_confirm = false
            end
        elseif ReflexMenuItem("Reset custom visibility", {
            id = "reset_nav_customizations",
            min_w = menu_w,
            enabled = NavHasNavigatorCustomizations(),
            hover_text_col = COL_NAV_REMOVE,
            no_auto_close = true,
        }) then
            nav_reset_confirm = true
        end
    end

    local function NavGlobalMenuWindowFlags()
        local flags = 0
        if r.ImGui_WindowFlags_AlwaysAutoResize then flags = flags | r.ImGui_WindowFlags_AlwaysAutoResize() end
        if r.ImGui_WindowFlags_NoTitleBar then flags = flags | r.ImGui_WindowFlags_NoTitleBar() end
        if r.ImGui_WindowFlags_NoResize then flags = flags | r.ImGui_WindowFlags_NoResize() end
        if r.ImGui_WindowFlags_NoSavedSettings then flags = flags | r.ImGui_WindowFlags_NoSavedSettings() end
        if r.ImGui_WindowFlags_NoDocking then flags = flags | r.ImGui_WindowFlags_NoDocking() end
        if r.ImGui_WindowFlags_TopMost then flags = flags | r.ImGui_WindowFlags_TopMost() end
        return flags
    end

    local function NavDrawMainContextPopup()
        if not nav_global_menu_open then
            nav_reset_confirm = false
            return
        end

        PushPopupStyle({ solid_outline = true, padding_scale = 2 })
        local color_count = 0
        local var_count = 0
        if r.ImGui_Col_WindowBg then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), C.popup_bg or C.bg)
            color_count = color_count + 1
        end
        if r.ImGui_StyleVar_WindowRounding then
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), S(10))
            var_count = var_count + 1
        end
        if nav_global_menu_pos_pending and nav_global_menu_pos_x and nav_global_menu_pos_y then
            local pivot_x, pivot_y = NavGlobalMenuPivot(nav_global_menu_pos_x, nav_global_menu_pos_y)
            local ok_pos = pcall(r.ImGui_SetNextWindowPos,
                ctx, nav_global_menu_pos_x, nav_global_menu_pos_y, 0, pivot_x, pivot_y)
            if not ok_pos then
                pcall(r.ImGui_SetNextWindowPos, ctx, nav_global_menu_pos_x, nav_global_menu_pos_y)
            end
            nav_global_menu_pos_pending = false
        end

        local visible, open = r.ImGui_Begin(ctx, "Track Navigator Options##navctx", true, NavGlobalMenuWindowFlags())
        if not open then NavCloseGlobalMenu() end
        if visible and nav_global_menu_open then
            notePopupActive()
            if r.ImGui_GetWindowPos and r.ImGui_GetWindowSize and r.ImGui_SetWindowPos then
                local px, py = r.ImGui_GetWindowPos(ctx)
                local pw, ph = r.ImGui_GetWindowSize(ctx)
                local clamped_x, clamped_y = NavClampRectToViewport(px, py, pw, ph)
                if math.abs(clamped_x - px) > 0.5 or math.abs(clamped_y - py) > 0.5 then
                    pcall(r.ImGui_SetWindowPos, ctx, clamped_x, clamped_y)
                end
            end
            if ReflexDrawSolidPopupOutline then
                ReflexDrawSolidPopupOutline(S(10), C.popup_border or C.window_outline)
            end
            ReflexPushPopupLayout()
            local menu_w = NavGlobalMenuWidth()
            local help_open = r.ImGui_IsPopupOpen(ctx, "##nav_help_manual")
            local esc_pressed = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape())
            if esc_pressed and not help_open then
                NavCloseGlobalMenu()
            else
                if nav_menu_context == "standalone" then
                    NavDrawStandaloneTitle(menu_w)
                    NavPopupSectionBreak(menu_w)
                end
                local size_label = nav_menu_context == "standalone" and "UI size" or "Navigator size"
                NavDrawSizeRow(menu_w, size_label)
                NavPopupSectionBreak(menu_w)
                NavDrawCustomItems(menu_w)
                NavDrawIgnoredFolders(menu_w)
                NavDrawResetCustomizations(menu_w)
                NavPopupSectionBreak(menu_w)
                NavDrawGlobalOptions(menu_w)
                NavPopupSectionBreak(menu_w)
                if nav_menu_context ~= "standalone" then
                    NavDrawRecoveryOptions(menu_w)
                    NavPopupSectionBreak(menu_w)
                end
                NavDrawHelperTooltipOption(menu_w)
                NavDrawHelpRow(menu_w)
                if nav_menu_context == "standalone" then
                    NavPopupSectionBreak(menu_w)
                    NavDrawRecoveryOptions(menu_w)
                    NavDockSectionGap()
                    NavDrawStandaloneWindowOptions(menu_w)
                    NavDockSectionGap()
                    NavDrawStandaloneQuit(menu_w)
                end
                NavDrawHelpManualPopup()
            end
            ReflexPopPopupLayout()
        end
        r.ImGui_End(ctx)
        if var_count > 0 then r.ImGui_PopStyleVar(ctx, var_count) end
        if color_count > 0 then r.ImGui_PopStyleColor(ctx, color_count) end
        PopPopupStyle()
    end

    local function NavDrawOptionsMenuItem(menu_w)
        ReflexPopupSeparator(menu_w)
        if ReflexMenuItem("Options", { id = "open_nav_options", min_w = menu_w }) then
            nav_open_global_menu = true
            r.ImGui_CloseCurrentPopup(ctx)
        end
    end

    local function NavDrawTlfContextItems(track, name, has_sub_group, ghost_parent, custom_item)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
        if custom_item then
            local menu_w = NavTlfMenuWidth(nil, nil, nil, true)
            if ReflexMenuItem("Hide in Track Navigator", {
                id = "tlf_remove_custom",
                min_w = menu_w,
                hover_text_col = COL_NAV_REMOVE,
            }) then
                if NavSetTrackIncluded then NavSetTrackIncluded(track, false) end
                r.ImGui_CloseCurrentPopup(ctx)
            end
            NavDrawOptionsMenuItem(menu_w)
            return
        end
        local guid = r.GetTrackGUID(track)
        local is_pinned = pinned_folders[guid] == true
        local pin_label = is_pinned and "Unpin" or "Pin"
        local is_excluded = nav_excluded and nav_excluded[guid] == true
        local is_hidden = nav_hidden and nav_hidden[guid] == true
        local ignore_label = nil
        if NavCanExcludeTrack and NavCanExcludeTrack(track, name, has_sub_group) then
            if is_hidden or is_excluded then
                ignore_label = "Show in Track Navigator"
            else
                ignore_label = "Hide in Track Navigator - show children"
            end
        end
        local menu_w = NavTlfMenuWidth(pin_label, ignore_label, ghost_parent, false)
        if ReflexMenuItem(pin_label, { id = "tlf_pin", min_w = menu_w }) then
            if is_pinned then pinned_folders[guid] = nil
            else pinned_folders[guid] = true end
            SavePinnedFolders()
        end
        if ReflexMenuItem("Unpin all", { id = "tlf_unpin_all", min_w = menu_w }) then
            pinned_folders = {}
            SavePinnedFolders()
        end

        if ghost_parent and ghost_parent.track and r.ValidatePtr(ghost_parent.track, "MediaTrack*") then
            ReflexPopupSeparator(menu_w)
            if ReflexMenuItem("Show parent in Track Navigator", { id = "tlf_unignore_parent", min_w = menu_w }) then
                NavSetTrackExcluded(ghost_parent.track, false)
                r.ImGui_CloseCurrentPopup(ctx)
            end
        end

        if ignore_label then
            ReflexPopupSeparator(menu_w)
            if is_hidden or is_excluded then
                if ReflexMenuItem("Show in Track Navigator", { id = "tlf_show_in_nav", min_w = menu_w }) then
                    if is_hidden and NavSetTrackHidden then NavSetTrackHidden(track, false) end
                    if is_excluded and NavSetTrackExcluded then NavSetTrackExcluded(track, false) end
                    r.ImGui_CloseCurrentPopup(ctx)
                end
            else
                local hide_clicked, hide_hov = ReflexMenuItem("Hide in Track Navigator", {
                    id = "tlf_hide_subtree",
                    min_w = menu_w,
                    hover_text_col = COL_NAV_REMOVE,
                })
                if hide_hov then
                    NavPopupTip({
                        "Hide this TLT and everything inside it",
                        "No descendant tracks are promoted.",
                        "Use this to remove a whole section from NAV.",
                    })
                end
                if hide_clicked then
                    if NavSetTrackHidden then NavSetTrackHidden(track, true) end
                    r.ImGui_CloseCurrentPopup(ctx)
                end
                local promote_clicked, promote_hov = ReflexMenuItem("Hide in Track Navigator - show children", {
                    id = "tlf_promote_children",
                    min_w = menu_w,
                    hover_text_col = COL_NAV_REMOVE,
                })
                if promote_hov then
                    NavPopupTip({
                        "Hide only this TLT button",
                        "Direct children appear as NAV buttons instead.",
                        "Future direct children will be promoted too.",
                    })
                end
                if promote_clicked then
                    NavSetTrackExcluded(track, true)
                    r.ImGui_CloseCurrentPopup(ctx)
                end
            end
        end
        NavDrawOptionsMenuItem(menu_w)
    end

    NavDrawSection = function(params)
        local bw = params.bw
        local win_h = params.win_h
        local vh_row_h = params.vh_row_h
        local rem_h = params.rem_h
        local divider_h = params.divider_h
        local wx = params.wx
        local ww = params.ww
        local arrow_w = params.arrow_w
        local bh = params.bh
        local BASE_PAD_Y = params.base_pad_y
        local nav_bottom_extra = params.nav_bottom_extra or S(180)
        local nav_context_scope = params.nav_context_scope or "nav"
        local nav_body_x_offset = params.nav_body_x_offset or 0
        local nav_header_x_offset = params.nav_header_x_offset or 0
        local nav_ar_x_offset = params.nav_ar_x_offset or nav_header_x_offset

          -- ── NAVIGATOR SECTION (fixed, non-scrolling) ──
          local nav_start_y = r.ImGui_GetCursorPosY(ctx)
          -- nav_end_y: bottom edge of the last visible NAV element. Set in
          -- both navigator_expanded branches below; consumed by the bottom-
          -- margin block to position the content child flush with NAV bottom
          -- so the child's WindowPadding(0, S(edge_pad)) provides exactly the
          -- standard 16-retina gap to the first card, identically in both
          -- expand/collapse states.
          local nav_end_y = nav_start_y
        if nav_visible then

          -- Push NAV down 1 logical px (~2 retina) to compensate for the
          -- NAV.arr glyph's -S(1.375) Y nudge (used for in-row optical
          -- centering of the ▼/▶ glyphs). Without this push, the visible top
          -- pixel of the arrow sits ~2 retina higher than the row's geometric
          -- top, making the apparent window-top padding 2 retina smaller than
          -- the standard left-side WindowPadding. Re-anchor nav_start_y after
          -- the push so all height math (nav_total_h, etc.) measures from the
          -- post-push origin.
          r.ImGui_SetCursorPosY(ctx, nav_start_y + S(1.25))
          nav_start_y = r.ImGui_GetCursorPosY(ctx)
          nav_end_y = nav_start_y

          -- Shared arrow + row geometry across BOTH expanded and collapsed nav
          -- states so the arrow visually rotates in place when toggling. Used by
          -- the expanded-state header below and by the collapsed-state mini
          -- circle row below the else branch.
          local mini_tlf_h = S(34)
          local nav_dot_r = math.floor(mini_tlf_h / 2)
          -- Float radius for the outer-disc DRAW only. nav_dot_r is floored
          -- (= 13 logical at 100%, diameter = 26) so layout math gets stable
          -- integer offsets, but using nav_dot_r as the AddCircleFilled radius
          -- makes the disc 1 logical px (~2 retina) smaller than the expanded
          -- pill height (S(34) = 27 logical). Drawing at mini_tlf_h/2 preserves
          -- the full diameter so collapsed mini-circles and fully-collapsed
          -- expanded pills are exactly the same size.
          local nav_dot_render_r = mini_tlf_h / 2
          local nav_dot_gap = S(4)
          local nav_circle_segments = NAV_CIRCLE_SEGMENTS or 48
          local nav_arrow_area = nav_dot_r * 2 + nav_dot_gap
          local nav_left_pad_shared = 0  -- collapsed dots/arrow now flush with expanded TLT pills' left edge (which has no padding from BeginChild WindowPadding(0,0))
          local nav_single_row_h = nav_dot_r * 2 + S(3.75)  -- inter-row pad matches expanded ItemSpacing.y so collapsed/expanded inter-row gaps are visually identical

          -- Arrow font: same step as the previous expanded section header (148%
          -- of UI.font_title). Used by both branches so the glyph stays the same
          -- size when toggling.
          local nav_arrow_step_shared = math.max(5, math.min(20, math.floor(GetFontStep(UI.font_title) * 1.2 + 0.5)))
          local nav_arrow_font_shared = scaled_fonts[nav_arrow_step_shared]
          local COL_NAV_ARROW_REST = rgb(0x545758)

          -- A/S/R nav buttons. Expanded NAV pins them to the top-right header
          -- space in normal widths, falling back to inline flow only when the
          -- header is too narrow. Collapsed NAV always renders them as the
          -- first grouped controls after NAV.arr.
          local nav_shared_scx, nav_shared_scy = r.ImGui_GetCursorScreenPos(ctx)
          local nav_ctx_x1 = nav_shared_scx
          local nav_ctx_y1 = nav_shared_scy
          local nav_ctx_x2 = nav_shared_scx + bw
          local nav_ctx_y2 = nav_shared_scy
          local nav_context_blocked = false
          local ar_d = nav_dot_r * 2
          local ar_gap = nav_dot_gap
          local ar_buttons = { "A", "S", "R" }
          local ar_reserved_w = ar_d * #ar_buttons + ar_gap * (#ar_buttons - 1)  -- [A] gap [S] gap [R]
          local ar_pair_w = ar_d + ar_gap + ar_d
          local ar_fixed = (bw - nav_left_pad_shared) >= (nav_arrow_area + ar_gap + ar_reserved_w)
          -- Wide-mode fixed positions (only valid when ar_fixed)
          local ar_r_cx = nav_shared_scx + bw - nav_dot_r + nav_ar_x_offset  -- R center X (flush right)
          local ar_s_cx = ar_r_cx - ar_d - ar_gap
          local ar_a_cx = ar_s_cx - ar_d - ar_gap
          local ar_cy = nav_shared_scy + math.floor(nav_single_row_h / 2)  -- center Y row 1, floored to match dot_cy convention

          local ar_font = GetSteppedFont(-1)

          -- Render A/S/R circle button at screen-space (cx, cy). Used by both
          -- fixed-position rendering (wide mode) and inline rendering (narrow
          -- mode where A/S/R appear as flow items in mini-circle layout).
          local DrawArButton = function(cx, cy, which)
              local mode_active = (which == "A" and active_view_active)
                  or (which == "S" and selected_view_active)
                  or (which == "R" and routing_view_active)
              local no_active_signal = which == "A"
                  and not active_view_active
                  and type(ActiveViewHasSignal) == "function"
                  and not ActiveViewHasSignal()
              local no_selected_selection = which == "S"
                  and not selected_view_active
                  and type(SelectedViewHasSelection) == "function"
                  and not SelectedViewHasSelection()
              local no_routing_selection = which == "R"
                  and not routing_view_active
                  and r.CountSelectedTracks(0) == 0
              local disabled = no_active_signal or no_selected_selection or no_routing_selection
              local state_col = (which == "A") and COL_AR_ACTIVE_RED
                  or (which == "S" and COL_AR_SELECTED_GREEN)
                  or COL_AR_ROUTING_BLUE
              if which == "A" and active_view_active then
                  local flash = NavActiveFlashAmount()
                  if flash > 0 then state_col = NavBrightenColor(state_col, flash) end
              end
              local btn_id = "##nav_" .. string.lower(which) .. "_btn"
              local draw_cy = cy
              r.ImGui_SetCursorScreenPos(ctx, cx - nav_dot_r, draw_cy - nav_single_row_h / 2)
              local bg_col = disabled and AR_DISABLED_BG or (mode_active and state_col or COL_AR_REST_BG)
              local hover_col = disabled and AR_DISABLED_BG or (mode_active and state_col or COL_AR_HOVER_BG)
              local active_col = disabled and AR_DISABLED_BG or state_col
              local hov, clk, held = NavCircle(btn_id, mini_tlf_h, nil, {
                  bg = bg_col,
                  hov = hover_col,
                  active = active_col,
                  hit_w = ar_d,
                  hit_h = nav_single_row_h,
              })
              local mods = NavClickMods()
              local nav_mods = NavMods(mods)
              local fg_col
              if disabled then
                  fg_col = AR_DISABLED_FG
              elseif mode_active or held then
                  fg_col = COL_AR_TEXT_ACTIVE
              elseif hov then
                  fg_col = state_col
              else
                  fg_col = COL_AR_TEXT_REST
              end
              local dl = r.ImGui_GetWindowDrawList(ctx)
              if not NavDrawArLabelImage(dl, cx, draw_cy, which, fg_col, mini_tlf_h) then
                  local ar_font_pushed = NavPushFont(ar_font)
                  local tw = r.ImGui_CalcTextSize(ctx, which)
                  local th = r.ImGui_GetTextLineHeight(ctx)
                  local nudge = AR_LABEL_TEXT_FALLBACK_NUDGE[which] or { x = 0, y = 0 }
                  local tx = cx - tw / 2 + nudge.x
                  local ty = draw_cy - th / 2 + nudge.y
                  r.ImGui_DrawList_AddText(dl, tx, ty, fg_col, which)
                  NavPopFont(ar_font_pushed)
              end
              if clk then
                  NavDebugEvent("A/S/R." .. which, {
                      mods = mods,
                      label = which,
                      item_active = r.ImGui_IsItemActive(ctx),
                      disabled = disabled,
                      state = mode_active and "active" or "inactive",
                  })
                  if disabled then
                      -- Disabled A/S/R still owns the hitbox, but does not enter
                      -- the view mode; hover tooltip explains why.
                  elseif which == "A" then
                      if active_view_active then
                          if nav_mods.pin then ActiveViewToggle()
                          else ActiveViewExit() end
                      else
                          ActiveViewToggle()
                      end
                  elseif which == "S" then
                      if selected_view_active then
                          if nav_mods.pin and SelectedViewRefreshFromSelection then SelectedViewRefreshFromSelection()
                          else SelectedViewToggle() end
                      else
                          SelectedViewToggle()
                      end
                  else
                      if routing_view_active then
                          if nav_mods.pin and RoutingViewRefreshFromSelection then RoutingViewRefreshFromSelection()
                          else RoutingViewToggle() end
                      else
                          RoutingViewToggle()
                      end
                  end
              end
              if hov then
                  if which == "A" then
                      if disabled then
                          NavArTooltip("Active tracks view", "No levels detected")
                      else
                          NavArTooltip("Active tracks view", active_view_active and ("Click: restore previous view\n" .. NavPinLabel() .. ": recalc active tracks") or nil)
                      end
                  elseif which == "S" then
                      NavArTooltip("Selected tracks view", disabled and "No track selection" or (selected_view_active and ("Click: restore previous view\n" .. NavPinLabel() .. ": recalc from selection") or nil))
                  else
                      NavArTooltip("Routing view", disabled and "No track selection" or (routing_view_active and ("Click: restore previous view\n" .. NavPinLabel() .. ": recalc from selection") or nil))
                  end
              end
          end

          local function NavAsrRowCenter(base_y, row)
              return base_y + math.floor(nav_single_row_h / 2) + (row - 1) * nav_single_row_h
          end

          local function NavAsrAddRow(placements, row, start_x, buttons)
              for i, which in ipairs(buttons) do
                  placements[#placements + 1] = {
                      which = which,
                      row = row,
                      cx = start_x + nav_dot_r + (i - 1) * (ar_d + ar_gap),
                  }
              end
          end

          local function NavAsrExpandedFlowLayout(start_x, max_x)
              local placements = {}
              if start_x + ar_reserved_w <= max_x then
                  NavAsrAddRow(placements, 2, start_x, ar_buttons)
                  return placements, 2
              elseif start_x + ar_pair_w <= max_x then
                  NavAsrAddRow(placements, 2, start_x, { "A" })
                  NavAsrAddRow(placements, 3, start_x, { "S", "R" })
                  return placements, 3
              end
              NavAsrAddRow(placements, 2, start_x, { "A" })
              NavAsrAddRow(placements, 3, start_x, { "S" })
              NavAsrAddRow(placements, 4, start_x, { "R" })
              return placements, 4
          end

          local function NavAsrCollapsedFlowLayout(first_x, wrap_x, max_x)
              local placements = {}
              if first_x + ar_reserved_w <= max_x then
                  NavAsrAddRow(placements, 1, first_x, ar_buttons)
                  return placements, 1, first_x + ar_reserved_w + ar_gap
              elseif wrap_x + ar_reserved_w <= max_x then
                  NavAsrAddRow(placements, 2, wrap_x, ar_buttons)
                  return placements, 2, wrap_x + ar_reserved_w + ar_gap
              elseif wrap_x + ar_pair_w <= max_x then
                  NavAsrAddRow(placements, 2, wrap_x, { "A" })
                  NavAsrAddRow(placements, 3, wrap_x, { "S", "R" })
                  return placements, 3, wrap_x + ar_pair_w + ar_gap
              end
              NavAsrAddRow(placements, 2, wrap_x, { "A" })
              NavAsrAddRow(placements, 3, wrap_x, { "S" })
              NavAsrAddRow(placements, 4, wrap_x, { "R" })
              return placements, 4, wrap_x + ar_d + ar_gap
          end

          -- Expanded mode's top header can grow when A/S/R have joined the dot
          -- flow and wrapped below row 1. Consumed by the cursor advance before
          -- the TLT pills.
          local nav_ar_flow_rows = 1
          local nav_render_expanded = navigator_expanded

          if nav_render_expanded then
              -- Custom header: a single_row_h-tall row with the down-arrow drawn
              -- at the exact same screen position the collapsed-state right-arrow
              -- uses. Visually the arrow rotates in place; row height stays
              -- constant across the toggle.
              local nav_cx_h, nav_cy_h = r.ImGui_GetCursorScreenPos(ctx)
              local dl_h = r.ImGui_GetWindowDrawList(ctx)

              local nav_arrow_hit = mini_tlf_h
              local nav_arrow_cx = nav_cx_h + nav_left_pad_shared + nav_dot_r + nav_header_x_offset
              local nav_arrow_cy = nav_cy_h + nav_single_row_h * 0.5
              r.ImGui_SetCursorScreenPos(ctx, nav_arrow_cx - nav_arrow_hit * 0.5, nav_arrow_cy - nav_arrow_hit * 0.5)
              r.ImGui_InvisibleButton(ctx, "##nav", nav_arrow_hit, nav_arrow_hit)
              local nav_clicked = r.ImGui_IsItemClicked(ctx, 0)
              local nav_rclicked = r.ImGui_IsItemClicked(ctx, 1)
              local nav_hovered = r.ImGui_IsItemHovered(ctx)
              if nav_hovered then nav_context_blocked = true end
              if nav_rclicked then
                  NavDebugEvent("NAV.global_popup.open", {
                      popup_id = "##navctx",
                      label = "expanded_header",
                      item_active = r.ImGui_IsItemActive(ctx),
                  })
                  NavOpenGlobalMenuAtMouse()
              end

              -- Draw down-arrow at the same (tx, ty) the collapsed view uses
              -- for its right-arrow. The down-glyph and right-glyph have
              -- different bounding-box asymmetry so they need different X
              -- nudges to land at the same optical center. Right-arrow uses
              -- -S(1.375) (1 logical px = ~2 retina px at 100% scale).
              -- Down-arrow needs ~2 more retina px of leftward nudge, so
              -- -S(2) total (2 logical px = ~3 retina px) lands the down-arrow
              -- one logical px further left than the right-arrow.
              local arrow_glyph_h = "\xE2\x96\xBC"
              local nav_arrow_font_pushed = NavPushFont(nav_arrow_font_shared)
              local arrow_gw_h = r.ImGui_CalcTextSize(ctx, arrow_glyph_h)
              local arrow_th_h = r.ImGui_GetTextLineHeight(ctx)
              local arrow_ty_h = nav_cy_h + Round((nav_single_row_h - arrow_th_h) / 2) - S(1.375)
              local arrow_tx_h = nav_cx_h + nav_left_pad_shared + Round((nav_arrow_area - arrow_gw_h) / 2) - S(2) + nav_header_x_offset
              local arrow_col_h = nav_hovered and C.text or COL_NAV_ARROW_REST
              r.ImGui_DrawList_AddText(dl_h, arrow_tx_h, arrow_ty_h, arrow_col_h, arrow_glyph_h)
              NavPopFont(nav_arrow_font_pushed)
              if nav_clicked then
                  local mods = NavClickMods()
                  local nav_mods = NavMods(mods)
                  NavDebugEvent("NAV.arr.expanded", {
                      mods = mods,
                      label = "header",
                      item_active = r.ImGui_IsItemActive(ctx),
                  })
                  if nav_mods.show_all then
                      ShowAllTracks()
                  elseif nav_mods.primary and not nav_mods.child_expand then
                      if current_page == "songs" then ShowAllSongsKeep() else ShowAllTLFs() end
                  elseif nav_mods.pin or nav_mods.child_expand then
                      -- Expand all visible tracks at every level
                      r.Undo_BeginBlock(); r.PreventUIRefresh(1)
                      local nt = r.CountTracks(0)
                      for ti = 0, nt - 1 do
                          local t = r.GetTrack(0, ti)
                          if r.GetMediaTrackInfo_Value(t, "B_SHOWINTCP") == 1
                             and r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH") == 1 then
                              r.SetMediaTrackInfo_Value(t, "I_FOLDERCOMPACT", 0)
                          end
                      end
                      r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
                      r.Undo_EndBlock("Track Navigator: Expand All Deep", 0)
                  elseif nav_mods.shift then
                      if current_page == "songs" then
                          r.Undo_BeginBlock(); r.PreventUIRefresh(1)
                          local all_c = true
                          for _, s in ipairs(song_entries) do
                              if r.GetMediaTrackInfo_Value(s.track, "B_SHOWINTCP") == 1 and s.is_folder
                                 and r.GetMediaTrackInfo_Value(s.track, "I_FOLDERCOMPACT") == 0 then all_c = false; break end
                          end
                          for _, s in ipairs(song_entries) do
                              if r.GetMediaTrackInfo_Value(s.track, "B_SHOWINTCP") == 1 and s.is_folder then
                                  r.SetMediaTrackInfo_Value(s.track, "I_FOLDERCOMPACT", all_c and 0 or 2)
                              end
                          end
                          r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
                          r.Undo_EndBlock("Track Navigator: Toggle Collapse Songs", 0)
                      else
                          ToggleCollapseAll()
                      end
                  else
                      navigator_expanded = false
                      SavePref("navigator_expanded", false)
                  end
              end
              if nav_hovered and opt_tooltips and opt_helper_tooltips ~= false then
                  ShowModKeyTip()
              end

              -- Expanded A/S/R wrap is grouped: fixed top-right while all
              -- three fit, then A/S/R on row 2, then A + S/R, then stacked.
              if not ar_fixed then
                  local flow_left = nav_cx_h + nav_left_pad_shared + nav_ar_x_offset
                  local placements, max_row = NavAsrExpandedFlowLayout(flow_left, nav_cx_h + bw)
                  for _, placement in ipairs(placements) do
                      DrawArButton(placement.cx, NavAsrRowCenter(nav_cy_h, placement.row), placement.which)
                  end
                  nav_ar_flow_rows = max_row
              end
          else
              -- Collapsed: arrow + mini TLT circles (flow layout). Each mini
              -- circle matches the fully-collapsed expanded-pill anatomy:
              -- dark charcoal outer disc (size = tlf_h diameter) + inner
              -- colored circle + pin overlay at center when pinned. Geometry
              -- (dot_r, arrow_area, single_row_h, nav_left_pad) reuses the
              -- shared values declared above so the arrow stays in the same
              -- screen position when toggling expanded/collapsed.
              local dot_r = nav_dot_r
              local dot_render_r = nav_dot_render_r  -- float radius for outer disc only; layout still uses integer dot_r
              local dot_inner_r = Round(S(9.03))  -- match expanded TLT circ_r
              local pin_overlay_r = Round(S(3.75))  -- match expanded TLT pin
              local dot_gap = nav_dot_gap
              -- Arrow occupies exactly one dot-step (nav_arrow_area), centered
              -- in column. Reuses shared geometry so collapsed/expanded states
              -- align identically.
              local arrow_area = nav_arrow_area
              local nav_left_pad = nav_left_pad_shared
              local single_row_h = nav_single_row_h
              local nav_sx = r.ImGui_GetCursorPosX(ctx)
              local nav_sy = r.ImGui_GetCursorPosY(ctx)
              local nav_cx, nav_cy = r.ImGui_GetCursorScreenPos(ctx)
              local dl = r.ImGui_GetWindowDrawList(ctx)

              -- Compute flow layout: how many rows needed.
              -- Row 1 col 0 = arrow; row 1 col 1+ = dots (start at +arrow_area).
              -- Rows 2+ col 0+ = dots (start at +0 from left margin, so col 0
              -- of row 2 sits directly under the arrow of row 1).
              local dot_start_x_first = nav_cx + nav_left_pad + arrow_area + nav_header_x_offset
              local dot_start_x_wrap = nav_cx + nav_left_pad + nav_header_x_offset
              -- Collapsed NAV treats A/S/R as one leading group, so the
              -- dot row uses the full width instead of reserving a top-right
              -- A/S/R zone.
              local max_dot_x = nav_cx + bw
              local asr_placements, asr_row, asr_next_x = NavAsrCollapsedFlowLayout(dot_start_x_first, dot_start_x_wrap, max_dot_x)
              local mini_items = {}
              for ri, item in ipairs(render_list) do
                  if item.kind == "folder" then mini_items[#mini_items + 1] = { kind = "tlf", ri = ri, item = item } end
              end
              local num_rows = asr_row
              do
                  local px = asr_next_x
                  for mi = 1, #mini_items do
                      -- Guard: only suppress wrap when we're already at row
                      -- start (otherwise an oversized arrow column would lock
                      -- the first dot to row 1 when it actually needs row 2).
                      if px + dot_r * 2 > max_dot_x and px > dot_start_x_wrap then
                          num_rows = num_rows + 1
                          px = dot_start_x_wrap
                      end
                      px = px + dot_r * 2 + dot_gap
                  end
              end
              local row_h = single_row_h * num_rows

              -- Arrow button (uses the SHARED arrow font so the glyph stays
              -- the same size when toggling expanded/collapsed).
              local arrow_font = nav_arrow_font_shared
              local arrow_hit = mini_tlf_h
              local arrow_cx = nav_cx + nav_left_pad + dot_r + nav_header_x_offset
              local arrow_cy = nav_cy + single_row_h * 0.5
              r.ImGui_SetCursorScreenPos(ctx, arrow_cx - arrow_hit * 0.5, arrow_cy - arrow_hit * 0.5)
              r.ImGui_InvisibleButton(ctx, "##navcol", arrow_hit, arrow_hit)
              local nav_col_clicked = r.ImGui_IsItemClicked(ctx, 0)
              local nav_col_rclicked = r.ImGui_IsItemClicked(ctx, 1)
              local arrow_hovered = r.ImGui_IsItemHovered(ctx)
              if arrow_hovered then nav_context_blocked = true end
              if nav_col_rclicked then
                  NavDebugEvent("NAV.global_popup.open", {
                      popup_id = "##navctx",
                      label = "collapsed_arrow",
                      item_active = r.ImGui_IsItemActive(ctx),
                  })
                  NavOpenGlobalMenuAtMouse()
              end
              if nav_col_clicked then
                  local mods = NavClickMods()
                  local nav_mods = NavMods(mods)
                  NavDebugEvent("NAV.arr.collapsed", {
                      mods = mods,
                      label = "arrow",
                      item_active = r.ImGui_IsItemActive(ctx),
                  })
                  if nav_mods.show_all then
                      ShowAllTracks()
                  elseif nav_mods.primary and not nav_mods.child_expand then
                      if current_page == "songs" then ShowAllSongsKeep() else ShowAllTLFs() end
                  elseif nav_mods.pin or nav_mods.child_expand then
                      r.Undo_BeginBlock(); r.PreventUIRefresh(1)
                      local nt = r.CountTracks(0)
                      for ti = 0, nt - 1 do
                          local t = r.GetTrack(0, ti)
                          if r.GetMediaTrackInfo_Value(t, "B_SHOWINTCP") == 1
                             and r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH") == 1 then
                              r.SetMediaTrackInfo_Value(t, "I_FOLDERCOMPACT", 0)
                          end
                      end
                      r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
                      r.Undo_EndBlock("Track Navigator: Expand All Deep", 0)
                  elseif nav_mods.shift then
                      if current_page == "songs" then
                          r.Undo_BeginBlock(); r.PreventUIRefresh(1)
                          local all_c = true
                          for _, s in ipairs(song_entries) do
                              if r.GetMediaTrackInfo_Value(s.track, "B_SHOWINTCP") == 1 and s.is_folder
                                 and r.GetMediaTrackInfo_Value(s.track, "I_FOLDERCOMPACT") == 0 then all_c = false; break end
                          end
                          for _, s in ipairs(song_entries) do
                              if r.GetMediaTrackInfo_Value(s.track, "B_SHOWINTCP") == 1 and s.is_folder then
                                  r.SetMediaTrackInfo_Value(s.track, "I_FOLDERCOMPACT", all_c and 0 or 2)
                              end
                          end
                          r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
                          r.Undo_EndBlock("Track Navigator: Toggle Collapse Songs", 0)
                      else
                          ToggleCollapseAll()
                      end
                  else
                      navigator_expanded = true
                      SavePref("navigator_expanded", true)
                  end
              end
              -- Draw arrow glyph at 148% size, white on hover. Centered in the
              -- arrow column (which is one dot-step wide) so it sits in the same
              -- column slot that wrapped-row dots will occupy below it.
              local arrow_font_pushed = NavPushFont(arrow_font)
              local arrow_glyph = "\xE2\x96\xB6"
              local arrow_gw = r.ImGui_CalcTextSize(ctx, arrow_glyph)
              local arrow_th = r.ImGui_GetTextLineHeight(ctx)
              -- 1 retina px nudge up + 1 retina px nudge left to optically align
              -- the arrow glyph with the dot column grid (the glyph's bounding
              -- box has asymmetric padding so geometric centering looks off).
              -- 1 retina px = S(1/1.6) per PK retina convention.
              local arrow_ty = nav_cy + Round((single_row_h - arrow_th) / 2) - S(1.375)
              local arrow_tx = nav_cx + nav_left_pad + Round((arrow_area - arrow_gw) / 2) - S(1.375) + nav_header_x_offset
              local arrow_col = arrow_hovered and C.text or COL_NAV_ARROW_REST
              r.ImGui_DrawList_AddText(dl, arrow_tx, arrow_ty, arrow_col, arrow_glyph)
              NavPopFont(arrow_font_pushed)

              for _, placement in ipairs(asr_placements) do
                  DrawArButton(placement.cx, NavAsrRowCenter(nav_cy, placement.row), placement.which)
              end

              -- Mini TLT circles (flow layout with wrapping; rows 2+ flow under arrow)
              local dot_x = asr_next_x
              local current_row = asr_row
              local dot_cy = NavAsrRowCenter(nav_cy, current_row)
              local mini_rclick = false
              for mi, md in ipairs(mini_items) do
                  -- Wrap to next row if needed. Same guard as the precount loop:
                  -- only suppress wrap when we're already at row start.
                  if dot_x + dot_r * 2 > max_dot_x and dot_x > dot_start_x_wrap then
                      current_row = current_row + 1
                      dot_x = dot_start_x_wrap
                      dot_cy = NavAsrRowCenter(nav_cy, current_row)
                  end
                  local item = md.item
                  local override_hex = track_color_overrides[item.label]
                  local base = override_hex and rgb(override_hex) or TrackColorToImGui(item.color)
                  local has_color = override_hex or item.color ~= 0
                  local vis = NavTlfVisible(item)
                  -- InvisibleButton FIRST so we know hover state before drawing
                  -- (color logic depends on hover, matching expanded TLT).
                  local hit_pad = S(3)
                  local hit_w = dot_r * 2 + hit_pad * 2
                  local circle_row_sy = nav_sy + (current_row - 1) * single_row_h
                  r.ImGui_SetCursorPos(ctx, nav_sx + (dot_x - nav_cx) - hit_pad, circle_row_sy)
                  r.ImGui_PushID(ctx, 9000 + mi)
                  r.ImGui_InvisibleButton(ctx, "##mini", hit_w, single_row_h)
                  local mini_raw_hov = r.ImGui_IsItemHovered(ctx)
                  if mini_raw_hov then nav_context_blocked = true end
                  local mini_hov = NavTlfHover(item, mini_raw_hov)
                  if r.ImGui_IsItemClicked(ctx, 0) then
                      local mods = NavClickMods()
                      local show_all, primary, shift, pin, child_expand = NavTrackClickMods(mods)
                      local was_visible = vis
                      NavDebugEvent("NAV.dot", {
                          mods = mods,
                          label = item.label,
                          item_active = r.ImGui_IsItemActive(ctx),
                      })
                      if show_all then
                          ShowAllTracks()
                      else
                          HandleTracksClick(md.ri, primary, shift, pin, child_expand)
                          NavMaybeSuppressTlfHover(item, was_visible, show_all, primary)
                      end
                      vis = NavTlfVisible(item)
                      mini_hov = NavTlfHover(item, mini_raw_hov)
                  end
                  if r.ImGui_IsItemClicked(ctx, 1) then
                      NavDebugEvent("NAV.dot.ctx.open", {
                          popup_id = "##tlfctx",
                          label = item.label,
                          item_active = r.ImGui_IsItemActive(ctx),
                      })
                      mini_rclick = true; remote_ctx_tlf_guid = r.GetTrackGUID(item.entry.track); remote_ctx_tlf_track = item.entry.track; remote_ctx_tlf_ghost_parent = item.ghost_parent; remote_ctx_tlf_custom = item.custom == true
                  end
                  if mini_hov then TipDirect(item.label) end

                  -- Match expanded TLT fade + color logic exactly. alpha applies
                  -- to the outer disc + base-color-masked circle uniformly.
                  local alpha = (vis or mini_hov) and 0xFF or 0x66
                  local outer_col = (C.bg & 0xFFFFFF00) | alpha
                  -- Default-color tracks (item.color == 0, no override) substitute
                  -- a medium grey as the "base" so they fade-with-alpha like
                  -- colored tracks do, instead of jumping to a totally different
                  -- darker hue when inactive. Active state stays the same grey;
                  -- inactive state becomes the same grey at 40% alpha.
                  local base_for_circ = has_color and base or 0x58616CFF
                  local circ_col
                  if vis and mini_hov then
                      circ_col = ScaleColor(base_for_circ, 1.2)
                  else
                      circ_col = (base_for_circ & 0xFFFFFF00) | alpha
                  end
                  -- Draw outer dark charcoal disc + inner colored circle.
                  -- Outer disc uses float radius (nav_dot_render_r = mini_tlf_h/2)
                  -- to preserve full diameter; layout still uses integer dot_r
                  -- for stable column/row offsets.
                  r.ImGui_DrawList_AddCircleFilled(dl, dot_x + dot_r, dot_cy, dot_render_r, outer_col, nav_circle_segments)
                  r.ImGui_DrawList_AddCircleFilled(dl, dot_x + dot_r, dot_cy, dot_inner_r, circ_col, nav_circle_segments)
                  -- Pinned indicator (C.bg punched through colored circle center,
                  -- matching expanded TLT collapsed-pill convention).
                  if PinnedTrack(item.entry.track) then
                      local pin_col = (C.bg & 0xFFFFFF00) | alpha
                      r.ImGui_DrawList_AddCircleFilled(dl, dot_x + dot_r, dot_cy, pin_overlay_r, pin_col, nav_circle_segments)
                  end
                  r.ImGui_PopID(ctx)
                  dot_x = dot_x + dot_r * 2 + dot_gap
              end
              if mini_rclick then r.ImGui_OpenPopup(ctx, "##tlfctx") end
              PushPopupStyle()
              if r.ImGui_BeginPopup(ctx, "##tlfctx") then
                  notePopupActive()
                  ReflexPushPopupLayout()
                  if remote_ctx_tlf_track and r.ValidatePtr(remote_ctx_tlf_track, "MediaTrack*") then
                      local _, tlf_name = r.GetTrackName(remote_ctx_tlf_track)
                      local has_sub_group = sub_group_by_name and sub_group_by_name[tlf_name] ~= nil
                      NavDrawTlfContextItems(remote_ctx_tlf_track, tlf_name, has_sub_group, remote_ctx_tlf_ghost_parent, remote_ctx_tlf_custom)
                  end
                  ReflexPopPopupLayout()
                  r.ImGui_EndPopup(ctx)
              end
              PopPopupStyle()
              if arrow_hovered and opt_tooltips and opt_helper_tooltips ~= false then
                  ShowModKeyTip()
              end
              -- Reset cursor below the row
              r.ImGui_SetCursorPos(ctx, nav_sx, nav_sy + row_h)
              -- Bottom edge of last NAV element in collapsed mode = nav_sy + row_h.
              nav_end_y = nav_sy + row_h
              nav_ctx_y2 = nav_cy + row_h
              last_nav_collapsed_visible_h = row_h
          end

          -- ── A/S/R nav buttons ──
          -- Expanded fixed mode: drawn at top-right of row 1 via DrawArButton.
          -- Collapsed NAV and expanded non-fixed modes draw A/S/R inline.
          if nav_render_expanded and ar_fixed then
              DrawArButton(ar_a_cx, ar_cy, "A")
              DrawArButton(ar_s_cx, ar_cy, "S")
              DrawArButton(ar_r_cx, ar_cy, "R")
          end

        if nav_render_expanded then

          -- Force cursor below the header/A/S/R flow rows. The explicit S(3.75)
          -- gap matches the expanded TLT inter-row spacing, so a wrapped A/S/R
          -- row and the first NAV.pill do not visually touch.
          local nav_body_y = nav_start_y + nav_single_row_h * nav_ar_flow_rows + S(3.75)
          r.ImGui_SetCursorPosY(ctx, nav_body_y)

          -- Make NAV's expanded list scrollable when it would otherwise push the
          -- inspector + remote off the bottom of the window. No ImGui scrollbar
          -- (NoScrollbar flag) - thin indicator drawn after EndChild matching
          -- the inspector pattern. Children resize naturally to interior width.
          local _bottom_used = vh_row_h + rem_h + (rem_h > 0 and divider_h or 0) + nav_bottom_extra
          local _nav_block_max_h = math.max(S(120), win_h - _bottom_used)
          local _nav_h
          if last_nav_natural_h and last_nav_natural_h > 0 then
              _nav_h = math.min(last_nav_natural_h, _nav_block_max_h)
          else
              _nav_h = _nav_block_max_h
          end

          r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
          if nav_body_x_offset ~= 0 then
              r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + nav_body_x_offset)
          end

          -- Standalone callers pass a width already adjusted for their current
          -- chrome: docked keeps the REAPER edge blend, floating keeps the
          -- standard left/right window padding.
          local _nav_child_visible = r.ImGui_BeginChild(ctx, "##nav_scroll", bw - nav_body_x_offset, _nav_h, 0, r.ImGui_WindowFlags_NoScrollbar())
          if _nav_child_visible then
              local _nav_child_y0 = r.ImGui_GetCursorPosY(ctx)
              -- Use child's interior width so rows aren't clipped by any scrollbar
              -- artifact and resize naturally.
              bw = r.ImGui_GetContentRegionAvail(ctx)

          r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), S(6))
          r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), S(12), S(BASE_PAD_Y))
        if current_page == "tracks" then
          -- TLT rows: 85% scale font, 6px retina row spacing
          local tlf_font_step = math.max(5, math.min(20, Round(GetFontStep(0) * 0.85)))
          local tlf_font = scaled_fonts[tlf_font_step]
          local tlf_font_pushed = NavPushFont(tlf_font)
          r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 0, Round(S(3.75)))
          local tlf_h = S(34)  -- 54.4px retina (64 * 0.85)
          local tlf_r = math.floor(tlf_h / 2)  -- full pill endcap rounding
          local circ_r = Round(S(9.03))  -- 28.9px retina diameter (34 * 0.85)
          local circ_gap = Round(S(9.56))  -- 15.3px retina gap (18 * 0.85)
          local pin_dot_r = S(4)
          local pin_collide_threshold = tlf_h + pin_dot_r + circ_r + S(7.5)
          local pill_collapsed = bw <= pin_collide_threshold
          local pill_w = pill_collapsed and tlf_h or bw
          local function NavTlfTextAnchors(row_cx, has_arrow, has_pin)
              local text_left_anchor, text_right_anchor
              if nav_mirror then
                  local _circ_cx_pre = row_cx + tlf_h * 0.5
                  text_left_anchor = _circ_cx_pre + circ_r + circ_gap
                  if has_arrow then text_left_anchor = text_left_anchor + arrow_w end
                  if has_pin then
                      text_right_anchor = row_cx + pill_w - tlf_h * 0.5 - pin_dot_r - circ_gap
                  else
                      text_right_anchor = row_cx + pill_w - circ_gap
                  end
              else
                  local _circ_cx_pre = row_cx + pill_w - tlf_h * 0.5
                  text_right_anchor = _circ_cx_pre - circ_r - circ_gap
                  if has_arrow then text_right_anchor = text_right_anchor - arrow_w end
                  if has_pin then
                      text_left_anchor = row_cx + tlf_h * 0.5 + pin_dot_r + circ_gap
                  else
                      text_left_anchor = row_cx + circ_gap
                  end
              end
              return text_left_anchor, text_right_anchor
          end
          local function NavTlfFitCharCount(label, available_text_w)
              label = label or ""
              local full_count = NavUtf8CharCount(label)
              if full_count == 0 then return 0, false end
              if available_text_w <= 0 then return 0, true end
              if r.ImGui_CalcTextSize(ctx, label) <= available_text_w then
                  return full_count, false
              end
              local candidate = label
              local count = full_count
              while count > 0 do
                  candidate = Utf8DropLast(candidate)
                  count = count - 1
                  if r.ImGui_CalcTextSize(ctx, candidate) <= available_text_w then
                      return count, true
                  end
              end
              return 0, true
          end
          local shared_label_char_limit = nil
          for _, item in ipairs(render_list) do
              local sg = item.kind == "folder" and item.sub_group or nil
              local has_arrow = sg and #sg.entries > 0
              local has_pin = item.kind == "folder" and PinnedTrack(item.entry.track)
              local text_left_anchor, text_right_anchor = NavTlfTextAnchors(0, has_arrow, has_pin)
              local count, clipped = NavTlfFitCharCount(item.label, text_right_anchor - text_left_anchor)
              if clipped then
                  shared_label_char_limit = shared_label_char_limit and math.min(shared_label_char_limit, count) or count
              end
          end
          for ri, item in ipairs(render_list) do
              -- Theme override: check nav_theme track_colors by label
              local override_hex = track_color_overrides[item.label]
              local base = override_hex and rgb(override_hex) or TrackColorToImGui(item.color)
              local has_color = override_hex or item.color ~= 0
              local sg = item.kind == "folder" and item.sub_group or nil
              local vis = NavTlfVisible(item)
              -- TLT pill row (custom draw, 85% scale)

              local row_cx, row_cy = r.ImGui_GetCursorScreenPos(ctx)
              local dl = r.ImGui_GetWindowDrawList(ctx)

              -- Pill collapse rule: when bw shrinks enough that the pin endcap
              -- dot would be within 12 retina px (= S(7.5) at 100%) of the
              -- colored circle, snap the entire pill to a circle (dark charcoal
              -- container, colored circle, pin overlay all concentrically
              -- aligned). Avoids the awkward zone where pin and circle overlap
              -- but the pill is still drawn as a stadium. Above the threshold,
              -- pill_w follows bw normally.

              -- Opacity: 40% when inactive, 100% when visible or hovered
              r.ImGui_InvisibleButton(ctx, "##tlf" .. ri, bw, tlf_h)
              local tlf_raw_hov = r.ImGui_IsItemHovered(ctx)
              if tlf_raw_hov then nav_context_blocked = true end
              local tlf_hov = NavTlfHover(item, tlf_raw_hov)
              local alpha = (vis or tlf_hov) and 0xFF or 0x66

              local clicked_main = r.ImGui_IsItemClicked(ctx, 0)
              local tlf_rclicked = r.ImGui_IsItemClicked(ctx, 1)

              -- Pre-compute label clipping so click handling matches what's drawn:
              -- truncate end-of-name (no ellipsis - every character of identifying
              -- info matters in narrow pills); drop text entirely when no chars
              -- fit (just the colored circle in the dark pill).
              -- Two layouts via nav_mirror: default = [pin|text|arrow?|circle]
              -- (text right-aligned), mirror = [circle|arrow?|text|pin] (text
              -- left-aligned). Width math is symmetric; only the anchor flips.
              local has_arrow = sg and #sg.entries > 0
              -- Pin reserves only its own dot + a circ_gap breathing room past
              -- the endcap center, not the full endcap width. Unpinned tracks
              -- (and sub_children, which never pin) reserve only circ_gap from
              -- the pill edge so text can extend across most of the pill body.
              -- Old behavior reserved the full tlf_h endcap on the pin side
              -- regardless of pin state, wasting ~17 logical px of label space.
              local has_pin = item.kind == "folder" and PinnedTrack(item.entry.track)
              local text_left_anchor, text_right_anchor = NavTlfTextAnchors(row_cx, has_arrow, has_pin)
              local available_text_w = text_right_anchor - text_left_anchor
              local display_label = item.label
              local label_clipped = false
              local clipped_tw = r.ImGui_CalcTextSize(ctx, display_label)
              if shared_label_char_limit ~= nil then
                  label_clipped = NavUtf8CharCount(item.label) > shared_label_char_limit
                  display_label = NavUtf8Prefix(item.label, shared_label_char_limit)
                  if display_label == "" then
                      display_label = nil
                      clipped_tw = 0
                  else
                      clipped_tw = r.ImGui_CalcTextSize(ctx, display_label)
                  end
              elseif clipped_tw > available_text_w then
                  label_clipped = true
                  local s = item.label
                  while #s > 0 do
                      local sw = r.ImGui_CalcTextSize(ctx, s)
                      if sw <= available_text_w then break end
                      s = Utf8DropLast(s)
                  end
                  if #s == 0 then
                      display_label = nil
                  else
                      display_label = s
                      clipped_tw = r.ImGui_CalcTextSize(ctx, display_label)
                  end
              end

              -- Arrow click detection for sub-groups. Keep the hit target to a
              -- square centered on the drawn arrow slot, instead of the whole
              -- side strip, so narrow scaling states don't steal pill clicks.
              local arrow_clicked = false
              if has_arrow and display_label and clicked_main then
                  local mx, my = r.ImGui_GetMousePos(ctx)
                  local arrow_hit = math.min(tlf_h, math.max(S(14), arrow_w))
                  local arrow_cx
                  if nav_mirror then
                      arrow_cx = text_left_anchor - arrow_w * 0.5
                  else
                      arrow_cx = text_right_anchor + arrow_w * 0.5
                  end
                  local arrow_cy = row_cy + tlf_h * 0.5
                  local half_hit = arrow_hit * 0.5
                  local in_arrow_region = mx >= arrow_cx - half_hit
                      and mx <= arrow_cx + half_hit
                      and my >= arrow_cy - half_hit
                      and my <= arrow_cy + half_hit
                  if in_arrow_region then
                      arrow_clicked = true
                      clicked_main = false
                  end
              end

              -- Pill background
              local pill_bg = (C.bg & 0xFFFFFF00) | alpha
              local mid_y = row_cy + tlf_h * 0.5
              local collapsed_cx = row_cx + tlf_h * 0.5
              local collapsed_clip_pushed = false
              if pill_collapsed then
                  if r.ImGui_DrawList_PushClipRect and r.ImGui_DrawList_PopClipRect then
                      r.ImGui_DrawList_PushClipRect(dl, row_cx, row_cy, row_cx + tlf_h, row_cy + tlf_h, false)
                      collapsed_clip_pushed = true
                  end
                  r.ImGui_DrawList_AddCircleFilled(dl, collapsed_cx, mid_y, tlf_h * 0.5, pill_bg, nav_circle_segments)
              else
                  local cap_r = tlf_h * 0.5
                  if r.ImGui_DrawList_PathClear and r.ImGui_DrawList_PathArcTo and r.ImGui_DrawList_PathFillConvex then
                      local pi = math.pi
                      local segs = math.max(12, math.floor(nav_circle_segments / 2))
                      r.ImGui_DrawList_PathClear(dl)
                      r.ImGui_DrawList_PathArcTo(dl, row_cx + cap_r, mid_y, cap_r, pi * 0.5, pi * 1.5, segs)
                      r.ImGui_DrawList_PathArcTo(dl, row_cx + pill_w - cap_r, mid_y, cap_r, pi * 1.5, pi * 2.5, segs)
                      r.ImGui_DrawList_PathFillConvex(dl, pill_bg)
                  else
                      r.ImGui_DrawList_AddRectFilled(dl, row_cx, row_cy, row_cx + pill_w, row_cy + tlf_h, pill_bg, tlf_r)
                  end
              end

              -- Colored circle (left endcap when mirror, right endcap otherwise).
              local circ_cx
              if pill_collapsed then
                  circ_cx = collapsed_cx
              elseif nav_mirror then
                  circ_cx = row_cx + tlf_h * 0.5
              else
                  circ_cx = row_cx + pill_w - tlf_h * 0.5
              end
              local circ_col
              -- Default-color tracks substitute a medium grey base so they fade
              -- via alpha like colored tracks (instead of switching to a
              -- different darker hue when inactive). See mini-circle path for
              -- matching logic.
              local base_for_circ = has_color and base or 0x58616CFF
              if vis and tlf_hov then
                  circ_col = ScaleColor(base_for_circ, 1.2)
              else
                  circ_col = (base_for_circ & 0xFFFFFF00) | alpha
              end
              r.ImGui_DrawList_AddCircleFilled(dl, circ_cx, mid_y, circ_r, circ_col, nav_circle_segments)

              -- TLT name text. Right-aligned by default; left-aligned in mirror.
              -- Already clipped above; nil display_label means show no text.
              local text_h = r.ImGui_GetTextLineHeight(ctx)
              local text_y = row_cy + Round((tlf_h - text_h) / 2)
              if display_label then
                  local text_col = (0xD1D6DBFF & 0xFFFFFF00) | alpha
                  local text_x
                  if nav_mirror then
                      text_x = text_left_anchor
                  else
                      text_x = text_right_anchor - clipped_tw
                  end
                  r.ImGui_DrawList_AddText(dl, text_x, text_y, text_col, display_label)
              end

              -- Sub-group expand arrow. Default: between text and circle (right
              -- side). Mirror: between circle and text (left side). Suppressed
              -- with text.
              if has_arrow and display_label then
                  local arrow = sg.ui_expanded and "\xE2\x96\xBC" or "\xE2\x96\xB6"
                  local arrow_col = (C.text_dim & 0xFFFFFF00) | alpha
                  local aw = r.ImGui_CalcTextSize(ctx, arrow)
                  local ax
                  if nav_mirror then
                      ax = text_left_anchor - arrow_w + Round((arrow_w - aw) / 2)
                  else
                      ax = text_right_anchor + Round((arrow_w - aw) / 2)
                  end
                  r.ImGui_DrawList_AddText(dl, ax, text_y, arrow_col, arrow)

                  if arrow_clicked then
                      local new_state = not sg.ui_expanded
                      local mods = NavClickMods()
                      local nav_mods = NavMods(mods)
                      NavDebugEvent("NAV.pill.sg_arrow", {
                          mods = mods,
                          label = item.label,
                          item_active = r.ImGui_IsItemActive(ctx),
                          state = new_state and "expand" or "collapse",
                      })
                      if nav_mods.pin then
                          for _, s in ipairs(sub_groups) do
                              if #s.entries > 0 then
                                  s.ui_expanded = new_state; SavePref(MakePrefKey(s.parent_name), new_state)
                              end
                          end
                          if #songs_sub.entries > 0 then
                              songs_sub.ui_expanded = new_state; SavePref(MakePrefKey(songs_sub.parent_name), new_state)
                          end
                      else
                          sg.ui_expanded = new_state; SavePref(MakePrefKey(sg.parent_name), new_state)
                      end
                      BuildRenderList()
                  end
              end

              -- Pin indicator. When pill is at full size: large amber dot at
              -- the opposite endcap from the colored circle. When pill_collapsed:
              -- small black dot overlaid on the colored circle's center,
              -- matching the compressed mini-circle pin convention.
              -- (pin_dot_r already declared above for the collapse-threshold math.)
              if item.kind == "folder" and PinnedTrack(item.entry.track) then
                  if pill_collapsed then
                      -- Use C.bg (dark charcoal of the outer pill container)
                      -- so the pin reads as concentric with the pill bg, not
                      -- as a separate grey blob inside the colored circle.
                      local pin_col = (C.bg & 0xFFFFFF00) | alpha
                      r.ImGui_DrawList_AddCircleFilled(dl, circ_cx, mid_y, Round(S(3.75)), pin_col, nav_circle_segments)
                  else
                      local pin_x
                      if nav_mirror then
                          pin_x = row_cx + pill_w - tlf_h * 0.5
                      else
                          pin_x = row_cx + tlf_h * 0.5
                      end
                      local pin_y = mid_y
                      local pin_col = (C.amber & 0xFFFFFF00) | alpha
                      r.ImGui_DrawList_AddCircleFilled(dl, pin_x, pin_y, pin_dot_r, pin_col, nav_circle_segments)
                  end
              end
              if collapsed_clip_pushed then
                  r.ImGui_DrawList_PopClipRect(dl)
              end

              if tlf_hov and item.kind == "folder" and opt_tooltips then
                  if opt_helper_tooltips == false then
                      if NavTlfNameTooltipNeeded(display_label, label_clipped) then
                          TipDirect(item.label)
                      end
                  else
                      PushTooltipStyle()
                      r.ImGui_BeginTooltip(ctx)
                      r.ImGui_Text(ctx, item.label)
                      r.ImGui_Separator(ctx)
                      r.ImGui_TextColored(ctx, C.text_dim, NavPrimaryLabel() .. ": add/remove from view")
                      if item.custom then
                          r.ImGui_TextColored(ctx, C.text_dim, NavPinLabel() .. ": expand all")
                          r.ImGui_TextColored(ctx, C.text_dim, "Right-click: hide in Track Navigator")
                      else
                          r.ImGui_TextColored(ctx, C.text_dim, NavPinLabel() .. ": toggle pin")
                      end
                      r.ImGui_TextColored(ctx, C.text_dim, NavChildExpandLabel() .. ": expand/collapse children")
                      r.ImGui_TextColored(ctx, C.text_dim, "Shift: range select")
                      r.ImGui_EndTooltip(ctx)
                      PopTooltipStyle()
                  end
              end

              -- TLT right-click menu
              if tlf_rclicked and item.kind == "folder" then
                  NavDebugEvent("NAV.pill.ctx.open", {
                      popup_id = "##tlfctx" .. ri,
                      label = item.label,
                      item_active = r.ImGui_IsItemActive(ctx),
                  })
                  r.ImGui_OpenPopup(ctx, "##tlfctx" .. ri)
              end
              PushPopupStyle()
              if r.ImGui_BeginPopup(ctx, "##tlfctx" .. ri) then
                  notePopupActive()
                  ReflexPushPopupLayout()
                  NavDrawTlfContextItems(item.entry.track, item.entry.name, item.sub_group ~= nil, item.ghost_parent, item.custom == true)
                  ReflexPopPopupLayout()
                  r.ImGui_EndPopup(ctx)
              end
              PopPopupStyle()

              if clicked_main then
                  local mods = NavClickMods()
                  local show_all, primary, shift, pin, child_expand = NavTrackClickMods(mods)
                  local was_visible = vis
                  NavDebugEvent("NAV.pill", {
                      mods = mods,
                      label = item.label,
                      item_active = r.ImGui_IsItemActive(ctx),
                  })
                  if show_all then
                      ShowAllTracks()
                  else
                      HandleTracksClick(ri, primary, shift, pin, child_expand)
                      NavMaybeSuppressTlfHover(item, was_visible, show_all, primary)
                  end
              end
          end
          r.ImGui_PopStyleVar(ctx, 1)  -- ItemSpacing
          NavPopFont(tlf_font_pushed)

          if opt_viewlock and viewlock_song ~= "" then
              r.ImGui_Spacing(ctx)
              r.ImGui_TextColored(ctx, C.amber, "View Lock: " .. viewlock_song)
          end

        elseif current_page == "songs" then
          if needs_song_rescan then ScanSongs() end
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.btn_bg)
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), C.btn_hover)
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), C.btn_active)
          r.ImGui_SetNextItemWidth(ctx, bw)
          local _cs; _cs, song_search = r.ImGui_InputTextWithHint(ctx, "##ss", "Search songs...", song_search)
          r.ImGui_PopStyleColor(ctx, 3)
          r.ImGui_Spacing(ctx)

          local filter = song_search:lower()
          local filtered = {}
          for _, s in ipairs(song_entries) do
              if filter == "" or s.name:lower():find(filter, 1, true) then filtered[#filtered+1] = s end
          end

          local sp_vis_bg  = ntc("songs_page", "visible_bg",    0x1E2228FF)
          local sp_vis_hov = ntc("songs_page", "visible_hover", 0x282E36FF)
          local sp_hid_bg  = ntc("songs_page", "hidden_bg",     0x13161BFF)
          local sp_hid_hov = ntc("songs_page", "hidden_hover",  0x1A1E24FF)

          for fi, song in ipairs(filtered) do
              local vis = r.GetMediaTrackInfo_Value(song.track, "B_SHOWINTCP") == 1
              local nbg = vis and sp_vis_bg or sp_hid_bg
              local nhov = vis and sp_vis_hov or sp_hid_hov
              local ntxt = vis and C.text or 0xFFFFFF66
              if StyledButton(song.name .. "##sf" .. fi, bw, bh, nbg, nhov, C.btn_active, ntxt) then
                  local mods = NavClickMods()
                  local nav_mods = NavMods(mods)
                  NavDebugEvent("songs.row", {
                      mods = mods,
                      label = song.name,
                      item_active = r.ImGui_IsItemActive(ctx),
                      state = vis and "visible" or "hidden",
                  })
                  HandleSongsClick(filtered, fi,
                      nav_mods.primary,
                      nav_mods.shift,
                      nav_mods.pin)
              end
          end
        end -- if/elseif page
          r.ImGui_PopStyleVar(ctx, 2)

              last_nav_natural_h = r.ImGui_GetCursorPosY(ctx) - _nav_child_y0
              last_nav_expanded_visible_h = (nav_body_y - nav_start_y) + last_nav_natural_h
              r.ImGui_EndChild(ctx)
          end
          r.ImGui_PopStyleVar(ctx, 1)

          if _nav_child_visible then
              local _, _iy1 = r.ImGui_GetItemRectMin(ctx)
              local _, _iy2 = r.ImGui_GetItemRectMax(ctx)
              nav_ctx_y2 = _iy2
          end
          -- Bottom edge of last NAV element in expanded mode = TLT body top
          -- (after header/A/S/R flow rows) + body child height.
          nav_end_y = nav_body_y + _nav_h
          if nav_ctx_y2 <= nav_ctx_y1 then
              nav_ctx_y2 = nav_ctx_y1 + (nav_end_y - nav_start_y)
          end
        end -- nav_render_expanded

          if r.ImGui_IsMouseClicked(ctx, 1) and not nav_context_blocked then
              local mx, my = r.ImGui_GetMousePos(ctx)
              local in_context_scope = false
              if nav_context_scope == "window" then
                  in_context_scope = r.ImGui_IsWindowHovered(ctx, r.ImGui_HoveredFlags_RootAndChildWindows())
              else
                  in_context_scope = mx >= nav_ctx_x1 and mx <= nav_ctx_x2 and my >= nav_ctx_y1 and my <= nav_ctx_y2
              end
              if in_context_scope then
                  NavDebugEvent("NAV.global_popup.open", {
                      popup_id = "##navctx",
                      label = "background",
                  })
                  NavOpenGlobalMenuAtMouse()
              end
          end
          if nav_open_global_menu then
              NavOpenGlobalMenuAtMouse()
              nav_open_global_menu = false
          end
          NavDrawMainContextPopup()

        end -- nav_visible

          -- Nav bottom margin: position cursor S(UI.edge_pad) below NAV's
          -- bottom edge to provide the standard 16-retina gap to the first
          -- card, consistently in both expanded and collapsed states.
          local nav_bottom_y
          if nav_visible then
              nav_bottom_y = nav_end_y + S(UI.edge_pad / 2)
          else
              nav_bottom_y = r.ImGui_GetCursorPosY(ctx) + 1
          end
          r.ImGui_SetCursorPosY(ctx, nav_bottom_y)
          local nav_total_h = nav_bottom_y - nav_start_y
          r.ImGui_Dummy(ctx, 1, 1)
          last_nav_h = nav_total_h
    end
end

return ReflexInstallNavViewCore
