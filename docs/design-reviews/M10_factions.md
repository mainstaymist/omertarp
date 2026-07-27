# Design Review — M10: Factions Core (Families and the Police Department)

Status: **AWAITING APPROVAL — no implementation until approved.**
Milestone: M10 (roadmap Track B — the first milestone that is not a foundation). Depends on: M0–M5, M9. Consumed by: M11 (treasuries belong to organizations), M12 (private lines are bought by them), M13 (businesses are owned by them), M14 (crews commit robberies), M17/M18 (the PD is an institution with authority), M20 (a confirmed kill triggers succession), M21 (the newspaper names institutions, not people).

> **Three rulings needed** (§4): the season bootstrap Q-1 left open, what being inducted actually *teaches* you, and whether the police department is the same system with a different ladder or a deliberately different one.

## 1. Purpose

Institutions are what make this game a world rather than a lobby. A character dies and their rank vacates; a season ends and the wealth resets; the Marino family is still the Marino family. Everything in Track B hangs off this milestone — there is no treasury without something to own it, no procurement without a rank to gate it, no succession without a chain to descend.

M10 builds the institution, its roster, its ladder, and the rules by which someone climbs it or is thrown off it. It builds no economy (M11), no territory (M13), and no authority to arrest (M17).

## 2. Responsibilities

**In scope:** organization definitions (data-driven, in code) and their per-season instances; rank ladders for both institution types; configurable rank permissions; membership with sponsorship, invitation and acceptance; promotion, demotion, expulsion and resignation, all server-authoritative and audited; acting authority and succession (Tech §19); the roster and who may see it; the D-009 track transition that family recruitment triggers; a written leadership-rules specification for players.

**Out of scope:** the treasury and its ledger (M11 — the organization *owns* one, this milestone does not build it); procurement (M11); organization-owned property and businesses (M13); crews and operations (M14); police authority to detain, search or arrest (M17); informant and corrupt-officer overlays (D-009 calls them covert overlays — they are not membership and are not built here); NPC-run institutions.

## 3. Public API

```lua
-- Institution definitions (code, like item definitions — behaviour and balance)
Omerta.Organizations.Define(key, {
    name = "Marino Family", type = "family",
    ladder = "family",              -- which rank ladder it uses
    colours = { ... },              -- for the newspaper, not for a HUD
})

Omerta.Organizations.DefineLadder(id, {
    { key = "associate",  name = "Associate",  grants = { "family.speak" } },
    { key = "soldier",    name = "Soldier",    grants = { "family.recruit_provisional" } },
    -- ... ascending; index IS the rank number
})

-- Per-season instances
Omerta.Organizations.Get(key)                    -- this season's instance
Omerta.Organizations.MembershipOf(characterId)   -- { org, rank, since } or nil
Omerta.Organizations.Roster(orgId, viewerId, cb) -- what THIS viewer may see

-- Permissions — the only question gameplay ever asks
Omerta.Organizations.Can(characterId, permission)

-- Membership changes (server; every one audited)
Omerta.Organizations.Invite(sponsorId, targetId, rank, cb)
Omerta.Organizations.Accept(targetId, cb) / Decline(targetId)
Omerta.Organizations.SetRank(actorId, targetId, rank, reason, cb)
Omerta.Organizations.Expel(actorId, targetId, reason, cb)
Omerta.Organizations.Resign(characterId, cb)

-- Authority
Omerta.Organizations.Leader(orgId)          -- the seated leader, online or not
Omerta.Organizations.ActingAuthority(orgId) -- who actually holds it right now
```

## 4. The Rulings

### 4a. Q-1 — how a season starts

Institutions "exist even when empty" (GDD §4.1), which is a fine principle and not a procedure. Somebody has to be the first Don of an empty family, and the design has never said who.

- **(a) Two active families at launch, seeded by staff from pre-season applications; the other two open mid-season by staff decision** — recommended, and what the Phase 1 review proposed. Two gives a real rivalry with enough players in each to feel like an organization; four at launch spreads a small population so thin that every family is three people who never meet anyone. Opening the third and fourth as the population justifies it makes expansion an event players notice.
- **(b) All four active from the start.** Truest to GDD §4.1, and the failure mode is a season where no family reaches critical mass.
- **(c) One family, plus the PD.** Maximum density, no rivalry — and family rivalry is most of the criminal content.

**Recommendation: (a).** With one addition: the number of active families is **configuration, not code**, so a season that fills up can open a third without a patch.

On succession from the seed: the staff-appointed Don is a normal Don from that moment. If they leave, §4's ordinary rules apply — staff do not re-seed a running season.

### 4b. What does being made actually teach you?

This is the milestone's real design problem, and it runs straight into the project's first principle.

A family that hands every new soldier a list of names would violate the rule this game exists to enforce. A family where nobody knows who anybody is has no reason to be a family at all.

- **(a) Induction is a formal introduction; the roster is rank-gated** — recommended. Being made is an *event* that happens in a room: everyone present at the induction learns the new member and the new member learns them, through M5's ordinary identity machinery, with no magical grant. Above that, the ability to *read the roster* is a rank permission — a Capo can see who reports to them, a Don sees the family. A soldier knows the people they have actually met, which is exactly how the real thing worked.
- **(b) Membership grants mutual knowledge of everyone at or below your rank.** Convenient, and it quietly turns "who is in the Marino family" into information the game gives away — the exact failure D-015 and M6 were built to prevent.
- **(c) No grant at all, and no roster.** Purest, and it makes running an organization of more than five people impossible.

**Recommendation: (a).** It costs one thing — an induction has to happen somewhere, with people present — and that cost is the feature.

### 4c. Is the police department the same system?

Structurally the PD is an institution with a roster and a ladder, and it would be a mistake to write it twice. But there is one asymmetry that is not cosmetic: **a uniformed officer is publicly identifiable as an officer.** A badge and a uniform are a deliberate announcement. Family membership is the opposite — its value is that nobody can prove it.

- **(a) One system, one asymmetry: police rank is visible on a uniformed officer, family rank is never visible** — recommended. Same tables, same ladder mechanism, same permission model. The difference is a single property on the institution definition (`public = true`), which M5's name resolution consults: a uniformed officer resolves as "Officer" to strangers instead of "Unknown", and as "Officer Marino" to those who know them. Out of uniform they are a stranger like anyone else, which is what makes plain clothes worth wearing.
- **(b) Fully symmetrical** — the PD is exactly a family with different rank names. Simplest, and it throws away the one piece of public information the setting genuinely has.
- **(c) A separate police module.** Duplicated logic for one property's worth of difference.

**Recommendation: (a).** The uniform, not the institution, is what makes an officer visible — which means the asymmetry is really about clothing, and lands on the seam D-014 already built.

## 5. Networking

| Message | Direction | Payload |
|---|---|---|
| `org.self` | server → client | your own membership: org index, rank, permissions bitfield |
| `org.roster_request` | client → server | organization (uint 8) |
| `org.roster_entry` | server → client | one member you are permitted to see |
| `org.invite` | server → client | sponsor entity, organization, offered rank |
| `org.invite_reply` | client → server | accept (bool) |
| `org.action` | client → server | action (uint 4), target entity, rank |

**No networked variable carries membership, and no GMod team is created.** M6's audit treats a second team as a leak by construction, and it is right to: teams are readable by every client, so a family team would publish the entire criminal underworld to anyone with a Lua console. Membership travels only as `org.self` to its owner and as roster entries to those with permission.

## 6. Persistence

Migration 8:

```lua
organizations: id(id), season_id ref NOT NULL, key text(32) NOT NULL,
               type text(16) NOT NULL, status text(16) NOT NULL DEFAULT 'active',
               leader_character_id ref, created_at timestamp NOT NULL
               unique: (season_id, key)

organization_members: organization_id ref NOT NULL, character_id ref NOT NULL,
                      rank int NOT NULL, joined_at timestamp NOT NULL,
                      sponsor_character_id ref, status text(16) NOT NULL,
                      left_at timestamp
                      primary: (organization_id, character_id)
                      indexes: (character_id), (organization_id, rank)
```

Organizations are **season-scoped instances of code-defined institutions**: the Marino family is a definition in version control, and each season gets a fresh row with a fresh roster and a fresh Don. That is what "institutions persist while characters, ranks and wealth reset" means in a schema.

Rank ladders and permissions live in **code**, not the database, for the same reason item definitions do — they are balance, and balance belongs where it can be reviewed and rolled back. Per-rank permissions are overridable through the config file (Tech §10 requires them configurable) without touching Lua.

Membership history is kept, not deleted: `status` and `left_at` mean "who was in this family in week two" stays answerable, which M15 and M21 will both want.

## 7. Security Considerations

- **Every rank change is checked against the actor's own permissions, server-side.** The client sends "promote that person"; the server decides whether they may, whether the target is theirs to promote, and whether the rank is one the actor outranks. A client cannot name a rank above its own authority.
- **You cannot promote yourself**, and you cannot promote past your own rank. Both are checked, not assumed.
- **Acting authority is computed, never stored.** It is derived from the ladder, the roster and who is currently connected — so it cannot be left stale by a crash, and there is no "acting Don" row for a bug to leave behind.
- **Every membership event is audited** (Tech §23) with actor, target, rank, reason and timestamp. "Who let him in" is the first question staff will ever ask about a leak.
- **Invitations are consent-based and expire**, following M5's introduction-prompt precedent: an invitation names a specific person, and a reply pointing anywhere else is discarded.
- **Membership is never inferred from anything a client can read** (§5).

## 8. Dependencies

M0 (config, net, log), M1 (migration 8, transactions), M2 (audit), M3 (season scoping — an organization instance belongs to exactly one season), M4 (members are characters), M5 (induction uses the identity system; §4b), M9 (M11 will tag organization property, and the column already exists).

D-009 is load-bearing here: **family recruitment is what performs the independent → criminal track transition**, one-way and audited. M10 owns that flow.

## 9. Future Extension Points

- **`Omerta.Organizations.Can` is the seam** every later milestone gates on: M11 asks it about spending, M13 about property, M14 about ordering an operation, M17 about police authority.
- **`DefineLadder` and `Define`** mean a fifth family, or a Sheriff's Department, is a data change.
- `leader_character_id` and the computed acting chain are what M20's succession cascade drives.
- The `public` property (§4c) is the hook clothing and disguises will use to make a uniform removable.
- Membership history supports M21's "the Marino family has lost three soldiers this week" without another table.

## 10. Architecture Rationale and Alternatives Rejected

**Rejected — GMod teams for factions.** They are readable by every client (§5), and M6's leak audit would flag them immediately. This is the single most common way a Garry's Mod RP gamemode leaks its entire social graph.

**Rejected — a separate police module** (§4c). One property's difference does not justify a parallel implementation that will drift.

**Rejected — ranks in the database.** Balance belongs in version control. Per-rank *permissions* are configurable because Tech §10 requires it; the ladder itself is not editable live.

**Rejected — storing acting authority.** A derived value that is stored is a derived value that can be wrong.

**Rejected — auto-filling a vacant leadership seat.** Acting authority is automatic and temporary so the organization does not freeze; *permanent* succession is an appointment somebody makes, because who ends up running a family after a Don is killed is the most interesting decision in the game and should not be resolved by a sort function.

## 11. Testing Strategy

- **Headless**: the permission resolver across a whole ladder, including the "cannot promote past yourself" and "cannot promote yourself" rules; the acting-authority chain with every combination of who is offline; rank validation; the D-009 transition matrix as applied by recruitment; ladder definition validation; migration 8 rendering.
- **In-engine** (`omerta_org_selftest`): a synthetic organization and synthetic characters through the full recruit → associate → soldier → capo chain, with permission gates asserted at each step; a demotion; an expulsion; a resignation; the Don going offline and authority descending; full cleanup.
- **The lived test**: two players, one Don and one outsider — sponsor, invite, accept, promote, and confirm the newcomer's account track flipped to criminal and every step appears in the audit log. Then the Don disconnects and the Underboss finds they can suddenly approve things.

## 12. Integration With Existing Systems

`modules/organizations/`, `depends = { "characters", "identity", "interaction", "chat" }`. Registers "Offer Membership" with M5's interaction framework. M5's `ResolveDisplayName` gains the uniformed-officer case from §4c — the first change to that function since M6, and the reason §4c needs a ruling before code is written. Nothing in M0–M9 changes otherwise.

---

**Requesting approval to implement M10 as specified**, with rulings on §4a (season bootstrap — recommend two families, staff-seeded, count configurable), §4b (what induction teaches — recommend formal introduction plus a rank-gated roster), and §4c (police symmetry — recommend one system with visibility carried by the uniform).
