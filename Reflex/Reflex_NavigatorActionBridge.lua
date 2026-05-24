-- @noindex

local r = reaper
local PREF = "reflex"
local COMMAND_KEY = "reflex_navigator_external_command"
local INSTANCE_KEY = "reflex_navigator_instance_token"

return function(command, opts)
    if not command or command == "" then return end
    local running = r.GetExtState(PREF, INSTANCE_KEY) ~= ""
    if not running and not (opts and opts.launch_if_missing) then return end
    local nonce = r.time_precise and r.time_precise() or os.clock()
    r.SetExtState(PREF, COMMAND_KEY, tostring(command) .. "|" .. tostring(nonce), false)
    if running then return end
    if not (opts and opts.launch_if_missing) then return end
    local script_dir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or ""
    dofile(script_dir .. "Navigator.lua")
end
