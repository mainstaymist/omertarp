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
-- WHERE THE ANIMATION BLOCKS ARE. On all three, as of 2026-08-02.
--
-- A weapon may declare `anim = { fire = "…", reload = "…", … }` naming the
-- sequence in its viewmodel that belongs to each event the base knows about —
-- that is Phase 2 of docs/review/06_weapon_art_port.md, and the rules for
-- reading one are in sh_weapons_anim.lua.
--
-- EVERY NAME BELOW WAS READ OFF A MODEL BY `omerta_weapon_dump <class>` ON A
-- REAL SERVER, and not one of them is a guess. That rule does not relax now
-- that the arsenal is fully ported; it is the whole reason it could be.
-- D-044's asymmetry is why — a wrong guess about a name is silently wrong
-- forever, where a wrong guess about a function simply does not match — and a
-- sequence name is the first kind. The Model 10 was the last one waiting, and
-- `arc9_doi_sw1917` came back on 2026-08-02; the fallback it was living on is
-- still there and is still what the next gun gets until its own dump arrives.
--
-- WHAT A DUMP MAY NOT DECIDE: which of a model's animations we USE. The
-- revolver came back with two complete and mutually exclusive reload families,
-- and only one of them is a reload our base can honestly drive — see its block.
-- A dump answers "what exists", never "what this gamemode does".
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

    --   reloadTime 5.375 / reloadEmptyTime 6.031 — MOVED ONTO THE ART,
    --     2026-08-02, from 2.8 for both. `arc9_doi_sw1917`'s moon-clip reload
    --     runs 5.375s and the same reload from an empty cylinder runs 6.031s.
    --
    --     THIS IS THE LARGEST BALANCE MOVE THE PORT HAS MADE and it deserves a
    --     look in the field rather than a nod here. 2.8s was a number nobody
    --     measured; 5.375s is nearly twice it, and it makes the Model 10 by a
    --     distance the slowest gun in the arsenal to bring back into a fight —
    --     slower than a Thompson's stick magazine (3.333s), and slower even
    --     than a Thompson run dry (4.762s).
    --
    --     What the move BUYS, and why it was taken rather than the animation
    --     being stretched to 2.8 (which is a 1.92x playback rate, inside the
    --     clamp and visibly hurried): the design's whole position on this gun is
    --     that it is the weapon anybody can hide, and that concealment is paid
    --     for somewhere. Until now it was paid for in damage and rate of fire
    --     only. Now it is paid for in the one currency a gunfight actually
    --     spends — a man who empties a revolver is out of the argument for six
    --     seconds, which is a genuinely frightening length of time and exactly
    --     what loading a cylinder by hand should feel like.
    --
    --     The M1911's paragraph below still holds and holds harder: its 2.635s
    --     magazine change is now less than half the revolver's, so "the sidearm
    --     that is back in the fight first" is no longer a close-run thing. What
    --     it LOSES is one line of that paragraph — the M1911's empty reload
    --     (3.333s) used to cost more than the revolver's only reload, and it no
    --     longer does. Running an automatic dry is still worse than not, but it
    --     is no longer worse than carrying a revolver.
    --
    --     The 0.656s between the two revolver numbers is the smallest gap in the
    --     arsenal, and the art agreeing with the prose is the pleasant part: the
    --     comment that used to live here argued that "a revolver that has fired
    --     five rounds is not meaningfully quicker to fill than one that has
    --     fired six", and the animator evidently thought so too.
    reloadTime = 5.375,
    reloadEmptyTime = 6.031,

    -- CORRECTED 2026-08-02 from a real server's class list. There is no
    -- TFA pack mounted and no .38 anywhere; the S&W M1917 is the only
    -- revolver installed. It is a .45 in life and this one stays .38 —
    -- the model is art and the caliber is ours, and nobody in a gunfight
    -- has ever counted the chambers.
    external = "arc9_doi_sw1917",

    holdType = "revolver",
    sound = "Weapon_357.Single",
    -- Their model first, ours behind it; see the M1911's note for why.
    viewModel = {
        "models/weapons/arc9_doi/c_sw1917.mdl",
        "models/weapons/c_357.mdl",
        "models/weapons/v_357.mdl",
    },
    worldModel = { "models/weapons/w_357.mdl" },
    holsterModel = {
        "models/weapons/arc9_doi/c_sw1917.mdl",
        "models/weapons/w_357.mdl",
    },
    viewModelFOV = 62,

    -- PORTED 2026-08-02 from `omerta_weapon_dump arc9_doi_sw1917` on a live
    -- server. Every name below was read off the model; the durations in the
    -- comments are the dump's, and they are where the two reload numbers above
    -- came from.
    --
    -- THIS MODEL RELOADS TWO DIFFERENT WAYS, and we take one of them.
    --
    --   the MOON CLIP — `base_reload_clip` (5.375s) and `base_reload_clip_empty`
    --   (6.031s): one animation, six rounds, the whole cylinder at once. That is
    --   what our base's reload IS — a single event, a single window, and one
    --   `PlanReload` that moves N rounds from a pocket in one transaction.
    --
    --   the LOOSE ROUNDS — `base_reload_start` (2.206s) or
    --   `base_reload_start_empty` (2.912s), then `base_reload_insert` (0.950s)
    --   once per round, then `base_reload_end` (2.000s). DELIBERATELY UNUSED.
    --   The base has no concept of a per-round loop: one reload event, one
    --   clock, one commit. Playing the start-insert-end family through a single
    --   reload event would either play the start and stop, or loop an insert
    --   that no round is actually going into — hands working ammunition the
    --   inventory is not moving, which is the exact lie the animation port
    --   exists to remove. What it would cost to want it is written up in the
    --   handover; it is a change to the base and to the server's reload, not
    --   data in this file.
    --
    -- The `iron_*` set is ignored as it is on the other two: there is no
    -- secondary attack to hang an ironsight on (W0 §6).
    anim = {
        draw         = "base_draw",              -- 0.469s
        idle         = "base_idle",              -- 4.000s
        fire         = "base_fire",              -- 1.257s, at its own rate
        fire_empty   = "base_fire_last",         -- 1.000s: the last chamber
        dry          = "base_dryfire",           -- 0.667s
        reload       = "base_reload_clip",       -- 5.375s = reloadTime, rate 1.0
        reload_empty = "base_reload_clip_empty", -- 6.031s = reloadEmptyTime
        holster      = "base_holster",           -- 0.457s
    },
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
    -- STILL UNCHANGED, and now for one reason where it used to have two.
    -- `arc9_doi_*` declares a stand-in world model that ARC9 itself never
    -- renders (the plan's §4b: the Thompson's is an AK-47), so pointing
    -- `worldModel` at theirs would put the wrong gun in every observer's hands
    -- and under every dropped weapon. What this field answers is what our own
    -- generated SWEP renders in a hand and what the M9 item lies on the
    -- pavement as, and §4b ruled on neither of those.
    worldModel = { "models/weapons/w_pistol.mdl" },
    -- §4b OPTION (a), TAKEN 2026-08-02. The prop that hangs off a hip or a back
    -- is built from the pack's `c_` viewmodel, with the HL2 placeholder behind
    -- it so a server without the pack is byte for byte what it was. The project
    -- lead has now reported the holstered weapon as the wrong model twice, and
    -- twice is a decision: an AK-47 slung across a 1930s gangster's back is a
    -- worse lie than any pose a `c_` model can hold.
    --
    -- THE RISK, ON THE RECORD, because it is real and it is visible. A `c_`
    -- model is authored to be bonemerged onto a viewmodel rig, so standing on
    -- its own as a prop it renders in its REFERENCE POSE — and models of this
    -- kind are commonly built with the arms in them. If ARC9's are, this puts a
    -- pair of disembodied hands on the holster prop. It cannot be fixed from
    -- here without guessing at a bodygroup index, which is the one thing this
    -- port refuses to do, so `omerta_weapon_dump` now prints every model's
    -- bodygroups: if one of them turns out to hide the arms, hiding it is a data
    -- edit on this line. If none does, the answer is §4b option (b) — real `w_`
    -- models — and this line reverts to the placeholder alone.
    holsterModel = {
        "models/weapons/arc9_doi/c_m1911.mdl",
        "models/weapons/w_pistol.mdl",
    },
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
    -- §4b option (a), taken 2026-08-02; the M1911's note above carries the
    -- argument and the risk for all three. This is the gun the ruling was
    -- ABOUT — the stand-in ARC9 declares for it is `w_rif_ak47.mdl`, and a
    -- slung Thompson is the design's own example of a thing everybody in the
    -- street can read off a man before he says a word. Reading an AK-47 off him
    -- is the worst available outcome.
    holsterModel = {
        "models/weapons/arc9_doi/c_thompson.mdl",
        "models/weapons/w_smg1.mdl",
    },
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
