-- The event record: the durable, referenceable fact that something happened.
--
-- Review improvement #1 proposed this as a formal core service rather than a
-- detail of whichever milestone happened to need it first, on the grounds that
-- "deaths, funerals, promotions, and openings also need EventIDs". M20 is the
-- milestone that first genuinely needs one, so M20 builds it (D-038) and M14
-- consumes it rather than the reverse.
--
-- An event is a FACT, not a notification. Nothing here is ever pushed to a
-- client. It exists so that M21 can find out a man was shot and print it, M22
-- can keep it, M15 can hang evidence off it and M17 can build a case around
-- it — all of which are ways the city finds things out, and none of which is
-- a message appearing on somebody's screen (§4a, GDD §6).

Omerta.Events = Omerta.Events or {}
Omerta.Events.Internal = Omerta.Events.Internal or {}

local types = {}

--------------------------------------------------------------------------------
-- The type registry
--------------------------------------------------------------------------------
-- Declared rather than stringly-invented at the call site. An event type that
-- nobody registered is a typo that would otherwise sit in the database
-- forever, unfindable by the milestone that meant to read it.

-- `public` is the one flag that matters here: whether this is the kind of
-- thing that could ever reach a newspaper. It is NOT a decision about whether
-- any particular event is printable — M21 owns that, because it depends on who
-- witnessed what. It only says the type is eligible at all.
function Omerta.Events.Register(id, def)
    if type(id) ~= "string" or not id:find("^[a-z0-9_%.]+$") then
        error("event type '" .. tostring(id) .. "' must be lowercase [a-z0-9_.]", 2)
    end
    if types[id] then error("event type '" .. id .. "' registered twice", 2) end
    if type(def) ~= "table" or type(def.name) ~= "string" or def.name == "" then
        error("event type '" .. id .. "' needs a name", 2)
    end
    def.id = id
    def.public = def.public == true
    types[id] = def
    return def
end

function Omerta.Events.GetType(id) return types[id] end

function Omerta.Events.Types()
    local out = {}
    for _, def in pairs(types) do out[#out + 1] = def end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

--------------------------------------------------------------------------------
-- Validation (pure)
--------------------------------------------------------------------------------

-- Returns true, or false + reason. Kept apart from the write so the rules are
-- testable without a database.
function Omerta.Events.Validate(spec)
    if type(spec) ~= "table" then return false, "an event needs a specification" end
    if not types[spec.type or ""] then
        return false, "unknown event type '" .. tostring(spec.type) .. "'"
    end
    if type(spec.season_id) ~= "number" then return false, "an event needs a season" end
    -- Everything else is optional on purpose: a fire has no subject, a
    -- promotion has no position, and forcing placeholders into columns is how
    -- a later query learns to distrust them.
    return true
end
