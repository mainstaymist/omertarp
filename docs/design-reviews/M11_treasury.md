# Design Review — M11: Treasury and Procurement

Status: **APPROVED 2026-07-27 — IMPLEMENTED AND VERIFIED IN-ENGINE** (`omerta_treasury_selftest`; the books-versus-safe discrepancy confirmed live). §4a, §4b and §4c all ruled (a); logged as D-024, D-026 and D-025. See §13.
Milestone: M11 (roadmap Track B). Depends on: M9 (money and items are physical), M10 (something has to own the money). Consumed by: M12 (private lines are bought), M13 (businesses feed the treasury and draw stock from it), M14 (robbery proceeds go somewhere and safes are worth robbing), M15 (marked bills), M17 (seizure), M19 (medical supplies).

> **Three rulings needed** (§4): whether a treasury is a balance or a safe, where purchased goods come from, and how a withdrawal is authorised.

## 1. Purpose

An institution with no money is a title. M11 gives families and the police department something to accumulate, argue over, spend and lose — and gives every later milestone the economic plumbing it assumes exists.

It is also the milestone where a design decision made in M9 either pays off or is quietly abandoned. Money became physical objects because the design wanted it stealable. A treasury that is a number in a table takes that back.

## 2. Responsibilities

**In scope:** the treasury as a place money lives; the append-only ledger recording every movement with actor, approver, reason and resulting balance (Tech §10); the data-driven procurement catalogue; rank-gated spending with limits and approval; organization-owned equipment tagging (M9 left `organization_id` on every item for this); the safe's physical location and its persistence; staff tooling.

**Out of scope:** income (M13's businesses and M14's robberies are where money *comes from*; M11 only holds it); the businesses themselves; territory; bribery and legal services as *gameplay* — the catalogue may list them, but what a bribe does belongs to M17/M18; taxation between institutions; anything that buys a statistic (§10 forbids it, see §7).

## 3. Public API

```lua
-- The treasury
Omerta.Treasury.Of(organizationId)               -- the container it lives in
Omerta.Treasury.Count(organizationId)            -- cash actually present, in cents
Omerta.Treasury.LedgerBalance(organizationId)    -- what the books say
Omerta.Treasury.Deposit(ply, orgId, cents, reason, cb)
Omerta.Treasury.Withdraw(ply, orgId, cents, reason, approverId, cb)
Omerta.Treasury.History(orgId, limit, cb)

-- Procurement (data-driven; each milestone registers its own goods)
Omerta.Procurement.Register(id, {
    name = "Telephone Line", category = "communications",
    price = 25000,                  -- cents
    item = "comms.private_line",    -- what arrives, or nil for a service
    permission = "org.treasury_spend",
    minRank = 4,                    -- optional, above the permission
    onPurchase = function(org, buyer) end,   -- services do their work here
})
Omerta.Procurement.Catalogue(orgId, viewerId)   -- what THIS buyer may order
Omerta.Procurement.Buy(ply, orgId, entryId, quantity, cb)
```

## 4. The Rulings

### 4a. Is a treasury a balance, or is it a safe?

- **(a) The treasury is a container holding physical cash; the ledger is the books beside it** — recommended. The family's money is M9 money: notes and coins in a safe with a location. `Count()` is what is actually in there; `LedgerBalance()` is what the books say. **The two can disagree**, and that disagreement is not a bug — it is embezzlement, or a robbery, or a Don who has been quietly skimming. Spending requires being at the safe or sending somebody who is.
- **(b) A ledger balance only.** Standard, simple, and it makes the family's money unstealable, un-skimmable and unfindable — undoing M9's central decision at the exact point it was supposed to pay off.
- **(c) A balance that is "backed" by cash notionally.** The worst of both: the complexity of physical money with none of the consequences.

**Recommendation: (a).** It needs no new mechanism — M9 already built containers, transactional moves and physical denominations, and M10 already built the permission to open one. The safe is the single most robbable object in the game, and it should be.

The cost, stated plainly: **procurement becomes a place you go**, not a menu you open anywhere. I think that is a feature, and §4b limits how much of a chore it is.

### 4b. Where do purchased goods come from?

Something has to create a Thompson when a family buys one.

- **(a) An abstract supplier: money leaves the safe, goods appear in it, immediately** — recommended for the MVP. One transaction, no travel, no NPC. The catalogue is the fiction of "your people know a guy".
- **(b) A delivery delay** — ordered now, arrives in the safe in N minutes. More texture, and a real strategic cost to arming up mid-crisis. I would build the seam for this and leave it switched off.
- **(c) Physical suppliers at map locations.** The most alive version and a milestone of its own — it needs NPCs, locations, and a relationship system that does not exist.

**Recommendation: (a), with (b)'s seam.** An order goes through a delivery function that currently completes instantly; making it take ten minutes later is a config value, not a rewrite.

### 4c. How is a withdrawal authorised?

Tech §10 requires an **Approver** on every treasury transaction, which implies something more than "the actor had permission".

- **(a) Per-rank spending limits; anything above a rank's limit needs a second person who can cover it** — recommended. An Underboss can spend up to their limit alone and is their own approver on the record. Above it, they need a Don present to approve, and the Don's name goes in the ledger. Limits are configuration, per rank, per institution type.
- **(b) Rank alone gates it, and the approver is always the actor.** Satisfies the column and nothing else; no organizational friction, no two-man rule, no argument about money — which is most of what a treasury is *for*.
- **(c) A full approval queue** — requests pending, approved later, asynchronously. Realistic, and it turns the game into an inbox.

**Recommendation: (a).** It produces the scene the design wants — two people standing at a safe, one of whom has to agree — without an approval inbox, and it fills Tech §10's Approver column honestly.

## 5. Networking

| Message | Direction | Payload |
|---|---|---|
| `treasury.state` | server → client | counted cash, ledger balance, your remaining limit |
| `treasury.action` | client → server | action (uint 3), amount |
| `procure.catalogue` | server → client | one entry you are permitted to order |
| `procure.order` | client → server | entry index, quantity |
| `treasury.history` | server → client | one ledger line |

Everything is sent **only to a member standing at their own safe**, and only what their rank permits: a Soldier is not told what the family is worth. The ledger is history and names characters, so it follows M10's roster precedent — sent to those whose rank earns it, and reading it teaches a name, never a face (D-023).

## 6. Persistence

Migration 9:

```lua
treasury_ledger: id(id), organization_id ref NOT NULL, season_id ref NOT NULL,
                 at timestamp NOT NULL,
                 character_id ref NOT NULL,        -- who moved it
                 approver_character_id ref,        -- who allowed it (§4c)
                 delta money NOT NULL,             -- signed, in cents
                 balance_after money NOT NULL,     -- the books' running total
                 counted_after money,              -- what was actually in the safe
                 reason text(64) NOT NULL,
                 category text(24),
                 note text(160)
                 indexes: (organization_id, at), (season_id), (character_id)

organizations: + safe_map text(64), + safe_x int, + safe_y int, + safe_z int
```

**The ledger is append-only.** There is no update path and no delete path; a correction is another line. A ledger you can edit is not a ledger, and every question M15 and staff will ask about money assumes this.

`counted_after` is what makes §4a's discrepancy visible historically: the books and the safe are recorded side by side at every movement, so "when did the money go missing" is answerable rather than merely noticeable.

The safe's **location** persists on the organization, because a safe that moves to the map origin on restart is not a safe. Placement is a staff action.

## 7. Security Considerations

- **The safe is the authority on how much money exists.** Withdrawals move real M9 stacks through M9's transactional, guarded moves — so the duplication protections built there cover the treasury for free, and there is no second place money can be created.
- **Nothing is bought with a number.** A purchase debits real cash and credits real items in the same transaction; a failure leaves both untouched.
- **Every movement is checked against the actor's rank, their remaining limit, and their physical presence at the safe** — all server-side, all re-derived, none taken from the client.
- **Approval is verified at the moment of spending**: the approver must be present, must hold the permission, and must not be the actor. Their name is written to the ledger and cannot be edited afterwards.
- **The ledger is append-only** (§6), and every line is also an audit row (Tech §23).
- **Tech §10's guardrail is a hard rule here:** procurement never modifies health, damage, speed or armour. It buys *objects*, which have their own consequences. The registry refuses an entry that tries — money buys advantage through what it puts in your hands, never through a number attached to your character.

## 8. Dependencies

M0 (config, net, log), M1 (migration 9, transactions), M2 (audit), M3 (`Omerta.Seasons.WhenReady`, added during M10, is how the treasury finds its season at boot), M9 (containers, physical money, transactional moves, `organization_id` on every item), M10 (the owner, the ladder, the permissions — `TREASURY_VIEW` and `TREASURY_SPEND` already exist on both ladders, unused until now).

## 9. Future Extension Points

- **`Omerta.Procurement.Register` is the seam** for M12's private lines, M13's bar stock, M14's burglary tools, M19's medical supplies.
- The delivery function (§4b) becomes a delay, then a courier, then a supplier NPC, without touching purchase or payment.
- `counted_after` gives M15 the embezzlement investigation for free.
- Multiple safes per institution is a container id change, not a redesign.
- The police "treasury" is the same code — a department budget, with the same ledger and the same approval rules.

## 10. Architecture Rationale and Alternatives Rejected

**Rejected — a balance column on the organization** (§4a). It would be one integer and one afternoon, and it would quietly delete the heist, the skim, and the reason money was made physical in M9.

**Rejected — buying from anywhere.** Remote procurement makes the safe's location meaningless, and its location is what makes it a target.

**Rejected — an editable ledger with corrections in place.** A correction is a new line. Anything else means the books can be made to say anything, which is exactly what they exist to prevent.

**Rejected — procurement that grants statistics** (§7, Tech §10).

**Rejected — an approval queue** (§4c).

## 11. Testing Strategy

- **Headless**: the spending-limit resolver across ranks; the approval rule including "the approver cannot be the actor"; ledger line construction and running-balance arithmetic; catalogue filtering by permission and rank; the purchase planner (cost, quantity, capacity of the safe); migration 9 rendering; the registry's refusal of a stat-granting entry.
- **In-engine** (`omerta_treasury_selftest`): a synthetic organization and safe — deposit, withdraw, over-limit refusal, approved over-limit success, a purchase that lands goods in the safe and cash out of it, a concurrent-spend attempt that must not overdraw, ledger read-back, full cleanup.
- **The lived test**: two players at a safe. One deposits the proceeds of something, the other tries to withdraw more than their rank allows and is refused, then the Don approves it and the ledger names them both. Then take cash out of the safe by hand and watch `Count()` and `LedgerBalance()` disagree — the discrepancy that makes §4a worth building.

## 12. Integration With Existing Systems

`modules/treasury/`, `depends = { "organizations", "inventory", "chat" }`. The safe is an `omerta_container` whose container id is derived from the organization, registered through M9's `RegisterContainer`; opening it uses M9's existing search interaction with an M10 permission check added. Nothing in M0–M10 changes, with one exception: M9's container-open path gains an access predicate, since until now any container could be opened by anyone standing at it.

---

## 13. Implementation Notes (post-implementation)

Implemented as `modules/treasury/`. The headless suite grew from 200 to 221 checks. All three rulings came back as recommended; what follows is what building it changed.

**A third readiness signal, for the same reason as the second.** M10 needed `Omerta.Seasons.WhenReady` because the active season is loaded by a query. The treasury needs `Omerta.Organizations.WhenReady` because a safe belongs to an institution and M10's own startup is *two* queries deep. Waiting a fixed tick would have worked on a fast database and failed on a slow one — the worst kind of bug to own. Both readiness primitives now share the same contract, including firing when the answer is "there is nothing", so a consumer is never left waiting forever.

**M10's ladders had to change for §4c to mean anything.** As shipped, `TREASURY_SPEND` sat only on the Don and the Commissioner — so the two-man rule had nobody to apply to. The Underboss and the Captain now hold spending authority with a $250 ceiling, the Capo and the Lieutenant can view the books, and the top rung declares no ceiling. A Thompson is priced at $340, deliberately above an Underboss's ceiling: arming a crew is an argument between two people rather than a click.

**Limits are declared at their own rung, not inherited.** Permissions accumulate upward; limits must not, or a Don would inherit the Underboss's ceiling and the head of the family could spend less than he can authorise. The test suite pins both behaviours side by side, because the two rules living in the same table is exactly the kind of thing a future reader will "fix".

**The approver is found server-side, never nominated.** The client sends an amount; the server looks for somebody from the same institution standing at the same safe who holds spending authority and is not the person spending. A client cannot name who signed for the money, which is the only version of an approval that means anything.

**Everything is serialised per institution.** A withdrawal is a cash move followed by a ledger line, and two of them interleaving would write a balance computed from a stale read. An in-flight flag per organization prevents it, in the same shape as M9's per-item locks.

**M9 gained a container access predicate**, as §12 anticipated. It ships refusing on error rather than allowing: a provider that throws locks the container, so a typo in somebody else's module can never open a family safe. Ordinary crates keep their old behaviour by having no opinion.

**The `treasury.line` message was nearly shipped unused.** §5 listed it, the client had nowhere to show it, and it carries character names — meaning M6's audit would have flagged an outbound name field that nothing sent. It is now wired properly: the books render above the catalogue for members whose rank earns them, names are gathered before sending so the lines arrive in one burst rather than interleaved by lookup latency, and the message is in the reviewed allowlist alongside M10's roster. Reading the books teaches a name and never a face (D-023).

**Safes persist in their own table** rather than as columns bolted onto `organizations`. Adding columns to an existing table means an `ALTER` in migration 9 that duplicates what migration 8 already creates on a fresh install — two paths that must agree forever. A separate table is one idempotent `CREATE TABLE IF NOT EXISTS` and no divergence.

**A correction I owe the record:** M10's review claimed per-rank permissions were "overridable through the config file without touching Lua". They were not, and are not. Tech §10 does require it. What exists today is a `treasury.limit_multiplier` that scales every ceiling server-wide; the ladders themselves are code. That is a real gap against Tech §10 rather than a design decision, and it belongs on the list — the config layer is scalar-typed and a nested permission table needs a schema type it does not have yet.

**Three defects found on the first in-engine run, all fixed — and two of them were older than this milestone.**

- **The ledger going negative was unsendable.** Money put into a safe by hand (through the container, not through `Deposit`) is never written down, so spending against it drives the books below zero — which is not a corrupt state, it is exactly the discrepancy §4a exists to produce. `treasury.state.ledger` was `uint`, so the first purchase after an unrecorded deposit failed validation and took the whole message with it. Now signed, with the crashing value pinned in a test.
- **`Omerta.Chat.Notice` had a latent crash since M7.** A channel's wire index is assigned by `GetOrdered()`, and `GetChannel()` returned the definition without ensuring that had ever run — so the *first* code path to speak got a nil index and errored inside `net.Send`. Chat itself never hit it because ordinary speech ordered the channels first. M11 was simply the first system to send a notice before anyone had spoken.
- **A failed write left a half-open net message.** `Omerta.Net.Send` called `net.Start` and then validated field by field while writing, so an invalid payload aborted mid-message and the engine discarded the *next, unrelated* message to make room — one bad payload breaking a second system that had done nothing wrong. Validation is now a separate pass that runs before `net.Start`.

The middle two are core-layer faults that M11 only happened to surface; both are now covered by tests in `test_chat.lua` and `test_net.lua` rather than in the treasury's own suite, because that is where they live.

In-engine acceptance (user-side): pull, restart, then **`omerta_treasury_selftest` in the SERVER console** — expect 9/9. Then, standing where you want the family's safe:

```
omerta_treasury_place marino
omerta_money_give 600 <your steamID64>
```

Walk to the safe and run `omerta_treasury` in the client console. Put $500 in, then try to take $400 out as an Underboss — refused, above your ceiling — and watch it succeed with a Don standing beside you. Order a revolver and confirm the cash falls and the gun appears *in the safe*, tagged to the family. Then the test that makes §4a worth building: open the safe as a container (hold **C** → Search), take cash out by hand, and reopen the treasury window — the books and the count now disagree, and it says by how much. `omerta_treasury_books marino` prints the same from the console.

---

**Delivered.** Rulings §4a, §4b and §4c all (a) as recommended; logged as D-024, D-026 and D-025.
