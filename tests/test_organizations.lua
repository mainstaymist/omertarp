-- M10 factions core. The rules that decide who may do what to whom, the
-- succession chain, the D-009 transition matrix as recruitment applies it, and
-- the officer title — all pure, all covered here rather than eyeballed on a
-- running server.

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
    "gamemodes/omertarp/gamemode/modules/hud/sh_hud.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sv_stamina.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sh_interaction.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sv_interaction.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sh_identity.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sv_identity.lua",
    "gamemodes/omertarp/gamemode/modules/chat/sh_chat.lua",
    "gamemodes/omertarp/gamemode/modules/chat/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/chat/sv_chat.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_currency.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_hunger.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_inventory.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_items.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_hunger.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_inventory.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_money.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sh_ladders.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sh_organizations.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sv_organizations.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sv_repository.lua",
}

local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

--------------------------------------------------------------------------------
suite("organizations.ladders")
--------------------------------------------------------------------------------

check("ladder definitions are validated", function()
    loadModules()
    local V = Omerta.Organizations.ValidateLadder
    assert(V("test", { { key = "a", name = "A" } }))
    assert(not V("Test", { { key = "a", name = "A" } }), "bad id")
    assert(not V("test", {}), "empty ladder")
    assert(not V("test", { { name = "A" } }), "missing key")
    assert(not V("test", { { key = "a" } }), "missing name")
    assert(not V("test", { { key = "a", name = "A" }, { key = "a", name = "B" } }),
        "duplicate key")
    -- A typo in a permission table fails open, so it is refused outright.
    assert(not V("test", { { key = "a", name = "A", grants = { "org.promotte" } } }),
        "unknown permission")
end)

check("permissions accumulate up the ladder", function()
    loadModules()
    local P = Omerta.Organizations.PERMISSIONS

    -- A Soldier can invite; a Don, who is four rungs above, still can.
    assert(Omerta.Organizations.Grants("family", 3, P.INVITE), "soldiers recruit")
    assert(Omerta.Organizations.Grants("family", 6, P.INVITE), "so does the Don")
    -- And a Prospect can do none of it.
    assert(not Omerta.Organizations.Grants("family", 1, P.INVITE))
    assert(not Omerta.Organizations.Grants("family", 1, P.ROSTER))

    -- Nothing is ever lost on the way up, on either ladder.
    for _, id in ipairs({ "family", "police" }) do
        for rank = 2, Omerta.Organizations.TopRank(id) do
            local below = Omerta.Organizations.PermissionsAt(id, rank - 1)
            local here = Omerta.Organizations.PermissionsAt(id, rank)
            for permission in pairs(below) do
                assert(here[permission], id .. " rank " .. rank .. " lost " .. permission)
            end
        end
    end
end)

check("only the top of a ladder leads", function()
    loadModules()
    local P = Omerta.Organizations.PERMISSIONS
    for _, id in ipairs({ "family", "police" }) do
        local top = Omerta.Organizations.TopRank(id)
        assert(Omerta.Organizations.Grants(id, top, P.LEAD), id .. " has no leader")
        assert(not Omerta.Organizations.Grants(id, top - 1, P.LEAD),
            id .. " has two ranks that lead")
        assert(not Omerta.Organizations.Grants(id, top - 1, P.APPOINT),
            "only the leader names a successor")
    end
end)

check("the permission bitfield round-trips", function()
    loadModules()
    local order = Omerta.Organizations.PERMISSION_ORDER
    for _, id in ipairs({ "family", "police" }) do
        for rank = 1, Omerta.Organizations.TopRank(id) do
            local bits = Omerta.Organizations.PermissionBits(id, rank)
            local held = Omerta.Organizations.PermissionsAt(id, rank)
            for i, permission in ipairs(order) do
                local set = math.floor(bits / 2 ^ (i - 1)) % 2 == 1
                assert(set == (held[permission] == true),
                    id .. " rank " .. rank .. " disagrees about " .. permission)
            end
        end
    end
end)

--------------------------------------------------------------------------------
suite("organizations.rank_rules")
--------------------------------------------------------------------------------

-- The two rules that carry the whole milestone: you must strictly outrank the
-- person you act on, and you can never create a rank at or above your own.
check("nobody promotes themselves, their equals or their betters", function()
    loadModules()
    local C = Omerta.Organizations.CanSetRank

    assert(C("family", 5, 3, 4), "an underboss may make a capo")
    assert(not C("family", 5, 3, 5), "cannot create an equal")
    assert(not C("family", 5, 3, 6), "cannot create a superior")
    assert(not C("family", 4, 5, 3), "cannot act on someone senior")
    assert(not C("family", 4, 4, 2), "cannot act on an equal")
    assert(not C("family", nil, 1, 2), "a non-member cannot act at all")
end)

check("promotion and demotion are separate permissions", function()
    loadModules()
    -- A Capo (4) has neither: they recommend, they do not decide.
    local C = Omerta.Organizations.CanSetRank
    local ok, why = C("family", 4, 2, 3)
    assert(not ok and why:find("promote"), tostring(why))
    ok, why = C("family", 4, 3, 2)
    assert(not ok and why:find("demote"), tostring(why))

    -- An Underboss (5) has both.
    assert(C("family", 5, 2, 3), "underboss promotes")
    assert(C("family", 5, 4, 2), "underboss demotes")
end)

check("a rank has to be a rank", function()
    loadModules()
    local C = Omerta.Organizations.CanSetRank
    assert(not C("family", 6, 3, 0), "rank 0")
    assert(not C("family", 6, 3, 99), "off the end of the ladder")
    assert(not C("family", 6, 3, 2.5), "half a rank")
    assert(not C("nosuchladder", 6, 3, 2), "unknown ladder")
    assert(not C("family", 6, 3, 3), "already there")
end)

--------------------------------------------------------------------------------
suite("organizations.succession")
--------------------------------------------------------------------------------

local DON, UNDERBOSS, CAPO, SOLDIER = 1, 2, 3, 4
local ROSTER = {
    { character_id = DON,       rank = 6 },
    { character_id = UNDERBOSS, rank = 5 },
    { character_id = CAPO,      rank = 4 },
    { character_id = SOLDIER,   rank = 3 },
}

local function present(...)
    local away = {}
    for _, id in ipairs({ ... }) do away[id] = true end
    return function(id) return not away[id] end
end

check("authority descends the chain and stops where it should", function()
    loadModules()
    local Compute = Omerta.Organizations.Internal.ComputeActing

    local holder, acting = Compute("family", ROSTER, DON, present())
    assert(holder == DON and not acting, "the Don holds his own")

    holder, acting = Compute("family", ROSTER, DON, present(DON))
    assert(holder == UNDERBOSS and acting, "the underboss acts")

    holder, acting = Compute("family", ROSTER, DON, present(DON, UNDERBOSS))
    assert(holder == CAPO and acting, "then the capo")

    -- A Soldier is not authorised to hold it, so nobody does.
    holder = Compute("family", ROSTER, DON, present(DON, UNDERBOSS, CAPO))
    assert(holder == nil, "a soldier must not inherit the family")

    holder = Compute("family", ROSTER, DON, function() return false end)
    assert(holder == nil, "an empty room needs no decision")
end)

check("with no seated leader the highest rank present holds it", function()
    loadModules()
    local Compute = Omerta.Organizations.Internal.ComputeActing
    -- No leader appointed yet (a fresh institution): the ladder decides.
    local holder, acting = Compute("family", ROSTER, nil, present())
    assert(holder == DON and not acting, "the top rank is the leader by default")

    holder, acting = Compute("family", ROSTER, nil, present(DON))
    assert(holder == UNDERBOSS and acting, "and it descends from there")
end)

check("an empty roster produces no authority rather than an error", function()
    loadModules()
    local Compute = Omerta.Organizations.Internal.ComputeActing
    assert(Compute("family", {}, nil, present()) == nil)
    assert(Compute("family", nil, nil, present()) == nil)
end)

--------------------------------------------------------------------------------
suite("organizations.institutions")
--------------------------------------------------------------------------------

check("definitions are validated and ordered deterministically", function()
    loadModules()
    local V = Omerta.Organizations.ValidateDefinition
    assert(V("x", { name = "X", type = "family", ladder = "family" }))
    assert(not V("X", { name = "X", type = "family", ladder = "family" }), "bad key")
    assert(not V("x", { type = "family", ladder = "family" }), "missing name")
    assert(not V("x", { name = "X", type = "gang", ladder = "family" }), "bad type")
    assert(not V("x", { name = "X", type = "family", ladder = "nope" }), "unknown ladder")

    local list = Omerta.Organizations.GetDefinitions()
    assert(#list == 5, "expected 4 families and a police department, got " .. #list)
    for i, def in ipairs(list) do
        assert(Omerta.Organizations.GetByIndex(i) == def, "index mismatch at " .. i)
        assert(Omerta.Organizations.IndexOf(def.key) == i, "IndexOf disagrees")
    end
    assert(list[#list].key == "police", "the police should sort last")
end)

check("only the configured number of families opens, and the police always do", function()
    loadModules()
    local Plan = Omerta.Organizations.Internal.PlanActive
    local defs = Omerta.Organizations.GetDefinitions()

    local plan = Plan(defs, 2)
    assert(plan.marino == "active" and plan.falcone == "active", "the first two open")
    assert(plan.ricci == "dormant" and plan.bianchi == "dormant", "the rest wait")
    assert(plan.police == "active", "a city has a police department regardless")

    plan = Plan(defs, 4)
    assert(plan.bianchi == "active", "all four when asked for")

    plan = Plan(defs, 1)
    assert(plan.marino == "active" and plan.falcone == "dormant")
end)

check("the police department is public and the families are not", function()
    loadModules()
    assert(Omerta.Organizations.GetDefinition("police").public == true)
    for _, key in ipairs({ "marino", "falcone", "ricci", "bianchi" }) do
        assert(Omerta.Organizations.GetDefinition(key).public == false,
            key .. " must not announce itself")
    end
end)

--------------------------------------------------------------------------------
suite("organizations.transitions")
--------------------------------------------------------------------------------

-- D-009's matrix, applied where recruitment actually happens.
check("recruitment obeys the season's track commitments", function()
    loadModules()
    local May = Omerta.Organizations.Internal.MayJoin
    local family = Omerta.Organizations.GetDefinition("marino")
    local police = Omerta.Organizations.GetDefinition("police")

    assert(May(family, "independent"), "an independent may be recruited")
    assert(May(family, "criminal"), "so may an unaffiliated criminal")
    assert(not May(family, "police"), "an officer may not join a family this season")

    assert(May(police, "police"), "the force recruits from the force")
    assert(not May(police, "independent"), "and never mid-season from outside")
    assert(not May(police, "criminal"), "least of all from a family")
end)

--------------------------------------------------------------------------------
suite("organizations.uniform")
--------------------------------------------------------------------------------

-- §4c: a uniform is a public announcement; a family is the opposite.
check("a title reads off a uniform, and composes with a known name", function()
    loadModules()
    local R = Omerta.Identity.ResolveDisplayName
    local officer = { id = 2, first_name = "Frank", last_name = "Doyle" }
    local stranger = { id = 3 }

    -- With no provider registered nothing changes: this is M5's old behaviour.
    assert(R(stranger, officer, nil) == "Unknown")
    assert(R(stranger, officer, "Frank Doyle") == "Frank Doyle")

    Omerta.Identity.RegisterTitleProvider(function(c)
        return c.uniformed and "Sergeant" or nil
    end)
    officer.uniformed = true

    -- A stranger reads the rank, not the man.
    assert(R(stranger, officer, nil) == "Sergeant", R(stranger, officer, nil))
    -- Someone who knows him reads both.
    assert(R(stranger, officer, "Frank Doyle") == "Sergeant Frank Doyle",
        R(stranger, officer, "Frank Doyle"))
    -- He still knows himself by name.
    assert(R(officer, officer, nil) == "Frank Doyle")
end)

check("a mask hides a face, not a uniform", function()
    loadModules()
    local R = Omerta.Identity.ResolveDisplayName
    local officer = { id = 2, first_name = "Frank", last_name = "Doyle", uniformed = true }

    Omerta.Identity.RegisterTitleProvider(function(c)
        return c.uniformed and "Sergeant" or nil
    end)
    Omerta.Identity.RegisterConcealmentProvider(function(c) return c.masked == true end)
    officer.masked = true

    -- Concealment defeats recognition (D-014) but a uniform is still a uniform,
    -- and the identification is false either way.
    local name, known = R({ id = 3 }, officer, "Frank Doyle")
    assert(name == "Sergeant", name)
    assert(known == false, "a masked officer is not identified")
end)

check("the uniform is an ordinary item, so it can be taken off", function()
    loadModules()
    local def = Omerta.Items.Get(Omerta.Organizations.UNIFORM_ITEM)
    assert(def, "the uniform was never registered as an item")
    assert(def.slot == "outerwear", "it has to be worn to count")
    assert(def.stackable == false, "one uniform is one uniform")
end)

--------------------------------------------------------------------------------
suite("organizations.flow")
--------------------------------------------------------------------------------

check("migration 8 creates the institutions and their rosters", function()
    loadModules()
    Omerta.Module.FinishLoading()

    local mock = { dialect = "sqlite", heuristic = true, log = {}, nextInsertId = 1 }
    function mock.Connect(_, cb) cb(nil) end
    function mock.RunQuery(sqlStr, _, cb)
        mock.log[#mock.log + 1] = sqlStr
        if sqlStr:find("SELECT version") then cb({}, nil) return end
        local id = mock.nextInsertId
        mock.nextInsertId = mock.nextInsertId + 1
        cb({}, nil, id)
    end
    function mock.RunTransaction(_, cb) cb(true, nil) end
    Omerta.DB.Internal.Drivers = Omerta.DB.Internal.Drivers or {}
    Omerta.DB.Internal.Drivers.sqlite = mock
    Omerta.Module.EnableAll()

    local sawOrgs, sawMembers, sawUnique = false, false, false
    for _, s in ipairs(mock.log) do
        if s:find("CREATE TABLE IF NOT EXISTS omerta_organizations", 1, true) then
            sawOrgs = true
            -- One row per institution per season, enforced by the database
            -- rather than by remembering to check first.
            if s:find("UNIQUE (season_id, org_key)", 1, true) then sawUnique = true end
        end
        if s:find("CREATE TABLE IF NOT EXISTS omerta_organization_members", 1, true) then
            sawMembers = true
        end
    end
    assert(sawOrgs, "organizations DDL missing")
    assert(sawMembers, "organization_members DDL missing")
    assert(sawUnique, "the season/key uniqueness is missing")
end)

-- MySQL 8 reserves KEY and RANK, so a column called either would make the
-- migration fail on the backend of record while passing every SQLite test.
-- The rest of the schema is checked too, because the next person to add a
-- column will not be thinking about MySQL's keyword list either.
check("no column name collides with a MySQL reserved word", function()
    loadModules()
    Omerta.Module.FinishLoading()

    local RESERVED = {
        key = true, rank = true, order = true, group = true, ["and"] = true,
        ["or"] = true, ["select"] = true, ["from"] = true, ["where"] = true,
        table = true, index = true, ["primary"] = true, ["default"] = true,
        ["int"] = true, ["read"] = true, ["range"] = true, ["rows"] = true,
        ["system"] = true, ["lead"] = true, ["first_value"] = true, ["cume_dist"] = true,
    }

    local offenders = {}
    for _, name in ipairs({ "accounts", "audit_log", "seasons", "characters",
                            "identity_knowledge", "chat_log", "items",
                            "character_needs", "organizations",
                            "organization_members" }) do
        local def = Omerta.DB.Internal.GetTableDef(name)
        if def then
            for _, col in ipairs(def.columns) do
                if RESERVED[col.name:lower()] then
                    offenders[#offenders + 1] = name .. "." .. col.name
                end
            end
        end
    end
    assert(#offenders == 0, "reserved column names: " .. table.concat(offenders, ", "))
end)

check("the module declares its dependencies and its interaction", function()
    loadModules()
    Omerta.Module.FinishLoading()

    local def = Omerta.Module.Get("organizations")
    assert(def, "the organizations module did not register")
    for _, dep in ipairs({ "characters", "identity", "interaction", "chat", "inventory" }) do
        local found = false
        for _, d in ipairs(def.depends or {}) do
            if d == dep then found = true end
        end
        assert(found, "missing dependency on " .. dep)
    end
    assert(Omerta.Interaction.Get("organizations.offer"), "Offer Membership was never registered")
end)

-- The single most common way a Garry's Mod RP gamemode leaks its social graph.
check("membership never travels anywhere a bystander can read it", function()
    loadModules()
    Omerta.Module.FinishLoading()

    local registry = Omerta.Net.GetRegistry()
    assert(registry["org.self"], "org.self is missing")
    assert(registry["org.self"].realm == "server_to_client")
    -- Your own membership carries no text at all: a family is a number and a
    -- rank, and even that goes only to its owner.
    for _, field in ipairs(registry["org.self"].schema) do
        assert(field.type ~= "string", "org.self must not carry text")
    end

    -- The roster does carry names, and that is the point of the permission
    -- gate; it must be outbound-only so it can never be asked for on
    -- somebody else's behalf.
    assert(registry["org.roster_entry"].realm == "server_to_client")
    assert(registry["org.roster_request"].realm == "client_to_server")
    -- Nothing in the request names an organization: you get your own or
    -- nothing, so it cannot be used to enumerate the other families.
    assert(#registry["org.roster_request"].schema == 0,
        "a roster request must not name which roster")
end)
