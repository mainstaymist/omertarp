-- A provider for a StormFox-2-SHAPED weather system.
--
-- READ THIS BEFORE CHANGING ANYTHING IN IT.
--
-- The project lead supplied workshop id 1132466603 as the weather system. That
-- id is a fact. Everything else about it — its name, which generation it is,
-- what its Lua API looks like — is an educated guess, because Steam was
-- unreachable from the machine this was written on and nothing here has been
-- verified against the addon itself. StormFox and StormFox 2 are separate,
-- incompatible addons with different globals and different functions, so
-- "probably StormFox" is not enough to build against; there is one of these
-- files per generation and the seam picks between them at runtime.
--
-- The paths in CALLS below are therefore the guesses, gathered in ONE table so
-- that correcting them is a data edit by whoever first gets to read the addon.
-- Nothing else in this file needs to change when they do.
--
-- If they are wrong, nothing breaks: `requires` fails, this provider is not
-- chosen, and the seam falls through to the next candidate and finally to the
-- null provider — a clear day. That is the property that makes it acceptable
-- to ship a guess at all.
--
-- Ranked ABOVE the first-generation provider (priority 20 against 10), and not
-- arbitrarily: a second-generation addon may well keep a compatibility alias
-- under the older global, in which case both providers would detect and the
-- newer, more specific one should win. Preferring the older one would mean
-- talking to a shim instead of to the real API.

Omerta.Environment = Omerta.Environment or {}
local Env = Omerta.Environment

-- Every function this provider intends to call, by path from the global table.
-- Detection is exactly "are these callable" — no name comparison, no version
-- string, no addon id, because we cannot verify any of those and a wrong guess
-- about a name is silently wrong forever where a wrong guess about a function
-- merely fails to match.
local CALLS = {
    -- REQUIRED. A weather system that cannot tell us the time is not one this
    -- provider knows how to talk to, so this is the single gate.
    time = { "StormFox2", "GetTime" },

    -- OPTIONAL, and independently so: each is looked up at the moment it is
    -- asked, and a missing one costs only its own answer. Believed shapes:
    --   IsNight()            -> boolean
    --   Weather.GetCurrent() -> a weather name, or a table naming itself
    night = { "StormFox2", "IsNight" },
    weather = { "StormFox2", "Weather", "GetCurrent" },
}

-- Believed to be minutes since midnight (0–1440). If it turns out to be hours
-- already, this divides a perfectly good number by sixty and the clock reads
-- wrong — so it is worth stating that the reading below is the guess most
-- likely to be silently wrong, rather than absent, and the first thing to
-- check against a real server. Everything else fails loudly-ish by not
-- detecting.
local MINUTES_PER_DAY = 1440

Omerta.Environment.RegisterProvider("stormfox2", {
    priority = 20,
    believed = "a StormFox-2-shaped weather system (workshop 1132466603 — " ..
        "UNVERIFIED: the addon's identity was never confirmed)",
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
        -- Handed through raw. The seam's coercion owns translating whatever
        -- word or self-naming table comes back into this project's six kinds,
        -- so that guess lives in one place for every provider rather than
        -- being re-guessed here.
        return fn()
    end,

    -- No wetness and no darkness on purpose. Both are derivable from what this
    -- provider does answer (wetness from the weather, darkness from the
    -- clock), and inventing a call path for them would be a third and fourth
    -- guess buying nothing that the derivation does not already give. A
    -- provider that can genuinely MEASURE either should add the call here and
    -- the derivation stops being used.
})
