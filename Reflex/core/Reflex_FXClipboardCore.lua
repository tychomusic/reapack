-- @noindex
-- Reflex FX clipboard core module.
-- Installs FX copy/cut/paste state, paste-target hover resolution,
-- carry visuals, and paste landing confirmation helpers.

ReflexInstallFXClipboardCore = function(deps)
    local r = deps.r
    local ctx = deps.ctx
    local C = deps.colors

-- =========================================================================
-- FX CLIPBOARD (v20.407)
-- =========================================================================
-- Session-forever clipboard for FX copy/cut/paste. Captures FX chunks at
-- copy/cut time so they survive source-track edits and cut deletion.
-- User model: "carrying state" — entering it is explicit (Cmd+C/X), exiting
-- is explicit (paste, click × on chip, Cmd+C with empty src, or menu clear).
-- Track navigation does NOT clear clipboard (separate lifecycle from multi-
-- select, which clears on every track switch).
--
-- Shape:
--   op = "copy" | "cut"              -- recorded; may drive future auto-variants
--   count = N                        -- #items (cached for fast predicate)
--   source_track_name = "KICK"       -- for chip label / undo fallback
--   items = {
--     { chunk = "BYPASS ...\n<VST ...\n  ...\n>\nFLOATPOS...\nFXID...\nWAK...",
--       wet = 1.0,
--       fx_name = "Pro-Q 3",
--       is_instr = false },
--     ...
--   }
-- nil when clipboard is empty.
nav_fx_clipboard = nil

-- Deferred paste request. Cmd+V keyboard dispatch runs near top of Loop,
-- before render registers drop targets. We set this flag there, then consume
-- it at end of render (after FxDropTargetRegister has run for this frame)
-- via FxClipResolveHover -> FxClipExecutePendingPaste.
nav_fx_clip_pending_paste = nil  -- nil | { where = "above"|"below"|"auto" }

-- Last-frame clipboard hover target (v20.411). Stroke decisions (pin amber
-- source_stroke, flow-selected send_stroke) happen during render BEFORE
-- FxClipResolveHover runs at end-of-frame — so we can't consult the live
-- hover state from the decision point. Instead, cache last frame's hover
-- track here and read it this frame. 1-frame lag is imperceptible.
-- Used to suppress card strokes so the dashed green paste target outline
-- becomes the exclusive outline on the hovered card.
nav_fx_clip_last_hover_track = nil

FxClipClear = function()
    nav_fx_clipboard = nil
end

FxClipHasContent = function()
    return nav_fx_clipboard ~= nil and nav_fx_clipboard.count and nav_fx_clipboard.count > 0
end

FxClipCount = function()
    if not nav_fx_clipboard then return 0 end
    return nav_fx_clipboard.count or 0
end

FxClipCapture = function(track, fis, op, include_automation)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    if not fis or #fis == 0 then return false end
    -- Sort ascending for extraction, descending for cut-delete
    local sorted = {}
    for _, fi in ipairs(fis) do sorted[#sorted + 1] = fi end
    table.sort(sorted)

    -- Fetch track chunk once, extract all FX blocks from it
    local rv, chunk = r.GetTrackStateChunk(track, "", false)
    if not rv then return false end

    local items = {}
    for _, fi in ipairs(sorted) do
        local block = FxChunkExtractFxBlock(chunk, fi)
        if block and block ~= "" then
            -- Capture wet value (redundant with chunk in practice, but defensive)
            local wet = 1.0
            if r.TrackFX_GetParamFromIdent then
                local wp = r.TrackFX_GetParamFromIdent(track, fi, ":wet")
                if wp and wp >= 0 then
                    wet = r.TrackFX_GetParam(track, fi, wp) or 1.0
                end
            end
            -- FX display name (for chip / single-item preview)
            local _, fx_name = r.TrackFX_GetFXName(track, fi, "")
            if fx_name then
                fx_name = fx_name:match(":%s*(.-)%s*%(") or fx_name:match(":%s*(.+)") or fx_name
            else
                fx_name = "FX"
            end
            -- Instrument flag (for blue text on single-item chip/preview)
            local is_instr = false
            if r.TrackFX_GetNamedConfigParm then
                local rv_ft, ft_str = r.TrackFX_GetNamedConfigParm(track, fi, "fx_type")
                if rv_ft and ft_str and ft_str:match("i$") then is_instr = true end
            end
            items[#items + 1] = { chunk = block, wet = wet, fx_name = fx_name, is_instr = is_instr }
        end
    end

    if #items == 0 then return false end

    local _, tname = r.GetTrackName(track)
    if not tname or tname == "" then
        tname = "Track " .. math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
    end

    nav_fx_clipboard = {
        op = op,
        count = #items,
        source_track = track,   -- MediaTrack*; used to suppress dashed outline on source card (v20.410)
        source_track_name = tname,
        include_automation = include_automation and true or false,  -- v20.411
        paste_count = 0,        -- v20.415: track # pastes for auto-dismiss-pill behavior
        items = items,
    }

    -- For cut: delete originals (descending order to preserve indices)
    if op == "cut" then
        r.Undo_BeginBlock()
        for i = #sorted, 1, -1 do
            local fi = sorted[i]
            if fi >= 0 and fi < r.TrackFX_GetCount(track) then
                r.TrackFX_Delete(track, fi)
            end
        end
        local label
        if #items == 1 then label = "Reflex: Cut FX"
        else label = "Reflex: Cut " .. #items .. " FX" end
        r.Undo_EndBlock(label, -1)
        -- Invalidate caches for this track
        InspMarkTrackFxDirty(track)
        if sends_fx_cache then sends_fx_cache[track] = nil end
    end

    -- Consume multi-selection on the source track for CUT only (v20.416).
    -- For cut, source FX are deleted, so selection refs would become stale —
    -- clear to keep state clean. For copy, retain selection: the green
    -- carry outline replaces the white selection visually during loud mode
    -- (paste_count==0). After first paste, green extinguishes and white
    -- naturally re-emerges because selection data was preserved.
    -- Earlier (v20.409) cleared on both ops to make white→green transition
    -- visible. Now achieved via outline-cascade priority swap instead.
    if op == "cut" and insp_fx_sel_track == track then InspFxSelClear() end
    return true
end

-- Paste the clipboard's FX blocks into target track at 0-based insert_at_fi.
-- Splices chunks directly, then SetTrackStateChunk. Post-paste, restores wet
-- values on each newly-inserted FX. Single Undo entry.
FxClipPaste = function(track, insert_at_fi)
    if not FxClipHasContent() then return false end
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end

    local existing_count = r.TrackFX_GetCount(track)
    if insert_at_fi < 0 then insert_at_fi = 0 end
    if insert_at_fi > existing_count then insert_at_fi = existing_count end

    local rv, chunk = r.GetTrackStateChunk(track, "", false)
    if not rv then return false end

    local blocks = {}
    for _, item in ipairs(nav_fx_clipboard.items) do
        -- v20.408: regen FXIDs so pasted FX don't share GUIDs with source
        -- (or with prior pastes of the same clipboard content). See
        -- FxChunkRegenFxids comment for rationale.
        blocks[#blocks + 1] = FxChunkRegenFxids(item.chunk)
    end
    local new_chunk = FxChunkSpliceFxBlocks(chunk, insert_at_fi, blocks)
    if new_chunk == chunk then return false end

    r.PreventUIRefresh(1)
    r.Undo_BeginBlock()
    r.SetTrackStateChunk(track, new_chunk, false)

    -- Restore wet values on newly-inserted FX (defensive; chunk should
    -- already preserve, but user-facing wet drift is painful to debug)
    if r.TrackFX_GetParamFromIdent and r.TrackFX_SetParam then
        for i, item in ipairs(nav_fx_clipboard.items) do
            local new_fi = insert_at_fi + (i - 1)
            if new_fi < r.TrackFX_GetCount(track) then
                local wp = r.TrackFX_GetParamFromIdent(track, new_fi, ":wet")
                if wp and wp >= 0 and item.wet then
                    r.TrackFX_SetParam(track, new_fi, wp, item.wet)
                end
            end
        end
    end

    -- Strip automation if clipboard was captured without include_automation
    -- (v20.411). REAPER's ⌘C default excludes envelopes; our chunk-based
    -- approach captures them regardless, so strip at paste time instead.
    -- Uses the same FxStripAutomation helper the drag pipeline uses for
    -- Cmd+drag (⌘+drag = copy w/o auto; drag = move w/ auto).
    if not nav_fx_clipboard.include_automation then
        local n_items = #nav_fx_clipboard.items
        for i = 1, n_items do
            local new_fi = insert_at_fi + (i - 1)
            if new_fi < r.TrackFX_GetCount(track) then
                FxStripAutomation(track, new_fi)
            end
        end
    end

    local n = #nav_fx_clipboard.items
    local label
    if n == 1 then label = "Reflex: Paste FX"
    else label = "Reflex: Paste " .. n .. " FX" end
    r.Undo_EndBlock(label, -1)
    r.PreventUIRefresh(-1)

    -- Invalidate caches for destination
    InspMarkTrackFxDirty(track)
    if sends_fx_cache then sends_fx_cache[track] = nil end

    -- v20.417: capture GUIDs of just-inserted FX for the pulse-then-fade
    -- landing animation. Must run after InspScanTrack so any caches are
    -- fresh; FX GUIDs from TrackFX_GetFXGUID are stable post-SetTrackStateChunk
    -- because RegenFxids assigned new ones during splice.
    do
        local landed = {}
        for i = 1, #nav_fx_clipboard.items do
            local new_fi = insert_at_fi + (i - 1)
            if new_fi < r.TrackFX_GetCount(track) then
                local g = r.TrackFX_GetFXGUID(track, new_fi)
                if g and g ~= "" then landed[g] = true end
            end
        end
        nav_fx_paste_landed = {
            track = track,
            guids = landed,
            started_at = r.time_precise(),
        }
    end

    -- v20.415: bump paste counter so the carry pill auto-dismisses after the
    -- first paste. Clipboard remains alive for additional pastes (silent,
    -- matching REAPER's clipboard model) but the cursor-following pill stops
    -- demanding attention. Subsequent Cmd+V pastes silently. Esc / chip × /
    -- new copy still fully clear the clipboard.
    local was_first_paste = (nav_fx_clipboard.paste_count or 0) == 0
    nav_fx_clipboard.paste_count = (nav_fx_clipboard.paste_count or 0) + 1
    -- v20.424: clear selection on first paste. Cut already implicitly clears
    -- (sources are gone); this makes copy match. Rule: paste ends the
    -- operation, full stop. The white selection outline persisting through
    -- the carry-mode visual reset (pill, source-strokes, chip all gone) was
    -- the odd signal out — looked like residue from a finished action.
    -- Subsequent silent pastes have no selection left to clear, so no special
    -- case needed.
    if was_first_paste then InspFxSelClear() end
    return true
end

-- Find FX row under the mouse (across all registered drop targets).
-- Returns { track, fi, surface } or nil. Uses previous frame's registry
-- when called at top of Loop (pre-render); current frame's when called
-- during render/end-of-frame. Both are fine for hover resolution — one
-- frame of lag on a moving mouse is imperceptible at 30fps.
FxClipFindHoveredRow = function()
    if not fx_drop_targets or #fx_drop_targets == 0 then return nil end
    local mx, my = r.ImGui_GetMousePos(ctx)
    for _, t in ipairs(fx_drop_targets) do
        if t.rects then
            for fi0, rc in pairs(t.rects) do
                if rc and mx >= rc.cx and mx <= rc.cx + rc.w
                   and my >= rc.cy and my <= rc.cy + rc.h then
                    return { track = t.track, fi = fi0, surface = t.surface }
                end
            end
        end
    end
    return nil
end

-- Find card under mouse (any FX chain surface). Returns { track, surface } or nil.
FxClipFindHoveredCard = function()
    if not fx_drop_targets or #fx_drop_targets == 0 then return nil end
    local mx, my = r.ImGui_GetMousePos(ctx)
    for _, t in ipairs(fx_drop_targets) do
        local b = t.body_rect
        if b and mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
            return { track = t.track, surface = t.surface, entry = t }
        end
    end
    return nil
end

-- Resolve paste target. where: "above" | "below" | "auto" (default below for Cmd+V).
-- Priority: hovered row → hovered card (append) → inspected track (append) → nil.
-- Returns (track, insert_at_fi_0_based) or nil.
FxClipResolvePasteTarget = function(where)
    where = where or "below"
    local row = FxClipFindHoveredRow()
    if row and r.ValidatePtr(row.track, "MediaTrack*") then
        local at
        if where == "above" then at = row.fi
        else at = row.fi + 1 end
        return row.track, at
    end
    local card = FxClipFindHoveredCard()
    if card and r.ValidatePtr(card.track, "MediaTrack*") then
        return card.track, r.TrackFX_GetCount(card.track)
    end
    if insp_track and r.ValidatePtr(insp_track, "MediaTrack*") then
        return insp_track, r.TrackFX_GetCount(insp_track)
    end
    return nil
end

-- True if a given FX (track, guid) is currently in the clipboard.
-- Used by source-row outline renderers. Matches by source_track_name +
-- clipboard chunk text containing the FXID. The cheapest reliable match
-- is GUID scanning the stored chunk: FX chunks contain `FXID {guid}`.
-- We memoize the set of GUIDs on the clipboard for per-frame lookup.
FxClipRebuildGuidSet = function()
    if not nav_fx_clipboard then
        nav_fx_clipboard_guid_set = nil
        return
    end
    local set = {}
    for _, item in ipairs(nav_fx_clipboard.items) do
        -- FXID line format: "FXID {ABCDEF12-...}"
        for guid in item.chunk:gmatch("FXID%s+(%b{})") do
            set[guid] = true
        end
    end
    nav_fx_clipboard_guid_set = set
end

-- v20.417: Paste-landing visual confirmation. After a successful paste, the
-- destination FX get a brief animated green outline that pulses then fades
-- — a "where did they land?" confirmation. Implemented as global state
-- captured at paste time and consumed in the outline cascade.
--
-- Lifecycle: FxClipPaste captures GUIDs of newly-inserted FX after the
-- SetTrackStateChunk, sets started_at = time_precise(), and the cascade
-- branch consults NavPasteLandedAlpha() each frame. Auto-clears when alpha
-- hits 0 (handled inside NavPasteLandedAlpha to avoid leaking state if no
-- one renders).
--
-- Animation curve (1.1s total):
--   0–100ms:    ramp up 0→1 (initial flash)
--   100–500ms:  2 sin pulses between 0.8 and 1.0
--   500–1100ms: linear fade 1.0→0 (settle)
nav_fx_paste_landed = nil  -- {track, guids = {[guid]=true}, started_at}

NavPasteLandedAlpha = function()
    if not nav_fx_paste_landed then return 0 end
    local now = r.time_precise()
    local t_ms = (now - nav_fx_paste_landed.started_at) * 1000
    if t_ms >= 1100 or t_ms < 0 then
        nav_fx_paste_landed = nil
        return 0
    end
    if t_ms < 100 then
        return t_ms / 100
    elseif t_ms < 500 then
        local phase = (t_ms - 100) / 400
        return 0.8 + 0.2 * math.sin(phase * 4 * math.pi)
    else
        local phase = (t_ms - 500) / 600
        return 1.0 - phase
    end
end

NavPasteLandedHas = function(track, guid)
    if not nav_fx_paste_landed then return false end
    if not guid or guid == "" then return false end
    if track ~= nav_fx_paste_landed.track then return false end
    return nav_fx_paste_landed.guids and nav_fx_paste_landed.guids[guid] == true
end

-- Outline-eligible predicate: is this FX GUID on the clipboard AND on its
-- source track? Cut operations delete the source, so after a cut the GUID
-- still "matches" in the set but there's no live FX to outline (which is
-- fine — the matching loop won't find it). For copy, source is live, so
-- outlines appear on source track rows.
-- v20.416: also gated on paste_count == 0 (green source-row outlines auto-
-- extinguish after first paste, mirroring the carry-pill auto-dismiss).
-- Loud carry visuals exit on action; clipboard data remains alive silently
-- for additional pastes via Cmd+V or right-click menu.
FxClipHasGuid = function(guid)
    if not guid or guid == "" then return false end
    if not nav_fx_clipboard then return false end
    if (nav_fx_clipboard.paste_count or 0) > 0 then return false end
    if not nav_fx_clipboard_guid_set then FxClipRebuildGuidSet() end
    return nav_fx_clipboard_guid_set and nav_fx_clipboard_guid_set[guid] == true
end

-- Is this track the one currently hovered as a paste / drag target?
-- (v20.411 / v20.412) Read from cached last-frame hover state. Used by
-- card-stroke render sites to suppress pin/selected strokes so the
-- dashed paste/drop target outline is the exclusive outline.
-- Also checks the card is not the source card — source cards don't get
-- the dashed outline, so their strokes should render normally.
NavCardIsDropTarget = function(track)
    if not track then return false end
    -- Drag-active hover (v20.412)
    if fx_drag.active then
        if track ~= nav_fx_drag_last_hover_track then return false end
        -- Don't suppress on source card during drag (drag pipeline doesn't
        -- draw a dashed outline on its own source card either).
        if fx_drag.src_track == track then return false end
        return true
    end
    -- Clipboard-active hover (v20.411)
    if FxClipHasContent() then
        if track ~= nav_fx_clip_last_hover_track then return false end
        if nav_fx_clipboard and nav_fx_clipboard.source_track == track then return false end
        return true
    end
    return false
end

-- Backward-compat alias kept for code paths that already use it; same logic.
FxClipIsHoveredTrack = NavCardIsDropTarget

-- Execute the pending paste, if any. Called near end-of-frame render so that
-- fx_drop_targets is fully populated by this frame's chains.
FxClipExecutePendingPaste = function()
    if not nav_fx_clip_pending_paste then return end
    local req = nav_fx_clip_pending_paste
    nav_fx_clip_pending_paste = nil
    if not FxClipHasContent() then return end
    local track, at = FxClipResolvePasteTarget(req.where)
    if track then FxClipPaste(track, at) end
end

-- Render clipboard-mode hover visuals at end of frame: dashed destination
-- outline on whichever card the cursor is over, and insert indicator line
-- inside that card at the computed paste position. Suppressed while a drag
-- is active (drag visuals take precedence).
--
-- v20.408: also owns the single fx_drop_targets clear per frame (previously
-- done inside FxDragResolveDrop, which ran first and wiped the registry
-- before this function could use it). Order at call site is:
--   1. FxDragResolveDrop  — reads fx_drop_targets, does NOT clear
--   2. FxClipResolveHover — reads fx_drop_targets, clears at end
-- Guarantees both consumers see the populated registry regardless of which
-- state (drag active / clipboard carrying) is live.
FxClipResolveHover = function()
    -- Execute any pending paste first, so rects from THIS frame are current.
    -- FxClipExecutePendingPaste uses fx_drop_targets to resolve paste target;
    -- must run before the clear at end.
    FxClipExecutePendingPaste()

    -- v20.414: Drop-target indicators (dashed outline + insert line) require
    -- Reflex focused, so users get consistent feedback that maps to whether
    -- Cmd+V will actually be received by Reflex vs REAPER. Carry pill,
    -- chip, and source-row outlines remain on regardless of focus — they're
    -- pure state indicators.
    local nav_focused = r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows())

    -- Reset hover-track cache at top of frame; it's repopulated below when
    -- clip is active, focused, and a card is hovered. Without this, a cached
    -- track from a previous carry/focus session would persist across Esc/clear
    -- or focus loss, causing stale stroke suppression.
    if not FxClipHasContent() or fx_drag.active or not nav_focused then
        nav_fx_clip_last_hover_track = nil
    end

    -- Guarded inner block so we can fall through to the registry clear even
    -- when the hover render is skipped.
    if FxClipHasContent() and not fx_drag.active and nav_focused then
        local hit = FxClipFindHoveredCard()
        -- Cache last-frame hover target for next frame's stroke-suppression
        -- decisions (stroke rendering happens during render, before this
        -- function runs at end-of-frame). v20.411.
        nav_fx_clip_last_hover_track = (hit and hit.track) or nil
        -- v20.423: split the source-card gate. Source card skips the dashed
        -- outline (visually noisy/redundant — green source-row strokes already
        -- mark the card; mirrors drag pipeline) but still gets the insert
        -- indicator so users can paste back into the source chain at a
        -- specific row position.
        local is_source = (hit and nav_fx_clipboard and nav_fx_clipboard.source_track
                          and hit.track == nav_fx_clipboard.source_track
                          and r.ValidatePtr(nav_fx_clipboard.source_track, "MediaTrack*"))
        if hit and hit.entry and hit.entry.body_rect then
            local entry = hit.entry
            local mx, my = r.ImGui_GetMousePos(ctx)
            -- v20.421: suppress foreground decorations while any popup is open
            -- (FX-row context menu, browser-action menu, etc.). dl_fg renders
            -- above ImGui's popup layer, which would otherwise draw the dashed
            -- outline + insert line on top of the menu. Hover-track caching
            -- above stays active so source-stroke suppression doesn't flicker
            -- when the menu closes.
            local any_popup_open = r.ImGui_IsPopupOpen(ctx, "",
                r.ImGui_PopupFlags_AnyPopupId() | r.ImGui_PopupFlags_AnyPopupLevel())
            if not any_popup_open then
            local dl_fg = r.ImGui_GetForegroundDrawList(ctx)
            local col = C.fx_clip_carry or rgb(0x3FB950)

            -- Dashed outline around the target card (skipped on source — v20.423)
            local b = entry.body_rect
            if not is_source then
                DrawDashedRoundedRect(dl_fg,
                    b.x, b.y, b.x + b.w, b.y + b.h,
                    col, S(UI.card_r), math.max(1, S(1.5)),
                    math.max(4, S(5)), math.max(2, S(3)))
            end

            -- Insert indicator line at the computed paste row position
            local target_fi0, is_end = FxDropComputeTarget(entry, mx, my)
            local half_gap = S(UI.fx_gap) / 2
            local line_y, rc_ref
            if entry.fx_count == 0 then
                local anchor = entry.fx_area_bottom_y or (b.y + S(UI.card_pad_top or 8))
                line_y = anchor - half_gap
            elseif is_end then
                rc_ref = entry.rects[entry.fx_count - 1]
                if rc_ref then line_y = rc_ref.cy + rc_ref.h + half_gap end
            else
                if target_fi0 == 0 then
                    rc_ref = entry.rects[0]
                    if rc_ref then line_y = rc_ref.cy - half_gap end
                else
                    rc_ref = entry.rects[target_fi0 - 1]
                    local nxt = entry.rects[target_fi0]
                    if rc_ref and nxt then
                        line_y = Round((rc_ref.cy + rc_ref.h + nxt.cy) / 2)
                    elseif rc_ref then
                        line_y = rc_ref.cy + rc_ref.h + half_gap
                    end
                end
            end
            if line_y then
                local line_inset = S(4)
                local x1, x2
                if rc_ref then
                    x1 = rc_ref.cx + line_inset
                    x2 = rc_ref.cx + rc_ref.w - line_inset
                elseif entry.row_x and entry.row_w then
                    x1 = entry.row_x + line_inset
                    x2 = entry.row_x + entry.row_w - line_inset
                else
                    x1 = b.x + line_inset
                    x2 = b.x + b.w - line_inset
                end
                local line_thick = math.max(2, S(2))
                local line_r = math.floor(line_thick / 2)
                r.ImGui_DrawList_AddRectFilled(dl_fg, x1, line_y - line_r, x2, line_y + line_r, col, line_r)
            end
            end -- v20.421: close popup-open guard
        end
    end

    -- Reset registry for next frame. Unconditional — both consumers have
    -- used it by now, and leaving entries across frames would cause stale
    -- hits from previously-rendered surfaces.
    fx_drop_targets = {}

    -- v20.410: Cursor-following carry pill. Floats near cursor showing
    -- "you are carrying N FX" while clipboard is active. Complements the
    -- fixed chip (exit path) and card-level hover indicators (where-to-drop).
    -- Gated on: clipboard non-empty, no drag active (drag preview wins),
    -- cursor over Reflex (don't leak onto desktop — this is a mode
    -- indicator, not a permanent on-top overlay).
    -- v20.415: also gated on paste_count == 0 (auto-dismiss after first paste).
    -- Rationale: REAPER's clipboard is silent infrastructure. Our cursor-
    -- following pill is the loudest carry-mode visual; making it auto-dismiss
    -- after first paste lets single-paste workflows (the 99% case) feel
    -- transparent like REAPER while still surfacing the carry state for the
    -- initial action moment. Multi-paste users can keep pasting silently;
    -- clipboard remains alive until Esc / chip click / new copy.
    if FxClipHasContent() and not fx_drag.active
       and (nav_fx_clipboard.paste_count or 0) == 0
       and r.ImGui_IsWindowHovered(ctx, r.ImGui_HoveredFlags_AnyWindow()) then
        FxClipRenderCarryPill()
    end
end

-- Floating "you are carrying N FX" pill rendered at cursor via BeginTooltip.
-- Green stroke matches carry color. Shows FX name for single-item clipboard
-- (blue text if instrument, matching drag-preview convention); "N plugins"
-- in muted text for multi.
FxClipRenderCarryPill = function()
    if not nav_fx_clipboard or not nav_fx_clipboard.items then return end
    local n = nav_fx_clipboard.count or #nav_fx_clipboard.items
    if n <= 0 then return end

    local text_str, text_col
    if n > 1 then
        text_str = tostring(n) .. " plugins"
        text_col = C.text_dim or rgb(0xB4B2A9)
    else
        local it = nav_fx_clipboard.items[1]
        text_str = it and it.fx_name or "FX"
        text_col = (it and it.is_instr) and (C.fx_instr_txt or rgb(0x1643D6))
                                        or (C.text or rgb(0xE6EDF3))
    end

    local op_tag = (nav_fx_clipboard.op == "cut") and "cut" or "copy"
    text_str = text_str .. "  " .. op_tag

    -- v20.415: when Reflex isn't focused, append a focus hint. Without
    -- this, users see the pill (since it follows cursor in any hovered state)
    -- and may try Cmd+V — which REAPER consumes when REAPER has focus.
    -- Showing the hint makes the focus rule discoverable in the moment that
    -- matters. Hint is dim text, slightly muted styling.
    local hint_str = nil
    if not r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows()) then
        hint_str = "click to focus"
    end

    local tw, th = r.ImGui_CalcTextSize(ctx, text_str)
    local hint_tw, hint_th = 0, 0
    local hint_sep = S(8)  -- separator gap between main text and hint
    if hint_str then
        hint_tw, hint_th = r.ImGui_CalcTextSize(ctx, hint_str)
    end
    local pad_x, pad_y = S(9), S(5)
    local total_w = tw + (hint_str and (hint_sep + hint_tw) or 0) + pad_x * 2
    local total_h = th + pad_y * 2
    local row_bg = C.fx_row_bg or C.btn_bg or rgb(0x1E2228)
    local row_r = math.max(3, S(3))
    local stroke_col = C.fx_clip_carry or rgb(0x3FB950)
    local hint_col = C.text_dim or rgb(0xB4B2A9)

    -- Same chrome/padding trick as drag preview: transparent popup bg + 2px
    -- WindowPadding so stroke AA doesn't get clipped by the tooltip viewport.
    local chrome_pad = math.max(2, S(2))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), 0x00000000)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), chrome_pad, chrome_pad)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
    if r.ImGui_BeginTooltip(ctx) then
        local dlt = r.ImGui_GetWindowDrawList(ctx)
        local tx, ty = r.ImGui_GetCursorScreenPos(ctx)
        r.ImGui_DrawList_AddRectFilled(dlt, tx, ty, tx + total_w, ty + total_h, row_bg, row_r)
        r.ImGui_DrawList_AddRect(dlt, tx, ty, tx + total_w, ty + total_h, stroke_col, row_r, 0, math.max(1, S(1)))
        r.ImGui_DrawList_AddText(dlt, tx + pad_x, ty + pad_y, text_col, text_str)
        if hint_str then
            r.ImGui_DrawList_AddText(dlt, tx + pad_x + tw + hint_sep, ty + pad_y, hint_col, hint_str)
        end
        r.ImGui_Dummy(ctx, total_w, total_h)
        r.ImGui_EndTooltip(ctx)
    end
    r.ImGui_PopStyleVar(ctx, 2)
    r.ImGui_PopStyleColor(ctx, 1)
end

-- Delete currently-selected FX (multi-select). Single undo entry, pluralized label.
-- No-op if no selection bound or selection is empty. Track validation required.
FxClipDeleteSelection = function()
    if InspFxSelCount() == 0 then return false end
    local track = insp_fx_sel_track
    if not track or not r.ValidatePtr(track, "MediaTrack*") then
        InspFxSelClear()
        return false
    end
    local fis = InspFxSelGetFis(track)
    if #fis == 0 then InspFxSelClear(); return false end
    table.sort(fis)  -- ascending; we'll delete descending below
    r.Undo_BeginBlock()
    for i = #fis, 1, -1 do
        local fi = fis[i]
        if fi >= 0 and fi < r.TrackFX_GetCount(track) then
            r.TrackFX_Delete(track, fi)
        end
    end
    local label
    if #fis == 1 then label = "Reflex: Delete FX"
    else label = "Reflex: Delete " .. #fis .. " FX" end
    r.Undo_EndBlock(label, -1)
    InspFxSelClear()
    InspMarkTrackFxDirty(track)
    if sends_fx_cache then sends_fx_cache[track] = nil end
    return true
end

-- Convert a "copy" clipboard to "cut": find the source-track FX whose GUIDs
-- match the clipboard's stored chunks, delete them, flip op to "cut".
-- Use case (v20.413): user hits Cmd+C, then immediately Cmd+X. Without this
-- conversion, the second Cmd+X would be a silent no-op because the multi-
-- selection got consumed into the carry state on Cmd+C — so no selection
-- exists for Cmd+X to operate on. REAPER's native menu does this automatically.
-- Returns true if anything was deleted, false otherwise (e.g. source track
-- gone, FX already moved by another operation).
FxClipConvertCopyToCut = function()
    if not nav_fx_clipboard then return false end
    if nav_fx_clipboard.op == "cut" then return false end  -- already cut
    local track = nav_fx_clipboard.source_track
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end

    -- Walk source track FX; match GUIDs against clipboard set
    if not nav_fx_clipboard_guid_set then FxClipRebuildGuidSet() end
    local set = nav_fx_clipboard_guid_set
    if not set then return false end

    local fis_to_delete = {}
    for fi = 0, r.TrackFX_GetCount(track) - 1 do
        local guid = r.TrackFX_GetFXGUID(track, fi)
        if guid and set[guid] then
            fis_to_delete[#fis_to_delete + 1] = fi
        end
    end
    if #fis_to_delete == 0 then return false end

    table.sort(fis_to_delete)
    r.Undo_BeginBlock()
    for i = #fis_to_delete, 1, -1 do
        r.TrackFX_Delete(track, fis_to_delete[i])
    end
    local label = (#fis_to_delete == 1) and "Reflex: Cut FX"
                  or ("Reflex: Cut " .. #fis_to_delete .. " FX")
    r.Undo_EndBlock(label, -1)

    -- Flip op so the carry pill reads "cut" and future Cmd+X re-conversions
    -- don't double-fire (the conversion itself is now idempotent — second
    -- attempt finds source FX already gone and no-ops).
    nav_fx_clipboard.op = "cut"

    -- Invalidate caches
    InspMarkTrackFxDirty(track)
    if sends_fx_cache then sends_fx_cache[track] = nil end
    return true
end

-- Copy/Cut entry points. Resolve source set: multi-selection (bound to a track)
-- first, else hovered FX row as single-item fallback. Empty case for cut:
-- if clipboard has content from a prior copy, convert that to cut (v20.413).
-- Empty case for copy: silent no-op (selection was consumed; nothing to refresh).
-- include_automation: v20.411, true when called via Opt+Cmd variants.
FxClipDoCopyOrCut = function(op, include_automation)
    -- Prefer live multi-selection
    if InspFxSelCount() > 0 and insp_fx_sel_track
       and r.ValidatePtr(insp_fx_sel_track, "MediaTrack*") then
        local fis = InspFxSelGetFis(insp_fx_sel_track)
        if #fis > 0 then
            if FxClipCapture(insp_fx_sel_track, fis, op, include_automation) then
                FxClipRebuildGuidSet()
                return true
            end
            return false
        end
    end
    -- Hover fallback (single FX)
    local row = FxClipFindHoveredRow()
    if row and r.ValidatePtr(row.track, "MediaTrack*") then
        if FxClipCapture(row.track, { row.fi }, op, include_automation) then
            FxClipRebuildGuidSet()
            return true
        end
        return false
    end
    -- Empty source (no selection, no hover).
    -- v20.413: if Cmd+X with an existing copy-clipboard, convert to cut.
    -- Matches REAPER: "I copied, then changed my mind, do the cut" works
    -- without re-selecting. Silent no-op for Cmd+C in same state (nothing
    -- to refresh-copy from since selection was already consumed).
    if op == "cut" and FxClipHasContent() and nav_fx_clipboard.op == "copy" then
        return FxClipConvertCopyToCut()
    end
    return false
end

-- Copy ALL FX from a given track (or from hovered card, or inspected track).
-- Wired to Cmd+Shift+C and the "Copy all FX" menu item. v20.411.
FxClipCopyAllFX = function(track, include_automation)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then
        -- Fallback resolution: hovered card → inspected track
        local card = FxClipFindHoveredCard()
        if card and r.ValidatePtr(card.track, "MediaTrack*") then
            track = card.track
        elseif insp_track and r.ValidatePtr(insp_track, "MediaTrack*") then
            track = insp_track
        else
            return false
        end
    end
    local n = r.TrackFX_GetCount(track)
    if n == 0 then return false end
    local fis = {}
    for i = 0, n - 1 do fis[#fis + 1] = i end
    if FxClipCapture(track, fis, "copy", include_automation) then
        FxClipRebuildGuidSet()
        return true
    end
    return false
end

-- Remove all FX from a given track. Wired to Cmd+Shift+Delete and
-- "Remove all FX" menu item. v20.411.
FxClipRemoveAllFX = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    local n = r.TrackFX_GetCount(track)
    if n == 0 then return false end
    r.Undo_BeginBlock()
    for i = n - 1, 0, -1 do
        r.TrackFX_Delete(track, i)
    end
    r.Undo_EndBlock("Reflex: Remove all FX", -1)
    if insp_fx_sel_track == track then InspFxSelClear() end
    InspMarkTrackFxDirty(track)
    if sends_fx_cache then sends_fx_cache[track] = nil end
    return true
end

end

return ReflexInstallFXClipboardCore
