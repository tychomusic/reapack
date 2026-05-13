-- @noindex
-- =======================================================================================
-- ENVISION THEME v1.0
-- =======================================================================================
-- Copy this file to Envision_Theme.lua to customize Envision's appearance.
-- Envision_Theme.lua is optional and is not installed by the ReaPack package.
--
-- COLOR FORMAT: 0xRRGGBB (alpha is added automatically)
--
-- Track Color Overrides:
--   Key: exact track name (case-sensitive, matches REAPER track name)
--   Value: 0xRRGGBB hex color, or nil to use REAPER track color
--   These override the color shown on Envision buttons, not in REAPER.

return {

  -- =====================================================
  -- FONTS
  -- =====================================================
  -- Base UI text size. Envision pre-creates scaled fonts
  -- at steps 0.5x – 2.0x around this value.
  -- family: font family name passed to ImGui_CreateFont. Default "SF Pro"
  -- (macOS system font). ReaImGui falls back to system sans-serif if the
  -- named family isn't installed. Try "Inter", "Helvetica Neue", or
  -- "sans-serif" to switch.
  fonts = {
    body_size = 14,
    family    = "SF Pro",
  },

  -- =====================================================
  -- COLORS
  -- =====================================================
  -- Override any Envision UI color. Delete or comment out
  -- a line to use the default. Key must match exactly.
  colors = {
    -- Background / Text
    -- bg              = 0x171B22,
    -- window_bg       = 0x3E3E3F,
    -- card_stroke     = 0x2B2F36,
    -- border          = 0x30363D,
    -- text            = 0xE6EDF3,
    -- text_dim        = 0x8B949E,
    -- text_muted      = 0x484F58,
    -- section_text    = 0x555D67,

    -- Buttons
    -- btn_bg          = 0x21262D,
    -- btn_hover       = 0x30363D,
    -- btn_active      = 0x3A424B,
    -- tab_sel_bg      = 0x6E7681,
    -- tab_sel_hov     = 0x7D8590,
    -- tab_sel_txt     = 0x0D1117,

    -- Status
    -- green           = 0x3FB950,
    -- green_dim       = 0x1A3D2A,
    -- amber           = 0xD29922,
    -- amber_dim       = 0x5C4A1A,
    -- midi_activity   = 0xFFCC00,
    -- input_meter_bg  = 0x4A5060,
    -- pan_color       = 0xDB8320,
    -- pan_dim         = 0x5C3810,

    -- FX States
    -- fx_offline_bg   = 0x15191E,
    -- fx_offline_txt  = 0xF85149,
    -- fx_bypassed_txt = 0xD29922,
    -- fx_bypass_env   = 0xC0A0F0,
    -- fx_drywet_txt   = 0x6B9BD2,
    -- fx_wrapper_text = 0x8B949E,
    -- fx_env_text     = 0xBB99DD,
    -- fx_send_text    = 0x58A6FF,
    fx_instr_txt    = 0x324bd0,
    -- fx_ctrl_bg      = 0x2A2F37,
    -- fx_ctrl_hover   = 0x363C46,
    -- fx_ctrl_active  = 0x424950,

    -- Compare
    -- cmp_a           = 0x3B82F6,
    -- cmp_b           = 0xF59E0B,
    -- cmp_a_dim       = 0x1E3A5F,
    -- cmp_b_dim       = 0x5C3D0E,
    -- cmp_aware_bg    = 0x363C46,
    -- cmp_aware_txt   = 0xA0A8B4,

    -- Inspector
    -- track_header_bg = 0x171B22,
    -- track_cap_none  = 0x2A2F37,
    -- env_row_bg      = 0x181C24,
    -- fx_row_bg       = 0x1E2228,
    -- fx_row_border   = 0x2A3040,
    -- flow_source_bg  = 0x1E2228,

    -- Volume / Pan Bars
    -- vol_bar         = 0x89FFDB,
    -- vol_bar_bg      = 0x171B22,
    -- pan_bar         = 0xE8A657,

    -- Volume Slider
    -- vol_slider_bg   = 0x262A2E,
    vol_slider_fill = 0x08a5f7,
    -- vol_slider_handle = 0xE6EDF3,
    -- vol_slider_handle_active = 0xFFFFFF,
    vol_slider_mark = 0x3e454b,
    vol_slider_mark_over = 0x82baf7,
    vol_slider_mark_intersect = 0xb9b9b9,
    -- pan_slider_fill = 0xF8BE2E,

    -- Routing
    -- route_parent    = 0x58A6FF,
    -- route_parent_dim= 0x1E3050,
    -- route_send      = 0xD29922,
    -- route_send_dim  = 0x3D2E10,
    -- route_recv      = 0xF85149,
    -- route_recv_dim  = 0x4A1A18,
    -- route_dim       = 0x484F58,
    -- route_bg        = 0x2A2F37,
  },

  -- =====================================================
  -- TRACK COLOR OVERRIDES
  -- =====================================================
  -- Override the button color for specific TLFs or sub-group children.
  -- Remove a line or set to nil to fall back to REAPER track color.
  track_colors = {
    -- ["SONGS"]    = 0x2EA04F,
    -- ["MONITORS"] = 0xDA3633,
    -- ["I/O"]      = 0x58A6FF,
    -- ["SYNC"]     = 0xD29922,
    -- ["VISUAL"]   = 0xBF40BF,
  },

  -- =====================================================
  -- REMOTE BUTTON COLORS
  -- =====================================================
  -- Palette for coloring remote macro pad buttons.
  -- Add or remove entries as needed. Index matches
  -- the swatch order in the right-click menu.
  remote_colors = {
    0x3B82F6,  -- blue
    0x3FB950,  -- green
    0xD29922,  -- amber
    0xF85149,  -- red
    0xBF40BF,  -- purple
    0x58A6FF,  -- light blue
  },

  -- =====================================================
  -- BUTTON BRIGHTNESS
  -- =====================================================
  -- Controls how bright track-colored buttons appear.
  -- Values are multipliers: 1.0 = full color, 0.5 = half brightness.
  button_brightness = {
    visible         = 0.65,
    visible_hover   = 0.80,
    visible_active  = 0.55,
    hidden          = 0.25,
    hidden_hover    = 0.35,
    hidden_active   = 0.20,
  },

  -- =====================================================
  -- SONGS PAGE COLORS
  -- =====================================================
  -- Override the flat colors used on the SONGS page buttons.
  -- Set to nil to use defaults.
  songs_page = {
    -- visible_bg    = 0x1E2228,
    -- visible_hover = 0x282E36,
    -- hidden_bg     = 0x13161B,
    -- hidden_hover  = 0x1A1E24,
  },
}
