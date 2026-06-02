-- @noindex
-- Reflex: Close All FX Windows
-- Bind this action in REAPER to close all track/take FX windows through Reflex.

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or ""
dofile(script_dir .. "Reflex_ActionBridge.lua")("close_all_fx_windows", { launch_if_missing = true })
