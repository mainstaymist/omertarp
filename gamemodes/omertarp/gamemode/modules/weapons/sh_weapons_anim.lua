-- How a weapon's ART is driven (Phase 2 of docs/review/06_weapon_art_port.md).
--
-- THE PROBLEM THIS SOLVES. Our base is activity-based: it asks the engine for
-- ACT_VM_PRIMARYATTACK and ACT_VM_RELOAD and lets the model decide what those
-- mean. That is the Half-Life 2 convention and it is exactly what a viewmodel
-- from somebody else's pack will NOT answer — those models carry NAMED
-- SEQUENCES instead, and an activity nothing is mapped to plays nothing.
--
-- So a weapon may declare, in the arsenal and nowhere else, which sequence
-- belongs to each event this base knows about:
--
--     Omerta.Weapons.Register("weapon.example", {
--         ...
--         anim = {
--             draw         = "draw",
--             idle         = "idle",
--             fire         = { sequence = "fire",      sound = "…/fire.wav"   },
--             fire_empty   = { sequence = "fire_last"  },  -- inherits fire's sound
--             dry          = { sound = "…/dryfire.wav" },  -- sound, no sequence
--             reload       = { sequence = "reload",    sound = "…/reload.wav" },
--             reload_empty = "reload_empty",
--             holster      = "holster",
--         },
--     })
--
-- One more field on the one Register call, so D-039 holds: adding a weapon is
-- still data in one file, and there is no second registry to keep in step.
--
-- BY NAME, NEVER BY INDEX. An index is a POSITION, and a position moves the
-- next time an artist inserts an animation — a weapon pinned to index 7 starts
-- playing somebody's reload as its draw and nothing anywhere says so. A name
-- that stops existing can be reported, and is: LookupSequence answers -1, we
-- say which weapon, which event and which name in one line, and fall back to
-- the activity the base used before any of this existed.
--
-- NOTHING HERE CALLS AN ARC9 OR A TFA FUNCTION, and nothing here knows one
-- exists. Every engine call is Garry's Mod base API on an ordinary animated
-- entity (see ANIM_CALLS). That is the same rule D-043's environment seam and
-- D-044's SWEP bridge work under, for the same reason: neither addon is
-- installed on the machine this was written on, so the only safe integration is
-- one that guesses nothing about them. Sequence NAMES are data supplied by a
-- dump from a real server; not one may be typed into the arsenal before that
-- dump exists, because a guessed name is silently wrong forever. All three
-- weapons have now been dumped and carry blocks (the Thompson and the M1911 on
-- 2026-08-02, the Model 10 the same day); the fallback for a weapon with no
-- block is unchanged and is what the fourth gun will live on.
--
-- The resolution — which sequence for which event, with which fallback and
-- which sound — is PURE and lives above the engine line, so the headless suite
-- pins it with models conjured and taken away again on a machine that has none.
--
-- THIS IS THE OTHER PATH FROM D-044, NOT A REPLACEMENT FOR IT. The `external`
-- seam hands a weapon over to somebody else's SWEP wholesale, which owns its
-- own animations along with its own reloading; an animation block drives OUR
-- base wearing THEIR model, which is what the port is for. A weapon that
-- resolves to an external class never reaches this file — its reload does not
-- go through Internal.Reload and its trigger does not go through
-- weapon_omerta_base — so the two never fight, and a weapon may carry both
-- fields while Phase 4 of the plan decides which one it should keep.

Omerta.Weapons = Omerta.Weapons or {}
Omerta.Weapons.Internal = Omerta.Weapons.Internal or {}
local Internal = Omerta.Weapons.Internal

-- Every engine call the animation path makes, gathered where a reader can
-- satisfy themselves in ten seconds that none of them belongs to an addon.
-- Same discipline, and the same list format, as EXTERNAL_CALLS in sh_weapons.
Omerta.Weapons.ANIM_CALLS = {
    "Player:GetViewModel",      -- the entity a first-person sequence plays on
    "Entity:LookupSequence",    -- name -> index, or -1 (the ONLY resolution)
    "Entity:GetSequence",
    "Entity:SetSequence",
    "Entity:SetCycle",
    "Entity:SetPlaybackRate",   -- how an animation is fitted to our clock
    "Entity:SequenceDuration",
    "Entity:GetModel",          -- for the log line, so it names the model
    "Weapon:SendWeaponAnim",    -- the activity fallback, unchanged from today
}

--------------------------------------------------------------------------------
-- The events this base knows about
--------------------------------------------------------------------------------
-- Eight, and no more: the base can only play an animation at a moment it
-- actually has, and every one of these is a line already in weapon_omerta_base
-- or sv_weapons. Ironsights are absent because there is no secondary attack to
-- hang one on (W0 §6, and the port plan §6 keeps it that way deliberately).
--
--   activity — the ACT_VM_* the base falls back to. Held as a STRING because
--     these are engine globals and this file loads headless, where they do not
--     exist; Internal.ActivityId resolves one at the moment of use.
--
--   inherit — the event to read when the model does not distinguish the two.
--     A pack whose gun has one firing animation declares `fire` and is done;
--     one whose slide locks back declares `fire_empty` beside it.
--
--   fitted — whether this event's animation is STRETCHED to a duration the
--     server is enforcing, or plays at its own natural speed. The whole of
--     that argument is in the ANIM_RATE section below, and this column is
--     where the answer lives: a rule stated once, per event, in the same table
--     the events are declared in, rather than a condition somebody has to find
--     inside PlayAnim. Two events are fitted. Six are not, and `false` is
--     written out for all six on purpose — an absent column reads as an
--     oversight, and this one was a decision.
--
--   soundField / sound — where the sound comes from when the block names none.
--     THESE ARE TODAY'S VALUES, so a weapon with no animation block at all
--     resolves to precisely the sounds the base emits now.
--
-- `reload` has no default sound on purpose: our base emits nothing on a reload
-- today (HL2 viewmodels carry their own sound events), and inventing foley for
-- the placeholder weapons would be a change to guns nobody asked to change. A
-- ported weapon declares its own and gets it — and NO PORTED WEAPON DOES YET,
-- because the dumps that named their sequences did not name their sound files.
-- All three gunshots are still the HL2 placeholders their `sound` field has
-- always held. A sound path is a name like any other, and a guessed one is
-- silently wrong forever.
Omerta.Weapons.ANIM_EVENTS = {
    -- The gun coming up. NOT the equip ceremony: W0's draw is a timed,
    -- interruptible commitment that runs BEFORE the weapon exists at all
    -- (sv_weapons' BeginEquip -> completeEquip -> M9's Equip -> the Give), so
    -- there is no viewmodel to animate while it runs. This is what plays once
    -- the gun is in the hand, and it gates nothing — see PlayAnim's header.
    -- Nothing is waiting on it, so there is no clock to fit it to.
    draw         = { activity = "ACT_VM_DRAW", fitted = false },
    -- A loop. Fitting one would mean deciding how long "at rest" lasts.
    idle         = { activity = "ACT_VM_IDLE", fitted = false },
    -- NEVER FITTED, and this is the load-bearing one. See ANIM_RATE.
    fire         = { activity = "ACT_VM_PRIMARYATTACK", fitted = false,
                     soundField = "sound", sound = "Weapon_Pistol.Single" },
    -- The shot that EMPTIES the gun (a slide locking back), not the click of
    -- an empty one — that is `dry`. A model that draws no distinction declares
    -- only `fire` and inherits it here.
    fire_empty   = { activity = "ACT_VM_PRIMARYATTACK", inherit = "fire",
                     fitted = false,
                     soundField = "sound", sound = "Weapon_Pistol.Single" },
    -- The trigger pulled on nothing. Sound-only in our base today; a model
    -- with a dryfire sequence may name one and it will play. Its lockout is a
    -- flat 0.4s of "you pulled the trigger and nothing happened" rather than a
    -- duration anybody promised the art, so it is not fitted either.
    dry          = { activity = "ACT_VM_DRYFIRE", fitted = false,
                     sound = "Weapon_Pistol.Empty" },
    -- The two the server puts a clock on: OmertaReloadUntil and
    -- SetNextPrimaryFire are set from the arsenal's number the moment the
    -- reload is allowed, and the hands must be back before that window ends.
    reload       = { activity = "ACT_VM_RELOAD", fitted = true },
    reload_empty = { activity = "ACT_VM_RELOAD", inherit = "reload",
                     fitted = true },
    -- The engine owns weapon switching and does not wait for us (see the base
    -- SWEP's Holster).
    holster      = { activity = "ACT_VM_HOLSTER", fitted = false },
}

-- Deterministic order, for validation messages and for anything that wants to
-- walk the set. `pairs` over the table above would name the events differently
-- on every boot, and an error message that reorders itself is one nobody can
-- diff against the last one.
Omerta.Weapons.ANIM_EVENT_ORDER = {
    "draw", "idle", "fire", "fire_empty", "dry",
    "reload", "reload_empty", "holster",
}

--------------------------------------------------------------------------------
-- Fitting somebody else's animation to our clock
--------------------------------------------------------------------------------
-- ONLY A DURATION-BOUND EVENT IS EVER FITTED, AND ONLY TWO OF THE EIGHT ARE.
--
-- This is the first thing the real dump corrected, so it goes first.
--
-- A RELOAD IS A WINDOW. The server decides a reload may happen, writes
-- OmertaReloadUntil and SetNextPrimaryFire from the arsenal's number, and takes
-- rounds out of a pocket against that clock. The animation is the visible half
-- of a promise the server has already made, so it must finish inside the
-- window: too long and the hands are still working after the gun can fire
-- again, too short and they are frozen on the last frame waiting for it. That
-- is what stretching is for, and it is the only thing it is for.
--
-- A SHOT IS AN EVENT. Nothing is waiting on a firing animation. It plays at its
-- natural speed and the NEXT SHOT RESTARTS IT — you see the first fraction of
-- the bolt cycle, and on an automatic that is not a compromise, it is what
-- automatic fire looks like. The arithmetic makes the point by itself: the
-- Thompson cycles at 540rpm, which is 0.111s, against a 1.333s firing
-- animation. Fitting one to the other asks for 12x — three times outside the
-- clamp below — so a fitted `fire` would clamp to 4x, warn on every burst, and
-- still be wrong, because there is no playback speed at which a full bolt cycle
-- fits in a ninth of a second. The animation was never the thing that was too
-- long; the request was the thing that was wrong.
--
-- So the two kinds are distinguished in ANIM_EVENTS' `fitted` column, one row
-- per event, and PlayAnim reads it. NOT as a condition inside PlayAnim: a rule
-- that lives in a branch is a rule that gets a second branch beside it the next
-- time somebody adds an event, and this one is a property OF THE EVENT.
-- `opts.fit` from a caller is offered, never obeyed — an event that is not
-- fitted ignores it, so no future call site can reintroduce this by passing a
-- number in good faith.
--
-- WHICH ONE WINS FOR THE TWO THAT ARE FITTED: `reloadTime` DOES, AND THE
-- ANIMATION IS STRETCHED TO IT.
--
-- Three reasons, in the order they mattered:
--
-- 1. `reloadTime` is a BALANCE number, argued for in the arsenal against the
--    other guns — the M1911's magazine change against the Model 10's 2.8s of
--    loading a cylinder by hand is a design position with a paragraph attached.
--    Letting an animation's length redefine it would move balance whenever a
--    pack updates, and would make the same gun a different gun on a server that
--    has the addon and one that does not. Their art, our rules.
--
-- 2. It gates real server work: OmertaReloadUntil, SetNextPrimaryFire, and the
--    M9 rows that come out of a pocket. Server authority cannot hang off a
--    duration read out of a model file the server may not even have mounted.
--
-- 3. The alternative is worse in a way that is hard to see coming — a weapon
--    whose lockout is its animation length is a weapon whose fire rate after a
--    reload depends on the client's content mount.
--
-- So the playback rate is length/target: a 3.0s reload animation fitted into a
-- 2.2s reload plays at 1.36. Clamped at both ends for the same reason
-- CycleDelay and EquipDuration are — a mismatch should produce a brisk reload
-- or a languid one, never a strobe and never a frozen hand.
--
-- AND THE HONEST MOVE, WHICH IS NOW TAKEN FOR EVERY GUN WE HAVE READ.
-- Stretching is a compensation for not knowing. With the real durations in hand
-- the arsenal's numbers were moved onto the art wherever the art's length was
-- defensible as balance — the M1911 reloads in 2.635s, the Thompson in 3.333s
-- and the Model 10 in 5.375s because that is how long their reloads take — so
-- this formula returns 1.0 for all six and nothing is stretched at all. The
-- Model 10 is the case that proves the principle is not free: its declared 2.8s
-- would have played at 1.92x, inside the clamp, silently, and the gun would have
-- reloaded at double speed for the rest of its life with nothing in the log. The
-- clamp-bite warning below is the worklist for the next gun; a stretch that
-- fits is the one this file cannot warn about, which is why the arsenal moves.
Omerta.Weapons.ANIM_RATE = { min = 0.25, max = 4 }

-- Is this event's animation stretched to a duration the server is enforcing?
--
-- The one reading of ANIM_EVENTS' `fitted` column, so the rule is asked for by
-- name rather than by indexing a table two files away — and so the headless
-- suite can pin "fire is never fitted" as a fact about the base rather than as
-- a side effect of which call sites happen to pass `opts.fit` today.
function Omerta.Weapons.AnimIsFitted(event)
    local spec = Omerta.Weapons.ANIM_EVENTS[type(event) == "string" and event or ""]
    return spec ~= nil and spec.fitted == true
end

-- Returns the playback rate, and whether the clamp had to bite.
-- Pure. A degenerate pair answers 1 — an animation that plays at its own speed
-- is always a defensible answer, where a rate of 0 is a frozen viewmodel and a
-- rate of inf is a crash waiting for a renderer.
function Omerta.Weapons.AnimRate(length, target)
    local R = Omerta.Weapons.ANIM_RATE
    length = tonumber(length) or 0
    target = tonumber(target) or 0
    -- NaN survives arithmetic and poisons every comparison downstream.
    if length ~= length or target ~= target then return 1, false end
    if length <= 0 or target <= 0 then return 1, false end

    local rate = length / target
    local fitted = math.max(R.min, math.min(R.max, rate))
    return fitted, fitted ~= rate
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------
-- Called from Omerta.Weapons.Validate, so a typo in the arsenal is a boot error
-- naming the line rather than a gun that silently plays nothing the first time
-- somebody pulls a trigger in front of other people.
--
-- Deliberately LOOSE about the sequence name itself: it must be a non-empty
-- string with no surrounding whitespace, and that is all. We have not read
-- either pack, so any pattern imposed here would be a guess about somebody
-- else's naming convention — and the failure mode of a wrong guess is rejecting
-- a CORRECT entry at boot, which is worse than the one it would catch. A name
-- that does not exist in the model is caught properly at the moment of use,
-- against the model, by name.
local function badName(value)
    if type(value) ~= "string" then return "must be a string" end
    if value == "" then return "must not be empty" end
    if value:find("^%s") or value:find("%s$") then
        return "has leading or trailing whitespace"
    end
    return nil
end

function Omerta.Weapons.ValidateAnim(id, map)
    local where = "weapon '" .. tostring(id) .. "' animation block"
    if type(map) ~= "table" then
        return false, where .. " must be a table of event = sequence"
    end

    for event, raw in pairs(map) do
        if type(event) ~= "string" or not Omerta.Weapons.ANIM_EVENTS[event] then
            return false, where .. " names unknown event '" .. tostring(event)
                .. "' — the events are "
                .. table.concat(Omerta.Weapons.ANIM_EVENT_ORDER, ", ")
        end

        if type(raw) == "string" then
            local why = badName(raw)
            if why then
                return false, where .. "'s " .. event .. " sequence " .. why
            end
        elseif type(raw) == "table" then
            if raw.sequence ~= nil then
                local why = badName(raw.sequence)
                if why then
                    return false, where .. "'s " .. event .. " sequence " .. why
                end
            end
            if raw.sound ~= nil then
                local why = badName(raw.sound)
                if why then
                    return false, where .. "'s " .. event .. " sound " .. why
                end
            end
            if raw.rate ~= nil and (type(raw.rate) ~= "number" or raw.rate ~= raw.rate
                or raw.rate <= 0) then
                return false, where .. "'s " .. event
                    .. " rate must be a playback speed above 0"
            end
            if raw.sequence == nil and raw.sound == nil then
                -- An entry that declares neither is a line that does nothing,
                -- which is always a mistake somebody made rather than a
                -- decision somebody took.
                return false, where .. "'s " .. event
                    .. " declares neither a sequence nor a sound"
            end
        else
            return false, where .. "'s " .. event
                .. " must be a sequence name, or a table of "
                .. "{ sequence =, sound =, rate = }"
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- What a weapon WANTS for an event (pure)
--------------------------------------------------------------------------------

-- An entry may be written as a bare sequence name or as a table. Both are read
-- here so no other function has to know there are two spellings.
local function entryOf(map, key)
    local raw = map and map[key]
    if type(raw) == "string" then return { sequence = raw } end
    if type(raw) == "table" then return raw end
    return nil
end

-- Returns { event, sequence, sound, activity, rate, fitted } or nil for an event
-- this base does not have. `sequence` is nil when the weapon declares none,
-- which is the state the revolver is in today and the state the whole fallback
-- exists to keep working.
--
-- `fitted` comes from the EVENT and never from the weapon: whether a reload is
-- stretched to the server's clock is a fact about what a reload is, not a
-- preference a gun gets to hold, and a per-weapon override would be the branch
-- ANIM_EVENTS' column exists to avoid.
--
-- Sound resolves whether or not there is an animation block, so the base can
-- read its firing sound and its dry click through one function: a weapon with
-- no block resolves to `def.sound` and "Weapon_Pistol.Empty", which is exactly
-- what the base emits now.
function Omerta.Weapons.AnimEntry(def, event)
    local spec = Omerta.Weapons.ANIM_EVENTS[type(event) == "string" and event or ""]
    if not spec then return nil end
    if type(def) ~= "table" then def = {} end

    local map = type(def.anim) == "table" and def.anim or nil

    -- The event's own entry first, then the one it inherits from. Walked per
    -- FIELD rather than per entry, so a `fire_empty` that names only a
    -- sequence still inherits `fire`'s sound instead of falling all the way
    -- through to the placeholder.
    local sequence, sound, rate
    for _, key in ipairs({ event, spec.inherit }) do
        local entry = entryOf(map, key)
        if entry then
            if sequence == nil and type(entry.sequence) == "string" then
                sequence = entry.sequence
            end
            if sound == nil and type(entry.sound) == "string" then
                sound = entry.sound
            end
            if rate == nil and type(entry.rate) == "number" then
                rate = entry.rate
            end
        end
    end

    -- Then the weapon's own top-level field (`sound` — what the arsenal has
    -- said since W0), then the base's placeholder.
    if sound == nil and spec.soundField and type(def[spec.soundField]) == "string" then
        sound = def[spec.soundField]
    end
    if sound == nil then sound = spec.sound end

    return {
        event = event,
        sequence = sequence,
        sound = sound,
        activity = spec.activity,
        rate = rate,
        fitted = spec.fitted == true,
    }
end

--------------------------------------------------------------------------------
-- What actually plays (pure, given the model's answer)
--------------------------------------------------------------------------------

-- `lookup` is a name -> sequence index function, injectable for the same
-- reason ResolveModel's validator and ResolveExternal's detector are: the
-- decision is then exercisable headlessly, with a model conjured and taken
-- away again, on a machine that has neither pack.
--
-- LookupSequence answers -1 for a name the model does not carry. Index 0 is a
-- perfectly ordinary sequence, so the test is `< 0` and not `<= 0` — a base
-- that treated 0 as absent would refuse the first animation in every model.
--
-- Returns { event, sequence, activity, sound, rate, fitted, wanted, missing }:
--   sequence — the INDEX to play, or nil when there is nothing to play by name
--   activity — the ACT_VM_* name to fall back on, always present
--   fitted   — whether a caller's clock may stretch this one (ANIM_EVENTS)
--   wanted   — the name that was asked for, for the log line
--   missing  — that same name IF the model does not have it, and nil otherwise
--
-- The caller owns the logging, exactly as ResolveExternal's does: a pure
-- function that writes a log line is one the suite has to tolerate rather than
-- pin.
function Omerta.Weapons.ResolveAnim(def, event, lookup)
    local want = Omerta.Weapons.AnimEntry(def, event)
    if not want then return nil end

    local plan = {
        event = event,
        sequence = nil,
        activity = want.activity,
        sound = want.sound,
        rate = want.rate,
        fitted = want.fitted,
        wanted = want.sequence,
        missing = nil,
    }

    -- No name declared: the activity, which is what the base did before any of
    -- this existed and what every weapon in the arsenal still does.
    if not want.sequence then return plan end
    if type(lookup) ~= "function" then return plan end

    -- A lookup that errors has answered: the sequence is not there. Anything
    -- else lets one bad model take a trigger pull down with it.
    local ok, index = pcall(lookup, want.sequence)
    if not ok then index = nil end
    if type(index) ~= "number" or index ~= index or index < 0 then
        plan.missing = want.sequence
        return plan
    end

    plan.sequence = index
    return plan
end

--------------------------------------------------------------------------------
-- The engine half
--------------------------------------------------------------------------------
-- Everything below touches entities and is behind Omerta.InEngine, exactly as
-- ResolveModel's one engine call is. The decisions it makes were all taken
-- above, where the suite can reach them.

-- ACT_VM_* are engine globals. Headless they do not exist; in the engine a
-- build that does not define one must not take the whole animation path down
-- with it, so this answers nil and the caller plays nothing rather than
-- erroring inside a trigger pull.
function Internal.ActivityId(name)
    if type(name) ~= "string" then return nil end
    local value = _G[name]
    if type(value) ~= "number" then return nil end
    return value
end

-- One line per weapon per event per boot.
--
-- Deliberately NOT sv_external's WarnOnce, which is server-only: a viewmodel is
-- a client-side object and the client is the realm that will notice a missing
-- sequence first. Two small tables beat making a server file shared.
local warnedAnim = {}

function Internal.AnimWarnOnce(key, format, ...)
    if warnedAnim[key] then return end
    warnedAnim[key] = true
    Omerta.Log.Warn("weapons", format, ...)
end

-- Play `event` on this weapon's viewmodel. Returns how many seconds it will
-- occupy, so a caller that has to know when the hands are free can.
--
-- A WEAPON WITH NO ANIMATION BLOCK RETURNS IMMEDIATELY, and that is the whole
-- of the promise that the placeholder guns are untouched. Everything the base
-- did before — ShootEffects sending ACT_VM_PRIMARYATTACK, sv_weapons sending
-- ACT_VM_RELOAD — still happens on its own line at its own call site; this
-- runs after and OVERRIDES it, and only for a weapon that asked to be
-- overridden. The activity fallback inside is therefore for one case only: a
-- weapon that DOES declare a block, whose named sequence the model turns out
-- not to have.
--
-- opts.fit    — seconds this animation must occupy, OFFERED not obeyed: it is
--               used only for an event ANIM_EVENTS marks `fitted` (the two
--               reloads), and ignored for every other. See ANIM_RATE's header
--               for why a firing animation must never be stretched to a rate of
--               fire.
-- opts.settle — do nothing if that sequence is already the one running, so an
--               idle can be re-asserted every tick for the price of a compare
function Internal.PlayAnim(wep, def, event, opts)
    if not Omerta.InEngine then return 0 end
    if not (IsValid(wep) and type(def) == "table") then return 0 end
    -- The gate. Nothing below this line runs for a weapon the arsenal has not
    -- given an animation block, on any realm, ever.
    if type(def.anim) ~= "table" then return 0 end

    local owner = wep:GetOwner()
    if not IsValid(owner) or not owner.GetViewModel then return 0 end
    local vm = owner:GetViewModel()
    if not IsValid(vm) then return 0 end

    local plan = Omerta.Weapons.ResolveAnim(def, event, function(name)
        return vm:LookupSequence(name)
    end)
    if not plan then return 0 end

    if plan.missing then
        -- The one clear line the port plan asked for: which weapon, which
        -- event, which name, on which model, and what is playing instead.
        --
        -- The model is named because it is usually the whole answer, and there
        -- are exactly two ways to get here. Either the pack is not mounted and
        -- the viewmodel is the HL2 placeholder the arsenal keeps behind it — in
        -- which case nothing is wrong with the block and the fix is the addon —
        -- or the pack is mounted and the name has gone stale, which is the case
        -- the dump exists for. Saying both stops the second sentence sending an
        -- operator to correct data that is already correct.
        Internal.AnimWarnOnce(tostring(def.id) .. "." .. tostring(event),
            "'%s' wants sequence '%s' for its %s animation, and %s does not " ..
            "have one — falling back to %s. If that is our placeholder model, " ..
            "the pack is not mounted and the block is fine; if it is the pack's, " ..
            "the name is stale — re-run 'omerta_weapon_dump %s' and correct the " ..
            "arsenal.",
            tostring(def.id), plan.missing, tostring(event),
            tostring(vm:GetModel()), tostring(plan.activity),
            tostring(Omerta.Weapons.ClassOf(def)))
    end

    local length = 0
    if plan.sequence then
        if opts and opts.settle and vm:GetSequence() == plan.sequence then
            return 0
        end
        -- SetCycle(0) unconditionally, INCLUDING when that sequence is already
        -- the one running: this is what makes the second shot of a burst
        -- RESTART the firing animation rather than let it run on from where it
        -- had got to. `settle` is the one opt-out and it exists for idle, which
        -- is the one event that means "keep doing what you were doing".
        vm:SetSequence(plan.sequence)
        vm:SetCycle(0)
        length = tonumber(vm:SequenceDuration(plan.sequence)) or 0
    else
        local activity = Internal.ActivityId(plan.activity)
        if not activity then return 0 end
        wep:SendWeaponAnim(activity)
        length = tonumber(vm:SequenceDuration()) or 0
    end

    -- Fitted to our clock where the EVENT is one the server puts a clock on and
    -- a caller supplied one; at its declared speed, or its own, otherwise. A
    -- caller's clock beats a declared rate deliberately: the clock is a rule the
    -- server is already enforcing and the rate is a preference about how the art
    -- looks while it does.
    --
    -- `plan.fitted` is the gate, and it comes from ANIM_EVENTS rather than from
    -- here. A caller that passes `fit` for a shot is not corrected, argued with
    -- or warned at — it is simply not obeyed, because a firing animation has no
    -- window to fit into and a rate of fire is not a duration the art was ever
    -- promised. See ANIM_RATE's header for the Thompson arithmetic that settles
    -- it.
    local rate = tonumber(plan.rate) or 1
    local fit = plan.fitted and opts and tonumber(opts.fit) or nil
    if fit then
        local fitted, clamped = Omerta.Weapons.AnimRate(length, fit)
        rate = fitted
        if clamped then
            Internal.AnimWarnOnce(tostring(def.id) .. "." .. tostring(event) .. ".rate",
                "'%s' has a %.2fs %s animation and a %.2fs clock for it — too far " ..
                "apart to fit by playback speed, so it is clamped to %.2fx. Move " ..
                "the arsenal's number to match the art, or the art to match it.",
                tostring(def.id), length, tostring(event), fit, rate)
        end
    end
    if rate > 0 then
        vm:SetPlaybackRate(rate)
        length = length / rate
    end

    return length
end

-- The sound half, which is wanted for weapons that declare no sequences at
-- all. Emitted on the WEAPON entity rather than on the viewmodel: a gunshot,
-- a dry click and the rattle of a magazine change are facts about the world
-- that everybody within earshot is entitled to, and a viewmodel is heard by
-- exactly one person.
function Internal.PlayAnimSound(wep, def, event)
    if not Omerta.InEngine then return end
    if not IsValid(wep) then return end
    local entry = Omerta.Weapons.AnimEntry(def, event)
    if not (entry and entry.sound) then return end
    wep:EmitSound(entry.sound)
end
