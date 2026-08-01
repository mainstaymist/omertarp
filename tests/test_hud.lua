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
