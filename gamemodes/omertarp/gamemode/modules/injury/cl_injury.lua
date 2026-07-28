-- What being hurt looks like.
--
-- M8 built the injury element as an empty seam and it has returned nil since.
-- This fills it in — with prose, never a bar and never a number (GDD §8). A
-- character knows they are bleeding badly; they do not know they are at 31%.

Omerta.Injury.Client = Omerta.Injury.Client or {}
local C = Omerta.Injury.Client

C.state = Omerta.Injury.STATE.HEALTHY
C.seconds = 0
C.total = 0
C.body = nil

local prompt, promptUntil = nil, 0
local carrying = false

hook.Add("Omerta.InjuryUpdated", "omerta.injury.state", function(newState, left)
    local wasDown = Omerta.Injury.IsDown(C.state)
    C.state = newState or Omerta.Injury.STATE.HEALTHY
    C.seconds = left or 0
    -- The first message of a bleed-out carries the full window, which is what
    -- the ring needs to draw a fraction rather than a countdown.
    if Omerta.Injury.IsDown(C.state) and not wasDown then
        C.total = math.max(1, C.seconds)
    elseif not Omerta.Injury.IsDown(C.state) then
        C.total = 0
    else
        C.total = math.max(C.total, C.seconds)
    end
end)

hook.Add("Omerta.InjuryBody", "omerta.injury.body", function(index)
    C.body = index > 0 and Entity(index) or nil
end)

hook.Add("Omerta.InjuryPrompt", "omerta.injury.prompt", function(text, duration)
    if not text or text == "" then prompt = nil return end
    prompt = text
    promptUntil = CurTime() + (duration or 4)
end)

hook.Add("Omerta.InjuryCarrying", "omerta.injury.carrying", function(value)
    carrying = value == true
end)

hook.Add("Omerta.CharactersState", "omerta.injury.reset", function()
    C.state = Omerta.Injury.STATE.HEALTHY
    C.seconds, C.total, C.body = 0, 0, nil
    prompt, carrying = nil, false
end)

-- 0 at full health, 1 at the moment of death. Everything visual scales off it.
function C.Progress()
    if not Omerta.Injury.IsDown(C.state) or C.total <= 0 then return 0 end
    return math.Clamp(1 - (C.seconds / C.total), 0, 1)
end

-- Only a bleed-out closes in. Stabilized has stopped the clock, so the screen
-- stops closing with it — which is how a player knows the bandage worked
-- without being told a number.
function C.IsDying()
    return C.state == Omerta.Injury.STATE.INCAPACITATED and C.total > 0
end

--------------------------------------------------------------------------------
-- M8's seam, finally used
--------------------------------------------------------------------------------

Omerta.HUD.RegisterInjuryProvider(function()
    -- While down, the big centred treatment below says it better.
    if Omerta.Injury.IsDown(C.state) then return nil end
    return Omerta.Injury.Describe(C.state)
end)

--------------------------------------------------------------------------------
-- The vignette
--------------------------------------------------------------------------------
-- Four edge gradients rather than one radial texture: it needs no asset, so it
-- cannot fail to load, and growing each edge inward reads exactly as the world
-- closing in. It pulses on a slow heartbeat that quickens as the end nears.

local GRADIENT_LEFT  = Material("gui/gradient")
local GRADIENT_UP    = Material("gui/gradient_up")
local GRADIENT_DOWN  = Material("gui/gradient_down")

local pulsePhase = 0

hook.Add("Think", "omerta.injury.pulse", function()
    if not C.IsDying() then pulsePhase = 0 return end
    pulsePhase = pulsePhase + FrameTime() * math.pi * 2 * Omerta.Injury.PulseRate(C.Progress())
end)

Omerta.HUD.Register("injury.vignette", {
    order = 5,
    fade = 1.2,
    visible = function() return C.IsDying() end,
    draw = function(alpha)
        local w, h = ScrW(), ScrH()
        local reach = Omerta.Injury.VignetteReach(C.Progress(), pulsePhase)
        local thickX, thickY = w * 0.5 * reach, h * 0.5 * reach

        -- Deep red rather than black: this is blood loss, not a fade to menu.
        local a = 255 * alpha
        surface.SetDrawColor(120, 10, 10, a)

        surface.SetMaterial(GRADIENT_DOWN)
        surface.DrawTexturedRect(0, 0, w, thickY)
        surface.SetMaterial(GRADIENT_UP)
        surface.DrawTexturedRect(0, h - thickY, w, thickY)

        surface.SetMaterial(GRADIENT_LEFT)
        surface.DrawTexturedRect(0, 0, thickX, h)
        -- Mirrored U, so the same material serves the right-hand edge.
        surface.DrawTexturedRectUV(w - thickX, 0, thickX, h, 1, 0, 0, 1)

        -- A flat wash underneath, so the very last seconds genuinely dim.
        surface.SetDrawColor(60, 0, 0, math.min(140, 160 * C.Progress()) * alpha)
        surface.DrawRect(0, 0, w, h)
    end,
})

--------------------------------------------------------------------------------
-- The circular timer
--------------------------------------------------------------------------------

-- An arc as a polygon ring. Drawn rather than textured for the same reason as
-- the vignette: no asset to be missing.
local function drawArc(cx, cy, radius, thickness, fraction, colour, segments)
    if fraction <= 0 then return end
    segments = segments or 96
    local used = math.max(1, math.ceil(segments * fraction))
    local inner = radius - thickness
    surface.SetDrawColor(colour)
    draw.NoTexture()
    for i = 0, used - 1 do
        -- Starts at twelve o'clock and runs clockwise, the way a clock does.
        local a1 = math.rad(-90 + (i / segments) * 360)
        local a2 = math.rad(-90 + ((i + 1) / segments) * 360)
        surface.DrawPoly({
            { x = cx + math.cos(a1) * inner,  y = cy + math.sin(a1) * inner },
            { x = cx + math.cos(a1) * radius, y = cy + math.sin(a1) * radius },
            { x = cx + math.cos(a2) * radius, y = cy + math.sin(a2) * radius },
            { x = cx + math.cos(a2) * inner,  y = cy + math.sin(a2) * inner },
        })
    end
end

Omerta.HUD.Register("injury.clock", {
    order = 12,
    fade = 0.8,
    visible = function() return C.IsDying() end,
    draw = function(alpha)
        local scale = Omerta.HUD.Scale()
        local radius, thickness = 46 * scale, 4 * scale
        local cx, cy = ScrW() * 0.5, ScrH() * 0.5 - 96 * scale
        local left = 1 - C.Progress()

        -- The track it is emptying along, so the ring reads as a measure
        -- rather than an arbitrary arc.
        drawArc(cx, cy, radius, thickness, 1, Color(70, 20, 20, 120 * alpha))
        drawArc(cx, cy, radius, thickness, left, Color(200, 70, 60, 235 * alpha))
    end,
})

--------------------------------------------------------------------------------
-- What is happening to you
--------------------------------------------------------------------------------

local DOWN_SUBTITLES = {
    [Omerta.Injury.STATE.INCAPACITATED] =
        "If you do not find help soon, you will die here.",
    [Omerta.Injury.STATE.STABILIZED] =
        "The bleeding has stopped. You still need a doctor.",
}

Omerta.HUD.Register("injury.down", {
    order = 13,
    fade = 0.8,
    visible = function() return Omerta.Injury.IsDown(C.state) end,
    draw = function(alpha)
        local scale = Omerta.HUD.Scale()
        local title = C.state == Omerta.Injury.STATE.INCAPACITATED
            and "You are bleeding out" or "You cannot move"

        draw.SimpleText(title, Omerta.HUD.Font("headline"),
            ScrW() * 0.5, ScrH() * 0.5,
            Color(226, 214, 198, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        local subtitle = DOWN_SUBTITLES[C.state]
        if subtitle then
            draw.SimpleText(subtitle, Omerta.HUD.Font("small"),
                ScrW() * 0.5, ScrH() * 0.5 + 26 * scale,
                Color(188, 168, 160, 220 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end,
})

--------------------------------------------------------------------------------
-- What somebody is doing to you, or you to them
--------------------------------------------------------------------------------

Omerta.HUD.Register("injury.prompt", {
    order = 45,
    fade = 0.2,
    visible = function() return prompt ~= nil and CurTime() < promptUntil end,
    draw = function(alpha)
        draw.SimpleText(prompt, Omerta.HUD.Font("label"),
            ScrW() * 0.5, ScrH() * 0.64,
            Color(225, 218, 200, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end,
})

Omerta.HUD.Register("injury.carrying", {
    order = 46,
    fade = 0.3,
    visible = function() return carrying end,
    draw = function(alpha)
        draw.SimpleText("You are carrying somebody", Omerta.HUD.Font("small"),
            ScrW() * 0.5, ScrH() * 0.84,
            Color(200, 194, 178, 220 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end,
})

--------------------------------------------------------------------------------
-- The dot lights up for a body worth walking to
--------------------------------------------------------------------------------
-- Predicate rather than class: bodies are prop_ragdolls now, and lighting the
-- dot up for every ragdoll on the map would point at the furniture.

Omerta.HUD.RegisterInteractablePredicate("injury.body", function(ent)
    return ent:GetNWBool("OmertaBody", false)
end)
