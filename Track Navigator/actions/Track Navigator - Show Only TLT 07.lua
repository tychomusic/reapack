-- @noindex

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or ""
dofile(script_dir .. "Track Navigator_ActionBridge.lua")("tlt_07_show_only")
