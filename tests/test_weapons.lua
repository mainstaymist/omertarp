-- The weapon foundation (Q-10, D-039). What gets pinned hardest is the
-- ruling itself: one Register call is the entire cost of a weapon, the item
-- half of every weapon is coherent with M9, and the ballistics arithmetic the
-- base SWEP trusts is correct at the edges.

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
    "gamemodes/omertarp/gamemode/modules/injury/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sh_injury.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sh_injury_falls.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sh_supplies.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_falls.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_injury.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_bodies.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_treatment.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_actions.lua",
    "gamemodes/omertarp/gamemode/modules/weapons/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/weapons/sh_weapons.lua",
    -- Between sh_weapons and the arsenal, exactly where the engine's own
    -- alphabetical-within-realm ordering puts it ('.' < '_' < 'r'): the
    -- arsenal's Register calls validate their animation blocks against rules
    -- this file defines, so it must be loaded before the first one runs.
    "gamemodes/omertarp/gamemode/modules/weapons/sh_weapons_anim.lua",
    "gamemodes/omertarp/gamemode/modules/weapons/sh_weapons_arsenal.lua",
    -- Listed before sv_weapons for the same reason the engine includes it
    -- first (alphabetical within a realm): it is the file sv_weapons' OnEnable
    -- calls into, and it must never grow a lifecycle method of its own.
    "gamemodes/omertarp/gamemode/modules/weapons/sv_external.lua",
    "gamemodes/omertarp/gamemode/modules/weapons/sv_weapons.lua",
}

local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

--------------------------------------------------------------------------------
suite("weapons.registry")
--------------------------------------------------------------------------------

-- The D-039 ruling made structural: registering a weapon creates its item too,
-- so there is no second place to keep in step.
check("one Register call yields the weapon AND its item", function()
    loadModules()
    local def = Omerta.Weapons.Get("weapon.revolver")
    assert(def, "no revolver definition")
    assert(def.class == "weapon_omerta_revolver", "wrong class: " .. tostring(def.class))

    local item = Omerta.Items.Get("weapon.revolver")
    assert(item, "the item half was not created")
    assert(item.category == "weapon")
    assert(item.slot == "sidearm", "a revolver lives in the sidearm slot")
    assert(item.concealable == true, "a revolver fits under a coat")
    assert(item.bulk == def.bulk, "the item and the weapon disagree about bulk")
    assert(item.weapon == "weapon.revolver", "the link the equip seam follows is missing")
end)

-- M9's founding example, now real: you do not put a Thompson in a pocket.
check("the Thompson cannot be carried without help, or hidden at all", function()
    loadModules()
    local item = Omerta.Items.Get("weapon.thompson")
    assert(item, "no Thompson item")
    assert(item.concealable == false, "a Thompson under a coat breaks the design")
    assert(item.bulk > Omerta.Config.Get("inventory.base_capacity"),
        "bulk " .. item.bulk .. " fits in empty pockets — the design's own example says it must not")
end)

check("every registered weapon chambers ammunition that exists as an item", function()
    loadModules()
    local all = Omerta.Weapons.All()
    assert(#all >= 2, "the arsenal is missing")
    for _, def in ipairs(all) do
        assert(Omerta.Weapons.GetAmmo(def.ammo), def.id .. " chambers unregistered ammo")
        local item = Omerta.Items.Get(def.ammo)
        assert(item, def.id .. "'s ammunition has no item")
        assert(item.stackable, "rounds must stack or a reload fills the inventory screen")
        assert(item.category == "ammo")
    end
end)

expectError("a weapon cannot chamber ammunition that was never registered",
    "unregistered ammunition", function()
    loadModules()
    Omerta.Weapons.Register("weapon.mystery", {
        name = "Mystery Gun", slot = "sidearm", bulk = 3,
        damage = 20, rpm = 100, clip = 5, ammo = "ammo.nonexistent",
    })
end)

expectError("a weapon cannot be registered twice", "registered twice", function()
    loadModules()
    local spec = { name = "Twice", slot = "sidearm", bulk = 3,
        damage = 20, rpm = 100, clip = 5, ammo = "ammo.38" }
    Omerta.Weapons.Register("weapon.twice", spec)
    Omerta.Weapons.Register("weapon.twice", spec)
end)

expectError("a weapon must name a real equipment slot", "unknown equipment slot", function()
    loadModules()
    Omerta.Weapons.Register("weapon.nowhere", {
        name = "Nowhere", slot = "holster_that_does_not_exist", bulk = 3,
        damage = 20, rpm = 100, clip = 5, ammo = "ammo.38",
    })
end)

check("class names are deterministic and collision-free by construction", function()
    loadModules()
    local C = Omerta.Weapons.ClassFor
    assert(C("weapon.revolver") == "weapon_omerta_revolver")
    assert(C("weapon.trench_gun") == "weapon_omerta_trench_gun")
    assert(C("weapon.revolver") ~= C("weapon.thompson"))
end)

--------------------------------------------------------------------------------
suite("weapons.ballistics")
--------------------------------------------------------------------------------

check("the cycle delay follows the rate of fire and never reaches zero", function()
    loadModules()
    local D = Omerta.Weapons.CycleDelay
    assert(math.abs(D(150) - 0.4) < 0.001, "150rpm is a shot every 0.4s")
    assert(D(540) < D(150), "a faster gun fires more often")
    -- A typo'd rate of fire produces a fast gun, never a hitscan hose.
    assert(D(1000000) >= 0.05, "the floor holds")
    assert(D(0) > 0 and D(nil) > 0, "degenerate inputs stay sane")
end)

check("stance changes the shot the way it should", function()
    loadModules()
    local S = Omerta.Weapons.SpreadFactor
    assert(S(0, false) == 1, "standing still is the baseline")
    assert(S(200, false) > S(0, false), "running ruins a shot")
    assert(S(0, true) < S(0, false), "crouching steadies one")
    assert(S(100000, false) <= 2.5, "clamped above")
    assert(S(0, true) >= 0.6, "clamped below")
end)

check("the cone is zero at zero and grows from there", function()
    loadModules()
    local C = Omerta.Weapons.Cone
    assert(C(0) == 0)
    assert(C(1) > 0 and C(3) > C(1))
    assert(C(-5) == 0, "negative spread is no spread")
end)

-- The one piece of arithmetic that touches both the clip and the inventory.
check("a reload takes exactly what is needed and available", function()
    loadModules()
    local P = Omerta.Weapons.PlanReload
    assert(P(6, 6, 10) == 0, "a full clip takes nothing")
    assert(P(6, 0, 10) == 6, "an empty one takes a clipful")
    assert(P(6, 4, 1) == 1, "short pockets give what they have")
    assert(P(6, 0, 0) == 0, "empty pockets give nothing")
    assert(P(6, -2, 10) == 6, "a corrupt clip cannot inflate the take")
    assert(P(20, 3, 500) == 17, "and a crate does not overfill a magazine")
end)

check("serials are unique by construction and absent when meaningless", function()
    loadModules()
    local S = Omerta.Weapons.Serial
    assert(S(123) == "S000123", "format: " .. tostring(S(123)))
    assert(S(123) ~= S(124))
    assert(S(nil) == nil and S(0) == nil, "no instance, no serial")
end)

--------------------------------------------------------------------------------
suite("weapons.drawing")
--------------------------------------------------------------------------------
-- Getting a gun out from under a coat takes time and can be interrupted. The
-- arithmetic of "how long" and "how far through" is pure on purpose: the
-- server ticks it and the client draws it, and both would be a screenshot to
-- test if the numbers lived in either of them.

-- The point of deriving the length from bulk is that the arsenal file inherits
-- it without an edit — so the pin is on the arsenal's own entries, not on a
-- fixture invented here.
check("a draw's length follows bulk, and the arsenal inherits it unedited", function()
    loadModules()
    local revolver = Omerta.Weapons.Get("weapon.revolver")
    local thompson = Omerta.Weapons.Get("weapon.thompson")

    assert(revolver.equipTime and thompson.equipTime,
        "Register must stamp a draw time so no weapon table has to name one")
    assert(math.abs(revolver.equipTime - 1.66) < 0.01,
        "a sidearm clears a coat in about 1.6s, not " .. tostring(revolver.equipTime))
    assert(math.abs(thompson.equipTime - 2.38) < 0.01,
        "a Thompson takes about 2.4s, not " .. tostring(thompson.equipTime))
    assert(thompson.equipTime > revolver.equipTime,
        "the gun nobody can hide must be the slower one to produce")
end)

check("either half of a weapon answers with the same draw", function()
    loadModules()
    local D = Omerta.Weapons.EquipDuration
    -- The equip seam holds the ITEM definition, the tick holds the weapon one.
    assert(D(Omerta.Items.Get("weapon.revolver")) == D(Omerta.Weapons.Get("weapon.revolver")),
        "the item and the weapon disagree about how long a draw takes")
    assert(D(nil) == Omerta.Weapons.EQUIP.base, "no definition, the shared fumble")
    assert(D({}) == Omerta.Weapons.EQUIP.base, "and bulk nobody declared is no bulk")
end)

check("a weapon may name its own draw, and a typo cannot freeze a character", function()
    loadModules()
    local D = Omerta.Weapons.EquipDuration
    assert(D({ bulk = 4, equipTime = 3 }) == 3, "an explicit draw time is believed")
    assert(D({ bulk = 4, equipTime = 900 }) == Omerta.Weapons.EQUIP.max,
        "a typo produces a slow draw, never a minute of paralysis")
    assert(D({ bulk = 4, equipTime = -2 }) > 0, "and a negative one falls back to the curve")
    assert(D({ bulk = 10000 }) == Omerta.Weapons.EQUIP.max, "the curve is clamped too")
end)

check("the draw fraction is 0 at the start, 1 at the end, and clamped outside", function()
    loadModules()
    local F = Omerta.Weapons.EquipFraction
    assert(F(10, 12, 10) == 0, "nothing has happened yet")
    assert(F(10, 12, 11) == 0.5, "halfway is halfway")
    assert(F(10, 12, 12) == 1, "and the end is the end")
    -- A late tick and a clock that jumped backwards are both real; neither may
    -- produce a bar drawn off the end of its own plate.
    assert(F(10, 12, 99) == 1, "clamped above")
    assert(F(10, 12, 0) == 0, "clamped below")
    assert(F(10, 10, 10) == 1, "a window of nothing has already elapsed")
    assert(F(12, 10, 11) == 1, "and so has a backwards one")
    assert(F(nil, nil, nil) == 1, "degenerate inputs stay drawable")
end)

check("the wire carries the draw once, and nothing that names anybody", function()
    loadModules()
    Omerta.Module.FinishLoading()

    local registry = Omerta.Net.GetRegistry()
    for _, name in ipairs({ "weapons.equipping", "weapons.equip_end", "weapons.reserve" }) do
        assert(registry[name], "net message '" .. name .. "' is missing")
        assert(registry[name].realm == "server_to_client",
            name .. " is the server telling one client about its own hands")
        for _, field in ipairs(registry[name].schema) do
            assert(field.type ~= "string", name .. " must not carry text")
        end
    end

    -- Milliseconds, not seconds: a 1.66s draw rounded to whole seconds would
    -- leave the bar filling after the gun was already in the hand.
    local fields = {}
    for _, field in ipairs(registry["weapons.equipping"].schema) do
        fields[field.name] = field
    end
    assert(fields.instance and fields.instance.bits == 32, "an instance id is 32 bits")
    assert(fields.millis, "the client is given the window, not a stream of fractions")
    assert(fields.millis.bits >= 16, "16 bits carries a full minute of draw")
end)

--------------------------------------------------------------------------------
suite("weapons.balance")
--------------------------------------------------------------------------------

-- Calibration against M19's bands, pinned so a retune is deliberate.
check("the revolver downs a healthy man in three body shots, not one", function()
    loadModules()
    local def = Omerta.Weapons.Get("weapon.revolver")
    assert(def.damage * 3 >= 100, "three hits must be enough")
    assert(def.damage * 2 < 100, "two must not be — that is a different game")
end)

check("the Thompson trades damage per round for rate", function()
    loadModules()
    local thompson = Omerta.Weapons.Get("weapon.thompson")
    local revolver = Omerta.Weapons.Get("weapon.revolver")
    assert(thompson.damage < revolver.damage, "per-round the revolver hits harder")
    assert(Omerta.Weapons.CycleDelay(thompson.rpm) < Omerta.Weapons.CycleDelay(revolver.rpm),
        "but the Thompson fires far faster")
    assert(thompson.automatic == true and not revolver.automatic)
end)

-- The M1911 is the first weapon to sit ON the line the other two draw rather
-- than at an end of it, so what is pinned is its POSITION between them rather
-- than any number on its own — a retune that keeps the ordering is free, and
-- one that collapses the three guns into two fails here.
check("the M1911 exists, is carried as a sidearm, and feeds off the Thompson's box", function()
    loadModules()
    local def = Omerta.Weapons.Get("weapon.m1911")
    assert(def, "no M1911 definition")
    assert(def.class == "weapon_omerta_m1911", "wrong class: " .. tostring(def.class))

    local item = Omerta.Items.Get("weapon.m1911")
    assert(item, "the item half was not created")
    assert(item.slot == "sidearm", "a sidearm lives in the sidearm slot")
    assert(item.concealable == true, "a .45 automatic goes under a coat")
    assert(item.bulk < Omerta.Config.Get("inventory.base_capacity"),
        "and it fits in a pocket, unlike the Thompson")

    assert(def.ammo == Omerta.Weapons.Get("weapon.thompson").ammo,
        "the M1911 and the Thompson share a caliber, so a crew has one supply line")
    assert(Omerta.Items.Get(def.ammo), "its ammunition has no item")
end)

check("the M1911 takes four body shots, between the revolver's three and the Thompson's eight", function()
    loadModules()
    local m1911 = Omerta.Weapons.Get("weapon.m1911")

    -- M19's bands: below 70 is injured, below 35 critical, 0 is down.
    assert(m1911.damage * 3 < 100, "three shots must NOT be enough")
    assert(m1911.damage * 4 >= 100, "four must be")
    assert(100 - m1911.damage * 3 < 35, "and the third must leave him critical")
    -- Not on the boundary: a gun whose lethality turns on how a comparison
    -- rounds is a gun that gets reported as a bug.
    assert(m1911.damage * 4 > 100, "four shots must clear 100, not land on it")

    local function shotsToDown(def) return math.ceil(100 / def.damage) end
    assert(shotsToDown(Omerta.Weapons.Get("weapon.revolver")) < shotsToDown(m1911),
        "the revolver must still hit harder per round")
    assert(shotsToDown(m1911) < shotsToDown(Omerta.Weapons.Get("weapon.thompson")),
        "and the Thompson must still hit softer")
end)

-- The price of the slot, stated as an assertion: a gun you can wear into a
-- room where nobody can wear a Thompson does not also win the fight fastest.
check("the concealable .45 is the slowest of the three to put a man down", function()
    loadModules()
    local function secondsToDown(def)
        return (math.ceil(100 / def.damage) - 1) * Omerta.Weapons.CycleDelay(def.rpm)
    end
    local m1911 = secondsToDown(Omerta.Weapons.Get("weapon.m1911"))
    assert(m1911 > secondsToDown(Omerta.Weapons.Get("weapon.revolver")),
        "it must not out-kill the revolver it is easier to keep shooting")
    assert(m1911 > secondsToDown(Omerta.Weapons.Get("weapon.thompson")),
        "and it must certainly not out-kill the gun nobody can hide")

    -- What it buys instead.
    local revolver = Omerta.Weapons.Get("weapon.revolver")
    assert(Omerta.Weapons.Get("weapon.m1911").clip > revolver.clip,
        "a magazine holds more than a cylinder")
    assert(Omerta.Weapons.Get("weapon.m1911").reloadTime < revolver.reloadTime,
        "and changes faster than one is loaded by hand")
end)

--------------------------------------------------------------------------------
suite("weapons.supply")
--------------------------------------------------------------------------------

-- GDD §10: the treasury buys capability. Every entry must deliver a real item
-- at a price real coins can pay.
-- Moved here from the treasury suite with the entry itself. Deliberate
-- (D-025's interplay): arming a crew is an argument between two people, not a
-- click, so the Thompson sits above what an underboss may approve alone.
check("a Thompson costs more than an underboss may spend alone", function()
    loadModules()
    Omerta.Module.FinishLoading()
    local thompson = Omerta.Procurement.Get("supply.thompson")
    local limit = Omerta.Treasury.LimitFor("family", 5)
    assert(thompson.price > limit,
        "a Thompson at " .. Omerta.Money.Format(thompson.price)
        .. " should exceed an underboss's " .. Omerta.Money.Format(limit))
    assert(Omerta.Treasury.CanSpend("family", 5, thompson.price, 6),
        "and a Don should be able to approve one")
end)

check("the arsenal is buyable, and priced in coins that exist", function()
    loadModules()
    Omerta.Module.FinishLoading()
    for _, id in ipairs({ "supply.revolver", "supply.m1911", "supply.thompson",
                          "supply.ammo_38", "supply.ammo_45" }) do
        local entry = Omerta.Procurement.Get(id)
        assert(entry, id .. " is not in the catalogue")
        assert(entry.price % Omerta.Money.SMALLEST == 0,
            id .. " is priced in coins that do not exist")
        assert(Omerta.Items.Get(entry.item), id .. " delivers an item that does not exist")
    end
end)

--------------------------------------------------------------------------------
suite("weapons.external")
--------------------------------------------------------------------------------
-- A weapon may name a SWEP somebody else wrote, and D-039 says that line is the
-- whole edit. Neither the ARC9 pack nor the TFA pack is installed on any
-- machine this suite runs on and neither ever will be, which is exactly the
-- state these checks exist to pin: the DEGRADATION is the load-bearing half,
-- and it is the half that would otherwise only be discovered by an operator.

check("naming a third party's SWEP is a line in the arsenal and nothing else", function()
    loadModules()
    for id, class in pairs({
        ["weapon.thompson"] = "arc9_bo2_thompson",
        ["weapon.revolver"] = "tfa_ins2_wpn_38revolver",
        ["weapon.m1911"]    = "arc9_waw_m1911",
    }) do
        local def = Omerta.Weapons.Get(id)
        assert(def, id .. " is missing")
        assert(def.external == class,
            id .. " should name '" .. class .. "', names " .. tostring(def.external))
        -- Our own class is generated REGARDLESS. It is the fallback, and a
        -- fallback that is only built when it turns out to be needed is a
        -- fallback nobody has ever run.
        assert(def.class == Omerta.Weapons.ClassFor(id),
            id .. " lost its own class to the external one")
    end
end)

check("with the addon absent every weapon falls back to our own base", function()
    loadModules()
    -- Nothing conjured: the default detector answers "not in the engine, so
    -- nothing is installed", which is the honest answer for this machine and
    -- for a server that never mounted the packs.
    local count, fellBack = Omerta.Weapons.ResolveExternal()
    assert(count == 3, "three weapons name an external; " .. count .. " fell back")

    for _, def in ipairs(fellBack) do
        assert(Omerta.Weapons.ClassOf(def) == def.class,
            def.id .. " fell back to " .. tostring(Omerta.Weapons.ClassOf(def)))
        assert(not Omerta.Weapons.IsExternal(def))
        -- The report is what the log line is built from, so it has to carry
        -- the class the operator has to go and install.
        assert(def.external and def.external ~= "", def.id .. " cannot say what is missing")
    end

    -- And the player is handed something. This is the whole point: a missing
    -- addon is our own gun and one line in the log, never an empty hand.
    assert(Omerta.Weapons.ClassOf(Omerta.Weapons.Get("weapon.thompson"))
        == "weapon_omerta_thompson")
end)

check("with the addon present the third party's class is what gets given", function()
    loadModules()
    -- The detector is injectable for the same reason ResolveModel's validator
    -- is: an addon can be conjured and taken away again on a machine that has
    -- neither, which is the only way this path is ever exercised.
    local installed = {
        arc9_bo2_thompson = true,
        arc9_waw_m1911 = true,
    }
    local count = Omerta.Weapons.ResolveExternal(function(class) return installed[class] end)
    assert(count == 1, "only the TFA revolver should have fallen back, " .. count .. " did")

    local thompson = Omerta.Weapons.Get("weapon.thompson")
    assert(Omerta.Weapons.ClassOf(thompson) == "arc9_bo2_thompson",
        "gave " .. tostring(Omerta.Weapons.ClassOf(thompson)))
    assert(Omerta.Weapons.IsExternal(thompson))

    -- Mixed, per weapon, with no ceremony: half an installed pack is a normal
    -- state and must not be an all-or-nothing decision.
    local revolver = Omerta.Weapons.Get("weapon.revolver")
    assert(Omerta.Weapons.ClassOf(revolver) == "weapon_omerta_revolver")
    assert(not Omerta.Weapons.IsExternal(revolver))
end)

check("a detector that errors means the class is not there, not that the boot is", function()
    loadModules()
    local count = Omerta.Weapons.ResolveExternal(function() error("addon exploded") end)
    assert(count == 3, "an exploding lookup must read as absent for every weapon")
    assert(Omerta.Weapons.ClassOf(Omerta.Weapons.Get("weapon.m1911"))
        == "weapon_omerta_m1911")
end)

check("the operator can refuse the third-party classes outright", function()
    loadModules()
    -- weapons.external = false. The recourse when an addon misbehaves on a
    -- live server and nobody is available to patch anything.
    local count = Omerta.Weapons.ResolveExternal(function() return true end, false)
    assert(count == 0, "a deliberate refusal is not a fallback and must not be reported as one")
    for _, def in ipairs(Omerta.Weapons.All()) do
        assert(Omerta.Weapons.ClassOf(def) == def.class,
            def.id .. " ignored the switch")
    end
end)

check("both halves of the pair answer to the same weapon", function()
    loadModules()
    local thompson = Omerta.Weapons.Get("weapon.thompson")
    -- The hotbar, the round readout, the reserve and the holster props all ask
    -- this one question, and none of them should have to know which class won.
    assert(Omerta.Weapons.ForClass("weapon_omerta_thompson") == thompson)
    assert(Omerta.Weapons.ForClass("arc9_bo2_thompson") == thompson)
    assert(Omerta.Weapons.ForClass("weapon_physgun") == nil,
        "a gun the arsenal does not know is not ours to reconcile")
    assert(Omerta.Weapons.ForClass(nil) == nil)
end)

expectError("an external must be somebody else's SWEP, not one of ours",
    "weapon_omerta_* is ours", function()
    loadModules()
    Omerta.Weapons.Register("weapon.pretender", {
        name = "Pretender", slot = "sidearm", bulk = 3,
        damage = 20, rpm = 100, clip = 5, ammo = "ammo.38",
        -- Claiming our own class would make the fallback point at itself, so a
        -- missing addon would resolve to "present" and the degradation would
        -- never fire.
        external = "weapon_omerta_revolver",
    })
end)

expectError("an external must look like a class name", "is not a class name", function()
    loadModules()
    Omerta.Weapons.Register("weapon.shouty", {
        name = "Shouty", slot = "sidearm", bulk = 3,
        damage = 20, rpm = 100, clip = 5, ammo = "ammo.38",
        external = "ARC9 Thompson",
    })
end)

expectError("two weapons cannot claim the same third-party class", "already claims", function()
    loadModules()
    Omerta.Weapons.Register("weapon.copycat", {
        name = "Copycat", slot = "sidearm", bulk = 3,
        damage = 20, rpm = 100, clip = 5, ammo = "ammo.38",
        external = "arc9_bo2_thompson",
    })
end)

--------------------------------------------------------------------------------
suite("weapons.ammunition_bridge")
--------------------------------------------------------------------------------
-- D-004 across a SWEP we did not write. The inventory stays the truth and the
-- engine's ammo pool becomes a projection of it; this is the arithmetic that
-- makes that sentence enforceable, and it is pure so the suite can pin it
-- rather than an in-engine session having to.
--
-- The rule under every one of these: where the accounting is ambiguous the
-- player ends up with FEWER rounds than they might have had, never more.

check("nothing happening costs nothing and re-projects the pocket", function()
    loadModules()
    local plan = Omerta.Weapons.PlanPoolSync(10, 6, 10, 6, 10)
    assert(plan.spend == 0, "an idle gun charges nothing")
    assert(plan.clip == 6, "and keeps its magazine")
    assert(plan.pool == 10, "the pool is the pocket, always")
end)

check("a reload charges the inventory for exactly what left the pool", function()
    loadModules()
    -- Empty gun, ten rounds in a pocket. The addon reloads itself: seven out
    -- of the pool, seven into the magazine.
    local plan = Omerta.Weapons.PlanPoolSync(10, 0, 10, 7, 3)
    assert(plan.spend == 7, "seven rounds left the pool and seven leave the pocket")
    assert(plan.clip == 7, "the magazine is honest and stands")
    assert(plan.pool == 3, "and the pool is what is left")
end)

check("firing costs nothing extra, because the reload already paid", function()
    loadModules()
    -- Three rounds in a pocket, seven in the magazine, three fired.
    local plan = Omerta.Weapons.PlanPoolSync(3, 7, 3, 4, 3)
    assert(plan.spend == 0, "the round was charged when it went into the gun")
    assert(plan.clip == 4)
    assert(plan.pool == 3)
end)

check("a weapon that eats the pool directly is charged just the same", function()
    loadModules()
    -- Some bases take the shot straight off the reserve without a magazine
    -- ever changing. The rounds are gone either way and the bill is the same.
    local plan = Omerta.Weapons.PlanPoolSync(20, 0, 20, 0, 17)
    assert(plan.spend == 3, "three rounds left the pool")
    assert(plan.pool == 17)
end)

check("a pool the addon inflated is clamped back to the pocket", function()
    loadModules()
    -- The single most important line in the bridge: an addon handing the
    -- player ammunition cannot make ammunition, because the next projection
    -- overwrites the pool with what the inventory actually holds.
    local plan = Omerta.Weapons.PlanPoolSync(3, 6, 3, 6, 999)
    assert(plan.spend == 0, "nothing left the pool, so nothing is charged")
    assert(plan.pool == 3, "and the pool goes back to being the pocket")
end)

check("a magazine filled out of nowhere is charged for", function()
    loadModules()
    -- Rounds appeared in the magazine without leaving the pool: the addon
    -- keeps ammunition somewhere we cannot see, or refilled itself. Same
    -- problem, same answer — the pocket pays.
    local plan = Omerta.Weapons.PlanPoolSync(10, 0, 5, 7, 5)
    assert(plan.spend == 7, "seven unbacked rounds, seven charged")
    assert(plan.clip == 7, "the pocket could afford them, so they stay in the gun")
    assert(plan.pool == 3)
end)

check("a magazine nobody can pay for comes straight back out of the gun", function()
    loadModules()
    -- Empty pockets, empty pool, thirty rounds in the magazine. This is the
    -- shape of every cheat the bridge cannot see coming, and it resolves to
    -- the same place: the character holds what the character owns.
    local plan = Omerta.Weapons.PlanPoolSync(0, 0, 0, 30, 0)
    assert(plan.spend == 0, "there is nothing to charge")
    assert(plan.clip == 0, "so there is nothing in the gun")
    assert(plan.pool == 0)
end)

check("a half-affordable magazine is cut down to what was owned", function()
    loadModules()
    -- Five rounds owned, five drawn from the pool, thirty somehow in the
    -- magazine. The five real ones stay; the twenty-five invented ones do not.
    local plan = Omerta.Weapons.PlanPoolSync(5, 0, 5, 30, 0)
    assert(plan.spend == 5, "everything that was owned is charged")
    assert(plan.clip == 5, "and the magazine holds exactly that")
    assert(plan.pool == 0)
end)

check("rounds arriving in a pocket reach the pool, and rounds leaving it do not strand the magazine", function()
    loadModules()
    -- Bought a box: thirty more rounds, nothing else changed.
    local bought = Omerta.Weapons.PlanPoolSync(33, 4, 3, 4, 3)
    assert(bought.spend == 0 and bought.pool == 33,
        "the projection follows the pocket without a hook to be told")

    -- Dropped every loose round while the gun is loaded. The four in the
    -- magazine were already charged for and stay where they are.
    local dropped = Omerta.Weapons.PlanPoolSync(0, 4, 3, 4, 3)
    assert(dropped.spend == 0 and dropped.pool == 0 and dropped.clip == 4)
end)

check("the arithmetic survives what an unread addon might hand it", function()
    loadModules()
    local P = Omerta.Weapons.PlanPoolSync
    for _, plan in ipairs({
        P(nil, nil, nil, nil, nil),
        P(-5, -5, -5, -5, -5),
        P(10, 0, 0, 6.7, 3.2),
        P(0 / 0, 0 / 0, 0 / 0, 0 / 0, 0 / 0),   -- NaN
        P(math.huge, 0, 0, math.huge, math.huge),
    }) do
        for _, field in ipairs({ "spend", "clip", "pool" }) do
            local value = plan[field]
            assert(type(value) == "number", field .. " stopped being a number")
            assert(value == value, field .. " came back NaN")
            assert(value >= 0, field .. " came back negative")
            assert(value % 1 == 0, field .. " came back fractional: " .. value)
        end
    end
end)

check("a refund puts back the magazine, and never more than we vouched for", function()
    loadModules()
    local R = Omerta.Weapons.RefundableClip
    -- Our own weapon: the clip is ours, we wrote every round of it.
    assert(R(6, 0, false) == 6, "our own gun refunds its magazine")
    assert(R(0, 0, false) == 0)

    -- A third party's: capped by what the bridge last settled. Clip1 on a
    -- magazine model we have never read is a number we did not write, and
    -- refunding a number we did not write is how strip-and-re-equip mints
    -- ammunition.
    assert(R(7, 7, true) == 7, "an honest magazine refunds honestly")
    assert(R(30, 7, true) == 7, "an inflated one refunds what was vouched for")
    assert(R(3, 7, true) == 3, "and a spent one refunds what is actually left")
    assert(R(7, nil, true) == 0, "vouched for nothing, refund nothing")
    assert(R(-4, 7, true) == 0 and R(7, -4, true) == 0, "and nonsense refunds nothing")
end)

--------------------------------------------------------------------------------
suite("weapons.animation")
--------------------------------------------------------------------------------
-- Phase 2 of docs/review/06_weapon_art_port.md: the base learns which SEQUENCE
-- belongs to each event, by name.
--
-- Two things are pinned hardest, and they are the two that would otherwise
-- only be discovered on a live server. The first is that a weapon which
-- declares NOTHING is the weapon it was yesterday — every gun in the arsenal is
-- in that state today and will be until a dump exists. The second is the
-- failure: a name the model does not carry must produce one line naming the
-- weapon, the event and the name, and then play the activity the base has
-- always played, rather than playing nothing and looking like a broken gun.

-- A model, as far as the resolver is concerned: names in, indices out, -1 for
-- a name that is not there. Which is exactly what Entity:LookupSequence is, and
-- the reason the resolver takes it as an argument — an addon can be conjured
-- and taken away again on a machine that has never had one.
local function fakeModel(sequences)
    return function(name)
        local index = sequences[name]
        if index == nil then return -1 end
        return index
    end
end

check("a weapon that declares no animation block resolves to exactly what the base did before", function()
    loadModules()
    -- The whole arsenal, because this is the promise being made to it.
    for _, def in ipairs(Omerta.Weapons.All()) do
        assert(def.anim == nil, def.id ..
            " grew an animation block — no sequence name may be typed before a dump exists")

        local fire = Omerta.Weapons.AnimEntry(def, "fire")
        assert(fire.sequence == nil, def.id .. " invented a firing sequence")
        assert(fire.activity == "ACT_VM_PRIMARYATTACK",
            def.id .. " lost the activity the base falls back to")
        assert(fire.sound == def.sound,
            def.id .. " stopped using its own gunshot: " .. tostring(fire.sound))

        -- The dry click is NOT the weapon's `sound` field and never was: an
        -- empty gun clicks, it does not fire quietly.
        local dry = Omerta.Weapons.AnimEntry(def, "dry")
        assert(dry.sound == "Weapon_Pistol.Empty",
            def.id .. "'s dry click changed to " .. tostring(dry.sound))
        assert(dry.sequence == nil)

        -- Reloading emits nothing in this base and must keep emitting nothing:
        -- inventing foley for a placeholder is a change to a gun nobody asked
        -- to change.
        local reload = Omerta.Weapons.AnimEntry(def, "reload")
        assert(reload.sound == nil, def.id .. " grew a reload sound")
        assert(reload.activity == "ACT_VM_RELOAD")
    end
end)

check("a weapon with no block asks the model nothing at all", function()
    loadModules()
    local def = Omerta.Weapons.Get("weapon.revolver")
    -- A model that would happily answer for every name in the world. The
    -- weapon declares none, so nothing is looked up and the activity stands.
    local asked = 0
    local plan = Omerta.Weapons.ResolveAnim(def, "fire", function(name)
        asked = asked + 1
        return 3
    end)
    assert(asked == 0, "a weapon with no block asked the model " .. asked .. " question(s)")
    assert(plan.sequence == nil, "and must not have been given a sequence anyway")
    assert(plan.missing == nil, "nothing was wanted, so nothing is missing")
    assert(plan.activity == "ACT_VM_PRIMARYATTACK")
    assert(plan.sound == def.sound)
end)

check("a declared sequence is resolved by NAME, against the model", function()
    loadModules()
    Omerta.Weapons.Register("weapon.ported", {
        name = "Ported", slot = "sidearm", bulk = 4,
        damage = 20, rpm = 120, clip = 6, ammo = "ammo.38",
        sound = "some/gun/fire.wav",
        anim = {
            draw    = "draw",
            idle    = "idle",
            fire    = "shoot",
            reload  = { sequence = "reload_full", sound = "some/gun/reload.wav" },
            holster = "holster",
        },
    })
    local def = Omerta.Weapons.Get("weapon.ported")
    local model = fakeModel({
        draw = 0, idle = 1, shoot = 2, reload_full = 3, holster = 4,
    })

    -- Index 0 is a perfectly ordinary sequence — the FIRST one in the model.
    -- A base that read 0 as "absent" would refuse the opening animation of
    -- every model ever made, which is why the miss test is `< 0`.
    local draw = Omerta.Weapons.ResolveAnim(def, "draw", model)
    assert(draw.sequence == 0, "index 0 read as missing: " .. tostring(draw.sequence))
    assert(draw.missing == nil)

    assert(Omerta.Weapons.ResolveAnim(def, "fire", model).sequence == 2)
    assert(Omerta.Weapons.ResolveAnim(def, "reload", model).sequence == 3)
    assert(Omerta.Weapons.ResolveAnim(def, "holster", model).sequence == 4)

    -- The name asked for is carried through whether or not it was found, so
    -- the log line can quote what the arsenal actually says.
    assert(Omerta.Weapons.ResolveAnim(def, "fire", model).wanted == "shoot")
end)

check("a sequence the model does not have is reported, and the activity plays instead", function()
    loadModules()
    Omerta.Weapons.Register("weapon.stale", {
        name = "Stale", slot = "sidearm", bulk = 4,
        damage = 20, rpm = 120, clip = 6, ammo = "ammo.38",
        -- The failure this whole design exists for: the artist renamed it, or
        -- somebody typed it from memory. An INDEX would have silently played
        -- whatever moved into that slot.
        anim = { fire = "shoot_v2" },
    })
    local def = Omerta.Weapons.Get("weapon.stale")
    local plan = Omerta.Weapons.ResolveAnim(def, "fire", fakeModel({ shoot = 2 }))

    assert(plan.missing == "shoot_v2",
        "a missing sequence must be nameable: " .. tostring(plan.missing))
    assert(plan.sequence == nil, "and must not play something else by accident")
    assert(plan.activity == "ACT_VM_PRIMARYATTACK",
        "and must fall back to the activity the base uses today")
    -- Still audible. A gun whose animation is wrong is not a gun that stops
    -- making a noise.
    assert(plan.sound == "Weapon_Pistol.Single")
end)

check("every way a model can fail to answer reads as missing, not as a crash", function()
    loadModules()
    Omerta.Weapons.Register("weapon.brittle", {
        name = "Brittle", slot = "sidearm", bulk = 4,
        damage = 20, rpm = 120, clip = 6, ammo = "ammo.38",
        anim = { fire = "shoot" },
    })
    local def = Omerta.Weapons.Get("weapon.brittle")

    for label, lookup in pairs({
        ["minus one"]     = function() return -1 end,
        ["nil"]           = function() return nil end,
        ["not a number"]  = function() return "sequence" end,
        ["NaN"]           = function() return 0 / 0 end,
        -- A lookup that errors has ANSWERED: the sequence is not there.
        -- Anything else lets one bad model take a trigger pull down with it.
        ["an error"]      = function() error("model exploded") end,
    }) do
        local plan = Omerta.Weapons.ResolveAnim(def, "fire", lookup)
        assert(plan.missing == "shoot", label .. " did not read as missing")
        assert(plan.sequence == nil, label .. " produced a sequence anyway")
        assert(plan.activity == "ACT_VM_PRIMARYATTACK", label .. " lost the fallback")
    end

    -- No model at all — the state of this machine, and of any realm that has
    -- not spawned a viewmodel yet. The activity, silently.
    local none = Omerta.Weapons.ResolveAnim(def, "fire", nil)
    assert(none.sequence == nil and none.missing == nil,
        "no model to ask is not the same as a model that said no")
end)

check("a model that does not distinguish the empty cases inherits the full ones", function()
    loadModules()
    Omerta.Weapons.Register("weapon.plain", {
        name = "Plain", slot = "sidearm", bulk = 4,
        damage = 20, rpm = 120, clip = 6, ammo = "ammo.38",
        anim = {
            fire   = { sequence = "shoot",  sound = "gun/fire.wav" },
            reload = { sequence = "reload", sound = "gun/reload.wav" },
        },
    })
    local def = Omerta.Weapons.Get("weapon.plain")

    -- One firing animation, one reload. The gun that empties itself and the
    -- gun that reloads from empty play the same thing, and the base never has
    -- to know which kind of model it is holding.
    local lastShot = Omerta.Weapons.AnimEntry(def, "fire_empty")
    assert(lastShot.sequence == "shoot", "fire_empty did not inherit fire")
    assert(lastShot.sound == "gun/fire.wav", "nor its sound")

    local fromEmpty = Omerta.Weapons.AnimEntry(def, "reload_empty")
    assert(fromEmpty.sequence == "reload" and fromEmpty.sound == "gun/reload.wav")
end)

check("a model that does distinguish them is believed, field by field", function()
    loadModules()
    Omerta.Weapons.Register("weapon.fancy", {
        name = "Fancy", slot = "sidearm", bulk = 4,
        damage = 20, rpm = 120, clip = 6, ammo = "ammo.38",
        anim = {
            fire       = { sequence = "shoot", sound = "gun/fire.wav" },
            -- A slide locking back looks different and sounds the same, which
            -- is the ordinary case: the sequence is declared, the sound is
            -- inherited, and neither had to be repeated.
            fire_empty = "shoot_last",
            reload       = "reload",
            reload_empty = "reload_empty",
        },
    })
    local def = Omerta.Weapons.Get("weapon.fancy")

    local lastShot = Omerta.Weapons.AnimEntry(def, "fire_empty")
    assert(lastShot.sequence == "shoot_last", "the declared sequence lost to the inherited one")
    assert(lastShot.sound == "gun/fire.wav", "the sound should still have been inherited")

    assert(Omerta.Weapons.AnimEntry(def, "reload_empty").sequence == "reload_empty")
    assert(Omerta.Weapons.AnimEntry(def, "reload").sequence == "reload")
end)

check("sound falls through the arsenal in one order, and ends at today's placeholder", function()
    loadModules()
    local E = Omerta.Weapons.AnimEntry

    -- Nothing declared anywhere: the base's own placeholders, which is what
    -- every weapon shipped before this existed used.
    local bare = { id = "weapon.bare" }
    assert(E(bare, "fire").sound == "Weapon_Pistol.Single")
    assert(E(bare, "dry").sound == "Weapon_Pistol.Empty")
    assert(E(bare, "reload").sound == nil, "the base emits nothing on a reload today")

    -- The weapon's own top-level `sound`, which is what the arsenal has said
    -- since W0 and must keep meaning the same thing.
    local classic = { id = "weapon.classic", sound = "Weapon_357.Single" }
    assert(E(classic, "fire").sound == "Weapon_357.Single")
    assert(E(classic, "fire_empty").sound == "Weapon_357.Single")
    assert(E(classic, "dry").sound == "Weapon_Pistol.Empty",
        "a gunshot is not a dry click")

    -- And the block, which beats both.
    local ported = {
        id = "weapon.ported2", sound = "Weapon_357.Single",
        anim = {
            fire   = { sequence = "shoot", sound = "thompson/fire.wav" },
            dry    = { sound = "thompson/dryfire.wav" },
            reload = { sequence = "reload", sound = "thompson/reload.wav" },
        },
    }
    assert(E(ported, "fire").sound == "thompson/fire.wav")
    assert(E(ported, "dry").sound == "thompson/dryfire.wav")
    assert(E(ported, "reload").sound == "thompson/reload.wav")
    -- Declared with a sound and no sequence: legal, and it stays legal. Not
    -- every model has a dryfire animation and every gun has a dry click.
    assert(E(ported, "dry").sequence == nil)
end)

check("an event this base does not have answers nothing at all", function()
    loadModules()
    -- Not an empty table, and not a guess. There is no ironsight event because
    -- there is no secondary attack to hang one on, and a base that quietly
    -- returned a plan for one would be a base somebody wrote a call site for.
    assert(Omerta.Weapons.AnimEntry({}, "ironsights") == nil)
    assert(Omerta.Weapons.AnimEntry({}, "") == nil)
    assert(Omerta.Weapons.AnimEntry({}, nil) == nil)
    assert(Omerta.Weapons.ResolveAnim({}, "ironsights", fakeModel({})) == nil)

    -- And every event it DOES have answers with an activity to fall back on,
    -- because the fallback is the whole reason a missing sequence is survivable.
    for _, event in ipairs(Omerta.Weapons.ANIM_EVENT_ORDER) do
        local entry = Omerta.Weapons.AnimEntry({}, event)
        assert(entry, "no entry for the base's own event '" .. event .. "'")
        assert(type(entry.activity) == "string" and entry.activity:find("^ACT_VM_"),
            event .. " has no activity to fall back to")
    end
end)

check("a typo in an animation block is a boot error, not a gun that plays nothing", function()
    loadModules()
    local base = {
        name = "Typo", slot = "sidearm", bulk = 4,
        damage = 20, rpm = 120, clip = 6, ammo = "ammo.38",
    }
    local function spec(anim)
        local out = {}
        for k, v in pairs(base) do out[k] = v end
        out.anim = anim
        return out
    end
    local V = Omerta.Weapons.Validate

    assert(V("weapon.ok", spec({ fire = "shoot" })))
    assert(V("weapon.ok", spec({ fire = { sequence = "shoot" } })))
    assert(V("weapon.ok", spec({ dry = { sound = "click.wav" } })))
    assert(V("weapon.ok", spec({ fire = { sequence = "shoot", rate = 1.5 } })))

    local function refused(anim, mention)
        local ok, why = V("weapon.bad", spec(anim))
        assert(not ok, "accepted " .. mention)
        assert(tostring(why):find(mention, 1, true),
            "the refusal did not mention '" .. mention .. "': " .. tostring(why))
    end

    refused({ shoot = "shoot" }, "unknown event")
    refused({ fire = 7 }, "must be a sequence name")
    refused({ fire = "" }, "must not be empty")
    refused({ fire = " shoot " }, "leading or trailing whitespace")
    refused({ fire = { sound = 3 } }, "sound must be a string")
    refused({ fire = { sequence = "shoot", rate = 0 } }, "rate must be a playback speed")
    -- An entry that declares neither is a line that does nothing, which is
    -- always a mistake somebody made rather than a decision somebody took.
    refused({ fire = {} }, "declares neither a sequence nor a sound")
    refused("reload", "must be a table")
end)

check("an animation is fitted to OUR clock, and says so when it cannot be", function()
    loadModules()
    local R = Omerta.Weapons.AnimRate

    -- `reloadTime` wins and the art is stretched to it: a 3.0s reload
    -- animation inside the M1911's 2.2s magazine change plays at 1.36x. The
    -- number is a balance position argued for in the arsenal and it gates real
    -- inventory work; an animation's length is neither.
    local rate, clamped = R(3.0, 2.2)
    assert(math.abs(rate - 3.0 / 2.2) < 1e-9, "the fit is length over target")
    assert(not clamped)

    -- Already agreeing: nothing is stretched, which is the state Phase 3
    -- should be aiming the arsenal's numbers at.
    assert(R(2.2, 2.2) == 1)

    -- A short animation in a long window slows down rather than finishing
    -- early and leaving the hands frozen.
    assert(R(1.1, 2.2) == 0.5)

    -- Too far apart to hide. Clamped at both ends for the reason CycleDelay
    -- and EquipDuration are — a mismatch produces a brisk reload or a languid
    -- one, never a strobe and never a frozen hand — and it SAYS so, because
    -- that pair is a conversation about the arsenal's number.
    local fast, saidFast = R(60, 2)
    assert(fast == Omerta.Weapons.ANIM_RATE.max and saidFast)
    local slow, saidSlow = R(0.01, 10)
    assert(slow == Omerta.Weapons.ANIM_RATE.min and saidSlow)

    -- Nothing an unread model can hand us produces a frozen or a negative
    -- viewmodel. Playing at its own speed is always defensible.
    for _, pair in ipairs({
        { nil, nil }, { 0, 2 }, { 2, 0 }, { -3, 2 }, { 2, -3 },
        { 0 / 0, 2 }, { 2, 0 / 0 }, { math.huge, math.huge },
    }) do
        local value = R(pair[1], pair[2])
        assert(type(value) == "number" and value == value and value > 0,
            "a degenerate pair produced " .. tostring(value))
        assert(value >= Omerta.Weapons.ANIM_RATE.min
            and value <= Omerta.Weapons.ANIM_RATE.max)
    end
end)

check("the three ported weapons are still waiting for their dump", function()
    loadModules()
    -- The gate the port plan set, made into something a machine checks. These
    -- three name a third party's SWEP class, which means their art is the
    -- whole point of the exercise — and NOT ONE sequence name may be typed for
    -- them until `omerta_weapon_dump` has been run on a server that has the
    -- packs. A guessed name is silently wrong forever (D-044's asymmetry); a
    -- weapon with no block plays the activities it always has.
    local waiting = 0
    for _, def in ipairs(Omerta.Weapons.All()) do
        if def.external then
            waiting = waiting + 1
            assert(def.anim == nil, def.id ..
                " has an animation block but its sequences have never been read")
        end
    end
    assert(waiting == 3, "expected three weapons awaiting a dump, found " .. waiting)
end)
