-- Crime: the milestone where the criminal half of the design acquires a verb.
--
-- Thirteen milestones built a city where crime is possible and nothing in it is
-- a crime. A player could already walk into a bar, shoot the barman and go
-- through his coat, and the game recorded an injury, a death and an event while
-- having no opinion whatsoever about the robbery that just happened.
--
-- This file is the pure half: the state machine, what makes a place robbable,
-- the escape and abandonment arithmetic, the take planner, and the rumour
-- builder. Nothing here touches an entity, a row or a client — which is what
-- lets the headless suite pin the design of the milestone rather than its
-- plumbing.

Omerta.Crime = Omerta.Crime or {}
Omerta.Crime.Internal = Omerta.Crime.Internal or {}

--------------------------------------------------------------------------------
-- The states
--------------------------------------------------------------------------------
-- Tech §16 names seven. M14 owns five of them and never sets two.

Omerta.Crime.STATE = {
    -- Declared and deliberately unreachable in M14. Tech §16 says in as many
    -- words not to require a planning UI for small crimes, and a store robbery
    -- is a small crime — it starts when somebody points a gun at a man, not
    -- when a form is filled in. C4's bank job is where a plan becomes a real
    -- object, and it should not have to migrate an enum to say so. Same
    -- discipline that put `published_at` in the events table a milestone before
    -- M21 needed it.
    PLANNED       = "planned",
    ACTIVE        = "active",
    ALARMED       = "alarmed",
    ESCAPED       = "escaped",
    FAILED        = "failed",
    -- M17's. M14 defines them and never writes them.
    INVESTIGATING = "investigating",
    CLOSED        = "closed",
}
local S = Omerta.Crime.STATE

-- Why it ended. Kept apart from the state because "escaped" and "failed" are
-- two stories, and M21 needs to tell them apart from more than a single word.
Omerta.Crime.RESOLUTION = {
    CLEAR     = "clear",      -- out of the building and away
    ABANDONED = "abandoned",  -- the ceiling, or a restart (D-050)
    STOPPED   = "stopped",    -- put down or arrested at the scene
}

--------------------------------------------------------------------------------
-- The legal-move table
--------------------------------------------------------------------------------
-- Written out rather than inferred, exactly as M19's is, because which
-- transitions are possible IS the design of this milestone and it should be
-- readable in one place. A move that is not listed cannot happen, which is what
-- stops a later milestone quietly reopening a closed case.

local TRANSITIONS = {
    [S.PLANNED]       = { [S.ACTIVE] = true, [S.FAILED] = true },
    [S.ACTIVE]        = { [S.ALARMED] = true, [S.ESCAPED] = true, [S.FAILED] = true },
    -- An alarm does not end anything. The crew can still walk out with the
    -- money and often does; what the alarm changes is who is waiting outside.
    [S.ALARMED]       = { [S.ESCAPED] = true, [S.FAILED] = true },
    -- Terminal for M14. NEITHER IS A VERDICT: escaped is not a reward and
    -- failed is not a punishment, they are two opening positions for M17. A
    -- crew that takes four hundred dollars and is then shot on the pavement
    -- resolves to failed, and the four hundred dollars is on the body —
    -- failure is a fact about the crew, not about the till.
    [S.ESCAPED]       = { [S.INVESTIGATING] = true },
    [S.FAILED]        = { [S.INVESTIGATING] = true },
    [S.INVESTIGATING] = { [S.CLOSED] = true },
    [S.CLOSED]        = {},
}

function Omerta.Crime.CanTransition(from, to)
    if from == to then return false end
    local allowed = TRANSITIONS[from]
    if not allowed then return false end
    return allowed[to] == true
end

function Omerta.Crime.IsTerminal(state)
    return state == S.ESCAPED or state == S.FAILED
        or state == S.INVESTIGATING or state == S.CLOSED
end

function Omerta.Crime.IsLive(state)
    return state == S.PLANNED or state == S.ACTIVE or state == S.ALARMED
end

--------------------------------------------------------------------------------
-- Operation types
--------------------------------------------------------------------------------
-- Data, in version control, exactly as an item or a weapon is. C4's bank is one
-- more table in this shape.

local operationTypes = {}

function Omerta.Crime.RegisterOperationType(id, def)
    if type(id) ~= "string" or not id:find("^[a-z0-9_%.]+$") then
        error("operation type '" .. tostring(id) .. "' must be lowercase [a-z0-9_.]", 2)
    end
    if operationTypes[id] then error("operation type '" .. id .. "' registered twice", 2) end
    if type(def) ~= "table" or type(def.name) ~= "string" or def.name == "" then
        error("operation type '" .. id .. "' needs a name", 2)
    end
    def.id = id
    def.maxSeconds = def.maxSeconds or 600
    def.escapeDistance = def.escapeDistance or 2500
    def.escapeSeconds = def.escapeSeconds or 45
    def.takeSource = def.takeSource or "business.till"
    operationTypes[id] = def
    return def
end

function Omerta.Crime.GetOperationType(id) return operationTypes[id] end

function Omerta.Crime.OperationTypes()
    local out = {}
    for _, def in pairs(operationTypes) do out[#out + 1] = def end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- The one M14 ships. Registered at file scope beside the personalities and the
-- venue types, because an operation type is DATA — the same argument M9 §6 makes
-- about item definitions, and the reason C4's bank is one more table here rather
-- than a branch anywhere.
Omerta.Crime.RegisterOperationType("robbery.store", {
    name = "Store robbery",
    maxSeconds = 600,        -- the abandonment ceiling
    escapeDistance = 2500,
    escapeSeconds = 45,
    takeSource = "business.till",
})

--------------------------------------------------------------------------------
-- Take sources
--------------------------------------------------------------------------------
-- Where the money is. A till here, a vault in C4 — one registration, and the
-- operation machinery never learns the difference.

local takeSources = {}

function Omerta.Crime.RegisterTakeSource(id, def)
    if type(id) ~= "string" or id == "" then error("a take source needs an id", 2) end
    if takeSources[id] then error("take source '" .. id .. "' registered twice", 2) end
    if type(def) ~= "table" or type(def.container) ~= "function" then
        error("take source '" .. id .. "' needs a container function", 2)
    end
    def.id = id
    takeSources[id] = def
    return def
end

function Omerta.Crime.GetTakeSource(id) return takeSources[id] end

--------------------------------------------------------------------------------
-- The robbery block, and its conservative default
--------------------------------------------------------------------------------
-- A type that declares no `robbery` block still gets one. Robbability as an
-- opt-in flag would make a funeral home invisible to the crime system until
-- somebody remembered to tick a box, which is the special case this codebase
-- registers behaviour to avoid.

Omerta.Crime.DEFAULT_ROBBERY = {
    clerk = { personalities = { "clerk.old_hand" } },
    -- Nobody's silent alarm and nobody's telephone by default: a place that has
    -- not said it can call the police cannot. That is the conservative
    -- direction — the default must never invent a capability the content author
    -- did not declare.
    alarm = { kind = "none", telephone = false, button = false },
    register = { openSeconds = 4, forceSeconds = 22, forceTool = "tool.crowbar" },
    float = { perHour = 0, ceiling = 0 },
    -- `fleeTo` is deliberately ABSENT rather than declared nil. A nil value is
    -- not a key in Lua, and the merge below walks the DECLARED keys as well as
    -- the default ones for exactly that reason — iterating the defaults alone
    -- would silently drop every field the defaults have no opinion about, which
    -- is every field a content author is most likely to add.
}

-- Merged rather than defaulted-at-read, so every consumer sees a complete block
-- and nobody has to remember which fields are optional.
function Omerta.Crime.RobberyBlock(typeDef)
    local declared = (typeDef and typeDef.robbery) or {}
    local out = {}

    local keys = {}
    for key in pairs(Omerta.Crime.DEFAULT_ROBBERY) do keys[key] = true end
    for key in pairs(declared) do keys[key] = true end

    for key in pairs(keys) do
        local fallback = Omerta.Crime.DEFAULT_ROBBERY[key]
        local given = declared[key]
        if type(fallback) == "table" and type(given) == "table" then
            local merged = {}
            for k, v in pairs(fallback) do merged[k] = v end
            for k, v in pairs(given) do merged[k] = v end
            out[key] = merged
        elseif given ~= nil then
            out[key] = given
        else
            out[key] = fallback
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- What makes a place robbable
--------------------------------------------------------------------------------
-- Pure, layered directly over M13's IsForceable, and DELIBERATELY WITHOUT A
-- POSITION ARGUMENT. D-030 was built with no way to express "somebody was
-- standing in the room" (M13 §13), and M14 must not be the milestone that
-- quietly reintroduces one.
--
--   forceable — the answer M13's own rule gives for this business
--   live      — whether an operation is already running on it
--   cooldown  — seconds remaining on the post-robbery cooldown, or 0
--
-- Returns true, or false + reason.
function Omerta.Crime.IsRobbable(typeDef, business, forceable, live, cooldownRemaining)
    if not business then return false, "there is nothing here" end
    if live then return false, "this is already happening" end
    if (cooldownRemaining or 0) > 0 then
        -- The words are deliberately about the room rather than about a timer:
        -- no client is ever told a number (§5).
        return false, "there is nothing left in the register"
    end

    -- D-030 GAINS A THIRD CASE HERE, and it is the one that makes the milestone
    -- work. M13's rule answers false when a business has no owner, which was
    -- the correct conservative default for a milestone with no unowned
    -- businesses and is exactly wrong for a store that exists to be robbed.
    -- D-030 exists to stop players being punished for logging off; an unowned
    -- store has no players to punish. Owned premises are untouched.
    if not business.owner_organization_id and not business.owner_character_id then
        return true
    end

    if not forceable then
        return false, "there is nobody here worth robbing"
    end
    return true
end

--------------------------------------------------------------------------------
-- Escape and abandonment
--------------------------------------------------------------------------------
-- Both computed from ABSOLUTE timestamps, never countdowns. M19 learned this
-- twice and it is now nearly a house rule: a restart that reset the clock would
-- make waiting for the nightly restart a robbery technique.

-- Whether the crew is clear. `clearSince` is the timestamp every live
-- participant has been beyond escapeDistance since, or nil if any of them is
-- still close. Pure over its inputs so the whole rule is testable without a map.
function Omerta.Crime.HasEscaped(typeDef, clearSince, now)
    if not clearSince then return false end
    return (now - clearSince) >= (typeDef.escapeSeconds or 45)
end

-- The ceiling. Guarantees the machine is TOTAL: no operation can sit open
-- forever holding a clerk in a compliance state that nobody is present to end.
function Omerta.Crime.HasExpired(operation, now)
    if not operation.deadline_at then return false end
    return now >= operation.deadline_at
end

function Omerta.Crime.DeadlineFor(typeDef, startedAt)
    return startedAt + (typeDef.maxSeconds or 600)
end

--------------------------------------------------------------------------------
-- The take planner
--------------------------------------------------------------------------------
-- A HANDFUL AT A TIME, and the reason is mechanical rather than aesthetic:
-- Money.Pay is all-or-nothing and refuses on capacity, so a robber whose
-- pockets are half full would otherwise get NOTHING. Repeating the grab is
-- better in every direction — it puts the time in front of the frightened man
-- where the scene needs it, it makes interrupting a robbery mid-take mean
-- something, and it makes the second robber genuinely useful rather than
-- decorative.
--
-- `fits(cents)` answers whether that much would go in the coat. Passed in
-- rather than computed, because bulk is M9's arithmetic and this is M14's
-- decision about how much to reach for.
--
-- Returns the amount to attempt, or 0.
function Omerta.Crime.PlanGrab(registerCents, handfulCents, fits)
    local want = math.min(tonumber(registerCents) or 0, tonumber(handfulCents) or 0)
    want = Omerta.Money.Round(want)
    if want < Omerta.Money.SMALLEST then return 0 end

    -- Halve down rather than refuse. A man with a Thompson across his back and
    -- room for eighty cents takes eighty cents; he does not stand there empty
    -- handed because the till holds more than his coat does (D-020).
    while want >= Omerta.Money.SMALLEST do
        if fits(want) then return want end
        want = Omerta.Money.Round(math.floor(want / 2))
    end
    return 0
end

--------------------------------------------------------------------------------
-- The rumour
--------------------------------------------------------------------------------
-- The one thing M14 puts in front of other players, and the first event-sourced
-- entry the pool has ever had (D-031). M13 built Omerta.Rumours.Add with an
-- `event` source for exactly this and nothing but M13's own self-test has
-- called it that way since.
--
-- THIS FUNCTION HAS NO VOCABULARY FOR A NAME. It takes a place and a shape of
-- event and returns a sentence; there is no parameter it could put a character
-- into, which is a stronger guarantee than remembering not to.

local OPENINGS = {
    "They say ",
    "Word is ",
    "Somebody was saying ",
}

function Omerta.Crime.RumourText(shape, placeName, seed)
    placeName = (type(placeName) == "string" and placeName ~= "") and placeName or "a place on the next street"

    local body
    if shape == "murder" then
        body = "a man was shot dead behind the counter at " .. placeName .. "."
    elseif shape == "alarmed" then
        body = "somebody tried it on at " .. placeName .. " and the police heard about it."
    elseif shape == "failed" then
        body = "somebody tried it on at " .. placeName .. " and it went badly for them."
    else
        body = "somebody put a gun in a shopkeeper's face at " .. placeName .. "."
    end

    local opening = OPENINGS[(math.floor(tonumber(seed) or 0) % #OPENINGS) + 1]
    return opening .. body
end
