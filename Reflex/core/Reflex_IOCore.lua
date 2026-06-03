-- @noindex
-- Reflex I/O core module.
-- Installs shared record-input aliases, favorites, device models, popup helpers,
-- meters, and persistence used by HDR.input and the I/O Manager window.

ReflexInstallIOCore = function(deps)
    local r = deps.r
    local ctx = deps.ctx
    local C = deps.colors
    local script_dir = deps.script_dir
    local PREF = deps.PREF

record_input_box_width = {}
record_input_activity_peak = {}
record_input_midi_flash = {}
record_input_midi_flash_level = {}
record_input_midi_recent_seq = 0
record_input_midi_recent = {}
record_input_midi_recent_level = {}
record_input_favorites = nil
record_input_context = nil
record_input_notice_text = ""
record_input_notice_until = 0
io_manager_open = false
io_manager_page = "audio_in"
io_manager_filter = ""
io_manager_edit = nil
io_manager_scroll_key = nil
io_manager_focus_key = nil
io_manager_first_open = true
io_manager_esc_consumed = false
io_manager_midi_hide_unavailable = LoadPref("io_manager_midi_hide_unavailable", false)
io_manager_audio_cleared_aliases = {}
record_io_audio_alias_cache = {}

RecordInputNotice = function(text)
    record_input_notice_text = text or ""
    record_input_notice_until = r.time_precise() + 3.0
end

RecordInputNoticeActive = function()
    return record_input_notice_text ~= ""
        and (record_input_notice_until or 0) > r.time_precise()
end

RecordInputFavoritesLoad = function()
    if record_input_favorites then return record_input_favorites end
    record_input_favorites = {}
    local raw = r.GetExtState(PREF, "record_input_favorites_v1")
    if raw and raw ~= "" then
        local seen = {}
        for key in raw:gmatch("[^|]+") do
            if key ~= "" and not seen[key] then
                record_input_favorites[#record_input_favorites + 1] = key
                seen[key] = true
            end
        end
    end
    return record_input_favorites
end

RecordInputFavoritesSave = function()
    local favs = RecordInputFavoritesLoad()
    r.SetExtState(PREF, "record_input_favorites_v1", table.concat(favs, "|"), true)
end

RecordInputFavoriteIndex = function(key)
    if not key or key == "" then return nil end
    local favs = RecordInputFavoritesLoad()
    for i, fav_key in ipairs(favs) do
        if fav_key == key then return i end
    end
    return nil
end

RecordInputFavoriteAdd = function(key)
    if not key or key == "" or RecordInputFavoriteIndex(key) then return end
    local favs = RecordInputFavoritesLoad()
    favs[#favs + 1] = key
    RecordInputFavoritesSave()
end

RecordInputFavoriteRemove = function(key)
    local favs = RecordInputFavoritesLoad()
    for i = #favs, 1, -1 do
        if favs[i] == key then table.remove(favs, i) end
    end
    RecordInputFavoritesSave()
end

RecordInputFavoriteMove = function(key, dir)
    local favs = RecordInputFavoritesLoad()
    local idx = RecordInputFavoriteIndex(key)
    if not idx then return end
    local dst = idx + dir
    while dst >= 1 and dst <= #favs and not RecordInputValueForFavoriteKey(favs[dst]) do
        dst = dst + dir
    end
    if dst < 1 or dst > #favs then return end
    favs[idx], favs[dst] = favs[dst], favs[idx]
    RecordInputFavoritesSave()
end

RecordInputFavoriteCanMove = function(key, dir)
    local favs = RecordInputFavoritesLoad()
    local idx = RecordInputFavoriteIndex(key)
    if not idx then return false end
    local dst = idx + dir
    while dst >= 1 and dst <= #favs do
        if RecordInputValueForFavoriteKey(favs[dst]) then return true end
        dst = dst + dir
    end
    return false
end

RecordInputMidiDeviceEnabled = function(device)
    device = math.floor(device or -1)
    if device == 62 then return true end
    if device == 63 or device < 0 or device >= 128 then return false end
    if not r.GetMIDIInputName then return false end
    local ok, rv = pcall(r.GetMIDIInputName, device, "")
    if not (ok and rv == true) then return false end
    if RecordIOMidiPrefsMap and RecordIOMidiInputEnabled then
        local prefs, has_prefs = RecordIOMidiPrefsMap()
        return RecordIOMidiInputEnabled(prefs, has_prefs, device)
    end
    return true
end

RecordInputFavoriteKeyForValue = function(value)
    local info = RecordInputInfo(value)
    if info.kind == "none" then return nil end
    if info.kind == "midi" then
        if info.device == 63 then return nil end
        return "midi:" .. tostring(info.device or 0) .. ":" .. tostring(info.channel or 0)
    end
    if info.kind == "mono" then return "mono:" .. tostring(info.channel or 0) end
    if info.kind == "stereo" then return "stereo:" .. tostring(info.channel or 0) end
    if info.kind == "multichannel" then return "multi:" .. tostring(info.channel or 0) end
    return nil
end

RecordInputValueForFavoriteKey = function(key)
    if not key or key == "" then return nil end
    local kind, a, b = key:match("^([^:]+):([^:]+):?([^:]*)$")
    local n = tonumber(a)
    if not kind or not n then return nil end
    if kind == "mono" then
        if n >= 0 and n < RecordInputNumAudioInputs() then return n end
    elseif kind == "stereo" then
        if n >= 0 and (n % 2) == 0 and n + 1 < RecordInputNumAudioInputs() then return 1024 + n end
    elseif kind == "multi" then
        if n >= 0 and n < RecordInputNumAudioInputs() then return 2048 + n end
    elseif kind == "midi" then
        local ch = tonumber(b) or 0
        if ch >= 0 and ch <= 16 and RecordInputMidiDeviceEnabled(n) then
            return RecordInputMidiValue(n, ch)
        end
    end
    return nil
end

RecordInputFavoriteMeterForValue = function(value, track)
    local meter = RecordInputMeterForValue(value, track)
    if meter then meter.align = nil end
    return meter
end

RecordInputFavoriteLabel = function(value, track)
    local info = RecordInputInfo(value)
    if info.kind == "none" then return "None", C.text end
    if info.kind == "midi" then
        if info.device == 63 and info.channel == 0 then return "All MIDI Inputs", C.midi_activity end
        local ch = info.channel == 0 and "" or (" / Channel " .. tostring(info.channel))
        return RecordInputMidiDeviceName(info.device) .. ch, C.midi_activity
    end
    local channel = info.channel or 0
    if info.kind == "stereo" then
        return RecordInputAudioName(channel) .. " / " .. RecordInputAudioName(channel + 1), C.text
    end
    if info.kind == "multichannel" then
        local track_ch = track and math.floor(r.GetMediaTrackInfo_Value(track, "I_NCHAN") or 2) or 2
        return "Multichannel (" .. tostring(track_ch) .. "ch): " .. RecordInputAudioName(channel), C.text
    end
    return RecordInputAudioName(channel), C.text
end

RecordInputFavoriteItems = function(track)
    local items = {}
    for _, key in ipairs(RecordInputFavoritesLoad()) do
        local value = RecordInputValueForFavoriteKey(key)
        if value then
            local label, label_col = RecordInputFavoriteLabel(value, track)
            items[#items + 1] = {
                key = key,
                value = value,
                index = RecordInputFavoriteIndex(key),
                label = label,
                label_col = label_col,
                meter = RecordInputFavoriteMeterForValue(value, track),
            }
        end
    end
    return items
end

RecordInputResourcePath = function(filename)
    local base = r.GetResourcePath and r.GetResourcePath() or script_dir
    return (base:gsub("[/\\]$", "")) .. "/" .. filename
end

RecordInputMainIniPath = function()
    if r.get_ini_file then
        local ok, path = pcall(r.get_ini_file)
        if ok and type(path) == "string" and path ~= "" then return path end
    end
    return RecordInputResourcePath("reaper.ini")
end

RecordInputIniAtomicWrite = function(path, text, old_text)
    if not path or path == "" or type(text) ~= "string" then return false end
    if not os or not os.rename then return false end

    local dir, name = path:match("^(.*[/\\])([^/\\]+)$")
    dir = dir or ""
    name = name or path
    local tmp_path = dir .. "." .. name .. ".reflex.tmp"
    local bak_path = path .. ".reflex.bak"

    local f = io.open(tmp_path, "w")
    if not f then return false end
    local ok = pcall(function() f:write(text) end)
    local close_ok = f:close()
    if not ok or not close_ok then
        if os.remove then pcall(os.remove, tmp_path) end
        return false
    end

    if old_text ~= nil then
        local bf = io.open(bak_path, "w")
        if bf then
            pcall(function() bf:write(old_text or "") end)
            bf:close()
        end
    end

    local moved = os.rename(tmp_path, path)
    if not moved then
        if os.remove then pcall(os.remove, tmp_path) end
        return false
    end
    return true
end

RecordInputIniSetKey = function(path, section, key, value)
    if not path or path == "" or not section or section == "" or not key or key == "" then return false end
    value = value and tostring(value):gsub("[\r\n]", " ") or nil
    local data = ""
    local f = io.open(path, "r")
    if f then data = f:read("*a") or ""; f:close() end

    local lines = {}
    for line in (data .. "\n"):gmatch("([^\n]*)\n") do
        if line:sub(-1) == "\r" then line = line:sub(1, -2) end
        lines[#lines + 1] = line
    end
    if #lines > 0 and lines[#lines] == "" then table.remove(lines, #lines) end

    local section_start, section_end = nil, nil
    for i, line in ipairs(lines) do
        local sec = line:match("^%s*%[(.-)%]%s*$")
        if sec then
            if sec == section then
                section_start = i
                section_end = #lines + 1
            elseif section_start and not section_end then
                section_end = i
                break
            elseif section_start then
                section_end = i
                break
            end
        end
    end
    if section_start and not section_end then section_end = #lines + 1 end

    if not section_start then
        if value == nil then return true end
        if #lines > 0 and lines[#lines] ~= "" then lines[#lines + 1] = "" end
        lines[#lines + 1] = "[" .. section .. "]"
        lines[#lines + 1] = key .. "=" .. value
    else
        local key_line = nil
        for i = section_start + 1, section_end - 1 do
            if lines[i]:match("^%s*" .. key:gsub("([^%w])", "%%%1") .. "%s*=") then
                key_line = i
                break
            end
        end
        if key_line then
            if value ~= nil then
                lines[key_line] = key .. "=" .. value
            else
                table.remove(lines, key_line)
            end
        elseif value ~= nil then
            table.insert(lines, section_end, key .. "=" .. value)
        end
    end

    return RecordInputIniAtomicWrite(path, table.concat(lines, "\n") .. "\n", data)
end

RecordInputIniSetKeys = function(path, section, updates)
    if not path or path == "" or not section or section == "" or type(updates) ~= "table" then
        return false
    end
    local has_write = false
    local sanitized = {}
    local deletes = {}
    for key, value in pairs(updates) do
        if key and key ~= "" then
            if value == false then
                deletes[key] = true
            else
                has_write = true
                sanitized[key] = tostring(value):gsub("[\r\n]", " ")
            end
        end
    end

    local data = ""
    local f = io.open(path, "r")
    if f then data = f:read("*a") or ""; f:close() end

    local lines = {}
    for line in (data .. "\n"):gmatch("([^\n]*)\n") do
        if line:sub(-1) == "\r" then line = line:sub(1, -2) end
        lines[#lines + 1] = line
    end
    if #lines > 0 and lines[#lines] == "" then table.remove(lines, #lines) end

    local section_start, section_end = nil, nil
    for i, line in ipairs(lines) do
        local sec = line:match("^%s*%[(.-)%]%s*$")
        if sec then
            if sec == section then
                section_start = i
                section_end = #lines + 1
            elseif section_start then
                section_end = i
                break
            end
        end
    end
    if section_start and not section_end then section_end = #lines + 1 end

    if not section_start then
        if not has_write then return true end
        if #lines > 0 and lines[#lines] ~= "" then lines[#lines + 1] = "" end
        lines[#lines + 1] = "[" .. section .. "]"
        section_start = #lines
        section_end = #lines + 1
    end

    local found = {}
    for i = section_end - 1, section_start + 1, -1 do
        local k = lines[i]:match("^%s*([^=]-)%s*=")
        if k then
            k = k:gsub("%s+$", "")
            if sanitized[k] ~= nil then
                if sanitized[k] ~= nil and not found[k] then
                    lines[i] = k .. "=" .. sanitized[k]
                    found[k] = true
                else
                    table.remove(lines, i)
                    section_end = section_end - 1
                end
            elseif deletes[k] then
                table.remove(lines, i)
                section_end = section_end - 1
            end
        end
    end

    for key, value in pairs(sanitized) do
        if value ~= nil and not found[key] then
            table.insert(lines, section_end, key .. "=" .. value)
            section_end = section_end + 1
        end
    end

    return RecordInputIniAtomicWrite(path, table.concat(lines, "\n") .. "\n", data)
end

RecordInputIniReadSection = function(path, section)
    local map = {}
    local order = {}
    if not path or path == "" or not section or section == "" then return map, order end
    local f = io.open(path, "r")
    if not f then return map, order end
    local in_section = false
    for raw in f:lines() do
        local line = raw
        if line:sub(-1) == "\r" then line = line:sub(1, -2) end
        local sec = line:match("^%s*%[(.-)%]%s*$")
        if sec then
            if in_section and sec ~= section then break end
            in_section = sec == section
        elseif in_section then
            local k, v = line:match("^%s*([^=]-)%s*=(.*)$")
            if k and k ~= "" then
                k = k:gsub("%s+$", "")
                map[k] = v or ""
                order[#order + 1] = k
            end
        end
    end
    f:close()
    return map, order
end

RecordInputIniGetKey = function(path, section, key)
    local map = RecordInputIniReadSection(path, section)
    return map[key]
end

RecordIOGetAudioIdent = function(direction)
    if not r.GetAudioDeviceInfo then return nil end
    local key = direction == "out" and "IDENT_OUT" or "IDENT_IN"
    local ok, rv, got = pcall(r.GetAudioDeviceInfo, key, "")
    if not ok then return nil end
    if type(rv) == "boolean" and rv and type(got) == "string" and got ~= "" then return got end
    if type(rv) == "string" and rv ~= "" then return rv end
    return nil
end

RecordInputGetAudioInputIdent = function()
    return RecordIOGetAudioIdent("in")
end

RecordIOAudioAliasIdent = function(direction)
    local ident = RecordIOGetAudioIdent(direction)
    if not ident then return nil end
    return ident:gsub("%s+", "_")
end

RecordIOAudioAliasSection = function(direction)
    local ident = RecordIOAudioAliasIdent(direction)
    if not ident then return nil end
    return (direction == "out" and "alias_out_" or "alias_in_") .. ident
end

RecordIOAudioAliasMap = function(direction, force)
    direction = direction == "out" and "out" or "in"
    local section = RecordIOAudioAliasSection(direction)
    if not section then return {} end
    local path = RecordInputMainIniPath()
    local cache = record_io_audio_alias_cache[direction]
    local now = r.time_precise and r.time_precise() or 0
    if force or not cache or cache.section ~= section or cache.path ~= path
        or (now > 0 and now - (cache.read_time or 0) > 1.0)
    then
        local map = RecordInputIniReadSection(path, section)
        cache = { section = section, path = path, map = map, read_time = now }
        record_io_audio_alias_cache[direction] = cache
    end
    return cache.map or {}
end

RecordIOAudioAlias = function(direction, channel, force)
    local map = RecordIOAudioAliasMap(direction, force)
    return map["name" .. tostring(math.floor(channel or 0))] or ""
end

RecordIOAudioClearedKey = function(direction, channel)
    return tostring(direction or "in") .. ":" .. tostring(math.floor(channel or 0))
end

RecordIOSetAudioAlias = function(direction, channel, alias)
    local section = RecordIOAudioAliasSection(direction)
    if not section then
        RecordInputNotice(direction == "out"
            and "Could not find REAPER output alias section"
            or "Could not find REAPER input alias section")
        return false
    end
    channel = math.floor(channel or 0)
    local alias_map = RecordIOAudioAliasMap(direction, true)
    local old_alias = alias_map["name" .. tostring(channel)] or ""
    alias = tostring(alias or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not alias:match("%S") then alias = "" end
    if alias == "" and old_alias == "" then
        io_manager_audio_cleared_aliases[RecordIOAudioClearedKey(direction, channel)] = nil
        RecordInputNotice("No alias saved for this channel")
        return true
    end
    local hw_n = math.max(channel + 1, RecordIOAudioHardwareCount(direction))
    local map_n = math.max(channel + 1, RecordIOAudioAliasCount(alias_map), hw_n)
    local updates = {
        ["name" .. tostring(channel)] = alias ~= "" and alias or false,
        ["ch" .. tostring(channel)] = tostring(channel),
        map_size = tostring(map_n),
        map_hwnch = tostring(hw_n),
    }
    local ok = RecordInputIniSetKeys(RecordInputMainIniPath(), section, updates)
    if not ok then
        RecordInputNotice("Could not write reaper.ini")
        return false
    end
    local clear_key = RecordIOAudioClearedKey(direction, channel)
    if alias == "" then
        io_manager_audio_cleared_aliases[clear_key] = old_alias ~= "" and old_alias or nil
    else
        io_manager_audio_cleared_aliases[clear_key] = nil
    end
    RecordIOAudioAliasMap(direction, true)
    local api_name = RecordIOAudioApiName(direction, channel)
    local live = alias ~= "" and RecordIOAudioNameMatches(api_name, alias)
    if alias == "" then
        live = old_alias == "" or not RecordIOAudioNameMatches(api_name, old_alias)
    end
    if live then
        RecordInputNotice(alias == "" and "Alias cleared; REAPER live name confirmed"
            or "Alias saved; REAPER live name confirmed")
    else
        RecordInputNotice(alias == "" and "Alias cleared in reaper.ini; reopen device or restart REAPER"
            or "Alias written to reaper.ini; reopen device or restart REAPER")
    end
    return true
end

RecordInputSetAudioAlias = function(channel, alias)
    return RecordIOSetAudioAlias("in", channel, alias)
end

RecordOutputSetAudioAlias = function(channel, alias)
    return RecordIOSetAudioAlias("out", channel, alias)
end

RecordIORestartAudio = function()
    if not r.Audio_Quit or not r.Audio_Init then
        RecordInputNotice("Audio restart API unavailable")
        return false
    end
    if r.GetPlayState and math.floor(r.GetPlayState() or 0) ~= 0 then
        RecordInputNotice("Stop transport before restarting audio")
        return false
    end
    r.Audio_Quit()
    r.Audio_Init()
    RecordIOAudioAliasMap("in", true)
    RecordIOAudioAliasMap("out", true)
    record_input_box_width = {}
    RecordInputNotice("Audio device restarted")
    return true
end

RecordIOMidiReinit = function(msg)
    if r.GetPlayState and r.GetPlayState() == 0 and r.midi_reinit then
        pcall(r.midi_reinit)
    else
        RecordInputNotice(msg or "MIDI setting saved; stop transport to refresh devices")
    end
end

RecordIOMidiPrefixes = function(direction)
    if direction == "out" then
        return { alias = "oa", name = "on", original = "ox", flags = "ot" }
    end
    return { alias = "ia", name = "in", original = "ix", flags = "it" }
end

RecordIOMidiIgnorePrefix = function(direction)
    return direction == "out" and "o" or "i"
end

RecordIOMidiIgnoreKey = function(direction, original, ignore_map)
    if not original or original == "" then return nil end
    local prefix = RecordIOMidiIgnorePrefix(direction)
    ignore_map = ignore_map or RecordInputIniReadSection(RecordInputResourcePath("reaper-midihw.ini"), "mididevignore")
    for key, value in pairs(ignore_map or {}) do
        if key:match("^" .. prefix .. "%d+$") and value == original then return key end
    end
    return nil
end

RecordIOSetMidiIgnored = function(direction, original, ignored)
    if not original or original == "" then return false end
    local path = RecordInputResourcePath("reaper-midihw.ini")
    local section = "mididevignore"
    local map = RecordInputIniReadSection(path, section)
    local prefix = RecordIOMidiIgnorePrefix(direction)
    local changed = false
    if ignored then
        if RecordIOMidiIgnoreKey(direction, original, map) then return true end
        local max_idx = -1
        for key in pairs(map) do
            local idx = key:match("^" .. prefix .. "(%d+)$")
            if idx then max_idx = math.max(max_idx, tonumber(idx) or -1) end
        end
        changed = RecordInputIniSetKey(path, section, prefix .. tostring(max_idx + 1), original)
    else
        for key, value in pairs(map) do
            if key:match("^" .. prefix .. "%d+$") and value == original then
                changed = RecordInputIniSetKey(path, section, key, nil) or changed
            end
        end
    end
    if changed then RecordIOMidiReinit("MIDI device state saved; stop transport to refresh devices") end
    return changed
end

RecordIOSetMidiAlias = function(direction, device, alias)
    device = math.floor(device or -1)
    if device < 0 or (direction == "in" and (device == 62 or device == 63)) then return false end
    local p = RecordIOMidiPrefixes(direction)
    local ok = RecordInputIniSetKey(RecordInputResourcePath("reaper-midihw.ini"),
        "mididevcache", p.alias .. tostring(device), alias ~= "" and alias or nil)
    if not ok then
        RecordInputNotice("Could not write reaper-midihw.ini")
        return false
    end
    RecordIOMidiReinit("MIDI alias saved; stop transport to refresh devices")
    return true
end

RecordInputSetMidiAlias = function(device, alias)
    return RecordIOSetMidiAlias("in", device, alias)
end

RecordOutputSetMidiAlias = function(device, alias)
    return RecordIOSetMidiAlias("out", device, alias)
end

RecordInputMidiDeviceOriginalName = function(device)
    if not r.GetMIDIInputNameNoAlias then return nil end
    local ok, rv, got = pcall(r.GetMIDIInputNameNoAlias, device, "")
    if not ok then return nil end
    if type(rv) == "boolean" and rv and type(got) == "string" and got ~= "" then return got end
    if type(rv) == "string" and rv ~= "" then return rv end
    return nil
end

RecordIOMidiDeviceOriginalName = function(direction, device)
    if direction == "out" then
        if not r.GetMIDIOutputNameNoAlias then return nil end
        local ok, rv, got = pcall(r.GetMIDIOutputNameNoAlias, device, "")
        if not ok then return nil end
        if type(rv) == "boolean" and rv and type(got) == "string" and got ~= "" then return got end
        if type(rv) == "string" and rv ~= "" then return rv end
        return nil
    end
    return RecordInputMidiDeviceOriginalName(device)
end

RecordInputCanAliasInfo = function(info)
    if not info then return false end
    if info.kind == "mono" or info.kind == "stereo" or info.kind == "multichannel" then return true end
    return info.kind == "midi" and (info.device or 63) ~= 62 and (info.device or 63) ~= 63
end

RecordIOPageDirection = function(page)
    if page == "audio_out" or page == "midi_out" then return "out" end
    return "in"
end

RecordIOFavoriteStore = function(page)
    if page == "audio_in" or page == "midi_in" then return "record_input_favorites_v1" end
    if page == "audio_out" then return "record_output_favorites_v1" end
    return "record_midi_output_favorites_v1"
end

RecordIOFavoritesLoad = function(page)
    local store = RecordIOFavoriteStore(page)
    if store == "record_input_favorites_v1" then return RecordInputFavoritesLoad() end
    local favs = {}
    local raw = r.GetExtState(PREF, store)
    if raw and raw ~= "" then
        local seen = {}
        for key in raw:gmatch("[^|]+") do
            if key ~= "" and not seen[key] then
                favs[#favs + 1] = key
                seen[key] = true
            end
        end
    end
    return favs
end

RecordIOFavoritesSave = function(page, favs)
    local store = RecordIOFavoriteStore(page)
    if store == "record_input_favorites_v1" then
        record_input_favorites = favs
        RecordInputFavoritesSave()
        return
    end
    r.SetExtState(PREF, store, table.concat(favs or {}, "|"), true)
end

RecordIOFavoriteHas = function(page, key)
    if not key or key == "" then return false end
    local favs = RecordIOFavoritesLoad(page)
    for _, fav in ipairs(favs) do
        if fav == key then return true end
    end
    return false
end

RecordIOFavoriteToggle = function(page, key)
    if not key or key == "" then return end
    local favs = RecordIOFavoritesLoad(page)
    for i = #favs, 1, -1 do
        if favs[i] == key then
            table.remove(favs, i)
            RecordIOFavoritesSave(page, favs)
            return
        end
    end
    favs[#favs + 1] = key
    RecordIOFavoritesSave(page, favs)
end

RecordIOAudioAliasCount = function(alias_map)
    local n = 0
    n = math.max(n, math.floor(tonumber(alias_map and alias_map.map_size) or 0))
    n = math.max(n, math.floor(tonumber(alias_map and alias_map.map_hwnch) or 0))
    for key in pairs(alias_map or {}) do
        local ch = tonumber(key:match("^name(%d+)$"))
        if ch then n = math.max(n, math.floor(ch) + 1) end
        ch = tonumber(key:match("^ch(%d+)$"))
        if ch then n = math.max(n, math.floor(ch) + 1) end
    end
    return n
end

RecordIOAudioInfoCount = function(direction)
    if not r.GetAudioDeviceInfo then return 0 end
    local key = direction == "out" and "NOUTPUTS" or "NINPUTS"
    local ok, rv, got = pcall(r.GetAudioDeviceInfo, key, "")
    if not ok then return 0 end
    local n = tonumber((type(rv) == "boolean" and got) or rv)
    if n then return math.max(0, math.floor(n)) end
    return 0
end

RecordIOAudioProbeCount = function(direction)
    if not r.GetAudioDeviceInfo then return 0 end
    local prefix = direction == "out" and "OUTPUT" or "INPUT"
    local n = 0
    for ch = 0, 255 do
        local ok, rv, got = pcall(r.GetAudioDeviceInfo, prefix .. tostring(ch), "")
        local name = nil
        if ok then
            if type(rv) == "boolean" and rv and type(got) == "string" and got ~= "" then name = got end
            if type(rv) == "string" and rv ~= "" then name = rv end
        end
        if name and name ~= "" then n = ch + 1 end
    end
    return n
end

RecordIOAudioHardwareCount = function(direction)
    direction = direction == "out" and "out" or "in"
    local n = RecordIOAudioInfoCount(direction)
    if direction == "out" then
        if r.GetNumAudioOutputs then
            local ok, got = pcall(r.GetNumAudioOutputs)
            if ok then n = math.max(n, math.floor(tonumber(got) or 0)) end
        end
    else
        n = math.max(n, RecordInputNumAudioInputs())
    end
    return math.max(n, RecordIOAudioProbeCount(direction))
end

RecordIOAudioCount = function(direction, alias_map)
    local alias_n = RecordIOAudioAliasCount(alias_map)
    local info_n = RecordIOAudioInfoCount(direction)
    if direction == "out" then
        if r.GetNumAudioOutputs then
            local ok, n = pcall(r.GetNumAudioOutputs)
            if ok then
                local live_n = math.max(0, math.floor(tonumber(n) or 0))
                local total_n = math.max(alias_n, info_n, live_n)
                if total_n > 0 then return total_n end
                return RecordIOAudioProbeCount(direction)
            end
        end
        local total_n = math.max(alias_n, info_n)
        if total_n > 0 then return total_n end
        return RecordIOAudioProbeCount(direction)
    end
    local total_n = math.max(alias_n, info_n, RecordInputNumAudioInputs())
    if total_n > 0 then return total_n end
    return RecordIOAudioProbeCount(direction)
end

RecordIOAudioDefaultName = function(direction, channel)
    return (direction == "out" and "Output " or "Input ") .. tostring(math.floor(channel or 0) + 1)
end

RecordIOAudioApiName = function(direction, channel)
    direction = direction == "out" and "out" or "in"
    channel = math.floor(channel or 0)
    local name = nil
    if direction == "out" then
        if r.GetOutputChannelName then
            local ok, got = pcall(r.GetOutputChannelName, channel)
            if ok and type(got) == "string" and got ~= "" then name = got end
        end
    elseif r.GetInputChannelName then
        local ok, got = pcall(r.GetInputChannelName, channel)
        if ok and type(got) == "string" and got ~= "" then name = got end
    end
    return name or RecordIOAudioDefaultName(direction, channel)
end

RecordIOAudioNameMatches = function(name, ...)
    if not name or name == "" then return false end
    local nl = tostring(name):lower()
    for i = 1, select("#", ...) do
        local other = select(i, ...)
        if other and other ~= "" and nl == tostring(other):lower() then return true end
    end
    return false
end

RecordIOAudioHWName = function(direction, channel, alias, exposed)
    channel = math.floor(channel or 0)
    local cleared = io_manager_audio_cleared_aliases[RecordIOAudioClearedKey(direction, channel)]
    if r.GetAudioDeviceInfo then
        local key = direction == "out" and ("OUTPUT" .. tostring(channel)) or ("INPUT" .. tostring(channel))
        local ok, rv, got = pcall(r.GetAudioDeviceInfo, key, "")
        if ok then
            local name = nil
            if type(rv) == "boolean" and rv and type(got) == "string" and got ~= "" then name = got end
            if type(rv) == "string" and rv ~= "" then name = rv end
            if name and not RecordIOAudioNameMatches(name, alias, cleared) then return name end
        end
    end
    if alias and alias ~= "" and exposed and exposed ~= "" and not RecordIOAudioNameMatches(exposed, alias) then
        return exposed
    end
    return RecordIOAudioDefaultName(direction, channel)
end

RecordIOAudioName = function(direction, channel)
    local alias = RecordIOAudioAlias(direction, channel)
    if alias and alias ~= "" then return alias end
    return RecordIOAudioApiName(direction, channel)
end

RecordIOAudioAliasStatus = function(direction, channel, alias, api_name)
    if alias and alias ~= "" then
        if RecordIOAudioNameMatches(api_name, alias) then
            return "Live", C.green, "Alias is confirmed in REAPER's live channel name"
        end
        return "Written", C.amber, "Alias is written to reaper.ini; reopen the audio device or restart REAPER"
    end
    local cleared = io_manager_audio_cleared_aliases[RecordIOAudioClearedKey(direction, channel)]
    if cleared and RecordIOAudioNameMatches(api_name, cleared) then
        return "Pending", C.amber, "Alias was cleared in reaper.ini; reopen the audio device or restart REAPER"
    end
    return "Native", C.text_muted, "No alias is saved for this hardware channel"
end

RecordIOAudioRows = function(page)
    local direction = RecordIOPageDirection(page)
    local alias_map = RecordIOAudioAliasMap(direction, true)
    local n = RecordIOAudioCount(direction, alias_map)
    local rows = {}
    for ch = 0, n - 1 do
        local alias = alias_map["name" .. tostring(ch)] or ""
        local api_name = RecordIOAudioApiName(direction, ch)
        local hw = RecordIOAudioHWName(direction, ch, alias, api_name)
        local exposed = api_name
        if RecordIOAudioNameMatches(exposed, alias, io_manager_audio_cleared_aliases[RecordIOAudioClearedKey(direction, ch)]) then
            exposed = hw
        end
        local status, status_col, status_tip = RecordIOAudioAliasStatus(direction, ch, alias, api_name)
        rows[#rows + 1] = {
            key = "audio:" .. direction .. ":" .. tostring(ch),
            channel = ch,
            alias = alias,
            exposed = exposed,
            hw = hw,
            display = alias ~= "" and alias or exposed,
            status = status,
            status_col = status_col,
            status_tip = status_tip,
            search = (tostring(ch + 1) .. " " .. exposed .. " " .. alias .. " "
                .. hw .. " " .. status):lower(),
            stereo_valid = (ch % 2) == 0 and ch + 1 < n,
        }
    end
    return rows
end

RecordIOMidiCount = function(direction)
    local fn = direction == "out" and r.GetNumMIDIOutputs or r.GetNumMIDIInputs
    if not fn then return 0 end
    local ok, n = pcall(fn)
    if ok then return math.max(0, math.floor(tonumber(n) or 0)) end
    return 0
end

RecordIOMidiUnavailableName = function(name)
    if not name or name == "" then return false end
    local s = tostring(name):lower():gsub("^%s+", ""):gsub("%s+$", "")
    return s:find("not present", 1, true) ~= nil
        or s:find("not found", 1, true) ~= nil
end

RecordIOMidiAvailableName = function(name)
    if name and name ~= "" and not RecordIOMidiUnavailableName(name) then return name end
    return nil
end

RecordIOMidiPrefsMap = function()
    local map = RecordInputIniReadSection(RecordInputMainIniPath(), "REAPER")
    local has_prefs = false
    for key in pairs(map or {}) do
        if key == "midiins" or key == "midiins_h"
            or key == "midiins_x" or key == "midiins_x_h"
            or key == "midiins_all" or key == "midiins_all_h"
            or key == "midiins_all_x" or key == "midiins_all_x_h"
            or key == "midiins_cs" or key == "midiins_cs_h"
            or key == "midiins_cs_x" or key == "midiins_cs_x_h"
            or key == "midiouts" or key == "midiouts_h"
            or key == "midiouts_x" or key == "midiouts_x_h"
        then
            has_prefs = true
            break
        end
    end
    return map, has_prefs
end

RecordIOMidiMaskKey = function(prefix, device)
    device = math.floor(device or -1)
    if device < 0 or device >= 128 then return nil, 0 end
    local bank = math.floor(device / 32)
    local bit = device % 32
    local key = nil
    if bank == 0 then key = prefix
    elseif bank == 1 then key = prefix .. "_h"
    elseif bank == 2 then key = prefix .. "_x"
    elseif bank == 3 then key = prefix .. "_x_h" end
    return key, bit
end

RecordIOMidiMaskBit = function(raw, bit)
    local value = tonumber(raw)
    if not value then return false end
    if value < 0 then value = value + 4294967296 end
    return (math.floor(value / (2 ^ bit)) % 2) == 1
end

RecordIOMidiMaskEnabled = function(pref_map, prefix, device)
    local key, bit = RecordIOMidiMaskKey(prefix, device)
    if not key then return false end
    return RecordIOMidiMaskBit(pref_map and pref_map[key], bit)
end

RecordIOMidiInputEnabled = function(pref_map, has_prefs, device)
    device = math.floor(device or -1)
    if device == 62 then return true end
    if device == 63 or device < 0 or device >= 128 then return false end
    if has_prefs ~= true then return true end
    return RecordIOMidiMaskEnabled(pref_map, "midiins", device)
        or RecordIOMidiMaskEnabled(pref_map, "midiins_all", device)
        or RecordIOMidiMaskEnabled(pref_map, "midiins_cs", device)
end

RecordIOMidiOutputEnabled = function(pref_map, has_prefs, device)
    device = math.floor(device or -1)
    if device < 0 or device >= 128 then return false end
    if has_prefs ~= true then return true end
    return RecordIOMidiMaskEnabled(pref_map, "midiouts", device)
end

RecordIOMidiEndpointEnabled = function(direction, device, pref_map, has_prefs)
    if direction == "out" then
        return RecordIOMidiOutputEnabled(pref_map, has_prefs, device)
    end
    return RecordIOMidiInputEnabled(pref_map, has_prefs, device)
end

RecordIOMidiLiveInfo = function(direction, device)
    device = math.floor(device or -1)
    if direction == "in" and device == 62 then
        return true, true, "Virtual MIDI Keyboard"
    end
    local fn = direction == "out" and r.GetMIDIOutputName or r.GetMIDIInputName
    if not fn or device < 0 then return false, false, nil end
    local ok, rv, got = pcall(fn, device, "")
    if not ok then return false, false, nil end
    local present = rv == true
    local name = nil
    if type(got) == "string" and got ~= "" then name = got end
    if type(rv) == "string" and rv ~= "" then
        name = rv
        present = true
    end
    if RecordIOMidiUnavailableName(name) then return false, false, name end
    return present, present, name
end

RecordIOMidiRows = function(page)
    local direction = RecordIOPageDirection(page)
    local p = RecordIOMidiPrefixes(direction)
    local map = RecordInputIniReadSection(RecordInputResourcePath("reaper-midihw.ini"), "mididevcache")
    local ignore_map = RecordInputIniReadSection(RecordInputResourcePath("reaper-midihw.ini"), "mididevignore")
    local prefs, has_prefs = RecordIOMidiPrefsMap()
    local seen = {}
    local rows = {}
    local function add_device(dev)
        dev = math.floor(dev or -1)
        if dev < 0 or seen[dev] then return end
        local live, _enabled, live_name = RecordIOMidiLiveInfo(direction, dev)
        local enabled = RecordIOMidiEndpointEnabled(direction, dev, prefs, has_prefs)
        local alias = map[p.alias .. tostring(dev)] or ""
        local short_name = map[p.name .. tostring(dev)] or ""
        local original = RecordIOMidiAvailableName(RecordIOMidiDeviceOriginalName(direction, dev))
            or RecordIOMidiAvailableName(map[p.original .. tostring(dev)])
            or RecordIOMidiAvailableName(short_name)
            or RecordIOMidiAvailableName(live_name)
            or ""
        if not live and alias == "" and original == "" and RecordIOMidiAvailableName(short_name) == nil then
            return
        end
        seen[dev] = true
        local display = alias ~= "" and alias
            or (live and RecordIOMidiAvailableName(live_name) or nil)
            or RecordIOMidiAvailableName(short_name)
            or original
        if display == "" then display = original end
        if display == "" then display = (direction == "out" and "MIDI Output " or "MIDI Input ") .. tostring(dev + 1) end
        local ignored_key = RecordIOMidiIgnoreKey(direction, original, ignore_map)
        local status
        if direction == "in" and dev == 62 then
            status = "Built-in"
        elseif ignored_key then
            status = "Ignored"
        elseif not enabled then
            status = "Disabled"
        elseif live then
            status = "Present"
        else
            status = "Missing"
        end
        rows[#rows + 1] = {
            key = "midi:" .. direction .. ":" .. tostring(dev),
            device = dev,
            alias = alias,
            name = display,
            original = original ~= "" and original or display,
            status = status,
            protected = direction == "in" and dev == 62,
            ignored_key = ignored_key,
            search = (display .. " " .. original .. " " .. status .. " " .. tostring(dev)):lower(),
        }
    end

    for dev = 0, RecordIOMidiCount(direction) - 1 do add_device(dev) end
    if direction == "in" then add_device(62) end
    for key in pairs(map) do
        local dev = tonumber(key:match("^" .. p.alias .. "(%d+)$"))
            or tonumber(key:match("^" .. p.name .. "(%d+)$"))
            or tonumber(key:match("^" .. p.original .. "(%d+)$"))
        if not dev then
            local flag_dev = tonumber(key:match("^" .. p.flags .. "(%d+)$"))
            if flag_dev then
                local suffix = tostring(flag_dev)
                if (map[p.alias .. suffix] or "") ~= ""
                    or RecordIOMidiAvailableName(map[p.name .. suffix]) ~= nil
                    or RecordIOMidiAvailableName(map[p.original .. suffix]) ~= nil
                then
                    dev = flag_dev
                end
            end
        end
        if dev then add_device(dev) end
    end
    local ignore_prefix = RecordIOMidiIgnorePrefix(direction)
    for key, value in pairs(ignore_map) do
        if key:match("^" .. ignore_prefix .. "%d+$") then
            local already = false
            for _, row in ipairs(rows) do
                if row.original == value then already = true; break end
            end
            if not already then
                rows[#rows + 1] = {
                    key = "midi:" .. direction .. ":ignored:" .. key,
                    device = nil,
                    device_label = "-",
                    alias = "",
                    name = value,
                    original = value,
                    status = "Ignored",
                    protected = false,
                    ignored_key = key,
                    search = (value .. " ignored"):lower(),
                }
            end
        end
    end
    table.sort(rows, function(a, b)
        local ad = a.device ~= nil and a.device or 100000
        local bd = b.device ~= nil and b.device or 100000
        if ad == bd then return (a.name or "") < (b.name or "") end
        return ad < bd
    end)
    return rows
end

RecordIOStartEdit = function(cell_key, value, commit, opts)
    opts = opts or {}
    io_manager_edit = {
        key = cell_key,
        buf = value or "",
        orig = value or "",
        commit = commit,
        focus = false,
        frames = 0,
        cancel = false,
        seeded = opts.seeded == true,
    }
end

RecordIOCommitEdit = function()
    local edit = io_manager_edit
    if not edit then return end
    if edit.commit and not edit.cancel then
        local changed = (edit.buf or "") ~= (edit.orig or "")
        if changed or not edit.seeded then edit.commit(edit.buf or "") end
    end
    io_manager_edit = nil
end

RecordIOCancelEdit = function()
    io_manager_edit = nil
end

RecordInputOpenManager = function(track, value)
    local info = value ~= nil and RecordInputInfo(value) or nil
    io_manager_open = true
    io_manager_first_open = true
    io_manager_filter = io_manager_filter or ""
    io_manager_edit = nil
    io_manager_scroll_key = nil
    io_manager_focus_key = nil

    if not info then
        io_manager_page = "audio_in"
        return
    end

    if info.kind == "mono" or info.kind == "stereo" or info.kind == "multichannel" then
        local ch = info.channel or 0
        io_manager_page = "audio_in"
        io_manager_scroll_key = "audio:in:" .. tostring(ch)
        io_manager_focus_key = io_manager_scroll_key .. ":alias"
    elseif info.kind == "midi" then
        io_manager_page = "midi_in"
        if info.device and info.device ~= 62 and info.device ~= 63 then
            io_manager_scroll_key = "midi:in:" .. tostring(info.device)
            io_manager_focus_key = io_manager_scroll_key .. ":alias"
        end
    else
        io_manager_page = "midi_in"
    end
end

RecordInputEditAlias = function(value, track, clear)
    local info = RecordInputInfo(value)
    if not RecordInputCanAliasInfo(info) then return end

    if info.kind == "midi" then
        if clear then
            RecordInputSetMidiAlias(info.device, "")
            return
        end
        RecordInputOpenManager(track, value)
        return
    end

    local channel = info.channel or 0
    if info.kind == "stereo" then
        if clear then
            RecordInputSetAudioAlias(channel, "")
            RecordInputSetAudioAlias(channel + 1, "")
            return
        end
        RecordInputOpenManager(track, value)
    else
        if clear then
            RecordInputSetAudioAlias(channel, "")
            return
        end
        RecordInputOpenManager(track, value)
    end
end

RecordInputOpenContext = function(track, value)
    local info = RecordInputInfo(value)
    local key = RecordInputFavoriteKeyForValue(value)
    record_input_context = {
        value = value,
        key = key,
        info = info,
        fav_idx = key and RecordInputFavoriteIndex(key) or nil,
    }
    r.ImGui_OpenPopup(ctx, "##recinput_ctx")
    nav_rclick_consumed = true
end

RecordInputContextPopup = function(track, styled)
    if styled then PushPopupStyle() end
    if r.ImGui_BeginPopup(ctx, "##recinput_ctx") then
        local item = record_input_context
        if item then
            local has_fav = item.key and RecordInputFavoriteIndex(item.key)
            if item.key then
                if has_fav then
                    if r.ImGui_MenuItem(ctx, "Remove Favorite") then
                        RecordInputFavoriteRemove(item.key)
                    end
                    local idx = RecordInputFavoriteIndex(item.key)
                    if idx and RecordInputFavoriteCanMove(item.key, -1)
                        and r.ImGui_MenuItem(ctx, "Move Favorite Up")
                    then
                        RecordInputFavoriteMove(item.key, -1)
                    end
                    idx = RecordInputFavoriteIndex(item.key)
                    if idx and RecordInputFavoriteCanMove(item.key, 1)
                        and r.ImGui_MenuItem(ctx, "Move Favorite Down")
                    then
                        RecordInputFavoriteMove(item.key, 1)
                    end
                else
                    if r.ImGui_MenuItem(ctx, "Add Favorite") then
                        RecordInputFavoriteAdd(item.key)
                    end
                end
            end

            if item.key or RecordInputCanAliasInfo(item.info)
                or (item.info and (item.info.kind == "none"
                    or (item.info.kind == "midi" and item.info.device == 63)))
            then
                if item.key then r.ImGui_Separator(ctx) end
                if r.ImGui_MenuItem(ctx, "Edit aliases / favorites") then
                    RecordInputOpenManager(track, item.value)
                end
            end
        end
        r.ImGui_EndPopup(ctx)
    end
    if styled then PopPopupStyle() end
end

RecordInputActivityLevel = function(input_id)
    if not r.GetInputActivityLevel then return 0 end
    local ok, level = pcall(r.GetInputActivityLevel, math.floor(input_id or -1))
    if not ok then return 0 end
    return tonumber(level) or 0
end

RecordInputAudioActivityAmp = function(input_id)
    local raw = RecordInputActivityLevel(input_id)
    -- Some REAPER builds/devices report audio activity as negative dBFS,
    -- while MIDI activity and some audio paths report positive values.
    if raw < 0 then
        if raw <= -150 then return 0 end
        return 10 ^ (raw / 20)
    end
    return raw
end

RecordInputAudioActivityLevel = function(channel, stereo, nchan)
    channel = math.floor(channel or 0)
    if nchan and nchan > 1 then
        local level = 0
        for i = 0, math.max(1, math.floor(nchan)) - 1 do
            level = math.max(level, RecordInputAudioActivityAmp(channel + i))
        end
        return level
    end
    local level = RecordInputAudioActivityAmp(channel)
    if stereo then
        level = math.max(level, RecordInputAudioActivityAmp(channel | 1024))
        level = math.max(level, RecordInputAudioActivityAmp(channel + 1))
    end
    return level
end

RecordInputMidiActivityLevel = function(device)
    device = math.floor(device or 63)
    local level = RecordInputActivityLevel(4096 + device * 32)
    if device == 63 then
        level = math.max(level, RecordInputActivityLevel(4096 + 62 * 32))
        local num_midi = 0
        if r.GetNumMIDIInputs then
            local ok, n = pcall(r.GetNumMIDIInputs)
            if ok then num_midi = math.max(0, math.floor(tonumber(n) or 0)) end
        end
        for dev = 0, num_midi - 1 do
            level = math.max(level, RecordInputActivityLevel(4096 + dev * 32))
        end
    end
    return level
end

RecordInputNormalizeMidiLevel = function(level)
    level = tonumber(level) or 0
    if level <= 0 then return 0 end
    if level > 1 and level <= 127 then return math.min(1, level / 127) end
    return math.min(1, level)
end

RecordInputMidiLevelFromMessage = function(buf)
    if type(buf) ~= "string" or #buf == 0 then return 0 end
    local status = buf:byte(1) or 0
    local event = status & 0xF0
    local data1 = buf:byte(2) or 0
    local data2 = buf:byte(3) or 0

    if event == 0x90 then
        return data2 > 0 and RecordInputNormalizeMidiLevel(data2) or 0
    elseif event == 0x80 then
        return 0
    elseif event == 0xA0 or event == 0xB0 then
        return RecordInputNormalizeMidiLevel(data2)
    elseif event == 0xC0 or event == 0xD0 then
        return RecordInputNormalizeMidiLevel(data1)
    elseif event == 0xE0 then
        local bend = data1 + data2 * 128
        return math.min(1, math.abs(bend - 8192) / 8192)
    end

    if #buf >= 3 then return RecordInputNormalizeMidiLevel(math.max(data1, data2)) end
    if #buf >= 2 then return RecordInputNormalizeMidiLevel(data1) end
    return 1
end

RecordInputMidiStoreRecentLevel = function(key, until_time, level)
    if not key or key == "" then return end
    local prev_until = record_input_midi_recent[key] or 0
    local prev_level = (prev_until >= r.time_precise()) and (record_input_midi_recent_level[key] or 0) or 0
    record_input_midi_recent[key] = until_time
    record_input_midi_recent_level[key] = math.max(prev_level, level or 0)
end

RecordInputMidiFlashLevel = function(key, level)
    local now = r.time_precise()
    level = RecordInputNormalizeMidiLevel(level)
    if level > 0 then
        record_input_midi_flash[key] = now + 0.10
        record_input_midi_flash_level[key] = level
    end
    if (record_input_midi_flash[key] or 0) >= now then
        return record_input_midi_flash_level[key] or 1
    end
    return 0
end

RecordInputMidiFlashActive = function(key, level)
    return RecordInputMidiFlashLevel(key, level) > 0
end

RecordInputPollRecentMidi = function()
    if not r.MIDI_GetRecentInputEvent then return end
    local ok, seq, buf, _ts, dev_idx = pcall(r.MIDI_GetRecentInputEvent, 0)
    if not ok or not seq or seq == 0 or seq == record_input_midi_recent_seq then return end
    local newest_seq = seq
    local now = r.time_precise()
    local until_time = now + 0.12
    local idx = 0

    while ok and seq and seq ~= 0 and seq ~= record_input_midi_recent_seq do
        local level = RecordInputMidiLevelFromMessage(buf)
        if level > 0 then
            dev_idx = math.floor(tonumber(dev_idx) or -1)
            local dev = dev_idx & 0xFFFF
            local channel = 0
            if type(buf) == "string" and #buf > 0 then
                local status = buf:byte(1) or 0
                if (status & 0xF0) ~= 0xF0 then channel = (status & 0x0F) + 1 end
            end
            RecordInputMidiStoreRecentLevel("any", until_time, level)
            RecordInputMidiStoreRecentLevel("dev:" .. tostring(dev), until_time, level)
            if channel > 0 then
                RecordInputMidiStoreRecentLevel("ch:" .. tostring(channel), until_time, level)
                RecordInputMidiStoreRecentLevel("devch:" .. tostring(dev) .. ":" .. tostring(channel), until_time, level)
            end
        end
        idx = idx + 1
        ok, seq, buf, _ts, dev_idx = pcall(r.MIDI_GetRecentInputEvent, idx)
    end

    record_input_midi_recent_seq = newest_seq
end

RecordInputRecentMidiLevel = function(device, channel)
    RecordInputPollRecentMidi()
    local now = r.time_precise()
    device = math.floor(device or 63)
    channel = math.floor(channel or 0)
    local keys
    if device == 63 then
        keys = channel > 0 and { "ch:" .. tostring(channel) } or { "any" }
    else
        keys = channel > 0
            and { "devch:" .. tostring(device) .. ":" .. tostring(channel) }
            or { "dev:" .. tostring(device) }
    end
    local level = 0
    for _, key in ipairs(keys) do
        if (record_input_midi_recent[key] or 0) >= now then
            level = math.max(level, record_input_midi_recent_level[key] or 0)
        end
    end
    return level
end

RecordInputRecentMidiActive = function(device, channel)
    return RecordInputRecentMidiLevel(device, channel) > 0
end

RecordInputMidiMeterLevel = function(meter, key, decay)
    meter = meter or {}
    local device = meter.device or 63
    local channel = meter.channel or 0
    key = key or ("midi-meter:" .. tostring(device) .. ":" .. tostring(channel))
    local raw = math.max(
        RecordInputRecentMidiLevel(device, channel),
        RecordInputMidiFlashLevel(key, RecordInputMidiActivityLevel(device))
    )
    return SmoothPeak(record_input_activity_peak, key, raw, decay or 0.80)
end

RecordInputMenuMeterDiameter = function()
    return math.max(4, S(10)) -- 16px Retina target per PK retina-px convention.
end

RecordInputCurrentMeterDiameter = function()
    return math.max(4, S(12.5)) -- 20px Retina target per PK retina-px convention.
end

RecordInputArmedGap = function()
    return S(11.25) -- 18px Retina gap.
end

RecordInputMeterHeight = function()
    return S(11.25) -- 18px Retina height.
end

DrawRecordInputMenuMeter = function(dl, meter, cx, cy, dot_r)
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, dot_r, C.input_meter_bg, 24)
    if not meter then return end

    if meter.kind == "audio" then
        local raw = RecordInputAudioActivityLevel(meter.channel, meter.stereo, meter.nchan)
        local key = "audio:" .. tostring(meter.nchan or (meter.stereo and "st" or "mo")) .. ":" .. tostring(meter.channel or 0)
        local peak = SmoothPeak(record_input_activity_peak, key, raw, 0.72)
        if peak <= 0.00001 then return end
        local db = 20 * math.log(math.max(peak, 0.00001), 10)
        local base_col = MeterColor(db)
        local alpha = math.min(1.0, peak ^ 0.4)
        local col = (base_col & 0xFFFFFF00) | math.floor(alpha * 255 + 0.5)
        r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, dot_r, col, 24)
    elseif meter.kind == "midi" then
        local device = meter.device or 63
        local channel = meter.channel or 0
        local key = "midi:" .. tostring(device) .. ":" .. tostring(channel)
        if RecordInputMidiMeterLevel(meter, key, 0.72) > 0.01 then
            r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, dot_r, C.amber, 24)
        end
    end
end

DrawRecordInputMidiSegmentMeter = function(dl, meter, x1, y1, x2, y2)
    local h = y2 - y1
    local w = x2 - x1
    if w <= 0 or h <= 0 then return end

    local dot_d = h
    local dot_r = dot_d * 0.5
    local gap = math.max(1, dot_d * 0.45)
    local count = math.max(1, math.floor((w + gap) / (dot_d + gap)))
    local total_w = count * dot_d + (count - 1) * gap
    local start_x = x1 + math.max(0, (w - total_w) * 0.5)
    local cy = y1 + h * 0.5
    local key = "midi-row:" .. tostring(meter.device or 63) .. ":" .. tostring(meter.channel or 0)
    local level = RecordInputMidiMeterLevel(meter, key, 0.78)
    local filled = level > 0.01 and math.max(1, math.min(count, math.ceil(level * count))) or 0

    for i = 1, count do
        local cx = start_x + dot_r + (i - 1) * (dot_d + gap)
        local col = i <= filled and C.amber or C.input_meter_bg
        r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, dot_r, col, 24)
    end
end

DrawRecordInputActivityMeter = function(dl, meter, x1, y1, x2, y2)
    local h = y2 - y1
    local w = x2 - x1
    if w <= 0 or h <= 0 then return end
    local rds = h / 2
    if not meter then
        r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, C.vol_slider_bg, rds)
        return
    end

    if meter.kind == "audio" then
        r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, C.vol_slider_bg, rds)
        local raw = RecordInputAudioActivityLevel(meter.channel, meter.stereo, meter.nchan)
        local key = "audio-row:" .. tostring(meter.nchan or (meter.stereo and "st" or "mo")) .. ":" .. tostring(meter.channel or 0)
        local peak = SmoothPeak(record_input_activity_peak, key, raw, 0.85)
        if peak <= 0.00001 then return end
        local fill = math.min(1, peak ^ 0.25)
        local meter_right = x1 + math.floor(fill * w)
        if meter_right <= x1 then return end
        local db = 20 * math.log(math.max(peak, 0.00001), 10)
        r.ImGui_DrawList_PushClipRect(dl, x1, y1, meter_right, y2, true)
        r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, MeterColor(db), rds)
        r.ImGui_DrawList_PopClipRect(dl)
    elseif meter.kind == "midi" then
        DrawRecordInputMidiSegmentMeter(dl, meter, x1, y1, x2, y2)
    end
end

RecordInputMeterForValue = function(value, track)
    local info = RecordInputInfo(value)
    if info.kind == "mono" then
        return { kind = "audio", channel = info.channel, stereo = false }
    elseif info.kind == "stereo" then
        return { kind = "audio", channel = info.channel, stereo = true }
    elseif info.kind == "multichannel" then
        local nchan = track and math.floor(r.GetMediaTrackInfo_Value(track, "I_NCHAN") or 2) or 2
        return { kind = "audio", channel = info.channel, nchan = math.max(1, nchan) }
    elseif info.kind == "midi" then
        return { kind = "midi", device = info.device or 63, channel = info.channel or 0 }
    end
    return nil
end

RecordInputRowHeight = function()
    return S(30) -- 48px Retina target per PK retina-px convention.
end

RecordInputRowGap = function()
    return RecordInputArmedGap()
end

RecordInputAudioName = function(channel)
    return RecordIOAudioName("in", channel)
end

RecordInputMidiDeviceName = function(device)
    if device == 63 then return "All MIDI Inputs" end
    if device == 62 then return "Virtual MIDI Keyboard" end

    local name = nil
    if r.GetMIDIInputName then
        local ok, rv, got = pcall(r.GetMIDIInputName, device, "")
        if ok then
            if type(rv) == "boolean" and rv and type(got) == "string" and got ~= "" then
                name = got
            elseif type(rv) == "string" and rv ~= "" then
                name = rv
            end
        end
    end
    return name or ("MIDI Input " .. tostring(device + 1))
end

RecordInputInfo = function(value)
    value = math.floor(value or -1)
    if value < 0 then return { kind = "none", value = value } end
    if (value & 4096) ~= 0 then
        return {
            kind = "midi",
            value = value,
            channel = value & 31,
            device = (value >> 5) & 127,
        }
    end

    local channel = value & 1023
    if (value & 2048) ~= 0 then
        return { kind = "multichannel", value = value, channel = channel }
    end
    if (value & 1024) ~= 0 then
        return { kind = "stereo", value = value, channel = channel }
    end
    return { kind = "mono", value = value, channel = channel }
end

RecordInputMidiValue = function(device, channel)
    return 4096 + ((device or 63) << 5) + (channel or 0)
end

RecordInputAllMidiValue = function()
    return RecordInputMidiValue(63, 0)
end

RecordInputMidiLabel = function(device, channel)
    local ch = channel == 0 and "" or (" / Channel " .. tostring(channel))
    return "MIDI: " .. RecordInputMidiDeviceName(device) .. ch
end

RecordInputValueLabel = function(value, track)
    local info = RecordInputInfo(value)
    if info.kind == "none" then return "None" end

    if info.kind == "midi" then
        if info.device == 63 and info.channel == 0 then return "All MIDI Inputs" end
        return RecordInputMidiLabel(info.device, info.channel)
    end

    local channel = info.channel or 0
    if info.kind == "multichannel" then
        local track_ch = track and math.floor(r.GetMediaTrackInfo_Value(track, "I_NCHAN") or 2) or 2
        return "Multichannel (" .. tostring(track_ch) .. "ch): " .. RecordInputAudioName(channel)
    end
    if info.kind == "stereo" then
        return "Stereo: " .. RecordInputAudioName(channel) .. " / " .. RecordInputAudioName(channel + 1)
    end
    return "Mono: " .. RecordInputAudioName(channel)
end

RecordInputNumAudioInputs = function()
    local num_audio = 0
    if r.GetNumAudioInputs then
        local ok, n = pcall(r.GetNumAudioInputs)
        if ok then num_audio = math.max(0, math.floor(tonumber(n) or 0)) end
    end
    return num_audio
end

RecordInputBuildMonoItems = function()
    local items = {}
    local num_audio = RecordInputNumAudioInputs()
    for i = 0, num_audio - 1 do
        items[#items + 1] = { label = RecordInputAudioName(i), value = i, channel = i }
    end
    return items
end

RecordInputBuildStereoItems = function()
    local items = {}
    local num_audio = RecordInputNumAudioInputs()
    for i = 0, num_audio - 2, 2 do
        items[#items + 1] = {
            label = RecordInputAudioName(i) .. " / " .. RecordInputAudioName(i + 1),
            value = 1024 + i,
            channel = i,
        }
    end
    return items
end

RecordInputMidiDevices = function(include_all)
    local items = {}
    if include_all then
        items[#items + 1] = { label = "All MIDI Inputs", device = 63, value = RecordInputAllMidiValue() }
    end
    items[#items + 1] = { label = "Virtual MIDI Keyboard", device = 62 }
    local prefs, has_prefs = RecordIOMidiPrefsMap()
    local num_midi = 0
    if r.GetNumMIDIInputs then
        local ok, n = pcall(r.GetNumMIDIInputs)
        if ok then num_midi = math.max(0, math.floor(tonumber(n) or 0)) end
    end
    for dev = 0, num_midi - 1 do
        local include = true
        local label = nil
        if r.GetMIDIInputName then
            local ok, rv, got = pcall(r.GetMIDIInputName, dev, "")
            include = ok and rv == true and RecordIOMidiInputEnabled(prefs, has_prefs, dev)
            if include and type(got) == "string" and got ~= "" then label = got end
        end
        if include then
            items[#items + 1] = { label = label or RecordInputMidiDeviceName(dev), device = dev }
        end
    end
    return items
end

RecordInputBuildList = function(track)
    local items = {}
    for _, it in ipairs(RecordInputBuildMonoItems()) do
        items[#items + 1] = { label = "Mono: " .. it.label, value = it.value }
    end
    for _, it in ipairs(RecordInputBuildStereoItems()) do
        items[#items + 1] = { label = "Stereo: " .. it.label, value = it.value }
    end
    items[#items + 1] = { label = "All MIDI Inputs", value = RecordInputAllMidiValue() }
    for _, it in ipairs(RecordInputMidiDevices(false)) do
        items[#items + 1] = { label = "MIDI: " .. it.label, value = RecordInputMidiValue(it.device, 0) }
    end
    items[#items + 1] = { label = "None", value = -1 }
    return items
end

RecordInputSet = function(track, value)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    value = math.floor(value or -1)
    local cur = math.floor(r.GetMediaTrackInfo_Value(track, "I_RECINPUT") or -1)
    if cur == value then return end
    r.Undo_BeginBlock()
    r.SetMediaTrackInfo_Value(track, "I_RECINPUT", value)
    r.Undo_EndBlock("Reflex: Record input", -1)
end

RecordInputStep = function(track, dir)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    local cur = math.floor(r.GetMediaTrackInfo_Value(track, "I_RECINPUT") or -1)
    local info = RecordInputInfo(cur)
    local items = {}
    if info.kind == "mono" then
        items = RecordInputBuildMonoItems()
    elseif info.kind == "stereo" then
        items = RecordInputBuildStereoItems()
    elseif info.kind == "midi" then
        local source_channel = info.channel or 0
        for _, it in ipairs(RecordInputMidiDevices(true)) do
            items[#items + 1] = {
                label = it.label,
                device = it.device,
                value = it.device == 63 and RecordInputAllMidiValue()
                    or RecordInputMidiValue(it.device, source_channel),
            }
        end
    else
        return
    end
    if #items == 0 then return end
    local idx = nil
    for i, it in ipairs(items) do
        if info.kind == "midi" then
            if it.device == info.device then idx = i; break end
        elseif it.value == cur then
            idx = i; break
        end
    end
    idx = idx or 1
    local next_idx = ((idx - 1 + dir) % #items) + 1
    RecordInputSet(track, items[next_idx].value)
end

RecordInputClipLabel = function(label, max_w)
    if not label or label == "" then return "" end
    if max_w <= 0 then return "" end
    local tw = r.ImGui_CalcTextSize(ctx, label)
    if tw <= max_w then return label end
    local ellipsis = "\xE2\x80\xA6"
    local ew = r.ImGui_CalcTextSize(ctx, ellipsis)
    if ew > max_w then return "" end
    local display = label
    while tw + ew > max_w and #display > 0 do
        display = Utf8DropLast(display)
        tw = r.ImGui_CalcTextSize(ctx, display)
    end
    return display .. ellipsis
end

RecordInputDesiredWidth = function(items, fallback_label, pad_x, chev_gap, chev_w)
    local max_label_w = r.ImGui_CalcTextSize(ctx, fallback_label or "")
    for _, it in ipairs(items or {}) do
        local tw = r.ImGui_CalcTextSize(ctx, it.label or "")
        if tw > max_label_w then max_label_w = tw end
    end
    return max_label_w + pad_x * 2 + chev_gap + chev_w
end

RecordInputMenuLabel = function(label, selected)
    return label
end

RecordInputMenuItem = function(track, label, value, current_value, meter, opts)
    opts = opts or {}
    local selected = current_value ~= nil and value == current_value
    local pad_x = S(8)
    local pad_y = S(4)
    local meter_d = meter and RecordInputMenuMeterDiameter() or 0
    local meter_left = meter and meter.align ~= "right"
    local meter_right = meter and meter.align == "right"
    local meter_box_w = meter_left and math.max(meter_d, S(12)) or 0
    local meter_gap = meter_left and S(6) or 0
    local meter_right_w = meter_right and (math.max(meter_d, S(12)) + S(6)) or 0
    local label_pad_x = meter_right and 0 or pad_x
    local text_w = r.ImGui_CalcTextSize(ctx, label)
    local line_h = r.ImGui_GetTextLineHeight(ctx)
    local row_w = text_w + label_pad_x + pad_x + meter_box_w + meter_gap + meter_right_w
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    if avail_w and avail_w > 1 then row_w = math.max(row_w, avail_w) end
    local row_h = math.max(S(18), line_h + pad_y * 2)
    local flags = 0
    if opts.no_auto_close then
        flags = r.ImGui_SelectableFlags_NoAutoClosePopups
            and r.ImGui_SelectableFlags_NoAutoClosePopups()
            or 1
    end

    r.ImGui_PushID(ctx, tostring(value) .. ":" .. label)
    local clicked = r.ImGui_Selectable(ctx, "##recinput_item", false, flags, row_w, row_h)
    local rclicked = r.ImGui_IsItemClicked(ctx, 1)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local tx = x1 + label_pad_x
    local cy = (y1 + y2) / 2
    if meter then
        local dot_r = meter_d / 2
        local dot_nudge = S(2.5) -- 4px Retina manual optical correction.
        if meter.align == "right" then
            DrawRecordInputMenuMeter(dl, meter, x2 - pad_x - dot_r - dot_nudge, cy - dot_nudge, dot_r)
        else
            DrawRecordInputMenuMeter(dl, meter, tx + meter_box_w - dot_r - dot_nudge, cy - dot_nudge, dot_r)
            tx = tx + meter_box_w + meter_gap
        end
    end
    local ty = y1 + Round((row_h - line_h) / 2)
    local txt_col = selected and C.cmp_b or (hovered and 0xFFFFFFFF or (opts.text_col or C.text))
    r.ImGui_DrawList_AddText(dl, tx, ty, txt_col, label)
    r.ImGui_PopID(ctx)

    if clicked then RecordInputSet(track, value) end
    if rclicked then RecordInputOpenContext(track, value) end
    RecordInputContextPopup(track, false)
end

RecordInputNativeMenuItem = function(track, label, value, current_value, meter)
    local selected = current_value ~= nil and value == current_value
    if selected then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.cmp_b) end
    local clicked = r.ImGui_MenuItem(ctx, label, "", false)
    if selected then r.ImGui_PopStyleColor(ctx, 1) end
    local rclicked = r.ImGui_IsItemClicked(ctx, 1)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    if meter then
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local dot_r = RecordInputMenuMeterDiameter() / 2
        local dot_nudge = S(2.5) -- Match popup input meter optical correction.
        DrawRecordInputMenuMeter(dl, meter, x2 - S(8) - dot_r - dot_nudge + S(6.875),
            (y1 + y2) / 2 - dot_nudge + S(3.75), dot_r)
    end
    if clicked then RecordInputSet(track, value) end
    if rclicked then RecordInputOpenContext(track, value) end
    RecordInputContextPopup(track, false)
end

RecordInputPreferredMidiDevice = function(info)
    if info and info.kind == "midi" and info.device and info.device ~= 63 then
        return info.device
    end
    local devices = RecordInputMidiDevices(false)
    return (devices[1] and devices[1].device) or 62
end

RecordInputDrawSourceChannelMenu = function(track, device, info)
    if r.ImGui_BeginMenu(ctx, "Source channel") then
        local current_device = info and info.device
        local current_channel = (info and info.kind == "midi" and info.channel) or 0
        RecordInputMenuItem(track, "Source Channel", RecordInputMidiValue(device, 0),
            current_device == device and RecordInputMidiValue(device, current_channel) or nil,
            nil, { no_auto_close = true })
        for ch = 1, 16 do
            RecordInputMenuItem(track, "Channel " .. tostring(ch), RecordInputMidiValue(device, ch),
                current_device == device and RecordInputMidiValue(device, current_channel) or nil,
                nil, { no_auto_close = true })
        end
        r.ImGui_EndMenu(ctx)
    end
end

RecordInputPopup = function(track, popup_id, current_value)
    PushPopupStyle()
    if r.ImGui_BeginPopup(ctx, popup_id) then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
        local fp = PushFont(GetSteppedFont(UI.font_fx))
        local info = RecordInputInfo(current_value)
        local favorite_items = RecordInputFavoriteItems(track)

        if #favorite_items > 0 then
            for _, fav in ipairs(favorite_items) do
                RecordInputMenuItem(track, fav.label, fav.value, current_value, fav.meter,
                    { text_col = fav.label_col })
            end
            r.ImGui_Separator(ctx)
        end

        if r.ImGui_BeginMenu(ctx, RecordInputMenuLabel("Mono", info.kind == "mono")) then
            for _, it in ipairs(RecordInputBuildMonoItems()) do
                RecordInputMenuItem(track, it.label, it.value, current_value,
                    { kind = "audio", channel = it.channel, stereo = false })
            end
            r.ImGui_EndMenu(ctx)
        end

        if r.ImGui_BeginMenu(ctx, RecordInputMenuLabel("Stereo", info.kind == "stereo")) then
            for _, it in ipairs(RecordInputBuildStereoItems()) do
                RecordInputMenuItem(track, it.label, it.value, current_value,
                    { kind = "audio", channel = it.channel, stereo = true })
            end
            r.ImGui_EndMenu(ctx)
        end

        if r.ImGui_BeginMenu(ctx, RecordInputMenuLabel("MIDI", info.kind == "midi" and info.device ~= 63)) then
            local preserve_channel = info.kind == "midi" and (info.channel or 0) or 0
            local midi_devices = RecordInputMidiDevices(false)
            for _, it in ipairs(midi_devices) do
                RecordInputMenuItem(track, it.label, RecordInputMidiValue(it.device, preserve_channel),
                    info.device == it.device and RecordInputMidiValue(it.device, preserve_channel) or nil,
                    { kind = "midi", device = it.device })
            end
            if #midi_devices > 0 then
                r.ImGui_Separator(ctx)
                RecordInputDrawSourceChannelMenu(track, RecordInputPreferredMidiDevice(info), info)
            end
            r.ImGui_EndMenu(ctx)
        end

        RecordInputNativeMenuItem(track, "All MIDI Inputs", RecordInputAllMidiValue(), current_value,
            { kind = "midi", device = 63 })
        RecordInputNativeMenuItem(track, "None", -1, current_value)
        RecordInputContextPopup(track, false)
        PopFont(fp)
        r.ImGui_PopStyleColor(ctx, 1)
        r.ImGui_EndPopup(ctx)
    end
    PopPopupStyle()
end


end

return ReflexInstallIOCore
