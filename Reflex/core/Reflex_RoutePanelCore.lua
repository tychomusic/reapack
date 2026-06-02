-- @noindex
-- Reflex route panel core module.
-- Installs expanded inline ROUTE panel renderer.

ReflexInstallRoutePanelCore = function(deps)
    local r = deps.r
    local ctx = deps.ctx
    local C = deps.colors

DrawRoutePanel = function(track, bw, hdr)
    local row_h = S(UI.btn_h)
    local row_gap = S(5 / 1.44)
    local header_row_gap = S(18 / 1.44)
    local section_gap = S(22 / 1.44)
    r.ImGui_SetCursorPosY(ctx, (hdr.route_panel_y or r.ImGui_GetCursorPosY(ctx)) + section_gap)

    local dl = r.ImGui_GetWindowDrawList(ctx)

    local num_sends = r.GetTrackNumSends(track, 0)
    local num_recvs = r.GetTrackNumSends(track, -1)
    local num_hw = r.GetTrackNumSends(track, 1)

    -- Section: Sends
    local sends_hdr_y = r.ImGui_GetCursorPosY(ctx)
    RouteSectionHeader("##addsend_dd", "##route_add_send", "Sends", C.route_send, hdr.trk_sx, row_h, dl, function()
        if r.ImGui_MenuItem(ctx, "Add send to new track") then
            RoutingAddSendTrack(track)
        end
        r.ImGui_Separator(ctx)
        local items = {}
        local nt_all = r.CountTracks(0)
        for ti = 0, nt_all - 1 do
            local t = r.GetTrack(0, ti)
            if t ~= track then
                local _, tn = r.GetTrackName(t)
                local tnum = math.floor(r.GetMediaTrackInfo_Value(t, "IP_TRACKNUMBER"))
                local label = tnum .. ": " .. tn
                items[#items + 1] = { label = label, label_lower = label:lower(), payload = t }
            end
        end
        RouteAddMenuList(items, function(t)
            r.Undo_BeginBlock()
            local si = r.CreateTrackSend(track, t)
            if si >= 0 then r.SetTrackSendInfo_Value(track, 0, si, "I_MIDIFLAGS", 31) end
            r.Undo_EndBlock("Reflex: Add send", -1)
        end)
    end, num_sends == 0, bw)
    r.ImGui_SetCursorPosY(ctx, sends_hdr_y + row_h)
    if num_sends > 0 then
        r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + header_row_gap)
        local send_list = RouteBuildSortedTrackList(track, 0)
        local src_nchan = math.floor(r.GetMediaTrackInfo_Value(track, "I_NCHAN"))
        for li, entry in ipairs(send_list) do
            local display = entry.num .. ": " .. entry.name
            DrawRouteRow("##s", entry.idx, dl, track, 0, display, C.text, src_nchan, entry.nchan, bw, hdr.trk_sx, C.route_send)
            if li < #send_list then r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + row_gap) end
        end
    end

    -- Section: Receives
    r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + section_gap)
    local recvs_hdr_y = r.ImGui_GetCursorPosY(ctx)
    RouteSectionHeader("##addrecv_dd", "##route_add_recv", "Receives", C.route_recv, hdr.trk_sx, row_h, dl, function()
        if r.ImGui_MenuItem(ctx, "Add receive from new track") then
            r.Undo_BeginBlock()
            local ti = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
            r.InsertTrackAtIndex(math.floor(ti), false)
            local new_trk = r.GetTrack(0, math.floor(ti))
            if new_trk then
                r.CreateTrackSend(new_trk, track)
                r.GetSetMediaTrackInfo_String(new_trk, "P_NAME", "New Recv", true)
            end
            r.Undo_EndBlock("Reflex: Add receive from new track", -1)
        end
        r.ImGui_Separator(ctx)
        local items = {}
        local nt_all = r.CountTracks(0)
        for ti = 0, nt_all - 1 do
            local t = r.GetTrack(0, ti)
            if t ~= track then
                local _, tn = r.GetTrackName(t)
                local tnum = math.floor(r.GetMediaTrackInfo_Value(t, "IP_TRACKNUMBER"))
                local label = tnum .. ": " .. tn
                items[#items + 1] = { label = label, label_lower = label:lower(), payload = t }
            end
        end
        RouteAddMenuList(items, function(t)
            r.Undo_BeginBlock()
            local si = r.CreateTrackSend(t, track)
            if si >= 0 then r.SetTrackSendInfo_Value(t, 0, si, "I_MIDIFLAGS", 31) end
            r.Undo_EndBlock("Reflex: Add receive", -1)
        end)
    end, num_recvs == 0, bw)
    r.ImGui_SetCursorPosY(ctx, recvs_hdr_y + row_h)
    if num_recvs > 0 then
        r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + header_row_gap)
        local recv_list = RouteBuildSortedTrackList(track, -1)
        local dst_nchan = math.floor(r.GetMediaTrackInfo_Value(track, "I_NCHAN"))
        for li, entry in ipairs(recv_list) do
            local display = entry.num .. ": " .. entry.name
            DrawRouteRow("##r", entry.idx, dl, track, -1, display, C.text, entry.nchan, dst_nchan, bw, hdr.trk_sx, C.route_recv)
            if li < #recv_list then r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + row_gap) end
        end
    end

    -- Section: Hardware Outputs
    r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + section_gap)
    local hw_hdr_y = r.ImGui_GetCursorPosY(ctx)
    RouteSectionHeader("##addhw_dd", "##route_add_hw", "HW", C.route_hw, hdr.trk_sx, row_h, dl, function()
        local num_outs = r.GetNumAudioOutputs()
        local function _hw_opt_name(ch_idx)
            if RouteHWOutputChannelName then return RouteHWOutputChannelName(ch_idx) end
            local n = r.GetOutputChannelName(ch_idx) or ""
            local stripped = n:match("^Output%s+(.+)$")
            if stripped then return stripped end
            return n ~= "" and n or tostring(ch_idx + 1)
        end
        local items = {}
        for ch = 0, num_outs - 1, 2 do
            local label = _hw_opt_name(ch) .. " / " .. _hw_opt_name(ch + 1)
            items[#items + 1] = { label = label, label_lower = label:lower(), payload = ch }
        end
        RouteAddMenuList(items, function(ch)
            r.Undo_BeginBlock()
            local si = r.CreateTrackSend(track, nil)
            if si and si >= 0 then
                if ch > 0 then
                    r.SetTrackSendInfo_Value(track, 1, si, "I_DSTCHAN", ch)
                end
            end
            r.Undo_EndBlock("Reflex: Add hardware output", -1)
        end)
    end, num_hw == 0, bw)
    r.ImGui_SetCursorPosY(ctx, hw_hdr_y + row_h)
    if num_hw > 0 then
        r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + header_row_gap)
        local src_nchan = math.floor(r.GetMediaTrackInfo_Value(track, "I_NCHAN"))
        local dst_nchan = r.GetNumAudioOutputs()
        for hi = 0, num_hw - 1 do
            local dst_val = math.floor(r.GetTrackSendInfo_Value(track, 1, hi, "I_DSTCHAN"))
            local hw_name = RouteHWOutputNameFromValue and RouteHWOutputNameFromValue(dst_val) or tostring(dst_val + 1)
            DrawRouteRow("##h", hi, dl, track, 1, hw_name, C.text, src_nchan, dst_nchan, bw, hdr.trk_sx, C.route_hw)
            if hi < num_hw - 1 then r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + row_gap) end
        end
    end

    -- No trailing gap: FX area owns the ROUTE→FX space via gap_ctrl_fx.
end

end

return ReflexInstallRoutePanelCore
