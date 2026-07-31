-- Omerta.Environment — the one place the gamemode asks what the sky is doing.
--
-- The city's weather and time of day come from a Workshop addon chosen by the
-- project lead (D-043; workshop 1132466603). No gamemode code may call that
-- addon directly, and this file is the reason: AT THE TIME IT WAS WRITTEN
-- NOBODY HAD VERIFIED WHAT THAT ADDON IS. It is most likely StormFox — which
-- exists in two mutually incompatible generations with different APIs — and it
-- might be neither of them. Steam was unreachable from the machine this was
-- built on, so the addon's name, its version and its Lua API are all guesses,
-- and none of them is written down anywhere as a fact.
--
-- So this is a provider seam, in the same shape as every other registration
-- seam in the project (Omerta.Injury.RegisterDownedAction,
-- Omerta.Inventory.RegisterContainerAccess, Omerta.HUD.RegisterTargetHint):
-- a registry of small definitions, exactly one of which wins at boot.
--
-- Three rules make the seam correct without knowing what is installed:
--
--   1. A provider is chosen by FEATURE DETECTION — the presence of the exact
--      functions it intends to call, declared as data in its `requires` list.
--      Never a name, never a version string, never a workshop id. A wrong
--      guess about a NAME is silently wrong forever; a wrong guess about a
--      FUNCTION simply fails to detect, which is a state this file already
--      handles correctly. That asymmetry is the whole argument.
--   2. Every answer is optional and every call is wrapped. A provider that
--      wins detection and then errors — because the function took a `self`,
--      or returns something absurd — costs one debug line and the clear-day
--      answer. It cannot take a caller down with it.
--   3. There is always a provider. The null provider is detected
--      unconditionally and answers "a clear day at noon" forever, so a server
--      with no weather addon gets a quieter world rather than an error.
--
-- ADDING A THIRD GENERATION, or a different addon entirely, is ONE NEW FILE in
-- this directory — `sh_provider_<something>.lua`, containing one
-- RegisterProvider call — and NO EDIT ANYWHERE ELSE. Not this file, not
-- sh_module.lua, not any call site. Providers are ordered by their own
-- declared `priority`, so a new one slots in without anybody rewriting a list.
-- That is the property the seam exists to buy, and it is the one to preserve.
--
-- What this file deliberately does NOT contain is any gameplay consequence of
-- weather or darkness. D-043 is explicit that the seam is approved and the
-- consequences are not: whether rain costs a witness their recall, whether
-- night shortens recognition distance, whether a storm moves an NPC indoors
-- are design questions with a review gate in front of them. This answers
-- questions. It does not decide what anybody does about the answers.

Omerta.Environment = Omerta.Environment or {}
local Env = Omerta.Environment

local MODULE = Omerta.Module.Get("environment")

--------------------------------------------------------------------------------
-- The vocabulary
--------------------------------------------------------------------------------
-- Our words, not the addon's. A provider translates whatever its addon says
-- into exactly these six, so a consumer written against this seam keeps working
-- when the thing underneath is swapped for one that calls rain "Rainy", "RAIN",
-- a table, or 3.
--
-- Six kinds, no more. The temptation is to mirror whatever vocabulary the
-- addon happens to have (drizzle, sleet, hail, blizzard…), and it is the wrong
-- instinct twice over: we cannot see that vocabulary to mirror it, and every
-- word added here is a word every future consumer has to have an opinion
-- about. A distinction nothing in the game acts on is not a distinction.

Env.WEATHER = {
    CLEAR = "clear",
    OVERCAST = "overcast",
    RAIN = "rain",
    STORM = "storm",
    SNOW = "snow",
    FOG = "fog",
}

local WEATHER_SET = {}
for _, word in pairs(Env.WEATHER) do WEATHER_SET[word] = true end

-- Words a weather addon might plausibly use for the six kinds above, folded
-- into ours on the way in. This lives here rather than in each provider file
-- for one reason: it is a guess in both places, and a guess is cheaper to
-- correct in one. A word that is not in this table and not one of the six is
-- refused outright — it becomes "no answer", which falls back to clear, rather
-- than becoming a seventh kind of weather nobody wrote a consumer for.
Env.WEATHER_WORDS = {
    sunny = Env.WEATHER.CLEAR,
    clearsky = Env.WEATHER.CLEAR,
    cloudy = Env.WEATHER.OVERCAST,
    clouds = Env.WEATHER.OVERCAST,
    cloud = Env.WEATHER.OVERCAST,
    rainy = Env.WEATHER.RAIN,
    raining = Env.WEATHER.RAIN,
    drizzle = Env.WEATHER.RAIN,
    shower = Env.WEATHER.RAIN,
    showers = Env.WEATHER.RAIN,
    thunder = Env.WEATHER.STORM,
    thunderstorm = Env.WEATHER.STORM,
    lightning = Env.WEATHER.STORM,
    stormy = Env.WEATHER.STORM,
    snowy = Env.WEATHER.SNOW,
    snowing = Env.WEATHER.SNOW,
    snowstorm = Env.WEATHER.SNOW,
    blizzard = Env.WEATHER.SNOW,
    sleet = Env.WEATHER.SNOW,
    hail = Env.WEATHER.SNOW,
    foggy = Env.WEATHER.FOG,
    mist = Env.WEATHER.FOG,
    misty = Env.WEATHER.FOG,
    haze = Env.WEATHER.FOG,
}

-- What "no idea" looks like: noon, clear, dry, bright. This is the answer a
-- server with no weather addon gets forever, and it is also the answer any
-- SINGLE question falls back to when the chosen provider cannot answer that
-- one. Both paths land here, which is why there is one table rather than a
-- scatter of literals.
Env.CLEAR_DAY = {
    timeOfDay = 12,
    isNight = false,
    weather = Env.WEATHER.CLEAR,
    wetness = 0,
    darkness = 0,
}

-- The boundaries of the day, used ONLY to derive an answer a provider did not
-- give: night from a clock, darkness from a clock. They are a reading of the
-- sky and nothing else — no rule in this game fires at eight in the evening,
-- and none may be added here (D-043). A provider that can actually measure the
-- light should say so and these are never consulted.
Env.DAWN, Env.MORNING, Env.EVENING, Env.DUSK = 6, 8, 18, 20

--------------------------------------------------------------------------------
-- Pure readings
--------------------------------------------------------------------------------
-- Arithmetic only, so the headless suite pins the parts that would otherwise
-- only be checkable by standing on a map at nine in the evening.

function Env.NightFromHour(hour)
    hour = tonumber(hour) or Env.CLEAR_DAY.timeOfDay
    return hour < Env.DAWN or hour >= Env.DUSK
end

-- 0 in full daylight, 1 in full night, ramped across the two twilights so a
-- consumer reading this every frame does not see it snap.
function Env.DarknessFromHour(hour)
    hour = tonumber(hour) or Env.CLEAR_DAY.timeOfDay
    if hour < Env.DAWN or hour >= Env.DUSK then return 1 end
    if hour < Env.MORNING then
        return 1 - (hour - Env.DAWN) / (Env.MORNING - Env.DAWN)
    end
    if hour < Env.EVENING then return 0 end
    return (hour - Env.EVENING) / (Env.DUSK - Env.EVENING)
end

-- If the addon has told us it is raining, "is the ground wet" has an obvious
-- answer and there is no reason to make a caller ask twice. Used only when the
-- provider cannot answer wetness itself.
local WETNESS = {
    [Env.WEATHER.CLEAR] = 0,
    [Env.WEATHER.OVERCAST] = 0,
    [Env.WEATHER.FOG] = 0.2,
    [Env.WEATHER.SNOW] = 0.5,
    [Env.WEATHER.RAIN] = 1,
    [Env.WEATHER.STORM] = 1,
}

function Env.WetnessFromWeather(weather)
    return WETNESS[weather] or Env.CLEAR_DAY.wetness
end

-- 21.5 -> "21:30". For the diagnostic command; a decimal hour is the right
-- thing to carry around and the wrong thing to read off a console.
function Env.Clock(hour)
    hour = tonumber(hour) or Env.CLEAR_DAY.timeOfDay
    hour = hour % 24
    local whole = math.floor(hour)
    local minutes = math.floor((hour - whole) * 60 + 0.5)
    if minutes >= 60 then
        minutes = 0
        whole = (whole + 1) % 24
    end
    return string.format("%02d:%02d", whole, minutes)
end

--------------------------------------------------------------------------------
-- Coercion
--------------------------------------------------------------------------------
-- Everything crossing the boundary from an addon we cannot read is untrusted,
-- in exactly the sense a client is untrusted: not malicious, just unknown. A
-- coercer returns a value this seam is willing to publish, or nil for "that
-- was not an answer" — and nil sends the caller to the clear-day fallback
-- rather than out to a consumer as a string where a number was promised.

local COERCE = {
    isNight = function(value)
        if type(value) == "boolean" then return value end
        -- An addon that answers 1/0 is answering; refusing it would be
        -- pedantry. Anything else is not, including "true".
        if type(value) == "number" then return value ~= 0 end
        return nil
    end,

    timeOfDay = function(value)
        if type(value) ~= "number" then return nil end
        -- NaN and both infinities: they survive arithmetic and poison every
        -- comparison downstream, which is the worst possible way for a bad
        -- reading to travel.
        if value ~= value or value == math.huge or value == -math.huge then
            return nil
        end
        -- Wrapped rather than rejected. A provider counting hours past midnight
        -- (25 for 1am) or minutes it forgot to convert is giving a usable
        -- answer in the wrong frame; Lua's modulo is already non-negative for a
        -- positive divisor, so -1 lands on 23 without help.
        return value % 24
    end,

    weather = function(value)
        -- A weather "type" may plausibly arrive as a table describing itself.
        if type(value) == "table" then value = value.Name or value.name end
        if type(value) ~= "string" then return nil end
        -- Trimmed and folded: "Rainy", "rain " and "RAIN" are one answer, and
        -- nothing about which of those an unread addon uses is knowable here.
        value = string.lower((value:gsub("^%s+", ""):gsub("%s+$", "")))
        if WEATHER_SET[value] then return value end
        return Env.WEATHER_WORDS[value]
    end,

    unit = function(value)
        if type(value) ~= "number" then return nil end
        if value ~= value or value == math.huge or value == -math.huge then
            return nil
        end
        return math.max(0, math.min(1, value))
    end,
}

COERCE.wetness = COERCE.unit
COERCE.darkness = COERCE.unit

function Env.Coerce(field, value)
    local fn = COERCE[field]
    if not fn then return nil end
    return fn(value)
end

--------------------------------------------------------------------------------
-- Looking a function up without naming an addon
--------------------------------------------------------------------------------
-- A provider declares the functions it intends to call as PATHS — arrays of
-- keys walked from the global table. That is the only form of "detection" this
-- seam performs, and it is deliberately the weakest claim that is still useful:
-- "the thing I am about to call exists and can be called".
--
-- `root` is threaded through everything instead of being read straight from
-- _G so the headless suite can hand a fake StormFox-shaped table in and get a
-- chosen provider out, with no addon installed and no engine running. Same
-- reason Omerta.Util.ResolveModel takes an injectable validator.

local function callable(value)
    if type(value) == "function" then return true end
    -- Some addon APIs are tables with __call. Cheap to allow, and refusing one
    -- would look exactly like the addon being absent.
    if type(value) == "table" then
        local meta = getmetatable(value)
        return meta ~= nil and meta.__call ~= nil
    end
    return false
end

function Env.Lookup(path, root)
    local node = root or _G
    for _, key in ipairs(path or {}) do
        if type(node) ~= "table" then return nil end
        node = node[key]
        if node == nil then return nil end
    end
    return node
end

-- Cheapest correct check first, and it falls out of the shape rather than
-- needing discipline: the first key of every path is the addon's namespace, so
-- the very first table index decides the common case (nothing installed) and
-- the loop stops. Nothing deeper is touched.
function Env.HasAll(paths, root)
    for _, path in ipairs(paths or {}) do
        if not callable(Env.Lookup(path, root)) then return false end
    end
    return true
end

--------------------------------------------------------------------------------
-- The registry
--------------------------------------------------------------------------------

local providers = {}

-- def:
--   priority  (number, required)  higher wins; the null provider is 0
--   believed  (string, required)  what this speaks to, in the boot log's words.
--                                 Say "believed" and mean it — see the header.
--   requires  (array of paths)    every one must be callable for this to win
--   detect    (function(root))    an extra predicate, ANDed with `requires`
--   always    (true)              detected unconditionally; the null case only
--   isNight / timeOfDay / weather / wetness / darkness
--                                 (function(root)) — each optional, each
--                                 answering in this seam's vocabulary. An
--                                 answer a provider does not define, or cannot
--                                 produce, falls back; it is never an error.
function Env.RegisterProvider(id, def)
    if type(id) ~= "string" or not id:find("^[a-z0-9_%.]+$") then
        error("environment provider '" .. tostring(id) .. "' must be lowercase [a-z0-9_.]", 2)
    end
    if providers[id] then
        error("environment provider '" .. id .. "' registered twice", 2)
    end
    if type(def) ~= "table" then
        error("environment provider '" .. id .. "' needs a definition table", 2)
    end
    if type(def.priority) ~= "number" then
        error("environment provider '" .. id .. "' needs a numeric priority", 2)
    end
    if type(def.believed) ~= "string" or def.believed == "" then
        error("environment provider '" .. id .. "' must say what it is believed " ..
            "to speak to — that line is what the boot log prints", 2)
    end
    -- A provider with no way of being detected and no `always` would either
    -- never win or always win, and which of those it is would depend on a
    -- typo. Make it say.
    if not def.always and not def.requires and not def.detect then
        error("environment provider '" .. id .. "' declares no `requires`, no " ..
            "`detect` and is not `always` — it cannot be chosen deliberately", 2)
    end
    if def.requires ~= nil and type(def.requires) ~= "table" then
        error("environment provider '" .. id .. "' needs `requires` to be a list of paths", 2)
    end
    if def.detect ~= nil and type(def.detect) ~= "function" then
        error("environment provider '" .. id .. "' needs `detect` to be a function", 2)
    end
    for _, field in ipairs({ "isNight", "timeOfDay", "weather", "wetness", "darkness" }) do
        if def[field] ~= nil and type(def[field]) ~= "function" then
            error("environment provider '" .. id .. "' needs " .. field .. " to be a function", 2)
        end
    end

    def.id = id
    providers[id] = def
    return def
end

function Env.GetProvider(id) return providers[id] end

-- In preference order: priority descending, then id, so two providers at the
-- same priority resolve the same way on every boot and on every machine.
function Env.Providers()
    local out = {}
    for _, def in pairs(providers) do out[#out + 1] = def end
    table.sort(out, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.id < b.id
    end)
    return out
end

function Env.Detect(def, root)
    if type(def) ~= "table" then return false end
    if def.always then return true end
    if def.requires and not Env.HasAll(def.requires, root) then return false end
    if def.detect then
        -- A detector that errors has answered: it is not present. Anything
        -- else would let a broken guess about one addon stop a working guess
        -- about another from ever being reached.
        local ok, yes = pcall(def.detect, root)
        if not ok then
            Omerta.Log.Debug("environment", "provider '%s' errored while " ..
                "detecting (%s) — treated as absent", tostring(def.id), tostring(yes))
            return false
        end
        return yes == true
    end
    return def.requires ~= nil
end

-- Pure: a list of provider definitions and a root table in, the chosen
-- definition out (or nil, if a caller passes a list with no null provider in
-- it). Sorting a copy rather than trusting the caller's order means the tests
-- can hand this any order at all and pin the same answer.
function Env.Choose(list, root)
    local ordered = {}
    for index, def in ipairs(list or {}) do ordered[index] = def end
    table.sort(ordered, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.id < b.id
    end)
    for _, def in ipairs(ordered) do
        if Env.Detect(def, root) then return def end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Which one won
--------------------------------------------------------------------------------

local root = _G
local selected = nil -- nil = not resolved yet, false = resolved to nothing
local announced = false
local complained = {}

-- For the headless suite (and for a future in-engine self-test): substitute
-- the table providers look their functions up in, so a StormFox-shaped world
-- can be conjured and taken away again without one being installed. Passing
-- nothing puts it back to _G. The selection is dropped either way — it was
-- made against a world that no longer applies.
function Env.UseRoot(where)
    root = where or _G
    Env.Forget()
end

function Env.Forget()
    selected = nil
    announced = false
    complained = {}
end

function Env.Select()
    selected = Env.Choose(Env.Providers(), root) or false
    return selected or nil
end

function Env.Selected()
    if selected == nil then Env.Select() end
    return selected or nil
end

function Env.ProviderId()
    local def = Env.Selected()
    return def and def.id or "none"
end

--------------------------------------------------------------------------------
-- The public read API
--------------------------------------------------------------------------------
-- These five ALWAYS answer. Whichever provider won, or none at all, a caller
-- gets a value of the promised type and never an error — which is what makes
-- it safe for gameplay code to read them without checking anything first.

local function ask(field)
    local def = Env.Selected()
    if not def or not def[field] then return nil end

    local ok, value = pcall(def[field], root)
    if not ok then
        -- Once per provider per field. These are read from Think loops; a
        -- provider whose function signature we guessed wrong would otherwise
        -- print sixty-six lines a second and bury everything else in the log.
        local key = def.id .. "." .. field
        if not complained[key] then
            complained[key] = true
            Omerta.Log.Debug("environment",
                "provider '%s' failed answering %s (%s) — falling back to the " ..
                "clear-day answer for it from here on", def.id, field, tostring(value))
        end
        return nil
    end

    return Env.Coerce(field, value)
end

function Env.TimeOfDay()
    local hour = ask("timeOfDay")
    if hour ~= nil then return hour end
    return Env.CLEAR_DAY.timeOfDay
end

function Env.IsNight()
    local night = ask("isNight")
    if night ~= nil then return night end
    -- Derived rather than assumed false: a provider that gives a clock and no
    -- night predicate still knows perfectly well that it is dark at three in
    -- the morning.
    return Env.NightFromHour(Env.TimeOfDay())
end

function Env.Weather()
    local weather = ask("weather")
    if weather ~= nil then return weather end
    return Env.CLEAR_DAY.weather
end

function Env.Wetness()
    local wet = ask("wetness")
    if wet ~= nil then return wet end
    return Env.WetnessFromWeather(Env.Weather())
end

function Env.Darkness()
    local dark = ask("darkness")
    if dark ~= nil then return dark end
    return Env.DarknessFromHour(Env.TimeOfDay())
end

--------------------------------------------------------------------------------
-- Saying so
--------------------------------------------------------------------------------

-- `map` is a parameter rather than a call so the whole report is exercisable
-- headlessly. In the engine the caller passes nothing and gets game.GetMap().
function Env.Report(map)
    local def = Env.Selected()
    local hour = Env.TimeOfDay()
    local lines = {
        string.format("provider   %s", def and def.id or "(none)"),
        string.format("believed   %s", def and def.believed or "(nothing registered)"),
        string.format("time       %.2f  (%s)", hour, Env.Clock(hour)),
        string.format("night      %s", Env.IsNight() and "yes" or "no"),
        string.format("weather    %s", Env.Weather()),
        string.format("wetness    %.2f", Env.Wetness()),
        string.format("darkness   %.2f", Env.Darkness()),
        string.format("map        %s", map or (Omerta.InEngine and game.GetMap()) or "(headless)"),
        "considered:",
    }
    -- Every candidate and whether its functions are actually there. This is
    -- the line that answers "why is the weather not doing anything" without
    -- anybody reading source.
    for _, candidate in ipairs(Env.Providers()) do
        lines[#lines + 1] = string.format("  %-12s priority %-4d %s",
            candidate.id, candidate.priority,
            Env.Detect(candidate, root) and "present" or "not present")
    end
    return lines
end

function Env.Boot()
    Env.Select()

    if not announced then
        announced = true
        local def = Env.Selected()
        if def then
            Omerta.Log.Info("environment", "weather/time provider: %s — %s",
                def.id, def.believed)
        else
            -- Only reachable if somebody deletes sh_provider_null.lua, which
            -- is worth a line rather than a silence.
            Omerta.Log.Info("environment", "weather/time provider: none — " ..
                "every reading will be a clear day at noon")
        end
    end

    if Omerta.InEngine then
        -- The map name, on the record, once. The server's map is set by
        -- server config (changelevel / server.cfg) and a gamemode cannot and
        -- should not choose it — but the gamemode is the only thing here that
        -- can READ it back, and at the time this was written the filename of
        -- the lead's map (workshop 1656078410) was not known to this
        -- repository. This line is how it becomes known.
        Omerta.Log.Info("environment", "map: %s", game.GetMap())
    end
end

--------------------------------------------------------------------------------
-- Boot
--------------------------------------------------------------------------------
-- One lifecycle method for the whole module, in one file. Both realm files
-- expose a function instead of a second OnEnable, because MODULE is a single
-- shared table and a later file defining the same method REPLACES the earlier
-- one silently — the incident sv_help.lua carries the scar tissue for, and a
-- lint test now fails the suite over.

function MODULE:OnEnable()
    -- Server-only, and reached through the function rather than realm checks
    -- scattered here: sv_content.lua is not included on a client at all.
    if SERVER and Omerta.Environment.MountContent then
        Omerta.Environment.MountContent()
    end

    Omerta.Environment.Boot()

    -- The front end's vantage registry lives on the client and is filled from
    -- here rather than by depending on `menu` — see sh_module.lua.
    if CLIENT and Omerta.Environment.RegisterVantages then
        Omerta.Environment.RegisterVantages()
    end
end

-- A Lua auto-refresh rebuilds every registry, so the chosen provider has to be
-- chosen again — otherwise a developer who just installed the weather addon
-- and refreshed would still be looking at a clear day.
function MODULE:OnReload()
    Omerta.Environment.Forget()
    Omerta.Environment.Boot()
end

if Omerta.InEngine then
    -- The addon may not exist yet when we boot.
    --
    -- Our OnEnable runs from GM:Initialize. An addon is free to build its API
    -- later — in its own InitPostEntity, or after the map's entities exist —
    -- and we have no way to find out which, because we cannot read it. So the
    -- choice is made again once the map is fully up, and a change is logged.
    -- Detection is a handful of table lookups; doing it twice costs nothing
    -- and removes a whole class of "it works on my listen server" report.
    hook.Add("InitPostEntity", "omerta.environment.recheck", function()
        local before = Omerta.Environment.Selected()
        Omerta.Environment.Select()
        local after = Omerta.Environment.Selected()
        if after ~= before then
            Omerta.Log.Info("environment",
                "weather/time provider changed once the map was up: %s — %s",
                after and after.id or "none",
                after and after.believed or "(nothing registered)")
        end
    end)

    -- Superadmin-gated on the server, exactly as omerta_whoami and omerta_help
    -- are, because it reports server state into the server's console.
    --
    -- NOT gated on a client, and that is deliberate rather than an oversight:
    -- run from a client console it reports only what that machine already
    -- believes about its own sky, which is not privileged, and the client is
    -- the realm where a weather addon actually renders anything. Gating there
    -- would hide the answer from the only person who can see the sky it
    -- describes.
    concommand.Add("omerta_env", function(caller)
        if SERVER and IsValid(caller) and not caller:IsSuperAdmin() then return end
        for _, line in ipairs(Omerta.Environment.Report()) do
            Omerta.Log.Info("environment", "%s", line)
        end
    end)
end
