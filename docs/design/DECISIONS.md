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
