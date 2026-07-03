-- Shared namespace table for the whole plugin.
-- All components attach their public functions here so they can call
-- each other without needing `require`. Because grandMA3 loads every
-- installed component of a plugin at import/reload time, this table is
-- guaranteed to be populated before any component's Main() runs.
BuskingTools = BuskingTools or {}
BuskingTools.Core = BuskingTools.Core or {}

function Main(display_handle, args)
    Printf("BuskingTools: Core loaded")
    BuskingTools.Util.Greet()
end

return Main