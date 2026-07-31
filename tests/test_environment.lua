-- The weather/time seam (D-043).
--
-- This is the module whose correctness is hardest to establish by playing the
-- game, because the thing it talks to could not be obtained: the addon behind
-- workshop 1132466603 was never verified, so nothing here has ever been run
-- against the real API. What CAN be established, and is, is that the seam
-- behaves correctly for every shape the unknown might turn out to have —
-- present, absent, half-present, present and lying.
--
-- Everything below runs against a FAKE global table handed to the seam through
-- UseRoot, so a StormFox-shaped world can be conjured and taken away again
-- inside one check.

local MODULE_FILES = {
    "gamemodes/omertarp/gamemode/modules/environment/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/environment/sh_environment.lua",
    "gamemodes/omertarp/gamemode/modules/environment/sh_provider_null.lua",
    "gamemodes/omertarp/gamemode/modules/environment/sh_provider_stormfox1.lua",
    "gamemodes/omertarp/gamemode/modules/environment/sh_provider_stormfox2.lua",
    "gamemodes/omertarp/gamemode/modules/environment/sv_content.lua",
}

local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
    Omerta.Module.FinishLoading()
end

-- A world with a second-generation-shaped weather system in it.
local function stormfox2World(overrides)
    overrides = overrides or {}
    return {
        StormFox2 = {
            GetTime = overrides.GetTime or function() return 21 * 60 end,
            IsNight = overrides.IsNight or function() return true end,
            Weather = { GetCurrent = overrides.GetCurrent or function() return "Rainy" end },
        },
    }
end

-- ...and one with a first-generation-shaped one.
local function stormfox1World()
    return {
        StormFox = {
            GetTime = function() return 9 * 60 end,
            IsNight = function() return false end,
            GetWeather = function() return "Clear" end,
        },
    }
end

--------------------------------------------------------------------------------
suite("environment.detection")
--------------------------------------------------------------------------------

check("a provider is found by the functions it means to call, not by a name", function()
    loadModules()
    local Env = Omerta.Environment

    -- The addon's own name never appears in a comparison, so a world carrying
    -- the right functions under the right namespace is enough, and a world
    -- carrying the NAME and nothing callable is not.
    assert(Env.Choose(Env.Providers(), stormfox2World()).id == "stormfox2")
    assert(Env.Choose(Env.Providers(), stormfox1World()).id == "stormfox1")

    local pretender = { StormFox2 = { Version = "2.0", Name = "StormFox 2" } }
    assert(Env.Choose(Env.Providers(), pretender).id == "null",
        "a namespace with no callable functions in it is not a weather system")

    -- A half-present API: the namespace is there, the required call is not.
    local half = { StormFox2 = { IsNight = function() return true end } }
    assert(Env.Choose(Env.Providers(), half).id == "null",
        "the required call is required")
end)

check("nothing installed selects the null provider", function()
    loadModules()
    local Env = Omerta.Environment
    local chosen = Env.Choose(Env.Providers(), {})
    assert(chosen and chosen.id == "null", "there is always a provider")
    assert(chosen.believed:find("clear day"), "and it says what it is")
end)

check("the newer generation outranks the older when both answer", function()
    loadModules()
    local Env = Omerta.Environment

    -- The case this ordering exists for: a second-generation addon shipping a
    -- compatibility alias under the first generation's global. Both detect;
    -- the specific one must win, or the gamemode spends the season talking to
    -- a shim.
    local both = stormfox2World()
    both.StormFox = stormfox1World().StormFox
    assert(Env.Choose(Env.Providers(), both).id == "stormfox2")
end)

check("selection is by declared priority, so a third generation is one new file", function()
    loadModules()
    local Env = Omerta.Environment

    -- The promise D-043 makes: supporting a different addon entirely is one
    -- RegisterProvider call and no edit anywhere else. Pinned by doing exactly
    -- that and nothing else.
    Env.RegisterProvider("something_else", {
        priority = 99,
        believed = "a third thing nobody has seen either",
        requires = { { "TheOtherOne", "WhatTimeIsIt" } },
        timeOfDay = function() return 3 end,
    })

    local world = { TheOtherOne = { WhatTimeIsIt = function() return 3 end } }
    assert(Env.Choose(Env.Providers(), world).id == "something_else")
    -- ...and it does not disturb the ones already there.
    assert(Env.Choose(Env.Providers(), stormfox2World()).id == "stormfox2")
    assert(Env.Choose(Env.Providers(), {}).id == "null")
end)

check("a detector that errors is treated as absent, not as fatal", function()
    loadModules()
    local Env = Omerta.Environment
    Env.RegisterProvider("explodes", {
        priority = 50,
        believed = "a provider whose detector is broken",
        detect = function() error("boom") end,
    })
    -- One bad guess about one addon must not stop a good guess about another
    -- from being reached.
    assert(Env.Choose(Env.Providers(), stormfox2World()).id == "stormfox2")
    assert(Env.Choose(Env.Providers(), {}).id == "null")
end)

check("a callable table counts as a function", function()
    loadModules()
    local Env = Omerta.Environment
    local fake = setmetatable({}, { __call = function() return 600 end })
    assert(Env.HasAll({ { "A", "B" } }, { A = { B = fake } }), "callable tables are callable")
    assert(not Env.HasAll({ { "A", "B" } }, { A = { B = 4 } }), "a number is not")
    assert(not Env.HasAll({ { "A", "B" } }, {}), "and absence is absence")
    -- Walking through a non-table must answer "no", not throw.
    assert(Env.Lookup({ "A", "B", "C" }, { A = { B = 4 } }) == nil)
end)

check("a provider must declare how it is to be found", function()
    loadModules()
    local Env = Omerta.Environment
    local ok = { priority = 1, believed = "x", requires = {} }

    assert(not pcall(Env.RegisterProvider, "Bad Id", ok), "ids are lowercase")
    assert(not pcall(Env.RegisterProvider, "null", ok), "and registered once")
    assert(not pcall(Env.RegisterProvider, "a", { believed = "x", requires = {} }),
        "priority decides the order and is not optional")
    assert(not pcall(Env.RegisterProvider, "b", { priority = 1, requires = {} }),
        "the boot log needs something to print")
    assert(not pcall(Env.RegisterProvider, "c", { priority = 1, believed = "x" }),
        "a provider with no requires, no detect and no always cannot be chosen deliberately")
    assert(not pcall(Env.RegisterProvider, "d",
        { priority = 1, believed = "x", always = true, weather = "clear" }),
        "an answer is a function")
end)

--------------------------------------------------------------------------------
suite("environment.readings")
--------------------------------------------------------------------------------

check("a missing addon degrades to a clear day, and never errors", function()
    loadModules()
    local Env = Omerta.Environment
    Env.UseRoot({}) -- an empty world: no weather system of any kind

    assert(Env.ProviderId() == "null")
    assert(Env.TimeOfDay() == 12, "noon")
    assert(Env.IsNight() == false, "and daylight")
    assert(Env.Weather() == "clear")
    assert(Env.Wetness() == 0, "dry")
    assert(Env.Darkness() == 0, "and bright")

    -- The point of the seam, stated as an assertion: every reading answers
    -- with the promised type whether or not anything is installed.
    assert(type(Env.TimeOfDay()) == "number")
    assert(type(Env.IsNight()) == "boolean")
    assert(type(Env.Weather()) == "string")
    assert(type(Env.Wetness()) == "number")
    assert(type(Env.Darkness()) == "number")
end)

check("a detected provider is actually read", function()
    loadModules()
    local Env = Omerta.Environment
    Env.UseRoot(stormfox2World())

    assert(Env.ProviderId() == "stormfox2")
    assert(math.abs(Env.TimeOfDay() - 21) < 0.001, "minutes since midnight become hours")
    assert(Env.IsNight() == true)
    assert(Env.Weather() == "rain", "the addon's word, folded into ours")
    assert(Env.Wetness() == 1, "rain implies a wet street")
    assert(Env.Darkness() == 1, "and nine in the evening implies a dark one")
end)

check("an answer the provider cannot give falls back on its own", function()
    loadModules()
    local Env = Omerta.Environment
    -- A world with the required call and NOTHING else — the half-right guess,
    -- which is the likeliest way to be wrong about an addon nobody has read.
    Env.UseRoot({ StormFox2 = { GetTime = function() return 3 * 60 end } })

    assert(Env.ProviderId() == "stormfox2", "the time is enough to be worth talking to")
    assert(math.abs(Env.TimeOfDay() - 3) < 0.001, "and the time is right")
    assert(Env.IsNight() == true, "night derived from the clock it did give")
    assert(Env.Weather() == "clear", "weather it cannot give is a clear sky")
    assert(Env.Wetness() == 0)
end)

check("a provider that errors mid-answer costs that answer and nothing else", function()
    loadModules()
    local Env = Omerta.Environment
    Env.UseRoot(stormfox2World({
        -- The exact failure a wrong guess about a signature produces: the
        -- function exists, so detection passes, and calling it throws.
        GetCurrent = function() error("expected self") end,
    }))

    assert(Env.ProviderId() == "stormfox2")
    assert(Env.Weather() == "clear", "the broken answer degrades")
    assert(math.abs(Env.TimeOfDay() - 21) < 0.001, "the working ones do not")
    assert(Env.IsNight() == true)
end)

check("an absurd answer is refused rather than published", function()
    loadModules()
    local Env = Omerta.Environment

    -- Everything crossing in from an addon nobody has read is untrusted in the
    -- same sense a client is: not malicious, just unknown.
    assert(Env.Coerce("timeOfDay", "half past ten") == nil, "a string is not a clock")
    assert(Env.Coerce("timeOfDay", 0 / 0) == nil, "NaN poisons every comparison downstream")
    assert(Env.Coerce("timeOfDay", math.huge) == nil)
    assert(math.abs(Env.Coerce("timeOfDay", 26) - 2) < 0.001, "past midnight wraps")
    assert(math.abs(Env.Coerce("timeOfDay", -1) - 23) < 0.001, "and so does before it")

    assert(Env.Coerce("weather", "hurricane") == nil, "a seventh weather is not adopted")
    assert(Env.Coerce("weather", " Thunderstorm ") == "storm", "case and space are noise")
    assert(Env.Coerce("weather", { Name = "Foggy" }) == "fog", "a type may name itself")
    assert(Env.Coerce("weather", 3) == nil)

    assert(Env.Coerce("isNight", 1) == true, "1/0 is an answer")
    assert(Env.Coerce("isNight", 0) == false)
    assert(Env.Coerce("isNight", "true") == nil, "the word is not")

    assert(Env.Coerce("wetness", 5) == 1, "clamped into the unit range")
    assert(Env.Coerce("darkness", -2) == 0)
    assert(Env.Coerce("wetness", nil) == nil)

    -- And the whole chain: a provider handing out nonsense reads as a clear day.
    Env.UseRoot(stormfox2World({
        GetTime = function() return "elevenish" end,
        IsNight = function() return "yes" end,
        GetCurrent = function() return 7 end,
    }))
    assert(Env.ProviderId() == "stormfox2")
    assert(Env.TimeOfDay() == 12 and Env.IsNight() == false and Env.Weather() == "clear")
end)

check("the derived readings are a reading of the sky and nothing more", function()
    loadModules()
    local Env = Omerta.Environment

    assert(Env.NightFromHour(3) and Env.NightFromHour(23), "small hours and late ones")
    assert(not Env.NightFromHour(12) and not Env.NightFromHour(Env.MORNING))
    -- The two agree at the boundaries: full dark is exactly night.
    assert(Env.DarknessFromHour(3) == 1 and Env.DarknessFromHour(12) == 0)
    assert(Env.DarknessFromHour(Env.DAWN) == 1 and Env.DarknessFromHour(Env.MORNING) == 0)
    assert(Env.DarknessFromHour(Env.EVENING) == 0 and Env.DarknessFromHour(Env.DUSK) == 1)
    -- Ramped, so a consumer reading it every frame does not see it snap.
    local half = Env.DarknessFromHour((Env.EVENING + Env.DUSK) / 2)
    assert(half > 0 and half < 1, "twilight is not a switch")

    assert(Env.WetnessFromWeather("rain") == 1 and Env.WetnessFromWeather("storm") == 1)
    assert(Env.WetnessFromWeather("clear") == 0)
    assert(Env.WetnessFromWeather("nonsense") == 0, "an unknown sky is not raining")

    assert(Env.Clock(21.5) == "21:30" and Env.Clock(0) == "00:00")
    assert(Env.Clock(23.999) == "00:00", "a rounded minute rolls the hour, not to 24:00")
end)

--------------------------------------------------------------------------------
suite("environment.boot")
--------------------------------------------------------------------------------

check("the boot chooses once and says which", function()
    loadModules()
    local Env = Omerta.Environment

    Env.UseRoot(stormfox1World())
    Omerta.Module.EnableAll() -- the module's own OnEnable
    assert(Env.ProviderId() == "stormfox1")

    -- Forgetting is what a Lua refresh does, and it must re-choose against the
    -- world as it is NOW — a developer who has just installed the addon and
    -- refreshed should not still be looking at a clear day.
    Env.UseRoot({})
    assert(Env.ProviderId() == "null")
end)

check("the report names the provider, the sky and the map", function()
    loadModules()
    local Env = Omerta.Environment
    Env.UseRoot(stormfox2World())

    local text = table.concat(Env.Report("some_map"), "\n")
    assert(text:find("stormfox2", 1, true), "which provider")
    assert(text:find("UNVERIFIED", 1, true), "and that we are guessing about it")
    assert(text:find("21:00", 1, true), "the time")
    assert(text:find("night      yes", 1, true), "whether it is night")
    assert(text:find("weather    rain", 1, true), "the weather")
    assert(text:find("some_map", 1, true), "and the map, which is the whole point")

    -- Every candidate and whether it is actually there: the line that answers
    -- "why is the weather doing nothing" without anybody reading source.
    assert(text:find("stormfox1", 1, true) and text:find("not present", 1, true))
    assert(text:find("null", 1, true))
end)

--------------------------------------------------------------------------------
suite("environment.content")
--------------------------------------------------------------------------------

check("both workshop items are declared, and both admit they are unverified", function()
    loadModules()
    local items = Omerta.Environment.WORKSHOP
    assert(#items == 2, "one table, both items")

    local ids = {}
    for _, item in ipairs(items) do
        -- A workshop id is the only verifiable thing we were given, so it is
        -- the only thing held as data. Strings, because that is what
        -- resource.AddWorkshop takes.
        assert(type(item.id) == "string" and item.id:find("^%d+$"), "an id is digits")
        assert(type(item.believed) == "string" and item.believed ~= "",
            "and is described as a belief, never as a name")
        assert(type(item.unverified) == "string" and item.unverified ~= "",
            item.id .. " must say what about it is unconfirmed")
        ids[item.id] = true
    end

    assert(ids["1656078410"], "the map the lead supplied")
    assert(ids["1132466603"], "the weather system the lead supplied")
end)

check("no guessed map filename is written down anywhere", function()
    -- The rule this module exists to keep: a workshop id is exact, a filename
    -- is not, and a wrong filename is a row that silently never matches. If
    -- somebody adds a vantage keyed by a guess, this fails.
    local handle = io.open("gamemodes/omertarp/gamemode/modules/environment/cl_vantage.lua", "r")
    assert(handle, "cl_vantage.lua is missing")
    local source = handle:read("*a")
    handle:close()

    local vantages = source:match("local VANTAGES = {(.-)\n}")
    assert(vantages, "the vantage table should still be one findable data block")
    for line in vantages:gmatch("[^\n]+") do
        local code = line:gsub("%-%-.*$", "")
        assert(not code:find("%["), "a vantage key appeared: " .. line ..
            " — is that filename verified, or a guess?")
    end
end)
