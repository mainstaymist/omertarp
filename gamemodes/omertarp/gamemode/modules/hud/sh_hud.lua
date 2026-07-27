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

Omerta.Module.Register({
    name = "hud",
    depends = { "characters" },
})

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
