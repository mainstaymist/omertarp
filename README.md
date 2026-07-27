# Omertà RP

A from-scratch Garry's Mod gamemode simulating organized crime in a compact city — built around information, trust, institutions, consequences, investigation, and social play rather than grinding or arcade PvP.

> **Guiding rule:** a player should never know information their character could not reasonably know.

Omertà RP is not a DarkRP derivative. There is no global chat, no scoreboard, no kill feed, no player list, and no omniscient UI. Identity is learned through introductions; events are learned through newspapers, witnesses, police work, rumor, and observation. Seasons last roughly four weeks; institutions (crime families, the police department) persist while characters, ranks, and wealth reset. Confirmed character death is permanent.

## Project status

**M3 (seasons + path selection) implemented; in-engine verification pending (`omerta_seasons_selftest`).** M0–M2 are verified in-engine on MySQL/MariaDB, the backend of record (D-008). The server now has persistent accounts with a live audit trail, and a season lifecycle with server-enforced allegiance tracks (D-009/D-010). No gameplay systems exist yet; M4 (characters) is next, pending its design review — where the portrait pipeline (P-001) and characters-per-account (Q-3) decisions come due.

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
| [`docs/design-reviews/M2_accounts.md`](docs/design-reviews/M2_accounts.md) | M2 design review — approved, implemented, verified in-engine. |
| [`docs/design-reviews/M3_seasons.md`](docs/design-reviews/M3_seasons.md) | M3 design review — approved and implemented (rules D-009/D-010). |
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
