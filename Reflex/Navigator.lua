-- @noindex
--[[
 * Description: Standalone Navigator section for Reflex.
 *              Top NAV visibility manager only.
 * Author:      S.Hansen / Tycho
 * Version:     20.673
--]]

local r = reaper
NAVIGATOR_VERSION = "20.673"

NavigatorDependencyError = function(detail)
    local msg = "Navigator requires ReaImGui 0.10 or newer."
    if detail and detail ~= "" then msg = msg .. "\n\n" .. tostring(detail) end
    if r.ReaPack_BrowsePackages then
        local choice = r.MB(msg .. "\n\nOpen ReaPack package browser for ReaImGui?", "Navigator: Missing dependency", 4)
        if choice == 6 then r.ReaPack_BrowsePackages("ReaImGui") end
    else
        r.MB(msg .. "\n\nInstall ReaImGui via ReaPack, then run Navigator again.", "Navigator: Missing dependency", 0)
    end
end

local imgui_api = r.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua'
local imgui_loader, imgui_load_err = loadfile(imgui_api)
if not imgui_loader then
    NavigatorDependencyError(imgui_load_err)
    return
end

local imgui_ok, imgui_err = pcall(function() imgui_loader('0.10') end)
if not imgui_ok or not r.ImGui_CreateContext then
    NavigatorDependencyError(imgui_err)
    return
end

local ctx = r.ImGui_CreateContext("Navigator")

NavigatorSetImGuiConfigBool = function(name, value)
    if not (r.ImGui_SetConfigVar and r["ImGui_ConfigVar_" .. name]) then return end
    local ok_var, var = pcall(r["ImGui_ConfigVar_" .. name])
    if ok_var and type(var) == "number" then
        pcall(r.ImGui_SetConfigVar, ctx, var, value and 1 or 0)
    end
end

NavigatorSetImGuiConfigFlag = function(name, enabled)
    if not (r.ImGui_GetConfigVar and r.ImGui_SetConfigVar
        and r.ImGui_ConfigVar_Flags and r["ImGui_ConfigFlags_" .. name]) then
        return
    end
    local ok_var, flags_var = pcall(r.ImGui_ConfigVar_Flags)
    local ok_flag, flag = pcall(r["ImGui_ConfigFlags_" .. name])
    if not ok_var or not ok_flag or type(flag) ~= "number" then return end
    local ok_flags, flags = pcall(r.ImGui_GetConfigVar, ctx, flags_var)
    if not ok_flags or type(flags) ~= "number" then return end
    flags = math.floor(flags)
    local next_flags = enabled and (flags | flag) or (flags & ~flag)
    if next_flags ~= flags then
        pcall(r.ImGui_SetConfigVar, ctx, flags_var, next_flags)
    end
end

NavigatorSetImGuiConfigBool("NavEscapeClearFocusWindow", false)
NavigatorSetImGuiConfigFlag("NavEnableKeyboard", false)

local script_dir = debug.getinfo(1, 'S').source:match('@?(.*[/\\])') or ''
package.path = script_dir .. 'core/?.lua;' .. script_dir .. '?.lua;' .. package.path

local nav_theme = {
    fonts = {
        body_size = 14,
        family = "SF Pro",
    },
    colors = {
        fx_instr_txt = 0x324bd0,
        vol_slider_fill = 0x08a5f7,
        vol_slider_mark = 0x3e454b,
        vol_slider_mark_over = 0x82baf7,
        vol_slider_mark_intersect = 0xb9b9b9,
    },
    track_colors = {},
    remote_colors = {
        0x3B82F6,
        0x3FB950,
        0xD29922,
        0xF85149,
        0xBF40BF,
        0x58A6FF,
    },
    button_brightness = {
        visible = 0.65,
        visible_hover = 0.80,
        visible_active = 0.55,
        hidden = 0.25,
        hidden_hover = 0.35,
        hidden_active = 0.20,
    },
    songs_page = {},
}

local C

rgb = function(hex) return (hex << 8) | 0xFF end
ntc = function(section, key, fallback)
    local s = nav_theme[section]
    if s and s[key] then return rgb(s[key]) end
    return fallback
end

NavigatorKeyValue = function(name)
    local v = r[name]
    if type(v) == "function" then
        local ok, key = pcall(v)
        if ok and type(key) == "number" then return key end
    elseif type(v) == "number" then
        return v
    end
    return nil
end

NavigatorIsMacOS = function()
    local os = r.GetOS and r.GetOS() or ""
    return os:find("OSX", 1, true) ~= nil
        or os:find("macOS", 1, true) ~= nil
        or os:find("Mac", 1, true) ~= nil
end

NavigatorReaperThemeName = function()
    if not r.GetLastColorThemeFile then return nil end
    local ok, path = pcall(r.GetLastColorThemeFile)
    if not ok or type(path) ~= "string" or path == "" then return nil end
    local name = path:match("([^/\\]+)$") or path
    name = name:gsub("%.ReaperThemeZip$", ""):gsub("%.ReaperTheme$", "")
    return name
end

NavigatorIsReapertipsTheme = function()
    local name = NavigatorReaperThemeName()
    if not name then return false end
    return name:lower():find("reapertips", 1, true) ~= nil
end

NavigatorModFlag = function(mods, fallback, ...)
    mods = tonumber(mods) or 0
    if fallback and (mods & fallback) ~= 0 then return true end
    for i = 1, select("#", ...) do
        local key = NavigatorKeyValue(select(i, ...))
        if key and (mods & key) ~= 0 then return true end
    end
    return false
end

NavigatorKeyDown = function(...)
    if not r.ImGui_IsKeyDown then return false end
    for i = 1, select("#", ...) do
        local key = NavigatorKeyValue(select(i, ...))
        if key then
            local ok_down, down = pcall(r.ImGui_IsKeyDown, ctx, key)
            if ok_down and down == true then return true end
        end
    end
    return false
end

IsCmd = function(mods)
    return NavigatorModFlag(mods, 0x8, "ImGui_Mod_Super", "ImGui_Mod_Shortcut", "ImGui_KeyModFlags_Super")
        or NavigatorKeyDown("ImGui_Key_ModSuper", "ImGui_Key_LeftSuper", "ImGui_Key_RightSuper")
end

IsShift = function(mods)
    return NavigatorModFlag(mods, 0x2, "ImGui_Mod_Shift", "ImGui_KeyModFlags_Shift")
        or NavigatorKeyDown("ImGui_Key_ModShift", "ImGui_Key_LeftShift", "ImGui_Key_RightShift")
end

IsAlt = function(mods)
    return NavigatorModFlag(mods, 0x4, "ImGui_Mod_Alt", "ImGui_KeyModFlags_Alt")
        or NavigatorKeyDown("ImGui_Key_ModAlt", "ImGui_Key_LeftAlt", "ImGui_Key_RightAlt")
end

IsCtrl = function(mods)
    return NavigatorModFlag(mods, 0x1, "ImGui_Mod_Ctrl", "ImGui_KeyModFlags_Ctrl")
        or NavigatorKeyDown("ImGui_Key_ModCtrl", "ImGui_Key_LeftCtrl", "ImGui_Key_RightCtrl")
end

NavigatorMacPrimaryAlias = function(mods)
    return NavigatorIsMacOS()
        and NavigatorModFlag(mods, 0x1000, "ImGui_Key_ModCtrl")
end

TrackNavigatorModState = function(mods)
    mods = tonumber(mods) or 0
    local ctrl = IsCtrl(mods)
    local cmd_alias = NavigatorMacPrimaryAlias(mods)
    local cmd = IsCmd(mods) or cmd_alias
    return {
        raw = mods,
        cmd = cmd,
        shift = IsShift(mods),
        alt = IsAlt(mods),
        ctrl = ctrl and not cmd_alias,
    }
end

TrackNavigatorEscapePressed = function()
    if not (r.ImGui_IsKeyPressed and r.ImGui_Key_Escape) then return false end
    local ok_key, key = pcall(r.ImGui_Key_Escape)
    if not ok_key then return false end
    local ok_pressed, pressed = pcall(r.ImGui_IsKeyPressed, ctx, key)
    return ok_pressed and pressed == true
end

NAV_DIAG_ENABLED = true
NAV_DIAG_MAX_LINES = 8
nav_diag_events = {}
nav_diag_seq = 0
nav_diag_log_header = false
nav_diag_log_path = script_dir .. "navigator_keyboard_diag.log"
nav_diag_last_capture = {
    policy = "not-called",
    api = false,
    active = false,
    requested = false,
    applied = false,
}

NavDiagBool = function(v)
    return v and "true" or "false"
end

NavDiagOS = function()
    if r.GetOS then
        local ok, os = pcall(r.GetOS)
        if ok and os then return tostring(os) end
    end
    return "?"
end

NavDiagIsMac = function(os)
    os = tostring(os or NavDiagOS()):lower()
    return os:find("osx", 1, true) ~= nil
        or os:find("mac", 1, true) ~= nil
        or os:find("darwin", 1, true) ~= nil
end

NavDiagPlatform = function(os, mods)
    os = os or NavDiagOS()
    mods = mods or 0
    local is_mac = NavDiagIsMac(os)
    local primary_name = is_mac and "Cmd" or "Ctrl"
    local primary_down = is_mac and IsCmd(mods) or IsCtrl(mods)
    local deep_name = is_mac and "Ctrl" or "Ctrl+Alt"
    local deep_down = is_mac and IsCtrl(mods) or (IsCtrl(mods) and IsAlt(mods))
    return primary_name, primary_down, deep_name, deep_down
end

NavDiagModsString = function(mods)
    mods = tonumber(mods) or 0
    local os = NavDiagOS()
    local primary_name, primary_down, deep_name, deep_down = NavDiagPlatform(os, mods)
    return string.format(
        "cmd=%s ctrl=%s shift=%s alt=%s primary=%s:%s deep=%s:%s",
        NavDiagBool(IsCmd(mods)),
        NavDiagBool(IsCtrl(mods)),
        NavDiagBool(IsShift(mods)),
        NavDiagBool(IsAlt(mods)),
        primary_name,
        NavDiagBool(primary_down),
        deep_name,
        NavDiagBool(deep_down)
    )
end

NavDiagPopupAny = function()
    if not r.ImGui_IsPopupOpen then return false end
    local flags = 0
    if r.ImGui_PopupFlags_AnyPopupId then flags = flags | r.ImGui_PopupFlags_AnyPopupId() end
    if r.ImGui_PopupFlags_AnyPopupLevel then flags = flags | r.ImGui_PopupFlags_AnyPopupLevel() end
    local ok, open = pcall(function() return r.ImGui_IsPopupOpen(ctx, "", flags) end)
    return ok and open == true
end

NavDiagPopupOpen = function(id)
    if not id or id == "" or not r.ImGui_IsPopupOpen then return false end
    local ok, open = pcall(function() return r.ImGui_IsPopupOpen(ctx, id) end)
    return ok and open == true
end

NavDiagFocusString = function()
    local focus_flags = r.ImGui_FocusedFlags_RootAndChildWindows
        and r.ImGui_FocusedFlags_RootAndChildWindows()
        or 0
    local hover_flags = r.ImGui_HoveredFlags_RootAndChildWindows
        and r.ImGui_HoveredFlags_RootAndChildWindows()
        or 0
    local win_focus = r.ImGui_IsWindowFocused and r.ImGui_IsWindowFocused(ctx, focus_flags) or false
    local win_hover = r.ImGui_IsWindowHovered and r.ImGui_IsWindowHovered(ctx, hover_flags) or false
    local js = "js_focus=n/a"
    if r.JS_Window_GetFocus then
        local hwnd = r.JS_Window_GetFocus()
        if hwnd then
            local title = "?"
            local class = "?"
            if r.JS_Window_GetTitle then
                local ok, v = pcall(function() return r.JS_Window_GetTitle(hwnd) end)
                if ok and v then title = tostring(v) end
            end
            if r.JS_Window_GetClassName then
                local ok, v = pcall(function() return r.JS_Window_GetClassName(hwnd) end)
                if ok and v then class = tostring(v) end
            end
            local main = r.GetMainHwnd and hwnd == r.GetMainHwnd()
            js = string.format("js_focus=%s title=%q class=%q", main and "main" or "other", title, class)
        else
            js = "js_focus=nil"
        end
    end
    return string.format("win_focus=%s win_hover=%s %s", NavDiagBool(win_focus), NavDiagBool(win_hover), js)
end

NavDiagCaptureSummary = function()
    local c = nav_diag_last_capture or {}
    return string.format(
        "policy=%s api=%s active=%s requested=%s applied=%s",
        tostring(c.policy or "?"),
        NavDiagBool(c.api),
        NavDiagBool(c.active),
        NavDiagBool(c.requested),
        NavDiagBool(c.applied)
    )
end

NavDiagCapture = function(facts)
    if not NAV_DIAG_ENABLED then return end
    facts = facts or {}
    nav_diag_last_capture = {
        policy = facts.policy or "active_only",
        api = facts.api == true,
        active = facts.active == true,
        requested = facts.requested == true,
        applied = facts.applied == true,
    }
end

NavDiagWriteLog = function(line)
    if not nav_diag_log_path or nav_diag_log_path == "" then return end
    local f = io.open(nav_diag_log_path, "a")
    if not f then return end
    if not nav_diag_log_header then
        f:write("\n[Navigator keyboard diagnostic " .. os.date("%Y-%m-%d %H:%M:%S") .. "]\n")
        nav_diag_log_header = true
    end
    f:write(line .. "\n")
    f:close()
end

NavDiagLog = function(source, opts)
    if not NAV_DIAG_ENABLED then return end
    opts = opts or {}
    local mods = opts.mods
    if mods == nil and r.ImGui_GetKeyMods then mods = r.ImGui_GetKeyMods(ctx) end
    mods = tonumber(mods) or 0
    local os = NavDiagOS()
    local popup_id = opts.popup_id
    local popup_line = string.format(
        "popup_any=%s navctx=%s tlfctx=%s specific=%s",
        NavDiagBool(NavDiagPopupAny()),
        NavDiagBool(NavDiagPopupOpen("##navctx")),
        NavDiagBool(NavDiagPopupOpen("##tlfctx")),
        NavDiagBool(NavDiagPopupOpen(popup_id))
    )
    local any_active = r.ImGui_IsAnyItemActive and r.ImGui_IsAnyItemActive(ctx) or false
    local item_active = opts.item_active
    if item_active == nil and r.ImGui_IsItemActive then item_active = r.ImGui_IsItemActive(ctx) end
    local api = r.ImGui_SetNextFrameWantCaptureKeyboard ~= nil
    local requested = any_active
    nav_diag_seq = nav_diag_seq + 1
    local label = opts.label and (" label=" .. tostring(opts.label)) or ""
    local state = opts.state and (" state=" .. tostring(opts.state)) or ""
    local disabled = opts.disabled ~= nil and (" disabled=" .. NavDiagBool(opts.disabled)) or ""
    local display = string.format(
        "%03d %s mods=%d %s active=%s popup=%s cap=%s",
        nav_diag_seq,
        source,
        mods,
        NavDiagModsString(mods),
        NavDiagBool(any_active),
        NavDiagBool(NavDiagPopupAny()),
        NavDiagBool(requested)
    )
    table.insert(nav_diag_events, 1, display)
    while #nav_diag_events > NAV_DIAG_MAX_LINES do table.remove(nav_diag_events) end
    NavDiagWriteLog(string.format(
        "%03d source=%s%s%s%s os=%s raw_mods=%d decoded={%s} %s active_any=%s active_item=%s %s capture={policy=active_only api=%s requested=%s last={%s}}",
        nav_diag_seq,
        source,
        label,
        state,
        disabled,
        os,
        mods,
        NavDiagModsString(mods),
        NavDiagFocusString(),
        NavDiagBool(any_active),
        NavDiagBool(item_active),
        popup_line,
        NavDiagBool(api),
        NavDiagBool(requested),
        NavDiagCaptureSummary()
    ))
end

NavDiagDrawReadout = function(w)
    if not NAV_DIAG_ENABLED then return end
    local os = NavDiagOS()
    local primary_name, _, deep_name = NavDiagPlatform(os, 0)
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, C.amber, "Keyboard diagnostic")
    r.ImGui_TextColored(ctx, C.text_dim, "OS: " .. os .. " | primary: " .. primary_name .. " | future deep: " .. deep_name)
    r.ImGui_TextColored(ctx, C.text_dim, "Capture: " .. NavDiagCaptureSummary())
    r.ImGui_TextColored(ctx, C.text_muted, "Log: navigator_keyboard_diag.log")
    if #nav_diag_events == 0 then
        r.ImGui_TextColored(ctx, C.text_muted, "Click NAV.arr, NAV.pill, NAV.dot, A/S/R, songs, or context menus.")
    else
        local count = math.min(#nav_diag_events, NAV_DIAG_MAX_LINES)
        for i = 1, count do
            r.ImGui_TextColored(ctx, C.text_dim, nav_diag_events[i])
        end
    end
end

local PREF = "reflex"
REFLEX_NAVIGATOR_INSTANCE_KEY = "reflex_navigator_instance_token"
REFLEX_NAVIGATOR_COMMAND_KEY = "reflex_navigator_external_command"
reflex_navigator_instance_token = "navigator:" .. tostring({}) .. ":" .. tostring(r.time_precise and r.time_precise() or os.clock())
r.SetExtState(PREF, REFLEX_NAVIGATOR_INSTANCE_KEY, reflex_navigator_instance_token, false)
if r.atexit then
    r.atexit(function()
        if r.GetExtState(PREF, REFLEX_NAVIGATOR_INSTANCE_KEY) == reflex_navigator_instance_token
            and r.DeleteExtState then
            r.DeleteExtState(PREF, REFLEX_NAVIGATOR_INSTANCE_KEY, false)
        end
    end)
end

LoadPref = function(key, default)
    local v = r.GetExtState(PREF, key)
    if v == "" then return default end
    if type(default) == "boolean" then return v == "1" end
    return tonumber(v) or default
end

SavePref = function(key, val)
    r.SetExtState(PREF, key, type(val) == "boolean" and (val and "1" or "0") or tostring(val), true)
end

NavigatorClampScale = function(v)
    local n = tonumber(v)
    if not n or n ~= n then return 1.0 end
    if n < 0.5 then return 0.5 end
    if n > 2.5 then return 2.5 end
    return math.floor(n * 100 + 0.5) / 100
end

opt_expand_children = LoadPref("expand_children", false)
opt_songs_expand = LoadPref("songs_expand_children", false)
opt_tooltips = LoadPref("tooltips", true)
opt_viewlock = LoadPref("view_lock", false)
opt_live_mode = LoadPref("tycho_live_mode", false)
opt_nav_ignore_archive = LoadPref("nav_ignore_archive", true)
opt_nav_tlt_expand = LoadPref("nav_tlt_expand", true)
opt_nav_show_search = LoadPref("nav_show_search", true)
opt_nav_custom_set_mode = LoadPref("nav_custom_set_mode", false)
opt_nav_indent_tlts = LoadPref("nav_indent_tlts", true)
opt_nav_flip_indent = LoadPref("nav_flip_indent", false)
opt_helper_tooltips = LoadPref("helper_tooltips", false)
opt_view_mode_restore_arrange = LoadPref("view_mode_restore_arrange", false)
opt_esc_key_to_close = LoadPref("esc_key_to_close", true)
local ui_scale = LoadPref("navigator_scale_v1", nil)
if ui_scale == nil then
    local old = LoadPref("ui_scale_v2", nil)
    if old == nil then
        local legacy = LoadPref("ui_scale", nil)
        old = legacy and math.floor(legacy / 0.8 * 100 + 0.5) / 100 or 1.0
    end
    ui_scale = old
    SavePref("navigator_scale_v1", ui_scale)
end
local unclamped_ui_scale = ui_scale
ui_scale = NavigatorClampScale(ui_scale)
if ui_scale ~= unclamped_ui_scale then SavePref("navigator_scale_v1", ui_scale) end

local body_size = (nav_theme.fonts and nav_theme.fonts.body_size) or 14
local body_family = (nav_theme.fonts and nav_theme.fonts.family) or 'SF Pro'
local scaled_fonts = {}
local scaled_fonts_italic = {}
local scaled_fonts_regular = {}
local scaled_font_sizes = {}
CreateNavigatorFont = function(family, flags)
    return r.ImGui_CreateFont(family, flags)
end
for step = 5, 20 do
    local scale = step / 10
    local sz = math.floor(body_size * scale + 0.5)
    local f = CreateNavigatorFont(body_family, r.ImGui_FontFlags_Bold())
    r.ImGui_Attach(ctx, f)
    scaled_fonts[step] = f
    if f then scaled_font_sizes[f] = sz end
    local fi = CreateNavigatorFont(body_family, r.ImGui_FontFlags_Italic())
    r.ImGui_Attach(ctx, fi)
    scaled_fonts_italic[step] = fi
    if fi then scaled_font_sizes[fi] = sz end
    local fr = CreateNavigatorFont(body_family, r.ImGui_FontFlags_None())
    r.ImGui_Attach(ctx, fr)
    scaled_fonts_regular[step] = fr
    if fr then scaled_font_sizes[fr] = sz end
end

local navigator_imgui_push_font = r.ImGui_PushFont
r.ImGui_PushFont = function(ctx_arg, font, size)
    if size == nil then
        if font ~= nil and scaled_font_sizes[font] then
            size = scaled_font_sizes[font]
        elseif r.ImGui_GetFontSize then
            local ok_size, current_size = pcall(r.ImGui_GetFontSize, ctx_arg)
            if ok_size and type(current_size) == "number" then size = current_size end
        end
    end
    if size ~= nil then return navigator_imgui_push_font(ctx_arg, font, size) end
    return navigator_imgui_push_font(ctx_arg, font)
end

package.loaded["Reflex_FontCore"] = nil
require("Reflex_FontCore")({
    r = r,
    ctx = ctx,
    scaled_fonts = scaled_fonts,
    scaled_fonts_italic = scaled_fonts_italic,
    scaled_fonts_regular = scaled_fonts_regular,
    font_sizes = scaled_font_sizes,
    get_ui_scale = function() return ui_scale end,
})

C = {
    bg = rgb(0x171B22),
    window_bg = rgb(0x3E3E3F),
    window_outline = rgb(0x525254),
    border = rgb(0x30363D),
    text = rgb(0xE6EDF3),
    text_dim = rgb(0x8B949E),
    text_muted = rgb(0x484F58),
    amber = rgb(0xD29922),
    btn_bg = rgb(0x21262D),
    btn_hover = rgb(0x30363D),
    btn_active = rgb(0x3A424B),
    fx_ctrl_bg = rgb(0x2A2F37),
    fx_ctrl_hover = rgb(0x363C46),
    fx_ctrl_active = rgb(0x424950),
    route_bg = rgb(0x2A2F37),
    section_text = rgb(0x555D67),
}

for key, hex in pairs(nav_theme.colors or {}) do
    if type(hex) == "number" then C[key] = rgb(hex) end
end

local track_color_overrides = nav_theme.track_colors or {}

local BASE_H = 28
local BASE_SPACING = 6
local BASE_PAD_X = 8
local BASE_PAD_Y = 4

UI = {
    pad_sm = 6,
    btn_h = 26,
    edge_pad = 12,
    font_title = 3,
    card_pad = 14,
}

S = function(v) return math.floor(v * ui_scale * 0.8 + 0.5) end
Round = function(v) return math.floor(v + 0.5) end
clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end

Utf8DropLast = function(s)
    local len = #s
    if len == 0 then return s end
    while len > 0 and s:byte(len) >= 0x80 and s:byte(len) <= 0xBF do len = len - 1 end
    if len > 0 then len = len - 1 end
    return s:sub(1, len)
end

DrawIcon = function(dl, cx, cy, size, icon, col)
    local arm = size * 0.22
    local thick = math.max(1, size * 0.09)
    local t = thick / 2
    if icon == "+" then
        r.ImGui_DrawList_AddRectFilled(dl, cx - arm, cy - t, cx + arm, cy + t, col)
        r.ImGui_DrawList_AddRectFilled(dl, cx - t, cy - arm, cx + t, cy + arm, col)
    elseif icon == "-" then
        r.ImGui_DrawList_AddRectFilled(dl, cx - arm, cy - t, cx + arm, cy + t, col)
    elseif icon == "x" or icon == "×" then
        r.ImGui_DrawList_AddLine(dl, cx - arm, cy - arm, cx + arm, cy + arm, col, thick)
        r.ImGui_DrawList_AddLine(dl, cx - arm, cy + arm, cx + arm, cy - arm, col, thick)
    end
end

local NAV_DEFAULT = {
    square = {bg = 0, hov = 0, active = 0, fg = 0, fg_hov = 0, fg_active = 0, rounding = 3},
    circle = {bg = 0, hov = 0, active = 0, fg = 0, fg_hov = 0, fg_active = 0},
    pill = {bg = 0, hov = 0, active = 0, fg = 0, fg_hov = 0, fg_active = 0},
    rect = {bg = 0, hov = 0, active = 0, fg = 0, fg_hov = 0, fg_active = 0, rounding = 3},
}
NAV_CIRCLE_SEGMENTS = 96

NavInitDefaults = function()
    local set = function(t, bg, hov, act)
        t.bg, t.hov, t.active = bg, hov, act
        t.fg, t.fg_hov, t.fg_active = C.text_dim, C.text, C.text
    end
    set(NAV_DEFAULT.square, C.fx_ctrl_bg, C.fx_ctrl_hover, C.fx_ctrl_active)
    set(NAV_DEFAULT.circle, C.fx_ctrl_bg, C.fx_ctrl_hover, C.fx_ctrl_active)
    set(NAV_DEFAULT.rect, C.fx_ctrl_bg, C.fx_ctrl_hover, C.fx_ctrl_active)
    set(NAV_DEFAULT.pill, C.route_bg, C.fx_ctrl_hover, C.fx_ctrl_active)
end

NavRounding = function(opts_r, default_r)
    local ro = opts_r
    if ro == nil then ro = default_r end
    if type(ro) == "number" then return ro, r.ImGui_DrawFlags_RoundCornersAll() end
    if type(ro) == "table" then
        local flags = 0
        local max_r = 0
        if ro.tl and ro.tl > 0 then flags = flags | r.ImGui_DrawFlags_RoundCornersTopLeft(); if ro.tl > max_r then max_r = ro.tl end end
        if ro.tr and ro.tr > 0 then flags = flags | r.ImGui_DrawFlags_RoundCornersTopRight(); if ro.tr > max_r then max_r = ro.tr end end
        if ro.bl and ro.bl > 0 then flags = flags | r.ImGui_DrawFlags_RoundCornersBottomLeft(); if ro.bl > max_r then max_r = ro.bl end end
        if ro.br and ro.br > 0 then flags = flags | r.ImGui_DrawFlags_RoundCornersBottomRight(); if ro.br > max_r then max_r = ro.br end end
        if flags == 0 then return 0, r.ImGui_DrawFlags_RoundCornersNone() end
        return max_r, flags
    end
    return 0, r.ImGui_DrawFlags_RoundCornersAll()
end

NavContentColor = function(opts, def, hov, active)
    if active then
        if opts.fg_active then return opts.fg_active end
        if opts.fg_hov then return opts.fg_hov end
        if opts.fg then return opts.fg end
        return def.fg_active
    end
    if hov then
        if opts.fg_hov then return opts.fg_hov end
        if opts.fg then return opts.fg end
        return def.fg_hov
    end
    return opts.fg or def.fg
end

NavBgColor = function(opts, def, hov, active)
    if active and not opts.no_press then
        if opts.active then return opts.active end
        if opts.hov then return opts.hov end
        if opts.bg then return opts.bg end
        return def.active
    end
    if hov then
        if opts.hov then return opts.hov end
        if opts.bg then return opts.bg end
        return def.hov
    end
    return opts.bg or def.bg
end

NavDrawContent = function(dl, x, y, w, h, content, fg)
    if content == nil or content == "" then return end
    if content == "+" or content == "-" or content == "x" or content == "×" then
        DrawIcon(dl, x + w / 2, y + h / 2, math.min(w, h), content, fg)
    else
        local tw, th = r.ImGui_CalcTextSize(ctx, content)
        local tx = Round(x + (w - tw) / 2)
        local ty = Round(y + (h - th) / 2)
        r.ImGui_DrawList_AddText(dl, tx, ty, fg, content)
    end
end

NavRect = function(id, w, h, content, opts)
    opts = opts or {}
    local d = NAV_DEFAULT.rect
    r.ImGui_InvisibleButton(ctx, id, opts.hit_w or w, opts.hit_h or h)
    local hov = r.ImGui_IsItemHovered(ctx)
    local active = r.ImGui_IsItemActive(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local x, y = r.ImGui_GetItemRectMin(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local bg = NavBgColor(opts, d, hov, active)
    local fg = NavContentColor(opts, d, hov, active)
    local rd, flags = NavRounding(opts.rounding, d.rounding)
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, rd, flags)
    NavDrawContent(dl, x, y, w, h, content, fg)
    return hov, clicked, active
end

NavSquare = function(id, w, h, content, opts)
    return NavRect(id, w, h, content, opts)
end

NavCircle = function(id, diameter, content, opts)
    opts = opts or {}
    local d = NAV_DEFAULT.circle
    local hit_w = opts.hit_w or diameter
    local hit_h = opts.hit_h or diameter
    r.ImGui_InvisibleButton(ctx, id, hit_w, hit_h)
    local hov = r.ImGui_IsItemHovered(ctx)
    local active = r.ImGui_IsItemActive(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local x, y = r.ImGui_GetItemRectMin(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local bg = NavBgColor(opts, d, hov, active)
    local fg = NavContentColor(opts, d, hov, active)
    local rad = diameter / 2
    local cx = x + hit_w / 2
    local cy = y + hit_h / 2
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, rad, bg, opts.segments or NAV_CIRCLE_SEGMENTS)
    NavDrawContent(dl, x, y, hit_w, hit_h, content, fg)
    return hov, clicked, active
end

NavPill = function(id, w, h, content, opts)
    opts = opts or {}
    local d = NAV_DEFAULT.pill
    r.ImGui_InvisibleButton(ctx, id, opts.hit_w or w, opts.hit_h or h)
    local hov = r.ImGui_IsItemHovered(ctx)
    local active = r.ImGui_IsItemActive(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local x, y = r.ImGui_GetItemRectMin(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local bg = NavBgColor(opts, d, hov, active)
    local fg = NavContentColor(opts, d, hov, active)
    local rd, flags = NavRounding(opts.rounding, h / 2)
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, rd, flags)
    NavDrawContent(dl, x, y, w, h, content, fg)
    return hov, clicked, active
end

NavInitDefaults()

DrawTrackNavigatorWindowOutline = function(dl, x, y, w, h, rounding, col)
    local x1 = Round(x)
    local y1 = Round(y)
    local x2 = Round(x + w)
    local y2 = Round(y + h)
    local t = 1
    local has_arc = r.ImGui_DrawList_PathClear and r.ImGui_DrawList_PathArcTo and r.ImGui_DrawList_PathStroke
    local cr = has_arc and math.max(0, math.min(Round(rounding or 0), math.floor(math.min(x2 - x1, y2 - y1) / 2))) or 0
    local straight_x1 = x1 + cr
    local straight_x2 = x2 - cr
    local straight_y1 = y1 + cr
    local straight_y2 = y2 - cr

    r.ImGui_DrawList_PushClipRect(dl, x1, y1, x2, y2, false)
    r.ImGui_DrawList_AddRectFilled(dl, straight_x1, y1, straight_x2, y1 + t, col)
    r.ImGui_DrawList_AddRectFilled(dl, straight_x1, y2 - t, straight_x2, y2, col)
    r.ImGui_DrawList_AddRectFilled(dl, x1, straight_y1, x1 + t, straight_y2, col)
    r.ImGui_DrawList_AddRectFilled(dl, x2 - t, straight_y1, x2, straight_y2, col)

    if cr > 1 then
        local radius = cr - 0.5
        local segs = math.max(6, Round(cr * 1.25))
        local pi = math.pi
        r.ImGui_DrawList_PathClear(dl)
        r.ImGui_DrawList_PathArcTo(dl, x1 + cr, y1 + cr, radius, pi, pi * 1.5, segs)
        r.ImGui_DrawList_PathStroke(dl, col, 0, t)
        r.ImGui_DrawList_PathClear(dl)
        r.ImGui_DrawList_PathArcTo(dl, x2 - cr, y1 + cr, radius, pi * 1.5, pi * 2, segs)
        r.ImGui_DrawList_PathStroke(dl, col, 0, t)
        r.ImGui_DrawList_PathClear(dl)
        r.ImGui_DrawList_PathArcTo(dl, x2 - cr, y2 - cr, radius, 0, pi * 0.5, segs)
        r.ImGui_DrawList_PathStroke(dl, col, 0, t)
        r.ImGui_DrawList_PathClear(dl)
        r.ImGui_DrawList_PathArcTo(dl, x1 + cr, y2 - cr, radius, pi * 0.5, pi, segs)
        r.ImGui_DrawList_PathStroke(dl, col, 0, t)
    else
        r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x1 + t, y1 + t, col)
        r.ImGui_DrawList_AddRectFilled(dl, x2 - t, y1, x2, y1 + t, col)
        r.ImGui_DrawList_AddRectFilled(dl, x2 - t, y2 - t, x2, y2, col)
        r.ImGui_DrawList_AddRectFilled(dl, x1, y2 - t, x1 + t, y2, col)
    end
    r.ImGui_DrawList_PopClipRect(dl)
end

DrawScrollIndicator = function(dl, region_y1, region_y2, scroll_y, scroll_max, child_h, fade, ind_x)
    if scroll_max <= 0 or fade <= 0 then return end
    local ind_w = S(3)
    local ind_pad = S(4)
    local ind_top = region_y1 + ind_pad
    local ind_track_h = (region_y2 - region_y1) - ind_pad * 2
    if ind_track_h < S(40) then return end
    local total_content = child_h + scroll_max
    local ind_h = math.max(S(20), (child_h / total_content) * ind_track_h)
    local scrollable = ind_track_h - ind_h
    local ratio = scroll_y / scroll_max
    local ind_y = ind_top + ratio * scrollable
    local alpha = math.floor(math.min(1, fade) * 255)
    local color = (C.border & 0xFFFFFF00) | alpha
    r.ImGui_DrawList_AddRectFilled(dl, ind_x, ind_y, ind_x + ind_w, ind_y + ind_h, color, ind_w / 2)
end

package.loaded["Reflex_StyleCore"] = nil
require("Reflex_StyleCore")({
    r = r,
    ctx = ctx,
    colors = C,
})

StyledButton = function(label, w, h, bg, hover, active, text_col, active_text_col)
    local cc = 3
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), active)
    if text_col then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_col); cc = 4 end
    local clicked = r.ImGui_Button(ctx, label, w, h)
    if active_text_col and r.ImGui_IsItemActive(ctx) then
        local bx, by = r.ImGui_GetItemRectMin(ctx)
        local bx2, by2 = r.ImGui_GetItemRectMax(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        r.ImGui_DrawList_AddRectFilled(dl, bx, by, bx2, by2, active, S(6))
        local display = label:match("^(.-)##") or label
        local tw, th = r.ImGui_CalcTextSize(ctx, display)
        local pad_x = S(12)
        r.ImGui_DrawList_AddText(dl, bx + pad_x, by + Round(((by2 - by) - th) / 2), active_text_col, display)
    end
    r.ImGui_PopStyleColor(ctx, cc)
    return clicked
end

SetTrackVis = function(track, visible)
    local v = visible and 1 or 0
    r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", v)
    r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", v)
end

package.loaded["Reflex_ColorCore"] = nil
require("Reflex_ColorCore")({
    r = r,
    colors = C,
})

local MONITOR_MUSICIANS = { RORY = true, ZAC = true, BILLY = true, SCOTT = true, OUTPUTS = true }
local SONG_SECTIONS = { ["LIVE FX"] = true, ["PLAYBACK"] = true }

MakePrefKey = function(name) return name:lower():gsub("[^%w]", "") .. "_expanded" end

CreateSubGroup = function(parent_name, filter_fn)
    return {
        parent_name = parent_name,
        entry_ref = nil,
        entries = {},
        selected = {},
        ui_expanded = LoadPref(MakePrefKey(parent_name), true),
        filter_fn = filter_fn,
    }
end

sub_groups = {}
if opt_live_mode then
    sub_groups = {
        CreateSubGroup("MONITORS", function(name)
            local d = name:match("^MON:%s*(.+)") or name
            return MONITOR_MUSICIANS[d] and d or nil
        end),
        CreateSubGroup("I/O", function(name) return name end),
    }
end

sub_group_by_name = {}
for _, sg in ipairs(sub_groups) do sub_group_by_name[sg.parent_name] = sg end

songs_sub = {
    is_song_sub = true,
    parent_name = "SONGS",
    entry_ref = nil,
    entries = {},
    selected = {},
    ui_expanded = LoadPref(MakePrefKey("SONGS"), true),
    song_name = "",
    song_track = nil,
    song_idx = -1,
}
songs_section_mode = false

top_folders = {}
archive_entry = nil
needs_rescan = true
current_page = "tracks"
song_entries = {}
song_search = ""
needs_song_rescan = true
viewlock_song = ""
songs_entry_ref = nil
songs_follow_active = false
songs_follow_last = ""
render_list = {}
tracks_last_click = nil
tracks_range_anchor_guid = nil
songs_last_click = nil

navigator_expanded = LoadPref("navigator_expanded", true)
nav_visible = true
nav_mirror = LoadPref("nav_mirror", false)
remote_ctx_tlf_guid = nil
remote_ctx_tlf_track = nil
remote_ctx_tlf_ghost_parent = nil
remote_ctx_tlf_custom = false
nav_tlt_search_text = ""
nav_tlt_search_effective_query = ""
nav_tlt_search_visible = false
nav_tlt_search_esc_consumed = false
nav_tlt_search_hide_clear = false
nav_tlt_search_recent_clear_frames = 0
nav_tlt_search_focus_requested_frames = 0
nav_tlt_search_window_focus_requested_frames = 0
last_nav_h = 0
last_nav_natural_h = 0
last_nav_collapsed_visible_h = 0
last_nav_expanded_visible_h = 0
nav_list_scroll_prev_y = -1
nav_list_scroll_fade = 0
nav_list_scroll_y = 0
nav_list_scroll_max = 0
nav_list_child_h = 0

routing_view_active = false
routing_view_source = nil
routing_view_sources = {}
routing_view_tracks = {}
routing_view_depth = LoadPref("routing_depth", 1)
routing_view_saved_snap = nil
selected_view_active = false
selected_view_tracks = {}
selected_view_saved_snap = nil
armed_view_active = false
armed_view_tracks = {}
armed_view_saved_snap = nil
active_view_active = false
active_view_tracks = {}
active_view_peak_times = {}
active_view_signal_available = false
active_view_threshold = 0.001
active_view_window = 3.0
active_view_last_play = 0
active_view_last_peak_scan_time = 0
active_view_peak_scan_interval = 0.10
active_view_idle_peak_scan_interval = 0.50
active_view_saved_snap = nil
active_view_flash_time = 0

flow_view_active = false
flow_view_anchor = nil
flow_view_chain = {}
flow_view_browsing = false
flow_view_expanded_set = {}
flow_env_expanded = {}
flow_mini_peak = {}
InspScanTrack = function() end
FlowViewBuildChain = function() return {} end

VIEW_HISTORY_MAX = 30
view_history = {}
view_history_idx = 0
view_history_count = 0
view_history_restoring = 0
view_history_pushing = false
view_history_tlf_debounce = -math.huge
view_history_launch_baseline = false

package.loaded["Reflex_PinCore"] = nil
require("Reflex_PinCore")({ r = r, PREF = PREF })
LoadPinnedFolders()

package.loaded["Reflex_NavTreeCore"] = nil
require("Reflex_NavTreeCore")({
    r = r,
    get_render_list = function() return render_list end,
    mark_dirty = function() needs_rescan = true end,
})
LoadNavTreeExpansion()

package.loaded["Reflex_NavExclusionCore"] = nil
require("Reflex_NavExclusionCore")({
    r = r,
    PREF = PREF,
    get_top_folders = function() return top_folders end,
    set_track_vis = SetTrackVis,
    mark_dirty = function() needs_rescan = true; needs_song_rescan = true end,
})
LoadNavExcluded()

package.loaded["Reflex_NavInclusionCore"] = nil
require("Reflex_NavInclusionCore")({
    r = r,
    can_include_track = function(track)
        if NavTrackAutoIgnored and NavTrackAutoIgnored(track) then return false end
        if NavTrackInHiddenSubtree and NavTrackInHiddenSubtree(track) then return false end
        if NavTrackInLiveSpecialArea and NavTrackInLiveSpecialArea(track) then return false end
        return true
    end,
    tree_expand_enabled = function() return opt_nav_tlt_expand ~= false end,
    expand_parent_chain = function(track)
        if NavTreeExpandParentChain then return NavTreeExpandParentChain(track) end
        return false
    end,
    mark_dirty = function() needs_rescan = true; needs_song_rescan = true end,
})
LoadNavIncluded()
local loaded_custom_set_entries = NavCustomSetEntries and NavCustomSetEntries({ include_blocked = true }) or {}
if opt_nav_custom_set_mode == true and #loaded_custom_set_entries == 0 then
    opt_nav_custom_set_mode = false
    SavePref("nav_custom_set_mode", false)
end

package.loaded["Reflex_RealistCore"] = nil
require("Reflex_RealistCore")({
    r = r,
    realist_section = "realist",
})

package.loaded["Reflex_TrackScanCore"] = nil
require("Reflex_TrackScanCore")({
    r = r,
    song_sections = SONG_SECTIONS,
    get_realist_current_song = GetRealistCurrentSong,
    excluded_track = ExcludedTrack,
    hidden_track = HiddenTrack,
    hidden_subtree = NavTrackInHiddenSubtree,
    live_mode = function() return opt_live_mode == true end,
    track_auto_ignored = function(track) return NavTrackAutoIgnored and NavTrackAutoIgnored(track) or false end,
    get_included_entries = function() return NavIncludedEntries and NavIncludedEntries() or {} end,
    get_custom_set_entries = function() return NavCustomSetEntries and NavCustomSetEntries() or {} end,
    custom_set_mode = function() return opt_nav_custom_set_mode == true end,
    get_sub_groups = function() return sub_groups end,
    get_sub_group_by_name = function() return sub_group_by_name end,
    get_songs_sub = function() return songs_sub end,
    get_top_folders = function() return top_folders end,
    set_top_folders = function(v) top_folders = v end,
    set_archive_entry = function(v) archive_entry = v end,
    get_songs_entry_ref = function() return songs_entry_ref end,
    set_songs_entry_ref = function(v) songs_entry_ref = v end,
    set_needs_rescan = function(v) needs_rescan = v end,
    set_render_list = function(v) render_list = v end,
    set_song_entries = function(v) song_entries = v end,
    set_needs_song_rescan = function(v) needs_song_rescan = v end,
    set_songs_last_click = function(v) songs_last_click = v end,
})

package.loaded["Reflex_TrackUtilCore"] = nil
require("Reflex_TrackUtilCore")({
    r = r,
    set_track_vis = SetTrackVis,
})

package.loaded["Reflex_SongCore"] = nil
require("Reflex_SongCore")({
    r = r,
    song_sections = SONG_SECTIONS,
    get_realist_current_song = GetRealistCurrentSong,
    set_track_vis = SetTrackVis,
    get_children = GetChildren,
    expand_child_folders = ExpandChildFolders,
    get_songs_entry_ref = function() return songs_entry_ref end,
    get_songs_sub = function() return songs_sub end,
    set_songs_follow_active = function(v) songs_follow_active = v end,
    set_songs_follow_last = function(v) songs_follow_last = v end,
    set_songs_section_mode = function(v) songs_section_mode = v end,
})

package.loaded["Reflex_SubGroupCore"] = nil
require("Reflex_SubGroupCore")({
    r = r,
    set_track_vis = SetTrackVis,
})

package.loaded["Reflex_ViewHistory"] = nil
require("Reflex_ViewHistory")({
    r = r,
    get_insp_pinned = function() return false end,
    set_insp_pinned = function(_) end,
    get_insp_track = function() return nil end,
    set_insp_track = function(_) end,
    reset_insp_env_expanded = function() end,
    set_insp_pin_suppress_selected = function(_) end,
})

package.loaded["Reflex_NavActionCore"] = nil
require("Reflex_NavActionCore")({
    r = r,
    mark_dirty = function() needs_rescan = true; needs_song_rescan = true end,
})

package.loaded["Reflex_ViewModes"] = nil
require("Reflex_ViewModes")({
    r = r,
    mark_dirty = function() needs_rescan = true; needs_song_rescan = true end,
})

nav_dock_request = nil
nav_quit_requested = false
nav_window_docked = false
nav_current_dock_id = 0
nav_last_side_dock_pos = nil
last_window_w = 0
last_window_h = 0
nav_floating_user_w = LoadPref("navigator_floating_user_w_v1", 0)
nav_floating_user_h = LoadPref("navigator_floating_user_h_v1", 0)
nav_floating_observed_w = 0
nav_floating_observed_h = 0
nav_pending_undock_snap = false
nav_suppress_floating_size_save = 0
nav_ignore_floating_size_until_mouse_up = false
nav_pending_collapse_snap_frames = 0
nav_collapsed_return_w = 0
nav_collapsed_return_h = 0
nav_popup_active_this_frame = false
nav_popup_active_previous_frame = false

package.loaded["Reflex_NavViewCore"] = nil
require("Reflex_NavViewCore")({
    r = r,
    ctx = ctx,
    colors = C,
    scaled_fonts = scaled_fonts,
    font_sizes = scaled_font_sizes,
    track_color_overrides = track_color_overrides,
    script_dir = script_dir,
    version = NAVIGATOR_VERSION,
    menu_context = "standalone",
    debug_event = NavDiagLog,
    mark_dirty = function() needs_rescan = true; needs_song_rescan = true end,
    get_nav_scale = function() return ui_scale end,
    set_nav_scale = function(v)
        ui_scale = NavigatorClampScale(v)
        SavePref("navigator_scale_v1", ui_scale)
    end,
    get_dock_id = function() return nav_current_dock_id end,
    request_dock = function(dock_id) nav_dock_request = dock_id end,
    request_quit = function() nav_quit_requested = true end,
    note_popup_active = function() nav_popup_active_this_frame = true end,
})

NavigatorDockPosition = function(dock_id)
    if type(dock_id) ~= "number" or dock_id >= 0 or not r.DockGetPosition then return nil end
    local ok, dock_pos = pcall(r.DockGetPosition, ~dock_id)
    if ok and type(dock_pos) == "number" then return dock_pos end
    return nil
end

NavigatorVisualSideDockPosition = function(wx, ww, dock_pos)
    if dock_pos == 1 or dock_pos == 3 then return dock_pos end
    local win_cx = wx + ww * 0.5
    if r.GetMainHwnd and r.JS_Window_GetRect then
        local ok_hwnd, hwnd = pcall(r.GetMainHwnd)
        if ok_hwnd and hwnd then
            local ok_rect, ok, left, _, right = pcall(r.JS_Window_GetRect, hwnd)
            if ok_rect and ok and type(left) == "number" and type(right) == "number" and right > left then
                return win_cx < ((left + right) * 0.5) and 1 or 3
            end
        end
    end
    if not (r.ImGui_GetMainViewport and r.ImGui_Viewport_GetWorkPos and r.ImGui_Viewport_GetWorkSize) then
        return nil
    end
    local ok_vp, viewport = pcall(r.ImGui_GetMainViewport, ctx)
    if not ok_vp or not viewport then return nil end
    local ok_pos, work_x = pcall(r.ImGui_Viewport_GetWorkPos, viewport)
    local ok_size, work_w = pcall(r.ImGui_Viewport_GetWorkSize, viewport)
    if not ok_pos or not ok_size or type(work_x) ~= "number" or type(work_w) ~= "number" or work_w <= 0 then
        return nil
    end
    local center_delta = win_cx - (work_x + work_w * 0.5)
    if math.abs(center_delta) <= math.max(1, ww * 0.25) then return nil end
    return center_delta < 0 and 1 or 3
end

NavigatorMaxAutoWindowHeight = function()
    local fallback = S(760)
    if r.ImGui_GetMainViewport and r.ImGui_Viewport_GetWorkSize then
        local ok_vp, viewport = pcall(r.ImGui_GetMainViewport, ctx)
        if ok_vp and viewport then
            local ok_size, _, work_h = pcall(r.ImGui_Viewport_GetWorkSize, viewport)
            if ok_size and type(work_h) == "number" and work_h > 0 then
                return math.max(S(220), Round(work_h * 0.86))
            end
        end
    end
    return fallback
end

NavigatorMouseDown = function()
    if not r.ImGui_IsMouseDown then return false end
    local ok_down, down = pcall(r.ImGui_IsMouseDown, ctx, 0)
    return ok_down and down == true
end

NavigatorSaveFloatingUserSize = function(w, h)
    if type(w) ~= "number" or type(h) ~= "number" then return end
    if w < S(40) or h < S(40) then return end
    nav_floating_user_w = Round(w)
    nav_floating_user_h = Round(h)
    SavePref("navigator_floating_user_w_v1", nav_floating_user_w)
    SavePref("navigator_floating_user_h_v1", nav_floating_user_h)
end

NavigatorFloatingSnapSize = function(min_window_w, content_fit_h)
    local has_user_size = nav_floating_user_w and nav_floating_user_w > 0
        and nav_floating_user_h and nav_floating_user_h > 0
    local target_w = has_user_size and nav_floating_user_w or S(240)
    local target_h = has_user_size and nav_floating_user_h or content_fit_h
    target_w = math.max(min_window_w, target_w)
    target_h = math.max(content_fit_h, target_h)
    return target_w, target_h
end

NavigatorEnsureDockingEnabled = function()
    if not (r.ImGui_GetConfigVar and r.ImGui_SetConfigVar
        and r.ImGui_ConfigVar_Flags and r.ImGui_ConfigFlags_DockingEnable) then
        return
    end
    local ok_var, flags_var = pcall(r.ImGui_ConfigVar_Flags)
    local ok_flag, dock_flag = pcall(r.ImGui_ConfigFlags_DockingEnable)
    if not ok_var or not ok_flag then return end
    local ok_flags, flags = pcall(r.ImGui_GetConfigVar, ctx, flags_var)
    if not ok_flags or type(flags) ~= "number" then return end
    flags = math.floor(flags)
    if (flags & dock_flag) == 0 then
        pcall(r.ImGui_SetConfigVar, ctx, flags_var, flags | dock_flag)
    end
end

TrackNavigatorSearchShortcutPressed = function()
    if not (r.ImGui_IsKeyPressed and r.ImGui_Key_F) then return false end
    local ok_key, key = pcall(r.ImGui_Key_F)
    if not ok_key or type(key) ~= "number" then return false end
    local ok_pressed, pressed = pcall(r.ImGui_IsKeyPressed, ctx, key, false)
    if not ok_pressed or pressed ~= true then return false end
    local mods = 0
    if r.ImGui_GetKeyMods then
        local ok_mods, value = pcall(r.ImGui_GetKeyMods, ctx)
        if ok_mods and type(value) == "number" then mods = value end
    end
    local nav_mods = TrackNavigatorModState(mods)
    return nav_mods.cmd and not nav_mods.shift and not nav_mods.alt
end

NavigatorRequestTltSearchFocus = function()
    current_page = "tracks"
    if not navigator_expanded then
        navigator_expanded = true
        SavePref("navigator_expanded", true)
    end
    if opt_nav_show_search == false then
        opt_nav_show_search = true
        SavePref("nav_show_search", true)
    end
    nav_tlt_search_hide_clear = false
    nav_tlt_search_recent_clear_frames = 0
    nav_tlt_search_focus_requested_frames = 8
    nav_tlt_search_window_focus_requested_frames = 8
    needs_rescan = true
end

ReflexNavigatorRunExternalCommand = function(command)
    if command == "armed_enable" then
        if not armed_view_active then ArmedViewToggle() end
        return true
    elseif command == "armed_rebuild" then
        ArmedViewRefreshFromRecordArm()
        return true
    elseif command == "armed_exit" then
        ArmedViewExit()
        return true
    elseif command == "armed_toggle" then
        ArmedViewToggle()
        return true
    elseif command == "armed_scroll" then
        return TrackNavigatorScrollToRecordArmed and TrackNavigatorScrollToRecordArmed() == true
    end
    return false
end

ReflexNavigatorPollExternalCommand = function()
    local raw = r.GetExtState(PREF, REFLEX_NAVIGATOR_COMMAND_KEY)
    if raw == "" then return false end
    if r.DeleteExtState then
        r.DeleteExtState(PREF, REFLEX_NAVIGATOR_COMMAND_KEY, false)
    else
        r.SetExtState(PREF, REFLEX_NAVIGATOR_COMMAND_KEY, "", false)
    end
    local command = tostring(raw):match("^([^|]+)") or tostring(raw)
    return ReflexNavigatorRunExternalCommand(command)
end

NavigatorAnyPopupOpen = function()
    if not (r.ImGui_IsPopupOpen and r.ImGui_PopupFlags_AnyPopup) then return false end
    local ok_flags, flags = pcall(r.ImGui_PopupFlags_AnyPopup)
    if not ok_flags or type(flags) ~= "number" then return false end
    local ok_open, popup_open = pcall(r.ImGui_IsPopupOpen, ctx, "", flags)
    return ok_open and popup_open == true
end

NavigatorSpecialViewActive = function()
    return routing_view_active == true
        or selected_view_active == true
        or armed_view_active == true
        or active_view_active == true
end

NavigatorReconcilePinnedVisibility = function()
    if not EnsurePinnedVisible or not pinned_folders or next(pinned_folders) == nil then return false end
    local changed = EnsurePinnedVisible()
    if changed then
        if SyncGhostVisibility then SyncGhostVisibility() end
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        needs_rescan = true
        needs_song_rescan = true
    end
    return changed
end

NavigatorRequestPinnedVisibilityReconcile = function()
    if pinned_folders and next(pinned_folders) ~= nil then
        pinned_visibility_reconcile_pending = true
    end
end

local window_initialized = false
local last_track_count = 0
local last_project_state = 0
project_state_rescan_pending = false
pinned_visibility_reconcile_pending = false
local last_rescan_time = 0
local RESCAN_THROTTLE = 0.5
local nav_project_key = nil
local nav_project_search_cache = {}

NavigatorCurrentProjectKey = function()
    local proj = r.EnumProjects and r.EnumProjects(-1, "") or nil
    local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
    return tostring(proj or "0") .. "|" .. tostring(master or "")
end

NavigatorSetSearchForProject = function(query)
    query = query or ""
    nav_tlt_search_text = query
    nav_tlt_search_effective_query = query
    nav_tlt_search_hide_clear = query == ""
    nav_tlt_search_recent_clear_frames = 0
    nav_tlt_search_focus_requested_frames = 0
    nav_tlt_search_window_focus_requested_frames = 0
    if NavSetTltSearchEffectiveQuery then NavSetTltSearchEffectiveQuery(query, true) end
end

NavigatorSyncProjectTab = function()
    local cur = NavigatorCurrentProjectKey()
    if cur == "" then return false end
    if not nav_project_key then
        nav_project_key = cur
        nav_project_search_cache[cur] = nav_tlt_search_text or ""
        return false
    end
    if cur == nav_project_key then return false end

    nav_project_search_cache[nav_project_key] = nav_tlt_search_text or ""
    nav_project_key = cur
    NavigatorSetSearchForProject(nav_project_search_cache[cur] or "")
    top_folders = {}
    render_list = {}
    song_entries = {}
    archive_entry = nil
    songs_entry_ref = nil
    for _, sg in ipairs(sub_groups) do sg.entry_ref = nil; sg.entries = {} end
    needs_rescan = true
    needs_song_rescan = true
    project_state_rescan_pending = false
    return true
end

NavigatorLoop = function()
    MaybeReloadPins()
    MaybeReloadNavTreeExpansion()
    MaybeReloadNavExcluded()
    MaybeReloadNavIncluded()
    MaybeSyncViewModeProject()
    local project_tab_changed = NavigatorSyncProjectTab()
    ActiveViewUpdatePeaks()
    ReflexNavigatorPollExternalCommand()
    if view_history_restoring > 0 then view_history_restoring = view_history_restoring - 1 end

    local nt = r.CountTracks(0)
    local proj_state = r.GetProjectStateChangeCount(0)
    if nt == 0 or (#top_folders > 0 and not r.ValidatePtr(top_folders[1].track, "MediaTrack*")) then
        top_folders = {}
        render_list = {}
        song_entries = {}
        archive_entry = nil
        songs_entry_ref = nil
        for _, sg in ipairs(sub_groups) do sg.entry_ref = nil; sg.entries = {} end
        needs_rescan = true
        needs_song_rescan = true
        if nt > 0 then NavigatorRequestPinnedVisibilityReconcile() end
    elseif nt ~= last_track_count then
        needs_rescan = true
        needs_song_rescan = true
        NavigatorRequestPinnedVisibilityReconcile()
    elseif project_tab_changed then
        NavigatorRequestPinnedVisibilityReconcile()
    elseif proj_state ~= last_project_state then
        project_state_rescan_pending = true
        NavigatorRequestPinnedVisibilityReconcile()
    end
    if project_state_rescan_pending then
        local now = r.time_precise()
        if now - last_rescan_time >= RESCAN_THROTTLE then
            needs_rescan = true
            needs_song_rescan = true
        end
    end
    last_track_count = nt

    if needs_rescan and nt > 0 then
        ScanTopFolders()
        ScanSubGroups()
        BuildRenderList()
        last_rescan_time = r.time_precise()
        last_project_state = proj_state
        project_state_rescan_pending = false
    elseif not project_state_rescan_pending then
        last_project_state = proj_state
    end
    if pinned_visibility_reconcile_pending
        and nt > 0
        and not project_state_rescan_pending
        and not NavigatorSpecialViewActive() then
        local pins_changed = NavigatorReconcilePinnedVisibility()
        pinned_visibility_reconcile_pending = false
        if pins_changed then
            last_project_state = r.GetProjectStateChangeCount(0)
            project_state_rescan_pending = false
        end
    end

    if (not opt_live_mode or not songs_entry_ref) and current_page == "songs" then current_page = "tracks" end

    local main_bg = C.window_bg
    local nav_is_mac = NavigatorIsMacOS()
    local nav_standard_edge_gap = S(UI.edge_pad)
    local nav_chrome_gap_delta = nav_standard_edge_gap - 3
    local nav_use_reapertips_dock_compensation = nav_is_mac and NavigatorIsReapertipsTheme()
    local nav_pre_begin_dock_pos = NavigatorDockPosition(nav_current_dock_id)
    local nav_pre_begin_side_dock_pos = (nav_pre_begin_dock_pos == 1 or nav_pre_begin_dock_pos == 3)
        and nav_pre_begin_dock_pos or nav_last_side_dock_pos
    local nav_window_pad_x = (nav_window_docked
        and nav_use_reapertips_dock_compensation
        and nav_pre_begin_side_dock_pos == 3)
        and 3 or nav_standard_edge_gap
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), main_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), C.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), main_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), main_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), main_bg)
    local dock_color_count = 0
    local function pushDockColor(col_fn, color)
        if col_fn then
            local ok_col, col = pcall(col_fn)
            if ok_col and type(col) == "number" then
                local ok_push = pcall(r.ImGui_PushStyleColor, ctx, col, color)
                if ok_push then dock_color_count = dock_color_count + 1 end
            end
        end
    end
    local col_tab = r.ImGui_Col_Tab
    local col_sel = r.ImGui_Col_TabSelected or r.ImGui_Col_TabActive
    local col_hov = r.ImGui_Col_TabHovered
    local col_dim = r.ImGui_Col_TabDimmed or r.ImGui_Col_TabUnfocused
    local col_dimsel = r.ImGui_Col_TabDimmedSelected or r.ImGui_Col_TabUnfocusedActive
    pushDockColor(col_tab, main_bg)
    pushDockColor(col_sel, main_bg)
    pushDockColor(col_hov, main_bg)
    pushDockColor(col_dim, main_bg)
    pushDockColor(col_dimsel, main_bg)
    pushDockColor(r.ImGui_Col_TabSelectedOverline, main_bg)
    pushDockColor(r.ImGui_Col_TabDimmedSelectedOverline, main_bg)
    pushDockColor(r.ImGui_Col_Button, main_bg)
    pushDockColor(r.ImGui_Col_ButtonHovered, main_bg)
    pushDockColor(r.ImGui_Col_ButtonActive, main_bg)
    pushDockColor(r.ImGui_Col_NavHighlight, 0x00000000)
    pushDockColor(r.ImGui_Col_NavCursor, 0x00000000)
    pushDockColor(r.ImGui_Col_NavWindowingHighlight, 0x00000000)
    pushDockColor(r.ImGui_Col_NavWindowingDimBg, 0x00000000)
    pushDockColor(r.ImGui_Col_ResizeGrip, C.window_outline)
    pushDockColor(r.ImGui_Col_ResizeGripHovered, C.window_outline)
    pushDockColor(r.ImGui_Col_ResizeGripActive, C.window_outline)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), nav_window_pad_x, nav_standard_edge_gap)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), S(BASE_PAD_X), S(BASE_PAD_Y))
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), S(BASE_SPACING), S(BASE_SPACING))
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), nav_window_docked and 0 or S(10))
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ButtonTextAlign(), 0, 0.5)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
    local smooth_tess_count = 0
    if r.ImGui_StyleVar_CircleTessellationMaxError then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CircleTessellationMaxError(), 0.03)
        smooth_tess_count = 1
    end
    PushPopupStyle()

    if not window_initialized then
        local startup_w = nav_floating_user_w and nav_floating_user_w > 0 and nav_floating_user_w or S(240)
        local startup_h = nav_floating_user_h and nav_floating_user_h > 0 and nav_floating_user_h or S(420)
        r.ImGui_SetNextWindowSize(ctx, startup_w, startup_h)
        window_initialized = true
    end
    NavigatorEnsureDockingEnabled()
    if nav_dock_request ~= nil and r.ImGui_SetNextWindowDockID then
        if nav_dock_request == 0 then
            nav_pending_undock_snap = true
        end
        pcall(r.ImGui_SetNextWindowDockID, ctx, nav_dock_request)
        nav_dock_request = nil
    end
    if (nav_tlt_search_window_focus_requested_frames or 0) > 0 then
        if r.ImGui_SetNextWindowFocus then pcall(r.ImGui_SetNextWindowFocus, ctx) end
        nav_tlt_search_window_focus_requested_frames = nav_tlt_search_window_focus_requested_frames - 1
    end
    local min_nav_w = S(34)
    local min_window_w = S(UI.edge_pad) + min_nav_w + S(UI.edge_pad / 2) + 1
    local min_nav_dot_r = math.floor(min_nav_w / 2)
    local min_nav_row_h = min_nav_dot_r * 2 + S(3.75)
    local min_nav_visible_h = min_nav_row_h
    if not navigator_expanded and last_nav_collapsed_visible_h and last_nav_collapsed_visible_h > 0 then
        min_nav_visible_h = math.max(min_nav_visible_h, last_nav_collapsed_visible_h)
    end
    local min_bottom_pad = navigator_expanded and S(UI.edge_pad) or (S(UI.edge_pad / 2) + 1)
    local min_window_h = S(UI.edge_pad) + S(1.25) + min_nav_visible_h + min_bottom_pad
    local content_fit_window_h = min_window_h
    if navigator_expanded and last_nav_expanded_visible_h and last_nav_expanded_visible_h > 0 then
        local desired_window_h = S(UI.edge_pad) + S(1.25) + last_nav_expanded_visible_h + S(UI.edge_pad)
        content_fit_window_h = math.max(content_fit_window_h, math.min(desired_window_h, NavigatorMaxAutoWindowHeight()))
    end
    if not nav_window_docked and navigator_expanded then
        min_window_h = math.max(min_window_h, content_fit_window_h)
        if last_window_w and last_window_w > 0 and (not last_window_h or last_window_h < content_fit_window_h - 1) then
            r.ImGui_SetNextWindowSize(ctx, math.max(last_window_w, min_window_w), content_fit_window_h)
        end
    end
    if nav_pending_undock_snap then
        local snap_w, snap_h = NavigatorFloatingSnapSize(min_window_w, content_fit_window_h)
        r.ImGui_SetNextWindowSize(ctx, snap_w, snap_h)
        nav_suppress_floating_size_save = 3
        nav_pending_undock_snap = false
    end
    if not nav_window_docked and not navigator_expanded and nav_pending_collapse_snap_frames > 0 then
        local snap_w = nav_collapsed_return_w and nav_collapsed_return_w > 0 and nav_collapsed_return_w or last_window_w
        local snap_h = nav_collapsed_return_h and nav_collapsed_return_h > 0 and nav_collapsed_return_h or min_window_h
        r.ImGui_SetNextWindowSize(ctx, math.max(min_window_w, snap_w), math.max(min_window_h, snap_h))
        nav_suppress_floating_size_save = math.max(nav_suppress_floating_size_save, 3)
        nav_ignore_floating_size_until_mouse_up = true
        nav_pending_collapse_snap_frames = nav_pending_collapse_snap_frames - 1
    end
    r.ImGui_SetNextWindowSizeConstraints(ctx, min_window_w, min_window_h, 99999, 99999)

    local wflags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
    if r.ImGui_WindowFlags_NoTitleBar then
        wflags = wflags | r.ImGui_WindowFlags_NoTitleBar()
    end
    if r.ImGui_WindowFlags_NoFocusOnAppearing then
        wflags = wflags | r.ImGui_WindowFlags_NoFocusOnAppearing()
    end
    local visible, open = r.ImGui_Begin(ctx, "Navigator", true, wflags)
    if visible then
        local was_docked = nav_window_docked
        nav_window_docked = r.ImGui_IsWindowDocked and r.ImGui_IsWindowDocked(ctx) or false
        if r.ImGui_GetWindowDockID then
            local ok_dock, dock_id = pcall(r.ImGui_GetWindowDockID, ctx)
            if ok_dock and type(dock_id) == "number" then
                nav_current_dock_id = dock_id
            end
        else
            nav_current_dock_id = nav_window_docked and -1 or 0
        end
        local raw_nav_esc_pressed = TrackNavigatorEscapePressed()
        local nav_esc_pressed = opt_esc_key_to_close and raw_nav_esc_pressed
        if TrackNavigatorSearchShortcutPressed() then
            NavigatorRequestTltSearchFocus()
        end
        if (nav_tlt_search_window_focus_requested_frames or 0) > 0 and r.ImGui_SetWindowFocus then
            pcall(r.ImGui_SetWindowFocus, ctx)
        end
        local nav_expanded_before_draw = navigator_expanded
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
        local wx, wy = r.ImGui_GetWindowPos(ctx)
        local ww, wh = r.ImGui_GetWindowSize(ctx)
        last_window_w = ww
        last_window_h = wh
        if was_docked and not nav_window_docked then
            nav_pending_undock_snap = true
            nav_suppress_floating_size_save = 3
            nav_ignore_floating_size_until_mouse_up = true
        end
        if nav_window_docked then
            nav_floating_observed_w = 0
            nav_floating_observed_h = 0
        else
            local size_changed = nav_floating_observed_w > 0
                and (math.abs(ww - nav_floating_observed_w) > 1 or math.abs(wh - nav_floating_observed_h) > 1)
            local mouse_down = NavigatorMouseDown()
            if nav_suppress_floating_size_save > 0 then
                nav_suppress_floating_size_save = nav_suppress_floating_size_save - 1
            elseif nav_ignore_floating_size_until_mouse_up then
                if not mouse_down then nav_ignore_floating_size_until_mouse_up = false end
            elseif size_changed and mouse_down then
                NavigatorSaveFloatingUserSize(ww, wh)
            end
            nav_floating_observed_w = ww
            nav_floating_observed_h = wh
        end
        local fp = PushFont(GetScaledFont())
        local bw, win_h = r.ImGui_GetContentRegionAvail(ctx)
        local dock_pos = NavigatorDockPosition(nav_current_dock_id)
        local visual_dock_pos = nil
        if nav_window_docked and nav_use_reapertips_dock_compensation then
            visual_dock_pos = NavigatorVisualSideDockPosition(wx, ww, dock_pos)
        end
        nav_last_side_dock_pos = (visual_dock_pos == 1 or visual_dock_pos == 3) and visual_dock_pos or nil
        local nav_right_dock_width_offset = visual_dock_pos == 3 and 1 or 0
        local nav_right_dock_gap_offset = visual_dock_pos == 3 and 7 or 0
        if visual_dock_pos == 1 then
            bw = bw + nav_chrome_gap_delta
        elseif visual_dock_pos == 3 then
            if nav_window_pad_x == 3 then
                bw = math.max(0, bw - nav_chrome_gap_delta + nav_right_dock_width_offset + nav_right_dock_gap_offset)
            else
                r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) - nav_chrome_gap_delta)
                bw = bw + nav_chrome_gap_delta + nav_right_dock_width_offset + nav_right_dock_gap_offset
            end
        end
        if not nav_window_docked then
            bw = math.max(bw, min_nav_w)
        end
        local nav_body_x_offset = 0
        local nav_header_x_offset = 0
        local nav_ar_x_offset = 0
        if visual_dock_pos == 1 then
            nav_body_x_offset = -1
            nav_header_x_offset = -0.5
            nav_ar_x_offset = -0.5
        elseif visual_dock_pos == 3 then
            nav_body_x_offset = -nav_right_dock_gap_offset
            nav_header_x_offset = -nav_right_dock_gap_offset
            nav_ar_x_offset = -nav_right_dock_gap_offset - 0.5
        end
        nav_popup_active_this_frame = false
        nav_tlt_search_esc_consumed = false
        NavDrawSection({
            bw = bw,
            win_h = win_h,
            vh_row_h = 0,
            rem_h = 0,
            divider_h = 0,
            wx = wx,
            ww = ww,
            arrow_w = S(28),
            bh = S(BASE_H),
            base_pad_y = BASE_PAD_Y,
            nav_bottom_extra = 0,
            nav_context_scope = "window",
            nav_body_x_offset = nav_body_x_offset,
            nav_header_x_offset = nav_header_x_offset,
            nav_ar_x_offset = nav_ar_x_offset,
        })
        if not nav_window_docked and nav_expanded_before_draw ~= navigator_expanded then
            if navigator_expanded then
                nav_collapsed_return_w = ww
                nav_collapsed_return_h = wh
                nav_suppress_floating_size_save = math.max(nav_suppress_floating_size_save, 3)
                nav_ignore_floating_size_until_mouse_up = true
            else
                nav_pending_collapse_snap_frames = 2
            end
        end
        if nav_esc_pressed
            and not nav_tlt_search_esc_consumed
            and not nav_popup_active_this_frame
            and not nav_popup_active_previous_frame
            and not NavigatorAnyPopupOpen() then
            nav_quit_requested = true
        end
        nav_popup_active_previous_frame = nav_popup_active_this_frame
        NavDiagDrawReadout(bw)
        PopFont(fp)
        if not nav_window_docked then
            local outline_dl = r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(ctx) or r.ImGui_GetWindowDrawList(ctx)
            DrawTrackNavigatorWindowOutline(outline_dl, wx, wy, ww, wh, S(10), C.window_outline)
        end
        r.ImGui_PopStyleColor(ctx, 1)
        r.ImGui_End(ctx)
    end

    PopPopupStyle()
    r.ImGui_PopStyleVar(ctx, 7 + smooth_tess_count)
    r.ImGui_PopStyleColor(ctx, 5 + dock_color_count)

    ReflexApplyKeyboardPassthrough({ debug = NavDiagCapture })

    if open and not nav_quit_requested then r.defer(NavigatorLoop) end
end

ScanTopFolders()
ScanSubGroups()
BuildRenderList()
NavigatorLoop()
