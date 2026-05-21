-- @noindex
-- Reflex send FX cache core module.
-- Installs SEND-surface FX-name cache refresh helpers.

ReflexInstallSendFxCacheCore = function(deps)
    local r = deps.r

SendsEnsureFxNameCache = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil, 0 end
    local cur_fx_count = r.TrackFX_GetCount(track)
    local fc = sends_fx_cache[track]
    if not fc or fc.count ~= cur_fx_count then
        local names = {}
        for fxi = 0, cur_fx_count - 1 do
            local _, fn = r.TrackFX_GetFXName(track, fxi)
            names[fxi] = CleanFXDisplayName(fn)
        end
        sends_fx_cache[track] = { names = names, count = cur_fx_count }
        fc = sends_fx_cache[track]
    end
    return fc, cur_fx_count
end

SendsFxCachedCount = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return 0 end
    local fc = sends_fx_cache[track]
    if fc then return fc.count or 0 end
    return r.TrackFX_GetCount(track)
end

end

return ReflexInstallSendFxCacheCore
