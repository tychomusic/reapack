-- @noindex
-- Reflex send creation core module.
-- Installs SEND/CTRL.route send creation and conforming Returns* helpers.

ReflexInstallSendCreateCore = function(deps)
    local r = deps.r
    local ctx = deps.ctx
    local C = deps.colors
    local script_dir = deps.script_dir or ""

QuickSendFolderPath = function()
    return script_dir .. "quick_sends"
end

QuickSendEnsureFolder = function()
    local dir = QuickSendFolderPath()
    if r.RecursiveCreateDirectory then
        r.RecursiveCreateDirectory(dir, 0)
    else
        local safe = dir:gsub('"', '\\"')
        os.execute('mkdir -p "' .. safe .. '"')
    end
    return dir
end

QuickSendOpenFolder = function()
    local dir = QuickSendEnsureFolder()
    local safe = dir:gsub('"', '\\"')
    os.execute('open "' .. safe .. '"')
end

QuickSendLabelFromFilename = function(filename)
    local label = tostring(filename or "")
    label = label:gsub("%.[Rr][Ff][Xx][Cc][Hh][Aa][Ii][Nn]$", "")
    label = label:gsub("^%s+", ""):gsub("%s+$", "")
    return label ~= "" and label or tostring(filename or "Quick Send")
end

QuickSendScan = function()
    local dir = QuickSendEnsureFolder()
    local presets = {}
    if not r.EnumerateFiles then return presets end
    local i = 0
    while true do
        local filename = r.EnumerateFiles(dir, i)
        if not filename then break end
        if tostring(filename):lower():match("%.rfxchain$") then
            presets[#presets + 1] = {
                label = QuickSendLabelFromFilename(filename),
                filename = filename,
                path = dir .. "/" .. filename,
            }
        end
        i = i + 1
    end
    table.sort(presets, function(a, b)
        return tostring(a.label):lower() < tostring(b.label):lower()
    end)
    return presets
end

QuickSendReadFile = function(path)
    local f = io.open(path, "rb")
    if not f then return nil, "Could not open FX chain file." end
    local data = f:read("*a")
    f:close()
    if not data or data == "" then return nil, "FX chain file is empty." end
    if data:sub(-1) ~= "\n" then data = data .. "\n" end
    return data
end

QuickSendFindFxChainClose = function(chunk)
    local search = 1
    local depth = 0
    local fx_depth = nil
    while search <= #chunk do
        local line_start = search
        local line_end = chunk:find("\n", search, true)
        local line
        if line_end then
            line = chunk:sub(line_start, line_end - 1)
            search = line_end + 1
        else
            line = chunk:sub(line_start)
            search = #chunk + 1
        end
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed == ">" then
            if fx_depth and depth == fx_depth then return line_start end
            depth = math.max(0, depth - 1)
        elseif trimmed:sub(1, 1) == "<" then
            depth = depth + 1
            if trimmed:match("^<FXCHAIN") then fx_depth = depth end
        end
    end
    return nil
end

QuickSendFindTrackClose = function(chunk)
    local search = 1
    local depth = 0
    while search <= #chunk do
        local line_start = search
        local line_end = chunk:find("\n", search, true)
        local line
        if line_end then
            line = chunk:sub(line_start, line_end - 1)
            search = line_end + 1
        else
            line = chunk:sub(line_start)
            search = #chunk + 1
        end
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed == ">" then
            if depth == 1 then return line_start end
            depth = math.max(0, depth - 1)
        elseif trimmed:sub(1, 1) == "<" then
            depth = depth + 1
        end
    end
    return nil
end

QuickSendInsertFxChain = function(track, chain_path)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false, "Destination track is invalid." end
    local chain, read_err = QuickSendReadFile(chain_path)
    if not chain then return false, read_err end
    local ok, chunk = r.GetTrackStateChunk(track, "", false)
    if not ok or type(chunk) ~= "string" or chunk == "" then
        return false, "Could not read destination track state."
    end
    local insert_pos = QuickSendFindFxChainClose(chunk)
    local new_chunk
    if insert_pos then
        new_chunk = chunk:sub(1, insert_pos - 1) .. chain .. chunk:sub(insert_pos)
    else
        local track_close_pos = QuickSendFindTrackClose(chunk)
        if not track_close_pos then return false, "Destination track has no writable state block." end
        local fxchain = "<FXCHAIN\nSHOW 0\n" .. chain .. "LASTSEL 0\nDOCKED 0\n>\n"
        new_chunk = chunk:sub(1, track_close_pos - 1) .. fxchain .. chunk:sub(track_close_pos)
    end
    local set_ok = r.SetTrackStateChunk(track, new_chunk, false)
    if not set_ok then return false, "Could not write destination track FX chain." end
    if InspMarkTrackFxDirty then InspMarkTrackFxDirty(track) end
    return true
end

QuickSendSanitizeFilename = function(name)
    local filename = tostring(name or "")
    filename = filename:gsub("[/\\:%*%?\"<>|]", "-")
    filename = filename:gsub("^%s+", ""):gsub("%s+$", "")
    filename = filename:gsub("%s+", " ")
    if filename == "" then filename = "Quick Send" end
    if not filename:lower():match("%.rfxchain$") then filename = filename .. ".RfxChain" end
    return filename
end

QuickSendExtractFxChain = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil, "Track is invalid." end
    local ok, chunk = r.GetTrackStateChunk(track, "", false)
    if not ok or type(chunk) ~= "string" or chunk == "" then return nil, "Could not read track FX chain." end

    local search = 1
    local depth = 0
    local fx_depth = nil
    local collect = false
    local out = {}
    while search <= #chunk do
        local line_end = chunk:find("\n", search, true)
        local line
        if line_end then
            line = chunk:sub(search, line_end - 1)
            search = line_end + 1
        else
            line = chunk:sub(search)
            search = #chunk + 1
        end

        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed == ">" then
            if fx_depth and depth == fx_depth then break end
            if collect then out[#out + 1] = line end
            depth = math.max(0, depth - 1)
        elseif trimmed:sub(1, 1) == "<" then
            depth = depth + 1
            if trimmed:match("^<FXCHAIN") then
                fx_depth = depth
                collect = true
            elseif collect then
                out[#out + 1] = line
            end
        elseif collect then
            if trimmed ~= "SHOW 0" and trimmed ~= "SHOW 1"
                and not trimmed:match("^LASTSEL%s+")
                and not trimmed:match("^DOCKED%s+") then
                out[#out + 1] = line
            end
        end
    end

    local chain = table.concat(out, "\n")
    chain = chain:gsub("^%s+", ""):gsub("%s+$", "")
    if chain == "" then return nil, "This track has no FX to save." end
    return chain .. "\n"
end

QuickSendSaveTrackFxChain = function(track)
    local chain, extract_err = QuickSendExtractFxChain(track)
    if not chain then
        if r.MB then r.MB(extract_err or "Could not save FX chain.", "Reflex: Quick Send", 0) end
        return false
    end

    local dir = QuickSendEnsureFolder()
    local _, track_name = r.GetTrackName(track)
    local default_name = QuickSendSanitizeFilename(track_name or "Quick Send")
    local ok, path
    if r.JS_Dialog_BrowseForSaveFile then
        ok, path = r.JS_Dialog_BrowseForSaveFile(
            "Save FX Chain as Quick Send",
            dir,
            default_name,
            "FX Chain (*.RfxChain)\0*.RfxChain\0All files (*.*)\0*.*\0")
    elseif r.GetUserFileNameForRead then
        ok, path = r.GetUserFileNameForRead(dir .. "/" .. default_name, "Save FX Chain as Quick Send", ".RfxChain")
    else
        if r.MB then r.MB("No file save dialog API is available.", "Reflex: Quick Send", 0) end
        return false
    end
    if not ok or not path or path == "" then return false end
    if not path:lower():match("%.rfxchain$") then path = path .. ".RfxChain" end

    local f = io.open(path, "wb")
    if not f then
        if r.MB then r.MB("Could not write FX chain file.", "Reflex: Quick Send", 0) end
        return false
    end
    f:write(chain)
    f:close()
    return true
end

-- Returns the color to inherit for a newly-created send-destination track.
-- Rule: inherit from source's parent folder; fall back to source's own color if top-level.
GetInheritedSendColor = function(source)
    if not source or not r.ValidatePtr(source, "MediaTrack*") then return 0 end
    local parent = r.GetParentTrack(source)
    if parent and r.ValidatePtr(parent, "MediaTrack*") then
        local c = r.GetTrackColor(parent)
        if c ~= 0 then return c end
    end
    return r.GetTrackColor(source) or 0
end

-- Build set of tracks that `source` already sends to (destination ptrs → send index).
-- Used for reverse-order walk-past and for sibling-return detection.
GetSourceSendDests = function(source)
    local dests = {}
    if not source or not r.ValidatePtr(source, "MediaTrack*") then return dests end
    if not r.BR_GetMediaTrackSendInfo_Track then return dests end
    local num = r.GetTrackNumSends(source, 0)
    for si = 0, num - 1 do
        local d = r.BR_GetMediaTrackSendInfo_Track(source, 0, si, 1)
        if d and r.ValidatePtr(d, "MediaTrack*") then dests[d] = si end
    end
    return dests
end

TrackNameStartsReturns = function(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    local _, name = r.GetTrackName(track)
    return name ~= nil and name:sub(1, 7) == "Returns"
end

IsConformingReturnsFolderForSource = function(source, folder)
    if not source or not r.ValidatePtr(source, "MediaTrack*") then return false end
    if not folder or not r.ValidatePtr(folder, "MediaTrack*") then return false end
    if math.floor(r.GetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH")) ~= 1 then return false end
    if r.GetParentTrack(folder) ~= r.GetParentTrack(source) then return false end
    if r.GetTrackDepth(folder) ~= r.GetTrackDepth(source) then return false end
    return TrackNameStartsReturns(folder)
end

-- Decide conform action for a new send from `source`.
-- Returns one of:
--   "rule1"  (nil, nil)                          — no existing local sends → normal placement
--   "rule2"  (loose_returns, loose_range)        — loose sibling returns exist → wrap in Returns folder
--                                                  loose_returns = sorted list of dest tracks
--                                                  loose_range   = {start_idx, end_idx} (0-based, contiguous)
--   "rule3"  (existing_returns_folder, nil)      — sibling "Returns*" folder already contains a send dest
--                                                  place new return as last child
-- Falls back to "rule1" if any structural condition is unsafe (loose return is a folder,
-- loose siblings non-contiguous, etc.).
DetermineConformTarget = function(source)
    if not source or not r.ValidatePtr(source, "MediaTrack*") then return "rule1" end
    if not r.BR_GetMediaTrackSendInfo_Track then return "rule1" end

    local src_parent = r.GetParentTrack(source)  -- may be nil (top-level)
    local src_depth = r.GetTrackDepth(source)

    local dests = GetSourceSendDests(source)

    -- Classify each existing dest:
    --   loose_sibling   = GetParentTrack(dest) == src_parent AND depth matches (direct sibling of source)
    --   in_returns_sib  = GetParentTrack(dest) is a folder whose parent == src_parent AND folder name starts with "Returns"
    local loose_returns = {}
    local returns_folder = nil  -- first matching sibling "Returns*" folder we find
    for dest, _ in pairs(dests) do
        local d_parent = r.GetParentTrack(dest)
        if d_parent == src_parent and r.GetTrackDepth(dest) == src_depth then
            -- Direct sibling of source
            loose_returns[#loose_returns + 1] = dest
        elseif IsConformingReturnsFolderForSource(source, d_parent) then
            if not returns_folder then returns_folder = d_parent end
        end
    end

    -- Rule 3 wins when both conditions apply (user has explicit Returns folder).
    if returns_folder then
        return "rule3", returns_folder, nil
    end

    if #loose_returns == 0 then return "rule1" end

    -- Rule 2 preconditions:
    -- (a) None of the loose returns may be folders (Q2 answered: skip if any has children).
    for _, d in ipairs(loose_returns) do
        if r.GetMediaTrackInfo_Value(d, "I_FOLDERDEPTH") == 1 then return "rule1" end
    end

    -- (b) Sort loose returns by track index; require contiguous range (no unrelated tracks interleaved).
    table.sort(loose_returns, function(a, b)
        return r.GetMediaTrackInfo_Value(a, "IP_TRACKNUMBER") < r.GetMediaTrackInfo_Value(b, "IP_TRACKNUMBER")
    end)
    local first_idx = math.floor(r.GetMediaTrackInfo_Value(loose_returns[1], "IP_TRACKNUMBER")) - 1
    local last_idx  = math.floor(r.GetMediaTrackInfo_Value(loose_returns[#loose_returns], "IP_TRACKNUMBER")) - 1
    if last_idx - first_idx + 1 ~= #loose_returns then return "rule1" end

    return "rule2", loose_returns, { first_idx, last_idx }
end

-- Insert a new send-destination track. If target_folder is provided, the new track
-- is placed inside that folder (as last child). Otherwise it's placed after `track`
-- (skipping folder children and prior send destinations).
-- Named "Return N". Creates stereo audio send (MIDI disabled). Inherits parent color.
-- When opt_conform_sends is true and target_folder is nil, applies conform rules:
--   Rule 1: no existing local sends → normal placement
--   Rule 2: loose sibling returns exist → wrap them in a new "Returns" folder
--   Rule 3: sibling "Returns*" folder exists → place inside it
RoutingAddSendTrack = function(track, send_mode, target_folder, opts)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    opts = opts or {}
    send_mode = send_mode or 0  -- 0=Post-Fader/Post-Pan, 1=Pre-Fader/Post-FX, 3=Pre-Fader/Pre-FX
    if target_folder and not IsConformingReturnsFolderForSource(track, target_folder) then
        target_folder = nil
    end

    -- Conform pre-processing. Only runs when no explicit target_folder was passed in
    -- (routing panel / per-group add buttons already pass target_folder and should bypass).
    if opt_conform_sends and not target_folder then
        local rule, a, b = DetermineConformTarget(track)
        if rule == "rule3" then
            -- Reuse existing Returns folder as target; fall through to target_folder path below.
            target_folder = a
        elseif rule == "rule2" then
            -- Build Returns folder in place, then add new return inside it.
            -- `a` = loose_returns list (sorted), `b` = {first_idx, last_idx} (0-based, inclusive).
            local loose, range = a, b
            local range_start, range_end = range[1], range[2]
            local last_existing = loose[#loose]
            local last_fd_orig = math.floor(r.GetMediaTrackInfo_Value(last_existing, "I_FOLDERDEPTH"))
            local inherit_col = GetInheritedSendColor(track)

            r.Undo_BeginBlock()
            r.PreventUIRefresh(1)

            -- Strip closures from the last existing loose return; new return inside Returns
            -- will close the Returns folder + inherit any outer closures last_existing was carrying.
            r.SetMediaTrackInfo_Value(last_existing, "I_FOLDERDEPTH", 0)

            -- Insert Returns folder header AT range_start. This shifts all loose returns down by 1
            -- and, because folder membership is position+delta based, reclassifies them as children.
            r.InsertTrackAtIndex(range_start, true)
            local folder = r.GetTrack(0, range_start)
            if folder then
                r.GetSetMediaTrackInfo_String(folder, "P_NAME", "Returns", true)
                r.SetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH", 1)
                if inherit_col ~= 0 then r.SetMediaTrackInfo_Value(folder, "I_CUSTOMCOLOR", inherit_col | 0x1000000) end
            end

            -- Insert new return as last child of Returns folder at range_end + 2
            -- (range_end shifted by 1 due to header insert, plus 1 to go after it).
            local new_insert_idx = range_end + 2
            r.InsertTrackAtIndex(new_insert_idx, true)
            local new_track = r.GetTrack(0, new_insert_idx)
            local created_si = -1
            local chain_ok, chain_err
            if new_track then
                -- Close Returns folder + carry any outer closures the old last_existing held.
                -- last_fd_orig was e.g. -1 if last_existing closed outer parent; new_track takes over.
                local new_depth = last_fd_orig - 1
                r.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", new_depth)
                local send_num = r.GetTrackNumSends(track, 0) + 1
                r.GetSetMediaTrackInfo_String(new_track, "P_NAME", opts.name or ("Return " .. send_num), true)
                if inherit_col ~= 0 then r.SetMediaTrackInfo_Value(new_track, "I_CUSTOMCOLOR", inherit_col | 0x1000000) end
                local si = r.CreateTrackSend(track, new_track)
                if si >= 0 then
                    r.SetTrackSendInfo_Value(track, 0, si, "I_MIDIFLAGS", 31)
                    if send_mode ~= 0 then r.SetTrackSendInfo_Value(track, 0, si, "I_SENDMODE", send_mode) end
                    created_si = si
                end
                if opts.fx_chain_path then
                    chain_ok, chain_err = QuickSendInsertFxChain(new_track, opts.fx_chain_path)
                end
            end

            r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
            if created_si >= 0 then SendEnvSetVisible(track, 0, created_si, 0, true) end
            r.Undo_EndBlock(opts.undo_label or "Reflex: Add send track (conform: wrap Returns)", -1)
            return { track = new_track, send_idx = created_si, fx_chain_ok = chain_ok, fx_chain_err = chain_err }
        end
        -- rule1: fall through to normal placement below.
    end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    local insert_idx, new_depth

    if target_folder and r.ValidatePtr(target_folder, "MediaTrack*")
       and r.GetMediaTrackInfo_Value(target_folder, "I_FOLDERDEPTH") == 1 then
        -- Insert as last child of target folder
        local folder_idx = math.floor(r.GetMediaTrackInfo_Value(target_folder, "IP_TRACKNUMBER")) - 1
        local nt = r.CountTracks(0)
        local depth = 1
        local last_child_idx = folder_idx
        local last_child_depth_before = 1
        for ti = folder_idx + 1, nt - 1 do
            local t = r.GetTrack(0, ti)
            last_child_depth_before = depth
            depth = depth + math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH"))
            last_child_idx = ti
            if depth <= 0 then break end
        end
        -- last_child_idx is the track that closes the folder (or last track in subtree)
        -- The closing track may close nested child folders, the target folder,
        -- and outer parent folders. Keep nested closures on the old last child;
        -- move the target/outer closures to the new last child.
        local last_t = r.GetTrack(0, last_child_idx)
        local last_fd = math.floor(r.GetMediaTrackInfo_Value(last_t, "I_FOLDERDEPTH"))
        if last_fd < 0 then
            local old_new_depth = 1 - last_child_depth_before
            local new_final_depth = last_child_depth_before + last_fd
            r.SetMediaTrackInfo_Value(last_t, "I_FOLDERDEPTH", old_new_depth)
            insert_idx = last_child_idx + 1
            new_depth = new_final_depth - 1
        else
            -- Folder has no closing track (shouldn't happen, but handle gracefully)
            insert_idx = last_child_idx + 1
            new_depth = -1
        end
    else
        -- Normal behavior: insert after source track (skipping subtree if folder, then past prior sends)
        local src_idx = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) - 1
        local src_depth = math.floor(r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH"))
        insert_idx = src_idx + 1
        new_depth = 0

        if src_depth == 1 then
            local depth = 1
            local nt = r.CountTracks(0)
            local last_idx = src_idx
            for ti = src_idx + 1, nt - 1 do
                local t = r.GetTrack(0, ti)
                depth = depth + math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH"))
                last_idx = ti
                if depth <= 0 then break end
            end
            insert_idx = last_idx + 1
            if depth < 0 then
                local last_t = r.GetTrack(0, last_idx)
                local last_d = math.floor(r.GetMediaTrackInfo_Value(last_t, "I_FOLDERDEPTH"))
                local extra = -depth
                r.SetMediaTrackInfo_Value(last_t, "I_FOLDERDEPTH", last_d + extra)
                new_depth = -extra
            end
        elseif src_depth < 0 then
            r.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 0)
            new_depth = src_depth
        end

        -- Walk past any existing send destinations of source that sit contiguously at insert_idx.
        -- Fixes reverse-order bug: without this, each new send inserts at the same position and
        -- pushes the prior one down, producing Return 3, 2, 1... rather than 1, 2, 3.
        local dests = GetSourceSendDests(track)
        local nt = r.CountTracks(0)
        local walked_any = false
        while insert_idx < nt do
            local t = r.GetTrack(0, insert_idx)
            if not t or not dests[t] then break end
            walked_any = true
            insert_idx = insert_idx + 1
        end
        if walked_any then
            -- The track immediately before our new insert_idx (i.e. the previously-last sibling send)
            -- may be carrying folder closures that were transferred to it on a prior call. Those closures
            -- must move to our new track so it becomes the new last sibling/closer.
            local prev_t = r.GetTrack(0, insert_idx - 1)
            if prev_t then
                local prev_fd = math.floor(r.GetMediaTrackInfo_Value(prev_t, "I_FOLDERDEPTH"))
                if prev_fd < 0 then
                    -- prev_fd already contains the closure count (possibly augmented by earlier transfers).
                    -- Pull it all onto the new track; previous becomes a normal mid-list track.
                    r.SetMediaTrackInfo_Value(prev_t, "I_FOLDERDEPTH", 0)
                    new_depth = prev_fd + (new_depth or 0)  -- accumulate onto whatever new_depth had
                end
            end
        end
    end

    r.InsertTrackAtIndex(insert_idx, true)
    local new_track = r.GetTrack(0, insert_idx)
    local created_si = -1
    local chain_ok, chain_err
    if new_track then
        if new_depth ~= 0 then
            r.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", new_depth)
        end
        local send_num = r.GetTrackNumSends(track, 0) + 1
        r.GetSetMediaTrackInfo_String(new_track, "P_NAME", opts.name or ("Return " .. send_num), true)
        local inherit_col = GetInheritedSendColor(track)
        if inherit_col ~= 0 then r.SetMediaTrackInfo_Value(new_track, "I_CUSTOMCOLOR", inherit_col | 0x1000000) end
        local si = r.CreateTrackSend(track, new_track)
        if si >= 0 then
            r.SetTrackSendInfo_Value(track, 0, si, "I_MIDIFLAGS", 31)
            if send_mode ~= 0 then r.SetTrackSendInfo_Value(track, 0, si, "I_SENDMODE", send_mode) end
            created_si = si
        end
        if opts.fx_chain_path then
            chain_ok, chain_err = QuickSendInsertFxChain(new_track, opts.fx_chain_path)
        end
    end
    r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
    -- Envelope visibility must be set outside PreventUIRefresh block, otherwise
    -- the BR_EnvFree commit lands in stale state and the envelope stays hidden.
    if created_si >= 0 then
        SendEnvSetVisible(track, 0, created_si, 0, true)
    end
    r.Undo_EndBlock(opts.undo_label or "Reflex: Add send track", -1)
    return { track = new_track, send_idx = created_si, fx_chain_ok = chain_ok, fx_chain_err = chain_err }
end

QuickSendAdd = function(track, preset, send_mode, target_folder)
    if not preset or not preset.path then return end
    local result = RoutingAddSendTrack(track, send_mode or 0, target_folder, {
        name = preset.label,
        fx_chain_path = preset.path,
        undo_label = "Reflex: Add quick send",
    })
    if result and result.fx_chain_ok == false and result.fx_chain_err and r.MB then
        r.MB(result.fx_chain_err, "Reflex: Quick Send", 0)
    end
    return result
end

QuickSendMenuItems = function(track, target_folder)
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, C.text_muted, "Quick sends:")
    r.ImGui_Spacing(ctx)
    local presets = QuickSendScan()
    if #presets == 0 then
        r.ImGui_TextColored(ctx, C.text_muted, "No .RfxChain files")
    else
        for _, preset in ipairs(presets) do
            if r.ImGui_MenuItem(ctx, preset.label) then
                QuickSendAdd(track, preset, 0, target_folder)
            end
        end
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Save FX Chain as Quick Send...") then
        QuickSendSaveTrackFxChain(track)
    end
    if r.ImGui_MenuItem(ctx, "Open Quick Sends Folder") then
        QuickSendOpenFolder()
    end
end

-- Right-click popup for send mode selection on + buttons.
-- Call after any + button. popup_id must be unique per button instance.
-- target_folder: optional folder track to place new track inside.
AddSendModePopup = function(popup_id, track, target_folder)
    PushPopupStyle()
    if r.ImGui_BeginPopup(ctx, popup_id) then
        r.ImGui_TextColored(ctx, C.text_muted, "Send to new track:")
        r.ImGui_Spacing(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), C.fx_ctrl_hover)
        if r.ImGui_MenuItem(ctx, "Post-Fader (Post-Pan)") then RoutingAddSendTrack(track, 0, target_folder) end
        if r.ImGui_MenuItem(ctx, "Pre-Fader (Post-FX)") then RoutingAddSendTrack(track, 1, target_folder) end
        if r.ImGui_MenuItem(ctx, "Pre-Fader (Pre-FX)") then RoutingAddSendTrack(track, 3, target_folder) end
        if QuickSendMenuItems then QuickSendMenuItems(track, target_folder) end
        r.ImGui_PopStyleColor(ctx, 2)
        r.ImGui_EndPopup(ctx)
    end
    PopPopupStyle()
end

end

return ReflexInstallSendCreateCore
