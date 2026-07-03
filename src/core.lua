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
Self.Data = {}

function Self.InitState(options)
    -- Import globally used images
    local imagesOffset = options and options.imagesOffset or Self.Preferences.Offset
    Self.Data.Images = BuskingTools.Util.ImportImages({
        { id = "ButtonOff", path = "busking_tools_button_off.png", label = "BuskingTools Button OFF" },
        { id = "ButtonOn",  path = "busking_tools_button_on.png",  label = "BuskingTools Button ON"  }
    }, imagesOffset)
end

-- ============================================================================
-- Core builtins
-- ============================================================================
function Fmt(...)
    return string.format(...)
end

function Panic(reason)
    -- TODO: Figure out a better way to stop plugin execution
    ErrEcho("BuskingTools plugin have failed: " .. reason .. "\nHalting execution by running bad command")
    Cmd("BadCommandToHaltExecution PanicHandler")
end

-- ============================================================================
-- Cleanup logic
-- ============================================================================
Self._CleanupActions = {}

function Self.RegisterCleanupHandler(handler)
   table.insert(Self._CleanupActions, handler)
end

function Self.Cleanup()
    for _, action in ipairs(Self._CleanupActions) do
        action()
    end
end

-- ============================================================================
-- Main plugin function
-- ============================================================================
function Main(displayHandle, args)
    Printf("BuskingTools: Core loaded")
    Self.InitState()
end

return Main, Self.Cleanup