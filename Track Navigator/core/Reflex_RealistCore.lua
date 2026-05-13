-- @noindex
-- Reflex Realist core module.
-- Installs read-only Realist song lookup and song-region view clamp helpers.

ReflexInstallRealistCore = function(deps)
    local r = deps.r
    local REALIST_SECTION = deps.realist_section or "realist"
    local VIEWLOCK_SETTLE = 15
    vl_stable, vl_ps, vl_pe = 0, 0, 0

    GetRealistCurrentSong = function()
        local rv, idx_str = r.GetProjExtState(0, REALIST_SECTION, "last_song_index")
        if rv == 0 or idx_str == "" then return nil end
        local idx = tonumber(idx_str)
        if not idx or idx < 1 then return nil end
        local rv2, so = r.GetProjExtState(0, REALIST_SECTION, "saved_order")
        if rv2 == 0 or so == "" then return nil end
        local pos = 0
        for entry in so:gmatch("([^|]+)") do
            pos = pos + 1
            if pos == idx then
                local et, label = entry:match("^(%u+):(.*)$")
                return (et == "SONG" or et == "UTIL") and label or nil
            end
        end
        return nil
    end

    FindSongRegionBounds = function(song_name)
        if not song_name then return nil, nil end
        local i = 0
        while true do
            local ret, is_rgn, pos, rgnend, name = r.EnumProjectMarkers(i)
            if ret == 0 then break end
            if is_rgn then
                local l = name:match("^SONG:%s*(.+)") or name:match("^UTIL:%s*(.+)")
                if l == song_name then return pos, rgnend end
            end
            i = i + 1
        end
        return nil, nil
    end

    ClampViewToRegion = function(rs, re)
        local vs, ve = r.GetSet_ArrangeView2(0, false, 0, 0)
        if math.abs(vs - vl_ps) > 0.0001 or math.abs(ve - vl_pe) > 0.0001 then
            vl_stable = 0; vl_ps = vs; vl_pe = ve; return
        end
        vl_ps = vs; vl_pe = ve; vl_stable = vl_stable + 1
        if vl_stable < VIEWLOCK_SETTLE then return end
        if vs < rs then
            local len = ve - vs
            r.GetSet_ArrangeView2(0, true, 0, 0, rs, rs + len)
            vl_ps = rs; vl_pe = rs + len; vl_stable = 0
        end
    end
end

return ReflexInstallRealistCore
