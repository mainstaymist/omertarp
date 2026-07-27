-- Client-side suppressions. Each one is a surface that publishes identity or
-- population for free.
--
-- These return true from hook.Add handlers, which stops the gamemode's own
-- implementation from running. That is the intended mechanism for overriding
-- gamemode functions from a module.

-- Scoreboard: a roster of everyone connected, with names. The single largest
-- leak in a default gamemode.
hook.Add("ScoreboardShow", "omerta.population.scoreboard", function() return true end)
hook.Add("ScoreboardHide", "omerta.population.scoreboard_hide", function() return true end)

-- Kill feed: publishes who killed whom, by name, to everyone — the opposite of
-- a city where a body is found and nobody knows who did it.
hook.Add("AddDeathNotice", "omerta.population.deathnotice", function() return true end)

-- Join/leave chat lines. `joinleave` is the message type the engine uses for
-- them, so this suppresses the announcements without touching ordinary chat.
hook.Add("ChatText", "omerta.population.joinleave", function(_, _, _, msgType)
    if msgType == "joinleave" then return true end
end)

-- The default voice panel renders the speaker's Steam name beside a talking
-- indicator — a live who-is-here list for anyone who listens.
hook.Add("PlayerStartVoice", "omerta.population.voice_start", function() return true end)
hook.Add("PlayerEndVoice", "omerta.population.voice_end", function() return true end)

-- The engine's own death-notice HUD element, belt-and-braces with the hook
-- above. Health, ammo and the rest are M8's business, not this milestone's.
local HIDDEN = {
    CHudDeathNotice = true,
}
hook.Add("HUDShouldDraw", "omerta.population.hud", function(name)
    if HIDDEN[name] then return false end
end)
