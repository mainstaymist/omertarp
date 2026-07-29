# Design Review — M19: Injury, Incapacitation, and Medical Care

Status: **APPROVED 2026-07-28 — §4a (a) persistent body entity, §4b (b) bleed out and die, §4c (a) light decaying penalty.** §4b was ruled against my recommendation; the ruling stands and §4d records what it changes. Logged as D-037.
Milestone: M19 (roadmap Track D). Depends on: M5 (interactions), M8 (the injury indicator seam, the speed modifiers), M9 (stabilization items, searching a body), M13 (the clinic is a business). Consumed by: M20 (confirmed death is the interaction this milestone refuses to build), M14 (a robbery that can put someone down), M15 (a body is evidence), M16/M17 (arrest is an interaction on an incapacitated person), M21 (a death needs to have happened somewhere).

> **Three rulings needed** (§4): what an incapacitated character physically *is*, what happens to one nobody helps, and whether losing a fight costs anything once you are back on your feet.

## 1. Purpose

Thirteen milestones in, a gunfight still ends the way it does in every other Garry's Mod gamemode: the loser dies, respawns, and walks back. Nothing in the codebase touches `PlayerDeath` — I checked, there is not one hook — which means the single sentence the entire consequence design rests on is currently false:

> Combat is dangerous. Most defeats create injuries and recovery; deliberate confirmed killings permanently end characters. (GDD §4)

M19 makes losing a fight into a *situation* instead of an event. You go down, you stay in the world, and what happens next is a decision somebody standing over you gets to make: leave you, rob you, carry you somewhere, patch you up, hand you to the police, or — from M20 — finish it. That decision is the whole point. Every system built so far assumes it exists: M14's robberies need a way to lose that is not a respawn, M15 needs a body to gather evidence around, M17 needs somebody arrestable, M20 needs something to confirm, and M13's clinic has been sitting in the type registry since last week doing nothing because there are no injuries to treat.

It is also the milestone that makes the information game load-bearing. If a defeat costs nothing, fighting is cheap and talking is optional.

## 2. Responsibilities

**In scope:** the state machine (Tech §17) and its persistence; intercepting lethal damage so a character is incapacitated rather than killed; the incapacitated character as a thing in the world that can be carried, searched, treated and (later) arrested or killed; stabilization items; the hospital as the fallback route out; M13's clinic as the player-run route; recovery timers; the injury indicator through M8's seam; the communication restrictions Tech §17 lists.

**Out of scope, and deliberately:**

- **Confirmed death (M20).** M19 defines the `dead` state and the one function that reaches it; it does not build the interaction that calls it, the cascade behind it, or the rules spec that governs it. Until M20 ships, nothing in the game can permanently kill a character — which is the correct order, because a permadeath mechanism with no audit trail, no succession and no newspaper is a mechanism that will be used before it can be reviewed.
- **Weapons (M14, Q-10).** M19 consumes ordinary engine damage. What produces that damage is somebody else's milestone.
- **Arrest (M17).** M19 ships the seam an arrest hooks into and registers nothing on it.
- **Permanent impairments.** Tech §17 marks these "optional later" and they stay there; §4c is about *temporary* recovery cost only.
- **Body decomposition, funerals, morgues (M20+).**

## 3. Public API

```lua
-- State (shared; the enum and the pure transition rules)
Omerta.Injury.STATE = {
    HEALTHY = "healthy", INJURED = "injured", CRITICAL = "critical",
    INCAPACITATED = "incapacitated", STABILIZED = "stabilized",
    RECOVERING = "recovering", DEAD = "dead",
}
Omerta.Injury.CanTransition(from, to)          -- pure; the legal-move table
Omerta.Injury.StateForHealth(health, current)  -- pure; damage -> state
Omerta.Injury.Describe(state)                  -- "You are bleeding badly." Never a number.
Omerta.Injury.IsDown(state)                    -- incapacitated or stabilized

-- Runtime (server)
Omerta.Injury.Get(ply)  / Omerta.Injury.GetByCharacter(characterId)
Omerta.Injury.Set(characterId, state, reason, cb)   -- audited, transactional
Omerta.Injury.Treat(actorPly, target, method, cb)   -- item | hospital | clinic
Omerta.Injury.Revive(characterId, toState, cb)      -- the way back up

-- Bodies (server)
Omerta.Injury.BodyOf(characterId)              -- the entity, or nil
Omerta.Injury.CharacterOfBody(ent)
Omerta.Injury.CarriedBy(ply)                   -- what this player is carrying

-- Seams for later milestones
Omerta.Injury.RegisterTreatment(id, {          -- M13's clinic, M11's medical supplies
    label = "Treat", range = 72, duration = 6,
    predicate = function(actorPly, targetChar) end,
    onComplete = function(actorPly, targetChar, cb) end,
})
Omerta.Injury.RegisterDownedAction(id, def)    -- M17's arrest, M20's confirm kill
Omerta.Injury.RegisterDamageFilter(id, fn)     -- fn(ply, dmg) -> multiplier
```

Note the shape of the last three. M19 is the second-to-last milestone that gets to define what "being at someone's mercy" means, and both of the milestones that need to add to it (M17, M20) are downstream. They register; they do not edit this module.

## 4. The Rulings

### 4a. What is an incapacitated character, physically?

This is the largest decision in the milestone and everything else bends around it. The question is what actually exists in the world when you go down.

- **(a) A persistent body entity.** The moment you are incapacitated an `omerta_body` is spawned holding your character id; your player entity is frozen, hidden and made non-solid, and your view is held at the body. Everything that touches you — carrying, searching, treating, arresting, killing — touches the body. **The body stays when you disconnect.**
- **(b) The player entity, ragdolled in place.** No second entity, no duplicated state; one thing in the world that is you. Disconnecting removes it, because a disconnected player has no entity.
- **(c) Hybrid**: the player entity while connected, a body spawned only on disconnect.

**Recommendation: (a),** and the deciding argument is not tidiness, it is combat logging.

Under (b), the counterplay to being shot is Alt-F4. Your body vanishes, your character is untouchable, and you reconnect somewhere safe. That is not a small exploit — it makes M20's confirmed kill *optional for the victim*, and a permadeath system that the victim can opt out of is not a permadeath system. Everything downstream inherits the hole: a robbery you can log out of, an arrest you can log out of, a body that stops being evidence when its owner quits.

(c) closes the same hole but pays for it with two code paths for every interaction — one against a player, one against a body — which is precisely the duplication the project's principles exist to prevent, and the pair will drift the first time either is touched.

(a) has real costs and I would rather name them now: the view has to be managed manually while you are down, your inventory is owned by a character whose player entity is hidden, and a body left by a disconnect needs a lifetime policy (I propose it persists until the state resolves, and the state's own timer under §4b resolves it). All three are bounded and testable. Log-out-to-escape is neither.

**One consequence worth stating explicitly:** a body is a *person*, so it does **not** get a D-033 object label. Looking at one runs the same `ResolveDisplayName` path M5 uses for a standing player — you recognise the man on the floor if and only if you would have recognised him upright, and a masked body stays Unknown. D-033 draws the line at objects naming themselves; a body is on the other side of it.

### 4b. What happens to an incapacitated character nobody helps?

- **(a) A timer runs out and they wake up Recovering, in hospital.** Time lost, whatever was taken from them gone, a hospital bill if we want one. **Permanent death requires somebody to deliberately cause it.**
- **(b) They bleed out and die permanently.**
- **(c) They stay down indefinitely until somebody acts.**

**RULED: (b) — an untreated incapacitated character bleeds out and dies.** My recommendation was (a) and the reasoning below is left standing as the record of what was weighed. §4d covers what the ruling changes.

One correction to my own argument, in fairness to the ruling: I framed (b) as contradicting GDD §19.2, and it is at least as fair to read bleeding out from untreated gunshot wounds as precisely the *"explicitly terminal circumstance"* that clause already carves out. On that reading the ruling exercises the GDD's own escape hatch rather than overriding it. Either way DECISIONS.md outranks the GDD, so the ruling governs.

---

*Original recommendation, retained as the record:*

**Recommendation: (a).**

(b) contradicts a design document I cannot override: *"A character permanently dies only through a deliberate confirmed kill or an explicitly terminal circumstance"* (GDD §19.2). Bleeding out on a pavement because nobody happened to walk past is neither deliberate nor explicit — it is permadeath by server population, and it would make firefights during quiet hours categorically more lethal than the same firefight at peak. It also quietly deletes M20's reason to exist: why perform a deliberate, logged, interruptible confirm-kill when waiting ninety seconds does the same job with no evidence and no witnesses? **(b) would make the safest way to murder someone doing nothing at all**, which is exactly backwards for a game about consequence.

(c) leaves a player face-down with nothing to do and no end in sight, which is a support ticket, not a mechanic.

(a) keeps the cost real — you lost the fight, you lost the time, you lost what was in your pockets, and you are in hospital where anyone watching the hospital can see you arrive — without making the cost permanent. The ambulance is the fallback, not a rescue: it takes long enough that a friend who wants to reach you first has a genuine window, which is where the clinic and the stabilization item earn their place.

### 4c. Does losing a fight cost anything after you are back up?

Tech §17 lists persistent impairments as "optional later", so this is genuinely open.

- **(a) Recovering is a real state with a decaying penalty**: slower, and stamina regenerates worse, for a configured window after you are back on your feet.
- **(b) Recovery is a timer and nothing else** — when it ends you are Healthy, indistinguishable from someone who was never shot.

**Recommendation: (a), lightly.**

Under (b) the entire cost of being shot is the minutes you spent horizontal, which means a firefight has no aftermath and the correct play after any loss is to go straight back. That erodes the reason to avoid fights, and the reason to avoid fights is what keeps the social and information game primary — which is the game.

Under (a), the hour after a shooting is one you spend carefully: you are slower, you tire faster, you would rather not be seen. That is atmosphere and mechanics agreeing, and it costs almost nothing to build — `Omerta.Stamina.RegisterSpeedModifier` and `RegisterRegenModifier` already exist and M9's hunger already uses both, so M19 registers two more functions and writes no new machinery. It is also easy to tune to nothing (set the multiplier to 1) if it plays badly, which (b) is not easy to add to later once nobody expects it.

**D-034 calibration note:** whatever multiplier we choose is measured against the new base of 100/200, not the old 200/400, and the slow floor (25% of walk) is now the hard limit. An injury multiplier below 0.25 will be silently clamped.

### 4d. What the §4b ruling changes (recorded, not re-argued)

Bleeding out is reachable by a *timer*, which means **M19 now ships permanent character death** — the thing §2 explicitly put out of scope on the assumption that only M20's interaction could reach `dead`. That is a real scope change and it is handled, not absorbed silently.

**One death funnel.** `Omerta.Injury.Die(characterId, cause, actorCharacterId, cb)` becomes the single path to `dead`. The bleed-out timer calls it. M20's confirm-kill interaction will call the same function, so nothing is built twice and the cascade cannot diverge between the two ways of dying. M19 performs the parts it owns — status, audit row, injury event, the body becoming a corpse, the player routed to new-character creation — and fires `Omerta.CharacterDied` for everything else. M10 exists, so rank removal and succession wire in now; M21's newspaper and M22's archive listen when they exist.

**M20 still has a reason to exist**, and it is a better one than before. Bleeding out is *slow and uncertain*: the timer is long enough that anyone walking past can interrupt it with a bandage, so leaving someone to die is a gamble on nobody finding them. The confirm kill is *fast and certain*, and costs you a deliberate, logged, interruptible act with a witness surface. That is a genuine strategic choice — patience and deniability against speed and certainty — and it is a better shape for M20 than "the only way to kill anyone".

**The population problem is a knob, not an argument.** `injury.bleed_out_seconds` defaults to five minutes, long enough that rescue is real at any population, and an operator running a quiet server can raise it. Lethality becomes something the server tunes rather than something the clock decides.

**Combat logging now cuts the right way.** Under §4a the body persists through a disconnect, and under §4b its timer keeps running. Logging out while incapacitated is no longer an escape from a confirmed kill — it is the most reliable way to die. The two rulings reinforce each other.

## 5. Networking

Four messages. All of them tell a client about *itself* or about what it can plainly see.

| Message | Direction | Payload | Notes |
|---|---|---|---|
| `injury.state` | server → client | state (uint 3) | Your own state only. Drives M8's indicator. |
| `injury.prompt` | server → client | text (string 64), seconds (uint 8) | "You are being carried", "Bandaging…" — the progress the actor and the target both need to see. |
| `injury.action` | client → server | target (uint 16), action (uint 8) | Rides M5's existing interaction path; listed for completeness. |
| `injury.carry` | server → client | carrying (bool), target (uint 16) | So the client can draw the carry state and suppress what it must. |

**No state is networked about other people.** A body's state is not an `NWVar` and not in its `SetupDataTables` — M6's rule, and the reason is concrete here: a networked state field would let every client in the room read whether the man on the floor has been stabilized, which is exactly the information a doctor is paid to establish by kneeling next to him. What a bystander learns, they learn from the animation and from being told.

The health *number* is never sent to anyone, including its owner (GDD §8). `Omerta.Injury.Describe` returns prose.

## 6. Persistence

Migration **12**, three tables.

```
character_injury      character_id (pk), state, since, expires_at, treated_by_character_id, note
bodies                id, season_id, character_id, map_name, pos_x/y/z, ang_y, state, created_at
injury_events         id, season_id, character_id, from_state, to_state, cause,
                      actor_character_id, at
```

`character_injury` is the truth. The body is a *representation* — it can be destroyed by a map cleanup and respawned from the row, exactly as M9's dropped items already work.

`injury_events` is append-only and is the reason this milestone has a table it could technically live without: M15 will want to know a body was moved, M17 will want to know who treated whom, M21 will want to know a shooting happened, and M24 will be asked "who put him down and who picked him up". Reconstructing that from an audit log written for a different purpose is how you end up unable to answer it. It costs one insert per transition.

**A server restart must not heal anybody.** State loads on boot, bodies respawn where they fell, and timers resume from `expires_at` rather than restarting — a restart that resets the ambulance clock is a restart that rescues everyone who was about to be robbed.

## 7. Security Considerations

- **Every transition is server-side**, driven by damage the server observed. The client is told its own state for display and cannot request one.
- **Damage interception must be total.** If any damage path reaches `PlayerDeath` for a loaded character, that character respawns and the milestone has failed silently for that case. The self-test drives lethal damage from several sources — bullet, fall, fire, crush, `ply:Kill()` — and asserts the state, not the survival.
- **Carrying is validated continuously, not once.** Range is re-checked every tick server-side; a carrier who is killed, disconnects, or is separated from the body drops it. A client that stops sending anything does not get to keep a body attached to it.
- **Actions on a body are re-validated by the server against the body's real position**, not against where the client says it is — M5's existing rule, restated because a carried body is the first target in the game that *moves while you are acting on it*.
- **Treatment cannot be self-administered while incapacitated.** Otherwise the state is a two-second inconvenience.
- **No identity leak**: a body resolves through `ResolveDisplayName` (§4a), so an unknown or masked victim stays unknown. Concealment (D-014) applies to a body exactly as to a person.

## 8. Dependencies

M4 (characters and status), M5 (interactions, identity resolution), M8 (`RegisterInjuryProvider` — built for this and empty since; the speed and regen modifier seams; `Omerta.Stamina.Drain`, whose comment already says "carrying a body (M19)"), M9 (stabilization items, searching, capacity while carrying), M13 (the clinic type, registered last week and explicitly deferred to this milestone), M11 (medical supplies are already in the procurement catalogue).

Every one of those is a seam that already exists. M19 registers into them and edits none of them — which is the test of whether M8 and M9 were designed correctly, and I would rather find out here than in M20.

## 9. Future Extension Points

- `RegisterDownedAction` is **M17's arrest and M20's confirm kill**. Both are actions on a downed character with a predicate and a duration; neither needs this module changed.
- `RegisterTreatment` is how a future surgeon, a better bandage, or a bribeable ambulance driver gets added.
- `RegisterDamageFilter` is where armour, a heavy coat, or M14's weapon-specific damage lands.
- `injury_events` is the query surface for M15's evidence, M21's articles and M24's staff tooling.
- Permanent impairments (Tech §17) attach to `character_injury` as an extra column and a modifier registration, with no change to the state machine.

## 10. Architecture Rationale and Alternatives Rejected

**Rejected — a parallel health model.** Tracking our own hit points and ignoring `ply:Health()` means reimplementing falls, fire, drowning and crush damage, and getting them subtly wrong. Engine health stays the input; the state machine is the output. M14's weapons then need no special integration — they deal damage like anything else.

**Rejected — states as a number on the player entity.** An `NWInt` would be one line and would publish every character's medical condition to every client in the room (§5, M6).

**Rejected — treating "unconscious" as a HUD overlay on a living player.** It is the cheap version of §4a(b) and it has the same hole: nothing in the world represents you, so nothing persists when you leave.

**Rejected — building confirmed death here because it is only one more interaction.** It is one more interaction and an eight-step cascade (Tech §18), a succession trigger, an archive reference, a newspaper queue and a rules specification. Shipping the kill without the cascade means the first permadeath in the project's history happens through a code path nobody reviewed for it.

**Rejected — an injury *bar*.** GDD §8 lists health among the things never displayed. The player learns their state from prose and from what stops working.

## 11. Testing Strategy

**Headless (pure, no engine):** the transition table — every legal move, and that illegal ones are refused rather than silently applied; `StateForHealth` across the thresholds including the boundaries; the timer arithmetic under §4b, including resumption from a stored `expires_at` rather than from now; the recovery-penalty curve under §4c; `Describe` returning prose for every state and never a number.

**In-engine (`omerta_injury_selftest`):** lethal damage from five sources lands in Incapacitated and never in `PlayerDeath`; a body persists across the owner disconnecting and reconnecting; a body persists across a server restart, in place, with its timer resumed; carry → walk → drop leaves the body where it was dropped and the carrier slowed while carrying; searching a body yields its inventory through M9's existing path and respects M9's access predicate; each treatment route reaches Recovering; the untreated timer reaches Recovering by the hospital route; a masked body resolves as Unknown to someone who knows the character's face but has not seen it.

**The headline check**, in the style M8 set: *a character who takes lethal damage is still in the world sixty seconds later.*

## 12. Integration With Existing Systems

`modules/injury/`, `depends = { "characters", "interaction", "identity", "hud", "inventory", "business" }`.

Changes to already-shipped code, and there are only three:

1. **M8's injury element gets a provider.** One registration, no change to `cl_hud.lua` — the seam was built for this in M8 §9 and has been returning nil ever since.
2. **M9's search path gains a person as a valid target.** Today `inventory.search_container` only accepts an `omerta_container`; searching a body is the same operation against a different owner, and M9's container-access predicate already has the shape to answer "may I open this". This is the one place M19 touches an existing module's behaviour rather than registering into it, and it should be reviewed as part of M19 rather than assumed.
3. **M13's clinic becomes a business that does something.** Its `services` list gains `"medical"`, and the treatment registration keys off it. No change to the business framework.

Nothing in M0–M13 changes otherwise.

---

**Awaiting rulings on §4a, §4b and §4c before implementation begins.**

---

## 13. Implementation Notes (post-implementation)

Implemented as `modules/injury/` — nine files plus `omerta_body`. Suite grew from 279 to 298 checks. Notes worth keeping:

- **§4b's ruling made M19 bigger than §2 said it would be**, exactly as §4d predicted. `Omerta.Injury.Die` is the funnel; the bleed-out timer is its only caller today and M20's confirm kill will be the second. M19 does the parts it owns (status, audit, event, corpse, the player told) and fires `Omerta.CharacterDied` for the rest. **M10 can wire rank removal and succession to that hook without touching this module**, and M21/M22 listen when they exist.

- **Three seams were added to already-shipped modules**, which is two more than §12 predicted, and each replaced a hardcoded check rather than forking a path:
  - **M9 gained `RegisterOpenable`.** Opening a container tested `ent:GetClass() == "omerta_container"` — right while a crate was the only thing worth looking in, wrong the moment a person is. `openContainer` now remembers an *owner* rather than assuming a container, so searching a body reuses M9's transactional moves, capacity checks and access predicate. A downed character's pockets **are** their inventory, not a copy of it: two homes for one coat is how an item gets duplicated.
  - **M5 gained `RegisterSubjectProvider`.** Identity resolution rejected anything that was not a player. A body claims itself through the seam, so looking at one runs `ResolveDisplayName` per observer — you recognise the man on the floor if and only if you would have recognised him upright, and a masked body stays Unknown.
  - **M7 gained `RegisterChannelFilter`.** A dying man is down to a whisper. The same seam covers gags, and M18's holding cells.

- **A load-order bug was caught before it shipped, and it is the fourth of its kind.** Module files include shared-first then *alphabetically*, so `sv_injury.lua` loads before `sv_repository.lua`. A file-scope `local Repo = Internal.Repo` therefore captured nil — invisible until the first query. Every shipped module already referenced `Internal.Repo` at call time; that convention is now a lint (`lint.repo_capture`) rather than something to remember.

- **The two-step medicine works out better than expected in play terms.** A bandage moves Incapacitated → Stabilized and stops the clock killing you; only treatment reaches Recovering. So a passer-by with 300 cents of bandages can save a stranger's life in an alley without being able to end the situation — which gives the clinic a reason to exist and gives the person who put them down a reason to check whether they are still there.

- **Deadlines are absolute, never countdowns**, and there is a lint-adjacent test asserting the column is a timestamp. A restart that reset the bleed-out clock would rescue everyone who was about to die, making "wait for the nightly restart" a medical procedure.

- **`injury.enabled` exists** as a master switch. Permadeath is now reachable by a timer and M20's audit cascade does not exist yet; a test server that wants the state machine without the consequence turns it off in one config value.

- **The engine must never see zero health.** `EntityTakeDamage` clamps lethal damage and sets health to 1; `PlayerDeath` logs an error if a loaded character ever reaches it, because that means damage bypassed the state machine and the milestone has silently failed for that case.

In-engine acceptance (user-side): pull, restart, then `omerta_injury_selftest` (13 steps). Then manually: `omerta_injury_state incapacitated` on yourself to go down, watch the body appear and the urgency text fade in; have a second character pick you up, carry you (slowly), drop you, search you; `omerta_item_give medical.bandage` and stabilize; `omerta_injury_list` and `omerta_injury_history <id>`. **To see D-037 end to end, set `injury.bleed_out_seconds` low in `data/omertarp/config/server.txt` and leave somebody alone.**

---

## 14. Amendment — the body, the camera, and the end (2026-07-28)

A presentation pass over what §4a and §4b actually feel like. The state machine is unchanged; what happens on screen is not.

**The body is a real ragdoll.** The first implementation was a scripted `omerta_body` posed at a fixed angle, which read as a mannequin rather than a person. A scripted entity cannot *be* a ragdoll — `base_anim` is a `CBaseAnimating` and ragdoll bone data belongs to `CRagdollProp` — so the body is now a genuine `prop_ragdoll` that the module owns and tags. It inherits the character's pose bone-for-bone and their momentum, so somebody shot mid-sprint goes down travelling.

Three consequences, each handled rather than worked around:

- **`omerta_body.lua` is gone.** Interaction predicates, search and identity all key on `ent.OmertaCharacter`, which is server-side and works on any entity, so nothing there changed.
- **The interaction dot needed a predicate, not a class.** `RegisterInteractableClass("prop_ragdoll")` would light up for every ragdoll on the map, so M8 gained `RegisterInteractablePredicate`. The body answers it through a networked boolean that says *somebody is on the floor here* — visible from across the street anyway — and nothing about who.
- **`prop_ragdoll` has no `ENT:Use`**, so the E shortcut is a `PlayerUse` hook. Same server-side path as the menu.

**The camera stays in your head.** `CalcView` rides the ragdoll's `eyes` attachment, so as you fall the view falls with you and ends up looking at whatever your face ends up looking at. This is the reason the ragdoll mattered: a posed prop has nothing to hang a camera on. Mouse look, the viewmodel and the weapon selector are all suppressed while down — a mouse that moves nothing reads as broken rather than as helpless.

**The screen closes in.** A red vignette built from four edge gradients rather than a radial texture, so there is no asset that can fail to load. It eases in — barely there early, unmistakable at the end — and pulses on a heartbeat that quickens with the loss. It never fully closes: a black screen would hide the person kneeling over you, which is the one thing worth seeing. A ring above the text empties as the clock runs down.

**Stabilizing visibly stops it.** The vignette and the ring are driven by `IsDying`, which is `incapacitated` only. A bandage stops the clock, so the screen stops closing with it — the player learns the bandage worked without being shown a number.

**The end.** Trombone on the instant of death, no fade of its own since the file opens on one. The camera holds on the body for a beat, then pulls up and away to a **map-relative** top-down shot — traced against the ceiling first, so dying in a stairwell gives a lower shot rather than a view of the inside of the floor above. Screen fades to black, "You have died…" fades in at headline size with the prompt under it, and the piano fades in once the words have fully landed, looping with a quick dip at each end so the seam is a breath rather than a click.

**"press any key to begin again"**, not "reincarnate". Reincarnation means a soul returning, and nothing of the sort happens: a dead character stays dead, keeps nothing, and passes nothing on (GDD §19.3, D-012). What comes next is a different person in the same city, starting from nothing. Both strings are constants in `sh_injury.lua`.

**M4 gained a creation gate.** Death routes a player to new-character creation immediately, and a "make a new person" form appearing over the body of the old one is the wrong beat entirely. `Omerta.Characters.RegisterCreationGate` holds the window; M19 releases it on the keypress. M4 still knows nothing about injuries.

**The corpse stays.** Death clears the injury row and the live state but leaves the ragdoll in the world. A body is evidence (M15), it is what M20's funeral is for, and a city where the dead vanish is one where nobody can prove anything happened.

**Every presentation curve is in the shared file**, not the `cl_` files that draw them — the vignette reach, the heartbeat rate, the camera phases and easing, the fade timings, the loop envelope. Arithmetic in a `cl_` file is arithmetic nothing can test, which is the same reason M8 put `StepAlpha` in its shared file.

Suite: 298 → 305 checks.

### 14a. The fifth load-order bug (2026-07-28)

`cl_death.lua` captured `Omerta.Injury.Client` at file scope, and the table is created in `cl_injury.lua`. Files load shared → **client** → server, alphabetically within each realm, so `cl_death` is the *first* non-shared file in the module and the capture got nil. Nothing failed at load; it errored once per frame from the first `Think`.

That is the fifth bug of this shape on this project, and the lint I added with M19 only checked `Internal.Repo` — the exact table that had bitten us before, not the pattern. It is now `lint.include_order`, which models the loader's own ordering: for every file-scope capture of a module sub-table, it finds which file first creates that table and flags the capture if that file sorts later and the capturing file has no `X = X or {}` guard of its own.

Verified by reintroducing the bug and confirming the lint names the file, the line, the table and the file it is created in. A lint that passes on a clean tree proves nothing; the test was whether it fails on the dirty one.

### 14b. Presentation defects found in play (2026-07-28)

Nine symptoms reported, two root causes.

**One line wiped the entire death sequence.** `cl_view.lua` cleared the client's death state on `Omerta.CharactersState` — and death *sends* `NEEDS_CREATION`, so the state was destroyed the instant it was set. That alone accounted for five of the nine: no fade to black, no camera pull-away, no head attachment (the view fell back to the frozen player entity, floating where they had been standing), no piano, and the creation window opening immediately because the gate it consults was already nil. The hook now clears only on `ACTIVE` — a *new* character — which is what it always meant.

**The clock never moved.** `Internal.SendState` is called on state *change*, so the remaining time was sent once and never again. Progress stayed at zero, so the timer sat full and the vignette never grew; the only thing moving was the sine, which is exactly what "grew and then shrunk a little" describes. The client is now given a deadline and counts down against it locally — smooth, and no new traffic. The message carries the whole window as well, so a client reconnecting mid-bleed draws the right fraction instead of restarting the bar.

Four smaller ones:

- **The pulse was a strobe.** Up to three beats a second. Now 0.35–0.9, well under a real pulse, because on screen anything faster stops reading as a heartbeat.
- **The pulse retreated.** A symmetric sine spends half of every beat pulling the edges back out. It is now one-sided — `(1 - cos)/2`, which runs 0..1 — so the beat only ever pushes further in and relaxes to the base, never below it. Pinned by a test that fails against the old formula.
- **The ring is a line.** A radial timer over a dying man read as a loading spinner. It is a thin line above the words, closing from both ends toward its middle — the same gesture the vignette is making.
- **`sound.PlayFile` had the wrong flag.** `"noblock"` is a streaming flag for `PlayURL`; on a file it silently returns nothing, which is why the trombone played and the piano never did. Also made the request non-re-entrant: it is called from `Think`, so without a guard it fired a fresh load every frame until the first returned.

Also added a bone fallback for the head camera. The `eyes` attachment exists on every Half-Life 2 playermodel, but a custom model without one would have dropped the camera back to the player entity — a view floating in mid-air, which is the failure that was already visible.

Suite: 305 → 307 checks.

### 14c. Second presentation pass (2026-07-28)

**The downed camera was never attaching to the head, and the reason was a race.** The client resolved `Entity(index)` the instant `injury.body` arrived — which is the instant the ragdoll is created server-side, before it has replicated. `Entity()` returned NULL, `C.body` stayed invalid forever, and the view silently fell back to the frozen player entity. It only *looked* fixed on death because the death message carries its own entity reference and arrives later. The index is now stored and resolved on demand, which costs nothing and cannot lose the race. You watch yourself go down.

**The pan starts already looking down.** Tweening the pitch from wherever the head was lying round to straight down spends the whole shot in an orientation that is neither, which is the "awkward middleground". The rise now cuts to a top-down shot 80 units above the body and only *translates* upward. A cut is the normal grammar for this; the rotation was the awkward part.

**The screen goes quiet.** Chat hides on death but **not while bleeding out** — somebody dying can still be spoken to, and cutting them off from the room would remove the last thing they can do. All world audio is suppressed through `EntityEmitSound`, and both the trombone and the piano moved onto `sound.PlayFile` channels so the silence cannot reach them. The death screen mutes the world; it must not mute itself.

**Vision blurs as it goes.** Three light passes of `pp/blurscreen` under the vignette (order 4 against its 5), on the same squared curve, so the two read as one effect rather than two.

**Bodies are dragged, not carried, and anyone can do it.** Nobody picks a grown man up and walks off with him. It is modelled as a rope: slack for the first 52 units, taut by 130, grip fails at 210. Past the slack the body is pulled after you, eased so it creeps at light tension and only really moves once you lean on it. Hauling halves your speed and costs stamina in proportion to how hard you are pulling. On screen: a line from your hands to the body that reddens and shudders with tension, a fainter line back to where you took hold, and a word for what is happening.

The tension is **not networked**. The client has both positions and the rule is pure and shared, so it computes the same number the server enforces with, every frame, for free.

**A test caught a real balance inversion here.** `injury.drag_speed` was an absolute 90 units/sec while a hauler under D-034 walks at 55 — so the body would have *outrun the person pulling it* and the rope could never go taut. That is the second time an absolute movement number silently coupled to D-034. It is now `injury.drag_catchup`, a fraction of the hauler's own speed, and the test asserts the relationship holds at four different walk speeds rather than at the current one.

**Searching a body takes a moment, once.** Four seconds of "Searching…" the first time, through the existing timed-action machinery — interruptible by walking away, same as treatment. After that, that person can go through that body instantly: you already know what is in the coat, and making somebody wait again for information they have is a tax on the interface, not a cost in the fiction. Taking something out clears everyone *else's* memory of the pockets.

**A body has a tooltip, and it is the identity system's answer.** `cl_identity.lua` only ever considered players, so the subject provider added in §12 had no client half and never fired. It now accepts registered predicates, so looking at a body resolves through `ResolveDisplayName` per observer — their name if you know them, Unknown if you do not, Unknown either way if their face is covered. D-033 keeps objects naming themselves and people not; a body is on the people side of that line, so the name comes from M5 and only the action hint ("Take hold, or search them") is drawn by M19.

Suite: 307 → 313 checks.

### 14d. Three defects from play (2026-07-28)

**A jump was free rest.** `StepStamina` only knew "sprinting or not", so the arc of a jump counted as standing still and regenerated — you paid the jump cost on the way up and earned it back before landing, which made a bunny-hopper recover faster than somebody standing still. Stamina is now held while airborne: no drain, and crucially no recovery. Catching your breath happens with your feet on the ground.

**A corpse could not be dragged, because death untagged it.** `OnDeath` cleared `OmertaCharacter` and the networked marker, with the comment "no longer searchable, still a corpse". That made the ragdoll inert — no dot, no tooltip, nothing to take hold of — which is backwards: **moving a body is the single most important thing anyone does with one.** Hiding it is what M15's evidence and M20's funeral are both about, and it is why the corpse was kept in the world in the first place.

A corpse now keeps its tag, its entry and its database row. What changes is the character's *state*, and the predicates read that: `IsDown` became `IsIncapable` for dragging and searching, since a corpse is as helpless as it gets. `ListActive` now includes the dead so bodies come back after a restart — a city where the dead vanish overnight is one where nobody can prove anything happened. Dragging your own former body is explicitly allowed; there is no reason to forbid it.

Also fixed a missing `return` in `Grab`: the "somebody already has them" branch reported the refusal and then took the body anyway.

**The cut to the top-down shot happened in vision.** It read as a glitch. The sequence now fades to black over the head shot, moves the camera *while nobody can see it*, and fades back in already looking down — which is how this shot is done everywhere else. The climb went from 5.5 s to 7.5 s and the whole thing is timed off derived constants (`CUT_AT`, `VISIBLE_AT`, `RISE_END`, `FADE_AT`) rather than independent numbers, so the phases cannot drift out of step with the fades. A test asserts the screen is fully black at the exact instant the camera cuts, and that instant is the first frame of the rise by construction rather than by two numbers happening to agree.

Suite: 313 → 317 checks.
