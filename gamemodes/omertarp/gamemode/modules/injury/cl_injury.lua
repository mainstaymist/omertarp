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

-- The rummage is audible from inside it: a RUSTLE-coded prompt plays a
-- stretch of the shared rustle bed for exactly the prompt's window. The
-- player itself lives in the hud module — injury owned its own BASS channel
-- once, and two copies of a sound player is how one of them keeps playing.
hook.Add("Omerta.InjuryPrompt", "omerta.injury.prompt", function(text, duration, soundKind)
    if not text or text == "" then
        prompt = nil
        Omerta.HUD.StopRustle()
        return
    end
    prompt = text
    promptStart = CurTime()
    promptTotal = duration or 0
    promptUntil = CurTime() + (duration or 4)

    if soundKind == Omerta.Injury.PROMPT_SOUND.RUSTLE then
        Omerta.HUD.Rustle(duration or 4)
    else
        Omerta.HUD.StopRustle()
    end
end)

hook.Add("Omerta.CharactersState", "omerta.injury.reset", function()
    C.state = Omerta.Injury.STATE.HEALTHY
    C.deadline, C.total, C.bodyIndex = nil, 0, 0
    prompt = nil
    Omerta.HUD.StopRustle()
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

-- A nested-ink-rectangles version replaced the gradients for a while and was
-- rejected: hard-edged frames read as a picture mount around the screen, not
-- as vision going. The soft edges are the effect.
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
    return "E to search"
end)
