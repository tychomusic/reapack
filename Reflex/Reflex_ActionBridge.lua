-- @noindex

local r = reaper
local PREF = "reflex"
local COMMAND_KEY = "reflex_navigator_external_command"
local INSTANCE_KEY = "reflex_navigator_instance_token"

return function(command, opts)
    if not command or command == "" then return end
    opts = opts or {}
    local nonce = r.time_precise and r.time_precise() or os.clock()
    r.SetExtState(PREF, COMMAND_KEY, tostring(command) .. "|" .. tostring(nonce), false)

    local running = r.GetExtState(PREF, INSTANCE_KEY) ~= ""
    if running or not opts.launch_if_missing then return end

    local script_dir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or ""
    dofile(script_dir .. "Reflex.lua")
end
