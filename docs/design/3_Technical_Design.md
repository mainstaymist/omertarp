# Omertà RP — Technical Design Notes
Version: 0.2.0
Status: Implementation blueprint
Last updated: 2026-07-26

> **Changelog**
> - **0.2.0** — Retitled to Omertà RP (D-001). §1 gains setting/asset/currency principles (D-002, D-004, D-005). §7 rewritten from personal cell phones to a payphone/private-line telephony model; PhoneService renamed TelephonyService (D-003). §2 Character field updated accordingly. §13 evidence types and §24 Phase 2 updated. §20 portrait approach points at the delivered evaluation (P-001). See `DECISIONS.md`.
> - **0.1.0** — Initial implementation blueprint (as "Mafia RP").

## 1. Architecture Principles

- Build from scratch; do not depend on DarkRP or another roleplay framework.
- Use server-authoritative state for identity, inventory, faction, evidence, death, money, communication permissions, and progression.
- Treat every client-supplied identity, item, interaction, or faction claim as untrusted.
- Keep systems modular so MVP features can ship without advanced subsystems.
- Design for compact maps and controlled entity counts.
- Persist only necessary seasonal and account data.
- Setting is a timeless early-to-mid 20th-century organized-crime atmosphere (D-002); prefer omitting or simplifying modern technology over simulating it.
- Currency is USD at historical purchasing power (D-004); coins are physical inventory items at minimum.
- Assets: existing GMod/Source props first, placeholders second, custom art only after gameplay is finalized (D-005).

Suggested module boundaries:

- CharacterService
- IdentityService
- SeasonService
- FactionService
- FamilyService
- PoliceService
- InventoryService
- EconomyService
- CommunicationService
- TelephonyService
- BusinessService
- CrimeService
- WitnessService
- EvidenceService
- CaseService
- InjuryService
- DeathService
- NewspaperService
- ArchiveService
- NPCResponseService
- UIService
- AuditService

## 2. Data Model

### Account

- SteamID64
- Cosmetic unlocks
- Career statistics
- Titles
- Seasonal history
- Moderation flags

### Character

- CharacterID
- AccountID
- FirstName
- LastName
- Status: active, retired, dead
- SeasonID
- Appearance descriptors
- Voice descriptor seed if implemented
- Current outfit
- Known identities
- Known telephone numbers (contact knowledge; no personal devices — see §7)
- Faction affiliation
- Rank
- Respect/fear values
- Injury state
- Public-record references

### Season

- SeasonID
- StartAt
- EndAt
- State
- RulesetVersion
- Winner summaries
- Archived event references

### Family

- FamilyID
- Stable name
- Season leadership
- Roster
- Rank assignments
- Treasury
- Supplies
- Businesses
- Influence
- Respect/fear
- Intelligence records
- Recruitment policy
- Acting leadership rules

### Police Department

- Season roster
- Rank assignments
- Department funding
- Capability unlocks
- Public trust
- Evidence storage
- Case registry
- Corruption flags
- Acting command

### IdentityKnowledge

Composite key:

- ObserverCharacterID
- SubjectCharacterID

Fields:

- LearnedName
- ClaimedName
- LearnedAt
- Source: introduction, document, police record, rumor
- Confidence
- Notes/aliases

Never replicate the full identity map to clients. Send only the resolved display identity needed for nearby subjects.

## 3. Character Name Validation

- Normalize whitespace and capitalization.
- Reject control characters and markup.
- Maintain a season-wide normalized full-name unique index.
- Optional reserved-name and prohibited-language filters.
- Family names do not constrain character surnames.

## 4. Hidden Population and Scoreboard

- Override or suppress default scoreboard.
- Do not network full player roster to custom UI.
- Disable join/leave chat announcements.
- Remove kill feed and death notices.
- Avoid exposing faction counts through team APIs or client-readable replicated state.
- Audit console commands and hooks that may leak player names.
- Administration tools may expose identities only to authorized staff outside normal roleplay UI.

Source-engine limitations must be reviewed carefully: some network or Steam overlay information may remain technically discoverable by determined users. The design should prevent ordinary in-game leakage and treat external metagaming as a rule violation.

## 5. Introduction Interaction

Flow:

1. Player targets another character at close range.
2. Opens context interaction.
3. Selects Introduce Yourself.
4. Target receives accept/decline prompt or introduction may be one-way depending on final rule.
5. Server writes IdentityKnowledge.
6. Both clients receive only the display update relevant to them.

Questions to finalize:

- Mutual versus one-way introductions
- Whether false names are allowed
- Whether police ID checks reveal legal names
- Whether masks block introduction
- Whether memory persists after major appearance changes

Recommended MVP:

- Mutual introduction
- Legal or selected character name only
- Knowledge persists for the life of both characters
- Faction is never included

## 6. Contextual Display Names

Client display function:

ResolveDisplayName(observer, subject):
- If same character: own name
- If observer has valid IdentityKnowledge: learned name
- Else: Unknown

Use for:

- Local text speaker label
- Interaction panel
- World-space contextual prompt
- Telephone caller resolution (known numbers/voices)
- Police documents only when identity is legally known

Do not use for:

- Global overhead nameplates
- Permanent labels
- Scoreboard

## 7. Communication

### Local voice

- Use distance-based voice.
- Preserve line-of-sight or muffling as optional later work.
- No global voice channels.
- Police radio and family radio require physical equipment and authorization.

### Local text

- Server validates range and status.
- Deliver to clients within audible radius.
- Each recipient resolves speaker name independently.
- Log moderation copy server-side with account/character identifiers.

### Telephony (payphones and private lines — D-003)

There are no personal phone devices. Telephone lines are fixed world infrastructure managed by TelephonyService.

Line record fields:

- LineID
- PhoneNumber
- Kind: payphone or private
- Location binding (map placement for payphones; owned property/business for private lines)
- OwnerOrganizationID or OwnerCharacterID (private lines; payphones are city infrastructure)
- InstalledAt / service status
- Tap or trace flags (content interception deferred)
- Evidence references

Payphone behavior:

- Fixed world entity; physical interaction begins a call session.
- Coin feed is server-validated: connecting consumes quarters from the caller's inventory, and the server continues deducting on a fixed interval. A low-change warning precedes disconnection; the call drops when the caller cannot pay.
- Pricing is configuration data tuned to historical purchasing power (D-004).
- Incoming calls ring the payphone entity audibly; any player at the phone may answer.
- Optional later: an internal coin box that accumulates inserted quarters and can be burgled.

Private line behavior:

- Purchased through family procurement or business accounts; bound to a location the buyer owns or controls (headquarters, business, apartment, safehouse).
- No per-call coin cost; optional recurring service fee as a money sink.
- Physical handset entity at the location; it can be unplugged, destroyed, or seized.
- The subscriber location of a private line is discoverable through lawful police process, making the line itself intelligence.

Calls:

- Server mediates call state.
- Remote audio routed only between participants.
- Local speaker's voice continues spatially; bystanders hear the local side of the call.
- Speakerphone-like re-emission of the remote side is optional later work (see §25 voice-routing risk).
- Text-call fallback presents a call-like text session so players without microphones can place and receive calls (accessibility requirement).
- Call metadata (line-to-line, start, duration) is recorded separately from content.

Number knowledge:

- Numbers must be shared or discovered; they are data learned per character or written on physical note items.
- Unknown callers present as a number only.
- There is no text messaging between phones; asynchronous messages travel as physical notes or by messenger.

MVP tracing:

- Police may obtain call-detail records for a line after warrant. Because lines are location-bound, call records reveal which places communicated — not which characters — preserving the information design.
- Content interception (taps) deferred unless explicitly authorized and technically reliable.

## 8. HUD and UI

Implement a UI-state controller that displays panels only in response to conditions.

Persistent screen should be empty by default.

Elements:

- Stamina: fade in below threshold or during drain
- Injury: appear for serious state
- Interaction prompt: target and range constrained
- Inventory: explicit key
- Item selector: explicit key/hold
- Telephone: physical use of a phone entity
- Newspaper/library: physical interaction

Avoid world-space nameplates.

Accessibility:

- Scalable text
- Caption/local text support
- Clear sound-independent cues for ringing, injury, and interaction
- No mechanic requires a microphone

## 9. Inventory

Recommended MVP model:

- Slot/grid or capacity-based inventory
- Item definitions in data tables
- Server-authoritative ownership
- Transaction IDs for moves
- Container support
- Equipment slots
- Concealment category
- Weight/size
- Organization ownership tag
- Serial/evidence metadata
- Currency denominations (coins and bills) as stackable physical items (D-004)

Operations:

- Add
- Remove
- Move
- Equip
- Unequip
- Drop
- Search
- Seize
- Transfer
- Store
- Destroy

All operations validate distance, permissions, capacity, and current state.

## 10. Family Treasury and Procurement

Treasury transactions require:

- CharacterID
- FamilyID
- Amount
- Reason
- Timestamp
- Approver
- Resulting balance

Procurement catalog categories:

- Communications (private telephone lines, radios)
- Weapons
- Ammunition
- Medical
- Vehicles
- Disguises
- Burglary
- Storage
- Business stock
- Intelligence equipment
- Legal/bribe services

Rank permissions must be configurable.

Avoid directly modifying health, damage, speed, or armor through family wealth.

## 11. Businesses

Business entity:

- BusinessID
- Type
- Owner
- Manager roster
- Inventory
- Income/expense ledger
- Public name
- Services
- Illegal functions
- Evidence exposure
- Security
- Rumor/intelligence value

Speakeasy MVP:

- Food/drink purchase
- Seating/social space
- Local text/voice
- Simple gambling optional
- Owner access
- Storage
- Rumor NPC
- Surveillance points
- Newspaper spawn point

## 12. Witness System

Witness record:

- WitnessEntityID
- EventID
- Observation timestamp
- Viewing distance
- Lighting
- Line of sight
- Stress
- Subject descriptors observed
- Vehicle/weapon descriptors
- Confidence
- Whether alarm was triggered
- Memory decay

Witnesses should not store CharacterID as reportable identity unless they already knew that person through a valid world relationship.

Descriptor generation uses visible appearance at event time.

Masks reduce face details. Gloves affect fingerprints, not visual descriptions.

## 13. Evidence

Evidence base fields:

- EvidenceID
- Type
- SourceEventID
- CreatedAt
- World location
- Integrity
- CollectedBy
- ChainOfCustody
- Suspect links
- Case links
- Public/private status

Initial types:

- Fingerprint
- Shell casing
- Weapon
- Camera image
- Witness statement
- Vehicle observation
- Ledger
- Seized telephone handset or line record
- Written note
- Call record
- Marked currency

Evidence should support contamination, destruction, planting, theft, and improper collection where feasible, but MVP may begin with integrity and chain-of-custody flags.

## 14. Cases and Warrants

Case:

- CaseID
- Title
- Lead officer
- Contributors
- Suspects
- Victims
- Evidence links
- Strength score by allegation
- Status
- Warrant requests
- Outcome

Warrant request:

- Type: arrest, search, phone records, business records
- Target
- Supporting evidence
- Threshold
- Judge result
- Scope
- Expiration

Use deterministic rules for MVP rather than generative legal decisions.

Illegal action detection:

- Search without valid warrant/exception
- Arrest without threshold
- Evidence collected outside scope
- Excessive force flags

## 15. NPC Police Coverage

Low-population support should be lightweight.

State machine:

1. Alarm received
2. Response delay calculated
3. NPC unit dispatched if capacity allows
4. Area secured
5. Suspects confronted
6. Evidence scene created
7. Unit leaves or transfers scene to players

NPC police should:

- Be defeatable
- Avoid advanced tactics
- Preserve consequences
- Not perfectly identify masked suspects
- Not replace detective gameplay

Population scaling inputs:

- Active police count
- Active criminal count
- Recent serious-crime rate
- District heat
- Public trust
- Time of day

## 16. Crime Operations

Crime event system should create a durable EventID used by witnesses, evidence, newspaper, cases, and archives.

Robbery stages can be represented by operation state:

- Planned
- Active
- Alarmed
- Escaped
- Failed
- Under investigation
- Closed

Do not require formal planning UI for every small crime. Use optional planning tools for larger jobs.

## 17. Injury and Incapacitation

Character health logic should map damage to gameplay state rather than immediate respawn.

States:

- Healthy
- Injured
- Critical
- Incapacitated
- Stabilized
- Recovering
- Dead

Incapacitated restrictions:

- No ordinary movement
- Limited local communication
- Can be carried
- Can be searched
- Can be arrested
- Can receive treatment
- Can be deliberately killed if rules permit

Medical treatment:

- Basic stabilization item
- Ambulance/hospital
- Illegal doctor
- Recovery timer
- Persistent temporary impairments optional later

## 18. Confirmed Death

The death-confirm interaction must be deliberate, logged, interruptible, and visible enough to support rules enforcement.

On confirmed death:

1. Set character status dead.
2. Remove organization rank.
3. Trigger leadership succession.
4. Create death event.
5. Preserve body/evidence.
6. Queue newspaper eligibility.
7. Create archive references.
8. Move player to new-character flow after scene/rules allow.

Do not automatically transfer:

- Rank
- Identity knowledge
- Contacts
- Owned items
- Police clearance
- Family permissions

A new character may be manually promoted by authorized family leadership.

## 19. Leadership Succession

Each institution defines:

- Primary leader
- Deputy
- Acting hierarchy
- Offline timeout
- Death/incapacitation behavior
- Appointment permissions

If Don unavailable:

- Underboss becomes acting authority.
- If unavailable, highest authorized capo may receive limited authority.
- Permanent succession follows family rules.

Police uses a parallel command hierarchy.

## 20. Newspaper Generation

Use event templates rather than unconstrained generation for MVP.

Eligible event types:

- Identified death
- Major robbery
- Major arrest
- Raid
- Trial/outcome
- Business opening
- Public funeral
- Political/funding change

Article data:

- Headline template
- Public facts
- Victim/offender public identity
- Location
- Time window
- Official quote template
- Image reference
- Accuracy/confidence flags

Portrait (P-001):

- **DECIDED (D-011): Option C.** A real image captured client-side in a controlled photo booth during character creation, uploaded once, stored server-side as base64. Option B (silhouette) is the fallback when no portrait exists. The Option E composite recommended here was superseded and spike S2 is closed; M4 implements the capture and storage.
- Avoid exposing a masks-off face if no public image logically existed; use the file-photo rule — a portrait appears only when the paper could plausibly have one. (M21 §4c decides when that is.)

Newspapers should be generated server-side and frozen once published.

## 21. Archive

Archive database indexes:

- Season
- Character
- Event
- Newspaper issue
- Case
- Organization
- Business
- Location

Library UI supports:

- Browse by season
- Search by public character name
- Search by headline
- View issue
- View closed case
- View seasonal summary

Only public records enter the public archive. Secret records remain private or become public after rules-defined release.

## 22. Persistence

Suggested split:

Account persistence:
- SteamID64
- Cosmetics
- Titles
- Career stats

Season persistence:
- Characters
- Organizations
- Businesses
- Inventory
- Money
- Cases
- Evidence
- News
- Public trust
- Heat

Archive persistence:
- Immutable season summary
- Published newspapers
- Public cases
- Notable character records
- Awards

Use transactional writes for money, items, deaths, promotions, and evidence.

## 23. Administration and Audit

Because hidden identity and metagaming are central, staff need secure audit tools.

Log:

- Introductions
- Identity disclosures
- Promotions
- Family invites
- Treasury transactions
- Item transfers
- Telephone line assignments
- Call metadata
- Evidence handling
- Warrants
- Confirmed kills
- Character creation
- Faction transitions

Staff UI must not leak into ordinary gameplay.

## 24. Development Order

Phase 1 — Foundation
- Character/account/season persistence
- Identity and introduction
- Hidden scoreboard/feeds
- Local text and voice
- Minimal HUD
- Inventory

Phase 2 — Organizations
- Persistent families
- Police department
- Ranks and acting leadership
- Treasury and procurement
- Telephony (payphones and private lines)

Phase 3 — City gameplay
- Businesses
- Store robbery
- Witnesses
- NPC police response
- Evidence
- Cases and warrants

Phase 4 — Consequences and history
- Injury/incapacitation
- Confirmed death
- Newspaper
- Library archive
- Seasonal reset

Phase 5 — Expansion
- Informants
- Corrupt police
- Sit-downs
- Territory/influence
- Advanced telephone records
- Funeral systems
- Bank operations

## 25. High-Risk Areas

- Source-engine player-list leakage
- Voice routing and speakerphone behavior
- Preventing UI/name leakage through addons
- Reliable persistence across wipes
- Abuse of confirmed death
- Metagaming through Discord
- Low-population NPC balance
- Evidence complexity and performance
- Newspaper portrait generation/storage
- Leadership griefing
- Rank restoration disputes
- Accessibility for text-only players

Each high-risk system should receive a written rules specification and admin audit support before release.
