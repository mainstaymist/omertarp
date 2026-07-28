-- The camera, while you are on the floor and after you stop being on it.
--
-- Going down does not cut to a spectator view. The camera stays in your head,
-- and your head is a ragdoll bone — so as you fall, the view falls with it and
-- ends up looking at whatever your face ends up looking at. That is the whole
-- reason the body is a real ragdoll rather than a prop lying at a fixed angle.

local C = Omerta.Injury.Client

--------------------------------------------------------------------------------
-- The death camera
--------------------------------------------------------------------------------

C.death = nil -- { startedAt, body, at, eye, eyeAng }

hook.Add("Omerta.CharacterDiedLocally", "omerta.injury.death_camera", function(index, at)
    local body = index > 0 and Entity(index) or nil
    local eye, eyeAng = EyePos(), EyeAngles()
    if IsValid(body) then
        local attachment = body:LookupAttachment("eyes")
        local data = attachment and attachment > 0 and body:GetAttachment(attachment)
        if data then eye, eyeAng = data.Pos, data.Ang end
    end

    C.death = {
        startedAt = CurTime(),
        body = body,
        at = at,
        eye = eye,
        eyeAng = eyeAng,
    }
end)

hook.Add("Omerta.CharactersState", "omerta.injury.death_clear", function()
    C.death = nil
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
    -- Dead: the pull-away.
    if C.death then
        local D = Omerta.Injury.DEATH
        local elapsed = CurTime() - C.death.startedAt
        local phase, t = Omerta.Injury.DeathPhase(elapsed)

        if phase == "hold" then
            return { origin = C.death.eye, angles = C.death.eyeAng, fov = fov,
                     drawviewer = true }
        end

        local at = IsValid(C.death.body) and C.death.body:GetPos() or C.death.at
        local eased = Omerta.Injury.RiseEase(t)
        local top = overheadPosition(at, D.HEIGHT)
        local origin = LerpVector(eased, C.death.eye, top)
        -- Pitch rolls over to straight down as it climbs; yaw is held so the
        -- world does not spin under the shot.
        local ang = Angle(
            Lerp(eased, C.death.eyeAng.p, 90),
            C.death.eyeAng.y,
            0)
        return { origin = origin, angles = ang, fov = fov, drawviewer = true }
    end

    -- Down: first person, riding the ragdoll's head.
    if not Omerta.Injury.IsDown(C.state) then return end
    local body = C.body
    if not IsValid(body) then return end

    local attachment = body:LookupAttachment("eyes")
    local data = attachment and attachment > 0 and body:GetAttachment(attachment)
    if not data then return end

    -- Not drawing the viewer: the camera is inside the head, and rendering the
    -- head from inside it is a view of the back of a face.
    return { origin = data.Pos, angles = data.Ang, fov = fov, drawviewer = false }
end)

--------------------------------------------------------------------------------
-- Everything a downed player must not be able to do
--------------------------------------------------------------------------------

-- The server freezes them, but the client should not offer the controls
-- either: swinging a mouse that moves nothing reads as being broken rather
-- than as being helpless.
hook.Add("InputMouseApply", "omerta.injury.no_look", function()
    if C.death or Omerta.Injury.IsDown(C.state) then return true end
end)

hook.Add("HUDShouldDraw", "omerta.injury.hide_world_hud", function(name)
    if not (C.death or Omerta.Injury.IsDown(C.state)) then return end
    -- No weapon selector or hands over a body.
    if name == "CHudWeaponSelection" or name == "CHudCrosshair" then return false end
end)

hook.Add("CalcViewModelView", "omerta.injury.no_viewmodel", function()
    if C.death or Omerta.Injury.IsDown(C.state) then
        -- Far enough behind the camera to be certainly out of frame.
        return Vector(0, 0, -10000), Angle(0, 0, 0)
    end
end)
