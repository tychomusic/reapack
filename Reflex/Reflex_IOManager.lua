-- @noindex
--[[
 * Description: Standalone I/O Manager window for Reflex.
 * Author:      S.Hansen / Tycho
 * Version:     20.670
--]]

local r = reaper

ReflexIOManagerDependencyError = function(detail)
    local msg = "Reflex I/O Manager requires ReaImGui 0.10 or newer."
    if detail and detail ~= "" then msg = msg .. "\n\n" .. tostring(detail) end
    if r.ReaPack_BrowsePackages then
        local choice = r.MB(msg .. "\n\nOpen ReaPack package browser for ReaImGui?", "Reflex I/O Manager: Missing dependency", 4)
        if choice == 6 then r.ReaPack_BrowsePackages("ReaImGui") end
    else
        r.MB(msg .. "\n\nInstall ReaImGui via ReaPack, then run Reflex I/O Manager again.", "Reflex I/O Manager: Missing dependency", 0)
    end
end

local imgui_api = r.GetResourcePath() .. '/Scripts/ReaTeam Extensions/API/imgui.lua'
local imgui_loader, imgui_load_err = loadfile(imgui_api)
if not imgui_loader then
    ReflexIOManagerDependencyError(imgui_load_err)
    return
end

local imgui_ok, imgui_err = pcall(function() imgui_loader('0.10') end)
if not imgui_ok or not r.ImGui_CreateContext then
    ReflexIOManagerDependencyError(imgui_err)
    return
end

local ctx = r.ImGui_CreateContext("Reflex I/O Manager")

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
}

rgb = function(hex) return (hex << 8) | 0xFF end

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

opt_tooltips = LoadPref("tooltips", true)
local ui_scale = LoadPref("ui_scale_v2", 1.0)

local body_size = (nav_theme.fonts and nav_theme.fonts.body_size) or 14
local body_family = (nav_theme.fonts and nav_theme.fonts.family) or 'SF Pro'
local scaled_fonts = {}
local scaled_fonts_italic = {}
local scaled_fonts_regular = {}
for step = 5, 20 do
    local scale = step / 10
    local sz = math.floor(body_size * scale + 0.5)
    local f = r.ImGui_CreateFont(body_family, sz, r.ImGui_FontFlags_Bold())
    r.ImGui_Attach(ctx, f)
    scaled_fonts[step] = f
    local fi = r.ImGui_CreateFont(body_family, sz, r.ImGui_FontFlags_Italic())
    r.ImGui_Attach(ctx, fi)
    scaled_fonts_italic[step] = fi
    local fr = r.ImGui_CreateFont(body_family, sz, r.ImGui_FontFlags_None())
    r.ImGui_Attach(ctx, fr)
    scaled_fonts_regular[step] = fr
end

local C = {
    bg = rgb(0x171B22),
    border = rgb(0x30363D),
    text = rgb(0xE6EDF3),
    text_dim = rgb(0x8B949E),
    text_muted = rgb(0x484F58),
    green = rgb(0x3FB950),
    amber = rgb(0xD29922),
    midi_activity = rgb(0xFFCC00),
    cmp_b = rgb(0x58A6FF),
    fx_ctrl_bg = rgb(0x2A2F37),
    fx_ctrl_hover = rgb(0x363C46),
    fx_ctrl_active = rgb(0x424950),
    fx_offline_txt = rgb(0xF85149),
}
for key, hex in pairs(nav_theme.colors or {}) do
    if type(hex) == "number" then C[key] = rgb(hex) end
end

UI = { btn_h = 26, corner_r = 4, font_fx = 0, pad_sm = 6 }
S = function(v) return math.floor(v * ui_scale * 0.8 + 0.5) end
Round = function(v) return math.floor(v + 0.5) end

Utf8DropLast = function(s)
    local len = #s
    if len == 0 then return s end
    while len > 0 and s:byte(len) >= 0x80 and s:byte(len) <= 0xBF do len = len - 1 end
    if len > 0 then len = len - 1 end
    return s:sub(1, len)
end

package.loaded["Reflex_FontCore"] = nil
require("Reflex_FontCore")({
    r = r,
    ctx = ctx,
    scaled_fonts = scaled_fonts,
    scaled_fonts_italic = scaled_fonts_italic,
    scaled_fonts_regular = scaled_fonts_regular,
    get_ui_scale = function() return ui_scale end,
})

package.loaded["Reflex_StyleCore"] = nil
require("Reflex_StyleCore")({ r = r, ctx = ctx, colors = C })

package.loaded["Reflex_MeterCore"] = nil
require("Reflex_MeterCore")({ colors = C })

NavRect = function(id, w, h, content, opts)
    opts = opts or {}
    r.ImGui_InvisibleButton(ctx, id, opts.hit_w or w, opts.hit_h or h)
    local hov = r.ImGui_IsItemHovered(ctx)
    local active = r.ImGui_IsItemActive(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local x, y = r.ImGui_GetItemRectMin(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local bg = active and (opts.active or C.fx_ctrl_active)
        or (hov and (opts.hov or C.fx_ctrl_hover) or (opts.bg or C.fx_ctrl_bg))
    local fg = active and (opts.fg_active or opts.fg_hov or C.text)
        or (hov and (opts.fg_hov or C.text) or (opts.fg or C.text_dim))
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, opts.rounding or S(UI.corner_r))
    if content and content ~= "" then
        local tw, th = r.ImGui_CalcTextSize(ctx, content)
        r.ImGui_DrawList_AddText(dl, x + Round((w - tw) / 2), y + Round((h - th) / 2), fg, content)
    end
    return hov, clicked, active
end

NavSquare = function(id, w, h, content, opts)
    return NavRect(id, w, h, content, opts)
end

local nav_screen_rect = { x = 120, y = 120, w = S(620), h = S(720) }

package.loaded["Reflex_IOCore"] = nil
require("Reflex_IOCore")({
    r = r,
    ctx = ctx,
    colors = C,
    script_dir = script_dir,
    PREF = PREF,
})

package.loaded["Reflex_IOManagerCore"] = nil
require("Reflex_IOManagerCore")({
    r = r,
    ctx = ctx,
    colors = C,
    nav_screen_rect = nav_screen_rect,
})

RecordInputOpenManager(nil, nil)

Loop = function()
    RecordIODrawManager()
    if io_manager_open then r.defer(Loop) end
end

Loop()
