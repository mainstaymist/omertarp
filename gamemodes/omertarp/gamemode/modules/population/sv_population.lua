-- Server side of hidden population: the real-name accessor, team posture, and
-- the server half of the leak audit (spike S3).
--
-- The audit exists because suppressions are easy to install and easy to lose:
-- a Lua refresh, an addon, or a future milestone can silently displace one.
-- Rather than trusting that M6 stays true, this checks — and is meant to be
-- re-run after every milestone.
--
-- Realm split matters here. The suppressions are CLIENT-side hooks, so the
-- server cannot see them; checking the server's hook table for them reports
-- four leaks that do not exist. Clients audit themselves via
-- `omerta_leak_audit_client`.

local MODULE = Omerta.Module.Get("population")

Omerta.Population = Omerta.Population or {}
local Internal = Omerta.Population.Internal

-- The genuine Steam name, for logs, audit rows and staff tools only. Never
-- send this to a client (D-015).
function Omerta.Population.RealName(ply)
    Omerta.AssertServer("Omerta.Population.RealName")
    if not IsValid(ply) then return "?" end
    local original = FindMetaTable("Player").OmertaSteamName
    return original and original(ply) or "?"
end

-- Server-side surfaces only.
function Omerta.Population.Audit()
    local findings = {}
    local function add(list)
        for _, f in ipairs(list) do findings[#findings + 1] = f end
    end

    add(Internal.AnalyzeNetRegistry(Omerta.Net.GetRegistry()))

    local PLAYER = FindMetaTable("Player")
    add(Internal.AnalyzeNickOverride(
        PLAYER.OmertaSteamName ~= nil and PLAYER.Nick ~= PLAYER.OmertaSteamName))

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

local function assignTeam(ply)
    if IsValid(ply) then ply:SetTeam(Omerta.Population.TEAM_CITIZEN) end
end

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    team.SetUp(Omerta.Population.TEAM_CITIZEN, "Citizen", Color(170, 170, 170))
    hook.Add("PlayerInitialSpawn", "omerta.population.team", assignTeam)

    -- Also cover players already connected: after a Lua refresh
    -- PlayerInitialSpawn never fires again, so without this they keep whatever
    -- team they had (TEAM_UNASSIGNED, 1001) and the audit rightly complains.
    for _, ply in ipairs(player.GetAll()) do assignTeam(ply) end

    -- Suppress the base gamemode's join announcement. PlayerDisconnected is
    -- deliberately NOT hooked here: returning a value from it would stop the
    -- accounts, characters and identity handlers that share the event, and the
    -- leave line is suppressed client-side via ChatText instead.
    hook.Add("PlayerConnect", "omerta.population.connect", function() return true end)

    concommand.Add("omerta_leak_audit", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        Omerta.Population.Report("population", Omerta.Population.Audit(), "server")
        Omerta.Log.Info("population",
            "client-side suppressions are not visible from here — run " ..
            "`omerta_leak_audit_client` in a client console to check those")
        Omerta.Log.Info("population",
            "note: Steam names and player count remain visible via `status`, the Steam " ..
            "overlay and server queries — see docs/rules/metagaming.md")
    end)
end
