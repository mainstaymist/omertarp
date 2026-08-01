-- Contextual HUD framework.
--
-- The design's interface rule is that the persistent screen is EMPTY, and
-- elements appear only in response to conditions (Tech §8, GDD §8). That rule
-- is easy to state and easy to erode, so this module makes it structural:
-- nothing draws except through a controller that asks each element whether it
-- currently deserves to be on screen.
--
-- Consumers (M5's label and interaction menu today; M9's inventory, M12's
-- phone and M19's injury later) register an element rather than hooking
-- HUDPaint, so "what is on screen right now, and why" stays answerable.


Omerta.HUD = Omerta.HUD or {}

-- Accessibility: text scales, and the maths is pure so it can be tested.
--
-- THE SETTING IS A MULTIPLE OF A BASE, NOT AN ABSOLUTE SIZE.
--
-- The size the project lead signed off in the field was `omerta_ui_scale
-- 1.75` — a number reached by typing into the console until the interface
-- looked right, which is not a number anybody should have to discover. So
-- 1.75 is now the BASE, the setting is a multiple of it, and 1x is that size:
-- a fresh install gets the approved interface with the setting untouched.
--
-- Every pixel constant in the interface is therefore written against a base of
-- 1.75, not against 1.0. That is one indirection, and it buys the property
-- that matters: "1x" in the settings and "the size we agreed on" are the same
-- thing, permanently, however the base is retuned later.
Omerta.HUD.SCALE_BASE = 1.75

-- The multiples the setting may take. Weighted downward because the base is
-- deliberately large: below 1x is where the tuning happens, and the room above
-- exists for players who need it.
Omerta.HUD.SCALE_MIN, Omerta.HUD.SCALE_MAX = 0.6, 1.4
Omerta.HUD.SCALE_STEPS = { 0.6, 0.7, 0.8, 0.9, 1, 1.2, 1.4 }

-- Perceived brightness of a colour, 0..255, for the black-and-white setting.
--
-- Rec. 601 weights, and the weights are the whole point: a straight average of
-- the channels renders the brass accent and the danger red at almost exactly
-- the same grey, because 200-169-106 and 142-43-34 average within a few points
-- of each other. The eye does not see those two as equally bright and neither
-- does this. Same coefficients the chat box uses to map a channel's declared
-- colour onto the palette, deliberately — two different answers to "how bright
-- is this" in one interface is one too many.
--
-- Here rather than in cl_hud so the suite can pin it without an engine.
function Omerta.HUD.Luma(r, g, b)
    local value = 0.299 * (tonumber(r) or 0)
        + 0.587 * (tonumber(g) or 0)
        + 0.114 * (tonumber(b) or 0)
    if value < 0 then return 0 end
    if value > 255 then return 255 end
    return math.floor(value + 0.5)
end

-- The stored multiple, clamped. NOT the effective scale — Omerta.HUD.Scale()
-- multiplies this by the base.
function Omerta.HUD.ClampScale(value)
    value = tonumber(value) or 1
    if value ~= value then return 1 end -- NaN
    return math.max(Omerta.HUD.SCALE_MIN, math.min(Omerta.HUD.SCALE_MAX, value))
end

-- Before the rebase the convar held an ABSOLUTE scale, and the value in the
-- field is 1.75 — which read as a multiple would clamp to 1.4 and hand that
-- player an interface 2.45x the base. Anything above the multiplier ceiling is
-- therefore a value from the old meaning, and the honest answer for it is the
-- new default: 1x now IS what 1.75 used to be, so resetting lands them exactly
-- where they already were.
function Omerta.HUD.MigrateScale(stored)
    stored = tonumber(stored)
    if not stored or stored ~= stored then return 1 end
    if stored > Omerta.HUD.SCALE_MAX then return 1 end
    return Omerta.HUD.ClampScale(stored)
end

-- One step of an element's fade, in isolation. Reversing mid-fade works
-- naturally because the current alpha is the only state.
function Omerta.HUD.StepAlpha(alpha, wantVisible, dt, fadeSeconds)
    local step = (fadeSeconds and fadeSeconds > 0) and (dt / fadeSeconds) or 1
    if wantVisible then
        return math.min(1, alpha + step)
    end
    return math.max(0, alpha - step)
end

--------------------------------------------------------------------------------
-- The reveal: how anything that pops up arrives, and how it leaves
--------------------------------------------------------------------------------
-- ONE curve, ONE pair of durations, ONE distance, for every window, modal and
-- plate in the game. The inventory window had this to itself for a while and
-- was the only thing on screen that felt made rather than switched on; the
-- numbers below are that implementation's, promoted rather than re-tuned,
-- because they were arrived at in the field and a second opinion on them buys
-- nothing.
--
-- WHY THERE IS MOVEMENT AT ALL. The style guide says "MOTION IS FADE ... no
-- slide, no scale" (sh_theme), and this departs from it deliberately, on the
-- project lead's instruction. A thing that only fades has no direction: the
-- window arrives from nowhere and reads as a state change rather than as
-- something picked up and put down. Forty-two pixels is small enough that
-- nobody watches it travel and large enough that the eye is told where the
-- window came from. The rest of the guide's rule survives — nothing in this
-- game slides sideways and nothing scales, so the departure is one axis wide.
--
-- WHY THE WAY OUT IS QUICKER THAN THE WAY IN. Coming in, the animation is the
-- thing announcing itself and wants a moment to be seen. Going out, the player
-- has already decided; anything they have to wait through on the way to
-- something else is an irritation, and they will dismiss these windows hundreds
-- of times a session. Twenty milliseconds is not a number anybody perceives as
-- a duration, but the asymmetry is felt as responsiveness.
--
-- WHY THIS IS THREE PURE FUNCTIONS AND NOT Panel:AlphaTo/MoveTo. Derma's own
-- animation system owns the panel's position for the length of the tween, and
-- half these windows re-lay-out and re-centre themselves while they are on
-- screen (the inventory does it on every inventory stream — several times a
-- second during Loot All). A tween would keep walking the panel toward a
-- coordinate the layout had already abandoned, and a close arriving mid-tween
-- would fight the one already running. Holding a single 0..1 position and
-- recomputing alpha and offset from it EVERY frame means a rebuild that moves
-- the window simply moves where the animation is aiming, and reversing
-- direction is one boolean rather than a cancel.
--
-- Pure and shared so the headless suite can pin all of it; the panel plumbing
-- that consumes it is Omerta.HUD.Reveal in cl_widgets.lua.

-- Seconds in, seconds out, and the travel in DESIGN pixels — before
-- Omerta.HUD.Scale(), like every other pixel constant in the interface. One
-- table rather than three loose constants so a call site cannot quietly pick up
-- half of the standard.
Omerta.HUD.REVEAL = {
    IN = 0.12,
    OUT = 0.10,
    RISE = 42,
}

-- Smoothstep, the same curve the inventory used: it leaves and arrives with
-- zero velocity, so neither end of the travel has a visible corner in it. A
-- linear ramp was what the very first version did and it read as a jump-cut at
-- both ends; an ease-out-only curve fixed the arrival and left the departure
-- looking like the window had been dropped.
--
-- Clamped rather than trusted, because the position it eases is stepped by
-- frame time and a single enormous frame (a map load, an alt-tab) would
-- otherwise hand a negative or over-unity value straight to a draw call.
function Omerta.HUD.RevealEase(position)
    position = tonumber(position) or 0
    if position ~= position then return 0 end -- NaN
    position = math.max(0, math.min(1, position))
    return position * position * (3 - 2 * position)
end

-- One step of a reveal's 0..1 position. Returns the new position and whether
-- the play-out has FINISHED — one call answers both "where is it" and "is it
-- gone", so a panel cannot be removed on a frame it is still being drawn on,
-- and cannot linger invisible on the frame after it stopped being drawn.
--
-- Reversing mid-animation needs no special case for the same reason StepAlpha
-- needs none: the position is the only state there is, so a window closed
-- halfway through opening sinks from halfway rather than snapping to the top
-- first.
function Omerta.HUD.StepReveal(position, closing, dt)
    position = tonumber(position) or 0
    if position ~= position then position = 0 end -- NaN
    dt = tonumber(dt) or 0

    if closing then
        local out = Omerta.HUD.REVEAL.OUT
        position = position - (out > 0 and (dt / out) or 1)
        if position <= 0 then return 0, true end
        return position, false
    end

    if position >= 1 then return 1, false end
    local inSeconds = Omerta.HUD.REVEAL.IN
    return math.min(1, position + (inSeconds > 0 and (dt / inSeconds) or 1)), false
end

-- How far BELOW its resting place a thing at this point in its reveal sits.
-- Positive is down, because screen Y is: at rest the offset is zero and the
-- window is where the layout put it, so nothing that reads a position while the
-- animation is finished has to know the animation exists.
function Omerta.HUD.RevealOffset(eased, rise)
    return (tonumber(rise) or 0) * (1 - (tonumber(eased) or 0))
end

--------------------------------------------------------------------------------
-- Entity labels
--------------------------------------------------------------------------------
-- What is written under the interaction dot when you look at something.
--
-- The label is asked of the ENTITY, not decided here: a crate, a counter and a
-- payphone each know what a stranger walking past is entitled to read off them,
-- and this file never learns what an item is. The same seam D-017 used for the
-- dot itself.
--
-- Two rules make this safe under §4a:
--
--   * A label may only repeat what the client ALREADY has. Entities carry the
--     public facts as networked variables (an item's definition, a bar's sign)
--     and keep the private ones — container ids, private line numbers, who owns
--     the safe — on the server, where they always were.
--   * PEOPLE ARE NOT LABELLED. Players have no OmertaLabel and must never get
--     one. Who somebody is, is learned by being told (M6); a name floating over
--     a stranger is the single thing this project exists to not do.
--
-- Returns title, subtitle — subtitle optional, both nil when there is nothing
-- to say.
function Omerta.HUD.LabelFor(ent)
    if not IsValid(ent) then return nil end
    if type(ent.OmertaLabel) ~= "function" then return nil end

    -- A label that errors must cost a frame's text, not the whole HUD.
    local ok, title, subtitle = pcall(ent.OmertaLabel, ent)
    if not ok or type(title) ~= "string" or title == "" then return nil end
    if type(subtitle) ~= "string" or subtitle == "" then subtitle = nil end
    return title, subtitle
end

--------------------------------------------------------------------------------
-- Stamina networking
--------------------------------------------------------------------------------
-- Sent PRIVATELY to its owner rather than stored in a networked variable. An
-- NWFloat would be the obvious implementation and is exactly what M6's audit
-- flags: networked variables are readable by every client, so a stamina value
-- would publish who is sprinting — and by extension who is running from what.

Omerta.Net.Register("hud.stamina", {
    realm = "server_to_client",
    schema = { { name = "value", type = "uint", bits = 7 } }, -- 0..100
    handler = function(payload)
        hook.Run("Omerta.StaminaUpdated", payload.value / 100)
    end,
})
