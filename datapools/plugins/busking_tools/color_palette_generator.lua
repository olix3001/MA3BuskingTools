-- ============================================================================
-- Color Picker Generator for GrandMA3
-- ============================================================================
-- Generates a complete color picker system including sequences, macros,
-- layouts, and a settings panel for controlling fade time, MAtricks patterns,
-- and effect speed.

-- ============================================================================
-- Image Asset Constants
-- ============================================================================

local IMAGE_PATH_ON  = "busking_tools_on"
local IMAGE_PATH_OFF = "busking_tools_off"

-- TODO: Replace with dedicated button images when available
local BUTTON_IMAGE_PATH_ON  = "busking_tools_button_on"
local BUTTON_IMAGE_PATH_OFF = "busking_tools_button_off"

-- ============================================================================
-- Color FX Effect Types
-- ============================================================================

local EFFECTS = { "Even-Odd", "Gradient", "Flicker", "Chase" }

-- ============================================================================
-- MAtricks Pattern Names (for Settings layout row 2)
-- ============================================================================

local MATRICKS_PATTERNS = {
    "Left to Right",
    "Right to Left",
    "Inwards",
    "Outwards",
}

local MATRICKS_CONFIGS = {
    { wings = 1, phase = {0, 180} },
    { wings = 1, phase = {180, 0} },
    { wings = 2, phase = {0, 180} },
    { wings = 2, phase = {180, 0} },
}

-- ============================================================================
-- Layout Dimension Constants
-- ============================================================================

local LAYOUT_LABEL_WIDTH  = 120
local LAYOUT_LABEL_HEIGHT = 50
local LAYOUT_LABEL_FONT_SIZE = 18

local LAYOUT_PICKER_SIZE    = 50
local LAYOUT_PICKER_SPACING = 60
local LAYOUT_LEFT_MARGIN    = 140
local LAYOUT_FX_GAP         = 20
local LAYOUT_FX_GROUP_WIDTH = 250
local LAYOUT_ROW_HEIGHT     = 60
local LAYOUT_ROW_GAP        = 10

-- ============================================================================
-- Shared State
-- ============================================================================

local fxOnAppearance   = {}
local fxOffAppearance  = {}
local settingsOnAppearance  = nil
local settingsOffAppearance = nil
local masterMacrosOffset = nil
local progressHandle   = nil

-- ============================================================================
-- Utility Helpers
-- ============================================================================

local function fmt(...)
    return string.format(...)
end

local function updateProgress(step, text)
    SetProgress(progressHandle, step)
    SetProgressText(progressHandle, text)
end

local function deleteIfExists(cmdPattern)
    CmdIndirectWait(cmdPattern .. " /NoConfirmation")
end

local function storeAndLabel(pattern, label)
    deleteIfExists("Delete " .. pattern)
    Cmd("Store " .. pattern .. " /Overwrite")
    Cmd("Label " .. pattern .. " '" .. label .. "'")
end

local function setLayoutCellProps(layoutId, elementIndex, props)
    for prop, value in pairs(props) do
        if type(value) == "number" then
            Cmd(fmt("Set Layout %d.%d '%s' %s", layoutId, elementIndex, prop, value))
        else
            Cmd(fmt("Set Layout %d.%d '%s' '%s'", layoutId, elementIndex, prop, tostring(value)))
        end
    end
end

-- ============================================================================
-- Prompt — Collects user parameters before generation
-- ============================================================================

local function generatePrompt()
    local result = MessageBox({
        title   = "Color Picker Generator",
        message = "Define parameters for color picker generation",
        commands = {
            { value = 1, name = "Generate" },
            { value = 0, name = "Cancel"   },
        },
        inputs = {
            { name = "01. Groups Offset",       value = "1",    whiteFilter = "0123456789" },
            { name = "02. Groups Count",        value = "4",    whiteFilter = "0123456789" },
            { name = "03. Color Preset Offset", value = "1",    whiteFilter = "0123456789" },
            { name = "04. Color Preset Amount", value = "10",   whiteFilter = "0123456789" },
            { name = "05. FX Color Offset",     value = "7001", whiteFilter = "0123456789" },
            { name = "06. FX Color Count",      value = "2",    whiteFilter = "0123456789" },
            { name = "07. Sequences Offset",    value = "7001", whiteFilter = "0123456789" },
            { name = "08. Macros Offset",       value = "7001", whiteFilter = "0123456789" },
            { name = "09. Timing Master",       value = "1",    whiteFilter = "0123456789" },
            { name = "10. Speed Master",        value = "1",    whiteFilter = "0123456789" },
            { name = "11. MAtricks Offset",     value = "7001", whiteFilter = "0123456789" },
            { name = "12. Image Pool Offset",   value = "7001", whiteFilter = "0123456789" },
            { name = "13. Appearance Offset",   value = "7001", whiteFilter = "0123456789" },
            { name = "14. Layout Offset",       value = "2", whiteFilter = "0123456789" },
        },
    })

    if not result.success or result.result == 0 then
        Echo("Color picker generation failed or cancelled")
        return
    end

    local groupOffset = tonumber(result.inputs["01. Groups Offset"])
    local groupCount  = tonumber(result.inputs["02. Groups Count"])
    local groupIds = {}
    for i = groupOffset, groupOffset + groupCount - 1 do
        table.insert(groupIds, i)
    end

    GeneratePalette({
        group_ids           = groupIds,
        color_preset_offset = tonumber(result.inputs["03. Color Preset Offset"]),
        color_preset_count  = tonumber(result.inputs["04. Color Preset Amount"]),
        fx_offset           = tonumber(result.inputs["05. FX Color Offset"]),
        fx_count            = tonumber(result.inputs["06. FX Color Count"]),
        sequences_offset    = tonumber(result.inputs["07. Sequences Offset"]),
        macros_offset       = tonumber(result.inputs["08. Macros Offset"]),
        timing_master       = tonumber(result.inputs["09. Timing Master"]),
        speed_master        = tonumber(result.inputs["10. Speed Master"]),
        matricks_offset     = tonumber(result.inputs["11. MAtricks Offset"]),
        image_pool_offset   = tonumber(result.inputs["12. Image Pool Offset"]),
        appearance_offset   = tonumber(result.inputs["13. Appearance Offset"]),
        layout_offset       = tonumber(result.inputs["14. Layout Offset"]),
    })
end

-- ============================================================================
-- extractFirstColor — Reads the first RGB color from a preset
-- ============================================================================

local function extractFirstColor(presetHandle)
    if not presetHandle then
        return nil
    end

    local presetData = GetPresetData(presetHandle, false, true)
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

    -- Convert MA3 percentage (0-100) to RGB integer (0-255)
    return {
        r = math.floor((rVal / 100) * 255 + 0.5),
        g = math.floor((gVal / 100) * 255 + 0.5),
        b = math.floor((bVal / 100) * 255 + 0.5),
    }
end

-- ============================================================================
-- extractColorPresets — Scans color pool for presets in range
-- ============================================================================

local function extractColorPresets(offset, amount)
    local colorPool = DataPool().PresetPools[4]
    if not colorPool then
        ErrEcho("Could not find color preset pool")
        return nil
    end

    local presets = {}
    for i = 1, amount do
        local poolIndex = i + offset - 1
        local preset = colorPool[poolIndex]

        if not preset then
            ErrEcho(fmt("Could not find preset 4.%d", poolIndex))
            goto continue
        end

        table.insert(presets, {
            id    = poolIndex,
            name  = preset.name,
            color = extractFirstColor(preset),
        })

        ::continue::
    end

    Printf("=================== COLOR POOL SCAN COMPLETE ===================")
    for _, item in ipairs(presets) do
        Printf("Preset 4.%d | Name: '%s' | R: %d, G: %d, B: %d",
            item.id, item.name, item.color.r, item.color.g, item.color.b)
    end
    Printf("================================================================")

    return presets
end

-- ============================================================================
-- extractGroupData — Scans group pool for groups in the given ID array
-- ============================================================================

local function extractGroupData(groupIds)
    local groupPool = DataPool().Groups
    if not groupPool then
        ErrPrintf("Could not find group pool")
        return {}
    end

    Printf("=================== EXTRACTING GROUPS ===================")

    local groups = {}
    for _, i in ipairs(groupIds) do
        local grp = groupPool[i]
        if grp then
            table.insert(groups, { id = i, name = grp.name })
            Printf("Found Group %d: %s", i, grp.name)
        else
            Printf("Warning: Group %d is empty, skipping.", i)
        end
    end

    Printf("=========================================================")
    return groups
end

-- ============================================================================
-- generateAppearances — Creates ON/OFF appearances per color
-- ============================================================================

local function generateAppearances(presets, appearanceOffset, images)
    for i, preset in ipairs(presets) do
        local onIndex  = appearanceOffset + i - 1
        local offIndex = appearanceOffset + i - 1 + #presets

        storeAndLabel(fmt("Appearance %d", onIndex),
            fmt("Picker %s@%d ON", preset.name, preset.id))
        storeAndLabel(fmt("Appearance %d", offIndex),
            fmt("Picker %s@%d OFF", preset.name, preset.id))

        Cmd(fmt("Assign Image %s At Appearance %d", images.fxImageOn, onIndex))
        Cmd(fmt("Assign Image %s At Appearance %d", images.fxImageOff, offIndex))

        local colorStr = fmt("ImageR %d ImageG %d ImageB %d ImageAlpha 255",
            preset.color.r, preset.color.g, preset.color.b)
        Cmd(fmt("Set Appearance %d %s", onIndex, colorStr))
        Cmd(fmt("Set Appearance %d %s", offIndex, colorStr))

        preset.on_appearance  = onIndex
        preset.off_appearance = offIndex
    end

    -- Dedicated FX ON/OFF appearances using separate FX images
    local fxIndex  = appearanceOffset + #presets * 2

    for j, fx in ipairs({
        { name = "Even-Odd", imageOn = images.fxDualImageOn, imageOff = images.fxDualImageOff },
        { name = "Gradient", imageOn = images.fxGradImageOn, imageOff = images.fxGradImageOff },
        { name = "Flicker",  imageOn = images.fxDualImageOn, imageOff = images.fxDualImageOff },
        { name = "Chase",    imageOn = images.fxGradImageOn, imageOff = images.fxGradImageOff },
    }) do
        storeAndLabel(fmt("Appearance %d", fxIndex),  "Picker FX " .. fx.name .. " ON")
        storeAndLabel(fmt("Appearance %d", fxIndex + #EFFECTS), "Picker FX " .. fx.name .. " OFF")

        Cmd(fmt("Assign Image %s At Appearance %d", fx.imageOn,  fxIndex))
        Cmd(fmt("Assign Image %s At Appearance %d", fx.imageOff, fxIndex + #EFFECTS))

        local fxColorStr = "ImageR 255 ImageG 255 ImageB 255 ImageAlpha 255"
        Cmd(fmt("Set Appearance %d %s", fxIndex,  fxColorStr))
        Cmd(fmt("Set Appearance %d %s", fxIndex + #EFFECTS, fxColorStr))

        fxOnAppearance[fx.name]  = fxIndex
        fxOffAppearance[fx.name] = fxIndex + #EFFECTS

        fxIndex = fxIndex + 1
    end

    -- Settings page ON/OFF appearances
    local settingsOnIndex  = fxIndex + #EFFECTS
    local settingsOffIndex = settingsOnIndex + 1

    storeAndLabel(fmt("Appearance %d", settingsOnIndex),  "Settings ON")
    storeAndLabel(fmt("Appearance %d", settingsOffIndex), "Settings OFF")

    Cmd(fmt("Assign Image %s At Appearance %d", images.buttonImageOn,  settingsOnIndex))
    Cmd(fmt("Assign Image %s At Appearance %d", images.buttonImageOff, settingsOffIndex))

    local settingsColorStr = "ImageR 255 ImageG 255 ImageB 200 ImageAlpha 255"
    Cmd(fmt("Set Appearance %d %s", settingsOnIndex,  settingsColorStr))
    Cmd(fmt("Set Appearance %d %s", settingsOffIndex, settingsColorStr))

    settingsOnAppearance  = settingsOnIndex
    settingsOffAppearance = settingsOffIndex
end

-- ============================================================================
-- generateReferencePresets — Creates FX color presets (A/B pairs)
-- ============================================================================

local function generateReferencePresets(fxOffset, fxCount)
    local index = fxOffset
    local fxPresets = {}

    for i = 1, fxCount do
        storeAndLabel(fmt("Preset 4.%d", index),     fmt("Picker FX %d A", i))
        storeAndLabel(fmt("Preset 4.%d", index + 1), fmt("Picker FX %d B", i))

        fxPresets[i] = { A = index, B = index + 1 }
        index = index + 2
    end

    return fxPresets
end

-- ============================================================================
-- generateColorSequences — Creates sequences with color and FX cues
-- ============================================================================

local function generateColorSequences(groups, colors, sequenceOffset, timingMaster, speedMaster, fxPresets)
    Printf("=================== GENERATING SEQUENCES ===================")

    for gi, group in ipairs(groups) do
        local seqIndex = sequenceOffset + gi - 1
        group.sequence = seqIndex

        storeAndLabel(fmt("Sequence %d", seqIndex),
            fmt("Color Picker %s@%d", group.name, group.id))
        Cmd(fmt("Set Sequence %d Property 'RestartMode' 'Current Cue'", seqIndex))
        Cmd(fmt("Set Sequence %d 'SpeedMaster' 'Speed%d'", seqIndex, speedMaster))

        local cueIndex = 1

        -- Color cue for each extracted preset
        for _, color in ipairs(colors) do
            Cmd(fmt("Store Sequence %d Cue %d /Overwrite", seqIndex, cueIndex))
            Cmd(fmt("Label Sequence %d Cue %d '%s@%d'", seqIndex, cueIndex, color.name, color.id))
            Cmd(fmt("Set Sequence %d Cue %d Cuefade 'Timing%d'", seqIndex, cueIndex, timingMaster))

            Cmd(fmt("Assign Group %d At Sequence %d Cue %d Part 0.*", group.id, seqIndex, cueIndex))
            Cmd(fmt("Assign Preset 4.%d At Sequence %d Cue %d Part 0.*", color.id, seqIndex, cueIndex))

            Cmd(fmt("Cook Sequence %d Cue %d /Overwrite", seqIndex, cueIndex))
            cueIndex = cueIndex + 1
        end

        -- FX cues per fx color and effect type
        for fxi, fxColor in ipairs(fxPresets) do
            -- Even-Odd
            Cmd(fmt("Store Sequence %d Cue %d /Overwrite", seqIndex, cueIndex))
            Cmd(fmt("Label Sequence %d Cue %d 'FX%d Even-Odd'", seqIndex, cueIndex, fxi))
            Cmd(fmt("Set Sequence %d Cue %d Cuefade 'Timing%d'", seqIndex, cueIndex, timingMaster))

            Cmd(fmt("Assign Group %d At Sequence %d Cue %d Part 0.1", group.id, seqIndex, cueIndex))
            Cmd(fmt("Assign Preset 4.%d At Sequence %d Cue %d Part 0.1", fxColor.A, seqIndex, cueIndex))
            Cmd(fmt("Set Sequence %d Cue %d Part 0.1 Property 'XGroup' 2 'X' 1", seqIndex, cueIndex))

            Cmd(fmt("Assign Group %d At Sequence %d Cue %d Part 0.2", group.id, seqIndex, cueIndex))
            Cmd(fmt("Assign Preset 4.%d At Sequence %d Cue %d Part 0.2", fxColor.B, seqIndex, cueIndex))
            Cmd(fmt("Set Sequence %d Cue %d Part 0.2 Property 'XGroup' 2 'X' 2", seqIndex, cueIndex))
            Cmd(fmt("Assign MAtricks %d At Sequence %d Cue %d Part 0.1", fxColor.matricks_base, seqIndex, cueIndex))
            Cmd(fmt("Assign MAtricks %d At Sequence %d Cue %d Part 0.2", fxColor.matricks_base, seqIndex, cueIndex))

            cueIndex = cueIndex + 1

            -- Gradient
            Cmd(fmt("Store Sequence %d Cue %d /Overwrite", seqIndex, cueIndex))
            Cmd(fmt("Label Sequence %d Cue %d 'FX%d Gradient'", seqIndex, cueIndex, fxi))
            Cmd(fmt("Set Sequence %d Cue %d Cuefade 'Timing%d'", seqIndex, cueIndex, timingMaster))

            Cmd(fmt("Store Type 'PhaserRecipe' Sequence %d Cue %d Part 0.1", seqIndex, cueIndex))
            Cmd(fmt("Assign Group %d At Sequence %d Cue %d Part 0.1", group.id, seqIndex, cueIndex))
            Cmd(fmt("Assign Preset 4.%d At Sequence %d Cue %d Part 0.1.'PhaserRecipeSteps'.1.1", fxColor.B, seqIndex, cueIndex))
            Cmd(fmt("Assign Preset 4.%d At Sequence %d Cue %d Part 0.1.'PhaserRecipeSteps'.2.1", fxColor.A, seqIndex, cueIndex))
            Cmd(fmt("Set Sequence %d Cue %d Part 0.1 Property 'SpeedX' 0", seqIndex, cueIndex))
            Cmd(fmt("Assign MAtricks %d At Sequence %d Cue %d Part 0.1", fxColor.matricks_base, seqIndex, cueIndex))

            cueIndex = cueIndex + 1

            -- Flicker
            Cmd(fmt("Store Sequence %d Cue %d /Overwrite", seqIndex, cueIndex))
            Cmd(fmt("Label Sequence %d Cue %d 'FX%d Flicker'", seqIndex, cueIndex, fxi))
            Cmd(fmt("Set Sequence %d Cue %d Cuefade 'Timing%d'", seqIndex, cueIndex, timingMaster))

            Cmd(fmt("Store Type 'PhaserRecipe' Sequence %d Cue %d Part 0.1", seqIndex, cueIndex))
            Cmd(fmt("Assign Group %d At Sequence %d Cue %d Part 0.1", group.id, seqIndex, cueIndex))
            Cmd(fmt("Assign Preset 4.%d At Sequence %d Cue %d Part 0.1.'PhaserRecipeSteps'.1.1", fxColor.A, seqIndex, cueIndex))
            Cmd(fmt("Assign Preset 4.%d At Sequence %d Cue %d Part 0.1.'PhaserRecipeSteps'.2.1", fxColor.B, seqIndex, cueIndex))
            Cmd(fmt("Set Sequence %d Cue %d Part 0.1 Property 'PhaseX' '0 Thru 360'", seqIndex, cueIndex))
            Cmd(fmt("Set Sequence %d Cue %d Part 0.1 Property 'XShuffle' '17549'", seqIndex, cueIndex))
            Cmd(fmt("Set Sequence %d Cue %d Part 0.1 Property 'PhaseY' '0 Thru 360'", seqIndex, cueIndex))
            Cmd(fmt("Set Sequence %d Cue %d Part 0.1 Property 'YShuffle' '21308'", seqIndex, cueIndex))
            Cmd(fmt("Assign MAtricks %d At Sequence %d Cue %d Part 0.1", fxColor.matricks_base, seqIndex, cueIndex))

            cueIndex = cueIndex + 1

            -- Chase
            Cmd(fmt("Store Sequence %d Cue %d /Overwrite", seqIndex, cueIndex))
            Cmd(fmt("Label Sequence %d Cue %d 'FX%d Chase'", seqIndex, cueIndex, fxi))
            Cmd(fmt("Set Sequence %d Cue %d Cuefade 'Timing%d'", seqIndex, cueIndex, timingMaster))

            Cmd(fmt("Store Type 'PhaserRecipe' Sequence %d Cue %d Part 0.1", seqIndex, cueIndex))
            Cmd(fmt("Assign Group %d At Sequence %d Cue %d Part 0.1", group.id, seqIndex, cueIndex))
            Cmd(fmt("Assign Preset 4.%d At Sequence %d Cue %d Part 0.1.'PhaserRecipeSteps'.1.1", fxColor.A, seqIndex, cueIndex))
            Cmd(fmt("Assign Preset 4.%d At Sequence %d Cue %d Part 0.1.'PhaserRecipeSteps'.2.1", fxColor.B, seqIndex, cueIndex))
            Cmd(fmt("Assign MAtricks %d At Sequence %d Cue %d Part 0.1", fxColor.matricks_base, seqIndex, cueIndex))

            cueIndex = cueIndex + 1
        end

        Printf(fmt("Generated sequence %d with %d cues", seqIndex, #colors + #fxPresets * #EFFECTS))
    end

    Printf("============================================================")
end

-- ============================================================================
-- Macro Helpers
-- ============================================================================

local function assignMacro(macroId, name, commands)
    storeAndLabel(fmt("Macro %d", macroId), name)

    for i, cmdStr in ipairs(commands) do
        Cmd(fmt("Insert Macro %d.%d", macroId, i))
        Cmd(fmt("Set Macro %d.%d Property 'Command' \"%s\"", macroId, i, cmdStr))
    end

    Printf("Macro '%s' created successfully.", name)
end

-- ============================================================================
-- generateSelectorGroup — Common logic for color/FX selector macro groups
-- ============================================================================

local function generateSelectorGroup(macroStartIndex, name, colors, fxPresets, groups, effectGroup, updateLogic)
    local groupBaseIndex = macroStartIndex
    local numColors = #colors
    local numEffects = #EFFECTS
    local numFxPresets = #fxPresets

    local firstColorAppearance = colors[1][effectGroup == "ALL" and "on_appearance" or "off_appearance"]
    local fxAppearanceRef = effectGroup == "ALL" and fxOnAppearance or fxOffAppearance

    -- Color selector macros
    for ci, color in ipairs(colors) do
        local lines = {
            -- Reset appearances for all color macros in this group
            fmt("Assign Appearance %d Thru %d At Macro %d Thru %d",
                firstColorAppearance, firstColorAppearance + numColors - 1,
                groupBaseIndex, groupBaseIndex + numColors - 1),
        }

        if effectGroup ~= "ALL" then
            table.insert(lines, fmt("Assign Appearance %d At Macro %d", color.on_appearance, macroStartIndex))
        end

        if effectGroup then
            table.insert(lines, fmt("Assign Appearance %d Thru %d At Macro %d Thru %d",
                fxAppearanceRef[EFFECTS[1]],
                fxAppearanceRef[EFFECTS[1]] + 3,
                groupBaseIndex + numColors,
                groupBaseIndex + numColors - 1 + numEffects * numFxPresets))
        end

        local cmdLines = updateLogic(ci, color)
        for _, cmd in ipairs(cmdLines) do
            table.insert(lines, cmd)
        end

        assignMacro(macroStartIndex, fmt("%s Color %d", name, ci), lines)
        macroStartIndex = macroStartIndex + 1
    end

    -- FX selector macros
    if effectGroup then
        for fxci = 1, numFxPresets do
            for fxi, fxName in ipairs(EFFECTS) do
                local lines = {
                    fmt("Assign Appearance %d Thru %d At Macro %d Thru %d",
                        firstColorAppearance, firstColorAppearance + numColors - 1,
                        groupBaseIndex, groupBaseIndex + numColors - 1),

                    fmt("Assign Appearance %d Thru %d At Macro %d Thru %d",
                        fxAppearanceRef[EFFECTS[1]],
                        fxAppearanceRef[EFFECTS[1]] + 3,
                        groupBaseIndex + numColors,
                        groupBaseIndex + numColors - 1 + numEffects * numFxPresets),
                }

                if effectGroup ~= "ALL" then
                    table.insert(lines, fmt("Assign Appearance %d At Macro %d", fxOnAppearance[fxName], macroStartIndex))
                end

                if effectGroup == "ALL" then
                    for _, group in ipairs(groups) do
                        table.insert(lines, fmt("Call Macro %d",
                            group.first_macro + numColors + fxi - 1 + (fxci - 1) * numEffects))
                    end
                else
                    table.insert(lines, fmt("Go Sequence %d Cue %d",
                        effectGroup, numColors + (fxci - 1) * numEffects + fxi))
                end

                assignMacro(macroStartIndex, fmt("%s FX%d %s", name, fxci, fxName), lines)
                macroStartIndex = macroStartIndex + 1
            end
        end
    end

    return macroStartIndex
end

-- ============================================================================
-- generateMacros — Creates all color picker and FX selector macros
-- ============================================================================

local function generateMacros(groups, colors, macroOffset, fxPresets)
    local macroIndex = macroOffset

    -- Per-group picker macros
    for gi, group in ipairs(groups) do
        group.first_macro = macroIndex
        macroIndex = generateSelectorGroup(
            macroIndex,
            fmt("Picker Group %d", group.id),
            colors, fxPresets, groups,
            group.sequence,
            function(ci, color)
                return { fmt("Go Sequence %d Cue %d", group.sequence, ci) }
            end
        )
    end

    -- Per-FX stop A/B macros (copy color into FX preset)
    for _, fxColor in ipairs(fxPresets) do
        fxColor.macroA = macroIndex
        macroIndex = generateSelectorGroup(
            macroIndex,
            fmt("Picker FX %d Stop A", fxColor.A),
            colors, fxPresets, groups,
            false,
            function(ci, color)
                return { fmt("Copy Preset 4.%d At Preset 4.%d /Merge", color.id, fxColor.A) }
            end
        )

        fxColor.macroB = macroIndex
        macroIndex = generateSelectorGroup(
            macroIndex,
            fmt("Picker FX %d Stop B", fxColor.B),
            colors, fxPresets, groups,
            false,
            function(ci, color)
                return { fmt("Copy Preset 4.%d At Preset 4.%d /Merge", color.id, fxColor.B) }
            end
        )
    end

    -- FX MAtricks direction macros
    for fxi, fxColor in ipairs(fxPresets) do
        local blockStart = macroIndex
        fxColor.matricks_macro_base = blockStart
        for mi = 1, #MATRICKS_PATTERNS do
            local cfg = MATRICKS_CONFIGS[mi]
            local mBase = fxColor.matricks_base
            local lines = {
                fmt("Assign Appearance %d Thru %d At Macro %d Thru %d",
                    settingsOffAppearance, settingsOffAppearance,
                    blockStart, blockStart + #MATRICKS_PATTERNS - 1),
                fmt("Assign Appearance %d At Macro %d", settingsOnAppearance, macroIndex),
                fmt("Set MAtricks %d Property 'XWings' %s",       mBase, cfg.wings),
                fmt("Set MAtricks %d Property 'PhaseFromX' '%s'", mBase, cfg.phase[1]),
                fmt("Set MAtricks %d Property 'PhaseToX' '%s'",   mBase, cfg.phase[2]),
            }
            assignMacro(macroIndex, fmt("FX%d MAtricks %s", fxi, MATRICKS_PATTERNS[mi]), lines)
            macroIndex = macroIndex + 1
        end
    end

    -- Master "ALL" macros (trigger all groups)
    masterMacrosOffset = macroIndex
    generateSelectorGroup(
        macroIndex, "Picker ALL",
        colors, fxPresets, groups,
        "ALL",
        function(ci, color)
            local lines = {}
            for _, group in ipairs(groups) do
                table.insert(lines, fmt("Call Macro %d", group.first_macro + ci - 1))
            end
            return lines
        end
    )
end

-- ============================================================================
-- Color Set Row Helper — Places a label + row of color picker buttons
-- ============================================================================

local function generateColorSetRow(layoutId, elementIndex, posY, label, macroOffset, colors)
    -- Label cell
    Cmd(fmt("Store Layout %d.%d", layoutId, elementIndex))
    Cmd(fmt("Label Layout %d.%d 'Label %s'", layoutId, elementIndex, label))
    setLayoutCellProps(layoutId, elementIndex, {
        Width              = LAYOUT_LABEL_WIDTH,
        Height             = LAYOUT_LABEL_HEIGHT,
        VisibilityBorder   = "Hidden",
        CustomTextText     = label,
        CustomTextSize     = LAYOUT_LABEL_FONT_SIZE,
        CustomTextAlignmentH = "Right",
        PosX               = 0,
        PosY               = posY,
    })
    elementIndex = elementIndex + 1

    -- Color picker buttons
    for ci = 1, #colors do
        Cmd(fmt("Assign Macro %d At Layout %d", macroOffset + ci - 1, layoutId))
        setLayoutCellProps(layoutId, elementIndex, {
            VisibilityObjectName    = "Hidden",
            VisibilityBorder        = "Hidden",
            VisibilityIndicatorBar  = "Hidden",
            Width  = LAYOUT_PICKER_SIZE,
            Height = LAYOUT_PICKER_SIZE,
            PosX   = LAYOUT_LEFT_MARGIN + (ci - 1) * LAYOUT_PICKER_SPACING,
            PosY   = posY,
        })
        elementIndex = elementIndex + 1
    end

    return elementIndex
end

-- ============================================================================
-- generateLayout — Creates Master Color Picker and FX Color Picker layouts
-- ============================================================================

local function generateLayout(layoutOffset, groups, colors, fxPresets)
    local numColors    = #colors
    local numEffects   = #EFFECTS
    local numFxPresets = #fxPresets

    local masterLayoutId = layoutOffset
    local fxLayoutId     = layoutOffset + 1

    -- Master Color Picker layout
    deleteIfExists(fmt("Delete Layout %d", masterLayoutId))
    Cmd(fmt("Store Layout %d /Overwrite", masterLayoutId))
    Cmd(fmt("Label Layout %d 'Master Color Picker'", masterLayoutId))
    Cmd(fmt("Select Layout %d", masterLayoutId))

    local numMatricks = #MATRICKS_PATTERNS
    storeAndLabel(fmt("Layout %d.1", masterLayoutId), "Spacer")
    setLayoutCellProps(masterLayoutId, 1, {
        VisibilityBorder = "Hidden",
        Width = LAYOUT_LEFT_MARGIN + numColors * LAYOUT_PICKER_SPACING
                + LAYOUT_FX_GAP + numFxPresets * LAYOUT_FX_GROUP_WIDTH + LAYOUT_FX_GAP,
    })

    -- FX Color Picker layout
    deleteIfExists(fmt("Delete Layout %d", fxLayoutId))
    Cmd(fmt("Store Layout %d /Overwrite", fxLayoutId))
    Cmd(fmt("Label Layout %d 'FX Color Picker'", fxLayoutId))

    storeAndLabel(fmt("Layout %d.1", fxLayoutId), "Spacer")
    setLayoutCellProps(fxLayoutId, 1, {
        VisibilityBorder = "Hidden",
        Width = LAYOUT_LEFT_MARGIN + numColors * LAYOUT_PICKER_SPACING + LAYOUT_FX_GAP
                + 2 * LAYOUT_PICKER_SPACING + 20,
    })

    local elementIndex = { [masterLayoutId] = 2, [fxLayoutId] = 2 }

    -- Per-group rows: color buttons + FX effect buttons
    for gi, group in ipairs(groups) do
        local posY = -(gi - 1) * LAYOUT_ROW_HEIGHT - 80

        elementIndex[masterLayoutId] = generateColorSetRow(
            masterLayoutId, elementIndex[masterLayoutId],
            posY, group.name, group.first_macro, colors)

        for fxi = 1, numFxPresets do
            for fi = 1, numEffects do
                local fxMacroId = group.first_macro + numColors + fi - 1 + (fxi - 1) * numEffects
                Cmd(fmt("Assign Macro %d At Layout %d", fxMacroId, masterLayoutId))
                setLayoutCellProps(masterLayoutId, elementIndex[masterLayoutId], {
                    VisibilityObjectName   = "Hidden",
                    VisibilityBorder       = "Hidden",
                    VisibilityIndicatorBar = "Hidden",
                    CustomTextText = fmt("FX %d", fxi),
                    CustomTextSize = LAYOUT_LABEL_FONT_SIZE,
                    Width  = LAYOUT_PICKER_SIZE,
                    Height = LAYOUT_PICKER_SIZE,
                    PosX = LAYOUT_LEFT_MARGIN + numColors * LAYOUT_PICKER_SPACING + LAYOUT_FX_GAP
                           + (fi - 1) * LAYOUT_PICKER_SPACING + (fxi - 1) * LAYOUT_FX_GROUP_WIDTH,
                    PosY = posY,
                })
                elementIndex[masterLayoutId] = elementIndex[masterLayoutId] + 1
            end
        end
    end

    -- FX Stop A/B rows and MAtricks 2x2 grid
    for fxi, fxColor in ipairs(fxPresets) do
        local baseY = -(fxi - 1) * 130
        elementIndex[fxLayoutId] = generateColorSetRow(
            fxLayoutId, elementIndex[fxLayoutId],
            baseY, fmt("FX %d Stop A", fxi), fxColor.macroA, colors)

        elementIndex[fxLayoutId] = generateColorSetRow(
            fxLayoutId, elementIndex[fxLayoutId],
            baseY - LAYOUT_ROW_HEIGHT, fmt("FX %d Stop B", fxi), fxColor.macroB, colors)

        -- MAtricks 2x2 direction grid for this FX preset
        local matricksGridX = LAYOUT_LEFT_MARGIN + numColors * LAYOUT_PICKER_SPACING + LAYOUT_FX_GAP
        for mi = 1, numMatricks do
            local col = (mi - 1) % 2
            local row = math.floor((mi - 1) / 2)
            local macroId = fxColor.matricks_macro_base + mi - 1
            Cmd(fmt("Assign Macro %d At Layout %d", macroId, fxLayoutId))
            setLayoutCellProps(fxLayoutId, elementIndex[fxLayoutId], {
                VisibilityObjectName   = "Hidden",
                VisibilityBorder       = "Hidden",
                VisibilityIndicatorBar = "Hidden",
                CustomTextText = MATRICKS_PATTERNS[mi],
                CustomTextSize = LAYOUT_LABEL_FONT_SIZE,
                Width  = LAYOUT_PICKER_SIZE,
                Height = LAYOUT_PICKER_SIZE,
                PosX = matricksGridX + col * LAYOUT_PICKER_SPACING,
                PosY = baseY - row * LAYOUT_ROW_HEIGHT,
            })
            elementIndex[fxLayoutId] = elementIndex[fxLayoutId] + 1
        end
    end

    -- Master "ALL" row
    elementIndex[masterLayoutId] = generateColorSetRow(masterLayoutId, elementIndex[masterLayoutId],
        0, "MASTER/ALL", masterMacrosOffset, colors)

    -- Master FX buttons
    for fxi = 1, numFxPresets do
        for fi, fxName in ipairs(EFFECTS) do
            local fxMacroId = masterMacrosOffset + numColors + fi - 1 + (fxi - 1) * numEffects
            Cmd(fmt("Assign Macro %d At Layout %d", fxMacroId, masterLayoutId))
            setLayoutCellProps(masterLayoutId, elementIndex[masterLayoutId], {
                VisibilityObjectName   = "Hidden",
                VisibilityBorder       = "Hidden",
                VisibilityIndicatorBar = "Hidden",
                CustomTextText = fxName,
                CustomTextSize = LAYOUT_LABEL_FONT_SIZE,
                Width  = LAYOUT_PICKER_SIZE,
                Height = LAYOUT_PICKER_SIZE,
                PosX = LAYOUT_LEFT_MARGIN + numColors * LAYOUT_PICKER_SPACING + LAYOUT_FX_GAP
                       + (fi - 1) * LAYOUT_PICKER_SPACING + (fxi - 1) * LAYOUT_FX_GROUP_WIDTH,
                PosY = 0,
            })
            elementIndex[masterLayoutId] = elementIndex[masterLayoutId] + 1
        end
    end
end

-- ============================================================================
-- generateMAtricksObjects — Creates MAtricks pool objects for patterns
-- ============================================================================

local function generateMAtricksObjects(matricksOffset, fxPresets)
    for i, fxColor in ipairs(fxPresets) do
        fxColor.matricks_base = matricksOffset + (i - 1)
        storeAndLabel(fmt("MAtricks %d", fxColor.matricks_base), fmt("Color Picker FX%d", i))
    end
end

-- ============================================================================
-- generateSettingsLayout — Creates "Color Picker Settings" layout with
-- fade time and speed multiplier rows
-- ============================================================================

local function generateSettingsLayout(layoutOffset, options, groups, fxPresets)
    local settingsLayoutId = layoutOffset + 2
    local numColors     = options.color_preset_count
    local numEffects    = #EFFECTS
    local numFxPresets  = options.fx_count
    local numGroups     = #groups

    local seqStart = options.sequences_offset
    local seqEnd   = options.sequences_offset + numGroups - 1

    -- ALL macros consume: numColors color + numFxPresets * numEffects FX macros
    local allMacrosCount = numColors + numEffects * numFxPresets
    local settingsMacroBase = masterMacrosOffset + allMacrosCount

    -- Create layout container
    deleteIfExists(fmt("Delete Layout %d", settingsLayoutId))
    Cmd(fmt("Store Layout %d /Overwrite", settingsLayoutId))
    Cmd(fmt("Label Layout %d 'Color Picker Settings'", settingsLayoutId))

    storeAndLabel(fmt("Layout %d.1", settingsLayoutId), "Spacer")
    setLayoutCellProps(settingsLayoutId, 1, {
        VisibilityBorder = "Hidden",
        Width = LAYOUT_LEFT_MARGIN + 600,
    })

    local cellIndex = 2
    local fadeTimes       = { 0, 1, 2, 5 }
    local speedFactors    = { "Div4", "Div2", "One", "Mul2" }
    local speedLabels     = { "1/4", "1/2", "1", "2" }
    local fadeColCount    = #fadeTimes
    local speedColCount   = #speedFactors

    -- Helper: build settings macro commands with per-row appearance toggling
    local function settingsMacroCommands(thisMacroId, actions, rowBase, rowCount)
        local rowEnd = rowBase + rowCount - 1
        local lines = {
            fmt("Assign Appearance %d Thru %d At Macro %d Thru %d",
                settingsOffAppearance, settingsOffAppearance, rowBase, rowEnd),
            fmt("Assign Appearance %d At Macro %d", settingsOnAppearance, thisMacroId),
        }
        for _, a in ipairs(actions) do
            table.insert(lines, a)
        end
        return lines
    end

    -- ============ ROW 1: Fade Time ============
    local rowY1 = 0

    Cmd(fmt("Store Layout %d.%d", settingsLayoutId, cellIndex))
    setLayoutCellProps(settingsLayoutId, cellIndex, {
        Width              = LAYOUT_LABEL_WIDTH,
        Height             = LAYOUT_LABEL_HEIGHT,
        VisibilityBorder   = "Hidden",
        CustomTextText     = "Fade Time",
        CustomTextSize     = LAYOUT_LABEL_FONT_SIZE,
        CustomTextAlignmentH = "Right",
        PosX = 0,
        PosY = rowY1,
    })
    cellIndex = cellIndex + 1

    for i, fadeTime in ipairs(fadeTimes) do
        local macroId = settingsMacroBase + (i - 1)
        assignMacro(macroId, fmt("Settings Fade %ds", fadeTime),
            settingsMacroCommands(macroId,
                { fmt("Master Timing.%d %d", options.timing_master, fadeTime * 10) },
                settingsMacroBase, fadeColCount))

        Cmd(fmt("Assign Macro %d At Layout %d", macroId, settingsLayoutId))
        setLayoutCellProps(settingsLayoutId, cellIndex, {
            VisibilityObjectName   = "Hidden",
            VisibilityBorder       = "Hidden",
            VisibilityIndicatorBar = "Hidden",
            CustomTextText = fmt("%ds", fadeTime),
            CustomTextSize = LAYOUT_LABEL_FONT_SIZE,
            Width  = LAYOUT_PICKER_SIZE,
            Height = LAYOUT_PICKER_SIZE,
            PosX   = LAYOUT_LEFT_MARGIN + (i - 1) * LAYOUT_PICKER_SPACING,
            PosY   = rowY1,
        })
        cellIndex = cellIndex + 1
    end
    Cmd(fmt("Call Macro %d", settingsMacroBase))

    -- ============ ROW 2: Speed Multiplier ============
    local rowY2 = -(LAYOUT_ROW_HEIGHT + LAYOUT_ROW_GAP)
    local speedMacroBase = settingsMacroBase + fadeColCount

    Cmd(fmt("Store Layout %d.%d", settingsLayoutId, cellIndex))
    setLayoutCellProps(settingsLayoutId, cellIndex, {
        Width              = LAYOUT_LABEL_WIDTH,
        Height             = LAYOUT_LABEL_HEIGHT,
        VisibilityBorder   = "Hidden",
        CustomTextText     = "Speed",
        CustomTextSize     = LAYOUT_LABEL_FONT_SIZE,
        CustomTextAlignmentH = "Right",
        PosX = 0,
        PosY = rowY2,
    })
    cellIndex = cellIndex + 1

    for i, factor in ipairs(speedFactors) do
        local macroId = speedMacroBase + (i - 1)
        assignMacro(macroId, fmt("Settings Speed %sx", speedLabels[i]),
            settingsMacroCommands(macroId,
                { fmt("Set Sequence %d Thru %d Property 'SpeedScale' '%s'",
                    seqStart, seqEnd, factor) },
                speedMacroBase, speedColCount))

        Cmd(fmt("Assign Macro %d At Layout %d", macroId, settingsLayoutId))
        setLayoutCellProps(settingsLayoutId, cellIndex, {
            VisibilityObjectName   = "Hidden",
            VisibilityBorder       = "Hidden",
            VisibilityIndicatorBar = "Hidden",
            CustomTextText = fmt("%sx", speedLabels[i]),
            CustomTextSize = LAYOUT_LABEL_FONT_SIZE,
            Width  = LAYOUT_PICKER_SIZE,
            Height = LAYOUT_PICKER_SIZE,
            PosX   = LAYOUT_LEFT_MARGIN + (i - 1) * LAYOUT_PICKER_SPACING,
            PosY   = rowY2,
        })
        cellIndex = cellIndex + 1
    end

    Cmd(fmt("Call Macro %d", speedMacroBase + 2))
end

-- ============================================================================
-- activateDefaults — Calls default macros to initialize state
-- ============================================================================

local function activateDefaults(fxPresets)
    Cmd(fmt("Call Macro %d", masterMacrosOffset))

    for _, fxColor in ipairs(fxPresets) do
        Cmd(fmt("Call Macro %d", fxColor.macroA))
        Cmd(fmt("Call Macro %d", fxColor.macroB))
        Cmd(fmt("Call Macro %d", fxColor.matricks_macro_base))
    end
end

-- ============================================================================
-- importImage — Imports an image into the image pool
-- ============================================================================

local function importImage(path, label, id)
    deleteIfExists(fmt("Delete Image %s", id))
    Cmd(fmt("Import Image %s /File '%s.png'", id, path))
    Cmd(fmt("Label Image %s '%s'", id, label))
end

-- ============================================================================
-- GeneratePalette — Main orchestrator
-- ============================================================================

function GeneratePalette(options)
    progressHandle = StartProgress("Generating Color Palette")
    SetProgressRange(progressHandle, 1, 8)

    -- Step 1: Import required images
    updateProgress(1, "Importing Assets")
    local colorImageOn   = fmt("3.%d", options.image_pool_offset)
    local colorImageOff  = fmt("3.%d", options.image_pool_offset + 1)
    local buttonImageOn  = fmt("3.%d", options.image_pool_offset + 2)
    local buttonImageOff = fmt("3.%d", options.image_pool_offset + 3)
    local fxDualImageOn  = fmt("3.%d", options.image_pool_offset + 4)
    local fxDualImageOff = fmt("3.%d", options.image_pool_offset + 5)
    local fxGradImageOn  = fmt("3.%d", options.image_pool_offset + 6)
    local fxGradImageOff = fmt("3.%d", options.image_pool_offset + 7)
    importImage(BUTTON_IMAGE_PATH_ON,  "Button ON",  buttonImageOn)
    importImage(BUTTON_IMAGE_PATH_OFF, "Button OFF", buttonImageOff)
    importImage(IMAGE_PATH_ON  .. "_color",  "Color Picker ON",  colorImageOn)
    importImage(IMAGE_PATH_OFF .. "_color",  "Color Picker OFF", colorImageOff)
    importImage(IMAGE_PATH_ON  .. "_dual", "Color Picker Dual ON",  fxDualImageOn)
    importImage(IMAGE_PATH_OFF .. "_dual", "Color Picker Dual OFF", fxDualImageOff)
    importImage(IMAGE_PATH_ON  .. "_gradient", "Color Picker Gradient ON",  fxGradImageOn)
    importImage(IMAGE_PATH_OFF .. "_gradient", "Color Picker Gradient OFF", fxGradImageOff)

    -- Step 2: Extract color presets and groups, generate appearances
    updateProgress(2, "Generating Appearances")
    local colors = extractColorPresets(options.color_preset_offset, options.color_preset_count)
    local groups = extractGroupData(options.group_ids)
    generateAppearances(colors, options.appearance_offset, {
        buttonImageOn = buttonImageOn,
        buttonImageOff = buttonImageOff,
        fxImageOn = colorImageOn,
        fxImageOff = colorImageOff,
        fxDualImageOn = fxDualImageOn,
        fxDualImageOff = fxDualImageOff,
        fxGradImageOn = fxGradImageOn,
        fxGradImageOff = fxGradImageOff,
    })

    -- Step 3: Generate FX color reference presets
    updateProgress(3, "Generating Base/FX Color Presets")
    local fxPresets = generateReferencePresets(options.fx_offset, options.fx_count)
    generateMAtricksObjects(options.matricks_offset, fxPresets)

    -- Step 4: Generate color sequences
    updateProgress(4, "Generating Color Sequences")
    generateColorSequences(groups, colors, options.sequences_offset,
        options.timing_master, options.speed_master, fxPresets)

    -- Step 5: Generate selection macros
    updateProgress(5, "Generating Selection Macros")
    generateMacros(groups, colors, options.macros_offset, fxPresets)

    -- Step 6: Generate main layouts
    updateProgress(6, "Generating Layouts")
    generateLayout(options.layout_offset, groups, colors, fxPresets)

    -- Step 7: Generate settings layout
    updateProgress(7, "Generating Settings Layout")
    generateSettingsLayout(options.layout_offset, options, groups, fxPresets)

    -- Step 8: Activate defaults
    updateProgress(8, "Finishing up")
    activateDefaults(fxPresets)

    StopProgress(progressHandle)
end

-- ============================================================================
-- Plugin Cleanup
-- ============================================================================

local function cleanup()
    if progressHandle then
        StopProgress(progressHandle)
    end
end

return generatePrompt, cleanup