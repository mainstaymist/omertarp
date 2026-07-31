-- A provider for a FIRST-GENERATION StormFox-SHAPED weather system.
--
-- The sibling file sh_provider_stormfox2.lua carries the full explanation of
-- why there are two of these and why every path below is a guess rather than a
-- fact; read it there rather than having it restated wrongly here. The short
-- version: workshop id 1132466603 is the only verified thing about the addon,
-- the two StormFox generations are incompatible, Steam was unreachable, and a
-- guess that fails detection costs a clear day rather than an error.
--
-- Ranked BELOW the second-generation provider (priority 10 against 20) so that
-- a newer addon shipping a compatibility alias under the older global does not
-- win this file by accident.

Omerta.Environment = Omerta.Environment or {}
local Env = Omerta.Environment

local CALLS = {
    -- REQUIRED.
    time = { "StormFox", "GetTime" },

    -- OPTIONAL, independently.
    night = { "StormFox", "IsNight" },
    weather = { "StormFox", "GetWeather" },
}

-- Believed to be minutes since midnight, as with the second generation.
local MINUTES_PER_DAY = 1440

Omerta.Environment.RegisterProvider("stormfox1", {
    priority = 10,
    believed = "a first-generation StormFox-shaped weather system " ..
        "(workshop 1132466603 — UNVERIFIED: the addon's identity was never confirmed)",
    requires = { CALLS.time },

    timeOfDay = function(root)
        local fn = Env.Lookup(CALLS.time, root)
        if not fn then return nil end
        local minutes = fn()
        if type(minutes) ~= "number" then return nil end
        return (minutes / MINUTES_PER_DAY) * 24
    end,

    isNight = function(root)
        local fn = Env.Lookup(CALLS.night, root)
        if not fn then return nil end
        return fn()
    end,

    weather = function(root)
        local fn = Env.Lookup(CALLS.weather, root)
        if not fn then return nil end
        return fn()
    end,
})
