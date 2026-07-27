# Design Review — M5: Interaction Framework, Identity and Introductions

Status: **APPROVED 2026-07-27 — IMPLEMENTED** (§4a ruled one-way; logged as D-013 and D-014). See §13.
Milestone: M5 (roadmap Track A). Depends on: M0–M4. Consumed by: M6 (hidden population), M7 (local text speaker labels), M9 (inventory interactions), M13/M14 (business and crime interactions), M15 (witness descriptors), M17 (police identification).

> **This review asks for rulings on the five questions Tech §5 leaves open** (§4). One of my recommendations **differs from the Technical Design's own MVP suggestion** and is flagged as such — precedence says Tech wins, so it needs your explicit call to override.

## 1. Purpose

This is the milestone the design exists for. Everyone is **Unknown** until introduced; identity knowledge is stored per observer–subject pair; display names resolve per viewer; and **the identity map never leaves the server** (Tech §2). It also delivers the generic **interaction framework** — targeting something and choosing a context action — which every later physical system reuses.

## 2. Responsibilities

**In scope:** the interaction framework (target tracing, action registry, server-validated execution); the `identity_knowledge` table and service (migration 5); the introduction flow; per-observer name resolution with on-demand networking; a contextual target label (never a nameplate); the concealment seam for future disguises; audit of every identity disclosure (Tech §23).

**Out of scope:** local text and voice (M7 — it will call `ResolveDisplayName` for speaker labels); scoreboard and population hardening (M6); aliases and false names (§4b — post-MVP); police ID checks against records (M17); witness descriptors (M15); clothing and masks (their own content milestone — M5 ships the *seam* they plug into); any permanent HUD (M8).

## 3. Public API

```lua
-- Identity (server)
Omerta.Identity.Knows(observerCharId, subjectCharId)          -- boolean, from cache
Omerta.Identity.GetKnownName(observerCharId, subjectCharId)   -- string or nil
Omerta.Identity.Learn(observerCharId, subjectCharId, name, source, cb)
      -- source: "introduction" | "document" | "police_record" | "rumor" | "staff"
Omerta.Identity.Forget(observerCharId, subjectCharId, cb)     -- staff//witness protection
Omerta.Identity.ResolveDisplayName(observerChar, subjectChar) -- the one resolution rule

-- Concealment seam (M5 ships the hook; disguises implement it later)
Omerta.Identity.IsConcealed(subjectChar)                      -- false for now
Omerta.Identity.RegisterConcealmentProvider(fn)

-- Interaction framework (shared registry, server-validated)
Omerta.Interaction.Register(id, {
    label     = "Introduce Yourself",
    range     = 96,
    order     = 10,
    targets   = "player",                    -- "player" | "entity" | "any"
    predicate = function(ply, target) end,   -- server-side availability test
    run       = function(ply, target) end,   -- server-side execution
})
Omerta.Interaction.GetAvailable(ply, target)  -- server: ids the actor may use now

-- Hooks
hook.Run("Omerta.IdentityLearned", observerCharId, subjectCharId, name, source)
```

## 4. The Five Rulings (Tech §5)

### 4a. Mutual vs one-way introductions — **RECOMMENDATION DIFFERS FROM TECH §5**

Tech §5's MVP suggestion is *mutual* introduction: one interaction, both parties learn each other. **I recommend one-way with a one-click reciprocate prompt instead**, because mutual quietly destroys a piece of gameplay this project is built on: the ability to learn someone's name **without giving your own**. A capo who takes your name and offers nothing back is a power move the fiction runs on, and mutual-by-default makes it impossible.

The flow: A introduces themselves to B → B immediately learns A's name, and receives a prompt offering to introduce back. Accepting is one keypress, so the ordinary social case costs the same as mutual; declining (or ignoring) is the asymmetric case. Nobody is ever forced to disclose.

If you prefer to honour Tech §5 as written, say so and I will build mutual — it is strictly simpler.

### 4b. False names — **no, not at MVP** (matches Tech §5)

An introduction discloses the character's real name. Aliases are a post-MVP system with consequences (the Brainstorm's "should not erase legal identity"), and building them now would mean designing the discovery-of-deception mechanics too. The `learned_name` column is stored per pair *precisely* so aliases can later differ from the legal name without a schema change.

### 4c. Do police ID checks reveal legal names — **deferred to M17**, seam present

The `source` field already accepts `police_record`, so when M17 builds identification-by-record it calls `Learn` with that source and everything downstream works. No M5 work.

### 4d. Do masks block introduction — **no, but concealment blocks *recognition***

This is the subtle one, and it exposes a distinction the documents never quite draw:

- **Knowledge** is "I know that character is named Tony Marino" — permanent, per pair.
- **Recognition** is "the person standing in front of me *is* that character" — situational.

Resolution currently treats these as one thing, which would make masks useless against anyone who has met you. So the rule is: **a character whose face is concealed resolves as Unknown to everyone, regardless of knowledge** — including their own crew, who will have to rely on voice, which is correct and good. Knowledge is never lost; it simply cannot be applied to a face that cannot be seen.

M5 has no clothing system, so `IsConcealed` returns false and the seam sits unused until disguises land. Building the seam now costs nothing and prevents a painful retrofit of the resolution rule later.

### 4e. Does memory survive appearance changes — **yes**

Knowledge is bound to the character, not their outfit. Given 4d, changing clothes never erases what someone knows; concealing your face merely suspends its application.

## 5. Networking

The hardest requirement in the project: *never replicate the identity map* (Tech §2). Two rules make it structural:

1. **Resolution is per-observer and on demand.** The client asks "who is entity N?" only for a player it is currently looking at within range; the server validates the distance server-side, resolves against *that observer's* knowledge, and returns one name. A client can never enumerate.
2. **Nothing is pushed preemptively.** Sending a client everything it knows about who is online would let it infer presence — the exact metagame the design forbids. If you cannot see them, you learn nothing.

| Message | Direction | Payload |
|---|---|---|
| `identity.resolve` | client → server | entity index (uint 16) |
| `identity.name` | server → client | entity index, name (text 56), known (bool) |
| `identity.forget_cache` | server → client | entity index — invalidate on knowledge change/disconnect |
| `interaction.query` | client → server | entity index |
| `interaction.options` | server → client | up to 8 × { id (uint 8), label } |
| `interaction.execute` | client → server | entity index, action id (uint 8) |
| `identity.introduce_prompt` | server → client | who introduced (entity), their name |
| `identity.introduce_reply` | client → server | accept (bool) |

Client-side cache is keyed by entity **and** cleared on disconnect, character change, and knowledge updates, so a stale name can never outlive its subject.

## 6. Persistence

Migration 5:

```lua
identity_knowledge: observer_id ref NOT NULL, subject_id ref NOT NULL,
                    learned_name text(56) NOT NULL,
                    source text(16) NOT NULL, learned_at timestamp NOT NULL,
                    confidence int NOT NULL DEFAULT 100,
                    notes text(255)
                    primary(observer_id, subject_id)   -- Tech §2's composite key
                    indexes: (subject_id)              -- "who knows me?" for staff/M17
```

Character-scoped, so season-scoped by construction; no cross-season leakage. Loaded per player into a per-character cache on `Omerta.CharacterLoaded` — bounded by how many people that character has actually met, which is small. `confidence` and `notes` are unused at MVP and exist for rumor-sourced knowledge later (Tech §2).

## 7. Security Considerations

- **Distance is validated server-side** on resolution, interaction queries, and execution. The client's trace is a suggestion; the server re-traces.
- **Resolution is scoped to one observer's own row.** There is no API — internal or networked — that returns the knowledge of anyone else.
- **Introductions require proximity and mutual visibility** (both alive, in range, not incapacitated once M19 exists). Line-of-sight is deliberately *not* required at MVP: it is fiddly through doorways and adds little, but the check is one function call away if abuse appears.
- **Every disclosure is audited** (Tech §23): who learned whose name, when, by what source.
- **Rate limits** on resolution and introduction messages via the M0 net layer, so neither becomes a scraping tool.
- The interaction registry is server-authoritative: a client sending an action id it was never offered fails the predicate.

## 8. Dependencies

M0 (net, config, log, hooks), M1 (migration 5), M2 (audit), M3 (season scoping), M4 (characters — knowledge is character-to-character).

## 9. Future Extension Points

- **Interaction registry** is the reusable surface: M9 adds "Search", M13 "Buy", M14 "Rob", M19 "Treat", M20 "Confirm Kill" — each a `Register` call, no framework changes.
- **Concealment provider** (4d) is where masks and disguises attach.
- **`source`** already covers documents, police records and rumor for M15/M17.
- **`Forget`** is what witness protection and staff correction will call.
- **`confidence`/`notes`** carry uncertain, rumor-sourced identification later.

## 10. Architecture Rationale and Alternatives Rejected

**Rejected — replicating each client's knowledge table on spawn.** Simpler and faster, but it tells a client who is online before they see anyone. That is the metagame the entire design is built to prevent.

**Rejected — resolving names client-side from a shared roster.** Same leak, worse: the data would sit in the client's memory for any addon to read.

**Rejected — overhead nameplates for known characters.** Explicitly forbidden (Tech §6), and it would turn earned knowledge into an omniscient overlay.

**Rejected — mutual-only introductions** (§4a), pending your ruling.

**Rejected — tying knowledge to the player account rather than the character.** Death must sever relationships (GDD §19.3); account-scoped knowledge would quietly resurrect them.

## 11. Testing Strategy

- **Headless**: the resolution rule exhaustively (self, known, unknown, concealed-but-known, dead/missing subject); knowledge cache behaviour; interaction availability filtering by predicate and range; introduction state machine including decline and timeout; migration 5; repository SQL against the mock driver.
- **In-engine** (`omerta_identity_selftest`): synthetic characters, learn/resolve/forget round-trip, composite-key upsert, per-observer isolation (A knowing B must not make B know A), full cleanup.
- **The lived test, which needs two clients**: two players see "Unknown"; one introduces; the recipient sees a name while the introducer still sees Unknown until reciprocated; a third player sees neither.

## 12. Integration With Existing Systems

`modules/identity/` and `modules/interaction/` — two modules, because the interaction framework is genuinely general and five later milestones depend on it without caring about identity. `identity` depends on `interaction`, `characters`, `database`. M2's lifecycle contract as always. Nothing in M0–M4 changes.

---

## 13. Implementation Notes (post-implementation)

Implemented as `modules/interaction/` and `modules/identity/`. Headless suite grew to 115 checks. Notes:

- **§4a ruled one-way** (D-013). Introductions disclose only the introducer; the recipient gets a prompt (`E` to give their name, `R` to say nothing) valid for 20 seconds, bound to the specific person who introduced themselves — a reply naming anyone else is discarded.
- **The resolution rule is one pure function** (`ResolveDisplayName`), the single place the project's central rule is expressed, and it is the most heavily tested code in the codebase: self-recognition, known, unknown, empty-string-is-not-knowledge, missing subject, concealed-but-known, and concealed-self.
- **Concealment seam registered but unused** (D-014): no provider exists, so `IsConcealed` returns false until clothing lands. The self-test registers a temporary provider to prove the rule bites.
- **Fixed-width option slots** in `interaction.options`: the net schema validator has no repeat construct, so eight `{index, label}` pairs are declared and unused slots carry index 0 with an empty label. Slightly ugly on the wire, but it keeps every message strictly schema-validated, which is the property worth protecting.
- **Action ids travel as small integers** derived from a deterministic `order`-then-id sort computed identically in both realms, so the wire never carries action names.
- **Client cache is cleared aggressively** — on entity removal, on server invalidation, on character state change, on Lua refresh — because a stale name outliving its subject is exactly the leak this milestone exists to prevent.
- **Interaction key is `+menu_context`** (default `C`), held to open, released to execute the highlighted option, mouse wheel to select. Plain text rendering; M8 owns presentation.
- **Staff tool**: `omerta_identity_who_knows <characterId>` lists every character who knows them and how they learned it — the metagaming-investigation tool the hidden-identity design requires.

In-engine acceptance (user-side): pull, restart (watch for `applying migration 5: identity knowledge`), then `omerta_identity_selftest` (expect 11/11). The real test needs **two clients**: both see "Unknown" when looking at each other; one holds `C` and picks *Introduce Yourself*; the recipient sees the name and a prompt, and — crucially — the introducer still sees "Unknown" until the other reciprocates with `E`. That asymmetry is the whole point of D-013.
