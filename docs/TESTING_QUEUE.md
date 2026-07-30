# Testing Queue

**What this is:** everything built but not yet confirmed working in-engine, in the order worth doing it. Kept current as work lands — when you report results, the statuses here get updated and anything that fails becomes a fix before new work starts.

**Last updated:** 2026-07-30, after the second field report (UI, icons, E-key rework).
**Headless suite:** 356 checks passing. `luac -p` clean across the tree. 17 modules resolving.

Status key: **☐ untested** · **☑ passed** · **☒ failed** (details inline) · **◐ partly**

---

## 0. Before anything else

| | Check | How |
|---|---|---|
| ☐ | **Server boots clean with 17 modules** | Look for `loaded 17 module(s): … injury, events, death, phone, weapons` and no Lua errors |
| ☐ | **Client boots clean** | Join and check the client console — this has never been confirmed since the module count grew |
| ☐ | **Migrations 12 and 13 apply on MySQL** | **This is the one that matters most.** D-008 makes MySQL the backend of record, and the injury/body/event tables have only ever run against SQLite |

If migrations fail, stop and send me the error — everything below depends on them.

---

## 1. The UI and interaction pass (2026-07-30) — re-test first

**Controls changed:** **C** now opens the inventory (it rides the context-menu
bind, so it follows your real key — no console command needed, the old convar
is gone). The old hold-C menu is now on **E**: tap E for the obvious thing,
hold E for the full menu. Your report said tap-E on a body should default to
drag in one line and search in another — **I went with drag** (it was the
dedicated bullet, and search is one wheel-notch away in the held menu); say
the word and it flips.

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **The new inventory table** | Press C | Our own rows — category icon, name, quantity, bulk — dark panels, zebra-free, no GMod list furniture anywhere |
| ☐ | **Icons make sense** | Carry a gun, rounds, an overcoat, food, cash | Gun/ammo/clothes/food/money line art per row; anything odd falls back to the junk icon. (No medical glyph existed in the set — bandages borrow the components icon for now) |
| ☐ | **Right-click works now** | Right-click any row | The menu opens (Equip/Unequip, Use, Split…, Store, Drop / Take). The old list widget was eating the click; the rows are ours now and own the mouse |
| ☐ | **Two loot windows** | Search a body or crate | Your **Pockets** window on the left, the container's own window on the right ("Body" / its label), each its own framed thing |
| ☐ | **Tap E = default action** | Tap E on a body / dropped item / crate | Body: **drag** (tap again to let go). Item: pick up. Crate: opens the loot windows. Tap-E on a *person* deliberately does nothing — introductions stay behind the held menu |
| ☐ | **Hold E = the menu** | Hold E ~0.3 s on a body | Menu appears already populated; wheel moves the selection (and does **not** switch weapons); release runs the highlighted option; looking away cancels, and the wheel goes straight back to the hotbar |
| ☐ | **Hover text no longer overlaps** | Look at a body | Name/"Unknown", then the hint, stacked with real spacing — one owner draws that region now, measured line by line |
| ☐ | **Search progress bar** | Search an unfamiliar body | Thin neutral bar under "Searching…" filling over the 4 s — stamina-bar styling, no red |
| ☐ | **Search rustle** | Search several bodies; cancel one mid-way | A different stretch of the rustle bed each time; goes silent the instant you walk away/cancel |
| ☐ | **"Search (empty)"** | Hold E over an emptied body or crate | The option itself reads "Search (empty)" (best effort — only when the server already has those pockets loaded) |
| ☐ | **Hotbar restyle** | Scroll or press 1–4 | Bigger type, no boxes, no borders; the held item is simply the vivid line, the rest faded |
| ☐ | **Hotbar click** | Scroll with 2+ items; then with only hands | Click sound on every actual switch; silence when there is nothing to switch to |
| ☐ | **Stamina bar is smooth** | Sprint, stop, watch | The bar glides instead of stepping four times a second |
| ☐ | **Blur starts stronger** | `omerta_injury_state incapacitated` | The world is already noticeably soft the moment you are down, worsening from there |
| ☐ | **Readability in bad light** | Stand somewhere bright/busy, check HUD text | Everything world-drawn now carries a soft drop shadow. If it still fights you anywhere, name the spot |

### From the first pass, still unconfirmed

| | Check | How | Expect |
|---|---|---|---|
| ☐ | Reloading finds your ammo | Carry `ammo.38`, press R | Clip fills, rounds leave inventory |
| ☐ | Weapons can be put away | Draw, then scroll/press 1 | Hands out, gun stays equipped |
| ☐ | Dropping an equipped weapon empties hands | Right-click → Drop while drawn | SWEP leaves with the item, clip refunded |
| ☐ | Equip/Unequip toggles, worn coat visible | Equip things, read the rows | "equipped — Slot" tag on the row, menu offers Unequip |
| ☐ | Splitting stacks | Right-click a stack → Split… | Asks how many, two stacks after |
| ☐ | Dragging moves the body and holds | Take hold, haul a street | Real pace, rope settles, grip survives |
| ☐ | One drag line, at the crosshair | Take hold | Single line, no second line at your feet |
| ☐ | Stamina lasts (~8 s sprint) | Sprint from full | Was ~5.5 s |
| ☐ | Creation form keyboard flow | New character | First box focused, Tab cycles the name fields |

## 2. W0 — the weapon foundation

| | Check | How | Expect |
|---|---|---|---|
| ☐ | The arsenal exists | `omerta_weapons_list` | revolver and thompson, classes `weapon_omerta_*` |
| ☑ | Getting armed | `omerta_item_give weapon.revolver`, equip it | The revolver appears in your hands, **empty** |
| ☒ | Rounds are items | press R with ammo carried | **Failed 2026-07-29** (OwnerOf pair misread) — fixed, re-test in §1 |
| ☐ | Firing works and is server-real | Shoot a second character | Damage lands through M19 — enough hits puts them down |
| ☐ | The round counter is contextual | Draw, fire, wait ~3 s | Count appears near the stamina bar, then fades |
| ☐ | Dry fire | Empty the clip, keep pressing | Click, "Empty — press R", nothing fires |
| ☐ | Out of ammo | Reload with none carried | "You are out of .38 rounds." |
| ☐ | **The Thompson cannot be pocketed** | `omerta_item_give weapon.thompson`, empty pockets | Refused (bulk 22 vs 20); fits with an overcoat on |
| ☐ | Going down disarms | Get put down while armed | Weapon leaves the hands; searching finds it in the inventory |
| ☐ | Standing up re-arms | Get treated | The equipped gun returns, still empty |
| ☐ | Rounds are conserved | Load 6, unequip | 6 rounds back in the inventory |
| ☐ | Disconnect refund | Load a clip, disconnect, rejoin | Rounds in inventory, clip empty |
| ☐ | Procurement | `omerta_procure` as a family with funds | Revolver $85, Thompson $340 (second approver), ammo boxes |

## 3. M20 — confirmed death and succession (nothing verified yet)

| | Check | How | Expect |
|---|---|---|---|
| ☐ | Self-test | `omerta_death_selftest` | 9 steps, 0 failed |
| ☐ | The act exists and is slow | Put a second character down, **hold E** on the body | **Finish** is last in the menu, takes 7 s |
| ☐ | It is interruptible | Start finishing, walk away | It stops; the target is unharmed |
| ☐ | §4a — a bandage is not immunity | Stabilize someone, then Finish them | Still offered, still works |
| ☐ | The event is recorded | `omerta_events` after a kill | One `death.confirmed` row with subject and actor |
| ☐ | Attempts are logged | Start and cancel a Finish; check the audit log | A `death.attempt_failed` entry |
| ☐ | §4c — belongings stay | Search the corpse after killing | Their things are still on them |
| ☐ | **§4b — the chair empties** | Seat a Don, Capo online, kill the Don, `omerta_org_list` | Chair empty; Capo holds authority; Capo cannot appoint |

---

## 4. M19 — earlier fixes, still unverified

| | Check | How | Expect |
|---|---|---|---|
| ☐ | Jump gives no free stamina | Sprint to near-empty, jump repeatedly | No recovery mid-air |
| ☐ | Corpse is draggable | Kill yourself, respawn, walk back | Dot lights, tooltip, tap E takes hold |
| ☐ | Death camera fades behind black | `omerta_injury_state incapacitated` then `dead` | Head-hold → fade → top-down slow climb → fade → text |
| ☐ | Confirm sound on keypress | Any key on the death screen | Tap plays, words fade, music fades, creation revealed |
| ☐ | Drag by the part you grabbed | Aim at a hand, take hold | That limb leads |
| ☐ | Chat hides on death only | Bleed out, then die | Visible dying, gone once dead |
| ☐ | World audio mutes on death | Die near noise | Only trombone and piano |
| ☐ | Body tooltip | Look at a body | Name if known, "Unknown" if not |
| ☐ | Stabilizing with a bandage | `omerta_item_give medical.bandage`, Stabilize via held-E menu | Bleeding stops (same empty-pocket bug as reload — fixed, never run in-engine) |
| ☐ | Search memory | Search the same body twice | 4 s first time, instant the second |
| ☐ | Clinic treatment | Treat at a `clinic` counter | They reach Recovering and stand |
| ☐ | Recovery penalty | Get treated, move | Slower for ~8 min, easing off |

---

## 5. Older, still unconfirmed

| | Check | How |
|---|---|---|
| ☐ | M13 self-test | `omerta_business_selftest` |
| ☐ | M8 HUD self-test | `omerta_hud_selftest` in a client console — several elements added since |

---

## 6. Known gaps — not bugs, just not built

- **Audio is ~46 MB uncompressed** (four originals + the new rustle). MP3 conversion is a local ffmpeg step; no encoder in my environment.
- **Sound licensing** — the Freesound files and "Cry Me a River" are a pre-release gate. The two new UI sounds and icons came from you; tell me if they carry terms. Germania One is OFL, licence ships next to the TTF.
- **Corpses accumulate.** M20's stated boundary.
- **`omerta_ui_scale` at 1.5** unchecked against the new font, hotbar, and inventory windows.

---

## How to report

Anything at all is useful — "1 and 2 pass, drag by the hand doesn't" is enough. Console output for failures if it is convenient. I will update the statuses here and fix what failed before starting anything new.
