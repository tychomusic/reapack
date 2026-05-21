-- @noindex
-- Reflex routing clipboard core module.
-- Installs sends/receives/HW output copy-paste helpers.

ReflexInstallRoutingClipboard = function(deps)
    local r = deps.r

    -- Session clipboard for sends/receives/HW outputs copy/paste. Mirrors FX
    -- clipboard model: single slot, replaced on Copy, append-on-Paste (never
    -- replaces existing routing). Self-paste (source == target) silently skips.
    -- Cross-track receive paste is literal: copy receives from track A, paste
    -- onto B, and A's source tracks now also feed B.
    --
    -- Shape:
    --   type = "sends" | "receives" | "hw_sends"
    --   count = N
    --   source_name = "KICK"
    --   items = { { other_guid, mode, vol, pan, mute, mono, phase,
    --                midiflags, srcchan, dstchan, autom }, ... }
    -- For "sends":    other_guid = destination track GUID.
    -- For "receives": other_guid = source track GUID.
    -- For "hw_sends": other_guid is nil; dstchan is plain channel index (REAPER
    -- HW-output convention) rather than the packed format used by track sends.
    -- nil when clipboard is empty.
    nav_routing_clipboard = nil

    RoutingClipboardClear = function()
        nav_routing_clipboard = nil
    end

    RoutingClipboardHasContent = function()
        return nav_routing_clipboard ~= nil and (nav_routing_clipboard.count or 0) > 0
    end

    -- Build one routing record from a live (track, category, send_idx) triplet.
    RoutingClipboardCaptureItem = function(track, category, si)
        local item = {
            mode      = math.floor(r.GetTrackSendInfo_Value(track, category, si, "I_SENDMODE")),
            vol       = r.GetTrackSendInfo_Value(track, category, si, "D_VOL"),
            pan       = r.GetTrackSendInfo_Value(track, category, si, "D_PAN"),
            mute      = r.GetTrackSendInfo_Value(track, category, si, "B_MUTE") == 1,
            mono      = r.GetTrackSendInfo_Value(track, category, si, "B_MONO") == 1,
            phase     = r.GetTrackSendInfo_Value(track, category, si, "B_PHASE") == 1,
            midiflags = math.floor(r.GetTrackSendInfo_Value(track, category, si, "I_MIDIFLAGS")),
            srcchan   = math.floor(r.GetTrackSendInfo_Value(track, category, si, "I_SRCCHAN")),
            dstchan   = math.floor(r.GetTrackSendInfo_Value(track, category, si, "I_DSTCHAN")),
            autom     = math.floor(r.GetTrackSendInfo_Value(track, category, si, "I_AUTOMODE")),
        }
        if category == 0 and r.BR_GetMediaTrackSendInfo_Track then
            local dest = r.BR_GetMediaTrackSendInfo_Track(track, 0, si, 1)
            if dest and r.ValidatePtr(dest, "MediaTrack*") then
                item.other_guid = r.GetTrackGUID(dest)
            end
        elseif category == -1 and r.BR_GetMediaTrackSendInfo_Track then
            local src = r.BR_GetMediaTrackSendInfo_Track(track, -1, si, 0)
            if src and r.ValidatePtr(src, "MediaTrack*") then
                item.other_guid = r.GetTrackGUID(src)
            end
        end
        return item
    end

    -- Resolve a track GUID string to a live MediaTrack*. Returns nil if not found.
    RoutingClipboardResolveTrack = function(guid)
        if not guid or guid == "" then return nil end
        local nt = r.CountTracks(0)
        for ti = 0, nt - 1 do
            local t = r.GetTrack(0, ti)
            if t and r.GetTrackGUID(t) == guid then return t end
        end
        return nil
    end

    -- Capture all routing of given category from `track`. Replaces clipboard.
    -- category: 0 sends, -1 receives, 1 hw_sends. Returns true if >0 captured.
    RoutingClipboardCopyAll = function(track, category)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
        local n = r.GetTrackNumSends(track, category)
        if n <= 0 then return false end
        local items = {}
        for si = 0, n - 1 do
            items[#items + 1] = RoutingClipboardCaptureItem(track, category, si)
        end
        local _, tname = r.GetTrackName(track)
        if not tname or tname == "" then
            tname = "Track " .. math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
        end
        nav_routing_clipboard = {
            type = (category == 0 and "sends") or (category == -1 and "receives") or "hw_sends",
            count = #items,
            source_name = tname,
            items = items,
        }
        return true
    end

    -- Capture a single routing item (per-row Copy in routing-view). Replaces clipboard.
    RoutingClipboardCopyOne = function(track, category, send_idx)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
        local _, tname = r.GetTrackName(track)
        if not tname or tname == "" then
            tname = "Track " .. math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
        end
        nav_routing_clipboard = {
            type = (category == 0 and "sends") or (category == -1 and "receives") or "hw_sends",
            count = 1,
            source_name = tname,
            items = { RoutingClipboardCaptureItem(track, category, send_idx) },
        }
        return true
    end

    -- Append clipboard items onto `track`. Returns # actually pasted (may be < count
    -- when an item is self-paste-skipped or its other_guid no longer resolves).
    -- Single Undo block.
    RoutingClipboardPaste = function(track)
        if not RoutingClipboardHasContent() then return 0 end
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return 0 end
        local cb = nav_routing_clipboard
        local pasted = 0
        r.Undo_BeginBlock()
        local function apply(write_track, write_cat, si, item)
            r.SetTrackSendInfo_Value(write_track, write_cat, si, "I_SENDMODE", item.mode)
            r.SetTrackSendInfo_Value(write_track, write_cat, si, "D_VOL", item.vol)
            r.SetTrackSendInfo_Value(write_track, write_cat, si, "D_PAN", item.pan)
            r.SetTrackSendInfo_Value(write_track, write_cat, si, "B_MUTE", item.mute and 1 or 0)
            r.SetTrackSendInfo_Value(write_track, write_cat, si, "B_MONO", item.mono and 1 or 0)
            r.SetTrackSendInfo_Value(write_track, write_cat, si, "B_PHASE", item.phase and 1 or 0)
            r.SetTrackSendInfo_Value(write_track, write_cat, si, "I_MIDIFLAGS", item.midiflags)
            r.SetTrackSendInfo_Value(write_track, write_cat, si, "I_SRCCHAN", item.srcchan)
            r.SetTrackSendInfo_Value(write_track, write_cat, si, "I_DSTCHAN", item.dstchan)
            r.SetTrackSendInfo_Value(write_track, write_cat, si, "I_AUTOMODE", item.autom)
        end
        for _, item in ipairs(cb.items) do
            if cb.type == "sends" then
                local dest = RoutingClipboardResolveTrack(item.other_guid)
                if dest and dest ~= track then
                    local si = r.CreateTrackSend(track, dest)
                    if si and si >= 0 then apply(track, 0, si, item); pasted = pasted + 1 end
                end
            elseif cb.type == "receives" then
                local src = RoutingClipboardResolveTrack(item.other_guid)
                if src and src ~= track then
                    -- CreateTrackSend returns the new index from src's POV; write
                    -- fields via src+category=0 (the canonical store side).
                    local si = r.CreateTrackSend(src, track)
                    if si and si >= 0 then apply(src, 0, si, item); pasted = pasted + 1 end
                end
            else  -- hw_sends
                local si = r.CreateTrackSend(track, nil)
                if si and si >= 0 then apply(track, 1, si, item); pasted = pasted + 1 end
            end
        end
        local label
        if pasted == 0 then
            label = "Reflex: Paste routing (no-op)"
        elseif cb.type == "sends" then
            label = (pasted == 1) and "Reflex: Paste send" or ("Reflex: Paste " .. pasted .. " sends")
        elseif cb.type == "receives" then
            label = (pasted == 1) and "Reflex: Paste receive" or ("Reflex: Paste " .. pasted .. " receives")
        else
            label = (pasted == 1) and "Reflex: Paste HW send" or ("Reflex: Paste " .. pasted .. " HW sends")
        end
        r.Undo_EndBlock(label, -1)
        return pasted
    end

    -- Menu label for the "Paste {N} {label}" item. Returns nil when empty.
    RoutingClipboardPasteLabel = function()
        if not RoutingClipboardHasContent() then return nil end
        local n = nav_routing_clipboard.count
        local t = nav_routing_clipboard.type
        local noun
        if t == "sends" then noun = (n == 1) and "send" or "sends"
        elseif t == "receives" then noun = (n == 1) and "receive" or "receives"
        else noun = (n == 1) and "HW send" or "HW sends" end
        if n == 1 then return "Paste " .. noun
        else return "Paste " .. n .. " " .. noun end
    end
end

return ReflexInstallRoutingClipboard
