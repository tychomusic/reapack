-- @noindex
-- Reflex Remote core module.
-- Installs Remote persistence, undo/redo, and button/page mutation helpers.

ReflexInstallRemoteCore = function(deps)
    local r = deps.r
    local getButtons = deps.get_buttons
    local setButtons = deps.set_buttons
    local getUndoStack = deps.get_undo_stack
    local getRedoStack = deps.get_redo_stack
    local setRedoStack = deps.set_redo_stack
    local getUndoMax = deps.get_undo_max
    local getDefaultHeight = deps.get_default_height
    local getCols = deps.get_cols
    local getCurrentPage = deps.get_current_page
    local setCurrentPage = deps.set_current_page
    local getPages = deps.get_pages
    local setPages = deps.set_pages

    local buttonsPath = function()
        return r.GetResourcePath() .. "/Scripts/Tycho/Reflex/remote_buttons.txt"
    end

    local pagesPath = function()
        return r.GetResourcePath() .. "/Scripts/Tycho/Reflex/remote_pages.txt"
    end

    local blankButton = function(page, height)
        return {
            action = 0,
            name = "",
            width = 1,
            height = height or getDefaultHeight(),
            icon = "",
            color = 0,
            plugin = "",
            page = page or getCurrentPage(),
        }
    end

    local cloneButton = function(btn)
        return {
            action = btn.action,
            name = btn.name,
            width = btn.width,
            height = btn.height or 1,
            icon = btn.icon or "",
            color = btn.color or 0,
            plugin = btn.plugin or "",
            page = btn.page or 1,
        }
    end

    local cloneButtons = function(buttons)
        local state = {}
        for _, btn in ipairs(buttons) do
            state[#state + 1] = cloneButton(btn)
        end
        return state
    end

    local setDefaultButtons = function()
        local buttons = {}
        for i = 1, 4 do
            buttons[i] = blankButton(getCurrentPage(), getDefaultHeight())
        end
        setButtons(buttons)
    end

    RemoteLoadButtons = function()
        local f = io.open(buttonsPath(), "r")
        setButtons({})
        if not f then
            setDefaultButtons()
            return
        end
        local data = f:read("*a")
        f:close()
        if data == "" then
            setDefaultButtons()
            return
        end
        local buttons = {}
        for entry in data:gmatch("([^\n]+)") do
            local fields = {}
            for field in (entry .. "|"):gmatch("([^|]*)|") do fields[#fields + 1] = field end
            if #fields >= 3 then
                local height = tonumber(fields[4]) or 1
                if height < 1 then height = 1 end
                if height > 3 then height = 3 end
                buttons[#buttons + 1] = {
                    action = tonumber(fields[1]) or 0,
                    name = fields[2] or "",
                    width = tonumber(fields[3]) or 1,
                    height = height,
                    icon = fields[5] or "",
                    color = tonumber(fields[6]) or 0,
                    plugin = fields[7] or "",
                    page = tonumber(fields[8]) or 1,
                }
            end
        end
        if #buttons == 0 then
            setDefaultButtons()
        else
            setButtons(buttons)
        end
    end

    RemoteSaveButtons = function()
        local f = io.open(buttonsPath(), "w")
        if not f then return end
        for _, btn in ipairs(getButtons()) do
            f:write(tostring(btn.action) .. "|" .. (btn.name or "") .. "|" .. tostring(btn.width) .. "|"
                .. tostring(btn.height or 1) .. "|" .. (btn.icon or "") .. "|" .. tostring(btn.color or 0)
                .. "|" .. (btn.plugin or "") .. "|" .. tostring(btn.page or 1) .. "\n")
        end
        f:close()
    end

    RemotePushUndo = function()
        local undo_stack = getUndoStack()
        undo_stack[#undo_stack + 1] = cloneButtons(getButtons())
        if #undo_stack > getUndoMax() then table.remove(undo_stack, 1) end
        setRedoStack({})
    end

    RemoteUndo = function()
        local undo_stack = getUndoStack()
        if #undo_stack == 0 then return end
        local redo_stack = getRedoStack()
        redo_stack[#redo_stack + 1] = cloneButtons(getButtons())
        setButtons(undo_stack[#undo_stack])
        table.remove(undo_stack, #undo_stack)
        RemoteSaveButtons()
    end

    RemoteRedo = function()
        local redo_stack = getRedoStack()
        if #redo_stack == 0 then return end
        local undo_stack = getUndoStack()
        undo_stack[#undo_stack + 1] = cloneButtons(getButtons())
        setButtons(redo_stack[#redo_stack])
        table.remove(redo_stack, #redo_stack)
        RemoteSaveButtons()
    end

    -- Insert button data at position, consuming trailing blank cells instead of pushing.
    -- Returns the number of cells actually inserted (not consumed).
    RemoteInsertAt = function(pos, button_data_list)
        local buttons = getButtons()
        for i, bd in ipairs(button_data_list) do
            local ti = pos + i - 1
            if ti <= #buttons and buttons[ti].action == 0 then
                -- Consume blank cell: overwrite it.
                buttons[ti] = {
                    action = bd.action,
                    name = bd.name,
                    width = bd.width,
                    height = buttons[ti].height or getDefaultHeight(),
                    icon = bd.icon or "",
                    color = bd.color or 0,
                    plugin = bd.plugin or "",
                    page = bd.page or 1,
                }
            else
                -- No blank to consume: insert.
                table.insert(buttons, ti, {
                    action = bd.action,
                    name = bd.name,
                    width = bd.width,
                    height = (ti <= #buttons and buttons[ti].height) or getDefaultHeight(),
                    icon = bd.icon or "",
                    color = bd.color or 0,
                    plugin = bd.plugin or "",
                    page = bd.page or 1,
                })
            end
        end
    end

    RemoteAddButton = function()
        RemotePushUndo()
        local buttons = getButtons()
        buttons[#buttons + 1] = blankButton(getCurrentPage(), getDefaultHeight())
        RemoteSaveButtons()
    end

    RemoteAddRow = function()
        RemotePushUndo()
        local buttons = getButtons()
        for i = 1, getCols() do
            buttons[#buttons + 1] = blankButton(getCurrentPage(), getDefaultHeight())
        end
        RemoteSaveButtons()
    end

    RemoteRemoveButton = function(idx)
        local buttons = getButtons()
        if #buttons <= 0 then return end
        RemotePushUndo()
        table.remove(buttons, idx)
        RemoteSaveButtons()
    end

    RemoteSetWidth = function(idx, w)
        local buttons = getButtons()
        if buttons[idx] then
            RemotePushUndo()
            buttons[idx].width = w
            RemoteSaveButtons()
        end
    end

    RemoteSetHeight = function(idx, h)
        local buttons = getButtons()
        if buttons[idx] then
            RemotePushUndo()
            buttons[idx].height = h
            RemoteSaveButtons()
        end
    end

    RemoteLoadPages = function()
        local f = io.open(pagesPath(), "r")
        if not f then
            setPages({ { name = "Main", color = 0, height = 1 } })
            return
        end
        local data = f:read("*a")
        f:close()
        local pages = {}
        for line in data:gmatch("([^\n]+)") do
            local parts = {}
            for p in (line .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = p end
            pages[#pages + 1] = {
                name = parts[1] or ("Page " .. #pages + 1),
                color = tonumber(parts[2]) or 0,
                height = tonumber(parts[3]) or 1,
            }
        end
        if #pages == 0 then
            pages = { { name = "Main", color = 0, height = 1 } }
        end
        setPages(pages)
    end

    RemoteSavePages = function()
        local f = io.open(pagesPath(), "w")
        if not f then return end
        for _, pg in ipairs(getPages()) do
            f:write((pg.name or "Page") .. "|" .. tostring(pg.color or 0) .. "|" .. tostring(pg.height or 1) .. "\n")
        end
        f:close()
    end

    RemoteAddPage = function()
        local pages = getPages()
        local idx = #pages + 1
        pages[idx] = { name = "Page " .. idx, color = 0, height = 1 }
        RemoteSavePages()
        setCurrentPage(idx)
        -- Add starter buttons on new page.
        RemotePushUndo()
        local buttons = getButtons()
        for i = 1, getCols() do
            buttons[#buttons + 1] = blankButton(idx, getDefaultHeight())
        end
        RemoteSaveButtons()
    end

    RemoteDeletePage = function(page_idx)
        local pages = getPages()
        if #pages <= 1 then return end
        -- Remove buttons on this page.
        RemotePushUndo()
        local buttons = getButtons()
        for i = #buttons, 1, -1 do
            if (buttons[i].page or 1) == page_idx then
                table.remove(buttons, i)
            end
        end
        -- Shift page numbers for buttons on higher pages.
        for _, btn in ipairs(buttons) do
            if (btn.page or 1) > page_idx then btn.page = btn.page - 1 end
        end
        table.remove(pages, page_idx)
        if getCurrentPage() > #pages then setCurrentPage(#pages) end
        RemoteSaveButtons()
        RemoteSavePages()
    end
end

return ReflexInstallRemoteCore
