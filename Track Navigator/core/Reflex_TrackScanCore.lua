-- @noindex
-- Reflex track scan core module.
-- Installs top-level-track, subgroup, song-section, render-list, and song-list scanners.

ReflexInstallTrackScanCore = function(deps)
    local r = deps.r
    local SONG_SECTIONS = deps.song_sections
    local getRealistCurrentSong = deps.get_realist_current_song
    local excludedTrack = deps.excluded_track
    local hiddenTrack = deps.hidden_track or function() return false end
    local hiddenSubtree = deps.hidden_subtree or function() return false end
    local liveMode = deps.live_mode or function() return opt_live_mode == true end
    local trackAutoIgnored = deps.track_auto_ignored or function() return false end
    local getIncludedEntries = deps.get_included_entries or function() return {} end
    local getCustomSetEntries = deps.get_custom_set_entries or function() return {} end
    local customSetMode = deps.custom_set_mode or function() return opt_nav_custom_set_mode == true end
    local getSubGroups = deps.get_sub_groups
    local getSubGroupByName = deps.get_sub_group_by_name
    local getSongsSub = deps.get_songs_sub
    local getTopFolders = deps.get_top_folders
    local setTopFolders = deps.set_top_folders
    local setArchiveEntry = deps.set_archive_entry
    local getSongsEntryRef = deps.get_songs_entry_ref
    local setSongsEntryRef = deps.set_songs_entry_ref
    local setNeedsRescan = deps.set_needs_rescan
    local setRenderList = deps.set_render_list
    local setSongEntries = deps.set_song_entries
    local setNeedsSongRescan = deps.set_needs_song_rescan
    local setSongsLastClick = deps.set_songs_last_click

    ScanTopFolders = function()
        local top_folders = {}
        local songs_entry_ref = nil
        local archive_entry = nil
        local nt = r.CountTracks(0)
        local i = 0
        while i < nt do
            local track = r.GetTrack(0, i)
            local fd = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            if fd == 1 then
                local _, name = r.GetTrackName(track)
                local entry = { track = track, name = name, color = r.GetTrackColor(track), idx = i }
                top_folders[#top_folders + 1] = entry
                if liveMode() and name == "SONGS" then songs_entry_ref = entry end
                if name:lower() == "archive" then archive_entry = entry end
                local depth = 1
                i = i + 1
                while i < nt and depth > 0 do
                    depth = depth + r.GetMediaTrackInfo_Value(r.GetTrack(0, i), "I_FOLDERDEPTH")
                    i = i + 1
                end
            elseif r.GetTrackDepth(track) == 0 then
                local _, name = r.GetTrackName(track)
                top_folders[#top_folders + 1] = {
                    track = track,
                    name = name,
                    color = r.GetTrackColor(track),
                    idx = i,
                }
                i = i + 1
            else
                i = i + 1
            end
        end
        setTopFolders(top_folders)
        setSongsEntryRef(songs_entry_ref)
        setArchiveEntry(archive_entry)
        setNeedsRescan(false)
    end

    ScanSubGroups = function()
        local sub_groups = getSubGroups()
        local top_folders = getTopFolders()
        for _, sg in ipairs(sub_groups) do
            sg.entry_ref = nil
            sg.entries = {}
            for _, entry in ipairs(top_folders) do
                if entry.name == sg.parent_name then sg.entry_ref = entry; break end
            end
            if not sg.entry_ref then goto next_sg end
            local nt = r.CountTracks(0)
            local depth, i = 1, sg.entry_ref.idx + 1
            while i < nt and depth > 0 do
                local child = r.GetTrack(0, i)
                local cfd = r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
                if depth == 1 then
                    local _, name = r.GetTrackName(child)
                    local display = sg.filter_fn(name)
                    if display then
                        sg.entries[#sg.entries + 1] = {
                            track = child,
                            name = name,
                            display_name = display,
                            idx = i,
                            is_folder = (cfd == 1),
                            color = r.GetTrackColor(child),
                        }
                        if sg.selected[display] == nil then
                            sg.selected[display] = r.GetMediaTrackInfo_Value(child, "B_SHOWINTCP") == 1
                        end
                    end
                end
                depth = depth + cfd
                i = i + 1
            end
            ::next_sg::
        end
    end

    ScanSongSections = function()
        local songs_sub = getSongsSub()
        local songs_entry_ref = getSongsEntryRef()
        songs_sub.entry_ref = songs_entry_ref
        local cs = liveMode() and getRealistCurrentSong() or nil
        if not cs or not songs_entry_ref then
            songs_sub.entries = {}
            songs_sub.song_name = ""
            songs_sub.song_track = nil
            return
        end
        if cs == songs_sub.song_name and #songs_sub.entries > 0 then return end
        songs_sub.entries = {}
        songs_sub.song_name = cs
        songs_sub.song_track = nil
        songs_sub.song_idx = -1

        local nt = r.CountTracks(0)
        local depth, i = 1, songs_entry_ref.idx + 1
        while i < nt and depth > 0 do
            local child = r.GetTrack(0, i)
            local cfd = r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
            if depth == 1 then
                local _, nm = r.GetTrackName(child)
                local sn = nm:match("^SONG:%s*(.+)") or nm:match("^UTIL:%s*(.+)")
                if sn == cs then songs_sub.song_track = child; songs_sub.song_idx = i; break end
            end
            depth = depth + cfd
            i = i + 1
        end
        if not songs_sub.song_track then songs_sub.song_name = ""; return end

        depth = 1
        i = songs_sub.song_idx + 1
        while i < nt and depth > 0 do
            local child = r.GetTrack(0, i)
            local cfd = r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
            if depth == 1 then
                local _, nm = r.GetTrackName(child)
                if SONG_SECTIONS[nm] then
                    songs_sub.entries[#songs_sub.entries + 1] = {
                        track = child,
                        name = nm,
                        display_name = nm,
                        idx = i,
                        is_folder = (cfd == 1),
                        color = r.GetTrackColor(child),
                    }
                    if songs_sub.selected[nm] == nil then songs_sub.selected[nm] = true end
                end
            end
            depth = depth + cfd
            i = i + 1
        end
    end

    BuildRenderList = function()
        local render_list = {}
        local represented = {}
        local live_guids = {}
        ScanSongSections()
        local sub_group_by_name = getSubGroupByName()
        local songs_sub = getSongsSub()
        local included_entries = getIncludedEntries()
        local custom_set_mode = customSetMode() == true
        local custom_set_entries = custom_set_mode and getCustomSetEntries() or {}
        local nt = r.CountTracks(0)

        local roots = {}
        local nodes = {}
        local stack = {}
        local current_depth = 0
        for i = 0, nt - 1 do
            while #stack > current_depth do
                stack[#stack].end_idx = i - 1
                stack[#stack] = nil
            end
            local track = r.GetTrack(0, i)
            local depth = current_depth
            local fd = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            local _, name = r.GetTrackName(track)
            local guid = r.GetTrackGUID(track)
            local node = {
                track = track,
                guid = guid,
                name = name,
                color = r.GetTrackColor(track),
                idx = i,
                depth = depth,
                is_folder = (fd == 1),
                children = {},
                end_idx = i,
            }
            live_guids[guid] = true
            nodes[#nodes + 1] = node
            local parent = depth > 0 and stack[depth] or nil
            node.parent = parent
            if parent then parent.children[#parent.children + 1] = node
            else roots[#roots + 1] = node end
            stack[depth + 1] = node
            current_depth = math.max(0, current_depth + fd)
        end
        for i = #stack, 1, -1 do
            if stack[i] then stack[i].end_idx = nt - 1 end
        end
        if NavTreePruneState then NavTreePruneState(live_guids) end

        if pinned_folders then
            for _, node in ipairs(nodes) do
                if pinned_folders[node.guid] then
                    node.pinned_self = true
                    local p = node
                    while p do
                        p.pinned_path = true
                        if p ~= node then p.pinned_descendant = true end
                        p = p.parent
                    end
                end
            end
        end

        local custom_set_guids = {}
        for _, entry in ipairs(custom_set_entries or {}) do
            if entry.guid then custom_set_guids[entry.guid] = true end
        end
        for _, node in ipairs(nodes) do
            if custom_set_guids[node.guid] then node.custom_set_self = true end
        end

        local renderable_child_cache = {}
        local pinned_path_cache = {}

        local function node_blocked(node)
            return not node
                or hiddenSubtree(node.track)
                or trackAutoIgnored(node.track)
        end

        local has_renderable_children
        local function node_or_graft_renderable(node)
            if node_blocked(node) then return false end
            if excludedTrack(node.track) then return has_renderable_children(node) end
            return true
        end

        has_renderable_children = function(node)
            if not node or #node.children == 0 then return false end
            if renderable_child_cache[node.guid] ~= nil then return renderable_child_cache[node.guid] end
            for _, child in ipairs(node.children) do
                if node_or_graft_renderable(child) then
                    renderable_child_cache[node.guid] = true
                    return true
                end
            end
            renderable_child_cache[node.guid] = false
            return false
        end

        local has_renderable_pinned_path
        has_renderable_pinned_path = function(node)
            if node_blocked(node) then return false end
            if pinned_path_cache[node.guid] ~= nil then return pinned_path_cache[node.guid] end
            if excludedTrack(node.track) then
                for _, child in ipairs(node.children) do
                    if has_renderable_pinned_path(child) then
                        pinned_path_cache[node.guid] = true
                        return true
                    end
                end
                pinned_path_cache[node.guid] = false
                return false
            end
            pinned_path_cache[node.guid] = node.pinned_path == true
            return pinned_path_cache[node.guid]
        end

        local function has_renderable_pinned_child_path(node)
            if not node then return false end
            for _, child in ipairs(node.children) do
                if has_renderable_pinned_path(child) then return true end
            end
            return false
        end

        local function entry_for_node(node, color)
            return {
                track = node.track,
                name = node.name,
                color = color or node.color,
                idx = node.idx,
                is_folder = node.is_folder,
            }
        end

        local tlt_expand_enabled = opt_nav_tlt_expand ~= false

        local function add_custom(entry, tree_depth, visible_parent_guid)
            if not entry or not entry.track or not r.ValidatePtr(entry.track, "MediaTrack*") then return end
            local guid = r.GetTrackGUID(entry.track)
            if not represented[guid]
               and not excludedTrack(entry.track)
               and not hiddenSubtree(entry.track)
               and not trackAutoIgnored(entry.track) then
                render_list[#render_list + 1] = {
                    kind = "folder",
                    label = entry.name,
                    color = entry.color,
                    track = entry.track,
                    idx = entry.idx,
                    entry = entry,
                    is_folder = entry.is_folder,
                    custom = true,
                    tree_depth = tree_depth or 0,
                    tree_parent_guid = visible_parent_guid,
                    tree_promoted = true,
                    nav_flat_promoted = tlt_expand_enabled == false,
                }
                represented[guid] = true
            end
        end

        local function add_custom_range(first_idx, last_idx, tree_depth, visible_parent_guid)
            if last_idx < first_idx then return end
            for _, entry in ipairs(included_entries) do
                if entry.idx >= first_idx and entry.idx <= last_idx then
                    add_custom(entry, tree_depth, visible_parent_guid)
                end
            end
        end

        local function add_sub_group_items(sg, first_idx, last_idx, tree_depth, visible_parent_guid)
            local last_emit_idx = first_idx - 1
            for _, child in ipairs(sg.entries) do
                if not hiddenSubtree(child.track) and not trackAutoIgnored(child.track) then
                    add_custom_range(last_emit_idx + 1, child.idx - 1, tree_depth, visible_parent_guid)
                    render_list[#render_list + 1] = {
                        kind = "sub_child",
                        label = child.display_name,
                        color = child.color,
                        track = child.track,
                        idx = child.idx,
                        entry = child,
                        is_folder = child.is_folder,
                        sub_group = sg,
                        tree_depth = tree_depth or 0,
                        tree_parent_guid = visible_parent_guid,
                    }
                    represented[r.GetTrackGUID(child.track)] = true
                    last_emit_idx = child.idx
                end
            end
            add_custom_range(last_emit_idx + 1, last_idx, tree_depth, visible_parent_guid)
        end

        local search_query = tostring(nav_tlt_search_effective_query or ""):lower()
        local normalized_search_query = search_query:match("^%s*(.-)%s*$") or ""
        local operator_search = normalized_search_query:sub(1, 1) == "/"
        local pinned_only_search = normalized_search_query == "/pin"
        local search_active = search_query ~= ""

        local function node_matches_search(node)
            if pinned_only_search then return node and node.pinned_self == true end
            if operator_search then return false end
            return node
                and search_query ~= ""
                and tostring(node.name or ""):lower():find(search_query, 1, true) ~= nil
        end

        local function node_sub_group(node, tree_depth, ghost_parent)
            if tree_depth == 0 and not ghost_parent then
                local sg = sub_group_by_name[node.name]
                if liveMode() and node.name == "SONGS" and #songs_sub.entries > 0 then sg = songs_sub end
                return sg
            end
            return nil
        end

        local function emit_flat_node(node, tree_depth, visible_parent_guid, ghost_parent, opts)
            opts = opts or {}
            if not node or represented[node.guid] then return nil end
            local display_color = node.color
            if display_color == 0 and ghost_parent and ghost_parent.color then display_color = ghost_parent.color end
            local sg = opts.no_sub_group == true and nil or node_sub_group(node, tree_depth or 0, ghost_parent)
            local expandable = opts.expandable == true and tlt_expand_enabled and has_renderable_children(node)
            local layer_scope = opts.layer_scope
            local explicit_expanded = nav_tree_expanded and nav_tree_expanded[node.guid] == true
            local expanded = false
            if expandable and tlt_expand_enabled then
                if NavTreeItemExpanded then
                    expanded = NavTreeItemExpanded(node.guid, layer_scope)
                else
                    expanded = explicit_expanded
                end
            end
            local item_entry = entry_for_node(node, display_color)
            render_list[#render_list + 1] = {
                kind = "folder",
                label = node.name,
                color = display_color,
                track = node.track,
                idx = node.idx,
                entry = item_entry,
                is_folder = node.is_folder,
                sub_group = sg,
                ghost_parent = ghost_parent,
                custom = opts.custom == true,
                tree_depth = tree_depth or 0,
                tree_parent_guid = visible_parent_guid,
                tree_guid = expandable and node.guid or nil,
                tree_layer_scope = expandable and layer_scope or nil,
                tree_expandable = expandable == true,
                tree_explicit_expanded = explicit_expanded,
                tree_expanded = expanded == true,
                tree_partial = false,
                tree_search_result = opts.search_result == true,
                tree_search_match = opts.search_match == true,
                tree_custom_set = opts.custom_set == true,
                nav_flat_promoted = opts.flat_promoted == true
                    or (opts.search_result == true and (tree_depth or 0) == 0 and node.parent ~= nil),
            }
            represented[node.guid] = true
            return expanded
        end

        local function emit_legacy_flat()
            for _, root in ipairs(roots) do
                if not node_blocked(root) then
                    local root_entry = entry_for_node(root)
                    local sg = node_sub_group(root, 0, nil)
                    if excludedTrack(root.track) then
                        represented[root.guid] = true
                        local last_emit_idx = root.idx
                        for _, child in ipairs(root.children) do
                            if not node_blocked(child) then
                                add_custom_range(last_emit_idx + 1, child.idx - 1, 0, nil)
                                if not excludedTrack(child.track) and not hiddenTrack(child.track) then
                                    local display_color = child.color
                                    if display_color == 0 then display_color = root.color end
                                    local child_entry = entry_for_node(child, display_color)
                                    render_list[#render_list + 1] = {
                                        kind = "folder",
                                        label = child.name,
                                        color = display_color,
                                        track = child.track,
                                        idx = child.idx,
                                        entry = child_entry,
                                        is_folder = child.is_folder,
                                        ghost_parent = root_entry,
                                        tree_promoted = true,
                                        nav_flat_promoted = true,
                                    }
                                end
                                represented[child.guid] = true
                                last_emit_idx = child.end_idx
                            end
                        end
                        add_custom_range(last_emit_idx + 1, root.end_idx, 0, nil)
                    else
                        render_list[#render_list + 1] = {
                            kind = "folder",
                            label = root.name,
                            color = root.color,
                            track = root.track,
                            idx = root.idx,
                            entry = root_entry,
                            is_folder = root.is_folder,
                            sub_group = sg,
                        }
                        represented[root.guid] = true
                        add_custom_range(root.idx + 1, root.end_idx, 0, nil)
                    end
                end
            end
        end

        local emit_search_matches
        local emit_search_expanded_children
        local function emit_search_row(node, tree_depth, visible_parent_guid, ghost_parent, search_match)
            local layer_scope = "search:" .. (((visible_parent_guid and visible_parent_guid ~= "") and visible_parent_guid or "root"))
                .. "#" .. tostring(tree_depth or 0)
            local expanded = emit_flat_node(node, tree_depth, visible_parent_guid, ghost_parent, {
                expandable = true,
                layer_scope = layer_scope,
                search_result = true,
                search_match = search_match == true,
            })
            if expanded then
                emit_search_expanded_children(node, (tree_depth or 0) + 1, node.guid, ghost_parent)
            end
            return expanded == true
        end

        emit_search_expanded_children = function(parent, tree_depth, visible_parent_guid, ghost_parent)
            for _, child in ipairs(parent.children) do
                if not node_blocked(child) then
                    if excludedTrack(child.track) then
                        represented[child.guid] = true
                        emit_search_expanded_children(child, tree_depth, visible_parent_guid, entry_for_node(child))
                    elseif not represented[child.guid] then
                        emit_search_row(child, tree_depth, visible_parent_guid, ghost_parent, node_matches_search(child))
                    end
                end
            end
        end

        emit_search_matches = function(node)
            if node_blocked(node) then return end
            if excludedTrack(node.track) then
                represented[node.guid] = true
                for _, child in ipairs(node.children) do emit_search_matches(child) end
                return
            end
            if node_matches_search(node) then
                local expanded = emit_search_row(node, 0, nil, nil, true)
                if not expanded then
                    for _, child in ipairs(node.children) do emit_search_matches(child) end
                end
            else
                for _, child in ipairs(node.children) do emit_search_matches(child) end
            end
        end

        local function emit_pinned_only_matches()
            for _, node in ipairs(nodes) do
                if node.pinned_self == true
                    and not node_blocked(node)
                    and not excludedTrack(node.track)
                    and not represented[node.guid] then
                    emit_flat_node(node, 0, nil, nil, {
                        no_sub_group = true,
                        search_result = true,
                        search_match = true,
                    })
                end
            end
        end

        local function emit_custom_set_matches()
            for _, node in ipairs(nodes) do
                if node.custom_set_self == true
                    and not node_blocked(node)
                    and not excludedTrack(node.track)
                    and not represented[node.guid]
                    and (not search_active or node_matches_search(node)) then
                    emit_flat_node(node, 0, nil, nil, {
                        no_sub_group = true,
                        search_result = true,
                        search_match = true,
                        custom_set = true,
                    })
                end
            end
        end

        if pinned_only_search then
            emit_pinned_only_matches()
            setRenderList(render_list)
            return
        end

        if custom_set_mode then
            emit_custom_set_matches()
            setRenderList(render_list)
            return
        end

        if search_active then
            for _, root in ipairs(roots) do emit_search_matches(root) end
            setRenderList(render_list)
            return
        end

        if not tlt_expand_enabled then
            emit_legacy_flat()
            setRenderList(render_list)
            return
        end

        local emit_node
        local function emit_children(parent, tree_depth, visible_parent_guid, only_pinned_path, graft_parent)
            local last_emit_idx = parent.idx
            for _, child in ipairs(parent.children) do
                if not node_blocked(child) then
                    local child_has_path = has_renderable_pinned_path(child)
                    if not only_pinned_path or child_has_path then
                        add_custom_range(last_emit_idx + 1, child.idx - 1, tree_depth, visible_parent_guid)
                        emit_node(child, tree_depth, visible_parent_guid, only_pinned_path, graft_parent)
                        last_emit_idx = child.end_idx
                    end
                end
            end
            add_custom_range(last_emit_idx + 1, parent.end_idx, tree_depth, visible_parent_guid)
        end

        emit_node = function(node, tree_depth, visible_parent_guid, only_pinned_path, ghost_parent)
            if node_blocked(node) then return end
            local node_entry = entry_for_node(node)
            if excludedTrack(node.track) then
                represented[node.guid] = true
                if has_renderable_children(node) then
                    emit_children(node, tree_depth, visible_parent_guid, only_pinned_path, node_entry)
                end
                return
            end

            if only_pinned_path and not has_renderable_pinned_path(node) then return end

            local is_root = tree_depth == 0 and not ghost_parent
            local sg = is_root and sub_group_by_name[node.name] or nil
            if is_root and liveMode() and node.name == "SONGS" and #songs_sub.entries > 0 then sg = songs_sub end

            local expandable = has_renderable_children(node) or (sg and #sg.entries > 0)
            local layer_scope = ((visible_parent_guid and visible_parent_guid ~= "") and visible_parent_guid or "root")
                .. "#" .. tostring(tree_depth or 0)
            local explicit_expanded = nav_tree_expanded and nav_tree_expanded[node.guid] == true
            local expanded = false
            if expandable then
                if NavTreeItemExpanded then
                    expanded = NavTreeItemExpanded(node.guid, layer_scope)
                else
                    expanded = explicit_expanded
                end
            end
            local forced_path = expandable and not expanded and has_renderable_pinned_child_path(node)
            local display_color = node.color
            if display_color == 0 and ghost_parent and ghost_parent.color then display_color = ghost_parent.color end
            local item_entry = entry_for_node(node, display_color)

            render_list[#render_list + 1] = {
                kind = "folder",
                label = node.name,
                color = display_color,
                track = node.track,
                idx = node.idx,
                entry = item_entry,
                is_folder = node.is_folder,
                sub_group = sg,
                ghost_parent = ghost_parent,
                tree_depth = tree_depth or 0,
                tree_parent_guid = visible_parent_guid,
                tree_guid = node.guid,
                tree_layer_scope = layer_scope,
                tree_expandable = expandable == true,
                tree_explicit_expanded = explicit_expanded,
                tree_expanded = expanded == true,
                tree_partial = forced_path == true,
            }
            represented[node.guid] = true

            if expanded then
                if sg and #sg.entries > 0 then
                    add_sub_group_items(sg, node.idx + 1, node.end_idx, (tree_depth or 0) + 1, node.guid)
                else
                    emit_children(node, (tree_depth or 0) + 1, node.guid, false)
                end
            elseif forced_path then
                emit_children(node, (tree_depth or 0) + 1, node.guid, true)
            end
        end

        for _, root in ipairs(roots) do
            emit_node(root, 0, nil, false, nil)
        end
        setRenderList(render_list)
    end

    ScanSongs = function()
        local song_entries = {}
        if not liveMode() then
            setSongEntries(song_entries)
            setNeedsSongRescan(false)
            setSongsLastClick(nil)
            return
        end
        local nt = r.CountTracks(0)
        for i = 0, nt - 1 do
            local track = r.GetTrack(0, i)
            local _, name = r.GetTrackName(track)
            local sn = name:match("^SONG:%s*(.+)")
            if sn then
                song_entries[#song_entries + 1] = {
                    track = track,
                    name = sn,
                    full_name = name,
                    idx = i,
                    is_folder = (r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1),
                }
            end
        end
        table.sort(song_entries, function(a, b) return a.name:lower() < b.name:lower() end)
        setSongEntries(song_entries)
        setNeedsSongRescan(false)
        setSongsLastClick(nil)
    end
end

return ReflexInstallTrackScanCore
