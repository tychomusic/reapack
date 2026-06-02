-- @noindex
-- Reflex meter core module.
-- Installs shared meter color, peak smoothing, and volume knob mapping helpers.

ReflexInstallMeterCore = function(deps)
    local C = deps.colors

    -- Map amplitude to knob position: 0dB at 12 o'clock (t=0.5).
    -- Left half (t=0..0.5): -inf..0dB with sqrt curve (spreads useful range).
    -- Right half (t=0.5..1): 0dB..+12dB linear.
    VolToKnobT = function(vol)
        if vol < 0.00001 then return 0 end
        local db = 20 * math.log(vol, 10)
        if db >= 0 then
            return 0.5 + db / 24
        else
            return 0.5 * (1 - math.sqrt(math.min(-db, 60) / 60))
        end
    end

    -- Meter color by dB threshold: green normally, red only at/above digital full scale.
    MeterColor = function(db)
        if db >= 0 then return C.fx_offline_txt
        else return C.green end
    end

    -- Smooth peak value with asymmetric attack/decay.
    -- cache: table, key: any hashable, raw: current raw peak, decay: 0..1.
    SmoothPeak = function(cache, key, raw, decay)
        local prev = cache[key] or 0
        if raw >= prev then
            cache[key] = raw
        else
            cache[key] = prev * (decay or 0.85)
        end
        return cache[key]
    end
end

return ReflexInstallMeterCore
