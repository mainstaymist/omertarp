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
-- Looking down a sight
--------------------------------------------------------------------------------
-- D-041 made the crosshair permanent and gave it its information by BRIGHTNESS
-- rather than by presence. Aiming is the one state where it should go entirely:
-- a sight picture IS the aiming instrument, and a dot painted over the middle
-- of it is a second one disagreeing with the first by a pixel or two.
--
-- HOW AIMING IS DETECTED, AND WHY IT IS NOT A QUESTION FOR THE WEAPON.
--
-- Nothing here asks ARC9, or TFA, or our own base, whether the player is
-- aiming. D-044's rule is that we detect by what we intend to READ, never by a
-- name — and the reading is this: EVERY weapon system that puts a player into
-- ironsights narrows their field of view, because that is what ironsights are.
-- ARC9 does it, TFA does it, a scope nobody has written yet will do it, and our
-- own base will do it on the day W0 §6's deferred ironsights land. One reading
-- covers all of them and none of them can break it, because none of them is
-- being called.
--
-- IT IS A RATIO, NOT A DIFFERENCE. A sight that takes a third off the picture
-- takes a third off it whether the player runs at 75 degrees or at 120, so
-- `fov / base` is the same number for both of them and `base - fov` is not.
-- Comparing the difference would mean a player on a wide field of view never
-- triggering it and a player on a narrow one triggering it constantly.
--
-- IT IS ONE-SIDED. Only NARROWING counts. Sprint effects and damage kicks widen
-- the field of view, and a wider picture is the opposite of a sight picture.
--
-- WHAT HAPPENS WHEN SOMETHING THAT IS NOT AIMING MOVES THE FIELD OF VIEW — a
-- cinematic, a spectate camera, a future security-camera view. The honest
-- answer is that this reading CANNOT TELL THEM APART, and it does not try:
-- there is no magnitude that distinguishes a four-power scope from a slow push
-- in on a face, and inventing a threshold that claimed to would be exactly the
-- guess D-044 forbids. What makes that acceptable is that all of them want the
-- SAME OUTCOME. A camera that is not the player's own eyes has nothing for the
-- player to aim at, so the dot going away is correct for the cinematic and the
-- spectate camera for their own reasons. The reading's failure mode is right by
-- coincidence, and saying so out loud is cheaper than a mechanism that would
-- have to be told about every camera anybody ever adds.
--
-- WHAT HAPPENS WHEN THE READING IS UNAVAILABLE — no player, a zero, a NaN, a
-- convar that is not there. It answers NOT AIMING, always. The dot is D-041's
-- one permitted permanent element and the expensive failure is losing it; a
-- broken reading must leave the interface as it was, never blank part of it.

Omerta.HUD.AIM = {
    -- Narrowed to 95% of the field of view this player chose: aiming.
    --
    -- Loose on purpose, and the asymmetry of the two mistakes is the argument.
    -- A false positive costs a 1.2px dot fading for as long as the narrowing
    -- lasts, which nobody will ever report. A false negative is the bug we were
    -- asked to fix — a sight that only takes 6% never hides the crosshair — and
    -- it is invisible from here because we cannot read what any sight does. So
    -- the threshold sits below anything worth calling a sight and above
    -- anything that happens by accident.
    ENTER = 0.95,

    -- And back out past 98%. TWO thresholds rather than one because a single
    -- one chatters: an aim that settles near the boundary would cross it on
    -- frame-time noise, and the thing it would flicker is a mark at the exact
    -- centre of the screen. Three points of hysteresis is far narrower than any
    -- real transition and far wider than any jitter.
    LEAVE = 0.98,

    -- Seconds, each way. QUICKER THAN THE ELEMENT'S OWN 0.15s, deliberately,
    -- and the element keeps its 0.15 for everything else.
    --
    -- 0.15 is tuned for something appearing because the WORLD changed — a door
    -- came into reach, a window opened — where a moment of travel reads as the
    -- screen responding to a situation. Aiming is not that. It is a thing the
    -- player is doing with their own hand, and an interface response to a
    -- direct input has to land inside the window where the eye still reads it
    -- as CAUSED BY the input; past about a tenth of a second it reads as the
    -- interface catching up instead.
    --
    -- 0.06 is four frames at 60Hz: enough that it is a fade rather than a cut
    -- at the centre of the screen (which is the jump-cut D-042 argues against),
    -- and short enough that the dot is gone before the sight picture has
    -- finished arriving. It is also comfortably under REVEAL.OUT's 0.10, so the
    -- crosshair is never the slowest thing on screen.
    FADE = 0.06,
}

-- Is this player looking down a sight?
--
--   fov    — their field of view this frame (Player:GetFOV)
--   base   — the field of view they play at with nothing narrowing it
--            (fov_desired). The SAME KIND of reading as `fov`, which is the
--            whole reason the pair is comparable.
--   aiming — the previous answer, so the hysteresis band above has somewhere
--            to live without this function holding state. Same idiom as
--            StepAlpha taking the current alpha: the caller owns the state and
--            the rule stays pure and pinnable.
function Omerta.HUD.IsAiming(fov, base, aiming)
    fov, base = tonumber(fov) or 0, tonumber(base) or 0
    -- NaN survives every comparison it touches, so it is caught rather than
    -- compared. Everything degenerate answers "not aiming"; see the header for
    -- why that direction is the safe one.
    if fov ~= fov or base ~= base then return false end
    if fov <= 0 or base <= 0 then return false end

    local ratio = fov / base
    if ratio > 1 then return false end -- widened, which is not aiming

    local A = Omerta.HUD.AIM
    if aiming then return ratio <= A.LEAVE end
    return ratio <= A.ENTER
end

--------------------------------------------------------------------------------
-- Is the player in the world?
--------------------------------------------------------------------------------
-- "A man standing in a street with pockets." It is the question every key poll
-- and every window in the game is really asking before it puts something on
-- screen, and until now each caller assembled its own answer out of whichever
-- full-screen states it happened to remember.
--
-- The inventory key is what made that a bug. It knew about the console, the
-- engine's own menu and the chat box — everything the ENGINE owns — and about
-- nothing this gamemode owns, so pockets opened over the front end, over
-- character creation and over the pause rail. The next screen to poll a key
-- would have had to remember the same list, and would have remembered a
-- different subset of it.
--
-- THE FACTS, and why each is a fact rather than three:
--
--   character  the client has a live character standing in the city. That one
--              fact is the whole of the front end's absence: somebody at the
--              menu with nobody to be, somebody mid-creation, somebody reading
--              "no season is running", somebody who has just died — the server
--              has put nobody in the city, so there are no pockets to look in.
--              It is also what covers M4's own fallback window, which is the
--              creation screen in a build with no menu module at all.
--   menu       ONE question — Omerta.Menu.IsShowing() — and deliberately the
--              broad one. The front end, character creation and the pause rail
--              are the same panel in three states (phase / mode / screen), and
--              IsShowing() is true for all three: IsPaused() is a strict subset
--              of it, and creation is a SCREEN of it. Asking the three
--              separately is how the fourth one gets forgotten.
--   death      the death card, and the fade that carries it away. Not implied
--              by `character`: the state message and the screen run on two
--              different clocks, and the seconds between them are exactly when
--              a window must not survive.
--
-- DEFAULT DENY. A fact that is missing, or is anything other than a plain
-- boolean, reads as "not in the world" — the same discipline SoundStillWanted
-- follows below. Being wrong in that direction costs a key that does nothing
-- for a frame; being wrong in the other puts an inventory over a death scene.
--
-- Pure, so the suite can pin the rule; the client gathers the facts below.
function Omerta.HUD.InWorldFrom(facts)
    if type(facts) ~= "table" then return false end
    if facts.character ~= true then return false end
    if facts.menu == true then return false end
    if facts.death == true then return false end
    return true
end

if CLIENT then
    -- The facts, gathered. Every reference is SOFT, for two different reasons:
    -- this is a shared file and the modules it asks are client-only, and one of
    -- them is genuinely optional — M4 still runs in a build with no menu.
    -- A module that is not there cannot be showing anything.
    function Omerta.HUD.InWorld()
        local characters = Omerta.Characters
        local menu = Omerta.Menu
        local injury = Omerta.Injury and Omerta.Injury.Client

        return Omerta.HUD.InWorldFrom({
            character = characters ~= nil and characters.GetLocal ~= nil
                and characters.GetLocal() ~= nil,
            menu = menu ~= nil and menu.IsShowing ~= nil and menu.IsShowing() == true,
            death = injury ~= nil
                and (injury.death ~= nil or injury.leaving ~= nil),
        })
    end
end

--------------------------------------------------------------------------------
-- The lens
--------------------------------------------------------------------------------
-- A slight, permanent darkening at the edges of the picture. It is there from
-- the moment the game starts and it never goes away, and that needs answering
-- rather than assuming: GDD §8 keeps the persistent screen EMPTY, and D-041
-- grants exactly one exception to it — the crosshair — with an M8 acceptance
-- test that fails the moment a second element joins it.
--
-- THE ANSWER IS THAT A VIGNETTE IS NOT AN ELEMENT. It is atmosphere, not
-- information. The empty-screen rule is a rule about what the interface TELLS
-- the player: D-033 states it as a ban on omniscient information rather than on
-- information as such, and D-041 admitted the dot because a player cannot aim
-- at a point that is not drawn. Both are arguments about things that are READ.
-- A vignette cannot be read. It has no state, it responds to nothing, it
-- answers no question, and a player who studies it learns precisely nothing
-- they did not already have. It is closer to the lens the picture is taken
-- through than to anything printed on top of it — which is why it is drawn
-- UNDER the interface, in HUDPaintBackground, and never through
-- Omerta.HUD.Register.
--
-- THAT DISTINCTION IS A DOOR, AND IT IS LOAD-BEARING THAT IT STAYS SHUT.
-- "Atmosphere, not information" is exactly the sentence somebody will reach for
-- in a year to justify a permanent ammunition ring, a permanent compass strip,
-- a permanent anything — and every one of those is a thing you look at in order
-- to find something out. The test is not whether a thing is subtle, or pretty,
-- or drawn in a different hook. It is whether a player could ever GAIN by
-- looking at it. If they could, it is information: it is an element, and it
-- goes through the controller, the visible() condition and the idle assertion
-- like everything else. cl_selftest.lua puts the test in those words rather
-- than the idle assertion being widened to let this through — the same move
-- D-041 made when it named its exception instead of weakening the check.
--
-- The numbers live here rather than in the client file so the suite can pin the
-- one thing about a vignette worth pinning: that "slight" is a quantity and not
-- an opinion.

Omerta.HUD.VIGNETTE = {
    -- How far each edge gradient reaches inward, as a fraction of the HALF
    -- dimension it grows from. That is the same measure M19's bleed-out
    -- vignette uses, deliberately: the two are the same object at different
    -- strengths, and a second way of expressing "how far in" would be a second
    -- thing to keep in step. At 0.38 the middle 62% of the picture is untouched
    -- in both axes, so nothing a player is looking at is ever inside it.
    REACH = 0.38,

    -- Ink opacity at the outermost pixel, before presence. Under the threshold
    -- at which the eye reads a vignette AS a vignette rather than as the
    -- picture having weight — which is the whole brief. The corners, where two
    -- gradients overlap, come to about 24%, and a corner is where a real lens
    -- is darkest anyway.
    EDGE = 0.13,

    -- Seconds to hand the edges over to M19's vignette, and to take them back.
    -- Matched to that element's own fade so the two cross rather than cut.
    FADE = 1.2,
}

-- The two band thicknesses and the ink opacity for the lens at this presence.
--
-- Pure — no Color, no ScrW — so the suite can drive it, and garbage-proof for
-- the same reason StepAlpha is: presence is stepped by frame time, and one
-- enormous frame (a map load, an alt-tab) must not hand a negative or
-- over-unity value to a draw call.
--
-- A presence of zero returns an alpha of zero, which is the caller's cue to
-- draw nothing at all rather than four invisible rectangles.
function Omerta.HUD.VignetteBands(w, h, presence)
    presence = tonumber(presence) or 0
    if presence ~= presence then return 0, 0, 0 end -- NaN
    presence = math.max(0, math.min(1, presence))

    local V = Omerta.HUD.VIGNETTE
    w, h = tonumber(w) or 0, tonumber(h) or 0
    return w * 0.5 * V.REACH, h * 0.5 * V.REACH, V.EDGE * 255 * presence
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
-- Asynchronous sound
--------------------------------------------------------------------------------
-- sound.PlayFile is ASYNCHRONOUS, and there is nothing to stop before its
-- callback lands: stopping a channel that does not exist yet is a no-op, so a
-- request cancelled during the load carries on and plays anyway. That is how a
-- search cancelled a tick after it started could still be heard rummaging for
-- four seconds with nothing on screen — the sound had already been asked for,
-- and the stop had nothing to act on.
--
-- Two facts answer it, and both are only knowable inside the callback: whether
-- the request is still the CURRENT one (a token, bumped by every stop and every
-- fresh request), and whether its window has since closed. Pure so the suite can
-- pin the rule; the BASS plumbing is Omerta.HUD.Rustle in cl_widgets.lua.
-- Silence is the safe answer to every question this cannot answer: a clock it
-- cannot read is not a licence to make a noise nothing on screen explains.
function Omerta.HUD.SoundStillWanted(token, current, now, stopAt)
    if token ~= current then return false end
    now, stopAt = tonumber(now), tonumber(stopAt)
    if not (now and stopAt) then return false end
    if now ~= now or stopAt ~= stopAt then return false end -- NaN
    return now <= stopAt
end

--------------------------------------------------------------------------------
-- When the controller gives up on an element
--------------------------------------------------------------------------------
-- A broken element must not take the whole screen down with it, and it must not
-- keep erroring forever either — but removing it on its FIRST bad frame turns
-- any momentary race into a HUD element that is gone for the rest of the
-- session, with no notice to the player and no way back short of reconnecting.
-- That is a large permanent punishment for a transient fault, and it is what
-- made one cancelled search look like "the search bar is broken now".
Omerta.HUD.DRAW_FAILURES_ALLOWED = 3

function Omerta.HUD.DrawFailureIsFatal(consecutive)
    return (tonumber(consecutive) or 0) >= Omerta.HUD.DRAW_FAILURES_ALLOWED
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
