-- Client side of the interaction framework: E does the one obvious thing.
--
-- A press runs the target's DEFAULT action — decided server-side, so the
-- client never names an action it was not entitled to. That is the whole
-- protocol: a target with more to offer surfaces its other actions in the
-- loot window, which queries the same registry over the same wire
-- (interaction.query/options). There used to be a held-E menu here; it was
-- cut in favour of that window rather than being a second list of the same
-- verbs.
--
-- The action fires on PRESS, not release. The release path re-checked the aim
-- and silently dropped the action when it had drifted a few pixels in the
-- meantime — which players reported as having to spam E. The press is the
-- moment of intent, and the server re-traces and re-checks everything anyway.

-- Whether the last +use press was ours. The engine pairs presses with
-- releases, so a swallowed press must swallow its own release too — but ONLY
-- its own: eating a release whose press went to the engine would leave a door
-- being held open.
local suppressedPress = false

hook.Add("PlayerBindPress", "omerta.interaction.bind", function(ply, bind, pressed)
    if bind ~= "+use" then return end

    if pressed then
        -- Only things the dot lights up for; a door or a valve keeps the
        -- engine's own use behaviour untouched.
        local target = Omerta.HUD.InteractableTarget()
        if not target then return end
        suppressedPress = true
        Omerta.Net.Request("interaction.default", { target = target:EntIndex() })
        return true
    end

    if suppressedPress then
        suppressedPress = false
        return true
    end
end)
