# S1 — Voice Routing Spike

Status: **ANSWERED from the engine's API contract; one manual confirmation outstanding.**
Question (roadmap §Technical spikes): *Can call audio be routed participant-only while local speech stays spatial? Is any speakerphone approximation viable?*
Gates: M12's design review.

## 1. Why this was a spike

M12 requires two things to be true at once: a person on a telephone hears the other end no matter how far away they are, and everybody standing in the room hears only the half of the conversation spoken in front of them. If Garry's Mod cannot express that, the payphone design in D-003 collapses into a text-only mechanic and M12 becomes a different milestone.

## 2. The answer: yes, and the reason is the hook's shape

`GM:PlayerCanHearPlayersVoice(listener, talker)` is called **once per listener/talker pair**, and returns two values: whether the listener hears them at all, and whether the audio is positional.

```lua
return canHear, is3D
```

Because the decision is per *pair* rather than per *speaker*, the two requirements are not in competition. For a caller A talking to B across the map, with bystander C standing beside A:

| Pair | Decided by | Result |
|---|---|---|
| C hears A | distance (M7's existing rule) | audible, **3D** |
| B hears A | the call | audible, **2D** |
| C hears B | nothing — C is not on the call and B is far away | inaudible |

That table is the design, and it falls out of the API rather than having to be engineered around it. M7 already returns `true, true` for spatial speech; M12 adds a branch returning `true, false` for call participants.

**Speakerphone is therefore also viable** — it is the `C hears B` cell flipped to `true, false`. It is an approximation rather than a simulation: the far side arrives non-positional and at full volume, indistinguishable from being on the call yourself. That is a design decision, not a technical one, so it goes to M12 as a ruling rather than being settled here.

## 3. The finding that actually matters

**There must be exactly one `PlayerCanHearPlayersVoice` hook in the gamemode.**

`hook.Run` returns the first non-nil result from any listener, and listener order is not defined. M7 already registers one. If M12 registers a second, then whichever happens to run first decides — and the symptom is not a crash but *intermittently inaudible calls*, which is close to the worst possible bug to diagnose from a player report.

M12 must therefore extend M7's single hook through a provider seam, in the same shape as D-014's concealment provider and D-021's title provider:

```lua
-- Registered by M12; consulted by M7's one hook.
Omerta.Chat.RegisterVoiceOverride(function(listener, talker)
    -- return canHear, is3D  — or nil to defer to distance
end)
```

This is a small change to M7 and it is not optional. It is recorded here because it is the kind of constraint that is obvious once stated and invisible until something breaks.

## 4. Secondary findings

- **`sv_alltalk` must be 0.** With it on, the engine bypasses the hook for the global case and everybody hears everybody. It should be forced and audited, exactly as M6 audits the other engine-level leaks.
- **Voice is opt-in on the client.** A player with `voice_enable 0`, no microphone, or push-to-talk unbound cannot participate at all. Tech §8's accessibility rule means a call must be completable without a microphone, so M12 needs a text path on the same channel — not as a fallback bolted on, but as an equal way to hold the conversation.
- **Volume is not controllable per pair.** The hook is binary plus a 3D flag; there is no per-listener gain. "Faint and crackly on a bad line" is not achievable through this API and should not be promised.
- **No engine-level ceiling on participants** — the hook scales to as many pairs as there are players, so a party line or a conference is not blocked technically.

## 5. What is still unconfirmed

Everything above follows from the API contract and from how M7's existing hook already behaves in-engine. The one claim that deserves eyes rather than reasoning is **the mixed case**: A on a call with B, C standing next to A, all three talking. The table in §2 says C hears A positionally and B not at all, while A hears both — B flat, C positional.

Confirming it takes three players and two minutes, and it is worth doing before M12 is built rather than after:

1. Two players stand together, a third goes across the map.
2. Temporarily return `true, false` for the distant pair.
3. Check that the near pair still sounds directional and that the distant voice does not.

If that behaves as described, §2 is confirmed and M12 proceeds as designed. If mixing a 2D and a 3D source for one listener misbehaves, the fallback is text-only calls with voice deferred — a materially smaller M12, which is why this is worth knowing first.

## 6. Conclusion

- Participant-only routing: **viable**, directly supported.
- Local speech staying spatial during a call: **viable**, automatic.
- Speakerphone: **technically viable**, sent to M12 as a design ruling.
- Binding constraint: **one voice hook, extended by providers** — M7 must gain the seam.
- Accessibility: **a text path is mandatory**, not a courtesy.

S1 is answered. M12's design review may proceed.
