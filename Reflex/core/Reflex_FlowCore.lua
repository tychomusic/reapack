-- @noindex
-- Reflex flow core module.
-- Installs flow-view chain and focus/toggle backend helpers.

ReflexInstallFlowCore = function(deps)
    local r = deps.r
    local getInspPinned = deps.get_insp_pinned
    local setInspPinned = deps.set_insp_pinned
    local setInspPinSuppressSelected = deps.set_insp_pin_suppress_selected
    local setNavScrollTarget = deps.set_nav_scroll_target

    -- Build display-ordered chain: [grandparent, ..., parent, FOCUS]
    -- Focus track (anchor) is always at chain[#chain].
    FlowViewBuildChain = function(focus)
        local chain = {}
        if not focus or not r.ValidatePtr(focus, "MediaTrack*") then return chain end

        -- Walk upward from focus via parent sends.
        local up = {}
        local visited = {}
        local track = focus
        while track and r.ValidatePtr(track, "MediaTrack*") and not visited[track] do
            up[#up + 1] = track
            visited[track] = true
            local parent_send = r.GetMediaTrackInfo_Value(track, "B_MAINSEND") == 1
            local parent = r.GetParentTrack(track)
            if parent_send and parent then
                track = parent
            else
                break
            end
        end

        -- up = {focus, parent, grandparent, ...}; reverse for display order.
        for i = #up, 1, -1 do
            chain[#chain + 1] = up[i]
        end

        return chain
    end

    FlowViewToggle = function()
        if flow_view_active then
            flow_view_active = false
            if getInspPinned() then setInspPinSuppressSelected(true) end
            flow_view_chain = {}
            flow_view_anchor = nil
            flow_view_browsing = false
            flow_view_expanded_set = {}
            flow_mini_peak = {}
            flow_env_expanded = {}
            setNavScrollTarget(0)
            return
        end
        local sel = r.GetSelectedTrack(0, 0)
        if not sel then return end
        flow_view_active = true
        flow_view_anchor = sel
        flow_view_expanded_set = {}
        flow_view_chain = FlowViewBuildChain(sel)
        flow_view_scroll_pending = true
    end

    -- Re-anchor flow view to a new focus track (double-click, external selection).
    FlowViewSetFocus = function(track)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
        setInspPinned(false)
        flow_view_anchor = track
        flow_view_expanded_set = {}
        flow_view_chain = FlowViewBuildChain(track)
        -- Select in REAPER.
        r.Undo_BeginBlock()
        r.SetOnlyTrackSelected(track)
        r.Undo_EndBlock("Reflex: Flow focus", 0)
    end

    FlowViewRefresh = function()
        if not flow_view_active then return end
        if not flow_view_anchor or not r.ValidatePtr(flow_view_anchor, "MediaTrack*") then
            flow_view_active = false
            flow_view_chain = {}
            flow_view_anchor = nil
            if getInspPinned() then setInspPinSuppressSelected(true) end
            flow_view_expanded_set = {}
            flow_env_expanded = {}
            return
        end
        flow_view_chain = FlowViewBuildChain(flow_view_anchor)
    end
end

return ReflexInstallFlowCore
