-- @noindex
--[[
 * Description: Track Navigator.
 *              Standalone NAV visibility manager for REAPER.
 * Author:      S.Hansen / Tycho
 * Version:     1.0
--]]

local r = reaper
TRACK_NAVIGATOR_VERSION = "1.0"

TrackNavigatorDependencyError = function(detail)
    local msg = "Track Navigator requires ReaImGui 0.7 or newer."
    if detail and detail ~= "" then msg = msg .. "\n\n" .. tostring(detail) end
    if r.ReaPack_BrowsePackages then
        local choice = r.MB(msg .. "\n\nOpen ReaPack package browser for ReaImGui?", "Track Navigator: Missing dependency", 4)
        if choice == 6 then r.ReaPack_BrowsePackages("ReaImGui") end
    else
        r.MB(msg .. "\n\nInstall ReaImGui via ReaPack, then run Track Navigator again.", "Track Navigator: Missing dependency", 0)
    end
end

local imgui_api = r.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua'
local imgui_loader, imgui_load_err = loadfile(imgui_api)
if not imgui_loader then
    TrackNavigatorDependencyError(imgui_load_err)
    return
end

local imgui_ok, imgui_err = pcall(function() imgui_loader('0.7') end)
if not imgui_ok or not r.ImGui_CreateContext then
    TrackNavigatorDependencyError(imgui_err)
    return
end

local ctx = r.ImGui_CreateContext("Track Navigator")

local script_dir = debug.getinfo(1, 'S').source:match('@?(.*[/\\])') or ''
package.path = script_dir .. 'core/?.lua;' .. script_dir .. '?.lua;' .. package.path

local nt_ok, nav_theme = pcall(dofile, script_dir .. 'Track Navigator_Theme.lua')
if not nt_ok or type(nav_theme) ~= "table" then
    nt_ok, nav_theme = pcall(dofile, script_dir .. 'Track Navigator_Theme_Default.lua')
end
if not nt_ok or type(nav_theme) ~= "table" then nav_theme = {} end

local C

rgb = function(hex) return (hex << 8) | 0xFF end
ntc = function(section, key, fallback)
    local s = nav_theme[section]
    if s and s[key] then return rgb(s[key]) end
    return fallback
end

TrackNavigatorKeyValue = function(name)
    local v = r[name]
    if type(v) == "function" then
        local ok, key = pcall(v)
        if ok and type(key) == "number" then return key end
    elseif type(v) == "number" then
        return v
    end
    return nil
end

TrackNavigatorIsMacOS = function()
    local os = r.GetOS and r.GetOS() or ""
    return os:find("OSX", 1, true) ~= nil
        or os:find("macOS", 1, true) ~= nil
        or os:find("Mac", 1, true) ~= nil
end

TrackNavigatorModFlag = function(mods, fallback, ...)
    mods = tonumber(mods) or 0
    if fallback and (mods & fallback) ~= 0 then return true end
    for i = 1, select("#", ...) do
        local key = TrackNavigatorKeyValue(select(i, ...))
        if key and (mods & key) ~= 0 then return true end
    end
    return false
end

TrackNavigatorKeyDown = function(...)
    if not r.ImGui_IsKeyDown then return false end
    for i = 1, select("#", ...) do
        local key = TrackNavigatorKeyValue(select(i, ...))
        if key then
            local ok_down, down = pcall(r.ImGui_IsKeyDown, ctx, key)
            if ok_down and down == true then return true end
        end
    end
    return false
end

IsCmd = function(mods)
    return TrackNavigatorModFlag(mods, 0x8, "ImGui_Mod_Super", "ImGui_Mod_Shortcut", "ImGui_KeyModFlags_Super")
        or TrackNavigatorKeyDown("ImGui_Key_ModSuper", "ImGui_Key_LeftSuper", "ImGui_Key_RightSuper")
end
IsShift = function(mods)
    return TrackNavigatorModFlag(mods, 0x2, "ImGui_Mod_Shift", "ImGui_KeyModFlags_Shift")
        or TrackNavigatorKeyDown("ImGui_Key_ModShift", "ImGui_Key_LeftShift", "ImGui_Key_RightShift")
end
IsAlt = function(mods)
    return TrackNavigatorModFlag(mods, 0x4, "ImGui_Mod_Alt", "ImGui_KeyModFlags_Alt")
        or TrackNavigatorKeyDown("ImGui_Key_ModAlt", "ImGui_Key_LeftAlt", "ImGui_Key_RightAlt")
end
IsCtrl = function(mods)
    return TrackNavigatorModFlag(mods, 0x1, "ImGui_Mod_Ctrl", "ImGui_KeyModFlags_Ctrl")
        or TrackNavigatorKeyDown("ImGui_Key_ModCtrl", "ImGui_Key_LeftCtrl", "ImGui_Key_RightCtrl")
end

TrackNavigatorMacPrimaryAlias = function(mods)
    return TrackNavigatorIsMacOS()
        and TrackNavigatorModFlag(mods, 0x1000, "ImGui_Key_ModCtrl")
end

TrackNavigatorModState = function(mods)
    mods = tonumber(mods) or 0
    local ctrl = IsCtrl(mods)
    -- Standalone macOS Cmd-click can report as raw Ctrl (0x1000).
    local cmd_alias = TrackNavigatorMacPrimaryAlias(mods)
    local cmd = IsCmd(mods) or cmd_alias
    return {
        raw = mods,
        cmd = cmd,
        shift = IsShift(mods),
        alt = IsAlt(mods),
        ctrl = ctrl and not cmd_alias,
    }
end

local PREF = "reflex"

LoadPref = function(key, default)
    local v = r.GetExtState(PREF, key)
    if v == "" then return default end
    if type(default) == "boolean" then return v == "1" end
    return tonumber(v) or default
end

SavePref = function(key, val)
    r.SetExtState(PREF, key, type(val) == "boolean" and (val and "1" or "0") or tostring(val), true)
end

opt_expand_children = LoadPref("expand_children", false)
opt_songs_expand = LoadPref("songs_expand_children", false)
opt_tooltips = LoadPref("tooltips", true)
opt_viewlock = LoadPref("view_lock", false)
opt_live_mode = LoadPref("tycho_live_mode", false)
opt_nav_ignore_archive = LoadPref("nav_ignore_archive", true)
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

local body_size = (nav_theme.fonts and nav_theme.fonts.body_size) or 14
local body_family = (nav_theme.fonts and nav_theme.fonts.family) or 'SF Pro'
local scaled_fonts = {}
local scaled_fonts_italic = {}
local scaled_fonts_regular = {}
local scaled_font_sizes = {}
CreateTrackNavigatorFont = function(family, flags)
    return r.ImGui_CreateFont(family, flags)
end
for step = 5, 20 do
    local scale = step / 10
    local sz = math.floor(body_size * scale + 0.5)
    local f = CreateTrackNavigatorFont(body_family, r.ImGui_FontFlags_Bold())
    r.ImGui_Attach(ctx, f)
    scaled_fonts[step] = f
    if f then scaled_font_sizes[f] = sz end
    local fi = CreateTrackNavigatorFont(body_family, r.ImGui_FontFlags_Italic())
    r.ImGui_Attach(ctx, fi)
    scaled_fonts_italic[step] = fi
    if fi then scaled_font_sizes[fi] = sz end
    local fr = CreateTrackNavigatorFont(body_family, r.ImGui_FontFlags_None())
    r.ImGui_Attach(ctx, fr)
    scaled_fonts_regular[step] = fr
    if fr then scaled_font_sizes[fr] = sz end
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
NAV_CIRCLE_SEGMENTS = 48

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
songs_last_click = nil

navigator_expanded = LoadPref("navigator_expanded", true)
nav_visible = true
nav_mirror = LoadPref("nav_mirror", false)
remote_ctx_tlf_guid = nil
remote_ctx_tlf_track = nil
remote_ctx_tlf_ghost_parent = nil
remote_ctx_tlf_custom = false
last_nav_h = 0
last_nav_natural_h = 0
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
active_view_active = false
active_view_tracks = {}
active_view_peak_times = {}
active_view_signal_available = false
active_view_threshold = 0.001
active_view_window = 3.0
active_view_last_play = 0
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
    mark_dirty = function() needs_rescan = true; needs_song_rescan = true end,
})
LoadNavIncluded()

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
require("Reflex_NavActionCore")({ r = r })

package.loaded["Reflex_ViewModes"] = nil
require("Reflex_ViewModes")({ r = r })

package.loaded["Reflex_NavViewCore"] = nil
require("Reflex_NavViewCore")({
    r = r,
    ctx = ctx,
    colors = C,
    scaled_fonts = scaled_fonts,
    font_sizes = scaled_font_sizes,
    track_color_overrides = track_color_overrides,
    script_dir = script_dir,
    version = TRACK_NAVIGATOR_VERSION,
    menu_context = "standalone",
    mark_dirty = function() needs_rescan = true; needs_song_rescan = true end,
    get_nav_scale = function() return ui_scale end,
    set_nav_scale = function(v) ui_scale = v; SavePref("navigator_scale_v1", v) end,
})

local window_initialized = false
local last_track_count = 0
local last_project_state = 0
local last_rescan_time = 0
local RESCAN_THROTTLE = 0.5

TrackNavigatorLoop = function()
    MaybeReloadPins()
    MaybeReloadNavExcluded()
    MaybeReloadNavIncluded()
    MaybeSyncViewModeProject()
    ActiveViewUpdatePeaks()
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
    elseif nt ~= last_track_count then
        needs_rescan = true
        needs_song_rescan = true
    elseif proj_state ~= last_project_state then
        local now = r.time_precise()
        if now - last_rescan_time >= RESCAN_THROTTLE then
            needs_rescan = true
            needs_song_rescan = true
        end
    end
    last_track_count = nt
    last_project_state = proj_state

    if needs_rescan and nt > 0 then
        ScanTopFolders()
        ScanSubGroups()
        BuildRenderList()
        last_rescan_time = r.time_precise()
    end

    if (not opt_live_mode or not songs_entry_ref) and current_page == "songs" then current_page = "tracks" end

    local main_bg = C.window_bg
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), main_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), C.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), main_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), main_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), main_bg)
    local dock_color_count = 0
    local function pushDockColor(col_fn, color)
        if col_fn then
            r.ImGui_PushStyleColor(ctx, col_fn(), color)
            dock_color_count = dock_color_count + 1
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
    pushDockColor(r.ImGui_Col_NavWindowingHighlight, 0x00000000)
    pushDockColor(r.ImGui_Col_NavWindowingDimBg, 0x00000000)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), S(UI.edge_pad), S(UI.edge_pad))
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), S(BASE_PAD_X), S(BASE_PAD_Y))
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), S(BASE_SPACING), S(BASE_SPACING))
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ButtonTextAlign(), 0, 0.5)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
    local smooth_tess_count = 0
    if r.ImGui_StyleVar_CircleTessellationMaxError then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CircleTessellationMaxError(), 0.1)
        smooth_tess_count = 1
    end
    PushPopupStyle()

    if not window_initialized then
        r.ImGui_SetNextWindowSize(ctx, S(240), S(420))
        window_initialized = true
    end
    r.ImGui_SetNextWindowSizeConstraints(ctx, S(70), S(48), 99999, 99999)

    local wflags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
    if r.ImGui_WindowFlags_NoFocusOnAppearing then
        wflags = wflags | r.ImGui_WindowFlags_NoFocusOnAppearing()
    end
    local visible, open = r.ImGui_Begin(ctx, "Track Navigator", true, wflags)
    if visible then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
        local wx, _wy = r.ImGui_GetWindowPos(ctx)
        local ww, _wh = r.ImGui_GetWindowSize(ctx)
        local fp = PushFont(GetScaledFont())
        local bw, win_h = r.ImGui_GetContentRegionAvail(ctx)
        local sb_inset = -(S(UI.edge_pad) - 3)
        bw = bw - sb_inset
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
        })
        PopFont(fp)
        r.ImGui_PopStyleColor(ctx, 1)
        r.ImGui_End(ctx)
    end

    PopPopupStyle()
    r.ImGui_PopStyleVar(ctx, 7 + smooth_tess_count)
    r.ImGui_PopStyleColor(ctx, 5 + dock_color_count)

    if open then r.defer(TrackNavigatorLoop) end
end

ScanTopFolders()
ScanSubGroups()
BuildRenderList()
TrackNavigatorLoop()
