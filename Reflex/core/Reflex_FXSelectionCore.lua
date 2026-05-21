-- @noindex
-- Reflex FX selection core module.
-- Installs FX multi-select state and backend helpers.

ReflexInstallFXSelectionCore = function(deps)
    local r = deps.r

    -- FX multi-select state (inspector only, v20.403).
    -- Selection is stored GUID-keyed so it survives FX reorder. Bound to a
    -- single MediaTrack*; any track switch or non-selection interaction clears.
    insp_fx_sel = {}             -- { [guid] = true }
    insp_fx_sel_track = nil      -- MediaTrack* this selection belongs to
    insp_fx_sel_anchor = nil     -- GUID for range-select anchor

    -- Mutate-in-place clear (preserves table identity for upvalue captures).
    InspFxSelClear = function()
        for k in pairs(insp_fx_sel) do insp_fx_sel[k] = nil end
        insp_fx_sel_track = nil
        insp_fx_sel_anchor = nil
    end

    InspFxSelCount = function()
        local n = 0
        for _ in pairs(insp_fx_sel) do n = n + 1 end
        return n
    end

    InspFxSelHas = function(guid)
        return guid ~= nil and guid ~= "" and insp_fx_sel[guid] == true
    end

    -- Sanity: if a click arrives on a track different from the bound one, the
    -- selection is stale. Clear before applying the click's modifier semantics.
    InspFxSelBindTrack = function(track)
        if insp_fx_sel_track ~= track then InspFxSelClear() end
        insp_fx_sel_track = track
    end

    -- Toggle one GUID; sets (or advances) the anchor to this row.
    -- If the toggle removes the current anchor, pick any remaining selected
    -- row as the new anchor, or clear if selection is now empty.
    InspFxSelToggle = function(guid)
        if not guid or guid == "" then return end
        if insp_fx_sel[guid] then
            insp_fx_sel[guid] = nil
            if insp_fx_sel_anchor == guid then
                insp_fx_sel_anchor = nil
                for k in pairs(insp_fx_sel) do insp_fx_sel_anchor = k; break end
            end
        else
            insp_fx_sel[guid] = true
            insp_fx_sel_anchor = guid
        end
    end

    -- Add to selection without removing others; sets anchor.
    InspFxSelAdd = function(guid)
        if not guid or guid == "" then return end
        insp_fx_sel[guid] = true
        insp_fx_sel_anchor = guid
    end

    -- Range-set: replace selection with the span from anchor_guid through
    -- end_guid (inclusive) in the target track's FX order. If no anchor exists
    -- yet, treat as single-select of end_guid (also sets as anchor).
    -- v20.406: takes `track` and iterates REAPER API directly instead of
    -- `insp_fx`, so it works for secondary cards and send modules.
    InspFxSelRangeSet = function(track, end_guid)
        if not end_guid or end_guid == "" then return end
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
        if not insp_fx_sel_anchor then
            for k in pairs(insp_fx_sel) do insp_fx_sel[k] = nil end
            insp_fx_sel[end_guid] = true
            insp_fx_sel_anchor = end_guid
            return
        end
        local anchor_idx, end_idx
        local count = r.TrackFX_GetCount(track)
        for i = 0, count - 1 do
            local g = r.TrackFX_GetFXGUID(track, i)
            if g == insp_fx_sel_anchor then anchor_idx = i end
            if g == end_guid then end_idx = i end
        end
        if not anchor_idx or not end_idx then return end
        for k in pairs(insp_fx_sel) do insp_fx_sel[k] = nil end
        local lo, hi = anchor_idx, end_idx
        if lo > hi then lo, hi = hi, lo end
        for i = lo, hi do
            local g = r.TrackFX_GetFXGUID(track, i)
            if g and g ~= "" then insp_fx_sel[g] = true end
        end
    end

    -- Return sorted 0-based fx indices on the given track for currently
    -- selected GUIDs. v20.406: takes `track` arg and iterates REAPER directly.
    InspFxSelGetFis = function(track)
        local out = {}
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return out end
        for i = 0, r.TrackFX_GetCount(track) - 1 do
            local g = r.TrackFX_GetFXGUID(track, i)
            if g and insp_fx_sel[g] then out[#out + 1] = i end
        end
        return out  -- already sorted ascending (loop order)
    end
end

return ReflexInstallFXSelectionCore
