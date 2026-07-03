BuskingTools = BuskingTools or {}
BuskingTools.Util = BuskingTools.Util or {}

local Self = BuskingTools.Util

-- ============================================================================
-- Lua QoL extensions
-- ============================================================================
function table.extend(table1, table2)
    for _, element in ipairs(table2) do
        table.insert(table1, element)
    end
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

-- ============================================================================
-- Pool object generation utilities
-- ============================================================================
function Self.StoreAndLabel(pattern, label, deleteOld)
    if deleteOld then
        CmdIndirectWait(Fmt("Delete %s /NoConfirmation", pattern))
    end
    Cmd(Fmt("Store %s /Overwrite", pattern))
    Cmd(Fmt("Label %s '%s'", label))
end

function Self.ImportImages(images, offset)
    local offset = offset or 0
    local result = {}

    for i, image in ipairs(images) do
        local imageId = (image.offset or (i-1)) + offset

        Cmd(Fmt("Import Image 3.%d /File '%s'", imageId, image.path))
        Cmd(Fmt("Label Image 3.%d '%s'", imageId, image.label))

        result[image.id] = imageId
    end

    return result
end

function Self.BuildMacro(id, label, ...)
    local commands = {}

    for _, command in ipairs(arg) do
        if type(command) == 'table' then
            table.extend(commands, command)
        else
            table.insert(commands, command)
        end
    end

    Self.StoreAndLabel(Fmt("Macro %d", id), label)

    for i, command in ipairs(commands) do
        if type(command) ~= 'string' then
            Panic("BuildMacro function only takes tables or strings")
        end

        Cmd(Fmt("Insert Macro %d.%d", id, i))
        Cmd(Fmt("Set Macro %d.%d Property 'Command' \"%s\"", id, i, command))
    end
end


return function() end, BuskingTools.Core.Cleanup