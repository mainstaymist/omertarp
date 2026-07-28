# Design Review — M19: Injury, Incapacitation, and Medical Care

Status: **AWAITING APPROVAL**
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
