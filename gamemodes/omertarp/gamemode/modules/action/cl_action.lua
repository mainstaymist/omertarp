-- What an action looks like from inside it.
--
-- The guide's §08 timed-action plate: a 320px scrim above the bottom edge, the
-- verb in Oswald caps, and a bare 2px progress line — no ticks, no number
-- (GDD §8). A character knows they are working on something; they do not know
-- they are 62% through it.
--
-- This lived in `injury/cl_injury.lua` and moved here with the machinery
-- (D-046). It was never an injury element: the death module was already firing
-- `Omerta.InjuryPrompt` from `death.progress` to borrow it, which is what a
-- shared thing looks like just before somebody makes it shared.

local prompt, promptUntil = nil, 0
local promptStart, promptTotal = 0, 0

-- WHETHER A PROMPT IS WANTED, HELD APART FROM WHAT IT SAYS.
--
-- The controller calls `draw` on every frame an element's alpha is above zero,
-- which includes the frames it is fading OUT — after `visible` has already gone
-- false. So an element that throws away the thing it draws the moment it stops
-- being wanted gets asked to draw nothing, errors, and is removed by the
-- controller. That is what turned a cancelled search into a client with no
-- timed-action plate at all for the rest of the session: the search was
-- cancelled server-side within a tick, this cleared `prompt` to nil while the
-- plate was still two frames into its fade, and string.upper(nil) took the
-- element off the screen permanently. The text and its clock now survive the
-- fade and only this flag is cleared.
local promptShown = false

-- The rummage is audible from inside it: a RUSTLE-coded prompt plays a stretch
-- of the shared rustle bed for exactly the prompt's window. The player itself
-- lives in the hud module — injury owned its own BASS channel once, and two
-- copies of a sound player is how one of them keeps playing.
hook.Add("Omerta.ActionPrompt", "omerta.action.prompt", function(text, duration, soundKind)
    if not text or text == "" then
        promptShown = false
        Omerta.HUD.StopRustle()
        return
    end
    prompt = text
    promptShown = true
    promptStart = CurTime()
    promptTotal = duration or 0
    promptUntil = CurTime() + (duration or 4)

    if soundKind == Omerta.Action.PROMPT_SOUND.RUSTLE then
        Omerta.HUD.Rustle(duration or 4)
    else
        Omerta.HUD.StopRustle()
    end
end)

-- A new character is a clean screen. Anything left over from the last one is
-- a plate describing work nobody in this body ever started.
hook.Add("Omerta.CharactersState", "omerta.action.reset", function()
    promptShown = false
    Omerta.HUD.StopRustle()
end)

Omerta.HUD.Register("action.prompt", {
    order = 45,
    fade = 0.2,
    -- This is the plate the project lead was describing: start searching a body
    -- and it appears with the clock running. It pops up, so it arrives like
    -- everything else that pops up — twelve pixels, the plate distance, not the
    -- window one. The weapon-draw plate below it in cl_equip.lua uses the same
    -- number for the same reason, and must keep doing so: the two are
    -- deliberately the same object in two modules' hands.
    rise = 12,
    visible = function() return promptShown and CurTime() < promptUntil end,
    draw = function(alpha, rise)
        -- Belt and braces on top of keeping the text through the fade: this
        -- runs on frames `visible` has already said no to, so it can never
        -- assume the state `visible` guards. The weapon-draw plate makes the
        -- same check for the same reason.
        if not prompt then return end
        local scale = Omerta.HUD.Scale()

        local width = 320 * scale
        local pad = 16 * scale
        local timed = promptTotal > 0
        local tall = timed and 62 * scale or 48 * scale
        local x = ScrW() * 0.5 - width * 0.5
        -- The plate's own Y, plus wherever the reveal currently has it. Every
        -- part of the plate is drawn relative to this one number, so the words
        -- and the progress line travel with the scrim rather than each needing
        -- to remember the offset.
        local y = ScrH() - 120 * scale - tall + rise

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
            -- A prompt with no clock (a sentence like "Somebody is working on
            -- you.") gets the plate and the words, nothing else.
            draw.SimpleText(prompt, Omerta.HUD.Font("label"),
                x + pad, y + tall * 0.5,
                Omerta.HUD.Colour("text", 255 * alpha),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end,
})
