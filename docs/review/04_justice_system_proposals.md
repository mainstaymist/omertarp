# Omertà RP — Justice System Proposals (P-002)

Commissioned design for the complete post-arrest loop — the largest gap identified in the Phase 1 review. Three self-contained designs follow, each covering the full required checklist, then a comparison and a recommendation.

**Binding constraints honored by all three proposals:**

- Sitting in a cell on a timer is **never** the primary punishment. Where custody exists it either contains real gameplay or is short enough that the true consequence lies elsewhere: fines, records, probation, reputation, seizures, investigations, business disruption.
- Server-authoritative, deterministic adjudication (Tech §14: "deterministic rules, not generative legal decisions"). NPC judges/prosecutors are threshold tables, not oracles.
- The information philosophy applies inside the system: court outcomes are *public records* (newspaper/archive feeds), investigation contents are not.
- Small money is real money (D-004): a $50 fine hurts; a $500 bond is a family decision.
- Everything integrates with the existing spine: EventIDs (Tech §16), evidence strength (Tech §14), confirmed death (Tech §18), succession (Tech §19), newspaper (Tech §20), archive (Tech §21), audit (Tech §23).

**Shared foundation (all proposals assume this):** an arrest ends in **booking** at the precinct — a physical, playable scene, not a menu: the suspect is searched (inventory interaction, evidence seizure), fingerprinted (creates the biometric record that makes prior evidence matchable), photographed (appearance snapshot → police records; feeds P-001 portraits via lawful "file photo"), and formally charged or released. Booking is where the state first learns *who it is holding* — an unidentified masked robber, once fingerprinted, retroactively connects to every print they ever left. Booking includes **one phone call**, made physically from the precinct payphone (D-003): the accused calls their lawyer, their family, or nobody — and anyone in the lobby can watch them make it.

---

## Proposal 1 — "The Ledger" (systemic-consequences model)

**Thesis:** punishment is not an event, it is a *state*. Conviction writes to a character's ledger — record, fines, probation terms, seizures — and the world continuously reads that ledger back. Custody is minutes; consequences are weeks.

### 1.1 Player flow, arrest to release

1. **Arrest** (from M17's warrant/threshold system) → cuffed and escorted. The walk/drive to the precinct is playable and interceptable.
2. **Booking** (shared foundation above): search, prints, photo, charge sheet drawn from the case's allegation list, one phone call.
3. **Arraignment** — within minutes, at the precinct's magistrate window (NPC): the deterministic magistrate reads the case's per-allegation evidence strength. Below threshold → **released, charges dismissed** (the arrest still happened and is on the record as an arrest, not a conviction). At or above → charges confirmed, **bail set** by table (charge tier × record tier), disposition scheduled.
4. **Disposition** — the sentencing table (below) converts confirmed charges into a consequence bundle: fines, restitution, probation terms, forfeitures, community service, and for the top tier a short processing custody (capped in minutes and full of scene gameplay — see 1.12).
5. **Release** — walked out the front door, in public view, with a new ledger state. The newspaper may already be typesetting.

An innocent player's path through this is typically: arrest → booking → arraignment collapse → released in under ten minutes with an arrest record and a grievance (see 1.3, 1.7).

### 1.2 How evidence affects outcomes

Evidence strength is the *only* input the magistrate reads. Each allegation on the case carries the strength score built in M15/M17; the arraignment threshold, charge tier, and sentencing multipliers are all deterministic functions of it. Evidence flagged as unlawfully collected (Tech §14 illegal-action detection) is excluded before scoring — a case built on a bad search collapses at arraignment, publicly, and the department eats the standing loss. Chain-of-custody breaks downgrade strength rather than nullifying, so sloppy police work weakens rather than voids.

### 1.3 Guilty vs. innocent experience

- **Guilty:** the system is a slow squeeze, not a wall. You are back on the street quickly — but poorer, on paper, constrained, and *interesting to the police*. Your name is in the ledger; your next arrest prices differently.
- **Innocent (or unproven):** fast exit at arraignment. The cost paid is real but bounded — time, the booking record, being *seen* arrested (social/reputational, and the newspaper may report a major arrest before it collapses). Remedies exist: expungement of dismissed-arrest records via lawyer petition (1.4), and a pattern of collapsed arrests by the same officer feeds the excessive/unlawful-conduct flags — innocent players are the fuel of internal-affairs gameplay.

### 1.4 Lawyers

A real independent profession (GDD §4.3):

- Retained via the booking phone call, a standing family arrangement (retainer paid from the treasury — Tech §10 "Legal defense"), or walk-in at the precinct.
- **Motions**: suppress evidence (attack lawfulness/custody flags — the mechanical hook for 1.2's exclusions), reduce bail, expunge dismissed arrests, contest forfeitures (1.6).
- **Negotiation**: fine/term reductions at disposition within table-defined bands — a represented character resolves at the favorable edge of the band, unrepresented at the harsh edge. Lawyers matter without making justice purchasable outright.
- Paid in real money; a family keeping a good lawyer on retainer is a genuine treasury line.

### 1.5 Plea bargains

Light-touch here (Proposal 3 makes this the centerpiece): at disposition the accused may **accept the sheet** (take the table outcome, done in minutes) or **contest** (lawyer motions get one pass at the evidence before the table re-runs). Accepting quickly earns the cooperative-disposition discount on fines. No trial layer exists in this proposal at MVP.

### 1.6 Sentencing

Deterministic matrix: **charge tier (1–5) × record tier (below) × aggravators** (weapon displayed, civilian injury, probation breach) → a bundle drawn from:

- Fines and restitution (victim businesses actually receive restitution — money re-enters the city)
- Probation terms (1.9)
- Community service (1.11)
- License consequences (business/liquor/firearm permissions suspended — a speakeasy owner's conviction is a *business* problem)
- **Forfeiture**: items seized at booking that are instruments or proceeds of the confirmed charge are forfeited; contested through lawyer motion. Marked-currency evidence (Tech §13) shines here.
- Top tier only: short processing custody (1.12).

### 1.7 Appeals

Paper, not courtroom: a lawyer files against **procedural error** — suppressed evidence that was counted, scope violations, threshold math on excluded items. Deterministic re-run of the arraignment/disposition with corrected inputs. Success vacates the ledger entry, refunds fines, restores forfeitures, and writes a conduct flag against the responsible officer. Appeals are rare, paid, and slow (days) — a family investment in clearing a valuable member's record.

### 1.8 Bail

Cash, physical, posted at the precinct window by *anyone* — which is the point. A soldier's $400 bond posted an hour after arrest tells detectives somebody with money cares; the treasury withdrawal is in the family ledger; marked bills post beautifully. Skipping disposition forfeits the bond and issues a bench warrant (auto-valid arrest threshold). Bail exists to compress custody, not to price freedom: indigent characters are released on recognizance for all but the top tier.

### 1.9 Probation

The load-bearing consequence, because it *changes how the world works around you*:

- **Terms** (table-assigned): weapon prohibition (possession alone = new charge), association conditions (being observed with flagged known offenders = violation), district conditions (curfew zones), and **scheduled check-ins** at the precinct.
- Check-ins are the masterstroke consequence under this design's philosophy: a probationer has a *predictable, public location and time* every few days. Police can watch who else shows up; rivals can too. Probation makes a character legible — the precise thing this game makes valuable.
- **Enforcement is evidentiary, not psychic**: violations must be *observed* (officer sighting, witness report, camera) and become probable cause — no magical server-side tattling. The server knows; the police must still learn.
- Violation → summary re-disposition at escalated tier.

### 1.10 Fines

Priced to hurt at D-004 scale (a soldier's week of earnings for a mid-tier charge). Unpaid by deadline → lien: the character's registered assets (business shares, bank balance) are garnished, then a bench warrant. Fines are the city's revenue: they visibly fund the police department's capability budget (Tech §10 department funding) — every conviction literally strengthens the opposition, which families feel.

### 1.11 Community service

Playable, public, and slightly humiliating by design: street sweeping, precinct cleaning, hospital portering — short supervised world-tasks performed in a marked work vest. The punishment is *visibility*: everyone who walks past learns something true about you. Completing service discounts the fine; skipping converts to fine + violation.

### 1.12 Prison gameplay

None. Top-tier convictions carry **processing custody** capped at single-digit minutes in the precinct holding cell — and the cell is a *scene*, not a void: detectives come to the bars for the flip conversation (1.16), cellmates overhear things, lawyers visit through the grille, and the release walk is public. Long-term incapacitation of a character is not a punishment this proposal uses; the ledger is heavier than any door.

### 1.13 Character death interactions

- No death penalty: no conviction ever kills a character (confirmed death stays exclusively a player-driven act — Tech §18).
- Death of an accused closes open cases as *death of suspect* (archived, not "solved").
- Murder convictions carry the maximum bundle, and — critically — a **conviction is a public record naming the killer**, which is newspaper- and archive-eligible: the justice system is one of the few lawful ways a killer's identity becomes public knowledge (feeds GDD §14's "credible source" rule).

### 1.14 Family involvement

The family experiences the system as an economy and an intelligence problem: bail postings and lawyer retainers are treasury lines (visible to cops who obtain records); restitution and fines drain members; a roster full of flagged offenders makes association conditions expensive for everyone; forfeitures claw back equipment the family bought. Leadership choices emerge naturally — pay for the soldier's lawyer or let him eat the record? Both answers are stories.

### 1.15 Witness protection

A cooperating witness facing credible danger may enter protection: mechanically, **voluntary character retirement** with an archive record sealed until season end, plus an account-level title/history credit so the player loses nothing meta. The character "leaves the city." Post-MVP: a relocated-in-place variant (new residence, police watch flag). Killing a witness *before* they enter protection remains the criminal counter — which is precisely the hit-pressure gameplay GDD §20 wants.

### 1.16 Informants

The holding cell and the arraignment gap are the recruiting office. A detective may offer a **cooperation disposition**: charges *deferred* (not dismissed) in exchange for registered informant status with tasking (BA §18). Deferred charges are a leash — stop cooperating and the original disposition executes at full price. All handled through the case system; the informant's file is department-private (corruption target, 1.17).

### 1.17 Corruption opportunities

Every consequence in the ledger is a bribe surface, and each leaves an audit trail (Tech §23) for internal affairs to find: a desk sergeant mis-files a charge sheet (tier downgrade), an evidence clerk breaks a custody chain on purpose, a probation officer fails to observe a violation, a records clerk sells the informant registry, a bail clerk tips the family when a rival posts bond. Corrupt acts are player actions with in-world mechanics and server-side logs — discoverable, prosecutable, and the seed of the corrupt-police storyline (BA §18).

### 1.18 Long-term consequences

The **record tier** — Clean / Noted / Known Offender / Notorious — is the spine: it multiplies future sentencing, prices bail, gates business licenses, colors newspaper language ("a known offender of this city…"), feeds NPC reactions (respect/fear inputs), and survives into the archive as the character's public biography. The ledger *is* the character's shadow; by season's end the archive can print it.

---

## Proposal 2 — "The Island" (playable-prison model)

**Thesis:** if conviction removes you from the city, the place it removes you *to* must be worth playing. Prison is a second, smaller social arena — visitation, contraband, letters, yard politics — where sentences are short in real time but dense in consequence.

### 2.1 Player flow, arrest to release

Arrest → booking → arraignment (as Proposal 1, steps 1–3) → conviction → **transport**: a prison van run, playable and ambushable — the classic convoy interception is deliberately left on the table as high-risk rescue gameplay → **intake**: searched again, inventory impounded, prison uniform (a real appearance change: witness descriptors and identity presentation shift) → **sentence** served in the facility (tiers: 10 / 20 / 40 real minutes; see 2.12 for why those minutes are full) → **parole hearing** (deterministic, behavior-based early release) or **gate release**: walked out to whoever came to pick you up — family car, lawyer, nobody.

### 2.2 How evidence affects outcomes

Identical arraignment mathematics to Proposal 1 (strength thresholds, exclusions, custody-flag downgrades). Evidence strength additionally sets the *sentence tier*, and in-prison conduct records feed the parole threshold, so evidence gameplay continues inside: contraband found in your cell is a new case.

### 2.3 Guilty vs. innocent experience

Innocent: identical fast arraignment exit as Proposal 1. Guilty: a *change of venue*, not a timeout — you keep playing, in a place with different rules, different power structures, and an audience of exactly the people (criminals, detectives visiting, guards) your story concerns. Wrongful convictions (evidence later vacated) are dramatic by construction: an appeal reaches into the prison and opens the gate early (2.7).

### 2.4 Lawyers

As Proposal 1, plus: **legal visits** inside the facility (privileged room — not surveilled, unlike regular visitation), carrying appeals paperwork, parole preparation, and — inevitably — things lawyers should not carry, at their own risk (a searched lawyer with contraband is a career-ending story).

### 2.5 Plea bargains

Meaningful lever: pleading at arraignment trades tier down (40→20→10 minutes) and skips transport (no rescue window — the family might *prefer* you refuse the plea). Cooperation pleas convert custody entirely into informant status (2.16).

### 2.6 Sentencing

The Proposal 1 matrix, with the bundle's centerpiece being the custody tier; fines/restitution/forfeiture still apply but lighter. Post-release **parole terms** replace probation (same mechanics as 1.9).

### 2.7 Appeals

As Proposal 1, with teeth: a successful appeal during a sentence releases immediately and publicly — the newspaper loves an exoneration, the department hates one.

### 2.8 Bail

Pre-disposition release as Proposal 1. Additionally **bond forfeiture funds the facility**: the city's prison quality (guard count, camera coverage) scales with justice revenue — criminal money literally builds the walls.

### 2.9 Probation / parole

Post-release parole identical to 1.9's probation mechanics (observed-violation enforcement, check-ins, association terms). Parole violation returns you through intake without a new arraignment — the leash is shorter than probation's.

### 2.10 Fines

Present but secondary (Proposal 1's schedule at reduced weight); the facility is the headline consequence.

### 2.11 Community service

Replaced inside the walls by **work details** (laundry, kitchen, yard maintenance) — opting in earns conduct credit toward parole and moves you around the facility (which is exactly what smugglers want too).

### 2.12 Prison gameplay

The proposal's heart. The facility is small (one cell block, yard, visitation, workshop, infirmary) but every system re-enters:

- **Visitation**: family meetings through glass, *recorded by default* (a monitored-conversation evidence stream — careless bosses convict themselves); the Don who visits a jailed soldier tells detectives something.
- **Letters**: physical mail, read by censors (police intelligence channel), smuggleable to avoid the censor.
- **The prison payphone** (D-003): monitored line, quarters from commissary — calls out are possible and dangerous.
- **Contraband economy**: commissary scrip and cigarettes as internal currency; smuggling via visitors, work details, corrupt guards; a shiv is a crime scene waiting to happen.
- **Yard politics**: family members inside protect (or tax) each other; a jailed capo can *run crews by visitation* — leadership from inside is playable (acting-leadership rules, Tech §19, interact deliberately).
- **In-prison violence**: full injury system applies; a deliberate confirmed kill inside is murder with a locked-room suspect list — the best detective setpiece in the game.
- **Protective custody wing**: for at-risk prisoners (flipped informants, witnesses) — safer, lonelier, and an *announcement* to every observer of what you probably are.
- **Escape**: rare, telegraphed, multi-stage ops (post-MVP flag) creating fugitive status: no new charges needed, arrest-on-sight, the newspaper's favorite front page.
- **NPC guards** baseline (bribable per 2.17); player Corrections Officer as a police-path posting post-MVP.

### 2.13 Character death interactions

Confirmed kills inside follow Tech §18 unchanged — prison does not suspend mortality, it concentrates it (silencing a cooperating witness inside the walls is the archetypal hit). No death penalty. Death in custody triggers automatic internal investigation + guaranteed newspaper story: the city always asks how.

### 2.14 Family involvement

Richest of the three proposals: visitation diplomacy, commissary funding (traceable), smuggling logistics, protecting members inside, deciding whether a jailed boss still rules (succession tension by design — Tech §19's acting-leadership timers meet a Don who is *present but confined*), and van-interception rescue as the ultimate loyalty statement.

### 2.15 Witness protection

The protective wing serves pre-trial custody of endangered witnesses; long-term protection as Proposal 1 (retirement/relocation). The wing makes protection *visible* — entering it is itself information.

### 2.16 Informants

Flipping continues inside — a cellmate wearing a wire is the classic. Cooperation pleas (2.5) route criminals into informant status instead of cells; the protective wing exists because of what happens when that leaks.

### 2.17 Corruption opportunities

Guards: smuggle, look away, open a door, lose paperwork. Facility funding creates institutional corruption: a warden's budget skim as a late-game storyline. All logged (Tech §23), all discoverable.

### 2.18 Long-term consequences

Record tiers as Proposal 1, plus **"did time" as social currency** — the archive notes it, the yard remembered it, and respect/fear inputs read it (a made man who served without talking *earned* something; the system should record that he didn't flip, because the family will ask).

**Honest weakness:** at low population, prison splits an already-small player base across two spaces, and its map/systems cost (facility area, visitation, contraband, guards) is the largest of the three proposals. It is the best *destination* design but the most expensive road.

---

## Proposal 3 — "The Deal" (negotiation-centric model)

**Thesis:** the courthouse's real product is not verdicts, it's *leverage*. Nearly every case resolves through negotiated disposition against a deterministic NPC District Attorney; trials are rare and seismic. The system's deepest hook: **prosecution reveals information** — and in this game, information is the whole economy. Its second hook is the game's namesake: every deal offered to a captured soldier is a test of omertà.

### 3.1 Player flow, arrest to release

Arrest → booking → **DA evaluation**: the NPC DA's office scores the case (same evidence math) and generates a physical **offer sheet** — a paper document listing the charges, an *excerpt of the supporting evidence* (see 3.2), and two to four resolution options (plead to schedule, cooperate, contest). → **The meeting**: a scheduled scene in the precinct interview room — accused, lawyer, the offer on the table. Accept → consequences execute immediately (fines/probation/etc. from the Proposal 1 bundle; custody almost never). Reject → **trial docket**: a deterministic verdict computed from final evidence strength after both sides' motions, delivered days later at a public courthouse session — high variance, winner-take-most (acquittal expunges; conviction prices at the top of every band). → Release with the outcome on the record.

### 3.2 How evidence affects outcomes — and the discovery hook

Evidence drives everything twice over:

- **Mechanically**: charge selection, offer harshness, and trial verdict are all functions of admissible strength (with exclusions/downgrades as in Proposal 1).
- **Strategically — discovery**: contesting charges entitles the defense to *see the state's evidence*. The offer sheet excerpts it; a full contest discloses the case file's evidence list (not its informant identities — those redact, imperfectly...). This weaponizes the justice system as an intelligence operation: **a family can deliberately let a soldier be arraigned to learn what the police actually have.** The DA's counter is thin offer sheets and sealed items; the police counter is parallel construction. This single mechanic makes every prosecution a two-sided information game and is the proposal's crown jewel.

### 3.3 Guilty vs. innocent experience

- **Innocent**: reject the offer with confidence — weak cases price weak offers (an offer sheet listing almost nothing *tells you they have almost nothing*), and trial acquittal is cheap, public vindication that costs the DA standing. Malicious prosecution has a price tag.
- **Guilty**: a genuinely interesting decision under uncertainty — the sheet shows part of the hand; take the sure loss, or pay for discovery and risk the top band? Guilt feels like *poker*, not punishment queueing.

### 3.4 Lawyers

The profession this proposal is built around: reading offer sheets (experience reveals what excerpt patterns imply about hidden strength), motions battle before trial math runs, negotiating within DA bands (representation shifts the deterministic outcome band, as 1.4), attending the meeting, working the trial docket. Family retainers become essential infrastructure; a great defense lawyer becomes a *named character* the whole server knows.

### 3.5 Plea bargains

The system *is* plea bargaining. Three offer families: **schedule pleas** (pay the bundle, done), **cooperation agreements** (3.16), **charge reductions** (plead to the lesser, forfeit the instrument). Offers expire; rejected offers don't return improved. All deterministic, all tabled, all tunable.

### 3.6 Sentencing

Proposal 1's bundle matrix supplies the consequences (fines, restitution, probation, forfeiture, licenses, service); custody exists only as the top band's processing hold. Trial conviction applies the harsh edge of every band; negotiated outcomes the tabled midpoint.

### 3.7 Appeals

Only trial convictions appeal (deals are waivers — you signed). Procedural-error basis as Proposal 1. This makes the reject-and-fight path the only one preserving appellate rights: another real strategic texture.

### 3.8 Bail

As Proposal 1, pre-resolution. Deal acceptance releases instantly, making bail mostly a *contest-path* cost — fighting is expensive in every dimension, by design.

### 3.9 Probation

As 1.9 (same terms/enforcement), arriving through deal terms rather than dispositions. Cooperation agreements layer reporting duties on top (a probation check-in that is *also* a handler meeting — two reasons to be at the precinct, observable by anyone watching).

### 3.10 Fines

As 1.10; the deal system prices them dynamically inside DA bands (strong case, thin wallet → the DA takes probation-heavy deals; the tables account for ability to pay so fines bite everyone proportionally).

### 3.11 Community service

As 1.11, offered as a deal component — visibly working off a deal reads differently than a sentence, and everyone watching knows you *signed something*.

### 3.12 Prison gameplay

None at MVP (as Proposal 1's 1.12 — scene-rich processing holds only). The trial docket's top band could route to a Proposal 2 facility if one is ever built — the proposals compose.

### 3.13 Character death interactions

As Proposal 1 (no death penalty; death-of-suspect closures; convictions as public killer-naming records). Additionally: a defendant murdered *between offer and trial* automatically publicizes that a deal was on the table — killing someone to stop a deal confirms there was one. Witness murder before a docketed trial voids that testimony's strength (and creates the obvious new case): the incentive structure GDD §20 wants, priced explicitly.

### 3.14 Family involvement

The proposal's beating heart, because omertà finally has mechanics: every arrested member *privately* holds an offer sheet the family cannot read. Did he take a schedule plea or a cooperation deal? The family sees only the outcome speed and the consequences worn openly. Trust becomes evidentiary: families develop doctrine (we pay for contests; nobody pleads without the lawyer; anyone released too cheap gets watched). The prisoner's dilemma isn't a metaphor here — it's the game loop, and it is named on the box.

### 3.15 Witness protection

As Proposal 1 (retirement/relocation), with sharper timing: protection triggers at cooperation-agreement signing — the moment of maximum danger is the gap between signature and safety, which both sides can see coming.

### 3.16 Informants

Institutionalized as the DA's strongest instrument: cooperation agreements with tasking, deferred charges as the leash (as 1.16), and *sealed* status in case files that redaction handles imperfectly under discovery (3.2) — meaning aggressive discovery litigation is also mole-hunting. The tension between prosecuting cases and protecting sources is the DA-side balancing act, expressed in tables.

### 3.17 Corruption opportunities

Everything in 1.17, plus the crown target: **the offer sheet pipeline**. A clerk who leaks sheets tells a family who is talking; a bribed DA's-office employee fattens or thins offers within capped bands (never dismissal — corruption bends, never breaks, the tables); discovering *that* corruption is a career-making internal-affairs case.

### 3.18 Long-term consequences

Record tiers as 1.18, plus a **disposition history** the archive keeps: who fought and won, who signed fast, who cooperated (sealed until season end — then the archive tells all, and reputations settle permanently; season-end informant reveals are already canon in BA §2). The library's "notable trials" shelf becomes server folklore.

**Honest weakness:** heavy tuning surface (offer tables, band math, discovery redaction rules) and the most abstraction to diegetize — every interaction must stay physical (paper sheets, interview rooms, courthouse sessions) or it collapses into menus, which D-003's philosophy forbids.

---

## Comparison

| Criterion | P1 Ledger | P2 Island | P3 Deal |
|---|---|---|---|
| Philosophy fit (information/consequence/immersion) | Strong | Strong | **Strongest** (discovery + omertà mechanics) |
| Consequence depth without jail timers | **Strong** | Medium (custody *is* gameplay, but is still custody) | Strong |
| Innocent-player experience | Good | Good | **Best** (weak cases visibly priced) |
| Lawyer gameplay | Good | Good | **Defining** |
| Informant/witness integration | Good | Good | **Defining** |
| Family/institutional gameplay | Good | **Richest** (visitation, rescue, inside rule) | **Richest** (trust doctrine, leak-hunting) |
| Low-population resilience | **Best** (fully NPC-resolvable) | Weakest (splits small population) | Strong (NPC DA scales down fine) |
| Dev cost (systems) | **Lowest** | Highest | Medium-high (tables + document/scene UX) |
| Map/content cost | **None new** | Facility required | Courthouse room + interview room |
| Abuse/griefing surface | Low | Medium (contraband/griefing in confinement) | Medium (deal metagaming; needs sealed-record discipline) |
| Tuning burden | Low | Medium | High |

## Recommendation

**Hybrid: "The Ledger" as the spine, "The Deal" as the resolution layer — "The Island" deferred as a post-MVP expansion.**

Concretely: Proposal 1 supplies the consequence machinery (booking, records, fines, probation, forfeiture, community service, appeals, bail) — it is the cheapest to build, needs no new map space, and resolves fully under NPCs at any population. Proposal 3's offer-sheet mechanic replaces Proposal 1's bare disposition step as *the way consequences are assigned*: even a reduced first version (one offer + accept/contest, excerpt-based discovery) delivers the omertà tension and the discovery intelligence game that make this system a defining feature rather than a punishment mechanic — which is precisely the commission. Proposal 2 composes cleanly on top later: when a facility is worth building (population and map budget permitting), the top sentencing band routes into it with no rework of the spine.

**Proposed MVP slice (M18), pending selection:** booking scene (search/prints/photo/one payphone call) → deterministic arraignment with exclusion math → offer sheet v1 (schedule plea / cooperate / contest, evidence excerpt) → consequence bundle v1 (fines, restitution, probation with observed-violation enforcement, forfeiture, record tiers) → bail + bench warrants → informant flip via cooperation offer → lawyer role v1 (retention, band-shifting representation, suppression motion, expungement) → newspaper/archive integration. Deferred within the hybrid: trials (contest path resolves via re-scored disposition until the docket ships), appeals beyond suppression-error, community service tasks, telegram-era paperwork flourishes.

**Status: RECOMMENDED (P-002), awaiting project-lead selection.** On selection, the chosen design folds into GDD §17+, Tech (new JusticeService section), and roadmap M18's design review.
