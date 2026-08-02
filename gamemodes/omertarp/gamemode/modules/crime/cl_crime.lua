-- What M14 draws, which is nothing of its own.
--
-- No robbery HUD. No timer, no progress ring pinned to the screen, no
-- objective. D-041 permits exactly one element on an idle screen and it is the
-- crosshair; M8's acceptance test fails the moment a second joins it, and this
-- milestone is not going to be the one that argues for an exception.
--
-- The register work uses the promoted timed-action prompt, refusals use the cue
-- stack, and everything else is communicated in the world: the till opening, the
-- clerk backing away, his hand going under the counter.
--
-- The headline check, in the style M8 set: TWO MEN WALK INTO A SHOP AND WALK
-- OUT WITH FOUR HUNDRED DOLLARS IN ACTUAL NOTES, AND THE ONLY THING ON
-- ANYBODY'S SCREEN IS WHAT IS IN THEIR POCKETS.

-- So the whole client half of this milestone is one line: the dot lights up for
-- the man behind the counter, because he is something worth walking to.
--
-- He gets an action hint and NO NAME. He has no character row, so M5 resolves
-- him as Unknown to everybody, permanently, through the path M19's bodies
-- already use. D-033 is not stretched here: objects name themselves and people
-- never do, and he is a person.
local function isClerk(ent)
    return ent:GetClass() == "omerta_clerk"
end

Omerta.HUD.RegisterInteractablePredicate("crime.clerk", isClerk)

-- ONE LINE UNDER THE DOT, AND IT NAMES THE JOB RATHER THAN THE MAN.
--
-- Without this he lights the dot up and says nothing, which reads as a bug
-- rather than as discretion — the counter beside him describes itself and he
-- does not. What he is NOT given is a name: he has no character row, so M5
-- resolves him as Unknown to everybody permanently, and D-033 is not stretched
-- by this because "the man behind the counter" is a role, not an identity.
--
-- Deliberately not a state readout. It says the same thing whether he is
-- complying, stalling or about to put his hand under the counter, because
-- reading his mind off the HUD is the one thing this milestone refuses.
Omerta.HUD.RegisterTargetHint("crime.clerk", function(target)
    if not isClerk(target) then return nil end
    return "The man behind the counter"
end)
