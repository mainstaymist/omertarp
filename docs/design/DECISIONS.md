# Omertà RP — Decision Log

Canonical record of project-lead rulings. Entries here override all other documents. Each decision lists the documents it modifies; those documents are amended in place with a version bump, but this log remains the authoritative history.

Status meanings:

- **DECIDED** — final ruling by the project lead.
- **RECOMMENDED** — engineering recommendation delivered, awaiting project-lead confirmation.
- **OPEN** — identified decision point, no ruling yet (tracked in `docs/review/01_project_review.md` §6).

---

## D-001 — Canonical project name (DECIDED, 2026-07-26)

The project is named **Omertà RP**. All documentation, code identifiers, and user-facing text use this name. The gamemode folder is `omertarp`. The working title "Mafia RP" in earlier documents is retired.

**Affects:** all documents; GDD §1; Tech title.

## D-002 — Setting and time period (DECIDED, 2026-07-26)

The game is **not locked to a strict historical period**. The world has a timeless "classic organized crime" atmosphere inspired by the early-to-mid 20th century — classic architecture, black-and-white newspapers, speakeasies, Tommy guns, revolvers, trench coats — while modern technology is intentionally omitted or simplified where it conflicts with the design. This is an artistic direction, not historical accuracy.

**Rationale:** resolves the era incoherence identified in the review (period speakeasies vs. modern cell phones) without imposing historical-research burden on every asset and system.

**Affects:** GDD §1.1 (new); Tech §1; content workstream in the roadmap.

## D-003 — Telephony model: payphones and private landlines (DECIDED, 2026-07-26)

Personal cell phones are **removed from the design**. They are replaced by:

- **Public payphones** placed throughout the city. Making a call requires inserting quarters, and the caller must keep feeding quarters to keep the call active. Players must physically possess quarters. Pricing reflects historical purchasing power, not modern inflation.
- **Private telephones** that families and businesses may purchase for locations they own or control (family headquarters, businesses, apartments, safehouses). Private phones do not consume coins but are fixed to their location.

Phones remain physical world objects, never abstract menus.

**Rationale:** reinforces D-002; makes communication a matter of place and planning (who controls which phone, who might be overheard, who watches the payphone); makes coins meaningful (D-004); removes the always-available private channel that personal cells would have created.

**Affects:** GDD §7.2 (rewritten); Tech §7 (rewritten, PhoneService → TelephonyService), Tech §2 Character, Tech §24 Phase 2; roadmap milestone M12.

## D-004 — Currency (DECIDED, 2026-07-26)

Currency is **USD**, with **historical purchasing power as inspiration** rather than modern values. Small amounts of money must be meaningful: a quarter should feel valuable. Coins exist as physical inventory items at minimum (required by D-003 payphones).

**Engineering recommendation attached (RECOMMENDED):** extend physicality to all cash — denominated coin/bill items in inventories, safes, and registers, with bank/ledger balances as the only abstract money. This matches the no-money-HUD rule, enables marked-currency evidence, physical bail payments, and robbery loot as real objects. Awaiting confirmation before the economy design review.

**Affects:** GDD §1.2 (new); Tech §1, §10; roadmap milestones M9, M11.

## D-005 — Asset policy: gameplay before art (DECIDED, 2026-07-26)

1. Use existing Garry's Mod / Source Engine props wherever possible.
2. Where no suitable prop exists, use a reasonable placeholder.
3. Custom assets are produced only after the gameplay they serve is finalized.

**Affects:** Tech §1; roadmap content workstream; every milestone's definition of done (placeholder art is acceptable).

---

## D-006 — Dual-backend verification is a standing requirement (DECIDED, 2026-07-27)

Both database backends are available in the project lead's environment (MySQL/MariaDB with the `mysqloo` binary module installed). Therefore the M1 acceptance bar — and a standing requirement for every later milestone that persists data — is that the **identical test suite passes against both backends unchanged**, verified by flipping `db.backend` and re-running the in-engine self-test.

**Rationale:** the "zero gameplay code changes when switching backends" requirement is only meaningfully enforced if both paths are actually exercised. A MySQL path that is written but never run will drift.

**Affects:** every milestone's definition of done from M1 onward; `docs/design-reviews/M1_database.md` §11.

## D-008 — MySQL/MariaDB is the backend of record (DECIDED, 2026-07-27; supersedes D-006)

SQLite support is deprioritized: **MySQL/MariaDB is the sole supported and in-engine-verified backend.** The M1 MariaDB self-test passed 10/10; no SQLite in-engine verification is required, now or per-milestone.

Scope of the decision:
- The SQLite driver and the abstraction layer **stay in the tree**: the code exists, is headless-tested, is useful for development without a MySQL server, and keeping it makes this decision cheaply reversible. It carries no support guarantee and no in-engine acceptance bar.
- Headless tests continue to exercise both dialects (they cost nothing and keep the abstraction boundary honest).
- Documentation and defaults may continue to name `sqlite` as the zero-setup development default; production guidance is MySQL/MariaDB.

**Affects:** D-006 (superseded); M1 §11/§13 acceptance criteria; every future data milestone's definition of done (MySQL-only verification).

## D-007 — Repository history stays on one branch (DECIDED, 2026-07-27)

Development continues on the single existing branch rather than adopting a `main` + per-milestone pull-request workflow. No pull requests are opened unless explicitly requested.

## D-009 — Seasonal allegiance is a track commitment with a fixed transition matrix (DECIDED, 2026-07-27)

Resolves Q-2. The per-season path (criminal / police / independent) is a track commitment, not a faction assignment. Permitted transitions, server-enforced and audited: initial choice of any path (police at season start only); independent → criminal via family recruitment (one-way); police → independent via resignation or expulsion (one-way). Cross-side transitions (criminal ↔ police, ex-cop → family) never occur within a season — they would launder one side's accumulated knowledge into the other. Replacement characters after death inherit the account's current track; the new character starts unaffiliated. Informant and corrupt-officer states are covert overlays, never path changes.

**Affects:** GDD §3/§4 (to be amended when M10 lands); `docs/design-reviews/M3_seasons.md` §4a; M4 creation flow; M10 recruitment/department flows.

## D-010 — At season end, all living characters retire (DECIDED, 2026-07-27)

Resolves Q-4. Ending a season automatically retires every living character ("leaves the city"; status `retired`, archive-eligible). Only account-level persistence (cosmetics, titles, career stats) crosses season boundaries; every player creates a fresh character each season.

**Affects:** `docs/design-reviews/M3_seasons.md` §4b; M4 (implements the retirement listener); M22/M23 (archive records).

---

## D-033 — Objects name themselves; people never do (DECIDED, 2026-07-28)

The interaction indicator (D-017) now carries a short label naming what is under the player's gaze. What a label may say is bounded by a single rule: **it repeats only what the object itself would tell a stranger standing in front of it**, and it is the object that decides, not the HUD.

What that yields in practice:

- **A dropped item** names itself and its stack size. Both were already on the wire, because the model on the floor gives them away regardless.
- **A container reads "Crate" and nothing more** — including a family's safe and a bar's stock room. Containers carry private labels ("Rossi's till", "the Marino safe") which go to whoever is allowed to open them and never onto the entity.
- **A business counter shows its public name and its kind.** A place nobody can name is a place nobody can be sent to; Tech §11 grants businesses a public name for exactly that reason, and a shopfront is legible from the pavement. This is the one genuine widening: the name previously reached a client only when they walked up and used the counter, and now reaches anyone who can see it. That matches what a sign does.
- **A payphone shows its number; a private line shows nothing.** D-027's asymmetry made structural: the number is painted on the public box, and a private number travels only by being told. The rule lives in one pure function (`Omerta.Phone.PublicNumberFor`) that the headless suite pins, rather than at each handset.
- **A person is never labelled.** Players have no label and must not be given one. Who somebody is, is learned by being introduced (D-013); a name floating over a stranger is the single thing this project exists to not do.

**Rationale:** the empty screen (GDD §8) was never a ban on information, it is a ban on *omniscient* information. "What is this object in front of me" is something a character plainly knows and a player, looking at an untextured placeholder model, plainly does not — the interface was withholding something the fiction grants. The scope rule keeps that from becoming a crack: two lints now enforce it, one requiring every interactable class to define its own label, one forbidding any entity from networking a container id, line id, or owner.

**Affects:** `docs/design-reviews/M8_hud.md` §4b (D-017's indicator gains a label); M9, M12, M13 entity classes; every future interactable, which must define `ENT:OmertaLabel` under this rule.

---

## D-032 — A business earns from customers and from being staffed, and its till is physical (DECIDED, 2026-07-27)

A business's income is **sales to players**, plus a small trickle that accrues **only while the place is open AND a real person is behind the counter**. An unstaffed business earns nothing at all. The trickle is deliberately small enough that it never beats a real customer; it exists so that tending a bar is worth doing — which is the role GDD §4.3 promises independents and never explains how to fill.

**The till is physical cash in a container on the premises**, not a balance. Somebody has to empty it and carry the money to a treasury, and that errand is the most robbable moment in the economy. D-024's reasoning, applied a second time.

There is **no per-business ledger**. Collections write M11's append-only books with a `business` category, because two sets of accounts that can disagree is worse than one.

**Rationale:** passive income is the idle-game money printer BA §13 warns against, and sales-only means a bar in a thirty-player city is empty most of the time and owning one is a liability.

**Affects:** D-024; Tech §11 (its "income/expense ledger" is M11's); GDD §4.3, §11; `docs/design-reviews/M13_businesses.md` §4b; M14 (the collection run is a target).

## D-031 — The rumour mill takes real events and paid lies, and tells them apart for nobody (DECIDED, 2026-07-27)

The rumour pool is fed from two places: **events that actually happened** (a seam M14 and M15 fill) and **rumours players pay to plant**. The barman never distinguishes them and neither does anyone listening.

Rumours expire, are served one at a time on request, are never repeated to the same listener, and are written down nowhere the listener can go back to — remembering what you were told is your job, exactly as it is with names and telephone numbers.

Planted rumours cost money and are **audited with their author**, because "who started that" is occasionally a question about rule-breaking rather than about the fiction.

**Rationale:** a rumour you can verify is a fact, and the design already has facts. Making disinformation purchasable turns the bar into an instrument rather than a decoration, and it gives the barman something to say from day one instead of three milestones from now.

**Affects:** Tech §11; `docs/design-reviews/M13_businesses.md` §4c; M14/M15 (they call `Omerta.Rumours.Add`); M21.

## D-030 — Premises are forceable only while the owning side is online (DECIDED, 2026-07-27; resolves Q-12)

Forced entry into an owned business or headquarters requires at least one member of the owning organization — or the owning independent — to be **connected**. Not present: **online**. A family with nobody logged in cannot be robbed; a family with three people logged in is a target whether or not any of them is standing in the room.

The **police warrant path is exempt** (M17): an institution with authority enters regardless, because that is what a warrant is.

**Rationale:** M11 made this urgent by putting a family's money in a physical container with a location. If that could be emptied at four in the morning, a season would be decided by who sleeps least, and the correct strategy would be to play at unpopular hours. Time-locked vulnerability sounds fairer and quietly makes the optimal play "leave somebody idling in the back room forever". This rule rewards presence instead of punishing absence, and it puts a person on the other end of every raid.

Accepted cost: a family that logs off with the takings uncollected is safe.

**Affects:** Q-12 (resolved); `docs/design-reviews/M13_businesses.md` §4a; M14 (consults the rule), M16/M17 (heat and warrants).

## D-029 — Call records are metadata, and nobody reads them in M12 (DECIDED, 2026-07-27)

Every call writes a record: which line called which line, when, for how long, how it ended. **Never content.** The `phone_calls` table has no column a recording or transcript could go in, so no later milestone can begin storing one without a migration and a conversation.

Records accumulate from day one and are readable by **staff only**. Player-facing access — what a detective may pull, under what authority, and what a wiretap adds — belongs to M15 and M17/M18. Building the read path in M12 would mean inventing police procedure a milestone early, in a review that has no business deciding it.

**Affects:** Tech §23; `docs/design-reviews/M12_telephony.md` §4c; M15 (wiretaps attach here), M18 (the authority to pull a record).

## D-028 — Bystanders hear only the half of a call spoken in front of them (DECIDED, 2026-07-27)

Call audio reaches the participants and nobody else. Somebody standing beside a caller hears **that caller**, positionally, exactly as they would hear any other speech — and hears nothing of the far end. The text path behaves identically: what a mic-less player types is spoken aloud in the room and sent down the line, so they are not playing a different game.

Speakerphone is technically free (S1 §2 — it is one cell of the routing table) and is **deferred, not rejected**: it belongs behind a deliberate action rather than as the default.

**Rationale:** it is what a telephone sounds like from across a room, and it makes overhearing genuinely partial. A witness who heard one side of a conversation is more interesting than one who heard both, and partial information is what this design runs on.

**Affects:** `docs/design-reviews/M12_telephony.md` §4b; `docs/review/05_voice_routing_spike.md`; M7 (gains the voice-override seam); M15 (what a witness can testify to).

## D-027 — Telephone numbers are learned, never listed (DECIDED, 2026-07-27)

There is **no directory**, no lookup and no call history in the dial. A number is four digits — short enough to shout across a bar or write on a scrap of paper, which are the two ways it will ever travel.

A **payphone's number is written on the box**, so anyone standing at one can read it and be called back there. That is the mechanic, not a detail: *"go to the box on Third Street, I'll ring you in ten minutes."* A **private line's** number is known to whoever bought it and to whoever they choose to tell.

Dialling an unassigned number rings and goes unanswered exactly as a real one would, and is rate-limited, so the dial pad cannot be used to sweep the map for private lines.

**Rationale:** a directory hands every player a map of who has what, which is the omniscience this project exists to refuse. Numbers belong to *places*, not people, so they are deliberately not part of M5's identity knowledge — that is the whole point of D-003.

**Affects:** D-003; `docs/design-reviews/M12_telephony.md` §4a; M9 (a number written down is an item).

## D-026 — Procurement buys objects from an abstract supplier, never statistics (DECIDED, 2026-07-27)

An institution orders from a **data-driven catalogue**. Money leaves the safe and the goods appear in it immediately; the fiction is that your people know a guy. Delivery goes through a single function so that a delay, a courier or a supplier NPC can replace it later without touching payment or authorisation.

Purchased goods are **tagged to the institution**, not to whoever fetched them (M9 reserved `organization_id` on every item for this).

Tech §10's guardrail — *"avoid directly modifying health, damage, speed, or armor through family wealth"* — is enforced by the registry as a **refusal**, not observed as a convention: an entry that sets any such field is rejected at registration. Money buys advantage through what it puts in your hands, never through a number attached to your character.

**Affects:** Tech §10; `docs/design-reviews/M11_treasury.md` §4b; M12/M13/M14/M19 (each registers its own catalogue entries).

## D-025 — Spending is limited by rank, and larger amounts need a second person (DECIDED, 2026-07-27)

Each rung of a ladder carries a **spending limit**. Below it, a member spends alone and is their own approver on the record. Above it, a second member must be **physically present at the safe**, hold spending authority themselves, be able to cover the amount, and not be the person spending — and their name is written into the ledger, filling Tech §10's Approver column honestly.

A limit is declared at its own rung and is **not** inherited upward the way permissions are: a rank declaring no limit has no ceiling. Limits are scaled server-wide by `treasury.limit_multiplier` without editing the ladder.

**Rationale:** the alternative satisfies the column and nothing else. This produces the scene the design is actually for — two people standing at a safe, one of whom has to agree — without an approval inbox. A Thompson is deliberately priced above an Underboss's ceiling, so arming a crew is an argument rather than a click.

**Affects:** Tech §10; `docs/design-reviews/M11_treasury.md` §4c; M10's ladders (spending limits added to both).

## D-024 — A treasury is a safe, not a balance (DECIDED, 2026-07-27)

An institution's money is **physical cash in a container with a location on the map**, held as ordinary M9 items. `Count()` is what is actually in the safe; the **ledger** is an append-only record of what should be there. **The two are allowed to disagree**, and that disagreement is not a bug — it is embezzlement, a robbery, or a Don who has been skimming. Every ledger line records the counted total beside the running balance, so a discrepancy has a date rather than merely being noticed one day.

The safe is the **authority** on how much money exists. Every movement is an M9 transactional transfer of real notes and coins, so there is no second place money can be created and M9's duplication protections cover the treasury unchanged.

The consequence, accepted: **procurement is a place you go**, not a menu you open anywhere.

**Rationale:** money was made physical in M9 precisely so it could be stolen, hidden and counted. A balance column would be one integer and one afternoon, and it would delete the heist, the skim, and the point of the earlier decision at the exact moment it was supposed to pay off.

**Affects:** D-018; Tech §10; `docs/design-reviews/M11_treasury.md` §4a; M9 (containers gain an access predicate); M14 (safes are worth robbing); M15 (embezzlement is investigable); M17 (seizure).

## D-023 — Induction is a formal introduction; the roster is rank-gated (DECIDED, 2026-07-27)

Joining an institution grants **no identity knowledge by itself**. Being made is an *event in a room*: every member of that organization who is present when someone is inducted learns them, and they learn those members, through M5's ordinary introduction machinery. Members who were not there learn nothing.

Reading the **roster** is a rank permission (Caporegime and above in a family, Detective and above in the police). The roster shows real names, because it is the institution's own books — but reading it **does not teach recognition**. A Don who reads that a Tony Marino is a soldier still cannot pick him out of a crowd until somebody introduces them. This is D-014's knowledge/recognition split applied literally.

**Rationale:** a family that hands every new soldier a list of names breaks the rule this project exists to enforce; a family where nobody knows anybody cannot be run. Making induction a ceremony that happens somewhere, with people present, costs one thing — and that cost is the feature.

**Affects:** `docs/design-reviews/M10_factions.md` §4b; GDD §4.1; M5 (uses its introduction path unchanged).

## D-022 — Two families are active at launch, seeded by staff (DECIDED, 2026-07-27; resolves Q-1 and C8)

A season starts with **two active families**; the remaining two are dormant and opened mid-season by staff decision as the population justifies it. The count is **configuration, not code** (`organizations.active_families`), so a season that fills up can open a third without a patch. The police department is always active.

The **first leader of an empty institution is seated by staff** from pre-season applications. From that moment they are an ordinary Don and the normal rules apply — staff do not re-seed a running season.

**Rationale:** four families across a small population is four groups of three who never meet anybody, and family rivalry is most of the criminal content. Opening the third as the season fills makes expansion an event players notice.

**Affects:** GDD §4.1 and §22 (resolves the internal contradiction C8 identified); `docs/design-reviews/M10_factions.md` §4a; M10 bootstrap.

## D-021 — Police rank is public; family membership never is (DECIDED, 2026-07-27)

Families and the police department are **one system** — the same tables, the same ladder mechanism, the same permission model — with exactly one asymmetry: **a uniformed officer is publicly identifiable as an officer.**

The visibility rides on the **uniform, not the institution**. The uniform is an ordinary item with an equipment slot, so it can be taken off, left at home or stolen. A stranger looking at a uniformed officer reads their **rank, not their name** ("Sergeant"); someone who knows them reads both ("Sergeant Frank Doyle"); an officer in plain clothes is a stranger like anybody else. A mask hides a face but not a uniform, so a concealed officer still reads as "Sergeant" — and is still not identified.

**Rationale:** a badge is a deliberate public announcement, and family membership is worth having precisely because nobody can prove it. Writing the police as a parallel implementation for one property's worth of difference would guarantee drift.

Implemented as a title seam on `Omerta.Identity.ResolveDisplayName`, mirroring D-014's concealment seam.

**Affects:** GDD §4.2; Tech §6; `docs/design-reviews/M10_factions.md` §4c; M5 (`ResolveDisplayName` gains the title case); M17/M18 (police authority will key off the same membership).

## D-020 — Carrying capacity is bulk, not a spatial grid (DECIDED, 2026-07-27; resolves Tech §9)

Each item carries a **bulk**; each owner has a **capacity**. What a character can carry is a single number, modified by what they are wearing and, later, what they are carrying it in. Tech §9 left the choice between this and a Tarkov-style packing grid open.

**Rationale:** bulk achieves the design's actual goal — big things are hard to carry and impossible to hide — without spending a large UI budget in the milestone that already carries items, money, hunger, containers and persistence. Packing puzzles also pull attention toward inventory management and away from people, which is the opposite of what this game is for.

A grid can be layered over the same data model later without altering a single stored row, so this is a presentation decision deferred, not a door closed.

**Affects:** Tech §9; `docs/design-reviews/M9_inventory.md` §4a.

## D-019 — Starvation warns; hunger does not (DECIDED, 2026-07-27; closes the question D-016 left open)

Hunger stays out of the HUD in normal play, exactly as D-016 requires. The **single** exception is starvation: once hunger is actually costing the player something, a warning fades in as stamina and injury do, and fades out when they eat.

**Rationale:** the contextual rule is that elements appear in response to conditions, not that nothing may ever appear. Degrading a player for a number they were given no chance to notice is not consequence, it is a bug. Below the starvation threshold nothing is shown — being merely hungry is something a character checks, like money in a wallet.

**Affects:** D-016 (closes its open question); `docs/design-reviews/M9_inventory.md` §4c; Tech §8.

## D-018 — Money is denominated, and change is automatic (DECIDED, 2026-07-27)

Cash exists as stacks of specific denominations — 5¢, 10¢, 25¢, $1, $5, $20, $100 — held as ordinary items that can be dropped, hidden, taken off a body and counted by whoever finds them.

Players are **never asked to count**. Shops, treasuries and hand-to-hand payments select notes automatically: an exact set where one exists, otherwise the payer overpays and the change comes straight back. The net cost is exact either way.

**Rationale:** D-003 requires a physical quarter to feed a payphone and D-004 requires small amounts to matter — both of which a single abstract balance dissolves, taking marked-bill evidence with it. Manual counting at every counter is the busywork the Brainstorm warns against (BA §13). Denominations with automatic change keep the one place a specific coin matters ("have you got a quarter?") and remove it everywhere else.

**Affects:** D-003, D-004; `docs/design-reviews/M9_inventory.md` §4b; M12 (payphones), M13 (businesses), M15 (marked bills).

## D-016 — Hunger exists, but is checked in the inventory (DECIDED, 2026-07-27; resolves Q-7)

Hunger is a real mechanic, **displayed only in the inventory view** — never on the HUD, in keeping with the rule that money, ammunition and other quantities are checked deliberately rather than displayed permanently (BA §11).

Consequences of the ruling:
- **Hunger is built in M9, not M8**, because the inventory is its only interface; shipping the mechanic earlier would mean an invisible system no player could inspect.
- Stamina remains separate and keeps its contextual indicator (Tech §8), since it changes second to second.
- **Hunger never kills.** Permanent character death is a deliberate act (GDD §19.2); starvation degrades (stamina recovery, and optionally movement) and no more.
- Open for M9: whether a *contextual* warning appears when genuinely starving, as stamina and injury do. Without one, a player is degraded by something they were given no chance to notice.

**Affects:** `docs/design-reviews/M8_hud.md` §4a; M9 (implements it); GDD §8.

## D-017 — No crosshair; an indicator for interactable targets (DECIDED, 2026-07-27)

The persistent crosshair is removed (GDD §8). In its place, a small indicator appears only when something interactable is under the player's gaze.

**Rationale:** preserves the empty screen and the deliberate, non-arcade feel, while keeping "what am I pointing at" answerable — which M5's introductions already require and M9's searching, M13's shopfronts and M14's robberies will require more.

**Affects:** `docs/design-reviews/M8_hud.md` §4b.

## D-015 — `Player:Nick()` returns a neutral placeholder (DECIDED, 2026-07-27)

`Nick()`, `Name()` and `GetName()` return `"Unknown"` for every player, except that on the client a player's own methods return their own character's name. The genuine Steam name remains available server-side as `Omerta.Population.RealName(ply)` for logs, audit rows and staff tools.

**Rationale:** `Nick()` returns the Steam name, so any stray print — ours, an addon's, an admin mod's — leaks a real-world identity that can be correlated with a character. Overriding converts a permanent discipline problem into a structural one. It is not airtight: `Nick()` is a Lua method and the engine still knows the truth (see M6 §7 on engine-level residue).

**Affects:** `docs/design-reviews/M6_hidden_population.md` §4; all future code, which must use `ResolveDisplayName` for player-facing names and `RealName`/SteamID64 for staff-facing ones.

## D-013 — Introductions are one-way, with reciprocation offered (DECIDED, 2026-07-27; overrides Tech §5)

An introduction discloses **only the introducer's** name. The recipient immediately learns it and is offered a one-keypress prompt to introduce themselves back; declining or ignoring it is always permitted.

**This overrides the Technical Design's own MVP recommendation of mutual introductions** (Tech §5), which precedence would otherwise carry. Mutual introductions make it mechanically impossible to take someone's name without surrendering your own — a power dynamic central to the fiction and to operational security (BA §4: "sharing one's identity with a rival family is a meaningful operational-security failure"). The reciprocate prompt keeps ordinary socializing to the same single keypress mutual would have cost.

**Affects:** Tech §5 (MVP recommendation superseded); `docs/design-reviews/M5_identity.md` §4a.

## D-014 — Knowledge is permanent; recognition is situational (DECIDED, 2026-07-27; resolves Tech §5)

Identity **knowledge** ("that character is named Tony Marino") is permanent, stored per observer–subject pair, and never lost through appearance changes. **Recognition** ("the person in front of me is that character") is situational: a character whose face is concealed resolves as **Unknown to everyone**, including people who know them and including their own crew, who must rely on voice.

Introductions are never blocked by concealment — a masked character may still state a name.

**Rationale:** conflating the two would make masks useless against anyone who had ever met you, gutting the disguise design (BA §5). Separating them costs one seam and preserves both systems.

M5 ships the seam (`Omerta.Identity.IsConcealed`, returning false); the clothing/disguise milestone implements it.

**Affects:** Tech §5, §6, §12; `docs/design-reviews/M5_identity.md` §4d/§4e.

## D-012 — One living character per account per season (DECIDED, 2026-07-27; resolves Q-3)

Each account may have exactly one character with status `alive` in the active season. A new character becomes possible only once the current one is `retired` or `dead`, and inherits nothing beyond the account's seasonal track (D-009).

**Rationale:** a second character would let one player hold two positions, launder knowledge between them, and hedge against permadeath — gutting the consequence design (GDD §19).

**Affects:** M4 creation flow; `docs/design-reviews/M4_characters.md` §4.

## D-011 — Newspaper portraits are creation-time mugshots (DECIDED, 2026-07-27; resolves P-001)

**Option C selected**: each character's portrait is a real image captured client-side in a controlled photo booth during character creation, uploaded once, and stored server-side. Option B (silhouette) remains the fallback when no portrait exists.

Engineering correction on the record: the P-001 evaluation overstated Option C's cost by framing distribution as "a small custom CDN." At newspaper size (128×128 JPEG ≈ 3–8 KB) a portrait fits in a single net message and is fetched on demand when a paper is read, then cached client-side — materially cheaper than evaluated. The decision is sound on those corrected facts.

Binding implementation constraints (from the risks the evaluation did identify):
- **One-shot and immutable**: captured at creation only; no re-upload path, so the upload surface exists for one moment per character.
- **Untrusted pixels**: server validates byte cap and JPEG magic bytes, audits every upload against the uploading account, and staff can wipe a portrait. Offensive *content* is a rules/staff matter, as with metagaming (Tech §4).
- **Base64 in a text column**, not a binary blob: the SQL layer rejects NUL bytes by design (M1 §7), and text keeps portraits inside normal database backups and multi-server setups.
- **Appearance snapshot is stored regardless**, both as the booth's reproducible input and as a graceful fallback.

**Affects:** `docs/review/03_portrait_evaluation.md` (recommendation superseded); Tech §20; M4 (capture + storage); M21 (display).

## P-002 — Justice loop (RECOMMENDED, 2026-07-26)

Three complete justice-system designs delivered in `docs/review/04_justice_system_proposals.md` with a comparison and a recommended hybrid ("The Ledger" spine + "The Deal" resolution layer; "The Island" prison deferred to post-MVP). Awaiting project-lead selection before integration into the GDD, Technical Design, and roadmap milestone M18.
