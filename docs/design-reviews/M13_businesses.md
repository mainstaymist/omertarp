# Design Review — M13: Businesses and the Speakeasy

Status: **AWAITING APPROVAL — no implementation until approved.**
Milestone: M13 (roadmap Track B). Depends on: M9 (stock and money are objects), M10 (ownership), M11 (the till is collected into a treasury), M12 (a business has a line). Consumed by: M14 (a store worth robbing, and a place to plan it), M15 (the bar is where witnesses are), M16/M17 (premises to raid), M21 (the newspaper is picked up somewhere).

> **Three rulings needed** (§4): Q-12's offline asset protection, where a business's money actually comes from, and what feeds the rumour mill.

## 1. Purpose

Every system built so far needs somewhere to happen. Recruitment needs a back room, a payphone needs a bar to stand in, a treasury needs premises, and the entire information design needs a place where people who do not know each other end up in the same room.

M13 builds that place. It is the first milestone whose output is *somewhere to be* rather than something to do, and the speakeasy is the one that has to work: GDD §11 lists seven business types, and six of them are content once the seventh is a framework.

## 2. Responsibilities

**In scope:** the business as an owned, located, named thing (Tech §11); ownership by an organization *or* an independent character; a staff roster with roles; the till and the stock room as M9 containers; selling stock to a customer; access control following ownership; opening and closing; the rumour pool and the barman who serves it; the newspaper spawn point and surveillance points as declared locations; Q-12's protection rule (§4a).

**Out of scope:** gambling (GDD §11 calls it optional; it is a mechanic of its own and not the one this milestone is for); the other six business types as *content* — the framework takes them, but a funeral home means nothing until there are bodies (M19/M20); robbery (M14 — this milestone builds the thing worth robbing); the newspaper itself (M21 — M13 declares where it is picked up); heat, and police raids (M16/M17).

## 3. Public API

```lua
-- Types are definitions in code, like items and institutions
Omerta.Business.DefineType(key, {
    name = "Speakeasy", model = "...",
    services = { "bar" },              -- what it can do
    tillCapacity = 400, stockCapacity = 1200,
})

-- Instances
Omerta.Business.Get(id) / AtPosition(pos)
Omerta.Business.OwnerOf(businessId)          -- organization or character
Omerta.Business.IsStaff(businessId, characterId)
Omerta.Business.Hire(actorPly, businessId, targetPly, role, cb)
Omerta.Business.SetOpen(ply, businessId, open, cb)

-- Trade
Omerta.Business.Menu(businessId)             -- what is for sale, from stock
Omerta.Business.Sell(customerPly, businessId, defId, quantity, cb)
Omerta.Business.CollectTill(ply, businessId, cb)   -- into a treasury or a pocket

-- Rumours
Omerta.Rumours.Add(text, source, opts, cb)
Omerta.Rumours.Draw(characterId)             -- one the barman will tell you
Omerta.Rumours.Plant(ply, businessId, text, cb)
```

## 4. The Rulings

### 4a. Q-12 — can a family's premises be emptied while everyone is offline?

This is the question the whole milestone hangs on, and M11 made it urgent: a treasury is now physical cash in a container with a location. If that can be taken at four in the morning, a season is decided by who sleeps least.

- **(a) Premises are live only while somebody from the owning side is online** — recommended. Not *present* — **online**. Force entry into an owned business or headquarters requires at least one member of the owning organization (or the owning independent) to be connected. A family with nobody logged in cannot be robbed; a family with three people logged in is a target whether or not any of them is standing in the room.
- **(b) Always robbable.** Honest to the fiction and ruinous in practice: the correct strategy becomes playing at unpopular hours, and the game punishes having a life.
- **(c) Time-locked vulnerability** — premises become progressively raidable the longer they are unattended. Sounds fair, and it means the safest thing a family can do is have somebody idle in the back room forever.

**Recommendation: (a).** It rewards presence instead of punishing absence, and it puts a person on the other end of every raid — which is the point of building a social game. The police warrant path (M17) is deliberately exempt: an institution with authority can enter regardless, because that is what a warrant *is*.

The honest cost: a family that logs off with the take uncollected is safe. That is a small exploit and the right trade against the alternative.

### 4b. Where does a business's money come from?

- **(a) Sales to players, plus a small trickle only while the place is open AND staffed by a real person** — recommended. The bar earns because somebody is tending it. An unstaffed business earns nothing at all; a staffed one earns from customers and a little from the room. This makes "somebody is behind the bar" a job worth doing, which is exactly the role GDD §4.3 promises independents and never explains how to fill.
- **(b) Sales to players only.** Purest, and in a thirty-player city a bar is empty most of the time — so owning one is a liability and nobody does.
- **(c) Passive income over time.** The idle-game money printer BA §13 warns against, and it makes premises an investment rather than a place.

**Recommendation: (a).** The trickle is small enough that it never beats a real customer, and it exists to make staffing worthwhile rather than to be a living.

**The till is not a balance** (D-024's logic, applied a second time). A business's takings are physical cash sitting in a container on the premises, and somebody has to physically **collect** it and carry it to a treasury. That errand is the most robbable moment in the economy, and it should be.

### 4c. What feeds the rumour mill?

Tech §11 lists a rumour NPC and does not say where rumours come from.

- **(a) Real events only.** The seam is right and the barman has nothing to say until M14 and M15 exist to feed him — a landmark feature that is empty for three milestones.
- **(b) Real events, plus rumours players pay to plant** — recommended. The pool takes entries from the event system (a seam, filled by M14/M15) *and* from anybody who buys the barman a drink and tells him something. **The NPC never distinguishes them**, which is the entire point: a rumour you hear is not evidence, and disinformation becomes something you can purchase.
- **(c) Hand-authored flavour text.** Atmosphere with no consequences, and players learn to ignore it within a day.

**Recommendation: (b).** Planted rumours cost money, expire, and are audited — so staff can always answer "who started that". Nothing else about them is trustworthy, deliberately.

## 5. Networking

| Message | Direction | Payload |
|---|---|---|
| `business.state` | server → client | the business you are standing in: open, your role, till (staff only) |
| `business.menu` | server → client | one item for sale, with its price |
| `business.buy` | client → server | item index, quantity |
| `business.action` | client → server | open/close, collect the till, hire |
| `rumour.heard` | server → client | one line of rumour text |

A customer is told **what is for sale and nothing else** — not the takings, not the stock levels, not the staff roster. Those go to staff only, and ownership is re-checked server-side on every one.

## 6. Persistence

Migration 11:

```lua
businesses: id(id), season_id ref NOT NULL, type_key text(32) NOT NULL,
            name text(64) NOT NULL,
            owner_organization_id ref, owner_character_id ref,
            map_name text(64) NOT NULL, pos_x int, pos_y int, pos_z int,
            is_open bool NOT NULL DEFAULT 0, created_at timestamp NOT NULL
            indexes: (season_id), (owner_organization_id)

business_staff: business_id ref NOT NULL, character_id ref NOT NULL,
                role text(16) NOT NULL, hired_at timestamp NOT NULL,
                primary: (business_id, character_id)

rumours: id(id), season_id ref NOT NULL, text text(240) NOT NULL,
         source text(16) NOT NULL,          -- event | planted
         planted_by_character_id ref, business_id ref,
         created_at timestamp NOT NULL, expires_at timestamp NOT NULL
         indexes: (season_id, expires_at)
```

**No ledger table.** A business's till is an M9 container and its earnings become a treasury line the moment somebody collects them (§4b) — so Tech §11's "income/expense ledger" is satisfied by M11's books rather than by a second, parallel set that could disagree with them.

Exactly one owner column is populated: an organization or a character, never both. A constraint the code enforces and the self-test asserts, because "who owns this" having two answers is how access control quietly stops working.

## 7. Security Considerations

- **Access follows ownership, re-derived server-side.** M11's container access predicate already exists; the till and the stock room register through it. A customer standing at the bar can open neither.
- **Selling is server-priced.** The client sends an item index and a quantity; the server looks up the price, checks the stock actually exists, takes the customer's money through M9's transactional path and puts the goods in their hands. A client cannot name a price.
- **The offline rule is checked at the point of force** (§4a), not at the point of looking. You can always *see* a family's front door.
- **Planted rumours are audited with their author** (Tech §23) even though nobody in-game can tell a planted rumour from a real one. Staff must be able to answer "who started that", because the answer to that question is occasionally "somebody breaking a rule".
- **Rumour text is sanitised through M7's path** and length-capped: it is player-authored text that other players will read, which is the same surface chat is.
- **Hiring cannot escalate.** Staff roles are not organization ranks and grant nothing outside the premises.

## 8. Dependencies

M0 (config, net, log), M1 (migration 11), M2 (audit), M3 (`Seasons.WhenReady`), M9 (stock, till, and the container access seam), M10 (`Organizations.WhenReady`, ownership, and the online check §4a needs), M11 (collections land in the treasury; the placement helper), M12 (a business may hold a private line).

## 9. Future Extension Points

- **`Omerta.Business.DefineType` is the seam** for GDD §11's other six businesses: a clinic is a type with a different service list, and M19 fills it in.
- **`Omerta.Rumours.Add`** is what M14's events and M15's witnesses call; neither needs to know a barman exists.
- Surveillance points and the newspaper spawn are declared per type now, and read by M15 and M21 later.
- The till is a container, so M14's robbery is M9's existing move operations with a crime attached.
- `is_open` is the hook heat and police pressure (M16) will read.

## 10. Architecture Rationale and Alternatives Rejected

**Rejected — a per-business ledger table.** Two sets of books that can disagree is worse than one (§6). Collections write M11's ledger, which is already append-only and already audited.

**Rejected — a till as a balance.** Same argument as D-024, and it would make the collection errand — the best robbery target in the game — disappear.

**Rejected — passive income** (§4b) and **always-robbable premises** (§4a).

**Rejected — staff roles as organization ranks.** A bartender is not a soldier. Conflating them would leak business staffing into M10's permission model and let hiring become promotion.

**Rejected — a rumour system that marks rumours as true.** A rumour you can verify is a fact, and the design already has facts.

## 11. Testing Strategy

- **Headless**: the ownership resolver including the exactly-one-owner rule; the access predicate across owner / staff / customer / stranger; pricing and stock arithmetic; the offline-protection rule as a pure function of the owning side's connected members; rumour selection and expiry; business type validation; migration 11 rendering.
- **In-engine** (`omerta_business_selftest`): a synthetic speakeasy — stock it, sell a drink to a synthetic customer, confirm the money lands in the till and the goods in their hands, collect the till into a treasury and see the line appear in M11's books, plant a rumour and draw it back, full cleanup.
- **The lived test**: two players. One tends the bar, the other buys a drink; the takings appear in the till and nowhere else. Then collect them, walk to the safe, and watch M11's ledger record the deposit. Then log the owner out and confirm the premises cannot be forced.

## 12. Integration With Existing Systems

`modules/business/`, `depends = { "organizations", "treasury", "inventory", "chat" }`. Businesses are placed by staff using M11's placement helper; the till and stock room are M9 containers registered through M11's access predicate; collecting is an M11 deposit with a `business` category. M12's private line gains a business owner as well as an organization one. Nothing in M0–M12 changes except that addition.

---

**Requesting approval to implement M13 as specified**, with rulings on §4a (Q-12 offline protection — recommend premises live only while the owning side is online), §4b (income — recommend sales plus a staffed-only trickle, with a physical till that must be collected), and §4c (rumours — recommend real events plus paid plants, indistinguishable to the listener).
