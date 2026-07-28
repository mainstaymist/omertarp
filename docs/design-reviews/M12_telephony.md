# Design Review — M12: Telephony (Payphones and Private Lines)

Status: **APPROVED 2026-07-27 — IMPLEMENTED AND VERIFIED IN-ENGINE** (lines installed, a call placed, rung, timed out, and recorded from both ends). §4a, §4b and §4c all ruled (a); logged as D-027, D-028 and D-029. See §13.
Milestone: M12 (roadmap Track B). Depends on: M7 (speech and the voice hook), M9 (quarters), M11 (a private line is bought), S1 (answered — `docs/review/05_voice_routing_spike.md`). Consumed by: M13 (a business has a line), M14 (calling ahead, and calling for help), M15 (call records are evidence), M18 (the booking phone call), M21 (a tip-off to the newspaper).

> **Three rulings needed** (§4): how a number becomes known, whether bystanders can hear the far end, and who may read call records.

## 1. Purpose

D-003 removed personal telephones from the design and replaced them with **payphones and location-bound private lines**. That is a deliberately awkward constraint, and the awkwardness is the point: to reach somebody you must know where they will be, or you must go and stand somewhere public and hope.

This milestone makes distance a thing you can cross deliberately, at a cost, from a fixed place — and leaves a record of having done so.

## 2. Responsibilities

**In scope:** the telephone line as a persistent, located, numbered thing; payphones (public, coin-fed) and private lines (bought, owned); dialling, ringing, answering, hanging up; call audio routed to participants only (S1); an equal text path on the same channel (S1 §4); coin consumption over the duration of a call (D-003); call detail records with metadata and never content; the M7 seam S1 requires.

**Out of scope:** any personal or portable telephone, ever (D-003); SMS (D-003); reading call records as a gameplay action (§4c — the records exist here, the investigation is M17/M18's); wiretapping and call interception (M15 — the CDR table is where it will attach); radios (M14's crews); operator-assisted or long-distance calling.

## 3. Public API

```lua
-- Lines
Omerta.Phone.RegisterLine(number, {
    kind = "payphone" | "private",
    organizationId = nil,        -- private lines belong to somebody
    label = "Marino social club",
})
Omerta.Phone.LineAt(entity)              -- which line this handset is
Omerta.Phone.Find(number)                -- server-side lookup

-- Calls
Omerta.Phone.Dial(ply, number, cb)       -- cb(ok, err)
Omerta.Phone.Answer(ply) / Hangup(ply)
Omerta.Phone.CallOf(ply)                 -- the call they are on, or nil
Omerta.Phone.Say(ply, text)              -- the text path (S1 §4)

-- Records
Omerta.Phone.Records(lineId, limit, cb)  -- metadata only, never content
```

## 4. The Rulings

### 4a. How does a number become known?

This is the milestone's information-philosophy question, and it has the same shape as identity.

- **(a) Numbers are learned, never listed** — recommended. A payphone has its number painted on it, so anyone standing at one can read it and **be called back there** — which is the whole mechanic: "go to the box on Third Street, I'll ring you in ten minutes." A private line's number is known to whoever bought it and to whoever they choose to tell. There is no directory, no lookup, no autocomplete.
- **(b) A directory of private lines.** Convenient, and it hands every player a map of who has what, which is precisely the omniscience the project exists to refuse.
- **(c) Numbers learned through M5's identity system**, as a kind of fact about a character. Elegant on paper; wrong in practice, because a number belongs to a *place*, not a person, and the whole point of D-003 is that those are different.

**Recommendation: (a).** A number written on a scrap of paper is an item M9 already supports, and a number shouted across a bar is M7 doing its job.

### 4b. Can bystanders hear the far end?

S1 confirmed this is technically free: it is one cell of the routing table flipped. So it is purely a design question.

- **(a) No — bystanders hear only the half spoken in front of them** — recommended. It is what a telephone actually sounds like from across a room, it makes overhearing a conversation genuinely partial, and partial information is the currency of this entire design. A witness who heard one side of a call is *more* interesting than one who heard both.
- **(b) Yes, always.** Loses the asymmetry for nothing.
- **(c) A speakerphone as an explicit action**, deliberately switched on. Buildable later on exactly the same routing; not worth the interface at MVP.

**Recommendation: (a)**, with (c) noted as a clean future addition rather than a rejected idea.

### 4c. Who may read call records?

Every call writes a record: which line called which line, when, for how long. Never content — the design has no place for stored recordings, and Tech §23's audit rules would make them a liability.

- **(a) Nobody, in M12. The records accumulate and are read by the investigation systems that earn access** — recommended. M17/M18 decide what a detective can pull and under what authority; M15 decides what a wiretap adds. Building the read path now means inventing that authority a milestone early, in a design review that should not be making police-procedure decisions.
- **(b) The line's owner can see their own line's records.** Defensible — it is your telephone bill. It also quietly hands every family a counter-intelligence tool before anybody has designed the intelligence half.
- **(c) Police can query freely.** Skips the authority question entirely, which is the interesting part of M18.

**Recommendation: (a).** Staff tooling to read records exists from day one; player-facing access is a later milestone's decision to make.

## 5. Networking

| Message | Direction | Payload |
|---|---|---|
| `phone.state` | server → client | your call: state (uint 3), the other number, seconds left |
| `phone.dial` | client → server | the number being dialled |
| `phone.action` | client → server | answer / hang up / feed a coin |
| `phone.say` | client → server | one line of text on the call |
| `phone.heard` | server → client | one line of text from the far end |
| `phone.ring` | server → client | this handset is ringing near you |

A client is told **its own call and nothing else**. It is never told who is on the other end beyond the number they dialled from, because a number is not a name (§4a) — identifying the voice is M5's job and the caller's problem.

Voice is not networked by this module at all: it goes through M7's single hook, extended by the provider seam S1 requires (§8).

## 6. Persistence

Migration 10:

```lua
phone_lines: id(id), season_id ref NOT NULL, number text(12) NOT NULL,
             kind text(12) NOT NULL, organization_id ref,
             map_name text(64) NOT NULL, pos_x int, pos_y int, pos_z int,
             label text(64), created_at timestamp NOT NULL
             unique: (season_id, number)

phone_calls: id(id), season_id ref NOT NULL,
             from_line ref NOT NULL, to_line ref NOT NULL,
             from_character_id ref, to_character_id ref,
             started_at timestamp NOT NULL, ended_at timestamp,
             seconds int NOT NULL DEFAULT 0,
             coins_spent money NOT NULL DEFAULT 0,
             outcome text(16) NOT NULL     -- answered | unanswered | cut_off
             indexes: (from_line, started_at), (to_line, started_at), (season_id)
```

**No content column, by construction.** There is no field a recording could be put in, so no later milestone can quietly start storing one without a migration and a conversation.

Lines are season-scoped like everything else, and located like M11's safes — a telephone that moves on restart is not a telephone.

## 7. Security Considerations

- **The server owns the call.** The client sends a number and the server decides whether that line exists, whether the caller is at a handset, whether the target is ringing, and who hears what. A client cannot join a call it was not connected to.
- **Voice routing is server-side and per-pair** (S1). A client cannot ask to hear anybody.
- **Coins are real** (D-018): a payphone consumes actual quarters from the caller's inventory through M9's transactional path, on a timer. When they run out the call ends — which is the mechanic D-003 asked for, not a fee.
- **Numbers are not enumerable.** Dialling an unassigned number rings nothing and is rate-limited, so the dial pad cannot be used to sweep the map for private lines.
- **Records are metadata only** (§6), and every call is audited (Tech §23).
- **`sv_alltalk` is forced to 0 and audited** (S1 §4) — with it on, the engine bypasses the hook entirely and the whole design silently evaporates.

## 8. Dependencies

M0 (config, net, log), M1 (migration 10), M2 (audit), M3 (season scoping and `WhenReady`), M9 (quarters, and a written-down number is an item), M11 (a private line is a procurement entry and the readiness primitive it added), S1 (answered).

**M7 changes**, and must: S1's binding finding is that a second `PlayerCanHearPlayersVoice` hook would make call audio depend on undefined hook ordering. M7 gains `Omerta.Chat.RegisterVoiceOverride(fn)`, consulted by its existing single hook, in the same shape as D-014's concealment provider. That is the only change to M0–M11.

## 9. Future Extension Points

- **`RegisterVoiceOverride` is the seam** M14's radios and any future party line use.
- The `phone_calls` table is where M15's wiretap attaches, and where M18's subpoena reads from.
- Speakerphone (§4b) is one routing branch away.
- A private line's `organization_id` lets M13 give a business its own number without a schema change.
- Numbers are strings, so exchanges ("KLondike 5-2368") are a formatting decision, not a data one.

## 10. Architecture Rationale and Alternatives Rejected

**Rejected — a second voice hook** (S1 §3). Intermittently inaudible calls, decided by hook ordering, is the worst class of bug this project could ship.

**Rejected — a directory** (§4a).

**Rejected — storing call audio or transcripts.** There is no column for it (§6). Content-free records are what make the CDR table safe to give an investigator later.

**Rejected — a per-call fee.** D-003 asks for quarters that run out mid-sentence; a flat charge is a different, worse mechanic.

**Rejected — text-only calls.** S1 confirmed voice works; a text path exists beside it for accessibility (Tech §8), not instead of it.

## 11. Testing Strategy

- **Headless**: number validation and formatting; the call state machine (idle → dialling → ringing → connected → ended, and every abnormal exit); coin consumption arithmetic over time, including the exact tick a call dies; the routing decision table from S1 §2 as a pure function of (listener, talker, call); record construction; migration 10 rendering.
- **In-engine** (`omerta_phone_selftest`): synthetic lines and a synthetic call — dial, ring, answer, run the coin timer down, confirm the call ends and the record is written with the right duration and outcome; a dial to an unassigned number; cleanup.
- **The lived test** (three players, and it is S1 §5's confirmation as well): one at a payphone, one at a private line across the map, one standing beside the payphone. The third must hear one half of the conversation, positionally, and nothing of the other. Then let the quarters run out mid-sentence.

## 12. Integration With Existing Systems

`modules/phone/`, `depends = { "chat", "inventory", "organizations", "treasury" }`. Handsets are entities placed by staff like M11's safes, using the placement helper M11 added. The private line is a procurement entry, so buying one is M11's existing flow with an `onPurchase` that registers a line. M7 gains the voice-override seam (§8); nothing else in M0–M11 changes.

---

## 13. Implementation Notes (post-implementation)

Implemented as `modules/phone/`. The headless suite grew from 224 to 238 checks. All three rulings came back as recommended.

**M7's voice hook became a seam before anything else was written**, because S1 said it had to. `Omerta.Chat.RegisterVoiceOverride(id, fn)` is consulted by the gamemode's one and only `PlayerCanHearPlayersVoice` hook; a provider that errors defers rather than silencing anybody. `sv_alltalk` is now checked at boot and forced off with a warning — with it on the engine bypasses the hook entirely and the whole design evaporates without a single error line.

**The first coin goes in when the call connects, not when it is placed.** A payphone that ate a quarter for an unanswered ring would be a fee with a friendly name, and D-003 asked for something you *feed*. Dialling checks you have a quarter; answering spends the first one; the timer spends the rest, one at a time, until your pocket is empty and the call stops mid-sentence.

**Picking up the receiver is one gesture, and the server decides what it meant.** Answering a ringing handset and opening a dial pad are the same physical act, so `Use` calls one function that works out which it was. The one number a handset will tell you is *its own*, printed on the box (D-027) — that is what makes being called back at a payphone possible.

**The text path goes through M7 rather than beside it.** What a mic-less player types is sent to the far end *and* spoken aloud in the room through `Omerta.Chat.Send`, which brings rate limiting, sanitisation, logging and range with it. That gives text exactly the asymmetry D-028 gives voice — bystanders see the near half and nothing of the far one — instead of a second, subtly different conversation system.

**An unassigned number rings and goes unanswered**, rather than refusing. A dial pad that reports "no such line" is a tool for sweeping the map for private lines; one that rings into nothing is a telephone.

**`phone_calls` has no content column and the test asserts it.** A rule somebody has to remember not to break is weaker than a table with nowhere to put the thing.

**A private line installs itself where the family already keeps its money.** M11's procurement seam takes an `onPurchase`, so buying a line places a handset beside the organization's safe and tells the buyer the number. No new placement flow, and it reinforces that the safe is the premises.

Not built, deliberately: reading records in-game (D-029 — that authority is M18's to design), wiretapping (M15), speakerphone (D-028 defers it behind a deliberate action), and any per-pair volume, which S1 §4 established the engine cannot express.

In-engine acceptance (user-side): pull, restart, then **`omerta_phone_selftest` in the SERVER console** — expect 10/10. Then, standing where a payphone should go:

```
omerta_phone_place payphone
omerta_phone_place private
omerta_phone_list
omerta_money_give 5 <your steamID64>
```

Walk to the payphone, press **E**, and dial the private line's number. The other handset rings — and so does the screen, for anyone standing near it who cannot hear the bell. Answer it, watch the credit tick down, and let it run out mid-sentence. `omerta_phone_records <number>` prints the record.

**The three-player test is also S1 §5's outstanding confirmation**, and is worth doing before M13: one player at each end of a call, a third standing beside one of them. The third should hear one half of the conversation, positionally, and nothing of the other.

---

**Delivered.** Rulings §4a, §4b and §4c all (a) as recommended; logged as D-027, D-028 and D-029.
