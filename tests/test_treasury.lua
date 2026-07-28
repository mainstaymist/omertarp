-- M11 treasury and procurement. Who may spend how much, who has to agree,
-- what a ledger line says, and the guardrail that keeps money from buying
-- statistics — all pure, all covered here.

local MODULE_FILES = {
    "gamemodes/omertarp/gamemode/modules/database/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/database/sh_database.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_schema.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_sqlbuild.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_database.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sh_accounts.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sv_accounts.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sh_seasons.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sv_seasons.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sh_characters.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sv_characters.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sh_hud.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sv_stamina.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sh_interaction.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sv_interaction.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sh_identity.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sv_identity.lua",
    "gamemodes/omertarp/gamemode/modules/chat/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/chat/sh_chat.lua",
    "gamemodes/omertarp/gamemode/modules/chat/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/chat/sv_chat.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_currency.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_hunger.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_inventory.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_items.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_hunger.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_inventory.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_money.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sh_ladders.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sh_organizations.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sv_organizations.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sh_ledger.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sh_procurement.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sh_supplies.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sv_procurement.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sv_treasury.lua",
}

local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

--------------------------------------------------------------------------------
suite("treasury.limits")
--------------------------------------------------------------------------------

check("a rank that cannot spend has a limit of nothing", function()
    loadModules()
    local L = Omerta.Treasury.LimitFor
    -- Prospect through Soldier hold no spending permission at all.
    for rank = 1, 3 do
        assert(L("family", rank) == 0, "family rank " .. rank .. " should not spend")
    end
    for rank = 1, 5 do
        assert(L("police", rank) == 0, "police rank " .. rank .. " should not spend")
    end
end)

check("a ceiling is declared at its own rung and not inherited upward", function()
    loadModules()
    local L = Omerta.Treasury.LimitFor
    -- An Underboss has a ceiling; a Don declares none, which means no ceiling —
    -- not the Underboss's inherited by accident.
    assert(L("family", 5) == 25000, tostring(L("family", 5)))
    assert(L("family", 6) == nil, "a Don must have no ceiling")
    assert(L("police", 6) == 25000, tostring(L("police", 6)))
    assert(L("police", 7) == nil, "a Commissioner must have no ceiling")
end)

check("the multiplier scales a ceiling without touching the ladder", function()
    loadModules()
    local L = Omerta.Treasury.LimitFor
    assert(L("family", 5, 2) == 50000, tostring(L("family", 5, 2)))
    assert(L("family", 5, 0.5) == 12500)
    assert(L("family", 6, 10) == nil, "unlimited stays unlimited")
    assert(L("family", 3, 10) == 0, "nothing stays nothing")
end)

--------------------------------------------------------------------------------
suite("treasury.authorisation")
--------------------------------------------------------------------------------

check("spending alone stops at the ceiling", function()
    loadModules()
    local C = Omerta.Treasury.CanSpend
    assert(C("family", 5, 25000, nil), "exactly at the ceiling is allowed")
    assert(C("family", 5, 100, nil), "well under is allowed")

    local ok, why = C("family", 5, 25005, nil)
    assert(not ok, "a nickel over the ceiling was allowed")
    assert(why and why:find("approve"), tostring(why))

    assert(C("family", 6, 999999999, nil), "a Don has no ceiling")
end)

check("an approver lifts the ceiling only if they could cover it", function()
    loadModules()
    local C = Omerta.Treasury.CanSpend
    assert(C("family", 5, 40000, 6), "a Don can approve anything")
    assert(not C("family", 5, 40000, 3), "a Soldier cannot approve")
    assert(not C("family", 5, 40000, 4), "nor a Capo, who cannot spend")
    -- An Underboss cannot approve past their own ceiling for another
    -- Underboss: two people who each cannot afford it still cannot afford it.
    assert(not C("family", 5, 40000, 5), "two underbosses do not make a Don")
end)

check("someone who cannot spend cannot be rescued by approval", function()
    loadModules()
    local C = Omerta.Treasury.CanSpend
    local ok, why = C("family", 3, 100, 6)
    assert(not ok, "a Soldier spent with a Don's blessing")
    assert(why and why:find("cannot take money"), tostring(why))
end)

check("amounts have to be amounts", function()
    loadModules()
    local C = Omerta.Treasury.CanSpend
    assert(not C("family", 6, 0, nil), "zero")
    assert(not C("family", 6, -500, nil), "negative")
    assert(not C("family", 6, 12.5, nil), "fractional cents")
end)

--------------------------------------------------------------------------------
suite("treasury.ledger")
--------------------------------------------------------------------------------

check("a line carries everything Tech §10 requires", function()
    loadModules()
    local line = Omerta.Treasury.Internal.BuildLine({
        organizationId = 3, seasonId = 1, at = 1000, characterId = 7, approverId = 9,
        delta = -25000, balanceBefore = 100000, counted = 74000,
        reason = "withdrawal", category = "weapons", note = "Thompson x1",
    })
    assert(line.character_id == 7, "who moved it")
    assert(line.approver_character_id == 9, "who allowed it")
    assert(line.delta == -25000, "how much")
    assert(line.balance_after == 75000, "resulting balance, got " .. line.balance_after)
    assert(line.counted_after == 74000, "and what was actually there")
    assert(line.at == 1000 and line.organization_id == 3)
end)

check("an unapproved line records no approver rather than a fake one", function()
    loadModules()
    local line = Omerta.Treasury.Internal.BuildLine({
        organizationId = 1, seasonId = 1, at = 1, characterId = 2,
        delta = 500, balanceBefore = 0, reason = "deposit",
    })
    assert(line.approver_character_id == Omerta.DB.NULL, "no approver means NULL, not the actor")
    assert(line.counted_after == Omerta.DB.NULL)
    assert(line.balance_after == 500)
end)

-- The point of §4a: the books and the safe are separate, and their
-- disagreement is a mechanic rather than a bug.
check("a discrepancy is measured and named from both directions", function()
    loadModules()
    local D = Omerta.Treasury.Discrepancy
    local N = Omerta.Treasury.DescribeDiscrepancy

    assert(D(100000, 100000) == 0)
    assert(N(100000, 100000) == "the books balance")

    -- Somebody took money without writing it down.
    assert(D(90000, 100000) == -10000)
    assert(N(90000, 100000):find("missing"), N(90000, 100000))
    assert(N(90000, 100000):find("%$100%.00"), N(90000, 100000))

    -- Or put money in without writing it down, which is its own kind of story.
    assert(D(110000, 100000) == 10000)
    assert(N(110000, 100000):find("more than the books"), N(110000, 100000))
end)

--------------------------------------------------------------------------------
suite("procurement.registry")
--------------------------------------------------------------------------------

check("entries are validated", function()
    loadModules()
    local V = Omerta.Procurement.Validate
    assert(V("test.ok", { name = "Thing", category = "weapons", price = 100,
        item = "weapon.revolver" }))
    assert(not V("Test", { name = "x", category = "weapons", price = 100, item = "weapon.revolver" }),
        "bad id")
    assert(not V("test.a", { category = "weapons", price = 100, item = "weapon.revolver" }),
        "missing name")
    assert(not V("test.b", { name = "x", category = "nonsense", price = 100,
        item = "weapon.revolver" }), "unknown category")
    assert(not V("test.c", { name = "x", category = "weapons", price = 0,
        item = "weapon.revolver" }), "free")
    assert(not V("test.d", { name = "x", category = "weapons", price = 100,
        item = "no.such.item" }), "unknown item")
    -- Delivers nothing and does nothing.
    assert(not V("test.e", { name = "x", category = "weapons", price = 100 }), "empty entry")
end)

check("a price has to be payable with coins that exist", function()
    loadModules()
    local ok, why = Omerta.Procurement.Validate("test.odd", {
        name = "x", category = "weapons", price = 103, item = "weapon.revolver",
    })
    assert(not ok, "103 cents cannot be paid")
    assert(why and why:find("coins in circulation"), tostring(why))
end)

-- Tech §10's guardrail, written as a refusal rather than a comment.
check("money buys objects, never statistics", function()
    loadModules()
    for _, field in ipairs({ "health", "armor", "armour", "speed", "damage",
                             "runSpeed", "maxHealth" }) do
        local def = { name = "Advantage", category = "medical", price = 100,
                      item = "food.bread" }
        def[field] = 25
        local ok, why = Omerta.Procurement.Validate("test." .. field:lower(), def)
        assert(not ok, "an entry setting '" .. field .. "' was accepted")
        assert(why and why:find("never statistics"), tostring(why))
    end
end)

check("the base catalogue is coherent", function()
    loadModules()
    local list = Omerta.Procurement.GetOrdered()
    assert(#list >= 10, "expected a catalogue, got " .. #list)
    for i, entry in ipairs(list) do
        assert(Omerta.Procurement.GetByIndex(i) == entry, "index mismatch at " .. i)
        assert(entry.price % Omerta.Money.SMALLEST == 0, entry.id .. " is unpayable")
        assert(Omerta.Procurement.CATEGORIES[entry.category], entry.id .. " has a bad category")
        if entry.item then
            assert(Omerta.Items.Get(entry.item), entry.id .. " delivers a missing item")
        end
    end
end)

--------------------------------------------------------------------------------
suite("procurement.availability")
--------------------------------------------------------------------------------

check("the catalogue shows only what this buyer may order", function()
    loadModules()
    local A = Omerta.Procurement.Available

    -- A Soldier holds no spending permission, so orders nothing.
    assert(#A("family", "family", 3) == 0, "a soldier should see nothing to order")
    -- An Underboss holds it, so sees the family catalogue.
    local underboss = A("family", "family", 5)
    assert(#underboss > 0, "an underboss should see the catalogue")

    -- A family never sees police-only stock, and the department does.
    for _, entry in ipairs(underboss) do
        assert(entry.orgType ~= "police", "a family was offered " .. entry.id)
    end
    local sawUniform = false
    for _, entry in ipairs(A("police", "police", 6)) do
        if entry.id == "supply.police_uniform" then sawUniform = true end
    end
    assert(sawUniform, "the department should be able to buy its own uniforms")
end)

check("a Thompson costs more than an underboss may spend alone", function()
    loadModules()
    -- Deliberate: arming a crew is an argument between two people, not a click.
    local thompson = Omerta.Procurement.Get("supply.thompson")
    local limit = Omerta.Treasury.LimitFor("family", 5)
    assert(thompson.price > limit,
        "a Thompson at " .. Omerta.Money.Format(thompson.price)
        .. " should exceed an underboss's " .. Omerta.Money.Format(limit))
    assert(Omerta.Treasury.CanSpend("family", 5, thompson.price, 6),
        "and a Don should be able to approve one")
end)

--------------------------------------------------------------------------------
suite("treasury.containers")
--------------------------------------------------------------------------------

check("treasury container ids never collide with hand-allocated ones", function()
    loadModules()
    local id = Omerta.Treasury.ContainerId(1)
    assert(id > Omerta.Treasury.CONTAINER_BASE, "should be namespaced away")
    assert(Omerta.Treasury.OrganizationOf(id) == 1, "and reversible")
    assert(Omerta.Treasury.OrganizationOf(7) == nil, "an ordinary crate is not a treasury")
    for org = 1, 50 do
        assert(Omerta.Treasury.OrganizationOf(Omerta.Treasury.ContainerId(org)) == org)
    end
end)

--------------------------------------------------------------------------------
suite("treasury.flow")
--------------------------------------------------------------------------------

check("migration 9 creates the ledger and the safes", function()
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

    local sawLedger, sawSafes = false, false
    for _, s in ipairs(mock.log) do
        if s:find("CREATE TABLE IF NOT EXISTS omerta_treasury_ledger", 1, true) then
            sawLedger = true
        end
        if s:find("CREATE TABLE IF NOT EXISTS omerta_treasury_safes", 1, true) then
            sawSafes = true
        end
    end
    assert(sawLedger, "treasury_ledger DDL missing")
    assert(sawSafes, "treasury_safes DDL missing")
end)

check("the module declares its dependencies", function()
    loadModules()
    Omerta.Module.FinishLoading()
    local def = Omerta.Module.Get("treasury")
    assert(def, "the treasury module did not register")
    for _, dep in ipairs({ "organizations", "inventory", "chat" }) do
        local found = false
        for _, d in ipairs(def.depends or {}) do
            if d == dep then found = true end
        end
        assert(found, "missing dependency on " .. dep)
    end
end)

-- A Soldier is never told what the family is worth.
check("the wire tells a client only what its rank has earned", function()
    loadModules()
    Omerta.Module.FinishLoading()
    local registry = Omerta.Net.GetRegistry()

    for _, name in ipairs({ "treasury.open", "treasury.action", "procure.order" }) do
        assert(registry[name] and registry[name].realm == "client_to_server",
            name .. " should be inbound")
    end
    for _, name in ipairs({ "treasury.state", "procure.entry", "treasury.line" }) do
        assert(registry[name] and registry[name].realm == "server_to_client",
            name .. " should be outbound")
    end

    -- A request to open the safe names nothing: you get your own or nothing,
    -- so it cannot be used to count another family's money.
    assert(#registry["treasury.open"].schema == 0,
        "opening the safe must not name which safe")
    -- The state message carries no text at all.
    for _, field in ipairs(registry["treasury.state"].schema) do
        assert(field.type ~= "string", "treasury.state must not carry text")
    end
end)

-- Money that enters a safe without being written down and is then spent drives
-- the books negative. That is the discrepancy D-024 exists to show, so the wire
-- has to be able to carry it — an unsigned field made a legitimate state
-- unsendable and took the whole message with it.
check("the wire can carry books that have gone negative", function()
    loadModules()
    Omerta.Module.FinishLoading()
    local registry = Omerta.Net.GetRegistry()

    local function fieldOf(message, name)
        for _, field in ipairs(registry[message].schema) do
            if field.name == name then return field end
        end
    end

    assert(fieldOf("treasury.state", "ledger").type == "int",
        "the ledger balance must be signed")
    assert(fieldOf("treasury.line", "balance").type == "int",
        "a line's resulting balance must be signed")
    assert(fieldOf("treasury.line", "delta").type == "int",
        "a movement must be signed")
    -- What is physically in the safe never goes below zero, so it stays
    -- unsigned and keeps the extra bit.
    assert(fieldOf("treasury.state", "counted").type == "uint")

    assert(Omerta.Net.ValidateValue(fieldOf("treasury.state", "ledger"), -35200),
        "the exact value that crashed a live server")
end)

check("container access refuses by default when a provider errors", function()
    loadModules()
    -- A provider that throws must lock the container rather than accidentally
    -- opening a safe because of a typo somewhere else.
    Omerta.Inventory.RegisterContainerAccess("broken", function() error("boom") end)
    local ok, why = Omerta.Inventory.MayOpen(nil, 12345)
    assert(not ok, "a broken access provider granted access")
    assert(why and why:find("locked"), tostring(why))
end)
