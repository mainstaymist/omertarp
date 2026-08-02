# Porting ARC9 / TFA weapons onto our own base

**Status:** plan, awaiting the first upload.
**Supersedes in practice:** D-044's external-SWEP bridge, which stays as a fallback but stops being the intended path if this lands.

---

## 1. Why the swap did nothing

The external classes fell back. That is the designed behaviour, not a failure: each weapon independently checks whether its class exists and reverts to our base with a log line when it does not. `omerta_weapons_list` prints `(wanted <class>)` on any weapon that fell back, which is the fastest way to confirm.

The likely cause is that `resource.AddWorkshop` only makes **clients** download an addon. The server needs the ARC9 base, the BO2 and WaW packs, and the TFA base + Insurgency 2 pack in its **own** collection. Worth confirming before we build anything, because it tells us whether the bridge works at all — and the port below needs those addons mounted regardless.

## 2. What we are actually doing

**Take their art. Leave their framework.**

| | Theirs | Ours |
|---|---|---|
| Viewmodel + world model | ✅ | |
| Animations (the sequences baked into the model) | ✅ | |
| Firing / reload / foley sounds | ✅ | |
| Ammunition | | ✅ M9 items (D-004) |
| Damage, rate, spread, recoil | | ✅ the arsenal (M19's bands) |
| Equip ceremony, holster props, concealment | | ✅ W0 |
| `Omerta.WeaponFired` | | ✅ (M14 depends on it) |
| Attachments, customisation UI, ballistics, their ammo pool | ❌ dropped | |

That gets us the "lightweight, suited for our gamemode, standardized" outcome you asked for: one base, one data table per gun, no second weapon framework running underneath ours.

## 3. The licensing line, which decides the architecture

ARC9 packs are overwhelmingly ports of commercial game assets. **We cannot copy their models, materials or sounds into this repository** — not into `content/`, not into an "Omertà assets" addon, not repacked. That is redistribution and it is exactly the kind of thing that gets a server and a Workshop upload taken down.

So the addons stay **mounted dependencies**. Their files stay theirs, delivered by the Workshop as they are today; we ship Lua that *points at* them by path. Our repository gains no binary assets at all.

This also decides what you need to upload: **Lua only**. I do not need — and must not have — the `.mdl`, `.vtf`, `.vmt` or `.wav` files.

## 4. The one unknown that changes the plan

ARC9 drives a weapon two ways at once:

1. **Baked sequences** in the viewmodel — `idle`, `fire`, `reload`, `draw`. These are ordinary Source animations and we can play them with `SendWeaponAnim` / `SetSequence` the moment we know their names.
2. **Procedural bone manipulation** — sights, sprint pose, sway, attachment offsets. This is ARC9 code operating on the model's bones every frame.

If a gun's feel is mostly (1), the port is straightforward and mostly data entry. If it leans on (2), reproducing it means reimplementing a chunk of ARC9, and the honest answer changes to "keep their SWEP and live with D-044's bridge."

**I expect mostly (1)** — ARC9's `SWEP.Animations` table names sequences by `Source`, which means they exist in the model. But that is an expectation, not a finding, and it is cheap to check, so we check it first.

## 4b. Phase 0 result (2026-08-02) — read this before the phases below

`omerta_weapon_dump arc9_doi_thompson` came back from a real server. Three findings, and two of them change the plan.

### The animations are baked. The port is viable.

25 named sequences on the viewmodel, with durations:

| sequence | length | our event |
|---|---|---|
| `base_draw` | 1.321s | draw |
| `idle` / `base_idle` | 1.000s | idle |
| `base_fire`, `base_fire_2`, `base_fire_3` | 1.667s | fire (three variants) |
| `base_dryfire` | 0.667s | dry |
| `base_reload` | 3.968s | reload |
| `base_reloadempty_1`, `_2` | 5.397s | reload_empty |
| `base_holster` | 0.559s | holster |

Plus iron-sight variants, `base_ready`, `base_sprint`, `base_crawl`, `base_melee_bash`, `base_fireselect`. This is the good case: everything our base needs exists as a playable sequence, and Phase 3 is data entry.

### The pack is Day of Infamy, not Black Ops 2 or World at War

The three class strings in the arsenal were **all wrong** — no `arc9_bo2_*` or `arc9_waw_*` exists on that server. What is installed is `arc9_doi_*`, a **Second World War** pack, which is a considerably better fit for this game's period than Black Ops 2 was ever going to be. The relevant classes:

| our weapon | candidate | note |
|---|---|---|
| M1921 AC Thompson | `arc9_doi_tommy` ("Tommy Gun") | the drum-magazine gangster Thompson — almost certainly the right one |
| | `arc9_doi_thompson` ("M1A1 Thompson") | the military stick-magazine version; the one dumped above |
| M1911 | `arc9_doi_m1911` | exact |
| Model 10 | `arc9_doi_sw1917` (S&W M1917) | the only revolver in the pack. Chambered .45 in reality; ours stays .38 — the model is art, the caliber is ours |

Also present and period-plausible for later: `arc9_doi_bar` (the 1918 BAR, a genuine gangster-era weapon), `arc9_doi_c96`, `arc9_doi_luger`, `arc9_doi_springfield`.

**No TFA classes were checked.** The revolver's `tfa_ins2_wpn_38revolver` is still unconfirmed and probably wants replacing with the S&W above regardless.

### The world model is a placeholder, and this is the real problem

```
arc9_doi_thompson worldmodel: models/weapons/w_rif_ak47.mdl   (2 sequences)
```

**The Thompson's third-person model is an AK-47.** That is not a bug in the pack — ARC9 renders what other players see from the `c_` viewmodel through its own framework, so the declared `WorldModel` is a stand-in nothing is expected to look at.

Drop their framework and that stand-in becomes what everybody sees: an AK-47 in a 1930s gangster's hands, and an AK-47 slung across his back on W0's holster props.

So the port gets first person right and third person badly wrong, and that is a decision rather than a detail:

- **(a) Bonemerge the `c_` model as the world model.** A `c_` model is built to be bonemerged onto a rig and this is what ARC9 itself effectively does. Most work, best result, and it is work on our side rather than theirs.
- **(b) Source proper `w_` models separately** for three guns. Cleanest to render, but it means finding or commissioning art.
- **(c) Keep D-044's external bridge for these three** and accept the ammunition-accounting risk in exchange for a framework that already solves the world model.
- **(d) Ship the port with placeholder world models** and treat third person as a later pass.

This needs a ruling. It did not exist as a question before the dump, which is exactly why the dump came first.

### Also learned

`UseHands=true`, `ViewModelFOV=62` (our base does not set one, so it inherits the default 54 — a ported gun will look wrong until this moves with it), `HoldType=ar2`. The `base_`/`iron_` prefixes are ARC9's own convention for pose sets; only the `base_` half matters to us.

## 4c. The two real dumps, and Phase 3 for the guns they cover (2026-08-02)

`arc9_doi_tommy` and `arc9_doi_m1911` came back from the live server. Both are `UseHands=true`, `ViewModelFOV=62`, and both are fully baked — every event our base has exists as a named sequence. Both are now ported: the sequence names, the two viewmodel paths and the field of view are data in `sh_weapons_arsenal.lua`, and nothing else was edited to add them.

| event | `arc9_doi_tommy` (83 seq) | `arc9_doi_m1911` (38 seq) |
|---|---|---|
| draw | `base_draw` 0.710 | `base_draw` 0.429 |
| idle | `base_idle` 0.000 (a rest pose) | `base_idle` 4.000 |
| fire | `base_fire_1` 1.333 | `base_fire` 1.000 |
| fire_empty | `base_fire_last` 1.333 | `base_firelast` 1.000 |
| dry | `base_dryfire` 0.667 | `base_dryfire` 0.667 |
| reload | `base_reload` 3.333 | `base_reload` 2.635 |
| reload_empty | `base_reloadempty` 4.762 | `base_reloadempty` 3.333 |
| holster | `base_holster` 0.559 | `base_holster` 0.429 |

**The naming is not shared between the two models.** `base_fire_1` against `base_fire`; `base_firelast` with no underscore. There is no convention to derive, only a dump to read.

**The Thompson's drum family is deliberately unused.** `base_reload_drum` (5.477), `base_reloadempty_drum` (6.923), `base_fire_last_drum` and `base_dryfire_drum` belong to an attachment bodygroup we drop and never set, and our clip is 20 — a stick. `foregrip_*` and `iron_*` are ignored for the same reason one step out: attachment and sight poses, and we have neither.

Three things the data changed:

1. **Firing animations are never fitted.** 540rpm is a 0.111s cycle against a 1.333s firing animation — 12x, three times outside the playback clamp. A firing animation plays at its natural rate and is *restarted* by the next shot. The distinction is now a `fitted` column in `ANIM_EVENTS`: two events (both reloads) are stretched to a window the server enforces, six are not, and `PlayAnim` ignores a `fit` offered for any of the six.
2. **`reloadEmptyTime`**, optional, defaulting to `reloadTime`. Both models make an empty reload substantially longer and that is a real cost for running dry, so `Internal.Reload` now decides which case it is in *before* setting `OmertaReloadUntil` and `SetNextPrimaryFire`. A weapon that declares none is unchanged in both cases.
3. **`viewModelFOV`**, optional, absent by default so the engine's own default stands. Both ported guns declare 62.

Our numbers moved onto the art where its length was defensible as balance, per §2's principle: the M1911 2.2 → 2.635/3.333, the Thompson 3.6 → 3.333/4.762. Nothing is stretched — the playback rate is 1.0 for all four reloads. No `damage`, `rpm` or `clip` was touched.

**Still open.** The revolver: `arc9_doi_sw1917` has not been dumped, so `weapon.revolver` has no animation block and must not be given one until it is. Sounds: the dump named sequences, not sound files, so both ported guns still fire HL2 placeholders. The world-model ruling in §4b. And the `external` seam still **wins** over all of this — a server with the packs runs `arc9_doi_*` and never reaches our base — so the blocks above are inert until an operator sets `weapons.external 0`, which is Phase 4's decision to make.

## 5. Phases

### Phase 0 — find out what we are dealing with (no upload needed) — **DONE, see §4b and §4c**

I add `omerta_weapon_dump <class>`: spawns the class's viewmodel server-side, enumerates every sequence with its name, duration and framerate, and prints the list. Run it on all three weapons and paste the output.

That single output tells us: whether the animations are baked (they will be, or they won't), what the events are actually called, and how long each one runs — which is what our reload timing and equip ceremony need to line up against.

**This is the gate.** If the sequences are there, we go on. If a weapon has three sequences and everything else is procedural, we stop and talk about that weapon.

### Phase 1 — upload the Lua

For each of the three weapons, the weapon file:

- `addons/<arc9 bo2 pack>/lua/weapons/arc9_bo2_thompson.lua`
- `addons/<arc9 waw pack>/lua/weapons/arc9_waw_m1911.lua`
- `addons/<tfa ins2 pack>/lua/weapons/tfa_ins2_wpn_38revolver.lua`

Plus, if the weapon file starts with `SWEP.Base = "something_other_than_weapon_base"`, the file that base lives in. ARC9 packs sometimes share a per-pack base holding common sounds and animation timing, and the weapon file alone would then be half the answer.

These are text files, a few hundred lines each. From them I get: exact model paths, `ViewModelFOV`, the animation table with sequence names and timings, the sound paths and when in the animation they fire, the hold type, and their stats — which I will read as a sanity check and then ignore, because our balance is M19's.

**If you cannot find them:** they will be inside the `.gma` in `steamapps/workshop/content/4000/<id>/`. GMod ships `gmad.exe` in `bin/` which extracts one.

### Phase 2 — the base learns about animations

Our base currently knows one animation event: it sends `ACT_VM_RELOAD` on a reload and nothing else. It gains a per-weapon animation map — draw, idle, fire, fire-empty, reload, reload-empty, holster — resolved by sequence **name** rather than by index, because indices shift when a model is updated and a name that no longer exists can fail loudly.

The arsenal entry for a gun grows one block. Adding a weapon stays one `Register` call, so D-039 holds.

Sound moves with it: firing sound, dry click, and the reload's foley become data on the same entry instead of the HL2 placeholders they are now.

### Phase 3 — per-weapon data, one gun at a time — **the M1911 and the Thompson are done, see §4c**

The Model 10 was meant to go first — simplest action, cheapest place to expose a bad assumption. The dump decided the order instead: the two guns that came back are the two that are ported, and the revolver waits on `omerta_weapon_dump arc9_doi_sw1917`.

Each gun is: model paths, the sequence map, the sound map, and the balance numbers — which turned out not to be "left alone" but *moved onto the art* wherever the animation's length was defensible as balance, which is what §2 asks for and what makes the playback rate 1.0. The sound map is still empty for both: the dump named sequences, not `.wav` paths.

### Phase 4 — decide what happens to D-044

If all three port cleanly, the external bridge becomes dead weight — a fallback for a case that no longer exists. My recommendation then is to keep the seam (it is small, tested, and is the reason a missing addon is not a crash) and stop using it for these three. Your call, and worth revisiting once it has actually run.

## 6. What this will and will not fix

**Fixes:** period-correct guns that fire, reload and look right; our ammunition rules intact; our damage; holster props pointing at real world models instead of HL2 placeholders; no second weapon framework in the process.

**Does not fix:** the addons still have to be installed — this is a port of *how they are driven*, not of the assets. A server without them still falls back to HL2 placeholders.

**Not included:** ironsights. The base deliberately has no secondary attack yet, and aiming is a feel question the presentation track owns. If the ported animations include a sight pose we can revisit it, but I would rather land firing and reloading first than bundle three things into one change.

## 7. What I need from you, in order

1. **Confirm the addons are on the server** (not just the client) — `omerta_weapons_list` will say.
2. **The `omerta_weapon_dump` output** for all three classes, once I ship it.
3. **The three weapon Lua files**, plus any per-pack base they inherit from.

Nothing else. No models, no textures, no sounds.
