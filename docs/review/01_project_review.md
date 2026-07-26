# Omertà RP — Project Review (Phase 1)

Reviewer role: lead software engineer.
Sources: Brainstorm Archive v0.1.0 ("BA"), Game Design Document v0.1.0 ("GDD"), Technical Design Notes v0.1.0 ("Tech"). Citations reference the original 0.1.0 section numbering; the 0.2.0 design documents in `docs/design/` already incorporate the decisions logged in `DECISIONS.md` (D-001…D-005), and resolved items below are marked accordingly.

Precedence applied throughout: **Decision log > Tech > GDD > BA.**

---

## 1. Understanding Summary

Omertà RP is a from-scratch, seasonal (≈4-week) Garry's Mod gamemode simulating organized crime in a compact city. Its single governing rule — *a player should never know information their character could not reasonably know* — is applied structurally, not just as a house rule:

- **Identity** is per-character knowledge. Everyone is "Unknown" until introduced; identity knowledge is stored server-side per observer–subject pair (Tech §2 IdentityKnowledge) and only resolved display names are networked (Tech §6). No scoreboard, player list, kill feed, join/leave messages, or faction counts exist (GDD §6, Tech §4).
- **Information** is the core economy. Events become knowable through witnesses, evidence, newspapers, rumor NPCs, informants, and observation (GDD §13, BA §6) — never through UI.
- **Institutions outlast individuals.** Up to four predefined crime families and one police department persist even when empty (GDD §4); ranks, treasuries, and businesses are organizational; acting-leadership rules prevent offline freeze (Tech §19).
- **Violence is consequential but survivable.** Damage maps to an injury state machine (Tech §17); only a deliberate, logged confirmed kill permanently ends a character (Tech §18), triggering succession, newspaper, and archive effects. Rank is never mechanically restored to a dead player's next character (GDD §19.3).
- **Investigation is systemic.** Crimes create durable events (Tech §16) that feed witness records (Tech §12), typed evidence with chain of custody (Tech §13), and cases with deterministic warrant thresholds (Tech §14). NPC police, alarms, and witnesses keep crime consequential at zero police population (GDD §18, Tech §15).
- **History accumulates.** A B&W newspaper reports public events on templates (Tech §20); a library archives issues, cases, and seasonal records across wipes (Tech §21, §22).
- The **MVP** is GDD §22 — roughly Tech §24 Phases 1–4 — deliberately deferring undercover systems, wiretapping content, deep courts, and complex crew AI.

Additional binding requirements from the project lead (not in the source docs): dual SQLite/MySQL-mysqloo support behind a database abstraction layer with zero gameplay-code changes to switch backends; strict server authority; modular, data-driven, professionally maintainable architecture; phased development with approval gates.

## 2. Strengths

1. **The philosophy is applied consistently across all three documents.** Almost every system — witnesses reporting descriptors instead of names (Tech §12), call records revealing metadata not content (Tech §7), newspapers requiring credible sources (GDD §14), compartmentalized family knowledge (GDD §13) — re-derives from the same rule. That coherence is rare and is the project's main asset.
2. **The precedence hierarchy works in practice.** In nearly every conflict found (below), the Technical document already contains the more implementable position, so "Tech wins" resolves disputes without damaging the design.
3. **Sound service decomposition.** Tech §1's module list maps cleanly onto independent systems with narrow interfaces; the durable EventID pattern (Tech §16) is exactly the right spine connecting crime → witnesses → evidence → cases → newspaper → archive.
4. **Low-population resilience is designed in, not patched in** (GDD §18, Tech §15, BA §21): alarms, witnesses, evidence, and delayed consequences don't require online police.
5. **Accessibility is a first-class requirement** (Tech §8, BA §10): every mechanic works without a microphone, which also keeps the game moderation-friendly (text logs).
6. **Seasons + archive give the server a memory** — a real answer to the "why does anything matter" problem of persistent RP servers, and a natural content-reset valve.
7. **Realistic engine humility.** Tech §4 and §25 already acknowledge Source-engine leakage limits and name the genuinely risky systems rather than hand-waving them.

## 3. Weaknesses

1. **No data-layer specification.** The docs list *what* persists (Tech §2, §22) but not how: no engine choice, schema, migration strategy, transaction model, or async-query handling. The project lead's dual SQLite/mysqloo requirement fills the engine question but the abstraction layer must be designed from scratch (roadmap M1).
2. **The justice loop stops at the courthouse door.** Case states end at "Prosecution or closure" (GDD §17); nothing defines charges, sentencing, fines, custody, records, or what an arrested player actually experiences. This is the largest gameplay hole in the spec. **Being addressed:** three complete designs delivered in `04_justice_system_proposals.md` (P-002, awaiting selection).
3. **No content/asset plan.** A compact custom map (with speakeasy, stores, bank, precinct, library, hospital), period-atmosphere playermodels, clothing/disguise assets, and a small weapon set are all assumed and none are planned. D-005 (placeholder-first) reduces but does not eliminate this workstream — the **map** in particular gates several milestones.
4. **The economy is underspecified.** Family treasuries are well-defined (Tech §10), but personal income, starting money, prices, money sinks, and the physical-vs-abstract cash question are not. D-004 fixes the currency and scale and forces physical coins; the rest needs a design review (roadmap M9/M11).
5. **NPC systems carry more weight than their specification.** NPC victims (GDD §12), witnesses (Tech §12), patrol response (Tech §15), rumor NPCs (Tech §11), and an NPC judge (Tech §14) are load-bearing for low-population play, but only the police response has a state machine sketch.
6. **No testing strategy anywhere.** For a systems-heavy server-authoritative game, unit-testable pure-Lua logic, a headless test harness, and scripted multi-client smoke tests need to be planned from M0, not retrofitted.
7. **Rules/process documents are deferred but load-bearing.** Confirmed-death abuse, Discord metagaming, and leadership griefing are explicitly out of code scope (Tech §25) yet determine whether the design survives contact with players. Written rules specs should ship with the relevant milestones.

## 4. Contradictions Found

| # | Conflict | Sources | Resolution | Status |
|---|---|---|---|---|
| C1 | Project name "Mafia RP" vs. "Omertà RP" | All docs vs. project lead | Omertà RP everywhere | **RESOLVED → D-001** |
| C2 | Era incoherence: speakeasies, Thompson SMGs, B&W period newspaper (BA §7, §27) vs. "cell phones" (BA §9, §10; GDD §7.2) | BA/GDD internal | Timeless classic-crime atmosphere; modern tech omitted where it conflicts; cell phones removed entirely | **RESOLVED → D-002, D-003** |
| C3 | Personal phones: physical inventory devices with SMS (GDD §7.2) vs. period tone | GDD vs. atmosphere | Payphones + location-bound private lines; no personal devices; no SMS (see Q-13) | **RESOLVED → D-003** |
| C4 | Bank robbery in MVP (GDD §22 "Store and bank robbery") vs. "Bank operations" deferred to Phase 5 (Tech §24) | GDD vs. Tech | Precedence says Tech: store robbery ships first, bank robbery follows using the same operation framework once robbery mechanics are proven. Recommend treating "bank robbery" as a Phase-3-adjacent content milestone, not Phase 5 — see roadmap M14 note | **Open — recommendation attached** |
| C5 | Injury model: 6 states, "Wounded" (GDD §19.1) vs. 7 states incl. "Critical", "Injured", "Dead" (Tech §17) | GDD vs. Tech | Tech's 7-state machine is authoritative; GDD naming should be updated when the injury design review lands | Resolved by precedence |
| C6 | Phone tapping available (GDD §7.2 "tapped") vs. content interception deferred (Tech §7) | GDD vs. Tech | Tech: metadata/call-detail records at MVP, content taps deferred. Landline model makes this cleaner (records reveal *places*, not people) | Resolved by precedence |
| C7 | Aliases/false names allowed (BA §4) vs. "legal or selected character name only" for MVP introductions (Tech §5) | BA vs. Tech | Tech MVP recommendation stands; aliases are a post-MVP extension with consequences | Resolved by precedence |
| C8 | Family count: "maximum of four predefined" (GDD §4.1, BA §3) vs. "two to four persistent families" in MVP (GDD §22) | GDD internal | Needs a ruling: how many families are *active* at launch (see Q-1) | **Open** |
| C9 | Character record duplicates identity data: "Known identities" field on Character (Tech §2) alongside the IdentityKnowledge table | Tech internal | Normalize: IdentityKnowledge is the single source of truth; the Character field is a relation, not stored data. Will be reflected in the M1+ schema design | Resolved (schema note) |
| C10 | Newspaper cadence: "daily" (GDD §14) vs. "start of each in-game day or fixed multi-hour interval" (BA §7) vs. "daily or at a fixed real-time interval" (GDD §14 itself) | GDD/BA | Needs a concrete number (see Q-6) | **Open** |

## 5. Missing Decisions (open questions)

Decisions the documents never make, ordered by how early they block implementation. Recommendations are attached but **nothing below is decided until logged in `DECISIONS.md`**.

| # | Question | Blocks | Recommendation |
|---|---|---|---|
| Q-1 | How many families are active at launch, and how is the first Don of a season chosen for an empty institution? (Institutions "exist even when empty" — GDD §4.1 — but bootstrap is undefined) | M10 | Launch with 2 active families; pre-season applications reviewed by staff seed each family's initial Don; remaining institutions open mid-season by staff decision |
| Q-2 | Seasonal-allegiance semantics: the account picks one path (GDD §3), but recruiting independents into families is core gameplay (GDD §4.3), and a dead criminal's next character needs a rule | M3/M4 | Path = criminal/police/independent *track*, chosen per account per season. Independents may be recruited into families (in-world transition, one-way per season). Replacement characters inherit the account's track, not any faction. Police path is locked at selection; leaving PD = becoming independent, never criminal, within the season |
| Q-3 | Characters per account: how many living characters may an account have simultaneously? | M4 | Exactly one active character per account per season; a new one can only be created when the current one dies or permanently retires |
| Q-4 | What happens to living characters at season end? (SeasonID on Character — Tech §2 — implies per-season characters) | M3/M23 | All characters retire to the archive at season end; notable ones get archive records. State this explicitly in the GDD |
| Q-5 | Personal economy: full physical cash vs. balances; income sources per path; starting money; prices; sinks | M9/M11 | Physical denominated cash items everywhere; bank/business ledgers are the only abstract balances (already RECOMMENDED under D-004). Full economy design review before M9 |
| Q-6 | Newspaper cadence in real time | M21 | Fixed real-time interval, config-driven; start at every 6 real hours, tune in testing |
| Q-7 | Stamina/food scope: is hunger a mechanic? | M8/M13 | No hunger meter. Sprint-driven stamina only; food/drink give minor stamina-recovery/comfort buffs (matches BA §13 "avoid busywork") |
| Q-8 | Respect/fear: which entities carry values (character and family both have them — Tech §2) and what do they do at MVP? | M10+ | MVP: family-level only, driven by logged events, affecting NPC reactions and rumor content. Character-level deferred |
| Q-9 | Map: which map, who builds it, what businesses must exist on it? | M13+, content | Decide early; prototype systems on an existing urban map (e.g., an rp_ downtown-style map) with placeholders per D-005, and commission/build the final compact map in parallel |
| Q-10 | Weapons base: custom SWEPs vs. adapting an existing base for the small period arsenal (BA §27) | M14+ | Small custom SWEP set built on the engine base class — full control over concealment, evidence (casings, serials), and injury integration outweighs reuse |
| Q-11 | Vehicles at MVP: procurement lists them (Tech §10), but no vehicle framework is chosen | M11+ | Defer drivable vehicles past MVP unless the chosen map demands them; "vehicle" descriptors in witness/evidence systems can exist without player driving |
| Q-12 | Offline asset protection: can a family's HQ/storage be raided while all members are offline? | M13+ | Physical intrusion requires occupants or police warrant service; container theft gated by heat/rules. Needs its own design note before businesses ship |
| Q-13 | Consequence of D-003: SMS removal. Text-call sessions cover accessibility, notes cover async messages — confirm this is acceptable | M12 | Confirm; optionally add telegram offices later as a paid async channel with a paper trail |
| Q-14 | Police joining flow and NPC judge thresholds | M10/M17 | Police path selected at season start (Q-2); NPC judge is a deterministic threshold table over evidence strength (Tech §14 already leans this way) |
| Q-15 | Justice loop design selection | M18 | See `04_justice_system_proposals.md` (P-002) — recommended hybrid attached there |

## 6. Implementation Risks

Ordered by (probability × impact):

1. **Source-engine identity leakage** (Tech §4, §25). The client console `status` command lists connected players' Steam names, player entities are networked within PVS, and third-party client addons can read `player.GetAll()`. Complete suppression is impossible. **Mitigation strategy:** treat *Steam identity* as unavoidably leaky but *worthless* — all gameplay identity lives in the character layer, which is never correlated with Steam identity in anything networked to clients (no Steam names in any UI, chat, or net message). Ship an automated leakage audit (spike S3) that scans our own networking for name/faction leaks, and cover external correlation by rules + audit logs.
2. **Voice routing for calls and radios** (Tech §7, §25). Per-pair audibility and 3D control via the engine's voice hooks makes basic calls feasible; spatial re-emission (speakerphone, radio crackle from a handset) is not natively supported. **Mitigation:** spike S1 before M12 commits; scope MVP to non-spatial call audio + local-side spatial voice, exactly as Tech §7 already suggests.
3. **Newspaper portraits** (Tech §20, §25). Servers cannot render; image capture/upload/redistribution pipelines are fragile. **Mitigation: resolved by design** — the recommended Option E renders portraits client-side from archived appearance data, eliminating the pipeline entirely (see `03_portrait_evaluation.md`, P-001).
4. **Database abstraction under two engines.** SQLite (synchronous, bundled) and mysqloo (asynchronous, binary module) have opposite execution models; a naive abstraction leaks blocking queries or callback hell into gameplay code. **Mitigation:** async-only public API from day one (SQLite calls wrapped to look async), prepared-statement-style parameterization, a migration runner, and transactional helpers — designed in M1's review before anything persists.
5. **Seasonal reset integrity** (Tech §22, §25). A wipe that half-runs destroys a month of community history. **Mitigation:** archive-then-reset as a single audited, resumable job; rehearsed on staging data before each season end; M23 exists specifically to prove this end-to-end.
6. **NPC scope creep.** Five distinct NPC behavior systems could each balloon. **Mitigation:** all NPC systems are table-driven state machines with deliberately predictable behavior (Tech §15's own principle, applied to victims/witnesses/judge too).
7. **Confirmed-death abuse and leadership griefing** (Tech §25). Code can log and slow these but not prevent them. **Mitigation:** the death interaction is deliberate/interruptible/logged (Tech §18); rules specifications ship as milestone deliverables alongside M20 and M10.
8. **Performance of evidence/witness accumulation** over a 4-week season. **Mitigation:** durable events and records live in the DB, not in entities; retention/decay policies (witness memory decay is already in Tech §12) and indexed queries from the start.

## 7. Proposed Improvements (each requires approval before adoption)

1. **Adopt the durable-EventID pattern as a formal core service** (EventService) rather than a CrimeService detail — deaths, funerals, promotions, and openings also need EventIDs (Tech §16 hints at this; making it explicit prevents three systems inventing their own event keys).
2. **Add a headless test harness requirement to M0/M1** — pure-logic modules (name validation, evidence scoring, sentencing math, treasury transactions) must be runnable under plain Lua for unit tests outside the game.
3. **Promote bank robbery to a fast-follow of store robbery (C4)** — same operation framework, bigger stakes; keeping it in "Phase 5 Expansion" contradicts the GDD MVP more than necessary.
4. **Introduce a telegram office post-MVP (Q-13)** as the paid, paper-trail async channel replacing SMS — thematically strong, mechanically simple, produces seizable evidence.
5. **Treat rules specifications as milestone deliverables** — confirmed death (with M20), leadership/succession (M10), metagaming policy (M6) — so Tech §25's "written rules before release" actually has owners.
6. **Keep the family-radio question separate from telephony** — radios (Tech §7 local voice; BA §10) are equipment-gated broadcast, a different mechanism from lines; schedule with procurement (M11+) rather than M12.

---

*Next document: [`02_development_roadmap.md`](02_development_roadmap.md).*
