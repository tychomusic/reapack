-- @noindex
-- Reflex: Open FX Browser
-- Bind this action in REAPER to launch Reflex's configured FX browser.

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or ""
dofile(script_dir .. "Reflex_ActionBridge.lua")("open_fx_browser", { launch_if_missing = true })
