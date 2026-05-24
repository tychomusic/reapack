-- @noindex

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or ""
dofile(script_dir .. "Reflex_NavigatorActionBridge.lua")("armed_scroll", { launch_if_missing = true })
