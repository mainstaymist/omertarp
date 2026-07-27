# Design Review — M6: Hidden Population

Status: **APPROVED 2026-07-27 — IMPLEMENTED** (§4 ruled option (b); logged as D-015). See §13.
Milestone: M6 (roadmap Track A). Depends on: M0–M5. Consumed by: nothing directly — it *removes* rather than adds, and every later milestone inherits its constraints.

> One decision needs your ruling (§4): how aggressively to override `Player:Nick()`. It trades addon compatibility against leak-proofing.

## 1. Purpose

M5 made identity something you earn. M6 makes sure nothing hands it out for free. The scoreboard, the kill feed, join/leave announcements, the voice-chat panel and `Player:Nick()` all cheerfully publish exactly what the design spent a milestone protecting — and unlike M5, this milestone is judged by what a determined player *cannot* find rather than by a feature list.

It also delivers **spike S3**: an automated audit that tells us what we are leaking, run on demand and re-run after every future milestone.

## 2. Responsibilities

**In scope:** scoreboard suppression; kill-feed and death-notice removal; join/leave announcement suppression; the default voice-chat panel (it renders Steam names); a single-team posture so team APIs reveal nothing; `Player:Nick()` handling (§4); the leak-audit command; the written metagaming rules specification the roadmap makes a deliverable of this milestone.

**Out of scope:** the contextual HUD framework and the remaining default HUD elements (M8 — M6 removes only what leaks *identity or population*); local text and voice routing (M7); staff tooling UI (M24). Engine-level residue that Lua cannot reach is documented, not "fixed" (§7).

## 3. Public API

Almost none, by nature. What exists:

```lua
Omerta.Population.Audit()        -- runs the leak audit, returns findings
Omerta.Population.RealName(ply)  -- the Steam name, for staff/logging only (server)
```

Plus the console commands `omerta_leak_audit` (staff) and the suppression hooks themselves, which have no callers.

## 4. The Ruling — how far to override `Player:Nick()`

`Nick()` returns the Steam name. Anything that prints a player — an addon, a stray `print`, a third-party admin mod, a future careless line of our own — leaks a real-world identity that can be correlated with a character. Three options:

- **(a) Leave it alone.** Zero compatibility risk; every leak is a discipline problem forever, and one careless addon undoes the milestone.
- **(b) Override to a neutral placeholder** — recommended. `Nick()`, `Name()` and `GetName()` return `"Unknown"` for everyone except the player themselves, who gets their own character name. The genuine Steam name stays available server-side as `Omerta.Population.RealName(ply)` for logs, audit rows and staff tools. Anything that prints a player without going through `ResolveDisplayName` now prints something harmless rather than something damaging.
- **(c) Override and also lie to staff tools.** Rejected outright: staff must be able to identify who they are moderating.

**Recommendation: (b).** The compatibility cost is real but small in a from-scratch gamemode that runs no third-party content, and it converts a permanent discipline problem into a structural one. Note it cannot be perfect — `Nick()` is a Lua method, and the engine still knows the truth (§7).

## 5. Networking

Nothing added. The milestone is mostly *deletions* plus hook overrides. The audit runs entirely server-side and reports to the server console.

## 6. Persistence

None. No tables, no migration — the first milestone since M0 with neither.

## 7. Security Considerations — and an honest limit

The suppressions:

| Surface | Treatment |
|---|---|
| Scoreboard | `GM:ScoreboardShow` returns false; no custom roster UI exists to replace it |
| Kill feed | `GM:AddDeathNotice` suppressed; no death events reach clients |
| Join/leave | Our `GM:PlayerConnect`/`PlayerDisconnected` never call the base implementation that prints them |
| Voice panel | Default `VoiceNotify` panel disabled — it renders Steam names beside a speaking indicator |
| Teams | Everyone on one team; faction never touches the team API (Tech §4) |
| Player names | §4 |

**What we cannot fix, and must therefore rule on instead.** The engine — not Lua — holds every connected player's Steam name and SteamID, and hands them to each client. `status` in the console lists them; any client-side addon can read `player.GetAll()`. **Population size and Steam identities are not concealable in Source.** Tech §4 already concedes this; M6's job is to make that residue *useless* rather than absent, which it does by keeping Steam identity and character identity completely uncorrelated in everything we network. Knowing "eight people are connected, one of them is SteamID X" tells you nothing about who the man in the trench coat is. The remaining gap — correlating a Steam identity to a character through outside channels — is a **rules** matter, which is why the written metagaming policy ships with this milestone rather than after it.

**The audit** (`omerta_leak_audit`) checks what we *can* control and is designed to be re-run after every future milestone:
- every registered net message, flagged if it carries name-like fields to recipients who may not be entitled to them;
- networked variables on players (client-readable) containing character data — the classic accidental leak;
- whether each suppression hook is actually installed (an addon or a refresh can silently displace one);
- whether `Nick()` is overridden as expected;
- team assignments beyond the single expected team.

## 8. Dependencies

M0 (config, log, net registry — the audit reads it), M4/M5 (to know what character data *should* look like when hunting for it).

## 9. Future Extension Points

- The audit's check list grows with each milestone; adding a check is a table entry.
- `Omerta.Population.RealName` is what M24's staff tooling will use.
- If a scoreboard-shaped UI is ever wanted for staff, it attaches behind the same authorization gate as M24.

## 10. Architecture Rationale and Alternatives Rejected

**Rejected — a custom scoreboard showing character names.** Tempting and wrong: it would hand every player a roster of everyone they have met *and* prove who is online, which is the correlation attack the whole design exists to prevent.

**Rejected — hiding player count by faking entities or blocking `player.GetAll()`.** Cannot be done reliably from Lua, and attempting it produces the worst outcome: a false sense of security. Better to state the limit plainly (§7) and make the leak worthless.

**Rejected — suppressing the entire default HUD here.** It is one line away, but health and ammo belong to M8's contextual framework; mixing them in would blur the milestone boundary and pre-empt design decisions M8 owns.

## 11. Testing Strategy

- **Headless**: the audit's pure analysis functions — net-schema name-field detection, NW-var scanning against a synthetic entity table, suppression-registry checks — driven with both clean and deliberately-leaky fixtures, so the audit is proven to *catch* leaks rather than merely to run.
- **In-engine** (`omerta_leak_audit`, plus manual): scoreboard key does nothing; no join/leave lines; no kill feed on death; the voice panel does not appear when speaking; `Nick()` returns the placeholder; the audit reports zero findings on a clean server.
- **Adversarial, needing two clients**: with a second client connected, confirm that nothing in ordinary gameplay UI reveals the other player's character name until introduced — and record honestly which engine-level surfaces still expose Steam identity, as input to the rules document.

## 12. Integration With Existing Systems

A single `modules/population/` module plus a short rules document at `docs/rules/metagaming.md`. The hooks live in one place so the audit can verify them and so a future reader can see the entire suppression surface at once. Nothing in M0–M5 changes.

---

## 13. Implementation Notes (post-implementation)

Implemented as `modules/population/`, plus the rules document at `docs/rules/metagaming.md`. Suite grew to 123 checks. Notes:

- **§4 ruled option (b)** (D-015). `Nick()`/`Name()`/`GetName()` return `"Unknown"`; on the client your own methods return your own character name. The original method is captured once as `PLAYER.OmertaSteamName`, guarded so a Lua refresh cannot overwrite it with our replacement and lose the real name permanently.
- **Option (b) required networking players their own character name**, which nothing had done: a new `characters.self` message plus `Omerta.Characters.GetLocal()`. Safe by construction — it is the player's own data and never carries anyone else's.
- **`PlayerDisconnected` is deliberately not hooked for suppression.** Returning a value from a `hook.Add` handler stops later handlers *and* the gamemode function, which would silently break the accounts, characters and identity handlers already sharing that event. The leave line is suppressed client-side through `ChatText` with `msgType == "joinleave"` instead — a case where the obvious implementation would have broken three earlier milestones.
- **Audit analysis is pure and adversarially tested**: every check is driven with a clean fixture *and* a deliberately leaky one, so the audit is proven to catch leaks rather than merely to run. One check asserts that every outbound name-bearing net message is on a reviewed allowlist (`identity.name`, `identity.introduce_prompt`, `characters.self`) — so a future milestone adding a fourth fails the suite until it is justified.
- **Also delivered here** (requested alongside): `omerta_character_retire <id> [reason]`, and the character gate refactored so a staff retirement re-gates a player who is still connected rather than leaving them walking around as nobody.

In-engine acceptance (user-side): pull, restart, then `omerta_leak_audit` — expect three `review` lines for the allowlisted messages and **zero** `LEAK` lines. Manually: TAB does nothing, no join/leave chat lines, no kill feed, no name panel when speaking. Confirm `status` still lists Steam names — that is the documented engine residue, not a failure.
