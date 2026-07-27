# Omertà RP — Glossary

Plain-language definitions of the engineering terms used in the design reviews and roadmap. Examples come from code already in this repository, so every term is checkable against something real.

---

**Public API** — the list of functions one part of the code offers to the rest of the code. The doorways in. `Omerta.Log.Info(...)` and `Omerta.Net.Register(...)` are public: any module may call them. The public API is the expensive thing to get wrong, because once twenty systems call a function, changing its shape means editing twenty systems. Each design review names the public API precisely so we decide it carefully once.

**Internal / private** — everything that is *not* the public API. The `emit()` function in `gamemode/core/sh_log.lua` is declared `local`, so nothing outside that file can reach it. Private code can be rewritten freely without affecting anything else.

**Module** — one self-contained system in its own directory under `gamemode/modules/`, registering itself with `Omerta.Module.Register`. Every gameplay system from M1 onward is a module. `modules/demo/` is the reference example.

**Realm** — which machine code runs on. **Server** (`sv_` files) runs on your server and is never sent to players. **Client** (`cl_` files) runs on each player's computer. **Shared** (`sh_` files) runs on both. Getting this wrong is how server logic leaks to players, so the module loader enforces the prefixes.

**Server-authoritative** — the server decides everything that matters, and the client only asks. A player's computer can be modified, so it may lie. If the server owns identity, money, and inventory, a cheating client can send whatever it likes and the server simply refuses.

**Hook** — a function the game engine calls when something happens (a player spawns, a round starts). `GM:Initialize` in `shared.lua` is a hook: the engine calls it once at startup.

**Net message** — a piece of data sent between server and client. All of ours go through `Omerta.Net`, which checks the contents before any handler sees them.

**Rate limit** — a cap on how often a client may send something, so one player cannot flood the server. Ours uses a *token bucket*: you get a small burst, which refills over time.

**Backend / driver** — the interchangeable thing behind an abstraction. Omertà RP supports two database backends, SQLite and MySQL; the *driver* is the code that translates our generic requests into what that specific database understands.

**Abstraction layer** — code that hides a messy or swappable detail behind a simple, stable interface. The database layer is one: gameplay says "save this character" without knowing or caring which database is running.

**Schema** — the structure of the stored data: which tables exist, what columns they have, and what type each holds. Roughly, the shape of the filing cabinet.

**Migration** — a recorded, versioned change to the schema (adding a table or column). Because a live server already holds real data, you cannot just change the shape — you apply migrations in order, and the database remembers which ones already ran.

**Transaction** — a group of database writes that must all succeed or all fail, never halfway. Moving money between a family treasury and a player is the classic case: deducting without crediting would destroy money.

**Idempotent** — safe to run more than once with the same result. Important for migrations that might be interrupted partway.

**Asynchronous (async) / callback** — work that finishes later instead of immediately. Rather than waiting for a database reply (which would freeze the server for everyone), you hand over a *callback* — a function to run when the answer arrives. "Fetch this, and here's what to do when you have it."

**Race condition** — a bug where the outcome depends on which of two things happens first. If a player sells an item twice in the same instant and both sales read the "you own it" state before either finishes, you get duplication. Transactions and server authority are the defenses.

**Parameterized query** — sending a database command and its values *separately*, so the values can never be mistaken for commands. Prevents **SQL injection**, where a player names a character something crafted to be executed as a command. Our database API only accepts values separately, making the whole class of attack structurally impossible.

**Repository** — a module that owns all the database code for one subject area and exposes plain domain functions. Gameplay calls something like `Omerta.Accounts.Load(steamID, callback)` and never writes SQL itself.

**Unit test / headless** — a test that runs the logic without the game running. Ours run under plain Lua (`lua tests/run_tests.lua`), which is why they can execute anywhere in seconds. Code that touches the engine has to be tested in-engine instead, so we deliberately keep decision-making logic separate from engine calls.

**Audit log** — a permanent record of who did what, kept for staff investigation. Central to this project because hidden identity makes cheating hard to see otherwise.

**Deterministic** — same inputs always produce the same output, with no randomness. Warrant thresholds are deterministic so the law is predictable and arguable rather than a dice roll.
