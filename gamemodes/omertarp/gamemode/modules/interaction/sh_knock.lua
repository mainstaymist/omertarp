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

-- Emitted at ordinary speech level: audible through a doorway and down a short
-- hall, not across the street. A knock that carried further would tell people
-- in the next building something they have no business hearing.
Knock.SOUND_LEVEL = 75

-- Fixed, and load-bearing rather than cosmetic: pitch scales playback SPEED, so
-- a randomised pitch would make the real duration differ from SOUND_SECONDS and
-- the lockout would be wrong in whichever direction the dice fell.
Knock.SOUND_PITCH = 100

-- Arm's reach. Well inside Omerta.Interaction.MAX_RANGE (256) on purpose: you
-- knock on a door you are standing at, not one you can see down a corridor.
Knock.RANGE = 96

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
