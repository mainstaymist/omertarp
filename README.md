# Omertà RP

A from-scratch Garry's Mod gamemode simulating organized crime in a compact city — built around information, trust, institutions, consequences, investigation, and social play rather than grinding or arcade PvP.

> **Guiding rule:** a player should never know information their character could not reasonably know.

Omertà RP is not a DarkRP derivative. There is no global chat, no scoreboard, no kill feed, no player list, and no omniscient UI. Identity is learned through introductions; events are learned through newspapers, witnesses, police work, rumor, and observation. Seasons last roughly four weeks; institutions (crime families, the police department) persist while characters, ranks, and wealth reset. Confirmed character death is permanent.

## Project status

**M0–M8 implemented and verified in-engine** on MySQL/MariaDB, the backend of record (D-008). Everyone is Unknown until introduced (D-013/D-014); the surfaces that used to hand identity out for free — scoreboard, kill feed, join/leave lines, voice panel, `Player:Nick()` (D-015) — are closed, with a leak audit reporting zero leaks; speech is ranged, with every listener seeing the speaker's name resolved through their own knowledge; and the persistent screen is empty by construction, elements drawing only through a controller that asks each one whether it currently deserves to be visible.

**M9 (inventory, items, currency and hunger) is implemented; in-engine verification pending** (`omerta_inventory_selftest`, run in the server console). Everything physical is now real: money is stacks of notes and coins you can drop, hide or take off a body (D-018); carrying capacity is bulk, so a Thompson does not go in a pocket (D-020); and hunger is read in the inventory, warning you only once starvation actually costs you something (D-016/D-019). Items live one row per instance with transactional, guarded ownership changes, so an item cannot exist in two places at once.

That completes Track A.

**M10 (factions core) is implemented and verified in-engine.** Four crime families and a police department exist as season-scoped instances of code-defined institutions, with rank ladders, cumulative rank permissions, sponsorship and induction, and authority that descends the chain when a leader is away. Two families are active at launch and staff open the rest as the population justifies it (D-022). Joining teaches you only the people who were in the room (D-023), and the one thing a stranger can read off you is a police uniform — the rank, not the name (D-021).

**M11 (treasury and procurement) is implemented and verified in-engine.** A treasury is a **safe** — physical cash in a container with a location on the map — and the ledger beside it is append-only. The two are allowed to disagree, and that disagreement is embezzlement, a robbery, or a Don who has been skimming (D-024). Spending is capped by rank, with larger amounts needing a second member present who can cover them (D-025), and procurement buys objects from a data-driven catalogue, never statistics (D-026).

**M12 (telephony) is implemented and verified in-engine.** Payphones and location-bound private lines, with call audio routed to the participants only — a bystander hears the half of the conversation spoken in front of them and nothing of the far end (D-028). Numbers are learned rather than listed, and a payphone's is written on the box so you can be called back there (D-027). Calls are fed with real quarters and stop mid-sentence when they run out (D-003); every call leaves a record of who called whom, for how long, and never a word of what was said (D-029).

**M13 (businesses and the speakeasy) is in design review and awaiting approval** — the first milestone whose output is somewhere to *be* rather than something to do, and the one that answers Q-12: whether a family's premises can be emptied while everybody is offline.

## Repository layout

- `gamemodes/omertarp/` — the gamemode (mount or symlink into your server's `garrysmod/gamemodes/`)
- `tests/` — headless core tests: `lua tests/run_tests.lua` (plain Lua 5.1, no engine required)
- `docs/` — design documents, reviews, roadmap, and per-milestone design reviews

## Documentation index

| Document | Role |
|---|---|
| [`docs/design/1_Brainstorm_Archive.md`](docs/design/1_Brainstorm_Archive.md) | Historical creative record. Preserved verbatim; **predates the decision log** and is superseded where they conflict. |
| [`docs/design/2_Game_Design_Document.md`](docs/design/2_Game_Design_Document.md) | Defines gameplay. |
| [`docs/design/3_Technical_Design.md`](docs/design/3_Technical_Design.md) | Defines architecture and implementation. |
| [`docs/design/DECISIONS.md`](docs/design/DECISIONS.md) | Canonical log of project-lead rulings. |
| [`docs/review/01_project_review.md`](docs/review/01_project_review.md) | Phase 1 specification review: strengths, weaknesses, contradictions, missing decisions, risks. |
| [`docs/review/02_development_roadmap.md`](docs/review/02_development_roadmap.md) | Phase 2 milestone roadmap with dependencies. |
| [`docs/review/03_portrait_evaluation.md`](docs/review/03_portrait_evaluation.md) | Newspaper-portrait pipeline evaluation — superseded by D-011 (Option C). |
| [`docs/review/04_justice_system_proposals.md`](docs/review/04_justice_system_proposals.md) | Justice-loop design proposals (awaiting selection). |
| [`docs/review/05_voice_routing_spike.md`](docs/review/05_voice_routing_spike.md) | S1 spike — voice routing for telephony; answered, gates M12. |
| [`docs/design-reviews/M0_foundation.md`](docs/design-reviews/M0_foundation.md) | M0 design review — approved and implemented. |
| [`docs/design-reviews/M1_database.md`](docs/design-reviews/M1_database.md) | M1 design review — approved and implemented; MySQL verified in-engine. |
| [`docs/design-reviews/M2_accounts.md`](docs/design-reviews/M2_accounts.md) | M2 design review — approved, implemented, verified in-engine. |
| [`docs/design-reviews/M3_seasons.md`](docs/design-reviews/M3_seasons.md) | M3 design review — approved, implemented, verified in-engine. |
| [`docs/design-reviews/M4_characters.md`](docs/design-reviews/M4_characters.md) | M4 design review — approved, implemented, verified in-engine (rules D-011/D-012). |
| [`docs/design-reviews/M5_identity.md`](docs/design-reviews/M5_identity.md) | M5 design review — approved, implemented, verified in-engine (rules D-013/D-014). |
| [`docs/design-reviews/M6_hidden_population.md`](docs/design-reviews/M6_hidden_population.md) | M6 design review — approved, implemented, verified in-engine (rules D-015). |
| [`docs/design-reviews/M7_communication.md`](docs/design-reviews/M7_communication.md) | M7 design review — approved, implemented, verified in-engine. |
| [`docs/design-reviews/M8_hud.md`](docs/design-reviews/M8_hud.md) | M8 design review — approved, implemented, verified in-engine (rules D-016/D-017). |
| [`docs/design-reviews/M9_inventory.md`](docs/design-reviews/M9_inventory.md) | M9 design review — approved and implemented (rules D-018/D-019/D-020). |
| [`docs/design-reviews/M10_factions.md`](docs/design-reviews/M10_factions.md) | M10 design review — approved, implemented, verified in-engine (rules D-021/D-022/D-023). |
| [`docs/design-reviews/M11_treasury.md`](docs/design-reviews/M11_treasury.md) | M11 design review — approved, implemented, verified in-engine (rules D-024/D-025/D-026). |
| [`docs/design-reviews/M12_telephony.md`](docs/design-reviews/M12_telephony.md) | M12 design review — approved, implemented, verified in-engine (rules D-027/D-028/D-029). |
| [`docs/design-reviews/M13_businesses.md`](docs/design-reviews/M13_businesses.md) | M13 design review — **awaiting approval**; requests three rulings. |
| [`docs/rules/metagaming.md`](docs/rules/metagaming.md) | Player-facing metagaming policy (ships with M6). |
| [`docs/GLOSSARY.md`](docs/GLOSSARY.md) | Plain-language definitions of the engineering terms used in the design reviews. |

## Document precedence

When documents disagree:

1. `DECISIONS.md` (explicit project-lead rulings)
2. Technical Design
3. Game Design Document
4. Brainstorm Archive

Review documents (`docs/review/`) analyze and recommend; they carry no design authority until a recommendation is accepted into the decision log or a design document.

## Development process

Work proceeds one milestone at a time. Each milestone receives a written design review (purpose, responsibilities, public API, data model, networking, persistence, security, dependencies, extension points) and is implemented only after that review is approved. See the roadmap for milestone ordering.
