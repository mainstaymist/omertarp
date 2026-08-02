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
-- The revolver and the Thompson are the design's own poles — the gun anybody
-- can hide and the gun nobody can — and every later weapon sits somewhere on
-- the line between them. The M1911 is the first to actually do it.
--
-- Damage is calibrated against M19's bands (below 70% hurt, below 35%
-- critical, 0 down), and models are HL2 placeholders per D-005.
--
-- THE `external` LINES ARE THE THIRD-PARTY SWEPS, AND THEY ARE THE WHOLE EDIT.
-- The project lead installed an ARC9 pack and a TFA pack; each of those three
-- strings names a SWEP class in them. Everything below still works with
-- neither addon installed — a class the server does not have falls back to our
-- own generated `weapon_omerta_*` and says so once in the log. See the
-- "Somebody else's SWEP" section of sh_weapons.lua for why that is the only
-- claim this file is allowed to make about an addon nobody here has read.
--
-- WHERE THE ANIMATION BLOCKS ARE. Nowhere, on purpose.
--
-- A weapon may declare `anim = { fire = "…", reload = "…", … }` naming the
-- sequence in its viewmodel that belongs to each event the base knows about —
-- that is Phase 2 of docs/review/06_weapon_art_port.md, and the rules for
-- reading one are in sh_weapons_anim.lua. NOT ONE WEAPON BELOW DECLARES ONE,
-- and none may until a sequence dump from a real server exists.
--
-- The reason is the one this whole file already lives under: neither pack is
-- installed on any machine this was written on, so a sequence name typed here
-- would be a GUESS. D-044's asymmetry decides what to do about that — a wrong
-- guess about a name is silently wrong forever, where a wrong guess about a
-- function simply does not match — and a sequence name is the first kind. A
-- weapon with no block plays exactly the ACT_VM_* activities it has always
-- played, which is the correct behaviour for a placeholder HL2 model and the
-- correct behaviour for a ported one nobody has read yet.
--
-- What fills them in is `omerta_weapon_dump <class>` run on a server that has
-- the packs mounted: it prints every sequence in the viewmodel with its name
-- and its duration, which is both halves of what an entry needs. That is
-- Phase 3, one gun at a time, and it is data in this file and nowhere else.
--
-- The item ids are DELIBERATELY UNCHANGED by the renaming. `weapon.revolver`
-- and `weapon.thompson` are what is sitting in pockets, safes and procurement
-- rows already; a gun's display name is data and its id is a key, and renaming
-- the key to match the label would orphan every instance in the database for
-- the sake of a string nobody sees.

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
-- The Model 10: the gun anybody can hide
--------------------------------------------------------------------------------
-- Three body shots put a healthy man down (34 × 3 > 100), which makes it
-- dangerous without making it quick — the deliberate, non-arcade feel D-017
-- asked the whole combat layer to keep.

Omerta.Weapons.Register("weapon.revolver", {
    name = "Model 10",
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

    -- CORRECTED 2026-08-02 from a real server's class list. There is no
    -- TFA pack mounted and no .38 anywhere; the S&W M1917 is the only
    -- revolver installed. It is a .45 in life and this one stays .38 —
    -- the model is art and the caliber is ours, and nobody in a gunfight
    -- has ever counted the chambers.
    external = "arc9_doi_sw1917",

    holdType = "revolver",
    sound = "Weapon_357.Single",
    viewModel = { "models/weapons/c_357.mdl", "models/weapons/v_357.mdl" },
    worldModel = { "models/weapons/w_357.mdl" },
})

--------------------------------------------------------------------------------
-- The M1911: the gun in between
--------------------------------------------------------------------------------
-- The first weapon to sit on the line the other two draw rather than at an end
-- of it: concealable like the Model 10 (bulk 5 against 4 — an automatic with a
-- magazine is a slightly bigger object than a service revolver, and still
-- nothing a coat notices), chambered in the Thompson's .45 so a crew's ammunition
-- is one supply line rather than two.
--
-- HOW THE NUMBERS WERE CHOSEN, against M19's bands (below 70% of 100 is
-- injured, below 35% critical, 0 is down) and against the two guns already
-- calibrated to them:
--
--   damage 26 — FOUR body shots to put a healthy man down (26 × 4 = 104), and
--     three leave him at 22, which is inside M19's critical band. That places
--     it exactly between the Model 10's three shots and the Thompson's eight,
--     which is the whole design intent expressed as an integer. Deliberately
--     NOT 25: 25 × 4 = 100 lands on the boundary, and a gun whose lethality
--     depends on which way a comparison rounds is a gun that will be reported
--     as a bug.
--
--   rpm 200 — 0.3s between shots. Its four shots therefore take 0.9s where the
--     Model 10's three take 0.8s and the Thompson's eight take 0.78s, so the
--     .45 automatic is the SLOWEST of the three to put somebody down with
--     perfect aim. That is on purpose and it is the price of the slot: a gun
--     you can wear into a room where nobody can wear a Thompson does not also
--     get to win the fight fastest. What it buys instead is the magazine —
--     seven rounds and a 2.2s change against six and 2.8s of loading a cylinder
--     by hand — so it is the sidearm that is still shooting when the revolver
--     is not.
--
--   spread 1.1 / recoil 1.6 — between the two, nearer the revolver. A light
--     automatic is less steady per shot than a deliberate double-action and
--     far steadier than a submachine gun.

Omerta.Weapons.Register("weapon.m1911", {
    name = "M1911",
    slot = "sidearm",
    bulk = 5,
    concealable = true,

    damage = 26,
    rpm = 200,
    clip = 7,             -- the 1911's magazine
    ammo = "ammo.45",     -- the same box that feeds the Thompson
    chamber = "magazine",
    spread = 1.1,
    recoil = 1.6,
    reloadTime = 2.2,     -- a magazine change, not a cylinder

    -- CORRECTED 2026-08-02: the pack installed is Day of Infamy, not
    -- World at War. Exact match, different prefix.
    external = "arc9_doi_m1911",

    holdType = "pistol",
    sound = "Weapon_Pistol.Single",
    viewModel = { "models/weapons/c_pistol.mdl", "models/weapons/v_pistol.mdl" },
    worldModel = { "models/weapons/w_pistol.mdl" },
})

--------------------------------------------------------------------------------
-- The M1921 AC Thompson: the gun nobody can
--------------------------------------------------------------------------------
-- Bulk 22 against a base capacity of 20 is M9's own founding example: you do
-- not put a Thompson in a pocket. Carrying one takes an overcoat or a case,
-- and carrying one OPENLY is a statement everybody in the street can read.

Omerta.Weapons.Register("weapon.thompson", {
    name = "M1921 AC Thompson",
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

    -- CORRECTED 2026-08-02: Day of Infamy, not Black Ops 2. The pack has
    -- two — `arc9_doi_thompson` is the military M1A1 with a stick
    -- magazine, `arc9_doi_tommy` is the drum-magazine Tommy Gun. This
    -- game wants the one a bootlegger carries.
    external = "arc9_doi_tommy",

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
        name = "Model 10", category = "weapons",
        price = 8500, order = 30,
        item = "weapon.revolver", quantity = 1,
    })
    Omerta.Procurement.Register("supply.m1911", {
        -- Above a service revolver and a long way below a Thompson, which is
        -- where it sits on every other axis too. Comfortably inside an
        -- Underboss's $250 ceiling (D-025): arming a crew with sidearms is a
        -- decision one person may take, and arming it with Thompsons is not.
        name = "M1911", category = "weapons",
        price = 12500, order = 31,
        item = "weapon.m1911", quantity = 1,
    })
    Omerta.Procurement.Register("supply.thompson", {
        name = "M1921 AC Thompson", category = "weapons",
        -- Deliberately above an Underboss's own ceiling (D-025), so buying
        -- one is an argument between two people rather than a click.
        price = 34000, order = 32,
        item = "weapon.thompson", quantity = 1,
    })
    Omerta.Procurement.Register("supply.ammo_38", {
        name = "Box of .38", category = "weapons",
        price = 300, order = 33,
        item = "ammo.38", quantity = 30,
    })
    Omerta.Procurement.Register("supply.ammo_45", {
        name = "Box of .45", category = "weapons",
        price = 450, order = 34,
        item = "ammo.45", quantity = 30,
    })
end
