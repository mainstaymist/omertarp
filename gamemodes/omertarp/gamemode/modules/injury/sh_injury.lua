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
-- Presentation curves
--------------------------------------------------------------------------------
-- The client draws these; they live here because they are arithmetic, and
-- arithmetic in a cl_ file is arithmetic nothing can test. Same reason M8 put
-- StepAlpha in its shared file.

-- How far the vignette has closed in, as a fraction of half the screen.
--
-- The base is MONOTONIC — it only ever grows — and the pulse is ONE-SIDED, so
-- the heartbeat pushes further in and relaxes back to where the base has got
-- to, never below it. A symmetric sine here was the first version and it read
-- as the screen breathing in and out rather than as the edges closing, because
-- half of every beat was spent retreating.
function Omerta.Injury.VignetteReach(progress, pulsePhase)
    progress = math.Clamp(progress or 0, 0, 1)
    local base = 0.16 + 0.66 * (progress * progress)
    -- (1 - cos) / 2 runs 0..1 rather than -1..1: it adds and then returns to
    -- zero, so the reach never dips below the base.
    local beat = (1 - math.cos(pulsePhase or 0)) * 0.5
    local amplitude = 0.015 + 0.05 * progress
    return math.Clamp(base + beat * amplitude, 0, 0.94)
end

-- How hard the world is out of focus, 0..1. Stays subtle: this is vision
-- going, not a pause menu. Squared like the vignette so the two move together.
function Omerta.Injury.BlurAmount(progress)
    return 0.9 + 4.6 * (math.Clamp(progress or 0, 0, 1) ^ 2)
end

-- Beats per second. Slow: this is a heartbeat felt from the inside, not a
-- strobe. Roughly 21 bpm at the start rising to 54 at the end — well under a
-- real pulse, because on screen anything faster reads as a flicker.
function Omerta.Injury.PulseRate(progress)
    return 0.35 + 0.55 * math.Clamp(progress or 0, 0, 1)
end

Omerta.Injury.DEATH = {
    HOLD    = 1.4,  -- still on the body, letting the trombone land
    RISE    = 5.5,  -- pulling up and away
    CEILING = 12,   -- keep this far off whatever is overhead
    START_HEIGHT = 80,  -- where the top-down shot cuts in, above the body
    HEIGHT  = 420,  -- how far up it climbs with nothing in the way
}

function Omerta.Injury.DeathPhase(elapsed)
    local D = Omerta.Injury.DEATH
    if (elapsed or 0) < D.HOLD then return "hold", math.Clamp((elapsed or 0) / D.HOLD, 0, 1) end
    return "rise", math.Clamp(((elapsed or 0) - D.HOLD) / D.RISE, 0, 1)
end

-- Eases out, so the pull-away starts quickly and settles, rather than sliding
-- at a constant speed like a lift.
function Omerta.Injury.RiseEase(t)
    t = math.Clamp(t or 0, 0, 1)
    return 1 - (1 - t) * (1 - t) * (1 - t)
end

-- The words on the death screen.
--
-- Not "reincarnate": that means a soul returning, and nothing of the sort
-- happens here. A dead character stays dead, keeps nothing and passes nothing
-- on (GDD §19.3, D-012) — what comes next is a different person, in the same
-- city, starting from nothing. "Begin again" says exactly that and stays in
-- the register the rest of the game is written in. Two constants, so it is two
-- edits if you would rather it said something else.
Omerta.Injury.DEATH_TITLE = "You have died..."
Omerta.Injury.DEATH_PROMPT = "press any key to begin again"

Omerta.Injury.DEATH_TIMING = {
    BLACK_AT   = 4.2,  -- screen fully black
    BLACK_OVER = 2.6,  -- how long the fade to black takes
    TEXT_AT    = 5.0,  -- words start to appear
    TEXT_OVER  = 2.2,  -- how long they take to arrive
    MUSIC_FADE = 2.0,  -- the piano easing in once the words have landed
    LOOP_FADE  = 1.2,  -- the quick dip at each end of the loop
}

function Omerta.Injury.DeathFade(elapsed)
    local T = Omerta.Injury.DEATH_TIMING
    return math.Clamp(((elapsed or 0) - (T.BLACK_AT - T.BLACK_OVER)) / T.BLACK_OVER, 0, 1)
end

function Omerta.Injury.DeathTextAlpha(elapsed)
    local T = Omerta.Injury.DEATH_TIMING
    return math.Clamp(((elapsed or 0) - T.TEXT_AT) / T.TEXT_OVER, 0, 1)
end

-- The loop's own envelope: a quick dip at both ends so the seam is a breath
-- rather than a click.
function Omerta.Injury.LoopVolume(position, length, fade)
    if not (length and length > 0) then return 1 end
    fade = fade or Omerta.Injury.DEATH_TIMING.LOOP_FADE
    if fade * 2 >= length then return 1 end
    position = math.Clamp(position or 0, 0, length)
    if position < fade then return math.Clamp(position / fade, 0, 1) end
    local remaining = length - position
    if remaining < fade then return math.Clamp(remaining / fade, 0, 1) end
    return 1
end

--------------------------------------------------------------------------------
-- Dragging
--------------------------------------------------------------------------------
-- Nobody picks a grown man up and walks off with him. You take hold and you
-- HAUL, and the whole street watches you do it — which is the point: moving a
-- body has to be a commitment, not a pocket operation.
--
-- Modelled as a rope. There is slack, and while you are inside it nothing
-- happens; past it the line goes taut and starts pulling. The further you
-- lean, the harder it pulls and the more obvious it is you are doing it. Past
-- breaking length your grip fails.

Omerta.Injury.DRAG = {
    SLACK  = 52,   -- you can move this far before the line even goes tight
    TAUT   = 130,  -- fully taut here; past this you are hauling with everything
    BREAK  = 210,  -- and here your grip goes
}

-- 0 while there is slack, 1 when the line is as tight as it gets. Pure.
function Omerta.Injury.DragTension(distance, slack, taut)
    slack = slack or Omerta.Injury.DRAG.SLACK
    taut = taut or Omerta.Injury.DRAG.TAUT
    if taut <= slack then return 0 end
    return math.Clamp(((distance or 0) - slack) / (taut - slack), 0, 1)
end

function Omerta.Injury.DragBreaks(distance, breakAt)
    return (distance or 0) > (breakAt or Omerta.Injury.DRAG.BREAK)
end

-- How fast the body is pulled along, in units per second. Eases in so a body
-- creeps at first and only really moves once you are leaning on it.
function Omerta.Injury.DragSpeed(tension, maxSpeed)
    return (maxSpeed or 90) * (math.Clamp(tension or 0, 0, 1) ^ 1.5)
end

-- How fast a body may be pulled, derived from how fast its hauler can walk.
-- At a catchup of 1 the body keeps pace and the rope settles taut; below 1 it
-- falls steadily behind until the grip goes.
function Omerta.Injury.HaulSpeed(walkSpeed, dragScale, catchup)
    return (walkSpeed or 100) * (dragScale or 0.55) * (catchup or 1)
end

-- Hauling is heavy on purpose: it should be a decision, not a detour.
function Omerta.Injury.DragSpeedMultiplier(isDragging, scale)
    if not isDragging then return 1 end
    return math.max(0.05, tonumber(scale) or 0.55)
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
        { name = "seconds", type = "uint", bits = 12 }, -- remaining; 0 = no clock
        { name = "total",   type = "uint", bits = 12 }, -- the whole window
    },
    handler = function(payload)
        local state = Omerta.Injury.STATE_BY_INDEX[payload.state]
        hook.Run("Omerta.InjuryUpdated", state, payload.seconds, payload.total)
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

-- Which entity in the world is you. Sent only to the character it belongs to,
-- so the client can hang its camera on its own head — nobody is ever told
-- whose body somebody else's is.
Omerta.Net.Register("injury.body", {
    realm = "server_to_client",
    schema = { { name = "body", type = "uint", bits = 16 } },
    handler = function(payload)
        hook.Run("Omerta.InjuryBody", payload.body)
    end,
})

-- Death, with where it happened, so the camera has somewhere to pull back to.
Omerta.Net.Register("injury.died", {
    realm = "server_to_client",
    schema = {
        { name = "body", type = "uint", bits = 16 },
        { name = "x", type = "int", bits = 20 },
        { name = "y", type = "int", bits = 20 },
        { name = "z", type = "int", bits = 20 },
    },
    handler = function(payload)
        hook.Run("Omerta.CharacterDiedLocally", payload.body,
            Vector(payload.x, payload.y, payload.z))
    end,
})

-- "I have watched the end." Nothing but an acknowledgement: the character is
-- already dead server-side, and this only decides when the new-character flow
-- may begin.
Omerta.Net.Register("injury.acknowledge_death", {
    realm = "client_to_server",
    schema = {},
    rate = { burst = 3, per = 10 },
    handler = function(ply)
        if Omerta.Injury.Internal.AcknowledgeDeath then
            Omerta.Injury.Internal.AcknowledgeDeath(ply)
        end
    end,
})

-- Which body this player has hold of, and where they took hold of it.
--
-- The tension itself is NOT networked: the client has both positions and the
-- rule is pure and shared, so it computes the same number the server does,
-- every frame, for free. The server still enforces — the client only draws.
Omerta.Net.Register("injury.dragging", {
    realm = "server_to_client",
    schema = {
        { name = "body", type = "uint", bits = 16 }, -- 0 = let go
        { name = "x", type = "int", bits = 20 },
        { name = "y", type = "int", bits = 20 },
        { name = "z", type = "int", bits = 20 },
    },
    handler = function(payload)
        hook.Run("Omerta.InjuryDragging", payload.body,
            Vector(payload.x, payload.y, payload.z))
    end,
})

Internal.TRANSITIONS = TRANSITIONS
