-- @noindex
-- Reflex view-mode backend module.
-- Installs Routing, Selected, and Active View scan/apply/toggle helpers.

ReflexInstallViewModes = function(deps)
    local r = deps.r
    local markDirty = deps.mark_dirty or function()
        if needs_rescan ~= nil then needs_rescan = true end
        if needs_song_rescan ~= nil then needs_song_rescan = true end
    end
    local VIEW_MODE_SCROLL_ATTEMPTS = 4

    local function RoutingViewSendTrack(track, category, send_idx, native_key)
        if r.GetTrackSendInfo_Value then
            local other = r.GetTrackSendInfo_Value(track, category, send_idx, native_key)
            if other and r.ValidatePtr(other, "MediaTrack*") then return other end
        end
        return nil
    end

    RoutingViewGetParentChain = function(track)
        local parents = {}
        local parent = r.GetParentTrack(track)
        while parent do
            parents[parent] = true
            parent = r.GetParentTrack(parent)
        end
        return parents
    end

    RoutingViewGetChildren = function(track)
        local children = {}
        local idx = r.CSurf_TrackToID(track, false) - 1
        if idx < 0 then return children end
        local fd = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        if fd ~= 1 then return children end
        local function child_flows_to_folder(child)
            local current = child
            local parent = r.GetParentTrack(current)
            while parent do
                if r.GetMediaTrackInfo_Value(current, "B_MAINSEND") == 0 then return false end
                if parent == track then return true end
                current = parent
                parent = r.GetParentTrack(current)
            end
            return false
        end
        local nt = r.CountTracks(0)
        local depth, i = 1, idx + 1
        while i < nt and depth > 0 do
            local c = r.GetTrack(0, i)
            if child_flows_to_folder(c) then children[c] = true end
            depth = depth + r.GetMediaTrackInfo_Value(c, "I_FOLDERDEPTH")
            i = i + 1
        end
        return children
    end

    RoutingViewGetSendDests = function(track)
        local dests = {}
        local num = r.GetTrackNumSends(track, 0)
        for i = 0, num - 1 do
            local dest = RoutingViewSendTrack(track, 0, i, "P_DESTTRACK")
            if dest then dests[dest] = true end
        end
        return dests
    end

    RoutingViewGetRecvSources = function(track)
        local srcs = {}
        local num = r.GetTrackNumSends(track, -1)
        for i = 0, num - 1 do
            local src = RoutingViewSendTrack(track, -1, i, "P_SRCTRACK")
            if src then srcs[src] = true end
        end
        return srcs
    end

    ViewModeFirstTrackInSet = function(track_set)
        local first = nil
        local first_num = math.huge
        for track in pairs(track_set or {}) do
            if track and r.ValidatePtr(track, "MediaTrack*") then
                local num = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
                if num > 0 and num < first_num then
                    first = track
                    first_num = num
                end
            end
        end
        return first
    end

    ViewModeScrollTrackToCenter = function(track)
        if not (track and r.ValidatePtr(track, "MediaTrack*")) then return end
        if r.JS_Window_FindChildByID then
            local tcp = r.JS_Window_FindChildByID(r.GetMainHwnd(), 1000)
            if tcp then
                r.TrackList_AdjustWindows(false)
                local _, _, th = r.JS_Window_GetClientSize(tcp)
                local ty = r.GetMediaTrackInfo_Value(track, "I_TCPY")
                local tkh = r.GetMediaTrackInfo_Value(track, "I_TCPH")
                local ok, sp = r.JS_Window_GetScrollInfo(tcp, "v")
                if ok then
                    local target = math.max(0, math.floor(sp + ty + tkh / 2 - th / 2))
                    r.JS_Window_SetScrollPos(tcp, "v", target)
                    return
                end
            end
        end
        if ScrollTrackToCenter then ScrollTrackToCenter(track) end
    end

    ViewModeDeferScroll = function(track, attempts)
        if not (track and r.ValidatePtr(track, "MediaTrack*")) then return end
        attempts = attempts or VIEW_MODE_SCROLL_ATTEMPTS
        local function scroll_step(remaining)
            if remaining <= 0 then return end
            r.defer(function()
                if track and r.ValidatePtr(track, "MediaTrack*") then
                    ViewModeScrollTrackToCenter(track)
                    scroll_step(remaining - 1)
                end
            end)
        end
        scroll_step(attempts)
    end

    RoutingViewScan = function(source, depth)
        local result = { [source] = true }
        local send_frontier = { source }
        local receive_frontier = { source }
        local send_seen = { [source] = true }
        local receive_seen = { [source] = true }
        local master = r.GetMasterTrack(0)

        local function AddRoutingTrack(track, next_frontier, seen)
            if not (track and track ~= master and r.ValidatePtr(track, "MediaTrack*")) then return end
            result[track] = true
            if not seen[track] then
                seen[track] = true
                next_frontier[#next_frontier + 1] = track
            end
        end

        local function RoutingViewMainSendParent(track)
            if not (track and r.ValidatePtr(track, "MediaTrack*")) then return nil end
            local parent = r.GetParentTrack(track)
            if not (parent and parent ~= master and r.ValidatePtr(parent, "MediaTrack*")) then return nil end
            if r.GetMediaTrackInfo_Value(track, "B_MAINSEND") == 0 then return nil end
            return parent
        end

        local function AddDownstreamParentPath(track, next_frontier)
            local parent = RoutingViewMainSendParent(track)
            local first_parent = true
            while parent do
                result[parent] = true
                if first_parent and not send_seen[parent] then
                    send_seen[parent] = true
                    next_frontier[#next_frontier + 1] = parent
                end
                first_parent = false
                parent = RoutingViewMainSendParent(parent)
            end
        end

        local function AddUpstreamReceives(track, next_frontier)
            for s in pairs(RoutingViewGetRecvSources(track)) do
                AddRoutingTrack(s, next_frontier, receive_seen)
            end
        end

        for hop = 1, depth do
            local next_send_frontier = {}
            local next_receive_frontier = {}

            for _, trk in ipairs(send_frontier) do
                AddDownstreamParentPath(trk, next_send_frontier)
                for d in pairs(RoutingViewGetSendDests(trk)) do
                    AddRoutingTrack(d, next_send_frontier, send_seen)
                    AddDownstreamParentPath(d, next_send_frontier)
                end
            end

            for _, trk in ipairs(receive_frontier) do
                AddUpstreamReceives(trk, next_receive_frontier)
                for c in pairs(RoutingViewGetChildren(trk)) do
                    AddRoutingTrack(c, next_receive_frontier, receive_seen)
                    AddUpstreamReceives(c, next_receive_frontier)
                end
            end

            send_frontier = next_send_frontier
            receive_frontier = next_receive_frontier
            if #send_frontier == 0 and #receive_frontier == 0 then break end
        end

        return result
    end

    local function RoutingViewNormalizeSources(sources)
        local out = {}
        local seen = {}
        for _, source in ipairs(sources or {}) do
            if source and r.ValidatePtr(source, "MediaTrack*") and not seen[source] then
                out[#out + 1] = source
                seen[source] = true
            end
        end
        return out
    end

    local function RoutingViewCollectSelectedSources()
        local sources = {}
        local count = r.CountSelectedTracks(0)
        for i = 0, count - 1 do
            sources[#sources + 1] = r.GetSelectedTrack(0, i)
        end
        return RoutingViewNormalizeSources(sources)
    end

    local function RoutingViewStoreSources(sources)
        routing_view_sources = RoutingViewNormalizeSources(sources)
        routing_view_source = routing_view_sources[1]
    end

    local function RoutingViewCurrentSources()
        local sources = RoutingViewNormalizeSources(routing_view_sources)
        if #sources == 0 and routing_view_source and r.ValidatePtr(routing_view_source, "MediaTrack*") then
            sources[1] = routing_view_source
        end
        return sources
    end

    local function RoutingViewScanSources(sources, depth)
        local result = {}
        for _, source in ipairs(sources or {}) do
            for track in pairs(RoutingViewScan(source, depth)) do
                result[track] = true
            end
        end
        return result
    end

    local function RoutingViewSourceSet(sources)
        local result = {}
        for _, source in ipairs(sources or {}) do
            result[source] = true
        end
        return result
    end

    local function SelectedViewCollectTracks()
        local tracks = {}
        local count = r.CountSelectedTracks(0)
        for i = 0, count - 1 do
            local track = r.GetSelectedTrack(0, i)
            if track and r.ValidatePtr(track, "MediaTrack*") then
                tracks[track] = true
            end
        end
        return tracks
    end

    ArmedViewCollectTracks = function()
        local tracks = {}
        local nt = r.CountTracks(0)
        for ti = 0, nt - 1 do
            local track = r.GetTrack(0, ti)
            if track and r.GetMediaTrackInfo_Value(track, "I_RECARM") == 1 then
                tracks[track] = true
            end
        end
        return tracks
    end

    SelectedViewHasSelection = function()
        return r.CountSelectedTracks(0) > 0
    end

    ArmedViewHasTracks = function()
        return ViewModeFirstTrackInSet(ArmedViewCollectTracks()) ~= nil
    end

    local view_mode_project_states = {}
    local view_mode_project_key = nil

    local function ViewModeCurrentProject()
        local proj = r.EnumProjects and r.EnumProjects(-1, "") or nil
        local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
        return tostring(proj or "0") .. "|" .. tostring(master or "")
    end

    local function ViewModeTrackGuid(track)
        if track and r.ValidatePtr(track, "MediaTrack*") then
            return r.GetTrackGUID(track)
        end
        return nil
    end

    local function ViewModeFindTrackByGuid(guid)
        if not guid then return nil end
        local nt = r.CountTracks(0)
        for ti = 0, nt - 1 do
            local t = r.GetTrack(0, ti)
            if r.GetTrackGUID(t) == guid then return t end
        end
        return nil
    end

    local function ViewModeCaptureTrackList(tracks)
        local guids = {}
        for _, track in ipairs(tracks or {}) do
            local guid = ViewModeTrackGuid(track)
            if guid then guids[#guids + 1] = guid end
        end
        return guids
    end

    local function ViewModeRestoreTrackList(guids)
        local tracks = {}
        local seen = {}
        for _, guid in ipairs(guids or {}) do
            local track = ViewModeFindTrackByGuid(guid)
            if track and not seen[track] then
                tracks[#tracks + 1] = track
                seen[track] = true
            end
        end
        return tracks
    end

    local function ViewModeCaptureTrackSet(track_set)
        local guids = {}
        for track, enabled in pairs(track_set or {}) do
            if enabled then
                local guid = ViewModeTrackGuid(track)
                if guid then guids[guid] = true end
            end
        end
        return guids
    end

    local function ViewModeRestoreTrackSet(guids)
        local track_set = {}
        if not guids then return track_set end
        local nt = r.CountTracks(0)
        for ti = 0, nt - 1 do
            local t = r.GetTrack(0, ti)
            if guids[r.GetTrackGUID(t)] then track_set[t] = true end
        end
        return track_set
    end

    local function ViewModeCapturePeakTimes()
        local peaks = {}
        for track, last_t in pairs(active_view_peak_times or {}) do
            local guid = ViewModeTrackGuid(track)
            if guid then peaks[guid] = last_t end
        end
        return peaks
    end

    local function ViewModeRestorePeakTimes(peaks)
        local peak_times = {}
        if not peaks then return peak_times end
        local nt = r.CountTracks(0)
        for ti = 0, nt - 1 do
            local t = r.GetTrack(0, ti)
            local last_t = peaks[r.GetTrackGUID(t)]
            if last_t then peak_times[t] = last_t end
        end
        return peak_times
    end

    local function ViewModeCaptureProjectState()
        local routing_sources = RoutingViewCurrentSources()
        return {
            routing_active = routing_view_active or false,
            routing_source_guid = ViewModeTrackGuid(routing_view_source),
            routing_source_guids = ViewModeCaptureTrackList(routing_sources),
            routing_tracks = ViewModeCaptureTrackSet(routing_view_tracks),
            routing_saved_snap = routing_view_saved_snap,
            selected_active = selected_view_active or false,
            selected_tracks = ViewModeCaptureTrackSet(selected_view_tracks),
            selected_saved_snap = selected_view_saved_snap,
            armed_active = armed_view_active or false,
            armed_tracks = ViewModeCaptureTrackSet(armed_view_tracks),
            armed_saved_snap = armed_view_saved_snap,
            active_active = active_view_active or false,
            active_tracks = ViewModeCaptureTrackSet(active_view_tracks),
            active_peaks = ViewModeCapturePeakTimes(),
            active_signal_available = active_view_signal_available or false,
            active_last_play = active_view_last_play or 0,
            active_saved_snap = active_view_saved_snap,
        }
    end

    local function ViewModeResetProjectState()
        routing_view_active = false
        routing_view_source = nil
        routing_view_sources = {}
        routing_view_tracks = {}
        routing_view_saved_snap = nil
        selected_view_active = false
        selected_view_tracks = {}
        selected_view_saved_snap = nil
        armed_view_active = false
        armed_view_tracks = {}
        armed_view_saved_snap = nil
        active_view_active = false
        active_view_tracks = {}
        active_view_peak_times = {}
        active_view_signal_available = false
        active_view_last_play = r.GetPlayState()
        active_view_saved_snap = nil
        active_view_flash_time = 0
    end

    local function ViewModeRestoreProjectState(state)
        ViewModeResetProjectState()
        if not state then return end

        if state.routing_active then
            local sources = ViewModeRestoreTrackList(state.routing_source_guids)
            if #sources == 0 then
                local source = ViewModeFindTrackByGuid(state.routing_source_guid)
                if source then sources[1] = source end
            end
            if #sources > 0 then
                routing_view_active = true
                RoutingViewStoreSources(sources)
                routing_view_tracks = RoutingViewScanSources(routing_view_sources, routing_view_depth)
                routing_view_saved_snap = state.routing_saved_snap
            end
        end

        selected_view_active = state.selected_active or false
        selected_view_tracks = ViewModeRestoreTrackSet(state.selected_tracks)
        selected_view_saved_snap = state.selected_saved_snap
        if selected_view_active and not next(selected_view_tracks) then
            selected_view_active = false
            selected_view_saved_snap = nil
        end

        armed_view_active = state.armed_active or false
        armed_view_tracks = ViewModeRestoreTrackSet(state.armed_tracks)
        armed_view_saved_snap = state.armed_saved_snap
        if armed_view_active and not next(armed_view_tracks) then
            armed_view_active = false
            armed_view_saved_snap = nil
        end

        active_view_active = state.active_active or false
        active_view_tracks = ViewModeRestoreTrackSet(state.active_tracks)
        active_view_peak_times = ViewModeRestorePeakTimes(state.active_peaks)
        active_view_signal_available = state.active_signal_available or false
        active_view_last_play = state.active_last_play or r.GetPlayState()
        active_view_saved_snap = state.active_saved_snap
    end

    ViewModeRememberProjectState = function()
        local cur = ViewModeCurrentProject()
        if not cur then return end
        if not view_mode_project_key then view_mode_project_key = cur end
        view_mode_project_states[view_mode_project_key] = ViewModeCaptureProjectState()
    end

    MaybeSyncViewModeProject = function()
        local cur = ViewModeCurrentProject()
        if not cur then return false end
        if not view_mode_project_key then
            view_mode_project_key = cur
            view_mode_project_states[cur] = ViewModeCaptureProjectState()
            return false
        end
        if cur == view_mode_project_key then return false end

        view_mode_project_states[view_mode_project_key] = ViewModeCaptureProjectState()
        view_mode_project_key = cur
        ViewModeRestoreProjectState(view_mode_project_states[cur])
        return true
    end

    -- Exit special view modes, restoring their saved snapshots.
    -- Called from any visibility-affecting action (TLT click, song click, show all, etc.)
    ExitSpecialViews = function()
        local restored = false
        local exited = false
        if active_view_active then
            exited = true
            active_view_active = false
            active_view_tracks = {}
            if active_view_saved_snap then
                ViewHistoryRestore(active_view_saved_snap)
                active_view_saved_snap = nil
                restored = true
            end
        end
        if armed_view_active then
            exited = true
            armed_view_active = false
            armed_view_tracks = {}
            if armed_view_saved_snap then
                ViewHistoryRestore(armed_view_saved_snap)
                armed_view_saved_snap = nil
                restored = true
            end
        end
        if routing_view_active then
            exited = true
            routing_view_active = false
            routing_view_source = nil
            routing_view_sources = {}
            routing_view_tracks = {}
            if routing_view_saved_snap then
                ViewHistoryRestore(routing_view_saved_snap)
                routing_view_saved_snap = nil
                restored = true
            end
        end
        if selected_view_active then
            exited = true
            selected_view_active = false
            selected_view_tracks = {}
            if selected_view_saved_snap then
                ViewHistoryRestore(selected_view_saved_snap)
                selected_view_saved_snap = nil
                restored = true
            end
        end
        if exited then markDirty() end
        ViewModeRememberProjectState()
        return restored
    end

    local function ViewModeExpandFoldersForTrackSet(track_set)
        local master = r.GetMasterTrack(0)
        for track, enabled in pairs(track_set or {}) do
            if enabled and track and r.ValidatePtr(track, "MediaTrack*") then
                if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
                    r.SetMediaTrackInfo_Value(track, "I_FOLDERCOMPACT", 0)
                end
                local parent = r.GetParentTrack(track)
                while parent and parent ~= master do
                    r.SetMediaTrackInfo_Value(parent, "I_FOLDERCOMPACT", 0)
                    parent = r.GetParentTrack(parent)
                end
            end
        end
    end

    RoutingViewApply = function()
        local sources = RoutingViewCurrentSources()
        if #sources == 0 then
            routing_view_active = false
            routing_view_source = nil
            routing_view_sources = {}
            markDirty()
            ViewModeRememberProjectState()
            return
        end
        RoutingViewStoreSources(sources)
        routing_view_tracks = RoutingViewScanSources(routing_view_sources, routing_view_depth)

        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        local nt = r.CountTracks(0)
        for ti = 0, nt - 1 do
            local t = r.GetTrack(0, ti)
            local show = routing_view_tracks[t] and 1 or 0
            r.SetMediaTrackInfo_Value(t, "B_SHOWINTCP", show)
            r.SetMediaTrackInfo_Value(t, "B_SHOWINMIXER", show)
        end
        ViewModeExpandFoldersForTrackSet(routing_view_tracks)
        r.PreventUIRefresh(-1)
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock("Track Navigator: Routing View", 0)
        ViewModeDeferScroll(ViewModeFirstTrackInSet(RoutingViewSourceSet(routing_view_sources)))
        markDirty()
        ViewModeRememberProjectState()
    end

    RoutingViewToggle = function()
        ViewHistoryPush()
        if routing_view_active then
            -- Exit: restore pre-entry snapshot
            routing_view_active = false
            routing_view_source = nil
            routing_view_sources = {}
            routing_view_tracks = {}
            if routing_view_saved_snap then
                ViewHistoryRestore(routing_view_saved_snap)
                routing_view_saved_snap = nil
            end
            markDirty()
        else
            local sources = RoutingViewCollectSelectedSources()
            if #sources == 0 then return end
            -- Silently discard other special view (no restore; current view becomes the new baseline)
            if active_view_active then
                active_view_active = false; active_view_tracks = {}; active_view_saved_snap = nil
            end
            if selected_view_active then
                selected_view_active = false; selected_view_tracks = {}; selected_view_saved_snap = nil
            end
            if armed_view_active then
                armed_view_active = false; armed_view_tracks = {}; armed_view_saved_snap = nil
            end
            -- Save current state (may be another mode's filtered view), then apply routing
            routing_view_saved_snap = ViewHistorySnapshot({ work_state = true })
            routing_view_active = true
            RoutingViewStoreSources(sources)
            RoutingViewApply()
        end
        ViewModeRememberProjectState()
    end

    RoutingViewRefreshFromSelection = function()
        local sources = RoutingViewCollectSelectedSources()
        if #sources == 0 then return false end
        if not routing_view_active then
            RoutingViewToggle()
            return true
        end
        RoutingViewStoreSources(sources)
        RoutingViewApply()
        return true
    end

    RoutingViewExit = function()
        if not routing_view_active then return end
        routing_view_active = false
        routing_view_source = nil
        routing_view_sources = {}
        routing_view_tracks = {}
        if routing_view_saved_snap then
            ViewHistoryRestore(routing_view_saved_snap)
            routing_view_saved_snap = nil
        end
        markDirty()
        ViewModeRememberProjectState()
    end

    SelectedViewApply = function()
        if not next(selected_view_tracks) then
            selected_view_active = false
            markDirty()
            ViewModeRememberProjectState()
            return
        end

        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        local nt = r.CountTracks(0)
        for ti = 0, nt - 1 do
            local t = r.GetTrack(0, ti)
            local show = selected_view_tracks[t] and 1 or 0
            r.SetMediaTrackInfo_Value(t, "B_SHOWINTCP", show)
            r.SetMediaTrackInfo_Value(t, "B_SHOWINMIXER", show)
        end
        ViewModeExpandFoldersForTrackSet(selected_view_tracks)
        r.PreventUIRefresh(-1)
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock("Track Navigator: Selected Tracks View", 0)
        ViewModeDeferScroll(ViewModeFirstTrackInSet(selected_view_tracks))
        markDirty()
        ViewModeRememberProjectState()
    end

    SelectedViewToggle = function()
        ViewHistoryPush()
        if selected_view_active then
            selected_view_active = false
            selected_view_tracks = {}
            if selected_view_saved_snap then
                ViewHistoryRestore(selected_view_saved_snap)
                selected_view_saved_snap = nil
            end
            markDirty()
        else
            local tracks = SelectedViewCollectTracks()
            if not next(tracks) then return end
            if routing_view_active then
                routing_view_active = false; routing_view_source = nil; routing_view_sources = {}; routing_view_tracks = {}; routing_view_saved_snap = nil
            end
            if active_view_active then
                active_view_active = false; active_view_tracks = {}; active_view_saved_snap = nil
            end
            if armed_view_active then
                armed_view_active = false; armed_view_tracks = {}; armed_view_saved_snap = nil
            end
            selected_view_saved_snap = ViewHistorySnapshot({ work_state = true })
            selected_view_active = true
            selected_view_tracks = tracks
            SelectedViewApply()
        end
        ViewModeRememberProjectState()
    end

    SelectedViewRefreshFromSelection = function()
        local tracks = SelectedViewCollectTracks()
        if not next(tracks) then return false end
        if not selected_view_active then
            SelectedViewToggle()
            return true
        end
        selected_view_tracks = tracks
        SelectedViewApply()
        return true
    end

    SelectedViewExit = function()
        if not selected_view_active then return end
        selected_view_active = false
        selected_view_tracks = {}
        if selected_view_saved_snap then
            ViewHistoryRestore(selected_view_saved_snap)
            selected_view_saved_snap = nil
        end
        markDirty()
        ViewModeRememberProjectState()
    end

    ArmedViewApply = function()
        if not next(armed_view_tracks) then
            armed_view_active = false
            markDirty()
            ViewModeRememberProjectState()
            return false
        end

        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        local nt = r.CountTracks(0)
        for ti = 0, nt - 1 do
            local t = r.GetTrack(0, ti)
            local show = armed_view_tracks[t] and 1 or 0
            r.SetMediaTrackInfo_Value(t, "B_SHOWINTCP", show)
            r.SetMediaTrackInfo_Value(t, "B_SHOWINMIXER", show)
        end
        ViewModeExpandFoldersForTrackSet(armed_view_tracks)
        r.PreventUIRefresh(-1)
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock("Track Navigator: Armed View", 0)
        ViewModeDeferScroll(ViewModeFirstTrackInSet(armed_view_tracks))
        markDirty()
        ViewModeRememberProjectState()
        return true
    end

    ArmedViewToggle = function()
        ViewHistoryPush()
        if armed_view_active then
            armed_view_active = false
            armed_view_tracks = {}
            if armed_view_saved_snap then
                ViewHistoryRestore(armed_view_saved_snap)
                armed_view_saved_snap = nil
            end
            markDirty()
        else
            local tracks = ArmedViewCollectTracks()
            if not next(tracks) then return false end
            if routing_view_active then
                routing_view_active = false; routing_view_source = nil; routing_view_sources = {}; routing_view_tracks = {}; routing_view_saved_snap = nil
            end
            if selected_view_active then
                selected_view_active = false; selected_view_tracks = {}; selected_view_saved_snap = nil
            end
            if active_view_active then
                active_view_active = false; active_view_tracks = {}; active_view_saved_snap = nil
            end
            armed_view_saved_snap = ViewHistorySnapshot({ work_state = true })
            armed_view_active = true
            armed_view_tracks = tracks
            ArmedViewApply()
        end
        ViewModeRememberProjectState()
        return true
    end

    ArmedViewRefreshFromRecordArm = function()
        local tracks = ArmedViewCollectTracks()
        if not next(tracks) then return false end
        if not armed_view_active then
            ArmedViewToggle()
            return true
        end
        armed_view_tracks = tracks
        ArmedViewApply()
        return true
    end

    ArmedViewExit = function()
        if not armed_view_active then return end
        armed_view_active = false
        armed_view_tracks = {}
        if armed_view_saved_snap then
            ViewHistoryRestore(armed_view_saved_snap)
            armed_view_saved_snap = nil
        end
        markDirty()
        ViewModeRememberProjectState()
    end

    TrackNavigatorScrollToRecordArmed = function()
        local track = ViewModeFirstTrackInSet(ArmedViewCollectTracks())
        if not track then return false end
        if r.SetOnlyTrackSelected then r.SetOnlyTrackSelected(track) end
        if r.UpdateArrange then r.UpdateArrange() end
        ViewModeDeferScroll(track)
        return true
    end

    -- Throttled peak scan: update active_view_peak_times for Active View.
    ActiveViewUpdatePeaks = function()
        local now = r.time_precise()
        -- Flush peaks on play/stop transitions (clears stale data from previous section)
        local ps = r.GetPlayState()
        local was_transport_active = (active_view_last_play & 1) == 1 or (active_view_last_play & 4) == 4
        local transport_active = (ps & 1) == 1 or (ps & 4) == 4
        if transport_active ~= was_transport_active then
            active_view_peak_times = {}
            active_view_signal_available = false
            active_view_last_peak_scan_time = 0
        end
        active_view_last_play = ps
        local interval = transport_active and (active_view_peak_scan_interval or 0.10)
            or (active_view_idle_peak_scan_interval or 0.50)
        if active_view_active and active_view_peak_scan_interval then
            interval = math.min(interval, active_view_peak_scan_interval)
        end
        if active_view_last_peak_scan_time and active_view_last_peak_scan_time > 0
            and now - active_view_last_peak_scan_time < interval then
            return
        end
        active_view_last_peak_scan_time = now

        local nt = r.CountTracks(0)
        local any_solo = false
        for ti = 0, nt - 1 do
            local t = r.GetTrack(0, ti)
            if r.GetMediaTrackInfo_Value(t, "I_SOLO") > 0 then any_solo = true end
            local peak = math.max(r.Track_GetPeakInfo(t, 0), r.Track_GetPeakInfo(t, 1))
            if peak >= active_view_threshold then
                active_view_peak_times[t] = now
            end
        end
        -- Prune entries older than window (avoid unbounded growth) and cache
        -- whether Active View can currently be entered.
        local cutoff = now - active_view_window - 1
        local signal_cutoff = now - active_view_window
        local signal_available = false
        for t, last_t in pairs(active_view_peak_times) do
            if last_t < cutoff or not r.ValidatePtr(t, "MediaTrack*") then
                active_view_peak_times[t] = nil
            elseif last_t >= signal_cutoff then
                if not any_solo or r.GetMediaTrackInfo_Value(t, "I_SOLO") > 0 then
                    signal_available = true
                end
            end
        end
        active_view_signal_available = signal_available
    end

    ActiveViewHasSignal = function()
        if active_view_signal_available ~= nil then
            return active_view_signal_available
        end
        local now = r.time_precise()
        local cutoff = now - active_view_window
        local nt = r.CountTracks(0)
        local any_solo = false
        for ti = 0, nt - 1 do
            if r.GetMediaTrackInfo_Value(r.GetTrack(0, ti), "I_SOLO") > 0 then
                any_solo = true
                break
            end
        end
        for t, last_t in pairs(active_view_peak_times) do
            if last_t >= cutoff and r.ValidatePtr(t, "MediaTrack*") then
                if not any_solo or r.GetMediaTrackInfo_Value(t, "I_SOLO") > 0 then
                    return true
                end
            end
        end
        return false
    end

    -- Collect tracks that were active within the time window, then expand forward-only
    -- (parents, children, send destinations; NO receives, to avoid pulling in unrelated tracks).
    ActiveViewScan = function()
        local now = r.time_precise()
        local cutoff = now - active_view_window
        -- Check if any track is soloed
        local nt = r.CountTracks(0)
        local any_solo = false
        for ti = 0, nt - 1 do
            if r.GetMediaTrackInfo_Value(r.GetTrack(0, ti), "I_SOLO") > 0 then any_solo = true; break end
        end
        -- Collect active sources (peak above threshold, respecting solo)
        local sources = {}
        for t, last_t in pairs(active_view_peak_times) do
            if last_t >= cutoff and r.ValidatePtr(t, "MediaTrack*") then
                if not any_solo or r.GetMediaTrackInfo_Value(t, "I_SOLO") > 0 then
                    sources[#sources + 1] = t
                end
            end
        end
        -- Forward-only scan for each active source
        local result = {}
        local master = r.GetMasterTrack(0)
        for _, src in ipairs(sources) do
            result[src] = true
            local frontier = { src }
            for hop = 1, routing_view_depth do
                local next_frontier = {}
                for _, trk in ipairs(frontier) do
                    -- Parents (folder hierarchy up)
                    for p in pairs(RoutingViewGetParentChain(trk)) do
                        if p ~= master and not result[p] then result[p] = true; next_frontier[#next_frontier + 1] = p end
                    end
                    -- Send destinations (parallel routes forward)
                    for d in pairs(RoutingViewGetSendDests(trk)) do
                        if d ~= master and not result[d] then result[d] = true; next_frontier[#next_frontier + 1] = d end
                    end
                    -- NO children or receives; only forward signal path
                end
                frontier = next_frontier
                if #frontier == 0 then break end
            end
        end
        -- Ensure parent folders of all visible tracks are also visible
        local parents_to_add = {}
        for trk in pairs(result) do
            local parent = r.GetParentTrack(trk)
            while parent and parent ~= master do
                if not result[parent] then parents_to_add[parent] = true end
                parent = r.GetParentTrack(parent)
            end
        end
        for p in pairs(parents_to_add) do result[p] = true end
        return result
    end

    ActiveViewApply = function()
        active_view_tracks = ActiveViewScan()
        if not next(active_view_tracks) then
            markDirty()
            ViewModeRememberProjectState()
            return
        end
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        local nt = r.CountTracks(0)
        for ti = 0, nt - 1 do
            local t = r.GetTrack(0, ti)
            local show = active_view_tracks[t] and 1 or 0
            r.SetMediaTrackInfo_Value(t, "B_SHOWINTCP", show)
            r.SetMediaTrackInfo_Value(t, "B_SHOWINMIXER", show)
        end
        ViewModeExpandFoldersForTrackSet(active_view_tracks)
        r.PreventUIRefresh(-1)
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock("Track Navigator: Active View", 0)
        ViewModeDeferScroll(ViewModeFirstTrackInSet(active_view_tracks))
        markDirty()
        ViewModeRememberProjectState()
    end

    ActiveViewToggle = function()
        if active_view_active then
            -- Already active: refresh (re-snapshot active tracks, keep original saved_snap).
            -- Keep state even if re-scan is empty; user is in the mode, silence is transient.
            active_view_flash_time = r.time_precise()
            ActiveViewApply()
        else
            -- Entering: scan first. If no active tracks exist, don't enter the mode;
            -- the disabled NAV A tooltip explains the unavailable state.
            local scan = ActiveViewScan()
            if not next(scan) then
                return
            end
            active_view_flash_time = r.time_precise()
            -- Silently discard other special view (no restore; current view becomes the new baseline)
            if routing_view_active then
                routing_view_active = false; routing_view_source = nil; routing_view_sources = {}; routing_view_tracks = {}; routing_view_saved_snap = nil
            end
            if selected_view_active then
                selected_view_active = false; selected_view_tracks = {}; selected_view_saved_snap = nil
            end
            if armed_view_active then
                armed_view_active = false; armed_view_tracks = {}; armed_view_saved_snap = nil
            end
            -- Save current state (may be another mode's filtered view), then apply active
            active_view_saved_snap = ViewHistorySnapshot({ work_state = true })
            active_view_active = true
            active_view_tracks = scan
            ActiveViewApply()
        end
        ViewModeRememberProjectState()
    end

    ActiveViewExit = function()
        if not active_view_active then return end
        active_view_active = false
        active_view_tracks = {}
        -- Restore pre-entry visibility
        if active_view_saved_snap then
            ViewHistoryRestore(active_view_saved_snap)
            active_view_saved_snap = nil
        end
        markDirty()
        ViewModeRememberProjectState()
    end
end

return ReflexInstallViewModes
