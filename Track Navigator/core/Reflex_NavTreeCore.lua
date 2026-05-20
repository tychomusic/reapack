-- @noindex
-- Reflex nav tree disclosure core module.
-- Installs GUID-keyed, per-project Navigator tree expansion helpers.

ReflexInstallNavTreeCore = function(deps)
    local r = deps.r
    local getRenderList = deps.get_render_list or function() return render_list or {} end
    local markDirty = deps.mark_dirty or function() end
    local _tree_last_proj = nil

    nav_tree_expanded = {}
    nav_tree_layer_overrides = {}

    local function NavTreeTrackGuid(track)
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
        return r.GetTrackGUID(track)
    end

    local function NavTreeSortedKeys(t)
        local parts = {}
        for key in pairs(t or {}) do parts[#parts + 1] = key end
        table.sort(parts)
        return parts
    end

    LoadNavTreeExpansion = function()
        nav_tree_expanded = {}
        local _, v = r.GetProjExtState(0, "reflex", "nav_tree_expanded")
        if v and v ~= "" then
            for guid in v:gmatch("([^|]+)") do nav_tree_expanded[guid] = true end
        end

        nav_tree_layer_overrides = {}
        local _, ov = r.GetProjExtState(0, "reflex", "nav_tree_layer_overrides")
        if ov and ov ~= "" then
            for scope, state in ov:gmatch("([^=|]+)=([^|]+)") do
                if state == "expanded" or state == "collapsed" then
                    nav_tree_layer_overrides[scope] = state
                end
            end
        end
        _tree_last_proj = r.EnumProjects(-1)
    end

    SaveNavTreeExpansion = function()
        local expanded = NavTreeSortedKeys(nav_tree_expanded)
        r.SetProjExtState(0, "reflex", "nav_tree_expanded", table.concat(expanded, "|"))

        local overrides = {}
        for _, scope in ipairs(NavTreeSortedKeys(nav_tree_layer_overrides)) do
            overrides[#overrides + 1] = scope .. "=" .. nav_tree_layer_overrides[scope]
        end
        r.SetProjExtState(0, "reflex", "nav_tree_layer_overrides", table.concat(overrides, "|"))
    end

    MaybeReloadNavTreeExpansion = function()
        local cur = r.EnumProjects(-1)
        if cur ~= _tree_last_proj then LoadNavTreeExpansion() end
    end

    NavTreeHasExpansionState = function()
        for _ in pairs(nav_tree_expanded or {}) do return true end
        for _ in pairs(nav_tree_layer_overrides or {}) do return true end
        return false
    end

    NavTreeResetExpansion = function()
        if not NavTreeHasExpansionState() then return false end
        nav_tree_expanded = {}
        nav_tree_layer_overrides = {}
        SaveNavTreeExpansion()
        markDirty()
        return true
    end

    NavTreePruneState = function(live_guids, live_scopes)
        local changed = false
        if live_guids then
            for guid in pairs(nav_tree_expanded) do
                if not live_guids[guid] then
                    nav_tree_expanded[guid] = nil
                    changed = true
                end
            end
            for scope in pairs(nav_tree_layer_overrides) do
                local parent_guid = tostring(scope):match("^(.-)#")
                if parent_guid and parent_guid:sub(1, 7) == "search:" then
                    parent_guid = parent_guid:sub(8)
                end
                if parent_guid and parent_guid ~= "root" and not live_guids[parent_guid] then
                    nav_tree_layer_overrides[scope] = nil
                    changed = true
                end
            end
        end
        if live_scopes then
            for scope in pairs(nav_tree_layer_overrides) do
                if not live_scopes[scope] then
                    nav_tree_layer_overrides[scope] = nil
                    changed = true
                end
            end
        end
        if changed then SaveNavTreeExpansion() end
        return changed
    end

    NavTreeLayerOverride = function(scope)
        if not scope then return nil end
        return nav_tree_layer_overrides and nav_tree_layer_overrides[scope] or nil
    end

    NavTreeItemExpanded = function(guid, layer_scope)
        if not guid then return false end
        local override = NavTreeLayerOverride(layer_scope)
        if override == "collapsed" then return false end
        if override == "expanded" then return true end
        return nav_tree_expanded and nav_tree_expanded[guid] == true
    end

    NavTreeSetItemExpanded = function(item, expanded)
        if not item then return false end
        local guid = item.tree_guid or NavTreeTrackGuid(item.track or (item.entry and item.entry.track))
        if not guid then return false end
        if expanded then nav_tree_expanded[guid] = true
        else nav_tree_expanded[guid] = nil end
        if item.tree_layer_scope then nav_tree_layer_overrides[item.tree_layer_scope] = nil end
        SaveNavTreeExpansion()
        markDirty()
        return true
    end

    NavTreeToggleItem = function(item)
        if not item or not item.tree_expandable then return false end
        return NavTreeSetItemExpanded(item, not item.tree_expanded)
    end

    NavTreeToggleGeneration = function(item)
        if not item or not item.tree_layer_scope then return false end
        local scope = item.tree_layer_scope
        nav_tree_layer_overrides[scope] = item.tree_expanded and "collapsed" or "expanded"
        SaveNavTreeExpansion()
        markDirty()
        return true
    end
end

return ReflexInstallNavTreeCore
