-- M13 businesses. Who may do what behind a counter, whether a sale can go
-- ahead, the Q-12 rule that decides when premises can be forced, and the
-- rumour mill — all pure.

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
    "gamemodes/omertarp/gamemode/modules/hud/sh_gait.lua",
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
    "gamemodes/omertarp/gamemode/modules/phone/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sh_lines.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sh_phone.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sv_calls.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sv_phone.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/business/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/business/sh_business.lua",
    "gamemodes/omertarp/gamemode/modules/business/sh_rumours.lua",
    "gamemodes/omertarp/gamemode/modules/business/sh_venues.lua",
    "gamemodes/omertarp/gamemode/modules/business/sv_business.lua",
    "gamemodes/omertarp/gamemode/modules/business/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/business/sv_rumours.lua",
    "gamemodes/omertarp/gamemode/modules/business/sv_trade.lua",
}


local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

--------------------------------------------------------------------------------
suite("business.types")
--------------------------------------------------------------------------------

check("a type is validated before it is accepted", function()
    loadModules()
    local V = Omerta.Business.ValidateType
    assert(V("test", { name = "Test" }))
    assert(not V("Test", { name = "x" }), "bad key")
    assert(not V("test", {}), "missing name")
    assert(not V("test", { name = "x", sells = { { item = "no.such", price = 100 } } }),
        "sells an item that does not exist")
    -- A price that cannot be paid with coins in circulation is not a price.
    assert(not V("test", { name = "x", sells = { { item = "drink.whiskey", price = 103 } } }),
        "unpayable price")
    assert(not V("test", { name = "x", sells = { { item = "drink.whiskey", price = 0 } } }),
        "free")
end)

check("the catalogue of venues is coherent", function()
    loadModules()
    local types = Omerta.Business.GetTypes()
    assert(#types >= 5, "expected the GDD's list, got " .. #types)
    assert(Omerta.Business.GetType("speakeasy"), "the speakeasy is the MVP and must exist")
    for _, def in ipairs(types) do
        for _, entry in ipairs(def.sells) do
            assert(Omerta.Items.Get(entry.item), def.key .. " sells a missing item")
            assert(entry.price % Omerta.Money.SMALLEST == 0, def.key .. " has an unpayable price")
        end
    end
end)

check("container ids never collide with treasuries or with each other", function()
    loadModules()
    for id = 1, 40 do
        local till, stock = Omerta.Business.TillId(id), Omerta.Business.StockId(id)
        assert(till ~= stock, "a till and a stock room are different containers")
        assert(Omerta.Treasury.OrganizationOf(till) ~= id, "a till is not a treasury")

        local fromTill, tillKind = Omerta.Business.OfContainer(till)
        local fromStock, stockKind = Omerta.Business.OfContainer(stock)
        assert(fromTill == id and tillKind == "till", "till id does not round-trip")
        assert(fromStock == id and stockKind == "stock", "stock id does not round-trip")
    end
    assert(Omerta.Business.OfContainer(7) == nil, "an ordinary crate is not a business")
end)

--------------------------------------------------------------------------------
suite("business.ownership")
--------------------------------------------------------------------------------

-- "Who owns this" having two answers is how access control quietly stops
-- working, so it is refused at creation rather than resolved by precedence.
check("a business has exactly one owner", function()
    loadModules()
    local V = Omerta.Business.Internal.ValidateOwner
    assert(V(3, nil), "an organization may own one")
    assert(V(nil, 7), "so may a person")
    assert(not V(3, 7), "never both")
    assert(not V(nil, nil), "never neither")
end)

check("roles resolve from ownership, rank and the roster", function()
    loadModules()
    local R = Omerta.Business.Internal.RoleOf
    local ROLE = Omerta.Business.ROLE
    local familyBar = { id = 1, owner_organization_id = 4 }
    local myBar = { id = 2, owner_character_id = 7 }

    assert(R(myBar, 7, nil, nil) == ROLE.OWNER, "the owner owns it")
    assert(R(myBar, 8, nil, nil) == nil, "a stranger is nobody")
    assert(R(myBar, 8, nil, ROLE.STAFF) == ROLE.STAFF, "somebody on the books works there")

    -- Owning the place is not the same as running it: a soldier in the family
    -- that owns a bar is not automatically behind its counter.
    local soldier = { organization_id = 4, canHandleMoney = false }
    local capo = { organization_id = 4, canHandleMoney = true }
    assert(R(familyBar, 9, soldier, nil) == nil, "a junior member is not staff by default")
    assert(R(familyBar, 9, soldier, ROLE.STAFF) == ROLE.STAFF, "unless they are hired")
    assert(R(familyBar, 9, capo, nil) == ROLE.MANAGER, "somebody senior runs it")

    -- Another family's capo is nobody here.
    assert(R(familyBar, 9, { organization_id = 5, canHandleMoney = true }, nil) == nil,
        "a rival's rank means nothing behind this counter")
end)

check("what each role may do", function()
    loadModules()
    local I = Omerta.Business.Internal
    local ROLE = Omerta.Business.ROLE

    assert(I.MaySeeTill(ROLE.OWNER) and I.MaySeeTill(ROLE.MANAGER))
    assert(not I.MaySeeTill(ROLE.STAFF), "a bartender does not count the takings")
    assert(not I.MaySeeTill(nil), "and neither does a customer")

    assert(I.MayServe(ROLE.STAFF) and I.MayServe(ROLE.OWNER))
    assert(not I.MayServe(nil))

    assert(I.MayHire(ROLE.OWNER) and I.MayHire(ROLE.MANAGER))
    assert(not I.MayHire(ROLE.STAFF), "staff do not hire staff")
end)

--------------------------------------------------------------------------------
suite("business.offline_protection")
--------------------------------------------------------------------------------

-- Q-12 (D-030). If premises could be emptied at four in the morning, a season
-- would be decided by who sleeps least.
check("premises are live only while the owning side is online", function()
    loadModules()
    local F = Omerta.Business.Internal.IsForceable
    local familyBar = { owner_organization_id = 4 }
    local myBar = { owner_character_id = 7 }

    assert(not F(familyBar, {}, {}), "a family with nobody logged in cannot be robbed")
    assert(F(familyBar, { [4] = true }, {}), "one member online makes it a target")
    assert(not F(familyBar, { [5] = true }, {}), "somebody else's family does not count")

    assert(not F(myBar, {}, {}), "an offline owner is safe")
    assert(F(myBar, {}, { [7] = true }), "an online one is not")
    assert(not F(myBar, {}, { [8] = true }), "somebody else being online does not expose them")
end)

-- Online, not present: the rule rewards playing rather than standing guard.
check("being elsewhere does not protect you", function()
    loadModules()
    local F = Omerta.Business.Internal.IsForceable
    -- The sets carry no position at all, which is the point — there is nowhere
    -- in this rule for "was standing in the room" to be expressed.
    assert(F({ owner_organization_id = 2 }, { [2] = true }, {}))
end)

check("a business with no owner is not forceable, it is broken", function()
    loadModules()
    local F = Omerta.Business.Internal.IsForceable
    assert(not F({}, { [1] = true }, { [1] = true }),
        "an ownerless business should never be a valid target")
end)

--------------------------------------------------------------------------------
suite("business.trade")
--------------------------------------------------------------------------------

check("a price comes from the definition, never from the wire", function()
    loadModules()
    local P = Omerta.Business.Internal.PriceOf
    local speakeasy = Omerta.Business.GetType("speakeasy")
    local entry = P(speakeasy, "drink.whiskey")
    assert(entry and entry.price > 0, "whiskey should be on the menu")
    assert(P(speakeasy, "weapon.thompson") == nil, "a bar does not sell Thompsons")
    assert(P(speakeasy, "no.such.item") == nil)
end)

check("a sale is refused for each of the reasons it should be", function()
    loadModules()
    local C = Omerta.Business.Internal.CanSell
    local entry = { item = "drink.whiskey", price = 250 }

    assert(C(entry, 1, 4, 250, true), "a good sale goes ahead")
    assert(C(entry, 2, 4, 500, true), "and so does a round of two")

    local ok, why = C(entry, 1, 4, 250, false)
    assert(not ok and why:find("closed"), tostring(why))

    ok, why = C(entry, 1, 0, 250, true)
    assert(not ok and why:find("none left"), tostring(why))

    ok, why = C(entry, 5, 2, 5000, true)
    assert(not ok and why:find("only 2"), tostring(why))

    ok, why = C(entry, 1, 4, 245, true)
    assert(not ok and why:find("afford"), tostring(why))

    assert(not C(nil, 1, 4, 5000, true), "off the menu")
    assert(not C(entry, 0, 4, 5000, true), "zero")
    assert(not C(entry, -1, 4, 5000, true), "negative")
    assert(not C(entry, 1.5, 4, 5000, true), "half a drink")
    assert(not C(entry, 999, 9999, 9999999, true), "an absurd quantity")
end)

--------------------------------------------------------------------------------
suite("business.rumours")
--------------------------------------------------------------------------------

check("expiry is what stops the pool becoming a permanent record", function()
    loadModules()
    local L = Omerta.Rumours.Internal.IsLive
    assert(L({ expires_at = 300 }, 200))
    assert(not L({ expires_at = 100 }, 200))
    assert(not L({ expires_at = 200 }, 200), "the moment it expires, it is gone")
    assert(not L(nil, 200))
end)

check("the barman does not repeat himself, and prefers what is fresh", function()
    loadModules()
    local Pick = Omerta.Rumours.Internal.Pick
    local pool = {
        { id = 1, text = "old",    created_at = 100, expires_at = 999 },
        { id = 2, text = "newer",  created_at = 200, expires_at = 999 },
        { id = 3, text = "stale",  created_at = 300, expires_at = 150 },
    }

    -- The freshest live one.
    assert(Pick(pool, {}, 200).id == 2, "should pick the newest that is still going round")
    -- Already told: he moves on.
    assert(Pick(pool, { [2] = true }, 200).id == 1, "should not repeat itself")
    -- Everything heard or expired: nothing, which is itself information.
    assert(Pick(pool, { [1] = true, [2] = true }, 200) == nil)
    assert(Pick({}, {}, 200) == nil)
    assert(Pick(nil, nil, 200) == nil)
end)

-- A rumour you can verify is a fact, and the design already has facts.
check("a planted rumour is indistinguishable from a real one to the listener", function()
    loadModules()
    local Pick = Omerta.Rumours.Internal.Pick
    local planted = { id = 1, text = "a lie", source = Omerta.Rumours.SOURCE.PLANTED,
                      created_at = 100, expires_at = 999 }
    local real = { id = 2, text = "the truth", source = Omerta.Rumours.SOURCE.EVENT,
                   created_at = 100, expires_at = 999 }

    -- Selection never consults `source`, so the two are interchangeable here.
    local first = Pick({ planted }, {}, 200)
    local second = Pick({ real }, {}, 200)
    assert(first and second, "both kinds must be servable")
    assert(first.text and second.text, "and both arrive as nothing but text")

    -- The wire carries the text alone: no source, no author, no timestamp.
    Omerta.Module.FinishLoading()
    local schema = Omerta.Net.GetRegistry()["rumour.heard"].schema
    assert(#schema == 1 and schema[1].name == "text",
        "a rumour must arrive as text and nothing else")
end)

--------------------------------------------------------------------------------
suite("business.flow")
--------------------------------------------------------------------------------

check("migration 11 creates premises, staff and rumours", function()
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

    local seen = {}
    for _, s in ipairs(mock.log) do
        for _, table_ in ipairs({ "businesses", "business_staff", "rumours" }) do
            if s:find("CREATE TABLE IF NOT EXISTS omerta_" .. table_, 1, true) then
                seen[table_] = true
            end
        end
    end
    for _, table_ in ipairs({ "businesses", "business_staff", "rumours" }) do
        assert(seen[table_], table_ .. " DDL missing")
    end

    -- No ledger table: two sets of books that can disagree is worse than one,
    -- so collections write M11's.
    assert(Omerta.DB.Internal.GetTableDef("business_ledger") == nil,
        "a business must not keep its own books")
end)

check("the module declares its dependencies", function()
    loadModules()
    Omerta.Module.FinishLoading()
    local def = Omerta.Module.Get("business")
    assert(def, "the business module did not register")
    for _, dep in ipairs({ "organizations", "treasury", "inventory", "chat" }) do
        local found = false
        for _, d in ipairs(def.depends or {}) do
            if d == dep then found = true end
        end
        assert(found, "missing dependency on " .. dep)
    end
end)

check("a customer is never told the takings", function()
    loadModules()
    Omerta.Module.FinishLoading()
    local registry = Omerta.Net.GetRegistry()

    for _, name in ipairs({ "business.open", "business.buy", "business.action",
                            "rumour.plant" }) do
        assert(registry[name] and registry[name].realm == "client_to_server",
            name .. " should be inbound")
    end
    -- The till is a field on the state message, and the server zeroes it for
    -- anybody who may not see it — the test that it does so is in-engine, but
    -- the shape has to be right here.
    local hasTill = false
    for _, field in ipairs(registry["business.state"].schema) do
        if field.name == "till" then hasTill = true end
    end
    assert(hasTill, "the state message should carry the till")
    -- Buying names an item and a quantity. Never a price.
    for _, field in ipairs(registry["business.buy"].schema) do
        assert(field.name ~= "price" and field.name ~= "cost",
            "the client must not be able to name a price")
    end
end)

--------------------------------------------------------------------------------
suite("business.interaction")
--------------------------------------------------------------------------------

-- THE COUNTER LOST ITS E PRESS AND NOBODY NOTICED FOR A MILESTONE.
--
-- M13 built the counter on the engine's +use. M8 later registered
-- `omerta_business` as an interactable class, and that makes the client swallow
-- the E press and route it to interaction.default instead — so ENT:Use stopped
-- being reached and pressing E on a counter did nothing at all. The two changes
-- are individually correct and jointly broken, which is why this asserts the
-- pairing rather than either half.
check("the counter has a default interaction, not just an ENT:Use", function()
    loadModules()
    Omerta.Business.Internal.RegisterInteractions()

    local def = nil
    for _, entry in ipairs(Omerta.Interaction.GetOrdered()) do
        if entry.id == "business.open" then def = entry end
    end
    assert(def, "the counter offers no interaction, so a swallowed E does nothing")
    assert(def.default == true, "and it has to be the DEFAULT one, or E still dies")
    assert(def.range <= Omerta.Interaction.MAX_RANGE, "out of reach of the dot")
end)
