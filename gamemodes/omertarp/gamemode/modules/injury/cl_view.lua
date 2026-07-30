-- The camera, while you are on the floor and after you stop being on it.
--
-- Going down does not cut to a spectator view. The camera stays in your head,
-- and your head is a ragdoll bone — so as you fall, the view falls with it and
-- ends up looking at whatever your face ends up looking at. That is the whole
-- reason the body is a real ragdoll rather than a prop lying at a fixed angle.

Omerta.Injury.Client = Omerta.Injury.Client or {}
local C = Omerta.Injury.Client

--------------------------------------------------------------------------------
-- The death camera
--------------------------------------------------------------------------------

C.death = nil -- { startedAt, body, at, eye, eyeAng }

-- Where a body's eyes are, right now.
--
-- The attachment is the good answer and every Half-Life 2 playermodel has it.
-- The head bone is the fallback, because a custom model without an "eyes"
-- attachment would otherwise drop the camera back to the frozen player entity
-- — which is a view floating in mid-air where they were standing.
local HEAD_BONES = {
    "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Neck1", "bip_head",
}

function Omerta.Injury.EyesOf(body)
    if not IsValid(body) then return nil end

    local attachment = body:LookupAttachment("eyes")
    if attachment and attachment > 0 then
        local data = body:GetAttachment(attachment)
        if data then return data.Pos, data.Ang end
    end

    for _, name in ipairs(HEAD_BONES) do
        local bone = body:LookupBone(name)
        if bone then
            local pos, ang = body:GetBonePosition(bone)
            if pos then return pos, ang or body:GetAngles() end
        end
    end
    return nil
end

hook.Add("Omerta.CharacterDiedLocally", "omerta.injury.death_camera", function(index, at)
    local body = index > 0 and Entity(index) or nil
    local pos, ang = Omerta.Injury.EyesOf(body)

    C.death = {
        startedAt = CurTime(),
        body = body,
        at = at,
        -- Only a fallback. While the camera is holding on the body it tracks
        -- the head live, so a ragdoll still settling carries the view with it.
        eye = pos or EyePos(),
        eyeAng = ang or EyeAngles(),
        from = nil, -- captured on the first frame of the rise
    }
end)

-- Cleared only when a NEW character is active.
--
-- This hook used to fire on any state change, and death sends NEEDS_CREATION —
-- so the death state wiped itself the instant it was set. No fade, no camera
-- move, no music, and the creation window opened over the body, all from this
-- one line.
hook.Add("Omerta.CharactersState", "omerta.injury.death_clear", function(state)
    if state == Omerta.Characters.STATE.ACTIVE then C.death = nil end
end)

-- Straight down onto the body, MAP-relative: the camera looks down at the
-- world, not down the body's own axis, so a man who fell face-first and a man
-- who fell on his back get the same shot.
--
-- Traced so it cannot end up inside a ceiling. Somebody dying in a stairwell
-- gets a lower shot rather than a view of the inside of the floor above.
local function overheadPosition(at, height)
    local target = at + Vector(0, 0, height)
    local trace = util.TraceLine({
        start = at + Vector(0, 0, 8),
        endpos = target,
        mask = MASK_SOLID_BRUSHONLY,
    })
    if trace.Hit then
        return trace.HitPos - Vector(0, 0, Omerta.Injury.DEATH.CEILING)
    end
    return target
end

hook.Add("CalcView", "omerta.injury.view", function(ply, pos, angles, fov)
    -- Leaving: the shot is frozen where the climb left it. Snapping back to
    -- the player entity behind the black would be invisible, but the first
    -- frame of the reveal would show it.
    --
    -- Unless the front end has already taken the screen: the menu is REVEALED
    -- by this fade, so its camera has to be running before the black lifts,
    -- not cut to afterwards. Soft reference — the menu module is not a
    -- dependency of injuries, and a server without it keeps the frozen shot.
    local menuUp = Omerta.Menu and Omerta.Menu.IsShowing and Omerta.Menu.IsShowing()
    if C.leaving and C.leaving.view and not menuUp then return C.leaving.view end

    -- Dead: hold on the body, then pull up and away.
    if C.death then
        local D = Omerta.Injury.DEATH
        local elapsed = CurTime() - C.death.startedAt
        local phase, t = Omerta.Injury.DeathPhase(elapsed)

        -- Track the head live rather than using the snapshot, so a ragdoll
        -- still coming to rest takes the view down with it.
        local livePos, liveAng = Omerta.Injury.EyesOf(C.death.body)
        local eye = livePos or C.death.eye
        local eyeAng = liveAng or C.death.eyeAng

        if phase == "hold" then
            return { origin = eye, angles = eyeAng, fov = fov, drawviewer = true }
        end

        -- Frozen at the instant the rise begins, so a ragdoll still settling
        -- does not make the climb stutter.
        if not C.death.from then C.death.from = eye end

        local at = IsValid(C.death.body) and C.death.body:GetPos() or C.death.at
        local eased = Omerta.Injury.RiseEase(t)

        -- The rise starts ALREADY looking down, from just above the body, and
        -- only translates. Tweening the pitch from wherever the head happened
        -- to be lying round to straight down spends the whole shot in an
        -- orientation that is neither, and reads as a mistake. A cut is the
        -- normal grammar here; the rotation was the awkward part.
        local origin = LerpVector(eased,
            overheadPosition(at, D.START_HEIGHT), overheadPosition(at, D.HEIGHT))
        -- Yaw is held from where they fell, so the world does not spin.
        local ang = Angle(90, C.death.eyeAng.y, 0)
        C.lastDeathView = { origin = origin, angles = ang, fov = fov, drawviewer = true }
        return C.lastDeathView
    end

    -- Down: first person, riding the ragdoll's head.
    if not Omerta.Injury.IsDown(C.state) then return end
    local eye, eyeAng = Omerta.Injury.EyesOf(C.Body())
    if not eye then return end

    -- Not drawing the viewer: the camera is inside the head, and rendering the
    -- head from inside it is a view of the back of a face.
    return { origin = eye, angles = eyeAng, fov = fov, drawviewer = false }
end)

--------------------------------------------------------------------------------
-- Everything a downed player must not be able to do
--------------------------------------------------------------------------------

-- The server freezes them, but the client should not offer the controls
-- either: swinging a mouse that moves nothing reads as being broken rather
-- than as being helpless.
hook.Add("InputMouseApply", "omerta.injury.no_look", function()
    -- Not during the exit: the character creator needs the mouse back the
    -- moment it is built, which is before the black has finished lifting.
    if C.death or Omerta.Injury.IsDown(C.state) then return true end
end)

local HIDDEN_WHILE_DOWN = {
    CHudWeaponSelection = true,
    CHudCrosshair = true,
}

-- Chat goes at the moment of death and not before: somebody bleeding out can
-- still be spoken to, and being cut off from the room would remove the only
-- thing left to do. Once dead there is nothing to read and the screen belongs
-- to the moment.
hook.Add("HUDShouldDraw", "omerta.injury.hide_world_hud", function(name)
    if (C.death or C.leaving) and (name == "CHudChat" or HIDDEN_WHILE_DOWN[name]) then
        return false
    end
    if Omerta.Injury.IsDown(C.state) and HIDDEN_WHILE_DOWN[name] then return false end
end)

-- Everything the world was making noise about stops. The trombone and the
-- piano are BASS channels (sound.PlayFile), which this hook does not touch —
-- which is exactly why both moved off surface.PlaySound.
hook.Add("EntityEmitSound", "omerta.injury.silence", function()
    if C.death or C.leaving then return false end
end)

hook.Add("CalcViewModelView", "omerta.injury.no_viewmodel", function()
    if C.death or C.leaving or Omerta.Injury.IsDown(C.state) then
        -- Far enough behind the camera to be certainly out of frame.
        return Vector(0, 0, -10000), Angle(0, 0, 0)
    end
end)
