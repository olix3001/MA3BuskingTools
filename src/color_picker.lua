BuskingTools = BuskingTools or {}
BuskingTools.ColorPicker = BuskingTools.ColorPicker or {}

local Self = BuskingTools.ColorPicker
local Util = BuskingTools.Util

local OFFSET = 700

-- ============================================================================
-- Globals and initialization
-- ============================================================================
Self.Data = Self.Data or {}

function Self.InitState(options)
    -- Import image picker images
    local imagesOffset = (options and options.imagesOffset or BuskingTools.Core.Preferences.Offset) + OFFSET
    Self.Data.Images = BuskingTools.Util.ImportImages({
        { id = "ColorOff",    path = "busking_tools_off_color.png",    label = "BT Color Picker Solid OFF" },
        { id = "ColorOn",     path = "busking_tools_on_color.png",     label = "BT Color Picker Solid ON" },
        { id = "DualOff",     path = "busking_tools_off_dual.png",     label = "BT Color Picker Dual OFF" },
        { id = "DualOn",      path = "busking_tools_on_dual.png",      label = "BT Color Picker Dual ON" },
        { id = "GradientOff", path = "busking_tools_off_gradient.png", label = "BT Color Picker Gradient OFF" },
        { id = "GradientOn",  path = "busking_tools_on_gradient.png",  label = "BT Color Picker Gradient ON" },
    }, imagesOffset)
end

-- ============================================================================
-- Data extraction
-- ============================================================================

-- ============================================================================
-- Object generation
-- ============================================================================
function Self.GenerateColorSelectorAppearances(colors, options, offset)
    local appearancesOffset = (options and options.appearancesOffset or BuskingTools.Core.Preferences.Offset) + OFFSET + (offset or 0)

    for i, color in ipairs(colors) do
        local offId = appearancesOffset + i - 1
        local onId = appearancesOffset + i - 1 + #colors

        Util.BuildAppearance(
            offId,
            Fmt("BT Color %s@%d OFF", color.name, color.id),
            Self.Data.Images.ColorOff,
            color.color
        )

        Util.BuildAppearance(
            onId,
            Fmt("BT Color %s@%d ON", color.name, color.id),
            Self.Data.Images.ColorOn,
            color.color
        )

        color.appearances = {
            off = offId,
            on = onId
        }
    end
end

-- ============================================================================
-- Palette generation
-- ============================================================================
function Self.GeneratePalette(options)
    BuskingTools.Core.InitState(options)
    Self.InitState(options)

    local progress = Util.StartProgress("Color Palette Generation")

    progress:Next("Fetching Color Preset Data")
    -- Color data extraction. This returns { [<id>] = { id = <id>, name = <name>, color = <color> }, ... }
    local colors = Util.ExtractPresets(
        DataPool().PresetPools[4],
        table.range(options.colorOffset, options.colorOffset + options.colorCount - 1),
        function(preset)
            return { color = Util.ExtractPresetColor(preset) }
        end
    )

    progress:Next("Generating Color Button Appearances")
    Self.GenerateColorSelectorAppearances(colors, options)

    progress:Stop()
end

-- ============================================================================
-- Main function with generation message box
-- ============================================================================
local function main()
    Self.GeneratePalette({
        colorOffset = 1,
        colorCount = 11,
    })
end

return main, BuskingTools.Core.Cleanup

