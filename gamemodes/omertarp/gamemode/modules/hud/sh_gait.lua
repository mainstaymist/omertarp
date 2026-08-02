-- The three gaits, and which animation each one plays. The pure half.
--
-- WHY THERE CAN BE A THIRD GAIT AT ALL. Source gives a player on his feet two
-- ground animations, ACT_MP_WALK and ACT_MP_RUN, and the base gamemode chooses
-- between them in exactly one place — GM:CalcMainActivity, in
-- gamemodes/base/gamemode/animations.lua:
--
--     local len2d = velocity:Length2D()
--     if ( len2d > 150 ) then ply.CalcIdeal = ACT_MP_RUN
--     elseif ( len2d > 0.5 ) then ply.CalcIdeal = ACT_MP_WALK end
--
-- Note what is NOT in that test. It does not ask which key is held. It does not
-- ask which of the engine's three speed slots the movement code used to arrive
-- at this velocity. GROUND SPEED IS THE ENTIRE INPUT. So "a brisk walk that
-- does not break into a run" is not an animation problem and needs no animation
-- code: it is an arithmetic one, and the answer is a speed that sits above the
-- walk and at or under 150. Below that line the engine plays the walk cycle and
-- speeds its playback up with the character (GM:UpdateAnimation divides the
-- real speed by the sequence's own), which is exactly what walking faster looks
-- like.
--
-- THE THRESHOLD IS A CONSTANT, NOT CONFIGURATION, and that is deliberate in the
-- same way M19's stride length is (sh_injury_falls: "these are GEOMETRY"). It
-- is not our number to tune — it is compiled into somebody else's file, the
-- client needs the same value the server does, and Omerta.Config is server
-- scope and does not replicate (D-036). A config key here would be an
-- invitation to move our copy of a number that had not moved, and the symptom
-- would be a running animation on a walking man.

Omerta.HUD = Omerta.HUD or {}

-- Strictly above this, the base gamemode plays the run. Exactly this, and
-- below, it plays the walk.
--
-- Read out of base/gamemode/animations.lua rather than measured in the field,
-- so it is worth one look at a running man on the first server that takes this
-- build. If a future engine ever moves it, this is the ONE line that moves with
-- it: the fast walk is clamped to this number rather than to a hand-picked one,
-- and every check in the suite asks this constant rather than repeating 150.
Omerta.HUD.RUN_ANIM_ABOVE = 150

Omerta.HUD.GAIT = {
    IDLE = "idle",
    WALK = "walk",
    RUN  = "run",
}

-- What a character at this ground speed LOOKS like, by the engine's own rule.
-- Modelled here so the suite can assert the answer rather than somebody having
-- to load the game and watch a man from the side.
function Omerta.HUD.GaitAnimation(groundSpeed)
    groundSpeed = tonumber(groundSpeed) or 0
    if groundSpeed ~= groundSpeed then return Omerta.HUD.GAIT.IDLE end -- NaN
    if groundSpeed > Omerta.HUD.RUN_ANIM_ABOVE then return Omerta.HUD.GAIT.RUN end
    if groundSpeed > 0.5 then return Omerta.HUD.GAIT.WALK end
    return Omerta.HUD.GAIT.IDLE
end

-- The fast walk: how quickly a character moves while holding ALT.
--
-- A MULTIPLE OF THE WALK rather than an absolute number, so it still means
-- "slightly quicker than walking" after an operator has moved the walk — the
-- same reason M9 expresses the overload reach as a fraction of a capacity.
--
-- Two clamps, and they are the whole reason this is a function rather than a
-- multiplication at the call site:
--
--   * never above the engine's run threshold, which is what makes "ALT does not
--     start the run animation" a property of the code instead of a property of
--     one well-chosen default. An operator may raise the scale as far as they
--     like; the gait stops getting faster before it starts looking wrong.
--   * never below the walk, because a key that makes you slower is the engine
--     behaviour the project lead asked to reverse, and a misconfigured scale
--     must not quietly restore it.
--
-- If the configured WALK is itself at or above the threshold — an operator who
-- has put the base back to the engine's 200 — there is no third gait to be had
-- and this returns the walk unchanged. That character is already playing the
-- run animation while walking; nothing here can fix that, and pretending
-- otherwise by returning something faster would only make it worse.
function Omerta.HUD.FastWalkSpeed(walk, scale)
    walk = math.floor(math.max(tonumber(walk) or 0, 0))
    scale = tonumber(scale) or 1
    -- NaN, or a scale that would make holding the key a penalty.
    if scale ~= scale or scale < 1 then scale = 1 end
    return math.max(walk, math.min(math.floor(walk * scale),
        Omerta.HUD.RUN_ANIM_ABOVE))
end
