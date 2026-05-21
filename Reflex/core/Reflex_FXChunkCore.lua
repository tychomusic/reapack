-- @noindex
-- Reflex FX chunk core module.
-- Installs REAPER track-chunk parsing and FX block splice helpers.

ReflexInstallFXChunkCore = function(deps)
    local r = deps.r

    -- Split a chunk into a plain array of lines. Strips trailing CR.
    -- Preserves empty lines. Does NOT drop a trailing line without newline.
    FxChunkSplitLines = function(text)
        local lines = {}
        local i = 1
        local n = #text
        while i <= n do
            local nl = text:find("\n", i, true)
            if nl then
                local line = text:sub(i, nl - 1)
                if #line > 0 and line:sub(-1) == "\r" then line = line:sub(1, -2) end
                lines[#lines + 1] = line
                i = nl + 1
            else
                lines[#lines + 1] = text:sub(i)
                break
            end
        end
        return lines
    end

    -- Join lines back into a chunk (with LF between).
    FxChunkJoinLines = function(lines)
        return table.concat(lines, "\n")
    end

    -- Classify a chunk line as block-open, block-close, or plain.
    -- Block-open: starts (after leading whitespace) with '<'.
    -- Block-close: after trim equals '>'.
    -- Plain: everything else (key-value lines, base64 data, etc.).
    FxChunkLineKind = function(line)
        local t = line:gsub("^%s+", "")
        if t:sub(1, 1) == "<" then return "open" end
        local t2 = t:gsub("%s+$", "")
        if t2 == ">" then return "close" end
        return "plain"
    end

    -- Find the FXCHAIN block in a parsed-line chunk.
    -- Returns open_ln, close_ln, content_depth; all nil if no FXCHAIN.
    FxChunkFindFxchain = function(lines)
        local abs_depth = 0
        local open_ln, close_ln, content_depth
        for ln = 1, #lines do
            local line = lines[ln]
            local t = line:gsub("^%s+", "")
            local kind = FxChunkLineKind(line)
            if not open_ln and kind == "open" and t:sub(1, 8) == "<FXCHAIN" then
                open_ln = ln
                content_depth = abs_depth + 1
                abs_depth = abs_depth + 1
            elseif kind == "open" then
                abs_depth = abs_depth + 1
            elseif kind == "close" then
                abs_depth = abs_depth - 1
                if open_ln and abs_depth == content_depth - 1 then
                    close_ln = ln
                    break
                end
            end
        end
        return open_ln, close_ln, content_depth
    end

    -- Walk FXCHAIN content and return per-FX line ranges.
    -- Returns { start_ln, end_ln } inclusive for each top-level FX.
    FxChunkFxRanges = function(lines, open_ln, close_ln, content_depth)
        local ranges = {}
        if not open_ln or not close_ln then return ranges end
        local abs_depth = content_depth
        local current_start = nil
        for ln = open_ln + 1, close_ln - 1 do
            local line = lines[ln]
            local t = line:gsub("^%s+", "")
            local kind = FxChunkLineKind(line)
            -- Check BYPASS before depth change. BYPASS is a plain line at content_depth.
            if kind == "plain" and abs_depth == content_depth then
                local is_bypass = (t:sub(1, 7) == "BYPASS " or t == "BYPASS")
                if is_bypass then
                    if current_start then
                        ranges[#ranges + 1] = { current_start, ln - 1 }
                    end
                    current_start = ln
                end
            end
            if kind == "open" then abs_depth = abs_depth + 1
            elseif kind == "close" then abs_depth = abs_depth - 1 end
        end
        if current_start then
            ranges[#ranges + 1] = { current_start, close_ln - 1 }
        end
        return ranges
    end

    -- Extract the chunk text for FX at 0-based index fi from a track chunk.
    -- Returns nil if FXCHAIN is absent or fi is out of range.
    FxChunkExtractFxBlock = function(track_chunk_text, fi)
        local lines = FxChunkSplitLines(track_chunk_text)
        local open_ln, close_ln, content_depth = FxChunkFindFxchain(lines)
        if not open_ln or not close_ln then return nil end
        local ranges = FxChunkFxRanges(lines, open_ln, close_ln, content_depth)
        local rng = ranges[fi + 1]
        if not rng then return nil end
        local out = {}
        for ln = rng[1], rng[2] do out[#out + 1] = lines[ln] end
        return table.concat(out, "\n")
    end

    -- Splice FX block texts into a track chunk's FXCHAIN at 0-based insert_at_fi.
    -- If the target track has no FXCHAIN, creates one. Returns new track chunk text.
    FxChunkSpliceFxBlocks = function(track_chunk_text, insert_at_fi, blocks)
        if not blocks or #blocks == 0 then return track_chunk_text end
        local lines = FxChunkSplitLines(track_chunk_text)
        local open_ln, close_ln, content_depth = FxChunkFindFxchain(lines)

        local insert_text = table.concat(blocks, "\n")
        local insert_lines = FxChunkSplitLines(insert_text)

        if not open_ln or not close_ln then
            -- No FXCHAIN present. Build one at track close.
            local track_close_ln
            for ln = #lines, 1, -1 do
                if FxChunkLineKind(lines[ln]) == "close" then
                    track_close_ln = ln
                    break
                end
            end
            if not track_close_ln then
                return track_chunk_text
            end
            local new_lines = {}
            for ln = 1, track_close_ln - 1 do new_lines[#new_lines + 1] = lines[ln] end
            new_lines[#new_lines + 1] = "  <FXCHAIN"
            new_lines[#new_lines + 1] = "    SHOW 0"
            new_lines[#new_lines + 1] = "    LASTSEL 0"
            new_lines[#new_lines + 1] = "    DOCKED 0"
            for _, il in ipairs(insert_lines) do new_lines[#new_lines + 1] = il end
            new_lines[#new_lines + 1] = "  >"
            for ln = track_close_ln, #lines do new_lines[#new_lines + 1] = lines[ln] end
            return table.concat(new_lines, "\n")
        end

        local ranges = FxChunkFxRanges(lines, open_ln, close_ln, content_depth)
        local insert_before_ln
        if insert_at_fi <= 0 then
            if #ranges > 0 then
                insert_before_ln = ranges[1][1]
            else
                insert_before_ln = close_ln
            end
        elseif insert_at_fi >= #ranges then
            insert_before_ln = close_ln
        else
            insert_before_ln = ranges[insert_at_fi + 1][1]
        end

        local new_lines = {}
        for ln = 1, insert_before_ln - 1 do new_lines[#new_lines + 1] = lines[ln] end
        for _, il in ipairs(insert_lines) do new_lines[#new_lines + 1] = il end
        for ln = insert_before_ln, #lines do new_lines[#new_lines + 1] = lines[ln] end
        return table.concat(new_lines, "\n")
    end

    -- Replace every FXID {guid} occurrence in a chunk fragment with a fresh GUID.
    -- SetTrackStateChunk preserves FXIDs verbatim; without regeneration, pasted
    -- FX inherit source GUIDs and break guid-keyed clipboard outlines, multi-select,
    -- and any other session state keyed by FXID.
    FxChunkRegenFxids = function(text)
        if not r.genGuid then return text end
        local out = text:gsub("FXID%s+%b{}", function()
            local ok, guid = pcall(r.genGuid, "")
            if ok and guid and guid ~= "" then
                return "FXID " .. guid
            end
            return "FXID {00000000-0000-0000-0000-000000000000}"
        end)
        return out
    end
end

return ReflexInstallFXChunkCore
