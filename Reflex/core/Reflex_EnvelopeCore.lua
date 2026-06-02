-- @noindex
-- Reflex envelope core module.
-- Installs inspector envelope cache, alias, visibility, and formatting helpers.

ReflexInstallEnvelopeCore = function(deps)
    local r = deps.r
    local C = deps.colors
    local getFxList = deps.get_fx_list

    -- Envelope alias system (ProjExtState).
    ENV_ALIAS_SECTION = deps.env_alias_section or "reflex_env_alias"

    -- Envelope cache (rebuilt once per frame, invalidated on envelope changes).
    -- Avoids repeated GetEnvelopeStateChunk calls within a single frame.
    insp_env_cache = nil  -- { track, entries, fx_env_count, by_name, has_any_active }
    insp_env_cache_dirty = true

    InspStripName = function(name)
        name = (name:gsub("^%u+%d*%a*:%s*", ""))
        name = (name:gsub("%s*%(.*%)%s*$", ""))
        name = (name:gsub("%s*%[.*%]%s*$", ""))
        return name
    end

    InspGetEnvAlias = function(env_name, fx_idx)
        local key = (fx_idx and fx_idx >= 0) and (fx_idx .. "|" .. env_name) or env_name
        local rv, val = r.GetProjExtState(0, ENV_ALIAS_SECTION, key)
        if rv > 0 and val ~= "" then return val end
        return nil
    end

    InspSetEnvAlias = function(env_name, fx_idx, alias)
        local key = (fx_idx and fx_idx >= 0) and (fx_idx .. "|" .. env_name) or env_name
        if alias and alias ~= "" then
            r.SetProjExtState(0, ENV_ALIAS_SECTION, key, alias)
        else
            r.SetProjExtState(0, ENV_ALIAS_SECTION, key, "")
        end
    end

    InspCountFXEnvelopes = function(track, fx_idx)
        if insp_env_cache and insp_env_cache.track == track and not insp_env_cache_dirty then
            return insp_env_cache.fx_env_count[fx_idx] or 0
        end
        local count = 0
        for e = 0, r.CountTrackEnvelopes(track) - 1 do
            local env = r.GetTrackEnvelope(track, e)
            if env then
                local _, fi = r.Envelope_GetParentTrack(env)
                if fi == fx_idx then count = count + 1 end
            end
        end
        return count
    end

    InspGetFXEnvelopeDetails = function(track, fx_idx)
        if insp_env_cache and insp_env_cache.track == track and not insp_env_cache_dirty then
            local details = {}
            for _, e in ipairs(insp_env_cache.entries) do
                if e.fx_idx == fx_idx then
                    details[#details + 1] = { env = e.env, name = e.name, visible = e.visible, bypassed = e.bypassed, fx_idx = e.fx_idx }
                end
            end
            return details
        end
        local details = {}
        for e = 0, r.CountTrackEnvelopes(track) - 1 do
            local env = r.GetTrackEnvelope(track, e)
            if env then
                local _, fi = r.Envelope_GetParentTrack(env)
                if fi == fx_idx then
                    local _, ename = r.GetEnvelopeName(env)
                    local _, chunk = r.GetEnvelopeStateChunk(env, "", false)
                    local vis = chunk and chunk:match("VIS%s+1") ~= nil
                    local byp = chunk and chunk:match("ACT%s+0") ~= nil
                    details[#details + 1] = { env = env, name = ename or "?", visible = vis, bypassed = byp, fx_idx = fx_idx }
                end
            end
        end
        return details
    end

    InspGetAllTrackEnvelopeDetails = function(track)
        if insp_env_cache and insp_env_cache.track == track and not insp_env_cache_dirty then
            local details = {}
            for _, e in ipairs(insp_env_cache.entries) do
                if not e.skip_detail then
                    details[#details + 1] = { env = e.env, name = e.name, visible = e.visible, fx_idx = e.fx_idx, bypassed = e.bypassed }
                end
            end
            return details
        end
        local details = {}
        for e = 0, r.CountTrackEnvelopes(track) - 1 do
            local env = r.GetTrackEnvelope(track, e)
            if env then
                local _, fi = r.Envelope_GetParentTrack(env)
                local _, ename = r.GetEnvelopeName(env)
                local _, chunk = r.GetEnvelopeStateChunk(env, "", false)
                local vis = chunk and chunk:match("VIS%s+1") ~= nil
                local act = chunk and chunk:match("ACT%s+(%d+)") or "1"
                local byp = act == "0"
                -- Skip deactivated track-level envelopes (REAPER's intelligent removal).
                local is_track_level = (fi or -1) < 0
                if is_track_level and act == "0" and not vis then
                    -- Deactivated + hidden = intelligently removed, skip.
                else
                    details[#details + 1] = { env = env, name = ename or "?", visible = vis, fx_idx = fi or -1, bypassed = byp }
                end
            end
        end
        return details
    end

    InspSetEnvelopeVisible = function(env, visible)
        if not env or not r.ValidatePtr(env, "TrackEnvelope*") then return end
        local v = visible and "1" or "0"
        local _, chunk = r.GetEnvelopeStateChunk(env, "", false)
        if chunk then
            chunk = (chunk:gsub("(VIS%s+)%d", "%1" .. v))
            r.SetEnvelopeStateChunk(env, chunk, false)
            InspInvalidateEnvCache()
            r.TrackList_AdjustWindows(false)
            r.UpdateArrange()
        end
    end

    InspSetEnvelopeVisibleRaw = function(env, visible)
        if not env or not r.ValidatePtr(env, "TrackEnvelope*") then return end
        local v = visible and "1" or "0"
        local _, chunk = r.GetEnvelopeStateChunk(env, "", false)
        if chunk then
            chunk = (chunk:gsub("(VIS%s+)%d", "%1" .. v))
            r.SetEnvelopeStateChunk(env, chunk, false)
            InspInvalidateEnvCache()
        end
    end

    InspBuildEnvCache = function(track)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then
            insp_env_cache = nil; return
        end
        local entries = {}
        local fx_env_count = {}
        local by_name = {}
        local has_any_active = false
        local total_env_ct = r.CountTrackEnvelopes(track)
        for e = 0, total_env_ct - 1 do
            local env = r.GetTrackEnvelope(track, e)
            if env then
                local _, fi = r.Envelope_GetParentTrack(env)
                local _, ename = r.GetEnvelopeName(env)
                local _, chunk = r.GetEnvelopeStateChunk(env, "", false)
                local act = chunk and (chunk:match("ACT%s+(%d+)") or "1") or "1"
                local vis = chunk and chunk:match("VIS%s+1") ~= nil or false
                local byp = act == "0"
                local is_track_level = (fi or -1) < 0
                fi = fi or -1
                -- Count FX envelopes.
                if fi >= 0 then fx_env_count[fi] = (fx_env_count[fi] or 0) + 1 end
                -- Track-level deactivated+hidden = intelligently removed, skip from details.
                local skip_detail = is_track_level and act == "0" and not vis
                if not skip_detail then has_any_active = true end
                entries[#entries + 1] = {
                    env = env, name = ename or "?", fx_idx = fi,
                    act = act, visible = vis, bypassed = byp,
                    is_track_level = is_track_level, skip_detail = skip_detail,
                }
                -- by_name lookup (for InspEnvelopeState).
                by_name[ename or "?"] = { exists = act ~= "0", visible = vis }
            end
        end
        insp_env_cache = {
            track = track, entries = entries,
            fx_env_count = fx_env_count, by_name = by_name,
            has_any_active = has_any_active,
            total_env_count = total_env_ct,
        }
        insp_env_cache_dirty = false
    end

    InspEnvelopeCacheStale = function(track)
        if insp_env_cache_dirty or not insp_env_cache or insp_env_cache.track ~= track then return true end
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return true end
        local total_env_ct = r.CountTrackEnvelopes(track)
        if total_env_ct ~= (insp_env_cache.total_env_count or -1) then return true end
        for e = 0, total_env_ct - 1 do
            local env = r.GetTrackEnvelope(track, e)
            local cached = insp_env_cache.entries[e + 1]
            if not env or not cached or cached.env ~= env then return true end
            local _, fi = r.Envelope_GetParentTrack(env)
            local _, ename = r.GetEnvelopeName(env)
            local _, chunk = r.GetEnvelopeStateChunk(env, "", false)
            local act = chunk and (chunk:match("ACT%s+(%d+)") or "1") or "1"
            local vis = chunk and chunk:match("VIS%s+1") ~= nil or false
            if cached.name ~= (ename or "?")
                or cached.fx_idx ~= (fi or -1)
                or cached.act ~= act
                or cached.visible ~= vis then
                return true
            end
        end
        return false
    end

    InspInvalidateEnvCache = function()
        insp_env_cache_dirty = true
    end

    InspStripEnvSuffix = function(name, fx_idx)
        if fx_idx and fx_idx >= 0 then
            local stripped = name:match("^(.+) / [^/]+$")
            if stripped then return stripped end
        end
        return name
    end

    -- Format send envelope name with destination track: "SND VOL - 5: TrackName".
    InspFormatSendEnvName = function(track, env, name)
        if not env or not track or not r.ValidatePtr(track, "MediaTrack*") then return name end
        if not r.BR_GetMediaTrackSendInfo_Envelope then return name end
        -- Determine envelope type from name.
        local env_type
        if name == "Send Volume" then env_type = 0
        elseif name == "Send Pan" then env_type = 1
        elseif name == "Send Mute" then env_type = 2
        else return name end
        local short
        if env_type == 0 then short = "SND VOL"
        elseif env_type == 1 then short = "SND PAN"
        else short = "SND MUTE" end
        -- Match envelope pointer against all sends.
        local num_sends = r.GetTrackNumSends(track, 0)
        for si = 0, num_sends - 1 do
            local send_env = r.BR_GetMediaTrackSendInfo_Envelope(track, 0, si, env_type)
            if send_env == env then
                local dest = r.BR_GetMediaTrackSendInfo_Track(track, 0, si, 1)
                if dest and r.ValidatePtr(dest, "MediaTrack*") then
                    local _, dname = r.GetTrackName(dest)
                    local dnum = math.floor(r.GetMediaTrackInfo_Value(dest, "IP_TRACKNUMBER"))
                    return short .. " - " .. dnum .. ": " .. dname
                end
                return short .. " - Send " .. (si + 1)
            end
        end
        return name
    end

    InspFormatEnvForTrackList = function(name, fx_idx, track)
        if not fx_idx or fx_idx < 0 then return name end
        local param = name:match("^(.+) / [^/]+$") or name
        -- v20.434 Stage C: read plugin name from track_fx_cache.
        local plugin_name = nil
        for _, fx in ipairs(getFxList(track)) do
            if fx.fx_idx == fx_idx then plugin_name = fx.name; break end
        end
        if plugin_name then return plugin_name .. ": " .. param end
        return param
    end

    InspEnvColor = function(name, fx_idx)
        if fx_idx == -1 or fx_idx == nil then
            if name == "Volume" or name == "Trim Volume" then return C.green end
            if name == "Pan" or name == "Width" then return C.amber end
            if name:match("^Send") then return C.fx_send_text end
            return C.fx_env_text
        end
        local stripped = InspStripEnvSuffix(name, fx_idx)
        local sl = stripped:lower()
        if sl == "wet" or sl == "bypass" or sl == "power" then return C.fx_wrapper_text end
        return C.fx_env_text
    end

    InspEnvSortKey = function(name, fx_idx)
        if fx_idx == -1 or fx_idx == nil then
            if name == "Volume" or name == "Trim Volume" then return 0 end
            if name == "Pan" or name == "Width" then return 1 end
            if name:match("^Send") then return 2 end
            return 3
        end
        -- FX parameters (shown in track-level list with plugin name).
        local stripped = InspStripEnvSuffix(name, fx_idx)
        local sl = stripped:lower()
        if sl == "bypass" or sl == "wet" or sl == "power" then return 4 end
        return 5
    end

    -- Returns exists (envelope active), visible (VIS 1 in chunk).
    -- ACT 0 = deactivated by REAPER's intelligent removal, treated as non-existent.
    InspEnvelopeState = function(track, env_name)
        if insp_env_cache and insp_env_cache.track == track and not insp_env_cache_dirty then
            local cached = insp_env_cache.by_name[env_name]
            if cached then return cached.exists, cached.visible end
            return false, false
        end
        for e = 0, r.CountTrackEnvelopes(track) - 1 do
            local env = r.GetTrackEnvelope(track, e)
            if env then
                local _, n = r.GetEnvelopeName(env)
                if n == env_name then
                    local _, chunk = r.GetEnvelopeStateChunk(env, "", false)
                    if chunk then
                        local act = chunk:match("ACT%s+(%d+)")
                        if act == "0" then return false, false end
                        local vis = chunk:match("VIS%s+1") ~= nil
                        return true, vis
                    end
                    return true, false
                end
            end
        end
        return false, false
    end
end

return ReflexInstallEnvelopeCore
