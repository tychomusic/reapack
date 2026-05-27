-- @noindex
-- Reflex: Focus Navigator Search
-- Bind this action in REAPER to focus Reflex's Navigator search field.

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or ""
dofile(script_dir .. "Reflex_ActionBridge.lua")("focus_tlt_search", { launch_if_missing = true })
