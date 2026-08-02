-- Knocking on a door.
--
-- A knock is the cleanest example in the game of the rule everything else here
-- is built to protect: a player must never learn something their character
-- could not reasonably know. Somebody inside a room hears a noise at the door
-- and learns EXACTLY that — not who is out there, not how many, not whether
-- they are armed. So nothing about the knocker travels: no name, no HUD
-- element, no notice, no networked "somebody is at the door". The sound is
-- emitted from the DOOR, into the world, and whoever is close enough to hear
-- it hears it. That is the entire information channel, and it is deliberately
-- the same channel a real knock has.
--
-- WHERE THE RULE LIVES. `weapon_omerta_hands` owns one fact — the attack
-- button went down while the character's hands were empty. Everything else is
-- here: what a knock is, what may be knocked on, how loud it is, and how often
-- it may happen. A SWEP that knew any of that would be a game rule hidden
-- inside a viewmodel, and the next thing that wants to knock (a nightstick, an
-- NPC, a scripted event) would have to reimplement it.
--
-- This file is deliberately pure — no entities, no engine calls, no
-- constructors — so the headless suite can drive the whole rule. The engine
-- edge (the trace, the sound, the content registration) is sv_knock.lua.

Omerta.Knock = Omerta.Knock or {}
local Knock = Omerta.Knock

--------------------------------------------------------------------------------
-- The sound
--------------------------------------------------------------------------------

-- Playback path (what EmitSound is given) and content path (what
-- resource.AddFile is given). They differ by the `sound/` prefix — see
-- content/README.md, which is where that trap is documented.
Knock.SOUND = "omertarp/world/door-knock.wav"
Knock.SOUND_FILE = "sound/omertarp/world/door-knock.wav"

-- THE MEASURED LENGTH OF THE FILE ABOVE, IN SECONDS. Measured, not estimated.
--
-- This one number is the lockout: a knock may not start until the previous one
-- on that door has finished sounding, because two overlapping knocks are a
-- garbled noise rather than two knocks. Re-record the wav and this is the only
-- line that changes — the SWEP does not know it, the server does not restate
-- it, and the tests pin it so a re-record cannot quietly desync from it.
--
-- Deliberately NOT a config key. It is a property of the asset, not a taste an
-- operator holds; a server that set it to 0.5 would simply reintroduce the
-- overlap this exists to prevent.
Knock.SOUND_SECONDS = 1.44

-- FULL VOLUME, written down rather than left as a bare 1 at the call site.
--
-- "If it's manually lowered from original just make it original" was the brief,
-- and the honest answer is that it never was lowered: the emit has always
-- passed 1, and the asset is a hot master — it peaks at 0 dBFS and runs about
-- -12 dBFS RMS across the four raps. There is no headroom above this either,
-- because EmitSound clamps volume at 1. So if a knock is ever wanted louder
-- than the level below can make it, the change is to the WAV and not to a
-- number in this file. Stated here so the next person reading "it's too quiet"
-- does not spend an afternoon hunting for the multiplier stealing it.
Knock.SOUND_VOLUME = 1

-- HOW FAR IT CARRIES, which is a different quantity from how loud it is.
--
-- This was 75 — SNDLVL_NORM, the level of a spoken sentence — and that was the
-- real defect behind the "too quiet" report. A fist on a wooden panel is not a
-- spoken sentence, and the two do not carry the same distance. Volume sets the
-- gain at the source; the sound LEVEL sets how quickly that gain is thrown away
-- with distance and how far away the engine stops sending the sound at all, and
-- it was the one tuned for a conversation.
--
-- 85 is Source's SNDLVL_85dB. It buys roughly 40% more earshot and 40% more
-- gain at any given distance, which is the difference between a knock heard by
-- whoever is standing at the door and a knock heard by whoever is in the room,
-- in the hall, or up the stairs — the people a knock is actually addressed to.
--
-- The original rule survives the change and is worth restating, because it is
-- the reason this is 85 and not 140: a knock must not reach the next building.
-- Somebody a street away learning that a door somewhere was knocked on is being
-- told something their character cannot hear.
Knock.SOUND_LEVEL = 85

-- Fixed, and load-bearing rather than cosmetic: pitch scales playback SPEED, so
-- a randomised pitch would make the real duration differ from SOUND_SECONDS and
-- the lockout would be wrong in whichever direction the dice fell.
Knock.SOUND_PITCH = 100

-- Arm's reach. Well inside Omerta.Interaction.MAX_RANGE (256) on purpose: you
-- knock on a door you are standing at, not one you can see down a corridor.
Knock.RANGE = 96

--------------------------------------------------------------------------------
-- How far a knock is worth sending
--------------------------------------------------------------------------------
-- Two lines of Source's own arithmetic, restated here so the server can apply
-- them itself rather than asking the engine to. sv_knock.lua explains why it
-- must; this is only the sum.
--
--   soundflags.h            attenuation = level > 50 and 20 / (level - 50) or 4
--   CPASAttenuationFilter   a listener is dropped past (2 * 1000) / attenuation
--
-- Restating an engine constant is normally the wrong move and it is done here
-- for exactly one reason: the alternative is a radius somebody invented, which
-- either drops listeners the engine would have kept — a knock that goes unheard
-- for no reason anybody could find — or carries to people the falloff has
-- already silenced, which is packets spent on nothing. Taking the engine's own
-- number means our audience is precisely the engine's audience minus the
-- visibility test, and that difference is the entire change.
--
-- This is a NETWORKING cutoff and not the distance a knock is loud at. Past a
-- little over a third of it the gain is already negligible; the radius is the
-- point beyond which sending the message is pointless, not the point where the
-- sound arrives.

function Knock.Attenuation(level)
    level = tonumber(level) or Knock.SOUND_LEVEL
    if level ~= level then return 4 end -- NaN
    if level <= 50 then return 4 end
    return 20 / (level - 50)
end

function Knock.AudibleRadius(level)
    return 2000 / Knock.Attenuation(level)
end

--------------------------------------------------------------------------------
-- What counts as a door
--------------------------------------------------------------------------------
-- Data, not a class list buried in a function — the same shape as
-- Omerta.Inventory.RegisterOpenable, for the same reason: the next thing worth
-- knocking on (a shutter, a hatch, a cell gate, a car window) should be one
-- registration in the module that owns it, not an edit here.
--
-- `fn` is optional. A class registered without one is knockable outright,
-- which is the common case and keeps the registrations one line each. A class
-- whose entities are not ALL doors passes a function and answers per entity,
-- exactly as RegisterInteractablePredicate does for M19's ragdoll bodies.

local knockables = {}

function Knock.RegisterKnockable(class, fn)
    if type(class) ~= "string" or class == "" then
        error("knockable class must be a non-empty string", 2)
    end
    if fn ~= nil and type(fn) ~= "function" then
        error("knockable '" .. class .. "' refinement must be a function", 2)
    end
    knockables[class] = fn or true
end

-- Returns true if this entity is something a person could knock on.
--
-- Note what is NOT consulted: whether the door is locked. Knocking on a locked
-- door is the entire point of knocking — an unlocked door you simply open. A
-- lock check here would delete the feature for precisely the case it exists
-- for, and would leak the lock state besides: a player who learned that
-- knocking was unavailable would have learned the door was open, which is
-- something their character cannot see from outside.
function Knock.IsKnockable(ent)
    if not IsValid(ent) then return false end
    if type(ent.GetClass) ~= "function" then return false end

    local entry = knockables[ent:GetClass()]
    if entry == nil then return false end
    if entry == true then return true end

    -- A refinement that errors REFUSES, rather than accidentally making every
    -- entity of its class knockable because of a typo in somebody else's
    -- module. Omerta.Inventory.MayOpen takes the same stance.
    local ok, allowed = pcall(entry, ent)
    if not ok then return false end
    return allowed == true
end

--------------------------------------------------------------------------------
-- The lockout — PER DOOR, not per player
--------------------------------------------------------------------------------
-- The brief was "it has to play all the way through before they start, to
-- prevent overlap". Overlap is a property of a PLACE: two people hammering on
-- the same door at once is the garbled noise; one person knocking on this door
-- while somebody across town knocks on that one is two knocks, and nobody
-- hears them together.
--
-- So the lockout belongs to the door. Per player would be both too weak and
-- too strong at once — it would still let two players overlap on the same door
-- (the actual failure), and it would stop one player knocking on the door next
-- to the one they just tried (not a failure at all: a man working his way
-- along a row of doors is a scene, not a bug).
--
-- A lockout is a plain table of key -> when that key's knock started. The
-- server keys it by entity index; the suite keys it by whatever it likes.

function Knock.NewLockout()
    return {}
end

-- Pure arithmetic: seconds still to run on a knock that began at `startedAt`.
-- 0 means the sound has finished and the door is free.
function Knock.Remaining(startedAt, now, duration)
    if type(startedAt) ~= "number" then return 0 end
    if type(now) ~= "number" then return 0 end
    duration = tonumber(duration) or Knock.SOUND_SECONDS

    -- A clock that has gone BACKWARDS is a map change: CurTime restarts at
    -- zero, and stale entries would otherwise lock every door that was knocked
    -- on before the change for the length of the old timestamp — potentially
    -- hours. Treat it as finished.
    if now < startedAt then return 0 end

    local remaining = startedAt + duration - now
    if remaining <= 0 then return 0 end
    return remaining
end

-- The rule. Claims the right to make a noise at `key` at time `now`.
-- Returns true, having recorded the knock — or false plus the seconds still to
-- run, so a caller that wants to say something about the wait can.
--
-- Takes no player on purpose: who is knocking is not an input to whether the
-- door may sound, and a signature that accepted one would invite somebody to
-- start keying on it.
function Knock.Claim(lockout, key, now, duration)
    if type(lockout) ~= "table" then return false, 0 end
    if key == nil then return false, 0 end

    local remaining = Knock.Remaining(lockout[key], now, duration)
    if remaining > 0 then return false, remaining end

    lockout[key] = now
    return true
end

--------------------------------------------------------------------------------
-- The doors the base game ships
--------------------------------------------------------------------------------
-- Every mappers' door in Source is one of these three. Registered as data,
-- with no refinement function, because every entity of each class IS a door.

Knock.RegisterKnockable("prop_door_rotating") -- the standard HL2 door prop
Knock.RegisterKnockable("func_door")          -- brush doors, mostly sliding
Knock.RegisterKnockable("func_door_rotating") -- brush doors on a hinge
