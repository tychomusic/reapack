-- @noindex
-- Reflex noise core module.
-- Installs the noise-floor scan helper used by the settings panel.

ReflexInstallNoiseCore = function(deps)
    local r = deps.r
    local get_noise_cache = deps.get_noise_cache

    NoiseScanAllTracks = function()
        local results = {}
        local noise_cache = get_noise_cache()
        local threshold_upper = 10 ^ (-50 / 20)   -- low-level-noise ceiling
        local threshold_lower = 10 ^ (-120 / 20)  -- ignore digital-floor residue
        local reliable_noise = 10 ^ (-100 / 20)
        local nt = r.CountTracks(0)
        for ti = 0, nt - 1 do
            local t = r.GetTrack(0, ti)
            local peak = math.max(r.Track_GetPeakInfo(t, 0), r.Track_GetPeakInfo(t, 1))
            if peak > threshold_lower and peak < threshold_upper then
                local tn = noise_cache[t]
                local has_variance = (tn and tn.L and tn.L.active) or (tn and tn.R and tn.R.active)
                if has_variance or peak > reliable_noise then
                    local _, name = r.GetTrackName(t)
                    local num = math.floor(r.GetMediaTrackInfo_Value(t, "IP_TRACKNUMBER"))
                    local db = 20 * math.log(math.max(peak, 1e-30), 10)
                    results[#results + 1] = { track = t, name = num .. ": " .. name, peak_db = db }
                end
            end
        end
        table.sort(results, function(a, b) return a.peak_db > b.peak_db end)
        return results
    end
end

return ReflexInstallNoiseCore
