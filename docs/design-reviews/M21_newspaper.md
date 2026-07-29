# Design Review — M21: The Newspaper

Status: **AWAITING APPROVAL**
Milestone: M21 (roadmap Track D). Depends on: M20 (the event log — this milestone is its first reader), M4 (portraits, per D-011), M13 (where papers are picked up), M5 (who is publicly identifiable). Consumed by: M22 (the archive is published issues plus closed cases).

> **Three rulings needed** (§4): what a newspaper is allowed to know, how often it comes out (Q-6), and when a face appears next to a story.
>
> **Spike S2 is closed as superseded** — see §2. It was going to prototype a portrait approach that D-011 rejected two weeks ago and M4 has already implemented the alternative of.

## 1. Purpose

The information design has a hole in the middle of it. Everything a character knows, they know because they saw it, were told it, or found it — which is exactly right, and which means that **nothing that happens outside your own line of sight has ever reached you**. A Don was murdered in an alley on the other side of the city last night and there is currently no mechanism by which you could ever find out.

The newspaper is that mechanism, and it is the only one the design permits: a thing you physically pick up, that tells you what a reporter could plausibly have learned, some of which is wrong. GDD §13 makes information the core economy; the paper is what gives that economy a public price list.

It is also the payoff for M20. The event log has been accumulating deaths with nobody reading it.

## 2. Responsibilities

**In scope:** the issue as a durable, frozen record; template-driven article generation from M20's event log (Tech §20 — templates, never free generation); the sourcing rule that decides what an article may contain (§4a); publication cadence (§4b, Q-6); portraits and the file-photo rule (§4c); the physical paper as a world object picked up at M13's declared spawns; the reading interface.

**Out of scope:** the archive and its search (M22 — M21 makes issues, M22 makes them findable); witness-derived accuracy (M15 — §4a ships the seam and a conservative default); police blotter detail from real cases (M17); staff-written articles (M24 could add them; nothing here prevents it).

### Spike S2 is closed, and M21 is not waiting for it

S2 was scheduled to prototype **Option E** — composite portraits rendered client-side from appearance descriptors. **D-011 selected Option C instead**: a real image captured in a photo booth at character creation, uploaded once, stored server-side. M4 shipped that, including the byte cap and the upload audit.

So the question S2 existed to answer was decided and implemented before the spike ran, and the roadmap and Tech §20 have both been carrying the superseded recommendation since. Both are corrected; S2 is marked closed. M21 consumes `characters.portrait` and there is nothing pending.

## 3. Public API

```lua
-- Templates: content in code, reviewed like code (Tech §20)
Omerta.News.RegisterTemplate("death.confirmed", {
    headline = "MAN FOUND DEAD ON %s",         -- filled from public facts only
    body     = "...",
    quote    = "police.routine",                -- an official saying nothing
    portrait = "subject",                       -- subject | none
    weight   = 90,                              -- front page if it is the biggest
})

-- Publishing (server)
Omerta.News.Publish(cb)                  -- compose the next issue and freeze it
Omerta.News.LatestIssue()
Omerta.News.IssueFor(eventId)

-- What an article is permitted to say (§4a) — pure, and the seam M15 tightens
Omerta.News.PublicFacts(event)           -- the redacted view of an event
Omerta.News.RegisterSourcing(id, fn)     -- M15 registers witness-derived detail

-- Reading (client)
Omerta.News.Open(issueId)
```

## 4. The Rulings

### 4a. What is a newspaper allowed to know?

This is the milestone. Everything else is layout.

- **(a) Public facts only, per template.** Each event type declares which of its fields a reporter could plausibly have obtained — a body in the street gives you a place, a time and a victim if identified, and *never* the killer. Anything not declared public is not printed, whatever is in the row.
- **(b) Everything in the event.** The log knows who did it, so the paper prints it.
- **(c) Witness-derived only.** Nothing is printed unless somebody actually saw it and their account survives M15's confidence and decay.

**Recommendation: (a), with (c) as the seam.**

(b) is the end of the game. The event row contains `actor_character_id` because M17 will need it to build a case; if the paper prints it, then every killing publicly names its killer for free, and eleven milestones of identity work evaporate on the first press run. **This is the single most dangerous line in the milestone** and it is one field in one template away from happening by accident, which is why (a) makes redaction the default rather than a discipline.

(c) is where this should end up and cannot be where it starts: M15 does not exist, so "witness-derived only" today means the paper prints nothing at all. (a) is (c) with a conservative stand-in — the template asserts what a reporter could have found out, and `RegisterSourcing` lets M15 replace that assertion with the real thing without M21 changing.

The rule I would write into the code: **an article may contain only what somebody standing in the street the next morning could have established.** A body, a place, a time, a name if the face was known. Not who, not why.

### 4b. How often does it come out? (Q-6)

- **(a) Fixed real-time interval**, config-driven, defaulting to every 6 hours.
- **(b) Event-driven** — an issue whenever enough has happened.
- **(c) Fixed, but with a front page that can be pre-empted** by something big.

**Recommendation: (a).** Q-6's own recommendation, and the reason is rhythm: a paper that arrives on a schedule is something players learn to wait for, plan around, and be somewhere for. An event-driven paper arrives when the city is busy, which is exactly when nobody has time to read it, and never during the quiet hours when it would matter most.

Six hours is a starting number, not a considered one, and it is the thing I would most expect to retune after a week. A slow issue is also a *cheaper* issue — a quiet day prints a short paper rather than no paper, which keeps the object in players' hands.

(c) is tempting and I would leave it for later: pre-emption needs a notion of "big" that M15 and M17 are better placed to supply than a weight column typed in by hand.

### 4c. When does a face appear?

D-011 gives us real captured mugshots. Tech §20 asks for the **file-photo rule**: a portrait appears only when the paper could plausibly have one.

- **(a) Only for the publicly identifiable** — police (D-021 makes rank public), business owners, and anybody the paper has already named in a previous issue. Everybody else gets the silhouette.
- **(b) Whenever the subject is named.**
- **(c) Never** — silhouettes throughout.

**Recommendation: (a).**

(b) is the same failure as §4b(b), one step removed. A paper that prints a face whenever it prints a name turns the newspaper into a directory: read enough issues and you have seen everybody, and introductions stop meaning anything. A criminal who has kept his head down has *no* file photo, and that absence is a fact worth having.

(c) is safe and dull, and throws away the thing D-011 decided to build.

Under (a) the portrait becomes a status marker: the first time your face runs, you are somebody the city knows. That is a consequence worth earning and worth avoiding, which is the correct shape for anything in this game.

## 5. Networking

| Message | Direction | Payload |
|---|---|---|
| `news.request` | client → server | issue (uint 16) — 0 for the latest |
| `news.issue` | server → client | issue metadata |
| `news.article` | server → client | one article, streamed |
| `news.portrait` | server → client | base64 chunk, on demand |

**Portraits are fetched only when an article carrying one is actually on screen**, never bundled with the issue. At 3–8 KB each (D-011's corrected estimate) a full issue would otherwise push a hundred kilobytes at every reader for faces most of them will not look at.

A client receives only issues that have been published. There is no "upcoming" state to leak.

## 6. Persistence

Migration **14**, two tables.

```
news_issues    id, season_id, number, published_at, frozen
news_articles  id, issue_id, event_id, template, headline, body,
               subject_character_id, portrait, weight, position
```

**An issue is frozen on publish** (Tech §20) and articles store *rendered text*, not a recipe. That is deliberate duplication: if articles re-rendered from their event on read, editing a template would silently rewrite history, and a newspaper you cannot trust to say the same thing tomorrow is not a record. M22 archives these rows as-is.

## 7. Security Considerations

- **Redaction happens at composition, on the server**, not at render. The client never receives a field the article does not print, so an inspecting client learns nothing a reader would not.
- `PublicFacts` is pure and headlessly tested against every registered template, and the suite asserts that **no template can emit an actor identity**. That is a test rather than a rule because it is the failure that would be least visible and most damaging.
- Portraits are served from the subject's stored image with the file-photo rule applied server-side; requesting an article's portrait when the article has none returns nothing.
- Issues are immutable after publication. There is no edit path, by design.

## 8. Dependencies

M20 (`Omerta.Events.Since` — the cursor built for exactly this), M4 (portraits), M13 (`newspaperSpawn`, declared in the venue registry since M13 and unused since), M5 (public identifiability), M9 (a paper is an item — `misc.newspaper` already exists and the funeral home already sells it).

## 9. Future Extension Points

- `RegisterTemplate` is how M14, M17, M18 and M20's funerals each add their own story without touching this module.
- `RegisterSourcing` is M15's: replacing the template's assertion of what was knowable with what was actually witnessed.
- Issue rows are M22's archive.
- A staff-written article is a template with a manual trigger; M24 needs nothing new.

## 10. Architecture Rationale and Alternatives Rejected

**Rejected — generating prose freely.** Tech §20 asks for templates and is right: generated text cannot be reviewed for what it accidentally reveals, and this is the one system where an accidental reveal is unrecoverable.

**Rejected — articles that re-render on read.** §6.

**Rejected — a notification that a new issue exists.** You find out there is a paper by seeing a paper. Anything else is a feed.

**Rejected — printing the killer.** §4a, and it deserves restating: the field is in the row, one template away.

## 11. Testing Strategy

**Headless:** `PublicFacts` against every registered template, including the assertion that no template can emit an actor identity; issue composition given a synthetic event log (ordering, weighting, front page); the cadence clock, including resuming after a restart; the file-photo rule across public/private/unnamed subjects; template rendering with missing fields.

**In-engine (`omerta_news_selftest`):** publish an issue from real events and read it; verify a killing prints the victim and place and *not* the killer; verify an issue is byte-identical after a restart; verify a portrait appears for a police officer and a silhouette for an unknown; verify a paper can be picked up at a speakeasy.

**The headline check:** *stage a murder in an alley with no witnesses, publish, and read the paper — it should tell you a man is dead and where, and give you no way to learn who did it.*

## 12. Integration With Existing Systems

`modules/news/`, `depends = { "events", "characters", "identity", "inventory", "business" }`.

Changes to shipped code: **one.** M13's `newspaperSpawn` flag becomes load-bearing — it has been declared on the speakeasy and restaurant since M13 and read by nothing. M21 reads it.

---

**Awaiting rulings on §4a, §4b and §4c before implementation begins.**
