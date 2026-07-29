# Rules — Confirmed Death

Status: **specification, M20 deliverable.** Tech §25 requires written rules before release; this is the one for the mechanic that ends characters permanently.

This document is for players and for staff. The code enforces what code can enforce; everything below is what the code deliberately does not, because it is a judgement about intent rather than a fact about state.

---

## What the mechanic is

A character who has been put down is helpless. Anyone standing over them can **finish** them, which takes several seconds, can be interrupted, and is visible to everybody in the room. A finished character is **permanently dead**: they do not come back, they keep nothing, and they pass nothing on.

A character who is left bleeding and is not helped also dies (D-037). That is not a rules matter — nobody did it.

## What the code enforces

You do not need to remember these; they are simply not possible.

- Only a **helpless** character can be finished — bleeding out or stabilized. Somebody on their feet cannot be, and neither can somebody already dead.
- **A bandage does not protect anybody.** Stabilizing stops the clock; it does not stop a knife (D-038 §4a).
- You cannot finish somebody while you are yourself down or dead.
- You cannot finish yourself.
- The act takes time, is interrupted by moving away or being put down yourself, and is re-checked at the moment it completes — a target treated and stood up during those seconds does not die.
- **Every attempt is recorded**, whether or not it completed.

## What the rules require

These are the parts the code cannot check.

### 1. A killing needs a reason that exists in the world

There must be something the killer's character knows that makes this person worth killing: an order, a betrayal, a robbery gone wrong, a standing conflict, a witness who saw too much. "I was bored", "they annoyed me out of character", and "they were an easy target" are not reasons.

You do not have to justify it to the person you killed. You have to be able to justify it to staff.

### 2. Killing is a last resort, not an opening move

The design is about what people do to avoid killing each other. Robbery, intimidation, theft, blackmail, humiliation, hospitalization and simply walking away are all available and all cheaper. A character who reaches for the knife first, every time, is playing a different game from everybody else.

Leaving somebody incapacitated is a complete and often better outcome. They lose time, they lose what was in their pockets, and they are alive to be dealt with again.

### 3. You may not kill somebody you cannot identify as a threat or a target

Killing a stranger you have no history with, in a situation that had no build-up, is the clearest form of this being broken.

### 4. Out-of-character motive is never in-character motive

Nothing that happened outside the fiction may drive a killing. Not a grudge, not a Discord argument, not who they are in real life, not that they killed your last character.

### 5. Do not kill somebody who cannot respond

Do not finish a character whose player has plainly disconnected mid-fight, is clearly having a technical problem, or is mid-way through a staff matter. The bleed-out clock keeps running for a disconnected player by design (D-037 §4a) — that is the anti-combat-logging rule doing its job, and it is not an invitation to make sure.

### 6. One killing is one killing

Do not use the same conflict to justify killing several people in sequence. Each death needs its own reason.

---

## For staff

Everything is queryable, and this is the point of the logging design.

- `omerta_injury_history <characterId>` — every state change that character went through, with cause and actor.
- `omerta_events` — the durable record, including who killed whom and where.
- The audit log carries `death.confirmed` for completions **and `death.attempt_failed` for attempts that did not land.** The abuse pattern that actually gets reported is *"he kept trying"*, and a log of successes alone cannot answer it.

**When judging a report, the question is not "was this allowed by the mechanics".** The mechanics allowed it or it would not have happened. The question is whether there was a reason inside the fiction, and whether this player's characters keep finding such reasons.

## What this document does not cover

- Police killings and lawful force — M16/M17, when they exist.
- Executions as a sentence — M18.
- Funerals and what is done with bodies — post-MVP.
- The economy of a dead character's belongings; that is decided (D-038 §4c — everything stays on the body) and is not a rules matter.
