BuskingTools = BuskingTools or {}
BuskingTools.Util = BuskingTools.Util or {}

local Self = BuskingTools.Util

-- ============================================================================
-- Lua QoL extensions
-- ============================================================================
function table.extend(table1, table2, withKeys)
    if withKeys then
        for key, element in pairs(table2) do
            table1[key] = element
        end
    else
        for _, element in ipairs(table2) do
            table.insert(table1, element)
        end
    end
end

function table.range(from, to)
    local result = {}
    for i = from, to do
        table.insert(result, i)
    end
    return result
end

-- ============================================================================
-- Progress bar object
-- ============================================================================
function Self.StartProgress(title, totalSteps)
    local handle = StartProgress(title)
    SetProgressRange(handle, 1, totalSteps or 1)
    SetProgress(handle, 1)

    -- Ensure that progress bar is always handled properly
    BuskingTools.Core.RegisterCleanupHandler(function()
        StopProgress(handle)
    end)

    return {
        _handle = handle,
        _step = 1,
        Next = Self.NextStepProgress,
        Stop = Self.StopProgress,
    }
end

function Self.NextStepProgress(progress, title)
    if not progress._handle then
        ErrEcho("NextStepProgress could not update progress because it does not have a handle")
    else
        progress._step = progress._step + 1
        SetProgress(progress._handle, progress._step)
        SetProgressText(progress._handle, title)
    end
end

function Self.StopProgress(progress)
    if not progress._handle then
        ErrEcho("StopProgress could not update progress because it does not have a handle")
    else
        StopProgress(progress._handle)
    end
end

-- ============================================================================
-- Data extraction utilities
-- ============================================================================
function Self.ExtractPresetColor(preset)
    local preset = type(preset) == 'number' and DataPool().PresetPools[4][preset] or preset
    if not preset then
        return nil
    end

    local presetData = GetPresetData(preset, false, true)
    if not presetData or not presetData.by_fixtures then
        return nil
    end

    local firstFixtureData = nil
    for _, data in pairs(presetData.by_fixtures) do
        firstFixtureData = data
        break
    end

    if not firstFixtureData then
        return nil
    end

    local rVal, gVal, bVal = 0, 0, 0

    -- Recipe-based presets: attributes nested inside recipe.channelData
    if firstFixtureData.recipe and firstFixtureData.recipe[1] then
        for _, layer in ipairs(firstFixtureData.recipe) do
            if layer.channelData then
                for _, channel in ipairs(layer.channelData) do
                    if     channel.attribute == "ColorRGB_R" then rVal = channel.absolute or 0
                    elseif channel.attribute == "ColorRGB_G" then gVal = channel.absolute or 0
                    elseif channel.attribute == "ColorRGB_B" then bVal = channel.absolute or 0
                    end
                end
            end
        end
    -- Standard presets (Selective / Global / Universal)
    else
        if firstFixtureData.ColorRGB_R and firstFixtureData.ColorRGB_R[1] then
            rVal = firstFixtureData.ColorRGB_R[1].absolute or 0
        end
        if firstFixtureData.ColorRGB_G and firstFixtureData.ColorRGB_G[1] then
            gVal = firstFixtureData.ColorRGB_G[1].absolute or 0
        end
        if firstFixtureData.ColorRGB_B and firstFixtureData.ColorRGB_B[1] then
            bVal = firstFixtureData.ColorRGB_B[1].absolute or 0
        end
    end

    -- Convert percentage (0-100) to RGB integer (0-255)
    return {
        r = math.floor((rVal / 100) * 255 + 0.5),
        g = math.floor((gVal / 100) * 255 + 0.5),
        b = math.floor((bVal / 100) * 255 + 0.5),
    }
end

function Self.ExtractPresets(pool, presets, getter)
    local result = {}

    for _, preset in ipairs(presets) do
        local presetInfo = pool[preset]

        if not presetInfo then
            BuskingTools.Core.Warn(Fmt("Could not find preset %d (TODO: Which pool). It will be skipped.", preset))
            goto continue
        end

        local data = {
            id = preset,
            name = presetInfo.name,
        }

        if getter then
            table.extend(data, getter(presetInfo), true)
        end

        result[preset] = data

        ::continue::
    end

    return result
end


-- ============================================================================
-- Pool object generation utilities
-- ============================================================================
function Self.StoreAndLabel(pattern, label, properties, deleteOld)
    if deleteOld then
        CmdIndirectWait(Fmt("Delete %s /NoConfirmation", pattern))
    end
    Cmd(Fmt("Store %s /Overwrite", pattern))
    Cmd(Fmt("Label %s '%s'", pattern, label))
    
    if properties then
        Self.SetProperties(pattern, properties)
    end
end

function Self.SetProperties(pattern, properties)
    for prop, value in pairs(properties) do
        if type(value) == "number" then
            Cmd(Fmt("Set %s '%s' %s", pattern, prop, value))
        else
            Cmd(Fmt("Set %s '%s' '%s'", pattern, prop, tostring(value)))
        end
    end
end

function Self.ImportImages(images, offset)
    local offset = offset or 0
    local result = {}

    for i, image in ipairs(images) do
        local imageId = (image.offset or (i-1)) + offset

        Cmd(Fmt("Import Image 3.%d /File '%s'", imageId, image.path))
        Cmd(Fmt("Label Image 3.%d '%s'", imageId, image.label))

        result[image.id] = Fmt("3.%d", imageId)
    end

    return result
end

function Self.BuildAppearance(id, label, image, fgColor, bgColor)
    Self.StoreAndLabel(Fmt("Appearance %d", id), label)
    Cmd(Fmt("Assign Image %s At Appearance %d", image, id))

    if fgColor then
        Cmd(Fmt(
            "Set Appearance %d ImageR %d ImageG %d ImageB %d ImageAlpha %d",
            id, fgColor.r or 0, fgColor.g or 0, fgColor.b or 0, fgColor.a or 255
        ))
    end

    if bgColor then
        Cmd(Fmt(
            "Set Appearance %d BackR %d BackG %d BackB %d BackAlpha %d",
            id, bgColor.r or 0, bgColor.g or 0, bgColor.b or 0, bgColor.a or 255
        ))
    end
end

function Self.BuildMacro(id, label, commandList)
    local commands = {}

    for _, command in ipairs(commandList) do
        if type(command) == 'table' then
            table.extend(commands, command)
        else
            table.insert(commands, command)
        end
    end

    Self.StoreAndLabel(Fmt("Macro %d", id), label)

    for i, command in ipairs(commands) do
        if type(command) ~= 'string' then
            Panic("BuildMacro function only takes tables or strings.")
        end

        Cmd(Fmt("Insert Macro %d.%d", id, i))
        Cmd(Fmt("Set Macro %d.%d Property 'Command' \"%s\"", id, i, command))
    end
end

function Self.BuildMacroGroup(offset, options, buttons)
    for i, button in ipairs(buttons) do
        local id = offset + i - 1

        Self.BuildMacro(id, button.label or "BT Button", {
            Fmt("Assign Appearance %d At Macro %d Thru %d", options.offAppearance, offset, offset + #buttons - 1),
            Fmt("Assign Appearance %d At Macro %d", options.onAppearance, id),
            button.commands
        })
    end
end


return function() end, BuskingTools.Core.Cleanup