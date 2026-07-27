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

--------------------------------------------------------------------------------
-- Client half of the leak audit
--------------------------------------------------------------------------------
-- The suppressions above are client-side hooks, so only a client can confirm
-- they are still installed — an addon or a Lua refresh can displace them here
-- without the server ever knowing.

function Omerta.Population.ClientAudit()
    local findings = {}
    local function add(list)
        for _, f in ipairs(list) do findings[#findings + 1] = f end
    end

    local hooks = hook.GetTable()
    local present = {}
    for event in pairs(Omerta.Population.SUPPRESSIONS) do
        local installed = hooks[event]
        present[event] = installed ~= nil and next(installed) ~= nil
    end
    add(Omerta.Population.Internal.AnalyzeSuppressions(present))

    local PLAYER = FindMetaTable("Player")
    add(Omerta.Population.Internal.AnalyzeNickOverride(
        PLAYER.OmertaSteamName ~= nil and PLAYER.Nick ~= PLAYER.OmertaSteamName))

    return findings
end

concommand.Add("omerta_leak_audit_client", function()
    Omerta.Population.Report("population", Omerta.Population.ClientAudit(), "this client")
end)
