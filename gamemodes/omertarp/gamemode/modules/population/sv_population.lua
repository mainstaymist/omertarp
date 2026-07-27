-- Server side of hidden population: the real-name accessor, team posture, and
-- the leak audit (spike S3).
--
-- The audit exists because suppressions are easy to install and easy to lose:
-- a Lua refresh, an addon, or a future milestone can silently displace one.
-- Rather than trusting that M6 stays true, this checks and is meant to be
-- re-run after every milestone.

local MODULE = Omerta.Module.Get("population")

Omerta.Population = Omerta.Population or {}
Omerta.Population.Internal = Omerta.Population.Internal or {}
local Internal = Omerta.Population.Internal

-- The genuine Steam name, for logs, audit rows and staff tools only. Never
-- send this to a client (D-015).
function Omerta.Population.RealName(ply)
    Omerta.AssertServer("Omerta.Population.RealName")
    if not IsValid(ply) then return "?" end
    local original = FindMetaTable("Player").OmertaSteamName
    return original and original(ply) or "?"
end

--------------------------------------------------------------------------------
-- Audit analysis (pure — the engine gathers, these decide)
--------------------------------------------------------------------------------

-- Field names that look like they carry a person's identity. Heuristic on
-- purpose: the audit's job is to make a human look at the right places, not to
-- prove safety.
local NAMEY = { "name", "nick", "steam", "player", "ident" }

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
-- publishes it to the whole server. We set none, so anything found is a fault.
-- samples: array of { player = label, key = string, value = any }
function Internal.AnalyzeNWVars(samples)
    local findings = {}
    for _, sample in ipairs(samples) do
        findings[#findings + 1] = {
            severity = "leak",
            what = string.format("player %s has networked var '%s' = %s",
                tostring(sample.player), tostring(sample.key), tostring(sample.value)),
        }
    end
    return findings
end

-- Each suppression must actually be installed. present: { [hookEvent] = bool }
function Internal.AnalyzeSuppressions(present)
    local expected = {
        ScoreboardShow = "scoreboard",
        AddDeathNotice = "kill feed",
        ChatText = "join/leave announcements",
        PlayerStartVoice = "voice speaker panel",
    }
    local findings = {}
    local events = {}
    for event in pairs(expected) do events[#events + 1] = event end
    table.sort(events)

    for _, event in ipairs(events) do
        if not present[event] then
            findings[#findings + 1] = {
                severity = "leak",
                what = string.format("%s suppression is missing (hook '%s' not installed)",
                    expected[event], event),
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

--------------------------------------------------------------------------------
-- Gathering (engine side)
--------------------------------------------------------------------------------

function Omerta.Population.Audit()
    local findings = {}
    local function add(list)
        for _, f in ipairs(list) do findings[#findings + 1] = f end
    end

    add(Internal.AnalyzeNetRegistry(Omerta.Net.GetRegistry()))

    local PLAYER = FindMetaTable("Player")
    add(Internal.AnalyzeNickOverride(
        PLAYER.OmertaSteamName ~= nil and PLAYER.Nick ~= PLAYER.OmertaSteamName))

    local hooks = hook.GetTable()
    local present = {}
    for _, event in ipairs({ "ScoreboardShow", "AddDeathNotice", "ChatText", "PlayerStartVoice" }) do
        local installed = hooks[event]
        present[event] = installed ~= nil and next(installed) ~= nil
    end
    add(Internal.AnalyzeSuppressions(present))

    local samples, teams, seenTeam = {}, {}, {}
    for _, ply in ipairs(player.GetAll()) do
        local label = ply:SteamID64() or "?"
        if ply.GetNWVarTable then
            for key, value in pairs(ply:GetNWVarTable() or {}) do
                samples[#samples + 1] = { player = label, key = key, value = value }
            end
        end
        local t = ply:Team()
        if not seenTeam[t] then seenTeam[t] = true; teams[#teams + 1] = t end
    end
    add(Internal.AnalyzeNWVars(samples))
    add(Internal.AnalyzeTeams(teams))

    return findings
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    team.SetUp(Omerta.Population.TEAM_CITIZEN, "Citizen", Color(170, 170, 170))
    hook.Add("PlayerInitialSpawn", "omerta.population.team", function(ply)
        ply:SetTeam(Omerta.Population.TEAM_CITIZEN)
    end)

    -- Suppress the base gamemode's join announcement. PlayerDisconnected is
    -- deliberately NOT hooked here: returning a value from it would stop the
    -- accounts, characters and identity handlers that share the event, and the
    -- leave line is suppressed client-side via ChatText instead.
    hook.Add("PlayerConnect", "omerta.population.connect", function() return true end)

    concommand.Add("omerta_leak_audit", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local findings = Omerta.Population.Audit()
        if #findings == 0 then
            Omerta.Log.Info("population", "leak audit: no findings")
            return
        end
        Omerta.Log.Info("population", "leak audit: %d finding(s)", #findings)
        for _, f in ipairs(findings) do
            if f.severity == "leak" then
                Omerta.Log.Error("population", "  LEAK   %s", f.what)
            else
                Omerta.Log.Warn("population", "  review %s", f.what)
            end
        end
        Omerta.Log.Info("population",
            "note: Steam names and player count remain visible via `status`, the Steam " ..
            "overlay and server queries — see docs/rules/metagaming.md")
    end)
end
