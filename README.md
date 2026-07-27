# Omertà RP

A from-scratch Garry's Mod gamemode simulating organized crime in a compact city — built around information, trust, institutions, consequences, investigation, and social play rather than grinding or arcade PvP.

> **Guiding rule:** a player should never know information their character could not reasonably know.

Omertà RP is not a DarkRP derivative. There is no global chat, no scoreboard, no kill feed, no player list, and no omniscient UI. Identity is learned through introductions; events are learned through newspapers, witnesses, police work, rumor, and observation. Seasons last roughly four weeks; institutions (crime families, the police department) persist while characters, ranks, and wealth reset. Confirmed character death is permanent.

## Project status

**M2 (accounts + audit) implemented; in-engine verification pending (`omerta_accounts_selftest`).** M0 (foundation) and M1 (database layer) are verified in-engine on MySQL/MariaDB, the backend of record (D-008 — the SQLite driver remains as an unsupported development convenience). Every connecting player now gets a persistent account (SteamID64-keyed; flags, career stats, playtime), and all audit events persist to the database. No gameplay systems exist yet; M3 (seasons) is next, pending its design review.

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
| [`docs/review/03_portrait_evaluation.md`](docs/review/03_portrait_evaluation.md) | Newspaper-portrait pipeline evaluation and recommendation. |
| [`docs/review/04_justice_system_proposals.md`](docs/review/04_justice_system_proposals.md) | Justice-loop design proposals (awaiting selection). |
| [`docs/design-reviews/M0_foundation.md`](docs/design-reviews/M0_foundation.md) | M0 design review — approved and implemented. |
| [`docs/design-reviews/M1_database.md`](docs/design-reviews/M1_database.md) | M1 design review — approved and implemented; MySQL verified in-engine. |
| [`docs/design-reviews/M2_accounts.md`](docs/design-reviews/M2_accounts.md) | M2 design review — approved and implemented. |
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
