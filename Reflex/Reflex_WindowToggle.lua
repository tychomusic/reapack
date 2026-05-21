-- @noindex
--[[
 * Description: Toggle all open FX windows (close with position memory, restore on repeat)
 * Author:      S.Hansen / Tycho
 * Version:     1.3
 *
 * Bind as a REAPER action to any key.
 * First press: snapshots all open FX window positions, closes them.
 * Second press: restores all windows to their saved positions.
 *
 * Entry format: track_guid;fx_guid;x;y;w;h separated by |
 * Requires: js_ReaScriptAPI
--]]

local r = reaper

if not r.JS_Window_GetRect then
    local msg = "Reflex FX Window Toggle requires js_ReaScriptAPI."
    if r.ReaPack_BrowsePackages then
        local choice = r.MB(msg .. "\n\nOpen ReaPack package browser for js_ReaScriptAPI?", "Reflex: Missing dependency", 4)
        if choice == 6 then r.ReaPack_BrowsePackages("js_ReaScriptAPI") end
    else
        r.MB(msg .. "\n\nInstall js_ReaScriptAPI via ReaPack, then run this action again.", "Reflex: Missing dependency", 0)
    end
    return
end

local EXT_SECTION = "reflex_fxwindows"
local SLOT_KEY = "slot_0"

local function FindTrackByGUID(target_guid)
    local master = r.GetMasterTrack(0)
    if r.GetTrackGUID(master) == target_guid then return master end
    for i = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, i)
        if r.GetTrackGUID(track) == target_guid then return track end
    end
    return nil
end

local function FindFXByGUID(track, target_guid)
    for f = 0, r.TrackFX_GetCount(track) - 1 do
        if r.TrackFX_GetFXGUID(track, f) == target_guid then return f end
    end
    return nil
end

local function GetAllTracks()
    local tracks = { r.GetMasterTrack(0) }
    for i = 0, r.CountTracks(0) - 1 do
        tracks[#tracks + 1] = r.GetTrack(0, i)
    end
    return tracks
end

local function CaptureAndClose()
    local entries = {}
    local to_close = {}
    local tracks = GetAllTracks()
    for _, track in ipairs(tracks) do
        local track_guid = r.GetTrackGUID(track)
        for f = 0, r.TrackFX_GetCount(track) - 1 do
            local hwnd = r.TrackFX_GetFloatingWindow(track, f)
            if hwnd then
                local fx_guid = r.TrackFX_GetFXGUID(track, f)
                if fx_guid then
                    local _, left, top, right, bottom = r.JS_Window_GetRect(hwnd)
                    local w = right - left
                    local h = bottom - top
                    -- Guard: only store if all values are valid numbers
                    if left and top and w and h then
                        entries[#entries + 1] = string.format("%s;%s;%d;%d;%d;%d",
                            track_guid, fx_guid, left, top, w, h)
                        to_close[#to_close + 1] = { track = track, fx_idx = f }
                    end
                end
            end
        end
    end
    if #entries == 0 then return nil end
    r.PreventUIRefresh(1)
    for _, c in ipairs(to_close) do
        r.TrackFX_Show(c.track, c.fx_idx, 2)
    end
    r.PreventUIRefresh(-1)
    return table.concat(entries, "|")
end

local function RestoreSnapshot(data_str)
    if not data_str or data_str == "" then return false end
    local windows = {}
    for entry in data_str:gmatch("([^|]+)") do
        local parts = {}
        for p in entry:gmatch("([^;]+)") do parts[#parts + 1] = p end
        if #parts == 6 then
            local track = FindTrackByGUID(parts[1])
            if track then
                local fx_idx = FindFXByGUID(track, parts[2])
                if fx_idx then
                    local x = tonumber(parts[3])
                    local y = tonumber(parts[4])
                    local w = tonumber(parts[5])
                    local h = tonumber(parts[6])
                    if x and y and w and h then
                        windows[#windows + 1] = {
                            track = track, fx_idx = fx_idx,
                            x = x, y = y, w = w, h = h,
                        }
                    end
                end
            end
        end
    end
    if #windows == 0 then return false end
    r.PreventUIRefresh(1)
    for _, win in ipairs(windows) do
        r.TrackFX_Show(win.track, win.fx_idx, 3)
    end
    r.PreventUIRefresh(-1)
    -- Defer position restore one frame
    local wins = windows
    r.defer(function()
        for _, win in ipairs(wins) do
            local hwnd = r.TrackFX_GetFloatingWindow(win.track, win.fx_idx)
            if hwnd then
                r.JS_Window_SetPosition(hwnd, win.x, win.y, win.w, win.h)
            end
        end
    end)
    return true
end

local function Main()
    local has_open = false
    local tracks = GetAllTracks()
    for _, track in ipairs(tracks) do
        for f = 0, r.TrackFX_GetCount(track) - 1 do
            if r.TrackFX_GetFloatingWindow(track, f) then
                has_open = true; break
            end
        end
        if has_open then break end
    end

    if has_open then
        local data = CaptureAndClose()
        if data then
            r.SetExtState(EXT_SECTION, SLOT_KEY, data, false)
        end
    else
        local data = r.GetExtState(EXT_SECTION, SLOT_KEY)
        if data ~= "" then
            if RestoreSnapshot(data) then
                r.SetExtState(EXT_SECTION, SLOT_KEY, "", false)
            end
        end
    end
end

Main()
