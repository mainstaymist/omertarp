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
Omerta.HUD.RegisterInteractablePredicate("crime.clerk", function(ent)
    return ent:GetClass() == "omerta_clerk"
end)
