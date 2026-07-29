# Design Review — W0: The Weapon Foundation

Status: **RULED AND IMPLEMENTED 2026-07-28** (Q-10 → D-039: custom modular base, "don't want to have to change the entire gamemode just to add a weapon"). This document records the architecture built under that ruling rather than requesting one.
Piece: the foundation under Track C. Depends on: M9 (a weapon is an item), M11 (a treasury buys it), M19 (its damage lands in the state machine). Consumed by: M14 (robberies armed with it), M15 (casings and serials), M16 (gunshots as alarms), every future gun.

## 1. What the ruling means structurally

"Modular" was the operative word, so it is enforced by shape rather than promised:

- **One `Omerta.Weapons.Register` call is the entire cost of a weapon.** It produces the M9 item (bulk, concealment, equip slot), the generated SWEP class, and every number the seams read. `sh_weapons_arsenal.lua` is the proof: the revolver and the Thompson are ~30-line tables, and gun number three is a third table.
- **All behaviour lives on `weapon_omerta_base`.** Generated classes contain an id and engine fields, nothing else. Changing how shooting works is one file; a new *kind* of weapon (melee, thrown) is a sibling base, not surgery.
- **A caliber is registered once** (`RegisterAmmo`) and any number of weapons chamber it. Rounds are items (D-004); the same box feeds every .45 in the city.

## 2. The load-bearing decisions

**The item is the truth; the SWEP is a projection.** The gun in a hand exists because an inventory row is equipped, exactly as M19's ragdoll exists because an injury row says down. M9 gained two seams for this (`Omerta.ItemEquipped` / `Omerta.ItemUnequipped`, plus `Omerta.CharacterInventoryLoaded` so hands are rebuilt after the rows actually load). Consequences that fall out for free: a weapon is searchable off a body, buyable through procurement, droppable, org-taggable, and **cannot be duplicated by any client behaviour**, because the client never owns anything.

**Rounds are conserved, everywhere.** Weapons are given empty, always. Reloading moves rounds from inventory rows into the clip server-side through M9's transactional `Remove`; stripping (unequip, going down, disconnect) refunds the clip through `Add` with `force = true` — the rounds were on the character's person a moment ago, so refusing them for capacity would delete real objects. There is no path on which ammunition appears or vanishes.

**Going down empties the hands.** The injury hook strips on incapable and re-gives on standing, which means *disarming somebody is putting them on the floor* — the search that follows finds the gun in their inventory, where M19's search already works.

**The engine's ammo pool is never used.** `Ammo = "none"` on every class. The pool is client-visible, server-writable global state with none of M9's guarantees; using it would have been a second, worse inventory.

## 3. The seams later milestones read

| Seam | Reader |
|---|---|
| `Omerta.WeaponFired(ply, defId, wep)` — every server-side shot | M15 witnesses, M16 alarms, heat. The loudest fact in the design, and it costs one hook. |
| `Omerta.Weapons.Serial(instanceId)` — derived, unique, zero storage | M15 evidence. A filed-off serial becomes a metadata flag on the instance, that milestone's business. |
| `Omerta.Weapons.InstanceOf(wep)` | Which physical gun fired — casings, org tags, provenance. |
| `weapons.damage_scale` config | The one lethality knob; the arsenal never gets retuned for balance panic. |
| `RegisterDamageFilter` (M19, already shipped) | Armour, heavy coats, weapon-vs-wound tuning. |

## 4. What surfaced during implementation

- **The sixth load-order incident, caught by the module-graph test before it shipped:** `sh_arsenal.lua` sorts before `sh_weapons.lua`, so the data ran before the registry existed. The file is named `sh_weapons_arsenal.lua` — the fix that cannot regress — and the incident is recorded in the file header.
- **M9 already had the items.** `weapon.revolver` and `weapon.thompson` were registered in M9's catalogue as placeholder objects, with a comment saying firearms were the combat milestone's business. Handed over under the same ids, so every instance already in a pocket or a safe became functional with no migration.
- **M11 already sold them.** The procurement entries moved into the arsenal — a weapon and its supply line in one file, and treasury loads before weapons so it could no longer validate them anyway. The prices moved unchanged: the Thompson still costs more than an Underboss may approve alone (D-025), and the test pinning that moved with it.
- **The round count is contextual, not permanent.** A character can count their loaded rounds — knowledge the fiction grants — but a pinned counter is the omniscient furniture GDD §8 removed. It fades in on deploy/fire/reload and back out.

## 5. Testing

Headless (suite grew 339 → 354): registration produces coherent item+weapon pairs; the Thompson exceeds base carry capacity and cannot be concealed (M9's founding example, now executable); every weapon chambers ammunition that exists; validation refuses duplicates, unknown slots, unregistered calibers; cycle delay, stance spread, cone, and reload arithmetic at the edges; serial uniqueness; the arsenal is buyable at prices real coins pay; the Thompson/Underboss pin.

In-engine (see `TESTING_QUEUE.md` §1): equip → fire → reload → down → search, the full loop.

## 6. What this deliberately is not

No melee base (the crowbar stays an object until M14 wants it swung), no holster worldmodels (Track E's feel pass), no ironsights, no weapon condition/jamming, and only two guns — BA §27's remaining arsenal is data, added when M14's design review knows what each gun is *for*.
