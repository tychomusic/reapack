-- @noindex
-- Reflex route tooltip core module.
-- Installs persistent CTRL.route tooltip formatting/display helpers.

ReflexInstallRouteTooltipCore = function(deps)
    local r = deps.r
    local ctx = deps.ctx
    local C = deps.colors

-- Format packed channel value as "1/2" etc.
FormatChanPacked = function(val)
    local first_ch = (val & 0x3FF)
    local num_ch = math.floor(val / 1024)
    if num_ch < 1 then num_ch = 2 end
    if num_ch == 1 then return tostring(first_ch + 1)
    else return (first_ch + 1) .. "/" .. (first_ch + num_ch) end
end

-- Format HW output dst channel (plain index).
FormatChanHW = function(val)
    if RouteHWOutputNameFromValue then return RouteHWOutputNameFromValue(val) end
    return "Output " .. (val + 1) .. "/" .. (val + 2)
end

-- Show persistent routing tooltip (ignores opt_tooltips).
ShowRoutingTooltip = function(track, opts)
    opts = opts or {}
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    local has_br = r.BR_GetMediaTrackSendInfo_Track ~= nil
    local num_sends = r.GetTrackNumSends(track, 0)
    local num_recvs = r.GetTrackNumSends(track, -1)
    local num_hw = r.GetTrackNumSends(track, 1)
    local has_routes = num_sends > 0 or num_recvs > 0 or num_hw > 0
    if insp_routing_expanded[track] and not opts.action_text then return end
    if not has_routes and not opts.action_text then return end

    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), S(12), S(10))
    r.ImGui_BeginTooltip(ctx)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 0, S(4))
    local th = r.ImGui_GetTextLineHeight(ctx)

    if opts.action_text then
        for line in tostring(opts.action_text):gmatch("[^\n]+") do
            r.ImGui_TextColored(ctx, C.text_muted, line)
        end
        if has_routes then r.ImGui_Spacing(ctx) end
    end

    if num_sends > 0 then
        r.ImGui_TextColored(ctx, C.text_muted, "Sends")
        for si = 0, num_sends - 1 do
            local dest_name = "?"
            local dest_num = ""
            if has_br then
                local dest = r.BR_GetMediaTrackSendInfo_Track(track, 0, si, 1)
                if dest and r.ValidatePtr(dest, "MediaTrack*") then
                    local _, dn = r.GetTrackName(dest); dest_name = dn
                    local tn = math.floor(r.GetMediaTrackInfo_Value(dest, "IP_TRACKNUMBER"))
                    dest_num = tostring(tn)
                end
            end
            local is_muted = r.GetTrackSendInfo_Value(track, 0, si, "B_MUTE") == 1
            local col = is_muted and C.text_muted or C.route_send
            local src_val = math.floor(r.GetTrackSendInfo_Value(track, 0, si, "I_SRCCHAN"))
            local dst_val = math.floor(r.GetTrackSendInfo_Value(track, 0, si, "I_DSTCHAN"))
            local src_str = FormatChanPacked(src_val)
            local dst_str = FormatChanPacked(dst_val)
            local is_default = src_str == "1/2" and dst_str == "1/2"
            r.ImGui_TextColored(ctx, col, dest_num .. "  " .. dest_name)
            if not is_default then
                r.ImGui_SameLine(ctx, 0, S(10))
                r.ImGui_TextColored(ctx, C.text_muted, src_str .. " \xE2\x86\x92 " .. dst_str)
            end
        end
    end

    if num_recvs > 0 then
        if num_sends > 0 then r.ImGui_Spacing(ctx) end
        r.ImGui_TextColored(ctx, C.text_muted, "Receives")
        for ri = 0, num_recvs - 1 do
            local src_name = "?"
            local src_num = ""
            if has_br then
                local src = r.BR_GetMediaTrackSendInfo_Track(track, -1, ri, 0)
                if src and r.ValidatePtr(src, "MediaTrack*") then
                    local _, sn = r.GetTrackName(src); src_name = sn
                    local tn = math.floor(r.GetMediaTrackInfo_Value(src, "IP_TRACKNUMBER"))
                    src_num = tostring(tn)
                end
            end
            local is_muted = r.GetTrackSendInfo_Value(track, -1, ri, "B_MUTE") == 1
            local col = is_muted and C.text_muted or C.route_recv
            local src_val = math.floor(r.GetTrackSendInfo_Value(track, -1, ri, "I_SRCCHAN"))
            local dst_val = math.floor(r.GetTrackSendInfo_Value(track, -1, ri, "I_DSTCHAN"))
            local src_str = FormatChanPacked(src_val)
            local dst_str = FormatChanPacked(dst_val)
            local is_default = src_str == "1/2" and dst_str == "1/2"
            r.ImGui_TextColored(ctx, col, src_num .. "  " .. src_name)
            if not is_default then
                r.ImGui_SameLine(ctx, 0, S(10))
                r.ImGui_TextColored(ctx, C.text_muted, src_str .. " \xE2\x86\x92 " .. dst_str)
            end
        end
    end

    if num_hw > 0 then
        if num_sends > 0 or num_recvs > 0 then r.ImGui_Spacing(ctx) end
        r.ImGui_TextColored(ctx, C.text_muted, "Hardware Outputs")
        for hi = 0, num_hw - 1 do
            local is_muted = r.GetTrackSendInfo_Value(track, 1, hi, "B_MUTE") == 1
            local col = is_muted and C.text_muted or (C.route_hw or C.text_dim)
            local src_val = math.floor(r.GetTrackSendInfo_Value(track, 1, hi, "I_SRCCHAN"))
            local dst_val = math.floor(r.GetTrackSendInfo_Value(track, 1, hi, "I_DSTCHAN"))
            local src_str = FormatChanPacked(src_val)
            local dst_str = FormatChanHW(dst_val)
            r.ImGui_TextColored(ctx, col, dst_str)
            r.ImGui_SameLine(ctx, 0, S(10))
            r.ImGui_TextColored(ctx, C.text_muted, src_str)
        end
    end

    r.ImGui_PopStyleVar(ctx)
    r.ImGui_EndTooltip(ctx)
    r.ImGui_PopStyleVar(ctx)
end

end

return ReflexInstallRouteTooltipCore
