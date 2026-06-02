-- @noindex
-- Reflex: Close All FX Windows
-- Bind this action in REAPER to close all track/take FX windows.

local r = reaper
local PREF = "reflex"
local COMMAND_KEY = "reflex_navigator_external_command"
local INSTANCE_KEY = "reflex_navigator_instance_token"

ReflexCloseAllFXWindowsActionSendToRunning = function()
    if r.GetExtState(PREF, INSTANCE_KEY) == "" then return false end
    local nonce = r.time_precise and r.time_precise() or os.clock()
    r.SetExtState(PREF, COMMAND_KEY, "close_all_fx_windows|" .. tostring(nonce), false)
    return true
end

ReflexCloseAllFXWindowsActionCloseTrack = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    if r.TrackFX_GetChainVisible(track) ~= -1 then r.TrackFX_Show(track, 0, 0) end
    for i = 0, r.TrackFX_GetCount(track) - 1 do
        if r.TrackFX_GetOpen(track, i) then r.TrackFX_SetOpen(track, i, 0) end
    end

    for i = 0, r.TrackFX_GetRecCount(track) - 1 do
        local rec_idx = i + 0x1000000
        if r.TrackFX_GetOpen(track, rec_idx) then r.TrackFX_SetOpen(track, rec_idx, 0) end
        if r.TrackFX_GetRecChainVisible(track) ~= -1 then r.TrackFX_Show(track, rec_idx, 0) end
    end
end

ReflexCloseAllFXWindowsActionCloseTake = function(take)
    if not take or not r.ValidatePtr(take, "MediaItem_Take*") then return end
    if r.TakeFX_GetChainVisible(take) ~= -1 then r.TakeFX_Show(take, 0, 0) end
    for i = 0, r.TakeFX_GetCount(take) - 1 do
        if r.TakeFX_GetOpen(take, i) then r.TakeFX_SetOpen(take, i, 0) end
    end
end

ReflexCloseAllFXWindowsActionRunStandalone = function()
    r.PreventUIRefresh(1)
    local ok, err = pcall(function()
        local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
        ReflexCloseAllFXWindowsActionCloseTrack(master)
        for i = 0, r.CountTracks(0) - 1 do
            local track = r.GetTrack(0, i)
            ReflexCloseAllFXWindowsActionCloseTrack(track)
            for j = 0, r.CountTrackMediaItems(track) - 1 do
                local item = r.GetTrackMediaItem(track, j)
                for k = 0, r.GetMediaItemNumTakes(item) - 1 do
                    ReflexCloseAllFXWindowsActionCloseTake(r.GetTake(item, k))
                end
            end
        end
    end)
    r.PreventUIRefresh(-1)
    if not ok then error(err) end
end

if not ReflexCloseAllFXWindowsActionSendToRunning() then
    ReflexCloseAllFXWindowsActionRunStandalone()
end
