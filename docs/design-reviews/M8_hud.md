# Design Review — M8: Contextual HUD Framework

Status: **APPROVED 2026-07-27 — IMPLEMENTED AND VERIFIED IN-ENGINE** (`omerta_hud_selftest` 6/6, including the headline check that the screen is empty when idle; 7 elements registered). §4a ruled *keep* hunger, inventory-only; §4b ruled (b); logged as D-016 and D-017. See §13. Amended 2026-07-28 with entity labels (D-033) and jump stamina — see §14.
Milestone: M8 (roadmap Track A). Depends on: M0–M7. Consumed by: M9 (inventory), M12 (telephony), M19 (injury), M21 (newspaper) — every system that ever needs to show the player something.

> **Two things need your ruling** (§4): confirmation of Q-7 (no hunger mechanic), and the crosshair, which the GDD says to remove and which materially changes how the game feels to play.

## 1. Purpose

The design's interface rule is unusually strict: *the persistent screen is empty*, and elements appear only in response to conditions (Tech §8, GDD §8). That is easy to state and easy to erode — one milestone adds a health bar "just for testing", another a money counter, and the game quietly becomes the thing it was built not to be.

M8 makes the rule structural. Nothing draws except through a controller that asks each element whether it currently *deserves* to be on screen, fades it in when the answer changes, and fades it out again. It also removes the last of the engine's own HUD, and establishes the accessibility baseline the design has promised since the Brainstorm.

## 2. Responsibilities

**In scope:** the element registry and visibility controller with fades; suppression of the remaining default HUD; a stamina system and its indicator (§4a); the injury-indicator seam (M19 fills it); migrating M5's target label and interaction menu onto the framework; UI scaling for accessibility; the sound-independent-cue rule.

**Out of scope:** the inventory interface (M9), the phone interface (M12), the newspaper reader (M21) — each builds its own panel *on* this framework; the character-creation window (a VGUI frame, not HUD, and it stays as-is); injury *states* (M19 — M8 only draws what it is told); any permanent element, ever.

## 3. Public API

```lua
-- Client
Omerta.HUD.Register(id, {
    order   = 20,
    fade    = 0.35,                    -- seconds in and out
    visible = function() return bool end,   -- the condition; false by default
    draw    = function(alpha) end,          -- only called while alpha > 0
})
Omerta.HUD.Unregister(id)
Omerta.HUD.Scale()            -- accessibility multiplier, 0.75–1.5
Omerta.HUD.Font(role)         -- "body" | "label" | "small", already scaled
Omerta.HUD.Cue(id, opts)      -- a visual cue; every audio cue must have one

-- Server
Omerta.Stamina.Get(ply)       -- 0..1
Omerta.Stamina.Drain(ply, amount)   -- for later systems (sprinting, carrying)
```

## 4. The Rulings

### 4a. Q-7 — hunger and stamina (confirmation)

The review recommended, and I still recommend: **no hunger mechanic.** Stamina exists and is driven by sprinting alone; food and drink give a small stamina recovery and social reason to sit in a bar, nothing more. The Brainstorm's own instruction was to "avoid turning hunger into constant busywork" (BA §13), and a hunger bar in a game with no permanent HUD would need a permanent HUD to be fair.

Confirming this closes Q-7 and logs it as a decision.

### 4b. The crosshair

GDD §8 lists the crosshair among things never displayed. I have no design objection — it suits the period and the deliberate, non-arcade combat — but it is the single change in this milestone a player will feel most, and it interacts with M5's interaction system, where you point at people to introduce yourself.

Three options:

- **(a) No crosshair at all**, per the GDD. Strongest immersion; aiming and interaction both become "point your body at it".
- **(b) No crosshair, but the interaction system shows a small dot or bracket when something interactable is under your gaze** — recommended. It preserves the empty screen and the immersion while making "what am I pointing at" answerable, which matters because M5 already requires precise targeting and M9/M13/M14 will require more.
- **(c) Keep a conventional crosshair.** Contradicts the GDD; I would not.

**Recommendation: (b).** It is the GDD's intent — no persistent aiming reticle — while keeping the interaction systems usable.

## 5. Networking

One message, and it exists because of M6.

| Message | Direction | Payload |
|---|---|---|
| `hud.stamina` | server → client | value (uint 7, 0–100) |

Stamina is **sent privately to its owner**, not stored in a networked variable. An `NWFloat` would be the obvious implementation and is exactly what M6's audit flags: networked variables are readable by every client, so a stamina value would publish who is sprinting, and by extension who is running from what. Sent on meaningful change only (threshold crossings and while draining), throttled to a few times a second.

## 6. Persistence

**None.** No tables, no migration — the second milestone after M6 with neither. UI scale is a client convar, stored client-side where it belongs.

## 7. Security Considerations

- **Stamina is server-authoritative**: the server owns the value, applies the movement penalty, and tells the client only for display. A client that lies about its stamina changes nothing.
- **No networked variables** (§5).
- The HUD reads only what the client has legitimately been told — resolved names from M5/M7, its own character from `characters.self`. M8 introduces no new source of information about other players.
- Cues are visual-only by policy: no mechanic may depend on hearing a sound (Tech §8 accessibility), which also means no mechanic leaks through audio a deaf player cannot check.

## 8. Dependencies

M0 (config, net), M4 (own character), M5 (target label, interaction menu — both migrate onto the framework), M6 (the audit's NW-var rule shaped §5), M7 (chat is GMod's own box and stays outside the controller).

## 9. Future Extension Points

- **`Omerta.HUD.Register` is the seam** for M9's inventory, M12's phone, M19's injury state, M21's newspaper — each a registration with a `visible` condition, no controller changes.
- **`Omerta.Stamina.Drain`** is what carrying bodies (M19), fleeing (M14) and later fatigue systems will call.
- The injury element ships with `visible` returning false until M19 registers a state provider — the same seam pattern D-014 used for concealment.
- UI scale and the font roles are the single place a future art pass changes typography.

## 10. Architecture Rationale and Alternatives Rejected

**Rejected — letting each system draw in its own `HUDPaint` hook.** This is what M5 currently does, and it is how the empty-screen rule dies: with a dozen independent painters, nobody can answer "what is on screen right now, and why?" The controller makes that a single, inspectable list, which is why M5's two elements migrate onto it as part of this milestone rather than being left alone.

**Rejected — a networked variable for stamina** (§5).

**Rejected — a permanent minimal HUD "just for development".** Temporary UI has a way of becoming permanent, and the design is explicit. Development visibility comes from the console and self-tests, which is where it has come from for eight milestones.

**Rejected — building the inventory or phone panels here.** They belong to their own milestones; M8 provides the surface they attach to.

## 11. Testing Strategy

- **Headless**: the controller's visibility/fade state machine (hidden → fading in → visible → fading out, and reversal mid-fade); registration validation; scale clamping; stamina drain/regen maths and the exhaustion threshold, all pure.
- **In-engine** (`omerta_hud_selftest`): every registered element reports its condition, and the suite asserts that with a healthy idle character **the screen is empty** — the milestone's actual acceptance criterion, checkable rather than eyeballed.
- **Manual**: sprint until winded and watch the indicator fade in and out; look at a player and see the target label; hold the interaction key; change `omerta_ui_scale` and confirm text rescales; confirm health, ammo, armour and crosshair are gone.

## 12. Integration With Existing Systems

`modules/hud/`, `depends = { "characters", "identity", "interaction" }`. M5's `cl_identity.lua` label and `cl_interaction.lua` menu are refactored to register elements instead of hooking `HUDPaint` directly; their behaviour is unchanged, but they gain fades and scaling and become visible to the controller's inspection. Nothing else in M0–M7 changes.

---

## 13. Implementation Notes (post-implementation)

Implemented as `modules/hud/`. Suite grew to 140 checks. Notes:

- **§4a was ruled against my recommendation, and better than it:** hunger is *kept*, but displayed only in the inventory — checked deliberately, like money in a wallet (BA §11). The consequence is that **hunger moved out of M8 entirely and into M9**, since the inventory is its only interface; building the mechanic here would have shipped an invisible system a milestone early. M8 therefore covers stamina alone. D-016 records the open follow-up: whether a *contextual* starvation warning should exist, since without one a player is degraded by something they were never given a chance to notice.
- **§4b ruled (b)** (D-017): `CHudCrosshair` is suppressed and a small dot appears only when something interactable is under the gaze. Players are the only interactable targets today; M9/M13/M14 extend the same predicate.
- **`HUDDrawTargetID` is suppressed too** — it draws player names, so it belonged in M6's leak sweep and was missed there. Caught while enumerating the engine's HUD elements.
- **M5's two elements migrated onto the controller** as planned, gaining fades and scaling. `cl_identity.lua`'s label moves its trace and resolve-request into the element's `visible()`, so the request only happens when the element is actually being considered.
- **A broken element unregisters itself** rather than taking the screen down: a `pcall` around each draw, an error log, and removal. One bad element must not blank the HUD.
- **Exhaustion is hysteretic** (falls below 5, recovers above 25) because a single threshold flickers the sprint on and off every frame at the boundary — the sort of thing that is invisible in a design document and obvious within ten seconds of playing.
- **Module dependency direction:** `identity` and `interaction` now depend on `hud`, not the reverse. The headless suite caught this immediately when three test files booted the graph without `hud` present — the loader refusing an unknown dependency doing exactly its job.
- `Omerta.SelfTest.Run` lost its server-only assertion, since the HUD suite must run client-side.

In-engine acceptance (user-side): pull, restart, then run **`omerta_hud_selftest` in a CLIENT console** (the HUD only exists there) — expect 6/6, including the headline check that the screen is empty when idle. Then manually: sprint until winded and watch the bar fade in and out, look at another player for the dot and the name label, hold `C`, and try `omerta_ui_scale 1.4`. Health, armour, ammo and crosshair should all be gone.

---

## 14. Amendment — labels and the jump (2026-07-28)

Two changes reached back into this milestone after M13, both because M8 owns the surface they belong to.

**Entity labels (D-033).** D-017's dot said *that you can interact*; it never said *with what*. In a world built from placeholder models that is a real gap — a character can obviously tell a crate of whiskey from a crate of nothing, and the player was looking at two identical wooden boxes. The indicator now carries a short label, under the dot rather than over it so the object stays unobstructed.

The label is asked of the entity (`ENT:OmertaLabel() -> title, subtitle`), never decided here, which is the same seam `RegisterInteractableClass` already used: `cl_hud.lua` still does not know what an item is. `Omerta.HUD.LabelFor` lives in the shared file so the guard logic — invalid entity, missing method, a label that errors, an empty string — is covered headlessly rather than only in front of a running server.

The scope rule and its consequences are in D-033. Two lints hold the line: every class registered as interactable must define a label, and no entity may network a container id, line id, character id or owner. The second is the one that matters long-term — a label draws for everyone in range, so anything reachable from one has already left the server, and the lint catches that at the point where it is cheap.

**Jumping costs stamina.** Movement speed has been this module's exclusive property since M9 (§10's single-owner rule), and jumping was the one part of movement nobody had claimed — so a winded character could still vault a fence indefinitely, which quietly undercut stamina as a limit on fleeing. A jump now spends `stamina.jump_cost` (default 12 of 100) on the press, and exhaustion scales jump height by `stamina.exhausted_jump_scale` (default 0.55) rather than removing it, because a character who cannot leave the floor reads as a bug rather than as being out of breath.

Charged on `KeyPress`/`IN_JUMP` while on the ground, not per tick: billing `IN_JUMP` every tick charges for holding the key, and the ground check is what stops a bunny-hopper being billed once per bounce for free height. Jump power is computed in `applySpeeds` alongside walk and run and diffed against the last applied value, so it obeys the same speed modifiers everything else does and is set only when it changes.

Suite: 266 → 274 checks.
