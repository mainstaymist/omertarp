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

-- Accessibility: text scales, and the clamp is pure so it can be tested.
Omerta.HUD.SCALE_MIN, Omerta.HUD.SCALE_MAX = 0.75, 1.5

function Omerta.HUD.ClampScale(value)
    value = tonumber(value) or 1
    if value ~= value then return 1 end -- NaN
    return math.max(Omerta.HUD.SCALE_MIN, math.min(Omerta.HUD.SCALE_MAX, value))
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
