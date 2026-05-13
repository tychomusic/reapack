-- @noindex
-- Reflex view-mode backend module.
-- Installs Routing View and Active View scan/apply/toggle helpers.

ReflexInstallViewModes = function(deps)
    local r = deps.r

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
        local nt = r.CountTracks(0)
        local depth, i = 1, idx + 1
        while i < nt and depth > 0 do
            local c = r.GetTrack(0, i)
            children[c] = true
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

    ViewModeDeferScroll = function(track)
        if not (track and r.ValidatePtr(track, "MediaTrack*")) then return end
        r.defer(function()
            if track and r.ValidatePtr(track, "MediaTrack*") then
                ViewModeScrollTrackToCenter(track)
            end
        end)
    end

    RoutingViewScan = function(source, depth)
        local result = { [source] = true }
        local frontier = { source }
        local master = r.GetMasterTrack(0)

        for hop = 1, depth do
            local next_frontier = {}
            for _, trk in ipairs(frontier) do
                -- Parents
                for p in pairs(RoutingViewGetParentChain(trk)) do
                    if p ~= master and not result[p] then result[p] = true; next_frontier[#next_frontier + 1] = p end
                end
                -- Children
                for c in pairs(RoutingViewGetChildren(trk)) do
                    if c ~= master and not result[c] then result[c] = true; next_frontier[#next_frontier + 1] = c end
                end
                -- Sends
                for d in pairs(RoutingViewGetSendDests(trk)) do
                    if d ~= master and not result[d] then result[d] = true; next_frontier[#next_frontier + 1] = d end
                end
                -- Receives
                for s in pairs(RoutingViewGetRecvSources(trk)) do
                    if s ~= master and not result[s] then result[s] = true; next_frontier[#next_frontier + 1] = s end
                end
            end
            frontier = next_frontier
            if #frontier == 0 then break end
        end

        -- Also add parent chain of every track in result (so they're visible in TCP)
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

    local view_mode_project_states = {}
    local view_mode_project_key = nil

    local function ViewModeCurrentProject()
        return r.EnumProjects(-1)
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
        return {
            routing_active = routing_view_active or false,
            routing_source_guid = ViewModeTrackGuid(routing_view_source),
            routing_tracks = ViewModeCaptureTrackSet(routing_view_tracks),
            routing_saved_snap = routing_view_saved_snap,
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
        routing_view_tracks = {}
        routing_view_saved_snap = nil
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
            local source = ViewModeFindTrackByGuid(state.routing_source_guid)
            if source then
                routing_view_active = true
                routing_view_source = source
                routing_view_tracks = RoutingViewScan(source, routing_view_depth)
                routing_view_saved_snap = state.routing_saved_snap
            end
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

    -- Exit both special view modes, restoring their saved snapshots.
    -- Called from any visibility-affecting action (TLT click, song click, show all, etc.)
    ExitSpecialViews = function()
        local restored = false
        if active_view_active then
            active_view_active = false
            active_view_tracks = {}
            if active_view_saved_snap then
                ViewHistoryRestore(active_view_saved_snap)
                active_view_saved_snap = nil
                restored = true
            end
        end
        if routing_view_active then
            routing_view_active = false
            routing_view_source = nil
            routing_view_tracks = {}
            if routing_view_saved_snap then
                ViewHistoryRestore(routing_view_saved_snap)
                routing_view_saved_snap = nil
                restored = true
            end
        end
        ViewModeRememberProjectState()
        return restored
    end

    RoutingViewApply = function()
        if not routing_view_source or not r.ValidatePtr(routing_view_source, "MediaTrack*") then
            routing_view_active = false
            ViewModeRememberProjectState()
            return
        end
        routing_view_tracks = RoutingViewScan(routing_view_source, routing_view_depth)

        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        local nt = r.CountTracks(0)
        for ti = 0, nt - 1 do
            local t = r.GetTrack(0, ti)
            local show = routing_view_tracks[t] and 1 or 0
            r.SetMediaTrackInfo_Value(t, "B_SHOWINTCP", show)
            r.SetMediaTrackInfo_Value(t, "B_SHOWINMIXER", show)
        end
        -- Uncollapse folder parents of visible tracks
        for ti = 0, nt - 1 do
            local t = r.GetTrack(0, ti)
            if routing_view_tracks[t] and r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH") == 1 then
                r.SetMediaTrackInfo_Value(t, "I_FOLDERCOMPACT", 0)
            end
        end
        r.PreventUIRefresh(-1)
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock("Envision: Routing View", 0)
        ViewModeDeferScroll(routing_view_source)
        ViewModeRememberProjectState()
    end

    RoutingViewToggle = function()
        ViewHistoryPush()
        if routing_view_active then
            -- Exit: restore pre-entry snapshot
            routing_view_active = false
            routing_view_source = nil
            routing_view_tracks = {}
            if routing_view_saved_snap then
                ViewHistoryRestore(routing_view_saved_snap)
                routing_view_saved_snap = nil
            end
        else
            local sel = r.CountSelectedTracks(0) > 0 and r.GetSelectedTrack(0, 0) or nil
            if not sel then return end
            -- Silently discard other special view (no restore; current view becomes the new baseline)
            if active_view_active then
                active_view_active = false; active_view_tracks = {}; active_view_saved_snap = nil
            end
            -- Save current state (may be another mode's filtered view), then apply routing
            routing_view_saved_snap = ViewHistorySnapshot()
            routing_view_active = true
            routing_view_source = sel
            RoutingViewApply()
        end
        ViewModeRememberProjectState()
    end

    -- Per-frame peak scan: update active_view_peak_times for all tracks.
    -- Called every frame; cheap (~1 C call per track via Track_GetPeakInfo).
    ActiveViewUpdatePeaks = function()
        local now = r.time_precise()
        -- Flush peaks on play/stop transitions (clears stale data from previous section)
        local ps = r.GetPlayState()
        local was_playing = (active_view_last_play & 1) == 1
        local is_playing = (ps & 1) == 1
        if is_playing ~= was_playing then
            active_view_peak_times = {}
        end
        active_view_last_play = ps
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
        for ti = 0, nt - 1 do
            local t = r.GetTrack(0, ti)
            if active_view_tracks[t] and r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH") == 1 then
                r.SetMediaTrackInfo_Value(t, "I_FOLDERCOMPACT", 0)
            end
        end
        r.PreventUIRefresh(-1)
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock("Envision: Active View", 0)
        ViewModeDeferScroll(ViewModeFirstTrackInSet(active_view_tracks))
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
                routing_view_active = false; routing_view_source = nil; routing_view_tracks = {}; routing_view_saved_snap = nil
            end
            -- Save current state (may be another mode's filtered view), then apply active
            active_view_saved_snap = ViewHistorySnapshot()
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
        ViewModeRememberProjectState()
    end
end

return ReflexInstallViewModes
