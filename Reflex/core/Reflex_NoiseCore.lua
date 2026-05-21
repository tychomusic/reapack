-- @noindex
-- Reflex noise core module.
-- Installs the noise-floor scan helper used by the settings panel.

ReflexInstallNoiseCore = function(deps)
    local r = deps.r
    local get_noise_cache = deps.get_noise_cache

    NoiseScanAllTracks = function()
        local results = {}
        local noise_cache = get_noise_cache()
        local threshold_upper = 0.00001  -- -100dB (meter display threshold)
        local threshold_lower = 1e-9     -- -180dB (above true zero, catches most plugin noise)
        local nt = r.CountTracks(0)
        for ti = 0, nt - 1 do
            local t = r.GetTrack(0, ti)
            local peak = math.max(r.Track_GetPeakInfo(t, 0), r.Track_GetPeakInfo(t, 1))
            if peak > threshold_lower and peak < threshold_upper then
                -- Check variance: read peak again and compare (crude single-frame check)
                local mn = noise_cache[t]
                local has_variance = mn and mn.active
                if has_variance or peak > 1e-7 then  -- either variance-confirmed or clearly above FP
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
