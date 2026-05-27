-- @noindex
-- Reflex: Toggle Navigator Expand
-- Bind this action in REAPER to toggle the Reflex/Navigator expand state.

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or ""
dofile(script_dir .. "Reflex_NavigatorActionBridge.lua")("toggle_navigator_expanded", { launch_if_missing = true })
