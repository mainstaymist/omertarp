# Omertà RP — Game Design Document
Version: 0.2.0
Status: Working design baseline
Last updated: 2026-07-26

> **Changelog**
> - **0.2.0** — Retitled to Omertà RP (D-001). Added §1.1 Setting and Art Direction (D-002, D-005) and §1.2 Currency (D-004). Rewrote §7.2 from personal cell phones to public payphones and private landlines (D-003). Added justice-loop note to §17 (pending P-002). Updated §22 MVP list to match. See `DECISIONS.md`.
> - **0.1.0** — Initial working baseline (as "Mafia RP").

## 1. Product Definition

Omertà RP is a seasonal Garry's Mod role-playing gamemode about building and opposing organized-crime institutions in a compact city environment.

It is not a DarkRP derivative centered on job selection, global chat, public player lists, rapid respawns, or unrestricted faction switching.

The defining experience is:

> Players earn identities, information, trust, authority, wealth, and consequences through the world rather than receiving them through omniscient UI.

### 1.1 Setting and Art Direction

The game is not locked to a strict historical period. The world carries a timeless "classic organized crime" atmosphere inspired by the early-to-mid 20th century:

- Classic architecture
- Black-and-white newspapers
- Speakeasies
- Tommy guns and revolvers
- Trench coats and period dress

Modern technology is intentionally omitted or simplified wherever it conflicts with the design (most notably: no personal cell phones — see §7.2). Treat this as an artistic direction rather than historical accuracy; anachronisms are acceptable when they serve gameplay and atmosphere.

Asset policy (D-005): use existing Garry's Mod / Source Engine props first, reasonable placeholders second, and produce custom assets only after the gameplay they serve is finalized. Gameplay takes priority over art.

### 1.2 Currency

The currency is USD, valued by historical purchasing power rather than modern inflation. Small amounts of money are meaningful: a quarter is real money, a few dollars is a good day, and hundreds of dollars is serious crime. All prices, wages, fines, and treasury figures are tuned to this scale. Coins exist as physical items (required for payphones, §7.2).

## 2. Design Pillars

### 2.1 Earned information

Names, affiliations, crimes, police strength, and major events are discovered through introductions, observation, witnesses, newspapers, evidence, informants, and archives.

### 2.2 Institutions over individual grinding

Families and the police department build shared capability. Individual authority is social and role-based rather than primarily statistical.

### 2.3 Consequential but playable violence

Combat is dangerous. Most defeats create injuries and recovery; deliberate confirmed killings permanently end characters. The player remains able to continue with a new character.

### 2.4 Population-resilient simulation

Crime and law enforcement remain functional at low population through NPC response, evidence, delayed consequences, acting leadership, and persistent institutions.

### 2.5 Minimal interface

The game uses contextual UI and physical world objects. It avoids permanent HUD elements and metagame information.

## 3. Seasonal Rules

- Standard season length: four weeks.
- Each account selects one primary seasonal path: criminal, police, or independent.
- Casual switching is prohibited.
- Defection, corruption, expulsion, resignation, informant recruitment, and witness protection are controlled in-world transitions.
- Seasonal organizations, ranks, wealth, territory, cases, and property reset.
- Cosmetics, history, titles, and account statistics may persist.
- Persistent unlocks must not provide decisive combat or economic advantages.

## 4. Factions

### 4.1 Crime families

The city supports a maximum of four predefined family institutions. They exist even when empty or inactive.

Ranks:

1. Independent
2. Prospect / connected outsider
3. Associate
4. Soldier
5. Caporegime
6. Underboss
7. Don

Recruitment:

- Outsiders earn work and sponsorship.
- Senior members may provisionally recruit.
- Capos recommend formal advancement.
- The Don or acting authority approves sensitive ranks.
- Leadership delegation prevents the organization from freezing while the Don is offline.

### 4.2 Police department

Ranks:

1. Patrol Officer
2. Senior Officer
3. Detective
4. Sergeant
5. Lieutenant
6. Captain
7. Commissioner

Progression prioritizes solved cases, lawful conduct, public safety, evidence quality, and successful prosecutions.

### 4.3 Independents

Independents remain viable as business owners, bartenders, doctors, drivers, lawyers, fixers, witnesses, contractors, and potential recruits.

The role is socially and operationally limited but not intentionally boring.

## 5. Character Creation and Names

- Character first and last names are selected at creation.
- Duplicate full names are not allowed within the active season.
- A character's surname does not change upon joining a crime family.
- Family membership is hidden organizational information.
- Character names remain locked until that character dies or retires.

## 6. Identity System

- Unknown characters display as “Unknown.”
- No Steam names are shown in ordinary gameplay.
- Players learn names through in-person introductions.
- Identity knowledge is stored per character.
- Introductions do not disclose faction, occupation, or rank.
- Local text and contextual labels use the known name only when the observer has learned it.
- No normal scoreboard, connected-player list, faction counts, global join/leave feed, kill feed, or global voice display.

## 7. Communication

### 7.1 Local communication

- Spatial voice is the primary communication method.
- Local text is a fully supported equivalent for players without microphones.
- Local text is range-limited and treated as audible speech.

### 7.2 Telephones

There are no personal cell phones (D-002, D-003). Telephony is fixed to places, not people.

**Public payphones**

- Payphones are physical world objects placed throughout the city (street corners, bars, the station, the hospital).
- Making a call requires inserting quarters, and the caller must keep feeding quarters to keep the call active.
- Players must physically possess quarters; running out of change ends the call.
- Call pricing reflects historical purchasing power (D-004): affordable for a short call, costly for long coordination.
- Payphones are public: anyone nearby can overhear the local side of the conversation, watch who uses a phone, or wait by one.
- An incoming call can ring a payphone; whoever answers, answers.

**Private telephones**

- Families and businesses may purchase private telephone lines for locations they own or control: family headquarters, businesses, apartments, safehouses.
- Private phones do not consume coins but are fixed to their location.
- A private line is an asset: it appears in procurement, can be traced to its subscriber location by police process, and its existence is intelligence.

**Shared rules**

- Every line has a number. Numbers must be shared or discovered; unknown callers appear as a number only.
- Nearby players hear the local participant's side of any call. Speakerphone-like behavior may expose the remote side where supported.
- Calls can be traced, and call records obtained, through lawful police process (or corrupt shortcuts).
- Phones are physical world objects with physical interactions — never abstract menus.
- Written messages travel by note, messenger, or in-person meeting; there is no text messaging between phones.
- No default global or faction chat exists.

## 8. Interface

Permanent HUD is limited or absent.

Contextual elements:

- Low-stamina indicator
- Serious-injury warning
- Targeted interaction prompt
- Inventory interface
- Phone interface (while physically using a telephone)
- Temporary item selector

Not displayed permanently:

- Health
- Armor
- Money
- Hunger
- Names
- Jobs
- Affiliations
- Server population
- Faction population
- Wanted status
- Crosshair
- Minimap
- Kill feed
- Objective markers
- Global notices

## 9. Inventory and Equipment

- Inventory opens through a dedicated key.
- The world remains active.
- Items consume physical capacity.
- Weapons differ in concealability.
- Clothing, bags, briefcases, trunks, and furniture affect storage.
- Items can be dropped, stolen, planted, searched, seized, and tracked.
- Organizational equipment remains accountable to the organization.

## 10. Family Economy

Family treasury purchases capability:

- Communications (private telephone lines, radios)
- Weapons and ammunition
- Medical supplies
- Vehicles
- Safehouses
- Storage
- Disguises
- Burglary tools
- Surveillance
- Counter-surveillance
- Food and drink stock
- Bribes
- Legal defense
- Funeral expenses
- Replacement equipment

Family wealth does not buy direct health, damage, armor, or movement bonuses.

## 11. Businesses and Social Hubs

Businesses provide income, services, cover, information, and physical meeting space.

Required early businesses:

- Speakeasy/bar
- Restaurant
- Social club
- Auto shop
- Funeral home
- Tailor or clothing shop
- Doctor/clinic

Speakeasies and bars support:

- Food and drink purchases
- Gambling
- Meetings
- Recruitment
- Rumor gathering
- Relaxation
- Surveillance
- Ambush risk
- Hit opportunities

## 12. Crime Operations

Robberies use planning and physical interaction.

Standard phases:

1. Intelligence
2. Preparation
3. Role assignment
4. Execution
5. Escape
6. Evidence management
7. Proceeds distribution or laundering

NPC victims assess concealment, weapons, aggression, witnesses, alarms, and personality before complying, stalling, fleeing, resisting, or calling police.

## 13. Information and Intelligence

Organizations learn city events through:

- Daily newspaper
- Rumors
- Businesses
- Witnesses
- Informants
- Surveillance
- Telephone traffic
- Police bulletins
- Stolen physical records
- Direct observation

Information is compartmentalized. Rank grants access only to information necessary for that role.

## 14. Newspaper

A black-and-white city newspaper is issued daily or at a fixed real-time interval.

It reports publicly knowable events:

- Murders
- Robberies
- Raids
- Trials
- New businesses
- Political changes
- Funerals
- Major arrests

A death story may show a black-and-white portrait of the identified victim.

Stories may be incomplete or inaccurate but never reveal hidden truths without a credible source.

## 15. Library and Archive

The public library stores:

- Newspapers
- Seasonal summaries
- Closed cases
- Cold cases
- Major public records
- Historic photographs
- Notable characters and events

The archive persists across seasons and becomes the server's long-term history.

## 16. Police Gameplay

Police are investigators and protectors rather than permanent robbery blockers.

They:

- Respond to calls
- Secure scenes
- Collect evidence
- Interview witnesses
- Recruit informants
- Conduct surveillance
- Build warrants
- Plan raids
- Recover property
- Prepare prosecutions
- Investigate corruption

Department capability progresses through shared funding and performance.

## 17. Evidence and Warrants

Evidence includes:

- Witness descriptions
- Fingerprints
- Casings
- Weapon matches
- Camera images
- Vehicle details
- Phone records
- Ledgers
- Recorded conversations
- Marked currency
- Confessions
- Informant statements

Case states:

1. Unknown suspect
2. Person of interest
3. Partially identified
4. Probable cause
5. Warrant
6. Arrest
7. Prosecution or closure

An NPC judicial system evaluates warrant thresholds. Unlawful searches harm police standing and may invalidate evidence.

**Justice loop (pending P-002):** everything that happens after arrest — charges, pleas, sentencing, fines, probation, records, appeals, and any custody — is under active design review. Three complete proposals and a recommendation are in `docs/review/04_justice_system_proposals.md`; this section will be extended once the project lead selects a design. The standing constraint: sitting in a cell on a timer is never the primary punishment.

## 18. Low-Population Balance

Crimes never require player police online.

When player police are absent:

- Alarms still function.
- NPC patrols may respond.
- Witnesses remember.
- Evidence remains.
- Cameras record.
- Future investigations can begin.
- City pressure can rise.

NPC police are limited and predictable.

Player police provide the advanced investigation and strategic response.

Balance systems must reduce extremes without making either side feel artificially punished.

## 19. Injury and Death

### 19.1 Injury flow

1. Healthy
2. Wounded
3. Incapacitated
4. Stabilized
5. Hospital or illegal treatment
6. Recovery

### 19.2 Confirmed character death

A character permanently dies only through a deliberate confirmed kill or an explicitly terminal circumstance.

Character death causes:

- Loss of character rank
- Loss of character relationships
- Leadership succession
- Police and newspaper consequences
- Possible funeral
- New-character creation

### 19.3 Promotion after death

The system never automatically restores rank.

The family may choose to fast-track the player's new character based on trust in the player or organizational needs.

A player may not claim an automatic entitlement to previous rank.

## 20. Hits

Hits are strategic operations justified by meaningful objectives, such as:

- Removing a detective
- Silencing a witness
- Disrupting succession
- Eliminating a capo
- Retaliating for treaty violation
- Removing an unreliable corrupt officer
- Stopping an informant
- Creating political fear

A hit creates major evidence, police attention, retaliation, and succession effects.

## 21. Diplomacy and Betrayal

Families can hold sit-downs and negotiate territory, peace, compensation, and business arrangements.

Betrayal has consequences for respect and future negotiation.

Informants, corrupt police, rival moles, and later undercover officers create infiltration gameplay without granting magical access to private information.

## 22. MVP Definition

Required MVP:

- Compact neighborhood map
- Two to four persistent families
- Police department
- Seasonal allegiance
- Identity and introductions
- Hidden population and no scoreboard
- Local voice/text
- Public payphones and private telephone lines
- Minimal HUD
- Inventory
- Family hierarchy
- Businesses and one speakeasy
- Store and bank robbery
- NPC witness behavior
- Evidence and case files
- Warrants
- Justice loop (scope pending P-002 selection)
- Injury/incapacitation
- Confirmed character death
- Newspaper
- Library archive
- Acting leadership
- Baseline NPC police response

Deferred candidates:

- Full undercover system
- Advanced phone forensics
- Deep courtroom simulation
- Complex NPC crew AI
- Large political simulation
