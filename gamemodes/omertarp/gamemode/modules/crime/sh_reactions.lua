-- What the man behind the counter does.
--
-- GDD §12: "NPC victims assess concealment, weapons, aggression, witnesses,
-- alarms, and personality before complying, stalling, fleeing, resisting, or
-- calling police." All six inputs, all five outputs, one pure function.
--
-- Three positions this file exists to hold:
--
-- IT IS DETERMINISTIC GIVEN A SEED, and the seed is drawn once per operation.
-- A model that rolled fresh dice every evaluation could not be pinned headlessly
-- and, worse, could not be LEARNED — and a robbery you cannot get better at is a
-- slot machine with a gun in it. The seed lives on the operation row, so the
-- same situation replays identically in a test and a robber cannot re-roll a
-- stubborn clerk by backing off and demanding again inside the same job.
--
-- IT IS EVALUATED ON EVENTS, NOT ON A TICK. The demand, a shot, somebody new
-- through the door, the clerk being struck, and a fixed nerve-decay step.
-- Pressure accumulates across evaluations; the function itself is stateless.
--
-- PAST A THRESHOLD HE STOPS BEING A RATIONAL ACTOR. Above his nerve the
-- personality's weights stop applying and he flees or freezes. That is what
-- makes firing a warning shot a genuinely bad idea rather than a stronger
-- version of a good one — it is the difference between a man who opens the
-- register and a man running for the door with your face in his memory.

Omerta.Crime = Omerta.Crime or {}
Omerta.Crime.Internal = Omerta.Crime.Internal or {}

Omerta.Crime.REACTION = {
    COMPLY = "comply",
    STALL  = "stall",
    ALARM  = "alarm",   -- the telephone or the button; which one is the room's
    FLEE   = "flee",
    RESIST = "resist",
}
local R = Omerta.Crime.REACTION

--------------------------------------------------------------------------------
-- Personalities
--------------------------------------------------------------------------------
-- Data, registered exactly like an item or a weapon: four numbers and a name.
-- "The old man who has been robbed twice and just opens the drawer", "the kid
-- who bolts" and "the ex-soldier who reaches under the counter" are three
-- tables in one file, and the fourth is a fourth table.

local personalities = {}

function Omerta.Crime.RegisterPersonality(id, def)
    if type(id) ~= "string" or not id:find("^[a-z0-9_%.]+$") then
        error("personality '" .. tostring(id) .. "' must be lowercase [a-z0-9_.]", 2)
    end
    if personalities[id] then error("personality '" .. id .. "' registered twice", 2) end
    if type(def) ~= "table" or type(def.name) ~= "string" or def.name == "" then
        error("personality '" .. id .. "' needs a name", 2)
    end
    def.id = id
    def.nerve         = def.nerve or 0.7          -- pressure before he stops thinking
    def.compliance    = def.compliance or 0.6     -- how readily he opens the register
    def.duty          = def.duty or 0.3           -- how much he cares about the money
    def.alarmAppetite = def.alarmAppetite or 0.5  -- how likely he is to reach for it
    personalities[id] = def
    return def
end

function Omerta.Crime.GetPersonality(id) return personalities[id] end

function Omerta.Crime.Personalities()
    local out = {}
    for _, def in pairs(personalities) do out[#out + 1] = def end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

--------------------------------------------------------------------------------
-- Extra inputs
--------------------------------------------------------------------------------
-- Where the disguise milestone adds "he can see your face", M15 adds "he has
-- been robbed by somebody dressed like you before", and M10 adds "he knows
-- whose neighbourhood this is". fn(situation) -> a number added to pressure.

local reactionInputs = {}

function Omerta.Crime.RegisterReactionInput(id, fn)
    if type(id) ~= "string" or id == "" then error("a reaction input needs an id", 2) end
    if type(fn) ~= "function" then
        error("reaction input '" .. id .. "' needs a function", 2)
    end
    if reactionInputs[id] then
        error("reaction input '" .. id .. "' registered twice", 2)
    end
    reactionInputs[id] = fn
end

Omerta.Crime.Internal.ReactionInputs = reactionInputs

--------------------------------------------------------------------------------
-- Pressure
--------------------------------------------------------------------------------
-- The situation reduced to one number. Every weight here is a balance
-- statement, so each one is named rather than buried in an expression.

-- What is pointed at him. A revolver is a threat; a Thompson is a different
-- conversation, and the difference is one W0 already wrote down: a thing you
-- cannot hide under a coat (`concealable = false`) is a long gun.
--
-- Read off the arsenal's existing fields rather than a new one, because the man
-- behind the counter is not a ballistician and the game should not need a
-- balance number per weapon to say what he can see. Three classes is what he
-- perceives.
local WEAPON_PRESSURE = {
    melee   = 0.25,
    handgun = 0.45,
    long    = 0.75,
}
Omerta.Crime.WEAPON_PRESSURE = WEAPON_PRESSURE

-- Pure over a weapon definition, so the whole mapping is one testable function
-- rather than a lookup repeated at every call site.
function Omerta.Crime.ThreatClass(weaponDef)
    if not weaponDef then return nil end
    if weaponDef.slot == "melee" then return "melee" end
    if weaponDef.concealable == false then return "long" end
    return "handgun"
end

Omerta.Crime.PRESSURE = {
    UNARMED        = 0.10,  -- a demand with empty hands is still a demand
    UNKNOWN_WEAPON = 0.45,  -- something is pointed at him; he is not a ballistician
    EXTRA_GUN      = 0.18,  -- per gun beyond the first
    SHOT_FIRED     = 0.32,  -- per shot, counted to three
    SHOTS_COUNTED  = 3,
    HE_IS_HURT     = 0.55,
    BYSTANDER_HURT = 0.65,
    -- Witnesses cut the other way and only a little: a room with people in it
    -- is a room where somebody might do something, and that is worth a shred of
    -- nerve. Capped, because the fourth onlooker is not braver than the third.
    PER_BYSTANDER  = -0.08,
    BYSTANDERS_COUNTED = 3,
    -- Once the alarm is going he knows help is coming, which is a reason to
    -- play for time rather than to hand it over.
    ALARM_RAISED   = -0.22,
    -- The nerve decay step. Standing in front of a gun does not get calmer.
    PER_SECOND     = 0.012,
}
local P = Omerta.Crime.PRESSURE

function Omerta.Crime.Pressure(situation)
    situation = situation or {}
    local pressure = 0

    if situation.armed then
        pressure = pressure + (WEAPON_PRESSURE[situation.weaponClass or ""] or P.UNKNOWN_WEAPON)
    else
        pressure = pressure + P.UNARMED
    end

    local guns = math.max(0, (tonumber(situation.weaponsVisible) or 0) - 1)
    pressure = pressure + guns * P.EXTRA_GUN

    local shots = math.min(tonumber(situation.shotsFired) or 0, P.SHOTS_COUNTED)
    pressure = pressure + shots * P.SHOT_FIRED

    if situation.victimHurt then pressure = pressure + P.HE_IS_HURT end
    if situation.bystanderHurt then pressure = pressure + P.BYSTANDER_HURT end

    local onlookers = math.min(tonumber(situation.bystanders) or 0, P.BYSTANDERS_COUNTED)
    pressure = pressure + onlookers * P.PER_BYSTANDER

    if situation.alarmRaised then pressure = pressure + P.ALARM_RAISED end

    pressure = pressure + math.max(0, tonumber(situation.elapsed) or 0) * P.PER_SECOND

    for _, fn in pairs(reactionInputs) do
        pressure = pressure + (tonumber(fn(situation)) or 0)
    end

    return math.max(0, pressure)
end

--------------------------------------------------------------------------------
-- The seed
--------------------------------------------------------------------------------
-- A deterministic roll, drawn from the operation's seed and the beat being
-- evaluated. Arithmetic rather than bitwise because this is shared code and
-- Garry's Mod is Lua 5.1 — `//` and `~` are not available and a float shift
-- would quietly differ between realms.

local function fold(hash, value)
    if type(value) == "string" then
        for i = 1, #value do
            hash = (hash * 31 + value:byte(i)) % 2147483647
        end
        return hash
    end
    return (hash * 31 + math.floor((tonumber(value) or 0) * 1000)) % 2147483647
end

-- Returns a number in [0, 1).
function Omerta.Crime.Roll(seed, ...)
    local hash = 2166136261 % 2147483647
    hash = fold(hash, tonumber(seed) or 0)
    local parts = { ... }
    for i = 1, #parts do hash = fold(hash, parts[i]) end
    return (hash % 100003) / 100003
end

--------------------------------------------------------------------------------
-- The mask (D-051)
--------------------------------------------------------------------------------
-- A mask LOWERS RESISTANCE NOW AND RAISES THE ODDS OF AN ALARM AFTERWARDS.
--
-- A masked robber plainly intends to leave anonymous, which reads to the man
-- behind the counter as somebody who does not need him dead — so he complies
-- more readily. Once the crew is out of the door he has nothing left to fear,
-- so he is likelier to reach for the telephone.
--
-- The rationale stops there, and the ruling trimmed it on purpose. An earlier
-- draft had the unmasked robber read as INTENDING MURDER; that is speculative
-- interior reasoning about an NPC, and the mechanical trade stands without it.
-- There is deliberately no term anywhere in this file for what the clerk thinks
-- the robber came to do.
Omerta.Crime.MASK = {
    COMPLIANCE = 0.30,  -- he believes he will live through this
    REPORT     = 0.35,  -- and he has nothing left to lose afterwards
}

--------------------------------------------------------------------------------
-- The decision
--------------------------------------------------------------------------------

Omerta.Crime.DRIVE = {
    COMPLY_PER_PRESSURE = 0.45,
    -- Duty is caring about somebody else's money, and it is the first thing
    -- pressure takes away from a person.
    RESIST_DECAY        = 0.80,
    -- Fleeing is not a weighted option — it is what is left when the weighing
    -- stops. It scores nothing at all until pressure is past his nerve, and
    -- then it climbs faster than anything else can.
    FLEE_PER_EXCESS     = 1.60,
    -- The floor. Doing nothing while you work out what to do is always
    -- available, which is why a clerk never simply has no reaction.
    STALL               = 0.38,
    -- How much the seed is allowed to move any one drive. Small: this is a
    -- personality with a bad day, not a dice roll wearing a personality.
    JITTER              = 0.16,
}
local D = Omerta.Crime.DRIVE

-- The opportunity to reach for the alarm. He does not lunge for the button with
-- a gun eighteen inches from his face and a second man watching the door; he
-- takes it when something is happening elsewhere, or once he has been ignored
-- long enough to matter.
function Omerta.Crime.AlarmOpportunity(situation)
    situation = situation or {}
    if situation.alarmRaised then return 0 end

    local opportunity = 0.25
    -- Every extra gun in the room is another pair of eyes.
    opportunity = opportunity - 0.10 * math.max(0, (tonumber(situation.weaponsVisible) or 0) - 1)
    -- Time is the only thing that reliably gives him a chance.
    opportunity = opportunity + math.min(0.45, (tonumber(situation.elapsed) or 0) * 0.015)
    -- Somebody else being dealt with is the moment.
    if situation.distracted then opportunity = opportunity + 0.35 end
    -- And a man who has been hit is not reaching for anything.
    if situation.victimHurt then opportunity = opportunity - 0.30 end

    return math.max(0, opportunity)
end

-- The five drives, before the seed touches them. Exposed because a balance
-- question ("why did he run?") should be answerable without instrumenting the
-- decision, and because the tests assert on the shape rather than the outcome.
function Omerta.Crime.Drives(situation, personality)
    situation = situation or {}
    local pressure = Omerta.Crime.Pressure(situation)

    local comply = personality.compliance + pressure * D.COMPLY_PER_PRESSURE
    if situation.masked then comply = comply + Omerta.Crime.MASK.COMPLIANCE end

    return {
        [R.COMPLY] = comply,
        [R.RESIST] = personality.duty * math.max(0, 1 - pressure * D.RESIST_DECAY),
        [R.ALARM]  = personality.alarmAppetite * Omerta.Crime.AlarmOpportunity(situation),
        -- ABOVE HIS NERVE THE WEIGHTS STOP APPLYING. Nothing else in this table
        -- grows with excess pressure, so past the threshold this one wins and
        -- keeps winning — which is the whole point of the warning shot being a
        -- mistake rather than an escalation.
        [R.FLEE]   = math.max(0, pressure - personality.nerve) * D.FLEE_PER_EXCESS,
        [R.STALL]  = D.STALL,
    }, pressure
end

-- The decision. `beat` names which evaluation this is — "demand", "shot",
-- "entry", "struck", "decay" — so the same operation asked twice about two
-- different things gets two independent rolls, and the same operation asked
-- twice about the SAME thing does not.
--
-- Returns the reaction, the drives, and the pressure.
function Omerta.Crime.Reaction(situation, personality, seed, beat)
    local drives, pressure = Omerta.Crime.Drives(situation, personality)

    local best, bestScore = nil, nil
    -- Iterated in a fixed order rather than through pairs(): a table walk is
    -- unordered, so a tie would resolve differently between two machines
    -- running the identical seed — which would quietly break the one property
    -- this model is built around.
    for _, reaction in ipairs({ R.COMPLY, R.STALL, R.ALARM, R.FLEE, R.RESIST }) do
        local score = drives[reaction]
            + Omerta.Crime.Roll(seed, beat or "", reaction) * D.JITTER
        if bestScore == nil or score > bestScore then
            best, bestScore = reaction, score
        end
    end

    return best, drives, pressure
end

--------------------------------------------------------------------------------
-- Afterwards (D-051)
--------------------------------------------------------------------------------
-- The post-resolution evaluation the ruling asked for. Once the crew has gone,
-- the question is no longer what he dares do — it is what he chooses to say.
-- Returns a chance in [0, 1].
Omerta.Crime.REPORT = {
    BASE           = 0.55,   -- multiplied by his appetite for the police
    HE_WAS_HURT    = 0.25,
    SHOTS_FIRED    = 0.20,
    SOMEBODY_DIED  = 1.00,   -- a body on the floor is not a decision he makes
    HE_COMPLIED    = -0.15,  -- a man who handed it over wants it to be over
}

function Omerta.Crime.ReportChance(situation, personality)
    situation = situation or {}
    if situation.clerkDead then
        -- D-052: killing him guarantees the alarm or the discovery on a fixed
        -- timer regardless of what he did or did not reach for. There is
        -- nothing probabilistic left here — a man does not report his own
        -- murder, somebody finds him.
        return 1
    end

    local chance = personality.alarmAppetite * Omerta.Crime.REPORT.BASE

    -- The other half of the trade. He has nothing left to fear from a man whose
    -- face he never saw, so the telephone is easier to reach for.
    if situation.masked then chance = chance + Omerta.Crime.MASK.REPORT end

    if situation.victimHurt then chance = chance + Omerta.Crime.REPORT.HE_WAS_HURT end
    if (tonumber(situation.shotsFired) or 0) > 0 then
        chance = chance + Omerta.Crime.REPORT.SHOTS_FIRED
    end
    if situation.bystanderHurt then chance = chance + Omerta.Crime.REPORT.SOMEBODY_DIED end
    if situation.complied then chance = chance + Omerta.Crime.REPORT.HE_COMPLIED end

    return math.max(0, math.min(1, chance))
end

--------------------------------------------------------------------------------
-- The three clerks
--------------------------------------------------------------------------------

Omerta.Crime.RegisterPersonality("clerk.old_hand", {
    name = "Old hand",
    -- Has been robbed twice and just opens the drawer. Hard to panic, does not
    -- care about the owner's money, and phones it in afterwards because he
    -- knows how this works.
    nerve = 0.85, compliance = 0.75, duty = 0.15, alarmAppetite = 0.60,
})

Omerta.Crime.RegisterPersonality("clerk.kid", {
    name = "The kid",
    -- Bolts. Complies readily right up until he does not, and the threshold is
    -- low enough that a warning shot is very likely to produce a boy running
    -- out of the back door with your face in his memory.
    nerve = 0.55, compliance = 0.70, duty = 0.10, alarmAppetite = 0.35,
})

Omerta.Crime.RegisterPersonality("clerk.ex_soldier", {
    name = "The ex-soldier",
    -- Reaches under the counter. High nerve, real duty, and the highest
    -- appetite for the button in the game — the clerk you do not want, and the
    -- reason knowing which shop you are walking into is worth something.
    nerve = 1.10, compliance = 0.40, duty = 0.55, alarmAppetite = 0.75,
})
