-- @noindex
-- Reflex: FX Window Next
-- Bind this action in REAPER to show the next FX window for Reflex's source track.

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or ""
dofile(script_dir .. "Reflex_ActionBridge.lua")("fx_window_next", { launch_if_missing = true })
