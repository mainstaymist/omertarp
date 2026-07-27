# Omertà RP — Metagaming Rules

Status: baseline policy, shipped with M6. Expand as systems land.

Omertà RP is built on one rule:

> **A player should never act on information their character could not reasonably know.**

Most of that is enforced by code — there is no scoreboard, no kill feed, no global chat, no player list, and names are learned through introductions rather than displayed. But some information leaks at a level the gamemode cannot reach, and a few things no software can police. This document covers the gap.

## 1. What the game deliberately does not tell you

Your character knows only what they have seen, been told, read, or been shown. In particular:

- **Names** are learned by introduction. Someone you have not met is *Unknown*, and that is not a bug.
- **Faction membership** is never displayed. A person's family or badge is something you infer, discover, or are told.
- **Who is online**, how many police are on duty, whether a particular person is connected — the game does not answer these questions, and you may not act on answers obtained elsewhere.
- **Deaths, arrests and crimes** reach you through the newspaper, witnesses, rumor and police work, not through notifications.

## 2. What still leaks, and what you must do about it

Source cannot hide certain things, and pretending otherwise would be dishonest. The following remain technically visible:

| Leak | How it is visible |
|---|---|
| Steam names and IDs of connected players | The `status` console command; the Steam overlay's Players tab |
| Player count | The same, plus the server browser |
| Player list from outside the server | Server-query sites and the browser |
| A person's real voice | Voice chat |

**These are out-of-character information. Acting on them is a bannable offence.** Specifically, the following are prohibited:

- Using `status`, the Steam overlay, or a server-query site to determine who is playing, and acting on it in character.
- Recognising a player by their Steam identity and treating their *character* as known — you have met the character or you have not.
- Recognising a player by their **voice** and using it as identification when your character has no in-world reason to know them. Hearing a familiar voice is a legitimate roleplay *prompt*; treating it as proof of identity is not.
- Timing crimes around who you know is connected, or concluding a raid is safe because you saw few players in the browser.

The design's protection is that Steam identity and character identity are never linked by anything the game networks. A list of connected Steam accounts tells you who is *playing*; it can never tell you which one is the man in the trench coat. Do not do that work manually.

## 3. Outside channels

Discord, voice servers, streams and direct messages are the largest metagaming risk in any roleplay server, and the only defence is the rule itself.

- **Do not relay live in-game information out of character.** Not locations, not who is where, not what just happened to you, not who killed you.
- **Do not receive it either.** If someone tells you out of character, your character still does not know.
- **Streaming**: viewers must not relay information to you, and stream sniping is treated as metagaming by both parties.
- **Death does not license disclosure.** When your character dies, everything they knew dies with them. Telling your family who killed you — out of character, from a new character, or over Discord — defeats the entire consequence system.

## 4. Character death and new characters

A new character is a new person:

- They do not know anyone the previous character knew.
- They do not know where safehouses, stashes or businesses are.
- They do not hold grudges from a previous character's death.
- They do not inherit rank; the family may promote them, but that is the family's in-world decision (GDD §19.3).

Playing a new character with a dead one's knowledge is the most damaging form of metagaming in this design, because it silently removes the consequence that makes violence meaningful.

## 5. Enforcement

Every identity disclosure, promotion, transaction and confirmed death is recorded in an audit log with timestamps and the accounts involved. Staff can determine who learned what, when, and from what source — including with `omerta_identity_who_knows`, which lists every character who knows a given person and how they came to know it.

That makes "my character knew that already" a checkable claim rather than an argument. When the log contradicts a player's account of how they knew something, the log is what counts.

Sanctions escalate: a warning and a correction for a first genuine mistake, character-level consequences for repeated use, and account sanctions for deliberate or coordinated abuse — particularly organised outside-channel relaying, which harms every other player's game at once.
