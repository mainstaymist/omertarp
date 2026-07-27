-- M6 hidden population: the leak audit's analysis logic, driven with both
-- clean and deliberately-leaky fixtures so the audit is proven to CATCH leaks
-- rather than merely to run.

local MODULE_FILES = {
    "gamemodes/omertarp/gamemode/modules/database/sh_database.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_schema.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_sqlbuild.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_database.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sh_accounts.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sv_accounts.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sh_seasons.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sv_seasons.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sh_characters.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sv_characters.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sh_interaction.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sv_interaction.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sh_identity.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sv_identity.lua",
    "gamemodes/omertarp/gamemode/modules/population/sh_population.lua",
    "gamemodes/omertarp/gamemode/modules/population/sv_population.lua",
}

local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

local function countSeverity(findings, severity)
    local n = 0
    for _, f in ipairs(findings) do
        if f.severity == severity then n = n + 1 end
    end
    return n
end

--------------------------------------------------------------------------------
suite("population.audit")
--------------------------------------------------------------------------------

check("net analysis flags name-bearing messages sent to clients", function()
    loadModules()
    local A = Omerta.Population.Internal.AnalyzeNetRegistry

    -- Clean: nothing name-like leaving the server.
    assert(#A({
        ["a.msg"] = { realm = "server_to_client",
                      schema = { { name = "count", type = "uint", bits = 8 } } },
    }) == 0, "numeric payloads should not be flagged")

    -- Client->server carrying a name is fine: it is the client's own input.
    assert(#A({
        ["b.msg"] = { realm = "client_to_server",
                      schema = { { name = "first_name", type = "string", maxlen = 24 } } },
    }) == 0, "inbound messages should not be flagged")

    -- Outbound name-like strings get flagged for review.
    local findings = A({
        ["c.msg"] = { realm = "server_to_client",
                      schema = { { name = "nickname", type = "string", maxlen = 32 } } },
    })
    assert(#findings == 1 and findings[1].severity == "review", "should flag for review")
    assert(findings[1].what:find("c.msg", 1, true), findings[1].what)
end)

check("the real registry's outbound name fields are all accounted for", function()
    loadModules()
    local findings = Omerta.Population.Internal.AnalyzeNetRegistry(Omerta.Net.GetRegistry())
    -- Every flagged message must be one we have deliberately reviewed: the
    -- per-observer resolved name, the introduction prompt, and the player's
    -- own character. If a new one appears, this fails until it is justified.
    local allowed = {
        ["identity.name"] = true,
        ["identity.introduce_prompt"] = true,
        ["characters.self"] = true,
    }
    for _, f in ipairs(findings) do
        local msg = f.what:match("net '([^']+)'")
        assert(allowed[msg], "unreviewed outbound name field: " .. f.what)
        assert(f.severity == "review", "should be review, not leak")
    end
end)

check("networked variables on players are always a leak", function()
    loadModules()
    local A = Omerta.Population.Internal.AnalyzeNWVars
    assert(#A({}) == 0, "no vars means no findings")
    local findings = A({ { player = "7656...", key = "CharName", value = "Tony Marino" } })
    assert(#findings == 1 and findings[1].severity == "leak", "NW vars must be a leak")
    assert(findings[1].what:find("Tony Marino", 1, true), findings[1].what)
end)

check("missing suppressions are reported by name", function()
    loadModules()
    local A = Omerta.Population.Internal.AnalyzeSuppressions
    assert(#A({ ScoreboardShow = true, AddDeathNotice = true,
                ChatText = true, PlayerStartVoice = true }) == 0, "all present")

    local findings = A({ ScoreboardShow = true, AddDeathNotice = true, ChatText = true })
    assert(#findings == 1 and findings[1].severity == "leak")
    assert(findings[1].what:find("voice", 1, true), findings[1].what)

    -- A totally unhooked server reports every one.
    assert(#A({}) == 4, "all four suppressions should be reported")
end)

check("a second team is a leak; one team is fine", function()
    loadModules()
    local A = Omerta.Population.Internal.AnalyzeTeams
    assert(#A({ Omerta.Population.TEAM_CITIZEN }) == 0, "single expected team is fine")
    assert(#A({}) == 0, "empty server is fine")
    local findings = A({ Omerta.Population.TEAM_CITIZEN, 7 })
    assert(#findings == 1 and findings[1].severity == "leak", "extra team must be flagged")
    assert(findings[1].what:find("client-readable", 1, true), findings[1].what)
end)

check("an un-overridden Nick() is a leak", function()
    loadModules()
    local A = Omerta.Population.Internal.AnalyzeNickOverride
    assert(#A(true) == 0, "overridden is clean")
    local findings = A(false)
    assert(#findings == 1 and findings[1].severity == "leak")
    assert(findings[1].what:find("D-015", 1, true), findings[1].what)
end)

check("a fully leaky server produces findings from every check", function()
    loadModules()
    local I = Omerta.Population.Internal
    local all = {}
    for _, list in ipairs({
        I.AnalyzeNWVars({ { player = "x", key = "Faction", value = "Marino" } }),
        I.AnalyzeSuppressions({}),
        I.AnalyzeTeams({ 2, 3 }),
        I.AnalyzeNickOverride(false),
    }) do
        for _, f in ipairs(list) do all[#all + 1] = f end
    end
    assert(countSeverity(all, "leak") == 8, "expected 8 leaks, got " .. countSeverity(all, "leak"))
end)
