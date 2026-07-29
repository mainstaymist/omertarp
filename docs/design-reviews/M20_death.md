# Design Review — M20: Confirmed Death and Succession

Status: **APPROVED 2026-07-28 — §4a (a) yes, down is down; §4b (a) empty the chair; §4c (a) it stays on the body.** All three as recommended. The §2 scope decision (M20 builds the EventService) was not contested and is taken as confirmed. Logged as D-038. **IMPLEMENTED** — see §13.
Milestone: M20 (roadmap Track D). Depends on: M19 (the funnel and the seam), M10 (rosters, ranks, the leader's chair), M9 (what is in the pockets), M11 (what the family paid for). Consumed by: M21 (a death is the story), M22 (an archive is what is left), M15/M17 (a body is evidence and a case), M14 (a robbery that goes wrong).

> **Three rulings** (§4, all answered): whether a man who has been bandaged can still be finished, whether death seats a successor or only empties the chair, and what happens to what the dead were carrying.
>
> **One scope decision** you should overrule if you disagree (§2): M20 builds the EventService, which the roadmap currently attributes to M14.

## 1. Purpose

D-037 made death reachable, and M19 shipped it as a bare fact: a status column, an audit row, a corpse. What it does *not* yet have is consequence. A Don can bleed out on a pavement right now and his family will not notice — the chair he sat in still says his name, the roster still counts him, and nothing anywhere in the world records that it happened.

M20 is the milestone that makes a death land. Tech §18 lists eight things that must follow one, and the point of all eight is the same: **a death has to be something the city finds out about.** The rank empties, somebody has to be appointed into it, the body is left where it fell with everything on it, and an event exists that M21 can print and M22 can keep.

It is also where the project's most abusable mechanic gets built, which is why M19 deliberately refused to build it. A permadeath interaction with no audit trail, no witnesses and no written rules would be used before it could be reviewed. Everything below exists to make the act deliberate, slow, loud, and recorded.

## 2. Responsibilities

**In scope:** the confirm-kill interaction (Tech §18 — deliberate, logged, interruptible, visible); the death cascade behind M19's `Omerta.CharacterDied`; rank removal and the emptying of the leader's chair; permanent succession as an appointment somebody makes (§4b); what happens to the dead's belongings (§4c); the durable death event; the confirmed-death rules specification as a written deliverable.

**Out of scope:** funerals and the funeral home (content, post-MVP per Tech §24); bodies decaying or being disposed of (M20 leaves a corpse in the world for good — cleanup is a staff command and a later milestone's mechanic); the newspaper article itself (M21 reads the event); police response to a killing (M16); murder as a *case* (M17).

### The scope decision: M20 builds the EventService

The roadmap gives M20 a dependency on **M14** for events. M14 does not exist, is blocked on Q-10, and is where review improvement #1 proposed an `EventService` with durable EventIDs — noting in the same breath that *"deaths, funerals, promotions, and openings also need EventIDs"*.

**M20 is the first milestone that actually needs one**, so M20 should build it and M14 should consume it. The alternative is M20 inventing a private death-record table that M14 then has to reconcile with, or M20 waiting on a milestone that is waiting on a ruling.

It is small: a durable id, a type, a season, a place, a time, an optional subject and actor, and a JSON payload. What makes it worth doing properly once is that four later milestones all key off it — M21 prints from it, M22 archives it, M15 links evidence to it, M17 builds a case around it. Say the word if you would rather it waited for M14.

## 3. Public API

```lua
-- The act (server)
Omerta.Death.CanConfirm(ply, characterId)     -- true, or false + reason
Omerta.Death.Confirm(ply, characterId, cb)    -- the timed, interruptible act

-- The cascade, for anything that needs to run one without the interaction
-- (staff tooling, M18's executions, a scripted event)
Omerta.Death.Cascade(characterId, cause, actorCharacterId, cb)

-- Events (server) — the new core service
Omerta.Events.Register(type, { name = "Killing", public = true })
Omerta.Events.Create({
    type = "death.confirmed",
    season_id = , subject_character_id = , actor_character_id = ,
    map_name = , pos = , data = { ... },
}, cb)                                        -- cb(eventId, err)
Omerta.Events.Get(eventId, cb)
Omerta.Events.ForCharacter(characterId, cb)
Omerta.Events.Since(eventId, limit, cb)       -- M21's newspaper cursor

-- Succession (M10 gains one function; §4b)
Omerta.Organizations.RecordDeath(characterId, cb)
```

## 4. The Rulings

### 4a. Can a man who has been bandaged still be finished?

M19 made stabilizing stop the clock. It did not decide whether it stops a knife.

- **(a) Yes.** Down is down. A bandage buys time and never buys safety, so saving somebody in the open is only half the job — the other half is standing over them.
- **(b) No.** Stabilizing protects against a confirm kill; an attacker must first put them back down (attacking a stabilized body returns it to Incapacitated), and only then finish it.
- **(c) Yes, but slower.** Stabilized takes noticeably longer to finish than bleeding out does.

**Recommendation: (a).**

(b) is the interesting-sounding one and I think it is a trap. It makes a 300-cent item into immunity, and the correct play becomes bandaging *first* and arguing later — which turns every firefight's aftermath into a race to apply gauze rather than a decision about what to do with a person. It also adds a mechanic (re-downing) whose only purpose is to undo another mechanic.

(a) keeps the meaning M19 gave the bandage: it buys **time**, which is the thing worth buying, because time is what lets friends arrive. What protects a stabilized man is not the bandage, it is whoever is standing next to him — and that is a scene rather than an inventory check.

(c) is a reasonable middle and I would not object to it; it costs one config value. I have not recommended it because the difference a player actually feels is "can I be finished or not", and a longer bar is a smaller answer than it looks.

### 4b. Does death seat a successor, or only empty the chair?

- **(a) Empty the chair.** The dead leader's seat is vacated. M10's existing acting-authority ladder descends to the most senior person present, exactly as it does when a leader is offline — and a *permanent* leader has to be appointed by somebody holding `org.appoint`.
- **(b) Auto-promote.** The deputy is permanently seated the moment the Don dies.

**Recommendation: (a),** and it is very nearly already built.

Tech §19 says permanent succession *"follows family rules"*, and GDD §19.3 is blunt that the system never restores rank by itself. More practically: M10 already empties the chair when a leader leaves by any other route, and already descends acting authority to the most senior person available. Death is the same event with a different cause, so M20 adds **one function** to M10 — `RecordDeath`, which takes the existing `leave` path with a `died` status — and the succession behaviour falls out of code that has been running since M10.

(b) would also be less interesting. An auto-promotion is an administrative fact; a family working out who takes over, in a back room, while an acting Capo holds things together, is the game.

**The consequence worth naming:** kill a Don and his family is not leaderless, it is *acting*-led, with a deliberately limited hand — M10's acting rank sits one rung below the leader's, so an acting Capo can run the family but cannot name a successor to it. Somebody with `org.appoint` has to be found. That is a power vacuum with a shape, which is what the design wants.

### 4c. What happens to what the dead were carrying?

- **(a) Nothing — it stays on the body.** M19 already makes a corpse searchable; the coat, the money and the Thompson the family bought are all lying in the street for whoever finds them first.
- **(b) Organization equipment returns to the treasury**, personal effects stay on the body.
- **(c) It vanishes with them.**

**Recommendation: (a).**

(c) is out on the design's own terms — items are objects (Tech §9, D-020) and objects do not evaporate.

(b) is the one worth arguing about, because M11 tags organization-owned equipment and there is a real case that a family should not lose a Thompson every time a soldier is unlucky. I would still not do it: **it makes death cheap for the only actors who can afford to make it expensive.** If the guns come home by themselves, a family loses a man and nothing else, and there is no reason to go and get him.

Under (a) there is every reason. Recovering your dead becomes a thing families *do* — which is precisely what M19's dragging is for, what M20's body-in-the-street is for, and what makes a funeral mean something when it eventually exists. It also gives the other side something to take, which is the whole economy of a robbery that turns lethal.

## 5. Networking

Almost none, and deliberately.

| Message | Direction | Payload |
|---|---|---|
| `death.progress` | server → client | text (string 48), seconds (uint 8) |

The killer sees a progress prompt; so does the victim, because being finished without knowing it is happening is the one thing worse than being finished. Both ride M19's existing `injury.prompt`.

**No death notice goes to anybody else, ever.** No feed, no announcement, no "X has died" (GDD §6, Tech §4). You learn about a killing by seeing it, by finding the body, by being told, or by reading about it in M21 — and that is the entire information design in one rule. The event row exists so the *newspaper* can find out; it is never pushed to a client.

## 6. Persistence

Migration **13**, one table.

```
events   id, season_id, type, subject_character_id, actor_character_id,
         map_name, pos_x/y/z, at, data (json), published_at
```

`published_at` is M21's, and is here now rather than in a migration later because adding a column to a table this central is more disruptive than reserving one.

The death itself needs no new storage: M19's `character_injury` already holds the state, `injury_events` already holds the transition, M4's `characters.status` already holds `dead`, and M10's membership row already records the exit. **M20 writes one event row and otherwise moves existing state**, which is the sign the milestones before it were cut in the right places.

## 7. Security Considerations

- **The act is server-authoritative and re-validated throughout.** Range, target state, and the actor's own condition are checked every tick of the cast, not once at the start — an attacker who is put down mid-act stops.
- **Interruptible by design** (Tech §18): moving away, being downed, or the target being treated all cancel it. Cancelling leaves no trace on the victim, which matters, because an interrupted attempt is a *near miss* the victim should be able to talk about rather than a state they carry.
- **Every attempt is audited, not just every success.** Tech §18 asks for enough visibility to support rules enforcement, and the abuse pattern staff will actually be asked about is "he kept trying" — which an audit log of completions cannot answer.
- **`Cascade` is server-internal.** There is no net message that runs it, so no client can ask for anybody to die.
- **The corpse keeps no identity of its own** (D-033, D-037 §4a): who it was resolves through M5, per observer, exactly as it did while they were alive.

## 8. Dependencies

M19 (`Omerta.Injury.RegisterDownedAction` — built for this and still empty; `Omerta.Injury.Die`, the funnel M20 becomes the second caller of), M10 (roster, ranks, the chair, `org.appoint`), M9 (pockets), M11 (organization tags), M4 (status), M5 (interaction and identity).

Note what is *not* here: M14. The roadmap listed it, for events, and §2 explains why that dependency inverts.

## 9. Future Extension Points

- **`Omerta.Events`** is the surface M21, M22, M15 and M17 all build on. M14 registers `crime.robbery` into it rather than inventing its own.
- **`Omerta.Death.Cascade`** is what M18's justice outcomes call if an execution is ever a sentence.
- The rules specification is a document M24's moderation tooling will be written against.
- Funerals attach to the corpse and the event, needing nothing new from this milestone.

## 10. Architecture Rationale and Alternatives Rejected

**Rejected — a second death path for the confirm kill.** D-037 §4d established one funnel. The interaction calls `Omerta.Injury.Die` like the bleed-out timer does; the cascade hangs off `Omerta.CharacterDied` and therefore runs identically whichever way somebody died. Two ways to die must not mean two cascades, because the second one written is the one missing a step.

**Rejected — M20 owning succession logic.** M10 already computes acting authority and already empties the chair. Reimplementing that here would be a second answer to "who is in charge", and the two would disagree within a milestone.

**Rejected — broadcasting a death.** Covered in §5; it is the single most tempting violation of §4a in the project and it would be one line.

**Rejected — deferring the event service to M14.** Covered in §2.

**Rejected — a "confirm?" dialogue box.** Tech §18 wants the act to be deliberate, and a modal is deliberate for the *player* while being instant in the *world*. A long cast that everyone nearby can see is deliberate in the fiction, which is where it needs to be.

## 11. Testing Strategy

**Headless:** the confirm-kill predicate across every injury state (including §4a's answer); the cascade's ordering, driven through a fake organization and character so each of Tech §18's eight steps is asserted individually; event id monotonicity and the `Since` cursor M21 will page through; the pure part of succession — that a dead leader vacates and the acting holder is recomputed — which is M10's `ComputeActing` given a roster with a dead member.

**In-engine (`omerta_death_selftest`):** a synthetic Don is killed and the chair is empty afterwards while acting authority sits with the next rung; the victim's belongings are still on the corpse and still searchable; exactly one event row exists with the right subject and actor; an interrupted attempt leaves the target alive and *unchanged*; a second confirm on an already-dead character is refused rather than producing a second cascade.

**The headline check:** *kill the Don of a family with a Capo standing next to him, and within one second the Capo is running the family, cannot appoint a successor to it, and the Don's Thompson is on the pavement.*

## 12. Integration With Existing Systems

`modules/death/`, `depends = { "injury", "organizations", "inventory", "chat" }`.

Changes to shipped code, and there are two:

1. **M10 gains `RecordDeath`.** One function, taking the existing `leave` path with a new `died` membership status. Everything else about succession is already there.
2. **M19's downed-action seam gets its first registration.** No change to M19 — that is what the seam was for, and it is the test of whether M19 was designed correctly.

`Omerta.Events` is new and lives in `modules/events/`, not in `death/`, because M14 and M21 will depend on it without depending on death.

---

**Approved. Implementation begins from here.**

---

## 13. Implementation Notes (post-implementation)

Implemented as two modules — `modules/events/` and `modules/death/` — plus one function in M10 and a rules specification. Suite grew from 323 to 339 checks; the module graph now resolves 16 modules.

- **The cascade is a listener, not a caller.** `Omerta.Death.Confirm` and the bleed-out clock both reach `Omerta.Injury.Die`, which fires `Omerta.CharacterDied`, which M20 listens to. So the eight steps run identically whichever way somebody died, and there is no second path to keep in step with the first.

- **M19 needed no change at all.** The confirm kill is a registration into `RegisterDownedAction`, which M19 shipped empty for exactly this. That is the test of whether the seam was cut in the right place, and it passed.

- **M10 needed one function and one enum value.** `RecordDeath` takes the existing `leave` path with a new `died` status; the chair emptying, the acting ladder descending, and the audit row all fall out of code that has been running since M10. `died` is its own status rather than a flavour of `left` because the roster has to answer "who did we lose" separately from "who walked out" — M21 prints one of those and M22 archives both.

- **The completion check is asked twice.** Once as the predicate that offers the action, and again at the instant it completes. A target who is treated and stood up during the seven-second cast does not die because somebody started while they were still down — which is what makes rescuing somebody mid-act actually work rather than merely look like it might.

- **Attempts are audited, not just successes.** `death.attempt_failed` exists because the report staff will actually receive is "he kept trying", and a log of completions cannot answer it. This is the one piece of logging that exists for the rules document rather than for the game.

- **`published_at` is in the events table from the start.** It is M21's and does nothing yet. A migration against a table four milestones read from is more disruptive than a column that sits empty for one.

- **The event's `public` flag is eligibility, not a decision.** It says a killing is the *kind* of thing that could reach a newspaper. Whether any particular one does is M21's to decide, because it depends on who witnessed it — and building that judgement into the event row would have put M21's rules in M20's table.

- **Nothing about a death is networked to anybody but the two people involved.** No feed, no notice, no announcement. The event row exists so the newspaper can find out; it is never pushed to a client. This is the single most tempting violation of §4a in the project and it would have been one line.

**Deliverable:** `docs/rules/confirmed_death.md` — what the code enforces, what the rules require, and what staff should actually ask when judging a report ("the mechanics allowed it or it would not have happened").

In-engine acceptance (user-side): pull, restart, then `omerta_death_selftest` (9 steps). Then manually: put a second character down and use the interaction menu on them — **Finish** is last in the list, takes seven seconds, and can be walked away from. Check `omerta_events` for the record and `omerta_injury_history <id>` for the trail. To see §4b, seat a Don with `omerta_org_seed`, kill him with a Capo online, and check `omerta_org_list` shows the chair empty while the Capo holds authority.
