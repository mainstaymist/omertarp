-- M8 contextual HUD: the fade state machine, scale clamping, and the stamina
-- maths. The controller itself is client-only (it draws), so its pure parts
-- live in the shared file and are covered here.

local MODULE_FILES = {
    "gamemodes/omertarp/gamemode/modules/database/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/database/sh_database.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_schema.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_sqlbuild.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_database.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sh_accounts.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sv_accounts.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sh_seasons.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sv_seasons.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sh_characters.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sv_characters.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sh_hud.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sv_stamina.lua",
}

local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

--------------------------------------------------------------------------------
suite("hud.fade")
--------------------------------------------------------------------------------

check("fades in and out, clamped at both ends", function()
    loadModules()
    local S = Omerta.HUD.StepAlpha
    assert(S(0, true, 0.1, 0.2) == 0.5, "half a fade")
    assert(S(0.5, true, 0.1, 0.2) == 1, "completes")
    assert(S(1, true, 1, 0.2) == 1, "clamps at 1")
    assert(S(1, false, 0.1, 0.2) == 0.5, "fades out")
    assert(S(0, false, 1, 0.2) == 0, "clamps at 0")
end)

check("reversing mid-fade continues from where it was", function()
    loadModules()
    local S = Omerta.HUD.StepAlpha
    -- Quarter of the way in, then the condition flips: it must fall back from
    -- 0.25, not snap to 0 or restart from 1.
    local a = S(0, true, 0.05, 0.2)
    assert(a == 0.25, tostring(a))
    a = S(a, false, 0.05, 0.2)
    assert(a == 0, "0.25 - 0.25 = 0")
    a = S(0.8, false, 0.05, 0.2)
    assert(a == 0.55, tostring(a))
end)

check("a zero fade time is instant, not a divide by zero", function()
    loadModules()
    local S = Omerta.HUD.StepAlpha
    assert(S(0, true, 0.016, 0) == 1)
    assert(S(1, false, 0.016, 0) == 0)
    assert(S(0, true, 0.016, nil) == 1, "missing fade should also be instant")
end)

--------------------------------------------------------------------------------
suite("hud.scale")
--------------------------------------------------------------------------------

check("scale is clamped and garbage-proof", function()
    loadModules()
    local C = Omerta.HUD.ClampScale
    assert(C(1) == 1)
    assert(C(1.25) == 1.25)
    assert(C(0) == Omerta.HUD.SCALE_MIN, "zero clamps up")
    assert(C(-5) == Omerta.HUD.SCALE_MIN)
    assert(C(100) == Omerta.HUD.SCALE_MAX)
    assert(C("nonsense") == 1, "unparseable falls back to 1")
    assert(C(nil) == 1, "nil falls back to 1")
    assert(C(0 / 0) == 1, "NaN falls back to 1")
end)

--------------------------------------------------------------------------------
suite("hud.stamina")
--------------------------------------------------------------------------------

check("drains while sprinting, recovers otherwise, bounded 0..100", function()
    loadModules()
    local S = Omerta.HUD.Internal.StepStamina
    assert(S(100, true, 1, 18, 11) == 82, "one second of sprint")
    assert(S(50, false, 1, 18, 11) == 61, "one second of rest")
    assert(S(5, true, 1, 18, 11) == 0, "cannot go below zero")
    assert(S(95, false, 1, 18, 11) == 100, "cannot exceed full")
end)

-- The arc of a jump was free rest: you paid on the way up and earned it back
-- before landing, so a bunny-hopper recovered faster than somebody standing
-- still. Catching your breath happens with your feet on the ground.
check("nothing recovers while your feet are off the ground", function()
    loadModules()
    local S = Omerta.HUD.Internal.StepStamina
    assert(S(50, false, 1, 18, 11, true) == 50, "no recovery mid-air")
    assert(S(50, true, 1, 18, 11, true) == 50, "and no drain either")
    assert(S(50, false, 1, 18, 11, false) == 61, "back on the ground it resumes")
    -- Omitting the flag has to keep the old meaning, or every caller changes.
    assert(S(50, false, 1, 18, 11) == 61, "grounded is the default")
end)

-- Hysteresis: a single threshold would flicker the sprint on and off every
-- frame at the boundary.
check("exhaustion latches and lifts at a higher mark", function()
    loadModules()
    local E = Omerta.HUD.Internal.StepExhausted
    assert(E(false, 20, 5, 25) == false, "tired but not exhausted")
    assert(E(false, 4, 5, 25) == true, "drops below the floor")
    assert(E(true, 10, 5, 25) == true, "still exhausted while recovering")
    assert(E(true, 24, 5, 25) == true, "just below the recovery mark")
    assert(E(true, 26, 5, 25) == false, "recovered")
    -- The gap between the two marks is what prevents flicker.
    assert(E(false, 5, 5, 25) == true and E(true, 6, 5, 25) == true,
        "at the floor it latches and does not immediately lift")
end)

-- A jump is movement, and this module owns movement. The cost is charged on
-- the press; the height is what exhaustion actually takes away.
check("exhaustion shortens the jump without grounding the character", function()
    loadModules()
    local J = Omerta.HUD.Internal.JumpPower
    assert(J(200, 1, false, 0.55) == 200, "rested and unencumbered")
    assert(J(200, 1, true, 0.55) == 110, "exhausted jumps lower")
    assert(J(200, 0.5, false, 0.55) == 100, "a speed modifier applies to the jump too")
    assert(J(200, 0.5, true, 0.55) == 55, "both at once, multiplied not added")
    -- Never zero: a character who cannot leave the floor is stuck on scenery,
    -- which reads as a bug rather than as being out of breath.
    assert(J(200, 0.001, true, 0) >= 1, "always able to leave the ground")
end)

check("the jump cost is configured, not hardcoded", function()
    loadModules()
    assert(Omerta.Config.Get("stamina.jump_cost") > 0, "a jump costs something")
    assert(Omerta.Config.Get("stamina.exhausted_jump_scale") < 1,
        "exhaustion has to cost height or the config is decorative")
end)

--------------------------------------------------------------------------------
suite("hud.movement")
--------------------------------------------------------------------------------

-- D-034. The engine's 200/400 is far too fast for a game about watching people.
check("base movement is a walk, and it is configuration", function()
    loadModules()
    assert(Omerta.Config.Get("movement.walk_speed") == 100, "D-034 walk")
    assert(Omerta.Config.Get("movement.jog_speed") == 200, "D-034 jog")
    assert(Omerta.Config.Get("movement.jump_power") == 200, "jump power is a knob too")
end)

local BASE = { walk = 100, jog = 200, jump = 200, exhaustedJumpScale = 0.55 }

check("all three values are decided together", function()
    loadModules()
    local M = Omerta.HUD.Internal.MovementFor

    local walk, jog, jump = M(BASE, 1, false)
    assert(walk == 100 and jog == 200 and jump == 200, "rested and unencumbered")

    walk, jog, jump = M(BASE, 0.75, false)
    assert(walk == 75 and jog == 150 and jump == 150,
        "one modifier scales everything, so nothing is exempt from being slowed")
end)

-- Exhaustion is a limit on FLEEING, not a general punishment: it takes the jog
-- away and leaves the walk alone.
check("exhaustion removes the jog rather than slowing the walk", function()
    loadModules()
    local M = Omerta.HUD.Internal.MovementFor

    local walk, jog = M(BASE, 1, true)
    assert(walk == 100, "an exhausted character still walks normally")
    assert(jog == walk, "but cannot outrun a walk")

    walk, jog = M(BASE, 0.5, true)
    assert(jog == walk, "still true once a modifier is stacked on top")
end)

-- The floor is a fraction of the base, not an absolute number. Left absolute
-- at 50, halving the base would have halved the range available to hunger,
-- encumbrance and M19's injuries without anyone touching those systems.
check("the slow floor tracks the configured base", function()
    loadModules()
    local M = Omerta.HUD.Internal.MovementFor

    local walk = M(BASE, 0.1, false)
    assert(walk == 25, "a quarter of 100, not an absolute 50")

    local fast = { walk = 200, jog = 400, jump = 200, exhaustedJumpScale = 0.55 }
    walk = M(fast, 0.1, false)
    assert(walk == 50, "the same quarter against the old base")

    -- The calibration point: the fraction bites at the same modifier either way.
    assert(M(BASE, 0.25, false) == 25 and M(fast, 0.25, false) == 50,
        "0.25 is the floor at any base")
end)

check("the jog never drops below the walk", function()
    loadModules()
    local M = Omerta.HUD.Internal.MovementFor
    -- A base whose jog is slower than its walk is a misconfiguration, not a
    -- reason to make sprinting a penalty.
    local silly = { walk = 100, jog = 50, jump = 200, exhaustedJumpScale = 0.55 }
    local walk, jog = M(silly, 1, false)
    assert(jog >= walk, "holding sprint may never be slower than not holding it")
end)

--------------------------------------------------------------------------------
suite("hud.labels")
--------------------------------------------------------------------------------

-- The label is asked of the entity, so the HUD never learns what an item is.
check("a label comes from the entity and both parts are optional", function()
    loadModules()
    local L = Omerta.HUD.LabelFor

    local title, subtitle = L({ OmertaLabel = function() return "Whiskey", "x3" end })
    assert(title == "Whiskey" and subtitle == "x3", "title and subtitle")

    title, subtitle = L({ OmertaLabel = function() return "Crate" end })
    assert(title == "Crate" and subtitle == nil, "a subtitle is optional")

    title = L({ OmertaLabel = function() return "", "x3" end })
    assert(title == nil, "an empty title is no label at all")

    title, subtitle = L({ OmertaLabel = function() return "Crate", "" end })
    assert(title == "Crate" and subtitle == nil, "an empty subtitle is dropped")
end)

-- §4a's hard line: a person never wears a name. Players have no OmertaLabel,
-- and anything else without one is simply not labelled.
check("anything without a label of its own gets none", function()
    loadModules()
    local L = Omerta.HUD.LabelFor
    assert(L(nil) == nil, "nothing")
    assert(L({}) == nil, "a player, which has no OmertaLabel")
    assert(L({ OmertaLabel = "Marco Rossi" }) == nil, "a field is not a method")
    assert(L({ __invalid = true, OmertaLabel = function() return "Crate" end }) == nil,
        "a removed entity")
end)

-- One broken label must cost a line of text, not the screen.
check("a label that errors is skipped rather than fatal", function()
    loadModules()
    local L = Omerta.HUD.LabelFor
    assert(L({ OmertaLabel = function() error("boom") end }) == nil)
    assert(L({ OmertaLabel = function() return 42 end }) == nil, "a number is not a label")
end)
