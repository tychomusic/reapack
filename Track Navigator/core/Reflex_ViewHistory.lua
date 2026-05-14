-- @noindex
-- Reflex ViewHistory module.
-- Installs the global ViewHistory* functions used throughout Reflex.

ReflexInstallViewHistory = function(deps)
    local r = deps.r
    local getInspPinned = deps.get_insp_pinned
    local setInspPinned = deps.set_insp_pinned
    local getInspTrack = deps.get_insp_track
    local setInspTrack = deps.set_insp_track
    local resetInspEnvExpanded = deps.reset_insp_env_expanded
    local setInspPinSuppressSelected = deps.set_insp_pin_suppress_selected

    local function ViewHistoryTcpWindow()
        if not (r.GetMainHwnd and r.JS_Window_FindChildByID) then return nil end
        return r.JS_Window_FindChildByID(r.GetMainHwnd(), 1000)
    end

    local function ViewHistoryCaptureTcpScroll()
        if not r.JS_Window_GetScrollInfo then return nil end
        local tcp = ViewHistoryTcpWindow()
        if not tcp then return nil end
        local ok, pos = r.JS_Window_GetScrollInfo(tcp, "v")
        if ok and type(pos) == "number" then return pos end
        return nil
    end

    local function ViewHistoryRestoreTcpScroll(pos)
        if type(pos) ~= "number" or not r.JS_Window_SetScrollPos then return end
        local function restore()
            local tcp = ViewHistoryTcpWindow()
            if tcp then r.JS_Window_SetScrollPos(tcp, "v", math.max(0, math.floor(pos + 0.5))) end
        end
        restore()
        r.defer(function()
            restore()
            r.defer(restore)
        end)
    end

    local function ViewHistoryCaptureArrangeView()
        if not r.GetSet_ArrangeView2 then return nil end
        local ok, start_time, end_time = pcall(r.GetSet_ArrangeView2, 0, false, 0, 0, 0, 0)
        if ok and type(start_time) == "number" and type(end_time) == "number" and end_time > start_time then
            return { start_time = start_time, end_time = end_time }
        end
        return nil
    end

    local function ViewHistoryRestoreArrangeView(arrange)
        if type(arrange) ~= "table" or not r.GetSet_ArrangeView2 then return end
        local start_time = arrange.start_time
        local end_time = arrange.end_time
        if type(start_time) ~= "number" or type(end_time) ~= "number" or end_time <= start_time then return end
        pcall(r.GetSet_ArrangeView2, 0, true, 0, 0, start_time, end_time)
    end

    local function ViewHistoryCaptureWorkState()
        local work = {}
        work.tcp_scroll_y = ViewHistoryCaptureTcpScroll()
        work.arrange_view = ViewHistoryCaptureArrangeView()
        if work.tcp_scroll_y ~= nil or work.arrange_view ~= nil then return work end
        return nil
    end

    local function ViewHistoryRestoreWorkState(work)
        if type(work) ~= "table" then return end
        if opt_view_mode_restore_arrange == true then
            ViewHistoryRestoreArrangeView(work.arrange_view)
        end
        ViewHistoryRestoreTcpScroll(work.tcp_scroll_y)
    end

    ViewHistorySnapshot = function(opts)
        local capture_work_state = opts and opts.work_state
        local insp_pinned = getInspPinned()
        local insp_track = getInspTrack()
        local snap = { vis = {}, mixer = {}, collapse = {}, sel_guid = nil, pinned = insp_pinned }
        if capture_work_state then
            snap.sel_guids = {}
            snap.work_state = ViewHistoryCaptureWorkState()
        end
        if insp_pinned and insp_track and r.ValidatePtr(insp_track, "MediaTrack*") then
            snap.pinned_guid = r.GetTrackGUID(insp_track)
        end
        -- v20.428: capture flow view state so Back/Forward restore the chain
        -- that was visible at snapshot time. Without this, restoring a flow-view
        -- snapshot leaves flow_view_anchor stale, and the pin marker (which
        -- renders on the anchor's card via show_pin = track == flow_view_anchor)
        -- ends up on the wrong track.
        snap.flow_active = flow_view_active or false
        if flow_view_active and flow_view_anchor
           and r.ValidatePtr(flow_view_anchor, "MediaTrack*") then
            snap.flow_anchor_guid = r.GetTrackGUID(flow_view_anchor)
        end
        local nt = r.CountTracks(0)
        for i = 0, nt - 1 do
            local t = r.GetTrack(0, i)
            local guid = r.GetTrackGUID(t)
            snap.vis[guid] = r.GetMediaTrackInfo_Value(t, "B_SHOWINTCP")
            snap.mixer[guid] = r.GetMediaTrackInfo_Value(t, "B_SHOWINMIXER")
            local fd = r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
            if fd == 1 then
                snap.collapse[guid] = r.GetMediaTrackInfo_Value(t, "I_FOLDERCOMPACT")
            end
            if r.IsTrackSelected(t) then
                snap.sel_guid = guid
                if capture_work_state then snap.sel_guids[guid] = true end
            end
        end
        return snap
    end

    ViewHistoryRestore = function(snap)
        if not snap then return end
        view_history_restoring = 3  -- suppress pushes for 3 frames after restore
        r.PreventUIRefresh(1)
        local nt = r.CountTracks(0)
        for i = 0, nt - 1 do
            local t = r.GetTrack(0, i)
            local guid = r.GetTrackGUID(t)
            if snap.vis[guid] ~= nil then
                r.SetMediaTrackInfo_Value(t, "B_SHOWINTCP", snap.vis[guid])
            end
            if snap.mixer and snap.mixer[guid] ~= nil then
                r.SetMediaTrackInfo_Value(t, "B_SHOWINMIXER", snap.mixer[guid])
            end
            if snap.collapse[guid] ~= nil then
                r.SetMediaTrackInfo_Value(t, "I_FOLDERCOMPACT", snap.collapse[guid])
            end
            if snap.sel_guids then
                r.SetMediaTrackInfo_Value(t, "I_SELECTED", snap.sel_guids[guid] and 1 or 0)
            elseif snap.sel_guid then
                r.SetMediaTrackInfo_Value(t, "I_SELECTED", guid == snap.sel_guid and 1 or 0)
            end
        end
        r.PreventUIRefresh(-1)
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        ViewHistoryRestoreWorkState(snap.work_state)
        -- Restore pin state
        if snap.pinned ~= nil then
            setInspPinned(snap.pinned)
            if snap.pinned and snap.pinned_guid then
                local nt2 = r.CountTracks(0)
                for i2 = 0, nt2 - 1 do
                    local t2 = r.GetTrack(0, i2)
                    if r.GetTrackGUID(t2) == snap.pinned_guid then
                        setInspTrack(t2)
                        InspScanTrack(t2)
                        resetInspEnvExpanded()
                        break
                    end
                end
            end
            setInspPinSuppressSelected(false)
        end
        -- v20.428: restore flow view state. Must come AFTER pin restore so
        -- flow_view_anchor is keyed off the resolved snap value rather than
        -- the live anchor (which is stale on the cross-frame restore path).
        -- Always clears flow_view_browsing and flow_view_expanded_set; these
        -- are transient browse-state, never history-meaningful. (v20.431: was
        -- flow_view_expanded_card, single-slot; now multi-card set.)
        if snap.flow_active ~= nil then
            flow_view_browsing = false
            flow_view_expanded_set = {}
            if snap.flow_active and snap.flow_anchor_guid then
                local target_anchor = nil
                local nt3 = r.CountTracks(0)
                for i3 = 0, nt3 - 1 do
                    local t3 = r.GetTrack(0, i3)
                    if r.GetTrackGUID(t3) == snap.flow_anchor_guid then
                        target_anchor = t3
                        break
                    end
                end
                if target_anchor then
                    flow_view_active = true
                    flow_view_anchor = target_anchor
                    flow_view_chain = FlowViewBuildChain(target_anchor)
                else
                    -- Anchor track no longer exists; collapse flow view safely.
                    flow_view_active = false
                    flow_view_anchor = nil
                    flow_view_chain = {}
                    flow_env_expanded = {}; flow_mini_peak = {}
                end
            elseif not snap.flow_active and flow_view_active then
                flow_view_active = false
                flow_view_anchor = nil
                flow_view_chain = {}
                flow_env_expanded = {}; flow_mini_peak = {}
            end
        end
        -- view_history_restoring counter will decrement each frame in main loop
    end

    ViewHistorySnapshotsEqual = function(a, b)
        if not a or not b then return false end
        if a.sel_guid ~= b.sel_guid then return false end
        if (a.pinned or false) ~= (b.pinned or false) then return false end
        -- v20.428: pinned_guid was previously omitted; two pinned states with
        -- different pinned tracks dedup'd as equal, suppressing legitimate pushes.
        if a.pinned_guid ~= b.pinned_guid then return false end
        -- v20.428: flow state. Without these, snapshots taken in different flow
        -- chains (or flow-on vs flow-off) collapse into one entry on dedup.
        if (a.flow_active or false) ~= (b.flow_active or false) then return false end
        if a.flow_anchor_guid ~= b.flow_anchor_guid then return false end
        for k, v in pairs(a.vis) do if b.vis[k] ~= v then return false end end
        for k, v in pairs(b.vis) do if a.vis[k] ~= v then return false end end
        for k, v in pairs(a.mixer or {}) do if not b.mixer or b.mixer[k] ~= v then return false end end
        for k, v in pairs(b.mixer or {}) do if not a.mixer or a.mixer[k] ~= v then return false end end
        for k, v in pairs(a.collapse) do if b.collapse[k] ~= v then return false end end
        for k, v in pairs(b.collapse) do if a.collapse[k] ~= v then return false end end
        if a.sel_guids or b.sel_guids then
            for k, v in pairs(a.sel_guids or {}) do if not b.sel_guids or b.sel_guids[k] ~= v then return false end end
            for k, v in pairs(b.sel_guids or {}) do if not a.sel_guids or a.sel_guids[k] ~= v then return false end end
        end
        return true
    end

    ViewHistoryPush = function(opts)
        if view_history_restoring > 0 then return end
        if view_history_pushing then return end
        view_history_pushing = true
        local is_launch_baseline = opts and opts.launch_baseline
        if not is_launch_baseline then view_history_launch_baseline = false end
        local snap = ViewHistorySnapshot()
        -- Skip if identical to current entry (prevents duplicate from restore-triggered selection change)
        if view_history_idx > 0
           and ViewHistorySnapshotsEqual(snap, view_history[view_history_idx]) then
            view_history_pushing = false
            return
        end
        -- Truncate forward history
        for i = view_history_idx + 1, view_history_count do
            view_history[i] = nil
        end
        view_history_idx = view_history_idx + 1
        view_history[view_history_idx] = snap
        view_history_count = view_history_idx
        view_history_launch_baseline = is_launch_baseline
            and view_history_idx == 1
            and view_history_count == 1
        if view_history_count > VIEW_HISTORY_MAX then
            table.remove(view_history, 1)
            view_history_idx = view_history_idx - 1
            view_history_count = view_history_count - 1
            view_history_launch_baseline = false
        end
        view_history_pushing = false
    end

    -- Debounced push for rapid TLT clicks. Within 500ms of the previous TLT push,
    -- this is a no-op; clicks within the window group into a single undo entry
    -- (the pre-burst state). Non-TLT pushes (bulk ops, mode toggles) bypass this
    -- and always fire via ViewHistoryPush() directly.
    ViewHistoryPushTlf = function()
        local now = r.time_precise()
        if now - view_history_tlf_debounce < 0.5 then return end
        view_history_tlf_debounce = now
        ViewHistoryPush()
    end

    ViewHistoryCanBack = function()
        if view_history_idx < 1 then return false end
        if view_history_launch_baseline
           and view_history_idx == 1
           and view_history_count == 1 then
            return false
        end
        if view_history_idx == view_history_count then return true end
        return view_history_idx > 1
    end

    ViewHistoryBack = function()
        if view_history_idx < 1 then return end
        if view_history_idx == view_history_count then
            -- At tip: check if live state actually differs from entry[idx]
            local live = ViewHistorySnapshot()
            if ViewHistorySnapshotsEqual(live, view_history[view_history_idx]) then
                -- Nothing changed since last push; go one further back if possible
                if view_history_idx <= 1 then return end
                view_history_idx = view_history_idx - 1
                ViewHistoryRestore(view_history[view_history_idx])
                return
            end
            -- Save current live state so redo can return
            view_history_count = view_history_count + 1
            view_history[view_history_count] = live
            if view_history_count > VIEW_HISTORY_MAX then
                table.remove(view_history, 1)
                view_history_idx = view_history_idx - 1
                view_history_count = view_history_count - 1
            end
        else
            if view_history_idx <= 1 then return end
            -- Skip back past entries identical to current state
            local live = ViewHistorySnapshot()
            while view_history_idx > 1 do
                view_history_idx = view_history_idx - 1
                if not ViewHistorySnapshotsEqual(live, view_history[view_history_idx]) then
                    break
                end
            end
        end
        ViewHistoryRestore(view_history[view_history_idx])
    end

    ViewHistoryForward = function()
        if view_history_idx >= view_history_count then return end
        -- Skip forward past entries identical to current state
        local live = ViewHistorySnapshot()
        while view_history_idx < view_history_count do
            view_history_idx = view_history_idx + 1
            if not ViewHistorySnapshotsEqual(live, view_history[view_history_idx]) then
                break
            end
        end
        ViewHistoryRestore(view_history[view_history_idx])
    end
end

return ReflexInstallViewHistory
