# Design Review — M14: Crime Events, Store Robbery, NPC Victims

Status: **AWAITING RULINGS**
Milestone: M14 (roadmap Track C). Depends on: M20 (the EventService — this is the second reader and the first *writer* other than death), M13 (the premises, the till, `IsForceable`, the rumour pool), M9 (the proceeds are items, the money is real, bulk is the pacing), W0 (`Omerta.WeaponFired`, and a gun that takes time to draw), M19 (a robbery that goes wrong puts somebody on the floor), M5 (every player action here is an interaction), M12 (a store with a line is a store where the clerk can telephone). Consumed by: M15 (witnesses and evidence hang off the event), M16 (the alarm is the thing it responds to), M17 (the operation is what a case is about), M21 (a robbery is a story), C4 (the bank is this framework with a bigger safe).

> **Five rulings** (§13): whether a register refills, what the victim NPC physically is, what an in-flight robbery becomes across a restart, whether a mask cuts both ways, and whether the clerk can be killed.
>
> **Two scope decisions** you should overrule if you disagree (§2): M14 promotes M19's timed-action machinery into a shared primitive, and M14 registers the project's first concealment provider — one mask — because without it this milestone's own acceptance test is unreachable.

## 1. Purpose

Thirteen milestones have built a city where crime is possible and nothing in it is a crime. A player can already walk into The Blue Room, draw a Thompson, shoot the bartender, and go through his coat — and the game will record an injury, a death and an event, and will have no opinion whatsoever about the fact that a robbery just happened. There is no state that says an operation is under way, no alarm, nothing for the police to be called *about*, and nothing anybody can be investigated *for*.

M14 is where the criminal half of the design acquires a verb. It is also the milestone three others are queued behind: M15 has nothing to witness, M16 has nothing to respond to, M17 has nothing to build a case around. Tech §16 is eleven lines long because everything it describes was going to be obvious once the systems underneath it existed. They now do, and the eleven lines turn out to hide five real decisions.

The thing it must not become is a job board. GDD §12 lists seven phases of a robbery and six of them are things players do to each other in a room — intelligence, preparation, roles, escape, evidence, laundering. Exactly one of them is a mechanic, and that one is *execution*. M14 builds the execution and refuses to build a planning UI for the rest, because the rest is the game.

## 2. Responsibilities

**In scope:** the operation state machine (Tech §16) as a durable record keyed to an M20 EventID; the NPC victim and the pure reaction model behind it (GDD §12); the store as a robbable place declared in data; the demand, the register, and the take as physical M9 cash; the alarm as a standalone durable fact with a seam M16 registers into; escape, failure and abandonment; the first entries into D-031's event-sourced rumour pool; one mask (see below); the operation's audit trail.

**Out of scope, and deliberately:**

- **Witnesses and descriptors (M15).** M14 computes *who could plausibly have seen this* at each notable beat and hands the set to a seam that nothing is registered on. It stores none of it, and it invents no descriptor vocabulary — that is M15's, and inventing it here would mean writing M15's rules in M14's tables.
- **Police response (M16).** M14 raises alarms and computes no response delay, dispatches nothing, and knows no police capacity. Tech §15's state machine is M16's whole milestone; M14 owes it a queue and nothing else.
- **Burglary — the stock room, the safe, forced entry into an empty building.** Robbery is a crime committed against a *person*; burglary is a crime committed against a *lock*, it wants the lockpicks and the crowbar the auto shop already sells, and it wants M17's warrant-adjacent rules about entering premises. Different mechanic, different milestone.
- **Heat, district pressure and public trust (M16, Q-8).** The event rows accumulate; nothing reads them yet.
- **A melee base.** W0 §6 left the crowbar an object "until M14 wants it swung". M14 does not want it swung: it wants it *levered*, against a register, as a tool in a timed action. A melee SWEP base is a real piece of work and it is not what makes a robbery work.
- **The bank (C4).** Same framework, bigger numbers, and it waits for M16/M17 to prove the loop.
- **Mugging a player.** Putting somebody on the floor and going through their coat already works (M19 + M9). Making it a *tracked operation* is a real design question about consent and griefing, and it deserves better than being smuggled in beside stores.

### Scope decision 1 — M14 promotes the timed action out of `injury`

M19 built the timed, interruptible, range-checked action inside `sv_treatment.lua` and wrote in the comment that "Tech §18 will require exactly this of M20's confirm kill; building it here means M20 inherits it instead of reinventing it." That reasoning was right and it now applies a third time: opening a register, levering one, and going through a till are all the same shape — a predicate, a duration, an interruption, one prompt.

M14 is therefore the milestone that moves it. `Omerta.Action.Begin/Cancel/IsBusy` becomes a core primitive beside `Omerta.Interaction`; M19's treatments and downed actions become its first two callers and change nothing about their own definitions; M17's arrest, M15's evidence collection and C4's drilling all inherit it.

The alternative is a second copy in `modules/crime/`, and the second copy is always the one that forgets to cancel on disconnect. Say the word if you would rather M14 duplicated it and a later milestone paid to merge them.

### Scope decision 2 — M14 ships one mask

This milestone's own definition of done is *"a two-player **masked** store robbery"*, and **nothing in the game can currently conceal a face.** D-014 shipped `Omerta.Identity.RegisterConcealmentProvider` in M5 and no milestone has ever registered one; the roadmap puts disguises in the content workstream, which owns models, not mechanics. There is no milestone that owns this.

So M14 registers one `face` equipment slot and one `clothing.mask` item, and becomes the first caller of a seam M5 shipped empty. That is one `RegisterSlot`, one `Omerta.Items.Register`, and one `RegisterConcealmentProvider` — the same shape and the same size as M20's registration into `RegisterDownedAction`, and the same test of whether the seam was cut correctly.

What it explicitly does **not** ship: a disguise *system*, appearance descriptors, partial concealment, gloves, or anything M15 will want. A mask is on or it is off, and while it is on you are Unknown to everybody including your own crew — which is exactly what D-014 already says and has never been able to demonstrate.

## 3. Public API

```lua
-- Operation kinds (data-driven; C4's bank is one more table)
Omerta.Crime.RegisterOperationType("robbery.store", {
    name = "Store robbery",
    maxSeconds = 600,            -- the abandonment ceiling
    escapeDistance = 2500, escapeSeconds = 45,
    takeSource = "business.till",
})

-- Victim personalities (data; the arsenal's shape, applied to people)
Omerta.Crime.RegisterPersonality("clerk.old_hand", {
    name = "Old hand",
    nerve = 0.8,                 -- how much pressure before he stops thinking
    compliance = 0.7,            -- how readily he opens the register
    duty = 0.2,                  -- how much he cares about somebody else's money
    alarmAppetite = 0.6,         -- how likely he is to reach for it, and when
})

-- Running an operation (server)
Omerta.Crime.CanBegin(ply, target)             -- true, or false + reason
Omerta.Crime.Begin(ply, typeKey, target, cb)   -- cb(operation, err)
Omerta.Crime.Get(operationId) / ForBusiness(businessId)
Omerta.Crime.Join(operation, characterId)      -- whoever else is in the room
Omerta.Crime.Resolve(operation, state, resolution, cb)

-- The pure core (shared; the headless suite's whole surface)
Omerta.Crime.STATE = {
    PLANNED = "planned", ACTIVE = "active", ALARMED = "alarmed",
    ESCAPED = "escaped", FAILED = "failed",
    INVESTIGATING = "investigating", CLOSED = "closed",
}
Omerta.Crime.CanTransition(from, to)           -- the legal-move table
Omerta.Crime.Reaction(situation, personality, seed)  -- comply|stall|alarm|flee|resist
Omerta.Crime.Pressure(situation)               -- the number the reaction reads
Omerta.Crime.IsRobbable(typeDef, business, onlineSides)  -- pure, over M13's rule

-- Alarms — a fact about a place, never about a person
Omerta.Crime.RaiseAlarm(spec, cb)              -- cb(alarmId, err)
Omerta.Crime.PendingAlarms(cb)                 -- M16's queue
Omerta.Crime.RegisterResponder(id, fn)         -- M16 registers; M14 ships it empty

-- Seams the neighbours fill
Omerta.Crime.RegisterReactionInput(id, fn)     -- one more factor the clerk weighs
Omerta.Crime.RegisterTakeSource(id, def)       -- a till here, a vault in C4
Omerta.Crime.RegisterObserverSink(id, fn)      -- M15; M14 ships it empty

-- What M13 gains, and it is one function (§12)
Omerta.Business.EmptyTill(business, toOwner, cents, cb)
```

Note what is **not** here: no `Omerta.Crime.Reward`, no `PayOut`, no `Distribute`. Reaching Escaped grants nothing, because the money was already in somebody's pockets and a function that granted more would be a mint.

## 4. Data Model

Two pure machines, and they are the whole milestone. Everything else is plumbing that already exists.

### 4a. The operation state machine

Tech §16 names seven states. **M14 owns five of them and never sets two.**

| From | To | On |
|---|---|---|
| *(none)* | `active` | the demand is made in front of a victim |
| `planned` | `active` | a planning tool starts the job — **unreachable in M14** |
| `active` | `alarmed` | any alarm is raised for this operation |
| `active` / `alarmed` | `escaped` | every live participant clear of the premises for the configured window |
| `active` / `alarmed` | `failed` | every live participant downed, dead or arrested at the scene; or the ceiling reached; or the server restarted (§13.3) |
| `escaped` / `failed` | `investigating` | **M17 sets this. M14 defines it and never writes it.** |
| `investigating` | `closed` | **M17.** |

`planned` exists in the enum and M14 never enters it. Tech §16 says in as many words not to require a planning UI for small crimes, and a store robbery is a small crime — it starts when somebody points a gun at a man, not when a form is filled in. Declaring the state now and leaving it unreachable is the same discipline that put `published_at` in M20's events table a milestone before M21 needed it: C4's bank job is where a plan becomes a real object, and it should not have to migrate an enum to say so.

**`escaped` and `failed` are both terminal for M14, and neither is a verdict.** Escaped is not a reward and Failed is not a punishment; they are two different stories for M21 and two different opening positions for M17. A crew that takes four hundred dollars and then gets shot on the pavement resolves to **Failed**, and the four hundred dollars is on the body — because failure is a fact about the crew, not about the till.

The machine is **total**: every non-terminal state has a timed exit, and the ceiling (`crime.max_seconds`, default ten minutes) guarantees that no operation can sit open forever holding a clerk hostage in a compliance state that nobody is present to end. `Omerta.Crime.CanTransition` is pure and is pinned exactly as M19's transition table is.

### 4b. The reaction model

GDD §12: *"NPC victims assess concealment, weapons, aggression, witnesses, alarms, and personality before complying, stalling, fleeing, resisting, or calling police."* All six inputs, all five outputs, one pure function.

```lua
situation = {
    armed = true, weaponClass = "smg",  -- what is pointed at him
    weaponsVisible = 2,                 -- how many of them there are
    masked = true,                      -- D-014's IsConcealed, per robber
    shotsFired = 0, victimHurt = false, bystanderHurt = false,
    bystanders = 1,                     -- people in the room who are not crew
    alarmRaised = false,
    elapsed = 12,                       -- seconds since the demand
}
```

`Omerta.Crime.Pressure(situation)` reduces that to one number. `Omerta.Crime.Reaction(situation, personality, seed)` compares it against the personality's thresholds and returns one of `comply`, `stall`, `alarm`, `flee`, `resist`. `alarm` covers both GDD's "calling police" and the button under the counter — which of the two he reaches for is the *premises'* property, not his.

Three positions worth defending:

**It is deterministic given a seed, and the seed is drawn once per operation.** A reaction model that rolls fresh dice every evaluation cannot be pinned headlessly and, worse, cannot be *learned* — and a robbery you cannot get better at is a slot machine with a gun in it. The seed is stored on the operation, so the same situation replays identically in a test, and a robber cannot re-roll a stubborn clerk by backing off and demanding again inside the same job. M13's own words on the barman apply: he is not random, he is just out of date.

**It is evaluated on events, not on a tick.** The demand, a shot, somebody new coming through the door, the clerk being struck, and a fixed nerve-decay step. Pressure accumulates across evaluations; the function itself is stateless.

**Past a threshold he stops being a rational actor.** Above his nerve the personality's weights stop applying and he flees or freezes. That is what makes firing a warning shot a genuinely bad idea rather than a stronger version of a good one — it is the difference between a man who opens the register and a man running for the door with your face in his memory.

**A personality is data**, registered exactly like an item or a weapon: four numbers and a name. "The old man who has been robbed twice and just opens the drawer", "the kid who bolts", "the ex-soldier who reaches under the counter" are three tables in one file, and the fourth is a fourth table.

### 4c. What makes a place robbable, and how an operator adds one

**Robbability is not a flag on a special kind of building. Every business with a till is robbable, and the type declares the terms.**

```lua
-- sh_venues.lua, beside the seven types M13 already registers
Define("store", {
    name = "General Store", order = 15,
    tillCapacity = 600, stockCapacity = 900,
    services = { "shop" },
    sells = { { item = "food.bread", price = 90 }, ... },
    robbery = {
        clerk = { personalities = { "clerk.old_hand", "clerk.kid" } },
        alarm = { kind = "silent", telephone = true, button = true },
        register = { openSeconds = 4, forceSeconds = 22, forceTool = "tool.crowbar" },
        float = { perHour = 1200, ceiling = 4000 },   -- §13.1
        fleeTo = "back",                               -- a declared point, §13.2
    },
})
```

Three positions in that table.

**The declaration lives on the type, in `sh_venues.lua`, which is the file M13 already treats as data.** This project's settled meaning of "data" is a registration table in version control — that is what `Omerta.Items.Register`, `Omerta.Weapons.Register` and `Omerta.Business.DefineType` all are, and M9 §6 wrote down why: a definition is behaviour and balance, and balance belongs where it can be reviewed and rolled back. Adding a *kind* of robbable place is therefore one table, edited by nobody's hand at runtime. Adding *an instance of one* is `omerta_business_place store — The Corner Grocer`, at the console, with no code change at all. Those are the two different things "data-driven" has to mean here and they have two different answers.

**A type that declares no `robbery` block still gets one, from a conservative default.** The alternative — robbability as an opt-in flag — means a funeral home is invisible to the crime system until somebody remembers to tick a box, which is the special case this codebase registers behaviour to avoid. A speakeasy is robbable the day it is placed; what its block *says* is that its clerk does not telephone the police, because the bar is illegal and its owner would rather tell his family. That is a per-type consequence falling out of one line of data, and it is the reason the block is worth having at all.

**Whether a *particular* premises can be robbed right now is a pure function**, `Omerta.Crime.IsRobbable(typeDef, business, onlineSides)`, layered directly over M13's `IsForceable` with no position argument — because D-030 was deliberately built with no way to express "somebody was standing in the room" (M13 §13), and M14 must not be the milestone that quietly reintroduces one.

### 4d. What is pure, and what needs the engine

**Pure (headless):** the transition table; `Pressure`; `Reaction` including every personality boundary and the seed determinism; the robbability predicate; the escape and abandonment arithmetic; the take planner (how much of a register fits in a coat); the rumour text builder, which is the function that must never be able to emit a name.

**Engine:** the clerk entity and its animations; line of sight for the observer set; the flee walk; range checks; the world audio of a bell. All of it is a thin shell over the pure half, and none of it decides anything.

## 5. Networking

**M14 adds no client → server message at all.** Every action a player takes in a robbery is already somebody else's registered mechanism: the demand is an M5 interaction on the clerk, opening the register is an M5 interaction, taking the money is the shared timed action, and carrying it is M9. There is nothing new for a client to send and therefore nothing new to validate.

| Message | Direction | Payload |
|---|---|---|
| *(none new)* | | the promoted `action.prompt` (§2) carries the register work; `Omerta.HUD.Cue` carries the rest |

What must **never** go on the wire, stated as rules rather than left as discipline:

- **No operation state reaches any client.** There is no "ROBBERY IN PROGRESS", no timer, no escape countdown and no marker on the premises. GDD §8 lists objective markers among the things never displayed, and a countdown to Escaped is an objective marker with a clock on it. A robber knows how long he has been in the building the same way he would in life: by being nervous.
- **No alarm is announced to anybody, including the robbers.** The clerk going for the telephone is an animation, visible in the room, and the *only* way to know it happened. Whether the police are coming is something you find out when they arrive. This is the single most tempting violation in the milestone and it would be one `Omerta.HUD.Cue`.
- **The take is not announced.** You learn what you got by counting it in your inventory, exactly as D-018 and M9 already require of every other cent in the game.
- **The clerk's nerve, personality, pressure and current decision are never networked.** M19's argument, restated because it bites harder here: a networked reaction state lets every client in the room read whether the man behind the counter is about to hit the button, which is the entire tension of the scene.
- **No observer set, descriptor or CharacterID is sent anywhere.** The observer set (§9) is a server-side hand-off between M14 and M15 and never touches a client. A witness records descriptors, never a CharacterID — and in M14 a witness records *nothing*, because M15 owns that vocabulary.
- **The clerk carries no networked identity.** He has no character row, so M5 resolves him as Unknown to everybody, permanently, through the path M19's bodies already use. He gets an action hint and no name. D-033 is not stretched here: he is a person, and people are not labelled.

The one thing M14 *does* put in front of other players is a **rumour** (D-031), and it is bounded by the same rule as everything else: the text is built by a pure function that has no access to a character id and no vocabulary for one. "They say somebody put a gun in a shopkeeper's face on Third Street last night" is the whole of it. This is the first event-sourced entry the pool has ever had — M13 built `Omerta.Rumours.Add` with an `event` source for M14 and D-031, and the only thing that has called it that way since is M13's own self-test.

## 6. Persistence

Migration **14**, three tables.

```
crime_operations   id, season_id, event_id, type_key, business_id,
                   state, resolution, seed,
                   map_name, pos_x/y/z,
                   started_at, state_at, ended_at, deadline_at,
                   take_cents, data (json)
                   indexes: (season_id, state), (business_id), (event_id)

crime_participants operation_id, character_id, joined_at, outcome
                   primary: (operation_id, character_id)
                   -- outcome: escaped | downed | dead | arrested | unknown

crime_alarms       id, season_id, operation_id (nullable), source, severity,
                   map_name, pos_x/y/z, raised_at, responded_at, data (json)
                   indexes: (season_id, responded_at), (operation_id)
```

**The operation is a row, not a table in memory.** Tech §16's last two states are M17's and are measured in days; an operation that lived only in RAM could not be investigated after a restart, and M15 would have nothing durable to hang a witness off. The in-memory copy is a cache over the row, exactly as M13's businesses and M19's injuries already are.

**Alarms are their own table and are not owned by robberies.** `operation_id` is nullable on purpose: a gunshot in an empty street at three in the morning is an alarm with no operation behind it, and M16 must not need two code paths to answer it. One queue, one responder seam, whatever raised it. `responded_at` is M16's column and is here now for the same reason `published_at` was in M20's — a migration against the table M16 is built on is more disruptive than a column that sits empty for a milestone.

**`take_cents` is a record, never a source of truth.** It is written *after* the transactional move has already succeeded, and nothing ever reads it to decide how much money exists. It exists because M21 wants to print "made off with about four hundred dollars" and M17 wants a figure to attach to an allegation, and neither can reconstruct it from item rows once the money has been spent.

**`deadline_at` is an absolute timestamp, never a countdown.** M19 learned this twice and it is now nearly a house rule: a restart that reset the clock would make waiting for the nightly restart a robbery technique.

## 7. Security Considerations

- **The client never names an operation.** It names an entity through M5 and the server resolves everything else. There is no message that starts, advances or ends a robbery.
- **The demand is validated at the point of the act and again at every step**: range, line of sight, that the target is a live clerk, that the business is robbable, that no operation is already live on it, that the cooldown has elapsed, and that the actor is not himself on the floor. M20's lesson — ask the question at the start *and* at completion — applies to every timed step of the take.
- **D-030 is consulted, and it has a third case now.** M13's `IsForceable` answers false when a business has no owner, which was the correct conservative default for a milestone with no unowned businesses and is exactly wrong for a store that exists to be robbed. The rule gains one branch — **an unowned business is always forceable**, because D-030 exists to stop players being punished for logging off and an unowned store has no players to punish. Owned premises are untouched, and M13's assertions on them stay green.
- **No new economic path exists.** The take is M9's transactional move of cash that was already in the till, through the same function a sale uses. There is no mint, so M9's duplication protections — the guarded `UPDATE` naming the owner it expects to move from, and the per-instance lock — cover the robbery unchanged and without being told about it.
- **Bulk is the anti-exploit.** A man with a Thompson slung across his back cannot pocket four hundred dollars in quarters (D-020). That is not a limitation to work around, it is the reason a big score needs a bag, a second man, or several trips in front of a frightened witness.
- **The seed is server-side and never leaves it.** A client that knew the clerk's seed would know his answer before asking.
- **Every operation, every transition, every alarm and every handful is audited** (Tech §23), because the question staff will actually be asked is "he robbed the same shop four times in an hour", and a log of completed robberies cannot answer it.
- **A robbery cannot be hidden by finishing it badly.** The event row is written at the demand, not at the resolution: an operation that is abandoned, crashed out of, or disconnected from has already been recorded.
- **Rumour text is built, never composed from player input**, so the one thing M14 puts in front of other players cannot carry an injected name.

## 8. Dependencies

M20 (`Omerta.Events.Register` / `Create` — M14 is the first milestone other than death to write one), M13 (`Business.Get`, `Till`, `IsForceable`, `DefineType`, `Rumours.Add`), M9 (`Money.Count/Pay/HasRoomFor`, `Inventory.Move`, bulk, containers), W0 (`Omerta.WeaponFired`, `Weapons.Get`, and the draw timer that makes pointing a gun a commitment), M19 (`IsIncapable`, the damage path, and the timed action §2 promotes), M5 (`Interaction.Register`, `ResolveDisplayName`, `RegisterSubjectProvider`, `RegisterConcealmentProvider`), M8 (`HUD.Cue`, `RegisterTargetHint`, `RegisterInteractablePredicate`), M12 (a premises with a private line is a premises where the clerk can telephone), M10/M11 (ownership and, through D-030, whether an owned place is live), M2 (audit), M1 (migration 14), M3 (season scoping).

Almost all of those are seams that already exist and are registered into rather than edited; §12 lists the four places that is not true. Two have never been called by any gameplay code: `RegisterConcealmentProvider` (M5, empty since it shipped) and `Rumours.Add` with an `event` source (M13, built for this, exercised only by M13's own self-test).

## 9. Future Extension Points

- **`Omerta.Crime.RegisterResponder`** is **M16's**, and M14 ships it with nothing registered — deliberately, in the shape M19 shipped `RegisterDownedAction` for M20. If M16 can be built entirely as a registration into it, the seam was cut correctly; if M16 has to edit `modules/crime/`, it was not, and I would rather find that out here than in M17.
- **`Omerta.Crime.RegisterObserverSink`** is **M15's**. At each notable beat — the demand, a shot, the register opening, the exit — M14 computes the set of people who could plausibly have seen it (range, line of sight, whether they were facing it) and hands it over. **M14 stores none of it and invents no descriptor vocabulary.** That is the cut: M14 owns the *moment*, M15 owns the *memory*.
- **`Omerta.Crime.RegisterReactionInput`** is where the disguise milestone adds "he can see your face", M15 adds "he has been robbed by somebody dressed like you before", and M10 adds "he knows whose neighbourhood this is".
- **`Omerta.Crime.RegisterOperationType` and `RegisterTakeSource`** are C4's whole bank robbery: a longer job, a vault instead of a register, a different alarm profile. If the bank needs anything else from this module, this section was wrong.
- **`crime_operations.state`** already contains M17's two states, so a case attaches with no migration.
- **The mask** (§2) is one item in a slot the disguise milestone will fill with a dozen, using the concealment provider M14 registers and does not otherwise touch.
- **The alarms table** is where a phoned-in tip, a patrol's own sighting and a burglar alarm all land later, without M16 learning a second shape.

## 10. Architecture Rationale and Alternatives Rejected

**Rejected — robbery state in memory only.** It is the cheap version and it fails at the first restart: Tech §16's `investigating` and `closed` outlive the process by days, M15 needs something durable to reference, and an operation with no row is a crime that stops having happened when the server is updated.

**Rejected — a `Planned` phase with a planning UI.** Tech §16 says not to require one for small crimes and GDD §12's planning phases are things players do to each other. A lobby where a crew assigns roles before walking in would replace the conversation in the back room with a form, and the conversation in the back room is what this game is.

**Rejected — the robbery opening the till container.** M9's `MayOpen` is refusal-only by design: a registered predicate can veto, none can grant, and M13's till predicate will always refuse a robber. Forcing a grant through it would mean teaching M9's access model about crime. Instead **M13 gains `EmptyTill`, the unauthorised half that `CollectTill` becomes a role-checked caller of** — one function, the existing transactional path, a different reason for being allowed. This is M20's `RecordDeath` shape exactly, and it is the third time that shape has been the right answer.

**Rejected — a lump-sum take.** `Money.Pay` is all-or-nothing and refuses on capacity, so a robber whose pockets are half full would get *nothing*. The take is therefore **a handful at a time**: a repeated timed action, each grab taking what fits, the register emptying only if you stay in the room. That is better in every direction — it puts the time in front of the frightened man where the scene needs it, it makes interrupting a robbery mid-take mean something, and it makes the second robber genuinely useful rather than decorative. It is also the direct answer to "a two-player robbery".

**Rejected — proceeds as a balance change, or as newly minted cash.** D-024's argument for the third time. The money in the register is the money that was in the register; the robbery moves it and creates none. This is also what makes an interrupted robbery need no rollback at all: physical proceeds are wherever they physically are, so there is no ledger to reconcile when the server comes back up.

**Rejected — an `npc_*` victim, and a nextbot victim.** An engine NPC brings the Half-Life 2 AI with it: relationships, schedules, and its own health and death, which is a second lethality model beside the one D-037 built. A nextbot brings a navmesh, which means `nav_generate` becomes a hard dependency of the content workstream and a robbery on an unmeshed map produces a clerk who stands still forever — the worst failure mode, because it looks like it works. The clerk is a scripted `base_anim` entity that does not navigate (§13.2).

**Rejected — announcing the alarm.** Covered in §5, and it is the line the whole information design stands on.

**Rejected — a robbery HUD.** No timer, no progress ring pinned to the screen, no "objective". D-041 permits exactly one element on an idle screen and it is the crosshair; M8's acceptance test fails the moment a second joins it, and this milestone is not going to be the one that argues for an exception. The register work uses the existing timed-action prompt, the refusals use `Omerta.HUD.Cue`, and everything else is communicated in the world — the till opening, the clerk backing away, his hand going under the counter.

**Rejected — a `store` entity of M14's own.** A store is a business with a till, and M13's framework already carries ownership, placement, staff, stock and access. Registering `store` as a type in `sh_venues.lua` costs one table; a parallel entity would cost a second answer to "who owns this place", which M13 §6 already refuses on the grounds that two answers is how access control quietly stops working.

**And so M14 draws almost nothing, none of which is its own.** The interaction verbs come from M5's menu, the prompt from the promoted timed action, the notices from the cue stack, the target hint from M8 — every one of them already built on `sh_theme.lua` and `cl_widgets.lua`. There is no M14 panel, no M14 colour and no M14 font: six hex, square corners, 1px rules, brass-fill selection with ink text, and the persistent screen still empty. If this milestone ever needs a window of its own — and it should not — it composes one out of the widget kit rather than drawing one.

## 11. Testing Strategy

**Headless (pure, no engine):** the transition table — every legal move, and that illegal ones are refused rather than silently applied; `Pressure` across the input space including every boundary; `Reaction` for each shipped personality at four seeds, asserting the same seed and situation always produce the same decision and that different seeds produce different ones; the nerve threshold, asserting that above it the personality's weights stop mattering; the robbability predicate over M13's `IsForceable` including the new unowned case; the escape window and the abandonment ceiling computed from an absolute deadline and resumed from a stored one; the take planner, including a wallet with no room and a register with less than a handful in it; the rumour builder, with a test that asserts it cannot emit a character name given a situation that contains one; migration 14 rendering.

**In-engine (`omerta_crime_selftest`):** a synthetic store with a synthetic clerk and a stocked register — drive demand → comply → open → take → escape and assert exactly one event row, one operation row in `escaped`, participants recorded, and **the till lighter by precisely what the robber is heavier by**; an alarmed path producing exactly one `crime_alarms` row with `responded_at` null and no client having been told anything; a resist path where the register never opens; abandonment resolving to `failed` after the ceiling; a simulated restart mid-operation resolving to `failed` with the proceeds still physically where they were; a second robbery on the same premises inside the cooldown refused.

**The two-player lived test**, which is the milestone's definition of done: two players, both masked, one holds the clerk and one works the register. Both of them read as Unknown to each other, to the clerk, and to anybody who walks in — including the crewmate who has known that face since the season opened (D-014, demonstrated for the first time). The money that leaves the register arrives in their pockets as notes. One of them gets shot on the way out and the operation resolves to Failed with his share on the pavement.

**The headline check**, in the style M8 set: *two men walk into a shop and walk out with four hundred dollars in actual notes, and the only thing on anybody's screen is what is in their pockets.*

## 12. Integration With Existing Systems

`modules/crime/`, `depends = { "events", "business", "inventory", "weapons", "injury", "interaction", "identity", "hud", "chat" }`. `business` already pulls in organizations, treasury and phone, so the graph resolves with `crime` last — which is the right place for the milestone that consumes everything and is consumed by nothing yet.

Changes to already-shipped code, and there are four:

1. **The timed action moves out of `injury` into a core primitive** (§2 scope decision 1). M19's registrations are unchanged; the file moves and the two call sites are renamed. Covered by the existing suite.
2. **M13 gains `EmptyTill`**, which `CollectTill` becomes a role-checked caller of. One function, the existing path, a different authority.
3. **M13's owner rule goes from "exactly one" to "at most one"**, and `IsForceable` gains the unowned branch (§7). This is the one place M14 changes an existing module's *behaviour* rather than registering into it, and it should be reviewed as part of M14 rather than assumed — it is small, and it is exactly the kind of small change that quietly widens an access rule if nobody looks at it.
4. **A `face` equipment slot, one mask item, and M5's first concealment provider** (§2 scope decision 2). All three are calls M14 makes from its own files into public seams (`RegisterSlot`, `Items.Register`, `RegisterConcealmentProvider`) — no line of M9 or M5 is edited. The slot registration is the only one that gives me pause, because the five existing slots all live in `sh_inventory.lua` and a sixth arriving from outside is new: it is either proof the seam works or the first sign it wants to become a data file, and the review after this one should say which.

Everything else is a registration: `Omerta.Events.Register` for the new event types, `Omerta.Interaction.Register` for the demand and the register work, `Omerta.HUD.RegisterTargetHint` and `RegisterInteractablePredicate` for the clerk, `Omerta.Identity.RegisterSubjectProvider` so that looking at him runs M5's path and returns Unknown, a `hook.Add` on `Omerta.WeaponFired` for the aggression input and the gunshot alarm, and `Omerta.Rumours.Add` on resolution.

Note that the clerk takes damage **outside** M19 entirely: `RegisterDamageFilter` is a filter over players, and the clerk is not one. That is a deliberate asymmetry and §13.5 is where it gets ruled on.

New event types: `crime.robbery.begun`, `crime.robbery.escaped`, `crime.robbery.failed`, `crime.alarm`, and — under §13.5 — `crime.victim_killed`. All `public = true` except the alarm, which is a police fact rather than a newspaper one; M21 decides which of them any given issue prints, exactly as it does for a death.

---

## 13. Open Questions / Rulings Requested

### 13.1 — Does a store's register refill, and from what?

D-032 ruled that a business earns from sales plus a small trickle *only while a real person is behind the counter*. A store with an NPC clerk has no real person behind the counter, so under the rule as written it earns nothing, and there is nothing in the register to rob. The milestone's own acceptance test cannot run.

- **(a) An unowned store accrues an NPC-custom float** — a small per-hour credit into its till, capped at a declared ceiling per type, paused while an operation is live and for a cooldown afterwards. Every cent is minted through `Money.Give` into a container, config-capped and audited. **Player-owned premises are excluded: if somebody owns it, D-032 governs its income unchanged.**
- **(b) Player-owned premises only.** Nothing accrues; the only thing worth robbing is what a player put there. Purest reading of D-032, and it means the first robbery in the season's history cannot happen until somebody has bought a shop and sold things in it.
- **(c) Seeded once at placement, never refilled.** A store is worth robbing exactly once per season.

**Recommendation: (a).** The float is what makes a place *nobody plays* worth walking into, and the exclusion is what stops a family buying a store and farming it. (b) makes the entire crime system dependent on the economy being busy, which inverts the causality — robbery is supposed to be what makes the economy tense, not a reward for it already being lively. (c) is a one-shot content item dressed as a system.

The honest cost of (a): it is a new source of money, and I would rather name that plainly than bury it. It is bounded by a ceiling, paused by a cooldown, audited per credit, and turned off entirely with one config value.

### 13.2 — What is the victim NPC, physically?

The project has never shipped an NPC. The design's own first one — M13's rumour NPC, "the barman" — was implemented as an *action on a counter* with no entity at all, which is the tell that this decision has been avoided rather than made.

- **(a) A scripted `base_anim` entity that does not navigate.** It stands where it was placed, plays reactions, opens the register, and flees to a **declared point** (the type declares one, exactly as M13 already declares `newspaperSpawn` and `surveillance` points) by a straight-line move with a stuck timeout. If it cannot get there it cowers.
- **(b) A `base_ai` NPC.** Real HL2 AI: it will path, it will take cover, it will react to sound for free.
- **(c) A nextbot.** Modern, flexible, and it navigates properly.
- **(d) No entity — an interaction on the counter**, the barman's precedent taken to its conclusion.

**Recommendation: (a).**

(b) brings the whole HL2 AI, including its own health, its own death and its own faction relationships — a second lethality model sitting beside the one D-037 spent a milestone building, and three systems' worth of behaviour we would spend M14 suppressing rather than using. (c) makes `nav_generate` a hard requirement of the map (Q-9), and a robbery on an unmeshed map produces a clerk who stands still forever, which is the failure mode that looks like success. (d) is honest about how little a victim needs to *do* and dishonest about what a robbery *is*: pointing a gun at a counter is not the same scene as pointing one at a man, and the reaction model has nowhere to be read from.

The cost of (a), named rather than discovered: no pathfinding, so the clerk cannot dodge, cannot take cover, and cannot chase. Tech §15 already requires NPCs to "avoid advanced tactics", and this is the victim rather than the police.

### 13.3 — What does an in-flight robbery become across a restart or a map change?

- **(a) It resolves to `failed`, resolution `abandoned`, at boot.** The crime is still on the record — the event was written at the demand — and the proceeds are physically wherever they physically are. The *operation* is over.
- **(b) It resumes.** State, clerk and timers restored.
- **(c) Frozen and resumable within a window**, failing if nobody returns.

**Recommendation: (a).**

(b) means respawning a clerk in the right reaction state, re-attaching a deadline, and re-deriving who was in the room — for a situation every participant has just been disconnected from. It restores a hostage scene with nobody in it. (c) is (b) with an extra state to test.

(a) is safe for one specific reason that is worth stating, because it is the design paying off: **physical proceeds mean there is nothing to reconcile.** If the take were a balance change, an abandoned operation would need a rollback and a rollback would need a rule about half-completed thefts. Because the money is items, an interrupted robbery is just some notes that moved. Nothing is owed to anybody.

M19's precedent cuts the same way — a restart must not heal anybody, and it likewise must not launder anything. Under (a) it does neither: the event, the alarm, the participants and the money all survive; only the live scene ends.

### 13.4 — Does a mask cut both ways?

- **(a) A mask lowers resistance now and raises the odds of an alarm afterwards.** A masked robber plainly intends to leave anonymous, which reads to the man behind the counter as "he does not need me dead" — so he complies more readily. And once you are out of the door he has nothing left to fear, so he is more likely to reach for the telephone. An unmasked robber is either an amateur or means to kill you, which reads as more dangerous to *defy* but also as more dangerous to obey.
- **(b) A mask is a strict benefit** — less resistance, no change to the alarm.
- **(c) The mask affects only M15's descriptors** and is invisible to the reaction model.

**Recommendation: (a).**

Under (b) masking is a free upgrade and there is no decision in it. Under (c) the milestone's own headline feature does nothing observable until M15 exists.

(a) makes the mask a genuine trade — **it buys compliance in the room and buys an alarm behind your back** — which gives a crew a real reason to argue about it, and gives the quiet unmasked job a reason to exist. It also makes M15's descriptor work matter *forward* rather than only backward: the whole point of covering your face is that the call the clerk makes afterwards is worth less.

The cost, which is why this is a ruling and not a paragraph: (a) requires the reaction model to have a **post-resolution evaluation** and a delayed alarm path, which is real work and a real gameplay shape. Under (b) the alarm is only ever raised during the act.

### 13.5 — Can the clerk be killed, and what does that do to the operation?

- **(a) Yes.** He takes ordinary damage, dies as an entity, and leaves a body. His death does **not** stop the crew emptying the register — but it is the single loudest thing in the game: its own event type, an alarm on a fixed timer regardless of what he did or did not reach for, a rumour, and front-page eligibility. The operation continues and resolves normally.
- **(b) Killing him fails the operation immediately.** No take.
- **(c) He cannot be killed** — reduced to fleeing at zero health.

**Recommendation: (a).**

(b) is a rule that exists to punish rather than to model, and it produces the absurd scene of a register full of money that nobody may touch because the man beside it is dead. (c) is a bullet that does not work, which is the kind of exception a player finds in ten minutes and never trusts the world again after.

(a) is also the only option that gives M15, M16 and M17 the case they are being built for. A murder committed during a robbery is the canonical thing this whole track exists to investigate, and under (b) it would be a mechanical dead end rather than the worst night of somebody's season.

Two consequences I would want recorded with the ruling: the clerk is **not** a character and does not enter M19's state machine — he has engine health, dies as an entity, and leaves a ragdoll M15 can gather evidence around; and killing him should be *worse* than the money is good, which is a tuning statement I would rather make explicit now than discover when somebody works out that a dead witness is a cheap witness.

---

**Awaiting rulings on §13.1–§13.5, and confirmation or reversal of the two scope decisions in §2, before implementation begins.**
