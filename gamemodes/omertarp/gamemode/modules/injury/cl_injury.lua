-- What being hurt looks like.
--
-- M8 built the injury element as an empty seam and it has returned nil since.
-- This fills it in — with a sentence, never a bar and never a number (GDD §8).
-- A character knows they are bleeding badly; they do not know they are at 31%.

local state = Omerta.Injury.STATE.HEALTHY
local seconds = 0
local prompt, promptUntil = nil, 0
local carrying = false

hook.Add("Omerta.InjuryUpdated", "omerta.injury.state", function(newState, left)
    state = newState or Omerta.Injury.STATE.HEALTHY
    seconds = left or 0
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
    state = Omerta.Injury.STATE.HEALTHY
    seconds, prompt, carrying = 0, nil, false
end)

--------------------------------------------------------------------------------
-- M8's seam, finally used
--------------------------------------------------------------------------------

Omerta.HUD.RegisterInjuryProvider(function()
    return Omerta.Injury.Describe(state)
end)

--------------------------------------------------------------------------------
-- The clock, while there is one worth watching
--------------------------------------------------------------------------------
-- Deliberately vague. A dying man knows he is running out of time; he does not
-- have a stopwatch, and a countdown in seconds would turn bleeding out into an
-- arithmetic problem.

local function urgency()
    if state ~= Omerta.Injury.STATE.INCAPACITATED then return nil end
    if seconds <= 0 then return nil end
    if seconds < 30 then return "You do not have long." end
    if seconds < 90 then return "You are fading." end
    return nil
end

Omerta.HUD.Register("injury.urgency", {
    order = 11,
    fade = 0.6,
    visible = function() return urgency() ~= nil end,
    draw = function(alpha)
        draw.SimpleText(urgency(), Omerta.HUD.Font("label"),
            ScrW() * 0.5, ScrH() * 0.76,
            Color(190, 90, 80, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
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
            ScrW() * 0.5, ScrH() * 0.62,
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

-- A body is worth walking over to, so the dot lights up for one.
Omerta.HUD.RegisterInteractableClass("omerta_body")
