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

## P-001 — Newspaper portrait pipeline (RECOMMENDED, 2026-07-26)

Evaluation of five options delivered in `docs/review/03_portrait_evaluation.md`. **Recommendation: Option E (composite portrait rendered client-side from archived appearance data), with Option B (silhouette) as the degraded fallback, and Option C (creation-time mugshot capture) as a possible post-MVP enhancement.** Awaiting project-lead confirmation.

## P-002 — Justice loop (RECOMMENDED, 2026-07-26)

Three complete justice-system designs delivered in `docs/review/04_justice_system_proposals.md` with a comparison and a recommended hybrid ("The Ledger" spine + "The Deal" resolution layer; "The Island" prison deferred to post-MVP). Awaiting project-lead selection before integration into the GDD, Technical Design, and roadmap milestone M18.
