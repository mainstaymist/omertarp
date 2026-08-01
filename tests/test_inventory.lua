-- M9 inventory, items, currency and hunger. The pure core of the milestone:
-- bulk accounting, the stacking planner, the money composer and the
-- change-making search, hunger's maths, and the transactional plans that keep
-- an item from ever existing in two places at once.

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
}

local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

local function countKeys(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

--------------------------------------------------------------------------------
suite("money.format")
--------------------------------------------------------------------------------

check("amounts read like money, including the awkward ones", function()
    loadModules()
    local F = Omerta.Money.Format
    assert(F(1000) == "$10.00", F(1000))
    assert(F(5) == "$0.05", F(5))
    assert(F(0) == "$0.00", F(0))
    assert(F(123456) == "$1234.56", F(123456))
    assert(F(-250) == "-$2.50", F(-250))
end)

--------------------------------------------------------------------------------
suite("money.compose")
--------------------------------------------------------------------------------

check("an amount is minted as the fewest notes and coins", function()
    loadModules()
    local wallet = Omerta.Money.Compose(275)
    assert(wallet[100] == 2 and wallet[25] == 3, "expected two dollars and three quarters")
    assert(countKeys(wallet) == 2, "nothing else should be minted")
    assert(Omerta.Money.Total(wallet) == 275)

    -- The greedy claim is only safe because the set is canonical: 40 cents
    -- must come back as a quarter, a dime and a nickel, not four dimes.
    local forty = Omerta.Money.Compose(40)
    assert(forty[25] == 1 and forty[10] == 1 and forty[5] == 1, "40c should be 25+10+5")

    assert(countKeys(Omerta.Money.Compose(0)) == 0, "nothing is nothing")
end)

check("amounts smaller than the smallest coin cannot be minted", function()
    loadModules()
    local wallet, why = Omerta.Money.Compose(3)
    assert(wallet == nil, "3 cents cannot exist")
    assert(why and why:find("multiple"), tostring(why))
    assert(Omerta.Money.Compose(-5) == nil, "negative amounts are refused")
    assert(Omerta.Money.Compose(10.5) == nil, "fractional cents are refused")
end)

check("rounding is explicit, never silent", function()
    loadModules()
    local R = Omerta.Money.Round
    assert(R(103) == 105, R(103))
    assert(R(102) == 100, R(102))
    assert(R(100) == 100)
    assert(R(0) == 0)
end)

--------------------------------------------------------------------------------
suite("money.payment")
--------------------------------------------------------------------------------

-- The case greedy alone gets wrong, and the reason the exact search exists.
check("exact change is found where greedy would overshoot", function()
    loadModules()
    local wallet = { [25] = 1, [10] = 3 }

    local greedy, paid = Omerta.Money.Internal.GreedyPayment(wallet, 30)
    assert(paid == 35, "greedy alone overshoots to 35, got " .. paid)

    local exact = Omerta.Money.Internal.ExactPayment(wallet, 30)
    assert(exact and exact[10] == 3 and exact[25] == nil, "three dimes is exact")

    local selection, change = Omerta.Money.SelectPayment(wallet, 30)
    assert(change == 0, "the exact set should be preferred")
    assert(selection[10] == 3, "three dimes")
end)

check("when exact is impossible you overpay and take change", function()
    loadModules()
    -- Two five-dollar notes, a $7.25 bill: there is no exact set.
    local selection, change, why = Omerta.Money.SelectPayment({ [500] = 2 }, 725)
    assert(selection, tostring(why))
    assert(selection[500] == 2, "both notes go over the counter")
    assert(change == 275, "expected $2.75 back, got " .. tostring(change))
end)

check("paying more than you have is refused, not approximated", function()
    loadModules()
    local selection, _, why = Omerta.Money.SelectPayment({ [25] = 2 }, 500)
    assert(selection == nil, "should refuse")
    assert(why and why:find("not enough"), tostring(why))
end)

check("the whole denomination set round-trips through payment", function()
    loadModules()
    -- One of everything, then pay every amount from 5c to $5 in 5c steps: the
    -- net cost must be exact every single time, which is the only promise the
    -- payment code actually makes.
    local wallet = {}
    for _, denom in ipairs(Omerta.Money.DENOMINATIONS) do wallet[denom.cents] = 4 end
    local held = Omerta.Money.Total(wallet)

    for target = 5, 500, 5 do
        local selection, change, why = Omerta.Money.SelectPayment(wallet, target)
        assert(selection, target .. ": " .. tostring(why))
        local handed = Omerta.Money.Total(selection)
        assert(handed - change == target,
            string.format("%d: handed %d, change %d", target, handed, change))
        assert(handed <= held, target .. ": handed over more than was held")
        -- Never hand over notes that are not there.
        for cents, count in pairs(selection) do
            assert(count <= wallet[cents], target .. ": spent " .. count .. " x " .. cents)
        end
    end
end)

check("zero costs nothing and moves nothing", function()
    loadModules()
    local selection, change = Omerta.Money.SelectPayment({ [100] = 1 }, 0)
    assert(countKeys(selection) == 0 and change == 0)
end)

--------------------------------------------------------------------------------
suite("items.registry")
--------------------------------------------------------------------------------

check("definitions are validated before they are accepted", function()
    loadModules()
    local V = Omerta.Items.Validate
    assert(V("test.thing", { name = "Thing", bulk = 1, category = "misc" }))
    assert(not V("Test Thing", { name = "x", bulk = 1, category = "misc" }), "bad id")
    assert(not V("test.a", { bulk = 1, category = "misc" }), "missing name")
    assert(not V("test.b", { name = "x", bulk = -1, category = "misc" }), "negative bulk")
    assert(not V("test.c", { name = "x", bulk = 1 }), "missing category")
    assert(not V("test.d", { name = "x", bulk = 1, category = "misc", slot = "nope" }),
        "unknown slot")
    assert(not V("test.e", { name = "x", bulk = 1, category = "misc",
        stackable = false, maxStack = 5 }), "unstackable cannot stack")
end)

check("registration fills in the defaults it promises", function()
    loadModules()
    local def = Omerta.Items.Register("test.crate", {
        name = "Crate", bulk = 5, category = "misc",
    })
    assert(def.stackable == false, "not stackable by default")
    assert(def.maxStack == 1, "unstackable things hold one")
    assert(def.concealable == true, "concealable unless it says otherwise")

    local stack = Omerta.Items.Register("test.nails", {
        name = "Nails", bulk = 0.1, category = "misc", stackable = true,
    })
    assert(stack.maxStack == 100, "stackables default to 100")

    assert(not pcall(Omerta.Items.Register, "test.crate", { name = "x", bulk = 1, category = "misc" }),
        "registering twice must fail")
end)

check("wire indices round-trip on a deterministic order", function()
    loadModules()
    local list = Omerta.Items.GetOrdered()
    assert(#list > 10, "the base catalogue should not be empty")
    for i, def in ipairs(list) do
        assert(Omerta.Items.GetByIndex(i) == def, "reverse lookup failed at " .. i)
        assert(Omerta.Items.IndexOf(def.id) == i, "IndexOf disagrees for " .. def.id)
    end
    -- Sorted by id, so both realms compute the same list from the same set.
    for i = 2, #list do
        assert(list[i - 1].id < list[i].id, "ordering is not by id at " .. i)
    end
end)

check("every denomination has an item and every money item a denomination", function()
    loadModules()
    for _, denom in ipairs(Omerta.Money.DENOMINATIONS) do
        local def = Omerta.Items.Get(denom.item)
        assert(def, "no item for " .. denom.cents)
        assert(def.stackable, denom.item .. " must stack")
        assert(Omerta.Money.DenominationOfItem(denom.item).cents == denom.cents,
            "reverse lookup failed for " .. denom.item)
    end
end)

--------------------------------------------------------------------------------
suite("inventory.bulk")
--------------------------------------------------------------------------------

check("bulk is integer arithmetic, so fractions do not drift", function()
    loadModules()
    local U = Omerta.Inventory.UnitBulk
    assert(U(Omerta.Items.Get("tool.crowbar")) == 300)
    assert(U(Omerta.Items.Get("money.cent25")) == 2, "a quarter is 0.02")
    assert(U(nil) == 0, "an unknown item weighs nothing")

    -- A hundred quarters is exactly 2 bulk, not 1.9999999999998.
    assert(Omerta.Inventory.StackBulk(Omerta.Items.Get("money.cent25"), 100) == 200)
end)

check("a sum ignores items the gamemode no longer knows about", function()
    loadModules()
    local rows = {
        { def_id = "misc.cigarettes", quantity = 3 },   -- 0.2 each
        { def_id = "gone.forever",    quantity = 99 },
    }
    assert(Omerta.Inventory.SumBulk(rows) == 60, Omerta.Inventory.SumBulk(rows))
    assert(Omerta.Inventory.SumBulk({}) == 0)
    assert(Omerta.Inventory.SumBulk(nil) == 0)
end)

check("the capacity boundary is inclusive", function()
    loadModules()
    local F = Omerta.Inventory.Fits
    assert(F(1900, 100, 2000), "exactly full still fits")
    assert(not F(1900, 101, 2000), "one over does not")
    assert(F(0, 0, 0), "nothing always fits")
end)

check("bulk displays as a short decimal", function()
    loadModules()
    local F = Omerta.Inventory.FormatBulk
    assert(F(2200) == "22", F(2200))
    assert(F(2250) == "22.5", F(2250))
    assert(F(2205) == "22", F(2205))
    assert(F(0) == "0")
end)

--------------------------------------------------------------------------------
suite("inventory.stacking")
--------------------------------------------------------------------------------

check("partial stacks are topped up before new ones are opened", function()
    loadModules()
    local def = Omerta.Items.Get("misc.cigarettes") -- maxStack 10
    local rows = { { id = 7, def_id = "misc.cigarettes", quantity = 8 } }

    local plan = Omerta.Inventory.Internal.PlanAdd(rows, def, 5)
    assert(#plan.updates == 1, "the existing stack should be topped up")
    assert(plan.updates[1].id == 7 and plan.updates[1].quantity == 10,
        "topped to the maximum")
    assert(plan.updates[1].expected == 8, "guarded on what we counted")
    assert(#plan.insertions == 1 and plan.insertions[1] == 3, "the remainder opens a stack")
end)

check("a large add splits into whole stacks", function()
    loadModules()
    local def = Omerta.Items.Get("money.cent25") -- maxStack 200
    local plan = Omerta.Inventory.Internal.PlanAdd({}, def, 450)
    assert(#plan.updates == 0)
    assert(#plan.insertions == 3, "expected 3 stacks, got " .. #plan.insertions)
    assert(plan.insertions[1] == 200 and plan.insertions[2] == 200 and plan.insertions[3] == 50)
end)

check("unstackable items get a row each, and never merge", function()
    loadModules()
    local def = Omerta.Items.Get("tool.crowbar")
    local rows = { { id = 1, def_id = "tool.crowbar", quantity = 1 } }
    local plan = Omerta.Inventory.Internal.PlanAdd(rows, def, 3)
    assert(#plan.updates == 0, "nothing merges")
    assert(#plan.insertions == 3, "three separate crowbars")
end)

-- An item carrying metadata is not interchangeable with one that does not:
-- merging a marked bill into a plain stack would destroy the mark, which is
-- exactly what M15 will depend on.
check("marked and equipped items never merge into a stack", function()
    loadModules()
    local def = Omerta.Items.Get("misc.cigarettes")
    local rows = {
        { id = 1, def_id = "misc.cigarettes", quantity = 2, metadata = "{\"marked\":true}" },
        { id = 2, def_id = "misc.cigarettes", quantity = 2, equipped_slot = "primary" },
    }
    local plan = Omerta.Inventory.Internal.PlanAdd(rows, def, 1)
    assert(#plan.updates == 0, "neither row is a merge target")
    assert(#plan.insertions == 1)
end)

check("adding nothing plans nothing", function()
    loadModules()
    local def = Omerta.Items.Get("misc.cigarettes")
    local plan = Omerta.Inventory.Internal.PlanAdd({}, def, 0)
    assert(#plan.updates == 0 and #plan.insertions == 0)
end)

--------------------------------------------------------------------------------
suite("money.plans")
--------------------------------------------------------------------------------

check("a selection is spent out of real stacks", function()
    loadModules()
    local rows = {
        { id = 1, def_id = "money.dollar5",  quantity = 2 },
        { id = 2, def_id = "money.cent25",   quantity = 4 },
        { id = 3, def_id = "misc.newspaper", quantity = 1 },
    }
    local updates = Omerta.Money.Internal.PlanSpend(rows, { [500] = 2, [25] = 3 })
    assert(#updates == 2, "two stacks touched, got " .. #updates)
    assert(updates[1].id == 1 and updates[1].quantity == 0, "the notes go entirely")
    assert(updates[1].expected == 2, "guarded on what we counted")
    assert(updates[2].id == 2 and updates[2].quantity == 1, "one quarter left")
end)

check("a spend that the stacks cannot cover is refused", function()
    loadModules()
    local rows = { { id = 1, def_id = "money.dollar5", quantity = 1 } }
    local updates, why = Omerta.Money.Internal.PlanSpend(rows, { [500] = 2 })
    assert(updates == nil, "should refuse")
    assert(why and why:find("short of"), tostring(why))
end)

check("the post-spend view is what change is planned against", function()
    loadModules()
    local A = Omerta.Money.Internal.ApplyUpdates
    local rows = {
        { id = 1, def_id = "money.dollar5", quantity = 2 },
        { id = 2, def_id = "money.cent25",  quantity = 4 },
    }
    local after = A(rows, { { id = 1, quantity = 0 }, { id = 2, quantity = 1 } })
    assert(#after == 1, "the emptied stack is gone")
    assert(after[1].id == 2 and after[1].quantity == 1)
    -- The originals must not be mutated: the caller still needs them to build
    -- the guarded UPDATEs.
    assert(rows[2].quantity == 4, "the source rows were modified in place")
end)

check("credit merges into partial stacks and mints the rest", function()
    loadModules()
    local rows = { { id = 9, def_id = "money.cent25", quantity = 198 } } -- maxStack 200
    local updates, insertions = Omerta.Money.Internal.PlanCredit(
        rows, { [25] = 5 }, "character", 1, 1, 1000)
    assert(#updates == 1 and updates[1].id == 9 and updates[1].quantity == 200,
        "the partial stack fills first")
    assert(#insertions == 1 and insertions[1].quantity == 3, "the rest is a new stack")
    assert(insertions[1].def_id == "money.cent25")
    assert(insertions[1].owner_type == "character" and insertions[1].owner_id == 1)
end)

--------------------------------------------------------------------------------
suite("hunger")
--------------------------------------------------------------------------------

check("decay is slow, bounded, and never fatal", function()
    loadModules()
    local S = Omerta.Hunger.Step
    assert(S(100, 3600, 20) == 80, "an hour at 20/hour")
    assert(S(100, 1800, 20) == 90, "half an hour")
    assert(S(5, 3600, 20) == 0, "it plateaus at empty rather than going negative")
    assert(S(100, 0, 20) == 100, "no time, no change")
end)

check("feeding is bounded at both ends", function()
    loadModules()
    local A = Omerta.Hunger.Apply
    assert(A(50, 35) == 85)
    assert(A(90, 35) == 100, "you cannot be more than full")
    assert(A(10, -50) == 0, "nor less than empty")
end)

check("the three states have the thresholds the design promises", function()
    loadModules()
    local S, State = Omerta.Hunger.State, Omerta.Hunger.STATE
    assert(S(100) == State.FED)
    assert(S(40) == State.FED, "40 is the boundary and still fed")
    assert(S(39) == State.HUNGRY)
    assert(S(15) == State.HUNGRY, "15 is the boundary and not yet starving")
    assert(S(14) == State.STARVING)
    assert(S(0) == State.STARVING)
end)

check("effects arrive in the right order and only when earned", function()
    loadModules()
    -- Merely hungry costs recovery; only starvation is visible in the legs.
    assert(Omerta.Hunger.SpeedMultiplier(50) == 1, "a fed character is not slowed")
    assert(Omerta.Hunger.SpeedMultiplier(30) == 1, "nor a hungry one")
    assert(Omerta.Hunger.SpeedMultiplier(10) < 1, "a starving one is")

    assert(Omerta.Hunger.RegenMultiplier(80) == 1)
    assert(Omerta.Hunger.RegenMultiplier(30) < 1, "hunger costs recovery")
    assert(Omerta.Hunger.RegenMultiplier(10) < Omerta.Hunger.RegenMultiplier(30),
        "starving is worse than hungry")
end)

check("the inventory reads a word, never a percentage", function()
    loadModules()
    assert(Omerta.Hunger.Describe(100) == "Well fed")
    assert(Omerta.Hunger.Describe(50) == "Peckish")
    assert(Omerta.Hunger.Describe(30) == "Hungry")
    assert(Omerta.Hunger.Describe(5) == "Starving")
end)

--------------------------------------------------------------------------------
suite("stamina.modifiers")
--------------------------------------------------------------------------------

-- M9 made hunger the second system with an opinion about movement speed, so
-- the modifiers must compose rather than overwrite one another.
check("modifiers multiply, and bad ones are ignored", function()
    loadModules()
    local C = Omerta.HUD.Internal.CombineModifiers
    assert(C({}, nil) == 1, "no opinions means no change")
    assert(C({ a = function() return 0.5 end }, nil) == 0.5)
    assert(C({ a = function() return 0.5 end, b = function() return 0.5 end }, nil) == 0.25,
        "two halvings quarter it")
    assert(C({ a = function() return nil end }, nil) == 1, "nonsense is ignored")
    assert(C({ a = function() error("boom") end }, nil) == 1, "a broken modifier is ignored")
    assert(C({ a = function() return -3 end }, nil) == 1, "negative speed is not a thing")
end)

--------------------------------------------------------------------------------
suite("inventory.flow")
--------------------------------------------------------------------------------

check("migration 7 creates the items and needs tables", function()
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

    local sawItems, sawNeeds, sawIndex = false, false, false
    for _, s in ipairs(mock.log) do
        if s:find("CREATE TABLE IF NOT EXISTS omerta_items", 1, true) then sawItems = true end
        if s:find("CREATE TABLE IF NOT EXISTS omerta_character_needs", 1, true) then sawNeeds = true end
        if s:find("ON omerta_items (owner_type, owner_id)", 1, true) then sawIndex = true end
    end
    assert(sawItems, "items DDL missing")
    assert(sawNeeds, "character_needs DDL missing")
    -- Without this index, "what is in this container" scans every item in the
    -- season on every open.
    assert(sawIndex, "the owner index is missing")
end)

check("the module declares its dependencies and its interactions", function()
    loadModules()
    Omerta.Module.FinishLoading()

    local def = Omerta.Module.Get("inventory")
    assert(def, "the inventory module did not register")
    for _, dep in ipairs({ "characters", "interaction", "hud", "chat" }) do
        local found = false
        for _, d in ipairs(def.depends or {}) do
            if d == dep then found = true end
        end
        assert(found, "missing dependency on " .. dep)
    end

    -- M5's framework is how anything in the world is reached; picking an item
    -- up must go through it rather than around it.
    assert(Omerta.Interaction.Get("inventory.pickup"), "Pick Up was never registered")
    assert(Omerta.Interaction.Get("inventory.search_container"), "Search was never registered")
end)

check("the wire never carries a name or a value it should not", function()
    loadModules()
    Omerta.Module.FinishLoading()

    local registry = Omerta.Net.GetRegistry()
    for _, name in ipairs({ "inventory.begin", "inventory.item", "inventory.end",
                            "inventory.hunger", "inventory.open", "inventory.action" }) do
        assert(registry[name], "net message '" .. name .. "' is missing")
    end

    -- Hunger follows M8's stamina precedent: a private message to its owner,
    -- with no string in it that could identify anybody.
    for _, field in ipairs(registry["inventory.hunger"].schema) do
        assert(field.type ~= "string", "hunger must not carry text")
    end
    assert(registry["inventory.hunger"].realm == "server_to_client")

    -- Everything the client can ask for is inbound-only, so there is no path
    -- by which one client's request produces another client's contents.
    for _, name in ipairs({ "inventory.open", "inventory.action" }) do
        assert(registry[name].realm == "client_to_server", name .. " should be inbound")
    end
    for _, name in ipairs({ "inventory.begin", "inventory.item", "inventory.end" }) do
        assert(registry[name].realm == "server_to_client", name .. " should be outbound")
    end
end)

--------------------------------------------------------------------------------
suite("inventory.hold_key")
--------------------------------------------------------------------------------

-- The C poll's whole decision, pure. Every stuck-window report this window has
-- produced came out of one of these rows being got wrong in a Think hook, so
-- they are pinned here instead.

-- The window descriptions the rule is fed. `revealed` is the one that matters:
-- a window that is SINKING OUT is still a panel for a tenth of a second, and it
-- counts as closed for every purpose below.
local POCKETS  = { revealed = true,  looting = false, held = true }
local SINKING  = { revealed = false, looting = false, held = true }
local LOOT     = { revealed = true,  looting = true,  held = false }
local LOOT_OUT = { revealed = false, looting = true,  held = false }

check("nothing on screen: the press opens, the hold does not re-open", function()
    loadModules()
    local A = Omerta.Inventory.HoldAction
    assert(A(nil, true, false) == "open", "the press edge opens the pockets")
    assert(A(nil, true, true) == "none", "and the rest of the hold does nothing")
    assert(A(nil, false, true) == "none", "letting go of nothing does nothing")
    assert(A(nil, false, false) == "none", "an idle frame is an idle frame")
end)

check("pockets are up exactly while the key is down", function()
    loadModules()
    local A = Omerta.Inventory.HoldAction
    assert(A(POCKETS, true, true) == "none", "held open, nothing to do")
    assert(A(POCKETS, false, true) == "close", "the release closes it")
    -- Level-triggered, deliberately: a release that the engine never reported
    -- (a panel took focus, the player alt-tabbed) must still close the window
    -- on the next frame the key is seen to be up.
    assert(A(POCKETS, false, false) == "close", "a missed release still closes it")
end)

check("A CLOSING WINDOW COUNTS AS CLOSED", function()
    loadModules()
    local A = Omerta.Inventory.HoldAction

    -- The rule that keeps getting missed. Tapping C again while the last window
    -- is still sinking must build a new one immediately — waiting for the
    -- animation and then ignoring the press is how the key stops answering.
    assert(A(SINKING, true, false) == "open", "the tap reopens mid-animation")
    -- And it must not be closed a second time: it is already leaving, and a
    -- second dismissal of a loot plate would be read as a press that never
    -- reached it.
    assert(A(SINKING, false, true) == "none", "nothing left to close")
    assert(A(LOOT_OUT, true, false) == "open", "a sinking loot plate is gone too")
end)

check("a loot plate is dismissed by a press, and by nothing else", function()
    loadModules()
    local A = Omerta.Inventory.HoldAction

    assert(A(LOOT, true, false) == "close", "the press dismisses it")
    assert(A(LOOT, true, true) == "none", "holding does not dismiss it twice")
    -- It was opened by a search, so there was never a key held down that could
    -- let go of it. A loot plate that the release of C could close would vanish
    -- under the hand of anyone who opened one while walking.
    assert(A(LOOT, false, true) == "none", "the release leaves it alone")
    assert(A(LOOT, false, false) == "none", "and so does an idle frame")
end)

check("the press that dismisses a loot plate does not then open the pockets", function()
    loadModules()
    local A = Omerta.Inventory.HoldAction

    -- THIS is the whole of the stuck-loot-window report, as arithmetic. Frame
    -- one dismisses the plate; on frame two the plate is sinking and therefore
    -- counts as closed, and the key is STILL physically down. A level-triggered
    -- open answers that by putting the player's own pockets up in the plate's
    -- place — which reads exactly like the dismissal having failed, and used to
    -- leave the plate on screen with no pointer to it.
    assert(A(LOOT, true, false) == "close", "frame one: dismissed")
    assert(A(LOOT_OUT, true, true) == "none", "frame two: the same hold opens nothing")
    assert(A(nil, true, true) == "none", "frame three, plate gone: still nothing")
    -- A fresh press is the honest signal for "now show me mine".
    assert(A(nil, true, false) == "open", "let go and press again, and it opens")
end)

check("a window nobody is holding is left alone", function()
    loadModules()
    local A = Omerta.Inventory.HoldAction
    -- omerta_inventory pins the window open with no key. The poll returns early
    -- on `pinned`, but the rule must not close such a window if it ever sees
    -- one: the release of a key that never opened it means nothing.
    local pinned = { revealed = true, looting = false, held = false }
    assert(A(pinned, false, true) == "none", "no hold, no release to honour")
    assert(A(pinned, true, false) == "none", "and a press does not toggle it")
end)

check("the rule survives whatever the poll hands it", function()
    loadModules()
    local A = Omerta.Inventory.HoldAction
    -- A window table straight off a fresh panel has none of these fields set,
    -- and a frame where the poll could not read the key hands it nil.
    assert(A({}, true, false) == "open", "an undescribed window is not up")
    assert(A(nil, nil, nil) == "none")
    assert(A(POCKETS, nil, true) == "close", "no key down is a key that is up")
end)
