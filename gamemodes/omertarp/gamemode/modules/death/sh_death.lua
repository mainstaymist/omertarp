-- Confirmed death (M20, D-038).
--
-- The most abusable mechanic in the project, which is why M19 refused to build
-- it and why everything here is shaped by Tech §18's four words: the act must
-- be deliberate, logged, interruptible, and visible.
--
-- This file is the pure half — who may do it, to whom, and what the act is
-- called. The act itself, and everything that follows it, is server-side.

Omerta.Death = Omerta.Death or {}
Omerta.Death.Internal = Omerta.Death.Internal or {}

-- Named causes rather than free text, so M21 can pick a headline template and
-- M17 can ask "was this a killing" without matching strings.
Omerta.Death.CAUSE = {
    CONFIRMED = "confirmed",  -- somebody stood over them and finished it
    BLED_OUT  = "untreated",  -- D-037 §4b: nobody came
    STAFF     = "staff",
}

--------------------------------------------------------------------------------
-- Who may finish whom
--------------------------------------------------------------------------------

-- D-038 §4a: down is DOWN. A bandage buys time, never immunity — so a
-- stabilized character is as finishable as a bleeding one, and what protects a
-- helpless man is whoever is standing over him rather than what is in his
-- pockets.
--
-- Pure, and returns a reason, so the interaction and the self-test ask exactly
-- the same question.
function Omerta.Death.CanFinish(targetState, actorState, actorId, targetId)
    if actorId and targetId and actorId == targetId then
        return false, "you cannot"
    end
    if not Omerta.Injury.IsDown(targetState) then
        -- Not down: either they are on their feet, or they are already dead.
        if targetState == Omerta.Injury.STATE.DEAD then
            return false, "they are already dead"
        end
        return false, "they are not helpless"
    end
    if actorState and Omerta.Injury.IsIncapable(actorState) then
        return false, "you are in no condition to"
    end
    return true
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------
-- There is exactly one message and it goes to the two people involved.
--
-- No death notice is broadcast, ever. No feed, no announcement, no "X has
-- died" (GDD §6, Tech §4). You learn about a killing by seeing it, by finding
-- the body, by being told, or by reading about it — and the event row exists so
-- the NEWSPAPER can find out, never so a client can be informed.

Omerta.Net.Register("death.progress", {
    realm = "server_to_client",
    schema = {
        { name = "text",    type = "string", maxlen = 48 },
        { name = "seconds", type = "uint", bits = 8 },
    },
    handler = function(payload)
        hook.Run("Omerta.InjuryPrompt", payload.text, payload.seconds)
    end,
})
