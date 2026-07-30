# Testing Queue

**What this is:** everything built but not yet confirmed working in-engine, in the order worth doing it. Kept current as work lands — when you report results, the statuses here get updated and anything that fails becomes a fix before new work starts.

**Last updated:** 2026-07-30, after the fourteen-item field-report fix pass.
**Headless suite:** 355 checks passing. `luac -p` clean across the tree. 17 modules resolving.

Status key: **☐ untested** · **☑ passed** · **☒ failed** (details inline) · **◐ partly**

---

## 0. Before anything else

| | Check | How |
|---|---|---|
| ☐ | **Server boots clean with 17 modules** | Look for `loaded 17 module(s): … injury, events, death, phone, weapons` and no Lua errors |
| ☐ | **Client boots clean** | Join and check the client console — this has never been confirmed since the module count grew |
| ☐ | **Migrations 12 and 13 apply on MySQL** | **This is the one that matters most.** D-008 makes MySQL the backend of record, and `character_injury`, `bodies`, `injury_events` (12) and `events` (13) have only ever run against SQLite. A DDL problem here is the class of bug that cost us the `key`/`rank` reserved-word incident |

If migrations fail, stop and send me the error — everything below depends on them.

---

## 1. The field-report fixes (2026-07-30) — re-test these first

Your fourteen items, what each turned out to be, and what to check now. Several
shared two root causes: reloading (and bandages, latently) read the inventory
through a broken call that always came back empty, and the server never told
clients which items were equipped — every row streamed as "not worn", which is
why Equip never became Unequip and a worn overcoat looked like nothing.

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **Weapons can be put away** | Draw the revolver, then scroll or press 1 | You switch to bare hands; the gun stays equipped in its slot |
| ☐ | **The new hotbar** | Scroll the wheel or press 1–4 | Four slots down the left — Hands / Primary / Sidearm / Melee — in the UI's own style, fading ~2 s after you choose. The engine's sandbox selector never appears |
| ☐ | **Reloading works** | Carry `ammo.38`, press R | Rounds leave the inventory, the clip fills. This was the OwnerOf bug — bandages had it too and are re-listed in §4 |
| ☐ | **Dropping an equipped weapon empties your hands** | Equip revolver, open inventory, right-click → Drop | The SWEP goes with the item; loaded rounds are refunded to your pockets first |
| ☐ | **Right-click menu replaces the buttons** | Right-click items in the inventory | Equip/Unequip (by state), Use, Split… (stackables above 1), Store (container open), Drop; Take on container rows. No button row anywhere |
| ☐ | **Equip/Unequip actually toggles** | Equip something, look at its row | Row reads "— equipped (Slot)", menu offers Unequip. Was the slot-index bug: the server told every client nothing was equipped |
| ☐ | **Worn overcoat is visible** | Equip the overcoat | Its row reads "— equipped (Outerwear)" and capacity rises |
| ☐ | **Splitting stacks** | Right-click a stack of rounds → Split… | Asks how many; two stacks after. Refuses 0 and the whole stack |
| ☐ | **Dragging actually moves the body** | Take hold, walk | The body comes with you at a real pace. Pull was applied to one ragdoll bone with no allowance for the weight it tows — now mass-compensated |
| ☐ | **Dragging no longer snaps on distance** | Haul a body a full street | The rope settles taut and stays; grip should only break if you genuinely sprint off. A body can now close a gap (catchup 1.35) and the break length grew 210→300 |
| ☐ | **One drag line only** | Take hold of a body | A single line from the crosshair to the grip. The faint second line to the old anchor is gone |
| ☐ | **Text is readable** | Play normally | All HUD text ~20% larger, in Germania One (ships with the gamemode; OFL licence alongside). Tell me if the blackletter flavour fights readability at small sizes — swapping back is one line |
| ☐ | **Stamina lasts longer** | Sprint from full | ~8 s of flat sprint (was ~5.5); jumps cost 10 (was 12). Air behaviour unchanged |
| ☐ | **Inventory on Q** | Press Q on a fresh client | Inventory opens. **Your existing client saved the old F3 default** — run `omerta_inventory_key 27` in the console once (the convar is archived; a new default does not override a saved value) |
| ☐ | **Creation form keyboard flow** | Make a new character | First-name box focused on open; Tab hops first↔last name and wraps |
| ☐ | **C menu: scroll, cancel, hand-off** | Hold C over a body | Wheel moves the selection (and does NOT switch weapons); releasing C runs the highlighted option; looking away closes it without running anything, and the wheel goes back to the hotbar |

## 2. W0 — the weapon foundation

Q-10 ruled and built: custom modular base, one registration per gun. Two reference weapons. Updated from your field report; the failures it found are the fixes in §1.

| | Check | How | Expect |
|---|---|---|---|
| ☐ | The arsenal exists | `omerta_weapons_list` | revolver and thompson, classes `weapon_omerta_*` |
| ☑ | Getting armed | `omerta_item_give weapon.revolver`, equip it | The revolver appears in your hands, **empty** (your report confirms give and equip work) |
| ☒ | Rounds are items | `omerta_item_give ammo.38 12`, press R | **Failed 2026-07-29: reload never found the ammo, even after re-equipping.** Root cause fixed (OwnerOf pair misread); re-test in §1 |
| ☐ | Firing works and is server-real | Shoot a second character | They take damage through M19 — enough hits puts them down, never respawns them |
| ☐ | The round counter is contextual | Draw, fire, then wait ~3 s | Count appears near the stamina bar, then fades away |
| ☐ | Dry fire | Empty the clip, keep pressing | Click sound, "Empty — press R", nothing fires |
| ☐ | Out of ammo | Reload with none carried | "You are out of .38 rounds." |
| ☐ | **The Thompson cannot be pocketed** | `omerta_item_give weapon.thompson` with empty pockets | Refused — no room (bulk 22 vs capacity 20). Equip an overcoat first, then it fits |
| ☐ | Going down disarms | Get put down while armed | Weapon leaves your hands; searching you finds it in your inventory |
| ☐ | Standing up re-arms | Get treated | The equipped gun returns to your hands, still empty |
| ☐ | Rounds are conserved | Load 6, unequip the gun | 6 rounds are back in your inventory |
| ☐ | Disconnect refund | Load a clip, disconnect, rejoin | The rounds are in your inventory, the clip is empty |
| ☐ | Procurement | `omerta_procure` as a family with funds | Revolver $85, Thompson $340 (needs a second approver), ammo boxes |

## 3. M20 — confirmed death and succession (nothing verified yet)

| | Check | How | Expect |
|---|---|---|---|
| ☐ | Self-test | `omerta_death_selftest` | 9 steps, 0 failed |
| ☐ | The act exists and is slow | Put a second character down, hold `C` on the body | **Finish** is last in the menu, takes 7 s |
| ☐ | It is interruptible | Start finishing, walk away | It stops; the target is unharmed |
| ☐ | §4a — a bandage is not immunity | Stabilize someone, then try to Finish them | Still offered, still works |
| ☐ | The event is recorded | `omerta_events` after a kill | One `death.confirmed` row with subject and actor |
| ☐ | Attempts are logged, not just kills | Start and cancel a Finish, then check the audit log | A `death.attempt_failed` entry exists |
| ☐ | §4c — belongings stay | Search the corpse after killing | Their things are still on them |
| ☐ | **§4b — the chair empties** | `omerta_org_seed`, seat a Don, have a Capo online, kill the Don, then `omerta_org_list` | Chair empty; Capo holds authority; Capo **cannot** appoint a successor |

---

## 4. M19 — the fixes from the earlier rounds (unverified)

Most of M19 you have already seen working. These are only the things changed since — minus what your field report answered (dragging moved to §1).

| | Check | How | Expect |
|---|---|---|---|
| ☐ | Jump no longer gives free stamina | Sprint to near-empty, then jump repeatedly | Stamina does **not** recover mid-air; only on landing |
| ☐ | Corpse is draggable | Kill yourself, respawn, walk to your old body | Dot lights up, tooltip shows, you can take hold |
| ☐ | Death camera fades behind black | `omerta_injury_state incapacitated` then `dead` | Hold on head → fade out → fade **in** already top-down → slow 7.5 s climb → fade → text |
| ☐ | Confirm sound on keypress | Press any key on the death screen | Tap plays, words fade, music fades, black holds, creation **revealed** underneath |
| ◐ | Drag line at the crosshair | Take hold of a body | **Your report: the crosshair line works, but a second faint line drew at the feet.** Second line removed; re-test in §1 |
| ☐ | Drag by the part you grabbed | Aim at a hand or foot, take hold | That limb leads; the rest trails |
| ☐ | Blur under the vignette | Bleed out with `injury.bleed_out_seconds` low | Focus softens as the red closes in |
| ☐ | Chat hides on death only | Bleed out, then die | Chat visible while dying, gone once dead |
| ☐ | World audio mutes on death | Die near something noisy | Only trombone and piano audible |
| ☐ | Body tooltip | Look at a body | Their name if you know them, "Unknown" if not |

### Never tested at all

| | Check | How | Expect |
|---|---|---|---|
| ☐ | Stabilizing with a bandage | `omerta_item_give medical.bandage`, use Stabilize on a bleeding character | Bleeding stops, screen stops closing, they stay down. **Had the same empty-pocket bug reloading had — fixed in the same pass, never yet run in-engine** |
| ☐ | Search delay and memory | Search a body | "Searching…" for 4 s the first time; instant on the second search of the same body |
| ☐ | Clinic treatment | Place a `clinic` business, stand at its counter, Treat a downed character | They reach Recovering and stand up |
| ☐ | Bandages are purchasable | `omerta_procure` list | `supply.bandages` present at 1200 |
| ☐ | Recovery penalty | Get treated, then move | Noticeably slower and worse stamina for ~8 min, easing off |

---

## 5. Older, still unconfirmed

| | Check | How |
|---|---|---|
| ☐ | M13 self-test | `omerta_business_selftest` — flagged unverified since M13 and never reported since |
| ☐ | M8 HUD self-test still passes | `omerta_hud_selftest` in a **client** console — M19 added five new HUD elements, W0 two more (round counter, hotbar) |

---

## 6. Known gaps — not bugs, just not built

- **Audio is 43 MB uncompressed.** Four WAVs, all sent to every client on first join. MP3 would take the set to ~6 MB. Local ffmpeg step; no encoder in my environment.
- **Sound licensing** — the three Freesound files need their individual licences checked, and attribution recorded if any is CC-BY. "Cry Me a River" needs a licence or a replacement before release. Pre-release gate, tracked in the roadmap. (Germania One is already covered: OFL, licence file ships next to the TTF.)
- **Corpses accumulate.** Nothing removes them; that is M20's stated boundary and a later milestone's mechanic. Staff can clean up.
- **`omerta_ui_scale` at 1.5** has not been checked against M19's new elements, the new font, or the hotbar.
- **The old F3 keybind lingers on existing clients** — archived convar; each existing client runs `omerta_inventory_key 27` once. Fresh installs get Q.

---

## How to report

Anything at all is useful — "1 and 2 pass, drag by the hand doesn't" is enough. Console output for failures if it is convenient. I will update the statuses here and fix what failed before starting anything new.
