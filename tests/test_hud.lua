-- M8 contextual HUD: the fade state machine, scale clamping, and the stamina
-- maths. The controller itself is client-only (it draws), so its pure parts
-- live in the shared file and are covered here.

local MODULE_FILES = {
    "gamemodes/omertarp/gamemode/modules/database/sh_database.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_schema.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_sqlbuild.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_database.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sh_accounts.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sv_accounts.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sh_seasons.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sv_seasons.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sh_characters.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sv_characters.lua",
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
