-- @noindex
-- Reflex FX row core module.
-- Installs shared FX.row context menu, outline, and interaction helpers.

ReflexInstallFXRowCore = function(deps)
    local r = deps.r
    local ctx = deps.ctx
    local C = deps.colors
    local CMP_EXT_SECTION = deps.cmp_ext_section
    local setCmpCheckTime = deps.set_cmp_check_time
    local beginFxRename = deps.begin_fx_rename

-- =====================================================================================
-- FxRowContextMenu — shared FX.row right-click menu (v20.419, Phase 1 unification)
-- =====================================================================================
-- Used by both InspDrawFXRow (inspector card) and DrawCompactTrackColumn (sends).
-- REAPER-native menu order: Copy all FX -> Copy/Cut variants -> Paste -> Remove ->
-- Bypass/Offline -> Duplicate -> Rename.
--
-- Selection-aware: when the clicked row is part of a live multi-selection bound to
-- `track`, action items operate on the whole selection (pluralized labels);
-- otherwise on this row only.
--
-- Args:
--   track    : MediaTrack* the FX lives on
--   fi       : 0-based REAPER FX index (inspector callers pass fx.fx_idx, not the
--              1-based ipairs index)
--   fx_guid  : FX GUID string (used for selection-scope detection)
--   fx_en    : bool — current enabled state (snapshot, ok to be ~1 frame stale)
--   fx_off   : bool — current offline state (snapshot)
--   popup_id : full popup id string (caller owns it; per-surface IDs avoid the
--              cross-card ImGui ID collision documented in PROJECT_KNOWLEDGE.md)
--   surface  : "inspector" | "sends" — retained for the unified signature
--
-- Note: PushPopupStyle wrap moved inside helper so both surfaces get the compact
-- popup style. Inspector previously rendered without it (v20.418 and earlier).
FxRowContextMenu = function(track, fi, fx_guid, fx_en, fx_off, popup_id, surface)
    PushPopupStyle()
    if r.ImGui_BeginPopup(ctx, popup_id) then
        -- Selection-scope detection
        local sel_active = (InspFxSelCount() > 0
                           and insp_fx_sel_track == track
                           and fx_guid ~= "" and InspFxSelHas(fx_guid))
        local sel_count = sel_active and InspFxSelCount() or 1
        local plural_suffix = (sel_count > 1) and (" " .. sel_count .. " FX") or " FX"

        -- Clipboard entries (REAPER-native menu layout)
        if r.ImGui_MenuItem(ctx, "Copy all FX", "\u{21E7}\u{2318}C") then
            FxClipCopyAllFX(track, false)
        end
        local copy_label = sel_active and ("Copy" .. plural_suffix) or "Copy FX"
        if r.ImGui_MenuItem(ctx, copy_label, "\u{2318}C") then
            if sel_active then
                FxClipCapture(track, InspFxSelGetFis(track), "copy", false)
            else
                FxClipCapture(track, { fi }, "copy", false)
            end
            FxClipRebuildGuidSet()
        end
        local copy_auto_label = (sel_active and ("Copy" .. plural_suffix) or "Copy FX") .. " (w/ auto)"
        if r.ImGui_MenuItem(ctx, copy_auto_label, "\u{2325}\u{2318}C") then
            if sel_active then
                FxClipCapture(track, InspFxSelGetFis(track), "copy", true)
            else
                FxClipCapture(track, { fi }, "copy", true)
            end
            FxClipRebuildGuidSet()
        end
        local cut_label = sel_active and ("Cut" .. plural_suffix) or "Cut FX"
        if r.ImGui_MenuItem(ctx, cut_label, "\u{2318}X") then
            if sel_active then
                FxClipCapture(track, InspFxSelGetFis(track), "cut", false)
            else
                FxClipCapture(track, { fi }, "cut", false)
            end
            FxClipRebuildGuidSet()
        end
        local cut_auto_label = (sel_active and ("Cut" .. plural_suffix) or "Cut FX") .. " (w/ auto)"
        if r.ImGui_MenuItem(ctx, cut_auto_label, "\u{2325}\u{2318}X") then
            if sel_active then
                FxClipCapture(track, InspFxSelGetFis(track), "cut", true)
            else
                FxClipCapture(track, { fi }, "cut", true)
            end
            FxClipRebuildGuidSet()
        end
        if FxClipHasContent() then
            local n = FxClipCount()
            local paste_noun = (n > 1) and (tostring(n) .. " FX") or "FX"
            if r.ImGui_MenuItem(ctx, "Paste " .. paste_noun .. " above") then
                FxClipPaste(track, fi)
            end
            if r.ImGui_MenuItem(ctx, "Paste " .. paste_noun .. " below", "\u{2318}V") then
                FxClipPaste(track, fi + 1)
            end
        else
            r.ImGui_BeginDisabled(ctx, true)
            r.ImGui_MenuItem(ctx, "Paste FX", "\u{2318}V")
            r.ImGui_EndDisabled(ctx)
        end
        r.ImGui_Separator(ctx)

        -- Remove entries
        local del_label = sel_active and ("Remove" .. plural_suffix) or "Remove FX"
        if r.ImGui_MenuItem(ctx, del_label, "\u{2326}") then
            if sel_active then
                FxClipDeleteSelection()
            else
                r.Undo_BeginBlock()
                r.TrackFX_Delete(track, fi)
                r.Undo_EndBlock("Reflex: Remove FX", -1)
                -- v20.433 Stage B: was `surface == "inspector"` gated — sends-surface
                -- removal of an FX on insp_track left insp_fx stale for one frame.
                -- Helper rescans on track-identity match instead of surface.
                InspMarkTrackFxDirty(track)
            end
        end
        if r.ImGui_MenuItem(ctx, "Remove all FX", "\u{21E7}\u{2326}") then
            FxClipRemoveAllFX(track)
        end
        r.ImGui_Separator(ctx)

        -- Bypass / Offline (selection-aware)
        local bypass_label = fx_en and "FX bypass" or "FX enable"
        if r.ImGui_MenuItem(ctx, bypass_label, "\u{2318}B") then
            if sel_active then
                local fis = InspFxSelGetFis(track)
                r.Undo_BeginBlock()
                for _, sfi in ipairs(fis) do
                    local en = r.TrackFX_GetEnabled(track, sfi)
                    r.TrackFX_SetEnabled(track, sfi, not en)
                end
                r.Undo_EndBlock((#fis == 1 and "Reflex: FX bypass" or ("Reflex: Bypass " .. #fis .. " FX")), -1)
            else
                r.Undo_BeginBlock()
                r.TrackFX_SetEnabled(track, fi, not fx_en)
                r.Undo_EndBlock("Reflex: " .. (fx_en and "Bypass" or "Enable") .. " FX", -1)
            end
        end
        local offline_label = fx_off and "FX online" or "FX offline"
        if r.ImGui_MenuItem(ctx, offline_label, "\u{2325}\u{2318}B") then
            if sel_active then
                local fis = InspFxSelGetFis(track)
                r.Undo_BeginBlock()
                for _, sfi in ipairs(fis) do
                    local off = r.TrackFX_GetOffline(track, sfi)
                    r.TrackFX_SetOffline(track, sfi, not off)
                end
                r.Undo_EndBlock((#fis == 1 and "Reflex: FX offline" or ("Reflex: Offline " .. #fis .. " FX")), -1)
            else
                r.Undo_BeginBlock()
                r.TrackFX_SetOffline(track, fi, not fx_off)
                r.Undo_EndBlock("Reflex: " .. (fx_off and "Online" or "Offline") .. " FX", -1)
            end
        end
        r.ImGui_Separator(ctx)

        -- Duplicate (Reflex addition, not in REAPER-native)
        if r.ImGui_MenuItem(ctx, "Duplicate") then
            r.Undo_BeginBlock()
            r.TrackFX_CopyToTrack(track, fi, track, fi + 1, false)
            r.Undo_EndBlock("Reflex: Duplicate FX", -1)
            -- v20.433 Stage B: see Remove FX site (~30 lines above) for rationale.
            InspMarkTrackFxDirty(track)
        end

        -- Rename FX instance — v20.430: extended to all surfaces (was
        -- inspector-only in Phase 1). Rename state now carries `insp_rename_track`
        -- for track binding; inspector and sends consumers both gate on it.
        if r.ImGui_MenuItem(ctx, "Rename FX instance", "F2") then
            local _, raw_name = r.TrackFX_GetFXName(track, fi, "")
            beginFxRename(track, fi, raw_name)
        end
        r.ImGui_EndPopup(ctx)
    end
    PopPopupStyle()
end

-- =====================================================================================
-- FxRowOutlineColor — shared FX.row outline cascade (v20.422, Phase 2 unification)
-- =====================================================================================
-- Returns a uint32 color for the row's outline rect, or nil for no outline.
-- Used by both InspDrawFXRow and DrawCompactTrackColumn. Caller draws its own
-- AddRect — only the color/priority logic is unified.
--
-- Args:
--   track   : MediaTrack* the FX lives on
--   fi      : 0-based REAPER FX index
--   guid    : FX GUID string. Empty string disables guid-based branches (defensive).
--   surface : "inspector" | "sends" — must match fx_drag.src_surface for the
--             drag-source branch to fire. Scopes drag visuals to the originating
--             surface (v20.422 — fixes latent inspector bug in self-send scenarios
--             where an inspected track that's also a sends-view return would
--             falsely light up under a sends-originated drag).
--
-- Cascade (mutually exclusive, first match wins):
--   1. drag active + src matches (track + surface) + fi in src_fis
--      → operation color (washed red move, blue copy) via live FxDragReadMode()
--   2. else not drag + NavPasteLandedHas(track, guid) + alpha > 0
--      → animated green (paste-landing pulse)
--   3. else not drag + FxClipHasGuid(guid)
--      → carry green C.fx_clip_carry
--   4. else not drag + InspFxSelHas(guid)
--      → white C.fx_sel_outline
--   5. else nil
FxRowOutlineColor = function(track, fi, guid, surface)
    if fx_drag.active and fx_drag.src_track == track
       and fx_drag.src_surface == surface and fx_drag.src_fis then
        for _, sf in ipairs(fx_drag.src_fis) do
            if sf == fi then
                local _op, _ = FxDragReadMode()
                return (_op == "copy") and (C.fx_drag_copy or rgb(0x58A6FF))
                                        or (C.fx_drag_move or rgb(0xE57373))
            end
        end
        return nil
    end
    if fx_drag.active then return nil end
    if guid == "" or guid == nil then return nil end

    if NavPasteLandedHas(track, guid) then
        local a = NavPasteLandedAlpha()
        if a > 0 then
            local base = C.fx_clip_carry or rgb(0x3FB950)
            local base_a = base & 0xFF
            local final_a = math.max(0, math.min(255, math.floor(base_a * a)))
            return (base & 0xFFFFFF00) | final_a
        end
        return nil
    end
    if FxClipHasGuid(guid) then
        -- Green wins over white during loud carry. FxClipHasGuid returns false
        -- once paste_count > 0, so after first paste this branch falls through
        -- and the white selection outline (data preserved) re-emerges.
        return C.fx_clip_carry or rgb(0x3FB950)
    end
    if InspFxSelHas(guid) then
        return C.fx_sel_outline or rgb(0xFFFFFF)
    end
    return nil
end

-- =====================================================================================
-- FxRowInteract — shared FX.row interaction kernel (v20.427, Phase 3 unification)
-- =====================================================================================
-- Caller still owns:
--   - Row sizing, geometry math, FxStateColors derivation
--   - Background AddRectFilled, Selectable + IsItemHovered (3-color push/pop)
--   - Tooltip suppression-during-carry (Tip("Shift: bypass\n..."))
--   - Per-surface rect cache (insp_fx_rects vs col_fx_rects)
--   - Text rendering, side widgets (A/B, wet, ENV, arrow), envelope details
--   - Fade overlay, outline render (FxRowOutlineColor + AddRect)
--   - Cursor advance, PopID
--
-- This helper handles:
--   - Drag begin (FxDragBegin) + activate (FxDragTryActivate)
--   - Hover/active fill (when not dragging) + pre-drag modifier legend
--   - Click dispatch (Opt remove / Cmd+Shift offline / Cmd toggle / Ctrl range /
--     Shift bypass / plain show)
--   - Focus-grab click suppression
--   - FxDragClear on release-without-drag
--   - Right-click open + FxRowContextMenu call
--
-- Two inspector-context side effects remain:
--   - cmp_key invalidation on Cmd+Shift offline (compare state is inspector-owned)
--   - InspPositionFXWindow after plain-click + opt_fx_float (geometry against inspector card)
--
-- Args (single table — many fields):
--   p.track, p.fi (0-based), p.guid, p.surface ("inspector"|"sends")
--   p.popup_id                              for FxRowContextMenu
--   p.sel, p.hovered                        caller's Selectable result
--   p.dl, p.cx, p.cy, p.w, p.h, p.radius    geometry for hover/active fill
--   p.hover_col, p.active_col               state colors for fill
--   p.enabled, p.offline                    FX state for bypass/offline branches
--   p.cmp_key                               inspector-only; nil/"" on sends
FxRowInteract = function(p)
    local track, fi, guid = p.track, p.fi, p.guid
    local surface = p.surface

    -- Drag begin / try-activate. Surface gate on activate is defensive (mirrors
    -- v20.422 FxRowOutlineColor surface gate); inspector now also checks
    -- src_track == track, harmless since inspector renders one track per frame.
    if r.ImGui_IsItemClicked(ctx, 0) and not fx_drag.active and not nav_focus_grab_eat_click then
        FxDragBegin(track, fi, surface)
    end
    if r.ImGui_IsItemActive(ctx) and fx_drag.src_fis and fx_drag.src_fis[1] == fi
       and fx_drag.src_track == track and fx_drag.src_surface == surface
       and not fx_drag.active then
        FxDragTryActivate()
    end

    -- Hover/active fill + pre-drag legend tip. Suppressed during active drag.
    if not fx_drag.active then
        if p.hovered and not p.sel then
            r.ImGui_DrawList_AddRectFilled(p.dl, p.cx, p.cy, p.cx + p.w, p.cy + p.h, p.hover_col, p.radius)
        elseif p.sel then
            r.ImGui_DrawList_AddRectFilled(p.dl, p.cx, p.cy, p.cx + p.w, p.cy + p.h, p.active_col, p.radius)
        end
        if p.hovered then FxDragLegendTip() end
    end

    -- Click dispatch — fires on release via Selectable. Gated on:
    --   sel: cursor still hovering on release frame
    --   not fx_drag.active: drag never crossed threshold (otherwise commit handles release)
    --   not nav_focus_grab_eat_click: v20.417 — first click after carry-mode
    --     "click to focus" hint is consumed for focus only.
    if p.sel and not fx_drag.active and not nav_focus_grab_eat_click then
        local mods = r.ImGui_GetKeyMods(ctx)
        if IsAlt(mods) then
            -- Opt: remove FX. Clears selection.
            InspFxSelClear()
            r.Undo_BeginBlock()
            r.TrackFX_Delete(track, fi)
            r.Undo_EndBlock("Reflex: Remove FX", -1)
            -- v20.433 Stage B: see FxRowContextMenu Remove for rationale.
            InspMarkTrackFxDirty(track)
        elseif IsCmd(mods) and IsShift(mods) then
            -- Cmd+Shift: offline. Clears selection.
            InspFxSelClear()
            local going_offline = not p.offline
            r.Undo_BeginBlock()
            r.TrackFX_SetOffline(track, fi, going_offline)
            if surface == "inspector" and going_offline and p.cmp_key and p.cmp_key ~= "" then
                r.SetProjExtState(0, CMP_EXT_SECTION, p.cmp_key, "")
                setCmpCheckTime(0)
            end
            r.Undo_EndBlock("Reflex: FX offline", -1)
        elseif IsCmd(mods) then
            -- Cmd: toggle individual FX in multi-select.
            InspFxSelBindTrack(track)
            InspFxSelToggle(guid)
        elseif IsCtrl(mods) then
            -- Ctrl: range-select from anchor through this row.
            InspFxSelBindTrack(track)
            InspFxSelRangeSet(track, guid)
        elseif IsShift(mods) then
            -- Shift: bypass (preserved — core REAPER interaction). Clears selection.
            InspFxSelClear()
            r.Undo_BeginBlock()
            r.TrackFX_SetEnabled(track, fi, not p.enabled)
            r.Undo_EndBlock("Reflex: FX bypass", -1)
        else
            -- Plain click: show FX chain/floating window. Clears selection.
            InspFxSelClear()
            local hwnd = r.TrackFX_GetFloatingWindow(track, fi)
            local chain_vis = r.TrackFX_GetChainVisible(track)
            if hwnd then
                r.TrackFX_Show(track, fi, 2)  -- hide float
            elseif chain_vis == fi then
                r.TrackFX_Show(track, fi, 0)  -- hide chain
            elseif opt_fx_float then
                r.TrackFX_Show(track, fi, 3)
                if surface == "inspector" then InspPositionFXWindow(track, fi) end
            else
                r.TrackFX_Show(track, fi, 1)  -- show in chain
            end
        end
        -- Clear seed state on release without drag — v20.427: previously inline
        -- only on sends; inspector relied on frame-level safety net in
        -- InspDrawFXArea (~line 8089). Inline clear is idempotent w/r/t the
        -- safety net so inspector behavior is unchanged in practice.
        if fx_drag.src_surface == surface and fx_drag.src_track == track
           and fx_drag.src_fis and fx_drag.src_fis[1] == fi then
            FxDragClear()
        end
    end

    -- Right-click menu (open + body). Right-click intentionally NOT gated on
    -- nav_focus_grab_eat_click — opening the paste menu is a valid focus-grab.
    if r.ImGui_IsItemClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, p.popup_id)
        nav_rclick_consumed = true  -- v20.486: claim rclick so card catch-all skips trknamectx
    end
    FxRowContextMenu(track, fi, guid, p.enabled, p.offline, p.popup_id, surface)
end

end

return ReflexInstallFXRowCore
