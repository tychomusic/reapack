-- @noindex
--[[
 * Description: Folder visibility and collapse manager for REAPER sessions.
 *              Companion to Realist. Realist-styled UI.
 * Author:      S.Hansen / Tycho
 * Version:     20.676
 *
 * Click:       solo (if others visible) or toggle collapse (if alone)
 * CMD+click:   add/remove from visible set
 * OPT+click:   toggle pin
 * CTRL+click:  expand/collapse children
 * Shift+click: range select
 * Gear button: options menu (lower-left, on view history row)
 *
 * TRACKS tab:  click = toggle collapse all, CMD+click = show all
 * SONGS tab:   click = toggle collapse songs, CMD+click = show all songs
--]]

local r = reaper

-- Single source of truth for Reflex version. Update this when bumping
-- the header comment; used by settings panel title.
REFLEX_VERSION = "20.676"

ReflexDependencyError = function(detail)
    local msg = "Reflex requires ReaImGui 0.10 or newer."
    if detail and detail ~= "" then msg = msg .. "\n\n" .. tostring(detail) end
    if r.ReaPack_BrowsePackages then
        local choice = r.MB(msg .. "\n\nOpen ReaPack package browser for ReaImGui?", "Reflex: Missing dependency", 4)
        if choice == 6 then r.ReaPack_BrowsePackages("ReaImGui") end
    else
        r.MB(msg .. "\n\nInstall ReaImGui via ReaPack, then run Reflex again.", "Reflex: Missing dependency", 0)
    end
end

local imgui_api = r.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua'
local imgui_loader, imgui_load_err = loadfile(imgui_api)
if not imgui_loader then
    ReflexDependencyError(imgui_load_err)
    return
end

local imgui_ok, imgui_err = pcall(function() imgui_loader('0.10') end)
if not imgui_ok or not r.ImGui_CreateContext then
    ReflexDependencyError(imgui_err)
    return
end

-- =========================================================================
-- IMGUI BOOTSTRAP
-- =========================================================================
local ctx = r.ImGui_CreateContext("Reflex")

ReflexSetImGuiConfigBool = function(name, value)
    if not (r.ImGui_SetConfigVar and r["ImGui_ConfigVar_" .. name]) then return end
    local ok_var, var = pcall(r["ImGui_ConfigVar_" .. name])
    if ok_var and type(var) == "number" then
        pcall(r.ImGui_SetConfigVar, ctx, var, value and 1 or 0)
    end
end

ReflexSetImGuiConfigFlag = function(name, enabled)
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

ReflexSetImGuiConfigBool("NavEscapeClearFocusWindow", false)
ReflexSetImGuiConfigFlag("NavEnableKeyboard", false)

-- =========================================================================
-- EMBEDDED THEME
-- =========================================================================
local script_dir = debug.getinfo(1, 'S').source:match('@?(.*[/\\])') or ''
package.path = script_dir .. 'core/?.lua;' .. script_dir .. '?.lua;' .. package.path

local nav_theme = {
    fonts = {
        body_size = 14,
        family = "SF Pro",
    },
    colors = {
        fx_instr_txt = 0x324bd0,
        vol_slider_fill = 0x3d83ff,
        vol_slider_mark = 0x171b22,
        vol_slider_mark_over = 0x171b22,
        vol_slider_mark_intersect = 0x171b22,
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

-- Theme helpers
rgb = function(hex) return (hex << 8) | 0xFF end
ntc = function(section, key, fallback)
    local s = nav_theme[section]
    if s and s[key] then return rgb(s[key]) end
    return fallback
end

-- Knob arc sweep constants (270° arc from 7:30 to 4:30 clock positions)
KNOB_ANGLE_MIN = math.pi * 0.75
KNOB_ANGLE_MAX = math.pi * 2.25
KNOB_ANGLE_MID = (KNOB_ANGLE_MIN + KNOB_ANGLE_MAX) / 2

-- =========================================================================
-- MODIFIER KEYS
-- =========================================================================
ReflexKeyValue = function(name)
    local v = r[name]
    if type(v) == "function" then
        local ok, key = pcall(v)
        if ok and type(key) == "number" then return key end
    elseif type(v) == "number" then
        return v
    end
    return nil
end

ReflexIsMacOS = function()
    local os = r.GetOS and r.GetOS() or ""
    return os:find("OSX", 1, true) ~= nil
        or os:find("macOS", 1, true) ~= nil
        or os:find("Mac", 1, true) ~= nil
end

ReflexReaperThemeName = function()
    if not r.GetLastColorThemeFile then return nil end
    local ok, path = pcall(r.GetLastColorThemeFile)
    if not ok or type(path) ~= "string" or path == "" then return nil end
    local name = path:match("([^/\\]+)$") or path
    name = name:gsub("%.ReaperThemeZip$", ""):gsub("%.ReaperTheme$", "")
    return name
end

ReflexIsReapertipsTheme = function()
    local name = ReflexReaperThemeName()
    if not name then return false end
    return name:lower():find("reapertips", 1, true) ~= nil
end

ReflexDockPosition = function(dock_id)
    if type(dock_id) ~= "number" or dock_id >= 0 or not r.DockGetPosition then return nil end
    local ok, dock_pos = pcall(r.DockGetPosition, ~dock_id)
    if ok and type(dock_pos) == "number" then return dock_pos end
    return nil
end

ReflexVisualSideDockPosition = function(wx, ww, dock_pos)
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

ReflexModFlag = function(mods, fallback, ...)
    mods = tonumber(mods) or 0
    if fallback and (mods & fallback) ~= 0 then return true end
    for i = 1, select("#", ...) do
        local key = ReflexKeyValue(select(i, ...))
        if key and (mods & key) ~= 0 then return true end
    end
    return false
end

ReflexKeyDown = function(...)
    if not r.ImGui_IsKeyDown then return false end
    for i = 1, select("#", ...) do
        local key = ReflexKeyValue(select(i, ...))
        if key then
            local ok_down, down = pcall(r.ImGui_IsKeyDown, ctx, key)
            if ok_down and down == true then return true end
        end
    end
    return false
end

IsCmd = function(mods)
    return ReflexModFlag(mods, 0x8, "ImGui_Mod_Super", "ImGui_Mod_Shortcut", "ImGui_KeyModFlags_Super")
        or ReflexMacPrimaryAlias(mods)
        or ReflexKeyDown("ImGui_Key_ModSuper", "ImGui_Key_LeftSuper", "ImGui_Key_RightSuper")
end

IsShift = function(mods)
    return ReflexModFlag(mods, 0x2, "ImGui_Mod_Shift", "ImGui_KeyModFlags_Shift")
        or ReflexKeyDown("ImGui_Key_ModShift", "ImGui_Key_LeftShift", "ImGui_Key_RightShift")
end

IsAlt = function(mods)
    return ReflexModFlag(mods, 0x4, "ImGui_Mod_Alt", "ImGui_KeyModFlags_Alt")
        or ReflexKeyDown("ImGui_Key_ModAlt", "ImGui_Key_LeftAlt", "ImGui_Key_RightAlt")
end

IsCtrl = function(mods)
    if ReflexMacPrimaryAlias(mods) then return false end
    return ReflexModFlag(mods, 0x1, "ImGui_Mod_Ctrl", "ImGui_KeyModFlags_Ctrl")
        or ReflexKeyDown("ImGui_Key_ModCtrl", "ImGui_Key_LeftCtrl", "ImGui_Key_RightCtrl")
end

ReflexMacPrimaryAlias = function(mods)
    return ReflexIsMacOS()
        and ReflexModFlag(mods, 0x1000, "ImGui_Key_ModCtrl")
end

TrackNavigatorModState = function(mods)
    mods = tonumber(mods) or 0
    local ctrl = IsCtrl(mods)
    local cmd_alias = ReflexMacPrimaryAlias(mods)
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

-- =========================================================================
-- PREFERENCES
-- =========================================================================
local PREF = "reflex"
REFLEX_NAVIGATOR_INSTANCE_KEY = "reflex_navigator_instance_token"
REFLEX_NAVIGATOR_COMMAND_KEY = "reflex_navigator_external_command"
reflex_navigator_instance_token = "reflex:" .. tostring({}) .. ":" .. tostring(r.time_precise and r.time_precise() or os.clock())
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

LoadPrefString = function(key, default)
    local v = r.GetExtState(PREF, key)
    if v == "" then return default end
    return v
end

SavePref = function(key, val)
    r.SetExtState(PREF, key, type(val) == "boolean" and (val and "1" or "0") or tostring(val), true)
end

opt_expand_children       = LoadPref("expand_children", false)
opt_songs_expand          = LoadPref("songs_expand_children", false)
opt_viewlock              = LoadPref("view_lock", false)
opt_live_mode             = LoadPref("tycho_live_mode", false) -- hidden: Tycho/Realist MONITORS/I/O/SONGS rules
opt_nav_ignore_archive    = LoadPref("nav_ignore_archive", true) -- public: auto-ignore ARCHIVE tracks in NAV
opt_nav_tlt_expand        = LoadPref("nav_tlt_expand", true)
opt_nav_show_search       = LoadPref("nav_show_search", true)
opt_nav_custom_set_mode   = LoadPref("nav_custom_set_mode", false)
opt_nav_indent_tlts       = LoadPref("nav_indent_tlts", true)
opt_nav_flip_indent       = LoadPref("nav_flip_indent", false)
opt_helper_tooltips       = LoadPref("helper_tooltips", false)
opt_view_mode_restore_arrange = LoadPref("view_mode_restore_arrange", false)
local ui_scale            = LoadPref("ui_scale_v2", nil)
if ui_scale == nil then
    local old = LoadPref("ui_scale", nil)
    ui_scale = old and math.floor(old / 0.8 * 100 + 0.5) / 100 or 1.0
    SavePref("ui_scale_v2", ui_scale)
end
nav_ui_scale              = LoadPref("navigator_scale_v1", nil) -- global: shared NAV scale for Reflex + standalone Navigator
if nav_ui_scale == nil then
    nav_ui_scale = ui_scale
    SavePref("navigator_scale_v1", nav_ui_scale)
end
local REFLEX_BODY_SCALE_MULT = 0.9
local reflex_body_scale_compensation_enabled = true
ReflexRawUiScale = function()
    return ui_scale or 1.0
end
ReflexEffectiveUiScale = function()
    local scale = ReflexRawUiScale()
    if reflex_body_scale_compensation_enabled then scale = scale * REFLEX_BODY_SCALE_MULT end
    return scale
end
ReflexSetBodyScaleCompensation = function(enabled)
    local previous = reflex_body_scale_compensation_enabled
    reflex_body_scale_compensation_enabled = enabled ~= false
    return previous
end
opt_instr_first           = LoadPref("instr_first", false)  -- global: no local slot
-- v20.449: Per-track FX count cache for instruments-first cross-surface
-- detection. Loop's MonitorTrackFxCounts compares live count against this map;
-- any track whose count grows triggers InspMoveNewInstruments. Catches all
-- add paths uniformly (sends columns, folder cards, distant sends, flow
-- chain, REAPER's UI, scripts). Replaces v20.445's registration system,
-- which only fired for Reflex-initiated browser opens and expired entries
-- after 120 frames.
nav_track_fx_counts = {}
-- v20.445/v20.448: Startup focus grab. Multi-attempt because ImGui/OS may take
-- a few frames to settle window state on script open; single-shot wasn't enough.
nav_focus_frame = 0
nav_focus_done  = false
opt_fx_float              = LoadPref("fx_float", true)      -- global: true=float, false=chain
opt_vol_track_color       = LoadPref("vol_track_color", false) -- global: vol fill follows track color
opt_show_sends            = LoadPref("show_sends", true)     -- global: always show sends section
opt_show_master_track     = LoadPref("show_master_track", true)
master_track_guid         = LoadPrefString("master_track_guid", "")
master_track_expanded     = false
opt_two_column_mode       = LoadPref("two_column_mode", false)
opt_two_column_nav        = LoadPref("two_column_nav", true)
two_column_left_w         = LoadPref("two_column_left_w", nil)
opt_tooltips              = LoadPref("tooltips", true)       -- global: show hover tooltips
opt_card_boxes            = true                                 -- always-on internal param (deprecated UI toggle removed v20.370)
opt_conform_sends         = LoadPref("conform_sends", false)  -- global: auto-group returns into Returns folder

-- =========================================================================
-- FONTS (pre-create at each UI scale step for runtime scaling)
-- =========================================================================
local body_size = (nav_theme.fonts and nav_theme.fonts.body_size) or 14
-- v20.444: explicit family lookup. Default "SF Pro" (macOS system font, neo-grotesque,
-- replaces Helvetica Neue). ReaImGui falls back to system sans-serif if the named
-- family isn't installed.
local body_family = (nav_theme.fonts and nav_theme.fonts.family) or 'SF Pro'
local scaled_fonts = {}
local scaled_fonts_italic = {}
local scaled_fonts_regular = {}
local scaled_font_sizes = {}
CreateReflexFont = function(family, flags)
    return r.ImGui_CreateFont(family, flags)
end
for step = 5, 20 do
    local scale = step / 10
    local sz = math.floor(body_size * scale + 0.5)
    local f = CreateReflexFont(body_family, r.ImGui_FontFlags_Bold())
    r.ImGui_Attach(ctx, f)
    scaled_fonts[step] = f
    if f then scaled_font_sizes[f] = sz end
    local fi = CreateReflexFont(body_family, r.ImGui_FontFlags_Bold() | r.ImGui_FontFlags_Italic())
    r.ImGui_Attach(ctx, fi)
    scaled_fonts_italic[step] = fi
    if fi then scaled_font_sizes[fi] = sz end
    local fr = CreateReflexFont(body_family, r.ImGui_FontFlags_None())
    r.ImGui_Attach(ctx, fr)
    scaled_fonts_regular[step] = fr
    if fr then scaled_font_sizes[fr] = sz end
end

local reflex_imgui_push_font = r.ImGui_PushFont
r.ImGui_PushFont = function(ctx_arg, font, size)
    if size == nil then
        if font ~= nil and scaled_font_sizes[font] then
            size = scaled_font_sizes[font]
        elseif r.ImGui_GetFontSize then
            local ok_size, current_size = pcall(r.ImGui_GetFontSize, ctx_arg)
            if ok_size and type(current_size) == "number" then size = current_size end
        end
    end
    if size ~= nil then return reflex_imgui_push_font(ctx_arg, font, size) end
    return reflex_imgui_push_font(ctx_arg, font)
end

package.loaded["Reflex_FontCore"] = nil
require("Reflex_FontCore")({
    r = r,
    ctx = ctx,
    scaled_fonts = scaled_fonts,
    scaled_fonts_italic = scaled_fonts_italic,
    scaled_fonts_regular = scaled_fonts_regular,
    font_sizes = scaled_font_sizes,
    get_ui_scale = function() return ReflexEffectiveUiScale() end,
})

-- =========================================================================
-- THEME (Reflex-owned; future user-facing customization should live in Options)
-- =========================================================================
local C = {
    bg          = rgb(0x171B22),  -- Reflex window/panel bg (charcoal) / card fill
    window_bg   = rgb(0x3E3E3F),  -- base window bg when card_boxes enabled
    window_outline = rgb(0x525254),
    card_stroke = rgb(0x2B2F36),  -- card border stroke
    border      = rgb(0x30363D),
    text        = rgb(0xE6EDF3),
    text_dim    = rgb(0x8B949E),
    text_muted  = rgb(0x484F58),
    green       = rgb(0x3FB950),
    green_dim   = rgb(0x1A3D2A),
    amber_dim   = rgb(0x5C4A1A),
    pan_color   = rgb(0xDB8320),
    pan_dim     = rgb(0x5C3810),
    amber       = rgb(0xD29922),
    midi_activity = rgb(0xFFCC00),
    input_meter_bg = rgb(0x4A5060),
    btn_bg      = rgb(0x21262D),
    btn_hover   = rgb(0x30363D),
    btn_active  = rgb(0x3A424B),
    tab_sel_bg  = rgb(0x6E7681),
    tab_sel_hov = rgb(0x7D8590),
    tab_sel_txt = rgb(0x0D1117),
    -- Inspector
    fx_offline_bg   = rgb(0x15191E),
    fx_offline_txt  = rgb(0xF85149),
    fx_bypassed_txt = rgb(0xD29922),
    fx_bypass_env   = rgb(0xC0A0F0),
    fx_drywet_txt   = rgb(0x6B9BD2),
    fx_env_text     = rgb(0xBB99DD),
    fx_wrapper_text = rgb(0x8B949E),
    fx_send_text    = rgb(0x58A6FF),
    fx_instr_txt    = rgb(0x1643D6),
    fx_ctrl_bg      = rgb(0x2A2F37),
    fx_ctrl_hover   = rgb(0x363C46),
    fx_ctrl_active  = rgb(0x424950),
    fx_power_on     = rgb(0x3D83FF), -- Renders near sampled #5784FC in ReaImGui output.
    fx_power_off    = rgb(0x636568),
    fx_power_bg     = rgb(0x3B4048),
    fx_power_hover  = rgb(0x464B54),
    fx_power_byp_bg = rgb(0x282C31),
    fx_power_byp_hover = rgb(0x30343A),
    fx_power_offline = rgb(0x613335),
    fx_cat_generic = rgb(0x7E7F81),
    fx_cat_instrument = rgb(0x4B90FF),
    fx_cat_container = rgb(0xCDA550),
    fx_cat_harmonics = rgb(0xBC5348),
    fx_cat_eq = rgb(0x69C2C1),
    fx_cat_compression = rgb(0xD18A51),
    fx_byp_env_active = rgb(0x525357),
    fx_byp_env_active_hov = rgb(0x727275),
    cmp_a           = rgb(0x3FB950),
    cmp_b           = rgb(0x3D83FF),
    cmp_a_dim       = rgb(0x1A3D2A),
    cmp_b_dim       = rgb(0x1E3A5F),
    cmp_aware_bg    = rgb(0x363C46),
    cmp_aware_txt   = rgb(0xA0A8B4),
    section_text    = rgb(0x555D67),
    track_cap_none  = rgb(0x2A2F37),
    vol_bar         = rgb(0x89FFDB),
    vol_bar_bg      = rgb(0x171B22),
    vol_slider_bg   = rgb(0x262A2E),
    vol_slider_fill = rgb(0x858789),
    vol_slider_handle = rgb(0xE6EDF3),
    vol_slider_handle_active = rgb(0xFFFFFF),
    vol_slider_mark = rgb(0x171B22),
    vol_slider_mark_over = rgb(0x171B22),
    vol_slider_mark_intersect = rgb(0x171B22),
    pan_slider_fill = rgb(0xF8BE2E),
    env_vol_dot     = rgb(0x6ABE74),
    pan_bar         = rgb(0xE8A657),
    env_row_bg      = rgb(0x363C46),
    fx_row_bg       = nil,  -- falls back to btn_bg if nil
    fx_row_border   = nil,  -- no border if nil
    flow_source_bg  = rgb(0x1E2228),  -- flow view source track header bg (default = fx_row_bg)
    route_parent    = rgb(0x3D83FF),
    route_parent_dim= rgb(0x1E3050),
    route_send      = rgb(0xD29922),
    route_send_dim  = rgb(0x3D2E10),
    route_recv      = rgb(0xF85149),
    route_recv_dim  = rgb(0x4A1A18),
    route_hw        = rgb(0x8E959E),
    route_dim       = rgb(0x484F58),
    route_bg        = rgb(0x2A2F37),
    source_stroke   = rgb(0xD29922),  -- source track card outline; aliased to C.amber after overrides
    send_stroke     = rgb(0xFFFFFF),  -- send/return module + folder card outline
    flow_stroke     = rgb(0xC4C4C4),  -- selected flow-card outline
    -- Mute/Solo button state colors
    record_arm      = rgb(0xFF4A4A),
    record_arm_act  = rgb(0xC25353),
    mute_hov        = rgb(0xD9453F),
    mute_act        = rgb(0xC25353),
    solo_bg         = rgb(0xF1B70A),
    solo_hov        = rgb(0xF1B70A),
    solo_act        = rgb(0xF1B70A),
    -- FX row active press
    fx_row_active   = rgb(0x48505C),
    -- Routing separator
    route_sep       = rgb(0x22252B),
    -- Route row cards
    route_section_text = rgb(0x5E626B),
    route_row_bg      = rgb(0x2A2D34),
    route_row_bg_hov  = rgb(0x32353C),
    route_row_btn     = rgb(0x3A4049),
    route_row_btn_row_hov = rgb(0x424851),
    route_row_btn_hov = rgb(0x464D58),
    route_row_btn_hov_row_hov = rgb(0x4E5560),
    route_row_btn_act = rgb(0x525A62),
    route_row_btn_act_row_hov = rgb(0x5A626A),
    -- Distant sends
    distant_bg      = rgb(0x202227),
    sc_badge        = rgb(0x2775DE),
    -- Placeholder
    placeholder_bg  = rgb(0x333436),
    -- Background-level section labels (distant sends, selected track, etc.)
    bg_label        = rgb(0x5C5C5C),
    -- Settings separator
    settings_sep    = rgb(0x2D2F35),
    -- Inspect arrow
    inspect_arrow   = rgb(0x2B2F36),
    inspect_arrow_hov = rgb(0xEABE3E),
    -- FX drag-and-drop visuals (v20.403)
    fx_drag_move    = rgb(0xD29922),  -- amber: move destination/indicator
    fx_drag_copy    = rgb(0x73A3F4),  -- muted blue: copy/clipboard destination/indicator
    fx_drag_source  = rgb(0xA4A4A4),  -- bright active source-row drag outline
    fx_sel_outline  = rgb(0xA4A4A4),  -- selected FX row outline
    fx_focus_outline = rgb(0x4B5059), -- focused floating FX window row outline
    -- FX clipboard carry visuals (v20.407)
    fx_clip_carry   = rgb(0x73A3F4),  -- muted blue: clipboard carrying/source rows/indicator/chip
}

-- Apply embedded color overrides captured from the former Reflex_Theme.lua.
local theme_colors = nav_theme.colors or {}
for key, hex in pairs(theme_colors) do
    if type(hex) == "number" then
        C[key] = rgb(hex)
    end
end
C.vol_slider_fill = C.fx_power_on
C.route_parent = C.fx_power_on
C.cmp_b = C.fx_power_on
C.mute_act = C.record_arm_act
C.source_stroke = C.amber

-- Icon primitives: draw +/-/× via DrawList rects/lines centered at (cx, cy).
-- Font-independent and scale-perfect. Always use these, never CalcTextSize("+")
-- + AddText — text glyphs have font-specific ascent/descent padding that makes
-- their visual center ≠ bounding-box center, and the offset changes with scale.
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

ArrowFontSize = function(font, target_w, glyph)
    target_w = math.max(1, target_w or 1)
    if not font then return target_w end
    r.ImGui_PushFont(ctx, font, target_w)
    local gw = r.ImGui_CalcTextSize(ctx, glyph)
    r.ImGui_PopFont(ctx)
    if not gw or gw <= 0 then return target_w end
    return math.max(1, target_w * (target_w / gw))
end

DrawArrowIcon = function(dl, cx, cy, size, direction, col)
    size = math.max(1, size or S(10))
    local glyphs = {
        right = "\xE2\x96\xB6",
        down = "\xE2\x96\xBC",
        up = "\xE2\x96\xB2",
        left = "\xE2\x97\x80",
    }
    local glyph = glyphs[direction or "right"] or glyphs.right
    local font = GetScaledFont and GetScaledFont()
    local font_size = ArrowFontSize(font, size, glyphs.right)
    if font then r.ImGui_PushFont(ctx, font, font_size) end
    local gw = r.ImGui_CalcTextSize(ctx, glyph)
    local th = r.ImGui_GetTextLineHeight(ctx)
    local dx = -S(1.375)
    if direction == "down" then dx = -S(2) end
    local tx = Round(cx - gw * 0.5 + dx)
    local ty = Round(cy - th * 0.5 - S(1.375))
    r.ImGui_DrawList_AddText(dl, tx, ty, col, glyph)
    if font then r.ImGui_PopFont(ctx) end
end

DrawDownArrowGlyphMeasured = function(dl, center_x, tip_y, target_w, col)
    local glyph = "\xE2\x96\xBC"
    local font = GetScaledFont and GetScaledFont()
    local font_size = ArrowFontSize(font, target_w, glyph)
    if font then r.ImGui_PushFont(ctx, font, font_size) end
    local gw, gh = r.ImGui_CalcTextSize(ctx, glyph)
    local tx = center_x - gw * 0.5
    local ty = tip_y - gh
    r.ImGui_DrawList_AddText(dl, tx, ty, col, glyph)
    if font then r.ImGui_PopFont(ctx) end
    return tx, ty, tx + gw, ty + gh
end

ArrowDirFromContent = function(content)
    if content == "\xE2\x96\xB6" then return "right" end
    if content == "\xE2\x96\xBC" then return "down" end
    if content == "\xE2\x96\xB2" then return "up" end
    if content == "\xE2\x97\x80" then return "left" end
    return nil
end

-- Draw a dashed outline tracing a rounded rectangle (v20.404). Traces the
-- full perimeter including arc corners as a dense polyline, then walks it
-- with a dash/gap cursor emitting AddLine per tiny sub-segment. This makes
-- the dashes actually follow the card's rounded edge — the v20.403 helper
-- skipped corners entirely, which read as 4 floating segments instead of
-- a unified outline. Use this to match a card's real corner radius.
DrawDashedRoundedRect = function(dl, x1, y1, x2, y2, col, rounding, thickness, dash_len, gap_len)
    thickness = thickness or math.max(1, S(1.5))
    rounding = rounding or 0
    dash_len = dash_len or math.max(4, S(5))
    gap_len = gap_len or math.max(2, S(3))
    -- Clamp rounding to half the smaller dimension (pure-circle degenerate case)
    local rr = math.min(rounding, math.min((x2 - x1) / 2, (y2 - y1) / 2))
    if rr < 0 then rr = 0 end

    -- Polyline tracing the perimeter clockwise, starting at top-edge left end.
    -- Segments per corner scale with radius for smoothness at larger sizes.
    local pts = {}
    local function add(x, y) pts[#pts+1] = x; pts[#pts+1] = y end
    local seg_c = math.max(6, math.ceil(rr * 0.6))

    if rr > 0 then
        add(x1 + rr, y1)                  -- start of top edge
        add(x2 - rr, y1)                  -- end of top edge / start of TR corner
        for i = 1, seg_c do               -- TR corner arc: -90° → 0°
            local a = -math.pi/2 + (math.pi/2) * (i / seg_c)
            add(x2 - rr + math.cos(a) * rr, y1 + rr + math.sin(a) * rr)
        end
        add(x2, y2 - rr)                  -- end of right edge / start of BR corner
        for i = 1, seg_c do               -- BR corner arc: 0° → 90°
            local a = (math.pi/2) * (i / seg_c)
            add(x2 - rr + math.cos(a) * rr, y2 - rr + math.sin(a) * rr)
        end
        add(x1 + rr, y2)                  -- end of bottom edge / start of BL corner
        for i = 1, seg_c do               -- BL corner arc: 90° → 180°
            local a = math.pi/2 + (math.pi/2) * (i / seg_c)
            add(x1 + rr + math.cos(a) * rr, y2 - rr + math.sin(a) * rr)
        end
        add(x1, y1 + rr)                  -- end of left edge / start of TL corner
        for i = 1, seg_c do               -- TL corner arc: 180° → 270°
            local a = math.pi + (math.pi/2) * (i / seg_c)
            add(x1 + rr + math.cos(a) * rr, y1 + rr + math.sin(a) * rr)
        end
    else
        add(x1, y1); add(x2, y1); add(x2, y2); add(x1, y2); add(x1, y1)
    end

    -- Walk the polyline with a dash-phase cursor. Each tiny polyline edge
    -- is walked; while in_dash, emit an AddLine for the walked fragment.
    local in_dash = true
    local remaining = dash_len
    for i = 1, #pts - 3, 2 do
        local ax, ay = pts[i], pts[i+1]
        local bx, by = pts[i+2], pts[i+3]
        local seg_len = math.sqrt((bx - ax)^2 + (by - ay)^2)
        if seg_len > 0.01 then
            local dx, dy = (bx - ax) / seg_len, (by - ay) / seg_len
            local trav = 0
            local cx, cy = ax, ay
            while trav < seg_len do
                local step = math.min(seg_len - trav, remaining)
                local nx = cx + dx * step
                local ny = cy + dy * step
                if in_dash then
                    r.ImGui_DrawList_AddLine(dl, cx, cy, nx, ny, col, thickness)
                end
                cx, cy = nx, ny
                trav = trav + step
                remaining = remaining - step
                if remaining <= 0.001 then
                    in_dash = not in_dash
                    remaining = in_dash and dash_len or gap_len
                end
            end
        end
    end
end

-- ── Nav button primitives ────────────────────────────────────────────────
-- Four canonical shapes: NavSquare, NavCircle, NavPill, NavRect.
-- All accept (id, x, y, ..., content, opts?) and return hov, clicked, active.
-- content: "+"/"-"/"×"/"x" → drawlist icons, arrows → disclosure glyphs, any other string → centered text,
--          nil → no content (caller draws its own).
-- opts (all optional):
--   bg, hov, active                colors — default to style table (C.fx_ctrl_bg/hover/active for square/circle/rect)
--   fg, fg_hov, fg_active          content colors — default C.text_dim → C.text
--   arrow_size                     explicit arrow glyph target size; defaults to min(w,h)*0.52
--   arrow_dx, arrow_dy             final arrow center offset in logical pixels
--   icon_size_mult, icon_dx, icon_dy final drawn-icon size/center adjustments for +/-/x icons
--   rounding                       number, or table {tl, tr, br, bl} with per-corner radii
--                                  (only nonzero corners rounded; zero corners stay square)
--   hit_w, hit_h                   override invisible hit-rect dims (used when hit area > visual)
--   no_press                       if true, skip active-state bg (useful when caller handles press state)
-- Defaults pulled from C after C is built; see NAV_DEFAULT init below.

local NAV_DEFAULT = {
    square = {bg = 0, hov = 0, active = 0, fg = 0, fg_hov = 0, fg_active = 0, rounding = 3},
    circle = {bg = 0, hov = 0, active = 0, fg = 0, fg_hov = 0, fg_active = 0},
    pill   = {bg = 0, hov = 0, active = 0, fg = 0, fg_hov = 0, fg_active = 0},
    rect   = {bg = 0, hov = 0, active = 0, fg = 0, fg_hov = 0, fg_active = 0, rounding = 3},
}
NAV_CIRCLE_SEGMENTS = 96

NavInitDefaults = function()
    local function set(t, bg, hov, act)
        t.bg, t.hov, t.active = bg, hov, act
        t.fg, t.fg_hov, t.fg_active = C.text_dim, C.text, C.text
    end
    set(NAV_DEFAULT.square, C.fx_ctrl_bg, C.fx_ctrl_hover, C.fx_ctrl_active)
    set(NAV_DEFAULT.circle, C.fx_ctrl_bg, C.fx_ctrl_hover, C.fx_ctrl_active)
    set(NAV_DEFAULT.rect,   C.fx_ctrl_bg, C.fx_ctrl_hover, C.fx_ctrl_active)
    set(NAV_DEFAULT.pill,   C.route_bg,   C.fx_ctrl_hover, C.fx_ctrl_active)
end

-- Resolve rounding: number → (r, ALL flag); table → (max_r, per-corner flag mask); nil → default.
NavRounding = function(opts_r, default_r)
    local ro = opts_r
    if ro == nil then ro = default_r end
    if type(ro) == "number" then
        return ro, r.ImGui_DrawFlags_RoundCornersAll()
    end
    if type(ro) == "table" then
        local flags = 0
        local max_r = 0
        if ro.tl and ro.tl > 0 then flags = flags | r.ImGui_DrawFlags_RoundCornersTopLeft();     if ro.tl > max_r then max_r = ro.tl end end
        if ro.tr and ro.tr > 0 then flags = flags | r.ImGui_DrawFlags_RoundCornersTopRight();    if ro.tr > max_r then max_r = ro.tr end end
        if ro.bl and ro.bl > 0 then flags = flags | r.ImGui_DrawFlags_RoundCornersBottomLeft();  if ro.bl > max_r then max_r = ro.bl end end
        if ro.br and ro.br > 0 then flags = flags | r.ImGui_DrawFlags_RoundCornersBottomRight(); if ro.br > max_r then max_r = ro.br end end
        if flags == 0 then return 0, r.ImGui_DrawFlags_RoundCornersNone() end
        return max_r, flags
    end
    return 0, r.ImGui_DrawFlags_RoundCornersAll()
end

-- Resolve the drawn content color based on state.
-- Priority: explicit state override → explicit base (stays on hover) → default transition.
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

-- Resolve the drawn background color based on state.
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

-- Per-glyph optical centering offsets (pixels at ui_scale=1).
-- ImGui only exposes advance-width and line-height, not ink bbox. These
-- offsets compensate by eye. Calibrated for the current body font;
-- re-tune if font family changes. Scaled by S() at apply time.
GLYPH_NUDGE = {
    ["A"] = { dx = 0, dy = 0 },
    ["B"] = { dx = 0, dy = 0 },
    ["M"] = { dx = 0, dy = 0 },
    ["S"] = { dx = 0, dy = 0 },
    ["V"] = { dx = 0, dy = 0 },
    ["P"] = { dx = 0, dy = 0 },
}

-- Draw centered content within rect (x, y, w, h).
-- +/-/× go through DrawIcon at the rect center; text uses CalcTextSize,
-- centers on exact integer pixels, then applies per-glyph optical offset.
NavDrawContent = function(dl, x, y, w, h, content, fg, opts)
    if content == nil or content == "" then return end
    opts = opts or {}
    local arrow_dir = ArrowDirFromContent(content)
    if arrow_dir then
        DrawArrowIcon(dl, x + w / 2 + (opts.arrow_dx or 0), y + h / 2 + (opts.arrow_dy or 0),
            opts.arrow_size or (math.min(w, h) * 0.52), arrow_dir, fg)
    elseif content == "+" or content == "-" or content == "x" or content == "×" then
        DrawIcon(dl, x + w / 2 + (opts.icon_dx or 0), y + h / 2 + (opts.icon_dy or 0),
            math.min(w, h) * (opts.icon_size_mult or 1), content, fg)
    else
        local tw, th = r.ImGui_CalcTextSize(ctx, content)
        local tx = Round(x + (w - tw) / 2)
        local ty = Round(y + (h - th) / 2)
        r.ImGui_DrawList_AddText(dl, tx, ty, fg, content)
    end
end

-- All primitives: caller sets cursor (window OR screen coords) BEFORE calling.
-- Primitives place InvisibleButton at the current cursor pos and read back
-- GetItemRectMin for drawing, so they work equally with SetCursorPos or
-- SetCursorScreenPos. Returns (hov, clicked, active).

-- Rectangle button. rounding defaults to 3.
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
    NavDrawContent(dl, x, y, w, h, content, fg, opts)
    return hov, clicked, active
end

-- Square button. Identical to NavRect (semantic alias for w≈h icon squares).
NavSquare = function(id, w, h, content, opts)
    return NavRect(id, w, h, content, opts)
end

-- Circle button. Invisible hit rect = diameter × (opts.hit_h or diameter).
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
    NavDrawContent(dl, x, y, hit_w, hit_h, content, fg, opts)
    return hov, clicked, active
end

-- Pill button: rounding = h/2.
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
    NavDrawContent(dl, x, y, w, h, content, fg, opts)
    return hov, clicked, active
end

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

    r.ImGui_DrawList_PushClipRect(dl, x1, y1, x2, y2, true)
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

DrawHighResRoundedRectFilled = function(dl, x1, y1, x2, y2, col, rounding)
    local cr = math.max(0, math.min(rounding or 0, math.min(x2 - x1, y2 - y1) * 0.5))
    if cr <= 0 or not (r.ImGui_DrawList_PathClear and r.ImGui_DrawList_PathArcTo and r.ImGui_DrawList_PathFillConvex) then
        r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, col, cr)
        return
    end
    local pi = math.pi
    local segs = math.max(12, Round(cr * 1.75))
    r.ImGui_DrawList_PathClear(dl)
    r.ImGui_DrawList_PathArcTo(dl, x1 + cr, y1 + cr, cr, pi, pi * 1.5, segs)
    r.ImGui_DrawList_PathArcTo(dl, x2 - cr, y1 + cr, cr, pi * 1.5, pi * 2, segs)
    r.ImGui_DrawList_PathArcTo(dl, x2 - cr, y2 - cr, cr, 0, pi * 0.5, segs)
    r.ImGui_DrawList_PathArcTo(dl, x1 + cr, y2 - cr, cr, pi * 0.5, pi, segs)
    r.ImGui_DrawList_PathFillConvex(dl, col)
end

DrawSolidRoundedRectOutline = function(dl, x1, y1, x2, y2, col, rounding, thickness)
    local t = thickness or SOURCE_STROKE_W or 1.5
    local w = x2 - x1
    local h = y2 - y1
    if w <= 0 or h <= 0 or t <= 0 then return end

    local cr = math.max(0, math.min(rounding or 0, math.min(w, h) * 0.5))
    if cr <= t or not (r.ImGui_DrawList_PathClear and r.ImGui_DrawList_PathArcTo and r.ImGui_DrawList_PathStroke) then
        r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, math.min(y2, y1 + t), col)
        r.ImGui_DrawList_AddRectFilled(dl, x1, math.max(y1, y2 - t), x2, y2, col)
        r.ImGui_DrawList_AddRectFilled(dl, x1, y1, math.min(x2, x1 + t), y2, col)
        r.ImGui_DrawList_AddRectFilled(dl, math.max(x1, x2 - t), y1, x2, y2, col)
        return
    end

    local inner_r = math.max(0, cr - t)
    local straight_x1 = x1 + cr
    local straight_x2 = x2 - cr
    local straight_y1 = y1 + cr
    local straight_y2 = y2 - cr

    r.ImGui_DrawList_PushClipRect(dl, x1, y1, x2, y2, true)
    r.ImGui_DrawList_AddRectFilled(dl, straight_x1, y1, straight_x2, y1 + t, col)
    r.ImGui_DrawList_AddRectFilled(dl, straight_x1, y2 - t, straight_x2, y2, col)
    r.ImGui_DrawList_AddRectFilled(dl, x1, straight_y1, x1 + t, straight_y2, col)
    r.ImGui_DrawList_AddRectFilled(dl, x2 - t, straight_y1, x2, straight_y2, col)

    if inner_r > 0 then
        local pi = math.pi
        local segs = math.max(12, Round(cr * 1.75))
        local radius = cr - t * 0.5
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
    end
    r.ImGui_DrawList_PopClipRect(dl)
end

DrawSolidUnderline = function(dl, x1, y, x2, col, thickness)
    local t = thickness or 1
    local yy = Round(y)
    r.ImGui_DrawList_AddRectFilled(dl, Round(x1), yy, Round(x2), yy + t, col)
end

-- =========================================================================
-- KNOB PRIMITIVES
-- =========================================================================

-- Draw a thick arc using PathStroke with round endpoint caps.
-- Single continuous stroke — no sub-segment seams.
DrawArcStroke = function(dl, cx, cy, radius, a_min, a_max, color, thickness, opts)
    if a_max - a_min <= 0.001 then return end
    opts = opts or {}
    local segs = math.max(32, math.floor(96 * (a_max - a_min) / (math.pi * 2)))
    r.ImGui_DrawList_PathClear(dl)
    r.ImGui_DrawList_PathArcTo(dl, cx, cy, radius, a_min, a_max, segs)
    r.ImGui_DrawList_PathStroke(dl, color, 0, thickness)
    if opts.flat_caps then return end
    -- Round caps at endpoints (PathStroke produces flat butt caps)
    local cap_r = thickness / 2
    local cap_segs = 16
    r.ImGui_DrawList_AddCircleFilled(dl, cx + radius * math.cos(a_min), cy + radius * math.sin(a_min), cap_r, color, cap_segs)
    r.ImGui_DrawList_AddCircleFilled(dl, cx + radius * math.cos(a_max), cy + radius * math.sin(a_max), cap_r, color, cap_segs)
end

-- Volume knob renderer: ring arc, blue fill from min to current position.
-- t = 0..1 normalized knob position.
DrawKnobVolume = function(dl, cx, cy, radius, t, hov, act)
    local thickness = radius * 0.28
    local arc_r = radius - thickness / 2
    DrawArcStroke(dl, cx, cy, arc_r, KNOB_ANGLE_MIN, KNOB_ANGLE_MAX, C.vol_slider_bg, thickness, { flat_caps = true })
    local a_cur = KNOB_ANGLE_MIN + clamp(t, 0, 1) * (KNOB_ANGLE_MAX - KNOB_ANGLE_MIN)
    DrawArcStroke(dl, cx, cy, arc_r, KNOB_ANGLE_MIN, a_cur, C.vol_slider_fill, thickness, { flat_caps = true })
end

-- Pan knob renderer: bidirectional from 12 o'clock center.
-- Amber fill left of center, red fill right. t = 0..1 (0.5 = center).
DrawKnobPan = function(dl, cx, cy, radius, t, hov, act, opts)
    opts = opts or {}
    local thickness = radius * 0.28
    local arc_r = radius - thickness / 2
    DrawArcStroke(dl, cx, cy, arc_r, KNOB_ANGLE_MIN, KNOB_ANGLE_MAX, C.vol_slider_bg, thickness, { flat_caps = true })
    -- Center notch at 12 o'clock (visible when near center)
    if t >= 0.495 and t <= 0.505 then
        local outer = arc_r + thickness / 2
        local inner = arc_r - thickness / 2
        local bar_w = opts.center_notch_w or math.max(1, thickness * 0.6)
        local x1 = Round(cx - bar_w * 0.5)
        local x2 = Round(cx + bar_w * 0.5)
        local y1 = Round(cy - outer - 1)
        local y2 = Round(cy - inner + 1)
        r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, C.bg)
    end
    local a_cur = KNOB_ANGLE_MIN + clamp(t, 0, 1) * (KNOB_ANGLE_MAX - KNOB_ANGLE_MIN)
    if t < 0.495 then
        DrawArcStroke(dl, cx, cy, arc_r, a_cur, KNOB_ANGLE_MID, C.pan_slider_fill, thickness, { flat_caps = true })
    elseif t > 0.505 then
        DrawArcStroke(dl, cx, cy, arc_r, KNOB_ANGLE_MID, a_cur, C.fx_offline_txt, thickness, { flat_caps = true })
    end
end

-- Knob primitive: arc-based rotary control with value readout.
-- draw_fn(dl, cx, cy, radius, t, hov, act) where t is 0-1 normalized.
-- val_str: text displayed below knob. val_col: color for that text.
-- Returns: hov, active, clicked, double_clicked, delta_y
NavKnob = function(id, diameter, t, draw_fn, val_str, val_col, opts)
    opts = opts or {}
    r.ImGui_InvisibleButton(ctx, id, diameter, diameter)
    local hov = r.ImGui_IsItemHovered(ctx)
    local active = r.ImGui_IsItemActive(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local dbl = hov and r.ImGui_IsMouseDoubleClicked(ctx, 0)
    local ix, iy = r.ImGui_GetItemRectMin(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local rad = diameter / 2
    draw_fn(dl, ix + rad, iy + rad, rad, t, hov, active, opts)
    if val_str and not opts.hide_value then
        local tw = r.ImGui_CalcTextSize(ctx, val_str)
        r.ImGui_DrawList_AddText(dl, ix + rad - tw / 2, iy + diameter + S(2),
            val_col or C.text_dim, val_str)
    end
    local dy = 0
    if active then
        local _, mdy = r.ImGui_GetMouseDelta(ctx)
        dy = mdy
    end
    return hov, active, clicked, dbl, dy, r.ImGui_IsItemDeactivated(ctx)
end

-- Draw a meter dot inside a volume knob center.
-- Reads peak from track, smooths via knob_meter_peak (separate from insp_meter_peak),
-- renders as a colored circle with alpha proportional to level.
-- cx/cy: knob center (screen coords), knob_d: knob diameter.
-- vol_scale: optional multiplier applied to raw peak (e.g. send volume).
-- meter_key: unique key for smoothing state (defaults to meter_track).
DrawKnobMeterDot = function(dl, meter_track, cx, cy, knob_d, vol_scale, meter_key)
    if not meter_track or not r.ValidatePtr(meter_track, "MediaTrack*") then return end
    local peak_raw = math.max(r.Track_GetPeakInfo(meter_track, 0), r.Track_GetPeakInfo(meter_track, 1))
    if vol_scale then peak_raw = peak_raw * vol_scale end
    local key = meter_key or meter_track
    local cur_peak = SmoothPeak(knob_meter_peak, key, peak_raw)
    if cur_peak < 0.00001 then return end
    local db = 20 * math.log(cur_peak, 10)
    local base_col
    base_col = MeterColor(db)
    local alpha = math.min(1.0, cur_peak ^ 0.4)
    local a_byte = math.floor(alpha * 255 + 0.5)
    local col = (base_col & 0xFFFFFF00) | a_byte
    local dot_r = knob_d * 0.24
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, dot_r, col, 32)
end


-- Unified vol/pan knob renderer with Option C drag/undo handling.
-- Replaces 12 near-identical blocks across DrawSendFolderCard and DrawCompactTrackColumn.
--
-- dl, id             ImGui draw list + unique button id
-- kx, ky, knob_d     screen position + diameter (caller owns layout)
-- kind               "vol" or "pan"
-- track, si          target. si=nil → track param (D_VOL/D_PAN). si=send_idx → send param.
-- state              { before, moved } table, mutated in place across frames
-- undo_label, tip    strings
-- meter_send_vol,
-- meter_send_idx     optional tail args for DrawKnobMeterDot on send knobs (vol only, ignored on pan)
NavParamKnob = function(dl, id, kx, ky, knob_d, kind, track, si, state, undo_label, tip,
                        meter_send_vol, meter_send_idx, opts)
    opts = opts or {}
    local is_send = si ~= nil
    local param = (kind == "vol") and "D_VOL" or "D_PAN"

    -- Read current value
    local val
    if is_send then
        val = r.GetTrackSendInfo_Value(track, 0, si, param)
    else
        val = r.GetMediaTrackInfo_Value(track, param)
    end

    -- Compute knob t-value, label, color, draw function
    local t_val, val_str, val_col, draw_fn
    if kind == "vol" then
        t_val = VolToKnobT(val)
        val_str = InspFormatVol(val)
        local db = val < 0.00001 and -60 or 20 * math.log(val, 10)
        val_col = (db > -0.05 and db < 0.05) and C.text_muted or C.text_dim
        draw_fn = DrawKnobVolume
    else
        t_val = (val + 1) / 2
        val_str = InspFormatPan(val)
        if math.abs(val) < 0.005 then val_col = C.text_muted
        elseif val < 0 then val_col = C.pan_slider_fill
        else val_col = C.fx_offline_txt end
        draw_fn = DrawKnobPan
    end

    -- Render the knob + capture interaction
    r.ImGui_SetCursorScreenPos(ctx, kx, ky)
    local _hov, act, clk, dbl, dy, deact = NavKnob(id, knob_d, t_val, draw_fn, val_str, val_col, opts)
    state.active = act

    if kind == "pan" and not is_send
        and InspTrackPanEnvelopeActive and InspTrackPanEnvelopeActive(track) then
        r.ImGui_DrawList_AddCircleFilled(dl, kx + knob_d / 2, ky + knob_d / 2, S(5), C.pan_slider_fill, 24)
    end

    -- Meter dot (vol only)
    if kind == "vol" then
        if is_send then
            DrawKnobMeterDot(dl, track, kx + knob_d / 2, ky + knob_d / 2, knob_d,
                             meter_send_vol, meter_send_idx)
        else
            DrawKnobMeterDot(dl, track, kx + knob_d / 2, ky + knob_d / 2, knob_d)
        end
    end

    -- Option C reset: capture pre-click value so deactivate can commit atomically.
    if clk then
        state.before = val
        state.moved = false
        state.resetting = false
        if IsAlt(r.ImGui_GetKeyMods(ctx)) then
            local reset_val = (kind == "vol") and 1.0 or 0
            if is_send then
                r.SetTrackSendInfo_Value(track, 0, si, param, reset_val)
            else
                r.SetMediaTrackInfo_Value(track, param, reset_val)
            end
            state.moved = true
            state.resetting = true
        end
    end

    -- Drag: raw writes, mark moved
    if act and dy ~= 0 and not state.resetting then
        if kind == "vol" then
            -- Clamp drag math to -60..+12 dB. VolToKnobT visually compresses < -60 dB
            -- into t=0, so letting internal db go below -60 creates a "stuck at -inf"
            -- dead zone where drag works mathematically but the knob doesn't move.
            -- True silence (val=0) is still written when new_db reaches -60.
            local cur_db = val < 0.00001 and -60 or 20 * math.log(val, 10)
            local new_db = clamp(cur_db - dy * 0.15, -60, 12)
            local new_val = new_db <= -60 and 0 or 10 ^ (new_db / 20)
            if is_send then
                r.SetTrackSendInfo_Value(track, 0, si, param, new_val)
            else
                r.SetMediaTrackInfo_Value(track, param, new_val)
            end
        else
            local new_pan = clamp(val - dy * 0.005, -1, 1)
            if math.abs(new_pan) < 0.015 then new_pan = 0 end
            if is_send then
                r.SetTrackSendInfo_Value(track, 0, si, param, new_pan)
            else
                r.SetMediaTrackInfo_Value(track, param, new_pan)
            end
        end
        state.moved = true
    end

    -- Double-click reset (vol→1.0, pan→0). Must set moved=true so deact commits.
    if dbl then
        local reset_val = (kind == "vol") and 1.0 or 0
        if is_send then
            r.SetTrackSendInfo_Value(track, 0, si, param, reset_val)
        else
            r.SetMediaTrackInfo_Value(track, param, reset_val)
        end
        state.moved = true
        state.resetting = true
    end

    -- Deactivate: silent rollback then atomic commit inside undo block
    if deact and state.moved and state.before ~= nil then
        local final
        if is_send then
            final = r.GetTrackSendInfo_Value(track, 0, si, param)
            r.SetTrackSendInfo_Value(track, 0, si, param, state.before)
            r.Undo_BeginBlock()
            r.SetTrackSendInfo_Value(track, 0, si, param, final)
        else
            final = r.GetMediaTrackInfo_Value(track, param)
            r.SetMediaTrackInfo_Value(track, param, state.before)
            r.Undo_BeginBlock()
            r.SetMediaTrackInfo_Value(track, param, final)
        end
        r.Undo_EndBlock(undo_label, -1)
        state.before = nil
        state.moved = false
        state.resetting = false
    elseif deact then
        state.resetting = false
    end

    Tip(tip)
end


-- Load the inspect arrow icon (white on transparent PNG, tinted at render time).
-- PNG must be pre-scaled to the desired rendered pixel size — rendered 1:1, no scaling.
inspect_arrow_img = nil
volume_fader_arrow_img = nil
volume_fader_arrow_img_loaded = false
record_input_chevron_imgs = {}
record_input_chevron_imgs_loaded = {}

GetInspectArrowImg = function()
    if inspect_arrow_img then return inspect_arrow_img end
    local path = script_dir .. "icons/inspect-send-arrow.png"
    local f = io.open(path, "rb")
    if f then
        f:close()
        local img = r.ImGui_CreateImage(path)
        if img then
            r.ImGui_Attach(ctx, img)
            inspect_arrow_img = img
            return img
        end
    end
    return nil
end

GetVolumeFaderArrowImg = function()
    if volume_fader_arrow_img_loaded then return volume_fader_arrow_img end
    volume_fader_arrow_img_loaded = true
    local path = script_dir .. "icons/volume-fader-arrow.png"
    local f = io.open(path, "rb")
    if f then
        f:close()
        local ok, img = pcall(r.ImGui_CreateImage, path)
        if ok and img then
            r.ImGui_Attach(ctx, img)
            volume_fader_arrow_img = img
        end
    end
    return volume_fader_arrow_img
end

GetRecordInputChevronImg = function(which)
    which = (which == "down") and "down" or "right"
    if record_input_chevron_imgs_loaded[which] then return record_input_chevron_imgs[which] end
    record_input_chevron_imgs_loaded[which] = true
    local path = script_dir .. "icons/record-input-chevron-" .. which .. ".png"
    local f = io.open(path, "rb")
    if f then
        f:close()
        local ok, img = pcall(r.ImGui_CreateImage, path)
        if ok and img then
            r.ImGui_Attach(ctx, img)
            record_input_chevron_imgs[which] = img
        end
    end
    return record_input_chevron_imgs[which]
end

DrawRecordInputChevronImage = function(dl, cx, cy, dir, col)
    local down = dir == "down"
    local img = GetRecordInputChevronImg(down and "down" or "right")
    if not img then return false end
    local w = down and 8.5 or 5.0
    local h = down and 5.0 or 8.5
    local x1 = cx - w / 2
    local y1 = cy - h / 2
    if dir == "left" then
        r.ImGui_DrawList_AddImage(dl, img, x1, y1, x1 + w, y1 + h, 1, 0, 0, 1, col)
    else
        r.ImGui_DrawList_AddImage(dl, img, x1, y1, x1 + w, y1 + h, 0, 0, 1, 1, col)
    end
    return true
end

-- Draw the inspect arrow icon scaled to target logical size, tinted to color.
-- cx/cy: center of the arrow. Same pattern as DrawFlowArrow.
DrawInspectArrow = function(dl, cx, cy, color)
    local img = GetInspectArrowImg()
    if not img then return end
    local iw, ih = r.ImGui_Image_GetSize(img)
    if iw < 1 or ih < 1 then return end
    local w = 14
    local h = math.floor(ih * (w / iw) + 0.5)
    local x = math.floor(cx - w / 2)
    local y = Round(cy - h / 2)
    r.ImGui_DrawList_AddImage(dl, img, x, y, x + w, y + h, 0, 0, 1, 1, color)
end

footer_settings_img = nil
footer_settings_img_loaded = false
footer_columns_img = nil
footer_columns_img_loaded = false
footer_label_images = {}
footer_label_images_loaded = {}

GetFooterSettingsImg = function()
    if footer_settings_img_loaded then return footer_settings_img end
    footer_settings_img_loaded = true
    local path = script_dir .. "icons/Nav.Settings.png"
    local f = io.open(path, "rb")
    if f then
        f:close()
        local ok, img = pcall(r.ImGui_CreateImage, path)
        if ok and img then
            r.ImGui_Attach(ctx, img)
            footer_settings_img = img
        end
    end
    return footer_settings_img
end

GetFooterLabelImg = function(which)
    if footer_label_images_loaded[which] then return footer_label_images[which] end
    footer_label_images_loaded[which] = true
    local files = {
        F = "Nav.Flow.F.png",
        S = "Nav.Select.S.png",
    }
    local filename = files[which]
    if not filename then return nil end
    local path = script_dir .. "icons/" .. filename
    local f = io.open(path, "rb")
    if f then
        f:close()
        local ok, img = pcall(r.ImGui_CreateImage, path)
        if ok and img then
            r.ImGui_Attach(ctx, img)
            footer_label_images[which] = img
        end
    end
    return footer_label_images[which]
end

GetFooterColumnsImg = function()
    if footer_columns_img_loaded then return footer_columns_img end
    footer_columns_img_loaded = true
    local path = script_dir .. "icons/Nav.Columns.png"
    local f = io.open(path, "rb")
    if f then
        f:close()
        local ok, img = pcall(r.ImGui_CreateImage, path)
        if ok and img then
            r.ImGui_Attach(ctx, img)
            footer_columns_img = img
        end
    end
    return footer_columns_img
end

DrawFooterImageInBox = function(dl, img, cx, cy, box, col)
    if not img then return false end
    local iw, ih = r.ImGui_Image_GetSize(img)
    if not iw or not ih or iw < 1 or ih < 1 then return false end
    -- Footer PNGs are authored at 2x. `box` is the logical on-screen draw box,
    -- not the source pixel size.
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

DrawFooterImageFixed = function(dl, img, cx, cy, w, h, col)
    if not img then return false end
    local iw, ih = r.ImGui_Image_GetSize(img)
    if not iw or not ih or iw < 1 or ih < 1 then return false end
    local x = cx - w / 2
    local y = cy - h / 2
    r.ImGui_DrawList_AddImage(dl, img, x, y, x + w, y + h, 0, 0, 1, 1, col)
    return true
end

DrawFooterLabel = function(dl, cx, cy, label, col, box)
    if DrawFooterImageInBox(dl, GetFooterLabelImg(label), cx, cy, box, col) then return end
    local font = GetSteppedFont(-1)
    if font then r.ImGui_PushFont(ctx, font) end
    local tw = r.ImGui_CalcTextSize(ctx, label)
    local th = r.ImGui_GetTextLineHeight(ctx)
    r.ImGui_DrawList_AddText(dl, cx - tw / 2, cy - th / 2, col, label)
    if font then r.ImGui_PopFont(ctx) end
end

DrawFooterSettingsIcon = function(dl, cx, cy, col, box)
    local gear_box = 31 * 0.5 * ReflexRawUiScale()
    if DrawFooterImageInBox(dl, GetFooterSettingsImg(), cx, cy, gear_box, col) then return end
    DrawFooterLabel(dl, cx, cy, "\xE2\x9A\x99", col, gear_box)
end

DrawFooterColumnsIcon = function(dl, cx, cy, col, box)
    if DrawFooterImageFixed(dl, GetFooterColumnsImg(), cx, cy, 12, 11, col) then return end
    local w = box * 0.56
    local h = box * 0.50
    local gap = math.max(1, ReflexFooterRetinaPx(2))
    local stroke = math.max(1, ReflexFooterRetinaPx(1.5))
    local col_w = (w - gap) * 0.5
    local x1 = Round(cx - w * 0.5)
    local y1 = Round(cy - h * 0.5)
    local y2 = Round(cy + h * 0.5)
    local rct = math.max(1, ReflexFooterRetinaPx(1.5))
    r.ImGui_DrawList_AddRect(dl, x1, y1, x1 + col_w, y2, col, rct, 0, stroke)
    r.ImGui_DrawList_AddRect(dl, x1 + col_w + gap, y1, x1 + w, y2, col, rct, 0, stroke)
end

ReflexFooterRetinaPx = function(px)
    return math.max(0.5, px * 0.5 * ReflexRawUiScale())
end

ReflexFooterEdgeGap = function()
    -- Literal Retina target: 14 px from the visible window edge.
    return 7
end

ReflexFooterButtonDiameter = function()
    return ReflexRawS(34)
end

ReflexFooterButtonHitWidth = function(diameter)
    return math.floor((diameter or ReflexFooterButtonDiameter()) / 2) * 2
end

ReflexFooterButtonGap = function()
    -- Match Navigator A/S/R circle spacing.
    return ReflexRawS(4)
end

ReflexFooterRowHeight = function(diameter)
    return ReflexFooterButtonHitWidth(diameter) + ReflexRawS(3.75)
end

ReflexFooterTotalHeight = function(diameter)
    diameter = diameter or ReflexFooterButtonDiameter()
    return math.floor(ReflexFooterRowHeight(diameter) / 2) + diameter / 2 + ReflexFooterEdgeGap()
end

-- Inspect arrow button: places InvisibleButton, draws arrow, returns clicked.
-- ax/ay: screen-space position for hit area. hit_w/hit_h: button dims.
-- Arrow is visually centered within the hit area unless arrow_cy is provided.
InspectArrowButton = function(id, ax, ay, hit_w, hit_h, track, arrow_cy, card_hovered)
    if card_hovered == false then return false end  -- hidden when card not hovered
    r.ImGui_SetCursorScreenPos(ctx, ax, ay)
    r.ImGui_InvisibleButton(ctx, id, hit_w, hit_h)
    local hov = r.ImGui_IsItemHovered(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local arrow_col = hov and C.inspect_arrow_hov or C.inspect_arrow
    DrawInspectArrow(dl, ax + hit_w / 2, arrow_cy or (ay + hit_h / 2), arrow_col)
    Tip("Inspect")
    -- v20.429: pre/post push so Back/Forward restore the previous flow chain
    -- context (anchor + chain), not just the unpin state.
    if clicked and track then
        ViewHistoryPush()
        FlowViewSetFocus(track)
        ViewHistoryPush()
    end
    return clicked
end

-- Card container helpers: wrap track modules in rounded-rect cards
-- Double-AddRectFilled technique: outer rect (stroke color) + inner rect (fill color)
-- avoids AddRect anti-aliased stroke which causes gradient fade on straight edges.
CardBegin = function(bw, card_opts)
    if not opt_card_boxes then return bw, nil end
    local px = S(UI.card_pad)
    local py_top = S(UI.card_pad_top)
    local sx = r.ImGui_GetCursorPosX(ctx)
    local sy = r.ImGui_GetCursorPosY(ctx)
    local scx, scy = r.ImGui_GetCursorScreenPos(ctx)
    scx = math.floor(scx)
    card_idx = card_idx + 1
    local ci = card_idx
    local est_h = (card_opts and card_opts.est_h) or card_heights_prev[ci] or S(300)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local cr = S(UI.card_r)
    local x2 = math.floor(scx + bw)
    local y2 = scy + est_h
    if r.ImGui_StyleVar_CircleTessellationMaxError then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CircleTessellationMaxError(), CARD_STROKE_TESSELLATION_MAX_ERROR)
    end
    local stroke_col = card_opts and card_opts.stroke
    if stroke_col then
        local sw = (card_opts and card_opts.stroke_w) or math.max(1, Round(S(STROKE_W)))
        r.ImGui_DrawList_AddRectFilled(dl, scx, scy, x2, y2, stroke_col, cr)
        local fill = (card_opts and card_opts.bg) or C.bg
        r.ImGui_DrawList_AddRectFilled(dl, scx + sw, scy + sw, x2 - sw, y2 - sw, fill, math.max(0, cr - sw))
    else
        local fill = (card_opts and card_opts.bg) or C.bg
        r.ImGui_DrawList_AddRectFilled(dl, scx, scy, x2, y2, fill, cr)
    end
    if r.ImGui_StyleVar_CircleTessellationMaxError then
        r.ImGui_PopStyleVar(ctx)
    end
    r.ImGui_SetCursorPos(ctx, sx + px, sy + py_top)
    return bw - px * 2, { scx = scx, scy = scy, bw = bw, sx = sx, ci = ci }
end

CardEnd = function(card, opts)
    if not card then return end
    local py_bot = S(UI.card_pad_bot) + ((opts and opts.pad_bot_adjust) or 0)
    r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + py_bot)
    local _, ecy = r.ImGui_GetCursorScreenPos(ctx)
    local actual_h = ecy - card.scy
    if not (opts and opts.no_height_cache) then
        card_heights_cur[card.ci] = actual_h
    end
    r.ImGui_SetCursorPosX(ctx, card.sx)
end

InspCardBottomPadAdjust = function(has_fx_rows)
    -- Raw logical draw-list adjustments from Retina screenshot deltas:
    -- collapsed/empty cards need no offset, visible FX rows need -4 Retina px.
    return has_fx_rows and -2.0 or 0
end

DrawTrackPinIndicator = function(dl, cx, cy, hovered, pinned)
    -- These are Retina screenshot-pixel targets. Keep them as raw half-logical
    -- draw coordinates so odd-pixel diameters do not get rounded through S().
    local outer_r = 21 * 0.25
    local segments = NAV_CIRCLE_SEGMENTS or 96
    if pinned then
        r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, outer_r, C.amber, segments)
        return outer_r
    end

    local outer_col = hovered and C.fx_ctrl_hover or C.fx_ctrl_bg
    local inner_r = 13 * 0.25
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, outer_r, outer_col, segments)
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, inner_r, C.bg, segments)
    return outer_r
end

-- Draw a thin scroll position indicator (non-interactive, supports fade alpha).
-- region_y1/y2: screen-space vertical bounds; ind_x: screen-space left edge of indicator.
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

NavInitDefaults()

package.loaded["Reflex_StyleCore"] = nil
require("Reflex_StyleCore")({
    r = r,
    ctx = ctx,
    colors = C,
})

-- Button brightness from embedded theme constants.
local BB = nav_theme.button_brightness or {}
local B_VIS     = BB.visible       or 0.65
local B_VIS_HOV = BB.visible_hover or 0.80
local B_VIS_ACT = BB.visible_active or 0.55
local B_HID     = BB.hidden        or 0.25
local B_HID_HOV = BB.hidden_hover  or 0.35
local B_HID_ACT = BB.hidden_active or 0.20

-- Track color overrides from embedded theme constants.
local track_color_overrides = nav_theme.track_colors or {}

-- Remote button color palette from embedded theme constants.
local remote_palette_raw = nav_theme.remote_colors or {
    0x3B82F6, 0x3FB950, 0xD29922, 0xF85149, 0xBF40BF, 0x58A6FF,
}
local remote_palette_base_count = #remote_palette_raw
local remote_palette = {}
for i, hex in ipairs(remote_palette_raw) do
    remote_palette[i] = rgb(hex)
end
-- Load user-added colors from ExtState
local extra_colors_str = r.GetExtState(PREF, "remote_extra_colors")
if extra_colors_str ~= "" then
    for hex in extra_colors_str:gmatch("([^|]+)") do
        local n = tonumber(hex)
        if n then remote_palette[#remote_palette + 1] = rgb(n) end
    end
end

RemoteSaveExtraColors = function()
    local parts = {}
    for i = remote_palette_base_count + 1, #remote_palette do
        parts[#parts + 1] = string.format("0x%06X", (remote_palette[i] >> 8) & 0xFFFFFF)
    end
    r.SetExtState(PREF, "remote_extra_colors", table.concat(parts, "|"), true)
end

RemoteAddPaletteColor = function(rgba)
    -- Check if color already exists in palette
    for i, c in ipairs(remote_palette) do
        if (c & 0xFFFFFF00) == (rgba & 0xFFFFFF00) then return i end
    end
    remote_palette[#remote_palette + 1] = rgba
    RemoteSaveExtraColors()
    return #remote_palette
end

-- =========================================================================
-- SCALE
-- =========================================================================
local BASE_W = 200
local BASE_H = 28
local BASE_SPACING = 3 * 2
local BASE_PAD_X = 6 + 2
local BASE_PAD_Y = 3 + 1
local BASE_INSP_H = 36
local BASE_CAP_H = 20

ReflexScaleValue = function(v, scale)
    return math.floor(v * (scale or 1.0) * 0.8 + 0.5)
end
ReflexRawS = function(v) return ReflexScaleValue(v, ReflexRawUiScale()) end
S = function(v) return ReflexScaleValue(v, ReflexEffectiveUiScale()) end
-- Round-half-up. Use for centering math (text in boxes, icons in cells)
-- where floor() would systematically bias left/up on fractional differences.
Round = function(v) return math.floor(v + 0.5) end
clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
lerp = function(a, b, t) return a + (b - a) * t end

-- =========================================================================
-- SHARED HELPERS (extracted to eliminate redundancy)
-- =========================================================================
package.loaded["Reflex_MeterCore"] = nil
require("Reflex_MeterCore")({
    colors = C,
})

-- Set track TCP + Mixer visibility in lockstep (always paired).
SetTrackVis = function(track, visible)
    local v = visible and 1 or 0
    r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", v)
    r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", v)
end

-- Mute button color opts for NavRect. Returns opts table.
MuteOpts = function(is_muted)
    if is_muted then
        return {
            bg = C.fx_offline_txt, hov = C.mute_hov, active = C.mute_act,
            fg = 0xFFFFFFFF, fg_hov = 0xFFFFFFFF,
        }
    else
        return {
            bg = C.fx_ctrl_bg, hov = C.fx_ctrl_hover, active = C.fx_ctrl_active,
            fg = (C.text_dim & 0xFFFFFF00) | math.floor((C.text_dim & 0xFF) * 0.4),
            fg_hov = C.text_dim,
        }
    end
end

-- Solo button color opts for NavRect. Returns opts table.
SoloOpts = function(is_solo)
    if is_solo then
        return {
            bg = C.solo_bg, hov = C.solo_hov, active = C.solo_act,
            fg = 0xFFFFFFFF, fg_hov = 0xFFFFFFFF,
        }
    else
        return {
            bg = C.fx_ctrl_bg, hov = C.fx_ctrl_hover, active = C.fx_ctrl_active,
            fg = (C.text_dim & 0xFFFFFF00) | math.floor((C.text_dim & 0xFF) * 0.4),
            fg_hov = C.text_dim,
        }
    end
end

DrawStaticRectButton = function(dl, rect, label, opts)
    if not (dl and rect and opts) then return end
    local x, y = rect[1], rect[2]
    local w, h = rect[3] - rect[1], rect[4] - rect[2]
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, opts.bg, 3)
    NavDrawContent(dl, x, y, w, h, label, opts.fg, opts)
end

FXPowerCircleDiameter = function()
    return 8 -- 16 Retina px.
end

FXPowerNamePad = function(row_h)
    return row_h + math.max(0, row_h / 2 - FXPowerCircleDiameter() / 2)
end

FXCategoryBarWidth = function()
    return 18 * 0.5 * ReflexEffectiveUiScale()
end

FXPowerBgColor = function(enabled, hovered, bypass_forced)
    if enabled and not bypass_forced then return hovered and C.fx_power_hover or C.fx_power_bg end
    return hovered and C.fx_power_byp_hover or C.fx_power_byp_bg
end

FXPowerEndcapBgColor = function(enabled, hovered, row_bg, offline, bypass_forced)
    if offline and not enabled then return row_bg end
    if offline and enabled then return FXPowerBgColor(false, hovered, true) end
    return FXPowerBgColor(enabled, hovered, bypass_forced)
end

DrawFXPowerEndcap = function(dl, x, y, row_h, enabled, hovered, rounding, bypass_forced)
    local col = FXPowerBgColor(enabled, hovered, bypass_forced)
    local flags = r.ImGui_DrawFlags_RoundCornersTopLeft() | r.ImGui_DrawFlags_RoundCornersBottomLeft()
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + row_h, y + row_h, col, rounding or 0, flags)
end

FXRowDefaultCorners = function()
    return { tr = true, br = true }
end

FXRowStackCorners = function(index, count)
    if not index or not count or count <= 0 then return FXRowDefaultCorners() end
    local first = index == 1
    local last = index == count
    return {
        tl = first,
        tr = first,
        br = last,
        bl = last,
    }
end

FXRowCornerFlags = function(corners, names)
    corners = corners or FXRowDefaultCorners()
    local flags = 0
    for _, name in ipairs(names or {}) do
        if name == "tl" and corners.tl then
            flags = flags | r.ImGui_DrawFlags_RoundCornersTopLeft()
        elseif name == "tr" and corners.tr then
            flags = flags | r.ImGui_DrawFlags_RoundCornersTopRight()
        elseif name == "br" and corners.br then
            flags = flags | r.ImGui_DrawFlags_RoundCornersBottomRight()
        elseif name == "bl" and corners.bl then
            flags = flags | r.ImGui_DrawFlags_RoundCornersBottomLeft()
        end
    end
    return flags
end

FXRowRadiusForFlags = function(radius, flags)
    return (flags and flags ~= 0) and (radius or 0) or 0
end

FXRowBodyCornerFlags = function(corners, category_w)
    local names = category_w and category_w > 0 and { "tr", "br" } or { "tl", "tr", "br", "bl" }
    return FXRowCornerFlags(corners, names)
end

DrawFXRowBase = function(dl, x, y, w, row_h, total_h, body_col, power_col, radius, category_col, category_w, corners)
    category_w = category_w or 0
    local power_x = x + category_w
    local body_x = power_x + row_h
    local cat_flags = FXRowCornerFlags(corners, { "tl", "bl" })
    local body_flags = FXRowBodyCornerFlags(corners, category_w)
    if category_w > 0 then
        r.ImGui_DrawList_AddRectFilled(dl, x, y, x + category_w, y + total_h,
            category_col or C.fx_cat_generic, FXRowRadiusForFlags(radius, cat_flags), cat_flags)
    end
    r.ImGui_DrawList_AddRectFilled(dl, x + category_w, y, x + w, y + total_h, body_col,
        FXRowRadiusForFlags(radius, body_flags), body_flags)
    r.ImGui_DrawList_AddRectFilled(dl, power_x, y, body_x, y + row_h, power_col, 0)
end

DrawFXRowRightOutline = function(dl, x, y, w, h, col, radius, thickness, corners)
    if not col then return end
    local x1 = Round(x)
    local y1 = Round(y)
    local x2 = Round(x + w)
    local y2 = Round(y + h)
    local t = thickness or SOURCE_STROKE_W or 1
    local rr = math.max(0, math.min(Round(radius or 0), math.floor(math.min(x2 - x1, y2 - y1) / 2)))
    corners = corners or FXRowDefaultCorners()
    local has_round = rr > t and (corners.tl or corners.tr or corners.br or corners.bl)

    if not has_round then
        r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, math.min(y2, y1 + t), col)
        r.ImGui_DrawList_AddRectFilled(dl, x1, math.max(y1, y2 - t), x2, y2, col)
        r.ImGui_DrawList_AddRectFilled(dl, x1, y1, math.min(x2, x1 + t), y2, col)
        r.ImGui_DrawList_AddRectFilled(dl, math.max(x1, x2 - t), y1, x2, y2, col)
        return
    end

    local top_l = corners.tl and rr or 0
    local top_r = corners.tr and rr or 0
    local bot_r = corners.br and rr or 0
    local bot_l = corners.bl and rr or 0

    r.ImGui_DrawList_PushClipRect(dl, x1, y1, x2, y2, true)
    r.ImGui_DrawList_AddRectFilled(dl, x1 + top_l, y1, x2 - top_r, y1 + t, col)
    r.ImGui_DrawList_AddRectFilled(dl, x1 + bot_l, y2 - t, x2 - bot_r, y2, col)
    r.ImGui_DrawList_AddRectFilled(dl, x1, y1 + top_l, x1 + t, y2 - bot_l, col)
    r.ImGui_DrawList_AddRectFilled(dl, x2 - t, y1 + top_r, x2, y2 - bot_r, col)

    if r.ImGui_DrawList_PathClear and r.ImGui_DrawList_PathArcTo and r.ImGui_DrawList_PathStroke then
        local pi = math.pi
        local radius = math.max(0, rr - t * 0.5)
        local segs = math.max(8, math.floor(rr * 3))
        local function arc(cx, cy, a1, a2)
            r.ImGui_DrawList_PathClear(dl)
            r.ImGui_DrawList_PathArcTo(dl, cx, cy, radius, a1, a2, segs)
            r.ImGui_DrawList_PathStroke(dl, col, 0, t)
        end
        if corners.tl then arc(x1 + rr, y1 + rr, pi, pi * 1.5) end
        if corners.tr then arc(x2 - rr, y1 + rr, pi * 1.5, pi * 2) end
        if corners.br then arc(x2 - rr, y2 - rr, 0, pi * 0.5) end
        if corners.bl then arc(x1 + rr, y2 - rr, pi * 0.5, pi) end
    else
        if corners.tl then r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x1 + t, y1 + t, col) end
        if corners.tr then r.ImGui_DrawList_AddRectFilled(dl, x2 - t, y1, x2, y1 + t, col) end
        if corners.br then r.ImGui_DrawList_AddRectFilled(dl, x2 - t, y2 - t, x2, y2, col) end
        if corners.bl then r.ImGui_DrawList_AddRectFilled(dl, x1, y2 - t, x1 + t, y2, col) end
    end
    r.ImGui_DrawList_PopClipRect(dl)
end

DrawFXRowOverlay = function(dl, x, y, w, row_h, total_h, category_w, col, radius, corners)
    category_w = category_w or 0
    local cat_flags = FXRowCornerFlags(corners, { "tl", "bl" })
    local body_flags = FXRowBodyCornerFlags(corners, category_w)
    if category_w > 0 then
        r.ImGui_DrawList_AddRectFilled(dl, x, y, x + category_w, y + total_h, col,
            FXRowRadiusForFlags(radius, cat_flags), cat_flags)
    end
    r.ImGui_DrawList_AddRectFilled(dl, x + category_w, y, x + w, y + total_h, col,
        FXRowRadiusForFlags(radius, body_flags), body_flags)
end

DrawFXPowerButton = function(id, x, y, row_h, enabled, payload)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_SetCursorScreenPos(ctx, x, y)
    r.ImGui_InvisibleButton(ctx, id, row_h, row_h)
    local hov = r.ImGui_IsItemHovered(ctx)
    local offline = payload and payload.offline
    local mods = r.ImGui_GetKeyMods(ctx)
    local offline_toggle = IsCmd(mods) and IsShift(mods)
    if hov and (not offline or offline_toggle) then
        r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
        Tip("Click: bypass\nOpt: remove\nCmd: select\nCtrl: range\nCmd+Shift: offline")
    end
    if r.ImGui_IsItemClicked(ctx, 0) and (not offline or offline_toggle) then
        FxRowPowerClick(payload)
    end
    local d = FXPowerCircleDiameter()
    local cx = x + row_h / 2
    local cy = y + row_h / 2
    local col
    if offline then
        col = C.fx_power_offline
    else
        col = enabled and C.fx_power_on or C.fx_power_off
    end
    if hov and not offline then col = ScaleColor(col, 1.2) end
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, d / 2, col, NAV_CIRCLE_SEGMENTS)
    return hov
end

ShowOfflineFxStateTooltip = function(enabled)
    PushTooltipStyle()
    local tip_fp = PushTooltipFont()
    r.ImGui_BeginTooltip(ctx)
    r.ImGui_Text(ctx, enabled and "Offline / enabled" or "Offline / bypassed")
    r.ImGui_EndTooltip(ctx)
    PopTooltipFont(tip_fp)
    PopTooltipStyle()
end

fx_category_cache = nil

FXFolderDefaults = {
    "Favorites", "Adaptive", "Channel Strip", "Compression", "Delay", "Drum Machine",
    "EQ", "Filter", "Guitar", "Harmonics", "Lofi", "Mastering", "Modulation",
    "Rack", "Reverb", "Sampler", "Shape", "Synth", "Tape", "Analog Obsession",
    "Korg Gadgets", "Width",
}

FXCategoryNormalize = function(s)
    s = tostring(s or ""):lower()
    s = s:gsub("^%s*[%w%+%-]+:%s*", "")
    s = s:gsub("%b()", "")
    return s:gsub("[^%w]+", "")
end

FXFolderItemNormalize = function(s)
    s = tostring(s or "")
    local base = s:match("([^/\\]+)$") or s
    return FXCategoryNormalize(s) .. "|" .. FXCategoryNormalize(base)
end

FXCategorySplit = function(val)
    local out = {}
    for part in tostring(val or ""):gmatch("([^|]+)") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if part ~= "" then out[#out + 1] = part end
    end
    return out
end

FXCategoryFirst = function(cats)
    return cats and cats[1] or nil
end

FXCategoryAddKnown = function(cache, cat)
    cat = tostring(cat or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if cat == "" then return end
    local norm = FXCategoryNormalize(cat)
    if norm == "" or cache.folder_seen[norm] then return end
    cache.folder_seen[norm] = true
    cache.folders[#cache.folders + 1] = cat
end

FXCategoryPutKey = function(cache, key, cats)
    if not key or key == "" then return end
    local first_cat = FXCategoryFirst(cats)
    cache.by_key[key] = first_cat
    cache.cats_by_key[key] = cats
    for _, cat in ipairs(cats or {}) do FXCategoryAddKnown(cache, cat) end
    local function put_norm(s)
        local norm = FXCategoryNormalize(s)
        if norm ~= "" then
            cache.by_norm[norm] = first_cat
            cache.cats_by_norm[norm] = cats
            cache.key_by_norm[norm] = key
        end
    end
    put_norm(key)
    local base = key:match("([^/\\]+)$") or key
    put_norm(base:gsub("%.[^.]+$", ""))
end

FXFolderFilePath = function()
    local resource_path = r.GetResourcePath and r.GetResourcePath() or ""
    local path = resource_path .. "/reaper-fxfolders.ini"
    local f = io.open(path, "r")
    if f then f:close(); return path end
    local fallback = "/Applications/Reaper/reaper-fxfolders.ini"
    f = io.open(fallback, "r")
    if f then f:close(); return fallback end
    return path
end

FXFolderPrimaryPath = function()
    return script_dir .. "fx_folder_primary.txt"
end

fx_folder_primary_cache = nil

FXFolderLoadPrimary = function()
    if fx_folder_primary_cache then return fx_folder_primary_cache end
    local map = {}
    local f = io.open(FXFolderPrimaryPath(), "r")
    if f then
        for line in f:lines() do
            local key, folder = line:match("^(.-)=(.*)$")
            if key and key ~= "" and folder and folder ~= "" then map[key] = folder end
        end
        f:close()
    end
    fx_folder_primary_cache = map
    return map
end

FXFolderSavePrimary = function(key, folder)
    if not key or key == "" then return false end
    local map = FXFolderLoadPrimary()
    map[key] = folder
    local keys = {}
    for k in pairs(map) do keys[#keys + 1] = k end
    table.sort(keys)
    local f = io.open(FXFolderPrimaryPath(), "w")
    if not f then return false end
    for _, k in ipairs(keys) do f:write(k .. "=" .. tostring(map[k]) .. "\n") end
    f:close()
    return true
end

FXLoadCategoryCache = function()
    if fx_category_cache then return fx_category_cache end
    local cache = {
        by_key = {}, by_norm = {},
        cats_by_key = {}, cats_by_norm = {}, key_by_norm = {},
        folders = {}, folder_seen = {},
        folder_ids = {}, folder_names_by_id = {}, folder_items = {},
    }
    local path = FXFolderFilePath()
    local f = io.open(path, "r")
    if f then
        local section = nil
        local folder_names, folder_ids = {}, {}
        local folder_items = {}
        for line in f:lines() do
            local new_section = line:match("^%s*%[([^%]]+)%]")
            if new_section then
                section = new_section
            elseif section == "Folders" then
                local name_i, name = line:match("^%s*Name(%d+)%s*=%s*(.-)%s*$")
                if name_i then
                    folder_names[tonumber(name_i)] = name
                else
                    local id_i, id = line:match("^%s*Id(%d+)%s*=%s*(%d+)%s*$")
                    if id_i then folder_ids[tonumber(id_i)] = tonumber(id) end
                end
            else
                local folder_id = section and tonumber(section:match("^Folder(%d+)$"))
                if folder_id then
                    local item_i, item = line:match("^%s*Item(%d+)%s*=%s*(.-)%s*$")
                    if item_i and item and item ~= "" then
                        folder_items[folder_id] = folder_items[folder_id] or {}
                        folder_items[folder_id][#folder_items[folder_id] + 1] = item
                    end
                end
            end
        end
        f:close()
        local order = {}
        for idx, name in pairs(folder_names) do order[#order + 1] = idx end
        table.sort(order)
        for _, idx in ipairs(order) do
            local name = folder_names[idx]
            local id = folder_ids[idx] or idx
            FXCategoryAddKnown(cache, name)
            cache.folder_ids[name] = id
            cache.folder_names_by_id[id] = name
            for _, item in ipairs(folder_items[id] or {}) do
                cache.folder_items[id] = cache.folder_items[id] or {}
                cache.folder_items[id][#cache.folder_items[id] + 1] = item
                local cats = cache.cats_by_key[item]
                if not cats then
                    cats = {}
                    cache.cats_by_key[item] = cats
                    cache.cats_by_norm[FXFolderItemNormalize(item)] = cats
                    cache.key_by_norm[FXFolderItemNormalize(item)] = item
                end
                cats[#cats + 1] = name
            end
        end
    else
        for _, cat in ipairs(FXFolderDefaults) do FXCategoryAddKnown(cache, cat) end
    end
    fx_category_cache = cache
    return cache
end

FXPluginCategory = function(track, fx_idx, raw_name, display_name, is_container, is_instrument)
    if is_container then return "Container" end
    local cache = FXLoadCategoryCache()
    local candidates = {}
    if track and r.ValidatePtr(track, "MediaTrack*") and fx_idx then
        local parms = { "fx_ident", "fx_name", "original_name", "renamed_name" }
        for _, parm in ipairs(parms) do
            local ok, val = r.TrackFX_GetNamedConfigParm(track, fx_idx, parm)
            if ok and val and val ~= "" then candidates[#candidates + 1] = val end
        end
    end
    candidates[#candidates + 1] = raw_name
    candidates[#candidates + 1] = display_name
    for _, candidate in ipairs(candidates) do
        local cats = cache.cats_by_key[candidate] or cache.cats_by_norm[FXFolderItemNormalize(candidate)]
        if cats then
            local key = cache.cats_by_key[candidate] and candidate or cache.key_by_norm[FXFolderItemNormalize(candidate)]
            local primary = FXFolderLoadPrimary()[key or candidate]
            for _, cat in ipairs(cats) do if cat == primary then return primary end end
            return cats[1]
        end
    end
    if is_instrument then return "Instrument" end
    return nil
end

FXPluginCategoryInfo = function(track, fx_idx)
    local raw_name = ""
    if track and r.ValidatePtr(track, "MediaTrack*") and fx_idx then
        local _, nm = r.TrackFX_GetFXName(track, fx_idx, "")
        raw_name = nm or ""
    end
    local display_name = InspStripName(raw_name)
    local cache = FXLoadCategoryCache()
    local candidates = {}
    if track and r.ValidatePtr(track, "MediaTrack*") and fx_idx then
        local parms = { "fx_ident", "fx_name", "original_name", "renamed_name" }
        for _, parm in ipairs(parms) do
            local ok, val = r.TrackFX_GetNamedConfigParm(track, fx_idx, parm)
            if ok and val and val ~= "" then candidates[#candidates + 1] = val end
        end
    end
    candidates[#candidates + 1] = raw_name
    candidates[#candidates + 1] = display_name
    local fallback_key
    for _, candidate in ipairs(candidates) do
        if candidate and candidate ~= "" then
            fallback_key = fallback_key or candidate
            local cats = cache.cats_by_key[candidate]
            if cats then
                local primary = FXFolderLoadPrimary()[candidate]
                local active_primary = nil
                for _, cat in ipairs(cats) do if cat == primary then active_primary = primary end end
                return candidate, cats, cache.folders, active_primary
            end
            local norm = FXFolderItemNormalize(candidate)
            cats = cache.cats_by_norm[norm]
            if cats then
                local key = cache.key_by_norm[norm] or candidate
                local primary = FXFolderLoadPrimary()[key]
                local active_primary = nil
                for _, cat in ipairs(cats) do if cat == primary then active_primary = primary end end
                return key, cats, cache.folders, active_primary
            end
        end
    end
    return fallback_key or display_name, {}, cache.folders, nil
end

FXSaveCategoryAssignment = function(key, cats)
    if not key or key == "" then return false end
    cats = cats or {}
    local path = FXFolderFilePath()
    local lines = {}
    local f = io.open(path, "r")
    if f then
        for line in f:lines() do lines[#lines + 1] = line end
        f:close()
    end
    local cache = FXLoadCategoryCache()
    local target_folders = {}
    for _, cat in ipairs(cats) do target_folders[cat] = true end
    local touched_ids = {}
    for _, folder in ipairs(cache.folders or {}) do
        local id = cache.folder_ids[folder]
        if id and target_folders[folder] then touched_ids[id] = true end
    end
    local key_norm = FXFolderItemNormalize(key)
    local sections = {}
    local order = {}
    local current = { name = nil, body = {} }
    local function push_section(sec)
        order[#order + 1] = sec
        if sec.name then sections[sec.name] = sec end
    end
    for _, line in ipairs(lines) do
        local section = line:match("^%s*%[([^%]]+)%]")
        if section then
            push_section(current)
            current = { name = section, body = {} }
        else
            current.body[#current.body + 1] = line
        end
    end
    push_section(current)

    local function folder_section_id(sec)
        return sec and sec.name and tonumber(sec.name:match("^Folder(%d+)$")) or nil
    end

    local folder_ids = {}
    for _, folder in ipairs(cache.folders or {}) do
        local id = cache.folder_ids[folder]
        if id then folder_ids[#folder_ids + 1] = id end
    end
    table.sort(folder_ids)

    local existing_match_ids = {}
    for _, sec in ipairs(order) do
        local id = folder_section_id(sec)
        if id then
            for _, line in ipairs(sec.body) do
                local item = line:match("^%s*Item%d+%s*=%s*(.-)%s*$")
                if item and FXFolderItemNormalize(item) == key_norm then
                    existing_match_ids[id] = true
                    touched_ids[id] = true
                end
            end
        end
    end

    for _, id in ipairs(folder_ids) do
        local folder = cache.folder_names_by_id[id]
        if target_folders[folder] then touched_ids[id] = true end
        if touched_ids[id] and not sections["Folder" .. tostring(id)] then
            local sec = { name = "Folder" .. tostring(id), body = {} }
            sections[sec.name] = sec
            order[#order + 1] = sec
        end
    end

    for _, sec in ipairs(order) do
        local id = folder_section_id(sec)
        if id and touched_ids[id] then
            local folder = cache.folder_names_by_id[id]
            local items = {}
            for _, line in ipairs(sec.body) do
                local item = line:match("^%s*Item%d+%s*=%s*(.-)%s*$")
                if item and item ~= "" and FXFolderItemNormalize(item) ~= key_norm then
                    items[#items + 1] = item
                end
            end
            if target_folders[folder] then items[#items + 1] = key end
            local new_body = {}
            for i, item in ipairs(items) do new_body[#new_body + 1] = "Item" .. (i - 1) .. "=" .. item end
            new_body[#new_body + 1] = "Nb=" .. tostring(#items)
            for i = 1, #items do new_body[#new_body + 1] = "Type" .. (i - 1) .. "=3" end
            sec.body = new_body
        end
    end

    local out = {}
    for _, sec in ipairs(order) do
        if sec.name then out[#out + 1] = "[" .. sec.name .. "]" end
        for _, line in ipairs(sec.body) do out[#out + 1] = line end
    end
    local wf = io.open(path, "w")
    if not wf then return false end
    wf:write(table.concat(out, "\n"))
    wf:write("\n")
    wf:close()
    fx_category_cache = nil
    if InspMarkTrackFxDirty and insp_track then InspMarkTrackFxDirty(insp_track) end
    return true
end

FXFolderMenu = function(track, fx_idx)
    if not (track and r.ValidatePtr(track, "MediaTrack*")) then return end
    local key, cats, folders, primary = FXPluginCategoryInfo(track, fx_idx)
    if not key or key == "" then return end
    local active = {}
    for _, cat in ipairs(cats or {}) do active[cat] = true end
    primary = primary or cats[1]
    if r.ImGui_BeginMenu(ctx, "Folder") then
        for _, folder in ipairs(folders or {}) do
            local checked = active[folder] == true
            local is_primary = primary == folder and checked
            local label = is_primary and (folder .. " *") or folder
            if r.ImGui_MenuItem(ctx, label, nil, checked) then
                local mods = r.ImGui_GetKeyMods(ctx)
                local next_cats = {}
                local make_primary = IsAlt and IsAlt(mods)
                if make_primary then
                    next_cats[#next_cats + 1] = folder
                    for _, cat in ipairs(cats) do if cat ~= folder then next_cats[#next_cats + 1] = cat end end
                    FXFolderSavePrimary(key, folder)
                elseif checked then
                    for _, cat in ipairs(cats) do if cat ~= folder then next_cats[#next_cats + 1] = cat end end
                else
                    next_cats[#next_cats + 1] = folder
                    for _, cat in ipairs(cats) do if cat ~= folder then next_cats[#next_cats + 1] = cat end end
                end
                if FXSaveCategoryAssignment(key, next_cats) then
                    if InspMarkTrackFxDirty then InspMarkTrackFxDirty(track) end
                    if sends_fx_cache then sends_fx_cache[track] = nil end
                end
            end
        end
        r.ImGui_EndMenu(ctx)
    end
end

FXCategoryColor = function(category, is_container, is_instrument, is_offline, is_enabled)
    local cat = tostring(category or ""):lower()
    local col = C.fx_cat_generic
    if is_container or cat:find("container", 1, true) or cat:find("rack", 1, true) then
        col = C.fx_cat_container
    elseif is_instrument
        or cat:find("instrument", 1, true)
        or cat:find("synth", 1, true)
        or cat:find("sampler", 1, true)
        or cat:find("drum", 1, true) then
        col = C.fx_cat_instrument
    elseif cat:find("harmonic", 1, true)
        or cat:find("satur", 1, true)
        or cat:find("distortion", 1, true)
        or cat:find("tape", 1, true)
        or cat:find("lofi", 1, true) then
        col = C.fx_cat_harmonics
    elseif cat == "eq" or cat:find("equal", 1, true) then
        col = C.fx_cat_eq
    elseif cat:find("compress", 1, true) or cat:find("dynamics", 1, true) then
        col = C.fx_cat_compression
    end
    if is_offline or not is_enabled then col = ScaleColor(col, 0.45) end
    return col
end

RecordArmColor = function(is_armed, hov, active)
    if active then return C.record_arm_act end
    if is_armed then return C.record_arm end
    if hov then return C.fx_ctrl_hover end
    return C.fx_ctrl_bg
end

DrawRecordArmRing = function(dl, x1, y1, x2, y2, is_armed, hov, active)
    local outer_r = (y2 - y1) / 2
    local inner_r = outer_r * 0.5
    if inner_r < 0 then inner_r = 0 end
    local thickness = math.max(1, outer_r - inner_r)
    local stroke_r = inner_r + thickness / 2
    local cx = (x1 + x2) / 2
    local cy = (y1 + y2) / 2
    r.ImGui_DrawList_AddCircle(dl, cx, cy, stroke_r,
        RecordArmColor(is_armed, hov, active), NAV_CIRCLE_SEGMENTS, thickness)
end

RecordArmButton = function(id, diameter, is_armed)
    local hov, clicked, active = NavCircle(id, diameter, nil, {
        bg = 0x00000000,
        hov = 0x00000000,
        active = 0x00000000,
        no_press = true,
    })
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    DrawRecordArmRing(r.ImGui_GetWindowDrawList(ctx), x1, y1, x2, y2, is_armed, hov, active)
    Tip("Record arm")
    return hov, clicked, active
end

RecordArmDisarmAll = function()
    r.Undo_BeginBlock()
    for i = 0, r.CountTracks(0) - 1 do
        r.SetMediaTrackInfo_Value(r.GetTrack(0, i), "I_RECARM", 0)
    end
    r.Undo_EndBlock("Reflex: Disarm all tracks", -1)
end

RecordArmExclusive = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    r.Undo_BeginBlock()
    for i = 0, r.CountTracks(0) - 1 do
        local t = r.GetTrack(0, i)
        r.SetMediaTrackInfo_Value(t, "I_RECARM", t == track and 1 or 0)
    end
    r.Undo_EndBlock("Reflex: Exclusive record arm", -1)
end

RecordArmAllMidi = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    r.Undo_BeginBlock()
    r.SetMediaTrackInfo_Value(track, "I_RECARM", 1)
    r.SetMediaTrackInfo_Value(track, "I_RECINPUT", RecordInputAllMidiValue())
    r.Undo_EndBlock("Reflex: Record arm all MIDI", -1)
end

RecordArmClick = function(track, is_armed)
    local mods = r.ImGui_GetKeyMods(ctx)
    if IsCmd(mods) then
        RecordArmDisarmAll()
    elseif IsAlt(mods) then
        RecordArmExclusive(track)
    elseif IsShift(mods) then
        RecordArmAllMidi(track)
    else
        r.Undo_BeginBlock()
        r.SetMediaTrackInfo_Value(track, "I_RECARM", is_armed and 0 or 1)
        r.Undo_EndBlock("Reflex: Record arm", -1)
    end
end

record_monitor_img = nil
record_monitor_img_loaded = false

GetRecordMonitorImg = function()
    if record_monitor_img_loaded then return record_monitor_img end
    record_monitor_img_loaded = true
    local path = script_dir .. "icons/rec.mon.button.png"
    local f = io.open(path, "rb")
    if f then
        f:close()
        local ok, img = pcall(r.ImGui_CreateImage, path)
        if ok and img then
            r.ImGui_Attach(ctx, img)
            record_monitor_img = img
        end
    end
    return record_monitor_img
end

RecordMonitorIconDrawSize = function()
    local iw, ih = 54, 62
    local img = GetRecordMonitorImg()
    if img then
        local img_w, img_h = r.ImGui_Image_GetSize(img)
        if img_w and img_w > 0 and img_h and img_h > 0 then
            iw, ih = img_w, img_h
        end
    end
    -- Retina PNGs are supplied at 2:1 over the Photoshop/screenshot target.
    -- Convert source px -> target retina px -> Reflex S-units.
    local draw_w = math.max(1, S((iw / 2) / 1.6))
    local draw_h = math.max(1, S((ih / 2) / 1.6))
    return draw_w, draw_h
end

RecordMonitorButtonWidth = function(hit_h)
    if hit_h and hit_h > 0 then return hit_h end
    local draw_w, draw_h = RecordMonitorIconDrawSize()
    return math.max(draw_w, draw_h)
end

RecordMonitorColor = function(is_on, hov, active)
    if is_on or active then return 0xFFFFFFFF end
    if hov then return C.fx_ctrl_hover end
    return C.fx_ctrl_bg
end

DrawRecordMonitorIconInRect = function(dl, x1, y1, x2, y2, is_on, hov, active)
    local img = GetRecordMonitorImg()
    if not img then return end
    local draw_w, draw_h = RecordMonitorIconDrawSize()
    local x = Round(x1 + ((x2 - x1) - draw_w) / 2)
    local y = Round(y1 + ((y2 - y1) - draw_h) / 2)
    r.ImGui_DrawList_AddImage(dl, img, x, y, x + draw_w, y + draw_h,
        0, 0, 1, 1, RecordMonitorColor(is_on, hov, active))
end

RecordMonitorButton = function(id, hit_w, hit_h, is_on)
    local hov, clicked, active = NavRect(id, hit_w, hit_h, nil, {
        bg = 0x00000000,
        hov = 0x00000000,
        active = 0x00000000,
        no_press = true,
        rounding = 0,
    })
    local rclicked = r.ImGui_IsItemClicked(ctx, 1)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    DrawRecordMonitorIconInRect(r.ImGui_GetWindowDrawList(ctx), x1, y1, x2, y2,
        is_on, hov, active)
    Tip("Record monitor")
    return hov, clicked, active, rclicked
end

RecordMonitorSetMode = function(track, mode)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    local cur = math.floor(r.GetMediaTrackInfo_Value(track, "I_RECMON") or 0)
    if cur == mode then return end
    r.Undo_BeginBlock()
    r.SetMediaTrackInfo_Value(track, "I_RECMON", mode)
    r.Undo_EndBlock("Reflex: Record monitor", -1)
end

RecordMonitorToggle = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    local cur = math.floor(r.GetMediaTrackInfo_Value(track, "I_RECMON") or 0)
    RecordMonitorSetMode(track, cur > 0 and 0 or 1)
end

RecordMonitorToggleTrackMedia = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    local cur = r.GetMediaTrackInfo_Value(track, "I_RECMONITEMS") == 1
    r.Undo_BeginBlock()
    r.SetMediaTrackInfo_Value(track, "I_RECMONITEMS", cur and 0 or 1)
    r.Undo_EndBlock("Reflex: Monitor track media when recording", -1)
end

RecordMonitorRunSelectedTrackAction = function(track, action, undo_label)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    local saved = {}
    for i = 0, r.CountSelectedTracks(0) - 1 do
        saved[#saved + 1] = r.GetSelectedTrack(0, i)
    end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    r.Main_OnCommand(40297, 0)
    r.SetTrackSelected(track, true)
    r.Main_OnCommand(action, 0)
    r.Main_OnCommand(40297, 0)
    for _, t in ipairs(saved) do
        if r.ValidatePtr(t, "MediaTrack*") then r.SetTrackSelected(t, true) end
    end
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock(undo_label, -1)
end

RecordMonitorMenu = function(track, popup_id)
    PushPopupStyle()
    if r.ImGui_BeginPopup(ctx, popup_id) then
        local rec_mon = math.floor(r.GetMediaTrackInfo_Value(track, "I_RECMON") or 0)
        local mon_items = r.GetMediaTrackInfo_Value(track, "I_RECMONITEMS") == 1

        if r.ImGui_MenuItem(ctx, "Monitor Input", "", rec_mon == 1) then
            RecordMonitorSetMode(track, 1)
        end
        if r.ImGui_MenuItem(ctx, "Monitor Input (Tape Auto Style)", "", rec_mon == 2) then
            RecordMonitorSetMode(track, 2)
        end
        if r.ImGui_MenuItem(ctx, "Monitor track media when recording", "", mon_items) then
            RecordMonitorToggleTrackMedia(track)
        end
        if r.ImGui_MenuItem(ctx, "Preserve PDC delayed monitoring in recorded items") then
            RecordMonitorRunSelectedTrackAction(track, 41919,
                "Reflex: Toggle preserve PDC delayed monitoring")
        end

        r.ImGui_EndPopup(ctx)
    end
    PopPopupStyle()
end

-- =========================================================================
-- I/O CORE (shared HDR.input + I/O Manager backend)
-- =========================================================================
package.loaded["Reflex_IOCore"] = nil
require("Reflex_IOCore")({
    r = r,
    ctx = ctx,
    colors = C,
    script_dir = script_dir,
    PREF = PREF,
})

InspVolumeRightWidth = function(row_h)
    local gap = S(UI.pad_sm)
    local vol_val_w = math.max(row_h, r.ImGui_CalcTextSize(ctx, "-00.0") + S(24))
    return vol_val_w + gap + row_h + gap + row_h, vol_val_w
end

InspVolumeMeterWidth = function(bw, row_h, wrapped)
    if wrapped then return math.max(1, bw) end
    local right_w = InspVolumeRightWidth(row_h)
    return math.max(1, bw - right_w - S(UI.pad_sm))
end

InspVolumeShouldWrap = function(bw, row_h)
    local inline_meter_w = InspVolumeMeterWidth(bw, row_h, false)
    local right_w = InspVolumeRightWidth(row_h)
    local min_meter_w = math.max(row_h * 4, right_w)
    return inline_meter_w < min_meter_w
end

InspHeaderPanInlineMinWidth = function()
    local row_h = S(UI.btn_h)
    local gap = S(UI.pad_sm)
    local group_gap = S(UI.group_gap)
    local pan_val_w = math.max(row_h, r.ImGui_CalcTextSize(ctx, "100R") + S(16))
    local pan_knob_d = S(64 / 1.44)
    local pan_knob_right_nudge = 5
    local vol_value_w = row_h * 2 + gap
    local rec_total = row_h + gap + RecordMonitorButtonWidth(row_h) + gap * 2
    local solo_right = rec_total + row_h + gap + row_h
    local left_end = solo_right + group_gap + vol_value_w
    return left_end + group_gap + pan_val_w + gap * 2 + pan_knob_d - pan_knob_right_nudge
end

InspControlsInlineMinWidth = function()
    local row_h = S(UI.btn_h)
    local gap = S(UI.pad_sm)
    local fx_btn_w = math.floor(InspCtrlW("FX") * 1.4)
    local fx_compound_w = fx_btn_w + row_h + row_h + math.floor(gap / 2)
    local route_w = InspRoutingPillWidth()
    local env_compound_w = InspTrackEnvCompoundBaseWidth and InspTrackEnvCompoundBaseWidth(row_h)
        or (r.ImGui_CalcTextSize(ctx, "ENV") + 18 + row_h)
    return fx_compound_w + gap + env_compound_w + gap + route_w
end

InspCardMinWidth = function()
    return math.max(InspHeaderPanInlineMinWidth(), InspControlsInlineMinWidth())
end

RecordInputChevronWidth = function()
    return S(9)
end

DrawRecordInputChevron = function(dl, x2, y1, y2, pad_x, col)
    local w = RecordInputChevronWidth()
    local h = S(5)
    local cx = x2 - pad_x - w / 2 - 1.5
    local cy = (y1 + y2) / 2
    local stroke = math.max(1, S(1.25))
    if r.ImGui_DrawList_PathClear and r.ImGui_DrawList_PathLineTo and r.ImGui_DrawList_PathStroke then
        r.ImGui_DrawList_PathClear(dl)
        r.ImGui_DrawList_PathLineTo(dl, cx - w / 2, cy - h / 2)
        r.ImGui_DrawList_PathLineTo(dl, cx, cy + h / 2)
        r.ImGui_DrawList_PathLineTo(dl, cx + w / 2, cy - h / 2)
        r.ImGui_DrawList_PathStroke(dl, col, 0, stroke)
    else
        r.ImGui_DrawList_AddLine(dl, cx - w / 2, cy - h / 2, cx + 0.25, cy + h / 2, col, stroke)
        r.ImGui_DrawList_AddLine(dl, cx - 0.25, cy + h / 2, cx + w / 2, cy - h / 2, col, stroke)
    end
end

RecordInputBoxWidth = function(track, geom_key, base_w, box_avail, desired_w)
    local w = math.min(box_avail, math.max(base_w, desired_w))
    local cached = record_input_box_width[track]
    if cached and cached.geom_key == geom_key then
        w = math.max(cached.w or w, w)
    end
    record_input_box_width[track] = { geom_key = geom_key, w = w }
    return w
end

InspDrawRecordInputRow = function(track, hdr, row_y, row_h, bw, text_pad, meter_row_h)
    local step_w = row_h
    local current_value = math.floor(r.GetMediaTrackInfo_Value(track, "I_RECINPUT") or -1)
    local label = RecordInputValueLabel(current_value, track)
    local box_w = math.max(step_w, bw - step_w * 2)
    local x = hdr.trk_sx + text_pad

    local sx = hdr.trk_cx + text_pad
    local sy = hdr.trk_cy + row_y - hdr.trk_sy
    local left_w = box_w
    local prev_x = x + left_w
    local next_x = prev_x + step_w
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local row_bg = C.fx_ctrl_bg
    local hover_bg = C.fx_ctrl_hover
    local active_bg = C.fx_ctrl_active
    local chevron_rest = rgb(0x5C5E62)
    local chevron_hover = rgb(0x8B8B8C)
    local text_col = (C.text & 0xFFFFFF00) | 0xBF

    r.ImGui_DrawList_AddRectFilled(dl, sx, sy, sx + bw, sy + row_h, row_bg, S(UI.corner_r))

    r.ImGui_SetCursorPos(ctx, x, row_y)
    r.ImGui_InvisibleButton(ctx, "##recinput", left_w, row_h)
    local input_hov = r.ImGui_IsItemHovered(ctx)
    local input_act = r.ImGui_IsItemActive(ctx)
    local clk = r.ImGui_IsItemClicked(ctx, 0)
    local rclk = r.ImGui_IsItemClicked(ctx, 1)
    Tip("Record input")
    if clk then r.ImGui_OpenPopup(ctx, "##recinput_popup") end
    if rclk then RecordInputOpenContext(track, current_value) end

    if input_hov or input_act then
        r.ImGui_DrawList_AddRectFilled(dl, sx, sy, sx + left_w, sy + row_h,
            input_act and active_bg or hover_bg, S(UI.corner_r),
            r.ImGui_DrawFlags_RoundCornersLeft())
    end

    local left_icon_col = (input_hov or input_act) and chevron_hover or chevron_rest
    DrawRecordInputChevronImage(dl, sx + step_w / 2, sy + row_h / 2, "down", left_icon_col)

    local fp2 = PushFont(GetSteppedFont(UI.font_fx))
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    local text_x = sx + step_w
    local label_avail = math.max(1, sx + left_w - S(8) - text_x)
    local display = RecordInputClipLabel(label, label_avail)
    local ty = sy + Round((row_h - text_h) / 2)
    r.ImGui_DrawList_AddText(dl, text_x, ty, text_col, display)
    PopFont(fp2)

    RecordInputPopup(track, "##recinput_popup", current_value)
    RecordInputContextPopup(track, true)

    r.ImGui_SetCursorPos(ctx, prev_x, row_y)
    r.ImGui_InvisibleButton(ctx, "##recinput_prev", step_w, row_h)
    local prev_hov = r.ImGui_IsItemHovered(ctx)
    local prev_act = r.ImGui_IsItemActive(ctx)
    local up_clk = r.ImGui_IsItemClicked(ctx, 0)
    Tip("Previous input")
    if prev_hov or prev_act then
        r.ImGui_DrawList_AddRectFilled(dl, sx + left_w, sy, sx + left_w + step_w, sy + row_h,
            prev_act and active_bg or hover_bg, 0)
    end
    DrawRecordInputChevronImage(dl, sx + left_w + step_w / 2, sy + row_h / 2, "left",
        (prev_hov or prev_act) and chevron_hover or chevron_rest)
    if up_clk then RecordInputStep(track, -1) end

    r.ImGui_SetCursorPos(ctx, next_x, row_y)
    r.ImGui_InvisibleButton(ctx, "##recinput_next", step_w, row_h)
    local next_hov = r.ImGui_IsItemHovered(ctx)
    local next_act = r.ImGui_IsItemActive(ctx)
    local down_clk = r.ImGui_IsItemClicked(ctx, 0)
    Tip("Next input")
    if next_hov or next_act then
        r.ImGui_DrawList_AddRectFilled(dl, sx + left_w + step_w, sy, sx + bw, sy + row_h,
            next_act and active_bg or hover_bg, S(UI.corner_r),
            r.ImGui_DrawFlags_RoundCornersRight())
    end
    DrawRecordInputChevronImage(dl, sx + left_w + step_w + step_w / 2, sy + row_h / 2, "right",
        (next_hov or next_act) and chevron_hover or chevron_rest)
    if down_clk then RecordInputStep(track, 1) end
end

InspTrackContextMenu = function(track, track_name, popup_id)
    if r.ImGui_BeginPopup(ctx, popup_id) then
        local rfp = PushFont(GetScaledFont())
        if r.ImGui_MenuItem(ctx, "Rename") then
            insp_rename_type = "track"; insp_rename_idx = nil
            insp_rename_buf = track_name; insp_rename_focus = false; insp_rename_frames = 0
        end
        -- v20.485: routing clipboard
        r.ImGui_Separator(ctx)
        local _ns = r.GetTrackNumSends(track, 0)
        local _nr = r.GetTrackNumSends(track, -1)
        local _nh = r.GetTrackNumSends(track, 1)
        r.ImGui_BeginDisabled(ctx, _ns == 0)
        if r.ImGui_MenuItem(ctx, "Copy all sends") then
            RoutingClipboardCopyAll(track, 0)
        end
        r.ImGui_EndDisabled(ctx)
        r.ImGui_BeginDisabled(ctx, _nr == 0)
        if r.ImGui_MenuItem(ctx, "Copy all receives") then
            RoutingClipboardCopyAll(track, -1)
        end
        r.ImGui_EndDisabled(ctx)
        r.ImGui_BeginDisabled(ctx, _nh == 0)
        if r.ImGui_MenuItem(ctx, "Copy all HW Sends") then
            RoutingClipboardCopyAll(track, 1)
        end
        r.ImGui_EndDisabled(ctx)
        local _plbl = RoutingClipboardPasteLabel()
        if _plbl and r.ImGui_MenuItem(ctx, _plbl) then
            RoutingClipboardPaste(track)
        end
        PopFont(rfp)
        r.ImGui_EndPopup(ctx)
    end
end

-- =========================================================================
-- UI LAYOUT TOKENS
-- =========================================================================
-- All spacing/sizing goes through these tokens via S(UI.xxx).
-- Rules:
--   1. Containers (headers, columns, panels) use UI.pad internal padding on all sides.
--   2. Elements within a row are separated by UI.pad_sm (standard element gap).
--   3. Button groups are separated by UI.group_gap (e.g. S↔FX, pan↔vol).
--   4. Vertical gap between control rows = UI.row_gap.
--   5. Vertical gap between major sections (header→slider, slider→controls, controls→FX) = UI.section_gap.
--   6. Elements sharing a horizontal row MUST use the same total height and
--      be placed at the same cursor Y. Use (row_h - elem_h) / 2 to center
--      shorter elements within the row.
--   7. Circle nav buttons (flow, sends, routing on nav bar) use DrawNavCircleButton
--      which guarantees identical size and alignment.
--   8. Text that may overflow truncates via Utf8DropLast + "…" ellipsis,
--      never PushClipRect (which cuts mid-glyph, showing half-characters at the edge).
--   9. All corner radii use UI.corner_r unless the element is a pill (radius = height/2).
UI = {
    pad         = 10,  -- container padding (headers, columns, sections)
    pad_sm      = 6,   -- small padding (pill internals, tight gaps)
    row_gap     = 10,  -- gap between control rows within a section
    section_gap = 10,  -- gap between major sections
    btn_h       = 26,  -- standard button height
    group_gap   = 10,  -- gap between button groups
    ctrl_sz     = 22,  -- smaller control height (routing pill, env dots)
    corner_r    = 4,   -- standard corner radius
    fx_gap      = 6,   -- gap between FX rows
    meter_h     = 6,   -- meter bar height
    slider_h    = 22,  -- volume slider height
    circ_btn_r  = 13,  -- nav circle button radius
    hdr_row_gap = 14,  -- gap between header row 1 and row 2
    -- Per-boundary section-gap offsets (added to section_gap before scaling).
    -- Top-margin-only convention: each section owns S(section_gap + gap_xxx) above itself.
    gap_hdr_vol    = -(18 / 1.44),  -- HDR → VOL
    gap_vol_ctrl   = 10,  -- VOL → CTRL
    gap_ctrl_route = 0,  -- CTRL → ROUTE
    gap_ctrl_fx    = 0,  -- CTRL/ROUTE → FX
    gap_route_fx   = 14,  -- extra ROUTE(expanded) → FX (added only when routing panel is open)
    gap_bottom     = 0,  -- FX → FLOW/CMP
    gap_sends      = 4,  -- above SENDS separator line
    card_r         = 12, -- card container corner radius
    card_stroke    = 3,  -- card border stroke width (legacy, kept for token compatibility)
    card_pad       = 18 / 1.44, -- card horizontal padding; 18 Retina px at 100%
    card_pad_top   = 18 / 1.44, -- card top inner padding
    card_pad_bot   = 18 / 1.44, -- card bottom inner padding
    card_gap       = 12, -- gap between independent cards (send rows)
    flow_gap       = 3,  -- gap between connected flow cards (tight, shows bg as separator)
    edge_pad       = 12, -- window border padding (main window + content margin)
    nav_inspector_gap_px = 21, -- literal Retina px; keep as half-logical, do not round through S()
    send_pad_top   = 10, -- send/folder column top padding (independent of card_pad_top)
    send_pad_bot   = 17, -- send column bottom padding
    send_folder_pad_bot = 12, -- send folder card bottom padding
    -- Font step offsets (added to base step = ui_scale * 0.8 * 10)
    font_title     = 3,  -- nav pill headers, section headers (bold)
    font_insp_name = 4,  -- main inspector track name (largest)
    font_section   = 2,  -- section headers (SENDS pill etc)
    font_fx        = 0,  -- FX row names, send column FX
    font_send_title = 0, -- send/folder column titles
    bg_label_gap_above = 25, -- gap above background-level section labels
    bg_label_gap_below = 16, -- gap below background-level section labels (to content)
}

-- Layout constants (formerly tunable via Design Mode, now fixed values)
INSP_MAX_W   = 295   -- inspector column cap in two-column layout (logical px, raw)
STROKE_W     = 1.5   -- card/send stroke width (logical px, S()-scaled at use sites)
SOURCE_STROKE_W = 1.5 -- pinned/source card stroke: 3 Retina px, raw draw-list px
FLOW_STROKE_W = 1.5   -- selected flow-card stroke: 3 Retina px, raw draw-list px
CARD_STROKE_TESSELLATION_MAX_ERROR = 0.005 -- tighter arcs for visible stroked card corners
WIN_MIN_W    = 280   -- main window minimum width constraint
WIN_MAX_W    = 480   -- main window maximum width constraint
TWO_COL_MULT = 1.75  -- minimum-viable-width multiplier for two-column layout threshold

-- UTF-8 safe: remove last character (handles multibyte)
Utf8DropLast = function(s)
    local len = #s
    if len == 0 then return s end
    -- Back up past continuation bytes (10xxxxxx = 0x80-0xBF)
    while len > 0 and s:byte(len) >= 0x80 and s:byte(len) <= 0xBF do len = len - 1 end
    -- Drop the leading byte of the last character
    if len > 0 then len = len - 1 end
    return s:sub(1, len)
end

-- =========================================================================
-- SUB-GROUP SYSTEM
-- =========================================================================
local MONITOR_MUSICIANS = { RORY = true, ZAC = true, BILLY = true, SCOTT = true, OUTPUTS = true }
local SONG_SECTIONS = { ["LIVE FX"] = true, ["PLAYBACK"] = true }

MakePrefKey = function(name) return name:lower():gsub("[^%w]", "") .. "_expanded" end

CreateSubGroup = function(parent_name, filter_fn)
    return {
        parent_name = parent_name, entry_ref = nil, entries = {}, selected = {},
        ui_expanded = LoadPref(MakePrefKey(parent_name), true), filter_fn = filter_fn,
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

-- Songs sub-section system (LIVE FX / PLAYBACK within current song)
songs_sub = {
    is_song_sub = true, parent_name = "SONGS", entry_ref = nil,
    entries = {}, selected = {},
    ui_expanded = LoadPref(MakePrefKey("SONGS"), true),
    song_name = "", song_track = nil, song_idx = -1,
}
songs_section_mode = false

-- =========================================================================
-- STATE
-- =========================================================================
top_folders = {}
archive_entry = nil
needs_rescan = true
local window_initialized = false
current_page = "tracks"

song_entries = {}
song_search = ""
needs_song_rescan = true

viewlock_song, viewlock_start, viewlock_end = "", 0, 0
songs_entry_ref = nil
songs_follow_active = false
songs_follow_last = ""

render_list = {}
tracks_last_click = nil      -- label of last-clicked TLT (for shift range select)
tracks_range_anchor_guid = nil
songs_last_click = nil

-- =========================================================================
-- PIN CORE
-- =========================================================================
package.loaded["Reflex_PinCore"] = nil
require("Reflex_PinCore")({ r = r, PREF = PREF })
LoadPinnedFolders()

-- =========================================================================
-- NAV TREE DISCLOSURE CORE
-- =========================================================================
package.loaded["Reflex_NavTreeCore"] = nil
require("Reflex_NavTreeCore")({
    r = r,
    get_render_list = function() return render_list end,
    mark_dirty = function() needs_rescan = true end,
})
LoadNavTreeExpansion()

-- =========================================================================
-- NAV EXCLUSION CORE
-- =========================================================================
package.loaded["Reflex_NavExclusionCore"] = nil
require("Reflex_NavExclusionCore")({
    r = r,
    PREF = PREF,
    get_top_folders = function() return top_folders end,
    set_track_vis = SetTrackVis,
    mark_dirty = function() needs_rescan = true; needs_song_rescan = true end,
})
LoadNavExcluded()

-- =========================================================================
-- NAV INCLUSION CORE
-- =========================================================================
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

-- Shared NAV action handlers are installed after view-history setup.

-- Inspector state
navigator_expanded = LoadPref("navigator_expanded", true)
nav_visible = LoadPref("nav_visible", true)
local reflex_window_docked = false
local reflex_current_dock_id = 0
local reflex_last_side_dock_pos = nil
-- nav_mirror: when true, expanded TLT pill contents flow [circle | (arrow) | text | pin]
-- (left-to-right) instead of the default [pin | text | (arrow) | circle]. For users
-- docking Reflex on the right side of the screen. Only affects expanded TLT rows;
-- compressed mini-circles and inspector layout unchanged. Persists with other
-- nav-section prefs (navigator_expanded, nav_visible) -- keep these grouped
-- when splitting Navigator off into a standalone script.
nav_mirror = LoadPref("nav_mirror", false)
nav_tlt_search_text = ""
nav_tlt_search_effective_query = ""
nav_tlt_search_active = false
nav_tlt_search_visible = false
nav_tlt_search_esc_consumed = false
nav_tlt_search_hide_clear = false
nav_tlt_search_recent_clear_frames = 0
nav_tlt_search_focus_requested_frames = 0
nav_tlt_search_force_empty_frames = 0
local insp_visible = LoadPref("insp_visible", true)
local insp_track = nil
-- v20.436 Stage D: legacy `local insp_fx = {}` slot REMOVED. FX records are
-- now keyed per-track in `track_fx_cache` (declared elsewhere). Read via
-- `InspGetFxList(track)` / `InspGetFxCount(track)` / `track_fx_cache[track]`.
-- Invalidate via `InspInvalidateTrackFx(track)` or the bug-fix-aware
-- `InspMarkTrackFxDirty(track)`. See Stages A–D in the v20.432–v20.436
-- changelog comments for the migration history.
local insp_env_expanded = {}
local insp_pinned = false
local insp_pin_suppress_selected = false  -- suppress secondary card after flow→normal
local insp_pin_last_sel_guid = nil        -- track selection changes to clear suppress
local insp_pin_sel_env = {}               -- persistent envelope state for secondary card
local insp_pin_sel_frames = 0             -- frame counter: skip frame 0 to avoid height glitch

-- Remote macro pad state
local remote_expanded = true  -- internal only, always expanded when visible
local remote_visible = LoadPref("remote_visible", false)
local remote_height = LoadPref("remote_height", 120)
local remote_dragging = false
local nav_inspector_split_h = LoadPref("nav_inspector_split_h", nil)
local nav_inspector_temp_split_h = LoadPref("nav_inspector_temp_split_h", nil)
local nav_inspector_dragging = false
local two_column_dragging = false
local two_column_dragging_id = nil
local nav_sends_left_overflow = false
local nav_sends_left_content_h = nil
local last_nav_side_layout = false

ReflexDrawNavSplitHandle = function(handle_w, gap_hit_h, max_split_h)
    if not (nav_visible and (navigator_expanded == true or nav_temporary_expanded == true)) then return end
    if not gap_hit_h or gap_hit_h <= 0 then return end
    handle_w = math.max(1, handle_w or 1)
    local gap_cursor_x = r.ImGui_GetCursorPosX(ctx)
    local gap_cursor_y = r.ImGui_GetCursorPosY(ctx)
    local gap_screen_x, content_screen_y = r.ImGui_GetCursorScreenPos(ctx)
    local hit_y = gap_cursor_y - gap_hit_h
    local hit_screen_y = content_screen_y - gap_hit_h
    local handle_h = 3.5 * nav_ui_scale
    local handle_y = hit_screen_y + (gap_hit_h - handle_h) * 0.5
    local handle_inset = math.min(S(UI.card_r), handle_w * 0.25)
    local handle_x = gap_screen_x + handle_inset
    local draw_w = math.max(1, handle_w - handle_inset * 2)
    r.ImGui_SetCursorPosY(ctx, hit_y)
    r.ImGui_InvisibleButton(ctx, "##nav_inspector_divider", handle_w, gap_hit_h)
    local divider_hovered = r.ImGui_IsItemHovered(ctx)
    local divider_active = r.ImGui_IsItemActive(ctx)
    if divider_hovered or divider_active then
        r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNS())
        local dl = r.ImGui_GetWindowDrawList(ctx)
        r.ImGui_DrawList_AddRectFilled(dl, handle_x, handle_y,
            handle_x + draw_w, handle_y + handle_h, rgb(0x8B8B8C), handle_h * 0.5)
    end
    if divider_active then
        local _, dy = r.ImGui_GetMouseDelta(ctx)
        if dy ~= 0 then
            local resizing_temp_nav = nav_temporary_expanded == true and navigator_expanded ~= true
            local current_split_h = (resizing_temp_nav and nav_inspector_temp_split_h or nav_inspector_split_h)
                or math.max(S(60), last_nav_h - (UI.nav_inspector_gap_px or 21) * 0.5 * nav_ui_scale)
            local min_split_h = S(72)
            max_split_h = math.max(min_split_h, max_split_h or min_split_h)
            local next_split_h = math.max(min_split_h, math.min(max_split_h, current_split_h + dy))
            if resizing_temp_nav then
                nav_inspector_temp_split_h = next_split_h
                SavePref("nav_inspector_temp_split_h", nav_inspector_temp_split_h)
            else
                nav_inspector_split_h = next_split_h
                SavePref("nav_inspector_split_h", nav_inspector_split_h)
            end
        end
        nav_inspector_dragging = true
    elseif nav_inspector_dragging then
        nav_inspector_dragging = false
    end
    r.ImGui_SetCursorPos(ctx, gap_cursor_x, gap_cursor_y)
end

ReflexTwoColumnLeftMinWidth = function()
    return math.max(1, S(48))
end

ReflexTwoColumnDefaultLeftWidth = function()
    local sends_min = ReflexSendsColumnMinWidth and ReflexSendsColumnMinWidth() or S(160)
    return math.max(ReflexTwoColumnLeftMinWidth(), sends_min, S(220))
end

ReflexTwoColumnResolvedLeftWidth = function()
    local w = tonumber(two_column_left_w) or ReflexTwoColumnDefaultLeftWidth()
    return math.max(ReflexTwoColumnLeftMinWidth(), w)
end

ReflexDrawColumnSplitHandle = function(id, x, y1, gap_w, y2, total_w, side_gap, current_w)
    if not id or gap_w <= 0 or y2 <= y1 then return end
    local hit_w = math.min(gap_w, math.max(3.5 * nav_ui_scale, S(4)))
    local hit_x = x + (gap_w - hit_w) * 0.5
    local hovered = r.ImGui_IsMouseHoveringRect(ctx, hit_x, y1, hit_x + hit_w, y2)
    if hovered and r.ImGui_IsMouseClicked(ctx, 0) then
        two_column_dragging = true
        two_column_dragging_id = id
    end
    local active = two_column_dragging == true
        and two_column_dragging_id == id
        and r.ImGui_IsMouseDown(ctx, 0)
    if hovered or active then
        local cursor = r.ImGui_MouseCursor_ResizeEW and r.ImGui_MouseCursor_ResizeEW()
            or r.ImGui_MouseCursor_ResizeNS()
        r.ImGui_SetMouseCursor(ctx, cursor)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local handle_w = math.max(1, 7 * 0.5 * nav_ui_scale)
        local hx = x + gap_w * 0.5 - handle_w * 0.5
        r.ImGui_DrawList_AddRectFilled(dl, hx, y1, hx + handle_w, y2, rgb(0x8B8B8C), handle_w * 0.5)
    end
    if active then
        local dx = r.ImGui_GetMouseDelta(ctx)
        if dx ~= 0 then
            local min_w = ReflexTwoColumnLeftMinWidth()
            local max_w = math.max(min_w, (total_w or 0) - (side_gap or 0) - ReflexInspectorColumnMinWidth())
            local base_w = tonumber(current_w) or math.min(ReflexTwoColumnResolvedLeftWidth(), max_w)
            two_column_left_w = math.max(min_w, math.min(max_w, base_w + dx))
            SavePref("two_column_left_w", two_column_left_w)
        end
        two_column_dragging = true
    elseif two_column_dragging_id == id then
        two_column_dragging = false
        two_column_dragging_id = nil
    end
end
local settings_open = false
local settings_win_pos_set = false   -- true after first open this session (position chosen)
local settings_win_x = LoadPref("settings_win_x", nil)
local settings_win_y = LoadPref("settings_win_y", nil)
local settings_routing_depth_open = false
settings_fx_browser_open = false
local settings_send_cols_open = false
local settings_noisy_open = false
local settings_panel_h = 600
local nav_sb_w = 0   -- no scrollbar; thin indicator drawn in edge_pad margin
card_heights_prev = {}  -- card heights from previous frame (for fill estimation)
card_heights_cur = {}   -- card heights being measured this frame
card_idx = 0            -- per-frame card counter
-- Sends scroll state (independent column scrolling)
local sends_scroll_y = 0
local sends_scroll_max = 0
local sends_scroll_target = nil
local sends_scroll_child_h = 100
-- Scroll indicator fade (>1.0 = hold visible, 1→0 = fading, 0 = hidden)
local insp_scroll_prev_y = -1
local insp_scroll_fade = 0
local sends_scroll_prev_y = -1
local sends_scroll_fade = 0
local sends_expand_scroll_cy = nil  -- cursor-Y of card that was just expanded (auto-scroll next frame)
local scroll_fade_last_t = 0
nav_scroll_y = 0
nav_scroll_max = 0
nav_scroll_target = nil
nav_child_h = 100
-- NAV expanded-list scroll indicator state
nav_list_scroll_prev_y = -1
nav_list_scroll_fade = 0
nav_list_scroll_y = 0
nav_list_scroll_max = 0
nav_list_child_h = 0
local remote_popped_out = LoadPref("remote_popped_out", false)
local remote_pop_w = LoadPref("remote_pop_w", 300)
local remote_pop_h = LoadPref("remote_pop_h", 200)
local remote_pop_initialized = false
local remote_buttons = {}
local remote_undo_stack = {}
local remote_redo_stack = {}
local REMOTE_UNDO_MAX = 30
local remote_prompt_active = false
local remote_prompt_target = nil
local remote_ctx_idx = nil
local remote_drag_idx = nil
local remote_drag_active = false
local remote_drag_sx, remote_drag_sy = 0, 0
local remote_selected = {}            -- set of selected indices (shift+click)
local remote_clipboard = {}           -- copied button data
local remote_cols = LoadPref("remote_cols", 4)
local remote_default_height = LoadPref("remote_default_height", 3)
local remote_icon_cache = {}          -- filename → ImGui image handle
local remote_icon_list = nil          -- cached list of available icon filenames
local remote_icon_picker_idx = nil    -- button index being assigned an icon (triggers open)
local remote_icon_picker_open = nil   -- button index while picker is open
local remote_icon_search = ""

-- FX browser state (globals — at 200/200 local limit)
fx_browser_open = false
fx_browser_search = ""
fx_browser_target_btn = nil
fx_browser_target_track = nil  -- when set, add FX to this track instead of insp_track
fx_browser_cache = nil
fx_browser_filter = nil
fx_browser_drag_name = nil
fx_browser_focus_search = false
fx_browser_clipper = nil
FX_BROWSER_PROVIDER_REFLEX = "reflex"
FX_BROWSER_PROVIDER_NVK = "nvk"
FX_BROWSER_PROVIDER_REAPER = "reaper"
FX_BROWSER_PROVIDER_CUSTOM = "custom"
FX_BROWSER_NVK_COMMAND = "_RS42ab70fd2ac65e9a003787709bb85f18c36dee52"
fx_browser_provider = LoadPref("fx_browser_provider", FX_BROWSER_PROVIDER_NVK)
if fx_browser_provider ~= FX_BROWSER_PROVIDER_REFLEX
   and fx_browser_provider ~= FX_BROWSER_PROVIDER_NVK
   and fx_browser_provider ~= FX_BROWSER_PROVIDER_REAPER
   and fx_browser_provider ~= FX_BROWSER_PROVIDER_CUSTOM then
    fx_browser_provider = FX_BROWSER_PROVIDER_NVK
end
external_fx_session = nil
external_fx_selection_guard = false
reflex_open_fx_suppress_until = 0
reflex_fx_window_cycle = { track_guid = nil, fx_guid = nil, managed = {}, protected = {} }
reflex_keyboard_capture_requested = false
remote_btn_rects = {}
remote_pages = { { name = "Main", color = 0, height = 1 } }
remote_current_page = 1
remote_page_ctx = nil
remote_page_drag_idx = nil
remote_last_content_h = 0

-- Routing view state
routing_view_active = false
routing_view_source = nil
routing_view_sources = {}
routing_view_tracks = {}  -- set: track_ptr → true
routing_view_depth = LoadPref("routing_depth", 1)
routing_view_saved_snap = nil       -- visibility snapshot from before entering routing view
-- Selected Tracks View state
selected_view_active = false
selected_view_tracks = {}
selected_view_saved_snap = nil
-- Armed View state
armed_view_active = false
armed_view_tracks = {}
armed_view_saved_snap = nil
-- Active view state (signal-based track visibility)
active_view_active = false
active_view_tracks = {}             -- set: track_ptr → true
active_view_peak_times = {}         -- track_ptr → last time peak was above threshold
active_view_signal_available = false -- cached by ActiveViewUpdatePeaks for NAV A disabled state
active_view_threshold = 0.001       -- ~-60dB linear
active_view_window = 3.0            -- seconds to look back
active_view_last_play = 0           -- previous transport state for start detection
active_view_last_peak_scan_time = 0
active_view_peak_scan_interval = 0.10
active_view_idle_peak_scan_interval = 0.50
active_view_saved_snap = nil        -- visibility snapshot from before entering active view
active_view_flash_time = 0          -- time_precise() when Active was last triggered (for flash animation)

flow_view_active = false
flow_view_chain = {}                -- display-ordered list of track pointers (top → bottom)
flow_view_scroll_pending = false    -- auto-scroll on activation
flow_view_anchor = nil              -- focus track that defines the chain
flow_view_browsing = false          -- true = selection change came from flow card click (skip re-anchor)
flow_view_expanded_set = {}         -- v20.431: track_ptr → true; non-focus cards rendered as full
flow_env_expanded = {}        -- per-track env expansion: track_ptr → insp_env_expanded table
-- Canonical per-track FX record cache. Single source of truth as of v20.437
-- (Stage G — flow_fx_cache merged in; previously the two coexisted as aliases
-- after Stage D removed the legacy file-scope insp_fx slot in v20.436).
-- Readers all go through InspGetFxList / InspGetFxCount or read
-- track_fx_cache[track] directly.
--
-- Invalidate via InspInvalidateTrackFx(track) or InspMarkTrackFxDirty(track)
-- (which also handles the "is this insp_track" rescan-eagerly bit).
track_fx_cache = {}           -- per-track FX cache: track_ptr → { list, count }

-- Route row slider drag state
route_slider_drag_id = nil      -- string ID of currently-dragged slider (nil = none)
route_hovered_send_idx = nil    -- send index hovered in routing panel (for sends view highlight)

-- Sends view state
sends_view_active = false
sends_view_tracks = {}            -- ordered list of send dest track pointers
sends_view_send_indices = {}      -- parallel list: send index on source for each dest track
sends_view_cols = LoadPref("sends_view_cols", 3)  -- columns per row (1-6)
sends_view_scroll_pending = false  -- scroll to sends on activation
sends_view_source = nil            -- source track for current sends list
sends_view_last_send_count = -1    -- cached send count for change detection
sends_fx_cache = {}                -- per-track FX cache: track_ptr → { names={}, count=N }
sends_view_groups = {}             -- grouped sends: { folder_chain={}, indices={} } per sibling folder
sends_view_distant = {}            -- remote/distant sends: { {svi=int, track=ptr, is_sidechain=bool}, ... }
sends_distant_expanded = {}        -- expanded distant pill indices: [di] = true
sends_distant_rendering = false    -- flag: suppresses stroke in DrawCompactTrackColumn for distant cards
sends_distant_collapse_request = false  -- flag: SND-header click in distant mode requests outer collapse
sends_folder_expanded = {}         -- expanded folder cards: [track_ptr] = true
reflex_focused_window_chain_cache = { focus = nil, chain = nil }

-- Per-frame cache of FX row geometry for sends view columns, keyed by 0-based fi.
-- (Historical: sends_fx_drag_* state migrated to unified fx_drag in v20.394.)
sends_fx_rects = {}

-- Knob per-peak smoothing
knob_meter_peak = {}  -- per-knob peak smoothing (keyed by meter_key, avoids insp_meter_peak conflicts)
sends_snd_expanded = {}  -- per-send SND section expand state (keyed by send_idx, default collapsed)

-- Option C drag state for NavParamKnob sites. Each table holds { before, moved } mutated in place.
-- fc = folder card, sk = send knob, rk = return knob. Folder narrow/wide share state (only one branch runs per frame).
fcvol_state = { before = nil, moved = false }
fcpan_state = { before = nil, moved = false }
skvol_state = { before = nil, moved = false }
skpan_state = { before = nil, moved = false }
rkvol_state = { before = nil, moved = false }
rkpan_state = { before = nil, moved = false }

remote_ctx_tlf_guid = nil             -- TLT guid for mini circle right-click menu (v20.480: was label)
remote_ctx_tlf_track = nil            -- TLT track for shared NAV.dot context menu actions
remote_ctx_tlf_ghost_parent = nil     -- ignored parent for promoted NAV.dot context rows
remote_ctx_tlf_custom = false         -- custom-included NAV.dot context row
local last_content_used_h = 0         -- previous frame's content height for adaptive remote
local last_inspector_cards_content_h = nil
local last_inline_sends_content_h = nil
local last_inline_sends_overflow = false
last_nav_h = 0                        -- previous frame's nav height for adaptive remote
last_nav_natural_h = 0                -- previous frame's NAV expanded-content natural height (drives BeginChild sizing)
last_nav_collapsed_visible_h = 0      -- shared NAV renderer state
last_nav_expanded_visible_h = 0
last_nav_body_offset_y = 0
last_nav_header_offset_y = 0
local nav_screen_rect = { x = 0, y = 0, w = 300, h = 500 } -- Reflex window rect for FX positioning

-- =========================================================================
-- I/O MANAGER CORE (floating panel UI)
-- =========================================================================
package.loaded["Reflex_IOManagerCore"] = nil
require("Reflex_IOManagerCore")({
    r = r,
    ctx = ctx,
    colors = C,
    nav_screen_rect = nav_screen_rect,
})

-- Position a newly opened FX floating window to avoid overlapping Reflex
InspPositionFXWindow = function(track, fx_idx)
    if not r.JS_Window_SetPosition then return end
    r.defer(function()
        local hwnd = r.TrackFX_GetFloatingWindow(track, fx_idx)
        if not hwnd then return end
        local _, fx_x, fx_y, fx_r, fx_b = r.JS_Window_GetRect(hwnd)
        local fx_w = fx_r - fx_x
        local fx_h = fx_b - fx_y
        local nr = nav_screen_rect
        -- Check overlap
        local overlaps = fx_x < (nr.x + nr.w) and (fx_x + fx_w) > nr.x
                     and fx_y < (nr.y + nr.h) and (fx_y + fx_h) > nr.y
        if not overlaps then return end
        -- Determine which side has more room
        local _, _, screen_w, screen_h = r.my_getViewport(0, 0, 0, 0, 0, 0, 0, 0, true)
        local space_right = screen_w - (nr.x + nr.w)
        local space_left = nr.x
        local new_x, new_y
        if space_right >= space_left then
            new_x = nr.x + nr.w + 8
        else
            new_x = nr.x - fx_w - 8
        end
        new_y = fx_y
        -- Clamp to screen
        new_x = math.max(0, math.min(new_x, screen_w - fx_w))
        new_y = math.max(0, math.min(new_y, screen_h - fx_h))
        -- Tile: offset down if another FX window is at the same position
        r.JS_Window_SetPosition(hwnd, new_x, new_y, fx_w, fx_h)
    end)
end
local CMP_EXT_SECTION = "ReaFX_Compare"
-- Composite key: trackGUID+fxGUID prevents collision when FX GUIDs are duplicated (copy/paste)
CmpKey = function(track, fx_idx)
    return (r.GetTrackGUID(track) or "") .. (r.TrackFX_GetFXGUID(track, fx_idx) or "")
end
local insp_route_dragging = false
local insp_route_click_x, insp_route_click_y = 0, 0
route_drag_targets = {}
route_drag_targets_prev = {}
route_drag_source_track = nil
route_drag_release_pending = nil

RouteDragBeginFrame = function()
    route_drag_targets_prev = route_drag_targets or {}
    route_drag_targets = {}
    if not r.ImGui_IsMouseDown(ctx, 0) and not insp_route_dragging then
        route_drag_source_track = nil
    end
end

RouteDragRegisterCardTarget = function(track, x, y, w, h, dl, rounding)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    if not x or not y or not w or not h or w <= 0 or h <= 0 then return end
    route_drag_targets[#route_drag_targets + 1] = { track = track, x = x, y = y, w = w, h = h }
    if insp_route_dragging and route_drag_source_track
       and track ~= route_drag_source_track then
        local mx, my = r.ImGui_GetMousePos(ctx)
        if mx >= x and mx <= x + w and my >= y and my <= y + h and dl then
            r.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, C.route_send,
                rounding or S(UI.card_r), 0, math.max(1, S(1.5)))
        end
    end
end

RouteDragResolveCardTarget = function(mx, my)
    local function scan(list)
        if not list then return nil end
        for i = #list, 1, -1 do
            local e = list[i]
            if e and mx >= e.x and mx <= e.x + e.w
               and my >= e.y and my <= e.y + e.h
               and e.track and r.ValidatePtr(e.track, "MediaTrack*") then
                return e.track
            end
        end
        return nil
    end
    return scan(route_drag_targets) or scan(route_drag_targets_prev)
end

RouteDragCreateSend = function(source_track, dest_track)
    if not source_track or not r.ValidatePtr(source_track, "MediaTrack*") then return false end
    if not dest_track or not r.ValidatePtr(dest_track, "MediaTrack*") then return false end
    if dest_track == source_track then return false end
    r.Undo_BeginBlock()
    local si = r.CreateTrackSend(source_track, dest_track)
    if si >= 0 then
        r.SetTrackSendInfo_Value(source_track, 0, si, "I_MIDIFLAGS", 31)
    end
    r.Undo_EndBlock("Reflex: Create send", -1)
    if si >= 0 then
        if SendsViewRefresh then SendsViewRefresh() end
        return true
    end
    return false
end

RouteDragQueueRelease = function(source_track)
    local imx, imy = r.ImGui_GetMousePos(ctx)
    local osx, osy = r.GetMousePosition()
    route_drag_release_pending = {
        source = source_track,
        imx = imx,
        imy = imy,
        osx = osx,
        osy = osy,
    }
end

RouteDragProcessPendingRelease = function()
    if not route_drag_release_pending then
        if insp_route_dragging and route_drag_source_track
           and r.ImGui_IsMouseReleased(ctx, 0) then
            RouteDragQueueRelease(route_drag_source_track)
            insp_route_dragging = false
        else
            return
        end
    end

    local pending = route_drag_release_pending
    route_drag_release_pending = nil
    local source_track = pending and pending.source or route_drag_source_track
    local imx = pending and pending.imx or nil
    local imy = pending and pending.imy or nil
    if not imx or not imy then imx, imy = r.ImGui_GetMousePos(ctx) end
    local osx = pending and pending.osx or nil
    local osy = pending and pending.osy or nil
    if not osx or not osy then osx, osy = r.GetMousePosition() end

    local dest_track = RouteDragResolveCardTarget(imx, imy)
    if not dest_track
       and not r.ImGui_IsWindowHovered(ctx, r.ImGui_HoveredFlags_AnyWindow()) then
        dest_track = r.GetTrackFromPoint(osx, osy)
    end
    RouteDragCreateSend(source_track, dest_track)
    insp_route_dragging = false
    route_drag_source_track = nil
end

local insp_cmp_has_any = false
local insp_cmp_check_time = 0
local insp_cmp_count = 0
local insp_vol_dragging = false
local insp_vol_drag_track = nil
local insp_vol_val_dragging = false
local insp_vol_val_drag_track = nil
local insp_vol_drag_moved = false
local insp_vol_button_show_until = setmetatable({}, { __mode = "k" })
local insp_pan_dragging = false
local insp_pan_drag_moved = false
local insp_pan_knob_state = { before = nil, moved = false }
local insp_hdr_card_hovered = setmetatable({}, { __mode = "k" })
local insp_vol_editing = false
local insp_pan_editing = false
local insp_vol_edit_buf = ""
local insp_pan_edit_buf = ""
local insp_vol_edit_focus = false
local insp_pan_edit_focus = false
local insp_vol_edit_frames = 0
local insp_pan_edit_frames = 0
local master_strip_rendering = false
local master_strip_env_expanded = {}
local master_strip_prev_h = nil
insp_wet_dragging = false
insp_wet_drag_moved = false
insp_wet_drag_fi = nil

-- Meter state
insp_meter_clip = {}      -- per-track clip hold: track_ptr → bool
insp_meter_peak = {}      -- per-track smoothed peak: track_ptr → number (fast, for meter fill)
insp_meter_display = {}   -- per-track smoothed peak: track_ptr → number (slow, for dB readout)
insp_meter_noise = {}     -- per-track stereo noise state: track_ptr → { L = state, R = state }
insp_meter_last_play = -1 -- transport state for auto-reset (global, shared)

package.loaded["Reflex_NoiseCore"] = nil
require("Reflex_NoiseCore")({
    r = r,
    get_noise_cache = function() return insp_meter_noise end,
})

-- Per-track cache cleanup: drops entries whose MediaTrack* pointer is dead.
-- Called periodically from Loop to prevent unbounded growth over long sessions.
cache_sweep_counter = 0
SweepDeadTrackCaches = function()
    local caches = {
        insp_meter_clip, insp_meter_peak, insp_meter_display, insp_meter_noise,
        flow_mini_peak, track_fx_cache, nav_track_fx_counts, record_input_box_width,
    }
    for _, cache in ipairs(caches) do
        for t in pairs(cache) do
            if type(t) == "userdata" and not r.ValidatePtr(t, "MediaTrack*") then
                cache[t] = nil
            end
        end
    end
end

-- Per-frame cache of FX row geometry for the inspector, keyed by 1-based fi.
-- Populated by InspDrawFXRow, reset each frame, consumed by drag-target hit testing.
insp_fx_rects = {}

-- =========================================================================
-- FX SELECTION CORE
-- =========================================================================
package.loaded["Reflex_FXSelectionCore"] = nil
require("Reflex_FXSelectionCore")({ r = r })

-- =========================================================================
-- ROUTING CLIPBOARD
-- =========================================================================
package.loaded["Reflex_RoutingClipboard"] = nil
require("Reflex_RoutingClipboard")({ r = r })

-- =========================================================================
-- FX CHUNK CORE
-- =========================================================================
package.loaded["Reflex_FXChunkCore"] = nil
require("Reflex_FXChunkCore")({ r = r })

-- =========================================================================
-- FX DRAG CORE
-- =========================================================================
package.loaded["Reflex_FXDragCore"] = nil
require("Reflex_FXDragCore")({
    r = r,
    ctx = ctx,
    colors = C,
})

-- =========================================================================
-- FX CLIPBOARD CORE
-- =========================================================================
package.loaded["Reflex_FXClipboardCore"] = nil
require("Reflex_FXClipboardCore")({
    r = r,
    ctx = ctx,
    colors = C,
})

-- FX insert-at-position state (drag + button to target) — unchanged
insp_fx_insert_dragging = false
insp_fx_insert_sy = 0
insp_fx_insert_target = nil   -- pending insert position (0-based), nil when inactive
insp_fx_insert_count = 0      -- FX count when browser opened
insp_fx_insert_time = 0       -- time when insert target was set (for stale guard)


InspFxSelTrackWouldRemainVisible = function(primary_track, flow_chain)
    local track = insp_fx_sel_track
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    if primary_track and track == primary_track then return true end
    if flow_view_active and flow_chain then
        for _, chain_track in ipairs(flow_chain) do
            if chain_track == track then return true end
        end
    end
    if sends_view_active then
        if sends_view_source and track == sends_view_source then return true end
        for _, send_track in ipairs(sends_view_tracks) do
            if send_track == track then return true end
        end
    end
    return false
end

-- Clean up in-progress drag state (called on track switch/invalidation).
-- With Option C, drag SetValues are unwrapped; interrupted drags leave
-- "ReaScript: Run" entries in history but no open blocks to close.
-- This function just clears the flag + cached pre-drag values.
-- v20.525: FX multi-selection may persist through FLOW browsing when the
-- selected FX track remains visible in the rendered chain.
InspCleanupDragState = function(opts)
    opts = opts or {}
    if insp_vol_dragging then insp_vol_dragging = false; insp_vol_drag_track = nil; insp_vol_before = nil end
    if insp_vol_val_dragging then insp_vol_val_dragging = false; insp_vol_val_drag_track = nil; insp_vol_val_before = nil end
    if insp_pan_dragging then insp_pan_dragging = false; insp_pan_before = nil end
    if insp_wet_dragging then insp_wet_dragging = false; insp_wet_drag_fi = nil; insp_wet_before = nil end
    FxDragClear()
    if not opts.keep_fx_selection then InspFxSelClear() end
    insp_fx_insert_target = nil; insp_fx_insert_count = 0; insp_fx_insert_time = 0; insp_fx_insert_dragging = false
end

-- FX list collapse state (ephemeral, per track pointer)
insp_fx_collapsed = {}        -- track_ptr → true/false
insp_routing_expanded = {}    -- track_ptr → true/false

-- View history (parallel undo stack for visibility/collapse/selection)
VIEW_HISTORY_MAX = 30
view_history = {}        -- circular buffer of snapshots
view_history_idx = 0     -- current position (1-based, 0 = empty)
view_history_count = 0   -- total entries in buffer
view_history_restoring = 0  -- frame counter: suppress push for N frames after restore
view_history_pushing = false    -- reentrant guard for nested calls
view_history_tlf_debounce = -math.huge  -- timestamp of last TLT-click push (groups rapid clicks)
view_history_launch_baseline = false -- launch sync entry; not a navigable previous view
opt_flow_fx_default_collapsed = LoadPref("flow_fx_default_collapsed", false)

-- FX browser custom action (saved to filesystem, not ExtState)
insp_fx_browser_action = 0
local insp_fx_prompt_active = false

-- Inline rename state
local insp_rename_type = nil   -- "fx", "track", "env" or nil
local insp_rename_idx = nil    -- 0-based fx_idx for fx rename (v20.430: was 1-based ipairs)
local insp_rename_track = nil  -- v20.430: target track for fx rename; "" or nil for track rename
local insp_rename_buf = ""
local insp_rename_focus = false
local insp_rename_frames = 0

-- =========================================================================
-- REALIST CORE (read-only)
-- =========================================================================
package.loaded["Reflex_RealistCore"] = nil
require("Reflex_RealistCore")({
    r = r,
    realist_section = "realist",
})

-- =========================================================================
-- SCAN
-- =========================================================================
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

-- =========================================================================
-- TRACK UTILITIES
-- =========================================================================
package.loaded["Reflex_TrackUtilCore"] = nil
require("Reflex_TrackUtilCore")({
    r = r,
    set_track_vis = SetTrackVis,
})

-- =========================================================================
-- SONGS: CURRENT SONG ONLY
-- =========================================================================
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

-- =========================================================================
-- SUB-GROUP: SAVE / APPLY / SHOW
-- =========================================================================
package.loaded["Reflex_SubGroupCore"] = nil
require("Reflex_SubGroupCore")({
    r = r,
    set_track_vis = SetTrackVis,
})

-- =========================================================================
-- SCROLL TO CENTER
-- =========================================================================
-- View History (parallel undo for visibility/collapse/selection)
package.loaded["Reflex_ViewHistory"] = nil
require("Reflex_ViewHistory")({
    r = r,
    get_insp_pinned = function() return insp_pinned end,
    set_insp_pinned = function(v) insp_pinned = v end,
    get_insp_track = function() return insp_track end,
    set_insp_track = function(track) insp_track = track end,
    reset_insp_env_expanded = function() insp_env_expanded = {} end,
    set_insp_pin_suppress_selected = function(v) insp_pin_suppress_selected = v end,
})

-- Shared NAV action handlers + ScrollTrackToCenter.
package.loaded["Reflex_NavActionCore"] = nil
require("Reflex_NavActionCore")({
    r = r,
    mark_dirty = function() needs_rescan = true; needs_song_rescan = true end,
})

-- Reveal a pinned track: show it, expand parents, select, scroll
InspRevealTrack = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    local ti = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) - 1
    if ti < 0 then return end
    -- Walk forward to find all parent folders of our track
    local folder_stack = {}
    for i = 0, ti - 1 do
        local t = r.GetTrack(0, i)
        local fd = r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
        if fd == 1 then
            folder_stack[#folder_stack + 1] = t
        elseif fd < 0 then
            for _ = 1, math.abs(fd) do
                if #folder_stack > 0 then folder_stack[#folder_stack] = nil end
            end
        end
    end
    -- folder_stack now contains all parent folders
    for _, pt in ipairs(folder_stack) do
        SetTrackVis(pt, true)
        r.SetMediaTrackInfo_Value(pt, "I_FOLDERCOMPACT", 0)
    end
    -- Show the track itself
    SetTrackVis(track, true)
    -- Select and scroll
    ScrollTrackToCenter(track)
end

-- =========================================================================
-- COLOR / BUTTON HELPERS
-- =========================================================================
package.loaded["Reflex_ColorCore"] = nil
require("Reflex_ColorCore")({
    r = r,
    colors = C,
})

StyledButton = function(label, w, h, bg, hover, active, text_col, active_text_col)
    local cc = 3
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), active)
    if text_col then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_col); cc = 4 end
    local clicked = r.ImGui_Button(ctx, label, w, h)
    -- Overdraw text in dimmed color when pressed
    if active_text_col and r.ImGui_IsItemActive(ctx) then
        local bx, by = r.ImGui_GetItemRectMin(ctx)
        local bx2, by2 = r.ImGui_GetItemRectMax(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        r.ImGui_DrawList_AddRectFilled(dl, bx, by, bx2, by2, active, S(6))
        local display = label:match("^(.-)##") or label
        local tw, th = r.ImGui_CalcTextSize(ctx, display)
        local pad_x = S(12)  -- matches TLT button FramePadding
        r.ImGui_DrawList_AddText(dl, bx + pad_x, by + Round(((by2 - by) - th) / 2), active_text_col, display)
    end
    r.ImGui_PopStyleColor(ctx, cc)
    return clicked
end

-- =========================================================================
-- INSPECTOR FUNCTIONS (global assignment — no local slots)
-- =========================================================================
package.loaded["Reflex_EnvelopeCore"] = nil
require("Reflex_EnvelopeCore")({
    r = r,
    colors = C,
    env_alias_section = "reflex_env_alias",
    get_fx_list = function(track) return InspGetFxList(track) end,
})

InspTrackPanEnvelopeActive = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    if InspEnvelopeCacheStale(track) then InspBuildEnvCache(track) end
    local details = InspGetAllTrackEnvelopeDetails(track)
    for _, ed in ipairs(details) do
        if (ed.fx_idx == -1 or ed.fx_idx == nil) and ed.name == "Pan" and not ed.bypassed then
            return true
        end
    end
    return false
end

InspTrackVolumeEnvelopeActive = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    if InspEnvelopeCacheStale(track) then InspBuildEnvCache(track) end
    local details = InspGetAllTrackEnvelopeDetails(track)
    for _, ed in ipairs(details) do
        if (ed.fx_idx == -1 or ed.fx_idx == nil) and ed.name == "Volume" and not ed.bypassed then
            return true
        end
    end
    return false
end

InspScanTrack = function(track)
    InspInvalidateEnvCache()
    if not track or not r.ValidatePtr(track, "MediaTrack*") then
        -- Drop any stale cache entry for this pointer (safe even on
        -- invalidated MediaTrack* — SweepDeadTrackCaches catches missed cases).
        if track then track_fx_cache[track] = nil end
        return
    end
    -- Build bypass envelope set for this track
    local bypass_env_set = {}
    for e = 0, r.CountTrackEnvelopes(track) - 1 do
        local env = r.GetTrackEnvelope(track, e)
        if env then
            local _, ename = r.GetEnvelopeName(env)
            if ename and ename:match("^Bypass") then
                local _, fi = r.Envelope_GetParentTrack(env)
                if fi and fi >= 0 then bypass_env_set[fi] = true end
            end
        end
    end
    -- v20.436 Stage D: build into a local fx_list and store directly in
    -- track_fx_cache. Previously this function maintained a file-scope
    -- `insp_fx` slot as scratch and dual-wrote; with insp_fx removed,
    -- track_fx_cache is the sole storage.
    local fx_list = {}
    for f = 0, r.TrackFX_GetCount(track) - 1 do
        local _, fx_name = r.TrackFX_GetFXName(track, f)
        local display_name = InspStripName(fx_name)
        -- Find Wet parameter index (REAPER wrapper param, not internal plugin params)
        local wet_idx, wet_val = -1, 1.0
        local wp = r.TrackFX_GetParamFromIdent(track, f, ":wet")
        if wp and wp >= 0 then
            wet_idx = wp
            wet_val = r.TrackFX_GetParam(track, f, wp)
        end
        local is_instr = false
        local rv_ft, ft_str = r.TrackFX_GetNamedConfigParm(track, f, "fx_type")
        if rv_ft and ft_str and ft_str:match("i$") then is_instr = true end
        local is_container = false
        local rv_cc, cc_str = r.TrackFX_GetNamedConfigParm(track, f, "container_count")
        if rv_cc and tonumber(cc_str) and tonumber(cc_str) > 0 then is_container = true end
        fx_list[#fx_list + 1] = {
            track = track, fx_idx = f,
            name = display_name,
            category = FXPluginCategory(track, f, fx_name, display_name, is_container, is_instr),
            enabled = r.TrackFX_GetEnabled(track, f),
            offline = r.TrackFX_GetOffline(track, f),
            env_count = InspCountFXEnvelopes(track, f),
            guid = r.TrackFX_GetFXGUID(track, f) or "",
            cmp_key = CmpKey(track, f),
            has_bypass_env = bypass_env_set[f] == true,
            wet_param_idx = wet_idx, wet_value = wet_val,
            is_instrument = is_instr,
            is_container = is_container,
        }
    end
    track_fx_cache[track] = { list = fx_list, count = #fx_list }
end

-- =====================================================================================
-- Per-track FX list API
-- =====================================================================================
-- Canonical reader/invalidator pair for `track_fx_cache`. The takes-a-track-arg
-- rule (v20.406) applies — every getter requires a track explicitly, no implicit
-- "current inspected track" behavior.
--
-- History: introduced v20.432 (Stage A) as a parallel cache, fully wired
-- through Stages B–D. As of v20.436 (Stage D), this is the only way to read
-- FX records — the legacy file-scope `insp_fx` slot was removed.

InspGetFxList = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return {} end
    local fc = track_fx_cache[track]
    local cur_count = r.TrackFX_GetCount(track)
    if not fc or fc.count ~= cur_count then
        InspScanTrack(track)
        fc = track_fx_cache[track]
    end
    return fc and fc.list or {}
end

InspGetFxCount = function(track)
    -- Lightweight: returns live REAPER count without touching the cache.
    -- For "do I have any FX here" checks where records aren't needed.
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return 0 end
    return r.TrackFX_GetCount(track)
end

InspInvalidateTrackFx = function(track)
    -- Drop the cache entry. Next InspGetFxList triggers a fresh scan.
    if track then track_fx_cache[track] = nil end
end

-- Post-action freshness for track FX state.
-- When the action targets insp_track, runs a full rescan eagerly so the
-- next render sees the new records on the same path readers normally take.
-- For other tracks, just invalidates the per-track cache; lazy rescan via
-- InspGetFxList handles count-change freshness on next read.
--
-- History: introduced v20.433 (Stage B) to replace the inline pattern
-- `if insp_fx and track == insp_track then InspScanTrack(track) end`.
-- The same helper also fixes the `surface == "inspector"` row-action gates
-- by routing them through track-identity instead of surface-identity (the
-- self-send staleness pattern, structurally — see PROJECT_KNOWLEDGE.md
-- "Pending Items → Architectural" for the corrected framing).
InspMarkTrackFxDirty = function(track)
    if not track then return end
    if track == insp_track then
        InspScanTrack(track)
    else
        InspInvalidateTrackFx(track)
    end
end

InspGetFxLatencyText = function(track, fx_idx)
    if not r.TrackFX_GetNamedConfigParm or not track or not r.ValidatePtr(track, "MediaTrack*") then
        return nil, false
    end
    local _, pdc_str = r.TrackFX_GetNamedConfigParm(track, fx_idx, "pdc")
    local _, chain_str = r.TrackFX_GetNamedConfigParm(track, fx_idx, "chain_pdc_reporting")
    local pdc = tonumber(pdc_str) or 0
    local chain = tonumber(chain_str) or 0
    local pdc_i = math.floor(pdc + 0.5)
    local chain_i = math.floor(chain + 0.5)
    return tostring(pdc_i) .. "/" .. tostring(chain_i) .. " spls", (pdc_i ~= 0 or chain_i ~= 0)
end

-- Move newly inserted instruments to slot 0
-- Returns true if any FX were moved (caller should rescan)
InspMoveNewInstruments = function(track, old_count)
    if not opt_instr_first or not track then return false end
    local new_count = r.TrackFX_GetCount(track)
    if new_count <= old_count then return false end
    -- Collect instrument indices first (indices shift during moves)
    local instr = {}
    for f = old_count, new_count - 1 do
        local rv, type_str = r.TrackFX_GetNamedConfigParm(track, f, "fx_type")
        if rv and type_str and type_str:match("i$") then
            instr[#instr + 1] = f
        end
    end
    if #instr == 0 then return false end
    -- Move each to slot 0, adjusting for prior moves
    for i, orig_idx in ipairs(instr) do
        local cur_idx = orig_idx + (i - 1)  -- each prior move shifted indices up by 1
        r.TrackFX_CopyToTrack(track, cur_idx, track, 0, true)
    end
    return true
end

-- v20.449: Monitor every track's FX count each frame for instruments-first
-- detection. Skips insp_track because Loop's existing pre-render block
-- handles it (and also fires InspMoveInsertedFX for the inspector's
-- insert-at-position drag feature).
MonitorTrackFxCounts = function()
    local external_target = external_fx_session and external_fx_session.target_track or nil
    local nt = r.CountTracks(0)
    for i = 0, nt - 1 do
        local t = r.GetTrack(0, i)
        if t then
            local cnt = r.TrackFX_GetCount(t)
            local prev = nav_track_fx_counts[t]
            if prev and cnt > prev and opt_instr_first and t ~= insp_track and t ~= external_target then
                if InspMoveNewInstruments(t, prev) then
                    InspMarkTrackFxDirty(t)
                end
            end
            -- Re-read post-move (count unchanged by move, but baseline updated)
            nav_track_fx_counts[t] = r.TrackFX_GetCount(t)
        end
    end
end

-- Move newly inserted FX to a specific target position (from insert-drag)
InspMoveInsertedFX = function(track)
    if not insp_fx_insert_target or not track then return end
    local new_count = r.TrackFX_GetCount(track)
    if new_count <= insp_fx_insert_count then return end
    local num_new = new_count - insp_fx_insert_count
    local dst = insp_fx_insert_target
    -- Move each new FX (appended at end) to target position
    r.Undo_BeginBlock()
    for i = 0, num_new - 1 do
        -- New FX are at end; after each move-to-dst, next one is still at end
        r.TrackFX_CopyToTrack(track, new_count - num_new + i, track, dst + i, true)
    end
    r.Undo_EndBlock("Reflex: Insert FX at position", -1)
    insp_fx_insert_target = nil
    insp_fx_insert_count = 0
    insp_fx_insert_time = 0
end

ExternalFxProviderValid = function(provider)
    return provider == FX_BROWSER_PROVIDER_REFLEX
        or provider == FX_BROWSER_PROVIDER_NVK
        or provider == FX_BROWSER_PROVIDER_REAPER
        or provider == FX_BROWSER_PROVIDER_CUSTOM
end

ExternalFxProviderLabel = function(provider)
    if provider == FX_BROWSER_PROVIDER_NVK then return "nvk_SEARCH" end
    if provider == FX_BROWSER_PROVIDER_REAPER then return "REAPER FX Browser" end
    if provider == FX_BROWSER_PROVIDER_CUSTOM then return "Custom Action" end
    return "Reflex Browser"
end

ExternalFxResolveAction = function(provider)
    if provider == FX_BROWSER_PROVIDER_NVK then
        local id = r.NamedCommandLookup and r.NamedCommandLookup(FX_BROWSER_NVK_COMMAND) or 0
        return id and id > 0 and id or 0
    elseif provider == FX_BROWSER_PROVIDER_REAPER then
        return 40271
    elseif provider == FX_BROWSER_PROVIDER_CUSTOM then
        return tonumber(insp_fx_browser_action) or 0
    end
    return 0
end

ExternalFxProviderAvailable = function(provider)
    if provider == FX_BROWSER_PROVIDER_REFLEX then return true end
    return ExternalFxResolveAction(provider) > 0
end

ExternalFxCaptureSelection = function()
    local selected = {}
    for i = 0, r.CountSelectedTracks(0) - 1 do
        local track = r.GetSelectedTrack(0, i)
        if track and r.ValidatePtr(track, "MediaTrack*") then selected[#selected + 1] = track end
    end
    local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
    if master and r.ValidatePtr(master, "MediaTrack*") and r.IsTrackSelected(master) then
        local has_master = false
        for _, track in ipairs(selected) do
            if track == master then has_master = true; break end
        end
        if not has_master then selected[#selected + 1] = master end
    end
    return selected
end

ExternalFxClearSelection = function()
    if r.Main_OnCommand then r.Main_OnCommand(40297, 0) end
    local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
    if master and r.ValidatePtr(master, "MediaTrack*") then r.SetTrackSelected(master, false) end
end

ExternalFxRestoreSelection = function(selection)
    r.PreventUIRefresh(1)
    ExternalFxClearSelection()
    for _, track in ipairs(selection or {}) do
        if track and r.ValidatePtr(track, "MediaTrack*") then r.SetTrackSelected(track, true) end
    end
    r.PreventUIRefresh(-1)
end

ExternalFxSelectOnlyTrack = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    r.PreventUIRefresh(1)
    ExternalFxClearSelection()
    r.SetTrackSelected(track, true)
    r.PreventUIRefresh(-1)
    return true
end

ExternalFxSelectionIsOnlyTrack = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    local selected = ExternalFxCaptureSelection()
    return #selected == 1 and selected[1] == track
end

ExternalFxFindTrackByGuid = function(guid)
    if not guid or guid == "" then return nil end
    local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
    if master and r.ValidatePtr(master, "MediaTrack*") and r.GetTrackGUID(master) == guid then
        return master
    end
    for i = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, i)
        if track and r.GetTrackGUID(track) == guid then return track end
    end
    return nil
end

ExternalFxLaunchProvider = function(provider)
    local action = ExternalFxResolveAction(provider)
    if action <= 0 then return false end
    if provider == FX_BROWSER_PROVIDER_NVK then
        r.SetExtState("nvk_SEARCH", "FILTER", "fx", false)
    end
    r.Main_OnCommand(action, 0)
    return true
end

ExternalFxProviderWindowOpen = function(provider)
    if provider ~= FX_BROWSER_PROVIDER_NVK or not r.JS_Window_Find then return nil end
    local ok, hwnd = pcall(r.JS_Window_Find, "nvk_SEARCH", false)
    if not ok then return nil end
    return hwnd ~= nil
end

ExternalFxSessionEnd = function(opts)
    if not external_fx_session then return end
    opts = opts or {}
    local session = external_fx_session
    external_fx_session = nil
    local target = session.target_track
    if (not target or not r.ValidatePtr(target, "MediaTrack*")) and session.target_guid then
        target = ExternalFxFindTrackByGuid(session.target_guid)
    end
    if opts.restore and target and ExternalFxSelectionIsOnlyTrack(target) then
        ExternalFxRestoreSelection(session.selection_before)
    end
end

ExternalFxSessionCancel = function()
    ExternalFxSessionEnd({ restore = true })
end

ExternalFxBrowserLaunch = function(track, provider, opts)
    opts = opts or {}
    provider = ExternalFxProviderValid(provider) and provider or fx_browser_provider
    if provider == FX_BROWSER_PROVIDER_REFLEX then return false end
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    if not ExternalFxProviderAvailable(provider) then return false end

    if not opts.preserve_insert then
        insp_fx_insert_target = nil
        insp_fx_insert_count = 0
        insp_fx_insert_time = 0
    end
    ExternalFxSessionCancel()
    local selection_before = ExternalFxCaptureSelection()
    local target_guid = r.GetTrackGUID(track)
    local target_count = r.TrackFX_GetCount(track)
    local insert_target = opts.preserve_insert and insp_fx_insert_target or nil

    if not ExternalFxSelectOnlyTrack(track) then return false end
    external_fx_session = {
        provider = provider,
        target_track = track,
        target_guid = target_guid,
        target_count = target_count,
        insert_target = insert_target,
        selection_before = selection_before,
        start_time = r.time_precise(),
        window_seen = false,
    }

    if not ExternalFxLaunchProvider(provider) then
        ExternalFxSessionEnd({ restore = true })
        return false
    end
    return true
end

ExternalFxSessionHandleAdded = function(session, track, old_count)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    if InspMoveNewInstruments(track, old_count) then
        -- Count is unchanged by moves; cache update happens below.
    end
    if session and session.insert_target ~= nil then InspMoveInsertedFX(track) end
    InspMarkTrackFxDirty(track)
    nav_track_fx_counts[track] = r.TrackFX_GetCount(track)
end

ExternalFxSessionUpdate = function()
    local session = external_fx_session
    if not session then return false end
    local track = session.target_track
    if not track or not r.ValidatePtr(track, "MediaTrack*") then
        track = ExternalFxFindTrackByGuid(session.target_guid)
        session.target_track = track
    end
    if not track then
        external_fx_session = nil
        return false
    end

    local count = r.TrackFX_GetCount(track)
    if count > (session.target_count or 0) then
        ExternalFxSessionHandleAdded(session, track, session.target_count or 0)
        ExternalFxSessionEnd({ restore = true })
        return false
    end

    if not ExternalFxSelectionIsOnlyTrack(track) then
        external_fx_session = nil
        return false
    end

    local provider_window_open = ExternalFxProviderWindowOpen(session.provider)
    if provider_window_open == true then
        session.window_seen = true
    elseif provider_window_open == false and session.window_seen then
        ExternalFxSessionEnd({ restore = true })
        return false
    end

    return true
end

ExternalFxCancelOnReflexInteraction = function()
    if not external_fx_session then return end
    local hover_flags = r.ImGui_HoveredFlags_RootAndChildWindows()
        | r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem()
        | r.ImGui_HoveredFlags_AllowWhenBlockedByPopup()
    if r.ImGui_IsWindowHovered(ctx, hover_flags)
       and (r.ImGui_IsMouseClicked(ctx, 0) or r.ImGui_IsMouseClicked(ctx, 1)) then
        ExternalFxSessionCancel()
    end
end

ProcessFXBrowserActionPrompt = function()
    if not insp_fx_prompt_active then return end
    local result = r.PromptForAction and r.PromptForAction(0, 0, 0) or -1
    if result > 0 then
        insp_fx_browser_action = result
        InspSaveFXBrowserAction(result)
        insp_fx_prompt_active = false
        if r.PromptForAction then r.PromptForAction(-1, 0, 0) end
    elseif result < 0 then
        insp_fx_prompt_active = false
        if fx_browser_provider == FX_BROWSER_PROVIDER_CUSTOM and insp_fx_browser_action <= 0 then
            fx_browser_provider = FX_BROWSER_PROVIDER_REFLEX
            SavePref("fx_browser_provider", fx_browser_provider)
        end
        if r.PromptForAction then r.PromptForAction(-1, 0, 0) end
    end
end

-- Refresh FX enable/offline/wet/env state without full rescan (per-frame poll)
-- Returns true if FX order changed (caller must rescan)
InspRefreshFXState = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    -- v20.434 Stage C: read FX records via track_fx_cache directly. The cache
    -- entry MUST exist by this point (caller has scanned via InspScanTrack or
    -- InspGetFxList). If absent, treat as no-op rather than scanning here —
    -- this function's contract is "refresh existing cached records," not
    -- "populate." Empty-list returns false (no reorder detected).
    local fc = track_fx_cache[track]
    if not fc or not fc.list then return false end
    local fx_list = fc.list
    -- Detect FX reorder: if any GUID changed position, full rescan needed
    for _, fx in ipairs(fx_list) do
        local cur_guid = r.TrackFX_GetFXGUID(fx.track, fx.fx_idx)
        if cur_guid ~= fx.guid then return true end
    end
    local total_env_count = r.CountTrackEnvelopes(track)
    local bset = {}
    local fx_env_ct = {}
    for e = 0, total_env_count - 1 do
        local env = r.GetTrackEnvelope(track, e)
        if env then
            local _, ename = r.GetEnvelopeName(env)
            local _, fi = r.Envelope_GetParentTrack(env)
            if fi and fi >= 0 then
                fx_env_ct[fi] = (fx_env_ct[fi] or 0) + 1
                if ename and ename:match("^Bypass") then bset[fi] = true end
            end
        end
    end
    -- Check if total envelope count changed (catches send/track-level envelope additions)
    local cached_total = insp_env_cache and insp_env_cache.total_env_count or -1
    local env_changed = total_env_count ~= cached_total
    for _, fx in ipairs(fx_list) do
        fx.enabled = r.TrackFX_GetEnabled(fx.track, fx.fx_idx)
        fx.offline = r.TrackFX_GetOffline(fx.track, fx.fx_idx)
        local new_ct = fx_env_ct[fx.fx_idx] or 0
        if new_ct ~= fx.env_count then env_changed = true end
        fx.env_count = new_ct
        fx.has_bypass_env = bset[fx.fx_idx] == true
        if fx.wet_param_idx >= 0 then fx.wet_value = (r.TrackFX_GetParam(fx.track, fx.fx_idx, fx.wet_param_idx)) end
    end
    if env_changed then InspInvalidateEnvCache() end
    return false
end

InspDrawSectionHeader = function(label, expanded, id, opts)
    opts = opts or {}
    -- Slightly larger font for headers
    local hdr_step = GetFontStep(UI.font_title)
    local hdr_font = scaled_fonts[hdr_step]
    if hdr_font then r.ImGui_PushFont(ctx, hdr_font) end
    local bw = r.ImGui_GetContentRegionAvail(ctx)
    local h = r.ImGui_GetTextLineHeight(ctx) + S(6)
    local sx = r.ImGui_GetCursorPosX(ctx)
    local sy = r.ImGui_GetCursorPosY(ctx)
    local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
    -- Invisible selectable for click
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x00000000)
    local clicked = r.ImGui_Selectable(ctx, "##" .. id, false, 0, bw, h)
    local rclicked = r.ImGui_IsItemClicked(ctx, 1)
    local hovered = r.ImGui_IsItemHovered(ctx)
    r.ImGui_PopStyleColor(ctx, 3)
    -- Draw text left, arrow right via DrawList
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    local ty = cy + Round((h - text_h) / 2)
    r.ImGui_DrawList_AddText(dl, cx + S(4), ty, C.section_text, label)
    -- Arrow: draw as a vector icon to avoid Windows emoji fallback.
    local arrow_col = opts.arrow_color or C.section_text
    if opts.arrow_hov_color and hovered then arrow_col = opts.arrow_hov_color end
    local arrow_x = label == "" and (cx + S(4)) or (cx + bw - S(16))
    DrawArrowIcon(dl, arrow_x + S(5), cy + h * 0.5, S(10), expanded and "down" or "right", arrow_col)
    if hdr_font then r.ImGui_PopFont(ctx) end
    return clicked, rclicked, hovered
end

-- InspCtrlButton removed; use NavRect with opts.fg_hov for hover-text behavior.

InspCtrlSz = function() return S(22) end
InspCtrlW = function(text)
    local base = S(22)
    if #text >= 2 then return base + S(6) end
    return base
end

-- =========================================================================
-- COMPARE CORE
-- =========================================================================
package.loaded["Reflex_CompareCore"] = nil
require("Reflex_CompareCore")({
    r = r,
    cmp_ext_section = CMP_EXT_SECTION,
    cmp_key = CmpKey,
    get_insp_track = function() return insp_track end,
    get_fx_list = InspGetFxList,
    get_cmp_check_time = function() return insp_cmp_check_time end,
    set_cmp_check_time = function(v) insp_cmp_check_time = v end,
    set_cmp_has_any = function(v) insp_cmp_has_any = v end,
    set_cmp_count = function(v) insp_cmp_count = v end,
})

-- Meter bar: thin level indicator, returns total height consumed (gap + bar)
InspDrawMeter = function(track, dl, bar_cx, bar_bottom_cy, bar_w, bar_sx, bar_bottom_sy)
    local mh = S(6)
    local mg = S(6)
    local my_screen = bar_bottom_cy + mg
    local my_cursor = bar_bottom_sy + mg
    local mr = mh / 2

    -- Peak level (max L/R)
    local peak_raw = math.max(r.Track_GetPeakInfo(track, 0), r.Track_GetPeakInfo(track, 1))

    -- Auto-reset on transport change
    local ps = r.GetPlayState()
    if ps ~= (insp_meter_last_play or -1) then
        insp_meter_clip = {}; insp_meter_peak = {}; insp_meter_display = {}; insp_meter_noise = {}
    end
    insp_meter_last_play = ps

    -- Smooth decay
    local cur_peak = SmoothPeak(insp_meter_peak, track, peak_raw)

    -- Clip hold
    if peak_raw >= 1.0 then insp_meter_clip[track] = true end

    -- Fill fraction (0dBFS = full, fourth-root scaling)
    local fill = cur_peak > 0.00001 and math.min(1, cur_peak ^ 0.25) or 0

    -- Background (pill with round endcaps)
    r.ImGui_DrawList_AddRectFilled(dl, bar_cx, my_screen, bar_cx + bar_w, my_screen + mh, C.vol_slider_bg, mr)

    -- Fill (clip rect + full pill for masked endcaps)
    if fill > 0 then
        local fr = bar_cx + math.floor(fill * bar_w)
        if fr > bar_cx then
            local db = 20 * math.log(math.max(cur_peak, 0.00001), 10)
            local col
            col = MeterColor(db)
            r.ImGui_DrawList_PushClipRect(dl, bar_cx, my_screen, fr, my_screen + mh, true)
            r.ImGui_DrawList_AddRectFilled(dl, bar_cx, my_screen, bar_cx + bar_w, my_screen + mh, col, mr)
            r.ImGui_DrawList_PopClipRect(dl)
        end
    end

    -- Click anywhere on meter to reset clip
    r.ImGui_SetCursorPos(ctx, bar_sx, my_cursor)
    r.ImGui_InvisibleButton(ctx, "##meter", bar_w, mh)
    if r.ImGui_IsItemClicked(ctx, 0) then insp_meter_clip[track] = false end

    return mg + mh  -- total height consumed
end

InspDrawPhaseIndicator = function(bw)
    local sx = r.ImGui_GetCursorPosX(ctx)
    local sy = r.ImGui_GetCursorPosY(ctx)
    local ctrl_h = InspCtrlSz()
    local row_r = S(4)
    local pill_h = ctrl_h + S(6)
    local btn_gap = S(6)  -- match ctrl_gap (V-to-vol_value spacing)

    if insp_cmp_has_any then
        local _, phase = r.GetProjExtState(0, CMP_EXT_SECTION, "_phase")
        if phase ~= "A" and phase ~= "B" then phase = "" end
        local _, mode_val = r.GetProjExtState(0, CMP_EXT_SECTION, "_mode")
        local is_drywet = mode_val == "drywet"

        local scx, scy = r.ImGui_GetCursorScreenPos(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local text_h = r.ImGui_GetTextLineHeight(ctx)

        -- Mode toggle button (square/circle)
        local mode_w = pill_h
        -- A/B rectangle
        local pill_pad = S(10)
        local letter_gap = S(10)
        local a_tw = r.ImGui_CalcTextSize(ctx, "A")
        local b_tw = r.ImGui_CalcTextSize(ctx, "B")
        local ab_div = S(2)
        local ab_half = pill_h
        local pill_w = ab_half * 2 + ab_div
        -- Float-all button with count
        local count_str = tostring(insp_cmp_count)
        local count_tw = r.ImGui_CalcTextSize(ctx, count_str)
        local circ_r = S(7)  -- match env list UI circle (S(14) diameter)
        local float_pad = S(8)
        local float_inner_gap = S(5)
        local float_w = float_pad * 2 + circ_r * 2 + float_inner_gap + count_tw

        -- Right-align to track header edge (no rpad — match header bg right edge)
        local total_w = pill_w + btn_gap + mode_w + btn_gap + float_w
        local group_x = scx + bw - total_w
        local group_sx = sx + bw - total_w

        -- Detect hover states first (InvisibleButtons consume no visual space)
        r.ImGui_SetCursorPos(ctx, group_sx, sy)
        r.ImGui_InvisibleButton(ctx, "##abphase", pill_w, pill_h)
        local ab_hov = r.ImGui_IsItemHovered(ctx)
        local ab_clicked = r.ImGui_IsItemClicked(ctx, 0)

        r.ImGui_SetCursorPos(ctx, group_sx + pill_w + btn_gap, sy)
        r.ImGui_InvisibleButton(ctx, "##cmpmode", mode_w, pill_h)
        local mode_hov = r.ImGui_IsItemHovered(ctx)
        local mode_clicked = r.ImGui_IsItemClicked(ctx, 0)

        r.ImGui_SetCursorPos(ctx, group_sx + pill_w + btn_gap + mode_w + btn_gap, sy)
        r.ImGui_InvisibleButton(ctx, "##abfloat", float_w, pill_h)
        local float_hov = r.ImGui_IsItemHovered(ctx)
        local float_clicked = r.ImGui_IsItemClicked(ctx, 0)

        -- ── A/B button (leftmost) ──
        local ab_x = group_x
        local a_bg = phase == "A" and C.cmp_a or (ab_hov and C.btn_hover or C.btn_bg)
        local b_bg = phase == "B" and C.cmp_b or (ab_hov and C.btn_hover or C.btn_bg)
        r.ImGui_DrawList_AddRectFilled(dl, ab_x, scy, ab_x + ab_half, scy + pill_h,
            a_bg, row_r, r.ImGui_DrawFlags_RoundCornersLeft())
        r.ImGui_DrawList_AddRectFilled(dl, ab_x + ab_half + ab_div, scy, ab_x + pill_w, scy + pill_h,
            b_bg, row_r, r.ImGui_DrawFlags_RoundCornersRight())
        local ty = scy + Round((pill_h - text_h) / 2)
        local a_txt = phase == "A" and 0xFFFFFFFF or (ab_hov and C.text or C.text_muted)
        local b_txt = phase == "B" and 0xFFFFFFFF or (ab_hov and C.text or C.text_muted)
        r.ImGui_DrawList_AddText(dl, ab_x + Round((ab_half - a_tw) / 2), ty, a_txt, "A")
        r.ImGui_DrawList_AddText(dl, ab_x + ab_half + ab_div + Round((ab_half - b_tw) / 2), ty, b_txt, "B")
        if ab_clicked then
            local mods = r.ImGui_GetKeyMods(ctx)
            if IsAlt(mods) then
                InspCmpClearAll()
                r.SetProjExtState(0, CMP_EXT_SECTION, "_phase", "")
            else
                InspCmpTogglePhase()
            end
        end

        -- ── Mode toggle button (middle) ──
        local mode_x = ab_x + pill_w + btn_gap
        r.ImGui_DrawList_AddRectFilled(dl, mode_x, scy, mode_x + mode_w, scy + pill_h,
            mode_hov and C.btn_hover or C.btn_bg, row_r)
        local icon_cx = mode_x + mode_w / 2
        local icon_cy = scy + pill_h / 2
        local mode_icon_col = mode_hov and C.text or C.text_muted
        if is_drywet then
            r.ImGui_DrawList_AddCircleFilled(dl, icon_cx, icon_cy, S(7), mode_icon_col, 0)
        else
            local sq = S(7)
            r.ImGui_DrawList_AddRectFilled(dl, icon_cx - sq, icon_cy - sq, icon_cx + sq, icon_cy + sq, mode_icon_col, S(2))
        end
        if mode_clicked then InspCmpSwitchMode() end

        -- ── Float-all button (rightmost) ──
        local float_x = mode_x + mode_w + btn_gap
        r.ImGui_DrawList_AddRectFilled(dl, float_x, scy, float_x + float_w, scy + pill_h,
            float_hov and C.btn_hover or C.btn_bg, row_r)
        local circ_cx = float_x + float_pad + circ_r
        local circ_cy_f = scy + pill_h / 2
        local cmp_any_open = InspCmpAnyFloating()
        local circ_col = cmp_any_open and 0xFFFFFFFF or (float_hov and C.text or C.text_muted)
        if cmp_any_open then
            r.ImGui_DrawList_AddCircleFilled(dl, circ_cx, circ_cy_f, circ_r, circ_col, 0)
        else
            r.ImGui_DrawList_AddCircle(dl, circ_cx, circ_cy_f, circ_r, circ_col, 0, S(1))
        end
        local count_x = circ_cx + circ_r + float_inner_gap
        local count_y = scy + Round((pill_h - text_h) / 2)
        r.ImGui_DrawList_AddText(dl, count_x, count_y, float_hov and C.text or C.text_muted, count_str)
        if float_clicked then InspCmpFloatAll() end
    end

    r.ImGui_SetCursorPos(ctx, sx, sy + pill_h + S(2))
end

InspGetTitleFont = function()
    local step = GetFontStep(UI.font_insp_name)
    return scaled_fonts[step]
end

TrackTitleNumberLabels = function(num_str)
    if num_str == nil or num_str == "" then return "", "" end
    local num_label = tostring(num_str or "")
    return num_label, num_label .. ":"
end

ReflexTrackTitleNumberString = function(track, track_num)
    if master_strip_rendering and track_num <= 0 then
        local real_master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
        if real_master and track == real_master then return nil end
    end
    return (track_num <= 0) and "M" or tostring(track_num)
end

PushTrackTitleScaledFont = function(font, size_mult)
    if not font then return false end
    size_mult = size_mult or 1
    local size = scaled_font_sizes and scaled_font_sizes[font]
    if size then
        r.ImGui_PushFont(ctx, font, size * 0.94 * size_mult)
    else
        r.ImGui_PushFont(ctx, font)
    end
    return true
end

PushTrackTitleNameFont = PushTrackTitleScaledFont

InspToggleEnvelope = function(track, env_name)
    -- Volume and Pan: use native REAPER commands for smart activate/deactivate
    -- (transfers fader value to/from envelope, removes if unmodified)
    local native_action = nil
    if env_name == "Volume" then native_action = 40406
    elseif env_name == "Pan" then native_action = 40407 end

    if native_action then
        local cur_sel = r.GetSelectedTrack(0, 0)
        local needs_restore = cur_sel ~= track
        if needs_restore then r.SetOnlyTrackSelected(track) end
        r.Main_OnCommand(native_action, 0)
        if needs_restore and cur_sel and r.ValidatePtr(cur_sel, "MediaTrack*") then
            r.SetOnlyTrackSelected(cur_sel)
        end
        InspInvalidateEnvCache()
        return
    end

    -- Other envelopes: toggle VIS in chunk
    for e = 0, r.CountTrackEnvelopes(track) - 1 do
        local env = r.GetTrackEnvelope(track, e)
        if env then
            local _, n = r.GetEnvelopeName(env)
            if n == env_name then
                local _, chunk = r.GetEnvelopeStateChunk(env, "", false)
                if chunk then
                    local vis = chunk:match("VIS%s+1") ~= nil
                    local v = vis and "0" or "1"
                    chunk = (chunk:gsub("(VIS%s+)%d", "%1" .. v))
                    r.SetEnvelopeStateChunk(env, chunk, false)
                    InspInvalidateEnvCache()
                    r.TrackList_AdjustWindows(false); r.UpdateArrange()
                end
                return
            end
        end
    end
end

InspRoutingPillWidth = function()
    local dot_r = S(5)
    local dot_gap = 4
    local btn_h = S(UI.btn_h)
    local hide_add_send = master_strip_rendering == true
    local route_dot_count = hide_add_send and 2 or 3
    local dots_total_w = dot_r * 2 * route_dot_count + dot_gap * (route_dot_count - 1)
    local plus_area_w = hide_add_send and 0 or btn_h
    local segment_gap = 5.5
    local arrow_dots_gap = segment_gap - 7 * 0.5
    local route_area_w = btn_h + arrow_dots_gap + dots_total_w + segment_gap
    return route_area_w + plus_area_w
end

InspDrawRoutingButton = function(track, sx, sy, override_w)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return S(50) end
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local scx, scy = r.ImGui_GetCursorScreenPos(ctx)

    local has_parent = r.GetMediaTrackInfo_Value(track, "B_MAINSEND") == 1
    local has_sends = r.GetTrackNumSends(track, 0) > 0
    local has_receives = r.GetTrackNumSends(track, -1) > 0

    -- Compound dimensions: [arrow + routing dots][+].
    local dot_r = S(5)
    local dot_gap = 4
    local btn_h = S(UI.btn_h)
    local hide_add_send = master_strip_rendering == true
    local route_dot_count = hide_add_send and 2 or 3
    local dots_total_w = dot_r * 2 * route_dot_count + dot_gap * (route_dot_count - 1)
    local plus_area_w = hide_add_send and 0 or btn_h
    local segment_gap = 5.5
    local arrow_dots_gap = segment_gap - 7 * 0.5
    local default_route_area_w = btn_h + arrow_dots_gap + dots_total_w + segment_gap
    local default_w = default_route_area_w + plus_area_w
    local pill_w = override_w or default_w
    local route_area_w = math.max(default_route_area_w, pill_w - plus_area_w)
    local plus_area_x = sx + route_area_w
    local is_expanded = insp_routing_expanded[track] == true

    -- Routing body: one hit area for hover, tooltip, click, and drag.
    local route_area_x = sx
    r.ImGui_SetCursorPos(ctx, route_area_x, sy)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 0)
    r.ImGui_InvisibleButton(ctx, "##route", route_area_w, btn_h)
    local is_clicked = r.ImGui_IsItemClicked(ctx, 0)
    local is_rclicked = r.ImGui_IsItemClicked(ctx, 1)
    local is_active = r.ImGui_IsItemActive(ctx)
    local is_hovered = r.ImGui_IsItemHovered(ctx)
    if is_hovered then
        local action_text = hide_add_send
            and "Click: toggle routing panel"
            or "Click: toggle routing panel\nOpt: toggle parent/master send"
        ShowRoutingTooltip(track, { action_text = action_text })
    end
    local is_released = r.ImGui_IsItemDeactivated(ctx)
    r.ImGui_PopStyleVar(ctx, 1)
    r.ImGui_PopStyleColor(ctx, 3)

    -- Add-send endcap.
    local plus_clicked = false
    local plus_rclicked = false
    if not hide_add_send then
        r.ImGui_SetCursorPos(ctx, plus_area_x, sy)
        _, plus_clicked = NavRect("##route_add", plus_area_w, btn_h, "+", {
            hov = C.route_send,
            active = (C.route_send & 0xFFFFFF00) | 0xCC,
            rounding = {tl = 0, bl = 0, tr = 3, br = 3},
        })
        plus_rclicked = r.ImGui_IsItemClicked(ctx, 1)
        Tip("Create send to new track\nRight-click for options")
    end

    -- Add-send click handling
    if not hide_add_send then
        if plus_clicked then
            RoutingAddSendTrack(track)
        end
        if plus_rclicked then r.ImGui_OpenPopup(ctx, "##route_addsend_popup"); nav_rclick_consumed = true end
        PushPopupStyle()
        if r.ImGui_BeginPopup(ctx, "##route_addsend_popup") then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), C.fx_ctrl_hover)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
            if r.ImGui_MenuItem(ctx, "Post-Fader (Post-Pan)") then RoutingAddSendTrack(track, 0) end
            if r.ImGui_MenuItem(ctx, "Pre-Fader (Post-FX)") then RoutingAddSendTrack(track, 1) end
            if r.ImGui_MenuItem(ctx, "Pre-Fader (Pre-FX)") then RoutingAddSendTrack(track, 3) end
            if QuickSendMenuItems then QuickSendMenuItems(track) end
            r.ImGui_PopStyleColor(ctx, 2)
            r.ImGui_EndPopup(ctx)
        end
        PopPopupStyle()
    end

    local route_group_hovered = is_hovered
    local route_group_active = is_active
    local route_bg = route_group_active and C.fx_ctrl_active
        or (route_group_hovered and C.fx_ctrl_hover or C.route_bg)
    local arrow_col = is_expanded and C.text or C.text_dim
    if route_group_hovered or route_group_active then arrow_col = C.text end
    local route_round_flags = 0
    if r.ImGui_DrawFlags_RoundCornersLeft then
        route_round_flags = route_round_flags | r.ImGui_DrawFlags_RoundCornersLeft()
    end
    if hide_add_send and r.ImGui_DrawFlags_RoundCornersRight then
        route_round_flags = route_round_flags | r.ImGui_DrawFlags_RoundCornersRight()
    end
    r.ImGui_DrawList_AddRectFilled(dl, scx, scy,
        scx + route_area_w, scy + btn_h, route_bg, S(3),
        route_round_flags)
    NavDrawContent(dl, scx, scy, btn_h, btn_h,
        is_expanded and "\xE2\x96\xBC" or "\xE2\x96\xB6",
        arrow_col, { bg = 0x00000000, arrow_dx = 1.0, arrow_dy = 0.5 })

    -- Route state circles in the middle segment. Master omits the parent-send dot.
    local cy_dot = scy + btn_h / 2
    local cx1 = scx + btn_h + arrow_dots_gap + dot_r
    local cx2 = cx1 + dot_r * 2 + dot_gap
    local cx3 = cx2 + dot_r * 2 + dot_gap
    if hide_add_send then
        r.ImGui_DrawList_AddCircleFilled(dl, cx1, cy_dot, dot_r, has_sends and C.route_send or C.route_dim, 0)
        r.ImGui_DrawList_AddCircleFilled(dl, cx2, cy_dot, dot_r, has_receives and C.route_recv or C.route_dim, 0)
    else
        r.ImGui_DrawList_AddCircleFilled(dl, cx1, cy_dot, dot_r, has_parent and C.route_parent or C.route_dim, 0)
        r.ImGui_DrawList_AddCircleFilled(dl, cx2, cy_dot, dot_r, has_sends and C.route_send or C.route_dim, 0)
        r.ImGui_DrawList_AddCircleFilled(dl, cx3, cy_dot, dot_r, has_receives and C.route_recv or C.route_dim, 0)
    end

    -- Record click position on mouse down
    if is_clicked then
        insp_route_click_x, insp_route_click_y = r.ImGui_GetMousePos(ctx)
        insp_route_dragging = false
        route_drag_source_track = track
    end

    -- Drag detection while held (large threshold)
    if is_active and not insp_route_dragging then
        local mx, my = r.ImGui_GetMousePos(ctx)
        local dist = math.sqrt((mx - insp_route_click_x)^2 + (my - insp_route_click_y)^2)
        if dist > S(12) then
            insp_route_dragging = true
            route_drag_source_track = track
        end
    end

    -- Drag visual: small routing pill follows cursor
    if is_active and insp_route_dragging then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
        r.ImGui_BeginTooltip(ctx)
        local dr = S(3)
        local dg = S(4)
        local dpx = S(6)
        local dpy = S(4)
        local dw = dpx * 2 + dr * 6 + dg * 2
        local dh = dpy * 2 + dr * 2
        r.ImGui_Dummy(ctx, dw, dh)
        local tdl = r.ImGui_GetWindowDrawList(ctx)
        local tx, ty = r.ImGui_GetWindowPos(ctx)
        r.ImGui_DrawList_AddRectFilled(tdl, tx, ty, tx + dw, ty + dh, C.route_bg, S(3))
        r.ImGui_DrawList_AddRect(tdl, tx, ty, tx + dw, ty + dh, 0xFFFFFF40, S(3))
        local dcy = ty + dh / 2
        local dcx1 = tx + dpx + dr
        r.ImGui_DrawList_AddCircleFilled(tdl, dcx1, dcy, dr, C.route_send, 0)
        r.ImGui_DrawList_AddCircleFilled(tdl, dcx1 + dr * 2 + dg, dcy, dr, C.route_send, 0)
        r.ImGui_DrawList_AddCircleFilled(tdl, dcx1 + (dr * 2 + dg) * 2, dcy, dr, C.route_send, 0)
        r.ImGui_EndTooltip(ctx)
        r.ImGui_PopStyleVar(ctx)
    end

    -- Right-clicking the routing body opens the normal track-card menu. The
    -- add-send endcap owns its separate send-mode menu above.
    if is_rclicked then
        r.ImGui_OpenPopup(ctx, "##trknamectx")
        nav_rclick_consumed = true
    end

    -- Release handling
    if is_released then
        if insp_route_dragging then
            insp_route_dragging = false
            RouteDragQueueRelease(track)
        else
            route_drag_source_track = nil
            -- Click (no drag)
            local mods = r.ImGui_GetKeyMods(ctx)
            if IsAlt(mods) then
                if not hide_add_send then
                    -- Opt-click: toggle parent/master send on regular tracks.
                    local cur = r.GetMediaTrackInfo_Value(track, "B_MAINSEND")
                    r.Undo_BeginBlock()
                    r.SetMediaTrackInfo_Value(track, "B_MAINSEND", cur == 1 and 0 or 1)
                    r.Undo_EndBlock("Reflex: Toggle master send", -1)
                end
            else
                -- Normal click: toggle inline routing panel
                if insp_routing_expanded[track] then
                    insp_routing_expanded[track] = nil
                else
                    insp_routing_expanded[track] = true
                end
            end
        end
    end

    return pill_w
end

InspDrawEnvRow = function(ed, display_name, name_col, bw, text_pad, on_eye_click, on_name_click, fx_track, fx_power_row_h)
    local ctrl_sz = InspCtrlSz()
    local env_row_h = ctrl_sz + S(4)
    local env_inner_pad = text_pad - S(4)
    local env_rounding = S(4)
    local env_nudge_y = S(1)
    local has_fx_btn = fx_track and ed.fx_idx and ed.fx_idx >= 0
    local fx_btn_sz = has_fx_btn and (ctrl_sz - S(2)) or 0
    local fx_btn_gap = has_fx_btn and S(6) or 0

    -- Apply alias if set
    local alias = InspGetEnvAlias(ed.name, ed.fx_idx)
    if alias then display_name = alias end

    local sx = r.ImGui_GetCursorPosX(ctx)
    local sy = r.ImGui_GetCursorPosY(ctx)
    local scx, scy = r.ImGui_GetCursorScreenPos(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)

    -- Hit area for click/right-click
    local row_click_w = has_fx_btn and (bw - fx_btn_sz - fx_btn_gap) or bw
    local row_clicked = r.ImGui_InvisibleButton(ctx, "##envrow", row_click_w, env_row_h)
    local row_rclicked = r.ImGui_IsItemClicked(ctx, 1)
    local row_hovered = r.ImGui_IsItemHovered(ctx)
    if row_hovered then
        r.ImGui_DrawList_AddRectFilled(dl, scx, scy, scx + bw, scy + env_row_h, 0xFFFFFF0A, env_rounding)
    end

    -- Font + text height (needed for all text positioning)
    local env_font
    local draw_col = name_col
    if ed.bypassed then
        env_font = GetScaledItalicFont()
        draw_col = (name_col & 0xFFFFFF00) | math.floor(((name_col & 0xFF) * 0.5) + 0.5)
    else
        env_font = GetScaledRegularFont()
    end
    if env_font then r.ImGui_PushFont(ctx, env_font) end
    local text_h = r.ImGui_GetTextLineHeight(ctx)

    -- Env visibility indicator: circle (filled when visible, outline when hidden)
    local icon_sz = S(14)
    local icon_r = icon_sz / 2
    local control_left = env_inner_pad + S(4)
    if fx_power_row_h then
        control_left = math.max(0, fx_power_row_h / 2 - FXPowerCircleDiameter() / 2)
    end
    local icon_cx_env = scx + control_left + icon_r
    local icon_cy_env = scy + math.floor(env_row_h / 2) + env_nudge_y
    local ecol = ed.visible and 0xFFFFFFFF or C.text_muted
    if ed.visible then
        r.ImGui_DrawList_AddCircleFilled(dl, icon_cx_env, icon_cy_env, icon_r, ecol, 0)
    else
        r.ImGui_DrawList_AddCircle(dl, icon_cx_env, icon_cy_env, icon_r, ecol, 0, S(1))
    end

    -- Name text (clipped to available width with buffer before right-side buttons)
    local text_x = scx + control_left + ctrl_sz + S(6)
    local text_y = scy + Round((env_row_h - text_h) / 2) + env_nudge_y
    local right_reserve = (has_fx_btn and (S(14) + S(10)) or 0) + S(8)  -- S(14) button + margins + buffer
    local max_text_w = bw - (text_x - scx) - right_reserve
    local full_tw = r.ImGui_CalcTextSize(ctx, display_name)
    if full_tw <= max_text_w then
        r.ImGui_DrawList_AddText(dl, text_x, text_y, draw_col, display_name)
    else
        -- Clip with ellipsis using clip rect
        local ellipsis = "…"
        local ew = r.ImGui_CalcTextSize(ctx, ellipsis)
        local clip_w = max_text_w - ew
        if clip_w > 0 then
            r.ImGui_DrawList_PushClipRect(dl, text_x, text_y, text_x + clip_w, text_y + text_h + S(2))
            r.ImGui_DrawList_AddText(dl, text_x, text_y, draw_col, display_name)
            r.ImGui_DrawList_PopClipRect(dl)
            r.ImGui_DrawList_AddText(dl, text_x + clip_w, text_y, draw_col, ellipsis)
        end
    end
    if env_font then r.ImGui_PopFont(ctx) end

    -- Fade overlay for bypassed envelopes
    if ed.bypassed then
        local fade = (C.bg & 0xFFFFFF00) | 0x70
        r.ImGui_DrawList_AddRectFilled(dl, scx, scy, scx + bw, scy + env_row_h, fade, env_rounding)
    end

    -- Full row click: toggle visibility + select lane
    if row_clicked then
        r.Undo_BeginBlock()
        on_eye_click()
        r.Undo_EndBlock("Toggle envelope visibility", -1)
        if ed.env and r.ValidatePtr(ed.env, "TrackEnvelope*") then
            r.SetCursorContext(2, ed.env)
        end
    end
    -- Right-click: alias
    if row_rclicked then
        r.ImGui_OpenPopup(ctx, "##envctx")
        nav_rclick_consumed = true
    end
    if r.ImGui_BeginPopup(ctx, "##envctx") then
        if r.ImGui_MenuItem(ctx, "Alias") then
            local cur_alias = alias or display_name
            local retval, new_alias = r.GetUserInputs("Alias Envelope", 1, "Name:,extrawidth=150", cur_alias)
            if retval then InspSetEnvAlias(ed.name, ed.fx_idx, new_alias) end
        end
        if alias then
            if r.ImGui_MenuItem(ctx, "Clear Alias") then
                InspSetEnvAlias(ed.name, ed.fx_idx, "")
            end
        end
        r.ImGui_Separator(ctx)
        if r.ImGui_MenuItem(ctx, "Delete Envelope") then
            if ed.env and r.ValidatePtr(ed.env, "TrackEnvelope*") then
                r.Undo_BeginBlock()
                local _, chunk = r.GetEnvelopeStateChunk(ed.env, "", false)
                if chunk then
                    -- Strip all point lines and hide
                    chunk = (chunk:gsub("PT [^\n]+\n", ""))
                    chunk = (chunk:gsub("(ACT%s+)%d", "%10"))
                    chunk = (chunk:gsub("(VIS%s+)%d%s+%d%s+%d", "%10 0 0"))
                    chunk = (chunk:gsub("(ARM%s+)%d", "%10"))
                    r.SetEnvelopeStateChunk(ed.env, chunk, false)
                    InspInvalidateEnvCache()
                    r.TrackList_AdjustWindows(false); r.UpdateArrange()
                end
                r.Undo_EndBlock("Reflex: Delete envelope", -1)
            end
        end
        r.ImGui_EndPopup(ctx)
    end

    -- FX window toggle button: square (for FX envelopes only)
    if has_fx_btn then
        local fb_sz = S(14)  -- smaller, fits inside endcap
        local fb_margin = Round((env_row_h - fb_sz) / 2)  -- uniform margin top/bottom/right
        local fb_x = sx + bw - fb_sz - fb_margin
        local fb_y = sy + fb_margin
        local fb_cx = scx + bw - fb_sz - fb_margin
        local fb_cy = scy + fb_margin
        local fb_r = S(2)
        r.ImGui_SetCursorPos(ctx, fb_x, fb_y)
        r.ImGui_InvisibleButton(ctx, "##fxtog", fb_sz, fb_sz)
        Tip("Click: bypass\nOpt: toggle all bypass")
        local fb_hov = r.ImGui_IsItemHovered(ctx)
        local hwnd = r.TrackFX_GetFloatingWindow(fx_track, ed.fx_idx)
        local fx_open = hwnd ~= nil
        if fb_hov then
            r.ImGui_DrawList_AddRectFilled(dl, fb_cx - S(2), fb_cy - S(2),
                fb_cx + fb_sz + S(2), fb_cy + fb_sz + S(2), C.fx_ctrl_hover, fb_r + S(1))
        end
        -- Outer square always filled with muted color
        r.ImGui_DrawList_AddRectFilled(dl, fb_cx, fb_cy, fb_cx + fb_sz, fb_cy + fb_sz,
            C.text_muted, fb_r)
        if fx_open then
            -- White inner square 1px smaller on each side
            local inset = S(1)
            r.ImGui_DrawList_AddRectFilled(dl, fb_cx + inset, fb_cy + inset,
                fb_cx + fb_sz - inset, fb_cy + fb_sz - inset, 0xFFFFFFFF, math.max(1, fb_r - 1))
        end
        if r.ImGui_IsItemClicked(ctx, 0) then
            local mods = r.ImGui_GetKeyMods(ctx)
            if IsAlt(mods) then
                -- Opt+click: solo this plugin's UI (close all other FX UIs on track)
                if r.ValidatePtr(fx_track, "MediaTrack*") then
                    for f = 0, r.TrackFX_GetCount(fx_track) - 1 do
                        if f ~= ed.fx_idx then
                            if r.TrackFX_GetFloatingWindow(fx_track, f) then
                                r.TrackFX_Show(fx_track, f, 2)
                            end
                        end
                    end
                    if not fx_open then
                        r.TrackFX_Show(fx_track, ed.fx_idx, 3)
                        InspPositionFXWindow(fx_track, ed.fx_idx)
                    end
                end
            else
                -- Normal click: toggle this plugin's UI
                if hwnd then r.TrackFX_Show(fx_track, ed.fx_idx, 2)
                else r.TrackFX_Show(fx_track, ed.fx_idx, 3); InspPositionFXWindow(fx_track, ed.fx_idx) end
            end
        end
    end

    -- Reset cursor to next row
    r.ImGui_SetCursorPos(ctx, sx, sy + env_row_h + S(3))
end

-- =========================================================================
-- FX ROW CORE
-- =========================================================================
package.loaded["Reflex_FXRowCore"] = nil
require("Reflex_FXRowCore")({
    r = r,
    ctx = ctx,
    colors = C,
    cmp_ext_section = CMP_EXT_SECTION,
    set_cmp_check_time = function(v) insp_cmp_check_time = v end,
    begin_fx_rename = function(track, fi, raw_name)
        insp_rename_type = "fx"
        insp_rename_track = track
        insp_rename_idx = fi
        insp_rename_buf = InspStripName(raw_name)
        insp_rename_focus = false
        insp_rename_frames = 0
    end,
})

InspDrawFXRow = function(fx, fi, bw, ibh, fx_count)
    r.ImGui_PushID(ctx, 5000 + fi)

    local gap = S(3)
    local ctrl_h = InspCtrlSz()
    local rpad = S(6)
    local cat_bar_w = FXCategoryBarWidth()
    local power_hit_w = ibh
    local text_pad = cat_bar_w + FXPowerNamePad(ibh)
    local pad_y = Round((ibh - ctrl_h) / 2)
    local row_r = S(4)
    local row_corners = fx_count and FXRowStackCorners(fi, fx_count) or FXRowDefaultCorners()
    local body_round_flags = FXRowBodyCornerFlags(row_corners, cat_bar_w)

    -- Expansion state (now controls extras: A/B + envelopes)
    local is_exp = insp_env_expanded[fi] ~= nil and insp_env_expanded[fi] ~= false
    local show_env_list = insp_env_expanded[fi] == true
    local extras_h = ibh  -- bottom row height for A/B buttons
    local total_h = is_exp and (ibh + gap + extras_h) or ibh

    -- State colors
    local is_dry = not fx.offline and fx.enabled and fx.wet_value < 0.005
    local bg, hover, active, txt = FxStateColors(fx.is_container, fx.is_instrument, fx.offline, fx.enabled, is_dry, fx.has_bypass_env, fx.wet_value)

    local instr_wet_col = C.fx_drywet_txt
    local instr_env_dim = C.route_dim
    local instr_env_hov = C.text_dim

    local start_x = r.ImGui_GetCursorPosX(ctx)
    local start_y = r.ImGui_GetCursorPosY(ctx)
    local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)

    -- Background (covers full height including extras)
    local row_bg = C.fx_row_bg or bg
    local row_hovered_pre = r.ImGui_IsMouseHoveringRect(ctx, cx, cy, cx + bw, cy + total_h)
    local power_hovered_pre = row_hovered_pre
        or r.ImGui_IsMouseHoveringRect(ctx, cx + cat_bar_w, cy, cx + cat_bar_w + power_hit_w, cy + ibh)
    local cat_col = FXCategoryColor(fx.category, fx.is_container, fx.is_instrument, fx.offline, fx.enabled)
    DrawFXRowBase(dl, cx, cy, bw, power_hit_w, total_h, row_bg,
        FXPowerEndcapBgColor(fx.enabled, power_hovered_pre, row_bg, fx.offline, fx.has_bypass_env == true),
        row_r, cat_col, cat_bar_w, row_corners)
    if C.fx_row_border then
        DrawFXRowRightOutline(dl, cx, cy, bw, total_h, C.fx_row_border, row_r, 1, row_corners)
    end

    -- Top row button positions (right to left): arrow, gap, ENV (if > 0)
    local btn_y = start_y + pad_y
    local ab_w = InspCtrlW("A")
    local env_label = "ENV"
    local env_w = r.ImGui_CalcTextSize(ctx, env_label) + S(12)
    local group_gap = S(8)

    local arrow_x = start_x + bw - rpad - ab_w
    local env_x = fx.env_count > 0 and (arrow_x - gap - env_w) or nil

    -- Click area: left side only, up to the button zone (with buffer)
    local leftmost_btn = env_x or arrow_x
    if not is_exp and fx.wet_value < 0.995 and not fx.offline then
        local wet_w = r.ImGui_CalcTextSize(ctx, "100%") + S(12)
        leftmost_btn = leftmost_btn - group_gap - wet_w
    end
    local click_right_edge = leftmost_btn - group_gap
    local click_w = math.max(S(20), click_right_edge - start_x)

    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x00000000)
    r.ImGui_SetCursorPos(ctx, start_x + cat_bar_w + power_hit_w, start_y)
    local body_click_w = math.max(S(20), click_w - cat_bar_w - power_hit_w)
    local sel = r.ImGui_Selectable(ctx, "##fxsel", false,
        r.ImGui_SelectableFlags_AllowOverlap(), body_click_w, total_h)
    local body_hovered = r.ImGui_IsItemHovered(ctx)
    local hovered = r.ImGui_IsMouseHoveringRect(ctx, cx + cat_bar_w + power_hit_w, cy, cx + bw, cy + total_h)
    local row_hovered_full = row_hovered_pre
    r.ImGui_PopStyleColor(ctx, 3)
    if fx.offline and row_hovered_full then
        ShowOfflineFxStateTooltip(fx.enabled)
    -- v20.424: descriptive hover tooltip on FX row (parity with sends).
    -- "Click: open" omitted — self-explanatory. Suppressed during carry mode
    -- to avoid competing with insert-indicator visuals.
    elseif body_hovered and not FxClipHasContent() then
        Tip("Shift: bypass\nOpt: remove\nCmd+Shift: offline")
    end

    -- Store rect for drag target detection
    insp_fx_rects[fi] = { cy = cy, h = total_h, cx = cx, w = bw }

    -- v20.427: drag begin/activate, hover/active fill + legend, click dispatch,
    -- and right-click open all extracted to FxRowInteract (Phase 3 unification).
    -- Inspector uses 1-based fi for ipairs convention; fx_drag stores 0-based.
    local fi0 = fi - 1
    FxRowInteract({
        track = fx.track, fi = fi0, guid = fx.guid, surface = "inspector",
        popup_id = "##fxctx" .. fi,
        sel = sel, hovered = hovered, item_hovered = body_hovered,
        dl = dl, cx = cx, cy = cy, w = bw, h = total_h, radius = row_r,
        fill_x = cx + cat_bar_w + power_hit_w, fill_w = math.max(1, bw - cat_bar_w - power_hit_w),
        body_round_flags = body_round_flags,
        hover_col = hover, active_col = active,
        enabled = fx.enabled, offline = fx.offline,
        cmp_key = fx.cmp_key,
    })

    DrawFXPowerButton("##fxpower", cx + cat_bar_w, cy, ibh, fx.enabled, {
        track = fx.track, fi = fi0, guid = fx.guid, surface = "inspector",
        enabled = fx.enabled, offline = fx.offline, cmp_key = fx.cmp_key,
    })

    -- A/B assignment group detection (used by expanded A/B controls).
    local grp = ""
    if fx.cmp_key ~= "" then
        local _, val = r.GetProjExtState(0, CMP_EXT_SECTION, fx.cmp_key)
        local parsed_grp = InspCmpParseAssignment(val)
        if parsed_grp then grp = parsed_grp end
    end
    local dot_offset = 0

    -- FX name (vertically centered in top row) — inline rename or normal display
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    local name_y = cy + Round((ibh - text_h) / 2)
    -- v20.430: rename keying changed from 1-based ipairs `fi` to 0-based
    -- `fx.fx_idx` + track binding via `insp_rename_track`. The track gate is
    -- mandatory for sends parity (rename target may be ≠ insp_track).
    if insp_rename_type == "fx" and insp_rename_track == fx.track
       and insp_rename_idx == fx.fx_idx then
        -- Inline rename mode
        insp_rename_frames = insp_rename_frames + 1
        r.ImGui_SetCursorPos(ctx, start_x + text_pad + dot_offset, start_y + Round((ibh - text_h) / 2))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.fx_ctrl_bg)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), S(4), 0)
        r.ImGui_SetNextItemWidth(ctx, click_w - text_pad - dot_offset)
        if not insp_rename_focus then r.ImGui_SetKeyboardFocusHere(ctx); insp_rename_focus = true end
        local changed; changed, insp_rename_buf = r.ImGui_InputText(ctx, "##fxrename", insp_rename_buf,
            r.ImGui_InputTextFlags_EnterReturnsTrue() | r.ImGui_InputTextFlags_AutoSelectAll())
        r.ImGui_PopStyleVar(ctx, 2); r.ImGui_PopStyleColor(ctx, 2)
        if changed then
            if r.TrackFX_SetNamedConfigParm then
                r.TrackFX_SetNamedConfigParm(fx.track, fx.fx_idx, "renamed_name", insp_rename_buf)
            end
            InspScanTrack(fx.track)
            insp_rename_type = nil
        elseif insp_rename_frames > 3 and not r.ImGui_IsItemActive(ctx) then
            insp_rename_type = nil
        end
    else
        -- FX name: always stop before row controls so ENV/arrow never overlap it.
        local name_x = cx + text_pad + dot_offset
        local name_right = cx + click_w
        local name_avail = math.max(0, name_right - name_x)
        local name_col = (not fx.enabled and not fx.offline and hovered) and C.fx_power_off or txt
        local display_name = fx.name
        local name_font_pushed = false
        if fx.offline then
            name_font_pushed = PushFont(GetSteppedFont(UI.font_fx, "italic"))
        end
        local name_tw = r.ImGui_CalcTextSize(ctx, display_name)
        if name_tw > name_avail then
            local ellipsis = "\xE2\x80\xA6"
            local ew = r.ImGui_CalcTextSize(ctx, ellipsis)
            while name_tw + ew > name_avail and #display_name > 0 do
                display_name = Utf8DropLast(display_name)
                name_tw = r.ImGui_CalcTextSize(ctx, display_name)
            end
            if name_avail >= ew then
                display_name = display_name .. ellipsis
                name_tw = r.ImGui_CalcTextSize(ctx, display_name)
            else
                display_name = ""
            end
        end
        r.ImGui_DrawList_AddText(dl, name_x, name_y, name_col, display_name)
        PopFont(name_font_pushed)
    end

    -- Wet percentage button in row 1 (only when collapsed AND wet < 100% and not offline, or during drag)
    local show_wet = not is_exp and ((fx.wet_value < 0.995 and not fx.offline) or
                     (insp_wet_drag_fi == fi and insp_wet_dragging))
    if show_wet then
        local wet_pct = math.floor(fx.wet_value * 100 + 0.5)
        local wet_str = tostring(wet_pct) .. "%"
        local wet_w = r.ImGui_CalcTextSize(ctx, "100%") + S(12)
        local leftmost = env_x or arrow_x
        local wet_x = leftmost - group_gap - wet_w
        r.ImGui_SetCursorPos(ctx, wet_x, btn_y)
        local wet_cx, wet_cy = r.ImGui_GetCursorScreenPos(ctx)
        r.ImGui_InvisibleButton(ctx, "##wet", wet_w, ctrl_h)
        Tip("Drag: wet/dry\nOpt: reset 100%")
        local wet_hov = r.ImGui_IsItemHovered(ctx)
        -- Draw bg on hover only
        if wet_hov or (insp_wet_dragging and insp_wet_drag_fi == fi) then
            r.ImGui_DrawList_AddRectFilled(dl, wet_cx, wet_cy, wet_cx + wet_w, wet_cy + ctrl_h,
                C.fx_ctrl_hover, S(3))
        end
        -- Draw text centered
        local wt_w = r.ImGui_CalcTextSize(ctx, wet_str)
        local wet_txt_col = wet_pct >= 100 and C.text_muted or instr_wet_col
        r.ImGui_DrawList_AddText(dl,
            wet_cx + Round((wet_w - wt_w) / 2),
            wet_cy + Round((ctrl_h - r.ImGui_GetTextLineHeight(ctx)) / 2),
            wet_txt_col, wet_str)
        -- Drag tracking
        if r.ImGui_IsItemClicked(ctx, 0) then
            insp_wet_dragging = true; insp_wet_drag_moved = false; insp_wet_drag_fi = fi
            if fx.wet_param_idx >= 0 then
                insp_wet_before = r.TrackFX_GetParam(fx.track, fx.fx_idx, fx.wet_param_idx)
            end
        end
        if r.ImGui_IsItemActive(ctx) and insp_wet_dragging and insp_wet_drag_fi == fi then
            local dx, dy = r.ImGui_GetMouseDelta(ctx)
            local delta = dx - dy
            if math.abs(delta) > 0 and fx.wet_param_idx >= 0 then
                insp_wet_drag_moved = true
                local new_wet = math.max(0, math.min(1, fx.wet_value + delta * 0.005))
                r.TrackFX_SetParam(fx.track, fx.fx_idx, fx.wet_param_idx, new_wet)
            end
        end
        if r.ImGui_IsItemDeactivated(ctx) and insp_wet_dragging and insp_wet_drag_fi == fi then
            insp_wet_dragging = false; insp_wet_drag_fi = nil
            if insp_wet_drag_moved and insp_wet_before ~= nil and fx.wet_param_idx >= 0 then
                -- Rollback + atomic commit (Option C)
                local wet_final = r.TrackFX_GetParam(fx.track, fx.fx_idx, fx.wet_param_idx)
                r.TrackFX_SetParam(fx.track, fx.fx_idx, fx.wet_param_idx, insp_wet_before)
                r.Undo_BeginBlock()
                r.TrackFX_SetParam(fx.track, fx.fx_idx, fx.wet_param_idx, wet_final)
                r.Undo_EndBlock("Reflex: Wet/Dry change", -1)
            elseif not insp_wet_drag_moved then
                local mods = r.ImGui_GetKeyMods(ctx)
                if IsAlt(mods) and fx.wet_param_idx >= 0 then
                    r.Undo_BeginBlock()
                    r.TrackFX_SetParam(fx.track, fx.fx_idx, fx.wet_param_idx, 1.0)
                    r.Undo_EndBlock("Reflex: Wet/Dry change", -1)
                end
            end
            insp_wet_before = nil
        end
    end

    -- ENV button (if envelopes exist) — InvisibleButton for hover-aware text
    local fx_env_btn_hov = false
    if fx.env_count > 0 then
        r.ImGui_SetCursorPos(ctx, env_x, btn_y)
        local env_cx, env_cy = r.ImGui_GetCursorScreenPos(ctx)
        -- Check if any FX envelopes are visible
        local fx_any_env_vis = false
        if r.ValidatePtr(fx.track, "MediaTrack*") then
            local fx_envs = InspGetFXEnvelopeDetails(fx.track, fx.fx_idx)
            for _, ed in ipairs(fx_envs) do if ed.visible then fx_any_env_vis = true; break end end
        end
        r.ImGui_InvisibleButton(ctx, env_label .. "##env", env_w, ctrl_h)
        Tip("Click: toggle env\nOpt: toggle all envs")
        local env_hov = r.ImGui_IsItemHovered(ctx)
        fx_env_btn_hov = env_hov
        local env_clicked = r.ImGui_IsItemClicked(ctx, 0)
        local bypassed_fx = not fx.enabled and not fx.offline
        local fx_env_txt
        if fx_any_env_vis then
            fx_env_txt = bypassed_fx and (env_hov and C.fx_byp_env_active_hov or C.fx_byp_env_active) or 0xFFFFFFFF
        else
            fx_env_txt = env_hov and instr_env_hov or instr_env_dim
        end
        local etw = r.ImGui_CalcTextSize(ctx, env_label)
        r.ImGui_DrawList_AddText(dl, env_cx + Round((env_w - etw) / 2),
            env_cy + Round((ctrl_h - r.ImGui_GetTextLineHeight(ctx)) / 2), fx_env_txt, env_label)
        if env_clicked then
            if r.ValidatePtr(fx.track, "MediaTrack*") then
                local mods = r.ImGui_GetKeyMods(ctx)
                r.Undo_BeginBlock()
                if IsAlt(mods) then
                    -- Opt+click: solo this plugin's envelopes (hide all others)
                    local all_envs = InspGetAllTrackEnvelopeDetails(fx.track)
                    local my_envs = InspGetFXEnvelopeDetails(fx.track, fx.fx_idx)
                    -- Check if this plugin's envs are already the only visible ones
                    local my_all_vis = true
                    for _, ed in ipairs(my_envs) do if not ed.visible then my_all_vis = false; break end end
                    local others_all_hid = true
                    for _, ed in ipairs(all_envs) do
                        if ed.fx_idx ~= fx.fx_idx and ed.visible then others_all_hid = false; break end
                    end
                    if my_all_vis and others_all_hid then
                        -- Already solo'd: show all envs
                        for _, ed in ipairs(all_envs) do InspSetEnvelopeVisibleRaw(ed.env, true) end
                    else
                        -- Solo: hide all, show only this plugin's
                        for _, ed in ipairs(all_envs) do
                            local show = ed.fx_idx == fx.fx_idx
                            InspSetEnvelopeVisibleRaw(ed.env, show)
                        end
                    end
                else
                    -- Normal click: toggle this plugin's envelopes
                    local envs = InspGetFXEnvelopeDetails(fx.track, fx.fx_idx)
                    local any_vis = false
                    for _, ed in ipairs(envs) do if ed.visible then any_vis = true; break end end
                    for _, ed in ipairs(envs) do InspSetEnvelopeVisibleRaw(ed.env, not any_vis) end
                end
                r.TrackList_AdjustWindows(false); r.UpdateArrange()
                r.Undo_EndBlock("Toggle envelope visibility", -1)
            end
        end
    end

    -- Expand arrow — hidden when collapsed unless row hovered
    r.ImGui_SetCursorPos(ctx, arrow_x, btn_y)
    local arrow_cx, arrow_cy = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_InvisibleButton(ctx, "##ea", ab_w, ctrl_h)
    Tip("Opt: toggle all")
    local arrow_clicked = r.ImGui_IsItemClicked(ctx, 0)
    local arrow_hov = r.ImGui_IsItemHovered(ctx)
    local arrow_active = r.ImGui_IsItemActive(ctx)
    local show_arrow = is_exp or ((hovered or arrow_hov or fx_env_btn_hov) and not FxClipHasContent())
    if show_arrow then
        local arrow_col
        local bypassed_fx = not fx.enabled and not fx.offline
        if is_exp or arrow_active then arrow_col = bypassed_fx and (arrow_hov and C.fx_byp_env_active_hov or C.fx_byp_env_active) or 0xFFFFFFFF
        elseif arrow_hov then arrow_col = instr_env_hov
        else arrow_col = instr_env_dim end
        DrawArrowIcon(dl, arrow_cx + ab_w * 0.5, arrow_cy + ctrl_h * 0.5,
            ctrl_h * 0.52, is_exp and "down" or "right", arrow_col)
    end
    if arrow_clicked then
        local mods = r.ImGui_GetKeyMods(ctx)
        if IsAlt(mods) then
            -- Opt+click: expand/collapse all plugin env lists (not track-level)
            local new_state = not is_exp
            -- v20.434 Stage C: count from track_fx_cache (matches what InspDrawFXArea iterates).
            for ffi = 1, #InspGetFxList(fx.track) do insp_env_expanded[ffi] = new_state end
        else
            insp_env_expanded[fi] = not is_exp
        end
    end

    -- ── Expanded extras row (A/B buttons + wet/dry) ──
    if is_exp then
        local row2_cy = cy + ibh + gap
        local row2_sy = start_y + ibh + gap
        local row2_btn_y = row2_sy + Round((extras_h - ctrl_h) / 2)
        local ab_cmp_w = ctrl_h * 1.10  -- square A/B buttons, 110%
        local ab_cmp_h = ctrl_h * 1.10
        local ab_btn_y = row2_sy + Round((extras_h - ab_cmp_h) / 2)
        local ab_gap = S(6)  -- match ctrl_gap spacing
        local a_x = start_x + text_pad + dot_offset
        local b_x = a_x + ab_cmp_w + ab_gap
        local show_ab = not fx.offline
        local wet_w = r.ImGui_CalcTextSize(ctx, "100%") + S(12)
        local latency_text, latency_has_value = InspGetFxLatencyText(fx.track, fx.fx_idx)
        local latency_gap = S(15)  -- 24 retina px at 100%; separates status from wet control
        local latency_tw = latency_text and r.ImGui_CalcTextSize(ctx, latency_text) or 0
        local show_latency = latency_text ~= nil
        local wet_block_w = fx.offline and 0 or wet_w
        local status_w = wet_block_w
        if show_latency then
            status_w = status_w + (status_w > 0 and latency_gap or 0) + latency_tw
        end
        local ab_right = show_ab and (b_x + ab_cmp_w) or a_x
        local status_right_x = start_x + bw - rpad - S(6)
        local status_x = status_right_x - status_w
        if show_latency and status_x < ab_right + S(8) then
            show_latency = false
            latency_tw = 0
            status_w = wet_block_w
            status_x = status_right_x - status_w
        end
        local muted_status_col = hovered and C.text_dim or C.text_muted

        -- Wet/dry percentage right-aligned in row 2 with latency/status text.
        if not fx.offline then
            local wet_pct = math.floor(fx.wet_value * 100 + 0.5)
            local wet_str = tostring(wet_pct) .. "%"
            r.ImGui_SetCursorPos(ctx, status_x, row2_btn_y)
            local wet_cx, wet_cy = r.ImGui_GetCursorScreenPos(ctx)
            r.ImGui_InvisibleButton(ctx, "##wet2", wet_w, ctrl_h)
            Tip("Drag: wet/dry\nOpt: reset 100%")
            local wet_hov = r.ImGui_IsItemHovered(ctx)
            if wet_hov or (insp_wet_dragging and insp_wet_drag_fi == fi) then
                r.ImGui_DrawList_AddRectFilled(dl, wet_cx, wet_cy, wet_cx + wet_w, wet_cy + ctrl_h,
                    C.fx_ctrl_hover, S(3))
            end
            local wt_w = r.ImGui_CalcTextSize(ctx, wet_str)
            local wet_txt_col = wet_pct >= 100 and muted_status_col or instr_wet_col
            r.ImGui_DrawList_AddText(dl,
                wet_cx + Round((wet_w - wt_w) / 2),
                wet_cy + Round((ctrl_h - r.ImGui_GetTextLineHeight(ctx)) / 2),
                wet_txt_col, wet_str)
            if r.ImGui_IsItemClicked(ctx, 0) then
                insp_wet_dragging = true; insp_wet_drag_moved = false; insp_wet_drag_fi = fi
                if fx.wet_param_idx >= 0 then
                    insp_wet_before = r.TrackFX_GetParam(fx.track, fx.fx_idx, fx.wet_param_idx)
                end
            end
            if r.ImGui_IsItemActive(ctx) and insp_wet_dragging and insp_wet_drag_fi == fi then
                local dx, dy = r.ImGui_GetMouseDelta(ctx)
                local delta = dx - dy
                if math.abs(delta) > 0 and fx.wet_param_idx >= 0 then
                    insp_wet_drag_moved = true
                    local new_wet = math.max(0, math.min(1, fx.wet_value + delta * 0.005))
                    r.TrackFX_SetParam(fx.track, fx.fx_idx, fx.wet_param_idx, new_wet)
                end
            end
            if r.ImGui_IsItemDeactivated(ctx) and insp_wet_dragging and insp_wet_drag_fi == fi then
                insp_wet_dragging = false; insp_wet_drag_fi = nil
                if insp_wet_drag_moved and insp_wet_before ~= nil and fx.wet_param_idx >= 0 then
                    -- Rollback + atomic commit (Option C)
                    local wet_final = r.TrackFX_GetParam(fx.track, fx.fx_idx, fx.wet_param_idx)
                    r.TrackFX_SetParam(fx.track, fx.fx_idx, fx.wet_param_idx, insp_wet_before)
                    r.Undo_BeginBlock()
                    r.TrackFX_SetParam(fx.track, fx.fx_idx, fx.wet_param_idx, wet_final)
                    r.Undo_EndBlock("Reflex: Wet/Dry change", -1)
                elseif not insp_wet_drag_moved then
                    local mods = r.ImGui_GetKeyMods(ctx)
                    if IsAlt(mods) and fx.wet_param_idx >= 0 then
                        r.Undo_BeginBlock()
                        r.TrackFX_SetParam(fx.track, fx.fx_idx, fx.wet_param_idx, 1.0)
                        r.Undo_EndBlock("Reflex: Wet/Dry change", -1)
                    end
                end
                insp_wet_before = nil
            end
        end

        if show_latency then
            local latency_x = status_x + (fx.offline and 0 or (wet_w + latency_gap))
            local latency_col = muted_status_col
            r.ImGui_DrawList_AddText(dl,
                cx + (latency_x - start_x),
                row2_cy + Round((extras_h - r.ImGui_GetTextLineHeight(ctx)) / 2),
                latency_col, latency_text)
        end

        local ab_offline = fx.offline
        local ab_bg, ab_hover_c, ab_active_c, ab_dim_txt
        local ab_set_a_bg, ab_set_a_hov, ab_set_a_act
        local ab_set_b_bg, ab_set_b_hov, ab_set_b_act
        local ab_set_txt
        ab_bg = ab_offline and ((C.fx_ctrl_bg & 0xFFFFFF00) | 0x20) or C.fx_ctrl_bg
        ab_hover_c = ab_offline and ab_bg or C.fx_ctrl_hover
        ab_active_c = ab_offline and ab_bg or C.fx_ctrl_active
        ab_dim_txt = ab_offline and ((C.text_muted & 0xFFFFFF00) | 0x20) or C.text_muted
        ab_set_a_bg = ab_offline and ((C.cmp_a & 0xFFFFFF00) | 0x20) or C.cmp_a
        ab_set_a_hov = ab_offline and ab_bg or (C.cmp_a & 0xFFFFFF00) | 0xCC
        ab_set_a_act = ab_offline and ab_bg or (C.cmp_a & 0xFFFFFF00) | 0xAA
        ab_set_b_bg = ab_offline and ((C.cmp_b & 0xFFFFFF00) | 0x20) or C.cmp_b
        ab_set_b_hov = ab_offline and ab_bg or (C.cmp_b & 0xFFFFFF00) | 0xCC
        ab_set_b_act = ab_offline and ab_bg or (C.cmp_b & 0xFFFFFF00) | 0xAA
        ab_set_txt = ab_offline and ((C.bg & 0xFFFFFF00) | 0x20) or C.bg

        local a_is_set = grp == "A"
        if show_ab then
            r.ImGui_SetCursorPos(ctx, a_x, ab_btn_y)
            local _, a_clk = NavRect("A##cmp", ab_cmp_w, ab_cmp_h, "A", {
                bg     = a_is_set and ab_set_a_bg  or ab_bg,
                hov    = a_is_set and ab_set_a_hov or ab_hover_c,
                active = a_is_set and ab_set_a_act or ab_active_c,
                fg     = a_is_set and ab_set_txt   or ab_dim_txt,
            })
            if a_clk then
                local mods = r.ImGui_GetKeyMods(ctx)
                if IsAlt(mods) then
                    InspCmpClearAll()
                elseif fx.cmp_key ~= "" then
                    if grp == "A" then
                        r.SetProjExtState(0, CMP_EXT_SECTION, fx.cmp_key, "")
                    else
                        r.SetProjExtState(0, CMP_EXT_SECTION, fx.cmp_key,
                            InspCmpBuildAssignment("A", fx.track, fx.fx_idx))
                    end
                    insp_cmp_check_time = 0
                end
            end
        end

        local b_is_set = grp == "B"
        if show_ab then
            r.ImGui_SetCursorPos(ctx, b_x, ab_btn_y)
            local _, b_clk = NavRect("B##cmp", ab_cmp_w, ab_cmp_h, "B", {
                bg     = b_is_set and ab_set_b_bg  or ab_bg,
                hov    = b_is_set and ab_set_b_hov or ab_hover_c,
                active = b_is_set and ab_set_b_act or ab_active_c,
                fg     = b_is_set and ab_set_txt   or ab_dim_txt,
            })
            if b_clk then
                local mods = r.ImGui_GetKeyMods(ctx)
                if IsAlt(mods) then
                    InspCmpClearAll()
                elseif fx.cmp_key ~= "" then
                    if grp == "B" then
                        r.SetProjExtState(0, CMP_EXT_SECTION, fx.cmp_key, "")
                    else
                        r.SetProjExtState(0, CMP_EXT_SECTION, fx.cmp_key,
                            InspCmpBuildAssignment("B", fx.track, fx.fx_idx))
                    end
                    insp_cmp_check_time = 0
                end
            end
        end
    end

    -- Fade overlay for offline/dry (covers full height) — bypassed rows own their colors directly.
    if fx.offline then
        local d = FXPowerCircleDiameter()
        r.ImGui_DrawList_AddCircleFilled(dl, cx + cat_bar_w + ibh / 2, cy + ibh / 2, d / 2, C.fx_power_offline, NAV_CIRCLE_SEGMENTS)
    elseif is_dry then
        local fade = (C.bg & 0xFFFFFF00) | 0x60
        DrawFXRowOverlay(dl, cx, cy, bw, ibh, total_h, cat_bar_w, fade, row_r, row_corners)
    end

    -- v20.422+: outline cascade extracted to FxRowOutlineColor.
    -- See helper for state priority (drag-source / paste-pulse / carry / select).
    local outline_col = FxRowOutlineColor(fx.track, fx.fx_idx, fx.guid, "inspector")
    if outline_col then
        DrawFXRowRightOutline(dl, cx, cy, bw, total_h, outline_col, row_r, SOURCE_STROKE_W, row_corners)
    end

    -- Reset cursor to next row with gap
    r.ImGui_SetCursorPos(ctx, start_x, start_y + total_h + S(3))
    r.ImGui_PopID(ctx)

    -- Envelope detail rows (only when fully expanded and envelopes exist)
    if show_env_list and fx.env_count > 0 and r.ValidatePtr(fx.track, "MediaTrack*") then
        local details = InspGetFXEnvelopeDetails(fx.track, fx.fx_idx)
        table.sort(details, function(a, b)
            local ka = InspEnvSortKey(a.name, fx.fx_idx)
            local kb = InspEnvSortKey(b.name, fx.fx_idx)
            if ka ~= kb then return ka < kb end
            return a.name < b.name
        end)
        for ei, ed in ipairs(details) do
            r.ImGui_PushID(ctx, 6000 + fi * 100 + ei)
            local display_name = InspStripEnvSuffix(ed.name, fx.fx_idx)
            local name_col = InspEnvColor(ed.name, fx.fx_idx)
            InspDrawEnvRow(ed, display_name, name_col, bw, text_pad,
                function()
                    local mods = r.ImGui_GetKeyMods(ctx)
                    if IsAlt(mods) then
                        local all = InspGetFXEnvelopeDetails(fx.track, fx.fx_idx)
                        for _, d in ipairs(all) do InspSetEnvelopeVisibleRaw(d.env, false) end
                        InspSetEnvelopeVisible(ed.env, true)
                    else
                        InspSetEnvelopeVisible(ed.env, not ed.visible)
                    end
                end,
                function()
                    local all_details = InspGetFXEnvelopeDetails(fx.track, fx.fx_idx)
                    if ed.visible then
                        InspSetEnvelopeVisible(ed.env, false)
                    else
                        for _, d in ipairs(all_details) do InspSetEnvelopeVisibleRaw(d.env, false) end
                        InspSetEnvelopeVisible(ed.env, true)
                    end
                end, fx.track, ibh)
            r.ImGui_PopID(ctx)
        end
        r.ImGui_Spacing(ctx)
        r.ImGui_Spacing(ctx)
    end
end

-- =========================================================================
-- SHARED COMPACT UI UTILITIES
-- =========================================================================
-- Reusable across sends view, compact flow, mixer view, etc.

-- Clean FX name for compact display: strip type prefix + vendor parenthetical
CleanFXDisplayName = function(raw)
    if not raw or raw == "" then return "" end
    local cleaned = raw:match("^[^:]+:%s*(.+)$") or raw
    cleaned = cleaned:match("^(.-)%s*%(.-%)%s*$") or cleaned
    cleaned = cleaned:match("^(.-)%s*%[.-%]%s*$") or cleaned
    return cleaned
end

-- Draw a compact button via InvisibleButton + DrawList. Returns clicked, hovered.
-- Draws bg rect + centered text. Caller must set cursor to (x, y) via SetCursorScreenPos before calling.
DrawCompactButton = function(id, dl, x, y, w, h, label, bg_col, txt_col, corner_r)
    r.ImGui_SetCursorScreenPos(ctx, x, y)
    r.ImGui_InvisibleButton(ctx, id, w, h)
    local hov = r.ImGui_IsItemHovered(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local cr = corner_r or S(3)
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg_col, cr)
    if hov then
        r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0xFFFFFF1A, cr)
    end
    local tw = r.ImGui_CalcTextSize(ctx, label)
    local th_l = r.ImGui_GetTextLineHeight(ctx)
    r.ImGui_DrawList_AddText(dl, x + Round((w - tw) / 2), y + Round((h - th_l) / 2), txt_col, label)
    return clicked, hov
end

-- Draw a compact meter bar (pill-rounded, fourth-root scaling, smoothed decay).
-- Uses shared insp_meter_peak for smoothing. Does NOT handle transport reset or clip hold
-- (those are handled by the main loop via InspDrawMeter for the primary track).
DrawMeterBarCompact = function(track, dl, x, y, w, h)
    local mr = h / 2
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.vol_slider_bg, mr)
    local peak_raw = math.max(r.Track_GetPeakInfo(track, 0), r.Track_GetPeakInfo(track, 1))
    -- Pure decay (matches InspDrawMeter): no blending on decay
    local cur_peak = SmoothPeak(insp_meter_peak, track, peak_raw)
    -- Clip hold
    if peak_raw >= 1.0 then insp_meter_clip[track] = true end
    local fill = cur_peak > 0.00001 and math.min(1, cur_peak ^ 0.25) or 0
    if fill > 0 then
        local fr = x + math.floor(fill * w)
        if fr > x then
            local db = 20 * math.log(math.max(cur_peak, 0.00001), 10)
            local col
            col = MeterColor(db)
            r.ImGui_DrawList_PushClipRect(dl, x, y, fr, y + h, true)
            r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, col, mr)
            r.ImGui_DrawList_PopClipRect(dl)
        end
    end
end

-- Draw a nav circle button (flow, sends, routing on nav bar).
-- Guarantees identical size and vertical alignment for all callers.
-- Returns: clicked, center_x, center_y, radius, hovered.
-- Caller draws content (text label or triangle) at returned center.
DrawNavCircleButton = function(id, is_active, tooltip_on, tooltip_off)
    local rv = S(UI.circ_btn_r)
    local d = rv * 2
    r.ImGui_InvisibleButton(ctx, id, d, d)
    local hov = r.ImGui_IsItemHovered(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local ix, iy = r.ImGui_GetItemRectMin(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local bcx = ix + rv
    local bcy = iy + rv
    local bg = is_active and C.cmp_b or (hov and C.btn_hover or C.btn_bg)
    r.ImGui_DrawList_AddCircleFilled(dl, bcx, bcy, rv, bg, NAV_CIRCLE_SEGMENTS)
    if hov and tooltip_on then
        Tip(is_active and tooltip_on or (tooltip_off or tooltip_on))
    end
    return clicked, bcx, bcy, rv, hov
end

-- Draw bold text label centered in a nav circle button.
-- Call after DrawNavCircleButton with the returned cx, cy.
DrawNavCircleLabel = function(cx, cy, label, is_active)
    local step = GetFontStep(UI.font_title)
    local font = scaled_fonts[step]
    if font then r.ImGui_PushFont(ctx, font) end
    local tw = r.ImGui_CalcTextSize(ctx, label)
    local th = r.ImGui_GetTextLineHeight(ctx)
    local txt = is_active and 0xFFFFFFFF or C.text_muted
    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddText(dl, cx - tw / 2, cy - th / 2, txt, label)
    if font then r.ImGui_PopFont(ctx) end
end

InspFormatVol = function(vol)
    if vol < 0.00001 then return "-inf" end
    local db = 20 * math.log(vol, 10)
    if db > -0.05 and db < 0.05 then return "0.0" end
    return string.format("%.1f", db)
end

InspFormatPan = function(pan)
    if math.abs(pan) < 0.005 then return "C" end
    local pct = math.floor(math.abs(pan) * 100 + 0.5)
    return tostring(pct) .. (pan < 0 and "L" or "R")
end

-- =========================================================================
-- INSPECTOR HEADER (extracted sub-function)
-- =========================================================================
-- Draws: track header (title, record/mon/M/S/pan/ENV buttons, record input, wrapping),
--        track envelope detail rows.
-- Sets cursor to just past the header for the next section (volume bar).
-- Returns table of values needed by downstream sections.
InspDrawHeader = function(track, bw, is_flow)
    local hdr = {}
    local gap = S(UI.pad_sm)
    local ctrl_h = InspCtrlSz()
    -- HDR L/R padding zeroed: content aligns to outer box edges, matching VOL/CTRL/FX below
    local rpad = 0
    local text_pad = 0

    -- Build envelope cache once per frame (or rebuild if REAPER-side state changed).
    if InspEnvelopeCacheStale(track) then
        InspBuildEnvCache(track)
    end

    local _, track_name = r.GetTrackName(track)
    hdr.track_name = track_name
    hdr.is_muted = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
    local is_solo = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0
    local track_num = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
    hdr.show_record = track_num > 0 and not master_strip_rendering
    hdr.record_armed = hdr.show_record and r.GetMediaTrackInfo_Value(track, "I_RECARM") == 1

    -- Track header (rounded bg, two/three rows plus armed-only input row)
    hdr.trk_sx = r.ImGui_GetCursorPosX(ctx)
    hdr.trk_sy = r.ImGui_GetCursorPosY(ctx)
    hdr.trk_cx, hdr.trk_cy = r.ImGui_GetCursorScreenPos(ctx)

    -- Measure heights
    local title_font = InspGetTitleFont()
    local tfp = false
    if title_font then r.ImGui_PushFont(ctx, title_font); tfp = true end
    local title_h = r.ImGui_GetTextLineHeight(ctx)
    if tfp then r.ImGui_PopFont(ctx) end

    local trk_pad_top = opt_card_boxes and 0 or S(UI.pad)
    local trk_row_gap = S(UI.hdr_row_gap)
    local trk_pad_bot = S(UI.pad)
    local row2_btn_h = S(UI.btn_h)
    local pan_knob_d = S(64 / 1.44)
    local vol_value_w = row2_btn_h * 2 + S(UI.pad_sm)
    local row2_h = math.max(row2_btn_h, pan_knob_d)
    local input_row_h = hdr.record_armed and RecordInputRowHeight() or 0
    local input_row_gap = hdr.record_armed and RecordInputRowGap() or 0
    local input_meter_h = hdr.record_armed and RecordInputMeterHeight() or 0

    -- Pre-compute button widths for wrapping check
    local ms_w = row2_btn_h
    local ms_gap = S(UI.pad_sm)
    local group_gap = S(UI.group_gap)
    hdr.fx_btn_w = math.floor(InspCtrlW("FX") * 1.4)  -- used by controls row
    local pan_val_w = math.max(row2_btn_h, r.ImGui_CalcTextSize(ctx, "100R") + S(16))
    local pan_group_w = pan_val_w + ms_gap + pan_knob_d
    hdr.pan_val_w = pan_val_w
    hdr.pan_knob_d = pan_knob_d
    hdr.pan_group_w = pan_group_w
    hdr.record_mon_w = hdr.record_armed and RecordMonitorButtonWidth(row2_btn_h) or 0
    local rec_total = 0
    if hdr.show_record then
        rec_total = ms_w + ms_gap
        if hdr.record_armed then rec_total = rec_total + hdr.record_mon_w + ms_gap * 2 end
    end
    local solo_right = text_pad + rec_total + ms_w + ms_gap + ms_w

    hdr.route_pill_w = InspRoutingPillWidth()
    local vol_row_wraps = InspVolumeShouldWrap(bw, row2_btn_h)
    local vol_value_x = solo_right + group_gap
    local fader_to_buttons_gap = ms_gap * 2
    local vol_pm_w = row2_btn_h + ms_gap + row2_btn_h
    local fader_right_x = bw - vol_pm_w - fader_to_buttons_gap
    local pan_knob_x = bw - pan_knob_d + 5
    local pan_value_x = pan_knob_x - ms_gap * 2 - pan_val_w
    local left_end = vol_value_x + vol_value_w
    local pan_value_wraps = false
    hdr.vol_row_wraps = vol_row_wraps
    hdr.pan_value_wraps = pan_value_wraps
    hdr.vol_fader_right_x = fader_right_x
    hdr.pan_value_x = pan_value_x
    hdr.pan_knob_x = pan_knob_x
    hdr.vol_value_x = vol_value_x
    hdr.vol_value_w = vol_value_w
    local record_input_fader_gap_extra = hdr.record_armed and Round((row2_h - row2_btn_h) / 2) or 0
    local record_input_extra_h = hdr.record_armed and (input_row_gap + input_meter_h + input_row_gap + input_row_h + record_input_fader_gap_extra) or 0
    hdr.trk_row_h = trk_pad_top + title_h + trk_row_gap + row2_h
        + (pan_value_wraps and (gap + row2_btn_h) or 0)
        + record_input_extra_h + trk_pad_bot

    -- Draw rounded background
    hdr.dl = r.ImGui_GetWindowDrawList(ctx)
    local dl = hdr.dl
    hdr.bw = bw
    hdr.track_color_raw = r.GetTrackColor(track)
    local hdr_bg = is_flow and 0x00000000 or C.bg
    r.ImGui_DrawList_AddRectFilled(dl, hdr.trk_cx, hdr.trk_cy, hdr.trk_cx + bw, hdr.trk_cy + hdr.trk_row_h, hdr_bg, S(UI.corner_r))

    -- Row 1: Track number + name (full-width click area)
    local title_y = hdr.trk_sy + trk_pad_top
    local num_str = ReflexTrackTitleNumberString(track, track_num)
    hdr.is_flow_secondary = is_flow and track ~= insp_track

    -- Pin circle: only on focus track (flow) or single inspector card (normal)
    local show_pin = false
    if master_strip_rendering then
        show_pin = false
    elseif flow_view_active then
        show_pin = is_flow and (track == flow_view_anchor)
    elseif not is_flow then
        show_pin = (track == insp_track)
    end
    local pin_d = 21 * 0.5
    local pin_hit = 20
    local pin_area = show_pin and (pin_hit + S(2)) or 0

    r.ImGui_SetCursorPos(ctx, hdr.trk_sx + text_pad, title_y)
    tfp = PushTrackTitleScaledFont(title_font)

    local num_col = hdr.track_color_raw ~= 0 and TrackColorToImGui(hdr.track_color_raw) or C.text_muted
    local num_label, num_slot_label = TrackTitleNumberLabels(num_str)
    local num_tw = r.ImGui_CalcTextSize(ctx, num_slot_label)
    local num_name_gap = (num_tw > 0) and S(4) or 0
    local title_text_h = r.ImGui_GetTextLineHeight(ctx)
    local title_text_offset_y = Round((title_h - title_text_h) / 2)

    if insp_rename_type == "track" then
        -- Inline track rename (unchanged)
        local name_cx, name_cy = r.ImGui_GetCursorScreenPos(ctx)
        r.ImGui_DrawList_AddText(dl, name_cx, name_cy + title_text_offset_y, num_col, num_label)
        r.ImGui_SetCursorPosX(ctx, hdr.trk_sx + text_pad + num_tw + num_name_gap)
        local name_avail = hdr.trk_cx + bw - rpad - S(8) - (hdr.trk_cx + text_pad + num_tw + num_name_gap)
        insp_rename_frames = insp_rename_frames + 1
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.fx_ctrl_bg)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), S(4), 0)
        r.ImGui_SetNextItemWidth(ctx, name_avail)
        if not insp_rename_focus then r.ImGui_SetKeyboardFocusHere(ctx); insp_rename_focus = true end
        local changed; changed, insp_rename_buf = r.ImGui_InputText(ctx, "##trkrename", insp_rename_buf,
            r.ImGui_InputTextFlags_EnterReturnsTrue() | r.ImGui_InputTextFlags_AutoSelectAll())
        r.ImGui_PopStyleVar(ctx, 2); r.ImGui_PopStyleColor(ctx, 2)
        if changed then
            r.Undo_BeginBlock()
            r.GetSetMediaTrackInfo_String(track, "P_NAME", insp_rename_buf, true)
            r.Undo_EndBlock("Reflex: Rename track", -1)
            insp_rename_type = nil
        elseif insp_rename_frames > 3 and not r.ImGui_IsItemActive(ctx) then
            insp_rename_type = nil
        end
    else
        -- Full-width header click area (from top of header bg to M/S row)
        local hdr_click_h = trk_pad_top + title_h + trk_row_gap
        local title_btn_w = bw - pin_area
        r.ImGui_SetCursorPos(ctx, hdr.trk_sx, hdr.trk_sy)
        r.ImGui_InvisibleButton(ctx, "##hdrtitle", title_btn_w, hdr_click_h)
        local hdr_clicked = r.ImGui_IsItemClicked(ctx, 0)
        local hdr_dbl = hdr_clicked and r.ImGui_IsMouseDoubleClicked(ctx, 0)
        local hdr_rclicked = r.ImGui_IsItemClicked(ctx, 1)

        -- v20.440: title-link dispatch happens AFTER text draw + TitleLink
        -- registration below, so the locate gesture can claim the title-text
        -- region before hdrtitle's broader handlers fire on the same click.

        -- Draw track number + name text
        local num_cx, num_cy = hdr.trk_cx + text_pad, hdr.trk_cy + trk_pad_top
        local title_text_y = num_cy + title_text_offset_y
        r.ImGui_DrawList_AddText(dl, num_cx, title_text_y, num_col, num_label)

        local name_x = num_cx + num_tw + num_name_gap
        local name_avail = hdr.trk_cx + bw - rpad - pin_area - S(4) - name_x
        local display_name = track_name
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
        local name_col = C.text
        r.ImGui_DrawList_AddText(dl, name_x, title_text_y, name_col, display_name)

        -- v20.440: TitleLink — number + name as a single locate-link.
        -- Register AFTER text draw so it sits on top of hdrtitle for hit-test.
        local link_w = (name_x + name_tw) - num_cx
        local link_dbl_handler = nil
            if master_strip_rendering then
                -- Master strip owns its own expansion state and should not
                -- browse/select or mutate Flow View when clicked.
                link_dbl_handler = function()
                    master_track_expanded = false
                end
            elseif is_flow then
            -- Flow view: double-click sets focus (preserves current behavior).
            link_dbl_handler = function()
                ViewHistoryPush()
                FlowViewSetFocus(track)
                ViewHistoryPush()
            end
        elseif track ~= insp_track and insp_pinned then
            -- Non-flow secondary card: double-click unpins and re-anchors.
            link_dbl_handler = function()
                ViewHistoryPush()
                insp_pinned = false
                insp_track = track
                InspScanTrack(insp_track)
                insp_env_expanded = {}
                insp_vol_editing = false; insp_pan_editing = false
                insp_rename_type = nil
                insp_pin_sel_env = {}
                ViewHistoryPush()
            end
        end
        local title_hovered, title_clicked = TitleLink(
            "##hdrnamelink", num_cx, title_text_y, link_w, title_text_h, track,
            { dbl_handler = link_dbl_handler })
        if master_strip_rendering and title_clicked then
            master_track_expanded = false
        end

        -- Underline on hover (web-link affordance)
        if title_hovered then
            DrawSolidUnderline(dl, name_x, title_text_y + title_text_h, name_x + name_tw, C.text, 1)
        end

        -- v20.440: hdrtitle dispatch — gated on `not title_clicked` so the
        -- TitleLink locate gesture doesn't double-fire with the broader
        -- hdrtitle handlers when the click landed on the title-text region.
        if not title_clicked then
            if master_strip_rendering then
                if hdr_clicked then
                    master_track_expanded = false
                end
            elseif is_flow then
                if hdr_dbl then
                    -- Double-click in flow: make this the focus track, unpin, rebuild.
                    -- v20.429: pre/post push so Back/Forward restore the previous flow
                    -- chain context (anchor + chain), not just the unpin state.
                    ViewHistoryPush()
                    FlowViewSetFocus(track)
                    ViewHistoryPush()
                elseif hdr_clicked then
                    local is_flow_focus = flow_view_active and flow_view_anchor == track
                    -- v20.503: distinguish the true flow focus/source from a
                    -- selected expanded non-focus card. "Not secondary" used
                    -- to mean both, which made selected non-focus cards and the
                    -- source card clear every other expansion on click.
                    if is_flow_focus and track == insp_track then
                        -- Source/focus card is always expanded; clicking it
                        -- again after selection has no collapse side effect.
                    elseif track == insp_track then
                        -- Selected expanded non-focus card: collapse only this
                        -- card, leaving other flow expansions untouched.
                        flow_view_expanded_set[track] = nil
                    else
                        r.Undo_BeginBlock()
                        r.SetOnlyTrackSelected(track)
                        r.Undo_EndBlock("Reflex: Browse track", 0)
                        flow_view_browsing = true
                    end
                end
            elseif hdr_dbl and track ~= insp_track and insp_pinned then
                -- Double-click secondary card title: unpin and make this the source.
                -- v20.426: capture the live "pinned + secondary" state before
                -- mutating. TCP-selection-driven changes during pinned mode don't
                -- push (per Pinned TCP Sync rule), so this is the first chance to
                -- record the secondary-selected state. Without this pre-push, Back
                -- skips the intermediate state and lands on bare-pinned.
                ViewHistoryPush()
                insp_pinned = false
                insp_track = track
                InspScanTrack(insp_track)
                insp_env_expanded = {}
                insp_vol_editing = false; insp_pan_editing = false
                insp_rename_type = nil
                insp_pin_sel_env = {}
                ViewHistoryPush()
            elseif hdr_dbl and r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") == 0 then
                -- Double-click card of hidden track: reveal in TCP with parents
                InspRevealTrack(track)
            end
        end

        -- Right-click title/header area. Broad blank-card capture is handled at
        -- the end of InspDrawTrackBlock after all card controls are registered.
        if hdr_rclicked then
            r.ImGui_OpenPopup(ctx, "##trknamectx")
            nav_rclick_consumed = true
        end

        -- Pin circle (upper right corner)
        if show_pin then
            local pin_r = pin_d / 2
            local pin_edge_gap = 20 * 0.5
            local pin_offset = pin_edge_gap + pin_r
            local pin_cx, pin_cy
            if opt_card_boxes then
                pin_cx = hdr.trk_cx + bw + S(UI.card_pad) - pin_offset
                pin_cy = hdr.trk_cy - S(UI.card_pad_top) + pin_offset
            else
                pin_cx = hdr.trk_cx + bw - pin_offset
                pin_cy = hdr.trk_cy + pin_offset
            end
            -- Hit area
            r.ImGui_SetCursorScreenPos(ctx, pin_cx - pin_hit / 2, pin_cy - pin_hit / 2)
            r.ImGui_InvisibleButton(ctx, "##pin", pin_hit, pin_hit)
            if r.ImGui_IsItemClicked(ctx, 0) then
                insp_pinned = not insp_pinned
                if not insp_pinned and insp_track and r.ValidatePtr(insp_track, "MediaTrack*") then
                    -- Reselect pinned track in TCP so main loop doesn't switch away
                    r.Undo_BeginBlock()
                    r.SetOnlyTrackSelected(insp_track)
                    -- Reveal in TCP if hidden (show parents, expand, scroll)
                    if r.GetMediaTrackInfo_Value(insp_track, "B_SHOWINTCP") == 0 then
                        InspRevealTrack(insp_track)
                    end
                    r.Undo_EndBlock("Reflex: Unpin", 0)
                end
                insp_pin_suppress_selected = false
                -- Initialize selection tracking to current selection
                local pin_sel = r.CountSelectedTracks(0) > 0 and r.GetSelectedTrack(0, 0) or nil
                insp_pin_last_sel_guid = pin_sel and r.ValidatePtr(pin_sel, "MediaTrack*") and r.GetTrackGUID(pin_sel) or nil
                insp_pin_sel_env = {}
                if ReflexSaveInspectorProjectState and nav_project_key then ReflexSaveInspectorProjectState(nav_project_key) end
                ViewHistoryPush()
            end
            local pin_hov = r.ImGui_IsItemHovered(ctx)
            if pin_hov then
                r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
            end
            -- Push scaled body font so tooltip matches other tooltips (title font still on stack here).
            local pin_tip_font = GetScaledFont()
            if pin_tip_font then r.ImGui_PushFont(ctx, pin_tip_font) end
            Tip(insp_pinned and "Unpin" or "Pin")
            if pin_tip_font then r.ImGui_PopFont(ctx) end
            DrawTrackPinIndicator(dl, pin_cx, pin_cy, pin_hov, insp_pinned)
            -- Capture pin geometry so the mute fade overlay can redraw it on top.
            -- Pin state is independent of mute state, so the indicator must not fade.
            hdr.pin_drawn = true
            hdr.pin_cx, hdr.pin_cy, hdr.pin_r = pin_cx, pin_cy, pin_r
            hdr.pin_hov = pin_hov
        end

        -- Advance cursor past title row
        r.ImGui_SetCursorPos(ctx, hdr.trk_sx, title_y + title_h)
    end
    if tfp then r.ImGui_PopFont(ctx) end

    -- Row 2: record/mon/M/S (left) + FX + routing + env controls (right, or row 3 if wrapped)
    local row2_y = title_y + title_h + trk_row_gap
    local row_btn_offset_y = Round((row2_h - row2_btn_h) / 2)
    local row2_btn_y = row2_y + row_btn_offset_y
    local row2_knob_y = row2_y + Round((row2_h - (hdr.pan_knob_d or row2_btn_h)) / 2)
    local pan_value_wraps = hdr.pan_value_wraps == true
    local pan_value_row_y = row2_btn_y
    hdr.vol_value_sx = hdr.trk_cx + (hdr.vol_value_x or (bw - row2_btn_h * 2 - gap))
    hdr.vol_value_sy = hdr.trk_cy + (row2_btn_y - hdr.trk_sy)
    hdr.vol_value_w = hdr.vol_value_w or (row2_btn_h * 2 + gap)
    hdr.vol_value_h = row2_btn_h
    local right_row_block_y = row2_y
    local right_row_h = row2_h

    local left_x = hdr.trk_sx + text_pad

    -- Record-arm button
    if hdr.show_record then
        r.ImGui_SetCursorPos(ctx, left_x, row2_btn_y)
        local rec_hov, rec_clk, rec_act = RecordArmButton("##recarm", row2_btn_h, hdr.record_armed)
        if rec_clk then
            RecordArmClick(track, hdr.record_armed)
        end
        hdr.record_drawn = true
        hdr.record_hov = rec_hov
        hdr.record_active = rec_act
        hdr.record_rect = { r.ImGui_GetItemRectMin(ctx) }
        hdr.record_rect[3], hdr.record_rect[4] = r.ImGui_GetItemRectMax(ctx)
        left_x = left_x + ms_w + ms_gap

        if hdr.record_armed then
            local is_mon_on = r.GetMediaTrackInfo_Value(track, "I_RECMON") > 0
            r.ImGui_SetCursorPos(ctx, left_x, row2_btn_y)
            local mon_hov, mon_clk, mon_act, mon_rclick =
                RecordMonitorButton("##recmon", hdr.record_mon_w, row2_btn_h, is_mon_on)
            local mon_rect = { r.ImGui_GetItemRectMin(ctx) }
            mon_rect[3], mon_rect[4] = r.ImGui_GetItemRectMax(ctx)
            if mon_clk then RecordMonitorToggle(track) end
            if mon_rclick then
                r.ImGui_OpenPopup(ctx, "##recmon_ctx")
                nav_rclick_consumed = true
            end
            RecordMonitorMenu(track, "##recmon_ctx")
            hdr.record_mon_drawn = true
            hdr.record_mon_on = is_mon_on
            hdr.record_mon_hov = mon_hov
            hdr.record_mon_active = mon_act
            hdr.record_mon_rect = mon_rect
            left_x = left_x + hdr.record_mon_w + ms_gap * 2
        end
    end

    -- Mute button
    local m_opts = MuteOpts(hdr.is_muted)
    r.ImGui_SetCursorPos(ctx, left_x, row2_btn_y)
    local _, m_clk = NavRect("M##mute", ms_w, row2_btn_h, "M", m_opts)
    if m_clk then
        r.Undo_BeginBlock()
        r.SetMediaTrackInfo_Value(track, "B_MUTE", hdr.is_muted and 0 or 1)
        r.Undo_EndBlock("Reflex: Mute", -1)
    end
    -- Save mute button rect for overlay exclusion
    hdr.mute_rect = { r.ImGui_GetItemRectMin(ctx) }
    hdr.mute_rect[3], hdr.mute_rect[4] = r.ImGui_GetItemRectMax(ctx)
    hdr.mute_colors = m_opts

    -- Solo button
    local s_opts = SoloOpts(is_solo)
    r.ImGui_SetCursorPos(ctx, left_x + ms_w + ms_gap, row2_btn_y)
    local _, s_clk = NavRect("S##solo", ms_w, row2_btn_h, "S", s_opts)
    if s_clk then
        r.Undo_BeginBlock()
        r.SetMediaTrackInfo_Value(track, "I_SOLO", is_solo and 0 or 2)
        r.Undo_EndBlock("Reflex: Solo", -1)
    end
    hdr.solo_rect = { r.ImGui_GetItemRectMin(ctx) }
    hdr.solo_rect[3], hdr.solo_rect[4] = r.ImGui_GetItemRectMax(ctx)
    hdr.solo_colors = s_opts

    local vol = r.GetMediaTrackInfo_Value(track, "D_VOL")
    local pan = r.GetMediaTrackInfo_Value(track, "D_PAN")
    local vol_str = InspFormatVol(vol)
    local pan_str = InspFormatPan(pan)

    -- Pan value button on header row 2 (after S, draggable, click to edit)
    do
        local pan_knob_d = hdr.pan_knob_d or row2_btn_h
        local pan_knob_x = hdr.pan_knob_x or (bw - pan_knob_d)
        local pan_x = hdr.pan_value_x or ((hdr.vol_fader_right_x or pan_knob_x) - pan_val_w)

        if not insp_pan_editing then
            r.ImGui_SetCursorPos(ctx, pan_knob_x, row2_knob_y)
            local pan_knob_sx, pan_knob_sy = r.ImGui_GetCursorScreenPos(ctx)
            NavParamKnob(dl, "##trkpan_knob", pan_knob_sx, pan_knob_sy, pan_knob_d, "pan",
                         track, nil, insp_pan_knob_state,
                         "Reflex: Pan change", "Track pan",
                         nil, nil, { hide_value = true, center_notch_w = 2 })
            pan = r.GetMediaTrackInfo_Value(track, "D_PAN")
            pan_str = InspFormatPan(pan)
        end

        local pan_val_col
        if math.abs(pan) < 0.005 then pan_val_col = C.text
        elseif pan < 0 then pan_val_col = C.pan_slider_fill
        else pan_val_col = C.fx_offline_txt end

        r.ImGui_SetCursorPos(ctx, pan_x, pan_value_row_y)
        if insp_pan_editing then
            insp_pan_edit_frames = insp_pan_edit_frames + 1
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.fx_ctrl_bg)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), pan_val_col)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), S(4), Round((row2_btn_h - r.ImGui_GetTextLineHeight(ctx)) / 2))
            r.ImGui_SetNextItemWidth(ctx, pan_val_w)
            if not insp_pan_edit_focus then r.ImGui_SetKeyboardFocusHere(ctx); insp_pan_edit_focus = true end
            local changed; changed, insp_pan_edit_buf = r.ImGui_InputText(ctx, "##paninput", insp_pan_edit_buf,
                r.ImGui_InputTextFlags_EnterReturnsTrue() | r.ImGui_InputTextFlags_AutoSelectAll())
            r.ImGui_PopStyleVar(ctx, 2); r.ImGui_PopStyleColor(ctx, 2)
            if changed then
                local buf = insp_pan_edit_buf:upper():gsub("%s", "")
                local new_pan = nil
                if buf == "C" or buf == "0" or buf == "" then new_pan = 0
                else
                    local num, dir = buf:match("^(%d+%.?%d*)([LR]?)$")
                    if num then
                        local v = tonumber(num)
                        if v and v >= 0 and v <= 100 then new_pan = v / 100; if dir == "L" then new_pan = -new_pan end end
                    end
                end
                if new_pan then
                    r.Undo_BeginBlock()
                    r.SetMediaTrackInfo_Value(track, "D_PAN", new_pan)
                    r.Undo_EndBlock("Reflex: Pan change", -1)
                end
                insp_pan_editing = false; insp_pan_edit_focus = false
            elseif insp_pan_edit_frames > 3 and not r.ImGui_IsItemActive(ctx) then
                insp_pan_editing = false; insp_pan_edit_focus = false
            end
        else
            local pan_btn_cx, pan_btn_cy = r.ImGui_GetCursorScreenPos(ctx)
            r.ImGui_InvisibleButton(ctx, "##pandrag", pan_val_w, row2_btn_h)
            Tip("Drag: adjust pan\nOpt: reset center")
            local pan_btn_hov = r.ImGui_IsItemHovered(ctx)
            local pan_btn_act = r.ImGui_IsItemActive(ctx)
            local knob_recent_release = insp_pan_knob_state.released_at
                and (r.time_precise() - insp_pan_knob_state.released_at <= 2.0)
            local show_pan_value = insp_hdr_card_hovered[track] == true
                or pan_btn_hov or pan_btn_act or insp_pan_dragging
                or insp_pan_knob_state.active or knob_recent_release
            if show_pan_value and (pan_btn_hov or pan_btn_act) then
                r.ImGui_DrawList_AddRectFilled(dl, pan_btn_cx, pan_btn_cy, pan_btn_cx + pan_val_w, pan_btn_cy + row2_btn_h, pan_btn_act and C.fx_ctrl_active or C.fx_ctrl_hover, 3)
            end
            local ptw = r.ImGui_CalcTextSize(ctx, pan_str)
            local pth = r.ImGui_GetTextLineHeight(ctx)
            local pan_draw_col
            if pan_str == "C" then
                pan_draw_col = (pan_btn_hov or pan_btn_act) and C.text or C.text_muted
            else
                pan_draw_col = pan_val_col
            end
            if show_pan_value then
                r.ImGui_DrawList_AddText(dl,
                    pan_btn_cx + Round((pan_val_w - ptw) / 2),
                    pan_btn_cy + Round((row2_btn_h - pth) / 2),
                    pan_draw_col, pan_str)
            end
            if r.ImGui_IsItemClicked(ctx, 0) then
                insp_pan_dragging = true; insp_pan_drag_moved = false
                insp_pan_before = r.GetMediaTrackInfo_Value(track, "D_PAN")
            end
            if r.ImGui_IsItemActive(ctx) and insp_pan_dragging then
                local dx, dy = r.ImGui_GetMouseDelta(ctx)
                local delta = dx - dy
                if math.abs(delta) > 0 then
                    insp_pan_drag_moved = true
                    local new_pan = math.max(-1, math.min(1, pan + delta * 0.005))
                    if math.abs(new_pan) < 0.015 then new_pan = 0 end
                    r.SetMediaTrackInfo_Value(track, "D_PAN", new_pan)
                end
            end
            if r.ImGui_IsItemDeactivated(ctx) and insp_pan_dragging then
                insp_pan_dragging = false
                if not insp_hdr_card_hovered[track] then
                    insp_pan_knob_state.released_at = r.time_precise()
                end
                if insp_pan_drag_moved and insp_pan_before ~= nil then
                    -- Rollback + atomic commit (Option C)
                    local pan_final = r.GetMediaTrackInfo_Value(track, "D_PAN")
                    r.SetMediaTrackInfo_Value(track, "D_PAN", insp_pan_before)
                    r.Undo_BeginBlock()
                    r.SetMediaTrackInfo_Value(track, "D_PAN", pan_final)
                    r.Undo_EndBlock("Reflex: Pan change", -1)
                elseif not insp_pan_drag_moved and IsAlt(r.ImGui_GetKeyMods(ctx)) then
                    r.Undo_BeginBlock(); r.SetMediaTrackInfo_Value(track, "D_PAN", 0)
                    r.Undo_EndBlock("Reflex: Reset pan", -1)
                end
                insp_pan_before = nil
            end
            if insp_pan_knob_state.active then
                insp_pan_knob_state.was_active = true
            elseif insp_pan_knob_state.was_active then
                insp_pan_knob_state.was_active = false
                if not insp_hdr_card_hovered[track] then
                    insp_pan_knob_state.released_at = r.time_precise()
                end
            end
            if pan_btn_hov and r.ImGui_IsMouseClicked(ctx, 1) then
                insp_pan_editing = true; insp_pan_edit_focus = false
                insp_pan_edit_frames = 0; insp_pan_edit_buf = pan_str
            end
        end
    end

    if hdr.record_armed then
        local current_value = math.floor(r.GetMediaTrackInfo_Value(track, "I_RECINPUT") or -1)
        local meter_y = right_row_block_y + right_row_h + input_row_gap
        local meter_h = RecordInputMeterHeight()
        local meter_w = math.max(1, bw - text_pad)
        local mx1, my1 = hdr.trk_cx + text_pad, hdr.trk_cy + meter_y - hdr.trk_sy
        local dl_meter = hdr.dl
        DrawRecordInputActivityMeter(dl_meter, RecordInputMeterForValue(current_value, track),
            mx1, my1, mx1 + meter_w, my1 + meter_h)

        local input_row_y = meter_y + meter_h + input_row_gap
        InspDrawRecordInputRow(track, hdr, input_row_y, input_row_h, bw, text_pad, row2_btn_h)
    end

    r.ImGui_SetCursorPos(ctx, hdr.trk_sx, hdr.trk_sy + hdr.trk_row_h)

    -- Read vol/pan for downstream sections
    hdr.vol = r.GetMediaTrackInfo_Value(track, "D_VOL")
    hdr.pan = r.GetMediaTrackInfo_Value(track, "D_PAN")
    hdr.vol_str = InspFormatVol(hdr.vol)
    hdr.pan_str = InspFormatPan(hdr.pan)

    return hdr
end

InspDrawTrackEnvelopeRows = function(track, hdr, bw)
    if not insp_env_expanded["track_env"] then return false end
    local text_pad = 0
    r.ImGui_SetCursorPos(ctx, hdr.trk_sx, r.ImGui_GetCursorPosY(ctx) + S(UI.section_gap))
    local details = InspGetAllTrackEnvelopeDetails(track)

    local has_vol, has_pan = false, false
    for _, ed in ipairs(details) do
        if (ed.fx_idx == -1 or ed.fx_idx == nil) then
            if ed.name == "Volume" then has_vol = true end
            if ed.name == "Pan" then has_pan = true end
        end
    end
    if not has_vol then
        details[#details + 1] = { env = nil, name = "Volume", visible = false, fx_idx = -1, bypassed = false }
    end
    if not has_pan then
        details[#details + 1] = { env = nil, name = "Pan", visible = false, fx_idx = -1, bypassed = false }
    end

    table.sort(details, function(a, b)
        local ka = InspEnvSortKey(a.name, a.fx_idx)
        local kb = InspEnvSortKey(b.name, b.fx_idx)
        if ka ~= kb then return ka < kb end
        if a.fx_idx ~= b.fx_idx then return a.fx_idx < b.fx_idx end
        return a.name < b.name
    end)
    for ei, ed in ipairs(details) do
        r.ImGui_PushID(ctx, 7000 + ei)
        local display_name
        if ed.fx_idx >= 0 then
            display_name = InspFormatEnvForTrackList(ed.name, ed.fx_idx, track)
        elseif ed.name and ed.name:match("^Send") and ed.env then
            display_name = InspFormatSendEnvName(track, ed.env, ed.name)
        else
            display_name = InspStripEnvSuffix(ed.name, ed.fx_idx)
        end
        local name_col = InspEnvColor(ed.name, ed.fx_idx)
        InspDrawEnvRow(ed, display_name, name_col, bw, text_pad,
            function()
                local mods = r.ImGui_GetKeyMods(ctx)
                local is_native = (ed.fx_idx == -1 or ed.fx_idx == nil) and (ed.name == "Volume" or ed.name == "Pan")
                if is_native then
                    InspToggleEnvelope(track, ed.name)
                elseif IsAlt(mods) then
                    for _, d in ipairs(details) do InspSetEnvelopeVisibleRaw(d.env, false) end
                    InspSetEnvelopeVisible(ed.env, true)
                else
                    InspSetEnvelopeVisible(ed.env, not ed.visible)
                end
            end,
            function()
                local is_native = (ed.fx_idx == -1 or ed.fx_idx == nil) and (ed.name == "Volume" or ed.name == "Pan")
                if is_native then
                    InspToggleEnvelope(track, ed.name)
                elseif ed.visible then
                    InspSetEnvelopeVisible(ed.env, false)
                else
                    for _, d in ipairs(details) do InspSetEnvelopeVisibleRaw(d.env, false) end
                    InspSetEnvelopeVisible(ed.env, true)
                end
            end, track)
        r.ImGui_PopID(ctx)
    end
    return true
end

InspTrackEnvLabelWidth = function()
    local env_text_nudge = 13 * 0.5
    local env_right_trim = 6 * 0.5
    local env_pad_each = 9
    return r.ImGui_CalcTextSize(ctx, "ENV") + env_pad_each * 2 - env_text_nudge - env_right_trim
end

InspTrackEnvCompoundBaseWidth = function(row_h)
    return row_h + InspTrackEnvLabelWidth()
end

InspTrackEnvCompoundWidth = function(row_h, track, opts)
    opts = opts or {}
    local dot_r = S(5)
    local dot_gap = 4
    local active_envs = track and InspGetAllTrackEnvelopeDetails(track) or {}
    if #active_envs == 0 then return 0, 0, 0, 0 end
    local show_dots = false
    local dots_w = show_dots and (dot_r * 2 + dot_gap + dot_r * 2) or 0
    local env_w = InspTrackEnvLabelWidth()
    if opts.stack_dots then
        return math.max(env_w + row_h, dots_w), dots_w, env_w, 0
    end
    local segment_gap = 5.5
    local dots_block_w = show_dots and (segment_gap + dots_w + segment_gap) or 0
    return dots_block_w + env_w + row_h, dots_w, env_w, segment_gap
end

InspDrawTrackEnvCompound = function(track, x, y, row_h, opts)
    opts = opts or {}
    local dot_r = S(5)
    local dot_gap = 4
    -- 7 Retina px from VP circle bottom to ENV glyph top = 3.5 logical px.
    local stacked_dot_gap = 3.5
    local total_w, dots_w, env_w, dots_gap = InspTrackEnvCompoundWidth(row_h, track, opts)
    if total_w <= 0 then return 0 end
    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_SetCursorPos(ctx, x, y)
    local comp_sx, comp_sy = r.ImGui_GetCursorScreenPos(ctx)

    local active_envs = InspGetAllTrackEnvelopeDetails(track)
    local vol_env_exists, pan_env_exists = false, false
    for _, ed in ipairs(active_envs) do
        if (ed.fx_idx == -1 or ed.fx_idx == nil) and ed.name == "Volume" then vol_env_exists = true end
        if (ed.fx_idx == -1 or ed.fx_idx == nil) and ed.name == "Pan" then pan_env_exists = true end
    end
    local show_dots = false
    local dot_h = dot_r * 2
    local env_text_h = r.ImGui_GetTextLineHeight(ctx)
    local env_text_offset_y = Round((row_h - env_text_h) / 2)
    local stacked_total_h = show_dots and (dot_h + stacked_dot_gap + env_text_h) or row_h
    local block_y = opts.stack_dots and (y + Round((row_h - stacked_total_h) / 2)) or y
    local env_y = opts.stack_dots and (block_y + (show_dots and (dot_h + stacked_dot_gap - env_text_offset_y) or 0)) or y
    local segment_gap = 5.5
    local arr_x = x
    local env_x = x + row_h
    local trk_env_exp = insp_env_expanded["track_env"] == true
    local any_env_vis = false
    for _, ed in ipairs(active_envs) do if ed.visible then any_env_vis = true; break end end
    local compound_hov = r.ImGui_IsMouseHoveringRect(ctx, comp_sx, comp_sy, comp_sx + total_w, comp_sy + row_h)
    local compound_active = compound_hov and r.ImGui_IsMouseDown(ctx, 0)

    if not opts.stack_dots then
        local compound_bg
        if any_env_vis then
            compound_bg = compound_active and ((C.fx_power_on & 0xFFFFFF00) | 0xCC) or C.fx_power_on
        else
            compound_bg = compound_active and C.fx_ctrl_active
                or (compound_hov and C.fx_ctrl_hover or C.fx_ctrl_bg)
        end
        r.ImGui_DrawList_AddRectFilled(dl, comp_sx, comp_sy, comp_sx + total_w, comp_sy + row_h,
            compound_bg, S(3))
    end

    if show_dots then
        local dot_x = x + segment_gap
        local dot_y = y + Round((row_h - dot_r * 2) / 2)
        if opts.stack_dots then
            dot_x = env_x + Round((env_w - dots_w) / 2)
            dot_y = block_y
        end
        r.ImGui_SetCursorPos(ctx, dot_x, dot_y)
        local dot_sx, dot_sy = r.ImGui_GetCursorScreenPos(ctx)
        r.ImGui_InvisibleButton(ctx, "##tenv_dots", dots_w, dot_r * 2)
        local dots_clk = r.ImGui_IsItemClicked(ctx, 0)
        local dot_cy = dot_sy + dot_r
        if vol_env_exists then
            r.ImGui_DrawList_AddCircleFilled(dl, dot_sx + dot_r, dot_cy, dot_r, C.env_vol_dot, 24)
        end
        if pan_env_exists then
            r.ImGui_DrawList_AddCircleFilled(dl, dot_sx + dot_r * 3 + dot_gap, dot_cy, dot_r, C.pan_slider_fill, 24)
        end
        if dots_clk then
            r.Undo_BeginBlock()
            local any_native_vis = false
            for _, ed in ipairs(active_envs) do
                if (ed.fx_idx == -1 or ed.fx_idx == nil)
                    and ed.env
                    and (ed.name == "Volume" or ed.name == "Pan")
                    and ed.visible then
                    any_native_vis = true
                    break
                end
            end
            for _, ed in ipairs(active_envs) do
                if (ed.fx_idx == -1 or ed.fx_idx == nil)
                    and ed.env
                    and (ed.name == "Volume" or ed.name == "Pan") then
                    InspSetEnvelopeVisibleRaw(ed.env, not any_native_vis)
                end
            end
            r.TrackList_AdjustWindows(false); r.UpdateArrange()
            r.Undo_EndBlock("Toggle track envelope visibility", -1)
        end
    end

    local arr_txt
    if any_env_vis then
        arr_txt = trk_env_exp and 0xFFFFFFFF or (0xFFFFFF00 | (C.text_dim & 0xFF))
    else
        arr_txt = trk_env_exp and C.text or C.text_dim
    end
    r.ImGui_SetCursorPos(ctx, arr_x, env_y)
    local _, trk_arr_clk = NavRect("##tea", row_h, row_h,
        trk_env_exp and "\xE2\x96\xBC" or "\xE2\x96\xB6",
        { bg = 0x00000000, hov = 0x00000000, active = 0x00000000,
          fg = arr_txt, fg_hov = any_env_vis and 0xFFFFFFFF or C.text, fg_active = any_env_vis and 0xFFFFFFFF or C.text,
          arrow_dx = 0.5, arrow_dy = 1.0 })
    Tip("Opt: toggle all")
    if trk_arr_clk then
        local mods = r.ImGui_GetKeyMods(ctx)
        if IsAlt(mods) then
            local new_state = not trk_env_exp
            for ffi = 1, #InspGetFxList(track) do insp_env_expanded[ffi] = new_state end
            insp_env_expanded["track_env"] = new_state
        else
            insp_env_expanded["track_env"] = not trk_env_exp
        end
    end

    r.ImGui_SetCursorPos(ctx, env_x, env_y)
    local env_txt, env_htxt = C.text_dim, C.text
    if any_env_vis then
        env_txt = 0xFFFFFFFF
        env_htxt = 0xFFFFFFFF
    else
        env_txt = C.text_dim
        env_htxt = C.text
    end
    r.ImGui_InvisibleButton(ctx, "##tenv", env_w, row_h)
    local env_hov = r.ImGui_IsItemHovered(ctx)
    local trk_env_clk = r.ImGui_IsItemClicked(ctx, 0)
    local env_sx, env_sy = r.ImGui_GetItemRectMin(ctx)
    local env_label = "ENV"
    local env_text_nudge = 13 * 0.5
    local env_pad_each = 9
    r.ImGui_DrawList_AddText(dl, env_sx + env_pad_each - env_text_nudge,
        env_sy + Round((row_h - r.ImGui_GetTextLineHeight(ctx)) / 2),
        env_hov and env_htxt or env_txt, env_label)
    if trk_env_clk then
        r.Undo_BeginBlock()
        local any_vis = false
        for _, ed in ipairs(active_envs) do if ed.visible then any_vis = true; break end end
        for _, ed in ipairs(active_envs) do InspSetEnvelopeVisibleRaw(ed.env, not any_vis) end
        r.TrackList_AdjustWindows(false); r.UpdateArrange()
        r.Undo_EndBlock("Toggle envelope visibility", -1)
    end

    return total_w
end

-- =========================================================================
-- INSPECTOR VOLUME SLIDER + METER (extracted sub-function)
-- =========================================================================
-- Draws: volume slider with -/+ circles, meter bar.
-- Sets cursor Y to start of next section (controls row).
InspDrawVolumeSlider = function(track, hdr)
    local dl = hdr.dl
    local bw = hdr.bw
    local trk_sx = hdr.trk_sx
    local vol = hdr.vol
    local vol_str = hdr.vol_str
    local track_color_raw = hdr.track_color_raw
    local is_flow_secondary = hdr.is_flow_secondary

    local arrow_w = 12.0  -- 24 Retina px
    local arrow_h = 9.5   -- 19 Retina px
    local arrow_top_gap = -6.0 -- compensates inherited header padding; visible target is 14 Retina px
    local bar_spacing = arrow_top_gap + arrow_h
    local vol_cur_y = r.ImGui_GetCursorPosY(ctx) + bar_spacing
    local vol_expanded_h = S(UI.btn_h)  -- match mute button height
    local vol_bar_h = vol_expanded_h
    local elem_gap = S(UI.pad_sm)  -- standard gap between all elements (matches ctrl_gap)

    r.ImGui_SetCursorPos(ctx, trk_sx, vol_cur_y)
    local vbar_sx = r.ImGui_GetCursorPosX(ctx)
    local vbar_sy = r.ImGui_GetCursorPosY(ctx)
    local vbar_cx, vbar_cy_raw = r.ImGui_GetCursorScreenPos(ctx)

    local vol_bar_r = vol_bar_h / 2
    local vol_y_offset = Round((vol_expanded_h - vol_bar_h) / 2)
    local vol_circ_d = vol_bar_h
    local vol_circ_r = vol_circ_d / 2

    -- Right-side layout: fader fills remaining space beside [-] [+].
    local vol_val_w = hdr.vol_value_w or (vol_bar_h * 2 + elem_gap)
    local fader_to_buttons_gap = elem_gap * 2
    local button_gap = elem_gap
    local pm_w = vol_bar_h + button_gap + vol_bar_h
    local vol_wrapped = false
    local vbar_cy = vbar_cy_raw + vol_y_offset
    local vbar_w = math.max(1, bw - pm_w - fader_to_buttons_gap)

    -- Ableton-style fader scale: dense control below unity, small boost range above.
    local VOL_MIN_DB = -60
    local VOL_MAX_DB = 12
    local VOL_DB_RANGE = VOL_MAX_DB - VOL_MIN_DB
    local function vol_gain_to_db(gain)
        return gain > 0.000001 and 20 * math.log(gain, 10) or VOL_MIN_DB
    end
    local function vol_db_to_frac(db)
        return math.max(0, math.min(1, (db - VOL_MIN_DB) / VOL_DB_RANGE))
    end
    local function vol_frac_to_gain(frac)
        if frac <= 0.005 then return 0 end
        local db = VOL_MIN_DB + math.max(0, math.min(1, frac)) * VOL_DB_RANGE
        return 10 ^ (db / 20)
    end
    local vol_fill = vol_db_to_frac(vol_gain_to_db(vol))
    local zero_frac = vol_db_to_frac(0)
    local zero_x = vbar_cx + math.floor(zero_frac * vbar_w)

    -- Handle assembly: 4 Retina px indicator line plus external bitmap arrow.
    local handle_line_w = 2.0
    local handle_x = vbar_cx + vol_fill * vbar_w
    handle_x = math.max(vbar_cx + handle_line_w / 2, math.min(vbar_cx + vbar_w - handle_line_w / 2, handle_x))
    local handle_left = handle_x - handle_line_w / 2
    local handle_right = handle_x + handle_line_w / 2
    local arrow_top_y = vbar_cy - arrow_h
    local vol_hit_x = vbar_cx - arrow_w / 2
    local vol_hit_w = vbar_w + arrow_w

    -- Check if mouse is in the volume row area (for handle/dot visibility)
    local mx_vol, my_vol = r.ImGui_GetMousePos(ctx)
    local vol_hit_top = arrow_top_y
    local vol_row_bottom = vol_wrapped and (vbar_cy + vol_bar_h + elem_gap + vol_bar_h) or (vbar_cy + vol_bar_h)
    local vol_row_hover = (insp_vol_dragging and insp_vol_drag_track == track)
        or (insp_vol_val_dragging and insp_vol_val_drag_track == track)
        or (mx_vol >= vol_hit_x and mx_vol <= vol_hit_x + vol_hit_w
            and my_vol >= vol_hit_top and my_vol <= vol_row_bottom)

    -- ── COMBINED STEREO METER + SLIDER BACKGROUND ──

    -- Peak level (independent L/R lanes) with smoothing and transport auto-reset.
    local peak_l_raw = r.Track_GetPeakInfo(track, 0)
    local peak_r_raw = r.Track_GetPeakInfo(track, 1)
    local peak_raw = math.max(peak_l_raw, peak_r_raw)
    local ps = r.GetPlayState()
    if ps ~= (insp_meter_last_play or -1) then
        insp_meter_clip = {}; insp_meter_peak = {}; insp_meter_display = {}; insp_meter_noise = {}
    end
    insp_meter_last_play = ps
    local meter_key = tostring(track)
    local cur_l = SmoothPeak(insp_meter_peak, meter_key .. ":L", peak_l_raw)
    local cur_r = SmoothPeak(insp_meter_peak, meter_key .. ":R", peak_r_raw)
    local cur_peak = math.max(cur_l, cur_r)
    if peak_raw >= 1.0 then insp_meter_clip[track] = true end

    -- Peak display: update at a calm interval so the tiny value button doesn't chatter.
    local display_interval = 0.35
    local now = r.time_precise()
    if not insp_meter_display[track] then
        insp_meter_display[track] = { val = 0, max = 0, time = now, noise_db = nil, noise_time = now }
    end
    local md = insp_meter_display[track]
    -- Track max peak since last display update
    if cur_peak > md.max then md.max = cur_peak end
    -- Update display value at interval
    if now - md.time >= display_interval then
        md.val = md.max
        md.max = cur_peak  -- reset accumulator
        md.time = now
    end
    local display_peak = md.val

    -- Rounded-rect track. Full-width rounded rects clipped to sub-rects act as
    -- the mask for meter lanes, zero line, and handle line.
    local track_r = S(4)
    local track_bg = C.vol_slider_bg
    local zero_mark_col = C.vol_slider_mark
    local lane_gap = 1.0  -- 2 Retina px
    local lane_h = (vol_bar_h - lane_gap) / 2
    local lane1_y1, lane1_y2 = vbar_cy, vbar_cy + lane_h
    local lane2_y1, lane2_y2 = lane1_y2 + lane_gap, vbar_cy + vol_bar_h

    local function draw_masked_track_slice(x1, x2, y1, y2, col)
        if x2 <= x1 or y2 <= y1 then return end
        r.ImGui_DrawList_PushClipRect(dl, x1, y1, x2, y2, true)
        r.ImGui_DrawList_AddRectFilled(dl, vbar_cx, vbar_cy, vbar_cx + vbar_w, vbar_cy + vol_bar_h, col, track_r)
        r.ImGui_DrawList_PopClipRect(dl)
    end

    r.ImGui_DrawList_AddRectFilled(dl, vbar_cx, vbar_cy, vbar_cx + vbar_w, vbar_cy + vol_bar_h, track_bg, track_r)
    draw_masked_track_slice(zero_x - 0.75, zero_x + 0.75, vbar_cy, vbar_cy + vol_bar_h, zero_mark_col)

    local function meter_fill_for_peak(cur)
        if cur <= 0.00001 then return 0 end
        local db = 20 * math.log(math.max(cur, 0.00001), 10)
        return vol_db_to_frac(db)
    end

    -- Noise floor indicator: grey fill from left edge, variance-based detection.
    -- This treats stable low-level plugin output as a held warning, not a momentary meter.
    local noise_floor_db = -120
    local noise_ceiling_db = -50
    local noise_floor_amp = 10 ^ (noise_floor_db / 20)
    local noise_ceiling_amp = 10 ^ (noise_ceiling_db / 20)
    local noise_hold_s = 2.25
    local noise_release_s = 0.45
    local noise_display_db = nil
    local track_noise = insp_meter_noise[track]
    if not track_noise then
        track_noise = {}
        insp_meter_noise[track] = track_noise
    end
    local function update_noise_lane(raw, lane)
        local mn = track_noise[lane]
        if not mn then
            mn = { variance = 0, score = 0, active = false, active_until = 0, time = now }
            track_noise[lane] = mn
        end

        local last_time = mn.time or now
        local dt = math.max(0, math.min(0.2, now - last_time))
        mn.time = now

        local in_band = raw >= noise_floor_amp and raw <= noise_ceiling_amp
        if in_band then
            local db = 20 * math.log(math.max(raw, 1e-30), 10)
            local prev_db = mn.prev_db or db
            local change = math.abs(db - prev_db)
            if change > mn.variance then
                mn.variance = mn.variance * 0.65 + change * 0.35
            else
                mn.variance = mn.variance * 0.92
            end
            mn.prev_db = db
            mn.avg_db = mn.avg_db and (mn.avg_db * 0.88 + db * 0.12) or db

            local clearly_audible_noise = db >= -100
            local varying_like_noise = mn.variance >= 0.015
            if clearly_audible_noise or varying_like_noise then
                local attack = clearly_audible_noise and 0.45 or 0.7
                mn.score = math.min(1, (mn.score or 0) + dt / attack)
            else
                mn.score = math.max(0, (mn.score or 0) - dt / 1.2)
            end
            if mn.score >= 0.55 then
                mn.active = true
                mn.active_until = now + noise_hold_s
            end
        else
            mn.score = math.max(0, (mn.score or 0) - dt / 0.55)
            if raw < noise_floor_amp and mn.active then
                mn.active_until = math.min(mn.active_until or 0, now + noise_release_s)
            end
            if raw > noise_ceiling_amp then
                mn.variance = 0
                mn.score = 0
                mn.avg_db = nil
                mn.prev_db = nil
                mn.active = false
                mn.active_until = 0
            end
        end

        if mn.active and now <= (mn.active_until or 0) then return mn end
        mn.active = false
        return nil
    end
    local noise_l = update_noise_lane(peak_l_raw, "L")
    local noise_r = update_noise_lane(peak_r_raw, "R")

    local function draw_meter_lane(cur, y1, y2, noise_state)
        if noise_state then return end
        local fill = meter_fill_for_peak(cur)
        if fill <= 0 then return end
        local meter_right = vbar_cx + math.floor(fill * vbar_w)
        if meter_right > vbar_cx then
            local db = 20 * math.log(math.max(cur, 0.00001), 10)
            draw_masked_track_slice(vbar_cx, meter_right, y1, y2, MeterColor(db))
        end
    end

    local function draw_noise_lane(noise_state, y1, y2)
        if not noise_state then return end
        local noise_db = math.max(noise_floor_db, math.min(noise_ceiling_db, noise_state.avg_db or noise_floor_db))
        noise_display_db = math.max(noise_display_db or noise_db, noise_db)
        local base_frac = 0.08
        local frac_part = noise_db - math.floor(noise_db)
        local jitter = (frac_part - 0.5) * S(6)
        local noise_w = math.max(S(4), math.floor(vbar_w * base_frac) + math.floor(jitter))
        draw_masked_track_slice(vbar_cx, vbar_cx + noise_w, y1, y2, C.text_muted)
    end
    draw_meter_lane(cur_l, lane1_y1, lane1_y2, noise_l)
    draw_meter_lane(cur_r, lane2_y1, lane2_y2, noise_r)
    draw_noise_lane(noise_l, lane1_y1, lane1_y2)
    draw_noise_lane(noise_r, lane2_y1, lane2_y2)

    local handle_line_col = vol_row_hover
        and rgb(0xE5B365) or 0xFFFFFFFF
    draw_masked_track_slice(handle_left, handle_right, vbar_cy, vbar_cy + vol_bar_h, handle_line_col)
    local arrow_img = GetVolumeFaderArrowImg and GetVolumeFaderArrowImg() or nil
    if arrow_img then
        local arrow_left = handle_x - arrow_w / 2
        r.ImGui_DrawList_AddImage(dl, arrow_img,
            arrow_left, arrow_top_y,
            arrow_left + arrow_w, vbar_cy,
            0, 0, 1, 1, 0xFFFFFFFF)
    else
        r.ImGui_DrawList_AddTriangleFilled(dl,
            handle_x - arrow_w / 2, arrow_top_y,
            handle_x + arrow_w / 2, arrow_top_y,
            handle_x, vbar_cy,
            0xFFFFFFFF)
    end
    if noise_display_db then
        if not md.noise_db or now - (md.noise_time or 0) >= display_interval then
            md.noise_db = md.noise_db and (md.noise_db * 0.7 + noise_display_db * 0.3) or noise_display_db
            md.noise_time = now
        end
    else
        md.noise_db = nil
    end

    -- Slider interaction (handle drag; opt+click resets to 0dB)
    r.ImGui_SetCursorScreenPos(ctx, vol_hit_x, vol_hit_top)
    r.ImGui_InvisibleButton(ctx, "##volbar", vol_hit_w, vol_row_bottom - vol_hit_top)
    Tip("Opt: reset 0 dB")
    if r.ImGui_IsItemClicked(ctx, 0) then
        if IsAlt(r.ImGui_GetKeyMods(ctx)) then
            r.Undo_BeginBlock(); r.SetMediaTrackInfo_Value(track, "D_VOL", 1.0); r.Undo_EndBlock("Reflex: Reset volume", -1)
        else
            insp_vol_dragging = true; insp_vol_drag_track = track
            insp_vol_drag_moved = false
            -- Option C test: cache pre-drag value, no undo block during drag
            insp_vol_before = r.GetMediaTrackInfo_Value(track, "D_VOL")
        end
    end
    if r.ImGui_IsItemActive(ctx) and insp_vol_dragging then
        local dx, dy = r.ImGui_GetMouseDragDelta(ctx, 0)
        if insp_vol_drag_moved or math.abs(dx) >= 1 or math.abs(dy) >= 1 then
            insp_vol_drag_moved = true
            local mx = r.ImGui_GetMousePos(ctx)
            local ratio = math.max(0, math.min(1, (mx - vbar_cx) / vbar_w))
            local new_vol = vol_frac_to_gain(ratio)
            -- Raw write during drag, no undo wrapping (audio feedback only)
            r.SetMediaTrackInfo_Value(track, "D_VOL", new_vol)
        end
    end
    if r.ImGui_IsItemDeactivated(ctx) and insp_vol_dragging then
        insp_vol_dragging = false; insp_vol_drag_track = nil
        -- Atomic commit: read final, rollback silently, then Begin/Set/End
        if insp_vol_drag_moved and insp_vol_before ~= nil then
            local vol_final = r.GetMediaTrackInfo_Value(track, "D_VOL")
            r.SetMediaTrackInfo_Value(track, "D_VOL", insp_vol_before)  -- silent rollback
            r.Undo_BeginBlock()
            r.SetMediaTrackInfo_Value(track, "D_VOL", vol_final)
            r.Undo_EndBlock("Reflex: Volume change", -1)
        end
        insp_vol_before = nil
        insp_vol_drag_moved = false
    end

    -- Click on slider background also resets clip indicator
    if r.ImGui_IsItemClicked(ctx, 0) and not IsAlt(r.ImGui_GetKeyMods(ctx)) then
        insp_meter_clip[track] = false
    end

    -- Right-side elements: header [vol_value], row [-] [+]
    local circ_cy = vbar_cy + vol_bar_h / 2
    local right_start = hdr.vol_value_sx or (vbar_cx + vbar_w + fader_to_buttons_gap)
    local right_cy = hdr.vol_value_sy or vbar_cy
    local minus_x = vbar_cx + vbar_w + fader_to_buttons_gap
    local plus_x = minus_x + vol_circ_d + button_gap

    -- Determine vol value display mode: peak dB (default) vs volume setting
    local vol_value_hover = mx_vol >= right_start and mx_vol <= right_start + vol_val_w
        and my_vol >= right_cy and my_vol <= right_cy + vol_bar_h
    local vol_button_hover = mx_vol >= minus_x and mx_vol <= plus_x + vol_circ_d
        and my_vol >= vbar_cy and my_vol <= vbar_cy + vol_bar_h
    local vol_button_hold = now < (insp_vol_button_show_until[track] or 0)
    local vol_row_interacting = vol_row_hover or vol_value_hover or vol_button_hover or vol_button_hold

    -- Format display value
    local display_str, display_col
    if vol_row_interacting then
        -- Show volume setting
        display_str = vol_str
        display_col = insp_meter_clip[track] and C.fx_offline_txt or C.text
    else
        -- Show peak dB (slow-smoothed for stable readout)
        if display_peak > 0.00001 then
            local peak_db = 20 * math.log(display_peak, 10)
            display_str = string.format("%.0f", peak_db)
        elseif md.noise_db then
            display_str = string.format("%.0f", md.noise_db)
        else
            display_str = "-inf"
        end
        if insp_meter_clip[track] then
            display_col = C.fx_offline_txt  -- red, stays red until clicked
        else
            display_col = C.text_muted
        end
    end

    -- Volume value (draggable, opt+click resets, right-click inline edit)
    if insp_vol_editing then
        insp_vol_edit_frames = insp_vol_edit_frames + 1
        r.ImGui_SetCursorScreenPos(ctx, right_start, right_cy)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.fx_ctrl_bg)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), insp_meter_clip[track] and C.fx_offline_txt or C.text)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), S(4), Round((vol_bar_h - r.ImGui_GetTextLineHeight(ctx)) / 2))
        r.ImGui_SetNextItemWidth(ctx, vol_val_w)
        if not insp_vol_edit_focus then r.ImGui_SetKeyboardFocusHere(ctx); insp_vol_edit_focus = true end
        local changed; changed, insp_vol_edit_buf = r.ImGui_InputText(ctx, "##volinput", insp_vol_edit_buf,
            r.ImGui_InputTextFlags_EnterReturnsTrue() | r.ImGui_InputTextFlags_AutoSelectAll())
        r.ImGui_PopStyleVar(ctx, 2); r.ImGui_PopStyleColor(ctx, 2)
        if changed then
            local val = tonumber(insp_vol_edit_buf)
            if val then
                r.Undo_BeginBlock()
                r.SetMediaTrackInfo_Value(track, "D_VOL", val <= -100 and 0 or 10 ^ (val / 20))
                r.Undo_EndBlock("Reflex: Volume change", -1)
            end
            insp_vol_editing = false; insp_vol_edit_focus = false
        elseif insp_vol_edit_frames > 3 and not r.ImGui_IsItemActive(ctx) then
            insp_vol_editing = false; insp_vol_edit_focus = false
        end
    else
        r.ImGui_SetCursorScreenPos(ctx, right_start, right_cy)
        r.ImGui_InvisibleButton(ctx, "##voldrag", vol_val_w, vol_bar_h)
        Tip("Click: edit\nOpt: reset 0 dB")
        local vv_hov = r.ImGui_IsItemHovered(ctx)
        local vv_act = r.ImGui_IsItemActive(ctx)
        if vv_hov or vv_act then
            r.ImGui_DrawList_AddRectFilled(dl, right_start, right_cy, right_start + vol_val_w, right_cy + vol_bar_h,
                vv_act and C.fx_ctrl_active or C.fx_ctrl_hover, 3)
        end
        -- Center text in the header volume value box.
        local text_x, text_col
        if display_str == "-inf" then
            local inf_w = r.ImGui_CalcTextSize(ctx, "-inf")
            text_x = right_start + Round((vol_val_w - inf_w) / 2)
            text_col = C.text_muted
        else
            local display_w = r.ImGui_CalcTextSize(ctx, display_str)
            text_x = right_start + Round((vol_val_w - display_w) / 2)
            text_col = display_col
        end
        r.ImGui_DrawList_AddText(dl, text_x,
            right_cy + Round((vol_bar_h - r.ImGui_GetTextLineHeight(ctx)) / 2),
            text_col, display_str)
        if r.ImGui_IsItemClicked(ctx, 0) then
            insp_vol_val_dragging = true; insp_vol_val_drag_track = track; insp_vol_drag_moved = false
            insp_vol_val_before = r.GetMediaTrackInfo_Value(track, "D_VOL")
        end
        if vv_act and insp_vol_val_dragging then
            local dx, dy = r.ImGui_GetMouseDelta(ctx)
            local delta = dx - dy
            if math.abs(delta) > 0 then
                insp_vol_drag_moved = true
                local cur_db = vol < 0.00001 and -100 or 20 * math.log(vol, 10)
                local new_db = math.max(-100, math.min(VOL_MAX_DB, cur_db + delta * 0.15))
                if math.abs(new_db) < 0.3 then new_db = 0 end
                r.SetMediaTrackInfo_Value(track, "D_VOL", new_db <= -100 and 0 or 10 ^ (new_db / 20))
            end
        end
        if r.ImGui_IsItemDeactivated(ctx) and insp_vol_val_dragging then
            insp_vol_val_dragging = false; insp_vol_val_drag_track = nil
            if insp_vol_drag_moved and insp_vol_val_before ~= nil then
                -- Rollback + atomic commit (Option C)
                local vol_final = r.GetMediaTrackInfo_Value(track, "D_VOL")
                r.SetMediaTrackInfo_Value(track, "D_VOL", insp_vol_val_before)
                r.Undo_BeginBlock()
                r.SetMediaTrackInfo_Value(track, "D_VOL", vol_final)
                r.Undo_EndBlock("Reflex: Volume change", -1)
            elseif not insp_vol_drag_moved then
                if IsAlt(r.ImGui_GetKeyMods(ctx)) then
                    r.Undo_BeginBlock(); r.SetMediaTrackInfo_Value(track, "D_VOL", 1.0)
                    r.Undo_EndBlock("Reflex: Reset volume", -1)
                else insp_meter_clip[track] = false end
            end
            insp_vol_val_before = nil
        end
        if vv_hov and r.ImGui_IsMouseClicked(ctx, 1) then
            insp_vol_editing = true; insp_vol_edit_focus = false
            insp_vol_edit_frames = 0; insp_vol_edit_buf = vol_str
        end
    end

    if InspTrackVolumeEnvelopeActive and InspTrackVolumeEnvelopeActive(track) then
        local dot_r = S(5)
        local dot_gap = 11 * 0.5
        r.ImGui_DrawList_AddCircleFilled(dl, right_start + vol_val_w + dot_gap + dot_r,
            right_cy + vol_bar_h / 2, dot_r, C.env_vol_dot, 24)
    end

    -- Minus square (hit rect taller than visible square for easier click)
    r.ImGui_SetCursorScreenPos(ctx, minus_x, vbar_cy)
    local _, md_clk = NavSquare("##vcirc_d", vol_circ_d, vol_circ_d, "-", { hit_h = vol_bar_h })
    Tip("Click: -1 dB\nOpt: -0.5 dB")
    if md_clk then
        local step = IsAlt(r.ImGui_GetKeyMods(ctx)) and 0.5 or 1.0
        local cur_db = vol < 0.00001 and -100 or 20 * math.log(vol, 10)
        local new_db = math.max(-100, cur_db - step)
        r.Undo_BeginBlock(); r.SetMediaTrackInfo_Value(track, "D_VOL", new_db <= -100 and 0 or 10 ^ (new_db / 20))
        r.Undo_EndBlock("Reflex: Volume change", -1)
        insp_vol_button_show_until[track] = now + 2.0
    end

    -- Plus square
    r.ImGui_SetCursorScreenPos(ctx, plus_x, vbar_cy)
    local _, pu_clk = NavSquare("##vcirc_u", vol_circ_d, vol_circ_d, "+", { hit_h = vol_bar_h })
    Tip("Click: +1 dB\nOpt: +0.5 dB")
    if pu_clk then
        local step = IsAlt(r.ImGui_GetKeyMods(ctx)) and 0.5 or 1.0
        local cur_db = vol < 0.00001 and -100 or 20 * math.log(vol, 10)
        r.Undo_BeginBlock(); r.SetMediaTrackInfo_Value(track, "D_VOL", 10 ^ (math.min(VOL_MAX_DB, cur_db + step) / 20))
        r.Undo_EndBlock("Reflex: Volume change", -1)
        insp_vol_button_show_until[track] = now + 2.0
    end

    -- Export alignment values for controls row
    hdr.vol_val_w = vol_val_w
    hdr.vol_right_x = right_start  -- screen X of vol value button
    hdr.vol_pm_combined_w = vol_circ_d + button_gap + vol_circ_d  -- width of -/+ buttons combined

    -- Set cursor for next section (no separate meter — combined into slider).
    -- No trailing gap: CTRL owns the VOL→CTRL space via gap_vol_ctrl.
    r.ImGui_SetCursorPos(ctx, trk_sx, vbar_sy + vol_expanded_h)
end

-- =========================================================================
-- INSPECTOR CONTROLS ROW (extracted sub-function)
-- =========================================================================
-- Draws: FX collapse arrow, add FX button, pan control, vol value, routing pill.
-- Returns is_fx_collapsed (needed by FX area).
-- Sets cursor Y to start of FX area.
-- =========================================================================
-- FX CHAIN COMPOUND BUTTON  [▶ FX +]
-- =========================================================================
-- Unified rendering for the 3-part FX control compound used in controls row
-- and FX area. Returns (is_fx_collapsed).
DrawFXChainCompound = function(track, trk_sx, y, fx_btn_w, ctrl_row_h, min_btn_w, ctrl_gap)
    local is_fx_collapsed = insp_fx_collapsed[track] == true
    -- v20.434 Stage C: live REAPER count, no cache touch needed.
    local has_fx = InspGetFxCount(track) > 0
    local fx_enabled = r.GetMediaTrackInfo_Value(track, "I_FXEN") == 1

    if has_fx then
        local arrow_hit_w = min_btn_w
        local arrow_label = is_fx_collapsed and "\xE2\x96\xB6" or "\xE2\x96\xBC"
        local fx_txt_col = fx_enabled and C.fx_power_on or C.fx_offline_txt

        -- Arrow half (left): round left corners only
        r.ImGui_SetCursorPos(ctx, trk_sx, y)
        local _, arrow_clk = NavRect("##fxcollapse", arrow_hit_w, ctrl_row_h, arrow_label, {
            fg = is_fx_collapsed and C.text_dim or C.text,
            arrow_dx = 1.0,
            arrow_dy = 0.5,
            rounding = {tl = 3, bl = 3, tr = 0, br = 0},
        })
        Tip("Opt: toggle all")
        if arrow_clk then
            if IsAlt(r.ImGui_GetKeyMods(ctx)) then
                for k in pairs(insp_fx_collapsed) do insp_fx_collapsed[k] = not is_fx_collapsed end
                insp_fx_collapsed[track] = not is_fx_collapsed
                if flow_view_active then
                    for _, ct in ipairs(flow_view_chain) do insp_fx_collapsed[ct] = not is_fx_collapsed end
                end
            else
                insp_fx_collapsed[track] = not is_fx_collapsed
            end
            is_fx_collapsed = insp_fx_collapsed[track] == true
        end

        -- FX-chain half (middle): no rounding
        r.ImGui_SetCursorPos(ctx, trk_sx + arrow_hit_w, y)
        local _, fxchain_clk = NavRect("##fxchain", fx_btn_w, ctrl_row_h, "FX", {
            fg = fx_txt_col,
            rounding = {tl = 0, bl = 0, tr = 0, br = 0},
        })
        Tip("Click: show chain\nShift: toggle FX bypass\nOpt: clear chain")
        if fxchain_clk then
            local mods = r.ImGui_GetKeyMods(ctx)
            if IsAlt(mods) then
                -- Opt+click: clear entire chain (v20.411). Matches row Opt+click
                -- "remove this FX" idiom — on chain-level button, removes all.
                -- Single undo entry, descending delete for stable indices.
                local count = r.TrackFX_GetCount(track)
                if count > 0 then
                    r.Undo_BeginBlock()
                    for i = count - 1, 0, -1 do
                        r.TrackFX_Delete(track, i)
                    end
                    r.Undo_EndBlock("Reflex: Clear FX chain", -1)
                    InspScanTrack(track)
                    if insp_fx_sel_track == track then InspFxSelClear() end
                    if sends_fx_cache then sends_fx_cache[track] = nil end
                end
            elseif IsShift(mods) then
                r.Undo_BeginBlock()
                r.SetMediaTrackInfo_Value(track, "I_FXEN", fx_enabled and 0 or 1)
                r.Undo_EndBlock("Reflex: FX chain bypass", -1)
            else
                local chain_vis = r.TrackFX_GetChainVisible(track)
                if chain_vis >= 0 then r.TrackFX_Show(track, 0, 0) else r.TrackFX_Show(track, 0, 1) end
            end
        end
        if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##fxchain_ctx"); nav_rclick_consumed = true end

        -- Add FX half (right): round right corners only
        local addfx_x = trk_sx + arrow_hit_w + fx_btn_w
        r.ImGui_SetCursorPos(ctx, addfx_x, y)
        do
            local _, addfx_clk, addfx_act = NavRect("##addfx_btn", min_btn_w, ctrl_row_h, "+", {
                hov = C.fx_power_on, active = (C.fx_power_on & 0xFFFFFF00) | 0xCC,
                rounding = {tl = 0, bl = 0, tr = 3, br = 3},
            })
            Tip("Click: FX browser\nDrag: insert at position")
            if addfx_clk then
                insp_fx_insert_sy = (select(2, r.ImGui_GetMousePos(ctx)))
                insp_fx_insert_dragging = false
            end
            if addfx_act and not insp_fx_insert_dragging then
                local _, imy = r.ImGui_GetMousePos(ctx)
                if math.abs(imy - insp_fx_insert_sy) > S(8) then insp_fx_insert_dragging = true end
            end
            if r.ImGui_IsItemDeactivated(ctx) and not insp_fx_insert_dragging then InspOpenFXBrowser(track) end
            if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##addfx_ctx"); nav_rclick_consumed = true end
        end
    else
        -- No FX: [FX | +] compound
        r.ImGui_SetCursorPos(ctx, trk_sx, y)
        local _, fxchain_clk = NavRect("##fxchain", fx_btn_w, ctrl_row_h, "FX", {
            fg = C.text_dim,
            rounding = {tl = 3, bl = 3, tr = 0, br = 0},
        })
        if fxchain_clk then
            local chain_vis = r.TrackFX_GetChainVisible(track)
            if chain_vis >= 0 then r.TrackFX_Show(track, 0, 0) else r.TrackFX_Show(track, 0, 1) end
        end
        if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##fxchain_ctx"); nav_rclick_consumed = true end
        local addfx_x = trk_sx + fx_btn_w
        r.ImGui_SetCursorPos(ctx, addfx_x, y)
        do
            local _, addfx_clk, addfx_act = NavRect("##addfx_btn", min_btn_w, ctrl_row_h, "+", {
                hov = C.fx_power_on, active = (C.fx_power_on & 0xFFFFFF00) | 0xCC,
                rounding = {tl = 0, bl = 0, tr = 3, br = 3},
            })
            Tip("Click: FX browser\nDrag: insert at position")
            if addfx_clk then
                insp_fx_insert_sy = (select(2, r.ImGui_GetMousePos(ctx)))
                insp_fx_insert_dragging = false
            end
            if addfx_act and not insp_fx_insert_dragging then
                local _, imy = r.ImGui_GetMousePos(ctx)
                if math.abs(imy - insp_fx_insert_sy) > S(8) then insp_fx_insert_dragging = true end
            end
            if r.ImGui_IsItemDeactivated(ctx) and not insp_fx_insert_dragging then InspOpenFXBrowser(track) end
            if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##addfx_ctx"); nav_rclick_consumed = true end
        end
    end

    -- FX chain right-click context menu
    PushPopupStyle()
    if r.ImGui_BeginPopup(ctx, "##fxchain_ctx") then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), C.fx_ctrl_hover)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
        if r.ImGui_MenuItem(ctx, "Add FX") then InspOpenFXBrowser(track) end
        r.ImGui_Separator(ctx)
        if r.ImGui_MenuItem(ctx, "Offline all") then
            r.Undo_BeginBlock()
            for fi = 0, r.TrackFX_GetCount(track) - 1 do
                r.TrackFX_SetOffline(track, fi, true)
            end
            r.Undo_EndBlock("Reflex: Offline all FX", -1)
            InspRefreshFXState()
        end
        if r.ImGui_MenuItem(ctx, "Online all") then
            r.Undo_BeginBlock()
            for fi = 0, r.TrackFX_GetCount(track) - 1 do
                r.TrackFX_SetOffline(track, fi, false)
            end
            r.Undo_EndBlock("Reflex: Online all FX", -1)
            InspRefreshFXState()
        end
        r.ImGui_PopStyleColor(ctx, 2)
        r.ImGui_EndPopup(ctx)
    end
    PopPopupStyle()

    -- Add FX right-click context menu (+ button)
    PushPopupStyle()
    if r.ImGui_BeginPopup(ctx, "##addfx_ctx") then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), C.fx_ctrl_hover)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
        if insp_fx_browser_action > 0 then
            if r.ImGui_MenuItem(ctx, "Run Custom FX Browser Action") then
                if not ExternalFxBrowserLaunch(track, FX_BROWSER_PROVIDER_CUSTOM) then
                    r.Main_OnCommand(insp_fx_browser_action, 0)
                end
            end
        end
        if r.ImGui_MenuItem(ctx, "Open REAPER FX Browser") then
            ExternalFxBrowserLaunch(track, FX_BROWSER_PROVIDER_REAPER)
        end
        r.ImGui_Separator(ctx)
        local action_label = insp_fx_browser_action > 0 and "Change FX Browser Action" or "Define FX Browser Action"
        if r.ImGui_MenuItem(ctx, action_label) then
            insp_fx_prompt_active = true
            if r.PromptForAction then r.PromptForAction(1, 0, 0) end
        end
        if insp_fx_browser_action > 0 then
            if r.ImGui_MenuItem(ctx, "Clear Custom Action") then
                insp_fx_browser_action = 0
                InspSaveFXBrowserAction(0)
            end
        end
        r.ImGui_PopStyleColor(ctx, 2)
        r.ImGui_EndPopup(ctx)
    end
    PopPopupStyle()

    return is_fx_collapsed
end

InspDrawControlsRow = function(track, hdr)
    local trk_sx = hdr.trk_sx
    local dl = hdr.dl
    local bw = hdr.bw
    -- CTRL owns the VOL→CTRL gap (top-margin-only convention)
    r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + S(UI.section_gap + UI.gap_vol_ctrl))
    local ctrl_row_y = r.ImGui_GetCursorPosY(ctx)
    local ctrl_row_h = S(UI.btn_h)
    local ctrl_gap = S(UI.pad_sm)
    local min_btn_w = ctrl_row_h

    local is_fx_collapsed = insp_fx_collapsed[track] == true
    local route_w = InspRoutingPillWidth()
    local env_w = InspTrackEnvCompoundWidth(ctrl_row_h, track)
    local env_stacked_w = InspTrackEnvCompoundWidth(ctrl_row_h, track, { stack_dots = true })
    local fx_has_items = InspGetFxCount(track) > 0
    local fx_compound_w = hdr.fx_btn_w + min_btn_w
    if fx_has_items then
        fx_compound_w = fx_compound_w + min_btn_w + math.floor(ctrl_gap / 2)
    end
    local stack_env_dots = false
    local active_env_w = stack_env_dots and env_stacked_w or env_w
    local ctrl_wraps = false
    hdr.fx_compound_w = fx_compound_w
    hdr.ctrl_row_h = ctrl_row_h
    hdr.ctrl_gap = ctrl_gap
    hdr.min_btn_w = min_btn_w

    if ctrl_wraps then
        -- Stacked layout: each element on its own row
        local cy = ctrl_row_y

        -- FX button
        is_fx_collapsed = DrawFXChainCompound(track, trk_sx, cy, hdr.fx_btn_w, ctrl_row_h, min_btn_w, ctrl_gap)
        cy = cy + ctrl_row_h + ctrl_gap

        InspDrawTrackEnvCompound(track, trk_sx, cy, ctrl_row_h, { stack_dots = true })
        cy = cy + ctrl_row_h + ctrl_gap

        r.ImGui_SetCursorPos(ctx, trk_sx, cy)
        InspDrawRoutingButton(track, trk_sx, cy, route_w)
        cy = cy + ctrl_row_h

        r.ImGui_SetCursorPos(ctx, trk_sx, cy)
        hdr.ctrl_row_y = cy
        hdr.route_panel_y = cy
        return is_fx_collapsed
    end

    -- Normal (wide) layout below
    is_fx_collapsed = DrawFXChainCompound(track, trk_sx, ctrl_row_y, hdr.fx_btn_w, ctrl_row_h, min_btn_w, ctrl_gap)

    -- Right-aligned: routing pill (always on this row)
    local right_x = trk_sx + bw
    local route_ctrl_x = right_x - route_w
    local env_lane_left = trk_sx + fx_compound_w + ctrl_gap
    local env_lane_right = route_ctrl_x - ctrl_gap * 2
    local env_x = env_lane_right - active_env_w
    env_x = math.max(env_lane_left, env_x)
    InspDrawTrackEnvCompound(track, env_x, ctrl_row_y, ctrl_row_h, { stack_dots = stack_env_dots })

    r.ImGui_SetCursorPos(ctx, route_ctrl_x, ctrl_row_y)
    InspDrawRoutingButton(track, route_ctrl_x, ctrl_row_y, route_w)

    -- Save routing panel Y after the controls row.
    hdr.ctrl_row_y = ctrl_row_y
    hdr.route_panel_y = ctrl_row_y + ctrl_row_h

    -- Reset cursor past controls row (no trailing gap: FX/ROUTE own the next top-margin)
    r.ImGui_SetCursorPos(ctx, trk_sx, ctrl_row_y + ctrl_row_h)

    return is_fx_collapsed
end

-- =========================================================================
-- INSPECTOR FX AREA (extracted sub-function)
-- =========================================================================
-- Draws: FX rows, drag-to-reorder, insert-drag, bypass/mute overlays,
--        FX browser prompt, + button right-click menu.
InspDrawFXArea = function(track, hdr, is_fx_collapsed, ibh)
    local trk_sx = hdr.trk_sx
    local trk_cx = hdr.trk_cx
    local trk_cy = hdr.trk_cy
    local dl = hdr.dl
    local bw = hdr.bw
    local is_muted = hdr.is_muted

    -- v20.434 Stage C: canonical FX record list for this track (per-track cache).
    -- Single fetch at function entry; all subsequent #/iter access uses this local.
    -- track_fx_cache will be populated lazily on first call here for an unscanned
    -- track (e.g. distant flow chain track first frame).
    local fx_list = InspGetFxList(track)

    -- CTRL/ROUTE → FX top gap (only when FX area has content to render)
    local has_fx_content = (not is_fx_collapsed) and #fx_list > 0
    if has_fx_content then
        local extra = 0
        r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + S(UI.section_gap + UI.gap_ctrl_fx + extra))
    end

    -- Record FX area start for bypass overlay
    local _, fx_area_start_cy = r.ImGui_GetCursorScreenPos(ctx)

    if not is_fx_collapsed then
    insp_fx_rects = {}
    for fi, fx in ipairs(fx_list) do
        r.ImGui_SetCursorPosX(ctx, trk_sx)
        InspDrawFXRow(fx, fi, bw, ibh, #fx_list)
        if fi < #fx_list then
            r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + S(UI.fx_gap))
        end
    end

    -- Register inspector chain as drop target (v20.396+).
    -- All drop handling centralized in FxDragResolveDrop.
    -- insp_fx_rects is 1-based; build a 0-based copy for the registry.
    -- body_rect covers the entire card from header (hdr.trk_cx/cy) to current
    -- cursor Y — catches hover on header, M/S, routing, and empty-chain areas.
    -- v20.405: body_rect now includes card_pad on all sides so it matches the
    -- CARD OUTER BOUNDS (matching how sends-view registers) rather than
    -- the content area inside the padding. CardBegin only applies padding
    -- when opt_card_boxes is on; mirror that here.
    if (fx_drag.active or FxClipHasContent()) and track and r.ValidatePtr(track, "MediaTrack*") then
        local rects0 = {}
        for fi = 1, #fx_list do
            local rc = insp_fx_rects[fi]
            if rc then rects0[fi - 1] = { cy = rc.cy, h = rc.h, cx = rc.cx, w = rc.w } end
        end
        local _, cursor_bottom_y = r.ImGui_GetCursorScreenPos(ctx)
        -- Indicator anchor: where the next FX row WOULD appear. For empty
        -- chains, a row would have gotten a section_gap above it; add that
        -- so the empty-chain indicator line lands at the expected position.
        local fx_area_bottom_y = cursor_bottom_y
        if #fx_list == 0 then
            fx_area_bottom_y = cursor_bottom_y + S(UI.section_gap)
        end
        -- Body rect uses ACTUAL visible card bottom,
        -- not the synthetic indicator anchor. v20.411: without this fix, the
        -- outline overshot below the card on empty chains because body_rect.h
        -- was being computed from fx_area_bottom_y (indicator-space, not card-
        -- space). Split: indicator_y uses synthetic; body_rect uses actual.
        local body_bottom_y = cursor_bottom_y
        local card_top_y = hdr and hdr.trk_cy or (rects0[0] and rects0[0].cy or nil)
        local card_left_x = hdr and hdr.trk_cx or (rects0[0] and rects0[0].cx or nil)
        local card_w = (hdr and hdr.bw) or (rects0[0] and rects0[0].w or nil)
        -- Row bounds for empty-chain indicator sizing
        local row_x = rects0[0] and rects0[0].cx or card_left_x
        local row_w = rects0[0] and rects0[0].w or card_w
        if card_top_y and card_left_x and card_w and body_bottom_y > card_top_y then
            local px    = opt_card_boxes and S(UI.card_pad)     or 0
            local pyt   = opt_card_boxes and S(UI.card_pad_top) or 0
            local pyb   = opt_card_boxes and (S(UI.card_pad_bot) + InspCardBottomPadAdjust(has_fx_content)) or 0
            local body = {
                x = card_left_x - px,
                y = card_top_y - pyt,
                w = card_w + 2 * px,
                h = (body_bottom_y - card_top_y) + pyt + pyb,
            }
            FxDropTargetRegister("inspector", track, rects0, #fx_list, body,
                "insp_" .. tostring(track), fx_area_bottom_y, row_x, row_w)
        end
    end
    -- Clear drag seed if mouse released without passing threshold (legacy safety)
    if fx_drag.src_fis and fx_drag.src_surface == "inspector" and fx_drag.src_track == track
       and not fx_drag.active and not r.ImGui_IsMouseDown(ctx, 0) then
        FxDragClear()
    end

    -- Insert-drag from + button: show insert line and handle drop
    if insp_fx_insert_dragging and #fx_list > 0 then
        local _, imy = r.ImGui_GetMousePos(ctx)
        local dl_fg = r.ImGui_GetForegroundDrawList(ctx)
        local ins_target = 0
        for i = 1, #fx_list do
            local rc = insp_fx_rects[i]
            if rc and imy > rc.cy + rc.h / 2 then ins_target = i end
        end
        local rc_ref = ins_target > 0 and insp_fx_rects[ins_target] or insp_fx_rects[1]
        if rc_ref then
            local ins_line_y
            if ins_target == 0 then
                ins_line_y = rc_ref.cy - S(2)
            elseif insp_fx_rects[ins_target + 1] then
                ins_line_y = Round((rc_ref.cy + rc_ref.h + insp_fx_rects[ins_target + 1].cy) / 2)
            else
                ins_line_y = rc_ref.cy + rc_ref.h + S(2)
            end
            r.ImGui_DrawList_AddRectFilled(dl_fg, rc_ref.cx + S(4), ins_line_y - math.max(1, S(1)),
                rc_ref.cx + rc_ref.w - S(4), ins_line_y + math.max(1, S(1)), 0xFFFFFF66, math.max(1, S(1)))
        end
        if r.ImGui_IsMouseReleased(ctx, 0) then
            insp_fx_insert_target = ins_target
            insp_fx_insert_count = r.TrackFX_GetCount(track)
            insp_fx_insert_time = r.time_precise()
            insp_fx_insert_dragging = false
            InspOpenFXBrowser(track, { preserve_insert = true })
        end
    end

    end -- if not is_fx_collapsed

    -- FX master bypass overlay (covers FX rows area)
    local fx_master_enabled = r.GetMediaTrackInfo_Value(track, "I_FXEN") == 1
    if not is_fx_collapsed and not fx_master_enabled and #fx_list > 0 then
        local _, fx_area_end_cy = r.ImGui_GetCursorScreenPos(ctx)
        local fx_fade = (C.bg & 0xFFFFFF00) | 0x90
        r.ImGui_DrawList_AddRectFilled(dl, trk_cx, fx_area_start_cy, trk_cx + bw, fx_area_end_cy, fx_fade)
    end

    -- Mute fade overlay (covers entire card with matching rounded corners; excludes mute button)
    if is_muted then
        local _, end_cy = r.ImGui_GetCursorScreenPos(ctx)
        local fade = (C.bg & 0xFFFFFF00) | 0x70
        local ox1, oy1, ox2, oy2, ord
        if opt_card_boxes then
            local cp  = S(UI.card_pad)
            local cpt = S(UI.card_pad_top)
            local cpb = S(UI.card_pad_bot) + InspCardBottomPadAdjust(has_fx_content)
            ox1, oy1 = trk_cx - cp, trk_cy - cpt
            ox2, oy2 = trk_cx + bw + cp, end_cy + cpb
            ord = S(UI.card_r)
        else
            ox1, oy1, ox2, oy2 = trk_cx, trk_cy, trk_cx + bw, end_cy
            ord = 0
        end
        r.ImGui_DrawList_AddRectFilled(dl, ox1, oy1, ox2, oy2, fade, ord)
        -- Redraw mute button on top so it stays undimmed
        local mr = hdr.mute_rect
        local mc = hdr.mute_colors
        if mr and mc then
            DrawStaticRectButton(dl, mr, "M", mc)
        end
        local solo_active = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0
        if solo_active and hdr.solo_rect then
            DrawStaticRectButton(dl, hdr.solo_rect, "S", SoloOpts(true))
        end
        if hdr.record_drawn and hdr.record_armed and hdr.record_rect then
            local rr = hdr.record_rect
            DrawRecordArmRing(dl, rr[1], rr[2], rr[3], rr[4], true, hdr.record_hov, hdr.record_active)
        end
        if hdr.record_mon_drawn and hdr.record_mon_rect then
            local mr = hdr.record_mon_rect
            DrawRecordMonitorIconInRect(dl, mr[1], mr[2], mr[3], mr[4],
                hdr.record_mon_on, hdr.record_mon_hov, hdr.record_mon_active)
        end
        -- Redraw pin indicator on top so it stays undimmed (pin state is
        -- independent of mute state).
        if hdr.pin_drawn then
            DrawTrackPinIndicator(dl, hdr.pin_cx, hdr.pin_cy, hdr.pin_hov, insp_pinned)
        end
        if insp_pinned and track == insp_track then
            DrawSolidRoundedRectOutline(dl, ox1, oy1, ox2, oy2, C.source_stroke, ord, SOURCE_STROKE_W)
        end
    end

    ProcessFXBrowserActionPrompt()

    return has_fx_content
end

-- Toggle visibility of a send/receive/hardware-output envelope.
-- category: <0 = receives, 0 = sends, >0 = hardware outputs
-- env_type: 0 = volume, 1 = pan, 2 = mute
--
-- Uses native REAPER Get/SetEnvelopeStateChunk to flip ACT + VIS flags on the
-- envelope's own chunk. REAPER handles splicing the <AUXVOLENV>/<AUXPANENV>/
-- <AUXMUTEENV> block into the track chunk as a sibling of the AUXRECV line.
--
-- Pointer is resolved via SWS BR_GetMediaTrackSendInfo_Envelope (that's the
-- only SWS dependency — BR_EnvAlloc/SetProperties can't persist phantom-
-- envelope state, but the native chunk path can).
--
-- REAPER strips AUX*ENV blocks that have no PT line on save, even with
-- ACT=1/VIS=1. When making visible on a fresh envelope we inject a single
-- PT line (vol unity=1, pan/mute=0) before the closing > via string gsub —
-- native InsertEnvelopePoint silently no-ops on ACT=0 envelopes, so chunk
-- injection is the reliable path. The AUX*ENV block contains exactly one
-- "\n>" (its closing bracket), so the `, 1` gsub limit is unambiguous.
SendEnvSetVisible = function(track, category, sendidx, env_type, visible)
    if not (track and r.ValidatePtr(track, "MediaTrack*")) then return end
    if not r.BR_GetMediaTrackSendInfo_Envelope then return end
    local env = r.BR_GetMediaTrackSendInfo_Envelope(track, category, sendidx, env_type)
    if not env then return end
    local ok, chunk = r.GetEnvelopeStateChunk(env, "", false)
    if not (ok and chunk) then return end
    local flag = visible and "1" or "0"
    chunk = chunk:gsub("\nACT %-?%d+", "\nACT " .. flag, 1)
    chunk = chunk:gsub("\nVIS %-?%d+", "\nVIS " .. flag, 1)
    if visible and not chunk:find("\nPT ") then
        local unity_str = (env_type == 0) and "1" or "0"
        chunk = chunk:gsub("\n>", "\nPT 0 " .. unity_str .. " 0\n>", 1)
    end
    r.SetEnvelopeStateChunk(env, chunk, false)
end

-- Check if a send/receive/hw-output envelope is visible.
-- Returns: exists (bool), visible (bool)
SendEnvIsVisible = function(track, category, sendidx, env_type)
    if not (track and r.ValidatePtr(track, "MediaTrack*")) then return false, false end
    if not r.BR_GetMediaTrackSendInfo_Envelope then return false, false end
    local env = r.BR_GetMediaTrackSendInfo_Envelope(track, category, sendidx, env_type)
    if not env then return false, false end
    local ok, chunk = r.GetEnvelopeStateChunk(env, "", false)
    if not (ok and chunk) then return false, false end
    local act = chunk:match("ACT%s+(%d+)")
    if act == "0" then return false, false end
    local vis = chunk:match("VIS%s+1") ~= nil
    return true, vis
end

-- =========================================================================
-- SEND TOPOLOGY CORE
-- =========================================================================
package.loaded["Reflex_SendTopologyCore"] = nil
require("Reflex_SendTopologyCore")({
    r = r,
    get_insp_pinned = function() return insp_pinned end,
    get_insp_track = function() return insp_track end,
    get_external_fx_guard = function()
        return external_fx_session ~= nil or external_fx_selection_guard == true
    end,
})

-- =========================================================================
-- SEND CREATE CORE
-- =========================================================================
package.loaded["Reflex_SendCreateCore"] = nil
require("Reflex_SendCreateCore")({
    r = r,
    ctx = ctx,
    colors = C,
    script_dir = script_dir,
})

-- =========================================================================
-- ROUTE CONTROLS CORE
-- =========================================================================
package.loaded["Reflex_RouteControlsCore"] = nil
require("Reflex_RouteControlsCore")({
    r = r,
    ctx = ctx,
    colors = C,
})

-- =========================================================================
-- ROUTE MENU CORE
-- =========================================================================
package.loaded["Reflex_RouteMenuCore"] = nil
require("Reflex_RouteMenuCore")({
    r = r,
    ctx = ctx,
    colors = C,
    get_screen_h = function() return nav_screen_rect and nav_screen_rect.h end,
})

-- =========================================================================
-- ROUTE TOOLTIP CORE
-- =========================================================================
package.loaded["Reflex_RouteTooltipCore"] = nil
require("Reflex_RouteTooltipCore")({
    r = r,
    ctx = ctx,
    colors = C,
})

-- =========================================================================
-- ROUTE PANEL CORE
-- =========================================================================
package.loaded["Reflex_RoutePanelCore"] = nil
require("Reflex_RoutePanelCore")({
    r = r,
    ctx = ctx,
    colors = C,
})

InspDrawTrackBlock = function(track, bw, bh, block_idx, is_flow)
    r.ImGui_PushID(ctx, block_idx)
    local ibh = S(BASE_INSP_H)

    local hdr = InspDrawHeader(track, bw, is_flow)
    InspDrawVolumeSlider(track, hdr)
    local is_fx_collapsed = InspDrawControlsRow(track, hdr)

    local route_expanded = insp_routing_expanded[track] == true

    -- Routing opens as an overlay layer over the inspector body. It hides ENV/FX
    -- rows while open, but does not mutate their expansion state.
    if route_expanded then
        DrawRoutePanel(track, bw, hdr)
    end

    local has_fx_rows
    if route_expanded then
        has_fx_rows = InspDrawFXArea(track, hdr, true, ibh) == true
    else
        InspDrawTrackEnvelopeRows(track, hdr, bw)
        has_fx_rows = InspDrawFXArea(track, hdr, is_fx_collapsed, ibh) == true
    end
    local pad_bot_adjust = InspCardBottomPadAdjust(has_fx_rows)

    local _, card_end_cy = r.ImGui_GetCursorScreenPos(ctx)
    local cp = opt_card_boxes and S(UI.card_pad) or 0
    local cpt = opt_card_boxes and S(UI.card_pad_top) or 0
    local cpb = opt_card_boxes and (S(UI.card_pad_bot) + pad_bot_adjust) or 0
    local cx1 = hdr.trk_cx - cp
    local cy1 = hdr.trk_cy - cpt
    local cx2 = hdr.trk_cx + bw + cp
    local cy2 = card_end_cy + cpb
    insp_hdr_card_hovered[track] = r.ImGui_IsMouseHoveringRect(ctx, cx1, cy1, cx2, cy2)
    RouteDragRegisterCardTarget(track, cx1, cy1, cx2 - cx1, cy2 - cy1,
        r.ImGui_GetWindowDrawList(ctx), opt_card_boxes and S(UI.card_r) or 0)
    if r.ImGui_IsMouseClicked(ctx, 1) and not nav_rclick_consumed then
        if r.ImGui_IsMouseHoveringRect(ctx, cx1, cy1, cx2, cy2)
           and not r.ImGui_IsAnyItemHovered(ctx) then
            r.ImGui_OpenPopup(ctx, "##trknamectx")
            nav_rclick_consumed = true
        end
    end
    InspTrackContextMenu(track, hdr.track_name or "", "##trknamectx")

    r.ImGui_PopID(ctx)
    return { pad_bot_adjust = pad_bot_adjust }
end

-- Responsive inspector/SEND column measurements shared by nested and outer layouts.
ReflexInspectorColumnMinWidth = function()
    local mvw_btn = S(UI.btn_h)
    local mvw_gap = S(UI.pad_sm)
    local mvw_gg = S(UI.group_gap)
    local mvw_env = math.max(mvw_btn, r.ImGui_CalcTextSize(ctx, "ENV") + S(12))
    local mvw_content = mvw_btn + mvw_gap + mvw_btn + mvw_gg + mvw_env + mvw_gap + mvw_btn
    return math.max(mvw_content + S(UI.card_pad) * 2, InspCardMinWidth())
end

ReflexSendsColumnMinWidth = function()
    local scmw_btn = S(UI.btn_h)
    local scmw_gap = S(UI.pad_sm)
    local scmw_vol = math.max(scmw_btn, r.ImGui_CalcTextSize(ctx, "-00.0") + S(24))
    local controls_min = scmw_btn * 2 + scmw_gap + scmw_gap + scmw_vol + S(UI.card_pad) * 2
    local module_min = ReflexSendModuleInlineMinWidth and ReflexSendModuleInlineMinWidth() or 0
    return math.max(controls_min, module_min)
end

ReflexSendModuleInlineMinWidth = function()
    local btn_h = S(UI.btn_h)
    local knob_d = Round(btn_h * 1.5)
    local knob_gap = S(20 / 1.44)
    local knob_pair_w = knob_d * 2 + knob_gap
    return math.ceil(S(UI.card_pad) * 2 + knob_pair_w)
end

ReflexComputeInspectorColumnLayout = function(total_w, side_gap)
    local layout = {
        two_column = false,
        inspector_w = total_w,
        side_w = 0,
        side_gap = side_gap or 0,
    }
    total_w = math.max(0, total_w or 0)
    side_gap = math.max(0, side_gap or 0)
    local inspector_min = ReflexInspectorColumnMinWidth()
    if opt_two_column_mode == true then
        local side_min_w = ReflexTwoColumnLeftMinWidth()
        local side_max_w = ReflexTwoColumnResolvedLeftWidth()
        local side_available_w = math.max(0, total_w - side_gap - inspector_min)
        local side_w = math.min(side_max_w, math.max(side_min_w, side_available_w))
        layout.two_column = true
        layout.side_w = side_w
        layout.inspector_w = math.max(inspector_min, total_w - side_w - side_gap)
    else
        layout.inspector_w = math.max(total_w, inspector_min)
    end
    return layout
end

ReflexResolveMasterTrack = function()
    if master_track_guid and master_track_guid ~= "" then
        local custom = ExternalFxFindTrackByGuid(master_track_guid)
        if custom and r.ValidatePtr(custom, "MediaTrack*") then return custom end
    end
    local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
    if master and r.ValidatePtr(master, "MediaTrack*") then return master end
    return nil
end

ReflexVisibleMasterTrack = function()
    if opt_show_master_track ~= true then return nil end
    return ReflexResolveMasterTrack()
end

ReflexIsVisibleMasterTrack = function(track)
    local master = ReflexVisibleMasterTrack()
    return master ~= nil and track == master
end

ReflexCurrentSelectedTrack = function()
    local sel_track = r.CountSelectedTracks(0) > 0 and r.GetSelectedTrack(0, 0) or nil
    if not sel_track and r.GetMasterTrack and r.IsTrackSelected then
        local master = r.GetMasterTrack(0)
        if master and r.IsTrackSelected(master) then sel_track = master end
    end
    return sel_track
end

ReflexShouldShowMasterTrackStrip = function()
    local master = ReflexVisibleMasterTrack()
    if not master then return false end
    if insp_track and insp_track == master then return false end
    local sel_track = ReflexCurrentSelectedTrack()
    if sel_track and sel_track == master then return false end
    return true
end

ReflexTrackHeaderBlankHovered = function(track, card_sx, card_sy, outer_w)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    local px = opt_card_boxes and S(UI.card_pad) or 0
    local py_top = opt_card_boxes and S(UI.card_pad_top) or 0
    local content_x = card_sx + px
    local content_y = card_sy + py_top
    local inner_w = math.max(0, outer_w - px * 2)
    local title_font = InspGetTitleFont()
    if title_font then r.ImGui_PushFont(ctx, title_font) end
    local title_h = r.ImGui_GetTextLineHeight(ctx)
    local _, track_name = r.GetTrackName(track)
    local track_num = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
    local num_str = ReflexTrackTitleNumberString(track, track_num)
    local _, num_slot_label = TrackTitleNumberLabels(num_str)
    local num_tw = r.ImGui_CalcTextSize(ctx, num_slot_label)
    local num_name_gap = (num_tw > 0) and S(4) or 0
    local name_avail = math.max(0, inner_w - num_tw - num_name_gap)
    local display_name = track_name
    local name_tw = r.ImGui_CalcTextSize(ctx, display_name)
    if name_tw > name_avail then
        local ellipsis = "\xE2\x80\xA6"
        local ew = r.ImGui_CalcTextSize(ctx, ellipsis)
        while name_tw + ew > name_avail and #display_name > 0 do
            display_name = Utf8DropLast(display_name)
            name_tw = r.ImGui_CalcTextSize(ctx, display_name)
        end
    end
    if title_font then r.ImGui_PopFont(ctx) end
    local x1 = content_x + num_tw + num_name_gap + name_tw + S(10)
    local x2 = content_x + inner_w
    local y1 = content_y
    local y2 = content_y + title_h + S(UI.hdr_row_gap)
    if x2 <= x1 then return false end
    local mx, my = r.ImGui_GetMousePos(ctx)
    return mx >= x1 and mx <= x2 and my >= y1 and my <= y2
end

ReflexDrawMasterTrackMini = function(track, bw)
    local gap = S(UI.pad_sm)
    local btn_h = S(UI.btn_h)
    local pad_x = S(UI.card_pad)
    local pad_top = S(UI.card_pad_top)
    local pad_bot = S(UI.card_pad_bot)
    local row_gap = S(UI.hdr_row_gap)
    local meter_h = btn_h

    local title_font = InspGetTitleFont()
    local title_h
    if title_font then r.ImGui_PushFont(ctx, title_font) end
    title_h = r.ImGui_GetTextLineHeight(ctx)
    if title_font then r.ImGui_PopFont(ctx) end

    local title_row_h = math.max(title_h, btn_h)
    local card_h = pad_top + title_row_h + row_gap + meter_h + pad_bot
    local sx = r.ImGui_GetCursorPosX(ctx)
    local sy = r.ImGui_GetCursorPosY(ctx)
    local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local col_r = opt_card_boxes and S(UI.card_r) or S(UI.corner_r)
    local rcx, rcy = math.floor(cx), math.floor(cy)
    local rcx2, rcy2 = math.floor(cx + bw), math.floor(cy + card_h)
    local hov = r.ImGui_IsMouseHoveringRect(ctx, rcx, rcy, rcx2, rcy2)
    local bg = C.bg
    r.ImGui_DrawList_AddRectFilled(dl, rcx, rcy, rcx2, rcy2, bg, col_r)
    RouteDragRegisterCardTarget(track, rcx, rcy, rcx2 - rcx, rcy2 - rcy, dl, col_r)
    card_idx = card_idx + 1

    local ix = cx + pad_x
    local iy = cy + pad_top
    local inner_w = bw - pad_x * 2
    local _, track_name = r.GetTrackName(track)
    local track_num = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
    local num_str = ReflexTrackTitleNumberString(track, track_num)
    local track_color_raw = r.GetTrackColor(track)
    local num_col = track_color_raw ~= 0 and TrackColorToImGui(track_color_raw) or C.text_muted
    local is_muted = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
    local is_solo = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0
    local ms_w = btn_h
    local ms_total_w = ms_w * 2 + gap
    local ms_y = iy + Round((title_row_h - btn_h) / 2)
    local m_rect = nil
    local s_rect = nil

    if title_font then r.ImGui_PushFont(ctx, title_font) end
    local num_label, num_slot_label = TrackTitleNumberLabels(num_str)
    local num_tw = r.ImGui_CalcTextSize(ctx, num_slot_label)
    local num_name_gap = (num_tw > 0) and S(4) or 0
    local name_avail = inner_w - ms_total_w - gap * 2 - num_tw - num_name_gap
    local display_name = track_name
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
    local title_text_y = iy + Round((title_row_h - title_h) / 2)
    r.ImGui_DrawList_AddText(dl, ix, title_text_y, num_col, num_label)
    r.ImGui_DrawList_AddText(dl, ix + num_tw + num_name_gap, title_text_y, C.text, display_name)
    if title_font then r.ImGui_PopFont(ctx) end

    local ms_x = ix + inner_w - ms_total_w
    r.ImGui_SetCursorScreenPos(ctx, ms_x, ms_y)
    local m_opts = MuteOpts(is_muted)
    local _, m_clk = NavRect("M##mastermini_m", ms_w, btn_h, "M", m_opts)
    m_rect = { r.ImGui_GetItemRectMin(ctx) }
    m_rect[3], m_rect[4] = r.ImGui_GetItemRectMax(ctx)
    if m_clk then
        r.Undo_BeginBlock()
        r.SetMediaTrackInfo_Value(track, "B_MUTE", is_muted and 0 or 1)
        r.Undo_EndBlock("Reflex: Mute master strip", -1)
    end
    r.ImGui_SetCursorScreenPos(ctx, ms_x + ms_w + gap, ms_y)
    local s_opts = SoloOpts(is_solo)
    local _, s_clk = NavRect("S##mastermini_s", ms_w, btn_h, "S", s_opts)
    s_rect = { r.ImGui_GetItemRectMin(ctx) }
    s_rect[3], s_rect[4] = r.ImGui_GetItemRectMax(ctx)
    if s_clk then
        r.Undo_BeginBlock()
        r.SetMediaTrackInfo_Value(track, "I_SOLO", is_solo and 0 or 2)
        r.Undo_EndBlock("Reflex: Solo master strip", -1)
    end

    local meter_x = ix
    local meter_y = iy + title_row_h + row_gap
    local meter_w = inner_w
    local meter_r = S(4)
    local lane_gap = 1.0
    local lane_h = (meter_h - lane_gap) / 2
    local zero_mark_col = C.vol_slider_mark
    local master_meter_min_db = -60
    local master_meter_max_db = 12
    local function master_mini_db_x(db)
        local t = (math.max(master_meter_min_db, math.min(master_meter_max_db, db)) - master_meter_min_db)
            / (master_meter_max_db - master_meter_min_db)
        return meter_x + Round(meter_w * t)
    end
    local zero_x = master_mini_db_x(0)
    local low_end_x = master_mini_db_x(-24)
    local green_end_x = master_mini_db_x(-12)
    local red_start_x = zero_x
    local low_level_col = rgb(0x1485E0)
    local function draw_master_mini_segment(x1, x2, fill_right, y1, y2, col)
        local sx1 = math.max(x1, meter_x)
        local sx2 = math.min(x2, fill_right, meter_x + meter_w)
        if sx2 <= sx1 then return end
        r.ImGui_DrawList_PushClipRect(dl, sx1, y1, sx2, y2, true)
        r.ImGui_DrawList_AddRectFilled(dl, meter_x, meter_y, meter_x + meter_w, meter_y + meter_h, col, meter_r)
        r.ImGui_DrawList_PopClipRect(dl)
    end
    local function draw_master_mini_slice(x1, x2, y1, y2, col)
        if x2 <= x1 or y2 <= y1 then return end
        r.ImGui_DrawList_PushClipRect(dl, x1, y1, x2, y2, true)
        r.ImGui_DrawList_AddRectFilled(dl, meter_x, meter_y, meter_x + meter_w, meter_y + meter_h, col, meter_r)
        r.ImGui_DrawList_PopClipRect(dl)
    end
    local function draw_master_mini_lane(raw_peak, key, y1, y2)
        local cur_peak = SmoothPeak(flow_mini_peak, key, raw_peak)
        if cur_peak <= 0.00001 then return end
        local db = 20 * math.log(math.max(cur_peak, 0.00001), 10)
        local fill_right = master_mini_db_x(db)
        draw_master_mini_segment(meter_x, low_end_x, fill_right, y1, y2, low_level_col)
        draw_master_mini_segment(low_end_x, green_end_x, fill_right, y1, y2, C.green)
        draw_master_mini_segment(green_end_x, red_start_x, fill_right, y1, y2, rgb(0xE5B365))
        draw_master_mini_segment(red_start_x, meter_x + meter_w, fill_right, y1, y2, C.fx_offline_txt)
    end
    r.ImGui_DrawList_AddRectFilled(dl, meter_x, meter_y, meter_x + meter_w, meter_y + meter_h, C.vol_slider_bg, meter_r)
    draw_master_mini_slice(zero_x - 0.75, zero_x + 0.75, meter_y, meter_y + meter_h, zero_mark_col)
    draw_master_mini_lane(r.Track_GetPeakInfo(track, 0), tostring(track) .. ":masterMiniL", meter_y, meter_y + lane_h)
    draw_master_mini_lane(r.Track_GetPeakInfo(track, 1), tostring(track) .. ":masterMiniR", meter_y + lane_h + lane_gap, meter_y + meter_h)

    if is_muted then
        local fade = (C.bg & 0xFFFFFF00) | 0x70
        r.ImGui_DrawList_AddRectFilled(dl, rcx, rcy, rcx2, rcy2, fade, col_r)
        if m_rect then DrawStaticRectButton(dl, m_rect, "M", MuteOpts(true)) end
        if is_solo and s_rect then DrawStaticRectButton(dl, s_rect, "S", SoloOpts(true)) end
    end

    if hov and r.ImGui_IsMouseClicked(ctx, 0) and not r.ImGui_IsAnyItemHovered(ctx) then
        master_track_expanded = true
    end

    r.ImGui_SetCursorPos(ctx, sx, sy + card_h)
    return card_h
end

ReflexDrawMasterTrackStrip = function(bw, bh, gap_after)
    if not ReflexShouldShowMasterTrackStrip() then return 0 end
    local track = ReflexVisibleMasterTrack()
    if not track then return 0 end
    local start_y = r.ImGui_GetCursorPosY(ctx)
    local saved_env = insp_env_expanded
    local saved_ve = insp_vol_editing
    local saved_pe = insp_pan_editing
    local saved_rn = insp_rename_type
    local saved_master_rendering = master_strip_rendering
    local saved_card_idx = card_idx

    r.ImGui_PushID(ctx, "master_track_strip")
    master_strip_rendering = true
    if master_track_expanded == true then
        local strip_scx, strip_scy = r.ImGui_GetCursorScreenPos(ctx)
        InspScanTrack(track)
        insp_env_expanded = master_strip_env_expanded or {}
        insp_vol_editing = false
        insp_pan_editing = false
        insp_rename_type = nil
        local card_bw, card_state = CardBegin(bw, { est_h = master_strip_prev_h or S(140) })
        local use_bw = card_bw or bw
        local card_layout = InspDrawTrackBlock(track, use_bw, bh, 9001, false)
        card_layout = card_layout or {}
        card_layout.no_height_cache = true
        CardEnd(card_state, card_layout)
        master_strip_env_expanded = insp_env_expanded
        if ReflexTrackHeaderBlankHovered(track, strip_scx, strip_scy, bw)
           and r.ImGui_IsMouseClicked(ctx, 0) then
            master_track_expanded = false
        end
    else
        ReflexDrawMasterTrackMini(track, bw)
    end
    r.ImGui_PopID(ctx)
    card_idx = saved_card_idx

    master_strip_rendering = saved_master_rendering
    insp_env_expanded = saved_env
    insp_vol_editing = saved_ve
    insp_pan_editing = saved_pe
    insp_rename_type = saved_rn

    local used_h = r.ImGui_GetCursorPosY(ctx) - start_y
    if used_h > 0 then
        master_strip_prev_h = used_h
        gap_after = gap_after or 0
        r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + gap_after)
        used_h = used_h + gap_after
    end
    return used_h
end

-- Secondary "Selected track" card shown below pinned track when REAPER's selected
-- track differs from the inspected track. Used in both normal view and flow view.
-- Callers must gate on: insp_pinned, not insp_pin_suppress_selected, and (in flow view)
-- sel_track not already present in flow_view_chain.
-- Handles: frame-skip for height-estimation glitch, section header, state save/restore,
-- env persistence to insp_pin_sel_env, and double-click to unpin + re-source
-- (in flow view, also re-anchors the chain via FlowViewSetFocus).
InspDrawSelectedTrackCard = function(sel_track, bw, bh)
    if not sel_track or not r.ValidatePtr(sel_track, "MediaTrack*") then return end

    -- Skip first frame to let card height estimation settle
    insp_pin_sel_frames = insp_pin_sel_frames + 1
    if insp_pin_sel_frames <= 1 then return end

    r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + S(UI.edge_pad) - 2)

    -- Save state. ImGui ID scope and per-track UI state must be isolated during
    -- the secondary card's render so they don't collide with the primary card.
    -- v20.436 Stage D: dropped saved_fx2 — the FX list save/restore was solely
    -- to repair damage from the now-deleted insp_fx swap. Track FX records
    -- are now per-track-keyed (track_fx_cache); rendering sel_track doesn't
    -- disturb insp_track's records.
    local saved_env2 = insp_env_expanded
    local saved_ve2 = insp_vol_editing
    local saved_pe2 = insp_pan_editing
    local saved_rn2 = insp_rename_type

    -- Prep secondary track
    InspScanTrack(sel_track)
    insp_env_expanded = insp_pin_sel_env or {}
    insp_vol_editing = false; insp_pan_editing = false; insp_rename_type = nil

    -- ImGui ID scope prevents every widget inside from colliding with the primary
    -- card's widgets (FX rows, +/-, mute, solo, FX chain, etc.). Without this,
    -- hovering/clicking the secondary card's widgets would trigger the primary's.
    r.ImGui_PushID(ctx, "nav_secondary_card")

    -- Normal card for selected track
    local sel_scx, sel_scy = r.ImGui_GetCursorScreenPos(ctx)
    local sel_bw, sel_card = CardBegin(bw, {})
    local sel_card_layout = InspDrawTrackBlock(sel_track, sel_bw or bw, bh, 1, false)
    CardEnd(sel_card, sel_card_layout)
    insp_pin_sel_env = insp_env_expanded  -- persist env state

    -- Double-click blank area or title: unpin and make this the source.
    -- In flow view, also re-anchor the chain to this track.
    local sel_bot_sx, sel_bot_sy = r.ImGui_GetCursorScreenPos(ctx)
    if r.ImGui_IsMouseHoveringRect(ctx, sel_scx, sel_scy, sel_scx + bw, sel_bot_sy)
       and not r.ImGui_IsAnyItemHovered(ctx)
       and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
        -- v20.426: capture pre-mutation pinned+secondary state before unpinning.
        -- See line 6938 site for full rationale.
        ViewHistoryPush()
        insp_pinned = false
        insp_track = sel_track
        InspScanTrack(insp_track)
        insp_env_expanded = {}
        insp_vol_editing = false; insp_pan_editing = false
        insp_rename_type = nil
        insp_pin_sel_env = {}
        if flow_view_active then FlowViewSetFocus(sel_track) end
        ViewHistoryPush()
    end

    r.ImGui_PopID(ctx)

    -- Restore state.
    -- v20.436 Stage D: removed `insp_fx = saved_fx2` and the redundant
    -- `InspScanTrack(insp_track)` rebuild that followed it. Both existed
    -- solely to repair damage from the now-deleted insp_fx swap. The primary
    -- track's FX records were never disturbed because they live in
    -- track_fx_cache[insp_track], which the secondary card never touches.
    insp_env_expanded = saved_env2
    insp_vol_editing = saved_ve2; insp_pan_editing = saved_pe2
    insp_rename_type = saved_rn2
end

InspDrawInspector = function(bw, bh)
    if not insp_track or not r.ValidatePtr(insp_track, "MediaTrack*") then
        insp_env_cache = nil
        return
    end

    local mvw = ReflexInspectorColumnMinWidth()
    bw = math.max(bw, mvw, InspCardMinWidth())

    -- Two-column SEND/NAV layout is owned by the outer content split. The
    -- inspector keeps SENDS inline when it is asked to draw them itself.
    local sends_side = false
    local sends_side_bw = 0
    local sends_side_x = 0
    local full_bw = bw
    local insp_start_sx = r.ImGui_GetCursorPosX(ctx)
    local insp_start_sy = r.ImGui_GetCursorPosY(ctx)

    if flow_view_active and #flow_view_chain >= 1 then
        -- Per-frame refresh: detect routing changes (parent send toggled, sends added/removed)
        FlowViewRefresh()
        -- Auto-deactivate if chain is empty (anchor invalid)
        if #flow_view_chain < 1 then
            flow_view_active = false; flow_view_chain = {}; flow_view_anchor = nil; if insp_pinned then insp_pin_suppress_selected = true end
            flow_view_expanded_set = {}; flow_env_expanded = {}
            nav_scroll_target = 0
        end
    end

    if flow_view_active and #flow_view_chain >= 1 then
        local saved_env_exp = insp_env_expanded
        local saved_rects = insp_fx_rects
        local saved_vol_editing = insp_vol_editing
        local saved_pan_editing = insp_pan_editing
        local saved_rename = insp_rename_type

        -- Helper: prepare a flow chain track for rendering
        local function flow_prepare_track(chain_track)
            if not r.ValidatePtr(chain_track, "MediaTrack*") then
                FlowViewRefresh(); return false
            end
            insp_env_expanded = flow_env_expanded[chain_track] or {}
            if chain_track ~= insp_track and opt_flow_fx_default_collapsed then
                if insp_fx_collapsed[chain_track] == nil then
                    insp_fx_collapsed[chain_track] = true
                end
            end
            if chain_track ~= insp_track then
                insp_vol_editing = false; insp_pan_editing = false; insp_rename_type = nil
            else
                insp_vol_editing = saved_vol_editing; insp_pan_editing = saved_pan_editing; insp_rename_type = saved_rename
            end
            -- v20.437 Stage G: readers all go to track_fx_cache directly.
            -- We just need to ensure the cache is populated and fresh:
            --   1. InspGetFxList does count-based lazy rescan if needed
            --   2. InspRefreshFXState does GUID-reorder detection + per-frame
            --      field-freshness mutations on the cached array
            InspGetFxList(chain_track)
            if InspRefreshFXState(chain_track) then InspScanTrack(chain_track) end
            return true
        end

        -- Display-order rendering: parents (top) → focus track (bottom)
        -- Non-focus cards render as minimal (title + M/S + meter) unless expanded.
        -- v20.431: multi-expand — any subset of non-focus chain cards may be
        -- expanded simultaneously. Tracked in flow_view_expanded_set.
        -- Focus track always renders full.
        local n = #flow_view_chain
        local flow_card_gap = S(UI.edge_pad) - 2
        local flow_focus_cursor_y = nil
        local flow_visible_count = 0

        -- Drop entries for tracks no longer in the chain
        if next(flow_view_expanded_set) then
            local in_chain = {}
            for _, ct in ipairs(flow_view_chain) do in_chain[ct] = true end
            for t in pairs(flow_view_expanded_set) do
                if not in_chain[t] then flow_view_expanded_set[t] = nil end
            end
        end

        for i = 1, n do
            local chain_track = flow_view_chain[i]
            -- v20.438: flow_view_chain can be replaced mid-loop by a
            -- FlowViewSetFocus call inside a card's double-click handler.
            -- If the new chain is shorter than n, subsequent iterations get
            -- nil/stale tracks. Break cleanly — already-drawn cards will
            -- re-render correctly next frame against the new chain.
            if not chain_track or not r.ValidatePtr(chain_track, "MediaTrack*") then break end
            if not ReflexIsVisibleMasterTrack(chain_track) then
                local is_focus = (i == n)
                local is_expanded = flow_view_expanded_set[chain_track] == true
                local show_full = is_focus or is_expanded

                -- v20.439: sends are never rendered inline within the flow chain.
                -- In single-column mode they are hidden; widen the window to see
                -- the sends column on the right (sends_side path at frame end).

                -- Gap between cards (not before first)
                if flow_visible_count > 0 then
                    r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + flow_card_gap)
                end
                flow_visible_count = flow_visible_count + 1

                if is_focus then
                    flow_focus_cursor_y = r.ImGui_GetCursorPosY(ctx)
                end

                if show_full then
                -- Full card rendering (focus track or expanded non-focus)
                if not flow_prepare_track(chain_track) then break end

                local is_selected = (chain_track == insp_track)
                local flow_scx, flow_scy = r.ImGui_GetCursorScreenPos(ctx)
                local flow_est_h = card_heights_prev[card_idx + 1] or S(300)
                local card_opts = {}
                -- Clipboard paste target outline replaces source/send strokes
                -- on the specific card being hovered (v20.411). Other flow
                -- cards keep their strokes normally.
                local clip_hovers_this = FxClipIsHoveredTrack(chain_track)
                if is_focus and insp_pinned and not clip_hovers_this then
                    card_opts.stroke = C.source_stroke
                    card_opts.stroke_w = SOURCE_STROKE_W
                elseif is_selected and not clip_hovers_this then
                    card_opts.stroke = C.flow_stroke
                    card_opts.stroke_w = FLOW_STROKE_W
                elseif not is_focus then
                    local flow_hov = r.ImGui_IsMouseHoveringRect(ctx, flow_scx, flow_scy, flow_scx + bw, flow_scy + flow_est_h)
                    card_opts.bg = flow_hov and C.bg or 0x202227FF
                end

                local flow_card_bw, flow_card = CardBegin(bw, card_opts)
                local flow_use_bw = flow_card_bw or bw
                local flow_card_layout = InspDrawTrackBlock(chain_track, flow_use_bw, bh, i, true)
                CardEnd(flow_card, flow_card_layout)
                flow_env_expanded[chain_track] = insp_env_expanded

                -- Card background click: any blank space = browse/focus
                local card_bot_sx, card_bot_sy = r.ImGui_GetCursorScreenPos(ctx)
                if r.ImGui_IsMouseHoveringRect(ctx, flow_scx, flow_scy, flow_scx + bw, card_bot_sy)
                   and not r.ImGui_IsAnyItemHovered(ctx) then
                    if r.ImGui_IsMouseDoubleClicked(ctx, 0) then
                        -- v20.431: clear set on focus change — chain rebuilds.
                        flow_view_expanded_set = {}
                        -- v20.429: pre/post push so Back/Forward restore the
                        -- previous flow chain context (anchor + chain).
                        ViewHistoryPush()
                        FlowViewSetFocus(chain_track)
                        ViewHistoryPush()
                    elseif r.ImGui_IsMouseClicked(ctx, 0) and chain_track ~= insp_track then
                        -- v20.431: click an expanded non-selected card — just
                        -- browse (select), keep expansion. (Previously this
                        -- referenced an undefined `track` and inadvertently
                        -- nilled flow_view_expanded_card.)
                        r.Undo_BeginBlock()
                        r.SetOnlyTrackSelected(chain_track)
                        r.Undo_EndBlock("Reflex: Browse track", 0)
                        flow_view_browsing = true
                    elseif r.ImGui_IsMouseClicked(ctx, 0)
                       and chain_track == insp_track
                       and not is_focus
                       and ReflexTrackHeaderBlankHovered(chain_track, flow_scx, flow_scy, bw) then
                        -- v20.431: click on already-selected expanded non-focus
                        -- card → collapse it. This is the "remove from set"
                        -- gesture that lets users dismiss a persistent expansion.
                        flow_view_expanded_set[chain_track] = nil
                    end
                end
                else
                    -- Minimal card (title + M/S + meter)
                    FlowDrawMinimalCard(chain_track, bw, i)
                end
            end
        end

        -- Restore active track state
        insp_vol_editing = saved_vol_editing; insp_pan_editing = saved_pan_editing; insp_rename_type = saved_rename
        insp_env_expanded = saved_env_exp
        insp_fx_rects = saved_rects
        -- v20.436 Stage D: removed insp_fx restore (`insp_fx = afc.list else insp_fx = saved_fx`).
        -- With insp_fx gone, readers look up via track_fx_cache[track] directly.

        -- Secondary selected track stays with the flow cards; SENDS render below
        -- all associated cards when there is enough vertical room.
        if insp_pinned and not insp_pin_suppress_selected then
            local sel_track = r.CountSelectedTracks(0) > 0 and r.GetSelectedTrack(0, 0) or nil
            if sel_track and r.ValidatePtr(sel_track, "MediaTrack*")
               and sel_track ~= flow_view_anchor
               and sel_track ~= insp_track then
                local in_chain = false
                for _, ct in ipairs(flow_view_chain) do
                    if ct == sel_track then in_chain = true; break end
                end
                if not in_chain then
                    InspDrawSelectedTrackCard(sel_track, bw, bh)
                end
            end
        end

        local sends_section_start_y = r.ImGui_GetCursorPosY(ctx)
        last_inspector_cards_content_h = sends_section_start_y - insp_start_sy
        if opt_show_sends and not sends_side then
            SendsDrawSection(bw)
            last_inline_sends_content_h = r.ImGui_GetCursorPosY(ctx) - sends_section_start_y
        end

        -- Auto-scroll on first frame after activation
        if flow_view_scroll_pending then
            flow_view_scroll_pending = false
            -- Scroll so focus card starts in the lower third of the viewport
            if flow_focus_cursor_y then
                local visible_h = r.ImGui_GetWindowHeight(ctx)
                local target = math.max(0, flow_focus_cursor_y - visible_h * 0.65)
                nav_scroll_target = target
            end
        end
    else
        local card_opts = {}
        -- Pin stroke yields to clipboard paste target outline (v20.411)
        if insp_pinned and not FxClipIsHoveredTrack(insp_track) then
            card_opts.stroke = C.source_stroke
            card_opts.stroke_w = SOURCE_STROKE_W
        end
        local card_bw, card_state = CardBegin(bw, card_opts)
        local use_bw = card_bw or bw
        local card_layout = InspDrawTrackBlock(insp_track, use_bw, bh, 0, false)

        CardEnd(card_state, card_layout)

        -- Secondary selected track stays with the primary card; SENDS render below
        -- both when the inline placement fits without extra scrolling.
        if insp_pinned and not insp_pin_suppress_selected then
            local sel_track = r.CountSelectedTracks(0) > 0 and r.GetSelectedTrack(0, 0) or nil
            if sel_track and sel_track ~= insp_track and r.ValidatePtr(sel_track, "MediaTrack*") then
                InspDrawSelectedTrackCard(sel_track, bw, bh)
            end
        end

        local sends_section_start_y = r.ImGui_GetCursorPosY(ctx)
        last_inspector_cards_content_h = sends_section_start_y - insp_start_sy
        if opt_show_sends and not sends_side then
            SendsDrawSection(bw)
            last_inline_sends_content_h = r.ImGui_GetCursorPosY(ctx) - sends_section_start_y
        end
    end

    -- Side-by-side sends: render sends column to the right of inspector
    if sends_side then
        local insp_end_y = r.ImGui_GetCursorPosY(ctx)
        r.ImGui_SetCursorPos(ctx, sends_side_x, insp_start_sy)
        DrawSendsColumn(sends_side_bw)
        local sends_end_y = r.ImGui_GetCursorPosY(ctx)
        r.ImGui_SetCursorPosY(ctx, math.max(insp_end_y, sends_end_y))
    end
end


-- ── Compare controls (right-aligned on bottom row, matches control row height) ──
-- Compute total width of compare controls given a button height.
-- Layout: [A|B compound pill with 3.75 gap] [gap] [mode circle] [gap] [UI pill]
InspGetCompareControlsWidth = function(cmp_h)
    if not insp_cmp_has_any then return 0 end
    cmp_h = cmp_h or S(26)
    local cmp_gap = S(4)
    local ab_gap = S(3.75)                      -- gap between A and B halves
    local ab_pill_w = cmp_h * 2 + ab_gap        -- A|B compound pill total
    local mode_w = cmp_h                        -- mode circle
    local count_str = tostring(insp_cmp_count)
    local count_tw = r.ImGui_CalcTextSize(ctx, count_str)
    local circ_r = S(5)
    local float_pad = S(10)                     -- roomier left/right padding
    local float_inner_gap = S(5)
    local float_w = float_pad * 2 + circ_r * 2 + float_inner_gap + count_tw
    return ab_pill_w + cmp_gap + mode_w + cmp_gap + float_w
end

InspDrawCompareControls = function(bw, cmp_h_override)
    if not insp_cmp_has_any then return end
    local cmp_h = cmp_h_override or S(26)
    local cmp_gap = S(4)
    local ab_gap = S(3.75)
    local dl = r.ImGui_GetWindowDrawList(ctx)

    local sx = r.ImGui_GetCursorPosX(ctx)
    local sy = r.ImGui_GetCursorPosY(ctx)
    local scx, scy = r.ImGui_GetCursorScreenPos(ctx)

    local _, phase = r.GetProjExtState(0, CMP_EXT_SECTION, "_phase")
    if phase ~= "A" and phase ~= "B" then phase = "" end
    local _, mode_val = r.GetProjExtState(0, CMP_EXT_SECTION, "_mode")
    local is_drywet = mode_val == "drywet"
    local text_h = r.ImGui_GetTextLineHeight(ctx)

    -- Widths
    local half_w = cmp_h
    local ab_pill_w = half_w * 2 + ab_gap           -- compound A|B pill total (halves + gap)
    local mode_w = cmp_h                            -- mode = circle
    local count_str = tostring(insp_cmp_count)
    local count_tw = r.ImGui_CalcTextSize(ctx, count_str)
    local circ_r = S(5)
    local float_pad = S(10)
    local float_inner_gap = S(5)
    local float_w = float_pad * 2 + circ_r * 2 + float_inner_gap + count_tw
    local total_w = ab_pill_w + cmp_gap + mode_w + cmp_gap + float_w
    local cmp_sx = sx + bw - total_w

    -- Hover detection in layout order
    r.ImGui_SetCursorPos(ctx, cmp_sx, sy)
    r.ImGui_InvisibleButton(ctx, "##cmp_a2", half_w, cmp_h)
    local a_hov = r.ImGui_IsItemHovered(ctx)
    local a_click = r.ImGui_IsItemClicked(ctx, 0)

    r.ImGui_SetCursorPos(ctx, cmp_sx + half_w + ab_gap, sy)
    r.ImGui_InvisibleButton(ctx, "##cmp_b2", half_w, cmp_h)
    local b_hov = r.ImGui_IsItemHovered(ctx)
    local b_click = r.ImGui_IsItemClicked(ctx, 0)

    r.ImGui_SetCursorPos(ctx, cmp_sx + ab_pill_w + cmp_gap, sy)
    r.ImGui_InvisibleButton(ctx, "##cmpmode2", mode_w, cmp_h)
    local mode_hov = r.ImGui_IsItemHovered(ctx)
    local mode_click = r.ImGui_IsItemClicked(ctx, 0)

    r.ImGui_SetCursorPos(ctx, cmp_sx + ab_pill_w + cmp_gap + mode_w + cmp_gap, sy)
    r.ImGui_InvisibleButton(ctx, "##cmpfloat2", float_w, cmp_h)
    local float_hov = r.ImGui_IsItemHovered(ctx)
    local float_click = r.ImGui_IsItemClicked(ctx, 0)

    -- Screen coords for draw list
    local ab_scx = scx + bw - total_w
    local row_r = cmp_h / 2
    local ty = scy + Round((cmp_h - text_h) / 2)

    -- A half (compound pill, rounded left only)
    local a_active = (phase == "A")
    local a_bg
    if a_active then a_bg = C.cmp_a                                 -- green, matches cmp convention
    elseif a_hov then a_bg = C.btn_hover
    else a_bg = C.btn_bg end
    local a_fg = a_active and 0xFFFFFFFF or (a_hov and C.text or C.text_dim)
    r.ImGui_DrawList_AddRectFilled(dl,
        ab_scx, scy, ab_scx + half_w, scy + cmp_h,
        a_bg, row_r, r.ImGui_DrawFlags_RoundCornersLeft())
    local a_tw = r.ImGui_CalcTextSize(ctx, "A")
    r.ImGui_DrawList_AddText(dl,
        ab_scx + Round((half_w - a_tw) / 2), ty, a_fg, "A")

    -- B half (compound pill, rounded right only)
    local b_active = (phase == "B")
    local b_bg
    if b_active then b_bg = C.cmp_b                                 -- blue, matches cmp convention
    elseif b_hov then b_bg = C.btn_hover
    else b_bg = C.btn_bg end
    local b_fg = b_active and 0xFFFFFFFF or (b_hov and C.text or C.text_dim)
    local b_scx = ab_scx + half_w + ab_gap
    r.ImGui_DrawList_AddRectFilled(dl,
        b_scx, scy, b_scx + half_w, scy + cmp_h,
        b_bg, row_r, r.ImGui_DrawFlags_RoundCornersRight())
    local b_tw = r.ImGui_CalcTextSize(ctx, "B")
    r.ImGui_DrawList_AddText(dl,
        b_scx + Round((half_w - b_tw) / 2), ty, b_fg, "B")

    if a_click or b_click then
        if IsAlt(r.ImGui_GetKeyMods(ctx)) then
            InspCmpClearAll(); r.SetProjExtState(0, CMP_EXT_SECTION, "_phase", "")
        else
            InspCmpTogglePhase()
        end
    end

    -- Mode toggle (circle). :active when dry/wet mode (otherwise neutral)
    local mode_scx = ab_scx + ab_pill_w + cmp_gap
    local mode_active = is_drywet
    local mode_bg
    if mode_active then mode_bg = C.cmp_b                           -- blue active, consistent with F/R/S
    elseif mode_hov then mode_bg = C.btn_hover
    else mode_bg = C.btn_bg end
    r.ImGui_DrawList_AddRectFilled(dl,
        mode_scx, scy, mode_scx + mode_w, scy + cmp_h, mode_bg, mode_w / 2)
    do
        local cx = mode_scx + mode_w / 2
        local cy = scy + cmp_h / 2
        local col = mode_active and 0xFFFFFFFF or (mode_hov and C.text or C.text_dim)
        if is_drywet then
            r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, S(5), col, 0)
        else
            local sq = S(5)
            r.ImGui_DrawList_AddRectFilled(dl, cx - sq, cy - sq, cx + sq, cy + sq, col, S(2))
        end
    end
    if mode_click then InspCmpSwitchMode() end

    -- Float-all (pill with roomier padding). :active when any plugin UI is floating
    local float_scx = mode_scx + mode_w + cmp_gap
    local any_open = InspCmpAnyFloating()
    local float_bg
    if any_open then float_bg = C.cmp_b
    elseif float_hov then float_bg = C.btn_hover
    else float_bg = C.btn_bg end
    r.ImGui_DrawList_AddRectFilled(dl,
        float_scx, scy, float_scx + float_w, scy + cmp_h, float_bg, cmp_h / 2)
    do
        local cx_c = float_scx + float_pad + circ_r
        local cy_c = scy + cmp_h / 2
        local col = any_open and 0xFFFFFFFF or (float_hov and C.text or C.text_dim)
        if any_open then
            r.ImGui_DrawList_AddCircleFilled(dl, cx_c, cy_c, circ_r, col, 0)
        else
            r.ImGui_DrawList_AddCircle(dl, cx_c, cy_c, circ_r, col, 0, S(1))
        end
        r.ImGui_DrawList_AddText(dl,
            cx_c + circ_r + float_inner_gap,
            scy + Round((cmp_h - text_h) / 2),
            col, count_str)
    end
    if float_click then InspCmpFloatAll() end

    r.ImGui_SetCursorPos(ctx, sx, sy + cmp_h)
end

ReflexInspectorFlatContentMinWidth = function()
    local row_h = S(UI.btn_h)
    local gap = S(UI.pad_sm)
    local group_gap = S(UI.group_gap)
    local ms_w = row_h
    local pan_val_w = math.max(row_h, r.ImGui_CalcTextSize(ctx, "100R") + S(16))
    local rec_total = ms_w + gap + RecordMonitorButtonWidth(row_h) + gap * 2
    local left_end = rec_total + ms_w + gap + ms_w + gap + pan_val_w + group_gap

    local trk_env_label = "ENV"
    local trk_ew = math.max(row_h, r.ImGui_CalcTextSize(ctx, trk_env_label) + S(12))
    local right_total = trk_ew + gap + row_h
    return math.max(InspCardMinWidth(), left_end + right_total)
end

ReflexFooterContentMinWidth = function()
    local d = ReflexFooterButtonDiameter()
    local hit_w = ReflexFooterButtonHitWidth(d)
    local gap = ReflexFooterButtonGap()
    local edge = ReflexFooterEdgeGap()
    local step = hit_w + gap
    local history_w = d + step
    local right_group_w = d + step * 3
    local cmp_w = InspGetCompareControlsWidth(d)
    local middle_w = cmp_w > 0 and (gap * 4 + cmp_w) or 0
    return edge * 2 + history_w + middle_w + right_group_w
end

ReflexWindowMinWidth = function()
    local fp = PushFont(GetScaledFont and GetScaledFont())
    local inspector_w = ReflexInspectorFlatContentMinWidth() + S(UI.edge_pad) * 2
    PopFont(fp)
    local saved_scale_comp = ReflexSetBodyScaleCompensation(false)
    local footer_fp = PushFont(GetScaledFont and GetScaledFont())
    local footer_w = ReflexFooterContentMinWidth()
    PopFont(footer_fp)
    ReflexSetBodyScaleCompensation(saved_scale_comp)
    return math.max(WIN_MIN_W, inspector_w, footer_w)
end

-- =========================================================================
-- FX BROWSER ACTION
-- =========================================================================
package.loaded["Reflex_FXBrowserCore"] = nil
require("Reflex_FXBrowserCore")({
    r = r,
    get_buttons = function() return remote_buttons end,
    get_provider = function() return fx_browser_provider end,
    launch_external = ExternalFxBrowserLaunch,
})

-- =========================================================================
-- REMOTE MACRO PAD
-- =========================================================================
package.loaded["Reflex_RemoteCore"] = nil
require("Reflex_RemoteCore")({
    r = r,
    get_buttons = function() return remote_buttons end,
    set_buttons = function(buttons) remote_buttons = buttons end,
    get_undo_stack = function() return remote_undo_stack end,
    get_redo_stack = function() return remote_redo_stack end,
    set_redo_stack = function(stack) remote_redo_stack = stack end,
    get_undo_max = function() return REMOTE_UNDO_MAX end,
    get_default_height = function() return remote_default_height end,
    get_cols = function() return remote_cols end,
    get_current_page = function() return remote_current_page end,
    set_current_page = function(page) remote_current_page = page end,
    get_pages = function() return remote_pages end,
    set_pages = function(pages) remote_pages = pages end,
})

-- Icon loading and scanning (from Scripts/Tycho/Reflex/icons/)
RemoteGetIconImage = function(filename)
    if not filename or filename == "" then return nil end
    if remote_icon_cache[filename] then return remote_icon_cache[filename] end
    local path = script_dir .. "icons/" .. filename
    local f = io.open(path, "rb")
    if f then
        f:close()
        local img = r.ImGui_CreateImage(path)
        if img then
            r.ImGui_Attach(ctx, img)
            remote_icon_cache[filename] = img
            return img
        end
    end
    return nil
end

RemoteScanIcons = function()
    if remote_icon_list then return remote_icon_list end
    remote_icon_list = {}
    local dir = script_dir .. "icons/"
    -- Create directory if it doesn't exist
    r.RecursiveCreateDirectory(dir, 0)
    local i = 0
    while true do
        local file = r.EnumerateFiles(dir, i)
        if not file then break end
        if file:match("%.png$") then
            remote_icon_list[#remote_icon_list + 1] = file
        end
        i = i + 1
    end
    table.sort(remote_icon_list)
    return remote_icon_list
end

RemoteDrawButton = function(btn, idx, x, y, w, h)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local scx, scy = r.ImGui_GetCursorScreenPos(ctx)
    local rounding = S(4)

    -- Dim source button(s) during drag
    local is_drag_src = remote_drag_active and (remote_drag_idx == idx or
        (remote_selected[remote_drag_idx] and remote_selected[idx]))
    local alpha_mult = is_drag_src and 0x40 or 0xFF

    -- Background (drawn after InvisibleButton so hover state is available)
    local btn_color_idx = btn.color or 0
    local has_palette = btn_color_idx > 0 and btn_color_idx <= #remote_palette

    -- Invisible button first (need hover/active for icon state, drag, and bg color)
    r.ImGui_SetCursorPos(ctx, x, y)
    r.ImGui_InvisibleButton(ctx, "##rmt" .. idx, w, h)
    local is_clicked = r.ImGui_IsItemClicked(ctx, 0)
    local rclicked = r.ImGui_IsItemClicked(ctx, 1)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local is_active = r.ImGui_IsItemActive(ctx)
    local is_deactivated = r.ImGui_IsItemDeactivated(ctx)

    local bg
    if has_palette then
        local pal = remote_palette[btn_color_idx]
        if hovered and not is_drag_src then
            bg = ScaleColor(pal, 1.2)
        else
            bg = ScaleColor(pal, 1.0)
        end
    else
        bg = (btn.action > 0 or (btn.plugin and btn.plugin ~= "")) and C.btn_hover or C.btn_bg
    end
    if is_drag_src then bg = (bg & 0xFFFFFF00) | alpha_mult end
    r.ImGui_DrawList_AddRectFilled(dl, scx, scy, scx + w, scy + h, bg, rounding)

    -- Label colors
    local txt_col = is_drag_src and ((C.text & 0xFFFFFF00) | alpha_mult) or C.text
    local dim_col = is_drag_src and ((C.text_dim & 0xFFFFFF00) | alpha_mult) or C.text_dim

    -- Icon rendering (supports 3-state horizontal strip PNGs)
    local icon_img = RemoteGetIconImage(btn.icon)
    local has_icon = icon_img ~= nil
    local has_label = btn.name ~= "" or (not has_icon and (btn.action > 0 or (btn.plugin and btn.plugin ~= "")))

    if has_icon then
        local iw, ih = r.ImGui_Image_GetSize(icon_img)
        -- Detect multi-state: width > height * 2 = 3-state horizontal strip
        local is_multi = iw > ih * 2
        local frame_w = is_multi and (iw / 3) or iw
        -- UV coords for current state
        local uv_x0, uv_x1 = 0, 1
        if is_multi then
            if is_active and not is_drag_src then
                uv_x0 = 2 / 3; uv_x1 = 1
            elseif hovered and not is_drag_src then
                uv_x0 = 1 / 3; uv_x1 = 2 / 3
            else
                uv_x0 = 0; uv_x1 = 1 / 3
            end
        end
        -- Scale single frame to fit button (no label offset — icon only)
        local max_icon = math.min(w - S(8), h - S(8))
        local scale = math.min(1, max_icon / math.max(frame_w, ih)) * 0.74
        local sw, sh = math.floor(frame_w * scale), math.floor(ih * scale)
        local ix = scx + Round((w - sw) / 2)
        local iy = scy + Round((h - sh) / 2)
        -- Tint to text color (icons should be white-on-transparent for correct tinting)
        local tint = (txt_col & 0xFFFFFF00) | (is_drag_src and 0x40 or 0xFF)
        r.ImGui_DrawList_AddImage(dl, icon_img, ix, iy, ix + sw, iy + sh, uv_x0, 0, uv_x1, 1, tint)
    elseif btn.name ~= "" then
        local reg_font = GetScaledFont()
        if reg_font then r.ImGui_PushFont(ctx, reg_font) end
        local pad = S(5)
        local avail = w - pad * 2
        local is_slim = (btn.height or 1) == 1
        local tw = r.ImGui_CalcTextSize(ctx, btn.name)
        if tw <= avail or is_slim then
            -- Single line (clip with ellipsis for slim)
            local display = btn.name
            if tw > avail then
                local ellipsis = "\xE2\x80\xA6"
                local ew = r.ImGui_CalcTextSize(ctx, ellipsis)
                while r.ImGui_CalcTextSize(ctx, display) + ew > avail and #display > 1 do
                    display = Utf8DropLast(display)
                end
                display = display .. ellipsis
                tw = r.ImGui_CalcTextSize(ctx, display)
            end
            local th = r.ImGui_GetTextLineHeight(ctx)
            r.ImGui_DrawList_AddText(dl, scx + Round((w - tw) / 2), scy + Round((h - th) / 2), txt_col, display)
        else
            -- Word wrap into lines
            local lines = {}
            local line = ""
            for word in btn.name:gmatch("%S+") do
                local test = line == "" and word or (line .. " " .. word)
                local test_w = r.ImGui_CalcTextSize(ctx, test)
                if test_w > avail and line ~= "" then
                    lines[#lines + 1] = line
                    line = word
                else
                    line = test
                end
            end
            if line ~= "" then lines[#lines + 1] = line end
            local line_h = r.ImGui_GetTextLineHeight(ctx)
            local line_gap = S(2)
            local total_h = #lines * line_h + (#lines - 1) * line_gap
            local start_y = scy + Round((h - total_h) / 2)
            for li, ln in ipairs(lines) do
                local lw = r.ImGui_CalcTextSize(ctx, ln)
                local lx = scx + Round((w - lw) / 2)
                local ly = start_y + (li - 1) * (line_h + line_gap)
                r.ImGui_DrawList_AddText(dl, lx, ly, txt_col, ln)
            end
        end
        if reg_font then r.ImGui_PopFont(ctx) end
    elseif btn.plugin and btn.plugin ~= "" then
        local pname = FxBrowserCleanName(btn.plugin)
        local reg_font = GetScaledFont()
        if reg_font then r.ImGui_PushFont(ctx, reg_font) end
        local pad = S(5)
        local avail = w - pad * 2
        local tw = r.ImGui_CalcTextSize(ctx, pname)
        local display = pname
        if tw > avail then
            local ellipsis = "\xE2\x80\xA6"
            local ew = r.ImGui_CalcTextSize(ctx, ellipsis)
            while r.ImGui_CalcTextSize(ctx, display) + ew > avail and #display > 1 do
                display = Utf8DropLast(display)
            end
            display = display .. ellipsis
            tw = r.ImGui_CalcTextSize(ctx, display)
        end
        local th = r.ImGui_GetTextLineHeight(ctx)
        r.ImGui_DrawList_AddText(dl, scx + Round((w - tw) / 2), scy + Round((h - th) / 2), dim_col, display)
        if reg_font then r.ImGui_PopFont(ctx) end
    elseif btn.action > 0 then
        local act_name = r.CF_GetCommandText and r.CF_GetCommandText(0, btn.action) or nil
        if act_name and act_name ~= "" then
            local reg_font = GetScaledFont()
            if reg_font then r.ImGui_PushFont(ctx, reg_font) end
            local pad = S(5)
            local avail = w - pad * 2
            local is_slim = (btn.height or 1) == 1
            local tw = r.ImGui_CalcTextSize(ctx, act_name)
            if tw <= avail or is_slim then
                local display = act_name
                if tw > avail then
                    local ellipsis = "\xE2\x80\xA6"
                    local ew = r.ImGui_CalcTextSize(ctx, ellipsis)
                    while r.ImGui_CalcTextSize(ctx, display) + ew > avail and #display > 1 do
                        display = Utf8DropLast(display)
                    end
                    display = display .. ellipsis
                    tw = r.ImGui_CalcTextSize(ctx, display)
                end
                local th = r.ImGui_GetTextLineHeight(ctx)
                r.ImGui_DrawList_AddText(dl, scx + Round((w - tw) / 2), scy + Round((h - th) / 2), dim_col, display)
            else
                local lines = {}
                local line = ""
                for word in act_name:gmatch("%S+") do
                    local test = line == "" and word or (line .. " " .. word)
                    local test_w = r.ImGui_CalcTextSize(ctx, test)
                    if test_w > avail and line ~= "" then
                        lines[#lines + 1] = line
                        line = word
                    else
                        line = test
                    end
                end
                if line ~= "" then lines[#lines + 1] = line end
                local line_h = r.ImGui_GetTextLineHeight(ctx)
                local line_gap = S(2)
                local total_h = #lines * line_h + (#lines - 1) * line_gap
                local start_y = scy + Round((h - total_h) / 2)
                for li, ln in ipairs(lines) do
                    local lw = r.ImGui_CalcTextSize(ctx, ln)
                    local lx = scx + Round((w - lw) / 2)
                    local ly = start_y + (li - 1) * (line_h + line_gap)
                    r.ImGui_DrawList_AddText(dl, lx, ly, dim_col, ln)
                end
            end
            if reg_font then r.ImGui_PopFont(ctx) end
        end
    end

    -- Drag initiation (only without shift or alt)
    local mods_click = r.ImGui_GetKeyMods(ctx)
    local is_shift_click = is_clicked and IsShift(mods_click)
    local is_alt_click = is_clicked and IsAlt(mods_click)
    if is_clicked and not remote_drag_active and not is_shift_click and not is_alt_click then
        remote_drag_idx = idx
        local mx, my = r.ImGui_GetMousePos(ctx)
        remote_drag_sx, remote_drag_sy = mx, my
    end
    if is_active and remote_drag_idx == idx and not remote_drag_active then
        local mx, my = r.ImGui_GetMousePos(ctx)
        local dx, dy = mx - remote_drag_sx, my - remote_drag_sy
        if math.sqrt(dx * dx + dy * dy) > S(12) then
            remote_drag_active = true
        end
    end

    -- Shift+click: toggle selection
    if is_shift_click then
        if remote_selected[idx] then remote_selected[idx] = nil
        else remote_selected[idx] = true end
    end

    -- Selection outline
    local is_selected = remote_selected[idx] == true
    if is_selected then
        r.ImGui_DrawList_AddRect(dl, scx - S(1), scy - S(1), scx + w + S(1), scy + h + S(1),
            0x3B82F6CC, rounding + S(1), 0, S(2))
    end

    -- Hover highlight (not during drag, not selected, non-palette only)
    if hovered and not remote_drag_active and not is_selected and not has_palette then
        r.ImGui_DrawList_AddRectFilled(dl, scx, scy, scx + w, scy + h, 0xFFFFFF1A, rounding)
    end

    -- Accept drag-drop from FX browser
    if r.ImGui_BeginDragDropTarget(ctx) then
        local payload = r.ImGui_AcceptDragDropPayload(ctx, "FX_PLUGIN")
        if payload then
            FxBrowserAssign(idx, payload)
        end
        r.ImGui_EndDragDropTarget(ctx)
    end

    -- Left click: run action (only if no drag occurred and no shift)
    if is_deactivated and remote_drag_idx == idx and not remote_drag_active then
        if btn.plugin and btn.plugin ~= "" then
            local trk = r.GetSelectedTrack(0, 0)
            if trk then
                r.Undo_BeginBlock()
                r.TrackFX_AddByName(trk, btn.plugin, false, -1)
                r.Undo_EndBlock("Reflex: Insert " .. FxBrowserCleanName(btn.plugin), -1)
            end
        elseif btn.action > 0 then r.Main_OnCommand(btn.action, 0) end
    end

    -- Opt+click: remove button
    if is_alt_click then
        RemoteRemoveButton(idx)
    end

    return rclicked, scx, scy, w, h
end

RemoteRenamePopup = function()
    if not remote_prompt_target then return end
    local btn = remote_buttons[remote_prompt_target]
    if not btn then remote_prompt_target = nil; return end

    local center_x, center_y = r.ImGui_Viewport_GetCenter(r.ImGui_GetWindowViewport(ctx))
    r.ImGui_SetNextWindowPos(ctx, center_x, center_y, r.ImGui_Cond_Appearing(), 0.5, 0.5)
    r.ImGui_SetNextWindowSize(ctx, S(300), 0, r.ImGui_Cond_Appearing())
end

RemoteDrawSection = function(bw)
    local cols = remote_cols
    local gap = S(6)
    local btn_h = S(36)
    local cell_w = math.floor((bw - gap * (cols - 1)) / cols)

    -- Process action prompt
    if remote_prompt_active and remote_prompt_target then
        local result = r.PromptForAction and r.PromptForAction(0, 0, 0) or -1
        if result > 0 then
            RemotePushUndo()
            remote_buttons[remote_prompt_target].action = result
            remote_prompt_active = false
            if r.PromptForAction then r.PromptForAction(-1, 0, 0) end
            -- Immediately prompt for name with action name pre-filled and selected
            local default_name = r.CF_GetCommandText and r.CF_GetCommandText(0, result) or ""
            local retval, new_name = r.GetUserInputs("Name Button", 1, "Name:,extrawidth=120", default_name)
            if retval then remote_buttons[remote_prompt_target].name = new_name end
            RemoteSaveButtons()
        elseif result < 0 then
            remote_prompt_active = false
            if r.PromptForAction then r.PromptForAction(-1, 0, 0) end
        end
    end

    -- Lay out buttons into rows — auto-fill gaps with empty cells
    -- Pre-pass: insert empty buttons wherever a wrap leaves dead space (current page only)
    local needs_save = false
    local pi, pcol = 1, 0
    while pi <= #remote_buttons do
        local btn = remote_buttons[pi]
        if (btn.page or 1) ~= remote_current_page then pi = pi + 1
        else
        local btn_cols = math.min(btn.width, cols - pcol)
        if btn_cols < btn.width and pcol > 0 then
            -- This button will wrap — fill remaining columns with empties
            while pcol < cols do
                table.insert(remote_buttons, pi, { action = 0, name = "", width = 1, height = 1, icon = "", color = 0, plugin = "", page = remote_current_page })
                needs_save = true
                pi = pi + 1
                pcol = pcol + 1
            end
            pcol = 0
        else
            pcol = pcol + btn_cols
            if pcol >= cols then pcol = 0 end
            pi = pi + 1
        end
        end -- page filter
    end
    if needs_save then RemoteSaveButtons() end

    local rows = {}
    local cur_row = {}
    local col = 0
    for i, btn in ipairs(remote_buttons) do
        if (btn.page or 1) ~= remote_current_page then goto continue_row end
        local btn_cols = math.min(btn.width, cols - col)
        if btn_cols < btn.width and col > 0 then
            rows[#rows + 1] = cur_row; cur_row = {}; col = 0
            btn_cols = math.min(btn.width, cols)
        end
        cur_row[#cur_row + 1] = { idx = i, btn = btn, col = col, btn_cols = btn_cols }
        col = col + btn_cols
        if col >= cols then
            rows[#rows + 1] = cur_row; cur_row = {}; col = 0
        end
        ::continue_row::
    end
    if #cur_row > 0 then rows[#rows + 1] = cur_row end

    -- Page tabs
    RemoteDrawPageTabs(bw)

    -- Render rows
    local start_x = r.ImGui_GetCursorPosX(ctx)
    local row_y = r.ImGui_GetCursorPosY(ctx)
    local ctx_menu_idx = nil
    remote_btn_rects = {}

    for _, row in ipairs(rows) do
        -- Row height: max height mode in the row
        -- 1=slim (btn_h), 2=half (btn_h*2+gap), 3=full (cell_w = square)
        local max_h = 1
        for _, item in ipairs(row) do
            local h = item.btn.height or 1
            if h > max_h then max_h = h end
        end
        local row_h
        if max_h == 3 then row_h = cell_w
        elseif max_h == 2 then row_h = btn_h * 2 + gap
        else row_h = btn_h end

        for _, item in ipairs(row) do
            local btn_w = cell_w * item.btn_cols + gap * (item.btn_cols - 1)
            local btn_x = start_x + item.col * (cell_w + gap)

            r.ImGui_SetCursorPos(ctx, btn_x, row_y)
            r.ImGui_PushID(ctx, 8000 + item.idx)
            local rclicked, bsx, bsy, bsw, bsh = RemoteDrawButton(item.btn, item.idx, btn_x, row_y, btn_w, row_h)
            remote_btn_rects[item.idx] = { x = bsx, y = bsy, w = bsw, h = bsh }
            if rclicked and not remote_drag_active then ctx_menu_idx = item.idx end
            r.ImGui_PopID(ctx)
        end

        row_y = row_y + row_h + gap
    end
    r.ImGui_SetCursorPos(ctx, start_x, row_y)
    -- Windows ReaImGui requires a submitted item after manual cursor extension.
    r.ImGui_Dummy(ctx, 1, 1)

    -- Context menu
    if ctx_menu_idx then
        remote_ctx_idx = ctx_menu_idx
        r.ImGui_OpenPopup(ctx, "##rmt_ctx")
    end
    if r.ImGui_BeginPopup(ctx, "##rmt_ctx") then
        local idx = remote_ctx_idx
        local btn = idx and remote_buttons[idx]
        local has_sel = false
        local sel_count = 0
        for _ in pairs(remote_selected) do has_sel = true; sel_count = sel_count + 1 end

        if btn then
            -- ── Action / Rename / Icon ──
            if r.ImGui_MenuItem(ctx, btn.action > 0 and "Change Action" or "Choose Action") then
                remote_prompt_target = idx
                remote_prompt_active = true
                if r.PromptForAction then r.PromptForAction(1, 0, 0) end
            end
            if btn.action > 0 then
                if r.ImGui_MenuItem(ctx, "Remove Action") then
                    RemotePushUndo(); btn.action = 0; btn.name = ""; RemoteSaveButtons()
                end
            end
            if r.ImGui_MenuItem(ctx, "Add Plugin") then
                fx_browser_target_btn = idx
                fx_browser_open = true
                fx_browser_search = ""
                fx_browser_focus_search = true
            end
            if btn.plugin and btn.plugin ~= "" then
                if r.ImGui_MenuItem(ctx, "Remove Plugin") then
                    RemotePushUndo(); btn.plugin = ""; btn.name = ""; RemoteSaveButtons()
                end
            end
            if r.ImGui_MenuItem(ctx, "Rename") then
                local retval, new_name = r.GetUserInputs("Rename Button", 1, "Name:", btn.name)
                if retval then RemotePushUndo(); btn.name = new_name; RemoteSaveButtons() end
            end
            if r.ImGui_MenuItem(ctx, "Choose Icon") then
                remote_icon_picker_idx = idx
                remote_icon_search = ""
            end
            if btn.icon and btn.icon ~= "" then
                if r.ImGui_MenuItem(ctx, "Remove Icon") then
                    RemotePushUndo(); btn.icon = ""; RemoteSaveButtons()
                end
            end

            -- ── Color swatches ──
            r.ImGui_Separator(ctx)
            local swatch_r = S(8)
            local swatch_gap = S(6)
            local swatch_y_pad = S(4)
            r.ImGui_Dummy(ctx, 0, swatch_y_pad)
            local sw_sx = r.ImGui_GetCursorPosX(ctx)
            local sw_sy = r.ImGui_GetCursorPosY(ctx)
            local sw_cx, sw_cy = r.ImGui_GetCursorScreenPos(ctx)
            local sw_dl = r.ImGui_GetWindowDrawList(ctx)
            local cur_color = btn.color or 0
            local none_cx = sw_cx + swatch_r + S(4)
            local none_cy = sw_cy + swatch_r
            r.ImGui_SetCursorPos(ctx, sw_sx + S(4), sw_sy)
            if r.ImGui_InvisibleButton(ctx, "##cNone", swatch_r * 2, swatch_r * 2) then
                RemotePushUndo()
                if has_sel then for si in pairs(remote_selected) do if remote_buttons[si] then remote_buttons[si].color = 0 end end
                else btn.color = 0 end
                RemoteSaveButtons()
            end
            if cur_color == 0 then
                r.ImGui_DrawList_AddCircleFilled(sw_dl, none_cx, none_cy, swatch_r, C.text_muted, 0)
            else
                r.ImGui_DrawList_AddCircle(sw_dl, none_cx, none_cy, swatch_r, C.text_muted, 0, S(1.5))
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_DrawList_AddCircle(sw_dl, none_cx, none_cy, swatch_r + S(1), 0xFFFFFF60, 0, S(1))
            end
            for ci = 1, #remote_palette do
                r.ImGui_SameLine(ctx, 0, swatch_gap)
                local ci_sx = r.ImGui_GetCursorPosX(ctx)
                local ci_cx, ci_cy = r.ImGui_GetCursorScreenPos(ctx)
                local dot_cx = ci_cx + swatch_r
                local dot_cy = ci_cy + swatch_r
                r.ImGui_SetCursorPos(ctx, ci_sx, sw_sy)
                if r.ImGui_InvisibleButton(ctx, "##c" .. ci, swatch_r * 2, swatch_r * 2) then
                    RemotePushUndo()
                    if has_sel then for si in pairs(remote_selected) do if remote_buttons[si] then remote_buttons[si].color = ci end end
                    else btn.color = ci end
                    RemoteSaveButtons()
                end
                r.ImGui_DrawList_AddCircleFilled(sw_dl, dot_cx, dot_cy, swatch_r, remote_palette[ci], 0)
                if cur_color == ci then
                    r.ImGui_DrawList_AddCircle(sw_dl, dot_cx, dot_cy, swatch_r + S(2), 0xFFFFFFCC, 0, S(1.5))
                elseif r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_DrawList_AddCircle(sw_dl, dot_cx, dot_cy, swatch_r + S(1), 0xFFFFFF60, 0, S(1))
                end
            end
            r.ImGui_Dummy(ctx, 0, swatch_y_pad)
            -- Track color options
            local sel_track_for_color = r.CountSelectedTracks(0) > 0 and r.GetSelectedTrack(0, 0) or nil
            if sel_track_for_color then
                local tc = r.GetTrackColor(sel_track_for_color)
                if tc ~= 0 then
                    local tc_rgba = TrackColorToImGui(tc)
                    if r.ImGui_MenuItem(ctx, "Get Color from Track") then
                        local ci = RemoteAddPaletteColor(tc_rgba)
                        RemotePushUndo()
                        if has_sel then for si in pairs(remote_selected) do if remote_buttons[si] then remote_buttons[si].color = ci end end
                        else btn.color = ci end
                        RemoteSaveButtons()
                    end
                    if r.ImGui_MenuItem(ctx, "Add Color from Track") then
                        RemoteAddPaletteColor(tc_rgba)
                    end
                end
            end

            -- ── Width submenu ──
            r.ImGui_Separator(ctx)
            if r.ImGui_BeginMenu(ctx, "Width") then
                local function WidthRadio(label, w)
                    local sel = btn.width == w
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), sel and C.green or C.text_dim)
                    if r.ImGui_MenuItem(ctx, (sel and "\xE2\x97\x8F " or "\xE2\x97\x8B ") .. label) then
                        RemotePushUndo()
                        if has_sel then for si in pairs(remote_selected) do if remote_buttons[si] then remote_buttons[si].width = w end end
                        else btn.width = w end
                        RemoteSaveButtons()
                    end
                    r.ImGui_PopStyleColor(ctx, 1)
                end
                WidthRadio("Single", 1); WidthRadio("Double", 2); WidthRadio("Triple", 3)
                WidthRadio("Quad", 4); WidthRadio("Penta", 5); WidthRadio("Hex", 6)
                r.ImGui_EndMenu(ctx)
            end

            -- ── Height submenu ──
            if r.ImGui_BeginMenu(ctx, "Height") then
                local cur_h = btn.height or 1
                local function HeightRadio(label, h)
                    local sel = cur_h == h
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), sel and C.green or C.text_dim)
                    if r.ImGui_MenuItem(ctx, (sel and "\xE2\x97\x8F " or "\xE2\x97\x8B ") .. label) then
                        RemotePushUndo()
                        if has_sel then for si in pairs(remote_selected) do if remote_buttons[si] then remote_buttons[si].height = h end end
                        else btn.height = h end
                        RemoteSaveButtons()
                    end
                    r.ImGui_PopStyleColor(ctx, 1)
                end
                HeightRadio("Full", 3); HeightRadio("Half", 2); HeightRadio("Slim", 1)
                r.ImGui_EndMenu(ctx)
            end

            -- ── Duplicate / Copy / Cut / Paste / Remove ──
            r.ImGui_Separator(ctx)
            if r.ImGui_MenuItem(ctx, "Duplicate") then
                RemotePushUndo()
                local dupes = {}
                if has_sel then
                    local sorted = {}
                    for si in pairs(remote_selected) do sorted[#sorted + 1] = si end
                    table.sort(sorted)
                    for _, si in ipairs(sorted) do
                        local sb = remote_buttons[si]
                        if sb then dupes[#dupes + 1] = { action = sb.action, name = sb.name, width = sb.width, height = sb.height or 1, icon = sb.icon or "", color = sb.color or 0, plugin = sb.plugin or "", page = sb.page or 1 } end
                    end
                    RemoteInsertAt(sorted[#sorted] + 1, dupes)
                else
                    dupes[1] = { action = btn.action, name = btn.name, width = btn.width, height = btn.height or 1, icon = btn.icon or "", color = btn.color or 0, plugin = btn.plugin or "", page = btn.page or 1 }
                    RemoteInsertAt(idx + 1, dupes)
                end
                RemoteSaveButtons()
            end
            if r.ImGui_MenuItem(ctx, has_sel and ("Copy (" .. sel_count .. ")") or "Copy") then
                remote_clipboard = {}
                if has_sel then
                    local sorted = {}
                    for si in pairs(remote_selected) do sorted[#sorted + 1] = si end
                    table.sort(sorted)
                    for _, si in ipairs(sorted) do
                        local sb = remote_buttons[si]
                        if sb then remote_clipboard[#remote_clipboard + 1] = { action = sb.action, name = sb.name, width = sb.width, height = sb.height or 1, icon = sb.icon or "", color = sb.color or 0, plugin = sb.plugin or "", page = sb.page or 1 } end
                    end
                else
                    remote_clipboard[1] = { action = btn.action, name = btn.name, width = btn.width, height = btn.height or 1, icon = btn.icon or "", color = btn.color or 0, plugin = btn.plugin or "", page = btn.page or 1 }
                end
            end
            if r.ImGui_MenuItem(ctx, has_sel and ("Cut (" .. sel_count .. ")") or "Cut") then
                remote_clipboard = {}
                RemotePushUndo()
                if has_sel then
                    local sorted = {}
                    for si in pairs(remote_selected) do sorted[#sorted + 1] = si end
                    table.sort(sorted)
                    for _, si in ipairs(sorted) do
                        local sb = remote_buttons[si]
                        if sb then remote_clipboard[#remote_clipboard + 1] = { action = sb.action, name = sb.name, width = sb.width, height = sb.height or 1, icon = sb.icon or "", color = sb.color or 0, plugin = sb.plugin or "", page = sb.page or 1 } end
                    end
                    table.sort(sorted, function(a, b) return a > b end)
                    for _, si in ipairs(sorted) do table.remove(remote_buttons, si) end
                    remote_selected = {}
                else
                    remote_clipboard[1] = { action = btn.action, name = btn.name, width = btn.width, height = btn.height or 1, icon = btn.icon or "", color = btn.color or 0, plugin = btn.plugin or "", page = btn.page or 1 }
                    table.remove(remote_buttons, idx)
                end
                RemoteSaveButtons()
            end
            if #remote_clipboard > 0 then
                if r.ImGui_MenuItem(ctx, "Paste (" .. #remote_clipboard .. ")") then
                    RemotePushUndo()
                    RemoteInsertAt(idx, remote_clipboard)
                    RemoteSaveButtons()
                end
            end
            if has_sel then
                if r.ImGui_MenuItem(ctx, "Delete Selected (" .. sel_count .. ")") then
                    RemotePushUndo()
                    local sorted = {}
                    for si in pairs(remote_selected) do sorted[#sorted + 1] = si end
                    table.sort(sorted, function(a, b) return a > b end)
                    for _, si in ipairs(sorted) do table.remove(remote_buttons, si) end
                    remote_selected = {}
                    RemoteSaveButtons()
                end
                if r.ImGui_MenuItem(ctx, "Clear Selection") then remote_selected = {} end
            else
                if r.ImGui_MenuItem(ctx, "Remove Button") then RemoteRemoveButton(idx) end
                -- Close Gap: remove contiguous empty cells
                if btn.action == 0 then
                    -- Count contiguous empty cells from idx
                    local gap_end = idx
                    while gap_end <= #remote_buttons and remote_buttons[gap_end].action == 0 do
                        gap_end = gap_end + 1
                    end
                    local gap_count = gap_end - idx
                    if gap_count > 0 then
                        if r.ImGui_MenuItem(ctx, "Close Gap (" .. gap_count .. ")") then
                            RemotePushUndo()
                            for i = 1, gap_count do table.remove(remote_buttons, idx) end
                            RemoteSaveButtons()
                        end
                    end
                end
            end
        end

        -- ── Global options ──
        r.ImGui_Separator(ctx)
        if r.ImGui_MenuItem(ctx, "Add Button") then RemoteAddButton() end
        if r.ImGui_MenuItem(ctx, "Add Row") then RemoteAddRow() end
        if r.ImGui_MenuItem(ctx, "Add Page") then RemoteAddPage() end

        -- ── Grid submenu ──
        if r.ImGui_BeginMenu(ctx, "Grid") then
            for gc = 4, 6 do
                local sel = remote_cols == gc
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), sel and C.green or C.text_dim)
                if r.ImGui_MenuItem(ctx, (sel and "\xE2\x97\x8F " or "\xE2\x97\x8B ") .. gc .. " columns") then
                    remote_cols = gc; SavePref("remote_cols", gc)
                end
                r.ImGui_PopStyleColor(ctx, 1)
            end
            r.ImGui_EndMenu(ctx)
        end

        -- ── Default Height submenu ──
        if r.ImGui_BeginMenu(ctx, "Default Height") then
            local dh_names = { [3] = "Full", [2] = "Half", [1] = "Slim" }
            for _, dh in ipairs({3, 2, 1}) do
                local sel = remote_default_height == dh
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), sel and C.green or C.text_dim)
                if r.ImGui_MenuItem(ctx, (sel and "\xE2\x97\x8F " or "\xE2\x97\x8B ") .. dh_names[dh]) then
                    remote_default_height = dh; SavePref("remote_default_height", dh)
                end
                r.ImGui_PopStyleColor(ctx, 1)
            end
            r.ImGui_EndMenu(ctx)
        end

        r.ImGui_Separator(ctx)
        if remote_popped_out then
            if r.ImGui_MenuItem(ctx, "Dock") then
                remote_popped_out = false; SavePref("remote_popped_out", false)
            end
        else
            if r.ImGui_MenuItem(ctx, "Pop Out") then
                remote_popped_out = true; SavePref("remote_popped_out", true)
                remote_pop_initialized = false
            end
        end
        r.ImGui_Separator(ctx)
        if #remote_undo_stack > 0 then
            if r.ImGui_MenuItem(ctx, "Undo") then RemoteUndo() end
        end
        if #remote_redo_stack > 0 then
            if r.ImGui_MenuItem(ctx, "Redo") then RemoteRedo() end
        end
        r.ImGui_EndPopup(ctx)
    end

    -- Icon picker popup (text list — only assigned icons are loaded as images)
    if remote_icon_picker_idx then
        r.ImGui_OpenPopup(ctx, "##icon_picker")
        remote_icon_picker_open = remote_icon_picker_idx
        remote_icon_picker_idx = nil
    end
    if r.ImGui_BeginPopup(ctx, "##icon_picker") then
        local icons = RemoteScanIcons()
        -- Search filter
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.fx_ctrl_bg)
        r.ImGui_SetNextItemWidth(ctx, S(260))
        local _, new_search = r.ImGui_InputTextWithHint(ctx, "##iconsearch", "Search icons...", remote_icon_search)
        remote_icon_search = new_search
        r.ImGui_PopStyleColor(ctx, 1)
        r.ImGui_SameLine(ctx)
        if r.ImGui_SmallButton(ctx, "\xE2\x86\xBB") then remote_icon_list = nil end
        if r.ImGui_IsItemHovered(ctx) and opt_tooltips then TipDirect("Rescan") end
        r.ImGui_SameLine(ctx)
        if r.ImGui_SmallButton(ctx, "Open") then
            local dir = script_dir .. "icons/"
            r.RecursiveCreateDirectory(dir, 0)
            os.execute('open "' .. dir .. '"')
        end
        if r.ImGui_IsItemHovered(ctx) and opt_tooltips then TipDirect("Show in Finder") end
        r.ImGui_Spacing(ctx)
        if #icons == 0 then
            r.ImGui_TextColored(ctx, C.text_dim, "Drop PNGs into Reflex/icons/")
            r.ImGui_Spacing(ctx)
        end
        -- Visual icon grid
        local icon_sz = S(36)
        local icon_gap = S(4)
        local grid_w = S(280)
        local icons_per_row = math.max(1, math.floor((grid_w + icon_gap) / (icon_sz + icon_gap)))
        r.ImGui_BeginChild(ctx, "##iconsgrid", grid_w, #icons > 0 and S(300) or S(1))
        local filter = remote_icon_search:lower()
        local col_i = 0
        for _, filename in ipairs(icons) do
            if filter == "" or filename:lower():find(filter, 1, true) then
                local img = RemoteGetIconImage(filename)
                if img then
                    if col_i > 0 then r.ImGui_SameLine(ctx, 0, icon_gap) end
                    r.ImGui_PushID(ctx, filename)
                    local scx_i, scy_i = r.ImGui_GetCursorScreenPos(ctx)
                    if r.ImGui_InvisibleButton(ctx, "##ic", icon_sz, icon_sz) then
                        local pi = remote_icon_picker_open
                        if pi and remote_buttons[pi] then
                            RemotePushUndo()
                            remote_buttons[pi].icon = filename
                            RemoteSaveButtons()
                        end
                        remote_icon_picker_open = nil
                        r.ImGui_CloseCurrentPopup(ctx)
                    end
                    local dl_i = r.ImGui_GetWindowDrawList(ctx)
                    -- Always show background so dark icons are visible
                    r.ImGui_DrawList_AddRectFilled(dl_i, scx_i, scy_i, scx_i + icon_sz, scy_i + icon_sz, 0x404040FF, S(3))
                    if r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_DrawList_AddRectFilled(dl_i, scx_i, scy_i, scx_i + icon_sz, scy_i + icon_sz, C.btn_hover, S(3))
                    end
                    -- Show first frame only for multi-state icons
                    local iw, ih = r.ImGui_Image_GetSize(img)
                    local uv_x1 = (iw > ih * 2) and (1 / 3) or 1
                    local pad = S(4)
                    r.ImGui_DrawList_AddImage(dl_i, img, scx_i + pad, scy_i + pad,
                        scx_i + icon_sz - pad, scy_i + icon_sz - pad, 0, 0, uv_x1, 1, 0xFFFFFFFF)
                    if r.ImGui_IsItemHovered(ctx) then
                        TipDirect((filename:gsub("%.png$", "")))
                    end
                    r.ImGui_PopID(ctx)
                    col_i = col_i + 1
                    if col_i >= icons_per_row then col_i = 0 end
                else
                    -- Fallback text for icons that failed to load
                    local display = (filename:gsub("%.png$", ""))
                    if r.ImGui_Selectable(ctx, display .. "##" .. filename) then
                        local pi = remote_icon_picker_open
                        if pi and remote_buttons[pi] then
                            RemotePushUndo()
                            remote_buttons[pi].icon = filename
                            RemoteSaveButtons()
                        end
                        remote_icon_picker_open = nil
                        r.ImGui_CloseCurrentPopup(ctx)
                    end
                    col_i = 0
                end
            end
        end
        r.ImGui_EndChild(ctx)
        r.ImGui_EndPopup(ctx)
    else
        remote_icon_picker_open = nil
    end

    -- Drag ghost and drop handling
    if remote_drag_active and remote_drag_idx then
        local dl = r.ImGui_GetForegroundDrawList(ctx)
        local mx, my = r.ImGui_GetMousePos(ctx)
        local src_btn = remote_buttons[remote_drag_idx]
        -- Determine if dragging selection
        local dragging_sel = remote_selected[remote_drag_idx] == true
        local drag_count = 0
        if dragging_sel then for _ in pairs(remote_selected) do drag_count = drag_count + 1 end end
        if drag_count == 0 then drag_count = 1 end
        if src_btn then
            -- Draw ghost pill at cursor
            local ghost_w = S(80)
            local ghost_h = S(28)
            local gx = mx - ghost_w / 2
            local gy = my - ghost_h / 2
            r.ImGui_DrawList_AddRectFilled(dl, gx, gy, gx + ghost_w, gy + ghost_h, 0x3B82F6A0, S(4))
            local label
            if dragging_sel and drag_count > 1 then
                label = tostring(drag_count) .. " buttons"
            else
                label = src_btn.name ~= "" and src_btn.name or (r.CF_GetCommandText and r.CF_GetCommandText(0, src_btn.action) or "")
            end
            if label and label ~= "" then
                local reg_font = GetScaledFont()
                if reg_font then r.ImGui_PushFont(ctx, reg_font) end
                local tw = r.ImGui_CalcTextSize(ctx, label)
                local avail = ghost_w - S(8)
                local display = label
                while tw > avail and #display > 3 do
                    display = display:sub(1, #display - 4) .. "..."
                    tw = r.ImGui_CalcTextSize(ctx, display)
                end
                local th = r.ImGui_GetTextLineHeight(ctx)
                r.ImGui_DrawList_AddText(dl, gx + Round((ghost_w - tw) / 2), gy + Round((ghost_h - th) / 2), 0xFFFFFFFF, display)
                if reg_font then r.ImGui_PopFont(ctx) end
            end

            -- Highlight drop target
            local drop_idx = nil
            for bi, rect in pairs(remote_btn_rects) do
                local is_drag_src = (dragging_sel and remote_selected[bi]) or (not dragging_sel and bi == remote_drag_idx)
                if not is_drag_src then
                    if mx >= rect.x and mx < rect.x + rect.w and my >= rect.y and my < rect.y + rect.h then
                        drop_idx = bi
                        r.ImGui_DrawList_AddRect(dl, rect.x, rect.y, rect.x + rect.w, rect.y + rect.h, 0x3B82F6FF, S(4), 0, S(2))
                        break
                    end
                end
            end

            -- Drop on mouse release
            if r.ImGui_IsMouseReleased(ctx, 0) then
                if drop_idx then
                    local drop_mods = r.ImGui_GetKeyMods(ctx)
                    local is_copy_drag = IsCmd(drop_mods)
                    RemotePushUndo()
                    if is_copy_drag then
                        -- Cmd+drag: copy to drop target (overwrite)
                        local src = dragging_sel and {} or { remote_buttons[remote_drag_idx] }
                        if dragging_sel then
                            local sorted = {}
                            for si in pairs(remote_selected) do sorted[#sorted + 1] = si end
                            table.sort(sorted)
                            for _, si in ipairs(sorted) do src[#src + 1] = remote_buttons[si] end
                        end
                        -- Overwrite at drop_idx, consuming blank cells after
                        for ci, sb in ipairs(src) do
                            local ti = drop_idx + ci - 1
                            if ti <= #remote_buttons then
                                remote_buttons[ti] = { action = sb.action, name = sb.name, width = sb.width,
                                    height = remote_buttons[ti].height or remote_default_height,
                                    icon = sb.icon or "", color = sb.color or 0, plugin = sb.plugin or "", page = sb.page or 1 }
                            end
                        end
                    elseif dragging_sel and drag_count > 1 then
                        -- Multi-drag: extract selected buttons, insert at drop position
                        local sorted = {}
                        for si in pairs(remote_selected) do sorted[#sorted + 1] = si end
                        table.sort(sorted)
                        local moved = {}
                        local target_h = (remote_buttons[drop_idx] and remote_buttons[drop_idx].height) or remote_default_height
                        for _, si in ipairs(sorted) do moved[#moved + 1] = remote_buttons[si] end
                        for i = #sorted, 1, -1 do table.remove(remote_buttons, sorted[i]) end
                        local insert_at = drop_idx
                        for _, si in ipairs(sorted) do if si < drop_idx then insert_at = insert_at - 1 end end
                        insert_at = math.max(1, math.min(insert_at, #remote_buttons + 1))
                        for i, mb in ipairs(moved) do
                            mb.height = target_h
                            table.insert(remote_buttons, insert_at + i - 1, mb)
                        end
                        remote_selected = {}
                        for i = 0, #moved - 1 do remote_selected[insert_at + i] = true end
                    else
                        -- Single drag: swap, but preserve each cell's height
                        local src_h = remote_buttons[remote_drag_idx].height or 1
                        local dst_h = remote_buttons[drop_idx].height or 1
                        remote_buttons[remote_drag_idx], remote_buttons[drop_idx] =
                            remote_buttons[drop_idx], remote_buttons[remote_drag_idx]
                        remote_buttons[remote_drag_idx].height = src_h
                        remote_buttons[drop_idx].height = dst_h
                    end
                    RemoteSaveButtons()
                end
                remote_drag_active = false
                remote_drag_idx = nil
            end
        else
            remote_drag_active = false
            remote_drag_idx = nil
        end
    elseif remote_drag_idx and r.ImGui_IsMouseReleased(ctx, 0) then
        remote_drag_active = false
        remote_drag_idx = nil
    end
end


-- =========================================================================
-- FX BROWSER
-- =========================================================================


-- =========================================================================
-- REMOTE PAGES
-- =========================================================================
-- Page persistence/mutation helpers are installed by Reflex_RemoteCore above.

RemoteDrawPageTabs = function(bw)
    if #remote_pages <= 1 then return end  -- don't show tabs for single page
    local gap = S(6)
    local btn_h = S(36)
    local tab_r = S(3)
    local n = #remote_pages
    -- Compute row height from max page height
    local max_ph = 1
    for _, pg in ipairs(remote_pages) do
        local ph = pg.height or 1
        if ph > max_ph then max_ph = ph end
    end
    local cell_w = math.floor((bw - gap * (n - 1)) / n)
    local tab_h
    if max_ph == 3 then tab_h = cell_w
    elseif max_ph == 2 then tab_h = btn_h * 2 + gap
    else tab_h = btn_h end
    local tab_w = cell_w
    local start_x = r.ImGui_GetCursorPosX(ctx)
    local start_y = r.ImGui_GetCursorPosY(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    local open_ctx_menu = false
    local tab_rects = {}

    for pi = 1, n do
        local pg = remote_pages[pi]
        local is_active = pi == remote_current_page
        local tx = start_x + (pi - 1) * (tab_w + gap)
        r.ImGui_SetCursorPos(ctx, tx, start_y)
        local scx, scy = r.ImGui_GetCursorScreenPos(ctx)
        tab_rects[pi] = { x = scx, y = scy, w = tab_w }

        r.ImGui_PushID(ctx, 9000 + pi)
        r.ImGui_InvisibleButton(ctx, "##page", tab_w, tab_h)
        local hov = r.ImGui_IsItemHovered(ctx)

        -- Background
        local bg
        if pg.color > 0 and pg.color <= #remote_palette then
            bg = is_active and ScaleColor(remote_palette[pg.color], 1.0) or ScaleColor(remote_palette[pg.color], 0.4)
        else
            bg = is_active and C.btn_hover or (hov and C.btn_bg or 0x1A1E26FF)
        end
        r.ImGui_DrawList_AddRectFilled(dl, scx, scy, scx + tab_w, scy + tab_h, bg, tab_r)

        -- Text
        local label = pg.name or ("Page " .. pi)
        local reg_font = GetScaledFont()
        if reg_font then r.ImGui_PushFont(ctx, reg_font) end
        local lw = r.ImGui_CalcTextSize(ctx, label)
        local txt_col = is_active and C.text or C.text_dim
        if lw > tab_w - S(8) then
            local ellipsis = "\xE2\x80\xA6"
            local ew = r.ImGui_CalcTextSize(ctx, ellipsis)
            local display = label
            while r.ImGui_CalcTextSize(ctx, display) + ew > tab_w - S(8) and #display > 1 do
                display = Utf8DropLast(display)
            end
            label = display .. ellipsis
            lw = r.ImGui_CalcTextSize(ctx, label)
        end
        r.ImGui_DrawList_AddText(dl, scx + Round((tab_w - lw) / 2),
            scy + Round((tab_h - text_h) / 2), txt_col, label)
        if reg_font then r.ImGui_PopFont(ctx) end

        -- Click to switch
        if r.ImGui_IsItemClicked(ctx, 0) then
            remote_current_page = pi
            remote_page_drag_idx = pi
        end

        -- Right-click
        if r.ImGui_IsItemClicked(ctx, 1) then
            remote_page_ctx = pi
            open_ctx_menu = true
        end

        r.ImGui_PopID(ctx)
    end

    -- Drag reorder: visual indicator during drag, swap on release
    if remote_page_drag_idx and r.ImGui_IsMouseDown(ctx, 0) then
        local mx = (select(1, r.ImGui_GetMousePos(ctx)))
        local src = remote_page_drag_idx
        local src_rect = tab_rects[src]
        if src_rect and math.abs(mx - (src_rect.x + tab_w / 2)) > S(8) then
            -- Find which tab the mouse is over
            for ti = 1, n do
                if ti ~= src then
                    local tr = tab_rects[ti]
                    if tr and mx >= tr.x and mx <= tr.x + tr.w then
                        -- Draw insert indicator
                        local dl_fg = r.ImGui_GetForegroundDrawList(ctx)
                        local ind_x = ti < src and tr.x - gap / 2 or (tr.x + tr.w + gap / 2)
                        r.ImGui_DrawList_AddLine(dl_fg, ind_x, tr.y, ind_x, tr.y + tab_h, 0xFFFFFF99, S(2))
                        break
                    end
                end
            end
        end
    end
    if remote_page_drag_idx and r.ImGui_IsMouseReleased(ctx, 0) then
        local mx = (select(1, r.ImGui_GetMousePos(ctx)))
        local src = remote_page_drag_idx
        remote_page_drag_idx = nil
        -- Find drop target
        for ti = 1, n do
            if ti ~= src then
                local tr = tab_rects[ti]
                if tr and mx >= tr.x and mx <= tr.x + tr.w then
                    -- Swap pages
                    remote_pages[src], remote_pages[ti] = remote_pages[ti], remote_pages[src]
                    for _, btn in ipairs(remote_buttons) do
                        if (btn.page or 1) == src then btn.page = ti
                        elseif (btn.page or 1) == ti then btn.page = src end
                    end
                    if remote_current_page == src then remote_current_page = ti
                    elseif remote_current_page == ti then remote_current_page = src end
                    RemoteSavePages()
                    RemoteSaveButtons()
                    break
                end
            end
        end
    end

    -- Open context menu outside PushID scope
    if open_ctx_menu then
        r.ImGui_OpenPopup(ctx, "##pagectx")
    end

    -- Page tab right-click menu
    if r.ImGui_BeginPopup(ctx, "##pagectx") then
        local pi = remote_page_ctx
        local pg = pi and remote_pages[pi]
        if pg then
            if r.ImGui_MenuItem(ctx, "Rename") then
                local retval, new_name = r.GetUserInputs("Rename Page", 1, "Name:", pg.name)
                if retval and new_name ~= "" then pg.name = new_name; RemoteSavePages() end
            end

            -- Color swatches
            r.ImGui_Separator(ctx)
            local swatch_r = S(8)
            local swatch_gap = S(6)
            r.ImGui_Dummy(ctx, 0, S(4))
            local sw_sx = r.ImGui_GetCursorPosX(ctx)
            local sw_sy = r.ImGui_GetCursorPosY(ctx)
            local sw_cx, sw_cy = r.ImGui_GetCursorScreenPos(ctx)
            local sw_dl = r.ImGui_GetWindowDrawList(ctx)
            local none_cx = sw_cx + swatch_r + S(4)
            local none_cy = sw_cy + swatch_r
            r.ImGui_SetCursorPos(ctx, sw_sx + S(4), sw_sy)
            if r.ImGui_InvisibleButton(ctx, "##pcNone", swatch_r * 2, swatch_r * 2) then
                pg.color = 0; RemoteSavePages()
            end
            if pg.color == 0 then
                r.ImGui_DrawList_AddCircleFilled(sw_dl, none_cx, none_cy, swatch_r, C.text_muted, 0)
            else
                r.ImGui_DrawList_AddCircle(sw_dl, none_cx, none_cy, swatch_r, C.text_muted, 0, S(1.5))
            end
            for ci = 1, #remote_palette do
                r.ImGui_SameLine(ctx, 0, swatch_gap)
                local ci_cx, ci_cy = r.ImGui_GetCursorScreenPos(ctx)
                local dot_cx = ci_cx + swatch_r
                local dot_cy = ci_cy + swatch_r
                r.ImGui_SetCursorPos(ctx, r.ImGui_GetCursorPosX(ctx), sw_sy)
                if r.ImGui_InvisibleButton(ctx, "##pc" .. ci, swatch_r * 2, swatch_r * 2) then
                    pg.color = ci; RemoteSavePages()
                end
                r.ImGui_DrawList_AddCircleFilled(sw_dl, dot_cx, dot_cy, swatch_r, remote_palette[ci], 0)
                if pg.color == ci then
                    r.ImGui_DrawList_AddCircle(sw_dl, dot_cx, dot_cy, swatch_r + S(2), 0xFFFFFFCC, 0, S(1.5))
                end
            end
            r.ImGui_Dummy(ctx, 0, S(4))

            r.ImGui_Separator(ctx)
            if #remote_pages > 1 then
                if r.ImGui_MenuItem(ctx, "Delete Page") then
                    RemoteDeletePage(pi)
                end
            end
            -- Height submenu
            if r.ImGui_BeginMenu(ctx, "Height") then
                local cur_h = pg.height or 1
                local function PageHeightRadio(label, h)
                    local sel = cur_h == h
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), sel and C.green or C.text_dim)
                    if r.ImGui_MenuItem(ctx, (sel and "\xE2\x97\x8F " or "\xE2\x97\x8B ") .. label) then
                        pg.height = h; RemoteSavePages()
                    end
                    r.ImGui_PopStyleColor(ctx, 1)
                end
                PageHeightRadio("Full", 3); PageHeightRadio("Half", 2); PageHeightRadio("Slim", 1)
                r.ImGui_EndMenu(ctx)
            end
        end
        r.ImGui_EndPopup(ctx)
    end

    r.ImGui_SetCursorPos(ctx, start_x, start_y + tab_h + gap)
end


-- Routing/Active view backend
package.loaded["Reflex_ViewModes"] = nil
require("Reflex_ViewModes")({
    r = r,
    mark_dirty = function() needs_rescan = true; needs_song_rescan = true end,
})

ReflexNavigatorRunExternalCommand = function(command)
    if command == "focus_tlt_search" then
        ReflexNavigatorRequestTltSearchFocus()
        return true
    elseif command == "toggle_navigator_expanded" then
        return ReflexToggleNavigatorExpanded and ReflexToggleNavigatorExpanded() == true
    elseif command == "armed_enable" then
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
    elseif command == "open_fx_browser" then
        return ReflexOpenFXBrowserForHotkey
            and ReflexOpenFXBrowserForHotkey({ source = "external" }) == true
    elseif command == "fx_window_next" then
        return ReflexCycleFXWindow and ReflexCycleFXWindow(1, { source = "external" }) == true
    elseif command == "fx_window_previous" then
        return ReflexCycleFXWindow and ReflexCycleFXWindow(-1, { source = "external" }) == true
    elseif command == "fx_window_stack_next" then
        return ReflexCycleFXWindow and ReflexCycleFXWindow(1, { source = "external", keep_open = true }) == true
    elseif command == "fx_window_stack_previous" then
        return ReflexCycleFXWindow and ReflexCycleFXWindow(-1, { source = "external", keep_open = true }) == true
    elseif command == "close_all_fx_windows" then
        return ReflexCloseAllFXWindows and ReflexCloseAllFXWindows() == true
    elseif command == "tile_fx_windows" then
        return ReflexTileFXWindowsOrCurrentTrack and ReflexTileFXWindowsOrCurrentTrack() == true
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

-- Shared NAV renderer (used by Reflex and standalone Navigator).
package.loaded["Reflex_NavViewCore"] = nil
require("Reflex_NavViewCore")({
    r = r,
    ctx = ctx,
    colors = C,
    scaled_fonts = scaled_fonts,
    font_sizes = scaled_font_sizes,
    track_color_overrides = track_color_overrides,
    script_dir = script_dir,
    version = REFLEX_VERSION,
    menu_context = "reflex",
    embedded_nav_panel = true,
    mark_dirty = function() needs_rescan = true; needs_song_rescan = true end,
    get_nav_scale = function() return nav_ui_scale end,
    set_nav_scale = function(v)
        local n = tonumber(v) or 1.0
        n = math.max(0.5, math.min(2.5, math.floor(n * 100 + 0.5) / 100))
        nav_ui_scale = n
        ui_scale = n
        SavePref("navigator_scale_v1", n)
    end,
    open_io_manager = function() RecordInputOpenManager(nil, nil) end,
})

-- =========================================================================
-- ROUTING VIEW
-- =========================================================================

RoutingViewDrawButton = function(dl, cx, cy, radius)
    local hov = false
    local scx, scy = r.ImGui_GetCursorScreenPos(ctx)

    r.ImGui_InvisibleButton(ctx, "##routing_view", radius * 2 + S(6), radius * 2 + S(6))
    hov = r.ImGui_IsItemHovered(ctx)
    if r.ImGui_IsItemClicked(ctx, 0) then
        RoutingViewToggle()
    end

    local btn_cx = scx + radius + S(3)
    local btn_cy = scy + radius + S(3)
    local bg_col = routing_view_active and C.cmp_b or (hov and C.btn_hover or C.btn_bg)
    r.ImGui_DrawList_AddCircleFilled(dl, btn_cx, btn_cy, radius, bg_col, 0)

    -- Bold "R" text
    local bold_step = GetFontStep(UI.font_title)
    local bold_font = scaled_fonts[bold_step]
    if bold_font then r.ImGui_PushFont(ctx, bold_font) end
    local rtw = r.ImGui_CalcTextSize(ctx, "R")
    local rth = r.ImGui_GetTextLineHeight(ctx)
    local txt_col = routing_view_active and 0xFFFFFFFF or C.text_muted
    r.ImGui_DrawList_AddText(dl, btn_cx - rtw / 2, btn_cy - rth / 2, txt_col, "R")
    if bold_font then r.ImGui_PopFont(ctx) end

    if hov and opt_tooltips then TipDirect(routing_view_active and "Exit Routing View" or "Routing View") end
end

-- ── Noise Floor Scan ──
-- Scans all tracks for sub-threshold signal (peak > 0 but below -100dB).
-- Returns list of { track, name, peak_db } sorted by peak level.
-- Only meaningful during playback.
noise_scan_results = {}
noise_scan_time = 0

-- ── Flow Arrow (down arrow between flow view tracks) ──
flow_arrow_img = nil
flow_arrow_loaded = false

DrawFlowArrow = function(dl, center_x, top_y, bot_y)
    -- Load image on first call
    if not flow_arrow_loaded then
        local path = script_dir .. "icons/rounded-arrow-down.png"
        local ok, img = pcall(r.ImGui_CreateImage, path)
        if ok and img then flow_arrow_img = img; r.ImGui_Attach(ctx, img) end
        flow_arrow_loaded = true
    end

    local total_h = bot_y - top_y
    local arrow_h = math.floor(total_h * 0.435)
    local arrow_w = arrow_h
    local ax = center_x - math.floor(arrow_w / 2)
    local ay = top_y + Round((total_h - arrow_h) / 2)

    if flow_arrow_img then
        local tint = (C.text_muted & 0xFFFFFF00) | math.floor((C.text_muted & 0xFF) * 0.4)
        r.ImGui_DrawList_AddImage(dl, flow_arrow_img,
            ax, ay, ax + arrow_w, ay + arrow_h, 0, 0, 1, 1, tint)
    else
        -- Fallback: simple line if image missing
        r.ImGui_DrawList_AddLine(dl, center_x, top_y + 4, center_x, bot_y - 4, C.text_muted, S(3))
    end
end

-- ── Flow View ──
package.loaded["Reflex_FlowCore"] = nil
require("Reflex_FlowCore")({
    r = r,
    get_insp_pinned = function() return insp_pinned end,
    set_insp_pinned = function(v) insp_pinned = v end,
    set_insp_pin_suppress_selected = function(v) insp_pin_suppress_selected = v end,
    set_nav_scroll_target = function(v) nav_scroll_target = v end,
})

-- Minimal flow card: compact track representation (title row + M/S + meter row)
-- Returns card height consumed. Handles click-to-expand and double-click-to-focus.
flow_mini_peak = {}  -- per-track smoothed peak for minimal card meters
FlowDrawMinimalCard = function(track, bw, block_idx)
    r.ImGui_PushID(ctx, block_idx + 2000)

    local gap = S(UI.pad_sm)
    local btn_h = S(UI.btn_h)
    local knob_gap = S(20 / 1.44)
    local pad_x = S(UI.card_pad)
    local pad_top = S(UI.card_pad_top)
    local pad_bot = S(UI.card_pad_bot)
    local row_gap = S(UI.hdr_row_gap)
    local meter_h = S(8)

    -- Measure title height with inspector font
    local title_font = InspGetTitleFont()
    local tfp = false
    if title_font then r.ImGui_PushFont(ctx, title_font); tfp = true end
    local title_h = r.ImGui_GetTextLineHeight(ctx)
    if tfp then r.ImGui_PopFont(ctx) end

    -- Row 2 height = btn_h (M/S buttons or meter, whichever is taller)
    local row2_h = math.max(btn_h, meter_h)
    local card_h = pad_top + title_h + row_gap + row2_h + pad_bot

    -- Card position
    local sx = r.ImGui_GetCursorPosX(ctx)
    local sy = r.ImGui_GetCursorPosY(ctx)
    local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)

    -- Stroke logic: selected track gets a gray outline even when collapsed.
    local is_selected = (track == insp_track)
    local stroke = is_selected and C.flow_stroke or nil

    -- Card bg
    local col_r = opt_card_boxes and S(UI.card_r) or S(UI.corner_r)
    local rcx, rcy = math.floor(cx), math.floor(cy)
    local rcx2, rcy2 = math.floor(cx + bw), math.floor(cy + card_h)
    if stroke then
        if r.ImGui_StyleVar_CircleTessellationMaxError then
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CircleTessellationMaxError(), CARD_STROKE_TESSELLATION_MAX_ERROR)
        end
        local sw = FLOW_STROKE_W
        local stroke_rgba = (stroke & 0xFFFFFF00) | 0xFF
        r.ImGui_DrawList_AddRectFilled(dl, rcx, rcy, rcx2, rcy2, stroke_rgba, col_r)
        r.ImGui_DrawList_AddRectFilled(dl, rcx + sw, rcy + sw, rcx2 - sw, rcy2 - sw, C.bg, math.max(0, col_r - sw))
        if r.ImGui_StyleVar_CircleTessellationMaxError then
            r.ImGui_PopStyleVar(ctx)
        end
    else
        local hov = r.ImGui_IsMouseHoveringRect(ctx, rcx, rcy, rcx2, rcy2)
        local bg = hov and C.bg or 0x202227FF
        r.ImGui_DrawList_AddRectFilled(dl, rcx, rcy, rcx2, rcy2, bg, col_r)
    end
    RouteDragRegisterCardTarget(track, rcx, rcy, rcx2 - rcx, rcy2 - rcy, dl, col_r)

    -- Keep card_idx in sync (minimal cards skip CardBegin but need counter parity)
    card_idx = card_idx + 1

    -- Content area
    local ix = cx + pad_x
    local iy = cy + pad_top
    local inner_w = bw - pad_x * 2

    -- Track info
    local _, track_name = r.GetTrackName(track)
    local track_num = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
    local num_str = (track_num <= 0) and "M" or tostring(track_num)
    local track_color_raw = r.GetTrackColor(track)
    local num_col = track_color_raw ~= 0 and TrackColorToImGui(track_color_raw) or C.text_muted
    local is_muted = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
    local is_solo = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0

    -- Row 1: Title (same font as normal inspector)
    if title_font then r.ImGui_PushFont(ctx, title_font); tfp = true else tfp = false end
    local num_label, num_slot_label = TrackTitleNumberLabels(num_str)
    local num_tw = r.ImGui_CalcTextSize(ctx, num_slot_label)
    local name_avail = inner_w - num_tw - S(4)
    local display_name = track_name
    local name_tw = r.ImGui_CalcTextSize(ctx, display_name)
    if name_tw > name_avail then
        local ellipsis = "\xE2\x80\xA6"
        local ew = r.ImGui_CalcTextSize(ctx, ellipsis)
        while name_tw + ew > name_avail and #display_name > 0 do
            display_name = Utf8DropLast(display_name)
            name_tw = r.ImGui_CalcTextSize(ctx, display_name)
        end
        display_name = display_name .. ellipsis
        name_tw = r.ImGui_CalcTextSize(ctx, display_name)
    end
    r.ImGui_DrawList_AddText(dl, ix, iy, num_col, num_label)
    r.ImGui_DrawList_AddText(dl, ix + num_tw + S(4), iy, C.text_dim, display_name)
    if tfp then r.ImGui_PopFont(ctx) end

    -- v20.441: TitleLink over the title text region.
    local mc_link_w = math.min(num_tw + S(4) + name_tw, inner_w)
    if title_font then r.ImGui_PushFont(ctx, title_font); tfp = true else tfp = false end
    local mc_link_h = r.ImGui_GetTextLineHeight(ctx)
    if tfp then r.ImGui_PopFont(ctx) end
    local mc_title_hov, mc_title_clk = TitleLink(
        "##mctitlelink", ix, iy, mc_link_w, mc_link_h, track, {})
    if mc_title_hov then
        local mc_name_x = ix + num_tw + S(4)
        DrawSolidUnderline(dl, mc_name_x, iy + mc_link_h, mc_name_x + name_tw, C.text_dim, 1)
    end

    -- Row 2: record/mon/M/S left-aligned + meter right-aligned (half width)
    local row2_y = iy + title_h + row_gap
    local ms_w = btn_h
    local ms_gap = gap  -- S(UI.pad_sm) — standard button spacing
    local left_x = ix

    -- Record-arm button (normal tracks only; not shown on master)
    if track_num > 0 then
        local is_armed = r.GetMediaTrackInfo_Value(track, "I_RECARM") == 1
        r.ImGui_SetCursorScreenPos(ctx, left_x, row2_y)
        local _, rec_clk = RecordArmButton("##mrecarm", btn_h, is_armed)
        if rec_clk then
            RecordArmClick(track, is_armed)
        end
        left_x = left_x + ms_w + ms_gap

        if is_armed then
            local mon_w = RecordMonitorButtonWidth(btn_h)
            local is_mon_on = r.GetMediaTrackInfo_Value(track, "I_RECMON") > 0
            r.ImGui_SetCursorScreenPos(ctx, left_x, row2_y)
            local _, mon_clk, _, mon_rclick =
                RecordMonitorButton("##mrecmon", mon_w, btn_h, is_mon_on)
            if mon_clk then RecordMonitorToggle(track) end
            if mon_rclick then
                r.ImGui_OpenPopup(ctx, "##mrecmon_ctx")
                nav_rclick_consumed = true
            end
            RecordMonitorMenu(track, "##mrecmon_ctx")
            left_x = left_x + mon_w + ms_gap * 2
        end
    end

    -- Mute button
    r.ImGui_SetCursorScreenPos(ctx, left_x, row2_y)
    local _, m_clk = NavRect("M##mm", ms_w, btn_h, "M", MuteOpts(is_muted))
    if m_clk then
        r.Undo_BeginBlock()
        r.SetMediaTrackInfo_Value(track, "B_MUTE", is_muted and 0 or 1)
        r.Undo_EndBlock("Reflex: Mute", -1)
    end

    -- Solo button (after mute)
    r.ImGui_SetCursorScreenPos(ctx, left_x + ms_w + ms_gap, row2_y)
    local _, s_clk = NavRect("S##ms", ms_w, btn_h, "S", SoloOpts(is_solo))
    if s_clk then
        r.Undo_BeginBlock()
        r.SetMediaTrackInfo_Value(track, "I_SOLO", is_solo and 0 or 2)
        r.Undo_EndBlock("Reflex: Solo", -1)
    end

    -- Peak meter (right-aligned, half inner width, bottom-aligned with M/S buttons)
    local meter_w = math.floor(inner_w / 2)
    local meter_x = ix + inner_w - meter_w
    local meter_y = row2_y + btn_h - meter_h  -- bottom-aligned with M/S
    local meter_r = S(2)

    local peak_raw = math.max(r.Track_GetPeakInfo(track, 0), r.Track_GetPeakInfo(track, 1))
    local cur_peak = SmoothPeak(flow_mini_peak, track, peak_raw)

    -- Meter bg
    r.ImGui_DrawList_AddRectFilled(dl, meter_x, meter_y, meter_x + meter_w, meter_y + meter_h, C.vol_slider_bg, meter_r)
    -- Meter fill (green → amber → red, matching volume slider)
    if cur_peak > 0.00001 then
        local meter_fill = math.min(1, cur_peak ^ 0.25)
        local fill_w = math.max(1, Round(meter_w * meter_fill))
        local db = 20 * math.log(math.max(cur_peak, 0.00001), 10)
        local meter_col
        meter_col = MeterColor(db)
        r.ImGui_DrawList_PushClipRect(dl, meter_x, meter_y, meter_x + fill_w, meter_y + meter_h, true)
        r.ImGui_DrawList_AddRectFilled(dl, meter_x, meter_y, meter_x + meter_w, meter_y + meter_h, meter_col, meter_r)
        r.ImGui_DrawList_PopClipRect(dl)
    end

    -- v20.431: hover-during-active-drag auto-expands the card so it becomes
    -- a drop target (full render → InspDrawFXArea registers via FxDropTargetRegister).
    -- We track which tracks were auto-expanded so FxDragClear can revert them
    -- on non-committal drags. Drop-into-card (commit) removes the track from
    -- the auto-expanded list so the expansion persists after the drop.
    -- Note: gating on IsMouseHoveringRect alone (not IsAnyItemHovered) — we
    -- want to fire even when over the card's M/S buttons, since drag intent
    -- spans the whole card.
    if fx_drag.active and r.ImGui_IsMouseHoveringRect(ctx, cx, cy, cx + bw, cy + card_h) then
        flow_view_expanded_set[track] = true
        fx_drag.flow_auto_expanded = fx_drag.flow_auto_expanded or {}
        fx_drag.flow_auto_expanded[track] = true
    end

    -- Background click handling (click-to-expand + browse, double-click = focus)
    -- v20.441: title-click is allowed to fall through to single-click expand
    -- (locate is additive — title click locates AND expands+browses). But
    -- title double-click is suppressed: a fast title click that registers as
    -- a double-click should not switch flow focus.
    -- v20.442: peek (Opt+click) is light-touch — suppress all bg fall-through.
    if r.ImGui_IsMouseHoveringRect(ctx, cx, cy, cx + bw, cy + card_h)
       and not r.ImGui_IsAnyItemHovered(ctx)
       and not nav_title_peek_consumed then
        if r.ImGui_IsMouseDoubleClicked(ctx, 0) and not mc_title_clk then
            -- v20.431: clear set on focus change — chain rebuilds.
            flow_view_expanded_set = {}
            -- v20.429: pre/post push so Back/Forward restore the previous
            -- flow chain context (anchor + chain), not just the unpin state.
            -- This is the user-reported bug site: pinned T18 → double-click
            -- T17 minimal card → Back. Without pre-push the intermediate
            -- "pinned but browsing" state is unrecorded, so the redo entry
            -- for Forward doesn't reflect the silent track switch.
            ViewHistoryPush()
            FlowViewSetFocus(track)
            ViewHistoryPush()
        elseif r.ImGui_IsMouseClicked(ctx, 0) then
            -- v20.431: minimal card click → expand AND select. Persists
            -- across selection changes; user collapses by clicking the card
            -- again once it's selected (handled in the full-card click path),
            -- or by clicking the focus card to clear all expansions.
            flow_view_expanded_set[track] = true
            r.Undo_BeginBlock()
            r.SetOnlyTrackSelected(track)
            r.Undo_EndBlock("Reflex: Browse track", 0)
            flow_view_browsing = true
        end
    end

    -- Advance cursor past card
    r.ImGui_SetCursorPos(ctx, sx, sy + card_h)
    r.ImGui_PopID(ctx)
    return card_h
end

-- Flow View pill button. full_row: click area spans full bw (separator between flow blocks)
FlowDrawInlineButton = function(bw, btn_id, full_row)
    local btn_h = S(UI.btn_h)
    local label = "FLOW"
    local arrow_dir = flow_view_active and "up" or "right"
    local arrow_w = math.max(S(8), btn_h * 0.34)
    local label_w = r.ImGui_CalcTextSize(ctx, label)
    local th = r.ImGui_GetTextLineHeight(ctx)
    local pad_x = S(10)
    local arrow_pad = S(8)
    local total_w = pad_x + label_w + arrow_pad + arrow_w + pad_x

    if full_row then
        -- Separator mode: wide click area, button drawn left-aligned
        r.ImGui_InvisibleButton(ctx, btn_id, bw, btn_h)
        local hov = r.ImGui_IsItemHovered(ctx)
        local pressed = r.ImGui_IsItemActive(ctx)
        if r.ImGui_IsItemClicked(ctx, 0) then FlowViewToggle() end
        local ix, iy = r.ImGui_GetItemRectMin(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        -- Background: hover only, inactive flow only
        if hov and not pressed and not flow_view_active then
            r.ImGui_DrawList_AddRectFilled(dl, ix, iy, ix + total_w, iy + btn_h, C.fx_ctrl_hover, 3)
        end
        local arrow_col, txt_col
        if pressed then
            arrow_col = 0xFFFFFFFF; txt_col = 0xFFFFFFFF
        elseif hov then
            if flow_view_active then arrow_col = 0xFFFFFFFF; txt_col = 0xFFFFFFFF
            else arrow_col = C.text_dim; txt_col = C.text end
        else
            if flow_view_active then arrow_col = 0xFFFFFFFF; txt_col = 0xFFFFFFFF
            else arrow_col = C.text_dim; txt_col = C.text_dim end
        end
        local ty = iy + Round((btn_h - th) / 2)
        r.ImGui_DrawList_AddText(dl, ix + pad_x, ty, txt_col, label)
        DrawArrowIcon(dl, ix + pad_x + label_w + arrow_pad + arrow_w * 0.5,
            iy + btn_h * 0.5, btn_h * 0.48, arrow_dir, arrow_col)
    else
        -- Standalone button
        local scx, scy = r.ImGui_GetCursorScreenPos(ctx)
        r.ImGui_InvisibleButton(ctx, btn_id, total_w, btn_h)
        local hov = r.ImGui_IsItemHovered(ctx)
        local pressed = r.ImGui_IsItemActive(ctx)
        if r.ImGui_IsItemClicked(ctx, 0) then FlowViewToggle() end
        local dl = r.ImGui_GetWindowDrawList(ctx)
        -- Background: hover only, inactive flow only
        if hov and not pressed and not flow_view_active then
            r.ImGui_DrawList_AddRectFilled(dl, scx, scy, scx + total_w, scy + btn_h, C.fx_ctrl_hover, 3)
        end
        local arrow_col, txt_col
        if pressed then
            arrow_col = 0xFFFFFFFF; txt_col = 0xFFFFFFFF
        elseif hov then
            if flow_view_active then arrow_col = 0xFFFFFFFF; txt_col = 0xFFFFFFFF
            else arrow_col = C.text_dim; txt_col = C.text end
        else
            if flow_view_active then arrow_col = 0xFFFFFFFF; txt_col = 0xFFFFFFFF
            else arrow_col = C.text_dim; txt_col = C.text_dim end
        end
        local ty = scy + Round((btn_h - th) / 2)
        r.ImGui_DrawList_AddText(dl, scx + pad_x, ty, txt_col, label)
        DrawArrowIcon(dl, scx + pad_x + label_w + arrow_pad + arrow_w * 0.5,
            scy + btn_h * 0.5, btn_h * 0.48, arrow_dir, arrow_col)
    end
    return total_w
end

-- ── Sends View ──

SendsViewDrawButton = function()
    local pill_h = S(UI.btn_h)
    local pill_pad_x = S(12)
    local label = "Sends"
    local label_w = r.ImGui_CalcTextSize(ctx, label)
    local pill_w = label_w + pill_pad_x * 2
    local bg = sends_view_active and C.cmp_b or C.fx_ctrl_bg
    local hov_bg = sends_view_active and C.cmp_b or C.fx_ctrl_hover
    local act_bg = sends_view_active and ((C.cmp_b & 0xFFFFFF00) | 0xCC) or C.fx_ctrl_active
    local txt = sends_view_active and 0xFFFFFFFF or C.text_dim
    local _, sv_clk = NavPill("##sends_view", pill_w, pill_h, label, {
        bg = bg, hov = hov_bg, active = act_bg, fg = txt,
    })
    if sv_clk then
        SendsViewToggle()
    end
    return pill_w
end

-- =========================================================================
-- SEND FX CACHE CORE
-- =========================================================================
package.loaded["Reflex_SendFxCacheCore"] = nil
require("Reflex_SendFxCacheCore")({
    r = r,
})

-- =========================================================================
-- SEND GRID CORE
-- =========================================================================
package.loaded["Reflex_SendGridCore"] = nil
require("Reflex_SendGridCore")({
    r = r,
    ctx = ctx,
    colors = C,
})

-- =========================================================================
-- SEND DISTANT CORE
-- =========================================================================
package.loaded["Reflex_SendDistantCore"] = nil
require("Reflex_SendDistantCore")({
    r = r,
    ctx = ctx,
    colors = C,
})

-- =========================================================================
-- SEND FOLDER CORE
-- =========================================================================
package.loaded["Reflex_SendFolderCore"] = nil
require("Reflex_SendFolderCore")({
    r = r,
    ctx = ctx,
    colors = C,
})

-- Draw a single compact track column. Reusable for sends, compact mixer, compact flow.
-- Requires: PushID called by caller, sends_fx_cache populated for this track.
-- source_track + send_idx: optional, when provided draws send vol/pan knobs at top.
SendsOverviewSourcePinned = function(source_track)
    if not (insp_pinned and insp_track and r.ValidatePtr(insp_track, "MediaTrack*")) then return false end
    if source_track then return source_track == insp_track end
    return sends_view_active == true and sends_view_source == insp_track
end

DrawCompactTrackColumn = function(track, dl, cx, cy, col_w, col_h, max_fx, source_track, send_idx, opts)
    opts = opts or {}
    local pad_x = S(UI.card_pad)
    local pad_top = S(UI.card_pad_top)
    if source_track and send_idx then pad_top = S(UI.send_pad_top) end
    local is_folder_column = not (source_track and send_idx)
    local is_folder_spanner = is_folder_column and opts.folder_spanner == true
    local corner_r = S(UI.corner_r)
    local gap = S(UI.pad_sm)
    local btn_h = S(UI.btn_h)
    local knob_gap = S(20 / 1.44)

    -- Column background (card styling when enabled)
    local col_r = opt_card_boxes and S(UI.card_r) or corner_r
    local rcx, rcy, rcx2, rcy2 = math.floor(cx), cy, math.floor(cx + col_w), cy + col_h
    r.ImGui_DrawList_AddRectFilled(dl, rcx, rcy, rcx2, rcy2, C.bg, col_r)
    local source_is_pinned = SendsOverviewSourcePinned and SendsOverviewSourcePinned(source_track)
    local module_outline = source_is_pinned and C.source_stroke
        or (send_idx and route_hovered_send_idx == send_idx and C.send_stroke or nil)
    if module_outline then
        DrawSolidRoundedRectOutline(dl, rcx, rcy, rcx2, rcy2, module_outline, col_r, SOURCE_STROKE_W)
    end
    RouteDragRegisterCardTarget(track, rcx, rcy, rcx2 - rcx, rcy2 - rcy, dl, col_r)

    local x = cx + pad_x
    local y = cy + pad_top
    local inner_w = col_w - pad_x * 2
    if inner_w < S(20) then return end
    local knob_d = Round(btn_h * 1.5)
    local knobs_wrap = inner_w < (knob_d * 2 + knob_gap)

    -- SND section (collapsible send controls — default collapsed, before title)
    if source_track and send_idx and r.ValidatePtr(source_track, "MediaTrack*") then
        local snd_expanded = sends_snd_expanded[send_idx] == true

        -- SND header row: [SND .................. arrow] — full-width hit area
        -- v20.441: arrow moved to right endcap (chevron convention, mirrors
        -- folder card expand affordance). Whole row stays clickable.
        local send_is_muted = r.GetTrackSendInfo_Value(source_track, 0, send_idx, "B_MUTE") == 1
        r.ImGui_SetCursorScreenPos(ctx, x, y)
        r.ImGui_InvisibleButton(ctx, "##snd_hdr", inner_w, btn_h)
        local snd_hov = r.ImGui_IsItemHovered(ctx)
        Tip("Open sending track controls")
        -- Arrow color: normal state (not affected by mute)
        local arrow_col
        if snd_hov or snd_expanded then arrow_col = C.text else arrow_col = C.text_muted end
        -- SND text color: same red as the active mute button when muted.
        local snd_txt_col
        if send_is_muted then
            snd_txt_col = MuteOpts(true).bg
        elseif snd_hov or snd_expanded then
            snd_txt_col = C.text
        else
            snd_txt_col = C.text_muted
        end
        local text_y = y + Round((btn_h - r.ImGui_GetTextLineHeight(ctx)) / 2)
        local arrow_w = math.max(S(8), btn_h * 0.34)
        r.ImGui_DrawList_AddText(dl, x, text_y, snd_txt_col, "SND")
        DrawArrowIcon(dl, x + inner_w - arrow_w * 0.5, y + btn_h * 0.5,
            btn_h * 0.48, snd_expanded and "down" or "right", arrow_col)
        if r.ImGui_IsItemClicked(ctx, 0) then
            -- v20.441: in distant rendering mode, SND is force-expanded every
            -- frame and clicking it should collapse the entire distant card
            -- (single state — no nested collapse). Self-toggle would be
            -- reverted on the next frame's force-write, producing a flicker
            -- instead of an actual collapse. Set the request flag for the
            -- outer handler to consume.
            if sends_distant_rendering then
                sends_distant_collapse_request = true
            else
                sends_snd_expanded[send_idx] = not snd_expanded
                snd_expanded = sends_snd_expanded[send_idx] == true
            end
        end
        y = y + btn_h + gap

        if snd_expanded then
            local text_h = r.ImGui_GetTextLineHeight(ctx)
            local half_w = inner_w / 2

            local send_vol = r.GetTrackSendInfo_Value(source_track, 0, send_idx, "D_VOL")
            local send_muted = r.GetTrackSendInfo_Value(source_track, 0, send_idx, "B_MUTE") == 1

            -- Knob row: [vol] [M] [pan] — mute centered between knobs
            local mute_w = btn_h
            if knobs_wrap then
                -- Stacked: vol, mute, pan each on own row centered
                local kx = x + Round((inner_w - knob_d) / 2)

                NavParamKnob(dl, "##skvol", kx, y, knob_d, "vol",
                             source_track, send_idx, skvol_state,
                             "Reflex: Send volume", "Send volume",
                             send_vol, send_idx)
                y = y + knob_d + S(2) + text_h + gap

                -- Mute button centered
                local mx = x + Round((inner_w - mute_w) / 2)
                local sm_opts = MuteOpts(send_muted)
                r.ImGui_SetCursorScreenPos(ctx, mx, y)
                local _, sm_clk = NavRect("M##sm", mute_w, btn_h, "M", sm_opts)
                Tip("Send mute")
                if sm_clk then
                    r.Undo_BeginBlock()
                    r.SetTrackSendInfo_Value(source_track, 0, send_idx, "B_MUTE", send_muted and 0 or 1)
                    r.Undo_EndBlock("Reflex: Send mute", -1)
                end
                y = y + btn_h + gap

                NavParamKnob(dl, "##skpan", kx, y, knob_d, "pan",
                             source_track, send_idx, skpan_state,
                             "Reflex: Send pan", "Send pan")
                y = y + knob_d + S(2) + text_h + gap
            else
                -- Side by side with mute centered between
                local third_w = inner_w / 3
                local vol_kx = x + Round((third_w - knob_d) / 2)
                local pan_kx = x + inner_w - third_w + Round((third_w - knob_d) / 2)
                local mx = x + Round((inner_w - mute_w) / 2)

                NavParamKnob(dl, "##skvol", vol_kx, y, knob_d, "vol",
                             source_track, send_idx, skvol_state,
                             "Reflex: Send volume", "Send volume",
                             send_vol, send_idx)

                -- Mute button vertically centered with knobs
                local m_cy = y + Round((knob_d - btn_h) / 2)
                local sm_opts = MuteOpts(send_muted)
                r.ImGui_SetCursorScreenPos(ctx, mx, m_cy)
                local _, sm_clk = NavRect("M##sm", mute_w, btn_h, "M", sm_opts)
                Tip("Send mute")
                if sm_clk then
                    r.Undo_BeginBlock()
                    r.SetTrackSendInfo_Value(source_track, 0, send_idx, "B_MUTE", send_muted and 0 or 1)
                    r.Undo_EndBlock("Reflex: Send mute", -1)
                end

                NavParamKnob(dl, "##skpan", pan_kx, y, knob_d, "pan",
                             source_track, send_idx, skpan_state,
                             "Reflex: Send pan", "Send pan")
                y = y + knob_d + S(2) + text_h + gap
            end

            -- Mode dropdown + ENV button row
            do
                local mode_w = r.ImGui_CalcTextSize(ctx, "PreFX") + S(16)
                if mode_w > inner_w then mode_w = inner_w end
                local env_w = math.floor(InspCtrlW("ENV") * 1.2)
                local mode_env_wrap = (mode_w + gap + env_w) > inner_w

                DrawRouteModeDD("##snd_mode", dl, source_track, 0, send_idx, x, y, mode_w, btn_h)
                Tip("Send mode")

                local env_x, env_y
                if mode_env_wrap then
                    y = y + btn_h + gap
                    env_x = x + inner_w - env_w; env_y = y
                else
                    env_x = x + inner_w - env_w; env_y = y
                end

                local _, env_vis = SendEnvIsVisible(source_track, 0, send_idx, 0)
                r.ImGui_SetCursorScreenPos(ctx, env_x, env_y)
                r.ImGui_InvisibleButton(ctx, "##senv", env_w, btn_h)
                local env_hov = r.ImGui_IsItemHovered(ctx)
                local env_clk = r.ImGui_IsItemClicked(ctx, 0)
                local env_draw_col = env_vis and C.amber or C.text_muted
                if env_hov then env_draw_col = C.text end
                local env_tw = r.ImGui_CalcTextSize(ctx, "ENV")
                r.ImGui_DrawList_AddText(dl, env_x + Round((env_w - env_tw) / 2),
                    env_y + Round((btn_h - r.ImGui_GetTextLineHeight(ctx)) / 2), env_draw_col, "ENV")
                Tip("Send volume envelope")
                if env_clk then
                    r.Undo_BeginBlock()
                    SendEnvSetVisible(source_track, 0, send_idx, 0, not env_vis)
                    r.Undo_EndBlock("Reflex: Toggle send envelope", -1)
                end
                y = y + btn_h + gap
            end

            -- Separator line (2.5px, rounded endcaps, equal gaps above and below)
            do
                local sep_gap = S(UI.edge_pad) + 1
                y = y + sep_gap - gap  -- subtract gap already advanced by mode/ENV row
                local line_h = math.max(S(2), Round(S(2.5)))
                local line_r = line_h / 2
                r.ImGui_DrawList_AddRectFilled(dl, x, y, x + inner_w, y + line_h, C.border, line_r)
                y = y + line_h + sep_gap
            end
        end -- snd_expanded
    end

    -- Track state (mute/solo used by M/S buttons)
    local is_muted = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
    local is_solo = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0
    local cm_rx, cm_ry, cm_rx2, cm_ry2 = 0, 0, 0, 0  -- mute button rect (for overlay redraw)
    local cs_rx, cs_ry, cs_rx2, cs_ry2 = 0, 0, 0, 0  -- solo button rect (for overlay redraw)

    -- Track title (card header — after SND section)
    local _, track_name = r.GetTrackName(track)
    local track_num = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
    local num_str = (track_num <= 0) and "M" or tostring(track_num)
    local num_label, num_slot_label = TrackTitleNumberLabels(num_str)
    local track_color_raw = r.GetTrackColor(track)
    local num_col = track_color_raw ~= 0 and TrackColorToImGui(track_color_raw) or C.text_muted
    local fstep = GetFontStep(UI.font_send_title)
    local title_font = scaled_fonts[fstep]
    local send_title_scale = 1.25
    local title_measure_pushed = PushTrackTitleScaledFont(title_font, send_title_scale)
    local title_h = r.ImGui_GetTextLineHeight(ctx)
    if title_measure_pushed then r.ImGui_PopFont(ctx) end
    local title_font_pushed = PushTrackTitleScaledFont(title_font, send_title_scale)
    local title_text_h = r.ImGui_GetTextLineHeight(ctx)
    local title_text_y = y + Round((title_h - title_text_h) / 2)
    local num_tw = r.ImGui_CalcTextSize(ctx, num_slot_label)
    local num_gap = S(4)
    local name_tw_raw = r.ImGui_CalcTextSize(ctx, track_name)
    local spanner_knob_d = knob_d
    local spanner_knobs_w = spanner_knob_d * 2 + knob_gap
    local title_clip_right = x + inner_w
    if is_folder_spanner then
        title_clip_right = math.max(x, x + inner_w - spanner_knobs_w - gap)
    end
    r.ImGui_DrawList_PushClipRect(dl, x, y, title_clip_right, y + title_h + 2, true)
    r.ImGui_DrawList_AddText(dl, x, title_text_y, num_col, num_label)
    r.ImGui_DrawList_AddText(dl, x + num_tw + num_gap, title_text_y, C.text, track_name)
    r.ImGui_DrawList_PopClipRect(dl)
    if title_font_pushed then r.ImGui_PopFont(ctx) end

    -- v20.441: TitleLink over the actual text bounds (number + name, clipped
    -- to inner_w). Manual hit-test inside TitleLink lets it dispatch even
    -- when ##ctitle below claims the broader area.
    local title_link_w = math.min(num_tw + num_gap + name_tw_raw, math.max(0, title_clip_right - x))
    local title_link_hov, title_link_clk = TitleLink(
        "##ctitle_link", x, title_text_y, title_link_w, title_text_h, track, {})
    if title_link_hov then
        local title_name_x = x + num_tw + num_gap
        local title_name_w = math.max(0, title_link_w - num_tw - num_gap)
        DrawSolidUnderline(dl, title_name_x, title_text_y + title_text_h,
            title_name_x + title_name_w, C.text, 1)
    end

    local title_hit_w = inner_w
    if is_folder_spanner then title_hit_w = math.max(1, title_clip_right - x) end
    r.ImGui_SetCursorScreenPos(ctx, x, y)
    r.ImGui_InvisibleButton(ctx, "##ctitle", title_hit_w, title_h)
    -- v20.441: title-link locate is ADDITIVE — ct_clicked still fires so
    -- callers (folder expand toggle) get title-click as a normal title hit.
    -- v20.442: but peek (Opt+click) is light-touch — suppress fall-through.
    local ct_clicked = r.ImGui_IsItemClicked(ctx, 0) and not nav_title_peek_consumed
    local title_row_h = title_h
    if is_folder_spanner then
        title_row_h = math.max(title_h, knob_d + S(2) + r.ImGui_GetTextLineHeight(ctx))
        local spanner_knob_y = y
        local pan_kx = x + inner_w - knob_d
        local vol_kx = pan_kx - knob_gap - knob_d
        NavParamKnob(dl, "##rkvol", vol_kx, spanner_knob_y, knob_d, "vol",
                     track, nil, rkvol_state,
                     "Reflex: Return volume", "Return volume")
        NavParamKnob(dl, "##rkpan", pan_kx, spanner_knob_y, knob_d, "pan",
                     track, nil, rkpan_state,
                     "Reflex: Return pan", "Return pan")
    end
    y = y + title_row_h + S(UI.section_gap)
    if source_track and send_idx then y = y + 3 end
    -- ct_clicked is returned at end of function for callers (e.g. folder expand toggle)

    -- FX and routing row (wraps when too narrow)
    local is_send_fx_collapsed = insp_fx_collapsed[track] == true
    local ctrl_wrap = false
    do
        local fx_btn_w = math.floor(InspCtrlW("FX") * 1.4)
        local fx_enabled = r.GetMediaTrackInfo_Value(track, "I_FXEN") == 1
        local has_any_fx = r.TrackFX_GetCount(track) > 0
        local fx_txt = (fx_enabled and has_any_fx) and C.fx_power_on or (has_any_fx and C.fx_offline_txt or C.text_muted)

        local route_dot_r = S(4)
        local route_dot_gap = S(7)
        local route_pill_pad = S(8)
        local route_w = route_pill_pad * 2 + route_dot_r * 6 + route_dot_gap * 2
        local route_h = btn_h

        -- v20.420: 3-segment compound [arrow|FX|+] when has FX, [FX|+] when empty.
        -- Mirrors inspector DrawFXChainCompound. Right-click on + opens
        -- ##snd_addfx_ctx (Open Browser / Define Action / Clear).
        local fx_end_x
        local arrow_hit_w = btn_h
        local fx_compound_w = (has_any_fx and arrow_hit_w or 0) + fx_btn_w + btn_h
        local ms_pair_w = btn_h + gap + btn_h
        local controls_w = fx_compound_w + (is_folder_spanner and (gap + ms_pair_w) or 0) + gap + route_w
        ctrl_wrap = controls_w > inner_w
        local fx_y = (ctrl_wrap and not is_folder_spanner) and (y + btn_h + gap) or y
        if has_any_fx then
            local arrow_label = is_send_fx_collapsed and "\xE2\x96\xB6" or "\xE2\x96\xBC"

            r.ImGui_SetCursorScreenPos(ctx, x, fx_y)
            local _, arrow_clk = NavRect("##fxcollapse", arrow_hit_w, btn_h, arrow_label, {
                fg = is_send_fx_collapsed and C.text_dim or C.text,
                arrow_dx = 1.0,
                arrow_dy = 0.5,
                rounding = {tl = 3, bl = 3, tr = 0, br = 0},
            })
            Tip("Collapse FX\nOpt: toggle all sends")
            if arrow_clk then
                if IsAlt(r.ImGui_GetKeyMods(ctx)) then
                    local new_state = not is_send_fx_collapsed
                    for _, st in ipairs(sends_view_tracks) do insp_fx_collapsed[st] = new_state end
                else
                    insp_fx_collapsed[track] = not is_send_fx_collapsed
                    if is_folder_spanner then
                        if insp_fx_collapsed[track] == true then
                            sends_folder_collapse_request = true
                        else
                            sends_folder_expand_request = true
                        end
                    end
                end
                is_send_fx_collapsed = insp_fx_collapsed[track] == true
            end

            -- FX middle segment: no rounding (joined on both sides)
            r.ImGui_SetCursorScreenPos(ctx, x + arrow_hit_w, fx_y)
            local _, cfx_clk = NavRect("FX##cfx", fx_btn_w, btn_h, "FX", {
                fg = fx_txt,
                rounding = {tl = 0, bl = 0, tr = 0, br = 0},
            })
            Tip("Click: FX chain\nShift: bypass all\nOpt: clear chain")
            if cfx_clk then
                local mods = r.ImGui_GetKeyMods(ctx)
                if IsAlt(mods) then
                    -- Opt+click: clear entire chain (v20.418). Mirrors the
                    -- inspector compound (DrawFXChainCompound, v20.411).
                    -- Send modules / return columns get the same idiom now.
                    -- Single undo entry, descending delete for stable indices.
                    local count = r.TrackFX_GetCount(track)
                    if count > 0 then
                        r.Undo_BeginBlock()
                        for i = count - 1, 0, -1 do
                            r.TrackFX_Delete(track, i)
                        end
                        r.Undo_EndBlock("Reflex: Clear FX chain", -1)
                        if insp_fx_sel_track == track then InspFxSelClear() end
                        InspMarkTrackFxDirty(track)
                        if sends_fx_cache then sends_fx_cache[track] = nil end
                    end
                elseif IsShift(mods) then
                    r.Undo_BeginBlock()
                    r.SetMediaTrackInfo_Value(track, "I_FXEN", fx_enabled and 0 or 1)
                    r.Undo_EndBlock("Reflex: FX bypass", -1)
                else
                    local chain_vis = r.TrackFX_GetChainVisible(track)
                    if chain_vis >= 0 then r.TrackFX_Show(track, 0, 0) else r.TrackFX_Show(track, 0, 1) end
                end
            end
            if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##cfx_ctx") end

            -- + button (right): round right corners only. v20.420.
            local addfx_x = x + arrow_hit_w + fx_btn_w
            r.ImGui_SetCursorScreenPos(ctx, addfx_x, fx_y)
            do
                local _, addfx_clk, addfx_act = NavRect("##snd_addfx_btn", btn_h, btn_h, "+", {
                    hov = C.fx_power_on, active = (C.fx_power_on & 0xFFFFFF00) | 0xCC,
                    rounding = {tl = 0, bl = 0, tr = 3, br = 3},
                })
                Tip("Click: FX browser\nDrag: insert at position")
                if addfx_clk then
                    insp_fx_insert_sy = (select(2, r.ImGui_GetMousePos(ctx)))
                    insp_fx_insert_dragging = false
                end
                if addfx_act and not insp_fx_insert_dragging then
                    local _, imy = r.ImGui_GetMousePos(ctx)
                    if math.abs(imy - insp_fx_insert_sy) > S(8) then insp_fx_insert_dragging = true end
                end
                if r.ImGui_IsItemDeactivated(ctx) and not insp_fx_insert_dragging then InspOpenFXBrowser(track) end
                if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##snd_addfx_ctx") end
            end
            fx_end_x = addfx_x + btn_h
        else
            -- No FX: [FX | +] compound
            r.ImGui_SetCursorScreenPos(ctx, x, fx_y)
            local _, cfx_clk = NavRect("FX##cfx", fx_btn_w, btn_h, "FX", {
                fg = fx_txt,
                rounding = {tl = 3, bl = 3, tr = 0, br = 0},
            })
            if cfx_clk then
                local chain_vis = r.TrackFX_GetChainVisible(track)
                if chain_vis >= 0 then r.TrackFX_Show(track, 0, 0) else r.TrackFX_Show(track, 0, 1) end
            end
            if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##cfx_ctx") end

            local addfx_x = x + fx_btn_w
            r.ImGui_SetCursorScreenPos(ctx, addfx_x, fx_y)
            do
                local _, addfx_clk, addfx_act = NavRect("##snd_addfx_btn", btn_h, btn_h, "+", {
                    hov = C.fx_power_on, active = (C.fx_power_on & 0xFFFFFF00) | 0xCC,
                    rounding = {tl = 0, bl = 0, tr = 3, br = 3},
                })
                Tip("Click: FX browser\nDrag: insert at position")
                if addfx_clk then
                    insp_fx_insert_sy = (select(2, r.ImGui_GetMousePos(ctx)))
                    insp_fx_insert_dragging = false
                end
                if addfx_act and not insp_fx_insert_dragging then
                    local _, imy = r.ImGui_GetMousePos(ctx)
                    if math.abs(imy - insp_fx_insert_sy) > S(8) then insp_fx_insert_dragging = true end
                end
                if r.ImGui_IsItemDeactivated(ctx) and not insp_fx_insert_dragging then InspOpenFXBrowser(track) end
                if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##snd_addfx_ctx") end
            end
            fx_end_x = addfx_x + btn_h
        end

        -- FX chain right-click context menu (send/return module)
        PushPopupStyle()
        if r.ImGui_BeginPopup(ctx, "##cfx_ctx") then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), C.fx_ctrl_hover)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
            if r.ImGui_MenuItem(ctx, "Add FX") then InspOpenFXBrowser(track) end
            r.ImGui_Separator(ctx)
            if r.ImGui_MenuItem(ctx, "Offline all") then
                r.Undo_BeginBlock()
                for fi = 0, r.TrackFX_GetCount(track) - 1 do
                    r.TrackFX_SetOffline(track, fi, true)
                end
                r.Undo_EndBlock("Reflex: Offline all FX", -1)
                InspRefreshFXState()
            end
            if r.ImGui_MenuItem(ctx, "Online all") then
                r.Undo_BeginBlock()
                for fi = 0, r.TrackFX_GetCount(track) - 1 do
                    r.TrackFX_SetOffline(track, fi, false)
                end
                r.Undo_EndBlock("Reflex: Online all FX", -1)
                InspRefreshFXState()
            end
            r.ImGui_PopStyleColor(ctx, 2)
            r.ImGui_EndPopup(ctx)
        end
        PopPopupStyle()

        -- Add-FX (+) right-click menu — mirrors inspector ##addfx_ctx (v20.420).
        PushPopupStyle()
        if r.ImGui_BeginPopup(ctx, "##snd_addfx_ctx") then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), C.fx_ctrl_hover)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
            if insp_fx_browser_action > 0 then
                if r.ImGui_MenuItem(ctx, "Run Custom FX Browser Action") then
                    if not ExternalFxBrowserLaunch(track, FX_BROWSER_PROVIDER_CUSTOM) then
                        r.Main_OnCommand(insp_fx_browser_action, 0)
                    end
                end
            end
            if r.ImGui_MenuItem(ctx, "Open REAPER FX Browser") then
                ExternalFxBrowserLaunch(track, FX_BROWSER_PROVIDER_REAPER)
            end
            r.ImGui_Separator(ctx)
            local action_label = insp_fx_browser_action > 0 and "Change FX Browser Action" or "Define FX Browser Action"
            if r.ImGui_MenuItem(ctx, action_label) then
                insp_fx_prompt_active = true
                if r.PromptForAction then r.PromptForAction(1, 0, 0) end
            end
            if insp_fx_browser_action > 0 then
                if r.ImGui_MenuItem(ctx, "Clear Custom Action") then
                    insp_fx_browser_action = 0
                    InspSaveFXBrowserAction(0)
                end
            end
            r.ImGui_PopStyleColor(ctx, 2)
            r.ImGui_EndPopup(ctx)
        end
        PopPopupStyle()

        if is_folder_spanner then
            local m_x = fx_end_x + gap
            local ms_y = fx_y
            local s_x = m_x + btn_h + gap
            if ctrl_wrap or s_x + btn_h > x + inner_w - route_w - gap then
                ctrl_wrap = true
                m_x = x
                ms_y = fx_y + btn_h + gap
                s_x = m_x + btn_h + gap
            end
            if s_x + btn_h <= x + inner_w then
                local m_opts = MuteOpts(is_muted)
                r.ImGui_SetCursorScreenPos(ctx, m_x, ms_y)
                local _, cm_clk = NavRect("M##cm", btn_h, btn_h, "M", m_opts)
                cm_rx, cm_ry = r.ImGui_GetItemRectMin(ctx)
                cm_rx2, cm_ry2 = r.ImGui_GetItemRectMax(ctx)
                Tip("Mute")
                if cm_clk then
                    r.Undo_BeginBlock()
                    r.SetMediaTrackInfo_Value(track, "B_MUTE", is_muted and 0 or 1)
                    r.Undo_EndBlock("Reflex: Mute", -1)
                end

                local s_opts = SoloOpts(is_solo)
                r.ImGui_SetCursorScreenPos(ctx, s_x, ms_y)
                local _, cs_clk = NavRect("S##cs", btn_h, btn_h, "S", s_opts)
                cs_rx, cs_ry = r.ImGui_GetItemRectMin(ctx)
                cs_rx2, cs_ry2 = r.ImGui_GetItemRectMax(ctx)
                Tip("Solo")
                if cs_clk then
                    r.Undo_BeginBlock()
                    r.SetMediaTrackInfo_Value(track, "I_SOLO", is_solo and 0 or 2)
                    r.Undo_EndBlock("Reflex: Solo", -1)
                end
            end
        end

        -- Routing pill stays on the upper row when controls wrap so FX remains
        -- visually attached to the FX chain below.
        local route_x, ry
        if ctrl_wrap and not is_folder_spanner then
            route_x = x
            ry = y + Round((btn_h - route_h) / 2)
        else
            route_x = x + inner_w - route_w
            ry = y + Round((btn_h - route_h) / 2)
        end
        local route_r = S(UI.corner_r)
        local has_parent = r.GetMediaTrackInfo_Value(track, "B_MAINSEND") == 1
        local has_sends_r = r.GetTrackNumSends(track, 0) > 0
        local has_receives = r.GetTrackNumSends(track, -1) > 0
        r.ImGui_DrawList_AddRectFilled(dl, route_x, ry, route_x + route_w, ry + route_h, C.route_bg, route_r)
        local dots_total = route_dot_r * 6 + route_dot_gap * 2
        local dots_off = Round((route_w - dots_total) / 2)
        local rcy = ry + route_h / 2
        local rcx1 = route_x + dots_off + route_dot_r
        r.ImGui_DrawList_AddCircleFilled(dl, rcx1, rcy, route_dot_r, has_parent and C.route_parent or C.route_dim, 24)
        r.ImGui_DrawList_AddCircleFilled(dl, rcx1 + route_dot_r * 2 + route_dot_gap, rcy, route_dot_r, has_sends_r and C.route_send or C.route_dim, 24)
        r.ImGui_DrawList_AddCircleFilled(dl, rcx1 + (route_dot_r * 2 + route_dot_gap) * 2, rcy, route_dot_r, has_receives and C.route_recv or C.route_dim, 24)
        r.ImGui_SetCursorScreenPos(ctx, route_x, ry)
        r.ImGui_InvisibleButton(ctx, "##croute", route_w, route_h)
        if r.ImGui_IsItemHovered(ctx) then ShowRoutingTooltip(track) end
        if r.ImGui_IsItemClicked(ctx, 0) then
            r.Undo_BeginBlock()
            r.PreventUIRefresh(1)
            local prev_sel = {}
            for si = 0, r.CountSelectedTracks(0) - 1 do prev_sel[#prev_sel + 1] = r.GetSelectedTrack(0, si) end
            r.SetOnlyTrackSelected(track)
            r.Main_OnCommand(40293, 0)
            for si = 0, r.CountTracks(0) - 1 do r.SetMediaTrackInfo_Value(r.GetTrack(0, si), "I_SELECTED", 0) end
            for _, t in ipairs(prev_sel) do
                if r.ValidatePtr(t, "MediaTrack*") then r.SetMediaTrackInfo_Value(t, "I_SELECTED", 1) end
            end
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("Reflex: Show routing", 0)
        end
    end
    y = y + btn_h + gap + (ctrl_wrap and (btn_h + gap) or 0)

    -- FX list (bold text, matching inspector row height and spacing)
    local fx_step = GetFontStep(UI.font_fx)
    local fx_font = scaled_fonts[fx_step]  -- bold (matches inspector)
    if fx_font then r.ImGui_PushFont(ctx, fx_font) end
    local fx_h = S(UI.btn_h)  -- match inspector row height
    local fx_gap_v = S(UI.fx_gap)
    local fx_r = S(UI.corner_r)
    local fx_pad = FXPowerNamePad(fx_h)
    local fx_cat_w = FXCategoryBarWidth()
    local fx_power_hit_w = fx_h
    local fxth = r.ImGui_GetTextLineHeight(ctx)

    local fc = sends_fx_cache[track]
    local fx_count = fc and fc.count or r.TrackFX_GetCount(track)
    local fx_names = fc and fc.names or {}
    local slots = is_send_fx_collapsed and 0 or math.max(fx_count, max_fx)

    -- Reset per-column rects for drag target detection
    local col_fx_rects = {}

    if not is_send_fx_collapsed then
    for fi = 0, slots - 1 do
        local fy = y + fi * (fx_h + fx_gap_v)
        if fi < fx_count then
            -- Build fx state matching InspDrawFXRow
            local fx_en = r.TrackFX_GetEnabled(track, fi)
            local fx_off = r.TrackFX_GetOffline(track, fi)
            local fx_name = fx_names[fi] or ""
            -- v20.406: cache GUID once per row for multi-select + drag-source logic
            local fx_guid = r.TrackFX_GetFXGUID(track, fi) or ""
            local is_instr = false
            local rv_ft, ft_str = r.TrackFX_GetNamedConfigParm(track, fi, "fx_type")
            if rv_ft and ft_str and ft_str:match("i$") then is_instr = true end
            local is_cont = false
            local rv_cc, cc_str = r.TrackFX_GetNamedConfigParm(track, fi, "container_count")
            if rv_cc and tonumber(cc_str) and tonumber(cc_str) > 0 then is_cont = true end
            local wet_val = 1.0
            local np_w = r.TrackFX_GetNumParams(track, fi)
            for p = np_w - 1, math.max(0, np_w - 3), -1 do
                local _, pn = r.TrackFX_GetParamName(track, fi, p, "")
                if pn == "Wet" then wet_val = r.TrackFX_GetParam(track, fi, p); break end
            end
            local is_dry = not fx_off and fx_en and wet_val < 0.005

            -- Colors via shared FxStateColors helper
            local bg, hover_c, active_c, txt = FxStateColors(is_cont, is_instr, fx_off, fx_en, is_dry, false, wet_val)

            local fx_category = FXPluginCategory(track, fi, fx_name, InspStripName(fx_name), is_cont, is_instr)
            local row_bg = C.fx_row_bg or bg
            local row_corners = FXRowStackCorners(fi + 1, fx_count)
            local body_round_flags = FXRowBodyCornerFlags(row_corners, fx_cat_w)
            local row_hovered_pre = r.ImGui_IsMouseHoveringRect(ctx, x, fy, x + inner_w, fy + fx_h)
            local power_hovered_pre = row_hovered_pre
                or r.ImGui_IsMouseHoveringRect(ctx, x + fx_cat_w, fy, x + fx_cat_w + fx_power_hit_w, fy + fx_h)
            local cat_col = FXCategoryColor(fx_category, is_cont, is_instr, fx_off, fx_en)
            DrawFXRowBase(dl, x, fy, inner_w, fx_power_hit_w, fx_h, row_bg,
                FXPowerEndcapBgColor(fx_en, power_hovered_pre, row_bg, fx_off, false), fx_r, cat_col, fx_cat_w, row_corners)
            if C.fx_row_border then
                DrawFXRowRightOutline(dl, x, fy, inner_w, fx_h, C.fx_row_border, fx_r, 1, row_corners)
            end

            col_fx_rects[fi] = { cy = fy, h = fx_h, cx = x, w = inner_w }

            r.ImGui_SetCursorScreenPos(ctx, x, fy)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x00000000)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x00000000)
            r.ImGui_SetCursorScreenPos(ctx, x + fx_cat_w + fx_power_hit_w, fy)
            local sel = r.ImGui_Selectable(ctx, "##sfxi" .. fi, false,
                r.ImGui_SelectableFlags_AllowOverlap(), math.max(S(20), inner_w - fx_cat_w - fx_power_hit_w), fx_h)
            local body_hovered = r.ImGui_IsItemHovered(ctx)
            local hovered = r.ImGui_IsMouseHoveringRect(ctx, x + fx_cat_w + fx_power_hit_w, fy, x + inner_w, fy + fx_h)
            local row_hovered_full = row_hovered_pre
            r.ImGui_PopStyleColor(ctx, 3)
            if fx_off and row_hovered_full then
                ShowOfflineFxStateTooltip(fx_en)
            -- v20.424: drop "Click: open" (self-explanatory). Suppress during
            -- carry mode — competes with insert-indicator
            -- visuals and pill messaging. Descriptive category, opt_tooltips-gated.
            elseif body_hovered and not FxClipHasContent() then
                Tip("Shift: bypass\nOpt: remove\nCmd+Shift: offline")
            end

            -- v20.427: drag begin/activate, hover/active fill + legend, click
            -- dispatch, and right-click open all extracted to FxRowInteract
            -- (Phase 3 unification). Sends is already 0-based on fi, matching
            -- fx_drag convention.
            FxRowInteract({
                track = track, fi = fi, guid = fx_guid, surface = "sends",
                popup_id = "##sfx_ctx" .. fi,
                sel = sel, hovered = hovered, item_hovered = body_hovered,
                dl = dl, cx = x, cy = fy, w = inner_w, h = fx_h, radius = fx_r,
                fill_x = x + fx_cat_w + fx_power_hit_w, fill_w = math.max(1, inner_w - fx_cat_w - fx_power_hit_w),
                body_round_flags = body_round_flags,
                hover_col = hover_c, active_col = active_c,
                enabled = fx_en, offline = fx_off,
            })

            DrawFXPowerButton("##sfxpower" .. fi, x + fx_cat_w, fy, fx_h, fx_en, {
                track = track, fi = fi, guid = fx_guid, surface = "sends",
                enabled = fx_en, offline = fx_off,
            })

            -- v20.430: inline rename mode swaps the AddText for an InputText
            -- when the rename state targets this row. Same style/focus/blur
            -- pattern as InspDrawFXRow's rename block. On commit, invalidate
            -- sends_fx_cache so the new name shows; if the rename target track
            -- is also insp_track (self-send), refresh inspector cache too.
            if insp_rename_type == "fx" and insp_rename_track == track
               and insp_rename_idx == fi then
                insp_rename_frames = insp_rename_frames + 1
                r.ImGui_SetCursorScreenPos(ctx, x + fx_cat_w + fx_pad, fy + Round((fx_h - fxth) / 2))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.fx_ctrl_bg)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), S(4), 0)
                r.ImGui_SetNextItemWidth(ctx, inner_w - fx_cat_w - fx_pad - S(UI.pad_sm))
                if not insp_rename_focus then
                    r.ImGui_SetKeyboardFocusHere(ctx); insp_rename_focus = true
                end
                local changed; changed, insp_rename_buf = r.ImGui_InputText(ctx, "##sfxrename", insp_rename_buf,
                    r.ImGui_InputTextFlags_EnterReturnsTrue() | r.ImGui_InputTextFlags_AutoSelectAll())
                r.ImGui_PopStyleVar(ctx, 2); r.ImGui_PopStyleColor(ctx, 2)
                if changed then
                    if r.TrackFX_SetNamedConfigParm then
                        r.TrackFX_SetNamedConfigParm(track, fi, "renamed_name", insp_rename_buf)
                    end
                    if sends_fx_cache then sends_fx_cache[track] = nil end
                    if track == insp_track then InspScanTrack(track) end
                    insp_rename_type = nil
                elseif insp_rename_frames > 3 and not r.ImGui_IsItemActive(ctx) then
                    insp_rename_type = nil
                end
            else
                local name_col = (not fx_en and not fx_off and hovered) and C.fx_power_off or txt
                local name_font_pushed = false
                if fx_off then
                    name_font_pushed = PushFont(GetSteppedFont(UI.font_fx, "italic"))
                end
                local name_x = x + fx_cat_w + fx_pad
                local name_avail = math.max(0, x + inner_w - S(UI.pad_sm) - name_x)
                local display_name = fx_name
                local name_tw = r.ImGui_CalcTextSize(ctx, display_name)
                if name_tw > name_avail then
                    local ellipsis = "\xE2\x80\xA6"
                    local ew = r.ImGui_CalcTextSize(ctx, ellipsis)
                    while name_tw + ew > name_avail and #display_name > 0 do
                        display_name = Utf8DropLast(display_name)
                        name_tw = r.ImGui_CalcTextSize(ctx, display_name)
                    end
                    if name_avail >= ew then
                        display_name = display_name .. ellipsis
                    else
                        display_name = ""
                    end
                end
                r.ImGui_DrawList_AddText(dl, name_x, fy + Round((fx_h - fxth) / 2), name_col, display_name)
                PopFont(name_font_pushed)
            end

            -- Fade overlay for offline/dry (matching InspDrawFXRow)
            if fx_off then
                local d = FXPowerCircleDiameter()
                r.ImGui_DrawList_AddCircleFilled(dl, x + fx_cat_w + fx_h / 2, fy + fx_h / 2, d / 2, C.fx_power_offline, NAV_CIRCLE_SEGMENTS)
            elseif is_dry then
                DrawFXRowOverlay(dl, x, fy, inner_w, fx_h, fx_h, fx_cat_w, (C.bg & 0xFFFFFF00) | 0x60, fx_r, row_corners)
            end

            -- v20.422+: outline cascade extracted to FxRowOutlineColor.
            -- See helper for state priority (drag-source / paste-pulse / carry / select).
            local sends_outline_col = FxRowOutlineColor(track, fi, fx_guid, "sends")
            if sends_outline_col then
                DrawFXRowRightOutline(dl, x, fy, inner_w, fx_h, sends_outline_col, fx_r, SOURCE_STROKE_W, row_corners)
            end
        else
            -- v20.420: empty slots render nothing. Variant B — column heights
            -- still equalize across the row of sibling columns (slots = max_fx)
            -- so M/S knobs stay aligned at column bottoms, but the empty space
            -- is invisible (no placeholder cells, no trailing add-FX row).
            -- Add-FX entry is now exclusively the + button on the compound
            -- header above. This makes the FX area render identically to the
            -- inspector card.
        end
    end

    -- Register this sends-view chain as drop target (v20.396+).
    -- col_fx_rects is already 0-based keyed. body_rect covers entire column card
    -- (cx/cy/col_w/col_h from DrawCompactTrackColumn args) so hover works on
    -- header, M/S, and empty-chain areas. fx_area_bottom_y is the Y where the
    -- next row would appear — used for empty-chain indicator placement.
    if (fx_drag.active or FxClipHasContent()) and track and r.ValidatePtr(track, "MediaTrack*") then
        local body = { x = cx, y = cy, w = col_w, h = col_h }
        local fx_area_bot_y
        if fx_count > 0 and col_fx_rects[fx_count - 1] then
            local last = col_fx_rects[fx_count - 1]
            fx_area_bot_y = last.cy + last.h
        else
            fx_area_bot_y = y  -- empty chain: FX area top = bottom
        end
        -- Row bounds for empty-chain indicator sizing (falls back to x/inner_w)
        local row_x = (col_fx_rects[0] and col_fx_rects[0].cx) or x
        local row_w = (col_fx_rects[0] and col_fx_rects[0].w) or inner_w
        FxDropTargetRegister("return", track, col_fx_rects, fx_count, body,
            "send_" .. tostring(track), fx_area_bot_y, row_x, row_w)
    end
    -- Clear drag seed if mouse released without passing threshold (legacy safety)
    if fx_drag.src_fis and fx_drag.src_surface == "sends" and fx_drag.src_track == track
       and not fx_drag.active and not r.ImGui_IsMouseDown(ctx, 0) then
        FxDragClear()
    end
    end -- not is_send_fx_collapsed

    if fx_font then r.ImGui_PopFont(ctx) end

    -- Track controls section (vol/pan knobs + M/S at very bottom)
    if not is_folder_spanner then
        local text_h = r.ImGui_GetTextLineHeight(ctx)
        -- v20.420: trailing add-FX row removed. Height = real FX rows + gaps only.
        local fx_area_h = is_send_fx_collapsed and 0
                          or (slots > 0 and (slots * fx_h + (slots - 1) * fx_gap_v) or 0)
        local knob_unit = knob_d + S(2) + text_h
        local knob_pair_h = knobs_wrap and (knob_unit * 2 + gap) or knob_unit
        local return_controls_h = is_folder_column and knob_pair_h or (knob_pair_h + S(UI.section_gap) + btn_h)
        local ret_y = cy + col_h - S(UI.send_pad_bot) - return_controls_h
        local knob_y = ret_y

        if knobs_wrap then
            -- Stacked: vol on top, pan below
            local kx = is_folder_column and (x + inner_w - knob_d) or (x + Round((inner_w - knob_d) / 2))

            NavParamKnob(dl, "##rkvol", kx, knob_y, knob_d, "vol",
                         track, nil, rkvol_state,
                         "Reflex: Return volume", "Return volume")
            knob_y = knob_y + knob_d + S(2) + text_h + gap

            NavParamKnob(dl, "##rkpan", kx, knob_y, knob_d, "pan",
                         track, nil, rkpan_state,
                         "Reflex: Return pan", "Return pan")
        else
            -- Side by side: fixed minimum gap, centered as a packed pair.
            local knobs_total_w = knob_d * 2 + knob_gap
            local vol_kx = is_folder_column and (x + inner_w - knobs_total_w) or (x + Round((inner_w - knobs_total_w) / 2))
            local pan_kx = vol_kx + knob_d + knob_gap

            NavParamKnob(dl, "##rkvol", vol_kx, knob_y, knob_d, "vol",
                         track, nil, rkvol_state,
                         "Reflex: Return volume", "Return volume")

            NavParamKnob(dl, "##rkpan", pan_kx, knob_y, knob_d, "pan",
                         track, nil, rkpan_state,
                         "Reflex: Return pan", "Return pan")
        end

        -- M/S buttons (return track mute/solo)
        -- v20.441: inspect arrow removed (locate via title click instead).
        local card_hov = r.ImGui_IsMouseHoveringRect(ctx, cx, cy, cx + col_w, cy + col_h)
        local ms_w = btn_h
        local ms_gap = S(UI.pad_sm)
        local ms_pair_w = ms_w + ms_gap + ms_w
        local m_x = is_folder_column and x or (x + Round((inner_w - ms_pair_w) / 2))
        local s_x = m_x + ms_w + ms_gap
        local ms_y = is_folder_column
            and (cy + col_h - S(UI.send_pad_bot) - btn_h)
            or (cy + col_h - S(UI.send_pad_bot - 3) - btn_h)

        local m_opts = MuteOpts(is_muted)
        r.ImGui_SetCursorScreenPos(ctx, m_x, ms_y)
        local _, cm_clk = NavRect("M##cm", ms_w, btn_h, "M", m_opts)
        -- Save mute button rect for overlay redraw
        cm_rx, cm_ry = r.ImGui_GetItemRectMin(ctx)
        cm_rx2, cm_ry2 = r.ImGui_GetItemRectMax(ctx)
        Tip("Mute")
        if cm_clk then
            r.Undo_BeginBlock()
            r.SetMediaTrackInfo_Value(track, "B_MUTE", is_muted and 0 or 1)
            r.Undo_EndBlock("Reflex: Mute", -1)
        end

        local s_opts = SoloOpts(is_solo)
        r.ImGui_SetCursorScreenPos(ctx, s_x, ms_y)
        local _, cs_clk = NavRect("S##cs", ms_w, btn_h, "S", s_opts)
        cs_rx, cs_ry = r.ImGui_GetItemRectMin(ctx)
        cs_rx2, cs_ry2 = r.ImGui_GetItemRectMax(ctx)
        Tip("Solo")
        if cs_clk then
            r.Undo_BeginBlock()
            r.SetMediaTrackInfo_Value(track, "I_SOLO", is_solo and 0 or 2)
            r.Undo_EndBlock("Reflex: Solo", -1)
        end
    end

    -- Mute fade overlay (covers entire card, active M/S indicators redrawn on top)
    if is_muted then
        local fade = (C.bg & 0xFFFFFF00) | 0x70
        r.ImGui_DrawList_AddRectFilled(dl, rcx, rcy, rcx2, rcy2, fade, col_r)
        DrawStaticRectButton(dl, { cm_rx, cm_ry, cm_rx2, cm_ry2 }, "M", MuteOpts(true))
        if is_solo then
            DrawStaticRectButton(dl, { cs_rx, cs_ry, cs_rx2, cs_ry2 }, "S", SoloOpts(true))
        end
        if SendsOverviewSourcePinned and SendsOverviewSourcePinned(source_track) then
            DrawSolidRoundedRectOutline(dl, rcx, rcy, rcx2, rcy2, C.source_stroke, col_r, SOURCE_STROKE_W)
        end
    end

    return ct_clicked
end

FxBrowserRender = function()
    if not fx_browser_open then return end
    if not fx_browser_cache then FxBrowserBuildCache() end

    local win_w = S(340)
    local win_h = S(450)

    r.ImGui_SetNextWindowSize(ctx, win_w, win_h, r.ImGui_Cond_FirstUseEver())
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), C.bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), C.bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), C.btn_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), C.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.fx_ctrl_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarBg(), C.bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrab(), C.btn_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), C.btn_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), C.btn_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), C.btn_active)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), S(8), S(8))
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), S(4), S(4))
    local fx_smooth_tess_count = 0
    if r.ImGui_StyleVar_CircleTessellationMaxError then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CircleTessellationMaxError(), 0.03)
        fx_smooth_tess_count = 1
    end

    local visible, open = r.ImGui_Begin(ctx, "Plugin Browser###fx_browser", true,
        r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoDocking())

    if visible then
        -- Search box
        r.ImGui_SetNextItemWidth(ctx, -1)
        if fx_browser_focus_search then
            r.ImGui_SetKeyboardFocusHere(ctx)
            fx_browser_focus_search = false
        end
        local changed, new_search = r.ImGui_InputTextWithHint(ctx, "##fxsearch", "Search plugins...",
            fx_browser_search, r.ImGui_InputTextFlags_AutoSelectAll() | r.ImGui_InputTextFlags_EscapeClearsAll())
        if changed then
            fx_browser_search = new_search
        end
        -- ESC closes browser when search is empty
        if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) and fx_browser_search == "" then
            fx_browser_open = false
        end

        r.ImGui_Spacing(ctx)

        -- Build filtered list
        local search_lower = fx_browser_search:lower()
        local results = {}
        if fx_browser_cache then
            if search_lower == "" then
                results = fx_browser_cache
            else
                -- Multi-word: all words must match
                local words = {}
                for w in search_lower:gmatch("%S+") do words[#words + 1] = w end
                for _, entry in ipairs(fx_browser_cache) do
                    local match = true
                    for _, w in ipairs(words) do
                        if not entry.lower:find(w, 1, true) then match = false; break end
                    end
                    if match then results[#results + 1] = entry end
                end
            end
        end

        -- Results count
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text_dim)
        r.ImGui_Text(ctx, #results .. " plugins")
        r.ImGui_PopStyleColor(ctx, 1)

        -- Results list
        local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
        if r.ImGui_BeginChild(ctx, "##fxresults", avail_w, avail_h) then
            local item_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)

            -- Reuse the clipper resource; creating one per frame trips ReaImGui's resource warning.
            if not fx_browser_clipper or (r.ImGui_ValidatePtr and
                not r.ImGui_ValidatePtr(fx_browser_clipper, "ImGui_ListClipper*"))
            then
                fx_browser_clipper = r.ImGui_CreateListClipper(ctx)
            end
            r.ImGui_ListClipper_Begin(fx_browser_clipper, #results)
            while r.ImGui_ListClipper_Step(fx_browser_clipper) do
                local display_start, display_end = r.ImGui_ListClipper_GetDisplayRange(fx_browser_clipper)
                for i = display_start, display_end - 1 do
                    local entry = results[i + 1]
                    if entry then
                        r.ImGui_PushID(ctx, i)

                        -- Type badge
                        local badge = entry.type
                        if badge ~= "" then
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text_muted)
                            r.ImGui_Text(ctx, badge)
                            r.ImGui_PopStyleColor(ctx, 1)
                            r.ImGui_SameLine(ctx, 0, S(6))
                        end

                        -- Selectable row
                        local sel = r.ImGui_Selectable(ctx, entry.display, false,
                            r.ImGui_SelectableFlags_AllowDoubleClick())

                        -- Double-click: assign to target button, or add to target track
                        if sel and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
                            if fx_browser_target_track and r.ValidatePtr(fx_browser_target_track, "MediaTrack*") then
                                r.Undo_BeginBlock()
                                r.TrackFX_AddByName(fx_browser_target_track, entry.name, false, -1)
                                r.Undo_EndBlock("Reflex: Add FX", -1)
                                fx_browser_open = false
                                fx_browser_target_track = nil
                            elseif fx_browser_target_btn then
                                FxBrowserAssign(fx_browser_target_btn, entry.name)
                                fx_browser_open = false
                            end
                        end

                        -- Drag source
                        if r.ImGui_BeginDragDropSource(ctx, r.ImGui_DragDropFlags_SourceNoPreviewTooltip()) then
                            r.ImGui_SetDragDropPayload(ctx, "FX_PLUGIN", entry.name)
                            fx_browser_drag_name = entry.display
                            r.ImGui_EndDragDropSource(ctx)
                        end

                        r.ImGui_PopID(ctx)
                    end
                end
            end
            r.ImGui_ListClipper_End(fx_browser_clipper)
            r.ImGui_EndChild(ctx)
        end
    end

    -- Tooltip while dragging (must be inside Begin/End scope to render)
    if fx_browser_drag_name and r.ImGui_IsMouseDown(ctx, 0) then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), S(5), S(3))
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), S(4))
        r.ImGui_BeginTooltip(ctx)
        r.ImGui_Text(ctx, fx_browser_drag_name)
        r.ImGui_EndTooltip(ctx)
        r.ImGui_PopStyleVar(ctx, 2)
    end

    r.ImGui_End(ctx)

    if not open then
        fx_browser_open = false
        fx_browser_drag_name = nil
        fx_browser_target_track = nil
    end

    r.ImGui_PopStyleVar(ctx, 2 + fx_smooth_tess_count)
    r.ImGui_PopStyleColor(ctx, 10)

    -- Handle drops OUTSIDE the browser window (TCP track, remote buttons, FX chain)
    if not r.ImGui_IsMouseDown(ctx, 0) and fx_browser_drag_name then
        local drop_name = fx_browser_drag_name
        fx_browser_drag_name = nil

        -- Get actual plugin name from drag payload (check if payload is still available)
        -- Since mouse is released, payload may be gone — use drop_name to find full ident
        local full_ident = nil
        if fx_browser_cache then
            for _, e in ipairs(fx_browser_cache) do
                if e.display == drop_name then full_ident = e.name; break end
            end
        end
        if not full_ident then return end

        -- Check if dropped on a remote button
        local mx, my = r.GetMousePosition()
        local dropped_on_btn = nil
        for bi, rect in pairs(remote_btn_rects) do
            if mx >= rect.x and mx <= rect.x + rect.w and my >= rect.y and my <= rect.y + rect.h then
                dropped_on_btn = bi
                break
            end
        end

        if dropped_on_btn then
            -- Assign plugin to remote button
            FxBrowserAssign(dropped_on_btn, full_ident)
        elseif not r.ImGui_IsWindowHovered(ctx, r.ImGui_HoveredFlags_AnyWindow()) then
            -- Dropped outside all ImGui windows — check TCP
            local dest_track = r.GetTrackFromPoint(mx, my)
            if dest_track and r.ValidatePtr(dest_track, "MediaTrack*") then
                r.Undo_BeginBlock()
                r.TrackFX_AddByName(dest_track, full_ident, false, -1)
                r.Undo_EndBlock("Reflex: Insert " .. drop_name, -1)
            end
        else
            -- Check if over FX chain area — use insp_fx_rects
            if insp_track and insp_fx_rects and #insp_fx_rects > 0 then
                local _, imy = r.ImGui_GetMousePos(ctx)
                local ins_target = 0
                for fi = 1, #insp_fx_rects do
                    local rc = insp_fx_rects[fi]
                    if rc and imy > rc.cy + rc.h / 2 then ins_target = fi end
                end
                -- Check if mouse is within the FX chain horizontal bounds
                local rc_first = insp_fx_rects[1]
                local imx = (select(1, r.ImGui_GetMousePos(ctx)))
                if rc_first and imx >= rc_first.cx and imx <= rc_first.cx + rc_first.w then
                    r.Undo_BeginBlock()
                    local before_count = r.TrackFX_GetCount(insp_track)
                    local new_idx = r.TrackFX_AddByName(insp_track, full_ident, false, -1)
                    if new_idx >= 0 and ins_target < before_count then
                        r.TrackFX_CopyToTrack(insp_track, before_count, insp_track, ins_target, true)
                    end
                    r.Undo_EndBlock("Reflex: Insert " .. drop_name .. " at position", -1)
                end
            end
        end
    end

    -- Draw insert indicator in FX chain while dragging from browser
    if fx_browser_drag_name and insp_fx_rects and #insp_fx_rects > 0 and insp_track then
        local _, imy = r.ImGui_GetMousePos(ctx)
        local imx = (select(1, r.ImGui_GetMousePos(ctx)))
        local rc_first = insp_fx_rects[1]
        if rc_first and imx >= rc_first.cx and imx <= rc_first.cx + rc_first.w then
            local ins_target = 0
            for fi = 1, #insp_fx_rects do
                local rc = insp_fx_rects[fi]
                if rc and imy > rc.cy + rc.h / 2 then ins_target = fi end
            end
            local rc_ref = ins_target > 0 and insp_fx_rects[ins_target] or insp_fx_rects[1]
            if rc_ref then
                local ins_line_y
                if ins_target == 0 then
                    ins_line_y = rc_ref.cy - S(2)
                elseif insp_fx_rects[ins_target + 1] then
                    ins_line_y = Round((rc_ref.cy + rc_ref.h + insp_fx_rects[ins_target + 1].cy) / 2)
                else
                    ins_line_y = rc_ref.cy + rc_ref.h + S(2)
                end
                local ins_inset = S(4)
                local dl_fg = r.ImGui_GetForegroundDrawList(ctx)
                local ins_thick = math.max(2, S(2))
                local ins_r = math.floor(ins_thick / 2)
                local ins_col = C.fx_drag_move or C.amber or rgb(0xD29922)
                r.ImGui_DrawList_AddRectFilled(dl_fg, rc_ref.cx + ins_inset, ins_line_y - ins_r,
                    rc_ref.cx + rc_ref.w - ins_inset, ins_line_y + ins_r, ins_col, ins_r)
            end
        end
    end
end

RemoteLoadPages()
RemoteLoadButtons()
insp_fx_browser_action = InspLoadFXBrowserAction()

-- =========================================================================
-- v20.440: LOCATE & TITLE LINK
-- Universal "track name = link to that track in REAPER" gesture.
-- Plain click locates: visibility on, parent folders expanded, scroll TCP
-- to center, select. Opt+click peeks: same REAPER-side mutation but saves
-- and restores the prior selection so Reflex's inspector / secondary
-- card stays put. View history follows existing rules — unpinned plain
-- locate pushes via the main loop's selection-tracking branch; pinned
-- plain locate pushes via pre/post around the mutation, except when the
-- target is in flow_view_chain in which case the existing flow-browse
-- silent-track-switch path handles the push. Peek never pushes history.
-- =========================================================================

LocateInREAPER = function(track, peek)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end

    -- Peek: mutate visibility + expand parents + scroll to center, but
    -- DO NOT touch selection. Saving and restoring selection had a race
    -- with REAPER's own auto-scroll-on-selection (the re-selection of the
    -- previously selected track would scroll back to it, defeating the
    -- locate's scroll). v20.441: scroll independently of selection.
    if peek then
        local ti = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) - 1
        if ti < 0 then return end
        -- Walk forward to find all parent folders of our track
        local folder_stack = {}
        for i = 0, ti - 1 do
            local t = r.GetTrack(0, i)
            local fd = r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
            if fd == 1 then
                folder_stack[#folder_stack + 1] = t
            elseif fd < 0 then
                for _ = 1, math.abs(fd) do
                    if #folder_stack > 0 then folder_stack[#folder_stack] = nil end
                end
            end
        end
        for _, pt in ipairs(folder_stack) do
            SetTrackVis(pt, true)
            r.SetMediaTrackInfo_Value(pt, "I_FOLDERCOMPACT", 0)
        end
        SetTrackVis(track, true)
        -- Direct scroll-to-center without selection mutation.
        if r.JS_Window_FindChildByID then
            local tcp = r.JS_Window_FindChildByID(r.GetMainHwnd(), 1000)
            if tcp then
                r.TrackList_AdjustWindows(false)
                local _, _, th = r.JS_Window_GetClientSize(tcp)
                local ty = r.GetMediaTrackInfo_Value(track, "I_TCPY")
                local tkh = r.GetMediaTrackInfo_Value(track, "I_TCPH")
                local ok, sp = r.JS_Window_GetScrollInfo(tcp, "v")
                if ok then
                    local target = math.max(0, math.floor(sp + ty + tkh/2 - th/2))
                    r.JS_Window_SetScrollPos(tcp, "v", target)
                end
            end
        end
        return
    end

    -- Plain locate.
    -- If target is in the active flow chain, set browsing flag so the
    -- main loop's flow-browse silent-track-switch path handles the
    -- selection change and pushes history (matches body-click behavior
    -- on flow chain cards).
    local in_flow_chain = false
    if flow_view_active and flow_view_chain then
        for _, ct in ipairs(flow_view_chain) do
            if ct == track then in_flow_chain = true; break end
        end
    end
    if in_flow_chain then
        flow_view_browsing = true
    end

    -- Pinned + non-flow-chain target: loop won't push (pinned TCP sync
    -- convention), so we pre/post-push to record the secondary card
    -- transition. v20.426 pattern.
    local pre_pushed = false
    if insp_pinned and not in_flow_chain then
        ViewHistoryPush()
        pre_pushed = true
    end

    InspRevealTrack(track)

    if pre_pushed then
        ViewHistoryPush()
    end
    -- Unpinned plain locate: main loop pushes when sel_track ~= insp_track.
    -- Pinned + flow chain target: main loop pushes via flow_view_browsing.
end

-- Track-title-as-link affordance. Caller draws the text; this helper
-- detects hover/click via IsMouseHoveringRect against the text bounds
-- (no InvisibleButton — avoids overlap conflicts with sibling buttons
-- like ##hdrtitle that may be registered earlier on the same screen
-- region without AllowOverlap). Renders hand cursor + tooltip on hover.
-- Caller is responsible for drawing the underline using the returned
-- `hovered` flag, and for gating its own click handlers on `clicked`
-- so the title click doesn't double-dispatch.
--
-- opts:
--   dbl_handler  -- optional callback for double-click; if absent,
--                   double-click is treated as a single click (locate).
--   tooltip      -- tooltip text override
TitleLink = function(id, x, y, w, h, track, opts)
    if not track or w < 1 or h < 1 then return false, false end
    opts = opts or {}

    -- Don't react during FX drag or on a focus-grab click.
    local suppress = fx_drag.active or nav_focus_grab_eat_click

    -- Manual hit-test against the text bounds. AllowWhenBlocked* flags so
    -- we still detect hover even though sibling InvisibleButtons (like
    -- ##hdrtitle) consider themselves the topmost item at this position.
    local mx, my = r.ImGui_GetMousePos(ctx)
    local hovered = (not suppress)
        and mx >= x and mx < x + w
        and my >= y and my < y + h
        and r.ImGui_IsWindowHovered(ctx,
            r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem()
            | r.ImGui_HoveredFlags_AllowWhenBlockedByPopup())

    local clicked = false
    if hovered then
        r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
        if r.ImGui_IsMouseClicked(ctx, 0) then
            clicked = true
            local dbl = r.ImGui_IsMouseDoubleClicked(ctx, 0)
            if dbl and opts.dbl_handler then
                opts.dbl_handler()
            else
                local mods = r.ImGui_GetKeyMods(ctx)
                local opt_held = IsAlt(mods)
                if opt_held then
                    -- v20.442: Opt+click peek is a pure light-touch gesture —
                    -- locate in REAPER, no Reflex state change. Set frame
                    -- flag so co-located bg/title handlers (folder expand,
                    -- minimal-flow browse, etc.) can suppress themselves.
                    nav_title_peek_consumed = true
                end
                LocateInREAPER(track, opt_held)
            end
        end
        -- Manual hit-test, so use the direct shared tooltip path.
        TipDirect(opts.tooltip or "Click: locate\nOpt: peek")
    end

    return hovered, clicked
end

-- Generic clickable text row for the settings panel. Hover-to-white.
-- opts: { color = base color (default C.text_dim), dot = "●"/"○"/nil, indent = 0 }
-- Returns: clicked (bool)
SettingsRow = function(label, opts)
    opts = opts or {}
    local row_h = S(UI.btn_h)
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    local base_col = opts.color or C.text_dim
    local indent = opts.indent or 0
    local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    if avail_w < 1 then return false end   -- popup first frame: skip, render next frame
    r.ImGui_InvisibleButton(ctx, "##srow_" .. label, avail_w, row_h)
    local hov = r.ImGui_IsItemHovered(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    -- Text color: hover → pure white; else base (allows green/muted/etc)
    local txt_col = hov and 0xFFFFFFFF or base_col
    local ty = cy + Round((row_h - text_h) / 2)
    local prefix_w = 0
    if opts.dot then
        r.ImGui_DrawList_AddText(dl, cx + indent, ty, txt_col, opts.dot)
        prefix_w = r.ImGui_CalcTextSize(ctx, opts.dot .. "  ")
    end
    r.ImGui_DrawList_AddText(dl, cx + indent + prefix_w, ty, txt_col, label)
    return clicked
end

-- Settings collapsing section header. Arrow right-aligned; click toggles expansion.
-- Returns: is_expanded (updated)
SettingsCollapsingRow = function(label, is_expanded)
    local row_h = S(UI.btn_h)
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    if avail_w < 1 then return is_expanded end   -- popup first frame: skip, render next frame
    local right_inset = S(UI.card_pad)
    r.ImGui_InvisibleButton(ctx, "##scol_" .. label, avail_w, row_h)
    local hov = r.ImGui_IsItemHovered(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local txt_col = hov and 0xFFFFFFFF or C.text_dim
    local ty = cy + Round((row_h - text_h) / 2)
    r.ImGui_DrawList_AddText(dl, cx, ty, txt_col, label)
    -- Right-aligned arrow
    DrawArrowIcon(dl, cx + avail_w - right_inset - S(5), cy + row_h * 0.5,
        S(10), is_expanded and "down" or "right", txt_col)
    if clicked then return not is_expanded end
    return is_expanded
end

MenuCheckbox = function(label, value)
    -- Horizontal pill toggle switch: [label left-aligned]      [pill+thumb right-aligned]
    -- ON: pill bg = C.cmp_b (blue), thumb right, thumb white
    -- OFF: pill bg = C.btn_bg, thumb left, thumb C.text_dim
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    if avail_w < 1 then return value end   -- popup first frame: skip, render next frame
    local row_h = S(UI.btn_h)                 -- matches routing M button height
    local toggle_w = Round(row_h * 38 / 26)   -- ~1.46× aspect ratio (smaller than before)
    local thumb_inset = S(3)
    local thumb_d = row_h - thumb_inset * 2
    local right_inset = S(UI.card_pad)        -- symmetric with left padding in settings panel
    local text_h = r.ImGui_GetTextLineHeight(ctx)

    -- Declare content width based on actual need so the popup auto-sizes to fit.
    -- Without this, InvisibleButton(avail_w, ...) feeds back the popup's current width
    -- and the popup never grows to accommodate long labels.
    local label_w = r.ImGui_CalcTextSize(ctx, label)
    local gap = S(UI.pad_sm)
    local needed_w = label_w + gap + toggle_w + right_inset
    local content_w = math.max(avail_w, needed_w)

    local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
    -- Full-row invisible button for click detection
    r.ImGui_InvisibleButton(ctx, "##toggle_" .. label, content_w, row_h)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local dl = r.ImGui_GetWindowDrawList(ctx)

    -- Label
    r.ImGui_DrawList_AddText(dl, cx, cy + Round((row_h - text_h) / 2), C.text_dim, label)

    -- Toggle pill (right-aligned with right_inset)
    local pill_x = cx + content_w - toggle_w - right_inset
    local pill_y = cy
    local pill_r = row_h / 2
    local pill_bg = value and C.cmp_b or C.btn_bg
    r.ImGui_DrawList_AddRectFilled(dl, pill_x, pill_y, pill_x + toggle_w, pill_y + row_h, pill_bg, pill_r)

    -- Thumb circle
    local thumb_cx
    if value then
        thumb_cx = pill_x + toggle_w - thumb_inset - thumb_d / 2
    else
        thumb_cx = pill_x + thumb_inset + thumb_d / 2
    end
    local thumb_cy = pill_y + row_h / 2
    local thumb_col = value and 0xFFFFFFFF or C.text_dim
    r.ImGui_DrawList_AddCircleFilled(dl, thumb_cx, thumb_cy, thumb_d / 2, thumb_col, 0)

    if clicked then return not value end
    return value
end

SettingsDrawFXBrowserProvider = function()
    local providers = {
        FX_BROWSER_PROVIDER_REFLEX,
        FX_BROWSER_PROVIDER_NVK,
        FX_BROWSER_PROVIDER_REAPER,
        FX_BROWSER_PROVIDER_CUSTOM,
    }
    for _, provider in ipairs(providers) do
        local selected = fx_browser_provider == provider
        local available = ExternalFxProviderAvailable(provider)
        local label = ExternalFxProviderLabel(provider)
        if provider == FX_BROWSER_PROVIDER_CUSTOM and insp_fx_browser_action <= 0 then
            label = label .. " (not set)"
            available = false
        elseif provider ~= FX_BROWSER_PROVIDER_REFLEX and not available then
            label = label .. " (missing)"
        end
        if SettingsRow(label, {
            color = selected and C.green or (available and C.text_dim or C.text_muted),
            dot = selected and "\xE2\x97\x8F" or "\xE2\x97\x8B",
            indent = S(UI.pad),
        }) then
            fx_browser_provider = provider
            SavePref("fx_browser_provider", provider)
            if provider == FX_BROWSER_PROVIDER_CUSTOM and insp_fx_browser_action <= 0 then
                insp_fx_prompt_active = true
                if r.PromptForAction then r.PromptForAction(1, 0, 0) end
            end
        end
    end
    if SettingsRow(insp_fx_browser_action > 0 and "Change Custom Action" or "Define Custom Action", {
        indent = S(UI.pad),
    }) then
        insp_fx_prompt_active = true
        if r.PromptForAction then r.PromptForAction(1, 0, 0) end
    end
    if insp_fx_browser_action > 0 then
        if SettingsRow("Clear Custom Action", { indent = S(UI.pad) }) then
            insp_fx_browser_action = 0
            InspSaveFXBrowserAction(0)
            if fx_browser_provider == FX_BROWSER_PROVIDER_CUSTOM then
                fx_browser_provider = FX_BROWSER_PROVIDER_REFLEX
                SavePref("fx_browser_provider", fx_browser_provider)
            end
        end
    end
end

local last_track_count = 0
local last_project_state = 0
local project_state_rescan_pending = false
local last_rescan_time = 0
local RESCAN_THROTTLE = 0.5  -- seconds between structure rescans
local nav_project_key = nil
local nav_project_search_cache = {}
local inspector_project_state_cache = {}
local fx_window_toggle_state_cache = {}

ReflexNavigatorCurrentProjectKey = function()
    local proj = r.EnumProjects and r.EnumProjects(-1, "") or nil
    local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
    return tostring(proj or "0") .. "|" .. tostring(master or "")
end

ReflexCopyShallowMap = function(src)
    local dst = {}
    for k, v in pairs(src or {}) do dst[k] = v end
    return dst
end

ReflexFindTrackByGuid = function(guid)
    if not guid or guid == "" then return nil end
    local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
    if master and r.ValidatePtr(master, "MediaTrack*") and r.GetTrackGUID(master) == guid then
        return master
    end
    local nt = r.CountTracks(0)
    for i = 0, nt - 1 do
        local track = r.GetTrack(0, i)
        if track and r.GetTrackGUID(track) == guid then return track end
    end
    return nil
end

ReflexGetTakeGUID = function(take)
    if not take or not r.ValidatePtr(take, "MediaItem_Take*") then return nil end
    if not r.GetSetMediaItemTakeInfo_String then return nil end
    local ok, rv, guid = pcall(r.GetSetMediaItemTakeInfo_String, take, "GUID", "", false)
    if ok and rv and guid and guid ~= "" then return guid end
    return nil
end

ReflexFindTakeByGuid = function(guid)
    if not guid or guid == "" then return nil end
    for i = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, i)
        for j = 0, r.CountTrackMediaItems(track) - 1 do
            local item = r.GetTrackMediaItem(track, j)
            for k = 0, r.GetMediaItemNumTakes(item) - 1 do
                local take = r.GetTake(item, k)
                if ReflexGetTakeGUID(take) == guid then return take end
            end
        end
    end
    return nil
end

ReflexCaptureInspectorProjectState = function()
    local state = {
        pinned = false,
        env_expanded = ReflexCopyShallowMap(insp_env_expanded),
        pin_suppress_selected = insp_pin_suppress_selected == true,
        pin_last_sel_guid = insp_pin_last_sel_guid,
        pin_sel_env = ReflexCopyShallowMap(insp_pin_sel_env),
        card_heights = ReflexCopyShallowMap(card_heights_prev),
    }
    if insp_track and r.ValidatePtr(insp_track, "MediaTrack*") then
        state.track_guid = r.GetTrackGUID(insp_track)
        state.pinned = insp_pinned == true
    end
    return state
end

ReflexSaveInspectorProjectState = function(project_key)
    if not project_key or project_key == "" then return end
    inspector_project_state_cache[project_key] = ReflexCaptureInspectorProjectState()
end

ReflexRestoreInspectorProjectState = function(project_key)
    local state = project_key and inspector_project_state_cache[project_key] or nil
    local track = state and ReflexFindTrackByGuid(state.track_guid) or nil

    InspCleanupDragState()
    insp_track = track
    insp_pinned = track ~= nil and state and state.pinned == true or false
    insp_env_expanded = state and ReflexCopyShallowMap(state.env_expanded) or {}
    insp_pin_suppress_selected = state and state.pin_suppress_selected == true or false
    insp_pin_last_sel_guid = state and state.pin_last_sel_guid or nil
    insp_pin_sel_env = state and ReflexCopyShallowMap(state.pin_sel_env) or {}
    insp_pin_sel_frames = 0
    card_heights_prev = state and ReflexCopyShallowMap(state.card_heights) or {}
    card_heights_cur = {}
    card_idx = 0
    insp_vol_editing = false; insp_pan_editing = false
    insp_rename_type = nil
    insp_vol_edit_focus = false; insp_pan_edit_focus = false
    insp_vol_edit_frames = 0; insp_pan_edit_frames = 0
    if insp_track then
        InspScanTrack(insp_track)
        insp_meter_clip[insp_track] = nil
        insp_meter_peak[insp_track] = nil
    end
    if SendsViewCheckRefresh then SendsViewCheckRefresh() end
end

ReflexSetNavigatorSearchForProject = function(query)
    query = query or ""
    nav_tlt_search_text = query
    nav_tlt_search_effective_query = query
    nav_tlt_search_active = query ~= ""
    nav_tlt_search_hide_clear = query == ""
    nav_tlt_search_recent_clear_frames = 0
    nav_tlt_search_focus_requested_frames = 0
    if NavSetTltSearchEffectiveQuery then NavSetTltSearchEffectiveQuery(query, true) end
end

ReflexNavigatorRequestTltSearchFocus = function()
    current_page = "tracks"
    if opt_nav_show_search == false then
        opt_nav_show_search = true
        SavePref("nav_show_search", true)
    end
    nav_tlt_search_active = true
    nav_tlt_search_hide_clear = false
    nav_tlt_search_recent_clear_frames = 0
    nav_tlt_search_focus_requested_frames = 8
    needs_rescan = true
end

ReflexNavigatorSearchShortcutPressed = function()
    if not (r.ImGui_IsKeyPressed and r.ImGui_Key_F) then return false end
    local ok_key, key = pcall(r.ImGui_Key_F)
    if not ok_key or type(key) ~= "number" then return false end
    local ok_pressed, pressed = pcall(r.ImGui_IsKeyPressed, ctx, key, false)
    if not ok_pressed or pressed ~= true then return false end
    local mods = r.ImGui_GetKeyMods(ctx)
    return IsCmd(mods) and not IsShift(mods) and not IsAlt(mods)
end

ReflexHotkeyKeyPressed = function(key_name)
    if not r.ImGui_IsKeyPressed then return false end
    local key = ReflexKeyValue(key_name)
    if not key then return false end
    local ok_pressed, pressed = pcall(r.ImGui_IsKeyPressed, ctx, key, false)
    return ok_pressed and pressed == true
end

ReflexHotkeyModsMatch = function(binding, mods)
    local state = TrackNavigatorModState(mods)
    return state.cmd == (binding.cmd == true)
        and state.shift == (binding.shift == true)
        and state.alt == (binding.alt == true)
        and state.ctrl == (binding.ctrl == true)
end

ReflexHotkeyPressed = function(binding, mods)
    if not binding or not binding.key then return false end
    return ReflexHotkeyModsMatch(binding, mods) and ReflexHotkeyKeyPressed(binding.key)
end

ReflexHotkeyInputBlocked = function()
    if r.ImGui_IsAnyItemActive(ctx) then return true end
    if ReflexAnyPopupOpen and ReflexAnyPopupOpen() then return true end
    if settings_open or fx_browser_open or io_manager_open then return true end
    if remote_prompt_active or remote_icon_picker_open then return true end
    if insp_rename_type or insp_vol_editing or insp_pan_editing then return true end
    return false
end

ReflexResolveFXBrowserHotkeyTarget = function()
    if RouteDragResolveCardTarget then
        local mx, my = r.ImGui_GetMousePos(ctx)
        local route_track = RouteDragResolveCardTarget(mx, my)
        if route_track and r.ValidatePtr(route_track, "MediaTrack*") then return route_track end
    end
    local card = FxClipFindHoveredCard and FxClipFindHoveredCard() or nil
    if card and card.track and r.ValidatePtr(card.track, "MediaTrack*") then
        return card.track
    end
    if insp_track and r.ValidatePtr(insp_track, "MediaTrack*") then return insp_track end
    local sel_track = r.CountSelectedTracks(0) > 0 and r.GetSelectedTrack(0, 0) or nil
    if sel_track and r.ValidatePtr(sel_track, "MediaTrack*") then return sel_track end
    local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
    if master and r.ValidatePtr(master, "MediaTrack*") and r.IsTrackSelected(master) then return master end
    return nil
end

ReflexResolveFXWindowCommandTrack = function()
    if insp_track and r.ValidatePtr(insp_track, "MediaTrack*") then return insp_track end
    local sel_track = r.CountSelectedTracks(0) > 0 and r.GetSelectedTrack(0, 0) or nil
    if sel_track and r.ValidatePtr(sel_track, "MediaTrack*") then return sel_track end
    local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
    if master and r.ValidatePtr(master, "MediaTrack*") and r.IsTrackSelected(master) then return master end
    return nil
end

ReflexFindFXByGUID = function(track, target_guid)
    if not target_guid or target_guid == "" then return nil end
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    for f = 0, r.TrackFX_GetCount(track) - 1 do
        if r.TrackFX_GetFXGUID(track, f) == target_guid then return f end
    end
    return nil
end

ReflexFXWindowKey = function(track, fx_idx)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    local track_guid = r.GetTrackGUID(track) or ""
    local fx_guid = r.TrackFX_GetFXGUID(track, fx_idx) or ""
    if track_guid == "" or fx_guid == "" then return nil end
    return track_guid .. "::" .. fx_guid
end

ReflexForEachProjectTrack = function(fn)
    if not fn then return end
    local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
    if master and r.ValidatePtr(master, "MediaTrack*") then fn(master, true) end
    for i = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, i)
        if track and r.ValidatePtr(track, "MediaTrack*") then fn(track, false) end
    end
end

ReflexCollectOpenTrackFXWindows = function(opts)
    opts = opts or {}
    local windows = {}
    ReflexForEachProjectTrack(function(track, is_master)
        if is_master and opts.include_master == false then return end
        if opts.only_track and track ~= opts.only_track then return end
        for f = 0, r.TrackFX_GetCount(track) - 1 do
            local hwnd = r.TrackFX_GetFloatingWindow(track, f)
            if hwnd then
                windows[#windows + 1] = {
                    kind = "track",
                    track = track,
                    fx_idx = f,
                    hwnd = hwnd,
                    key = ReflexFXWindowKey(track, f),
                }
            end
        end
    end)
    return windows
end

ReflexCollectOpenFXWindows = function()
    local windows = ReflexCollectOpenTrackFXWindows()
    for i = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, i)
        for j = 0, r.CountTrackMediaItems(track) - 1 do
            local item = r.GetTrackMediaItem(track, j)
            for k = 0, r.GetMediaItemNumTakes(item) - 1 do
                local take = r.GetTake(item, k)
                if take and r.ValidatePtr(take, "MediaItem_Take*") then
                    for f = 0, r.TakeFX_GetCount(take) - 1 do
                        local hwnd = r.TakeFX_GetFloatingWindow(take, f)
                        if hwnd then
                            windows[#windows + 1] = {
                                kind = "take",
                                take = take,
                                fx_idx = f,
                                hwnd = hwnd,
                            }
                        end
                    end
                end
            end
        end
    end
    return windows
end

ReflexCurrentFXWindowToggleKey = function()
    return ReflexNavigatorCurrentProjectKey and ReflexNavigatorCurrentProjectKey() or "default"
end

ReflexCaptureFXWindowToggleSet = function(windows)
    local snapshot = {}
    for _, win in ipairs(windows or {}) do
        if win.kind == "track" and win.track and r.ValidatePtr(win.track, "MediaTrack*") then
            local track_guid = r.GetTrackGUID(win.track) or ""
            local fx_guid = r.TrackFX_GetFXGUID(win.track, win.fx_idx) or ""
            if track_guid ~= "" and fx_guid ~= "" then
                snapshot[#snapshot + 1] = {
                    kind = "track",
                    track_guid = track_guid,
                    fx_guid = fx_guid,
                }
            end
        elseif win.kind == "take" and win.take and r.ValidatePtr(win.take, "MediaItem_Take*") then
            local take_guid = ReflexGetTakeGUID(win.take)
            if take_guid and take_guid ~= "" then
                snapshot[#snapshot + 1] = {
                    kind = "take",
                    take_guid = take_guid,
                    fx_idx = win.fx_idx,
                }
            end
        end
    end
    return snapshot
end

ReflexRememberFXWindowToggleSet = function(windows)
    local key = ReflexCurrentFXWindowToggleKey()
    if not key or key == "" then return end
    local snapshot = ReflexCaptureFXWindowToggleSet(windows)
    if #snapshot > 0 then fx_window_toggle_state_cache[key] = snapshot end
end

ReflexRestoreFXWindowToggleSet = function()
    local key = ReflexCurrentFXWindowToggleKey()
    local snapshot = key and fx_window_toggle_state_cache[key] or nil
    if not snapshot or #snapshot == 0 then return false end

    local opened = 0
    local restored = {}
    r.PreventUIRefresh(1)
    for _, entry in ipairs(snapshot) do
        if entry.kind == "track" then
            local track = ReflexFindTrackByGuid(entry.track_guid)
            local fx_idx = ReflexFindFXByGUID(track, entry.fx_guid)
            if track and fx_idx ~= nil then
                r.TrackFX_Show(track, fx_idx, 3)
                restored[#restored + 1] = { kind = "track", track = track, fx_idx = fx_idx }
                opened = opened + 1
            end
        elseif entry.kind == "take" then
            local take = ReflexFindTakeByGuid(entry.take_guid)
            if take and entry.fx_idx and entry.fx_idx < r.TakeFX_GetCount(take) then
                r.TakeFX_Show(take, entry.fx_idx, 3)
                restored[#restored + 1] = { kind = "take", take = take, fx_idx = entry.fx_idx }
                opened = opened + 1
            end
        end
    end
    r.PreventUIRefresh(-1)
    if opened > 0 then
        local function raise_restored(attempts)
            local windows = {}
            for _, entry in ipairs(restored) do
                local hwnd
                if entry.kind == "track" and entry.track and r.ValidatePtr(entry.track, "MediaTrack*") then
                    hwnd = r.TrackFX_GetFloatingWindow(entry.track, entry.fx_idx)
                elseif entry.kind == "take" and entry.take and r.ValidatePtr(entry.take, "MediaItem_Take*") then
                    hwnd = r.TakeFX_GetFloatingWindow(entry.take, entry.fx_idx)
                end
                if hwnd then windows[#windows + 1] = { hwnd = hwnd } end
            end
            if #windows > 0 then
                ReflexRaiseFXWindowsSmallOnTop(windows, 4)
            elseif attempts > 1 then
                r.defer(function() raise_restored(attempts - 1) end)
            end
        end
        r.defer(function() raise_restored(8) end)
    end
    return opened > 0
end

ReflexSnapshotProtectedFXWindows = function()
    reflex_fx_window_cycle.protected = {}
    for _, win in ipairs(ReflexCollectOpenTrackFXWindows()) do
        if win.key then reflex_fx_window_cycle.protected[win.key] = true end
    end
end

ReflexFocusedWindowChain = function()
    if not r.JS_Window_GetFocus then return nil end
    local ok, focused = pcall(function() return r.JS_Window_GetFocus() end)
    if not ok or not focused then return nil end
    if reflex_focused_window_chain_cache.focus == focused then
        return reflex_focused_window_chain_cache.chain
    end

    local focus_chain = {}
    local hwnd = focused
    for _ = 1, 16 do
        if not hwnd then break end
        focus_chain[hwnd] = true
        if not r.JS_Window_GetParent then break end
        local parent_ok, parent = pcall(function() return r.JS_Window_GetParent(hwnd) end)
        if not parent_ok or not parent or parent == hwnd then break end
        hwnd = parent
    end
    reflex_focused_window_chain_cache.focus = focused
    reflex_focused_window_chain_cache.chain = focus_chain
    return focus_chain
end

ReflexIsFocusedFloatingFX = function(track, fx_idx)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    local focus_chain = ReflexFocusedWindowChain and ReflexFocusedWindowChain() or nil
    if not focus_chain then return false end
    local fx_hwnd = r.TrackFX_GetFloatingWindow(track, fx_idx)
    return fx_hwnd ~= nil and focus_chain[fx_hwnd] == true
end

ReflexFindFocusedFloatingFX = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    for f = 0, r.TrackFX_GetCount(track) - 1 do
        if ReflexIsFocusedFloatingFX(track, f) then return f end
    end
    return nil
end

ReflexCollectFloatingFX = function(track)
    local open = {}
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return open end
    for f = 0, r.TrackFX_GetCount(track) - 1 do
        if r.TrackFX_GetFloatingWindow(track, f) then open[#open + 1] = f end
    end
    return open
end

ReflexResolveFXWindowCurrentIndex = function(track)
    local focused_idx = ReflexFindFocusedFloatingFX(track)
    if focused_idx ~= nil then return focused_idx end

    local track_guid = r.GetTrackGUID(track)
    if reflex_fx_window_cycle.track_guid == track_guid then
        local stored_idx = ReflexFindFXByGUID(track, reflex_fx_window_cycle.fx_guid)
        if stored_idx ~= nil and r.TrackFX_GetFloatingWindow(track, stored_idx) then
            return stored_idx
        end
    end

    local open = ReflexCollectFloatingFX(track)
    if #open == 1 then return open[1] end
    return nil
end

ReflexAnyManagedCycleWindowsOpen = function()
    for _, win in ipairs(ReflexCollectOpenTrackFXWindows()) do
        if win.key and reflex_fx_window_cycle.managed[win.key] then return true end
    end
    return false
end

ReflexCycleHasOpenManagedAndOtherWindows = function()
    local managed_open, other_open = false, false
    for _, win in ipairs(ReflexCollectOpenTrackFXWindows()) do
        if win.key and reflex_fx_window_cycle.managed[win.key] then
            managed_open = true
        else
            other_open = true
        end
        if managed_open and other_open then return true end
    end
    return false
end

ReflexResolveNextCyclableFXIndex = function(track, current_idx, direction)
    local fx_count = r.TrackFX_GetCount(track)
    if fx_count <= 0 then return nil end
    direction = direction < 0 and -1 or 1

    local idx = current_idx
    for _ = 1, fx_count do
        if idx == nil then
            idx = direction < 0 and (fx_count - 1) or 0
        else
            idx = (idx + direction) % fx_count
        end
        local key = ReflexFXWindowKey(track, idx)
        local offline = r.TrackFX_GetOffline(track, idx)
        if not offline and not (key and reflex_fx_window_cycle.protected[key]) then
            return idx
        end
    end
    return nil
end

ReflexRaiseFXWindow = function(track, fx_idx, attempts)
    attempts = attempts or 8
    r.defer(function()
        local hwnd = r.TrackFX_GetFloatingWindow(track, fx_idx)
        if not hwnd then
            if attempts > 1 then ReflexRaiseFXWindow(track, fx_idx, attempts - 1) end
            return
        end
        if r.JS_Window_SetZOrder then r.JS_Window_SetZOrder(hwnd, "TOP") end
        if r.JS_Window_SetForeground then r.JS_Window_SetForeground(hwnd) end
        if r.JS_Window_SetFocus then r.JS_Window_SetFocus(hwnd) end
        if attempts > 1 then ReflexRaiseFXWindow(track, fx_idx, attempts - 1) end
    end)
end

ReflexCenterFXWindow = function(track, fx_idx, attempts)
    attempts = attempts or 8
    if not (r.JS_Window_Move or r.JS_Window_SetPosition) then
        InspPositionFXWindow(track, fx_idx)
        return
    end
    r.defer(function()
        local hwnd = r.TrackFX_GetFloatingWindow(track, fx_idx)
        if not hwnd then
            if attempts > 1 then ReflexCenterFXWindow(track, fx_idx, attempts - 1) end
            return
        end
        if not r.my_getViewport then
            InspPositionFXWindow(track, fx_idx)
            return
        end
        local w, h
        if r.JS_Window_GetClientSize then
            local ok, client_w, client_h = r.JS_Window_GetClientSize(hwnd)
            if ok then w, h = client_w, client_h end
        end
        if (not w or not h or w <= 0 or h <= 0) and r.JS_Window_GetRect then
            local ok, left, top, right, bottom = r.JS_Window_GetRect(hwnd)
            if ok and left and top and right and bottom then
                w = right - left
                h = bottom - top
            end
        end
        if not w or not h or w <= 0 or h <= 0 then
            if attempts > 1 then ReflexCenterFXWindow(track, fx_idx, attempts - 1) end
            return
        end
        local sx, sy, sr, sb = r.my_getViewport(0, 0, 0, 0, 0, 0, 0, 0, false)
        sx, sy, sr, sb = sx or 0, sy or 0, sr or 0, sb or 0
        local sw = sr - sx
        local sh = sb - sy
        if sw <= 0 or sh <= 0 then return end
        local x = sx + math.floor((sw - w) * 0.5 + 0.5)
        local y = sy + math.floor((sh - h) * 0.5 + 0.5)
        if r.JS_Window_Move then
            r.JS_Window_Move(hwnd, x, y)
        else
            r.JS_Window_SetPosition(hwnd, x, y, w, h)
        end
        if attempts > 1 then ReflexCenterFXWindow(track, fx_idx, attempts - 1) end
    end)
end

ReflexCycleFXWindow = function(direction, opts)
    opts = opts or {}
    direction = tonumber(direction) or 1
    direction = direction < 0 and -1 or 1
    local keep_open = opts.keep_open == true

    local track = ReflexResolveFXWindowCommandTrack()
    if not track then return false end

    local fx_count = r.TrackFX_GetCount(track)
    if fx_count <= 0 then
        reflex_fx_window_cycle.track_guid = r.GetTrackGUID(track)
        reflex_fx_window_cycle.fx_guid = nil
        return false
    end

    ExternalFxSessionCancel()
    if not ReflexAnyManagedCycleWindowsOpen() then
        reflex_fx_window_cycle.managed = {}
        ReflexSnapshotProtectedFXWindows()
    end
    local current_idx = ReflexResolveFXWindowCurrentIndex(track)
    local next_idx = ReflexResolveNextCyclableFXIndex(track, current_idx, direction)
    if next_idx == nil then return false end

    r.PreventUIRefresh(1)
    local current_key = current_idx ~= nil and ReflexFXWindowKey(track, current_idx) or nil
    if not keep_open and current_idx ~= nil and current_idx ~= next_idx
       and current_key and reflex_fx_window_cycle.managed[current_key]
       and r.TrackFX_GetFloatingWindow(track, current_idx) then
        r.TrackFX_Show(track, current_idx, 2)
    end
    r.TrackFX_Show(track, next_idx, 3)
    r.PreventUIRefresh(-1)

    ReflexCenterFXWindow(track, next_idx)
    ReflexRaiseFXWindow(track, next_idx)
    reflex_fx_window_cycle.track_guid = r.GetTrackGUID(track)
    reflex_fx_window_cycle.fx_guid = r.TrackFX_GetFXGUID(track, next_idx) or ""
    local next_key = ReflexFXWindowKey(track, next_idx)
    if next_key then reflex_fx_window_cycle.managed[next_key] = true end
    return true
end

ReflexOpenFXBrowserForHotkey = function(opts)
    opts = opts or {}
    local now = r.time_precise and r.time_precise() or os.clock()
    if reflex_open_fx_suppress_until > now then return true end
    local track = ReflexResolveFXBrowserHotkeyTarget()
    if not track then return false end
    ExternalFxSessionCancel()
    InspOpenFXBrowser(track)
    reflex_open_fx_suppress_until = now + 0.35
    return true
end

ReflexToggleNavigatorExpanded = function()
    ExternalFxSessionCancel()
    if NavToggleNavigatorExpandedPlain then
        return NavToggleNavigatorExpandedPlain()
    end
    navigator_expanded = not (navigator_expanded == true)
    SavePref("navigator_expanded", navigator_expanded)
    return true
end

ReflexCloseTrackFXWindows = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    for i = 0, r.TrackFX_GetCount(track) - 1 do
        if r.TrackFX_GetOpen(track, i) then r.TrackFX_SetOpen(track, i, 0) end
        if r.TrackFX_GetChainVisible(track) ~= -1 then r.TrackFX_Show(track, 0, 0) end
    end

    for i = 0, r.TrackFX_GetRecCount(track) - 1 do
        local rec_idx = i + 0x1000000
        if r.TrackFX_GetOpen(track, rec_idx) then r.TrackFX_SetOpen(track, rec_idx, 0) end
        if r.TrackFX_GetRecChainVisible(track) ~= -1 then r.TrackFX_Show(track, rec_idx, 0) end
    end
end

ReflexCloseTakeFXWindows = function(take)
    if not take or not r.ValidatePtr(take, "MediaItem_Take*") then return end
    for i = 0, r.TakeFX_GetCount(take) - 1 do
        if r.TakeFX_GetOpen(take, i) then r.TakeFX_SetOpen(take, i, 0) end
        if r.TakeFX_GetChainVisible(take) ~= -1 then r.TakeFX_Show(take, 0, 0) end
    end
end

ReflexCloseAllFXWindows = function()
    ExternalFxSessionCancel()
    local open_windows = ReflexCollectOpenFXWindows()
    if #open_windows == 0 then
        return ReflexRestoreFXWindowToggleSet()
    end
    ReflexRememberFXWindowToggleSet(open_windows)
    reflex_fx_window_cycle.track_guid = nil
    reflex_fx_window_cycle.fx_guid = nil
    reflex_fx_window_cycle.managed = {}
    reflex_fx_window_cycle.protected = {}
    r.PreventUIRefresh(1)
    local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
    if master and r.ValidatePtr(master, "MediaTrack*") then
        ReflexCloseTrackFXWindows(master)
    end
    for i = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, i)
        ReflexCloseTrackFXWindows(track)
        for j = 0, r.CountTrackMediaItems(track) - 1 do
            local item = r.GetTrackMediaItem(track, j)
            for k = 0, r.GetMediaItemNumTakes(item) - 1 do
                ReflexCloseTakeFXWindows(r.GetTake(item, k))
            end
        end
    end
    r.PreventUIRefresh(-1)
    return true
end

ReflexCollectTileFXWindows = function(target_track)
    if target_track then
        return ReflexCollectOpenTrackFXWindows({ only_track = target_track })
    end
    return ReflexCollectOpenFXWindows()
end

ReflexFXWindowRect = function(hwnd)
    if not (hwnd and r.JS_Window_GetRect) then return nil end
    local ok, left, top, right, bottom = r.JS_Window_GetRect(hwnd)
    if not (ok and left and top and right and bottom) then return nil end
    local w = math.max(1, right - left)
    local h = math.max(1, bottom - top)
    return { x = left, y = top, w = w, h = h, area = w * h }
end

ReflexClampWindowPos = function(x, y, w, h, work)
    local max_x = math.max(work.x, work.r - w)
    local max_y = math.max(work.y, work.b - h)
    x = math.max(work.x, math.min(x, max_x))
    y = math.max(work.y, math.min(y, max_y))
    return math.floor(x + 0.5), math.floor(y + 0.5)
end

ReflexRectOverlapArea = function(a, b)
    local left = math.max(a.x, b.x)
    local top = math.max(a.y, b.y)
    local right = math.min(a.x + a.w, b.x + b.w)
    local bottom = math.min(a.y + a.h, b.y + b.h)
    if right <= left or bottom <= top then return 0 end
    return (right - left) * (bottom - top)
end

ReflexAddTileCandidateValue = function(values, seen, v)
    local key = tostring(math.floor(v + 0.5))
    if seen[key] then return end
    seen[key] = true
    values[#values + 1] = v
end

ReflexFXTileAnchor = function(index)
    local anchors = {
        { 0.00, 0.00 },
        { 1.00, 0.00 },
        { 0.00, 1.00 },
        { 1.00, 1.00 },
        { 0.50, 1.00 },
        { 0.50, 0.00 },
        { 0.00, 0.50 },
        { 1.00, 0.50 },
        { 0.50, 0.50 },
    }
    return anchors[((index - 1) % #anchors) + 1]
end

ReflexBuildFXTileCandidates = function(win, placed, work, preferred)
    local xs, ys, seen_x, seen_y = {}, {}, {}, {}
    local function add_x(v)
        local x = ReflexClampWindowPos(v, work.y, win.w, win.h, work)
        ReflexAddTileCandidateValue(xs, seen_x, x)
    end
    local function add_y(v)
        local _, y = ReflexClampWindowPos(work.x, v, win.w, win.h, work)
        ReflexAddTileCandidateValue(ys, seen_y, y)
    end

    add_x(work.x)
    add_x(work.r - win.w)
    add_x(work.x + (work.w - win.w) * 0.5)
    add_x(work.x + (work.w - win.w) * 0.25)
    add_x(work.x + (work.w - win.w) * 0.75)
    add_x(preferred.x)

    add_y(work.y)
    add_y(work.b - win.h)
    add_y(work.y + (work.h - win.h) * 0.5)
    add_y(work.y + (work.h - win.h) * 0.25)
    add_y(work.y + (work.h - win.h) * 0.75)
    add_y(preferred.y)

    for _, p in ipairs(placed) do
        add_x(p.x)
        add_x(p.x + p.w)
        add_x(p.x - win.w)
        add_x(p.x + p.w - win.w)
        add_x(p.x + (p.w - win.w) * 0.5)

        add_y(p.y)
        add_y(p.y + p.h)
        add_y(p.y - win.h)
        add_y(p.y + p.h - win.h)
        add_y(p.y + (p.h - win.h) * 0.5)
    end

    local candidates = {}
    for _, x in ipairs(xs) do
        for _, y in ipairs(ys) do
            candidates[#candidates + 1] = { x = x, y = y }
        end
    end
    return candidates
end

ReflexChooseFXTilePosition = function(win, placed, work, index)
    local anchor = ReflexFXTileAnchor(index)
    local preferred = {
        x = work.x + (work.w - win.w) * anchor[1],
        y = work.y + (work.h - win.h) * anchor[2],
    }
    preferred.x, preferred.y = ReflexClampWindowPos(preferred.x, preferred.y, win.w, win.h, work)

    local best, best_score
    for _, candidate in ipairs(ReflexBuildFXTileCandidates(win, placed, work, preferred)) do
        local rect = { x = candidate.x, y = candidate.y, w = win.w, h = win.h }
        local overlap = 0
        local max_overlap = 0
        for _, p in ipairs(placed) do
            local area = ReflexRectOverlapArea(rect, p)
            overlap = overlap + area
            max_overlap = math.max(max_overlap, area / math.max(1, math.min(win.area, p.area or p.w * p.h)))
        end
        local dx = candidate.x - preferred.x
        local dy = candidate.y - preferred.y
        local distance = math.sqrt(dx * dx + dy * dy)
        local edge_bonus = 0
        if candidate.x == work.x or candidate.x == work.r - win.w then edge_bonus = edge_bonus - work.w * 0.03 end
        if candidate.y == work.y or candidate.y == work.b - win.h then edge_bonus = edge_bonus - work.h * 0.03 end
        local score = overlap * 20 + max_overlap * win.area * 12 + distance + edge_bonus
        if not best_score or score < best_score then
            best_score = score
            best = candidate
        end
    end
    return best and best.x or preferred.x, best and best.y or preferred.y
end

ReflexRaiseFXWindowsSmallOnTop = function(windows, attempts)
    attempts = attempts or 2
    if not (windows and #windows > 0 and r.JS_Window_SetZOrder) then return end
    local ordered = {}
    for _, win in ipairs(windows) do
        if win.hwnd then
            if not win.area then
                local rect = ReflexFXWindowRect(win.hwnd)
                if rect then
                    win.w, win.h, win.area = rect.w, rect.h, rect.area
                end
            end
            ordered[#ordered + 1] = win
        end
    end
    table.sort(ordered, function(a, b) return (a.area or 0) > (b.area or 0) end)
    r.defer(function()
        for _, win in ipairs(ordered) do
            if win.hwnd then r.JS_Window_SetZOrder(win.hwnd, "TOP") end
        end
        if attempts > 1 then ReflexRaiseFXWindowsSmallOnTop(ordered, attempts - 1) end
    end)
end

ReflexTileFXWindows = function(opts)
    opts = opts or {}
    if not r.JS_Window_GetRect or not r.JS_Window_Move or not r.my_getViewport then return false end
    local windows = {}
    local target_track = opts.target_track
    for _, win in ipairs(ReflexCollectTileFXWindows(target_track)) do
        local rect = ReflexFXWindowRect(win.hwnd)
        if rect then
            win.w = rect.w
            win.h = rect.h
            win.area = rect.area
            windows[#windows + 1] = win
        end
    end
    local n = #windows
    if n == 0 then
        if opts.retry_attempts and opts.retry_attempts > 0 then
            r.defer(function()
                ReflexTileFXWindows({
                    target_track = target_track,
                    retry_attempts = opts.retry_attempts - 1,
                })
            end)
            return true
        end
        return false
    end
    if opts.expected_count and n < opts.expected_count and opts.retry_attempts and opts.retry_attempts > 0 then
        r.defer(function()
            ReflexTileFXWindows({
                target_track = target_track,
                retry_attempts = opts.retry_attempts - 1,
                expected_count = opts.expected_count,
            })
        end)
        return true
    end

    table.sort(windows, function(a, b) return (a.area or 0) > (b.area or 0) end)

    local sx, sy, sr, sb = r.my_getViewport(0, 0, 0, 0, 0, 0, 0, 0, true)
    sx, sy, sr, sb = sx or 0, sy or 0, sr or 0, sb or 0
    local sw = sr - sx
    local sh = sb - sy
    if sw <= 0 or sh <= 0 then return false end
    local work = { x = sx, y = sy, r = sr, b = sb, w = sw, h = sh }
    local placed = {}

    r.PreventUIRefresh(1)
    for i, win in ipairs(windows) do
        local x, y = ReflexChooseFXTilePosition(win, placed, work, i)
        x, y = ReflexClampWindowPos(x, y, win.w, win.h, work)
        r.JS_Window_Move(win.hwnd, x, y)
        placed[#placed + 1] = { x = x, y = y, w = win.w, h = win.h, area = win.area }
    end
    r.PreventUIRefresh(-1)
    ReflexRaiseFXWindowsSmallOnTop(windows, 3)
    return true
end

ReflexTileFXWindowsOrCurrentTrack = function()
    if #ReflexCollectOpenFXWindows() > 0 then
        return ReflexTileFXWindows()
    end

    local track = ReflexResolveFXWindowCommandTrack()
    if not track then return false end
    local fx_count = r.TrackFX_GetCount(track)
    if fx_count <= 0 then return false end

    ExternalFxSessionCancel()
    r.PreventUIRefresh(1)
    for f = 0, fx_count - 1 do
        r.TrackFX_Show(track, f, 3)
    end
    r.PreventUIRefresh(-1)
    r.defer(function()
        ReflexTileFXWindows({ target_track = track, retry_attempts = 8, expected_count = fx_count })
    end)
    return true
end

reflex_app_hotkeys = {
    {
        id = "toggle_navigator_expanded",
        label = "Toggle Navigator",
        key = "ImGui_Key_N",
        handler = function()
            return ReflexToggleNavigatorExpanded()
        end,
    },
    {
        id = "focus_tlt_search",
        label = "Navigator Search",
        key = "ImGui_Key_F",
        cmd = true,
        handler = function()
            ExternalFxSessionCancel()
            ReflexNavigatorRequestTltSearchFocus()
            return true
        end,
    },
    {
        id = "open_fx_browser",
        label = "Add FX",
        key = "ImGui_Key_A",
        handler = function()
            return ReflexOpenFXBrowserForHotkey({ source = "hotkey" })
        end,
    },
    {
        id = "fx_window_previous",
        label = "Previous FX Window",
        key = "ImGui_Key_UpArrow",
        alt = true,
        handler = function()
            return ReflexCycleFXWindow(-1, { source = "hotkey" })
        end,
    },
    {
        id = "fx_window_next",
        label = "Next FX Window",
        key = "ImGui_Key_DownArrow",
        alt = true,
        handler = function()
            return ReflexCycleFXWindow(1, { source = "hotkey" })
        end,
    },
    {
        id = "fx_window_stack_previous",
        label = "Stack Previous FX Window",
        key = "ImGui_Key_UpArrow",
        alt = true,
        shift = true,
        handler = function()
            return ReflexCycleFXWindow(-1, { source = "hotkey", keep_open = true })
        end,
    },
    {
        id = "fx_window_stack_next",
        label = "Stack Next FX Window",
        key = "ImGui_Key_DownArrow",
        alt = true,
        shift = true,
        handler = function()
            return ReflexCycleFXWindow(1, { source = "hotkey", keep_open = true })
        end,
    },
    {
        id = "history_back",
        label = "View History Back",
        key = "ImGui_Key_LeftBracket",
        cmd = true,
        handler = function()
            ExternalFxSessionCancel()
            ViewHistoryBack()
            return true
        end,
    },
    {
        id = "history_forward",
        label = "View History Forward",
        key = "ImGui_Key_RightBracket",
        cmd = true,
        handler = function()
            ExternalFxSessionCancel()
            ViewHistoryForward()
            return true
        end,
    },
    {
        id = "close_all_fx_windows",
        label = "Close All FX Windows",
        key = "ImGui_Key_Escape",
        shift = true,
        handler = function()
            return ReflexCloseAllFXWindows()
        end,
    },
}

reflex_reaper_hotkey_allowlist = {
    {
        id = "reaper_undo",
        key = "ImGui_Key_Z",
        cmd = true,
        action = 40029,
    },
    {
        id = "reaper_redo",
        key = "ImGui_Key_Z",
        cmd = true,
        shift = true,
        action = 40030,
    },
    {
        id = "reaper_previous_track",
        key = "ImGui_Key_UpArrow",
        action = 40286,
    },
    {
        id = "reaper_next_track",
        key = "ImGui_Key_DownArrow",
        action = 40285,
    },
    {
        id = "reaper_play_stop",
        key = "ImGui_Key_Space",
        action = 40044,
    },
    {
        id = "reaper_action_list",
        key = "ImGui_Key_Slash",
        shift = true,
        action = 40605,
    },
}

ReflexRunReaperAction = function(action)
    if type(action) == "number" then
        if action <= 0 then return false end
        r.Main_OnCommand(action, 0)
        return true
    elseif type(action) == "string" and action ~= "" then
        local cmd = r.NamedCommandLookup and r.NamedCommandLookup(action) or 0
        if cmd == 0 then return false end
        r.Main_OnCommand(cmd, 0)
        return true
    end
    return false
end

ReflexDispatchHotkeyList = function(list, mods)
    for _, binding in ipairs(list or {}) do
        if ReflexHotkeyPressed(binding, mods) then
            if binding.action then
                return ReflexRunReaperAction(binding.action)
            elseif binding.handler then
                return binding.handler() == true
            end
        end
    end
    return false
end

ReflexDispatchAppHotkeys = function()
    if not r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows()) then return false end
    if ReflexHotkeyInputBlocked() then return false end
    return ReflexDispatchHotkeyList(reflex_app_hotkeys, r.ImGui_GetKeyMods(ctx))
end

ReflexSyncNavigatorProjectTab = function()
    local cur = ReflexNavigatorCurrentProjectKey()
    if cur == "" then return false end
    if not nav_project_key then
        nav_project_key = cur
        nav_project_search_cache[cur] = nav_tlt_search_text or ""
        ReflexSaveInspectorProjectState(cur)
        return false
    end
    if cur == nav_project_key then
        ReflexSaveInspectorProjectState(cur)
        return false
    end

    -- Inspector state for the old tab is cached while that tab is active;
    -- its MediaTrack* may already be invalid by the time this branch runs.
    nav_project_search_cache[nav_project_key] = nav_tlt_search_text or ""
    nav_project_key = cur
    ReflexSetNavigatorSearchForProject(nav_project_search_cache[cur] or "")
    ReflexRestoreInspectorProjectState(cur)
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

ReflexAnyPopupOpen = function()
    return r.ImGui_IsPopupOpen(ctx, "",
        r.ImGui_PopupFlags_AnyPopupId() | r.ImGui_PopupFlags_AnyPopupLevel())
end

ReflexCanMirrorReaperShortcuts = function()
    if not r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows()) then return false end
    if r.ImGui_IsAnyItemActive(ctx) then return false end
    if ReflexAnyPopupOpen() then return false end
    if settings_open or fx_browser_open or io_manager_open then return false end
    if remote_prompt_active or remote_icon_picker_open then return false end
    if insp_rename_type or insp_vol_editing or insp_pan_editing then return false end
    return true
end

ReflexMirrorReaperShortcuts = function()
    if not ReflexCanMirrorReaperShortcuts() then return end
    ReflexDispatchHotkeyList(reflex_reaper_hotkey_allowlist, r.ImGui_GetKeyMods(ctx))
end

-- =========================================================================
-- MAIN LOOP
-- =========================================================================
Loop = function()
    -- Clear design mode overlay rects for this frame
    dm_rects = {}
    reflex_keyboard_capture_requested = false
    route_hovered_send_idx = nil  -- reset per frame
    nav_title_peek_consumed = false  -- v20.442: reset Opt+title-click peek flag
    nav_rclick_consumed = false  -- v20.486: any in-card right-click handler consumed the click; gates inspector card catch-all
    MaybeReloadPins()  -- v20.480: refresh pin set if user switched project tab
    MaybeReloadNavTreeExpansion()
    MaybeReloadNavExcluded()  -- v20.501: excluded TLTs are per-project GUID state
    MaybeReloadNavIncluded()
    MaybeSyncViewModeProject()
    local project_tab_changed = ReflexSyncNavigatorProjectTab()

    -- v20.445/v20.448: Hand keyboard focus to REAPER's main window so arrow
    -- keys (transport, item nav) work without first clicking either window.
    -- Multi-frame attempts because OS window state takes time to settle on
    -- script open. Combines SetForeground (macOS-aggressive activation) with
    -- SetFocus (keyboard-focus claim).
    if not nav_focus_done then
        nav_focus_frame = nav_focus_frame + 1
        if nav_focus_frame == 1 or nav_focus_frame == 3
           or nav_focus_frame == 8 or nav_focus_frame == 18 then
            local main_hwnd = r.GetMainHwnd and r.GetMainHwnd() or nil
            if main_hwnd then
                if r.JS_Window_SetForeground then r.JS_Window_SetForeground(main_hwnd) end
                if r.JS_Window_SetFocus then r.JS_Window_SetFocus(main_hwnd) end
            end
        end
        if nav_focus_frame >= 18 then nav_focus_done = true end
    end

    -- v20.449: Monitor all tracks for FX-count growth (instruments-first).
    MonitorTrackFxCounts()
    ProcessFXBrowserActionPrompt()

    -- FX drag: Escape cancels any in-progress drag (seeded or active)
    FxDragPollEscape()

    -- Periodic dead-pointer cache cleanup (every ~300 frames)
    cache_sweep_counter = cache_sweep_counter + 1
    if cache_sweep_counter >= 300 then
        cache_sweep_counter = 0
        SweepDeadTrackCaches()
    end

    -- Invalidate stale data when project changes or closes
    local nt = r.CountTracks(0)
    local proj_state = r.GetProjectStateChangeCount(0)
    if nt == 0 or (#top_folders > 0 and not r.ValidatePtr(top_folders[1].track, "MediaTrack*")) then
        top_folders = {}; render_list = {}; song_entries = {}
        archive_entry = nil; songs_entry_ref = nil
        for _, sg in ipairs(sub_groups) do sg.entry_ref = nil; sg.entries = {} end
        needs_rescan = true; needs_song_rescan = true
    elseif nt ~= last_track_count then
        needs_rescan = true; needs_song_rescan = true
    elseif project_tab_changed then
        needs_rescan = true; needs_song_rescan = true
    elseif proj_state ~= last_project_state then
        project_state_rescan_pending = true
    end
    if project_state_rescan_pending then
        local now = r.time_precise()
        if now - last_rescan_time >= RESCAN_THROTTLE then
            needs_rescan = true; needs_song_rescan = true
        end
    end
    last_track_count = nt

    if needs_rescan and nt > 0 then
        ScanTopFolders(); ScanSubGroups(); BuildRenderList()
        last_rescan_time = r.time_precise()
        last_project_state = proj_state
        project_state_rescan_pending = false
        -- Refresh routing view if active (tracks may have been added/removed/rearranged)
        -- (Routing/Active views are inert snapshots — no re-apply on rescan)
        if flow_view_active then FlowViewRefresh() end
    elseif not project_state_rescan_pending then
        last_project_state = proj_state
    end

    -- Force tracks page if no SONGS folder exists
    if (not opt_live_mode or not songs_entry_ref) and current_page == "songs" then current_page = "tracks" end

    -- Inspector: poll selected track (unless pinned). External selected-track FX
    -- browser handoffs temporarily select a target track; while that synthetic
    -- selection is active, keep Reflex's current view/state pinned in place.
    external_fx_selection_guard = ExternalFxSessionUpdate()
    if external_fx_selection_guard then
        if insp_track and not r.ValidatePtr(insp_track, "MediaTrack*") then
            InspCleanupDragState()
            insp_track = nil; insp_env_expanded = {}; insp_pinned = false
        end
    elseif insp_pinned and insp_track then
        -- Clear suppress flag when TCP selection changes in normal view
        if not flow_view_active then
            local cur_sel = r.CountSelectedTracks(0) > 0 and r.GetSelectedTrack(0, 0) or nil
            local cur_sel_guid = cur_sel and r.ValidatePtr(cur_sel, "MediaTrack*") and r.GetTrackGUID(cur_sel) or nil
            if cur_sel_guid ~= insp_pin_last_sel_guid then
                insp_pin_last_sel_guid = cur_sel_guid
                insp_pin_suppress_selected = false
                insp_pin_sel_env = {}
                insp_pin_sel_frames = 0
                -- Don't push view history here: pinned TCP clicks don't change
                -- any navigatable state (insp_track/pinned/visibility all unchanged).
            end
        end
        -- Pinned: only validate pointer and refresh state
        -- Exception: flow browse override (clicking a flow card while pinned)
        if flow_view_active and flow_view_browsing then
            local sel_track = r.CountSelectedTracks(0) > 0 and r.GetSelectedTrack(0, 0) or nil
            if sel_track and sel_track ~= insp_track then
                insp_track = sel_track
                InspScanTrack(insp_track)
                insp_env_expanded = {}
                SendsViewCheckRefresh()
                -- v20.429: push history. Unlike normal pinned TCP sync (no push,
                -- per Pinned TCP Sync convention — pinned mode doesn't change
                -- navigatable state), this branch DOES change insp_track and
                -- is a navigatable transition. Without this, the intermediate
                -- "pinned + browsing other track" state is never recorded.
                ViewHistoryPush()
            end
            flow_view_browsing = false
        elseif not r.ValidatePtr(insp_track, "MediaTrack*") then
            InspCleanupDragState()
            insp_track = nil; insp_env_expanded = {}; insp_pinned = false
        else
            -- v20.434 Stage C: read cached count directly to compare against live
            -- REAPER count. Going through InspGetFxList here would lazy-rescan and
            -- defeat the mismatch detection (cached_count would always equal live).
            local fx_count = r.TrackFX_GetCount(insp_track)
            local cached = track_fx_cache[insp_track]
            local cached_count = cached and cached.count or 0
            if fx_count ~= cached_count then
                InspMoveNewInstruments(insp_track, cached_count)
                InspMoveInsertedFX(insp_track)
                local te = insp_env_expanded["track_env"]
                InspScanTrack(insp_track); insp_env_expanded = { track_env = te }; insp_rename_type = nil
            else
                if InspRefreshFXState(insp_track) then
                    local te = insp_env_expanded["track_env"]
                    InspScanTrack(insp_track); insp_env_expanded = { track_env = te }; insp_rename_type = nil
                end
            end
        end
    else
        local sel_track = r.CountSelectedTracks(0) > 0 and r.GetSelectedTrack(0, 0) or nil
        if not sel_track then
            local master = r.GetMasterTrack(0)
            if r.IsTrackSelected(master) then sel_track = master end
        end
        -- When nothing is selected (e.g. click blank TCP), keep showing last track
        if not sel_track and insp_track and r.ValidatePtr(insp_track, "MediaTrack*") then
            sel_track = insp_track
        end
        if sel_track ~= insp_track then
            local is_launch_sync = view_history_count == 0 and insp_track == nil
            -- Close any open drag undo blocks before switching
            local next_flow_chain = nil
            if flow_view_active then
                if flow_view_browsing then
                    next_flow_chain = flow_view_chain
                elseif sel_track then
                    next_flow_chain = FlowViewBuildChain(sel_track)
                end
            end
            local keep_fx_selection = InspFxSelTrackWouldRemainVisible(sel_track, next_flow_chain)
            InspCleanupDragState({ keep_fx_selection = keep_fx_selection })
            insp_track = sel_track
            InspScanTrack(insp_track)
            insp_env_expanded = {}
            insp_vol_editing = false; insp_pan_editing = false
            if insp_track then insp_meter_clip[insp_track] = nil; insp_meter_peak[insp_track] = nil end
            insp_rename_type = nil
            insp_vol_edit_focus = false; insp_pan_edit_focus = false
            insp_vol_edit_frames = 0; insp_pan_edit_frames = 0
            if flow_view_active then
                if flow_view_browsing then
                    -- Selection came from clicking a flow card — don't re-anchor
                    flow_view_browsing = false
                else
                    -- External selection change (TCP click, etc.) — re-anchor the chain
                    if sel_track then
                        flow_view_anchor = sel_track
                        flow_view_chain = next_flow_chain or FlowViewBuildChain(sel_track)
                    end
                end
            end
            SendsViewCheckRefresh()
            ViewHistoryPush(is_launch_sync and { launch_baseline = true } or nil)
        elseif insp_track and r.ValidatePtr(insp_track, "MediaTrack*") then
            -- v20.434 Stage C: see pinned branch above for cached_count rationale.
            local fx_count = r.TrackFX_GetCount(insp_track)
            local cached = track_fx_cache[insp_track]
            local cached_count = cached and cached.count or 0
            if fx_count ~= cached_count then
                InspMoveNewInstruments(insp_track, cached_count)
                InspMoveInsertedFX(insp_track)
                local te = insp_env_expanded["track_env"]
                InspScanTrack(insp_track); insp_env_expanded = { track_env = te }; insp_rename_type = nil
            else
                if InspRefreshFXState(insp_track) then
                    local te = insp_env_expanded["track_env"]
                    InspScanTrack(insp_track); insp_env_expanded = { track_env = te }; insp_rename_type = nil
                end
            end
        elseif insp_track and not r.ValidatePtr(insp_track, "MediaTrack*") then
            insp_track = nil; insp_env_expanded = {}
        end
    end

    -- Stale insert position guard: clear if FX count unchanged after 5s (browser was closed without adding)
    if insp_fx_insert_target and insp_fx_insert_time > 0 then
        if insp_track and r.ValidatePtr(insp_track, "MediaTrack*") then
            if r.TrackFX_GetCount(insp_track) ~= insp_fx_insert_count then
                -- FX was added, InspMoveInsertedFX will handle it
            elseif r.time_precise() - insp_fx_insert_time > 15.0 then
                insp_fx_insert_target = nil; insp_fx_insert_count = 0; insp_fx_insert_time = 0
            end
        else
            insp_fx_insert_target = nil; insp_fx_insert_count = 0; insp_fx_insert_time = 0
        end
    end

    local sp = S(BASE_SPACING)

    InspCmpCheckGlobal()

    -- Push 5 colors + 6 vars (+ optional tab/dock colors)
    local main_bg = opt_card_boxes and C.window_bg or C.bg
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), main_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), C.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), main_bg)  -- hide dock tab bar text/triangle
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), main_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), main_bg)
    -- Hide dock tab bar elements (blue triangle, tab backgrounds)
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
    -- Try new API names first (ReaImGui 0.9+), fall back to old names
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
    -- Also hide the triangle button itself
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
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), S(UI.edge_pad), S(UI.edge_pad))
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), S(BASE_PAD_X), S(BASE_PAD_Y))
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), sp, sp)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), reflex_window_docked and 0 or S(10))
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ButtonTextAlign(), 0, 0.5)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
    local smooth_tess_count = 0
    if r.ImGui_StyleVar_CircleTessellationMaxError then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CircleTessellationMaxError(), 0.03)
        smooth_tess_count = 1
    end
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarBg(), 0x3E3E3FFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrab(), C.bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrabHovered(), C.bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrabActive(), C.bg)
    dock_color_count = dock_color_count + 4
    PushPopupStyle()

    local reflex_min_w = ReflexWindowMinWidth()
    if not window_initialized then
        r.ImGui_SetNextWindowSize(ctx, math.max(S(BASE_W) + S(28), reflex_min_w), 500)
        window_initialized = true
    end
    r.ImGui_SetNextWindowSizeConstraints(ctx, reflex_min_w, 200, math.max(WIN_MAX_W, reflex_min_w), 99999)

    local wflags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
    if r.ImGui_WindowFlags_NoTitleBar then
        wflags = wflags | r.ImGui_WindowFlags_NoTitleBar()
    end
    -- v20.448: prevent the window from grabbing OS-level focus when it first
    -- appears, so REAPER keeps keyboard input on script open.
    if r.ImGui_WindowFlags_NoFocusOnAppearing then
        wflags = wflags | r.ImGui_WindowFlags_NoFocusOnAppearing()
    end
    local visible, open = r.ImGui_Begin(ctx, "Reflex", true, wflags)

    if visible then
        RouteDragBeginFrame()
        ExternalFxCancelOnReflexInteraction()
        -- v20.417: Focus-grab click suppression for carry mode.
        -- When Reflex is unfocused while clipboard is active, the user
        -- has been told (via the carry pill hint) to "click to focus" so
        -- they can paste. If their focus-grabbing click lands on an FX row,
        -- the row's normal action — opening the plugin UI — fires before
        -- the user can press Cmd+V. Worse, a click on M/S would toggle
        -- audio state. Solution: detect the false→true focus transition
        -- on the click PRESS, set the eat_click flag, and persist it through
        -- the entire press→release cycle so action gates (which fire at the
        -- Selectable's release frame) and the bg-click release gate both
        -- see eat=true. Other circumstances (no clipboard, already focused,
        -- etc.) are unaffected — narrow gate per design.
        --
        -- v20.435: persistence-across-press-release fix. Previously eat_click
        -- was set only on the focus-transition frame; ImGui Selectable returns
        -- sel=true on RELEASE (typically frame N+1 from focus-grab press),
        -- by which time the flag had reset and the action fired anyway.
        -- Now eat_click persists until one frame after the mouse goes up.
        local nav_focus_now = r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows())
        -- Reflex owns clipboard/app shortcuts while focused. If we leave
        -- keyboard capture disabled in the idle state, REAPER can consume
        -- native edit chords (Cmd+C/X/V) before ReaImGui reports them, even
        -- though non-conflicting keys like A still appear to work.
        reflex_keyboard_capture_requested = nav_focus_now
        local mouse_down = r.ImGui_IsMouseDown(ctx, 0)
        if nav_focus_now and not (nav_focus_was or false)
           and FxClipHasContent() and mouse_down then
            -- Focus transition during a left-button press → mark this entire
            -- click cycle as "to be eaten" until release fully completes.
            nav_focus_grab_eat_click = true
        end
        if nav_focus_grab_eat_click and not mouse_down
           and not r.ImGui_IsMouseReleased(ctx, 0) then
            -- Mouse has been up for at least one frame past the release.
            -- All action gates have had a chance to see eat=true on the
            -- release frame. Safe to clear now.
            nav_focus_grab_eat_click = false
        end
        nav_focus_was = nav_focus_now

        -- v20.435: force OS focus on right-click anywhere within Reflex.
        -- macOS default: right-click on an unfocused window delivers the click
        -- but doesn't activate the window. ImGui auto-focuses on left-click
        -- (handles that case naturally), but a right-click → popup → menu-item
        -- path leaves Reflex unfocused — so subsequent ⌘V is intercepted
        -- by REAPER and the user can't paste their just-copied clipboard.
        -- Calling SetWindowFocus on right-click brings Reflex to the front
        -- of ImGui's window stack and (in ReaImGui's docking-branch
        -- implementation) requests OS-level activation for the viewport.
        --
        -- Ungated: any right-click within window bounds triggers focus, even
        -- if Reflex already has focus. Idempotent in that case.
        if r.ImGui_IsMouseClicked(ctx, 1)
           and r.ImGui_IsWindowHovered(ctx, r.ImGui_HoveredFlags_RootAndChildWindows()
                | r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem()
                | r.ImGui_HoveredFlags_AllowWhenBlockedByPopup()) then
            r.ImGui_SetWindowFocus(ctx)
        end

        -- Track window position for FX window positioning
        local wx, wy = r.ImGui_GetWindowPos(ctx)
        local ww, wh = r.ImGui_GetWindowSize(ctx)
        nav_screen_rect.x = wx; nav_screen_rect.y = wy
        nav_screen_rect.w = ww; nav_screen_rect.h = wh

        reflex_window_docked = r.ImGui_IsWindowDocked and r.ImGui_IsWindowDocked(ctx) or false
        if r.ImGui_GetWindowDockID then
            local ok_dock, dock_id = pcall(r.ImGui_GetWindowDockID, ctx)
            if ok_dock and type(dock_id) == "number" then
                reflex_current_dock_id = dock_id
            end
        else
            reflex_current_dock_id = reflex_window_docked and -1 or 0
        end
        local reflex_dock_pos = ReflexDockPosition(reflex_current_dock_id)
        local reflex_use_reapertips_dock_compensation = ReflexIsMacOS() and ReflexIsReapertipsTheme()
        local reflex_detected_dock_pos = (reflex_window_docked and reflex_use_reapertips_dock_compensation)
            and ReflexVisualSideDockPosition(wx, ww, reflex_dock_pos) or nil
        local reflex_visual_dock_pos = reflex_detected_dock_pos
            or (reflex_window_docked and reflex_last_side_dock_pos or nil)
        if reflex_visual_dock_pos == 1 or reflex_visual_dock_pos == 3 then
            reflex_last_side_dock_pos = reflex_visual_dock_pos
        end
        local reflex_use_dock_gap_offset = reflex_window_docked
            and reflex_use_reapertips_dock_compensation
            and (reflex_visual_dock_pos == 1 or reflex_visual_dock_pos == 3)
        local reflex_right_edge_extend = reflex_use_dock_gap_offset and (S(UI.edge_pad) - 3) or 0
        local reflex_scroll_indicator_x = wx + ww - (reflex_use_dock_gap_offset and S(3) or S(UI.edge_pad))

        -- ReaperTips needs the same side-dock chrome compensation as Navigator.
        -- Other themes keep the normal window gap on both sides.
        local sb_inset = -reflex_right_edge_extend
        -- Single source of truth for ALL card gaps. REAPER's docker frame
        -- consumes ~2px of WindowPadding at the edges, so card-to-card gaps
        -- must subtract the same amount to match the visible edge gap.
        local gap_px = S(UI.edge_pad) - 2

        -- Restore text color (was set to bg to hide dock tab triangle)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
        local fp = PushFont(GetScaledFont())

        -- Per-frame peak tracking for active view (always runs to build history)
        ActiveViewUpdatePeaks()
        ReflexNavigatorPollExternalCommand()

        -- Decrement view history restore cooldown
        if view_history_restoring > 0 then view_history_restoring = view_history_restoring - 1 end

        -- Poll ExtState for history actions (set by companion REAPER action scripts)
        if r.GetExtState("reflex", "history_back") == "1" then
            r.SetExtState("reflex", "history_back", "", false)
            ExternalFxSessionCancel()
            ViewHistoryBack()
        end
        if r.GetExtState("reflex", "history_forward") == "1" then
            r.SetExtState("reflex", "history_forward", "", false)
            ExternalFxSessionCancel()
            ViewHistoryForward()
        end

        -- Reflex-owned app shortcuts. REAPER shortcuts are mirrored only from
        -- the explicit allowlist below.
        ReflexDispatchAppHotkeys()
        ReflexMirrorReaperShortcuts()

        -- FX clipboard + Delete shortcuts (v20.407, widened v20.410).
        -- These are Reflex-owned shortcuts; REAPER global shortcuts are allowed
        -- through by the shared keyboard-passthrough helper. Reason: after
        -- alt-tabbing away from REAPER and
        -- returning via a click in Arrange (not Reflex), Reflex's ImGui
        -- window doesn't regain focus until the user clicks inside it.
        -- Pressing Cmd+V in that state would otherwise silently fail — green
        -- outlines still visible, clipboard still populated, but dispatch
        -- never fires. Widening to accept hover as an intent signal makes
        -- "hover over a target card and paste" work without a pre-click.
        -- Remaining safety: Cmd+V fires REAPER's global paste too if REAPER
        -- has focus; user should dismiss Reflex carrying state (Esc) if
        -- they don't want Reflex's paste to engage.
        -- FX clipboard + Delete shortcuts.
        -- v20.414: focus required (was widened to focused-OR-hovered in v20.410).
        -- The widened version made the UI promise paste would work when Reflex
        -- wasn't actually receiving the keystroke — REAPER consumes Cmd+V when
        -- it has focus, so user thought they were pasting to Reflex but were
        -- actually pasting REAPER's clipboard into REAPER. Reverted to strict
        -- focus to match OS conventions: click into Reflex first, then act.
        -- Visual state indicators (carry pill, chip, source-row outlines) remain
        -- always-on since they reflect state, not action affordance. Dashed
        -- destination outline + insert line are also gated on focus (see
        -- FxClipResolveHover) so user gets consistent feedback: "if I see the
        -- target indicator, paste will work; if not, I need to click first."
        do
            local nav_focused = r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows())
            if nav_focused then
                local mods = r.ImGui_GetKeyMods(ctx)
                local key_c = ReflexHotkeyKeyPressed("ImGui_Key_C")
                local key_x = ReflexHotkeyKeyPressed("ImGui_Key_X")
                local key_v = ReflexHotkeyKeyPressed("ImGui_Key_V")
                local key_b = ReflexHotkeyKeyPressed("ImGui_Key_B")
                -- Clean Cmd (no Shift, no Opt): ⌘C / ⌘X / ⌘V / ⌘B
                if not r.ImGui_IsAnyItemActive(ctx) and IsCmd(mods)
                   and not IsShift(mods) and not IsAlt(mods) then
                    if key_c then
                        FxClipDoCopyOrCut("copy", false)
                    elseif key_x then
                        FxClipDoCopyOrCut("cut", false)
                    elseif key_v then
                        if FxClipHasContent() then
                            nav_fx_clip_pending_paste = { where = "below" }
                        end
                    elseif key_b then
                        if InspFxSelCount() > 0 and insp_fx_sel_track
                           and r.ValidatePtr(insp_fx_sel_track, "MediaTrack*") then
                            local fis = InspFxSelGetFis(insp_fx_sel_track)
                            if #fis > 0 then
                                r.Undo_BeginBlock()
                                for _, fi in ipairs(fis) do
                                    local en = r.TrackFX_GetEnabled(insp_fx_sel_track, fi)
                                    r.TrackFX_SetEnabled(insp_fx_sel_track, fi, not en)
                                end
                                r.Undo_EndBlock((#fis == 1 and "Reflex: FX bypass" or ("Reflex: Bypass " .. #fis .. " FX")), -1)
                            end
                        end
                    end
                end
                if not r.ImGui_IsAnyItemActive(ctx) and IsCmd(mods)
                   and IsShift(mods) and not IsAlt(mods) then
                    if key_c then
                        FxClipCopyAllFX(nil, false)
                    end
                end
                if not r.ImGui_IsAnyItemActive(ctx) and IsCmd(mods)
                   and IsAlt(mods) and not IsShift(mods) then
                    if key_c then
                        FxClipDoCopyOrCut("copy", true)
                    elseif key_x then
                        FxClipDoCopyOrCut("cut", true)
                    elseif key_b then
                        if InspFxSelCount() > 0 and insp_fx_sel_track
                           and r.ValidatePtr(insp_fx_sel_track, "MediaTrack*") then
                            local fis = InspFxSelGetFis(insp_fx_sel_track)
                            if #fis > 0 then
                                r.Undo_BeginBlock()
                                for _, fi in ipairs(fis) do
                                    local off = r.TrackFX_GetOffline(insp_fx_sel_track, fi)
                                    r.TrackFX_SetOffline(insp_fx_sel_track, fi, not off)
                                end
                                r.Undo_EndBlock((#fis == 1 and "Reflex: FX offline" or ("Reflex: Offline " .. #fis .. " FX")), -1)
                            end
                        end
                    end
                end
                if not r.ImGui_IsAnyItemActive(ctx) and not IsCmd(mods)
                   and not IsAlt(mods) and not IsCtrl(mods) then
                    local del = ReflexHotkeyKeyPressed("ImGui_Key_Delete")
                             or ReflexHotkeyKeyPressed("ImGui_Key_Backspace")
                    if del then
                        if IsShift(mods) then
                            local card = FxClipFindHoveredCard()
                            local tgt = (card and card.track) or insp_track
                            if tgt and r.ValidatePtr(tgt, "MediaTrack*") then
                                FxClipRemoveAllFX(tgt)
                            end
                        else
                            if InspFxSelCount() > 0 then FxClipDeleteSelection() end
                        end
                    end
                end
            end
        end

        -- ── LAYOUT: content + divider + remote ──
        local divider_h = S(6)
        local vh_bar_h = ReflexFooterButtonDiameter()
        local vh_row_h = ReflexFooterTotalHeight(vh_bar_h)
        local remote_inline = remote_visible and not remote_popped_out
        local win_pad = S(UI.edge_pad)
        local _, win_h = r.ImGui_GetContentRegionAvail(ctx)
        local rem_h
        if remote_inline then
            rem_h = math.max(remote_height, S(60))
            -- If content needs more room, shrink remote to accommodate
            if last_content_used_h > 0 then
                local nav_h_for_content = last_nav_side_layout and 0 or last_nav_h
                local needed_for_content = last_content_used_h + nav_h_for_content + divider_h + vh_row_h + win_pad
                local max_remote = math.max(S(60), win_h - needed_for_content)
                if max_remote < rem_h then rem_h = max_remote end
            end
        else
            rem_h = 0
        end
        local nav_content_gap_px = UI.nav_inspector_gap_px or 21
        -- BeginChild snaps the parent boundary to even Retina pixels. Keep that
        -- parent gap even, then place the card surface on a 1px half-logical
        -- child offset so odd Retina gaps remain possible.
        local nav_content_gap = math.max(0, nav_content_gap_px - 1) * 0.5 * nav_ui_scale
        local content_child_top_pad = nav_visible and 0 or S(UI.edge_pad)
        local content_surface_top_nudge = nav_visible and (0.5 * nav_ui_scale) or 0
        local pre_nav_parent_w = r.ImGui_GetContentRegionAvail(ctx)
        local pre_nav_child_w = math.max(pre_nav_parent_w + reflex_right_edge_extend, InspCardMinWidth())
        local pre_nav_layout = ReflexComputeInspectorColumnLayout(pre_nav_child_w, gap_px)
        local nav_two_column_body_visible = navigator_expanded == true
        if current_page == "tracks" then
            nav_two_column_body_visible = nav_two_column_body_visible
                or opt_nav_show_search ~= false
                or opt_nav_custom_set_mode == true
                or (nav_tlt_search_text or "") ~= ""
                or (nav_tlt_search_effective_query or "") ~= ""
        end
        local nav_side_layout = nav_visible
            and nav_two_column_body_visible
            and opt_two_column_nav == true
            and insp_visible
            and pre_nav_layout.two_column == true
        local bw = pre_nav_child_w
        if not nav_side_layout then
            local reflex_ui_scale = ui_scale
            local saved_scale_comp = ReflexSetBodyScaleCompensation(false)
            ui_scale = nav_ui_scale
            local nav_fp = PushFont(GetScaledFont())
            NavDrawSection({
                bw = bw,
                win_h = win_h,
                vh_row_h = vh_row_h,
                rem_h = rem_h,
                divider_h = divider_h,
                wx = wx,
                ww = ww,
                arrow_w = S(28),
                bh = S(BASE_H),
                base_pad_y = BASE_PAD_Y,
                content_gap = nav_content_gap,
                nav_split_h = nav_inspector_split_h,
                nav_temp_split_h = nav_inspector_temp_split_h,
            })
            PopFont(nav_fp)
            ui_scale = reflex_ui_scale
            ReflexSetBodyScaleCompensation(saved_scale_comp)
        end

        -- ── SCROLLABLE CONTENT (inspector, context menu) ──
        local content_parent_w = r.ImGui_GetContentRegionAvail(ctx)
        -- The child boundary is the card margin. On normal right-side docks,
        -- keep the right gap equal to WindowPadding instead of extending into
        -- the docker chrome compensation used by Reflex's left-dock baseline.
        local child_w = content_parent_w + reflex_right_edge_extend
        child_w = math.max(child_w, InspCardMinWidth())
        local pre_bw = child_w  -- total card region width
        if not nav_side_layout and nav_visible and (navigator_expanded == true or nav_temporary_expanded == true) then
            local gap_hit_h = math.max(nav_content_gap + content_surface_top_nudge, 0.5 * nav_content_gap_px * nav_ui_scale)
            local max_split_h = math.max(S(72), win_h - vh_row_h - rem_h - divider_h - gap_hit_h - S(60))
            ReflexDrawNavSplitHandle(child_w, gap_hit_h, max_split_h)
        end

        local master_stack_est_h = (insp_visible and ReflexShouldShowMasterTrackStrip())
            and ((master_strip_prev_h or S(72)) + gap_px)
            or 0
        local function draw_master_in_card_stack(stack_w)
            if not (insp_visible and ReflexShouldShowMasterTrackStrip()) then return 0 end
            ReflexDrawMasterTrackStrip(stack_w, S(BASE_H), gap_px)
        end

        local scroll_h = rem_h > 0 and -(rem_h + divider_h + vh_row_h) or -vh_row_h

        -- Pre-compute sends_side at loop level for independent column scrolling
        local loop_sends_side = false
        local loop_insp_bw = pre_bw
        local loop_sends_bw = 0
        local loop_side_gap = gap_px
        local sends_inline_min_w = ReflexSendModuleInlineMinWidth()
        local sends_force_inline = false
        local sends_prefer_inline = false
        local loop_sends_inline = false
        local nav_body_offset_est = nav_side_layout and math.max(0, last_nav_body_offset_y or 0) or 0
        local content_visible_h = math.max(S(80),
            win_h - master_stack_est_h
                - (rem_h > 0 and (rem_h + divider_h + vh_row_h) or vh_row_h)
                - content_child_top_pad
                - nav_body_offset_est)
        if insp_visible and opt_two_column_mode == true and (opt_show_sends or nav_side_layout) then
            local loop_layout = nav_side_layout and pre_nav_layout
                or ReflexComputeInspectorColumnLayout(pre_bw, loop_side_gap)
            if loop_layout.two_column then
                loop_insp_bw = loop_layout.inspector_w
                loop_sends_bw = loop_layout.side_w
                sends_force_inline = opt_show_sends and loop_sends_bw < sends_inline_min_w
                if opt_show_sends then
                    local fallback_cards_h = (last_content_used_h and last_content_used_h > 0)
                        and math.max(0, last_content_used_h - master_stack_est_h)
                        or S(320)
                    local estimated_cards_h = last_inspector_cards_content_h or fallback_cards_h
                    local estimated_sends_h = math.max(
                        last_inline_sends_content_h or 0,
                        nav_sends_left_content_h or 0,
                        S(220)
                    )
                    local overflow_retry_margin = last_inline_sends_overflow and S(24) or 0
                    sends_prefer_inline = (estimated_cards_h + estimated_sends_h
                        + S(UI.edge_pad) + overflow_retry_margin) <= content_visible_h
                end
                loop_sends_inline = opt_show_sends and (sends_force_inline or sends_prefer_inline)
                loop_sends_side = opt_show_sends and not loop_sends_inline
            end
        end

        -- Fade timing
        local now_t = r.time_precise()
        local dt = scroll_fade_last_t > 0 and (now_t - scroll_fade_last_t) or 0
        scroll_fade_last_t = now_t
        dt = math.min(dt, 0.1)  -- clamp for first frame / hitches

        local main_dl = r.ImGui_GetWindowDrawList(ctx)

        last_nav_side_layout = nav_side_layout == true

        if nav_side_layout then
            local child_start_x = r.ImGui_GetCursorPosX(ctx)
            local child_start_y = r.ImGui_GetCursorPosY(ctx)
            local nav_child_w = loop_sends_bw
            local nav_layer_w = child_w
            local insp_child_w = loop_insp_bw
            local sends_under_card = loop_sends_inline
            local left_used_h = 0
            local right_used_h = 0
            local nav_body_offset_y = 0

            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
            local nav_layer_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
            local nav_child_open = r.ImGui_BeginChild(ctx, "##nav_sends_content", nav_layer_w, scroll_h, 0, nav_layer_flags)
            r.ImGui_PopStyleVar(ctx, 1)

            if nav_child_open then
                if r.ImGui_GetScrollY(ctx) ~= 0 then
                    r.ImGui_SetScrollY(ctx, 0)
                end
                local nav_col_h = select(2, r.ImGui_GetWindowSize(ctx))
                local reflex_ui_scale = ui_scale
                local saved_scale_comp = ReflexSetBodyScaleCompensation(false)
                ui_scale = nav_ui_scale
                local nav_fp = PushFont(GetScaledFont())
                NavDrawSection({
                    bw = nav_layer_w,
                    nav_body_w = nav_child_w,
                    win_h = nav_col_h,
                    vh_row_h = 0,
                    rem_h = 0,
                    divider_h = 0,
                    wx = wx,
                    ww = ww,
                    arrow_w = S(28),
                    bh = S(BASE_H),
                    base_pad_y = BASE_PAD_Y,
                    content_gap = nav_content_gap,
                    nav_split_h = nav_inspector_split_h,
                    nav_temp_split_h = nav_inspector_temp_split_h,
                    nav_bottom_extra = sends_under_card and 0 or S(60),
                })
                PopFont(nav_fp)
                ui_scale = reflex_ui_scale
                ReflexSetBodyScaleCompensation(saved_scale_comp)
                nav_body_offset_y = math.max(0, last_nav_body_offset_y or 0)

                local gap_hit_h = math.max(nav_content_gap + content_surface_top_nudge, 0.5 * nav_content_gap_px * nav_ui_scale)
                local max_split_h = math.max(S(72), nav_col_h - (sends_under_card and 0 or S(60)))
                r.ImGui_SetCursorPosX(ctx, 0)
                ReflexDrawNavSplitHandle(nav_child_w, gap_hit_h, max_split_h)
                do
                    local nav_win_x, nav_win_y = r.ImGui_GetWindowPos(ctx)
                    local _, nav_win_h = r.ImGui_GetWindowSize(ctx)
                    ReflexDrawColumnSplitHandle("##two_col_split_nav", nav_win_x + nav_child_w,
                        nav_win_y + nav_body_offset_y, loop_side_gap, nav_win_y + nav_win_h,
                        pre_bw, loop_side_gap, nav_child_w)
                end

                if sends_under_card or not opt_show_sends then
                    if not opt_show_sends then
                        nav_sends_left_overflow = false
                    else
                        local estimated_sends_h = nav_sends_left_content_h or S(220)
                        local _, remaining_h = r.ImGui_GetContentRegionAvail(ctx)
                        if remaining_h >= estimated_sends_h + S(UI.edge_pad) then
                            nav_sends_left_overflow = false
                        end
                    end
                    r.ImGui_Dummy(ctx, 1, 1)
                else
                    r.ImGui_SetCursorPosX(ctx, 0)
                    local _, sends_avail_h = r.ImGui_GetContentRegionAvail(ctx)
                    sends_avail_h = math.max(S(40), sends_avail_h)
                    if content_surface_top_nudge > 0 then
                        r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + content_surface_top_nudge)
                    end
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
                    local sends_child_open = r.ImGui_BeginChild(ctx, "##sends_content", nav_child_w, sends_avail_h, 0, r.ImGui_WindowFlags_NoScrollbar())
                    r.ImGui_PopStyleVar(ctx, 1)
                    if sends_child_open then
                        if sends_scroll_target then
                            r.ImGui_SetScrollY(ctx, sends_scroll_target)
                            sends_scroll_target = nil
                        end
                        if sends_expand_scroll_cy then
                            local visible_h = select(2, r.ImGui_GetWindowSize(ctx))
                            r.ImGui_SetScrollY(ctx, math.max(0, sends_expand_scroll_cy - visible_h * 0.3))
                            sends_expand_scroll_cy = nil
                        end
                        FxDragApplyScroll("##sends_content")
                        if insp_track and r.ValidatePtr(insp_track, "MediaTrack*") then
                            DrawSendsColumn(nav_child_w)
                        end
                        r.ImGui_Dummy(ctx, 1, S(UI.edge_pad))
                        nav_sends_left_content_h = r.ImGui_GetCursorPosY(ctx)
                        sends_scroll_y = r.ImGui_GetScrollY(ctx)
                        sends_scroll_max = r.ImGui_GetScrollMaxY(ctx)
                        sends_scroll_child_h = select(2, r.ImGui_GetWindowSize(ctx))
                        nav_sends_left_overflow = sends_scroll_max > 0.5
                        do
                            local cwx, cwy = r.ImGui_GetWindowPos(ctx)
                            local cww, cwh = r.ImGui_GetWindowSize(ctx)
                            FxDragAutoScrollCheck("##sends_content", cwx, cwy, cww, cwh)
                        end
                        r.ImGui_EndChild(ctx)
                    end
                end
                left_used_h = r.ImGui_GetCursorPosY(ctx)
                r.ImGui_Dummy(ctx, 1, 1)
                left_used_h = math.max(left_used_h, r.ImGui_GetCursorPosY(ctx))
                r.ImGui_EndChild(ctx)
            end

            r.ImGui_SetCursorPos(ctx, child_start_x + nav_child_w + loop_side_gap, child_start_y + nav_body_offset_y)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, content_child_top_pad)
            local insp_child_open = r.ImGui_BeginChild(ctx, "##content", insp_child_w, scroll_h, 0, r.ImGui_WindowFlags_NoScrollbar())
            r.ImGui_PopStyleVar(ctx, 1)

            if insp_child_open then
                if nav_scroll_target then
                    r.ImGui_SetScrollY(ctx, nav_scroll_target)
                    nav_scroll_target = nil
                end
                if sends_under_card and sends_expand_scroll_cy then
                    local visible_h = select(2, r.ImGui_GetWindowSize(ctx))
                    r.ImGui_SetScrollY(ctx, math.max(0, sends_expand_scroll_cy - visible_h * 0.3))
                    sends_expand_scroll_cy = nil
                end
                FxDragApplyScroll("##content")
                if content_surface_top_nudge > 0 then
                    r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + content_surface_top_nudge)
                end

                bw = insp_child_w
                card_idx = 0
                card_heights_cur = {}

                draw_master_in_card_stack(bw)

                if insp_visible then
                    local saved_sends = opt_show_sends
                    opt_show_sends = sends_under_card
                    InspDrawInspector(bw, bh)
                    opt_show_sends = saved_sends
                end

                r.ImGui_Spacing(ctx)
                r.ImGui_Dummy(ctx, 1, S(UI.edge_pad))
                right_used_h = nav_body_offset_y + r.ImGui_GetCursorPosY(ctx)
                last_content_used_h = math.max(left_used_h, right_used_h)
                nav_scroll_y = r.ImGui_GetScrollY(ctx)
                nav_scroll_max = r.ImGui_GetScrollMaxY(ctx)
                if opt_show_sends and sends_under_card then
                    last_inline_sends_overflow = sends_under_card == true and nav_scroll_max > 0.5
                elseif not opt_show_sends then
                    last_inline_sends_overflow = false
                end
                nav_child_h = select(2, r.ImGui_GetWindowSize(ctx))
                card_heights_prev = card_heights_cur

                do
                    local cwx, cwy = r.ImGui_GetWindowPos(ctx)
                    local cww, cwh = r.ImGui_GetWindowSize(ctx)
                    FxDragAutoScrollCheck("##content", cwx, cwy, cww, cwh)
                end
                r.ImGui_EndChild(ctx)
            end

            do
                local _, iy1 = r.ImGui_GetItemRectMin(ctx)
                local _, iy2 = r.ImGui_GetItemRectMax(ctx)
                if nav_scroll_y ~= insp_scroll_prev_y then insp_scroll_fade = 1.8 end
                insp_scroll_prev_y = nav_scroll_y
                if insp_scroll_fade > 0 then insp_scroll_fade = insp_scroll_fade - dt * 2.5 end
                DrawScrollIndicator(main_dl, iy1, iy2, nav_scroll_y, nav_scroll_max, nav_child_h, insp_scroll_fade, reflex_scroll_indicator_x)
            end
        elseif loop_sends_side then
            -- ── TWO-COLUMN LAYOUT: independent scrolling ──
            local child_start_x = r.ImGui_GetCursorPosX(ctx)
            local child_start_y = r.ImGui_GetCursorPosY(ctx)
            local insp_child_w = loop_insp_bw  -- exact content width — no dead space
            local sends_child_w = loop_sends_bw

            -- Sends scroll child (left column)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, content_child_top_pad)
            local sends_child_open = r.ImGui_BeginChild(ctx, "##sends_content", sends_child_w, scroll_h, 0, r.ImGui_WindowFlags_NoScrollbar())
            r.ImGui_PopStyleVar(ctx, 1)

            if sends_child_open then

            if sends_scroll_target then
                r.ImGui_SetScrollY(ctx, sends_scroll_target)
                sends_scroll_target = nil
            end
            if sends_expand_scroll_cy then
                local visible_h = select(2, r.ImGui_GetWindowSize(ctx))
                r.ImGui_SetScrollY(ctx, math.max(0, sends_expand_scroll_cy - visible_h * 0.3))
                sends_expand_scroll_cy = nil
            end
            FxDragApplyScroll("##sends_content")
            if content_surface_top_nudge > 0 then
                r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + content_surface_top_nudge)
            end

            if insp_track and r.ValidatePtr(insp_track, "MediaTrack*") then
                DrawSendsColumn(loop_sends_bw)
            end

            r.ImGui_Spacing(ctx)
            r.ImGui_Dummy(ctx, 1, S(UI.edge_pad))  -- bottom padding for full scroll range
            nav_sends_left_content_h = r.ImGui_GetCursorPosY(ctx)
            sends_scroll_y = r.ImGui_GetScrollY(ctx)
            sends_scroll_max = r.ImGui_GetScrollMaxY(ctx)
            sends_scroll_child_h = select(2, r.ImGui_GetWindowSize(ctx))

            -- Auto-scroll detection during FX drag
            do
                local cwx, cwy = r.ImGui_GetWindowPos(ctx)
                local cww, cwh = r.ImGui_GetWindowSize(ctx)
                FxDragAutoScrollCheck("##sends_content", cwx, cwy, cww, cwh)
            end

            r.ImGui_EndChild(ctx)

            end -- sends_child_open

            local _, sends_item_y1 = r.ImGui_GetItemRectMin(ctx)
            local sends_item_x2, sends_item_y2 = r.ImGui_GetItemRectMax(ctx)

            -- Sends scroll indicator (centered in gap between columns)
            do
                if sends_scroll_y ~= sends_scroll_prev_y then sends_scroll_fade = 1.8 end
                sends_scroll_prev_y = sends_scroll_y
                if sends_scroll_fade > 0 then sends_scroll_fade = sends_scroll_fade - dt * 2.5 end
                local ind_cx = sends_item_x2 + math.floor((loop_side_gap - S(3)) / 2)
                DrawScrollIndicator(main_dl, sends_item_y1, sends_item_y2, sends_scroll_y, sends_scroll_max, sends_scroll_child_h, sends_scroll_fade, ind_cx)
            end
            ReflexDrawColumnSplitHandle("##two_col_split_sends", sends_item_x2, sends_item_y1,
                loop_side_gap, sends_item_y2, pre_bw, loop_side_gap, sends_child_w)

            -- Inspector scroll child (right column)
            r.ImGui_SetCursorPos(ctx, child_start_x + sends_child_w + loop_side_gap, child_start_y)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, content_child_top_pad)
            local insp_child_open = r.ImGui_BeginChild(ctx, "##content", insp_child_w, scroll_h, 0, r.ImGui_WindowFlags_NoScrollbar())
            r.ImGui_PopStyleVar(ctx, 1)

            if insp_child_open then

            if nav_scroll_target then
                r.ImGui_SetScrollY(ctx, nav_scroll_target)
                nav_scroll_target = nil
            end
            FxDragApplyScroll("##content")
            if content_surface_top_nudge > 0 then
                r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + content_surface_top_nudge)
            end

            bw = loop_insp_bw
            card_idx = 0
            card_heights_cur = {}

            draw_master_in_card_stack(bw)

            if insp_visible then
                local saved_sends = opt_show_sends
                opt_show_sends = false
                InspDrawInspector(bw, bh)
                opt_show_sends = saved_sends
            end

            r.ImGui_Spacing(ctx)
            r.ImGui_Dummy(ctx, 1, S(UI.edge_pad))  -- bottom padding for full scroll range
            last_content_used_h = r.ImGui_GetCursorPosY(ctx)
            nav_scroll_y = r.ImGui_GetScrollY(ctx)
            nav_scroll_max = r.ImGui_GetScrollMaxY(ctx)
            if not opt_show_sends then
                last_inline_sends_overflow = false
            end
            nav_child_h = select(2, r.ImGui_GetWindowSize(ctx))
            card_heights_prev = card_heights_cur

            -- Auto-scroll detection during FX drag (wheel + edge proximity)
            do
                local cwx, cwy = r.ImGui_GetWindowPos(ctx)
                local cww, cwh = r.ImGui_GetWindowSize(ctx)
                FxDragAutoScrollCheck("##content", cwx, cwy, cww, cwh)
            end

            r.ImGui_EndChild(ctx)

            end -- insp_child_open

            -- Inspector scroll indicator (flush with window right edge)
            do
                local _, iy1 = r.ImGui_GetItemRectMin(ctx)
                local _, iy2 = r.ImGui_GetItemRectMax(ctx)
                if nav_scroll_y ~= insp_scroll_prev_y then insp_scroll_fade = 1.8 end
                insp_scroll_prev_y = nav_scroll_y
                if insp_scroll_fade > 0 then insp_scroll_fade = insp_scroll_fade - dt * 2.5 end
                DrawScrollIndicator(main_dl, iy1, iy2, nav_scroll_y, nav_scroll_max, nav_child_h, insp_scroll_fade, reflex_scroll_indicator_x)
            end

            -- Cursor Y is correctly positioned after second EndChild
        else
            -- ── SINGLE-COLUMN LAYOUT ──
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, content_child_top_pad)
            local content_open = r.ImGui_BeginChild(ctx, "##content", child_w, scroll_h, 0, r.ImGui_WindowFlags_NoScrollbar())
            r.ImGui_PopStyleVar(ctx, 1)

            if content_open then

            if nav_scroll_target then
                r.ImGui_SetScrollY(ctx, nav_scroll_target)
                nav_scroll_target = nil
            end
            if sends_expand_scroll_cy then
                local visible_h = select(2, r.ImGui_GetWindowSize(ctx))
                r.ImGui_SetScrollY(ctx, math.max(0, sends_expand_scroll_cy - visible_h * 0.3))
                sends_expand_scroll_cy = nil
            end
            FxDragApplyScroll("##content")
            if content_surface_top_nudge > 0 then
                r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + content_surface_top_nudge)
            end

            bw = r.ImGui_GetContentRegionAvail(ctx)  -- full width (right margin is outside child)
            card_idx = 0
            card_heights_cur = {}

            draw_master_in_card_stack(bw)

            if insp_visible then
                InspDrawInspector(bw, bh)
            end

            r.ImGui_Spacing(ctx)
            r.ImGui_Dummy(ctx, 1, S(UI.edge_pad))  -- bottom padding for full scroll range
            last_content_used_h = r.ImGui_GetCursorPosY(ctx)
            nav_scroll_y = r.ImGui_GetScrollY(ctx)
            nav_scroll_max = r.ImGui_GetScrollMaxY(ctx)
            if opt_show_sends then
                last_inline_sends_overflow = opt_two_column_mode == true
                    and loop_sends_side ~= true
                    and nav_scroll_max > 0.5
            else
                last_inline_sends_overflow = false
            end
            nav_child_h = select(2, r.ImGui_GetWindowSize(ctx))
            card_heights_prev = card_heights_cur

            -- Auto-scroll detection during FX drag (wheel + edge proximity)
            do
                local cwx, cwy = r.ImGui_GetWindowPos(ctx)
                local cww, cwh = r.ImGui_GetWindowSize(ctx)
                FxDragAutoScrollCheck("##content", cwx, cwy, cww, cwh)
            end

            r.ImGui_EndChild(ctx)

            end -- content_open

            -- Single-column scroll indicator (flush with window right edge)
            do
                local _, iy1 = r.ImGui_GetItemRectMin(ctx)
                local _, iy2 = r.ImGui_GetItemRectMax(ctx)
                if nav_scroll_y ~= insp_scroll_prev_y then insp_scroll_fade = 1.8 end
                insp_scroll_prev_y = nav_scroll_y
                if insp_scroll_fade > 0 then insp_scroll_fade = insp_scroll_fade - dt * 2.5 end
                DrawScrollIndicator(main_dl, iy1, iy2, nav_scroll_y, nav_scroll_max, nav_child_h, insp_scroll_fade, reflex_scroll_indicator_x)
            end
        end

        RouteDragProcessPendingRelease()

        -- ── FOOTER BAR (history left, settings/F/S right) ──
        do
            local saved_scale_comp = ReflexSetBodyScaleCompensation(false)
            local footer_fp = PushFont(GetScaledFont())
            local footer_d = ReflexFooterButtonDiameter()
            local footer_hit_w = ReflexFooterButtonHitWidth(footer_d)
            local footer_gap = ReflexFooterButtonGap()
            local footer_edge = ReflexFooterEdgeGap()
            local footer_row_h = ReflexFooterRowHeight(footer_d)
            local footer_dot_r = math.floor(footer_d / 2)
            local footer_y = r.ImGui_GetCursorPosY(ctx)
            local footer_cy = footer_y + math.floor(footer_row_h / 2)
            local footer_left_x = footer_edge
            local footer_right_x = ww - footer_edge - sb_inset
            local dl_footer = r.ImGui_GetWindowDrawList(ctx)
            local _, footer_screen_y = r.ImGui_GetCursorScreenPos(ctx)
            r.ImGui_DrawList_AddRectFilled(dl_footer, wx, footer_screen_y - S(2), wx + ww,
                footer_screen_y + ReflexFooterTotalHeight(footer_d), main_bg)

            local COL_FOOTER_REST_BG = rgb(0x171B21)
            local COL_FOOTER_TEXT_REST = rgb(0x919394)
            local FOOTER_INACTIVE_BG = (COL_FOOTER_REST_BG & 0xFFFFFF00) | 0x66
            local FOOTER_INACTIVE_FG = (COL_FOOTER_TEXT_REST & 0xFFFFFF00) | 0x66
            local FOOTER_TEXT_ACTIVE = 0xFFFFFFFF

            local function history_unavailable_bg()
                return (C.btn_bg & 0xFFFFFF00) | 0x30
            end

            local function history_unavailable_fg()
                return (C.text_dim & 0xFFFFFF00) | 0x50
            end

            local function footer_circle(id, cx, cy, opts)
                r.ImGui_SetCursorPos(ctx, cx - footer_dot_r, cy - footer_row_h * 0.5)
                local hov, clk, held = NavCircle(id, footer_d, nil, {
                    bg = opts.bg,
                    hov = opts.hov,
                    active = opts.active,
                    fg = opts.fg,
                    fg_hov = opts.fg_hov,
                    fg_active = opts.fg_active,
                    hit_w = footer_hit_w,
                    hit_h = footer_row_h,
                    no_press = opts.no_press,
                    segments = NAV_CIRCLE_SEGMENTS,
                })
                return hov, clk, held, r.ImGui_GetItemRectMin(ctx)
            end

            local function footer_history_button(id, glyph, enabled, tooltip, action_fn, cx, cy, glyph_x_nudge)
                local opts
                if enabled then
                    opts = {
                        bg = FOOTER_INACTIVE_BG,
                        hov = COL_FOOTER_REST_BG,
                        active = COL_FOOTER_REST_BG,
                        fg = COL_FOOTER_TEXT_REST,
                        fg_hov = COL_FOOTER_TEXT_REST,
                        fg_active = COL_FOOTER_TEXT_REST,
                        no_press = true,
                    }
                else
                    local fbg = history_unavailable_bg()
                    local ffg = history_unavailable_fg()
                    opts = {
                        bg = fbg,
                        hov = fbg,
                        active = fbg,
                        fg = ffg,
                        fg_hov = ffg,
                        fg_active = ffg,
                        no_press = true,
                    }
                end
                local hov, clk, _, x, y = footer_circle(id, cx, cy, opts)
                local fg = enabled and COL_FOOTER_TEXT_REST or history_unavailable_fg()
                local tw, th = r.ImGui_CalcTextSize(ctx, glyph)
                local tx = x + Round((footer_hit_w - tw) / 2) + (glyph_x_nudge or 0)
                local ty = y + Round((footer_row_h - th) / 2)
                r.ImGui_DrawList_AddText(dl_footer, tx, ty, fg, glyph)
                if hov and enabled then Tip(tooltip) end
                if enabled and clk and action_fn then action_fn() end
            end

            local function footer_mode_button(id, label, active, enabled, tooltip, action_fn, cx, cy, draw_icon)
                local active_bg = COL_FOOTER_REST_BG
                local bg = enabled and (active and active_bg or FOOTER_INACTIVE_BG) or FOOTER_INACTIVE_BG
                local hov_bg = enabled and active_bg or FOOTER_INACTIVE_BG
                local act_bg = enabled and active_bg or FOOTER_INACTIVE_BG
                local hov, clk, held, x, y = footer_circle(id, cx, cy, {
                    bg = bg,
                    hov = hov_bg,
                    active = act_bg,
                    fg = FOOTER_INACTIVE_FG,
                    fg_hov = COL_FOOTER_TEXT_REST,
                    fg_active = FOOTER_TEXT_ACTIVE,
                })
                local visual_active = active == true
                if enabled and clk then visual_active = not visual_active end
                local fg
                if not enabled then
                    fg = FOOTER_INACTIVE_FG
                elseif visual_active then
                    fg = FOOTER_TEXT_ACTIVE
                elseif hov or held then
                    fg = COL_FOOTER_TEXT_REST
                else
                    fg = FOOTER_INACTIVE_FG
                end
                local icon_cx = x + footer_hit_w * 0.5
                local icon_cy = y + footer_row_h * 0.5
                if draw_icon then
                    draw_icon(dl_footer, icon_cx, icon_cy, fg, footer_d)
                else
                    DrawFooterLabel(dl_footer, icon_cx, icon_cy, label, fg, footer_d)
                end
                if hov then Tip(tooltip) end
                if enabled and clk and action_fn then action_fn() end
            end

            local can_back = ViewHistoryCanBack and ViewHistoryCanBack() or false
            local can_fwd = ViewHistoryCanForward and ViewHistoryCanForward() or (view_history_idx < view_history_count)
            local footer_step = footer_hit_w + footer_gap
            local footer_render_r = footer_d / 2
            local back_cx = footer_left_x + footer_render_r
            local fwd_cx = back_cx + footer_step
            footer_history_button("##vhback", "\xE2\x97\x80", can_back,
                "Previous view", ViewHistoryBack, back_cx, footer_cy, -ReflexFooterRetinaPx(2))
            footer_history_button("##vhfwd", "\xE2\x96\xB6", can_fwd,
                "Next view", ViewHistoryForward, fwd_cx, footer_cy)

            local sends_cx = footer_right_x - footer_render_r
            local flow_cx = sends_cx - footer_step
            local columns_cx = flow_cx - footer_step
            local settings_cx = columns_cx - footer_step
            local right_group_x = settings_cx - footer_render_r
            local next_left_x = fwd_cx + footer_render_r

            if FxClipHasContent() then
                local clip_n = FxClipCount()
                local clip_col = C.fx_clip_carry or rgb(0x73A3F4)
                local clip_label = tostring(clip_n) .. "  ×"
                local clip_tw = r.ImGui_CalcTextSize(ctx, clip_label)
                local clip_pad_x = S(10)
                local clip_h = footer_d
                local clip_w = clip_tw + clip_pad_x * 2
                local clip_x = next_left_x + S(6)
                local clip_y = footer_cy - clip_h / 2
                if clip_x + clip_w <= right_group_x - footer_gap * 2 then
                    r.ImGui_SetCursorPos(ctx, clip_x, clip_y)
                    r.ImGui_InvisibleButton(ctx, "##fxclipchip", clip_w, clip_h)
                    local chov = r.ImGui_IsItemHovered(ctx)
                    local clk = r.ImGui_IsItemClicked(ctx, 0)
                    local cix, ciy = r.ImGui_GetItemRectMin(ctx)
                    local body_r = math.max(3, clip_h / 2)
                    if chov then
                        local fill = (clip_col & 0xFFFFFF00) | 0x4D
                        r.ImGui_DrawList_AddRectFilled(dl_footer, cix, ciy, cix + clip_w, ciy + clip_h, fill, body_r)
                    end
                    r.ImGui_DrawList_AddRect(dl_footer, cix, ciy, cix + clip_w, ciy + clip_h,
                        clip_col, body_r, 0, math.max(1, S(1)))
                    local _, cth = r.ImGui_CalcTextSize(ctx, clip_label)
                    local ctx_x = cix + clip_pad_x
                    local ctx_y = ciy + Round((clip_h - cth) / 2)
                    local txt_col = chov and (C.text or rgb(0xE6EDF3)) or clip_col
                    r.ImGui_DrawList_AddText(dl_footer, ctx_x, ctx_y, txt_col, clip_label)
                    if chov then TipDirect("FX in clipboard\nClick or press Esc to clear") end
                    if clk then
                        FxClipClear()
                        FxClipRebuildGuidSet()
                    end
                    next_left_x = clip_x + clip_w
                end
            end

            local cmp_w = InspGetCompareControlsWidth(footer_d)
            local cmp_x = next_left_x + footer_gap * 2
            if insp_cmp_has_any and cmp_w > 0 and cmp_x + cmp_w <= right_group_x - footer_gap * 2 then
                r.ImGui_SetCursorPos(ctx, cmp_x, footer_cy - footer_d / 2)
                InspDrawCompareControls(cmp_w, footer_d)
            end

            local has_flow_routes = insp_track and r.ValidatePtr(insp_track, "MediaTrack*")

            footer_mode_button("##vhsettings", "Settings", settings_open, true, "Settings",
                function() settings_open = not settings_open end,
                settings_cx, footer_cy, DrawFooterSettingsIcon)
            footer_mode_button("##two_col_footer", "Columns", opt_two_column_mode, true, "Two Column Mode",
                function()
                    opt_two_column_mode = not opt_two_column_mode
                    SavePref("two_column_mode", opt_two_column_mode)
                end,
                columns_cx, footer_cy, DrawFooterColumnsIcon)
            footer_mode_button("##flow_footer", "F", flow_view_active, has_flow_routes or flow_view_active, "Flow View",
                function() FlowViewToggle() end,
                flow_cx, footer_cy)
            footer_mode_button("##sends_footer", "S", opt_show_sends, true, "Show Sends",
                function()
                    opt_show_sends = not opt_show_sends
                    SavePref("show_sends", opt_show_sends)
                end,
                sends_cx, footer_cy)

            r.ImGui_SetCursorPosY(ctx, footer_y + ReflexFooterTotalHeight(footer_d))
            PopFont(footer_fp)
            ReflexSetBodyScaleCompensation(saved_scale_comp)
        end

        -- ── SETTINGS PANEL (free-floating window) ──
        -- Pops halfway over the right edge of the main window (or left if no room).
        -- Vertically centered on the main window. Draggable with docking defeated.
        -- Closes on gear click, X button, or Esc. Clicking inside stays open.
        if settings_open then
            -- Settings window renders at fixed 100% scale regardless of user's ui_scale.
            -- All S() calls, font step lookups, and positioning inside this block use 1.0.
            -- Reflex Size +/- buttons read/write real_ui_scale (the global) directly.
            local real_ui_scale = ui_scale
            local saved_scale_comp = ReflexSetBodyScaleCompensation(false)
            ui_scale = 1.0

            -- Push a scale-1.0 bold font immediately so ALL text inside the settings block
            -- (including custom header, ImGui built-in widgets like Selectable, CollapsingHeader,
            -- Separator heights, etc.) computes line-height against 100% font. This overrides
            -- the outer-frame scaled font push that's still active from the main loop.
            local settings_outer_font = GetSteppedFont(0, "bold") or GetScaledFont()
            if settings_outer_font then r.ImGui_PushFont(ctx, settings_outer_font) end

            local sp_pad = S(UI.card_pad)
            local th = r.ImGui_GetTextLineHeight(ctx)
            local hbar_h = S(UI.btn_h + 12)
            local sp_w_fixed = S(320)
            local sp_h_estimate = S(680)   -- used only for initial centering calculation
            local border_w = S(1.25)       -- ~2px retina
            local cr = S(UI.card_r)

            -- On first open (this session), compute placement.
            -- Prefer saved position from prefs if it's still on-screen; else half-over-edge default.
            if not settings_win_pos_set then
                local margin = S(10)
                local screen_left, screen_top = 0, 0
                local screen_w, screen_h = 1920, 1080
                if r.ImGui_GetMainViewport then
                    local vp = r.ImGui_GetMainViewport(ctx)
                    if vp and r.ImGui_Viewport_GetWorkPos and r.ImGui_Viewport_GetWorkSize then
                        screen_left, screen_top = r.ImGui_Viewport_GetWorkPos(vp)
                        screen_w, screen_h = r.ImGui_Viewport_GetWorkSize(vp)
                    end
                end
                -- Validate saved position: must lie within screen bounds with reasonable margin.
                local have_saved = (type(settings_win_x) == "number")
                              and (type(settings_win_y) == "number")
                if have_saved
                   and settings_win_x >= screen_left - sp_w_fixed / 2
                   and settings_win_x + sp_w_fixed <= screen_left + screen_w + sp_w_fixed / 2
                   and settings_win_y >= screen_top - margin
                   and settings_win_y <= screen_top + screen_h - margin then
                    -- Use saved position as-is
                else
                    -- Default: half-over-edge, vertically centered on main window
                    local right_x = wx + ww - Round(sp_w_fixed / 2)
                    local left_x  = wx - Round(sp_w_fixed / 2)
                    if right_x + sp_w_fixed <= screen_left + screen_w then
                        settings_win_x = right_x
                    elseif left_x >= screen_left then
                        settings_win_x = left_x
                    else
                        settings_win_x = wx + Round((ww - sp_w_fixed) / 2)
                    end
                    settings_win_y = wy + Round((wh - sp_h_estimate) / 2)
                    if settings_win_y < screen_top + margin then settings_win_y = screen_top + margin end
                    if settings_win_y + sp_h_estimate > screen_top + screen_h - margin then
                        settings_win_y = math.max(screen_top + margin, screen_top + screen_h - sp_h_estimate - margin)
                    end
                end
                r.ImGui_SetNextWindowPos(ctx, settings_win_x, settings_win_y)
                settings_win_pos_set = true
            end
            -- Width locked; height auto-fits to content.
            r.ImGui_SetNextWindowSizeConstraints(ctx, sp_w_fixed, 0, sp_w_fixed, 99999)

            -- Window style: grey border, no title bar (we draw our own header), no resize, no docking.
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), border_w)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), cr)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), C.border)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), C.bg)

            local flags = r.ImGui_WindowFlags_NoTitleBar()
                        | r.ImGui_WindowFlags_NoCollapse()
                        | r.ImGui_WindowFlags_NoResize()
                        | r.ImGui_WindowFlags_NoScrollbar()
                        | r.ImGui_WindowFlags_NoDocking()
                        | r.ImGui_WindowFlags_AlwaysAutoResize()
            local visible, still_open = r.ImGui_Begin(ctx, "Reflex Settings###nav_settings", true, flags)

            if visible then
                -- Push regular (non-bold) font for the whole settings window body
                local reg_font = GetScaledRegularFont and GetScaledRegularFont()
                if reg_font then r.ImGui_PushFont(ctx, reg_font) end

                local sp_sx_scr, sp_top = r.ImGui_GetWindowPos(ctx)
                local sp_w_actual, sp_h_actual = r.ImGui_GetWindowSize(ctx)
                local sp_right = sp_sx_scr + sp_w_actual
                local sp_bot = sp_top + sp_h_actual
                local sp_dl = r.ImGui_GetWindowDrawList(ctx)

                -- Persist window position if user dragged it.
                if sp_sx_scr ~= settings_win_x or sp_top ~= settings_win_y then
                    settings_win_x = sp_sx_scr
                    settings_win_y = sp_top
                    SavePref("settings_win_x", sp_sx_scr)
                    SavePref("settings_win_y", sp_top)
                end

                -- Header bar: rounded top corners only, muted bg, 1px separator below.
                local hbar_top = sp_top
                local hbar_bot = hbar_top + hbar_h
                local header_bg = 0x20252CFF
                r.ImGui_DrawList_AddRectFilled(sp_dl, sp_sx_scr, hbar_top, sp_right, hbar_bot,
                    header_bg, cr, r.ImGui_DrawFlags_RoundCornersTop())
                r.ImGui_DrawList_AddLine(sp_dl, sp_sx_scr, hbar_bot - 1, sp_right, hbar_bot - 1,
                    C.border, S(1))
                -- Title text — bold, larger
                local title_font = GetSteppedFont(2)   -- bold variant, 2 steps up
                if title_font then r.ImGui_PushFont(ctx, title_font) end
                local title_text = "Reflex v" .. REFLEX_VERSION
                local title_tw, title_th = r.ImGui_CalcTextSize(ctx, title_text)
                r.ImGui_DrawList_AddText(sp_dl, sp_sx_scr + sp_pad,
                    hbar_top + Round((hbar_h - title_th) / 2), C.text, title_text)
                if title_font then r.ImGui_PopFont(ctx) end
                -- Close button (top-right)
                local close_sz = hbar_h
                local close_x = sp_right - close_sz
                local mx, my = r.ImGui_GetMousePos(ctx)
                local close_hov = (mx >= close_x and mx < close_x + close_sz
                               and my >= hbar_top and my < hbar_bot)
                if close_hov then
                    r.ImGui_DrawList_AddRectFilled(sp_dl, close_x, hbar_top, close_x + close_sz, hbar_bot,
                        C.fx_ctrl_hover, cr, r.ImGui_DrawFlags_RoundCornersTopRight())
                end
                local x_sz = S(4)
                local x_cx = close_x + Round(close_sz / 2)
                local x_cy = hbar_top + Round(hbar_h / 2)
                local x_col = close_hov and C.text or C.text_dim
                r.ImGui_DrawList_AddLine(sp_dl, x_cx - x_sz, x_cy - x_sz,
                    x_cx + x_sz, x_cy + x_sz, x_col, S(1.5))
                r.ImGui_DrawList_AddLine(sp_dl, x_cx + x_sz, x_cy - x_sz,
                    x_cx - x_sz, x_cy + x_sz, x_col, S(1.5))
                if close_hov and r.ImGui_IsMouseClicked(ctx, 0) then settings_open = false end

                -- Position cursor for content (below header, padded)
                r.ImGui_SetCursorScreenPos(ctx, sp_sx_scr + sp_pad, hbar_bot + S(UI.pad))

                -- Style push: no hover highlighting on rows
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x00000000)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x00000000)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x00000000)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text_dim)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(), C.text_muted)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), (C.border & 0xFFFFFF00) | 0x60)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C.fx_ctrl_bg)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C.fx_ctrl_hover)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C.fx_ctrl_active)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarBg(), 0x00000000)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrab(), 0x5A5A5EFF)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrabHovered(), 0x6E6E74FF)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrabActive(), 0x7E7E84FF)
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 0, S(10))

                -- Content wrapped in a group so the auto-resize window sizes to it.
                -- Width manually constrained to keep interior padding.
                r.ImGui_BeginGroup(ctx)
                local inner_w = sp_w_actual - sp_pad * 2

            -- Page selector (tracks / songs)
            local has_songs = opt_live_mode and songs_entry_ref ~= nil
            if has_songs then
                local tr_sel = current_page == "tracks"
                if SettingsRow("Tracks", { color = tr_sel and C.green or C.text_dim,
                                           dot = tr_sel and "\xE2\x97\x8F" or "\xE2\x97\x8B" }) then
                    current_page = "tracks"
                end
                local sn_sel = current_page == "songs"
                if SettingsRow("Songs", { color = sn_sel and C.green or C.text_dim,
                                          dot = sn_sel and "\xE2\x97\x8F" or "\xE2\x97\x8B" }) then
                    current_page = "songs"; if needs_song_rescan then ScanSongs() end
                end
                r.ImGui_Separator(ctx)
            end

            if SettingsRow("I/O Manager") then
                RecordInputOpenManager(nil, nil)
                settings_open = false
            end
            r.ImGui_Separator(ctx)

            -- Page content
            if current_page == "tracks" then
                if SettingsRow("Show All") then ShowAllTracks() end
                if SettingsRow("Hide All") then HideAllTLFs() end
                if SettingsRow("Expand All") then ExpandAllTracks() end
                if SettingsRow("Rescan") then needs_rescan = true; needs_song_rescan = true end
                settings_routing_depth_open = SettingsCollapsingRow("Routing Depth", settings_routing_depth_open)
                if settings_routing_depth_open then
                    for rd = 1, 3 do
                        local sel = routing_view_depth == rd
                        local lbl = rd .. (rd == 1 and " hop" or " hops")
                        if SettingsRow(lbl, {
                            color = sel and C.green or C.text_dim,
                            dot = sel and "\xE2\x97\x8F" or "\xE2\x97\x8B",
                            indent = S(UI.pad),
                        }) then
                            routing_view_depth = rd; SavePref("routing_depth", rd)
                            if routing_view_active then RoutingViewApply() end
                        end
                    end
                end
                r.ImGui_Separator(ctx)
                local ne = MenuCheckbox("Expand Children", opt_expand_children)
                if ne ~= opt_expand_children then opt_expand_children = ne; SavePref("expand_children", ne) end
                if has_songs then
                    local nv = MenuCheckbox("View Lock", opt_viewlock)
                    if nv ~= opt_viewlock then opt_viewlock = nv; SavePref("view_lock", nv) end
                end
                if archive_entry and opt_nav_ignore_archive then
                    local avis = IsFolderVisible(archive_entry)
                    local nav = MenuCheckbox("Show Archive", avis)
                    if nav ~= avis then
                        r.Undo_BeginBlock(); r.PreventUIRefresh(1)
                        SetFolderVisible(archive_entry, nav, { allow_ignored = true }); if nav then SetFolderCollapsed(archive_entry, true) end
                        r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
                        r.Undo_EndBlock("Reflex: Toggle Archive", 0)
                    end
                end
            else
                if SettingsRow("Hide All Songs") then HideAllSongs() end
                if SettingsRow("Expand All Songs") then ExpandAllSongs() end
                if SettingsRow("Rescan") then needs_rescan = true; needs_song_rescan = true end
                r.ImGui_Separator(ctx)
                local ns = MenuCheckbox("Expand Children", opt_songs_expand)
                if ns ~= opt_songs_expand then opt_songs_expand = ns; SavePref("songs_expand_children", ns) end
            end
            r.ImGui_Separator(ctx)
            local nn = MenuCheckbox("Show Nav", nav_visible)
            if nn ~= nav_visible then nav_visible = nn; SavePref("nav_visible", nn) end
            local nm = MenuCheckbox("Mirror Nav (right-side dock)", nav_mirror)
            if nm ~= nav_mirror then nav_mirror = nm; SavePref("nav_mirror", nm) end
            local ni = MenuCheckbox("Show Inspector", insp_visible)
            if ni ~= insp_visible then insp_visible = ni; SavePref("insp_visible", ni) end
            local nmt = MenuCheckbox("Show Master Track", opt_show_master_track)
            if nmt ~= opt_show_master_track then opt_show_master_track = nmt; SavePref("show_master_track", nmt) end
            if SettingsRow("Set Selected Track as Master") then
                local selected = ExternalFxCaptureSelection()
                local sel_track = selected and selected[1] or nil
                if sel_track and r.ValidatePtr(sel_track, "MediaTrack*") then
                    local real_master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
                    if real_master and sel_track == real_master then
                        master_track_guid = ""
                    else
                        master_track_guid = r.GetTrackGUID(sel_track) or ""
                    end
                    SavePref("master_track_guid", master_track_guid)
                    opt_show_master_track = true
                    SavePref("show_master_track", true)
                end
            end
            if master_track_guid and master_track_guid ~= "" then
                if SettingsRow("Use Reaper Master Track") then
                    master_track_guid = ""
                    SavePref("master_track_guid", "")
                end
            end
            local n2c = MenuCheckbox("Two Column Mode", opt_two_column_mode)
            if n2c ~= opt_two_column_mode then opt_two_column_mode = n2c; SavePref("two_column_mode", n2c) end
            local n2n = MenuCheckbox("Two Column Nav", opt_two_column_nav)
            if n2n ~= opt_two_column_nav then opt_two_column_nav = n2n; SavePref("two_column_nav", n2n) end
            local ntt = MenuCheckbox("Show Tooltips", opt_tooltips)
            if ntt ~= opt_tooltips then opt_tooltips = ntt; SavePref("tooltips", ntt) end
            local nif = MenuCheckbox("Insert Instruments First", opt_instr_first)
            if nif ~= opt_instr_first then opt_instr_first = nif; SavePref("instr_first", nif) end
            settings_fx_browser_open = SettingsCollapsingRow("FX Browser", settings_fx_browser_open)
            if settings_fx_browser_open then
                SettingsDrawFXBrowserProvider()
            end
            local nff = MenuCheckbox("Float Plugin UIs", opt_fx_float)
            if nff ~= opt_fx_float then opt_fx_float = nff; SavePref("fx_float", nff) end
            local nvtc = MenuCheckbox("Volume Follows Track Color", opt_vol_track_color)
            if nvtc ~= opt_vol_track_color then opt_vol_track_color = nvtc; SavePref("vol_track_color", nvtc) end
            local ncs = MenuCheckbox("Conform New Sends", opt_conform_sends)
            if ncs ~= opt_conform_sends then opt_conform_sends = ncs; SavePref("conform_sends", ncs) end
            if opt_show_sends then
                settings_send_cols_open = SettingsCollapsingRow("Send Columns", settings_send_cols_open)
                if settings_send_cols_open then
                    for nc = 1, 6 do
                        local sel = nc == sends_view_cols
                        if SettingsRow(tostring(nc), {
                            color = sel and C.green or C.text_dim,
                            dot = sel and "\xE2\x97\x8F" or "\xE2\x97\x8B",
                            indent = S(UI.pad),
                        }) then
                            sends_view_cols = nc; SavePref("sends_view_cols", nc)
                        end
                    end
                end
            end
            r.ImGui_Separator(ctx)
            settings_noisy_open = SettingsCollapsingRow("Noisy Tracks", settings_noisy_open)
            if settings_noisy_open then
                local now = r.time_precise()
                if now - noise_scan_time > 0.5 then
                    noise_scan_results = NoiseScanAllTracks()
                    noise_scan_time = now
                end
                if #noise_scan_results == 0 then
                    r.ImGui_TextDisabled(ctx, "No sub-threshold noise detected")
                else
                    r.ImGui_TextDisabled(ctx, string.format("%d track%s with noise floor signal:",
                        #noise_scan_results, #noise_scan_results > 1 and "s" or ""))
                    r.ImGui_Separator(ctx)
                    for _, entry in ipairs(noise_scan_results) do
                        local label = string.format("%s  (%.0f dB)", entry.name, entry.peak_db)
                        if SettingsRow(label, { indent = S(UI.pad) }) then
                            if r.ValidatePtr(entry.track, "MediaTrack*") then
                                r.Undo_BeginBlock()
                                r.SetOnlyTrackSelected(entry.track)
                                r.Main_OnCommand(40913, 0)
                                r.Undo_EndBlock("Reflex: Show track", 0)
                            end
                        end
                    end
                end
            end
            r.ImGui_Separator(ctx)
            if SettingsRow("Refresh FX list") then
                fx_browser_cache = nil
            end
            local nr = MenuCheckbox("Show Remote", remote_visible)
            if nr ~= remote_visible then remote_visible = nr; SavePref("remote_visible", nr) end
            if remote_visible and not remote_popped_out then
                if SettingsRow("Pop Out Remote") then
                    remote_popped_out = true; SavePref("remote_popped_out", true)
                    remote_pop_initialized = false
                end
            end
            r.ImGui_Separator(ctx)
            local scale_row_h = S(UI.btn_h)
            local scale_btn_sz = scale_row_h
            -- Display actual user scale (ui_scale is locked to 1.0 during settings render)
            local scale_label = string.format("%d%%", math.floor(real_ui_scale * 100 + 0.5))
            local scale_tw = r.ImGui_CalcTextSize(ctx, scale_label)
            local scale_text_w = scale_tw + S(12)
            local scale_scx, scale_scy = r.ImGui_GetCursorScreenPos(ctx)
            local scale_sdl = r.ImGui_GetWindowDrawList(ctx)
            -- "Reflex Size" label (bold — temporarily pop the regular font)
            if reg_font then r.ImGui_PopFont(ctx) end
            local uisize_lbl = "Reflex Size"
            local uisize_tw, uisize_th = r.ImGui_CalcTextSize(ctx, uisize_lbl)
            r.ImGui_DrawList_AddText(scale_sdl, scale_scx, scale_scy + Round((scale_row_h - uisize_th) / 2), C.text, uisize_lbl)
            local scale_lbl_w = uisize_tw
            if reg_font then r.ImGui_PushFont(ctx, reg_font) end
            local scale_x = scale_scx + scale_lbl_w + S(UI.pad)
            -- - button
            r.ImGui_SetCursorScreenPos(ctx, scale_x, scale_scy)
            local _, minus_clk = NavSquare("##sc_minus", scale_btn_sz, scale_btn_sz, "-", {
                bg = C.fx_ctrl_bg, hov = C.fx_ctrl_hover, active = C.fx_ctrl_active, fg = C.text_dim, fg_hov = C.text,
            })
            if minus_clk then
                real_ui_scale = math.max(0.5, math.floor((real_ui_scale - 0.10) * 100 + 0.5) / 100)
                SavePref("ui_scale_v2", real_ui_scale)
            end
            -- Percentage display
            scale_x = scale_x + scale_btn_sz + S(2)
            r.ImGui_SetCursorScreenPos(ctx, scale_x, scale_scy)
            local _, _ = NavRect("##sc_val", scale_text_w, scale_row_h, nil, { bg = C.fx_ctrl_bg, hov = C.fx_ctrl_bg, no_press = true })
            local val_sx, val_sy = r.ImGui_GetItemRectMin(ctx)
            local val_tw = r.ImGui_CalcTextSize(ctx, scale_label)
            r.ImGui_DrawList_AddText(scale_sdl, val_sx + Round((scale_text_w - val_tw) / 2), val_sy + Round((scale_row_h - th) / 2), C.text, scale_label)
            -- + button
            scale_x = scale_x + scale_text_w + S(2)
            r.ImGui_SetCursorScreenPos(ctx, scale_x, scale_scy)
            local _, plus_clk = NavSquare("##sc_plus", scale_btn_sz, scale_btn_sz, "+", {
                bg = C.fx_ctrl_bg, hov = C.fx_ctrl_hover, active = C.fx_ctrl_active, fg = C.text_dim, fg_hov = C.text,
            })
            if plus_clk then
                real_ui_scale = math.min(2.5, math.floor((real_ui_scale + 0.10) * 100 + 0.5) / 100)
                SavePref("ui_scale_v2", real_ui_scale)
            end
            r.ImGui_SetCursorScreenPos(ctx, scale_scx, scale_scy + scale_row_h)

            settings_panel_h = r.ImGui_GetCursorPosY(ctx)
            r.ImGui_EndGroup(ctx)
            -- Bottom padding so content isn't flush with window bottom edge
            r.ImGui_Dummy(ctx, 1, S(UI.card_pad))

            r.ImGui_PopStyleVar(ctx, 1)   -- ItemSpacing
            r.ImGui_PopStyleColor(ctx, 14)

                -- Esc closes; clicking outside does NOT close (user must explicitly dismiss via X or gear).
                if TrackNavigatorEscapePressed() then settings_open = false end

                if reg_font then r.ImGui_PopFont(ctx) end
            end -- visible
            r.ImGui_End(ctx)

            r.ImGui_PopStyleColor(ctx, 2)
            r.ImGui_PopStyleVar(ctx, 3)

            if not still_open then settings_open = false end

            if settings_outer_font then r.ImGui_PopFont(ctx) end

            -- Restore real ui_scale (was locked to 1.0 for settings render)
            ui_scale = real_ui_scale
            ReflexSetBodyScaleCompensation(saved_scale_comp)
        end

        -- ── DIVIDER + REMOTE (fixed bottom panel) ──
        if remote_inline then
            -- Draggable divider (narrow pill, wide hit area)
            local div_cx, div_cy = r.ImGui_GetCursorScreenPos(ctx)
            local div_bw = r.ImGui_GetContentRegionAvail(ctx) - sb_inset
            local dl = r.ImGui_GetWindowDrawList(ctx)
            local bar_w = math.floor(div_bw / 3)
            local bar_inset = Round((div_bw - bar_w) / 2)
            local bar_h = S(6)
            local bar_y = div_cy + Round((divider_h - bar_h) / 2)
            r.ImGui_InvisibleButton(ctx, "##divider", div_bw, divider_h + S(10))
            if r.ImGui_IsItemHovered(ctx) or r.ImGui_IsItemActive(ctx) then
                r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNS())
                r.ImGui_DrawList_AddRectFilled(dl, div_cx + bar_inset, bar_y,
                    div_cx + bar_inset + bar_w, bar_y + bar_h, C.text_muted, bar_h / 2)
            end
            if r.ImGui_IsItemActive(ctx) then
                local _, dy = r.ImGui_GetMouseDelta(ctx)
                if dy ~= 0 then
                    remote_height = math.max(S(60), remote_height - dy)
                    SavePref("remote_height", math.floor(remote_height))
                end
                remote_dragging = true
            elseif remote_dragging then
                remote_dragging = false
            end
            r.ImGui_Spacing(ctx)

            -- Remote child window (scrollbar stabilized to prevent flicker)
            local remote_flags = 0
            if remote_last_content_h > 0 and rem_h > 0 and remote_last_content_h > rem_h - S(10) then
                remote_flags = r.ImGui_WindowFlags_AlwaysVerticalScrollbar()
            end
            local remote_open = r.ImGui_BeginChild(ctx, "##remote", r.ImGui_GetContentRegionAvail(ctx) - sb_inset, rem_h, 0, remote_flags)
            if remote_open then
                local rbw = r.ImGui_GetContentRegionAvail(ctx)
                RemoteDrawSection(rbw)
                remote_last_content_h = r.ImGui_GetCursorPosY(ctx)

                -- Remote right-click menu (blank space in remote panel only)
                if r.ImGui_IsMouseClicked(ctx, 1) and not r.ImGui_IsAnyItemHovered(ctx)
                   and r.ImGui_IsWindowHovered(ctx, r.ImGui_HoveredFlags_ChildWindows()) then
                    remote_ctx_idx = nil
                    r.ImGui_OpenPopup(ctx, "##rmt_ctx")
                end

                r.ImGui_EndChild(ctx)
            end
        else
            -- The footer reserves bottom space with SetCursorPosY(); when there
            -- is no inline Remote item afterward, submit a tiny item so ReaImGui
            -- records the extended main-window boundary before End().
            r.ImGui_Dummy(ctx, 1, 1)
        end

        PopFont(fp)
        r.ImGui_PopStyleColor(ctx, 1)  -- pop restored text color

        -- Resolve any active FX drag: hit-test registered targets, draw insert
        -- indicator, handle release. Must be inside main window's Begin/End so
        -- foreground draw list is available.
        FxDragResolveDrop()

        -- v20.424: Click on script bg (with no other ImGui item involved) to
        -- Click on script bg = exit FX selection (Esc-equivalent for selection).
        -- v20.435: clipboard carry mode is NOT cleared by bg click. Carry mode
        -- only exits via Esc, the chip × button, paste completion, or a new
        -- copy/cut. Previous behavior (bg click clears clipboard) actively
        -- fought the focus-grab UX: when Reflex is unfocused in carry
        -- mode, the user must click to refocus, and clicking bg would drop
        -- their carry. Now bg click is a pure deselect gesture and is also
        -- a safe focus-grab path (combined with the eat_click suppression
        -- below for any in-flight selection clear during a focus-grab click).
        --
        -- Pin is intentionally untouched (different category: persistent
        -- view setting, not transient operation state).
        --
        -- Guards against errant clicks:
        --   * Tracks press position; only fires if release is within 4px of
        --     press (movement = a drag attempt, leave state alone).
        --   * Requires window-hovered + no item hovered + no popup open at
        --     both press AND release (latter implicit; ImGui consumes hovers
        --     when popups are open).
        --   * Press must originate on script bg, not just release there
        --     (prevents drag-from-card-into-bg from clearing).
        --   * Release-time eat_click check: focus-grab clicks suppress all
        --     side effects, so a bg click that grabs focus from REAPER does
        --     nothing else. Once focused, subsequent bg clicks deselect.
        if r.ImGui_IsMouseClicked(ctx, 0) then
            local item_hov = r.ImGui_IsAnyItemHovered(ctx)
            local win_hov = r.ImGui_IsWindowHovered(ctx, r.ImGui_HoveredFlags_RootAndChildWindows())
            local popup_open = r.ImGui_IsPopupOpen(ctx, "",
                r.ImGui_PopupFlags_AnyPopupId() | r.ImGui_PopupFlags_AnyPopupLevel())
            if win_hov and not item_hov and not popup_open then
                local mx, my = r.ImGui_GetMousePos(ctx)
                nav_bg_click_press = { x = mx, y = my }
            else
                nav_bg_click_press = nil
            end
        end
        if nav_bg_click_press and r.ImGui_IsMouseReleased(ctx, 0) then
            local item_hov = r.ImGui_IsAnyItemHovered(ctx)
            local popup_open = r.ImGui_IsPopupOpen(ctx, "",
                r.ImGui_PopupFlags_AnyPopupId() | r.ImGui_PopupFlags_AnyPopupLevel())
            local mx, my = r.ImGui_GetMousePos(ctx)
            local dx = mx - nav_bg_click_press.x
            local dy = my - nav_bg_click_press.y
            local moved = (dx * dx + dy * dy) > (S(4) * S(4))
            if not item_hov and not popup_open and not moved
               and not nav_focus_grab_eat_click then
                if InspFxSelCount() > 0 then InspFxSelClear() end
            end
            nav_bg_click_press = nil
        end

        -- Clipboard-mode hover visuals + deferred paste execution (v20.407).
        -- Runs after drag resolve so fx_drop_targets has this frame's rects
        -- and drag visuals take precedence when both states overlap.
        FxClipResolveHover()

        if not reflex_window_docked then
            local outline_dl = r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(ctx) or r.ImGui_GetWindowDrawList(ctx)
            DrawTrackNavigatorWindowOutline(outline_dl, wx, wy, ww, wh, S(10), C.window_outline)
        end

        r.ImGui_End(ctx)
    end

    PopPopupStyle()
    r.ImGui_PopStyleVar(ctx, 7 + smooth_tess_count)
    r.ImGui_PopStyleColor(ctx, 5 + dock_color_count)

    -- ── FX BROWSER (own window, always available regardless of remote visibility) ──
    FxBrowserRender()
    RecordIODrawManager()

    -- ── POP-OUT REMOTE WINDOW ──
    if remote_visible and remote_popped_out then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), C.bg)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), C.border)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), C.bg)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), C.bg)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), S(12), S(10))
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), S(BASE_PAD_X), S(BASE_PAD_Y))
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), S(BASE_SPACING), S(BASE_SPACING))
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 4)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 0)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ButtonTextAlign(), 0, 0.5)
        local remote_smooth_tess_count = 0
        if r.ImGui_StyleVar_CircleTessellationMaxError then
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CircleTessellationMaxError(), 0.03)
            remote_smooth_tess_count = 1
        end
        PushPopupStyle()

        if not remote_pop_initialized then
            r.ImGui_SetNextWindowSize(ctx, remote_pop_w, remote_pop_h)
            remote_pop_initialized = true
        end

        local rflags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
        local rvis, ropen = r.ImGui_Begin(ctx, "Remote", true, rflags)
        if rvis then
            local rfp = PushFont(GetScaledFont())
            local rbw = r.ImGui_GetContentRegionAvail(ctx)
            RemoteDrawSection(rbw)

            -- Right-click blank space
            if r.ImGui_IsMouseClicked(ctx, 1) and not r.ImGui_IsAnyItemHovered(ctx)
               and r.ImGui_IsWindowHovered(ctx, r.ImGui_HoveredFlags_ChildWindows()) then
                remote_ctx_idx = nil
                r.ImGui_OpenPopup(ctx, "##rmt_ctx")
            end

            -- Save size on resize
            local pw, ph = r.ImGui_GetWindowSize(ctx)
            if pw ~= remote_pop_w or ph ~= remote_pop_h then
                remote_pop_w = pw; remote_pop_h = ph
                SavePref("remote_pop_w", math.floor(pw))
                SavePref("remote_pop_h", math.floor(ph))
            end

            PopFont(rfp)
            r.ImGui_End(ctx)
        end
        if not ropen then
            remote_popped_out = false; SavePref("remote_popped_out", false)
        end

        PopPopupStyle()
        r.ImGui_PopStyleVar(ctx, 6 + remote_smooth_tess_count)
        r.ImGui_PopStyleColor(ctx, 5)
    end

    -- ── View Lock ──
    if opt_live_mode and opt_viewlock then
        local song = GetRealistCurrentSong()
        if song and song ~= viewlock_song then
            local s, e = FindSongRegionBounds(song)
            if s and e then
                viewlock_song = song; viewlock_start = math.max(0, s - 120); viewlock_end = e
                vl_stable = 0; vl_ps = 0; vl_pe = 0
            end
        end
        if viewlock_start < viewlock_end then ClampViewToRegion(viewlock_start, viewlock_end) end
    else viewlock_song = ""; viewlock_start = 0; viewlock_end = 0; vl_stable = 0; vl_ps = 0; vl_pe = 0 end

    -- ── Songs follow ──
    if opt_live_mode and songs_follow_active and songs_entry_ref and current_page == "tracks" then
        local current = GetRealistCurrentSong()
        if current and current ~= songs_follow_last then
            songs_sub.song_name = "" -- force rescan of song sections
            ScanSongSections(); BuildRenderList()
            r.PreventUIRefresh(1)
            if songs_section_mode then
                ShowSongSectionsSelected(opt_expand_children)
            else
                ShowSongsForCurrentSong(songs_entry_ref, opt_expand_children)
            end
            r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
        end
    end

    ReflexApplyKeyboardPassthrough({ capture_keyboard = reflex_keyboard_capture_requested })

    if open then r.defer(Loop) end
end

ScanTopFolders(); ScanSubGroups(); BuildRenderList(); Loop()
