-- @noindex
-- Reflex FX drag core module.
-- Installs FX drag/drop state, drop-target registry, automation-strip helper,
-- auto-scroll helpers, and drag resolution/overlay logic.

ReflexInstallFXDragCore = function(deps)
    local r = deps.r
    local ctx = deps.ctx
    local C = deps.colors

-- FX drag state (unified across inspector + sends view).
-- Built in v20.394 as foundation for cross-chain FX drag coming in v20.395+.
-- v20.403: src_fis can now be multi (inspector surface only) when inspector
-- has an active multi-selection at drag-activate time.
-- src_fis stored 0-based (matches REAPER API); inspector call sites convert on entry.
fx_drag = {
    active = false,           -- threshold passed? becomes true once mouse moves > threshold
    src_track = nil,          -- MediaTrack* of source
    src_track_guid = nil,     -- GUID for stability across ValidatePtr edges
    src_fis = nil,            -- { fi, ... } 0-based, ascending
    src_surface = nil,        -- "inspector" | "sends"
    start_mx = 0,
    start_my = 0,
    cancelled = false,        -- Escape pressed this frame; blocks commit
    tooltip_shown = false,    -- sticky: flips true once tooltip gate is first satisfied
    src_chain_rect = nil,     -- {x,y,w,h} of source chain body; used for "left source chain" check
    is_instr = false,         -- (v20.403) seed FX is an instrument; colors row-style preview text
}

FX_DRAG_THRESHOLD = 8         -- logical px before drag flips active; S() scales it at use sites

-- Last-frame DRAG hover target (v20.412). Kept for compatibility with older
-- card-stroke suppression paths; target-card dashed outlines are no longer drawn.
nav_fx_drag_last_hover_track = nil

-- Seed drag state on mouse-down over an FX row.
-- track: MediaTrack*, fi: 0-based FX index, surface: "inspector" | "sends".
-- Does NOT mark active; threshold must be exceeded via FxDragTryActivate.
FxDragBegin = function(track, fi, surface)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    local mx, my = r.ImGui_GetMousePos(ctx)
    fx_drag.active = false
    fx_drag.src_track = track
    fx_drag.src_track_guid = r.GetTrackGUID(track)
    fx_drag.src_fis = { fi }
    fx_drag.src_surface = surface
    fx_drag.start_mx = mx
    fx_drag.start_my = my
    fx_drag.cancelled = false
    fx_drag.tooltip_shown = false
    fx_drag.src_chain_rect = nil
    -- Cache instrument flag once at seed time — FX identity can't change
    -- mid-drag, and checking each frame would cost an API call per hover.
    fx_drag.is_instr = false
    local rv_ft, ft_str = r.TrackFX_GetNamedConfigParm(track, fi, "fx_type")
    if rv_ft and ft_str and ft_str:match("i$") then fx_drag.is_instr = true end
    -- v20.406: cache seed GUID. FxDragTryActivate previously looked up the
    -- seed's guid by iterating insp_fx, which is the INSPECTED track's FX
    -- cache — wrong for sends drags or secondary-card drags. Caching at
    -- seed time avoids needing to know which cache holds the FX later.
    fx_drag.seed_guid = r.TrackFX_GetFXGUID(track, fi) or ""
end

-- Check whether mouse has moved past threshold since drag seed. Once true, stays true.
-- Returns current active state.
--
-- v20.403: On the frame we flip to active, expand src_fis from the inspector
-- multi-selection if one exists. Three cases:
--   (a) no selection:                    src_fis stays [seed_fi]
--   (b) selection exists, seed in it:    src_fis becomes the full selection
--   (c) selection exists, seed NOT in it: promote seed into selection, then (b)
-- Case (c) is Option C: dragging an unselected row with a live selection
-- grabs it too, matching the spec "drag unselected row → promotes AND drags".
-- Promotion happens here (at activate) rather than at seed (mouse-down) so
-- Cmd+click with no drag doesn't visually churn — a Cmd+click that never
-- exceeds threshold is a plain toggle, unaffected by promotion.
--
-- v20.406: Removed the `src_track == insp_track` gate (which broke secondary-
-- card drags in pinned mode and made sends-surface drags ignore selection).
-- Selection is bound to ANY track via `insp_fx_sel_track`; as long as the
-- drag source matches that binding, promotion applies. Seed-guid lookup now
-- uses the cached `fx_drag.seed_guid` (from FxDragBegin) instead of iterating
-- `insp_fx` — which only holds the inspected track's FX and was wrong for
-- secondary/sends sources. Works for all three surfaces: inspector, secondary
-- card (pinned mode), and sends modules.
FxDragTryActivate = function()
    if fx_drag.active or not fx_drag.src_track then return fx_drag.active end
    local _, my = r.ImGui_GetMousePos(ctx)
    if math.abs(my - fx_drag.start_my) > S(FX_DRAG_THRESHOLD) then
        fx_drag.active = true
        -- Multi-select expansion — selection must be bound to the track we're
        -- dragging from. No surface restriction: sends and secondary drags
        -- can also adopt the selection.
        if insp_fx_sel_track == fx_drag.src_track
           and InspFxSelCount() > 0 then
            local seed_guid = fx_drag.seed_guid
            if seed_guid and seed_guid ~= "" and not insp_fx_sel[seed_guid] then
                InspFxSelAdd(seed_guid)  -- case (c): promote clicked row
            end
            local sel_fis = InspFxSelGetFis(fx_drag.src_track)
            if #sel_fis > 0 then fx_drag.src_fis = sel_fis end
        end
    end
    return fx_drag.active
end

-- Release all drag state. Call on commit, release-without-drop, abort, track switch, etc.
FxDragClear = function()
    -- v20.431: revert any minimal cards that were auto-expanded during
    -- drag-hover but did NOT receive the drop. FxDragResolveDrop's commit
    -- path removes the dropped-onto track from this list before calling
    -- FxDragClear, so committed targets stay expanded.
    if fx_drag.flow_auto_expanded and flow_view_expanded_set then
        for t in pairs(fx_drag.flow_auto_expanded) do
            flow_view_expanded_set[t] = nil
        end
    end
    fx_drag.flow_auto_expanded = nil
    fx_drag.active = false
    fx_drag.src_track = nil
    fx_drag.src_track_guid = nil
    fx_drag.src_fis = nil
    fx_drag.src_surface = nil
    fx_drag.cancelled = false
    fx_drag.tooltip_shown = false
    fx_drag.src_chain_rect = nil
    fx_drag.is_instr = false
    fx_drag.seed_guid = nil
end

-- Predicate helpers for sites that need to gate other behavior during drag.
FxDragIsActive = function() return fx_drag.active end
FxDragSourceIs = function(track, surface)
    return fx_drag.src_track == track and (surface == nil or fx_drag.src_surface == surface)
end

-- Escape-to-cancel. Polled once per frame at top of Loop.
-- Sets cancelled so release-frame code blocks commit, then clears state.
-- v20.403: also clears FX multi-selection (Escape is the universal "cancel").
-- v20.410: also clears FX clipboard. Earlier spec ruled Esc safe (clipboard
-- preserved across Esc), but live testing showed the chip alone wasn't
-- intuitive as an exit path; users expect Esc to drop the carrying state.
-- There's no undo/restore for either selection or clipboard, so safety-of-
-- accidental-tap is a wash — intuitiveness wins. Chip × remains as mouse exit.
FxDragPollEscape = function()
    local esc_pressed = false
    if TrackNavigatorEscapePressed then
        esc_pressed = TrackNavigatorEscapePressed()
    elseif r.ImGui_IsKeyPressed and r.ImGui_Key_Escape then
        local ok_key, key = pcall(r.ImGui_Key_Escape)
        if ok_key then
            local ok_pressed, pressed = pcall(r.ImGui_IsKeyPressed, ctx, key)
            esc_pressed = ok_pressed and pressed == true
        end
    end
    if esc_pressed then
        if fx_drag.active or fx_drag.src_track then
            fx_drag.cancelled = true
            FxDragClear()
        end
        if InspFxSelCount() > 0 then InspFxSelClear() end
        if FxClipHasContent() then
            FxClipClear()
            FxClipRebuildGuidSet()
        end
    end
end

-- Read current drag mode from modifier state. Called each frame during drag
-- so visuals and release behavior reflect live modifier presses.
-- Returns operation, with_automation:
--   op = "move" | "copy"
--   with_auto = true | false
-- Mac-only modifier mapping (v20.401).
FxDragReadMode = function()
    local mods = r.ImGui_GetKeyMods(ctx)
    local is_cmd = IsCmd(mods)
    local is_opt = IsAlt(mods)
    if is_cmd then
        -- Copy: default = no automation; Opt adds it
        return "copy", is_opt
    else
        -- Move always carries automation with the FX.
        return "move", true
    end
end

-- Strip all automation from an FX on a track.
-- Called as post-step after TrackFX_CopyToTrack to implement "no automation" variants.
-- Covers regular params + :wet + :bypass envelopes.
--
-- IMPORTANT (v20.402 fix): GetFXEnvelope(..., create=false) can return a valid
-- envelope handle for :bypass even when the user never created one — REAPER
-- always maintains an implicit bypass envelope container. Poking that container
-- (flipping ACT/VIS on an envelope with zero points) creates a serialized-but-
-- hidden envelope lane that manifests as a "ghost lane" in the UI until the
-- track is refreshed. Fix: only act on envelopes that ACTUALLY HAVE CONTENT
-- (points or automation items with points). Empty envelopes are skipped entirely.
FxStripAutomation = function(track, fx_idx)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    if fx_idx < 0 or fx_idx >= r.TrackFX_GetCount(track) then return end

    -- Build param list: all visible params + special param idents
    local np = r.TrackFX_GetNumParams(track, fx_idx)
    local params = {}
    for p = 0, np - 1 do params[#params + 1] = p end
    if r.TrackFX_GetParamFromIdent then
        local wet = r.TrackFX_GetParamFromIdent(track, fx_idx, ":wet")
        if wet and wet >= 0 then params[#params + 1] = wet end
        local byp = r.TrackFX_GetParamFromIdent(track, fx_idx, ":bypass")
        if byp and byp >= 0 then params[#params + 1] = byp end
    end

    local did_strip = false
    for _, p in ipairs(params) do
        local env = r.GetFXEnvelope(track, fx_idx, p, false)  -- don't create
        if env then
            -- Tally all content: underlying points + points inside automation items
            local underlying_pts = r.CountEnvelopePointsEx(env, -1)
            local ai_count = r.CountAutomationItems(env)
            local ai_total_pts = 0
            for ai = 0, ai_count - 1 do
                ai_total_pts = ai_total_pts + r.CountEnvelopePointsEx(env, ai)
            end

            -- Only proceed if envelope has any actual content. This avoids
            -- poking REAPER's implicit bypass-envelope container, which would
            -- create a ghost lane with no visible content but a displayed slot.
            if underlying_pts > 0 or ai_total_pts > 0 then
                -- Delete automation-item points
                for ai = ai_count - 1, 0, -1 do
                    local ai_pts = r.CountEnvelopePointsEx(env, ai)
                    for i = ai_pts - 1, 0, -1 do
                        r.DeleteEnvelopePointEx(env, ai, i)
                    end
                end
                -- Delete underlying envelope points
                for i = underlying_pts - 1, 0, -1 do
                    r.DeleteEnvelopePointEx(env, -1, i)
                end
                -- Deactivate + hide: flip ACT and VIS flags so the lane disappears now
                if r.GetSetEnvelopeInfo_String then
                    r.GetSetEnvelopeInfo_String(env, "ACTIVE", "0", true)
                    r.GetSetEnvelopeInfo_String(env, "VISIBLE", "0", true)
                end
                did_strip = true
            end
        end
    end

    -- v20.402: After stripping a real envelope with points, REAPER's TCP layout
    -- doesn't immediately reclaim the now-hidden envelope's lane space. This
    -- produces a "ghost lane" — blank slot with no header/content — until the
    -- user navigates away and back. TrackList_AdjustWindows forces a layout
    -- recalc. Only called when we actually stripped something to avoid
    -- unnecessary refresh on no-op strip passes.
    if did_strip then
        r.TrackList_AdjustWindows(false)
    end
end

-- Format source track name for undo labels. Falls back to "Track N" when empty.
FxDragTrackLabel = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return "?" end
    local _, name = r.GetTrackName(track)
    if name and name ~= "" then return name end
    return "Track " .. math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
end

-- Pre-drag modifier legend. Shows drag modes when Cmd or Opt is held
-- over an FX row AND no drag is yet active. Gated on opt_tooltips (descriptive
-- category per v20.392 tooltip categorization). Call from FX row hover scope.
FxDragLegendTip = function()
    if not opt_tooltips then return end
    if fx_drag.active then return end
    local mods = r.ImGui_GetKeyMods(ctx)
    if not (IsCmd(mods) or IsAlt(mods)) then return end
    local legend =
        "drag: move\n" ..
        "⌘ drag: copy\n" ..
        "⌘⌥ drag: copy (with auto)"
    TipDirect(legend)
end

-- Drop-target registry (v20.396+).
-- Rebuilt each frame. Each entry describes one FX chain rendering surface.
-- Populated by surfaces during their render pass; consumed by FxDragResolveDrop
-- and FxClipResolveHover at end of frame. FxClipResolveHover snapshots the table
-- to fx_drop_targets_prev before clearing it so top-of-loop hotkeys can still
-- resolve the hovered card/row before the next render pass repopulates geometry.
-- Entry shape:
--   surface        : "inspector" | "secondary" | "return"
--   track          : MediaTrack* the chain belongs to
--   rects          : { [fi0] = {cy, h, cx, w} }  -- 0-based
--   fx_count       : number of rows in the chain
--   body_rect      : {x, y, w, h}  -- card-body hit area (for end-of-chain fallback)
--   card_id        : unique string ID (for ImGui scope)
fx_drop_targets = {}
fx_drop_targets_prev = {}

-- Auto-scroll request queue (v20.396+).
-- Drag hover detection writes pending scroll deltas here.
-- Each scrollable child reads + clears its own entry during BeginChild next frame.
fx_drag_scroll_req = {}   -- { ["##content"] = dy, ["##sends_content"] = dy }

-- Register a drop-target surface during a render pass.
-- Call from inside each FX chain rendering site AFTER building local rects.
-- fx_area_bottom_y is the screen-Y where the next FX row would appear (end of
-- FX area). row_x / row_w describe the x-bounds a row would occupy, used for
-- empty-chain indicator sizing so it matches a row's width, not the card's.
FxDropTargetRegister = function(surface, track, rects, fx_count, body_rect, card_id, fx_area_bottom_y, row_x, row_w)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    fx_drop_targets[#fx_drop_targets + 1] = {
        surface = surface,
        track = track,
        rects = rects,
        fx_count = fx_count,
        body_rect = body_rect,
        card_id = card_id,
        fx_area_bottom_y = fx_area_bottom_y,
        row_x = row_x,
        row_w = row_w,
    }
end

-- Compute insert position for a target hovered at (mx, my).
-- Returns (target_fi0, is_end_of_chain) where target is 0..fx_count.
-- Each row's hit zone extends into the gaps above/below to eliminate dead zones
-- between rows. Hovers outside the row-list (header, card body, below last row,
-- above first row beyond the half-gap) fall through to end-of-chain — matching
-- REAPER's default "append to chain" semantics and the script's rule: only
-- precise insert-points are explicit row gaps.
FxDropComputeTarget = function(target_entry, mx, my)
    local rects = target_entry.rects
    local fx_count = target_entry.fx_count
    if fx_count == 0 then return 0, true end
    local half_gap = S(UI.fx_gap) / 2
    for fi0 = 0, fx_count - 1 do
        local rc = rects[fi0]
        if rc then
            local zone_top
            if fi0 == 0 then
                zone_top = rc.cy - half_gap
            else
                local prev = rects[fi0 - 1]
                zone_top = prev and Round((prev.cy + prev.h + rc.cy) / 2) or rc.cy
            end
            local next_r = rects[fi0 + 1]
            local zone_bot
            if next_r then
                zone_bot = Round((rc.cy + rc.h + next_r.cy) / 2)
            else
                zone_bot = rc.cy + rc.h + half_gap
            end
            if my >= zone_top and my < zone_bot then
                local mid = rc.cy + rc.h / 2
                if my < mid then return fi0, false
                else return fi0 + 1, false end
            end
        end
    end
    return fx_count, true
end

-- Auto-scroll detection during drag. Called once per frame while drag active.
-- Reads mouse position, detects which scrollable child cursor is over,
-- accumulates wheel + edge-proximity delta into fx_drag_scroll_req.
-- child_id: "##content" or "##sends_content"
-- child_x, child_y, child_w, child_h: screen-space bounds of the scrollable child
FxDragAutoScrollCheck = function(child_id, child_x, child_y, child_w, child_h)
    if not fx_drag.active then return end
    local mx, my = r.ImGui_GetMousePos(ctx)
    if mx < child_x or mx > child_x + child_w then return end
    if my < child_y or my > child_y + child_h then return end
    local delta = 0
    -- Mouse wheel (ImGui returns lines; typical wheel notch = 1 line ≈ 30px)
    local wheel = r.ImGui_GetMouseWheel(ctx)
    if wheel ~= 0 then delta = delta - wheel * S(40) end
    -- Edge proximity: within S(40) of top/bottom, scroll proportionally
    local edge = S(40)
    if my < child_y + edge then
        local prox = 1 - (my - child_y) / edge
        delta = delta - prox * S(12)
    elseif my > child_y + child_h - edge then
        local prox = 1 - (child_y + child_h - my) / edge
        delta = delta + prox * S(12)
    end
    if delta ~= 0 then
        fx_drag_scroll_req[child_id] = (fx_drag_scroll_req[child_id] or 0) + delta
    end
end

-- Apply queued scroll delta to current BeginChild. Call right after BeginChild body start.
FxDragApplyScroll = function(child_id)
    local dy = fx_drag_scroll_req[child_id]
    if dy then
        r.ImGui_SetScrollY(ctx, r.ImGui_GetScrollY(ctx) + dy)
        fx_drag_scroll_req[child_id] = nil
    end
end

-- Resolve the current drag to a drop target (if any), draw visual overlays,
-- and handle release. Called once per frame near end of render.
--
-- v20.403 redesign:
--   • In-flight preview redesigned as a miniature FX row (bg/radius/padding
--     matching real rows) instead of a neutral tooltip. For single FX it shows
--     the FX name (blue text if instrument, matching how row would render).
--     For multi it shows "N plugins" in muted text.
--   • Move destinations use amber; copy destinations use the clipboard blue.
--   • Indicator line uses the operation color.
--   • Multi-source commit with index arithmetic for same-chain/cross-chain
--     and move/copy combinations. Sources are always 0-based ascending in
--     fx_drag.src_fis (populated by FxDragTryActivate from the selection).
FxDragResolveDrop = function()
    if not fx_drag.active or not fx_drag.src_fis then
        -- v20.408: no longer clears fx_drop_targets here. Registry lifecycle
        -- is owned by FxClipResolveHover (called immediately after us), which
        -- clears at its own end. This lets clipboard-mode consumers see the
        -- populated registry even when no drag is active.
        -- v20.412: also clear drag hover cache so cards don't think they're
        -- still drop targets when drag has ended.
        nav_fx_drag_last_hover_track = nil
        return
    end
    local mx, my = r.ImGui_GetMousePos(ctx)
    local src_track = fx_drag.src_track
    local src_fis = fx_drag.src_fis
    local n_src = #src_fis
    local src_fi0 = src_fis[1]  -- kept for name lookup + single-source noop

    -- Read live drag mode (op + automation) from modifier state
    local op, with_auto = FxDragReadMode()
    local is_move_flag = (op == "move")
    local op_col = (op == "copy") and (C.fx_drag_copy or C.fx_clip_carry or rgb(0x73A3F4))
                                   or (C.fx_drag_move or C.amber or rgb(0xD29922))

    -- Find which target the cursor is over (card body contains the mouse)
    local hit
    for _, t in ipairs(fx_drop_targets) do
        local b = t.body_rect
        if b and mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
            hit = t
            break
        end
    end

    -- Cache drag hover target for legacy readers.
    nav_fx_drag_last_hover_track = (hit and hit.track) or nil

    -- Locate source chain rect (for tooltip visibility gate)
    if not fx_drag.src_chain_rect then
        for _, t in ipairs(fx_drop_targets) do
            if t.track == src_track then
                fx_drag.src_chain_rect = {
                    x = t.body_rect.x, y = t.body_rect.y,
                    w = t.body_rect.w, h = t.body_rect.h
                }
                break
            end
        end
    end

    -- Update sticky tooltip visibility flag: true once cursor has ever left the source chain
    if not fx_drag.tooltip_shown and fx_drag.src_chain_rect then
        local sc = fx_drag.src_chain_rect
        local inside = (mx >= sc.x and mx <= sc.x + sc.w and my >= sc.y and my <= sc.y + sc.h)
        if not inside then fx_drag.tooltip_shown = true end
    end
    -- Multi-select: always show preview immediately (user can't "decide" individually)
    if n_src > 1 then fx_drag.tooltip_shown = true end

    local dl_fg = r.ImGui_GetForegroundDrawList(ctx)

    -- Floating in-flight preview — styled as an FX row clone.
    -- v20.404: rendered inside a BeginTooltip so it can extend past the
    -- script window's edge (ForegroundDrawList is clipped to the viewport,
    -- which cut the preview off when the cursor was near the script border).
    -- ImGui positions tooltips at cursor with on-screen keep-in-view heuristics.
    if fx_drag.tooltip_shown then
        local text_str
        local text_col
        if n_src > 1 then
            text_str = tostring(n_src) .. " plugins"
            text_col = C.text_dim or rgb(0xB4B2A9)
        else
            local fx_name = ""
            if src_track and r.ValidatePtr(src_track, "MediaTrack*") then
                local _, nm = r.TrackFX_GetFXName(src_track, src_fi0, "")
                if nm then
                    nm = nm:match(":%s*(.-)%s*%(") or nm:match(":%s*(.+)") or nm
                    fx_name = nm
                end
            end
            text_str = fx_name
            text_col = C.text or rgb(0xE6EDF3)
        end
        -- Automation-variant suffix only when user has modifier active.
        if op == "copy" and with_auto then
            text_str = text_str .. "  + auto"
        end

        local tw, th = r.ImGui_CalcTextSize(ctx, text_str)
        local pad_x, pad_y = S(9), S(5)
        local total_w = tw + pad_x * 2
        local total_h = th + pad_y * 2
        local row_bg = C.fx_row_bg or C.btn_bg or rgb(0x1E2228)
        local row_r = math.max(3, S(3))

        -- Transparent tooltip chrome — we draw the row-style card ourselves.
        -- v20.405: WindowPadding must be > 0 so the stroke's anti-aliasing
        -- pixels (extending ~0.5px beyond the nominal edge) don't get clipped
        -- by the tooltip's viewport clip rect. With padding=0, sides rendered
        -- faded/incomplete and rounded corners looked square. 2px of padding
        -- gives safe headroom without being visually detectable (tooltip bg
        -- is transparent so the pad area is invisible).
        local chrome_pad = math.max(2, S(2))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), 0x00000000)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), chrome_pad, chrome_pad)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
        if r.ImGui_BeginTooltip(ctx) then
            local dlt = r.ImGui_GetWindowDrawList(ctx)
            local tx, ty = r.ImGui_GetCursorScreenPos(ctx)
            r.ImGui_DrawList_AddRectFilled(dlt, tx, ty, tx + total_w, ty + total_h, row_bg, row_r)
            r.ImGui_DrawList_AddRect(dlt, tx, ty, tx + total_w, ty + total_h, op_col, row_r, 0, math.max(1, S(1)))
            r.ImGui_DrawList_AddText(dlt, tx + pad_x, ty + pad_y, text_col, text_str)
            r.ImGui_Dummy(ctx, total_w, total_h)  -- reserve space so tooltip auto-sizes correctly
            r.ImGui_EndTooltip(ctx)
        end
        r.ImGui_PopStyleVar(ctx, 2)
        r.ImGui_PopStyleColor(ctx, 1)
    end

    local committed = false
    if hit and r.ValidatePtr(hit.track, "MediaTrack*") then
        local target_fi0, is_end = FxDropComputeTarget(hit, mx, my)
        local same_chain = (hit.track == src_track)
        -- Noop detection: single-source move-in-same-chain where target is adjacent.
        -- Multi-source intentionally always commits (simpler; user can Ctrl+Z).
        local is_noop = (n_src == 1) and (op == "move") and same_chain
                        and (target_fi0 == src_fi0 or target_fi0 == src_fi0 + 1)

        -- Draw insert indicator (skip when noop for visual de-emphasis)
        local line_y
        local rc_ref
        local half_gap = S(UI.fx_gap) / 2
        if hit.fx_count == 0 then
            local anchor = hit.fx_area_bottom_y or (hit.body_rect.y + S(UI.card_pad_top or 8))
            line_y = anchor - half_gap
        elseif is_end then
            rc_ref = hit.rects[hit.fx_count - 1]
            if rc_ref then line_y = rc_ref.cy + rc_ref.h + half_gap end
        else
            if target_fi0 == 0 then
                rc_ref = hit.rects[0]
                if rc_ref then line_y = rc_ref.cy - half_gap end
            else
                rc_ref = hit.rects[target_fi0 - 1]
                local nxt = hit.rects[target_fi0]
                if rc_ref and nxt then
                    line_y = Round((rc_ref.cy + rc_ref.h + nxt.cy) / 2)
                elseif rc_ref then
                    line_y = rc_ref.cy + rc_ref.h + half_gap
                end
            end
        end
        if line_y and not is_noop then
            local line_inset = S(4)
            local x1, x2
            if rc_ref then
                x1 = rc_ref.cx + line_inset
                x2 = rc_ref.cx + rc_ref.w - line_inset
            elseif hit.row_x and hit.row_w then
                x1 = hit.row_x + line_inset
                x2 = hit.row_x + hit.row_w - line_inset
            else
                x1 = hit.body_rect.x + line_inset
                x2 = hit.body_rect.x + hit.body_rect.w - line_inset
            end
            local line_thick = math.max(2, S(2))
            local line_r = math.floor(line_thick / 2)
            r.ImGui_DrawList_AddRectFilled(dl_fg, x1, line_y - line_r, x2, line_y + line_r, op_col, line_r)
        end

        -- Drop on release
        if r.ImGui_IsMouseReleased(ctx, 0) then
            if not fx_drag.cancelled and not is_noop
               and src_track and r.ValidatePtr(src_track, "MediaTrack*") then
                local src_name = FxDragTrackLabel(src_track)
                local dst_name = FxDragTrackLabel(hit.track)
                local auto_tag = (op == "copy" and not with_auto) and " (no auto)" or ""
                local count_tag = (n_src > 1) and (" " .. n_src) or ""
                -- Label construction: singular for n=1 preserves existing labels
                local label
                if same_chain then
                    if op == "move" then
                        label = "Reflex: Reorder" .. count_tag .. " FX" .. auto_tag
                    else
                        label = "Reflex: Duplicate" .. count_tag .. " FX" .. auto_tag
                    end
                else
                    local verb = (op == "move") and "Move" or "Copy"
                    label = "Reflex: " .. verb .. count_tag .. " FX from " .. src_name .. " to " .. dst_name .. auto_tag
                end

                r.Undo_BeginBlock()

                if n_src == 1 then
                    -- Single-source: unchanged from v20.402 commit path
                    local dst_fi0 = target_fi0
                    if op == "move" and same_chain and src_fi0 < dst_fi0 then
                        dst_fi0 = dst_fi0 - 1
                    end
                    r.TrackFX_CopyToTrack(src_track, src_fi0, hit.track, dst_fi0, is_move_flag)
                    if not with_auto then
                        FxStripAutomation(hit.track, dst_fi0)
                    end
                else
                    -- Multi-source commit. Four cases via same_chain × op cross.
                    if same_chain and op == "move" then
                        -- Split sources by position relative to target. Below processed
                        -- descending (target decrements); above processed ascending with
                        -- target reset to original (below moves don't shift above positions).
                        local below, above = {}, {}
                        for _, s in ipairs(src_fis) do
                            if s < target_fi0 then below[#below+1] = s
                            elseif s > target_fi0 then above[#above+1] = s
                            end
                            -- s == target_fi0 is a noop contribution; skip it
                        end
                        local t = target_fi0
                        for i = #below, 1, -1 do
                            local s = below[i]
                            local adj = t - 1  -- src < t always here
                            r.TrackFX_CopyToTrack(src_track, s, src_track, adj, true)
                            if not with_auto then FxStripAutomation(src_track, adj) end
                            t = t - 1
                        end
                        t = target_fi0  -- reset for above; above positions unaffected by below moves
                        for _, s in ipairs(above) do
                            r.TrackFX_CopyToTrack(src_track, s, src_track, t, true)
                            if not with_auto then FxStripAutomation(src_track, t) end
                            t = t + 1
                        end
                    elseif same_chain and op == "copy" then
                        -- Ascending order, target advances. Source positions shift for
                        -- sources >= target_fi0 by (i-1) prior insertions.
                        local t = target_fi0
                        for i, s in ipairs(src_fis) do
                            local cur_src = (s < target_fi0) and s or (s + (i - 1))
                            r.TrackFX_CopyToTrack(src_track, cur_src, src_track, t, false)
                            if not with_auto then FxStripAutomation(src_track, t) end
                            t = t + 1
                        end
                    else
                        -- Cross-chain (move or copy). Process sources descending so each
                        -- insert lands at target_fi0, pushing prior inserts down by 1.
                        -- For move: removing higher src first doesn't affect lower src.
                        -- For copy: src stays intact regardless.
                        for i = n_src, 1, -1 do
                            local s = src_fis[i]
                            r.TrackFX_CopyToTrack(src_track, s, hit.track, target_fi0, is_move_flag)
                            if not with_auto then FxStripAutomation(hit.track, target_fi0) end
                        end
                    end
                end

                r.Undo_EndBlock(label, -1)

                -- Selection consumed by the drag: clear after commit (GUIDs may
                -- no longer reference the same FX after move/copy anyway).
                InspFxSelClear()

                -- Invalidate affected caches
                InspMarkTrackFxDirty(src_track)
                InspMarkTrackFxDirty(hit.track)
                if sends_fx_cache then
                    sends_fx_cache[src_track] = nil
                    sends_fx_cache[hit.track] = nil
                end
                committed = true
            end
            -- v20.431: drop committed onto an auto-expanded card → promote
            -- to permanent expansion (survives FxDragClear). Cards still in
            -- flow_auto_expanded after this point get reverted in FxDragClear.
            if committed and fx_drag.flow_auto_expanded and hit and hit.track then
                fx_drag.flow_auto_expanded[hit.track] = nil
            end
            FxDragClear()
        end
    elseif r.ImGui_IsMouseReleased(ctx, 0) then
        -- Released outside any target
        FxDragClear()
    end

    -- v20.408: no longer clears fx_drop_targets here. See top of function.
end

end

return ReflexInstallFXDragCore
