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
