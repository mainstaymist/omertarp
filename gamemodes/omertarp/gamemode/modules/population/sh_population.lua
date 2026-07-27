-- Hidden population: the suppressions that stop the engine and the default
-- gamemode from handing out what M5 made players earn.
--
-- This module mostly DELETES. Its correctness is measured by what a player
-- cannot find, which is why it ships with an audit (sv_population.lua) rather
-- than trusting that the suppressions stay installed.

Omerta.Module.Register({
    name = "population",
    depends = { "characters", "identity" },
})

Omerta.Population = Omerta.Population or {}

-- Every player sits on one team, always. Faction never touches the team API
-- (Tech §4): team counts are client-readable, so a faction-shaped team layout
-- would publish the size of the police force to anyone who asked.
Omerta.Population.TEAM_CITIZEN = 1

--------------------------------------------------------------------------------
-- D-015: Player:Nick() / Name() / GetName()
--------------------------------------------------------------------------------
-- These return the Steam name, so any stray print — ours, an addon's, an admin
-- mod's — would leak a real-world identity that can be correlated with a
-- character. They now return "Unknown" for everyone, except that on the client
-- your own methods return your own character's name.
--
-- The true Steam name stays reachable server-side via Omerta.Population.RealName
-- for logs, audit rows and staff tooling. This is not airtight: Nick() is a Lua
-- method and the engine still knows the truth (M6 §7).

if Omerta.InEngine then
    local PLAYER = FindMetaTable("Player")

    -- Captured once. Guarded so a Lua refresh cannot overwrite the original
    -- with our own replacement and lose the real name permanently.
    PLAYER.OmertaSteamName = PLAYER.OmertaSteamName or PLAYER.Nick

    local function displayName(self)
        if CLIENT and self == LocalPlayer() then
            local own = Omerta.Characters.GetLocal()
            if own then return own.first_name .. " " .. own.last_name end
        end
        return Omerta.Identity.UNKNOWN
    end

    PLAYER.Nick = displayName
    PLAYER.Name = displayName
    PLAYER.GetName = displayName
end

--------------------------------------------------------------------------------
-- Leak audit analysis (spike S3)
--------------------------------------------------------------------------------
-- Pure: the engine gathers, these decide. Shared because the surfaces live in
-- BOTH realms — the suppressions are client-side hooks, so only a client can
-- confirm they are installed, while net registry, networked vars and teams are
-- the server's business.

Omerta.Population.Internal = Omerta.Population.Internal or {}
local Internal = Omerta.Population.Internal

-- Hooks whose absence means a suppression has been displaced. Client-side.
Omerta.Population.SUPPRESSIONS = {
    ScoreboardShow   = "scoreboard",
    AddDeathNotice   = "kill feed",
    ChatText         = "join/leave announcements",
    PlayerStartVoice = "voice speaker panel",
}

-- Field names that look like they carry a person's identity. Heuristic on
-- purpose: the audit's job is to make a human look in the right places, not to
-- prove safety. "first"/"last" are here because a name field is often split.
local NAMEY = { "name", "nick", "steam", "player", "ident", "first", "last" }

-- Networked variables GMod itself sets on players. Ours must be none, so
-- anything outside this list came from us or an addon and wants a look.
local ENGINE_NWVARS = {
    UserGroup = true,
}

local function looksNamey(field)
    local lower = string.lower(field)
    for _, needle in ipairs(NAMEY) do
        if lower:find(needle, 1, true) then return true end
    end
    return false
end

-- Server->client messages carrying name-like string fields. Some are entirely
-- legitimate (identity.name is a per-observer resolved name — the whole point
-- of M5), so these are reported for review rather than as faults.
function Internal.AnalyzeNetRegistry(registry)
    local findings = {}
    local names = {}
    for name in pairs(registry) do names[#names + 1] = name end
    table.sort(names)

    for _, name in ipairs(names) do
        local def = registry[name]
        if def.realm == "server_to_client" then
            for _, field in ipairs(def.schema or {}) do
                if field.type == "string" and looksNamey(field.name) then
                    findings[#findings + 1] = {
                        severity = "review",
                        what = string.format("net '%s' sends string field '%s' to clients",
                            name, field.name),
                    }
                end
            end
        end
    end
    return findings
end

-- Networked variables on players are readable by EVERY client, which makes
-- them the classic accidental leak: one SetNWString with a character name
-- publishes it to the whole server. String values can carry identity, so those
-- are faults; numbers and booleans are worth a look but rarely identifying.
-- samples: array of { player = label, key = string, value = any }
function Internal.AnalyzeNWVars(samples)
    local findings = {}
    for _, sample in ipairs(samples) do
        if not ENGINE_NWVARS[sample.key] then
            findings[#findings + 1] = {
                severity = type(sample.value) == "string" and "leak" or "review",
                what = string.format("player %s has networked var '%s' = %s",
                    tostring(sample.player), tostring(sample.key), tostring(sample.value)),
            }
        end
    end
    return findings
end

-- Each suppression must actually be installed. present: { [hookEvent] = bool }
function Internal.AnalyzeSuppressions(present)
    local findings = {}
    local events = {}
    for event in pairs(Omerta.Population.SUPPRESSIONS) do events[#events + 1] = event end
    table.sort(events)

    for _, event in ipairs(events) do
        if not present[event] then
            findings[#findings + 1] = {
                severity = "leak",
                what = string.format("%s suppression is missing (hook '%s' not installed)",
                    Omerta.Population.SUPPRESSIONS[event], event),
            }
        end
    end
    return findings
end

-- Everyone belongs to one team; a second team means something is publishing
-- group membership through a client-readable API.
function Internal.AnalyzeTeams(teamsInUse)
    local findings = {}
    for _, teamId in ipairs(teamsInUse) do
        if teamId ~= Omerta.Population.TEAM_CITIZEN then
            findings[#findings + 1] = {
                severity = "leak",
                what = "players are split across teams (found team " .. tostring(teamId) ..
                    ") — team membership is client-readable",
            }
        end
    end
    return findings
end

function Internal.AnalyzeNickOverride(isOverridden)
    if isOverridden then return {} end
    return { {
        severity = "leak",
        what = "Player:Nick() is not overridden — Steam names are reachable from Lua (D-015)",
    } }
end

-- Shared reporting so both realms print findings identically.
function Omerta.Population.Report(channel, findings, context)
    if #findings == 0 then
        Omerta.Log.Info(channel, "leak audit (%s): no findings", context)
        return
    end
    Omerta.Log.Info(channel, "leak audit (%s): %d finding(s)", context, #findings)
    for _, f in ipairs(findings) do
        if f.severity == "leak" then
            Omerta.Log.Error(channel, "  LEAK   %s", f.what)
        else
            Omerta.Log.Warn(channel, "  review %s", f.what)
        end
    end
end
