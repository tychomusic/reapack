-- @noindex
-- Reflex: FX Window Stack Next
-- Bind this action in REAPER to show/raise the next FX window for Reflex's source track without closing other FX windows.

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or ""
dofile(script_dir .. "Reflex_ActionBridge.lua")("fx_window_stack_next", { launch_if_missing = true })
