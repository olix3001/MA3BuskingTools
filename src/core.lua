-- Shared namespace table for the whole plugin.
-- All components attach their public functions here so they can call
-- each other without needing `require`. Because grandMA3 loads every
-- installed component of a plugin at import/reload time, this table is
-- guaranteed to be populated before any component's Main() runs.
BuskingTools = BuskingTools or {}
BuskingTools.Core = BuskingTools.Core or {}

local Self = BuskingTools.Core

-- ============================================================================
-- Configuration
-- ============================================================================
Self.Preferences = Self.Preferences or {
    Offset = 7001,
}

-- ============================================================================
-- Globals and initialization
-- ============================================================================
Self.Data = Self.Data or {}

function Self.InitState(options)
    -- Import globally used images
    local imagesOffset = options and options.imagesOffset or Self.Preferences.Offset
    Self.Data.Images = BuskingTools.Util.ImportImages({
        { id = "ButtonOff", path = "busking_tools_button_off.png", label = "BT Button OFF" },
        { id = "ButtonOn",  path = "busking_tools_button_on.png",  label = "BT Button ON"  }
    }, imagesOffset)

    -- Generate appearances for buttons
    local appearancesOffset = (options and options.appearancesOffset or BuskingTools.Core.Preferences.Offset)
    BuskingTools.Util.BuildAppearance(appearancesOffset,     "BT Button OFF", Self.Data.Images.ButtonOff)
    BuskingTools.Util.BuildAppearance(appearancesOffset + 1, "BT Button ON",  Self.Data.Images.ButtonOn )
    Self.Data.Button = { OffAppearance = appearancesOffset, OnAppearance = appearancesOffset + 1 }
end

-- ============================================================================
-- Core builtins
-- ============================================================================
function Fmt(...)
    return string.format(...)
end

function Panic(reason)
    -- TODO: Figure out a better way to stop plugin execution
    ErrEcho("BuskingTools plugin have failed: " .. reason .. "\nHalting execution by running bad command.")
    Cmd("BadCommandToHaltExecution PanicHandler")
end

-- ============================================================================
-- Cleanup logic
-- ============================================================================
Self._CleanupActions = {}

function Self.RegisterCleanupHandler(handler)
   table.insert(Self._CleanupActions, handler)
end

function Self.Warn(message)
    Self.RegisterCleanupHandler(function()
        ErrEcho(Fmt("Warning: %s", message))
    end)
end

function Self.Cleanup()
    for _, action in ipairs(Self._CleanupActions) do
        action()
    end
end

-- ============================================================================
-- Main plugin function
-- ============================================================================
local function main(displayHandle, args)
    Printf("BuskingTools: Core loaded")
    Self.InitState()
end

return main, Self.Cleanup