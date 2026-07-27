# Design Review — M7: Local Text and Voice

Status: **AWAITING APPROVAL — no implementation until approved.**
Milestone: M7 (roadmap Track A). Depends on: M0–M6. Consumed by: M11 (radios register a channel), M12 (telephony registers call channels), M13 (businesses as social space), every social system thereafter.

## 1. Purpose

M5 made identity earned; M6 stopped it leaking. M7 is where that work finally becomes *visible in ordinary play*: the same sentence appears as **"Tony Marino says…"** to someone who has met him and **"Unknown says…"** to everyone else in earshot. It also delivers the accessibility guarantee the design has promised since the Brainstorm — that a player without a microphone is never a second-class citizen.

## 2. Responsibilities

**In scope:** distance-based 3D voice; ranged local text with per-recipient speaker resolution; a channel registry (say / whisper / yell / me) that later systems extend; suppression of GMod's default global chat; message validation and rate limiting; queryable moderation logging with retention (migration 6); the client chat renderer.

**Out of scope:** radios (M11 — equipment-gated, registers a channel here); telephony (M12, same); OOC and global chat (never — no milestone will add them); voice muffling and line-of-sight occlusion (Tech §7 explicitly calls these optional later work); typing indicators (they would publish presence); the contextual HUD (M8).

## 3. Public API

```lua
-- Channel registry: later milestones add channels without touching this module
Omerta.Chat.RegisterChannel(id, {
    label    = "says",           -- verb used in the rendered line
    range    = 400,              -- audible radius in units; nil = not proximity-based
    prefix   = "/w",             -- optional chat trigger
    emote    = false,            -- emotes render as narration, not speech
    colour   = Color(...),
    canUse   = function(ply) end,        -- server-side gate (equipment, state)
    audience = function(ply, channel) end, -- optional override; default is radius
})

Omerta.Chat.Send(ply, channelId, text)   -- server: validate, deliver, log
Omerta.Chat.GetChannel(id)

-- Hooks
hook.Run("Omerta.ChatSent", ply, channel, text, recipients)
```

## 4. The Resolution Question — why the server resolves, not the client

M5 established that a client may ask "who is entity N?" and get an answer scoped to its own knowledge. Chat could reuse that: send the speaker's entity index and let each client resolve it.

**It shouldn't.** The server already knows every answer at send time, so a round-trip adds latency to the one system where latency is most visible, and it would leave the name arriving *after* the words. Worse, it would require clients to hold resolved names for people they cannot currently see, which is exactly the cache M5 refuses to keep.

So: **the server resolves the speaker's name once per recipient and embeds it in that recipient's copy of the message.** The same sentence goes out N times with N different labels. N is bounded by earshot — a handful of people — so the cost is trivial, and each client receives only what it is entitled to know. Concealment (D-014) applies automatically, since resolution runs through `ResolveDisplayName`: a masked speaker is "Unknown" even to people who know him, which is precisely right.

## 5. Networking

| Message | Direction | Payload |
|---|---|---|
| `chat.say` | client → server | channel (uint 4), text (string, 256) |
| `chat.message` | server → client | speaker entity (uint 16), channel (uint 4), name (string 56), text (string 256) |

Rate-limited through the M0 layer (a burst of 4 over 6 seconds, so ordinary conversation is unimpeded and flooding is not). GMod's default chat is suppressed entirely by returning `""` from `PlayerSay` — otherwise every message would broadcast globally, which would undo M5 and M6 in a single line of text.

The `name` field is a fifth outbound name-bearing field, so **M6's audit allowlist gains one entry** — deliberately, and with the same review reasoning as `identity.name`.

## 6. Persistence

Migration 6, a dedicated table rather than the audit log — chat volume would swamp the audit trail that exists for sensitive actions:

```lua
chat_log: id(id), at timestamp NOT NULL, season_id ref NOT NULL,
          character_id ref NOT NULL, channel text(16) NOT NULL,
          text text(256) NOT NULL,
          pos_x int, pos_y int, pos_z int,   -- where it was said
          recipients int NOT NULL DEFAULT 0
          indexes: (character_id), (at), (season_id)
```

Position is stored because "who else was in the room" is a question staff will need to answer when investigating metagaming, and it is far cheaper to record than to reconstruct. Retention is configurable (`chat.retention_days`, default 14) with the same periodic sweep M2 uses for audit rows.

Config: `chat.range_say` (400), `chat.range_whisper` (120), `chat.range_yell` (800), `chat.max_length` (256), `chat.retention_days` (14).

## 7. Security Considerations

- **Range is computed server-side**; the client never states who should hear it.
- **Speaking requires a living character** — no character, no voice, no text. This also covers the gated state M4 puts characterless players in.
- **Text is sanitised**: control characters stripped, length capped, no markup. Names in the rendered line come from the server's resolution, never from the message body.
- **Voice**: `PlayerCanHearPlayersVoice` returns audibility from distance alone and 3D positioning always; there is no global channel and `sv_alltalk` must remain 0. The check runs per listener-talker pair and stays a distance comparison for that reason.
- **Every message is logged** with character, channel, position and recipient count — the record that makes "my character overheard that" a checkable claim (`docs/rules/metagaming.md` §5).
- **No typing indicator, no speaking indicator** beyond what the local player can see: both would publish presence.

## 8. Dependencies

M0 (net, config, log), M1 (migration 6), M3 (season scoping), M4 (characters), M5 (`ResolveDisplayName`), M6 (the audit allowlist gains an entry).

## 9. Future Extension Points

- **`RegisterChannel` is the seam** M11's radios and M12's phone calls plug into: a channel with its own `canUse` gate and `audience` function, needing no changes here.
- `audience` also accommodates non-proximity delivery (a radio net, a phone line) without special-casing.
- Voice occlusion and muffling attach to the same audibility function when they arrive.
- The chat log is where a future "what was said near this crime scene" investigation tool will read from.

## 10. Architecture Rationale and Alternatives Rejected

**Rejected — client-side speaker resolution** (§4).

**Rejected — reusing GMod's chat with a hooked prefix.** The default system broadcasts globally by design; building on it means one missed suppression publishes everything to everyone.

**Rejected — logging chat into the audit table.** Volume would bury the sensitive-action trail M2 exists to preserve. A separate table with its own retention keeps both useful.

**Rejected — a single "say" range.** Whisper and yell cost almost nothing to add and give players real control over who hears them, which in a game about operational security is a mechanic rather than a convenience.

**Rejected — line-of-sight occlusion at MVP.** Consistent with M5's introduction decision: it behaves badly around doorways and thin walls, and the honest version needs sound propagation the engine will not give us cheaply. Deferred, with the audibility function shaped to accept it later.

## 11. Testing Strategy

- **Headless**: audibility by range per channel (in range, out of range, exactly at the boundary); text sanitisation (control characters, over-length, empty, markup); channel registration validation; prefix parsing (`/w`, `/y`, `/me`, plain text, an unknown slash command); the per-recipient resolution decision table, including a concealed speaker; retention cutoff maths; migration 6 rendering.
- **In-engine** (`omerta_chat_selftest`): channel registry integrity, a synthetic message through validation and logging, retention sweep, cleanup.
- **The lived test, two clients**: A and B in earshot, unacquainted — both see "Unknown says…". A introduces themselves; B's *subsequent* messages from A now read "Tony Marino says…" while A still sees "Unknown" until reciprocated. Step out of range and the messages stop arriving at all, rather than arriving greyed out.

## 12. Integration With Existing Systems

`modules/chat/`, `depends = { "characters", "identity" }`. M2's lifecycle contract: schema and migration 6 in `OnLoad`; hooks, channels and net handling in `OnEnable`. The only change to an existing module is adding `chat.message`'s `name` field to M6's reviewed allowlist.

---

**Requesting approval to implement M7 as specified.** No ruling is needed this time — the open questions (§4 resolution strategy, three ranges, separate chat log, deferred occlusion) all have clear recommendations, but say the word if you would prefer different ranges or a single one.
