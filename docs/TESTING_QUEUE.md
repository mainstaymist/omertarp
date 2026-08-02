# Testing Queue

**What this is:** everything built but not yet confirmed working in-engine, in the order worth doing it. Kept current as work lands — when you report results, the statuses here get updated and anything that fails becomes a fix before new work starts.

**Last updated:** 2026-08-02, after M14 landed.
**Headless suite:** 619 checks passing. `luac -p` clean across the tree. 21 modules resolving.

Status key: **☐ untested** · **☑ passed** · **☒ failed** (details inline) · **◐ partly**

---

## M14 — crime, robbery and the clerk (NEW, untested in engine)

Everything here is fresh and none of it has been run in a server. **Start with
`omerta_crime_selftest`** — it builds an unowned store with a clerk and a full
register, drives the loop, and takes it all back out again. It needs you to be
in-game with a character: a robbery needs a robber.

| | Check | How |
|---|---|---|
| ☐ | **Migration 15 applies on MySQL** | Three tables: `crime_operations`, `crime_participants`, `crime_alarms`. This is the one that matters most — D-008 makes MySQL the backend of record and these have only ever run against SQLite |
| ☐ | **`omerta_crime_selftest` passes** | The arithmetic step is the one to read: *the till is lighter by what the robber is heavier by*. If those two numbers disagree, money is being created or destroyed and everything else can wait |
| ☐ | **The clerk is visible and shootable** | `omerta_business_place store nobody The Corner Grocer`, then stand at the counter and `omerta_clerk_place`. He is a `base_anim` with a physics box — if he is invisible, the model list in `omerta_clerk.lua` needs a fourth entry |
| ☐ | **The dot lights up on him and E holds him up** | He should get an action hint and **no name**, permanently, to everybody |
| ☐ | **He reacts** | Hands up, or backing away, or a hand going under the counter. Nothing about his decision reaches your screen — that is the design, not a missing feature |
| ☐ | **The register empties a handful at a time** | The promoted timed-action plate, repeated. Interrupting it mid-grab must take nothing |
| ☐ | **A full coat stops you** | Carry a Thompson and try to empty a full register. You should get what fits and be told you cannot carry more (D-020) |
| ☐ | **The crowbar levers a register he would not open** | Buy one from the auto shop; the interaction should only appear when he has refused |
| ☐ | **A mask makes you Unknown to your own crew** | **This is D-014 demonstrated for the first time since M5 cut the seam.** Buy one through procurement (`disguises`), equip it, and have somebody who knows your name look at you |
| ☐ | **The float fills an unowned register and stops at the ceiling** | Place a store as `nobody`, wait, and watch the till. An owned store must accrue nothing beyond D-032's trickle |
| ☐ | **A restart abandons rather than resumes** | Start a robbery, take some money, restart the server. The operation should be `failed`/`abandoned`, the event should still exist, and **the money should still be in your pockets** |
| ☐ | **Killing the clerk does not seal the register** | It should still empty, and it should be much worse for you afterwards |

**What cannot be tested alone**, and is the milestone's actual definition of
done: two players, both masked, one holding the clerk and one working the
register, both reading as Unknown to each other and to anybody who walks in.

---

## 0. Before anything else

| | Check | How |
|---|---|---|
| ☑ | **Server boots clean with 18 modules** | Look for `loaded 18 module(s): … injury, events, death, phone, weapons, menu` and no Lua errors |
| ☑ | **Client boots clean** | Join and check the client console — this has never been confirmed since the module count grew |
| ☑ | **Migrations 12 and 13 apply on MySQL** | **This is the one that matters most.** D-008 makes MySQL the backend of record, and the injury/body/event tables have only ever run against SQLite |

If migrations fail, stop and send me the error — everything below depends on them.

---

## 1. Knocking, and falling (2026-08-02)

**Migration 14 runs on first boot** (`character_impairments`). It is the first
new table since 13, and the first written since you confirmed MySQL applies
12 and 13 — so if a migration is going to fail, it fails here. Send me the
error and stop.

### Knocking

Empty hands, left click, a door. The sound comes out of the **door**, so
anybody near it hears it and learns nothing else about who knocked.

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **It works at all** | Empty hands, face a door, left click | The knock plays from the door |
| ☐ | **No overlap** | Click repeatedly as fast as you can | One knock finishes before the next starts (1.44s) |
| ☐ | **Two people, one door** | Both knock at once | Still no overlap — the lockout is per door, not per player |
| ☐ | **Locked doors too** | Knock on a locked door | It works. That is the entire point of knocking |
| ☐ | **Not with a gun out** | Hold a weapon, click at a door | Nothing. Only empty hands knock |
| ☐ | **E still opens doors** | Press E on a door | Opens normally. Doors were deliberately left out of the interaction registry so this keeps working |
| ☐ | **The map's doors count** | Try several doors around rp_unioncity | If some do nothing, tell me the class — it is one line to add |

**If knocking does nothing at all**, that is the one failure I predicted: it
relies on the engine running `PrimaryAttack` server-side for a SWEP that has no
clip. The weapon base proves that path for guns; hands takes a different branch.
The fix is known and small, so just say "knocking is dead" and I will land it.

### Falling

Three bands, one continuous curve, all five numbers configurable:

| height | damage | what happens |
|---|---|---|
| under 150 | none | a full storey is free |
| 150 – 340 | 0 → 34 | **low** — hurt, no break |
| 340 – 700 | 34 → 100 | **medium** — leg breaks |
| 700+ | 100 | **high** — leg breaks and you go down |

34 damage at the break height is exactly one Model 10 round, so the cheapest
leg-breaking fall leaves you where one revolver shot would.

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **A short drop is free** | Jump off something waist-high | No damage |
| ☐ | **It scales** | Fall from a few different heights | Damage rises smoothly with height, not in three steps |
| ☐ | **The leg breaks** | Fall from roughly two storeys | One of three break sounds, and you start limping |
| ☐ | **Full health does not save you** | Fall from something very high at 100 health | **You go down.** This is the requirement — armour or health must not be able to catch a six-storey fall |
| ☐ | **The limp reads as a limp** | Walk around with a broken leg | Slower, then faster, in one cycle per stride, with a slight one-sided camera dip. **Watch for rubber-banding** — if it feels like lag rather than a drag, tell me and I will speed up how often it is applied |
| ☐ | **Standing still does not bob** | Stand still with a broken leg | Camera is still |
| ☐ | **It survives a reconnect** | Break a leg, disconnect, rejoin | Still limping, with the clock where you left it |
| ☐ | **It does not survive death** | Break a leg, die, make a new character | No limp |
| ☐ | **A doctor sets it** | Get treated while down with a broken leg | The break clears with the treatment. A bandage alone does not |
| ☐ | **The sounds are quiet enough** | Break a leg | They were loud, so they play at about a third. Tell me if that is still wrong |

**One thing needs a ruling.** A medium fall from full health breaks your leg
without putting you on the floor — and every treatment in the game targets
somebody who is *down*. So a walking man with a broken leg **cannot currently
be treated at all**; his only cure is the ten-minute clock. That may well be
right. If you want a doctor to be able to set a standing man's leg, say so and
it becomes a real piece of work in the interaction layer.

---

## 1b. Third-party weapons, the period models, and three search bugs (2026-08-01)

### Install these server-side first

Nothing in this section works until the server's own collection carries
them — `resource.AddWorkshop` only feeds clients:

- the **ARC9 base** plus the **BO2** and **WaW** packs (`arc9_bo2_thompson`, `arc9_waw_m1911`)
- the **TFA base** plus the **Insurgency 2** pack (`tfa_ins2_wpn_38revolver`)
- the **playermodel pack** those six mafia models come from

**A missing pack is not a crash.** Each weapon independently falls back to our
own base and logs it. `omerta_weapons_list` prints what each gun is actually
running, and `(wanted <class>)` when it fell back — run that first.

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **What is actually running** | `omerta_weapons_list` | Three weapons on their external classes, no `(wanted …)` |
| ☐ | **The names** | Same, and in a shop | Model 10, M1921 AC Thompson, M1911 |
| ☐ | **The M1911 exists and can be bought** | Treasury/procurement | `supply.m1911` at $125 |
| ☐ | **They fire and kill sensibly** | Shoot a second character | Revolver 3 body shots, M1911 4, Thompson 8. **Our numbers, not the addon's** |
| ☐ | **Reload comes out of your pockets** | Carry rounds, fire, reload | Rounds leave the inventory. The reserve readout tracks it |
| ☐ | **You cannot mint ammunition** | **Try to break this.** Equip, unequip, re-equip, drop mid-reload, reload with a full magazine, swap guns mid-reload | Your total rounds must never go **up**. Fewer than you expected is a known and accepted failure direction; more is a bug and I want to hear about it immediately |
| ☐ | **Fallback works** | Rename or remove one pack | That weapon reverts to our base, the others keep theirs, nothing errors |
| ☐ | **Playermodels** | Create a character | Six appearances, no error models |

**The accounting risk, stated plainly.** ARC9 may keep ammunition in state that
`Clip1()` does not report. If it does, the bridge is blind on that gun — it can
never hand out more than a character owns, but it may not see everything. This
is the one thing that needs a real session before it is trusted, which is why
"try to break the ammo" is the check that matters most in this section.

Also: the arsenal's world models are still HL2 placeholders, so a **holstered**
gun on somebody's back or hip will look wrong until they are pointed at the
addons' own models. Firing and holding will look right.

### The search bug was three bugs

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **Holding E searches to completion** | Hold E on a body without releasing | One search that finishes and opens the pockets. It used to cancel itself a tick after starting |
| ☐ | **Aim badly on purpose** | Search a ragdoll aiming at the gap between a limb and the floor | Works the same. That mis-aim is what chose the broken path |
| ☐ | **Cancelling silences the rustle** | Start a search, press E again | Sound stops **immediately**. It could not be cancelled at all before |
| ☐ | **The plate survives a cancel** | Cancel a search, then search again. Then have somebody treat you | Everything still draws. One cancel used to permanently unregister the plate for the rest of the session |
| ☐ | **The settings toggles change at once** | Settings → Black and white, watch the button | It flips on the click, not on the next visit |
| ☐ | **The season number** | Bottom of the menu | Your existing season now shows a number — it takes its ordinal, since its label is a name |

---

## 1c. The fourteen-item pass (2026-08-01)

Two of these were the same bug, and two more were not what they looked like.

### The stuck windows — one race, reported twice

*"Spam C and it duplicates the inventory menu which stays and will not go away"*
and *"the looting screen cannot be closed with C and you can still open your
inventory in that view"* have a single cause.

`Panel:Remove()` does not destroy a panel where it stands — GMod marks it and
deletes it at the end of the frame. So a **replaced** window's teardown always
ran after its replacement had been built, and it nulled the live window's
pointer and zeroed the shared loot session. No pointer meant nothing could
close what was on screen and the next C built another over the top; a zeroed
loot session meant a live loot plate stopped counting as looting, so C stopped
dismissing it and the pockets branch became reachable underneath it.

And the C poll was level-triggered, so the press that dismissed a loot plate
was still down on the next frame — by which time the plate read as "not open"
and the dismissal opened pockets itself. **Pressing C to close the loot window
was the thing that fired the race.**

| | Check | How | Expect |
|---|---|---|---|
| ☑ | **Spam C** | Hold and release C repeatedly, fast | One window, every time. Never two, never one that will not leave |
| ☑ | **C closes the loot window** | Search a body, press C | It closes. This is the one that was completely stuck |
| ☑ | **C does not then open your pockets** | Same press, watch what follows | Nothing opens behind it |
| ☑ | **Pockets cannot open over a loot plate** | Loot plate up, press and hold C | The plate closes; your pockets do not appear in its place |
| ☑ | **The server lets go too** | Dismiss a loot plate, then pick something up | Your pockets refresh silently. The body's plate does **not** come back unasked |
| ☑ | **E again cancels a search** | Start searching, press E again | It stops. Nothing was taken, nothing to undo |
| ☑ | **Holding E does not stutter** | Hold E on a body | One continuous search, not a rummage restarting several times a second |
| ☑ | **The titles sit properly** | Open pockets, then a body, then a container | POCKETS / the body's name / the container's name all clear of the plate edge |

### The gun

| | Check | How | Expect |
|---|---|---|---|
| ☑ | **The crosshair is round** | Look at anything | An actual circle, slightly smaller. It was a rounded *square* — `draw.RoundedBox` builds corners from a texture, which cannot resolve a curve at three pixels |
| ☑ | **The ammo reads left to right** | Hold a gun | Big loaded count **first**, `/ reserve` small after it. It was reversed |
| ☑ | **Reload with empty pockets** | Hold R with no ammo | One line per press. Hold it down and it stays one line |
| ☑ | **Tapping R twice still says it twice** | Press R, pause, press again | Two lines. The suppression is per press, not a cooldown |

### The screen

| | Check | How | Expect |
|---|---|---|---|
| ☑ | **No more legs** | Look straight down | Your own model does not appear. It is removed, not fixed — see below |
| ☑ | **Black and white takes the UI with it** | Settings → Black and white → on, then open anything | Menus, inventory, HUD all grey. Brass and the danger red stay **tellable apart** — that is what the weighting is for |
| ☑ | **Settings clears the wordmark** | Menu → Settings | Nothing overlaps OMERTÀ or the tagline |
| ☒ | **The season number shows** | Look at the bottom of the menu | **Failed 2026-08-01** — read a bare "THE CITY". The running season predates numbering, so its label was a name and the number was read off the label alone. Fixed: a season with an unreadable label now takes its ordinal |

**The legs are gone rather than repaired.** `ShouldDrawLocalPlayer` draws the
whole model at its world position, head included, and the first-person camera
sits inside that head — which is exactly the "appears and you look through it"
you described. A real first-person body needs a separate rig with the head bone
scaled away and arms driven off the viewmodel. Your addon is the right call.

**Your console error is not ours.** Nothing in this repository mentions
ClearSans — we ship Germania One and IBM Plex Mono. The path in that message is
`cache\workshop\`, so it is another addon shipping a font it cannot load.
Harmless.

### Joining, and seasons

Everyone is met by the menu now, including a player who already has a
character. The rail has two ways in, never both at once: **Enter the city** for
a new arrival (which goes to creation) and **Return to the city** for somebody
who has somebody to be.

The join no longer loads your character at all until you ask it to — which
means the hold on your movement is the same gate a character-less player has
always had, and the release stays in the one place it has always been. That
ordering matters: M19 puts a reconnecting downed player back on the floor from
that hook, and releasing after it would stand them up out of their own body.

Seasons are numbered. `omerta_season_create` takes no arguments now.

| | Check | How | Expect |
|---|---|---|---|
| ☑ | **A returning player gets the menu** | Rejoin with a living character | Menu, with **RETURN TO THE CITY** at the top |
| ☑ | **And can get back in** | Press it | Fade, then you are standing in the world where you left off |
| ☑ | **You cannot move behind the menu** | Push forward while the menu is up | You do not move. **This is the one to break hardest** — a player who cannot move after pressing Return is worse than the bug this fixes |
| ☑ | **A new player still creates** | Fresh account | **ENTER THE CITY**, then the creation form |
| ☑ | **Dying still skips the intro** | Die, make a new character | No title card on the way back |
| ☑ | **Rejoining while down** | Go down, disconnect, rejoin, Return | You come back **on the floor**, not standing |
| ☑ | **A season is one command** | `omerta_season_create` | Creates the next number with no label typed. Nine existing named seasons should produce #10, not #1 |
| ☑ | **Numbers survive a gap** | Delete a middle season, create another | The next number, never a reused one |

**Three things could not be verified without a running server**, all in the
join path: that `PlayerSpawn` fires reliably for a player who now never loads a
character at join (the mechanism is unchanged, but the returning-player case
has never taken that path); the round-trip feel of Return, which has an
8-second ceiling on the hold that is a guess; and whether the season number
arrives before the menu first paints — with `omerta_intro 0` the margin is one
frame, and the line reads "THE CITY" until it lands.

Also unseen: whether IBM Plex Mono renders `·` at the drawn size.

---

## 1d. Motion, and the world outside (2026-07-31)

### Every window now arrives and leaves

One implementation, nine windows, three plates. A window rises 42px as it fades
in over 120ms and sinks as it fades out over 100ms. `:Close()` is routed
through it — including a DFrame's own corner close button — so a window gets
the play-out without its author having thought about it. `:Remove()` stays
instant, because tearing a window down to rebuild it is a real need that wants
a word of its own.

**A correction to what I told you.** I said the loot window was missing the
animation and that this was your bug. It was not — I traced it, and both the
loot and pockets paths already recorded where the window rests, so searching a
body always rose. What you were describing is almost certainly the **progress
plate** — the "SEARCHING" line with the bar that appears *while* you search.
That faded but never moved. It moves now.

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **The searching plate arrives** | Search a body | The bottom-centre plate rises in and sinks out, rather than blinking |
| ☐ | **So does the drawing plate** | Start a draw with the inventory shut | Same motion, same place — those two are meant to read as one object |
| ☐ | **And notices** | Trigger any refusal | Rises in, sinks out |
| ☐ | **Every window** | Open the phone, a treasury, a business, an org window, the loot plate | All of them rise and sink. None blinks |
| ☐ | **Closing plays out** | Close each of the above, including by its corner X | It sinks away rather than vanishing |
| ☐ | **The pause menu fades but does not move** | F1 | Fade only. It is the whole screen — moving it would show bare world along the top edge |
| ☐ | **Instruments never move** | Sprint, draw a gun, look at a body | Crosshair, stamina ticks, hotbar, ammo and the hint ladder stay exactly still. The hint ladder especially — it is anchored to the crosshair |
| ☐ | **Searching straight after closing your pockets** | Hold C, release, immediately search a body | The loot window appears. It used to show **nothing at all** — a loot push landing during the tenth of a second the window spends leaving rebuilt the leaving window, which then finished leaving |

### The inventory preview

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **Framed from the hip up** | Hold C | Waist to head, not head to foot. Wearing a coat and holding a gun should both be obvious |
| ☐ | **It still follows you** | Put a coat on, draw a gun | The preview updates within half a second, still idle-only, never mirroring your movement |

### The map and the weather

**Read this before testing.** I could not reach Steam from this machine — the
network policy blocks it — so **I do not know what either Workshop item is.**
The IDs are used exactly as you gave them and nothing is guessed from them.

`resource.AddWorkshop` only makes **clients** download these. **Your server must
carry both IDs in its own collection** (`host_workshop_collection`) or have them
mounted locally, or it will be running a map it does not have and calling into
an addon that was never loaded.

Weather and time are read through a seam. Providers are detected by whether the
functions they intend to call actually exist — never by name or version — and
if nothing matches, the game answers "clear day at noon" forever rather than
erroring.

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **Clients get the content** | Join a fresh client | Both items download |
| ☐ | **What did it detect** | `omerta_env` | Names the provider it chose, the time, whether it is night, the weather, and the map |
| ☐ | **It degrades** | `omerta_env` on a server without the weather addon | "clear day", no errors anywhere |
| ☐ | **The clock is right** | Compare `omerta_env`'s time against the sky | **The most likely thing to be silently wrong.** I assumed the addon reports minutes since midnight; if it reports hours, the time reads wrong while everything else works |
| ☐ | **Tell me the map's filename** | Read `[environment] map: …` off the boot log, or run `omerta_env` | Send me the name and I will author the front-end camera for it. Nothing guesses it today |

Nothing in the game reads the weather yet, deliberately — D-043 approved the
seam and nothing else. Six candidate consumers are listed at the end of this
document for you to rule on.

---

## 1e. The four-item follow-up (2026-07-31)

All four were real, and two of them were bugs I had already "fixed" twice by
changing a number that was never being used.

**1x is now the size you approved.** The setting was an absolute scale; it is
now a multiple of a base of **1.75**, so 1x is that size and it is the default.

One thing you could not have seen: `omerta_ui_scale 1.75` was being **clamped
to 1.5** by a ceiling in the code, so what was actually on your screen was 1.5,
not 1.75. 1x is therefore about 17% larger than what you have been looking at.
If it is too big, **0.9x** is almost exactly your old size and **0.8x** is what
you have right now. Your stored 1.75 is rewritten to 1 on first load, so
nothing has to be typed in the console.

**The right-click options were never getting the height they were told to.**
`DMenuOption` re-derives its own height from its font immediately after
construction, so `SetTall` on one is thrown away before anything draws. Stock
to 36 to 42 — none of the three was ever the number in use. They are plain
panels now, which keep the height they are given.

**The settings screen was seven buttons in a rail built for four.** They ran
past the end of the column and through each other. It is one cycler now — the
same control the character creator uses — and the whole screen is laid out by
measuring down the column rather than by asking a container to arrange things
nobody had added up.

**The chat box could not be typed into.** Hiding `CHudChat` hides the engine's
text entry with it, and a hidden panel cannot take the keyboard: the box opened
and swallowed every keystroke. The keyboard is ours now — an invisible entry in
a popup panel, with the line still drawn over the world in our own type.

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **Chat accepts letters** | Open chat, type, press enter | The line appears as you type and goes out on enter |
| ☐ | **Escape closes it** | Open chat, press escape | Box closes, nothing sent, the game menu does **not** open |
| ☐ | **No leading letter** | Open chat several times | The key that opened it never appears as the first character |
| ☐ | **C does not open the inventory mid-sentence** | Type "come here" | You get the sentence, not the inventory |
| ☐ | **F1 does not open the pause menu either** | Type something with F1… you cannot — just confirm chat holds the keyboard | The pause menu stays shut while chat is up |
| ☐ | **You cannot shoot while typing** | Hold a gun, open chat, click | Nothing fires |
| ☐ | **Right-click options are properly tall** | Right-click an item | Roughly double what they were. Easy to hit without aiming |
| ☐ | **Settings does not overlap** | Menu → Settings | Interface scale as a cycler (`< 1x >`), then two toggles and Back, each clear of the next |
| ☐ | **1x is the default and is set** | Fresh look at Settings | Reads **1x**, and the interface is the size you signed off (see the note above about it being ~17% larger) |
| ☐ | **The scale still applies** | Step down to 0.8x and back | Everything resizes, including the chat and the right-click menu |
| ☐ | **Windows fit the screen** | Open the inventory, search a body | At 1x the loot window is large; it must not run off any edge |

---

## 1f. The nine-item pass (2026-07-31)

Your notes after the city let you in. Everything here is new or changed since
that session, so it is all first-time verification.

### Drawing a weapon now takes time

The biggest change in this pass, and the one worth breaking first. A gun no
longer appears in a hand because a row changed — it is a timed, interruptible
draw, about **1.7s** for the revolver and **2.4s** for the Thompson. The length
comes from the weapon's bulk, so a third gun inherits a sensible number the day
its table exists.

Nothing is written until the timer runs out, which is what makes every
interruption free: there is no half-equipped state to unwind and no way for a
cancelled draw to leave a gun anywhere.

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **The draw has a length** | Equip a revolver, then a Thompson | The row fills with the same bar "loot all" uses. Thompson visibly slower |
| ☐ | **Closing the window keeps the clock** | Start a draw, release C immediately | The bottom-centre "DRAWING" plate picks up **mid-bar** — not from zero |
| ☐ | **Reopening keeps it too** | Start a draw with the window closed (hotbar), then hold C | The row is already part-full. Both directions are one clock, so neither should ever restart |
| ☐ | **Walking out of it cancels** | Start a draw, walk ~64u | It stops, you are told, nothing is equipped |
| ☐ | **Going down cancels** | `omerta_injury_state incapacitated` mid-draw | Stops on the same frame, no gun |
| ☐ | **Losing the item cancels** | Start a draw, have somebody take that row | "it is not yours to draw" |
| ☐ | **Leaning on it does not stack** | Spam equip | One draw running, not a queue that all lands at once |
| ☐ | **A coat is still instant** | Equip an overcoat | No bar, no delay — only weapons wait |

### What other people see

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **"Reaching for something…"** | Second player starts a draw, look at them | The line sits under their identity label, stacked by the same ladder as "E to search". It never says what for |
| ☐ | **It goes away** | Watch the draw finish, and watch one get cancelled | Line clears both ways |
| ☐ | **Primary across the back** | Equip a Thompson, switch to something else | Slung across the upper back, muzzle down past the left hip |
| ☐ | **Sidearm on the right hip** | Same with the revolver | Right hip, pointing at the ground |
| ☐ | **In the hands is not on the body** | Select the slung weapon | The prop leaves the back as it arrives in the hands. Up to a quarter second of lag is expected and fine |
| ☐ | **A corpse is not still armed** | Kill an armed player | Nothing left hanging on them |

**Every holster offset is eyeballed.** They were set by hanging a model on a
model and looking at it. If a gun clips through a shoulder or floats off a hip,
that is expected at this stage — tell me which weapon and which way it is
wrong, and it is six numbers in one table.

### The rest of the notes

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **Crosshair is half the size** | Look around | Was too big; the dot is now half the radius it was |
| ☐ | **This scale is 1x** | Menu → Settings → Interface scale | The size you approved is **1x**. Steps run 0.6 / 0.7 / 0.8 / 0.9 / **1** / 1.2 / 1.4 — weighted downward because it is already large |
| ☐ | **Right-click options are wider** | Right-click an item | Wider menu, taller rows, more inset. Say if it is still tight |
| ☐ | **Inventory slides and fades** | Hold C, release | Rises and fades in over ~0.12s, drops and fades out over ~0.10s. It should read as quick, not as an animation you wait through |
| ☐ | **Inventory is centred** | Hold C | Centred, not shifted right, with the player view to its left |
| ☐ | **The background blurs** | Hold C | Slight blur behind the window — enough to separate it, not enough to hide the street |
| ☐ | **Ammunition, bottom right** | Draw a gun and keep it out | Loaded count large, `/ reserve` small and dimmer beside it. **Stays while the gun is held** and fades with the draw rather than timing out |
| ☐ | **The reserve is real** | Fire, reload, drop rounds, pick rounds up | The number after the slash tracks what is actually in your pockets **for that caliber** — a .45 in the coat is not the revolver's reserve |
| ☐ | **Stamina lasts longer** | Sprint | Same twelve notches, about 13 seconds of sprint. Still not enough, or too much? |

### The chat box

The engine's chat is gone; this is ours. Messages stack upward from the bottom
left, hold for twelve seconds, and fade to nothing — the screen returns to
empty, as GDD §8 wants.

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **It opens and sends** | Y (or your bind), type, enter | Line goes out, appears in the list |
| ☐ | **The channel is named before you speak** | Type `/w hello`, then `/y hello`, don't send | The channel shown on the input line changes as you type, so you know who will hear it |
| ☐ | **`/me` is italic** | `/me coughs` | "Tiny Marino coughs" in italics — reads as description, never as speech |
| ☐ | **Long lines wrap** | Send a very long sentence | Wraps against the column, no text running off the edge |
| ☐ | **It goes away** | Send something, wait | Full for ~12s, fades over ~2s, gone. Opening chat brings the recent lines back to full while you are typing |
| ☐ | **Console still works** | Open chat, type a console command | The engine still owns the field's focus and passthrough — nothing about that was reimplemented |
| ☐ | **Scale follows the setting** | Change interface scale, open chat | The italic face rebuilds with the rest of the type |

---

## 2. The frozen spawn — two independent causes, both fixed (2026-07-31)

**Test this before anything else: can you get into the city at all.**

The report was "frozen at spawn, grey model, no intro, no menu, no errors."
Two separate bugs produced it, either of which alone is enough:

**1. Multi-core rendering ate the menu.** `mat_queue_mode` cannot be changed
quietly — the engine rebuilds the material system to apply it, and that takes
every live VGUI panel with it. It was being applied from a Think hook the
instant `LocalPlayer()` became valid, which is exactly when the front-end menu
builds itself. It is now **off by default and never applied automatically**.

**2. The state message raced the client.** The join flow starts at
`PlayerInitialSpawn` — fired while the client is still loading — and the
"you need a character" message went out ~6 ticks later from an async database
chain. A message sent to a client that is not listening yet is simply gone, and
that message is said **once** and is the only thing that raises the menu. There
was no client-ready handshake anywhere in the gamemode; there is now.

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **You can join at all** | Join with no character | Menu (or intro) appears, you can create somebody and spawn |
| ☐ | **The listen-server host works** | Host the server yourself and join | Not "the city is closed" — the join path used to read the season before its query had landed, and the host always wins that race |
| ☐ | **Rejoin with an existing character** | Rejoin | Straight into the city, able to move |
| ☐ | **Lua refresh does not strand you** | Save a gamemode file mid-session | The front end comes back rather than leaving you gated in silence |
| ☐ | **Multi-core is off and optional** | Settings | Toggle reads Off. Turn it on: expect a hitch as the material system rebuilds. If the menu survives that and frames improve, say so and it can default on |
| ☐ | **Settings is complete** | Menu → Settings | Interface scale, Black and white, Multi-core, **and Back** — the last two were being drawn outside a panel that was too short |
| ☐ | **Dead men do not walk** | Die, press a key on the death screen | You stay put on the way to the menu. Acknowledging death used to hand movement back to a player whose character had just been retired |
| ☐ | **The crosshair is always there** | Look at nothing, then at something | A faint dot at rest, full brightness on a target. Gone only when a window has the mouse, or while down/dead (D-041 amends D-017) |

If you are still frozen after this, the next suspect is the account load itself
— send me the server console from join and I will read it rather than guess.

## 3. The twenty-four-item field report (2026-07-31)

**Start here: `omerta_help`.** Every console command in the game, grouped by
area, with arguments and which ones need a *client* console. `omerta_help
giving` narrows it. A lint test fails the suite if anyone adds a command
without describing it, so the list cannot quietly go stale.

**Controls changed again:** **E** now does one thing per target, on press —
no hold, no wheel. **Dragging bodies is shelved** (E on a body = search); the
maths and the server machinery are untouched behind an unregistered seam, so
bringing it back is a re-registration, not a rebuild. **F1** is the pause menu.
**C** still holds the pockets open.

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **Germania One is back** | Look anywhere | The old face, everywhere except the small mono captions (IBM Plex Mono keeps those — Germania has no such register) |
| ☐ | **Everything is bigger** | Play at default scale | ~30% larger than the last build. If anything is *still* small, name it — the multiplier is one number in `sh_theme.lua` |
| ☐ | **Body tooltip no longer overlaps** | Look at a body, then at 1.5× scale | Name and hint stack with measured spacing at every scale (they were on fixed pixel offsets the type outgrew) |
| ☐ | **E is not finnicky** | Tap E once at a phone, a speakeasy counter, a dropped item, a body | Registers on the PRESS, first time — the old release path re-checked your aim and silently dropped it if you'd drifted a pixel |
| ☐ | **E on a body searches** | Tap E on a body | Straight into the search; no drag, no menu |
| ☐ | **No held-E menu anywhere** | Hold E on anything | Nothing appears. Stabilize / Treat / Finish now live as buttons in the loot window |
| ☐ | **You can see your feet** | Look down | Your own body is there, below a steep enough angle |
| ☐ | **Black and white** | Menu → Settings → Black and white | The whole game desaturates; off by default, and it persists |
| ☐ | **F1 pauses** | Press F1 in play, then again | The rail appears over your CURRENT view, blurred — not the orbit camera, not the spawn. "Resume" is the top entry. F1 closes it |
| ☐ | **Death → menu is smooth** | Die, press a key | No black flash: the intro is skipped on the death handover, so the death fade lifts straight onto the menu |
| ☐ | **The vignette is a vignette again** | `omerta_injury_state incapacitated` | Soft red gradients closing in from the edges — the nested rectangles are gone |
| ☐ | **Hotbar fades cleanly** | Let the hotbar time out; get put down while armed | No flicker or re-flash on the way out |
| ☐ | **Creation: nothing is cut off** | Enter the city, at 1× and 1.5× | Back (a third) and Confirm (the rest) share one row pinned to the bottom of the panel, always on screen |
| ☐ | **"Last name"** | Look at the form | Not "Family name" |
| ☐ | **The permadeath warning** | Press Confirm | A modal naming the character: they cannot be remade, and the name is never used again. Back returns to the form; Confirm commits |
| ☐ | **The fade into the city** | Confirm the modal | Screen fades to black, holds through the server round-trip, lifts as you spawn. (That held black is where the intro cinematic will go.) A rejected name cancels the fade instead of stranding you in it |

### The inventory and looting rebuild — same pass

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **Searching a body no longer flashes** | Search a body with items | The body's contents open and STAY. The wire tagged body-loot as a plain pockets refresh (a body has no container id), so the client showed your own inventory and closed it |
| ☐ | **Picking up doesn't flash either** | Walk over an item and take it | The refresh updates silently; no window appears |
| ☐ | **The character panel** | Hold C | The plate sits right of centre with your live player model (idle only — it must NOT run when you run) beside the ledger, plus STAMINA and APPETITE notch rows |
| ☐ | **The model follows your gear** | Equip an overcoat (when models exist), or change model | The preview reflects it |
| ☐ | **Right-click has no title** | Right-click an item | Straight to the verbs — no repeated item name — with room above and below each |
| ☐ | **Drag between loot columns** | Search a body, drag rows across | Items move both ways without right-clicking |
| ☐ | **Loot all** | Search a body, press LOOT ALL | Top to bottom, ~half a second each: the row greys, a progress bar sweeps its full width, the rustle plays, the item moves. Stops when empty or when something will not fit |
| ☐ | **Body actions are buttons now** | Search a downed character | Stabilize / Treat (and Finish on a body you can finish) as buttons at the foot of their column |

## 4. The style guide, implemented (2026-07-31)

Your handoff zip read clean, and direction **1a** is now the standard — the
IBM-Carbon detour (and its blue) is gone. `modules/hud/sh_theme.lua` holds the
guide's six hex, the 4px grid and the type ladder, all pinned by tests
(including "nothing in the palette may be blue"); the guide itself is
versioned at `docs/design/style-guide/`.

**Superseded in places by the passes above** — the guide's Oswald/Archivo pairing was tried
and rejected in the field, so Germania One carries every role again except the
mono captions; the creation screen's wording and buttons changed too. The
palette, the 4px grid and the plate/rule/selection grammar all still stand.

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **Hold C = pockets, absolutely** | Hold C, click rows, release mid-click | Open exactly while held, gone the instant it is not — polling the real key now, so no interaction can wedge it. No X button anywhere |
| ☐ | **The menu error is gone** | Sit on the main menu | No `attempt to index field 'Seasons'` spam; the season line reads "THE CITY" until the client knows better |
| ☐ | **Creation lives IN the menu** | Enter the city | The rail widens into §11: NEW ARRIVAL kicker, GIVEN/FAMILY NAME side by side over bare rules, prose life paths (chosen one brass-inverted), the portrait tile on the city side, "STEP INTO THE CITY" in bone, the permadeath sentence beside it. Esc or BACK returns |
| ☐ | **Inventory is the ledger (§09)** | Hold C | One ink plate: ITEM/QTY/BULK/STATE mono captions, the in-hands item as the full brass-inverted row, WORN/CARRIED in brass, the bulk tick meter, ON HAND and APPETITE bottom-right |
| ☐ | **Loot is one plate, two columns (§10)** | Search a body | Identical columns, one vertical rule, hover = brass wash + 1px brass edge on the travel side. C dismisses |
| ☐ | **Item menu (§10)** | Right-click a row | Mono header naming the item; verbs; hovered verb brass-inverted; **Drop alone at the bottom, under a rule, in the red** |
| — | ~~Verb menu (§06)~~ | — | **Removed.** Held-E is gone; E does the one obvious thing. Nothing to test |
| ☐ | **Hotbar (§07)** | Scroll / press 1–4 | Column of 52px slot squares, left-centre; only the held slot gets the brass border and the name caption under the column |
| ☐ | **Stamina is ticks (§07)** | Sprint | Twelve 9×3 ticks bottom-left; spent ones dim to 18% and STAY — no sliding bar |
| ☐ | **Ammunition block (§07)** | Draw, fire, reload | Bottom-right: big tabular count, `/ reserve` small beside it, "EMPTY · PRESS R" when dry. **Rewritten in §1** — it now stays while the gun is held rather than timing out after two seconds |
| ☐ | **Timed action (§08)** | Search a stranger | Bottom-centre 320px plate: "SEARCHING…" in Oswald caps, bare 2px progress line, no number; vanishes instantly on cancel |
| ☐ | **Notices** | Trigger two notices quickly | Top-left scrim plates stacking down, newest loud, older at 50% |
| ☐ | **Bleeding out (§14)** | `omerta_injury_state incapacitated` | Four nested ink rectangles closing in (no red gradient); the clock is a 2px red line at the bottom BREATHING at your pulse rate, shortening — no bar, no track |
| ☐ | **Death card (§15)** | Die | Hairline rules above and below, the title in light Oswald caps, "PRESS ANY KEY" breathing in the mono voice |
| ☐ | **World text outline** | Look at names/hints against sky and alley | Hard 1px black outline (not a soft shadow) — same weight everywhere |
| ☐ | **The dot ladder (§05)** | Look at a body | Dot, subject at a fixed +24, hint at +48 — the subject's baseline never moves |

**Known deviations from the guide, deliberate, say if you want them changed:**
the dot only appears when something is in reach (the guide keeps a dimmed
always-on dot; GDD §8's empty screen won that argument for now); the death
card still says "YOU HAVE DIED…" rather than the character's name + epitaph
(needs the name plumbed to the death screen — small follow-up); double-click
/ shift-click / drag-to-split in loot are not wired (right-click menu does
those jobs); treasury and payphone windows are still on stock Derma — they
are the next restyle targets now the kit exists.

## 5. The front end (intro + main menu) — from an earlier pass

The intro and menu are **placeholder sets for M27/M28**, built as systems so
those milestones fill in data. Three of their open rulings I had to assume an
answer to — all reversible, all flagged in `sh_menu.lua`:
**(a)** the 30.9 MB intro WAV is *not* sent to clients (`menu.send_music` off) so
nobody downloads it before it is compressed — you will hear it, since you have
the file; **(b)** the sequence is scene-driven, not music-driven, so it can be
skipped; **(c)** one camera mode (a slow orbit) plus the registration seam, since
the real shots are per-map authoring work that lands with the map (Q-9).

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **The intro plays** | Join with no character | Black → "OMERTÀ" and the line under it → words fade → the city fades up under a slow orbiting camera → menu. ~9.6 s |
| ☐ | **The intro is skippable — but not by accident** | Hammer a key from the loading screen; then press one once the words are up | Early presses do nothing; a press after the title is legible jumps straight to the menu |
| ☐ | **The menu works on the keyboard** | Arrows/W/S, Enter | Highlight moves and wraps, click sound per move, Enter chooses. The selected entry is the brass-inverted row |
| ☐ | **The menu works on the mouse** | Hover and click | Hover moves the highlight; click chooses |
| ☐ | **Enter the city** | Choose it | Menu goes, character creation appears, music fades out |
| ☐ | **Death lands on the menu, not the creator** | Die | Death screen → the black lifts to reveal the **menu**, with its camera already orbiting behind it (not a cut after the fade) |
| ☐ | **Settings** | Menu → Settings | Four scale buttons (0.75/1/1.25/1.5); picking one rebuilds the menu at that scale; Back or Escape returns |
| ☐ | **Leave** | Menu → Leave | Disconnects |
| ☐ | **Intro can be turned off** | `omerta_intro 0`, then rejoin | Straight to the menu, no intro. (Client convar — the player's call) |
| ☐ | **Music** | Join | "Cry Me a River" fades in under the intro and continues under the menu; fades out entering the city. Silent for a client without the file — that is expected until it is compressed |
| ☐ | **The typefaces are the guide's** | Look anywhere | Oswald caps for titles and verbs, Archivo for names and numbers, Plex Mono for the small caps annotations |
| ☐ | **Nothing is rounded any more** | Inventory, menu, loot windows | Square corners everywhere — a Carbon signature and the quickest way to spot a panel that has not been converted |
| ☐ | **Scale still holds** | `omerta_ui_scale 0.75` then `1.5`, walk around | Menu, inventory, hotbar and HUD all stay laid out; nothing overlaps or leaves the screen |

## 6. The UI and interaction pass (2026-07-30)

**Controls changed:** **C** now opens the inventory — **hold to view, release
to close**, which you confirmed is what you wanted. The old hold-C menu is now on
**E**: tap E for the obvious thing,
hold E for the full menu. Your report said tap-E on a body should default to
drag in one line and search in another — **I went with drag** (it was the
dedicated bullet, and search is one wheel-notch away in the held menu); say
the word and it flips.

| | Check | How | Expect |
|---|---|---|---|
| ☐ | **The new inventory table** | Press C | Our own rows — category icon, name, quantity, bulk — dark panels, zebra-free, no GMod list furniture anywhere |
| ☐ | **Icons make sense** | Carry a gun, rounds, an overcoat, food, cash | Gun/ammo/clothes/food/money line art per row; anything odd falls back to the junk icon. (No medical glyph existed in the set — bandages borrow the components icon for now) |
| ☐ | **Right-click works now** | Right-click any row | The menu opens (Equip/Unequip, Use, Split…, Store, Drop / Take). The old list widget was eating the click; the rows are ours now and own the mouse |
| ☐ | **Two loot windows** | Search a body or crate | Your **Pockets** window on the left, the container's own window on the right ("Body" / its label), each its own framed thing |
| ☐ | **Tap E = default action** | Tap E on a body / dropped item / crate | Body: **drag** (tap again to let go). Item: pick up. Crate: opens the loot windows. Tap-E on a *person* deliberately does nothing — introductions stay behind the held menu |
| ☐ | **Hold E = the menu** | Hold E ~0.3 s on a body | Menu appears already populated; wheel moves the selection (and does **not** switch weapons); release runs the highlighted option; looking away cancels, and the wheel goes straight back to the hotbar |
| ☐ | **Hover text no longer overlaps** | Look at a body | Name/"Unknown", then the hint, stacked with real spacing — one owner draws that region now, measured line by line |
| ☐ | **Search progress bar** | Search an unfamiliar body | Thin neutral bar under "Searching…" filling over the 4 s — stamina-bar styling, no red |
| ☐ | **Search rustle** | Search several bodies; cancel one mid-way | A different stretch of the rustle bed each time; goes silent the instant you walk away/cancel |
| ☐ | **"Search (empty)"** | Hold E over an emptied body or crate | The option itself reads "Search (empty)" (best effort — only when the server already has those pockets loaded) |
| ☐ | **Hotbar restyle** | Scroll or press 1–4 | Bigger type, no boxes, no borders; the held item is simply the vivid line, the rest faded |
| ☐ | **Hotbar click** | Scroll with 2+ items; then with only hands | Click sound on every actual switch; silence when there is nothing to switch to |
| ☐ | **Stamina bar is smooth** | Sprint, stop, watch | The bar glides instead of stepping four times a second |
| ☐ | **Blur starts stronger** | `omerta_injury_state incapacitated` | The world is already noticeably soft the moment you are down, worsening from there |
| ☐ | **Readability in bad light** | Stand somewhere bright/busy, check HUD text | Everything world-drawn now carries a soft drop shadow. If it still fights you anywhere, name the spot |

### From the first pass, still unconfirmed

| | Check | How | Expect |
|---|---|---|---|
| ☐ | Reloading finds your ammo | Carry `ammo.38`, press R | Clip fills, rounds leave inventory |
| ☐ | Weapons can be put away | Draw, then scroll/press 1 | Hands out, gun stays equipped |
| ☐ | Dropping an equipped weapon empties hands | Right-click → Drop while drawn | SWEP leaves with the item, clip refunded |
| ☐ | Equip/Unequip toggles, worn coat visible | Equip things, read the rows | "equipped — Slot" tag on the row, menu offers Unequip |
| ☐ | Splitting stacks | Right-click a stack → Split… | Asks how many, two stacks after |
| ☐ | Dragging moves the body and holds | Take hold, haul a street | Real pace, rope settles, grip survives |
| ☐ | One drag line, at the crosshair | Take hold | Single line, no second line at your feet |
| ☐ | Stamina lasts (~8 s sprint) | Sprint from full | Was ~5.5 s |
| ☐ | Creation form keyboard flow | New character | First box focused, Tab cycles the name fields |

## 7. W0 — the weapon foundation

| | Check | How | Expect |
|---|---|---|---|
| ☐ | The arsenal exists | `omerta_weapons_list` | revolver and thompson, classes `weapon_omerta_*` |
| ☑ | Getting armed | `omerta_item_give weapon.revolver`, equip it | The revolver appears in your hands, **empty** |
| ☒ | Rounds are items | press R with ammo carried | **Failed 2026-07-29** (OwnerOf pair misread) — fixed 2026-07-30, re-test alongside the reserve readout in §1 |
| ☐ | Firing works and is server-real | Shoot a second character | Damage lands through M19 — enough hits puts them down |
| ☐ | The round counter | Draw, fire, holster | Bottom-right while the gun is out, gone with it. Superseded by the §1 rewrite — test it there |
| ☐ | Dry fire | Empty the clip, keep pressing | Click, "Empty — press R", nothing fires |
| ☐ | Out of ammo | Reload with none carried | "You are out of .38 rounds." |
| ☐ | **The Thompson cannot be pocketed** | `omerta_item_give weapon.thompson`, empty pockets | Refused (bulk 22 vs 20); fits with an overcoat on |
| ☐ | Going down disarms | Get put down while armed | Weapon leaves the hands; searching finds it in the inventory |
| ☐ | Standing up re-arms | Get treated | The equipped gun returns, still empty |
| ☐ | Rounds are conserved | Load 6, unequip | 6 rounds back in the inventory |
| ☐ | Disconnect refund | Load a clip, disconnect, rejoin | Rounds in inventory, clip empty |
| ☐ | Procurement | `omerta_procure` as a family with funds | Revolver $85, Thompson $340 (second approver), ammo boxes |

## 8. M20 — confirmed death and succession (nothing verified yet)

| | Check | How | Expect |
|---|---|---|---|
| ☐ | Self-test | `omerta_death_selftest` | 9 steps, 0 failed |
| ☐ | The act exists and is slow | Put a second character down, **hold E** on the body | **Finish** is last in the menu, takes 7 s |
| ☐ | It is interruptible | Start finishing, walk away | It stops; the target is unharmed |
| ☐ | §4a — a bandage is not immunity | Stabilize someone, then Finish them | Still offered, still works |
| ☐ | The event is recorded | `omerta_events` after a kill | One `death.confirmed` row with subject and actor |
| ☐ | Attempts are logged | Start and cancel a Finish; check the audit log | A `death.attempt_failed` entry |
| ☐ | §4c — belongings stay | Search the corpse after killing | Their things are still on them |
| ☐ | **§4b — the chair empties** | Seat a Don, Capo online, kill the Don, `omerta_org_list` | Chair empty; Capo holds authority; Capo cannot appoint |

---

## 9. M19 — earlier fixes, still unverified

| | Check | How | Expect |
|---|---|---|---|
| ☐ | Jump gives no free stamina | Sprint to near-empty, jump repeatedly | No recovery mid-air |
| ☐ | Corpse is draggable | Kill yourself, respawn, walk back | Dot lights, tooltip, tap E takes hold |
| ☐ | Death camera fades behind black | `omerta_injury_state incapacitated` then `dead` | Head-hold → fade → top-down slow climb → fade → text |
| ☐ | Confirm sound on keypress | Any key on the death screen | Tap plays, words fade, music fades, creation revealed |
| ☐ | Drag by the part you grabbed | Aim at a hand, take hold | That limb leads |
| ☐ | Chat hides on death only | Bleed out, then die | Visible dying, gone once dead |
| ☐ | World audio mutes on death | Die near noise | Only trombone and piano |
| ☐ | Body tooltip | Look at a body | Name if known, "Unknown" if not |
| ☐ | Stabilizing with a bandage | `omerta_item_give medical.bandage`, Stabilize via held-E menu | Bleeding stops (same empty-pocket bug as reload — fixed, never run in-engine) |
| ☐ | Search memory | Search the same body twice | 4 s first time, instant the second |
| ☐ | Clinic treatment | Treat at a `clinic` counter | They reach Recovering and stand |
| ☐ | Recovery penalty | Get treated, move | Slower for ~8 min, easing off |

---

## 10. Older, still unconfirmed

| | Check | How |
|---|---|---|
| ☐ | M13 self-test | `omerta_business_selftest` |
| ☐ | M8 HUD self-test | `omerta_hud_selftest` in a client console — several elements added since |

---

## 11. Known gaps — not bugs, just not built

- **Audio is ~46 MB uncompressed** (four originals + the new rustle). MP3 conversion is a local ffmpeg step; no encoder in my environment.
- **Sound licensing** — the Freesound files and "Cry Me a River" are a pre-release gate. The two new UI sounds and icons came from you; tell me if they carry terms. Germania One is OFL, licence ships next to the TTF.
- **Corpses accumulate.** M20's stated boundary.
- **`omerta_ui_scale` at 1.5** unchecked against the new font, hotbar, and inventory windows.

---

## Waiting on a ruling from you

These are not tests — they are decisions that block work. Nothing here has been
built, and none of it will be until you rule.

*(M14's five rulings and two scope decisions were decided on 2026-08-02 —
D-046 through D-052 — and the milestone is built. It has moved to the queue
below.)*

### M21 — newspaper

Three rulings outstanding from an earlier pass. `docs/design-reviews/M21_newspaper.md`.

### What weather and darkness should actually DO

The seam reads the world; nothing consumes it, and nothing will without a
ruling. In rough order of how safe each one looks:

| | Candidate | Why it is a decision, not an implementation detail |
|---|---|---|
| ☐ | **NPC population by hour** (M16) | Tech §15 already names time of day as a population input. The least speculative of these |
| ☐ | **Newspaper flavour** (M21) | Presentation only. The cheapest to approve |
| ☐ | **Business footfall by hour** (M13) | D-032 ties income to real customers, so this changes what a shop earns |
| ☐ | **Crime and darkness** (M14) | Whether night affects heat, alarms, or how loud a forced entry is |
| ☐ | **Witness recall in bad weather** (M15) | Whether rain or darkness reduces what a witness can testify to — and whether it hits accuracy or recall |
| ☐ | **Recognition at night** (D-014) | **Handle with care.** This touches the core knowledge rule. Concealment already has a seam; darkness would be a second, weaker one, and two ways to become unrecognisable is a design question rather than a feature |

---

## How to report

Anything at all is useful — "1 and 2 pass, drag by the hand doesn't" is enough. Console output for failures if it is convenient. I will update the statuses here and fix what failed before starting anything new.
