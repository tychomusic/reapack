-- @noindex
-- Reflex: Tile FX Windows
-- Bind this action in REAPER to tile all open FX windows through Reflex.

local script_dir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or ""
dofile(script_dir .. "Reflex_ActionBridge.lua")("tile_fx_windows", { launch_if_missing = true })
