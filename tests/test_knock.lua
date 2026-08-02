-- Knocking on a door.
--
-- Two things are worth pinning here and nothing else is: the lockout
-- arithmetic, because "the sound must finish before the next one starts" is a
-- claim about a number that no amount of playing the game will prove; and the
-- knockable registry, because the moment it stops being data it becomes a
-- class list buried in a function.
--
-- The engine edge (sv_knock.lua's trace and EmitSound) is loaded so it is at
-- least known to parse and to bind its lifecycle, but it is not driven: every
-- decision it makes is delegated to the pure half below.

local MODULE_FILES = {
    "gamemodes/omertarp/gamemode/modules/interaction/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sh_knock.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sv_knock.lua",
}

local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

-- An entity, as much of one as any of this needs.
local function entity(class, fields)
    local ent = fields or {}
    ent.GetClass = function() return class end
    return ent
end

--------------------------------------------------------------------------------
suite("knock.duration")
--------------------------------------------------------------------------------

check("the lockout is the measured length of the sound file", function()
    loadModules()
    -- door-knock.wav is 1.440s, measured. If the asset is re-recorded this is
    -- the line that has to change, and it is the only one: nothing else in the
    -- tree restates the number.
    assert(Omerta.Knock.SOUND_SECONDS == 1.44,
        "expected 1.44s, got " .. tostring(Omerta.Knock.SOUND_SECONDS))
end)

check("the playback path and the content path differ by the sound/ prefix", function()
    loadModules()
    -- EmitSound is given one, resource.AddFile the other. Getting this wrong
    -- is silent: the sound simply never reaches a client.
    assert(Omerta.Knock.SOUND == "omertarp/world/door-knock.wav",
        "playback path is " .. tostring(Omerta.Knock.SOUND))
    assert(Omerta.Knock.SOUND_FILE == "sound/" .. Omerta.Knock.SOUND,
        "content path is " .. tostring(Omerta.Knock.SOUND_FILE))
end)

check("pitch is fixed, because pitch scales duration", function()
    loadModules()
    -- A randomised pitch would make the real playback length differ from
    -- SOUND_SECONDS, and the lockout would be wrong by however much.
    assert(Omerta.Knock.SOUND_PITCH == 100,
        "knock pitch must stay at 100, got " .. tostring(Omerta.Knock.SOUND_PITCH))
end)

check("a knock is only offered at arm's reach", function()
    loadModules()
    assert(Omerta.Knock.RANGE > 0, "range must be positive")
    assert(Omerta.Knock.RANGE <= 128,
        "you knock on a door you are standing at, not one down a corridor: " ..
        tostring(Omerta.Knock.RANGE))
end)

--------------------------------------------------------------------------------
suite("knock.audibility")
--------------------------------------------------------------------------------
-- The "too quiet, and not heard on both sides" report, turned into arithmetic.
--
-- Three quantities fail differently and were being conflated: the VOLUME at the
-- source (never lowered), the sound LEVEL that governs falloff (tuned for
-- speech, which is what made it quiet), and WHO the sound is sent to at all
-- (the engine's PAS, which a closed door is designed to cut). Only the first
-- two are arithmetic; the third is pinned as far as it can be here, by the
-- radius the server picks its listeners with.

check("the knock is emitted at full volume", function()
    loadModules()
    -- The "make it original" half of the report. It always was original; this
    -- pins it so a future tuning pass cannot quietly turn the knock down and
    -- leave the reason to be rediscovered by ear.
    assert(Omerta.Knock.SOUND_VOLUME == 1,
        "a knock is not attenuated at the source, got " ..
        tostring(Omerta.Knock.SOUND_VOLUME))
end)

check("a knock carries further than a spoken sentence and less far than a gun", function()
    loadModules()
    -- 75 is SNDLVL_NORM, the level of speech, and it is what the knock shipped
    -- at — which is why it went unheard through the door it was aimed at. The
    -- ceiling matters just as much: a knock audible across the map would tell a
    -- player something their character cannot possibly hear.
    assert(Omerta.Knock.SOUND_LEVEL > 75,
        "a fist on a panel is not a spoken sentence: " ..
        tostring(Omerta.Knock.SOUND_LEVEL))
    assert(Omerta.Knock.SOUND_LEVEL < 100,
        "a knock must not reach the next building: " ..
        tostring(Omerta.Knock.SOUND_LEVEL))
end)

check("the audible radius is Source's own arithmetic", function()
    loadModules()
    -- Restated from soundflags.h and CPASAttenuationFilter so the server can
    -- pick its own listeners. If these drift from the engine, our filter starts
    -- dropping people the engine would have kept.
    assert(math.abs(Omerta.Knock.Attenuation(75) - 0.8) < 1e-9,
        "attn(75) should be 0.8, got " .. tostring(Omerta.Knock.Attenuation(75)))
    assert(math.abs(Omerta.Knock.AudibleRadius(75) - 2500) < 1e-6,
        "radius(75) should be 2500, got " .. tostring(Omerta.Knock.AudibleRadius(75)))
    assert(math.abs(Omerta.Knock.AudibleRadius(85) - 3500) < 1e-6,
        "radius(85) should be 3500, got " .. tostring(Omerta.Knock.AudibleRadius(85)))
end)

check("raising the level actually widened the audience", function()
    loadModules()
    -- The claim the change is making, checked rather than asserted in a comment.
    assert(Omerta.Knock.AudibleRadius(Omerta.Knock.SOUND_LEVEL) >
        Omerta.Knock.AudibleRadius(75),
        "the new level must reach further than the speech level it replaced")
end)

check("a nonsense level falls back rather than dividing by zero", function()
    loadModules()
    -- Attenuation is 4 at and below 50 in the engine, which is also the only
    -- value that keeps 20/(level-50) away from a division by zero.
    assert(Omerta.Knock.Attenuation(50) == 4, "at the floor, attenuation is 4")
    assert(Omerta.Knock.Attenuation(10) == 4, "below the floor, attenuation is 4")
    assert(Omerta.Knock.Attenuation("loud") ==
        Omerta.Knock.Attenuation(Omerta.Knock.SOUND_LEVEL),
        "garbage falls back to the knock's own level")
    assert(Omerta.Knock.Attenuation(0 / 0) == 4, "NaN must not escape into a radius")
end)

--------------------------------------------------------------------------------
suite("knock.lockout")
--------------------------------------------------------------------------------

check("nothing is owed on a door that has never been knocked on", function()
    loadModules()
    assert(Omerta.Knock.Remaining(nil, 100) == 0, "a fresh door owes nothing")
end)

check("a first knock is allowed and claims the door", function()
    loadModules()
    local lock = Omerta.Knock.NewLockout()
    assert(Omerta.Knock.Claim(lock, 12, 100) == true, "the first knock must sound")
    assert(lock[12] == 100, "the claim must record when the knock started")
end)

check("a second knock while the first is still sounding is refused", function()
    loadModules()
    local lock = Omerta.Knock.NewLockout()
    Omerta.Knock.Claim(lock, 12, 100)

    local allowed, remaining = Omerta.Knock.Claim(lock, 12, 100.5)
    assert(allowed == false, "a knock must not start over one already sounding")
    assert(math.abs(remaining - 0.94) < 1e-9,
        "expected 0.94s left, got " .. tostring(remaining))
end)

check("a refused knock does not extend the lockout", function()
    loadModules()
    local lock = Omerta.Knock.NewLockout()
    Omerta.Knock.Claim(lock, 12, 100)
    Omerta.Knock.Claim(lock, 12, 100.5) -- refused
    -- If a refusal reset the timer, hammering the button would hold a door
    -- silent forever — the spam case, inverted.
    assert(lock[12] == 100, "a refusal must leave the original start time alone")
    assert(Omerta.Knock.Claim(lock, 12, 101.44) == true,
        "the door must free up on the original schedule")
end)

check("the door frees the instant the sound ends, and not before", function()
    loadModules()
    local lock = Omerta.Knock.NewLockout()
    Omerta.Knock.Claim(lock, 12, 0)

    assert(Omerta.Knock.Claim(lock, 12, 1.439) == false,
        "a hair before the end is still overlap")
    assert(Omerta.Knock.Claim(lock, 12, 1.44) == true,
        "the sound has played all the way through; the door is free")
end)

check("two doors are independent", function()
    loadModules()
    local lock = Omerta.Knock.NewLockout()
    assert(Omerta.Knock.Claim(lock, 12, 100) == true)
    -- The whole reason the lockout is per door: knocking here must not lock
    -- somebody out of the door beside it, or across town.
    assert(Omerta.Knock.Claim(lock, 13, 100) == true,
        "a knock on one door must not silence another")
end)

check("the lockout belongs to the door, not to whoever knocked", function()
    loadModules()
    local lock = Omerta.Knock.NewLockout()
    Omerta.Knock.Claim(lock, 12, 100)
    -- Claim takes no player, so a second person hammering the same door hits
    -- exactly the same entry. Per-player would let these two overlap, which is
    -- the failure the lockout exists to prevent.
    assert(Omerta.Knock.Claim(lock, 12, 100.2) == false,
        "a different knocker must not overlap the same door")
end)

check("a clock that goes backwards does not lock a door forever", function()
    loadModules()
    local lock = Omerta.Knock.NewLockout()
    Omerta.Knock.Claim(lock, 12, 5000)
    -- CurTime restarts at zero on a map change. Without the guard this door
    -- would stay silent for the better part of an hour and a half.
    assert(Omerta.Knock.Claim(lock, 12, 3) == true,
        "a stale timestamp from before a map change must not survive it")
end)

check("an explicit duration overrides the default", function()
    loadModules()
    -- The seam a re-recorded asset or a second knock sound would use, without
    -- the arithmetic having to learn about either.
    assert(Omerta.Knock.Remaining(100, 100.5, 2) == 1.5,
        "expected 1.5s left on a 2s sound")
    assert(Omerta.Knock.Remaining(100, 100.5, 0.25) == 0,
        "a quarter-second sound is long finished")
end)

check("a malformed lockout refuses rather than erroring", function()
    loadModules()
    assert(Omerta.Knock.Claim(nil, 12, 100) == false, "no table, no knock")
    assert(Omerta.Knock.Claim({}, nil, 100) == false, "no door, no knock")
end)

--------------------------------------------------------------------------------
suite("knock.knockable")
--------------------------------------------------------------------------------

check("the doors the base game ships are knockable", function()
    loadModules()
    for _, class in ipairs({ "prop_door_rotating", "func_door", "func_door_rotating" }) do
        assert(Omerta.Knock.IsKnockable(entity(class)) == true,
            class .. " should be knockable")
    end
end)

check("everything else is not", function()
    loadModules()
    assert(Omerta.Knock.IsKnockable(entity("prop_physics")) == false,
        "a crate is not a door")
    assert(Omerta.Knock.IsKnockable(entity("player")) == false,
        "a person is not a door")
end)

check("a locked door is still knockable", function()
    loadModules()
    -- The entire point of knocking. A lock check would delete the feature for
    -- exactly the case it exists for — and refusing on a locked door would
    -- leak the lock state to somebody standing outside, who cannot see it.
    local locked = entity("prop_door_rotating", { locked = true })
    assert(Omerta.Knock.IsKnockable(locked) == true,
        "a door somebody has locked is the one worth knocking on")
end)

check("what counts as a door is data", function()
    loadModules()
    assert(Omerta.Knock.IsKnockable(entity("func_movelinear")) == false,
        "not knockable until somebody says so")
    Omerta.Knock.RegisterKnockable("func_movelinear")
    assert(Omerta.Knock.IsKnockable(entity("func_movelinear")) == true,
        "one registration is the entire cost of a new kind of door")
end)

check("a class whose entities are not all doors can answer per entity", function()
    loadModules()
    Omerta.Knock.RegisterKnockable("prop_dynamic", function(ent)
        return ent.isShutter == true
    end)
    assert(Omerta.Knock.IsKnockable(entity("prop_dynamic", { isShutter = true })) == true,
        "the shutter is knockable")
    assert(Omerta.Knock.IsKnockable(entity("prop_dynamic")) == false,
        "every other prop_dynamic on the map is not")
end)

check("a refinement that errors refuses", function()
    loadModules()
    Omerta.Knock.RegisterKnockable("prop_dynamic", function() error("boom") end)
    -- A typo in somebody else's module must not make every prop on the map
    -- into a door. MayOpen takes the same stance for containers.
    assert(Omerta.Knock.IsKnockable(entity("prop_dynamic")) == false,
        "a broken refinement must refuse, not grant")
end)

check("nothing at all is not knockable", function()
    loadModules()
    assert(Omerta.Knock.IsKnockable(nil) == false, "nil is not a door")
    assert(Omerta.Knock.IsKnockable({ __invalid = true }) == false,
        "a removed entity is not a door")
    assert(Omerta.Knock.IsKnockable({}) == false,
        "something without a class is not a door")
end)

expectError("a knockable class must be a string", "non-empty string", function()
    loadModules()
    Omerta.Knock.RegisterKnockable(nil)
end)

expectError("a refinement must be a function", "must be a function", function()
    loadModules()
    Omerta.Knock.RegisterKnockable("prop_dynamic", "yes please")
end)

--------------------------------------------------------------------------------
suite("knock.wiring")
--------------------------------------------------------------------------------

check("the server half binds the module lifecycle exactly once", function()
    loadModules()
    -- sv_knock.lua is the only file in the interaction module with a lifecycle
    -- method; MODULE is one shared table and a second definition would silently
    -- replace this one (lint.module_lifecycle covers the tree, this covers the
    -- registration actually taking).
    local module = Omerta.Module.Get("interaction")
    assert(module ~= nil, "the interaction module must be registered")
    assert(type(module.OnEnable) == "function",
        "sv_knock.lua must own the interaction module's OnEnable")
end)

check("the knock entry point exists for the SWEP to call", function()
    loadModules()
    -- weapon_omerta_hands calls exactly this and nothing else. If it moves or
    -- is renamed, left click silently stops knocking.
    assert(type(Omerta.Knock.Attempt) == "function",
        "Omerta.Knock.Attempt is the SWEP's only entry point")
    local ok, reason = Omerta.Knock.Attempt(nil)
    assert(ok == false, "there is no engine here, so nothing may sound")
    assert(reason == "not in engine", "expected the engine guard, got " .. tostring(reason))
end)

check("the sound registered for download is the one that gets played", function()
    loadModules()
    -- The two halves of a content bug that is invisible until a fresh client
    -- joins: a file registered under one name and played under another.
    local handle = io.open(
        "gamemodes/omertarp/content/" .. Omerta.Knock.SOUND_FILE, "rb")
    assert(handle, "the wav is missing from content/: " .. Omerta.Knock.SOUND_FILE)
    handle:close()

    local source = io.open(
        "gamemodes/omertarp/gamemode/modules/interaction/sv_knock.lua", "r")
    assert(source, "sv_knock.lua is missing")
    local text = source:read("*a")
    source:close()
    assert(text:find("resource.AddFile(Knock.SOUND_FILE)", 1, true),
        "the module that plays a sound registers it (content/README.md)")
end)
