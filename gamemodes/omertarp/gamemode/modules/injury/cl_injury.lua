-- What being hurt looks like.
--
-- M8 built the injury element as an empty seam and it has returned nil since.
-- This fills it in — with prose, never a bar and never a number (GDD §8). A
-- character knows they are bleeding badly; they do not know they are at 31%.

Omerta.Injury.Client = Omerta.Injury.Client or {}
local C = Omerta.Injury.Client

C.state = Omerta.Injury.STATE.HEALTHY
C.deadline = nil   -- CurTime() the clock runs out; counted down locally
C.total = 0        -- the whole window, so a fraction can be drawn
C.bodyIndex = 0    -- resolved lazily; see C.Body()

local prompt, promptUntil = nil, 0
local promptStart, promptTotal = 0, 0
C.drag = nil -- { bodyIndex, anchor }

-- The sound of a timed action, from inside it. One BASS channel, seeked to a
-- random stretch of the rustle bed so no two searches sound identical, and
-- stopped the moment the prompt goes — a cancelled search goes quiet with it.
local rustle = { channel = nil, stopAt = 0 }

local function stopRustle()
    if rustle.channel and rustle.channel:IsValid() then
        rustle.channel:Stop()
    end
    rustle.channel = nil
end

local function startRustle(duration)
    stopRustle()
    -- "noplay": opened paused so it can be seeked before it makes a sound.
    -- (NOT "noblock" — that flag silently fails for disk files.)
    sound.PlayFile("sound/omertarp/ui/searching-rustle.wav", "noplay", function(channel)
        if not (channel and channel:IsValid()) then return end
        -- The prompt may have ended while the file opened.
        if CurTime() > rustle.stopAt then channel:Stop() return end
        local length = channel:GetLength() or 0
        if length > duration + 1 then
            channel:SetTime(math.Rand(0, length - duration - 0.5))
        end
        channel:SetVolume(0.6)
        channel:Play()
        rustle.channel = channel
    end)
end

hook.Add("Think", "omerta.injury.rustle", function()
    if rustle.channel and CurTime() > rustle.stopAt then stopRustle() end
end)

-- The server sends the clock ONCE, when the state changes. It is not a stream
-- and must not become one — so the client is given a deadline and counts down
-- against it locally. That is also smooth, where a once-per-second push would
-- step the bar in visible jerks.
hook.Add("Omerta.InjuryUpdated", "omerta.injury.state", function(newState, left, total)
    C.state = newState or Omerta.Injury.STATE.HEALTHY

    if (left or 0) > 0 then
        C.deadline = CurTime() + left
        -- `total` is the whole window; falling back to the remainder keeps a
        -- reconnect sane rather than dividing by zero.
        C.total = (total and total > 0) and total or left
    else
        C.deadline, C.total = nil, 0
    end
end)

-- The INDEX is stored, not the entity.
--
-- This message arrives the moment the ragdoll is created server-side, which is
-- before it has replicated here — so Entity(index) was NULL, C.body was
-- invalid forever after, and the first-person camera silently fell back to the
-- frozen player entity. Resolving on demand costs nothing and cannot lose the
-- race.
hook.Add("Omerta.InjuryBody", "omerta.injury.body", function(index)
    C.bodyIndex = index or 0
end)

function C.Body()
    if C.bodyIndex <= 0 then return nil end
    local ent = Entity(C.bodyIndex)
    return IsValid(ent) and ent or nil
end

hook.Add("Omerta.InjuryPrompt", "omerta.injury.prompt", function(text, duration, soundKind)
    if not text or text == "" then
        prompt = nil
        stopRustle()
        return
    end
    prompt = text
    promptStart = CurTime()
    promptTotal = duration or 0
    promptUntil = CurTime() + (duration or 4)

    if soundKind == Omerta.Injury.PROMPT_SOUND.RUSTLE then
        rustle.stopAt = promptUntil
        startRustle(duration or 4)
    else
        stopRustle()
    end
end)

hook.Add("Omerta.InjuryDragging", "omerta.injury.dragging", function(index, bone, anchor)
    C.drag = index > 0 and { bodyIndex = index, bone = bone or 0, anchor = anchor } or nil
end)

-- The body currently being hauled, or nil. Resolved on demand for the same
-- reason C.Body() is: the entity may not have replicated when the message
-- naming it arrived.
function C.DragBody()
    if not C.drag then return nil end
    local ent = Entity(C.drag.bodyIndex)
    return IsValid(ent) and ent or nil
end

-- The client computes tension itself from two positions it already has, using
-- the same pure rule the server enforces with. Nothing about the rope needs to
-- travel over the wire every frame.
-- Where the rope actually meets the body: the physics object that was taken
-- hold of, not the entity origin. Grab a hand and the line ends at the hand.
function C.DragGrip()
    local body = C.DragBody()
    if not body then return nil end
    local phys = body:GetPhysicsObjectNum(C.drag.bone or 0)
    if IsValid(phys) then return phys:GetPos() end
    return body:GetPos()
end

-- The client computes tension itself from two positions it already has, using
-- the same pure rules the server enforces with — including the hold point, so
-- the line on screen tightens at exactly the moment the body starts to move.
function C.DragTension()
    local grip = C.DragGrip()
    if not grip then return 0 end
    local ply = LocalPlayer()
    local hold = Omerta.Injury.HoldPoint(ply:GetPos(), ply:GetAimVector())
    return Omerta.Injury.DragTension(grip:Distance(hold))
end

hook.Add("Omerta.CharactersState", "omerta.injury.reset", function()
    C.state = Omerta.Injury.STATE.HEALTHY
    C.deadline, C.total, C.bodyIndex = nil, 0, 0
    prompt, C.drag = nil, nil
    stopRustle()
end)

-- Seconds left on the clock right now, counted locally.
function C.SecondsLeft()
    if not C.deadline then return 0 end
    return math.max(0, C.deadline - CurTime())
end

-- 0 when the clock starts, 1 at the moment it runs out. Everything visual
-- scales off this one number.
function C.Progress()
    if not Omerta.Injury.IsDown(C.state) or C.total <= 0 then return 0 end
    return math.Clamp(1 - (C.SecondsLeft() / C.total), 0, 1)
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

-- The blur sits UNDER the vignette (order 4 against its 5) so the red is drawn
-- over an already-soft world rather than being smeared itself.
local BLUR = Material("pp/blurscreen")

Omerta.HUD.Register("injury.blur", {
    order = 4,
    fade = 1.4,
    visible = function() return C.IsDying() end,
    draw = function(alpha)
        local amount = Omerta.Injury.BlurAmount(C.Progress()) * alpha
        if amount <= 0.05 then return end

        -- Several light passes rather than one heavy one: the material's own
        -- blur is stepped, and stacking is what makes it read as focus going
        -- rather than as a smear.
        surface.SetMaterial(BLUR)
        surface.SetDrawColor(255, 255, 255, 255)
        for pass = 1, 3 do
            BLUR:SetFloat("$blur", (pass / 3) * amount)
            BLUR:Recompute()
            render.UpdateScreenEffectTexture()
            surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
        end
    end,
})

local pulsePhase = 0

hook.Add("Think", "omerta.injury.pulse", function()
    if not C.IsDying() then pulsePhase = 0 return end
    pulsePhase = pulsePhase + FrameTime() * math.pi * 2 * Omerta.Injury.PulseRate(C.Progress())
end)

-- The guide's §14: the world closing in is FOUR NESTED TRANSLUCENT INK
-- RECTANGLES thickening as you go — cheap, immediate-mode, no gradient asset,
-- and it reads as the edges of vision going rather than a colour filter. The
-- same VignetteReach curve drives the total thickness (with its one-sided
-- heartbeat), split across the four frames from the outside in.
local FRAMES = { 0.55, 0.50, 0.45, 0.40 } -- each layer's ink, outermost first

local function drawFrame(inset, thick, a)
    local w, h = ScrW(), ScrH()
    surface.DrawRect(inset, inset, w - inset * 2, thick)                       -- top
    surface.DrawRect(inset, h - inset - thick, w - inset * 2, thick)           -- bottom
    surface.DrawRect(inset, inset + thick, thick, h - (inset + thick) * 2)     -- left
    surface.DrawRect(w - inset - thick, inset + thick, thick,
        h - (inset + thick) * 2)                                               -- right
end

Omerta.HUD.Register("injury.vignette", {
    order = 5,
    fade = 1.2,
    visible = function() return C.IsDying() end,
    draw = function(alpha)
        local reach = Omerta.Injury.VignetteReach(C.Progress(), pulsePhase)
        local total = math.min(ScrW(), ScrH()) * 0.5 * reach
        local layer = total / #FRAMES

        local inset = 0
        for _, ink in ipairs(FRAMES) do
            surface.SetDrawColor(4, 4, 5, 255 * ink * alpha)
            drawFrame(inset, layer, alpha)
            inset = inset + layer
        end
    end,
})

--------------------------------------------------------------------------------
-- The clock
--------------------------------------------------------------------------------
-- A line above the words, shrinking toward its own centre as the time goes.
-- The first version was a radial ring, which read as a loading spinner sitting
-- over a dying man; a line is quieter and says the same thing.

-- The guide's clock: TIME IS A PULSE, NOT A BAR. One 2px #8E2B22 line at the
-- bottom edge that breathes at the same heart rate as the vignette, slowing
-- and shortening as you fade — you feel how long you have without being able
-- to read it, and you can't strategise off it. No track, no ticks, no number.
Omerta.HUD.Register("injury.clock", {
    order = 12,
    fade = 0.8,
    visible = function() return C.IsDying() end,
    draw = function(alpha)
        local scale = Omerta.HUD.Scale()
        local progress = C.Progress()
        local width = 220 * scale * (1 - 0.72 * progress)
        local beat = (1 - math.cos(pulsePhase)) * 0.5
        local presence = (0.35 + 0.65 * beat) * alpha

        surface.SetDrawColor(Omerta.HUD.Colour("danger", 255 * presence))
        surface.DrawRect(ScrW() * 0.5 - width * 0.5,
            ScrH() - 64 * scale, width, 2)
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

        -- The guide writes this moment as PROSE, not a headline: a sentence in
        -- text type, outlined over the world. The game does not raise its
        -- voice even here.
        Omerta.HUD.Text(title, "prose",
            ScrW() * 0.5, ScrH() * 0.5,
            Omerta.HUD.Colour("text", 255 * alpha),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        local subtitle = DOWN_SUBTITLES[C.state]
        if subtitle then
            Omerta.HUD.Text(subtitle, "small",
                ScrW() * 0.5, ScrH() * 0.5 + 34 * scale,
                Omerta.HUD.Colour("secondary", 220 * alpha),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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
        local scale = Omerta.HUD.Scale()

        -- The guide's §08 timed-action plate: a 320px scrim above the bottom
        -- edge, the verb in Oswald caps, and a bare 2px progress line — no
        -- ticks, no number. A prompt with no clock (a sentence like "Somebody
        -- is working on you.") gets the plate and the words, nothing else.
        local width = 320 * scale
        local pad = 16 * scale
        local timed = promptTotal > 0
        local tall = timed and 62 * scale or 48 * scale
        local x = ScrW() * 0.5 - width * 0.5
        local y = ScrH() - 120 * scale - tall

        Omerta.HUD.Scrim(x, y, width, tall, "top", alpha)

        if timed then
            draw.SimpleText(string.upper(prompt), Omerta.HUD.Font("verb"),
                x + pad, y + 14 * scale,
                Omerta.HUD.Colour("text", 255 * alpha),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            local progress = math.Clamp((CurTime() - promptStart) / promptTotal, 0, 1)
            local by = y + tall - 16 * scale
            surface.SetDrawColor(Omerta.HUD.Colour("text", 0.18 * 255 * alpha))
            surface.DrawRect(x + pad, by, width - pad * 2, 2)
            surface.SetDrawColor(Omerta.HUD.Colour("text", 255 * alpha))
            surface.DrawRect(x + pad, by, (width - pad * 2) * progress, 2)
        else
            draw.SimpleText(prompt, Omerta.HUD.Font("label"),
                x + pad, y + tall * 0.5,
                Omerta.HUD.Colour("text", 255 * alpha),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end,
})

--------------------------------------------------------------------------------
-- The rope
--------------------------------------------------------------------------------
-- A line from your hands to whoever you have hold of, drawn taut. It is the
-- only feedback that says how hard you are pulling, and it tightens, reddens
-- and finally shudders as you approach the point where your grip goes.

Omerta.HUD.Register("injury.drag", {
    order = 47,
    fade = 0.25,
    visible = function() return C.DragBody() ~= nil end,
    draw = function(alpha)
        local grip = C.DragGrip()
        if not grip then return end

        local tension = C.DragTension()
        local scale = Omerta.HUD.Scale()

        -- The rope is anchored at the CROSSHAIR, not the bottom of the screen.
        -- That is what makes the mouse part of the mechanic: the hold point in
        -- the world follows where you are looking, so swinging the view swings
        -- the body, and the line on screen is the handle you are swinging.
        local fromX, fromY = ScrW() * 0.5, ScrH() * 0.5

        local at = grip:ToScreen()
        if not at.visible then return end

        -- A taut rope shivers. Amplitude rides on tension, so a slack line is
        -- perfectly still and a straining one is visibly working.
        local shudder = tension * tension * 3 * scale
        local jitter = shudder > 0 and math.sin(CurTime() * 34) * shudder or 0

        surface.SetDrawColor(
            150 + 90 * tension,
            120 - 70 * tension,
            110 - 70 * tension,
            (110 + 120 * tension) * alpha)
        surface.DrawLine(fromX, fromY, at.x + jitter, at.y)

        -- ONE line, deliberately. A second, fainter line back to the original
        -- grab point shipped first and read as a bug — two ropes to one body —
        -- rather than as distance covered. The rope you are holding is the
        -- crosshair one; the anchor stays in the data for the server's use.

        local label = tension >= 0.98 and "Your grip is going"
            or tension > 0.05 and "Hauling" or "You have hold of them"
        Omerta.HUD.Text(label, "small",
            ScrW() * 0.5, ScrH() * 0.62,
            Omerta.HUD.Colour(tension >= 0.98 and "danger" or "secondary", 235 * alpha),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end,
})

--------------------------------------------------------------------------------
-- The dot lights up for a body worth walking to
--------------------------------------------------------------------------------
-- Predicate rather than class: bodies are prop_ragdolls now, and lighting the
-- dot up for every ragdoll on the map would point at the furniture.

local function isBody(ent)
    return ent:GetNWBool("OmertaBody", false)
end

Omerta.HUD.RegisterInteractablePredicate("injury.body", isBody)

-- And the identity label resolves them, so looking at somebody on the floor
-- tells you who they are exactly when looking at them upright would have —
-- their name if you know them, "Unknown" if you do not, and Unknown either way
-- if their face is covered. D-033 keeps objects naming themselves and people
-- not; a body is on the people side of that line, so the answer comes from M5
-- per observer rather than from anything written on the entity.
Omerta.Identity.RegisterLabelPredicate("injury.body", isBody)

-- What you can do with them, under the name. A TARGET HINT rather than its
-- own HUD element: the hud module stacks it below the identity label with
-- measured spacing, which is what ended the two of them being drawn through
-- each other at guessed offsets.
Omerta.HUD.RegisterTargetHint("injury.body", function(target)
    if not isBody(target) then return nil end
    if C.DragBody() ~= nil then return "E to let go" end
    return "E to drag — hold E for more"
end)
