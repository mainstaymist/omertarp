# Design Review — M9: Inventory, Items, Currency and Hunger

Status: **APPROVED 2026-07-27 — IMPLEMENTED** (§4a ruled (a) bulk, §4b ruled (a) denominated with automatic change, §4c ruled (a) a contextual starvation warning; logged as D-020, D-018 and D-019). See §13.
Milestone: M9 (roadmap Track A — the last foundational milestone). Depends on: M0–M8. Consumed by: M11 (treasury buys items), M12 (payphones need quarters), M13 (businesses sell stock), M14 (robbery proceeds are physical), M15 (evidence is items), M17 (seizure), M19 (medical supplies), M20 (searching a body).

> **Three rulings needed** (§4): the capacity model, how granular money is, and the hunger warning question D-016 left open.

## 1. Purpose

Everything physical in Omertà RP becomes real here. Money stops being a number and becomes something you can drop, hide, steal off a corpse, or hand to a bartender. A Thompson stops being an entry in a loadout and becomes an object too big to conceal under a jacket. This is what makes robbery worth committing, searching worth doing, and evidence possible.

It also closes D-016: hunger exists, checked in the inventory, never on the HUD.

## 2. Responsibilities

**In scope:** the item definition registry (data-driven); item instances with persistence (migration 7); capacity and concealment; equipment slots; containers; the operations that move items around, all server-authoritative and validated; physical currency; hunger; the inventory interface; auditing of transfers between characters.

**Out of scope:** seizure by police (M17 — needs authority), searching a person (M19/M18 — needs an incapacitated or arrested target; searching *containers and corpses* is in scope), organisational ownership enforcement (M11 — the column exists, unenforced), evidence collection semantics (M15 — the serial/evidence fields exist, unused), whether others can *see* your visible weapon (M15's descriptor work — concealment is stored now, observed later), vehicles and their trunks (deferred with vehicles).

## 3. Public API

```lua
-- Definitions (data-driven; each milestone registers its own items)
Omerta.Items.Register(id, {
    name = "Thompson", bulk = 22, concealable = false,
    category = "weapon", stackable = false, maxStack = 1,
    slot = "primary",              -- equippable items only
    model = "models/...",          -- world model when dropped
    onUse = function(ply, item) end,
})

-- Inventories (server)
Omerta.Inventory.Get(owner)                       -- character or container
Omerta.Inventory.Add(owner, defId, qty, meta, cb) -- cb(instance, err)
Omerta.Inventory.Remove(instanceId, qty, cb)
Omerta.Inventory.Move(instanceId, toOwner, cb)    -- one place; capacity checked
Omerta.Inventory.Drop(ply, instanceId, cb)        -- becomes a world entity
Omerta.Inventory.Transfer(fromPly, toPly, instanceId, cb)  -- audited
Omerta.Inventory.Equip(ply, instanceId, cb) / Unequip(...)
Omerta.Inventory.BulkUsed(owner) / BulkLimit(owner)

-- Money
Omerta.Money.Give(owner, cents, cb)      -- composes denominations
Omerta.Money.Take(owner, cents, cb)      -- decomposes, makes change
Omerta.Money.Count(owner)                -- total in cents
Omerta.Money.CountCoins(owner, denom)    -- what M12's payphone asks

-- Hunger
Omerta.Hunger.Get(ply)  -- 0..1
Omerta.Hunger.Feed(ply, amount)
```

## 4. The Rulings

### 4a. Capacity model — bulk, or a grid?

Tech §9 leaves this open ("slot/grid or capacity-based").

- **(a) Bulk/capacity** — recommended. Each item has a `bulk`; your carrying capacity is a number, modified by clothing and bags. A Thompson is bulk 22; a coat gives you 30. Simple to build, simple to reason about, and it achieves the design's actual goal — big things are hard to carry and impossible to hide.
- **(b) Spatial grid** (Tarkov-style). More tactile and genuinely more immersive; but it is a large UI investment in a milestone already carrying items, money, hunger, containers and persistence, and packing puzzles pull attention toward inventory management and away from people.

**Recommendation: (a).** The grid can be layered on later over the same data model if it proves worth it — bulk is the honest MVP.

### 4b. How granular is money?

D-003 requires players to physically possess **quarters** to feed a payphone; D-004 requires small amounts to matter. But making players count exact change in every shop is precisely the busywork the Brainstorm warns against.

- **(a) Denominated stacks with automatic change** — recommended. Cash exists as stacks of specific denominations (5¢, 10¢, 25¢, $1, $5, $20, $100). Shops, treasuries and hand-to-hand payments compose and decompose automatically — you are never asked to count. The payphone is the one place a *specific* denomination matters, exactly as D-003 intends, and "have you got a quarter?" becomes a real question.
- **(b) A single abstract cash value.** Simplest, but it dissolves D-003's payphone entirely and makes marked-bill evidence meaningless.
- **(c) Fully manual denominations.** Maximum realism, and it would make buying a beer a chore.

**Recommendation: (a).**

### 4c. The hunger warning D-016 left open

Hunger lives in the inventory. But with no passive display, a player is degraded by something they were given no chance to notice.

- **(a) A contextual warning when genuinely starving** — recommended. Silent while you are merely hungry; when starvation actually begins to cost you, a warning fades in exactly as stamina and injury do. This keeps hunger out of the HUD in normal play — your ruling's intent — while never punishing someone invisibly.
- **(b) Strictly inventory-only.** Purest reading of D-016; a player who forgets to check simply suffers.

**Recommendation: (a)**, as the natural extension of the contextual rule rather than a breach of it.

Hunger's effects, in any case: slow (a full stomach lasts hours of play), costing stamina recovery when hungry and movement speed when starving. **It never kills** — permanent death is a deliberate act (GDD §19.2).

## 5. Networking

| Message | Direction | Payload |
|---|---|---|
| `inventory.state` | server → client | the player's own inventory (paged) |
| `inventory.open` | client → server | container entity |
| `inventory.container` | server → client | contents of a container they may see |
| `inventory.action` | client → server | action (uint 4), instance id, target |
| `inventory.hunger` | server → client | value (uint 7) — private, like stamina |

A client is told **its own** inventory and any container it has legitimately opened, never anyone else's. Hunger follows M8's stamina precedent: a private message, never a networked variable, since an NW var would publish who is starving.

## 6. Persistence

Migration 7:

```lua
items:  id(id), def_id text(48) NOT NULL, season_id ref NOT NULL,
        owner_type text(12) NOT NULL,   -- character | container | world
        owner_id ref, quantity int NOT NULL DEFAULT 1,
        equipped_slot text(16),
        serial text(32),                -- evidence identity (M15)
        organization_id ref,            -- family property (M11, unenforced here)
        metadata json, created_at timestamp NOT NULL
        indexes: (owner_type, owner_id), (season_id), (serial)

character_needs: character_id ref PRIMARY, hunger int NOT NULL DEFAULT 100,
                 updated_at timestamp NOT NULL
```

Items are season-scoped and vanish with the wipe (GDD §3). Definitions live in code, not the database: an item *definition* is behaviour and balance, which belongs in version control; only instances persist.

**Transactional moves.** Every operation that changes ownership runs in one `Omerta.DB.Transaction` — the M1 facility built for exactly this. A move that credits without debiting would duplicate items, and duplication is the one economic bug that cannot be walked back.

## 7. Security Considerations

- **The client names an instance id and an action; the server decides everything else** — ownership, distance, capacity, whether the action exists. A client asking to move an item it does not own simply fails.
- **Duplication is structurally prevented**: ownership changes are transactional and every instance has exactly one owner row.
- **Capacity is enforced server-side** before any write.
- **Transfers between characters are audited** (Tech §23), which is what makes "where did that gun come from" answerable later.
- **Money cannot be conjured**: `Give`/`Take` compose and decompose real instances, and every economic source (M11 treasury, M13 sales, M14 proceeds) goes through them.
- Dropped items become world entities with a server-owned instance id; picking one up validates the id rather than trusting the entity.

## 8. Dependencies

M0 (net, config, log), M1 (migration 7, transactions), M2 (audit), M3 (season scoping), M4 (characters own inventories), M5 (interaction registers Search/Pick Up), M8 (the inventory panel is a HUD element; hunger uses the stamina precedent).

## 9. Future Extension Points

- **`Omerta.Items.Register` is the seam** every later milestone uses: M11 registers procurement goods, M12 the payphone's coin requirement, M13 bar stock, M15 evidence items, M19 medical supplies.
- `serial` and `organization_id` exist now, unenforced, so M15 and M11 add meaning without a migration.
- Container support generalises to world containers (M13's safes, M14's registers) and later vehicle trunks.
- Concealment is stored per item so M15 can decide what a witness saw.
- A spatial grid could later replace the bulk display without touching the data model (§4a).

## 10. Architecture Rationale and Alternatives Rejected

**Rejected — item definitions in the database.** Definitions are behaviour and balance; they belong in version control where they can be reviewed and rolled back, not edited live.

**Rejected — inventories as a JSON blob on the character.** Unqueryable ("who is holding a Thompson?"), and it makes an item's location ambiguous when two systems touch it at once. One row per instance, one owner, transactional moves.

**Rejected — trusting client-side capacity checks.** They are a courtesy for responsiveness; the server recomputes.

**Rejected — a grid at MVP** (§4a) and **abstract money** (§4b).

## 11. Testing Strategy

- **Headless**: bulk accounting including the boundary; stackability and stack-splitting; the money composer/decomposer across every denomination (does £-shaped change work when you only have quarters?); hunger decay maths; definition-registry validation; the operation permission table; migration 7 rendering; transactional move behaviour against the mock driver, including a failed move leaving *nothing* changed.
- **In-engine** (`omerta_inventory_selftest`): synthetic character, add/move/drop/pick up/transfer round-trip, capacity refusal, money compose-and-make-change, hunger persistence, full cleanup.
- **The lived test**: pick something up, open the inventory, drop it, see it in the world, have a second player take it — and confirm the transfer appears in the audit log.

## 12. Integration With Existing Systems

`modules/inventory/`, `depends = { "characters", "interaction", "hud" }`. Registers "Pick Up" and "Search Container" with M5's interaction framework, and the inventory panel with M8's HUD controller. Hunger's element registers alongside stamina. Nothing in M0–M8 changes.

---

## 13. Implementation Notes (post-implementation)

Implemented as `modules/inventory/` plus two entities. The headless suite grew from 140 to 175 checks. All three rulings came back as recommended, so the design above stands; what follows is what building it changed.

**Schema additions the review did not have.** `items` gained `pos_x/pos_y/pos_z`. Without them a dropped item is a row owned by `world` with nowhere to be, so a restart would silently destroy it — and "drop it and log off" would be a way to destroy evidence that nobody could ever discover. World items are now restored to the floor when the database comes up.

**Bulk is integer arithmetic.** Definitions declare bulk as a decimal (a quarter is 0.02, a Thompson is 22), but it is carried internally as hundredths and only divided for display. Summing 0.02 two hundred times in floating point does not reliably compare against a limit, and "your inventory is full" is not a place for a rounding error.

**Exact change needed more than greedy.** Greedy largest-first is optimal for *minting* an amount, because the denomination set is canonical — but not for *paying* one from a limited wallet: with a quarter and three dimes it takes the quarter and then cannot find a nickel, when three dimes were exact. Payment therefore tries a bounded dynamic program first (up to $200, in 5¢ units) and falls back to greedy-plus-cheapest-overshoot above that. Both halves are pure and both are tested, including a loop that pays every amount from 5¢ to $5 and asserts the net cost is exact each time.

**Change and payment are one transaction, planned against the future.** The change a player receives is planned against their wallet *as it will be after paying*, not as it is now. Planning against the current wallet let the credit try to top up a stack the payment was about to empty, which is one row needing two contradicting guarded `UPDATE`s. Everything then goes through `Omerta.DB.Transaction` as a single unit.

**Duplication is prevented twice over.** Every move is a guarded `UPDATE` naming the owner it expects to move *from*, so the same request arriving twice moves the item once; and every operation takes an in-memory lock on the instance for the duration of its round-trip, so two requests naming one item cannot interleave. The self-test asserts the second move of an already-moved item is refused. The guard assumes one game server owns a season's items — the same assumption characters and identity knowledge already make, now written down.

**The driver has no affected-row count**, so a guarded move confirms itself with a read-back rather than trusting that the `UPDATE` matched. It is one extra query on an operation that is not hot.

**An amendment to M8, which the review said would not change.** Hunger became the second system with an opinion about movement speed, and two systems calling `SetRunSpeed` is how one silently undoes the other. `sv_stamina.lua` is now the single owner of movement speed and exposes `RegisterSpeedModifier` / `RegisterRegenModifier`; exhaustion was refactored onto the same mechanism. `cl_hud.lua` gained `RegisterInteractableClass`, which is the extension point its own D-017 comment anticipated for exactly this milestone.

**The inventory is a VGUI frame, not a HUD element** — a deliberate departure from §12. It takes input, and the empty-screen rule is about what is on screen when the player has not asked for anything; the character-creation window is the same shape and M8 explicitly left it alone. What *is* registered with M8's controller is the starvation warning (D-019). F3 opens the window; `omerta_inventory` does the same from the console.

**Corpse searching is deferred, not delivered.** §2 put "searching containers and corpses" in scope. Containers shipped — the owner type, the operations, a world container entity and an admin command to place one. Corpses did not: there is no death system until M19/M20, so there is no corpse to search and no owner to map one to. Building it now would mean inventing the death model M19 exists to design.

**Items are addressed by entity in the world, never by id.** A client is told the instance ids of things it is holding and of things in a container it has opened, and nothing else. Picking something up names the entity; the server resolves it to a row. Reaching into a container re-checks range on every action, not just when it was opened, so walking away closes the hand as well as the window.

**`chat` is a declared dependency.** Every refusal the server issues ("there is no room for that") reaches the player through `Omerta.Chat.Notice`, because there is no error box to put it in. That is a real edge in the module graph and is declared as one.

**Three defects found on the first in-engine run, all fixed:**

- **Both entities derived from `base_gmodentity`**, which is defined by SANDBOX — and this gamemode derives `base`. The classes failed to load entirely ("Trying to derive entity omerta_item from non existant entity base_gmodentity"), which would have made dropping and containers silently do nothing. Now `base_anim`, with a lint check so it cannot come back.
- **The self-test asserted 42 reads as hungry.** It does not: `HUNGRY_BELOW` is 40, so 42 is fed. The code was right and the expectation was wrong; the step now uses 30 and pins the boundary on both sides.
- **F3 did nothing.** `GM:ShowSpare1` only fires if the player has F3 bound to `gm_showspare1`, which a fresh install frequently does not. The key is now read directly through `PlayerButtonDown` against `omerta_inventory_key` (default F3), guarded so it cannot fire while typing or in the menu.

In-engine acceptance (user-side): pull, restart, then run **`omerta_inventory_selftest` in the SERVER console** — expect 10/10. Then, with a character loaded:

```
omerta_money_give 12.50
omerta_item_give food.sandwich 2
omerta_item_give clothing.overcoat
omerta_item_give weapon.thompson      -- refused: no room without the coat
omerta_container_spawn 1 100
```

Press **F3** for the inventory. Check the cash total reads $12.50, equip the coat and watch the capacity line grow, then give yourself the Thompson again and see it fit. Drop something and watch it land in the world; walk over it for the dot; pick it up. Search the crate, store something, walk away, and confirm you can no longer take it back. `omerta_inventory_dump` prints the same state to the console.

---

**Delivered.** Rulings §4a (a), §4b (a) and §4c (a) as recommended; logged as D-020, D-018 and D-019.
