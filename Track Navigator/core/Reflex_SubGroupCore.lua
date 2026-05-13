-- @noindex
-- Reflex subgroup core module.
-- Installs subgroup save/apply/show helpers.

ReflexInstallSubGroupCore = function(deps)
    local r = deps.r
    local setTrackVis = deps.set_track_vis

    SaveSubGroupState = function(sg)
        for _, e in ipairs(sg.entries) do
            sg.selected[e.display_name] = r.GetMediaTrackInfo_Value(e.track, "B_SHOWINTCP") == 1
        end
    end

    ApplySubGroupSelection = function(sg)
        if not sg.entry_ref then return end
        local sel = {}
        for _, e in ipairs(sg.entries) do
            if sg.selected[e.display_name] then sel[e.idx] = true end
        end
        local nt = r.CountTracks(0)
        local d, i, cv = 1, sg.entry_ref.idx + 1, false
        while i < nt and d > 0 do
            local child = r.GetTrack(0, i)
            local cfd = r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
            if d == 1 then
                cv = (sel[i] == true)
                setTrackVis(child, cv)
                if cfd == 1 then r.SetMediaTrackInfo_Value(child, "I_FOLDERCOMPACT", cv and 0 or 2) end
            else
                setTrackVis(child, cv)
            end
            d = d + cfd
            i = i + 1
        end
    end

    ShowSubGroupSelected = function(sg)
        local any = false
        for _, e in ipairs(sg.entries) do
            if sg.selected[e.display_name] then any = true; break end
        end
        if not any then
            for _, e in ipairs(sg.entries) do sg.selected[e.display_name] = true end
        end
        ApplySubGroupSelection(sg)
        -- Set parent visible LAST.
        setTrackVis(sg.entry_ref.track, true)
        r.SetMediaTrackInfo_Value(sg.entry_ref.track, "I_FOLDERCOMPACT", 0)
    end
end

return ReflexInstallSubGroupCore
