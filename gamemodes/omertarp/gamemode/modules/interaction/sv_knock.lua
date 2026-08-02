-- Server side of knocking: the engine edge only. Every rule this file applies
-- is defined in sh_knock.lua and tested headless; what lives here is the trace,
-- the sound, and the content registration.
--
-- Server-authoritative, in the same shape as the rest of the interaction
-- module. The client contributes one bit — the attack button went down — and
-- contributes it through the engine's own predicted attack path, which the
-- server runs itself from the usercmd. Everything that decides whether a noise
-- happens is below: whether the character exists, whether their hands are
-- empty, whether they are actually facing a door within reach, and whether
-- that door is still sounding from the last knock.
--
-- There is deliberately NO net message for this. One was considered and
-- rejected: it would be a second, forgeable route to the same sound, reachable
-- while holding a Thompson and standing nowhere near a door, and it would need
-- a rate limit to make it as hard to abuse as the path we already get for free.
-- SWEP:PrimaryAttack is the codebase's existing "the trigger was pulled"
-- channel — weapon_omerta_base counts ammunition and fires Omerta.WeaponFired
-- off exactly this path — and the engine bounds its rate with
-- SetNextPrimaryFire before a single line of ours runs.

local MODULE = Omerta.Module.Get("interaction")

Omerta.Knock = Omerta.Knock or {}
local Knock = Omerta.Knock

-- One lockout for the map, keyed by entity index.
--
-- Indices are recycled, so an index freed and reissued inside the length of one
-- knock would hand a brand-new entity up to 1.44s of somebody else's lockout.
-- The cost of that is a single swallowed knock, and map doors are never removed
-- anyway; carrying the entity around to detect it would buy nothing. The table
-- is bounded by the number of doors on the map, so it is never cleaned.
local lockout = Knock.NewLockout()

-- You knock with a bare hand. The weapons module owns that class name, and it
-- loads AFTER this one (weapons -> inventory -> interaction), so it is read at
-- call time rather than captured at file scope.
--
-- No fallback literal: if the weapons module is not present then nobody is
-- holding our hands, nobody is holding our anything, and nobody knocks. A
-- second copy of the string here would be a second thing to keep in step.
local function isBareHanded(ply)
    local hands = Omerta.Weapons and Omerta.Weapons.HANDS
    if not hands then return false end
    local wep = ply:GetActiveWeapon()
    return IsValid(wep) and wep:GetClass() == hands
end

-- What the character is actually reaching for. The client's aim arrives in the
-- usercmd, but the trace is run HERE — a client cannot nominate a door.
local function doorInReach(ply)
    local tr = util.TraceLine({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * Knock.RANGE,
        filter = ply,
    })
    if not Knock.IsKnockable(tr.Entity) then return nil end
    return tr.Entity
end

--------------------------------------------------------------------------------
-- Who hears it
--------------------------------------------------------------------------------
-- DECIDED HERE, rather than by the engine's visibility system.
--
-- Entity:EmitSound with no filter of its own builds a CPASAttenuationFilter:
-- the potentially-audible set around the door, intersected with a distance
-- cutoff taken from the sound level. The distance half was never the problem —
-- it is generous, and Knock.AudibleRadius is that same arithmetic. The PAS half
-- is the problem, and it is the problem in precisely the place this feature
-- lives.
--
-- The PAS is derived from the map's compiled visibility, and a Source map
-- optimises a doorway by tying a func_areaportal to the door — which SEVERS the
-- two sides of that doorway in the visibility data whenever the door is shut. A
-- knock is a noise made specifically to be heard through a shut door, so the
-- single case the feature exists for is the single case the engine is built to
-- cut. That is the "heard from both sides" half of the report, and it is not a
-- volume problem at all: those listeners were never sent the sound.
--
-- So the recipients are chosen by DISTANCE, in the open, at the engine's own
-- radius. The engine still does the falloff, and it still positions the sound at
-- the door; all that changes is who is handed the message.
--
-- Ears, not feet: EyePos is where a listener actually is, and on a stairwell the
-- difference between the two is most of a floor.
local function audience(door)
    local filter = RecipientFilter()
    local origin = door:WorldSpaceCenter()
    local reach = Knock.AudibleRadius(Knock.SOUND_LEVEL)
    reach = reach * reach

    for _, ply in ipairs(player.GetAll()) do
        if ply:EyePos():DistToSqr(origin) <= reach then
            filter:AddPlayer(ply)
        end
    end
    return filter
end

-- The trailing recipient-filter argument is a comparatively recent addition to
-- Entity:EmitSound, and this was written on a machine with no engine to check it
-- against. A build that will not take it must not lose the knock — so a rejected
-- call falls back to the plain emit, which is exactly the behaviour that shipped
-- last week, and SAYS SO once. Silently doing less than the comment above claims
-- is the one outcome that would be worse than either.
--
-- The argument is validated before anything sounds, so the fallback cannot
-- double up: either the filtered call played it or nothing did.
local filterRefused = false

local function emit(door)
    if not filterRefused then
        local ok, err = pcall(door.EmitSound, door,
            Knock.SOUND, Knock.SOUND_LEVEL, Knock.SOUND_PITCH,
            Knock.SOUND_VOLUME, CHAN_STATIC, 0, 0, audience(door))
        if ok then return end

        filterRefused = true
        Omerta.Log.Warn("knock",
            "this build will not take a recipient filter on EmitSound (%s) — " ..
            "knocks fall back to the engine's PAS, which a closed areaportal cuts",
            tostring(err))
    end

    door:EmitSound(Knock.SOUND, Knock.SOUND_LEVEL, Knock.SOUND_PITCH,
        Knock.SOUND_VOLUME, CHAN_STATIC)
end

-- Knock, if everything about the moment allows it. Returns true, or false plus
-- a reason — for the log and for tests, never for the player: a refusal that
-- reached the screen would answer questions ("is anyone in there?", "is that a
-- real door?") that a character standing outside cannot answer.
function Knock.Attempt(ply)
    if not Omerta.InEngine then return false, "not in engine" end
    if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) then
        return false, "no knocker"
    end
    if not (Omerta.Characters and Omerta.Characters.IsLoaded(ply)) then
        return false, "no character"
    end
    if not isBareHanded(ply) then return false, "hands are full" end

    local door = doorInReach(ply)
    if not door then return false, "nothing to knock on" end

    local claimed, remaining = Knock.Claim(lockout, door:EntIndex(), CurTime())
    if not claimed then
        Omerta.Log.Debug("knock", "door %d still sounding (%.2fs left)",
            door:EntIndex(), remaining)
        return false, "still sounding"
    end

    -- From the DOOR, into the world, at full volume and a fixed pitch (see
    -- sh_knock.lua), to everyone within earshot on either side of it (see
    -- `audience` above). Anyone near enough hears a knock; nobody learns
    -- anything else, including the people who can already see who is standing
    -- there — they learn it with their eyes, which is the point.
    emit(door)
    return true
end

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    -- Mounting makes the file available to the SERVER; only this sends it to
    -- clients. Registered by the module that plays it, in the change that
    -- starts playing it, exactly as content/README.md asks.
    resource.AddFile(Knock.SOUND_FILE)
end
