-- The timed action: a predicate, a duration, an interruption, one prompt.
--
-- M19 built this inside `injury/sv_treatment.lua` and wrote in the comment that
-- "Tech §18 will require exactly this of M20's confirm kill; building it here
-- means M20 inherits it instead of reinventing it." That reasoning was right
-- and M14 is the third time it applies — opening a register, levering one, and
-- going through a till are the same shape as bandaging a man — so D-046
-- promotes it out of injury and into a primitive beside Omerta.Interaction.
--
-- M19's treatments and downed actions are its first callers and their
-- definitions did not change shape. M15's evidence collection, M17's arrest and
-- C4's drilling inherit it rather than writing a fourth copy — and the fourth
-- copy is always the one that forgets to cancel on disconnect.
--
-- The rule this module exists to enforce: NOTHING WORTH DOING IS INSTANT, and
-- everything that takes time can be taken away from you halfway through.

Omerta.Action = Omerta.Action or {}
Omerta.Action.Internal = Omerta.Action.Internal or {}

--------------------------------------------------------------------------------
-- The prompt
--------------------------------------------------------------------------------

-- What a timed action sounds like from inside it. Codes rather than paths on
-- the wire; the client owns which file a code means. Frozen — these travel on
-- the wire and a renumber is a silent behaviour change on every client that has
-- not reconnected.
Omerta.Action.PROMPT_SOUND = {
    NONE   = 0,
    RUSTLE = 1, -- going through pockets
}

-- MILLISECONDS, not whole seconds.
--
-- This carried a floored `seconds` and it was the wrong unit for the same
-- reason the weapon draw already gives (sh_weapons): a duration that is not a
-- whole number is a bar that finishes at the wrong moment, and a duration below
-- one second floors to ZERO — which reaches the client as a prompt whose window
-- has already closed, so the plate is never drawn at all while everything else
-- the action does still happens. `injury.search_seconds` is configurable down
-- to 0, so that was a live setting away rather than hypothetical. 16 bits
-- carries just over a minute, which is the longest action the registry allows.
function Omerta.Action.PromptMillis(seconds)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then return 0 end
    return math.min(65535, math.floor(seconds * 1000 + 0.5))
end

-- The longest an action may run. Not a taste limit: the wire carries the clock
-- in 16 bits of milliseconds, so anything past this reaches the client as a
-- truncated bar that finishes early while the server is still counting.
Omerta.Action.MAX_SECONDS = 65

Omerta.Net.Register("action.prompt", {
    realm = "server_to_client",
    schema = {
        { name = "text",   type = "string", maxlen = 72 },
        { name = "millis", type = "uint", bits = 16 },
        { name = "sound",  type = "uint", bits = 2 },
    },
    handler = function(payload)
        -- Handed on in seconds: the client counts against a clock, and every
        -- other clock it holds is in seconds.
        hook.Run("Omerta.ActionPrompt", payload.text,
            (payload.millis or 0) / 1000, payload.sound)
    end,
})

--------------------------------------------------------------------------------
-- Validation (pure)
--------------------------------------------------------------------------------
-- Kept apart from Begin so the rules are testable without a server, exactly as
-- M20's event validation is.

-- Returns true, or false + reason.
function Omerta.Action.Validate(spec)
    if type(spec) ~= "table" then return false, "an action needs a specification" end
    if type(spec.id) ~= "string" or not spec.id:find("^[a-z0-9_%.]+$") then
        return false, "action id '" .. tostring(spec.id) .. "' must be lowercase [a-z0-9_.]"
    end
    if type(spec.label) ~= "string" or spec.label == "" then
        return false, "action '" .. spec.id .. "' needs a label"
    end
    local duration = tonumber(spec.duration)
    if not duration or duration < 0 then
        return false, "action '" .. spec.id .. "' needs a duration"
    end
    if duration > Omerta.Action.MAX_SECONDS then
        -- Loud rather than clamped. A clamp would leave the server finishing at
        -- one time and every client's bar at another, which looks like lag and
        -- is actually a truncated integer.
        return false, string.format("action '%s' runs %ds, past the %ds the wire carries",
            spec.id, duration, Omerta.Action.MAX_SECONDS)
    end
    if type(spec.onComplete) ~= "function" then
        return false, "action '" .. spec.id .. "' needs an onComplete"
    end
    return true
end
