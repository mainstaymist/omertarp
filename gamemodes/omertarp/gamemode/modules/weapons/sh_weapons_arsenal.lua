-- The arsenal (BA §27: small and period).
--
-- Named sh_weapons_arsenal rather than sh_arsenal because module files load
-- ALPHABETICALLY within a realm, and "arsenal" sorts before "weapons" — the
-- data would run before the registry existed. The sixth load-order incident
-- on this project was caught by the module-graph test before it shipped; the
-- name is the fix that cannot regress.
--
-- THIS FILE IS THE ENTIRE COST OF A WEAPON. A new gun is a Register call here
-- — the item it exists as, the SWEP class the engine fires, and the numbers
-- every seam reads all come from the one table. Nothing else in the gamemode
-- is edited, per the D-039 ruling.
--
-- Two firearms on purpose. The revolver and the Thompson are the design's own
-- poles — the gun anybody can hide and the gun nobody can — and every later
-- weapon sits somewhere on the line between them. Six more guns is six more
-- tables, added when M14 knows what it wants them for.
--
-- Damage is calibrated against M19's bands (below 70% hurt, below 35%
-- critical, 0 down), and models are HL2 placeholders per D-005.

--------------------------------------------------------------------------------
-- Calibers first: a weapon cannot chamber ammunition that does not exist.
--------------------------------------------------------------------------------

Omerta.Weapons.RegisterAmmo("ammo.38", {
    name = ".38 Rounds",
    model = "models/items/357ammo.mdl",
})

Omerta.Weapons.RegisterAmmo("ammo.45", {
    name = ".45 Rounds",
    model = "models/items/boxsrounds.mdl",
})

--------------------------------------------------------------------------------
-- The revolver: the gun anybody can hide
--------------------------------------------------------------------------------
-- Three body shots put a healthy man down (34 × 3 > 100), which makes it
-- dangerous without making it quick — the deliberate, non-arcade feel D-017
-- asked the whole combat layer to keep.

Omerta.Weapons.Register("weapon.revolver", {
    name = ".38 Revolver",
    slot = "sidearm",
    bulk = 4,
    concealable = true,   -- it fits under a coat, which is the point of it

    damage = 34,
    rpm = 150,            -- 0.4s between shots: aimed fire, not a hose
    clip = 6,
    ammo = "ammo.38",
    chamber = "cylinder", -- what the ammunition counter calls where rounds sit
    spread = 0.9,
    recoil = 2.2,
    reloadTime = 2.8,

    holdType = "revolver",
    sound = "Weapon_357.Single",
    viewModel = { "models/weapons/c_357.mdl", "models/weapons/v_357.mdl" },
    worldModel = { "models/weapons/w_357.mdl" },
})

--------------------------------------------------------------------------------
-- The Thompson: the gun nobody can
--------------------------------------------------------------------------------
-- Bulk 22 against a base capacity of 20 is M9's own founding example: you do
-- not put a Thompson in a pocket. Carrying one takes an overcoat or a case,
-- and carrying one OPENLY is a statement everybody in the street can read.

Omerta.Weapons.Register("weapon.thompson", {
    name = "Thompson",
    slot = "primary",
    bulk = 22,
    concealable = false,

    damage = 13,
    rpm = 540,
    clip = 20,            -- the stick magazine; a drum is a later table edit
    ammo = "ammo.45",
    chamber = "magazine",
    spread = 2.4,
    recoil = 0.9,
    reloadTime = 3.6,
    automatic = true,

    holdType = "smg",
    sound = "Weapon_SMG1.Single",
    viewModel = { "models/weapons/c_smg1.mdl", "models/weapons/v_smg1.mdl" },
    worldModel = { "models/weapons/w_smg1.mdl" },
})

--------------------------------------------------------------------------------
-- Where they come from (GDD §10: the treasury buys capability)
--------------------------------------------------------------------------------
-- Registered here rather than in a treasury file so a weapon and its supply
-- line live in one place — the same pattern M19's bandages set.

-- Prices carried over from M11's catalogue exactly, where they were set
-- deliberately: arming a crew is a decision the books will show.
if SERVER and Omerta.Procurement then
    Omerta.Procurement.Register("supply.revolver", {
        name = "Revolver", category = "weapons",
        price = 8500, order = 30,
        item = "weapon.revolver", quantity = 1,
    })
    Omerta.Procurement.Register("supply.thompson", {
        name = "Thompson", category = "weapons",
        -- Deliberately above an Underboss's own ceiling (D-025), so buying
        -- one is an argument between two people rather than a click.
        price = 34000, order = 31,
        item = "weapon.thompson", quantity = 1,
    })
    Omerta.Procurement.Register("supply.ammo_38", {
        name = "Box of .38", category = "weapons",
        price = 300, order = 32,
        item = "ammo.38", quantity = 30,
    })
    Omerta.Procurement.Register("supply.ammo_45", {
        name = "Box of .45", category = "weapons",
        price = 450, order = 33,
        item = "ammo.45", quantity = 30,
    })
end
