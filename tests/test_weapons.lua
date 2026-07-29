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
    "gamemodes/omertarp/gamemode/modules/injury/sh_supplies.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_injury.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_bodies.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_treatment.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_actions.lua",
    "gamemodes/omertarp/gamemode/modules/weapons/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/weapons/sh_weapons.lua",
    "gamemodes/omertarp/gamemode/modules/weapons/sh_weapons_arsenal.lua",
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
    for _, id in ipairs({ "supply.revolver", "supply.thompson",
                          "supply.ammo_38", "supply.ammo_45" }) do
        local entry = Omerta.Procurement.Get(id)
        assert(entry, id .. " is not in the catalogue")
        assert(entry.price % Omerta.Money.SMALLEST == 0,
            id .. " is priced in coins that do not exist")
        assert(Omerta.Items.Get(entry.item), id .. " delivers an item that does not exist")
    end
end)
