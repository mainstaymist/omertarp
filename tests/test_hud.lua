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
    "gamemodes/omertarp/gamemode/modules/hud/sh_gait.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sh_hud.lua",
    -- The design tokens. Needed here because the black-and-white maths is
    -- checked against the real palette rather than against invented colours —
    -- the assertion that matters is about THESE six hex, not about arithmetic.
    "gamemodes/omertarp/gamemode/modules/hud/sh_theme.lua",
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
suite("hud.aiming")
--------------------------------------------------------------------------------
-- D-041's crosshair goes away down a set of sights, and the only thing this
-- gamemode is allowed to know about a set of sights is that it narrows the
-- picture. Nothing in the predicate touches a weapon, a class name or an addon;
-- it is two field-of-view readings and a previous answer, which is exactly why
-- it can be pinned here on a machine that has neither addon installed.

check("aiming is a RATIO of the player's own field of view, not a difference", function()
    loadModules()
    local A = Omerta.HUD.IsAiming
    -- The same 25% narrowing, at three very different player settings. A
    -- difference-based rule would answer these three differently, which is the
    -- bug the ratio exists to prevent.
    assert(A(56.25, 75, false), "narrowed a quarter at 75")
    assert(A(67.5, 90, false), "narrowed a quarter at 90")
    assert(A(90, 120, false), "narrowed a quarter at 120")
    -- And an untouched field of view is never aiming, at any setting.
    assert(not A(75, 75, false))
    assert(not A(90, 90, false))
    assert(not A(120, 120, false))
end)

check("only NARROWING counts — a widened picture is the opposite of a sight", function()
    loadModules()
    local A = Omerta.HUD.IsAiming
    -- Sprint effects and damage kicks push the field of view out. None of that
    -- may take the crosshair away, and the rule is one-sided so none of it can.
    assert(not A(100, 90, false), "widened")
    assert(not A(140, 90, true), "widened, even coming out of an aim")
end)

check("the thresholds are the declared ones, and they hysteresise", function()
    loadModules()
    local AIM = Omerta.HUD.AIM
    assert(AIM.ENTER == 0.95, "enter at 95% of the player's field of view")
    assert(AIM.LEAVE == 0.98, "and leave past 98%")
    assert(AIM.ENTER < AIM.LEAVE,
        "leaving must be looser than entering or the band is inverted")

    local A = Omerta.HUD.IsAiming
    -- Inside the band the answer is whatever it already was: that is the whole
    -- of the hysteresis, and it is what stops a mark at the exact centre of the
    -- screen flickering when an aim settles near the boundary.
    assert(not A(90 * 0.965, 90, false), "0.965 does not START an aim")
    assert(A(90 * 0.965, 90, true), "but does not END one either")
    -- Outside it, the previous answer is irrelevant.
    assert(A(90 * 0.94, 90, false), "past ENTER, from not aiming")
    assert(not A(90 * 0.99, 90, true), "past LEAVE, from aiming")
end)

check("the fade is quicker than the element's own, and still a fade", function()
    loadModules()
    local AIM = Omerta.HUD.AIM
    -- The crosshair element fades at 0.15s for the reasons the world changes.
    -- Aiming is the player's own hand and must land inside the window where the
    -- eye reads it as caused by the input.
    assert(AIM.FADE < 0.15, "an aim fade at or above the element's own is not 'fast'")
    -- And not a cut: a hard switch on a mark at the centre of the screen is the
    -- jump-cut D-042 argues against.
    assert(AIM.FADE > 0, "a zero fade is a cut, not a fade")
    assert(AIM.FADE <= 0.1, "past a tenth of a second it reads as the HUD catching up")
    -- Never the slowest thing on screen: a window's play-out is 0.10s.
    assert(AIM.FADE < Omerta.HUD.REVEAL.OUT, "slower than a window leaving")

    -- It reaches the ends in the time it says it does, through the same stepper
    -- every other fade in the interface uses.
    local a = 1
    for _ = 1, 4 do a = Omerta.HUD.StepAlpha(a, false, AIM.FADE / 4, AIM.FADE) end
    assert(a == 0, "four steps of a quarter of the fade should finish it")
end)

check("an unreadable camera keeps the crosshair rather than losing it", function()
    loadModules()
    local A = Omerta.HUD.IsAiming
    -- D-041's dot is the ONE permanent element and the expensive failure is
    -- blanking it, so every degenerate reading answers "not aiming".
    assert(not A(nil, 90, false), "no reading at all")
    assert(not A(45, nil, false), "no player preference to compare against")
    assert(not A(0, 90, false), "a zero field of view")
    assert(not A(45, 0, false), "a zero base")
    assert(not A(-45, 90, false), "a negative reading")
    assert(not A("wide", 90, false), "something that is not a number")
    local nan = 0 / 0
    assert(not A(nan, 90, false), "NaN survives every comparison it touches")
    assert(not A(45, nan, false), "and so does a NaN base")
    -- Including while already aiming: a reading that breaks mid-aim brings the
    -- crosshair back rather than leaving the screen blank forever.
    assert(not A(nan, 90, true))
end)

--------------------------------------------------------------------------------
-- The whole rule, one frame at a time.
--------------------------------------------------------------------------------
-- StepAiming is the part that failed in the field and the part the first
-- attempt did not have: the baseline. The first version compared
-- Player:GetFOV() against fov_desired and was blind to a weapon base that
-- narrows the picture only inside CalcView — which is what ARC9 does, and the
-- reason the dot did not move on any weapon.
--
-- The readings below are a 16:9 screen: fov_desired 90 draws at about 106.3
-- because the field of view is aspect-corrected. That correction is exactly
-- what the first pass rejected this reading for, and exactly what a ratio
-- against a self-measured baseline divides out.
local RESTING, DESIRED = 106.3, 90

check("the reading that is blind to CalcView is not the one this uses", function()
    loadModules()
    -- The regression, written as the bug rather than as the fix. GetFOV()
    -- answers 90 through the whole of an ARC9 aim; the DRAWN field of view
    -- falls to 80. A rule reading the first cannot ever fire, whatever its
    -- thresholds are, and a rule reading the second cannot miss.
    assert(not Omerta.HUD.IsAiming(DESIRED, DESIRED, false),
        "the old reading answered 'aiming' — this test no longer reproduces the bug")

    local aiming, scale = Omerta.HUD.StepAiming(RESTING, DESIRED, nil, false, false)
    assert(not aiming, "the first readable frame is a calibration, not an aim")
    aiming = Omerta.HUD.StepAiming(80, DESIRED, scale, false, aiming)
    assert(aiming, "a narrowing that only exists in the drawn view was missed again")
end)

check("the baseline is measured off the same reading, so aspect correction cancels", function()
    loadModules()
    -- The same 25% narrowing on three screens whose correction factors are
    -- wildly different. Nothing here knows what any of those factors are, which
    -- is the entire point: a ratio against a baseline taken from the same
    -- reading is unaffected by a constant nobody measured.
    for _, drawn in ipairs({ 90, 106.3, 121.5 }) do
        local _, scale = Omerta.HUD.StepAiming(drawn, DESIRED, nil, true, false)
        local aiming = Omerta.HUD.StepAiming(drawn, DESIRED, scale, false, false)
        assert(not aiming, "a resting picture read as an aim at " .. drawn)
        aiming = Omerta.HUD.StepAiming(drawn * 0.75, DESIRED, scale, false, false)
        assert(aiming, "a quarter off the picture was missed at " .. drawn)
    end
end)

check("a whole aim: calibrate, narrow, hold, release", function()
    loadModules()
    local aiming, scale = false, nil

    -- At rest, with a window open — the moment the baseline is read.
    aiming, scale = Omerta.HUD.StepAiming(RESTING, DESIRED, scale, true, aiming)
    assert(not aiming and math.abs(scale - RESTING / DESIRED) < 1e-9)

    -- The gun comes up over a handful of frames. Nothing may be re-calibrated
    -- while it does, or the baseline would follow the picture down and the aim
    -- would be absorbed frame by frame — which is the failure mode of every
    -- design that tracks continuously.
    local before = scale
    for _, drawn in ipairs({ 104, 98, 90, 80, 74 }) do
        aiming, scale = Omerta.HUD.StepAiming(drawn, DESIRED, scale, false, aiming)
        assert(scale == before, "the baseline moved during an aim")
    end
    assert(aiming, "the aim never registered")

    -- Held, for as long as anybody holds one. The answer does not drift.
    for _ = 1, 600 do
        aiming, scale = Omerta.HUD.StepAiming(74, DESIRED, scale, false, aiming)
    end
    assert(aiming and scale == before, "a held aim decayed")

    -- And released.
    aiming = Omerta.HUD.StepAiming(RESTING, DESIRED, scale, false, aiming)
    assert(not aiming, "the crosshair never came back")
end)

check("a widening never becomes the baseline, so a sprint cannot cost the dot", function()
    loadModules()
    local _, scale = Omerta.HUD.StepAiming(RESTING, DESIRED, nil, true, false)

    -- Something widens the picture — a sprint effect, a damage kick. It is not
    -- aiming (the rule is one-sided) and, more importantly, it does not move
    -- the baseline: a baseline that crept up during the excursion would make
    -- every later resting frame look narrowed and would hide the dot for good.
    local aiming, after = Omerta.HUD.StepAiming(RESTING * 1.1, DESIRED, scale, false, false)
    assert(not aiming, "a wider picture read as a sight")
    assert(after == scale, "a widening moved the baseline")

    -- Back to rest, and the dot is still the player's.
    assert(not Omerta.HUD.StepAiming(RESTING, DESIRED, after, false, false),
        "the picture came back to rest and the crosshair did not")
end)

check("changing the field-of-view slider does not read as aiming", function()
    loadModules()
    -- The most likely way a fixed baseline goes wrong: the player moves the
    -- slider mid-session, every frame afterwards is narrower than the number we
    -- measured, and the dot is gone for the session. It cannot happen here
    -- because the baseline is a RATIO to fov_desired rather than an absolute
    -- field of view, so the player's own preference divides out of it.
    local _, scale = Omerta.HUD.StepAiming(RESTING, DESIRED, nil, true, false)
    -- 90 -> 75. The drawn picture narrows to about 91.3, which is a 14%
    -- narrowing to anything comparing absolute numbers.
    assert(not Omerta.HUD.StepAiming(91.3, 75, scale, false, false),
        "a field-of-view change read as an aim, and the dot would never return")
end)

check("a mis-calibration is re-read rather than lived with", function()
    loadModules()
    -- Suppose the baseline is measured at a bad moment — mid-aim, say. Every
    -- resting frame afterwards is WIDER than it, which the one-sided rule reads
    -- as "not aiming", so the dot is safe; and the next moment the player
    -- provably cannot be aiming (any window, the menu, being down) re-reads it.
    local _, bad = Omerta.HUD.StepAiming(74, DESIRED, nil, true, false)
    assert(not Omerta.HUD.StepAiming(RESTING, DESIRED, bad, false, false),
        "a bad calibration turned a resting picture into an aim")

    local _, fixed = Omerta.HUD.StepAiming(RESTING, DESIRED, bad, true, false)
    assert(math.abs(fixed - RESTING / DESIRED) < 1e-9, "the re-read did not take")
    assert(Omerta.HUD.StepAiming(74, DESIRED, fixed, false, false),
        "and aiming works again afterwards")
end)

check("resting is never aiming, whatever the picture is doing", function()
    loadModules()
    -- A window is open, or the player is dead. Whatever the camera says, there
    -- is nothing to aim, so the answer is false and the reading becomes the new
    -- baseline rather than a verdict.
    local aiming, scale = Omerta.HUD.StepAiming(40, DESIRED, 1.18, true, true)
    assert(not aiming, "a resting frame answered 'aiming'")
    assert(math.abs(scale - 40 / DESIRED) < 1e-9)
    -- Only a plain `true` counts, the same discipline InWorldFrom follows.
    assert(Omerta.HUD.StepAiming(74, DESIRED, 106.3 / 90, "yes", false),
        "something that is not a boolean was believed")
end)

check("an unreadable frame answers 'not aiming' and keeps the calibration", function()
    loadModules()
    local S = Omerta.HUD.StepAiming
    local nan = 0 / 0
    for _, case in ipairs({
        { nil, DESIRED }, { RESTING, nil }, { 0, DESIRED }, { RESTING, 0 },
        { -5, DESIRED }, { RESTING, -5 }, { nan, DESIRED }, { RESTING, nan },
        { "wide", DESIRED },
    }) do
        local aiming, scale = S(case[1], case[2], 1.18, false, true)
        assert(not aiming, "a degenerate reading answered 'aiming'")
        assert(scale == 1.18,
            "one bad frame cost the calibration — the renderer skipping a frame " ..
            "must not be the same event as changing screens")
    end

    -- A degenerate CALIBRATION is no calibration: this frame becomes one.
    local _, recovered = S(RESTING, DESIRED, nan, false, false)
    assert(math.abs(recovered - RESTING / DESIRED) < 1e-9)
    local _, fromZero = S(RESTING, DESIRED, 0, false, false)
    assert(math.abs(fromZero - RESTING / DESIRED) < 1e-9)
end)

--------------------------------------------------------------------------------
-- The two signals, composed.
--------------------------------------------------------------------------------
-- The view reading above is the optical CONSEQUENCE of a sight. It has now been
-- reported twice as never firing, and the second reading was structurally sound
-- — which is the evidence that these weapons do not narrow the field of view at
-- all, because ARC9 commonly enters sights by moving the VIEWMODEL and a
-- viewmodel reposition is invisible to every camera reading there is.
--
-- So there is a second signal of a different KIND: the player's own input. A
-- weapon in the hands and IN_ATTACK2 held. Nothing here calls into ARC9, TFA or
-- our own base — the facts are gathered off the player in cl_hud.lua and this
-- is the pure rule they feed, which is why the whole composition is pinnable on
-- a machine with neither addon.

check("either signal is sufficient, and neither replaces the other", function()
    loadModules()
    local A = Omerta.HUD.AimingFrom

    -- The view half alone: a scope, a magnified optic, our own ironsights when
    -- W0 §6's deferred pass lands. No button involved.
    assert(A({ narrowed = true, armed = false, secondary = false }),
        "a narrowed picture stopped counting when the input signal was added")

    -- The input half alone: the case the view reading is blind to, and the
    -- reason this pass exists. A gun that goes to the sights without zooming.
    assert(A({ narrowed = false, armed = true, secondary = true }),
        "a weapon and a held right mouse button is a man aiming")

    -- Both, which is the ordinary case for anything that does zoom.
    assert(A({ narrowed = true, armed = true, secondary = true }))

    -- And neither.
    assert(not A({ narrowed = false, armed = true, secondary = false }),
        "a weapon in the hands is not by itself aiming")
    assert(not A({ narrowed = false, armed = false, secondary = false }))
end)

check("empty hands and right-click is NOT aiming", function()
    loadModules()
    local A = Omerta.HUD.AimingFrom
    -- The holster (weapon_omerta_hands) is a valid weapon entity, because the
    -- engine has no concept of holding nothing — so "is there a weapon" would
    -- be true all day and every right-click in the game would take D-041's dot
    -- away. `armed` is the class comparison that excludes it, and this is the
    -- assertion that must hold whatever else changes about the rule.
    assert(not A({ narrowed = false, armed = false, secondary = true }),
        "right-clicking with nothing drawn hid the crosshair")
    -- Held down forever, still not aiming.
    for _ = 1, 100 do
        assert(not A({ narrowed = false, armed = false, secondary = true }))
    end
    -- And the moment something is drawn, it is.
    assert(A({ narrowed = false, armed = true, secondary = true }))
end)

check("a moment no sight can be up vetoes BOTH signals", function()
    loadModules()
    local A = Omerta.HUD.AimingFrom
    -- A window has the cursor, the player is dead, the player is on the floor.
    -- `resting` is not evidence about a sight; it is the absence of anywhere
    -- for one to be, so it overrides rather than joins. It matters most for the
    -- input half: a right-click aimed at a window's close box is not a man
    -- raising a gun, and nothing else gates a button.
    assert(not A({ resting = true, narrowed = true, armed = true, secondary = true }),
        "a state where nothing can be aimed still answered 'aiming'")
    assert(not A({ resting = true, narrowed = false, armed = true, secondary = true }))
    assert(not A({ resting = true, narrowed = true }))
    -- Only a plain `true` vetoes, the same discipline InWorldFrom follows.
    assert(A({ resting = "yes", narrowed = true }),
        "something that is not a boolean was believed")
end)

check("default deny: a fact this rule cannot read is a fact it does not have", function()
    loadModules()
    local A = Omerta.HUD.AimingFrom
    -- D-041's dot is the ONE permanent element and the expensive failure is
    -- blanking it, so anything that is not plainly `true` reads as absent.
    assert(not A(nil), "no facts at all")
    assert(not A("aiming"), "something that is not a table")
    assert(not A({}), "an empty table")
    assert(not A({ narrowed = 1, armed = 1, secondary = 1 }), "truthy is not true")
    assert(not A({ armed = "yes", secondary = "yes" }))
    assert(not A({ narrowed = "yes" }))
end)

check("the input signal is momentary, which is the toggle-ADS gap", function()
    loadModules()
    local A = Omerta.HUD.AimingFrom
    -- Written down as a TEST rather than only as a comment, because it is the
    -- one thing about this rule somebody will otherwise discover in the field
    -- and report as a bug. A player who has ARC9 set to TOGGLE sights holds the
    -- button for a few frames and lets go while the gun stays up: the input
    -- signal follows the button, not the gun.
    local held = { narrowed = false, armed = true, secondary = true }
    assert(A(held), "the toggle press registers")
    local released = { narrowed = false, armed = true, secondary = false }
    assert(not A(released),
        "the input signal outlived the button — it is not, and must not be, a latch")

    -- The view half covers that case ONLY IF the weapon also zooms. When it
    -- does, the release changes nothing.
    assert(A({ narrowed = true, armed = true, secondary = false }),
        "a raised scope needs no button")
end)

--------------------------------------------------------------------------------
suite("hud.reveal")
--------------------------------------------------------------------------------
-- The one animation every popup in the game shares. Pinned here rather than
-- trusted, because it is now installed on eight windows and three HUD plates
-- from one place: a change to any of these three numbers changes all eleven at
-- once, which is the point of the helper and also the risk of it.

check("the standard is one set of numbers, and these are they", function()
    loadModules()
    local R = Omerta.HUD.REVEAL
    assert(R.IN == 0.12, "0.12s in — the inventory's, arrived at in the field")
    assert(R.OUT == 0.10, "0.10s out")
    assert(R.RISE == 42, "42 design px of travel")
    -- The asymmetry is deliberate and is the thing most likely to be tidied
    -- away by somebody making the two match: the way out is quicker because the
    -- player has already decided to leave.
    assert(R.OUT < R.IN, "leaving must not take longer than arriving")
    -- Both short enough that nobody waits on them. A window a player opens
    -- hundreds of times a session cannot cost a third of a second each way.
    assert(R.IN <= 0.2 and R.OUT <= 0.2, "an animation you wait for is a bug")
end)

check("the ease is a smoothstep, and cannot leave 0..1", function()
    loadModules()
    local E = Omerta.HUD.RevealEase
    assert(E(0) == 0, "closed")
    assert(E(1) == 1, "open")
    assert(E(0.5) == 0.5, "symmetric about the middle")
    assert(math.abs(E(0.25) - 0.15625) < 1e-9, "3t² - 2t³")

    -- Zero velocity at both ends is the whole reason for the curve: a linear
    -- ramp read as a jump-cut at the start and a drop at the finish.
    assert(E(0.02) < 0.02, "eases in")
    assert(E(0.98) > 0.98, "and eases out")

    -- Monotonic, or the window would visibly go backwards mid-animation.
    local previous = -1
    for step = 0, 100 do
        local value = E(step / 100)
        assert(value >= previous, "the curve must never fall")
        previous = value
    end

    -- One enormous frame (a map load, an alt-tab) hands this a position well
    -- outside the range, and an alpha of 340 is a draw call that misbehaves
    -- rather than an error anybody sees.
    assert(E(1.7) == 1 and E(-3) == 0, "clamped, not trusted")
    assert(E(nil) == 0 and E("nonsense") == 0 and E(0 / 0) == 0, "garbage-proof")
end)

check("a reveal opens, closes, and says when it is finished", function()
    loadModules()
    local S = Omerta.HUD.StepReveal
    local R = Omerta.HUD.REVEAL

    local position, finished = S(0, false, R.IN * 0.5)
    assert(math.abs(position - 0.5) < 1e-9, "half a second's worth is half open")
    assert(finished == false, "opening is never finished — only closing is")

    position, finished = S(0.5, false, R.IN)
    assert(position == 1 and finished == false, "completes and stops at 1")
    assert(S(1, false, 10) == 1, "an open window does not keep opening")

    position, finished = S(1, true, R.OUT * 0.5)
    assert(math.abs(position - 0.5) < 1e-9, "half way out")
    assert(finished == false, "still on screen")

    -- The second return is what removes the panel, so it must arrive with the
    -- position AT zero and not a frame before or after it: a panel removed
    -- early is drawn at partial alpha and then vanishes, and one removed late
    -- sits invisible on screen holding the mouse.
    position, finished = S(0.4, true, R.OUT)
    assert(position == 0 and finished == true, "reaching zero is being gone")
end)

check("closing halfway open sinks from halfway", function()
    loadModules()
    local S = Omerta.HUD.StepReveal
    local R = Omerta.HUD.REVEAL
    -- Tapping the key twice in a tenth of a second is ordinary play. The
    -- position is the only state there is, so a reversal has no special case —
    -- and must not snap to either end first.
    local position = S(0, false, R.IN * 0.25)
    assert(math.abs(position - 0.25) < 1e-9, tostring(position))
    position = S(position, true, R.OUT * 0.1)
    assert(position < 0.25 and position > 0, "falls back from where it was")
end)

check("a reveal is garbage-proof and cannot stall", function()
    loadModules()
    local S = Omerta.HUD.StepReveal
    assert(S(nil, false, 1) == 1, "no position is a closed one")
    assert(S(0 / 0, false, 1) == 1, "NaN does not poison it")
    assert(S(0.5, true, nil) == 0.5, "no frame time is no movement")
    -- A single frame long enough to overshoot must land exactly at the ends
    -- rather than past them.
    assert(S(0, false, 99) == 1, "a huge frame opens it fully, not more")
    local position, finished = S(1, true, 99)
    assert(position == 0 and finished == true, "and closes it fully")
end)

check("the offset is the travel remaining, and zero at rest", function()
    loadModules()
    local O = Omerta.HUD.RevealOffset
    local E = Omerta.HUD.RevealEase
    assert(O(E(1), 42) == 0, "at rest a window is exactly where the layout put it")
    assert(O(E(0), 42) == 42, "and starts a full travel BELOW it — positive is down")
    assert(O(E(0.5), 42) == 21, "half eased is half travelled")
    assert(O(E(0.5), 0) == 0, "rise = 0 is a fade with no movement (full-screen panels)")
    assert(O(E(0.5), nil) == 0, "and so is no rise at all")

    -- The rise is a DESIGN pixel count, like every other constant in the
    -- interface: the caller multiplies by the accessibility scale, so the
    -- travel grows with the type rather than staying a fixed fraction of a
    -- window that has got bigger.
    assert(O(E(0), 42 * Omerta.HUD.SCALE_BASE) == 42 * 1.75,
        "the helper never applies the scale itself")
end)

--------------------------------------------------------------------------------
suite("hud.async_sound")
--------------------------------------------------------------------------------

-- sound.PlayFile hands the channel back some milliseconds after it is asked
-- for, and until then there is nothing for a stop to act on. So a cancel that
-- lands inside that window used to do nothing at all: the load finished, found
-- its own deadline still in the future, and played — which is how a search
-- cancelled a tick after it began was still audible for four seconds with no
-- plate on screen to explain it.

check("a sound cancelled while it was loading does not play when it lands", function()
    loadModules()
    local W = Omerta.HUD.SoundStillWanted
    -- Asked for at t=0 with a four-second window, still the current request.
    assert(W(1, 1, 0.05, 4) == true, "the ordinary case: it landed and is wanted")

    -- Stopped while in flight. The stop bumps the token, so the callback
    -- carrying the old one knows it was disowned — even though its own
    -- deadline has not passed and there was no channel to stop at the time.
    assert(W(1, 2, 0.05, 4) == false, "a stale request is not played")

    -- Superseded rather than stopped: a second rummage began before the first
    -- had finished loading. Only the newest may install itself.
    assert(W(1, 3, 0.05, 4) == false, "nor is one that was overtaken")
    assert(W(3, 3, 0.05, 4) == true, "the newest still plays")
end)

check("a sound that lands after its own window has closed does not play", function()
    loadModules()
    local W = Omerta.HUD.SoundStillWanted
    assert(W(1, 1, 5, 4) == false, "a very slow load is simply too late")
    assert(W(1, 1, 4, 4) == true, "the last instant of the window still counts")
    -- A stop zeroes the deadline, so even the matching token cannot revive it.
    assert(W(1, 1, 0.05, 0) == false)
    assert(W(1, 1, nil, nil) == false, "garbage is not a reason to make a noise")
end)

--------------------------------------------------------------------------------
suite("hud.draw_failures")
--------------------------------------------------------------------------------

-- The controller calls draw on every frame an element's alpha is above zero,
-- which includes the frames after `visible` has gone false and it is fading
-- out. An element that assumes otherwise throws — and removing it on that first
-- bad frame cost the player the element for the whole session.

check("one bad frame is survivable; a broken element is still removed", function()
    loadModules()
    local F = Omerta.HUD.DrawFailureIsFatal
    assert(F(0) == false and F(1) == false, "a race is not a broken element")
    assert(F(Omerta.HUD.DRAW_FAILURES_ALLOWED) == true, "erroring every frame is")
    assert(F(99) == true)
    assert(F(nil) == false, "no failures is not a failure")
end)

check("the allowance is frames, not seconds", function()
    loadModules()
    local allowed = Omerta.HUD.DRAW_FAILURES_ALLOWED
    assert(allowed >= 2, "one frame of tolerance is no tolerance at all")
    -- Counted in CONSECUTIVE frames and reset by any clean one, so this is a
    -- fraction of a second for something genuinely broken. Anything larger
    -- would be a broken element left erroring on screen instead.
    assert(allowed <= 10, "a broken element must still go, and quickly")
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

    -- 1.0 is the size signed off in the field, so it has to be a real option
    -- and it has to sit INSIDE the range — and the steps offered are weighted
    -- below it, because that is the direction players actually reach.
    local steps = Omerta.HUD.SCALE_STEPS
    assert(#steps >= 5, "a scale with three options is not an accessibility control")
    local hasOne, below, above = false, 0, 0
    for _, value in ipairs(steps) do
        assert(C(value) == value, value .. "x is offered but would be clamped away")
        if math.abs(value - 1) < 0.001 then hasOne = true
        elseif value < 1 then below = below + 1
        else above = above + 1 end
    end
    assert(hasOne, "1x must be offered — it is the size the game was tuned at")
    assert(below > above, "the room below 1x is where the tuning happens")
    assert(C("nonsense") == 1, "unparseable falls back to 1")
    assert(C(nil) == 1, "nil falls back to 1")
    assert(C(0 / 0) == 1, "NaN falls back to 1")
end)

check("black and white separates the accent from the warning", function()
    loadModules()
    local L = Omerta.HUD.Luma
    local palette = Omerta.HUD.Theme.COLOUR

    assert(L(0, 0, 0) == 0)
    assert(L(255, 255, 255) == 255)

    -- The whole reason for weighted luma rather than a channel average. Brass
    -- is the accent and danger is the warning, and a straight mean renders
    -- them within a few points of each other — an interface where "this is
    -- selected" and "this cannot be undone" are the same grey.
    local brass = L(palette.brass[1], palette.brass[2], palette.brass[3])
    local danger = L(palette.danger[1], palette.danger[2], palette.danger[3])
    assert(brass - danger > 40,
        "the accent and the warning must stay tellable apart in monochrome")

    -- The reading has to survive being drawn: text over plate is the contrast
    -- every screen depends on, and it must not collapse.
    local text = L(palette.text[1], palette.text[2], palette.text[3])
    local plate = L(palette.plate[1], palette.plate[2], palette.plate[3])
    assert(text - plate > 150, "type must stay readable against its plate")

    assert(L(nil, nil, nil) == 0, "garbage reads as black, never as an error")
    assert(L(9999, 9999, 9999) == 255, "and never above the channel ceiling")
end)

check("1x is the size that was signed off, not the engine's 1", function()
    loadModules()
    -- The setting is a MULTIPLE of a base, and the base is the number the
    -- project lead reached by typing into the console. If this ever drifts
    -- back to 1, every pixel constant in the interface quietly shrinks by a
    -- third and the size that was approved stops being reachable at all.
    assert(Omerta.HUD.SCALE_BASE == 1.75,
        "1x must stay the size the interface was tuned at")
    assert(Omerta.HUD.SCALE_BASE * 1 == 1.75, "1x IS the base")
end)

check("a pre-rebase scale is corrected rather than reinterpreted", function()
    loadModules()
    local M = Omerta.HUD.MigrateScale

    -- The value in the field. Read as a multiple it would clamp to 1.4 and
    -- serve an interface 2.45x the base — bigger than anything the control
    -- can reach, from a config the player never edited again.
    assert(M(1.75) == 1, "the old absolute default becomes the new 1x")
    assert(M(1.5) == 1, "so does anything else above the multiplier ceiling")

    -- Everything inside the range is already a multiple and is left alone,
    -- so a player who picks 0.8x keeps 0.8x across restarts.
    for _, value in ipairs(Omerta.HUD.SCALE_STEPS) do
        assert(M(value) == value, value .. "x must survive a restart")
    end
    assert(M(0.1) == Omerta.HUD.SCALE_MIN, "below the floor still clamps up")
    assert(M(nil) == 1)
    assert(M("nonsense") == 1)
    assert(M(0 / 0) == 1)
end)

--------------------------------------------------------------------------------
suite("hud.vignette")
--------------------------------------------------------------------------------
-- The always-on lens. What is pinned here is the word "slight": the brief was
-- that it must be felt rather than seen, and a number is the only form of that
-- claim anybody can check a year from now. The reasoning that lets an always-on
-- effect exist beside GDD §8 at all lives in sh_hud.lua, and the in-engine
-- self-test is what holds it to being a lens rather than an element.

check("slight is a quantity, not an opinion", function()
    loadModules()
    local V = Omerta.HUD.VIGNETTE

    -- At the edge. Past about a fifth the eye stops reading "the picture has
    -- weight" and starts reading "there is a vignette on my screen", which is
    -- the failure the brief named.
    assert(V.EDGE > 0, "a vignette nobody can see is not a vignette")
    assert(V.EDGE <= 0.2,
        "the edge is at " .. tostring(V.EDGE) .. " — that is a vignette you notice")

    -- And the centre stays clear. Reach is measured against the HALF dimension,
    -- so anything at or above 1 would have the two bands meeting in the middle
    -- of the screen and darkening the thing the player is looking at.
    assert(V.REACH > 0 and V.REACH < 0.5,
        "the middle of the picture must never be inside the vignette")

    -- And the edge opacity has to be UNAMBIGUOUS to Omerta.HUD.Colour, which
    -- accepts either 0..1 or 0..255 and tells them apart with `alpha <= 1`. An
    -- edge that came out at or under 1 would be read as a fraction, multiplied
    -- back to 255, and painted solid black at the exact moment it is meant to
    -- be faintest. The draw path guards the fading end of that; this guards the
    -- constant, so nobody can tune EDGE down into the trap.
    local _, _, full = Omerta.HUD.VignetteBands(1920, 1080, 1)
    assert(full > 1,
        "an edge opacity of " .. tostring(full) ..
        " reads as a 0..1 fraction to Omerta.HUD.Colour and paints solid black")
end)

check("the bands are a fraction of the screen and scale with presence", function()
    loadModules()
    local thickX, thickY, alpha = Omerta.HUD.VignetteBands(1920, 1080, 1)
    local V = Omerta.HUD.VIGNETTE

    assert(math.abs(thickX - 1920 * 0.5 * V.REACH) < 1e-9, "horizontal band")
    assert(math.abs(thickY - 1080 * 0.5 * V.REACH) < 1e-9, "vertical band")
    assert(math.abs(alpha - V.EDGE * 255) < 1e-9, "edge opacity at full presence")

    -- The bands do not move as it fades; only the ink does. A vignette that
    -- grew and shrank would be M19's, which is a different statement — that one
    -- closes in because you are dying, and this one must never look like it.
    local halfX, halfY, halfAlpha = Omerta.HUD.VignetteBands(1920, 1080, 0.5)
    assert(halfX == thickX and halfY == thickY,
        "the reach is fixed; only the presence fades")
    assert(math.abs(halfAlpha - alpha * 0.5) < 1e-9, "half presence, half ink")
end)

check("switched off it draws nothing, and garbage cannot switch it on", function()
    loadModules()
    local _, _, off = Omerta.HUD.VignetteBands(1920, 1080, 0)
    assert(off == 0, "zero presence must draw literally nothing")

    -- Presence is stepped by frame time, so a single enormous frame — a map
    -- load, an alt-tab — must not reach a draw call as a negative or an
    -- over-unity alpha. Same guard, same reason, as StepAlpha and RevealEase.
    local _, _, under = Omerta.HUD.VignetteBands(1920, 1080, -3)
    assert(under == 0, "a negative presence is off, not inverted")
    local _, _, over = Omerta.HUD.VignetteBands(1920, 1080, 12)
    assert(math.abs(over - Omerta.HUD.VIGNETTE.EDGE * 255) < 1e-9,
        "over-unity clamps to the edge opacity, never above it")
    local _, _, nan = Omerta.HUD.VignetteBands(1920, 1080, 0 / 0)
    assert(nan == 0, "NaN must not escape into a draw call")
    local _, _, none = Omerta.HUD.VignetteBands(nil, nil, nil)
    assert(none == 0, "and neither must nil")
end)

check("the lens is ink, so it survives black and white", function()
    loadModules()
    -- It is drawn with the "plate" token through Omerta.HUD.Colour, which is
    -- the one chokepoint the black-and-white setting acts at. Plate is already
    -- the game's black, so desaturating it barely moves it — which is the
    -- correct amount for a vignette to move when the world goes grey.
    local plate = Omerta.HUD.Theme.COLOUR.plate
    local luma = Omerta.HUD.Luma(plate[1], plate[2], plate[3])
    assert(math.abs(luma - plate[1]) <= 1,
        "the ink must read the same in monochrome as in colour, got " .. luma)
    assert(luma < 24, "the lens darkens; it must never lighten the edges")
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
-- The jog came down again on 2026-08-02 ("lower the runspeed overall by a
-- little bit"), and 175 is not a free number: see sv_stamina.lua, it is fenced
-- above by the engine's 150 run-animation threshold and below by the fast walk.
check("base movement is a walk, and it is configuration", function()
    loadModules()
    assert(Omerta.Config.Get("movement.walk_speed") == 100, "D-034 walk")
    assert(Omerta.Config.Get("movement.jog_speed") == 175, "the lowered jog")
    assert(Omerta.Config.Get("movement.jump_power") == 200, "jump power is a knob too")
    assert(Omerta.Config.Get("movement.fast_walk_scale") > 1,
        "a fast walk that is not faster than a walk is not a gait")

    -- The whole of the third gait's guarantee, in one line: the jog is a run to
    -- look at and the fast walk is not.
    local base = Omerta.HUD.Internal.BaseMovement()
    assert(Omerta.HUD.GaitAnimation(base.jog) == Omerta.HUD.GAIT.RUN,
        "a jog that does not play the run animation is not a jog")
    assert(Omerta.HUD.GaitAnimation(base.fastWalk) == Omerta.HUD.GAIT.WALK,
        "the fast walk must not start the run animation")
    assert(base.jog - base.fastWalk >= 20,
        "the jog and the fast walk are too close together to read as two gaits")
end)

local BASE = { walk = 100, fastWalk = 130, jog = 175, jump = 200,
    exhaustedJumpScale = 0.55 }

check("every movement value is decided together", function()
    loadModules()
    local M = Omerta.HUD.Internal.MovementFor

    local walk, fastWalk, jog, jump = M(BASE, 1, false)
    assert(walk == 100 and fastWalk == 130 and jog == 175 and jump == 200,
        "rested and unencumbered")

    walk, fastWalk, jog, jump = M(BASE, 0.75, false)
    assert(walk == 75 and fastWalk == 97 and jog == 131 and jump == 150,
        "one modifier scales everything, so nothing is exempt from being slowed")

    -- The fast walk is a WAY OF WALKING, not a way out of a penalty. A gait
    -- that ignored the stack would let a starving man hold ALT and outwalk his
    -- own hunger.
    local _, penalised = M(BASE, 0.5, false)
    assert(penalised == 65, "the modifier stack reaches the third gait too")
end)

-- The gaits are ORDERED, at every factor and either side of exhaustion. A key
-- that makes a character slower than not pressing it reads as broken rather
-- than as a penalty — which is exactly what the engine's own +walk does, and
-- what this seam exists to invert.
check("the three gaits never cross, however they are modified", function()
    loadModules()
    local M = Omerta.HUD.Internal.MovementFor

    for step = 0, 20 do
        local factor = step / 20
        for _, tired in ipairs({ false, true }) do
            local walk, fastWalk, jog = M(BASE, factor, tired)
            assert(walk <= fastWalk, string.format(
                "walk %d beat the fast walk %d at %.2f", walk, fastWalk, factor))
            assert(fastWalk <= jog, string.format(
                "the fast walk %d beat the jog %d at %.2f", fastWalk, jog, factor))
        end
    end

    -- Including against a base that has no third gait at all, which is what an
    -- operator who set movement.fast_walk_scale to 1 has.
    local flat = { walk = 100, fastWalk = 100, jog = 175, jump = 200,
        exhaustedJumpScale = 0.55 }
    local walk, fastWalk = M(flat, 1, false)
    assert(walk == 100 and fastWalk == 100, "scale 1 is simply no fast walk")

    -- And against a caller from before there was a third gait: degrade to the
    -- walk rather than to an error.
    local old = { walk = 100, jog = 175, jump = 200, exhaustedJumpScale = 0.55 }
    walk, fastWalk = M(old, 1, false)
    assert(walk == 100 and fastWalk == 100, "a base with no fastWalk is not a crash")
end)

-- Exhaustion is a limit on FLEEING, not a general punishment: it takes the jog
-- away and leaves the walk alone.
check("exhaustion removes the jog rather than slowing the walk", function()
    loadModules()
    local M = Omerta.HUD.Internal.MovementFor

    local walk, fastWalk, jog = M(BASE, 1, true)
    assert(walk == 100, "an exhausted character still walks normally")
    assert(jog == fastWalk, "but cannot outrun a brisk walk")
    assert(jog < 175, "and the jog is genuinely gone, not merely trimmed")

    -- The fast walk SURVIVES exhaustion: it costs no stamina and it is not a
    -- run. Taking it away too would mean ALT silently stops working at the one
    -- moment a player is hammering every key they have.
    assert(fastWalk == 130, "a man out of breath can still walk with purpose")
    assert(Omerta.HUD.GaitAnimation(jog) == Omerta.HUD.GAIT.WALK,
        "and what he is doing looks like walking, because it is")

    walk, fastWalk, jog = M(BASE, 0.5, true)
    assert(jog == fastWalk, "still true once a modifier is stacked on top")
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
    local silly = { walk = 100, fastWalk = 130, jog = 50, jump = 200,
        exhaustedJumpScale = 0.55 }
    local walk, fastWalk, jog = M(silly, 1, false)
    assert(fastWalk >= walk, "holding ALT may never be slower than not holding it")
    assert(jog >= fastWalk, "holding sprint may never be slower than not holding it")
end)

--------------------------------------------------------------------------------
suite("hud.gait")
--------------------------------------------------------------------------------

-- The third gait, and the one thing it must not do. Source has two ground
-- animations and the base gamemode picks between them on GROUND SPEED ALONE
-- (GM:CalcMainActivity: len2d > 150 is the run) — no key, no speed slot, no
-- hook. So "a fast walk that does not start the run animation" is arithmetic,
-- and this is where it is pinned.
check("the animation is decided by speed and nothing else", function()
    loadModules()
    local A, G = Omerta.HUD.GaitAnimation, Omerta.HUD.GAIT
    local T = Omerta.HUD.RUN_ANIM_ABOVE

    assert(T == 150, "the engine's own threshold, not one of ours")
    assert(A(0) == G.IDLE, "standing still")
    assert(A(0.4) == G.IDLE, "and shuffling is still standing still")
    assert(A(1) == G.WALK)
    assert(A(T) == G.WALK, "the test is STRICTLY greater, so the line itself walks")
    assert(A(T + 1) == G.RUN, "and one unit past it runs")
    assert(A(nil) == G.IDLE and A("nonsense") == G.IDLE, "nonsense stands still")
    assert(A(0 / 0) == G.IDLE, "NaN does not pick an animation at random")
end)

check("the fast walk is quicker than a walk and never quick enough to run", function()
    loadModules()
    local F = Omerta.HUD.FastWalkSpeed
    local T = Omerta.HUD.RUN_ANIM_ABOVE

    assert(F(100, 1.3) == 130, "the shipped pair")
    assert(Omerta.HUD.GaitAnimation(F(100, 1.3)) == Omerta.HUD.GAIT.WALK)
    assert(F(100, 1) == 100, "a scale of 1 turns the gait off rather than breaking it")

    -- THE CAP IS THE POINT. An operator may type any scale they like; the gait
    -- stops getting faster before it starts looking wrong, so the guarantee is
    -- a property of the code and not of one well-chosen default.
    assert(F(100, 3) == T, "clamped to the threshold, not to 300")
    assert(F(140, 1.3) == T, "and clamped from a base that could nearly reach it")
    for scale = 1, 3, 0.05 do
        assert(Omerta.HUD.GaitAnimation(F(100, scale)) ~= Omerta.HUD.GAIT.RUN,
            "a scale of " .. scale .. " reached the running animation")
    end

    -- Never SLOWER than the walk, which is the engine's own +walk behaviour and
    -- precisely what this reverses. Including where there is no third gait to be
    -- had: a walk already past the threshold is already playing the run, and
    -- returning something faster would only make that worse.
    assert(F(200, 1.3) == 200, "no third gait above the threshold, and no lie")
    assert(F(100, 0.5) == 100, "a scale under 1 is refused, not obeyed")
    assert(F(100, nil) == 100 and F(nil, 1.3) == 0, "nonsense in, nothing invented")
    assert(F(100, 0 / 0) == 100, "NaN is not a gait")
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

--------------------------------------------------------------------------------
suite("hud.in_world")
--------------------------------------------------------------------------------

-- "A man standing in a street with pockets" — the one question a key poll or a
-- window asks before it puts anything on screen. The client gathers the facts;
-- the rule that reads them is pure, and this is it.
check("a live character, no rail, no death card: in the world", function()
    loadModules()
    assert(Omerta.HUD.InWorldFrom({ character = true, menu = false, death = false }),
        "somebody standing in the city with nothing over the screen")
end)

check("each full-screen state on its own takes the player out of the world", function()
    loadModules()
    local inWorld = Omerta.HUD.InWorldFrom

    assert(not inWorld({ character = false, menu = false, death = false }),
        "nobody to be: the front end, creation, or a city with no season")
    -- ONE question covers three screens. The front end, character creation and
    -- the pause rail are the same panel in three states, and this is what stops
    -- the fourth one being forgotten.
    assert(not inWorld({ character = true, menu = true, death = false }),
        "the rail is up — front end, creation screen or pause, all one fact")
    assert(not inWorld({ character = true, menu = false, death = true }),
        "the death card, and the fade that carries it away")
end)

-- Default deny: the cost of being wrong this way is a key that does nothing for
-- a frame, and the cost of being wrong the other way is a window over a death.
check("a fact nobody supplied reads as 'not in the world'", function()
    loadModules()
    local inWorld = Omerta.HUD.InWorldFrom

    assert(not inWorld(nil), "no facts at all")
    assert(not inWorld({}), "nobody said there was a character")
    assert(not inWorld("yes"), "not even a table")
    assert(not inWorld({ character = "yes" }), "a truthy value is not a boolean true")
    -- ...and only a plain `true` closes a screen, so a soft reference that
    -- returned a function or a table cannot silently hide the world.
    assert(inWorld({ character = true, menu = "maybe" }),
        "anything that is not true is not the rail being up")
end)
