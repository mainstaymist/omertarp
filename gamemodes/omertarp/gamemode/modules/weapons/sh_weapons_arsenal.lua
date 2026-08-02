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
-- WHERE THE ANIMATION BLOCKS ARE. On two of the three, as of 2026-08-02.
--
-- A weapon may declare `anim = { fire = "…", reload = "…", … }` naming the
-- sequence in its viewmodel that belongs to each event the base knows about —
-- that is Phase 2 of docs/review/06_weapon_art_port.md, and the rules for
-- reading one are in sh_weapons_anim.lua.
--
-- EVERY NAME BELOW WAS READ OFF A MODEL BY `omerta_weapon_dump <class>` ON A
-- REAL SERVER, and not one of them is a guess. That rule does not relax now
-- that two guns have been ported; it is the whole reason those two could be.
-- D-044's asymmetry is why — a wrong guess about a name is silently wrong
-- forever, where a wrong guess about a function simply does not match — and a
-- sequence name is the first kind. The Model 10 therefore still has no block:
-- `arc9_doi_sw1917` has never been dumped, and a weapon with no block plays
-- exactly the ACT_VM_* activities it has always played.
--
-- The dump prints every sequence with its name and its DURATION, and both
-- halves are used: the names are the block, and the durations are what the
-- reload numbers below were re-derived from, so nothing is stretched. Phase 3,
-- one gun at a time, and it is data in this file and nowhere else.
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

    -- NO ANIMATION BLOCK, AND NO viewModelFOV. `arc9_doi_sw1917` has never been
    -- dumped — the Thompson and the M1911 came back from a live server on
    -- 2026-08-02 and this one did not — so there is no sequence name for it
    -- that would not be a guess, and a guessed name is silently wrong forever.
    -- It plays the ACT_VM_* activities on the HL2 placeholder exactly as it
    -- always has. What it needs is one line of output from
    -- `omerta_weapon_dump arc9_doi_sw1917`; nothing else is in the way.
    --
    -- Its 2.8s reload is therefore still our own number rather than the art's,
    -- and it has one duration for both cases: a cylinder is loaded by hand and
    -- a revolver that has fired five rounds is not meaningfully quicker to fill
    -- than one that has fired six, which is the one case in the arsenal where a
    -- single `reloadTime` is the honest model rather than a missing field.
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
--
--   reloadTime 2.635 / reloadEmptyTime 3.333 — MOVED ONTO THE ART, 2026-08-02.
--     Both were 2.2, which was a number nobody had measured against anything.
--     `arc9_doi_m1911`'s magazine change runs 2.635s and its reload from a
--     locked-back slide runs 3.333s, and both are defensible as balance, so the
--     arsenal moved rather than the animation being stretched to hide the
--     difference (the port plan says to prefer that, and it means the playback
--     rate is 1.0 and the art plays as its artist timed it).
--
--     The paragraph above still holds where it matters: 2.635s is faster than
--     the Model 10's 2.8s of loading a cylinder by hand, so the automatic is
--     still the sidearm that is back in the fight first. What is new is the
--     price of running it dry — 3.333s, slower than the revolver — which is a
--     real reason to change magazines before the slide locks rather than after,
--     and a mechanic the base could not express until it had two numbers.

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
    reloadTime = 2.635,      -- a magazine change, not a cylinder
    reloadEmptyTime = 3.333, -- and one that starts with the slide locked back

    -- CORRECTED 2026-08-02: the pack installed is Day of Infamy, not
    -- World at War. Exact match, different prefix.
    external = "arc9_doi_m1911",

    holdType = "pistol",
    sound = "Weapon_Pistol.Single",
    -- Their model first, ours behind it. ResolveModel takes the first path the
    -- machine actually has, so a server with the pack mounted gets the ported
    -- viewmodel and one without gets the HL2 placeholder it has always had —
    -- the same degradation the `external` seam performs, on the art instead of
    -- the class. Nothing is copied into this repository; we point at files the
    -- Workshop delivers (the port plan §3 licensing line).
    viewModel = {
        "models/weapons/arc9_doi/c_m1911.mdl",
        "models/weapons/c_pistol.mdl",
        "models/weapons/v_pistol.mdl",
    },
    -- UNCHANGED, deliberately. `arc9_doi_*` declares a stand-in world model
    -- that ARC9 itself never renders (the plan's §4b: the Thompson's is an
    -- AK-47), so pointing at theirs would put the wrong gun in every observer's
    -- hands and on every holster prop. That ruling — bonemerge the c_ model,
    -- source proper w_ models, or ship placeholders — is still open.
    worldModel = { "models/weapons/w_pistol.mdl" },
    -- What the pack authored the viewmodel for. Our base sets none and inherits
    -- the engine's 54, which makes a ported model sit visibly wrong.
    viewModelFOV = 62,

    -- PORTED 2026-08-02 from `omerta_weapon_dump arc9_doi_m1911` on a live
    -- server: 38 sequences, every name below read off the model. The durations
    -- in the comments are the dump's, and they are why the two reload numbers
    -- above are what they are.
    --
    -- The naming is NOT the Thompson's. This model spells its first firing
    -- animation `base_fire` where the Thompson spells it `base_fire_1`, and its
    -- last-round shot `base_firelast` with no underscore. There is no
    -- convention to derive here, only a dump to read.
    --
    -- The `iron_*` set is ignored: there is no secondary attack to hang an
    -- ironsight on (W0 §6). So is the `empty_*` set — a whole parallel pose
    -- family for a gun standing open, which needs a base that tracks "the slide
    -- is back" as a state rather than as a moment, and that is a feel change
    -- rather than a port.
    anim = {
        draw         = "base_draw",        -- 0.429s
        idle         = "base_idle",        -- 4.000s
        fire         = "base_fire",        -- 1.000s, at its own rate, always
        fire_empty   = "base_firelast",    -- 1.000s: the shot that locks it open
        dry          = "base_dryfire",     -- 0.667s
        reload       = "base_reload",      -- 2.635s = reloadTime, so rate 1.0
        reload_empty = "base_reloadempty", -- 3.333s = reloadEmptyTime
        holster      = "base_holster",     -- 0.429s
    },
})

--------------------------------------------------------------------------------
-- The M1921 AC Thompson: the gun nobody can
--------------------------------------------------------------------------------
-- Bulk 22 against a base capacity of 20 is M9's own founding example: you do
-- not put a Thompson in a pocket. Carrying one takes an overcoat or a case,
-- and carrying one OPENLY is a statement everybody in the street can read.
--
--   reloadTime 3.333 / reloadEmptyTime 4.762 — MOVED ONTO THE ART, 2026-08-02.
--     `reloadTime` was 3.6, a number chosen to feel like "longer than a pistol"
--     and never measured; `arc9_doi_tommy`'s stick-magazine change is 3.333s
--     and its change from empty is 4.762s. Both are defensible as balance, so
--     the arsenal moved and the animation is not stretched at all.
--
--     The 0.267s the tactical reload got quicker is not the interesting half.
--     The interesting half is that a 20-round automatic at 540rpm empties in
--     2.2s of held trigger, so EMPTY is this gun's ordinary reload — and it now
--     costs 4.762s, a second and a half more than the number it replaced, and
--     nearly twice what the M1911 beside it pays. A man who dumps a magazine is
--     out of the fight for the length of a conversation, which is the correct
--     price for the gun nobody can hide.

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
    reloadTime = 3.333,      -- the stick magazine, off the model's own clock
    reloadEmptyTime = 4.762, -- and the same change with the bolt locked back
    automatic = true,

    -- CORRECTED 2026-08-02: Day of Infamy, not Black Ops 2. The pack has
    -- two — `arc9_doi_thompson` is the military M1A1 with a stick
    -- magazine, `arc9_doi_tommy` is the drum-magazine Tommy Gun. This
    -- game wants the one a bootlegger carries.
    external = "arc9_doi_tommy",

    holdType = "smg",
    sound = "Weapon_SMG1.Single",
    -- Their model first, ours behind it; see the M1911's note for why, and for
    -- why the world model is not touched.
    viewModel = {
        "models/weapons/arc9_doi/c_thompson.mdl",
        "models/weapons/c_smg1.mdl",
        "models/weapons/v_smg1.mdl",
    },
    worldModel = { "models/weapons/w_smg1.mdl" },
    viewModelFOV = 62,

    -- PORTED 2026-08-02 from `omerta_weapon_dump arc9_doi_tommy` on a live
    -- server: 83 sequences, every name below read off the model.
    --
    -- THE STICK SET, NOT THE DRUM. The model carries a complete parallel family
    -- — `base_fire_last_drum`, `base_reload_drum`, `base_reloadempty_drum`,
    -- `base_dryfire_drum` — belonging to a drum-magazine bodygroup that ARC9
    -- switches on when its own attachment is fitted. Which also corrects the
    -- plan's §4b: `arc9_doi_tommy` is not "the drum-magazine Thompson", it is a
    -- Thompson that CAN take a drum, and what it displays unattached is a stick
    -- magazine. That is the state we get it in. We dropped attachments
    -- (the port plan §2) and never set that bodygroup, and this gun's clip is
    -- 20, which is a stick. Playing a drum reload would animate hands working a
    -- magazine the model is not displaying, so those names are deliberately
    -- absent and the 5.477s/6.923s drum durations are not what the numbers
    -- above were derived from.
    --
    -- The `foregrip_*` and `iron_*` families are ignored for the same reason
    -- one step further out: they are attachment and sight poses, and we have
    -- neither.
    --
    -- `base_fire_2` exists beside `base_fire_1` (both 1.333s) as a firing
    -- variant. The base has ONE fire event and picks no variants; choosing
    -- between them per shot would be a change to sh_weapons_anim.lua, not data,
    -- and it is not worth making before somebody has watched this fire.
    anim = {
        draw         = "base_draw",        -- 0.710s
        -- 0.000s: a single-frame rest pose rather than a loop, which is what
        -- ARC9 leaves behind when it drives idle sway procedurally. It is
        -- exactly what this base wants from an idle — something to put the
        -- model back to after a shot or a reload — and `settle` in PlayAnim
        -- means re-asserting it every half second costs a comparison.
        idle         = "base_idle",
        -- 1.333s against a 0.111s cycle at 540rpm. NOT fitted, and this is the
        -- gun that proves the rule: each shot restarts it and you see the first
        -- ninth of the bolt cycle, which is what an automatic looks like.
        fire         = "base_fire_1",
        fire_empty   = "base_fire_last",   -- 1.333s: the round that empties it
        dry          = "base_dryfire",     -- 0.667s
        reload       = "base_reload",      -- 3.333s = reloadTime, so rate 1.0
        reload_empty = "base_reloadempty", -- 4.762s = reloadEmptyTime
        holster      = "base_holster",     -- 0.559s
    },
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
