-- Injury and incapacitation (M19, D-037).
--
-- Losing a fight is a SITUATION, not an event. You go down, you stay in the
-- world, and what happens next is a decision somebody standing over you gets
-- to make. Everything in this file is the pure half of that: the states, the
-- legal moves between them, what damage means, and what a character is told
-- about their own condition.
--
-- Health is an INPUT, never an output. The engine still deals damage the way
-- it always has — bullets, falls, fire — and this module reads the result and
-- decides what state it puts you in. Reimplementing damage would mean getting
-- drowning and crush subtly wrong for no gain, and M14's weapons would then
-- need special handling to hurt anybody.
--
-- The player is never shown a number (GDD §8). They are told a sentence.

Omerta.Injury = Omerta.Injury or {}
Omerta.Injury.Internal = Omerta.Injury.Internal or {}
local Internal = Omerta.Injury.Internal

Omerta.Injury.STATE = {
    HEALTHY       = "healthy",
    INJURED       = "injured",
    CRITICAL      = "critical",
    INCAPACITATED = "incapacitated",
    STABILIZED    = "stabilized",
    RECOVERING    = "recovering",
    DEAD          = "dead",
}
local S = Omerta.Injury.STATE

-- Wire codes. Frozen: the client sends nothing, but it receives an index, and
-- renumbering these would silently relabel a stale client's condition.
Omerta.Injury.STATE_INDEX = {
    [S.HEALTHY] = 1, [S.INJURED] = 2, [S.CRITICAL] = 3, [S.INCAPACITATED] = 4,
    [S.STABILIZED] = 5, [S.RECOVERING] = 6, [S.DEAD] = 7,
}
Omerta.Injury.STATE_BY_INDEX = {}
for name, index in pairs(Omerta.Injury.STATE_INDEX) do
    Omerta.Injury.STATE_BY_INDEX[index] = name
end

--------------------------------------------------------------------------------
-- The legal-move table
--------------------------------------------------------------------------------
-- Written out rather than inferred, because "which transitions are possible"
-- is the actual design of this milestone and it should be readable in one
-- place. A move that is not listed cannot happen, which is what stops a future
-- milestone quietly reviving a corpse.

local TRANSITIONS = {
    [S.HEALTHY]       = { [S.INJURED] = true, [S.CRITICAL] = true,
                          [S.INCAPACITATED] = true, [S.DEAD] = true },
    [S.INJURED]       = { [S.HEALTHY] = true, [S.CRITICAL] = true,
                          [S.INCAPACITATED] = true, [S.DEAD] = true },
    [S.CRITICAL]      = { [S.HEALTHY] = true, [S.INJURED] = true,
                          [S.INCAPACITATED] = true, [S.DEAD] = true },
    -- Down. The only ways out are somebody's decision or the clock.
    [S.INCAPACITATED] = { [S.STABILIZED] = true, [S.RECOVERING] = true, [S.DEAD] = true },
    -- Stabilized has stopped bleeding but is still on the floor: a bandage
    -- buys time, it does not get you up. That two-step is what makes both the
    -- item and M13's clinic worth having.
    [S.STABILIZED]    = { [S.RECOVERING] = true, [S.INCAPACITATED] = true, [S.DEAD] = true },
    [S.RECOVERING]    = { [S.HEALTHY] = true, [S.INJURED] = true, [S.CRITICAL] = true,
                          [S.INCAPACITATED] = true, [S.DEAD] = true },
    -- Terminal, and deliberately so. D-037 gives death exactly two causes and
    -- no way back from either.
    [S.DEAD]          = {},
}

function Omerta.Injury.CanTransition(from, to)
    if from == to then return false end
    local allowed = TRANSITIONS[from]
    if not allowed then return false end
    return allowed[to] == true
end

-- Every state, in severity order. Used by the self-test and by anything that
-- wants to iterate without hardcoding the list a second time.
Omerta.Injury.ORDER = {
    S.HEALTHY, S.INJURED, S.CRITICAL, S.INCAPACITATED,
    S.STABILIZED, S.RECOVERING, S.DEAD,
}

--------------------------------------------------------------------------------
-- Damage to state
--------------------------------------------------------------------------------

-- Thresholds as fractions of full health, so a future milestone changing max
-- health does not silently re-tune every band.
Omerta.Injury.INJURED_BELOW  = 0.70
Omerta.Injury.CRITICAL_BELOW = 0.35

-- What a given amount of remaining health means, given where the character
-- already is. `current` matters because being down is not something you climb
-- out of by regenerating: an incapacitated character with full health is still
-- incapacitated until somebody treats them.
function Omerta.Injury.StateForHealth(health, maxHealth, current)
    if current and not (current == S.HEALTHY or current == S.INJURED
            or current == S.CRITICAL) then
        return current
    end
    maxHealth = (maxHealth and maxHealth > 0) and maxHealth or 100
    local fraction = (tonumber(health) or maxHealth) / maxHealth
    if fraction <= 0 then return S.INCAPACITATED end
    if fraction < Omerta.Injury.CRITICAL_BELOW then return S.CRITICAL end
    if fraction < Omerta.Injury.INJURED_BELOW then return S.INJURED end
    return S.HEALTHY
end

-- Down means at somebody's mercy: on the floor, in the world, unable to act.
function Omerta.Injury.IsDown(state)
    return state == S.INCAPACITATED or state == S.STABILIZED
end

-- Anything that is not standing and not dead. M14/M17 will want this to ask
-- "can this person do things" without listing states.
function Omerta.Injury.IsIncapable(state)
    return Omerta.Injury.IsDown(state) or state == S.DEAD
end

function Omerta.Injury.IsAlive(state)
    return state ~= S.DEAD
end

--------------------------------------------------------------------------------
-- What the character is told
--------------------------------------------------------------------------------
-- Prose, never a percentage. A character knows they are bleeding badly; they
-- do not know they are at 31%.

local DESCRIPTIONS = {
    [S.HEALTHY]       = nil, -- nothing to say, so nothing on screen (M8)
    [S.INJURED]       = "You are hurt.",
    [S.CRITICAL]      = "You are bleeding badly.",
    [S.INCAPACITATED] = "You are bleeding out.",
    [S.STABILIZED]    = "The bleeding has stopped. You cannot move.",
    [S.RECOVERING]    = "You are still weak.",
    [S.DEAD]          = "You are dead.",
}

function Omerta.Injury.Describe(state)
    return DESCRIPTIONS[state]
end

--------------------------------------------------------------------------------
-- Timers
--------------------------------------------------------------------------------
-- Every timed state carries an absolute deadline rather than a countdown, so a
-- server restart resumes it instead of restarting it. A restart that resets
-- the bleed-out clock is a restart that rescues everybody who was about to
-- die, which would make "wait for the nightly restart" a medical procedure.

-- Which states expire, and into what.
Omerta.Injury.EXPIRES_TO = {
    [S.INCAPACITATED] = S.DEAD,        -- D-037 §4b
    [S.STABILIZED]    = S.RECOVERING,  -- treated in time; you come round
    [S.RECOVERING]    = S.HEALTHY,
}

-- Pure: has this deadline passed? nil means "no deadline", which never expires.
function Omerta.Injury.HasExpired(expiresAt, now)
    if not expiresAt or expiresAt <= 0 then return false end
    return (now or 0) >= expiresAt
end

-- Seconds left, for the prompt. Never negative, nil when there is no clock.
function Omerta.Injury.SecondsLeft(expiresAt, now)
    if not expiresAt or expiresAt <= 0 then return nil end
    return math.max(0, expiresAt - (now or 0))
end

--------------------------------------------------------------------------------
-- The recovery penalty (§4c, D-037)
--------------------------------------------------------------------------------
-- Losing a fight has to cost something after you are upright, or the correct
-- play after any loss is to walk straight back into it. The penalty decays
-- across the recovery window: worst at the moment you stand up, gone by the
-- time you are healthy.
--
-- Built on M8's modifier seams, so this is arithmetic and two registrations
-- rather than a system.

-- fraction 0..1 of the recovery window still remaining -> multiplier.
-- `worst` is the multiplier at the moment of standing up; it eases back to 1.
function Omerta.Injury.RecoveryMultiplier(remainingFraction, worst)
    local f = math.max(0, math.min(1, tonumber(remainingFraction) or 0))
    worst = tonumber(worst) or 1
    return worst + (1 - worst) * (1 - f)
end

-- How much of the recovery window is left, as a fraction. Pure so the curve is
-- testable without a clock.
function Omerta.Injury.RemainingFraction(expiresAt, total, now)
    if not (expiresAt and total and total > 0) then return 0 end
    local left = Omerta.Injury.SecondsLeft(expiresAt, now) or 0
    return math.max(0, math.min(1, left / total))
end

--------------------------------------------------------------------------------
-- Carrying
--------------------------------------------------------------------------------

-- A carried body is dead weight held in both arms. The penalty is heavy on
-- purpose: moving a body across a city should be a decision, not a detour.
function Omerta.Injury.CarrySpeedMultiplier(isCarrying, scale)
    if not isCarrying then return 1 end
    return math.max(0.05, tonumber(scale) or 0.5)
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------
-- Private to its owner, following M8's stamina precedent and M6's rule. A
-- networked state field would let everyone in the room read whether the man on
-- the floor has been stabilized — which is exactly what a doctor is paid to
-- find out by kneeling next to him.

Omerta.Net.Register("injury.state", {
    realm = "server_to_client",
    schema = {
        { name = "state",   type = "uint", bits = 3 },
        { name = "seconds", type = "uint", bits = 12 }, -- 0 = no clock
    },
    handler = function(payload)
        local state = Omerta.Injury.STATE_BY_INDEX[payload.state]
        hook.Run("Omerta.InjuryUpdated", state, payload.seconds)
    end,
})

Omerta.Net.Register("injury.prompt", {
    realm = "server_to_client",
    schema = {
        { name = "text",    type = "string", maxlen = 72 },
        { name = "seconds", type = "uint", bits = 8 },
    },
    handler = function(payload)
        hook.Run("Omerta.InjuryPrompt", payload.text, payload.seconds)
    end,
})

Omerta.Net.Register("injury.carrying", {
    realm = "server_to_client",
    schema = { { name = "carrying", type = "bool" } },
    handler = function(payload)
        hook.Run("Omerta.InjuryCarrying", payload.carrying)
    end,
})

Internal.TRANSITIONS = TRANSITIONS
