-- @noindex
-- Reflex FX Browser core module.
-- Installs FX browser action persistence and backend/cache helpers.

ReflexInstallFXBrowserCore = function(deps)
    local r = deps.r
    local getButtons = deps.get_buttons

    local actionPath = function()
        return r.GetResourcePath() .. "/Scripts/Tycho/Reflex/fx_browser_action.txt"
    end

    InspLoadFXBrowserAction = function()
        local f = io.open(actionPath(), "r")
        if not f then return 0 end
        local val = f:read("*l")
        f:close()
        return tonumber(val) or 0
    end

    InspSaveFXBrowserAction = function(action_id)
        local f = io.open(actionPath(), "w")
        if f then f:write(tostring(action_id)); f:close() end
    end

    InspOpenFXBrowser = function(track)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
        -- Left-click +FX must target the clicked track deterministically. Do
        -- not delegate to saved REAPER actions here; stale actions can run
        -- unrelated commands such as creating/arming tracks.
        fx_browser_target_track = track
        fx_browser_target_btn = nil
        fx_browser_open = true
        fx_browser_search = ""
        fx_browser_focus_search = true
    end

    FxBrowserCleanName = function(raw)
        if not raw or raw == "" then return "" end
        -- Strip type prefix: "VST3: Name (Vendor)" -> "Name (Vendor)"
        local cleaned = raw:match("^[^:]+:%s*(.+)$") or raw
        return cleaned
    end

    FxBrowserBuildCache = function()
        fx_browser_cache = {}
        if not r.EnumInstalledFX then return end
        local idx = 0
        while true do
            local retval, name = r.EnumInstalledFX(idx)
            if not retval or not name or name == "" then break end
            local display = FxBrowserCleanName(name)
            local ftype = name:match("^([^:]+):") or ""
            fx_browser_cache[#fx_browser_cache + 1] = {
                name = name,          -- full ident for TrackFX_AddByName
                display = display,    -- cleaned for display
                lower = display:lower(),
                type = ftype,
            }
            idx = idx + 1
        end
        -- Sort alphabetically by display name
        table.sort(fx_browser_cache, function(a, b) return a.lower < b.lower end)
    end

    FxBrowserAssign = function(btn_idx, fx_name)
        local remote_buttons = getButtons()
        if not btn_idx or not remote_buttons[btn_idx] then return end
        RemotePushUndo()
        remote_buttons[btn_idx].plugin = fx_name
        remote_buttons[btn_idx].action = 0
        if remote_buttons[btn_idx].name == "" then
            remote_buttons[btn_idx].name = FxBrowserCleanName(fx_name):gsub("%s*%([^)]+%)%s*$", "")
        end
        RemoteSaveButtons()
    end
end

return ReflexInstallFXBrowserCore
