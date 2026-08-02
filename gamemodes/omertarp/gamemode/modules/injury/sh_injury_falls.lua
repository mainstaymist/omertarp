-- Falling, breaking a leg, and walking on it afterwards. The pure half.
--
-- Named sh_injury_falls rather than sh_falls for the reason sh_weapons_arsenal
-- carries in its own header: module files load ALPHABETICALLY within a realm,
-- and "falls" sorts before "injury" — this file would have run before the state
-- machine it extends existed. The prefix is the fix that cannot regress.
--
-- Everything here is arithmetic, and it is here so the headless suite can pin
-- it. Two of the three things in this file are the kind that get retuned in the
-- field six months from now — the fall curve and the limp — which is precisely
-- why neither may live inside the function that consumes it.
--
-- THE SHAPE OF A FALL, in one sentence: how far you fell decides what KIND of
-- thing happens (nothing, hurt, hurt and a broken leg, or on the floor), and
-- within every one of those the damage keeps climbing with the distance. The
-- bands are cut points on one continuous line, not three flat outcomes.

Omerta.Injury = Omerta.Injury or {}

--------------------------------------------------------------------------------
-- How far did they fall?
--------------------------------------------------------------------------------
-- The engine hands us an impact SPEED, and the project lead asked for damage
-- relative to a DISTANCE. Those are the same fact twice: a body falling freely
-- arrives at sqrt(2gh), so h = v² / 2g and the conversion is exact.
--
-- Working in height rather than speed matters for one practical reason. A
-- height is a number an operator can pace out in the map — a Half-Life 2 player
-- is 72 units tall, so a unit is about an inch and a storey is about 128 — and
-- `injury.fall_break_height 340` is therefore a sentence somebody can check. An
-- impact speed of 639 units/second is not.

-- Source's default sv_gravity. Read from the cvar at the call site; this is the
-- answer when there is no engine to ask (the headless suite, and a server whose
-- cvar has been set to something impossible).
Omerta.Injury.FALL_GRAVITY = 600

function Omerta.Injury.FallHeight(speed, gravity)
    speed = tonumber(speed) or 0
    if speed ~= speed or speed <= 0 then return 0 end -- NaN, or going upward
    gravity = tonumber(gravity) or Omerta.Injury.FALL_GRAVITY
    if not gravity or gravity ~= gravity or gravity <= 0 then
        gravity = Omerta.Injury.FALL_GRAVITY
    end
    return (speed * speed) / (2 * gravity)
end

--------------------------------------------------------------------------------
-- The curve
--------------------------------------------------------------------------------
-- Three knots and two straight segments:
--
--     (safe, 0) ---- (breakAt, breakDamage) ---- (downAt, downDamage)
--
-- Below `safe` nothing happens at all. From there the damage climbs
-- CONTINUOUSLY to `downAt`, and past `downAt` it stops climbing because there
-- is nothing worse to be than on the floor.
--
-- Continuous is the point. A step at a band edge would mean one unit of height
-- costing eight points of health, which is the shape of thing that gets
-- reported as a bug and is impossible to argue with when it is.

Omerta.Injury.FALL_BAND = {
    NONE   = "none",   -- you walk it off
    LOW    = "low",    -- health taken, the leg holds
    MEDIUM = "medium", -- more health taken, and the leg goes
    HIGH   = "high",   -- the leg goes and so do you, whatever your health was
}

-- Assembles a curve from five configured numbers, and makes them behave.
--
-- Omerta.Config validates each key against its own min/max and cannot see the
-- RELATIONSHIP between two keys — so an operator who sets the break height
-- above the down height gets an inverted curve unless somebody normalises. The
-- normalisation is here, in the pure function, rather than at the call site,
-- because it is part of what the curve MEANS and it is worth a test of its own.
function Omerta.Injury.FallCurve(safe, breakAt, downAt, breakDamage, downDamage)
    safe = math.max(tonumber(safe) or 0, 0)
    breakAt = math.max(tonumber(breakAt) or 0, safe + 1)
    downAt = math.max(tonumber(downAt) or 0, breakAt + 1)
    breakDamage = math.max(tonumber(breakDamage) or 0, 0)
    -- The curve may never fall as it rises: a higher fall that hurt less would
    -- make the safest thing to do jump from further up.
    downDamage = math.max(tonumber(downDamage) or 0, breakDamage)
    return {
        safe = safe, breakAt = breakAt, downAt = downAt,
        breakDamage = breakDamage, downDamage = downDamage,
    }
end

-- WHICH SIDE OF A THRESHOLD IS WHICH, stated once so nothing has to guess.
-- A configured height is the height at which the thing NAMED by the key
-- happens: at exactly `fall_break_height` the leg breaks, at exactly
-- `fall_down_height` you are on the floor. Below `fall_safe_height` — strictly
-- below — nothing at all.
function Omerta.Injury.FallBand(height, curve)
    height = tonumber(height) or 0
    if height ~= height then return Omerta.Injury.FALL_BAND.NONE end -- NaN
    if height < curve.safe then return Omerta.Injury.FALL_BAND.NONE end
    if height < curve.breakAt then return Omerta.Injury.FALL_BAND.LOW end
    if height < curve.downAt then return Omerta.Injury.FALL_BAND.MEDIUM end
    return Omerta.Injury.FALL_BAND.HIGH
end

-- Whole points, like every other damage number in the game (the Model 10 does
-- 34, the Thompson 13). Rounded HERE rather than at the call site so the suite
-- can pin the integer a player actually loses, which is the number that decides
-- which of M19's bands they land in.
function Omerta.Injury.FallDamage(height, curve)
    height = tonumber(height) or 0
    if height ~= height then return 0 end -- NaN
    if height <= curve.safe then return 0 end

    local value
    if height <= curve.breakAt then
        value = curve.breakDamage
            * (height - curve.safe) / (curve.breakAt - curve.safe)
    elseif height >= curve.downAt then
        value = curve.downDamage
    else
        value = curve.breakDamage + (curve.downDamage - curve.breakDamage)
            * (height - curve.breakAt) / (curve.downAt - curve.breakAt)
    end
    return math.floor(value + 0.5)
end

--------------------------------------------------------------------------------
-- The leg
--------------------------------------------------------------------------------
-- A broken leg is a CONDITION, not a state. M19's states are one ladder — the
-- situation you are in, from upright to dead — and a condition rides alongside
-- them: you can have a broken leg while healthy, while hurt, while bleeding out
-- on a pavement, and it is still the same broken leg. M19 §9 wrote this down in
-- advance ("permanent impairments attach to character_injury ... with no change
-- to the state machine") and this is that entry being cashed.
--
-- Named rather than boolean because Tech §17's impairments are a list and the
-- second one should cost a row, not a schema.
Omerta.Injury.IMPAIRMENT = {
    LEG = "leg",
}

-- THE SOUND, and the reason it is a function.
--
-- A sound path that is registered for download and a sound path that is played
-- must be the same string, and the way that goes wrong is a typo in one of them
-- — which is silent, forever, on everybody's machine but the developer's. One
-- function answers both questions, so they cannot disagree, and the suite pins
-- the three names against the three files that are actually on disk.
Omerta.Injury.LEG_BREAK_SOUNDS = 3

function Omerta.Injury.LegBreakSound(index)
    index = math.floor(tonumber(index) or 1)
    if index < 1 or index > Omerta.Injury.LEG_BREAK_SOUNDS then index = 1 end
    return "omertarp/injury/leg-break-" .. index .. ".wav"
end

--------------------------------------------------------------------------------
-- The limp
--------------------------------------------------------------------------------
-- "Walk slower then faster" — an uneven gait, not a flat speed penalty. The
-- whole difficulty is that a speed which changes for no visible reason reads as
-- NETWORK LAG, and the fix is that the reason has to be visible: the change is
-- tied to the stride, it happens the same way every stride, and the camera
-- moves with it so the eye is told what the legs are doing.
--
-- THE PHASE IS DRIVEN BY DISTANCE, NOT BY TIME, and that is the load-bearing
-- decision in this section. Three things follow from it and none of them would
-- follow from a clock:
--
--   * standing still cannot limp. A stationary player travels no distance, the
--     phase does not advance, and there is nothing to see or feel. A timer
--     would have the camera rocking a man who is stood at a bar.
--   * the gait does not change cadence with speed the way a timed one would.
--     One cycle is one stride, whether it is walked or hurried.
--   * the client can compute the same number the server enforces with, from its
--     own position, every frame, for free — exactly the arrangement the drag
--     rope already uses (sh_injury, "the tension is NOT networked"). Nothing
--     about the limp goes on the wire except the one bit that says the leg is
--     broken at all.
--
-- These are GEOMETRY, so they are constants rather than configuration, and
-- they are constants for a concrete reason: the client needs them too, and
-- Omerta.Config is server-scope and does not replicate (D-036 and sh_config).
-- A stride length that only the server knew would put the camera out of step
-- with the legs. How SLOW and how UNEVEN — the gameplay half — is configuration
-- and lives on the server alone, where it is applied.
Omerta.Injury.LIMP = {
    -- Units of ground covered per gait cycle. At a limping ~68 units/second
    -- that is a cycle a little over a second long, which is the cadence of
    -- somebody favouring a leg rather than somebody marching. Measured in
    -- GROUND, so retuning how slow a limp is (injury.limp_speed_scale) changes
    -- how long a cycle takes and never how far it covers — one stride stays
    -- one stride.
    STRIDE = 78,
    -- How much of the stride it takes to get from the slowest point up to the
    -- push. Well under a half on purpose: a limp is a SHORT SHOVE off the sound
    -- leg followed by a LONG SETTLE back onto the bad one, and reversing those
    -- two durations is the difference between favouring a leg and skipping.
    PUSH_SHARE = 0.34,
    -- The camera, and it is deliberately small. The screen belongs to the
    -- player; this is a hint that something is wrong with a leg, not a ride.
    DIP  = 1.6,  -- units the head drops as the bad leg takes the weight
    ROLL = 0.9,  -- degrees of lean onto the sound side
    -- Ground speed at which the bob is at full size. Below it the bob scales
    -- down with the speed, so easing to a halt eases the camera to a halt with
    -- it rather than stopping it mid-lurch.
    FULL_AT = 45,
}

-- Skews the cycle so the shove is short and the settle is long.
--
-- Returns a 0..1 position around the gait, where 0 and 1 are the moment the bad
-- leg is fully loaded (slowest, head lowest) and 0.5 is the push off the good
-- one (fastest, head level). Everything that draws or moves a limping character
-- consumes a cosine of this, and BOTH KNOTS SIT EXACTLY ON AN EXTREME OF THAT
-- COSINE — which is what leaves the composed curve with no corner at either of
-- them. A corner is a jerk, and a jerk is the thing that reads as a dropped
-- packet rather than as a leg.
--
-- What the warp does and does not buy, stated plainly because it is easy to
-- overclaim: exactly half of every stride is below the middle of the gait, and
-- no value of `pushShare` changes that. What it changes is how a character gets
-- between the two — a quick heave up onto the sound leg and a long ease back
-- down onto the bad one. That asymmetry is the whole difference between a limp
-- and a waddle; the first version of this was a plain symmetric cosine and read
-- as exactly that.
function Omerta.Injury.LimpWarp(phase, pushShare)
    phase = tonumber(phase) or 0
    if phase ~= phase then return 0 end -- NaN
    phase = math.Clamp(phase, 0, 1)
    pushShare = math.Clamp(tonumber(pushShare) or Omerta.Injury.LIMP.PUSH_SHARE,
        0.05, 0.95)
    if phase < pushShare then return 0.5 * (phase / pushShare) end
    return 0.5 + 0.5 * (phase - pushShare) / (1 - pushShare)
end

-- Where in the gait a character is, from how far they have walked. Pure, so
-- both realms get the same answer from their own measurement of the same walk.
function Omerta.Injury.LimpPhase(distance, stride)
    stride = tonumber(stride) or Omerta.Injury.LIMP.STRIDE
    if not stride or stride ~= stride or stride <= 0 then return 0 end
    distance = tonumber(distance) or 0
    if distance ~= distance then return 0 end -- NaN
    local phase = (distance % stride) / stride
    if phase < 0 then phase = phase + 1 end
    return phase
end

-- The speed multiplier, one gait cycle wide.
--
-- `mid` is the middle of the gait — call it the average pace of a limp — and
-- `swing` is how far either side of it the two legs go. Slowest at phase 0
-- (weight on the bad leg), fastest half a warped cycle later (pushing off the
-- good one), and back. The lead's "slower then faster", written as one number.
--
-- The swing is clamped against the middle rather than trusted, because a swing
-- that reached the middle would stop somebody dead for part of every stride —
-- and a character who stops dead is not limping, they are stuck. Same floor of
-- 0.05 the drag multiplier uses, for the same reason.
function Omerta.Injury.LimpSpeedMultiplier(phase, mid, swing, pushShare)
    mid = tonumber(mid) or 1
    swing = math.max(tonumber(swing) or 0, 0)
    swing = math.min(swing, math.max(0, mid - 0.05))
    local warped = Omerta.Injury.LimpWarp(phase, pushShare)
    return math.max(0.05, mid - swing * math.cos(2 * math.pi * warped))
end

-- How much of the bob to draw, from how fast the character is actually moving.
-- Zero when they are not, which is the whole reason this is a separate
-- function: "does not fire while standing still" is a rule worth being able to
-- test on its own rather than an `if` buried in a draw call.
function Omerta.Injury.LimpIntensity(groundSpeed)
    local full = Omerta.Injury.LIMP.FULL_AT
    if not full or full <= 0 then return 0 end
    groundSpeed = tonumber(groundSpeed) or 0
    if groundSpeed ~= groundSpeed then return 0 end -- NaN
    return math.Clamp(groundSpeed / full, 0, 1)
end

-- The camera. Returns a vertical offset in units (negative: the head drops) and
-- a roll in degrees.
--
-- ONE-SIDED, like M19's heartbeat and for the same reason: (1 + cos) / 2 runs
-- 1..0..1, so the head only ever drops from where it was and comes back, never
-- rises above the resting eye line. A symmetric bob would lift the camera on
-- the good leg, which reads as a bounce — a man enjoying himself rather than a
-- man dragging a foot.
--
-- The dip and the lean share one term deliberately. They are one event: the bad
-- leg takes the weight, the body sinks onto it and leans off it.
function Omerta.Injury.LimpBob(phase, intensity, pushShare)
    intensity = tonumber(intensity) or 0
    if intensity ~= intensity then return 0, 0 end -- NaN
    intensity = math.Clamp(intensity, 0, 1)
    if intensity <= 0 then return 0, 0 end

    local warped = Omerta.Injury.LimpWarp(phase, pushShare)
    local weight = (1 + math.cos(2 * math.pi * warped)) * 0.5
    local L = Omerta.Injury.LIMP
    return -L.DIP * intensity * weight, L.ROLL * intensity * weight
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------
-- One bit and a clock, private to its owner, exactly like injury.state and for
-- exactly M6's reason: whether the man across the street is walking on a broken
-- leg is something you find out by watching him walk, not by reading it off his
-- entity. He limps in front of everybody — the server slows him down and every
-- client sees that — and nothing about WHY is networked to anyone but him.
--
-- The gait itself is not on the wire either. The client accumulates its own
-- distance and runs the same pure functions the server does, which is the
-- arrangement the drag rope has used since §14c.
Omerta.Net.Register("injury.leg", {
    realm = "server_to_client",
    schema = {
        { name = "broken",  type = "bool" },
        -- Seconds left before it has knitted. Sent so the client stops limping
        -- on time even if the healing message is late or lost — the §14b
        -- lesson, where a clock that was pushed once and never again left the
        -- screen frozen at the value it started with.
        { name = "seconds", type = "uint", bits = 16 },
    },
    handler = function(payload)
        hook.Run("Omerta.InjuryLegUpdated", payload.broken, payload.seconds)
    end,
})
