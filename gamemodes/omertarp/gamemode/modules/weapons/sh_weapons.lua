-- The weapon foundation (Q-10, D-039).
--
-- The ruling: a small custom SWEP base, built so that ADDING A WEAPON IS DATA.
-- One Omerta.Weapons.Register call produces everything the gamemode needs to
-- know about a gun — the M9 item it exists as (bulk, concealment, slot), the
-- SWEP class the engine fires, and the numbers the seams read. Nothing else is
-- edited, ever. A new weapon is a table in sh_arsenal.lua; a new KIND of
-- weapon (melee, thrown) is a new base beside this one, not surgery on it.
--
-- Why custom rather than an adapted base: three later systems need control a
-- third-party base does not give away. Concealment rides M9's bulk model (a
-- Thompson at 22 bulk is the design's own example of a thing you cannot
-- pocket); evidence (M15) needs to own the fire path for casings and serials;
-- injury (M19) needs damage it can reason about. Fighting somebody else's
-- damage pipeline in three places costs more than a small base of our own.
--
-- Everything in this file is pure or registry. The engine parts live in the
-- base SWEP and sv_weapons; the arsenal is data in sh_arsenal.

Omerta.Weapons = Omerta.Weapons or {}
Omerta.Weapons.Internal = Omerta.Weapons.Internal or {}

local weapons_ = {}     -- id -> definition
local byItem = {}       -- item id -> weapon definition
local byClass = {}      -- SWEP class (ours OR a third party's) -> definition
local ammo = {}         -- ammo item id -> ammo definition

local ID_PATTERN = "^[a-z0-9_%.]+$"
-- A SWEP class as the engine spells one. Deliberately narrower than the engine
-- allows: every class we will ever be handed is a folder name under
-- `entities/weapons`, and refusing punctuation is what stops a typo'd arsenal
-- entry becoming a lookup for something that could never exist.
local CLASS_PATTERN = "^[a-z0-9_]+$"

-- The holster. Every character carries this SWEP at all times; holding it IS
-- having nothing drawn, and switching to it is how a weapon is put away. Not a
-- registered weapon — it is not an item, cannot be dropped and has no rounds.
Omerta.Weapons.HANDS = "weapon_omerta_hands"

--------------------------------------------------------------------------------
-- Ammunition
--------------------------------------------------------------------------------
-- Ammunition is an ITEM (D-004: everything physical). A caliber is registered
-- once and any number of weapons chamber it; the rounds in your coat are the
-- same rounds whichever gun they go into.

function Omerta.Weapons.RegisterAmmo(itemId, def)
    if type(itemId) ~= "string" or not itemId:find(ID_PATTERN) then
        error("ammo id '" .. tostring(itemId) .. "' must be lowercase [a-z0-9_.]", 2)
    end
    if ammo[itemId] then error("ammo '" .. itemId .. "' registered twice", 2) end
    if type(def) ~= "table" or type(def.name) ~= "string" or def.name == "" then
        error("ammo '" .. itemId .. "' needs a name", 2)
    end

    ammo[itemId] = def
    -- The item is created here, so a caliber is one call too.
    Omerta.Items.Register(itemId, {
        name = def.name,
        category = "ammo",
        -- A round weighs about what a coin does. A pocketful is nothing; a
        -- crate is a trip.
        bulk = def.bulk or 0.03,
        stackable = true,
        maxStack = def.maxStack or 60,
        model = def.model or "models/items/boxsrounds.mdl",
    })
    return def
end

function Omerta.Weapons.GetAmmo(itemId) return ammo[itemId] end

--------------------------------------------------------------------------------
-- Weapons
--------------------------------------------------------------------------------

-- The SWEP class a weapon id becomes. Deterministic and collision-free because
-- item ids already are.
function Omerta.Weapons.ClassFor(id)
    return "weapon_omerta_" .. tostring(id):gsub("^weapon%.", ""):gsub("%.", "_")
end

--------------------------------------------------------------------------------
-- Somebody else's SWEP
--------------------------------------------------------------------------------
-- A weapon may name a SWEP written by a third party:
--
--     Omerta.Weapons.Register("weapon.thompson", {
--         ...
--         external = "arc9_bo2_thompson",
--     })
--
-- and per D-039 that line IS the whole edit. The module gives, strips,
-- holsters and reconciles that class in place of our generated one; nothing
-- else in the gamemode learns the addon exists.
--
-- READ THIS BEFORE CHANGING ANYTHING BELOW IT.
--
-- The project lead installed an ARC9 pack and a TFA pack and named three
-- classes. Those three strings are the only facts. EVERYTHING ELSE ABOUT
-- EITHER ADDON IS UNKNOWN HERE: neither is installed on the machine this was
-- written on and there was no network to fetch them, so not one function of
-- theirs has been read, not one field name verified, not one model path
-- confirmed.
--
-- What makes that survivable is the rule D-043's environment seam set, applied
-- to a different kind of dependency: DETECT BY WHAT YOU INTEND TO CALL, never
-- by a name or a version. So the shape of this integration was chosen to make
-- that detection trivial — everything the bridge drives on a third-party
-- weapon is Garry's Mod BASE API, listed in EXTERNAL_CALLS below, and not one
-- line of it calls an ARC9 or a TFA function. There is nothing of theirs to
-- guess at, because we guess at nothing of theirs.
--
-- That leaves exactly one thing to detect: whether the class exists at all.
-- `weapons.Get(class)` answers that honestly and is the only check performed.
--
-- When it answers no, the weapon falls back to the generated `weapon_omerta_*`
-- class — which is registered UNCONDITIONALLY for exactly that reason, even
-- for a weapon that names an external. A server without the addon gets our own
-- gun and one line in the log, never an empty hand.

-- Every engine call the bridge makes against a third-party weapon, gathered in
-- one place so that a reader can satisfy themselves in ten seconds that none
-- of them belongs to an addon. If a future bridge needs something outside this
-- list, that is the moment to stop and detect it properly.
Omerta.Weapons.EXTERNAL_CALLS = {
    "weapons.Get",                  -- does the class exist (the ONLY detection)
    "Player:Give",                  -- put it in a hand
    "Player:StripWeapon",           -- take it out again
    "Player:HasWeapon",
    "Player:SetAmmo",               -- project the inventory into the engine pool
    "Player:GetAmmoCount",          -- read the pool back
    "Weapon:Clip1",                 -- read the magazine
    "Weapon:SetClip1",              -- and clamp it
    "Weapon:GetPrimaryAmmoType",    -- which pool this weapon eats from
}

-- The default existence check, in the engine. Headless there is no `weapons`
-- table at all, which is the correct answer for a machine with no addons: no
-- external class is present and every weapon falls back.
function Omerta.Weapons.ExternalPresent(class)
    if not Omerta.InEngine then return false end
    return weapons.Get(class) ~= nil
end

-- Which class this weapon is actually using RIGHT NOW. Resolution runs at boot
-- and again once the map is up; until it has, this answers with our own class,
-- which is the safe half of the pair.
function Omerta.Weapons.ClassOf(def)
    if type(def) ~= "table" then return nil end
    return def.activeClass or def.class
end

function Omerta.Weapons.IsExternal(def)
    return type(def) == "table" and def.external ~= nil
        and def.activeClass == def.external
end

-- A SWEP class back to the weapon it is. Both halves of the pair resolve to
-- the same definition, deliberately: whichever class ends up in a hand, the
-- hotbar, the round readout and the holster all want the same table, and none
-- of them should have to know which one won.
function Omerta.Weapons.ForClass(class) return byClass[class or ""] end

-- Chooses a class per weapon. `present` is injectable for the same reason
-- Omerta.Util.ResolveModel's validator is: the decision is then exercisable
-- headlessly, with an addon conjured and taken away again, on a machine that
-- has neither.
--
-- Returns the number that fell back, and the list of them, so the caller owns
-- the logging rather than this owning a log line the tests have to tolerate.
function Omerta.Weapons.ResolveExternal(present, allow)
    present = present or Omerta.Weapons.ExternalPresent
    if allow == nil then allow = true end

    local fellBack = {}
    for _, def in pairs(weapons_) do
        if not def.external then
            def.activeClass = def.class
        elseif not allow then
            def.activeClass = def.class
        else
            -- A detector that errors has answered: the class is not there.
            -- Anything else would let one bad lookup stop every other weapon
            -- in the arsenal from resolving.
            local ok, yes = pcall(present, def.external)
            if ok and yes then
                def.activeClass = def.external
            else
                def.activeClass = def.class
                fellBack[#fellBack + 1] = def
            end
        end
    end
    table.sort(fellBack, function(a, b) return a.id < b.id end)
    return #fellBack, fellBack
end

--------------------------------------------------------------------------------
-- The ammunition bridge (pure)
--------------------------------------------------------------------------------
-- D-004 does not bend for a third-party SWEP: THE INVENTORY IS STILL THE
-- TRUTH. What changes is that a gun we did not write does its own reloading,
-- out of the engine's ammo pool — so the pool becomes a PROJECTION of the M9
-- rows, written by the server and re-written every quarter second, and the
-- rounds that leave it are charged to the inventory that backed them.
--
-- The whole accounting is this one function, and it is pure so the suite can
-- pin it rather than an in-engine session having to. Every ambiguous case
-- resolves the SAME way — the player ends up with FEWER rounds than they might
-- have had, never more — because we cannot read the addon and a bridge that
-- guesses generously is a duplication bug with extra steps.

-- Sanity ceiling for anything crossing in from the engine. Infinities and NaN
-- survive arithmetic and poison every comparison downstream, and a pocket
-- holding a million rounds is a bug somewhere else that this must not amplify.
local MAX_ROUNDS = 1000000

local function wholeRounds(value)
    value = tonumber(value) or 0
    if value ~= value then return 0 end -- NaN
    if value >= MAX_ROUNDS then return MAX_ROUNDS end
    if value <= 0 then return 0 end
    return math.floor(value)
end

-- reserve  — rounds of this caliber in the M9 inventory right now (the truth)
-- lastClip — the magazine the server last settled on for this weapon
-- lastPool — the pool the server last projected for this caliber
-- clip     — what the live weapon says its magazine is now
-- pool     — what the engine says the pool is now
--
-- Returns { spend, clip, pool }:
--   spend — rounds to take out of the inventory, transactionally
--   clip  — what the magazine must be clamped to (rounds nothing paid for
--           come straight back out of it)
--   pool  — what the pool must be set to, which is always the inventory after
--           the spend, because the pool is a projection and nothing else
function Omerta.Weapons.PlanPoolSync(reserve, lastClip, lastPool, clip, pool)
    reserve  = wholeRounds(reserve)
    lastClip = wholeRounds(lastClip)
    lastPool = wholeRounds(lastPool)
    clip     = wholeRounds(clip)
    pool     = wholeRounds(pool)

    -- Rounds the SWEP pulled out of the pool since we last looked. The pool
    -- WAS a projection of the inventory, so these are backed by real objects
    -- and charging for them is simply settling up. This also covers a weapon
    -- that eats the pool directly instead of through a magazine, which some
    -- bases do — the rounds are gone either way and the bill is the same.
    local drawn = math.max(0, lastPool - pool)

    -- Rounds that turned up in the magazine.
    local appeared = math.max(0, clip - lastClip)

    -- Magazine rounds that nothing paid for: they did not come out of the
    -- pool, so either the addon keeps ammunition somewhere we cannot see or it
    -- refilled itself. Both are the same problem and get the same answer.
    local unbacked = math.max(0, appeared - drawn)

    local spend = math.min(drawn, reserve)
    spend = spend + math.min(unbacked, reserve - spend)

    -- Whatever could not be paid for comes straight back out of the magazine.
    -- This is the conservative failure, stated in one line: the gun ends up
    -- holding what the character actually owns.
    local shortfall = (drawn + unbacked) - spend

    return {
        spend = spend,
        clip = math.max(0, clip - shortfall),
        pool = reserve - spend,
    }
end

-- What may be put back in a pocket when a gun leaves a hand.
--
-- For our own weapons that is simply the magazine — those rounds were on the
-- character's person a moment ago. For a third party's it is the magazine OR
-- what we last vouched for, whichever is SMALLER: `Clip1` on a SWEP whose
-- magazine model we cannot read is a number we did not write, and refunding a
-- number we did not write is how a strip-and-re-equip loop mints ammunition.
function Omerta.Weapons.RefundableClip(clip, committed, external)
    clip = wholeRounds(clip)
    if not external then return clip end
    return math.min(clip, wholeRounds(committed))
end

--------------------------------------------------------------------------------

-- Returns true, or false + reason. Split out so the rules are testable and the
-- error messages are the documentation.
function Omerta.Weapons.Validate(id, def)
    if type(id) ~= "string" or not id:find(ID_PATTERN) then
        return false, "weapon id '" .. tostring(id) .. "' must be lowercase [a-z0-9_.]"
    end
    if type(def) ~= "table" then return false, "weapon '" .. id .. "' needs a definition" end
    if type(def.name) ~= "string" or def.name == "" then
        return false, "weapon '" .. id .. "' needs a name"
    end
    if not Omerta.Inventory.GetSlot(def.slot or "") then
        return false, "weapon '" .. id .. "' names unknown equipment slot '"
            .. tostring(def.slot) .. "'"
    end
    if type(def.damage) ~= "number" or def.damage <= 0 then
        return false, "weapon '" .. id .. "' needs a damage above 0"
    end
    if type(def.rpm) ~= "number" or def.rpm <= 0 then
        return false, "weapon '" .. id .. "' needs a rate of fire above 0"
    end
    if type(def.clip) ~= "number" or def.clip % 1 ~= 0 or def.clip < 1 then
        return false, "weapon '" .. id .. "' needs a whole clip size of at least 1"
    end
    if not ammo[def.ammo or ""] then
        return false, "weapon '" .. id .. "' chambers unregistered ammunition '"
            .. tostring(def.ammo) .. "' — register the caliber first"
    end
    if type(def.bulk) ~= "number" or def.bulk <= 0 then
        return false, "weapon '" .. id .. "' needs a bulk above 0"
    end
    if def.spread ~= nil and (type(def.spread) ~= "number" or def.spread < 0) then
        return false, "weapon '" .. id .. "' spread must be at least 0"
    end
    if def.external ~= nil then
        if type(def.external) ~= "string" or not def.external:find(CLASS_PATTERN) then
            return false, "weapon '" .. id .. "' names external SWEP class '"
                .. tostring(def.external) .. "', which is not a class name — "
                .. "lowercase [a-z0-9_], exactly as the addon spells its folder"
        end
        -- Claiming one of ours would make the fallback point at itself, so a
        -- missing addon would resolve to "present" and the degradation this
        -- whole seam exists for would never fire.
        if def.external:find("^weapon_omerta_") then
            return false, "weapon '" .. id .. "' names '" .. def.external
                .. "' as an EXTERNAL class, but weapon_omerta_* is ours — "
                .. "an external is somebody else's SWEP or it is nothing"
        end
    end
    -- The animation block, if there is one. Checked here rather than at the
    -- moment of use so a typo'd event name is a boot error naming the arsenal
    -- line, not a gun that silently plays nothing the first time somebody
    -- pulls a trigger in front of other people.
    --
    -- Safe to call unguarded: sh_weapons_anim.lua sorts between this file and
    -- sh_weapons_arsenal.lua ('.' < '_' < 'r'), so the rules exist before the
    -- first Register call that could need them. The include-order lint models
    -- that same ordering.
    if def.anim ~= nil then
        local okAnim, whyAnim = Omerta.Weapons.ValidateAnim(id, def.anim)
        if not okAnim then return false, whyAnim end
    end
    return true
end

--------------------------------------------------------------------------------
-- Drawing takes time
--------------------------------------------------------------------------------
-- A gun does not appear in a hand because a row changed. Getting one out from
-- under a coat is a visible, interruptible commitment — which is what makes
-- being armed a decision taken BEFORE an argument starts rather than during
-- it, and what gives the other man in the room the second he needs to read
-- what is happening. Track E's feel pass, which W0 §6 deferred along with the
-- holster models.
--
-- The length is DERIVED FROM BULK rather than declared per weapon, so the
-- arsenal inherits it without a single edit to that file: the revolver at bulk
-- 4 clears a coat in about 1.7s, the Thompson at 22 takes about 2.4s, and gun
-- number three is sensible the moment its table exists. A weapon that wants to
-- argue with the curve says `equipTime` and is believed.

Omerta.Weapons.EQUIP = {
    base    = 1.5,  -- the fumble every draw shares
    perBulk = 0.04, -- and what having to clear something bigger costs on top
    -- Clamped at both ends for the reason CycleDelay is: a typo in a table
    -- should produce a slow draw or a quick one, never a weapon that appears
    -- instantly and never a character frozen for a minute.
    min     = 0.4,
    max     = 6,
}

-- Seconds. Accepts either half of a weapon — the weapon definition or the M9
-- item it exists as — because both call sites are real and they must not be
-- able to disagree about how long the same gun takes.
function Omerta.Weapons.EquipDuration(def)
    local E = Omerta.Weapons.EQUIP
    if type(def) ~= "table" then return E.base end
    -- An item definition names its weapon; follow the link rather than reading
    -- the item's own bulk, so a future coat-sized case with its own bulk still
    -- reports the gun's draw.
    if def.weapon and byItem[def.weapon] then def = byItem[def.weapon] end

    local seconds = def.equipTime
    if type(seconds) ~= "number" or seconds <= 0 then
        seconds = E.base + (type(def.bulk) == "number" and def.bulk or 0) * E.perBulk
    end
    return math.max(E.min, math.min(E.max, seconds))
end

-- How far through a draw is, 0..1, clamped. Pure: the caller supplies the
-- clock, so the server's tick and the client's frame ask the same question of
-- the same numbers and the headless suite can pin the edges.
--
-- NOT called EquipProgress. That name belongs to the zero-argument client
-- accessor in cl_equip.lua, which the inventory window is written against; two
-- functions of one name would mean the window silently reading a helper that
-- returns a fraction where it expected an instance id.
function Omerta.Weapons.EquipFraction(startedAt, finishAt, now)
    startedAt = tonumber(startedAt) or 0
    finishAt = tonumber(finishAt) or 0
    now = tonumber(now) or 0

    local window = finishAt - startedAt
    -- A window of nothing has already elapsed. Answering 0 here would leave a
    -- bar empty forever on any degenerate pair rather than reading as done.
    if window <= 0 then return 1 end
    return math.max(0, math.min(1, (now - startedAt) / window))
end

-- ONE call. The item, the SWEP class, and the definition all come from here;
-- adding a weapon to the game is adding a call to this in sh_arsenal.lua and
-- nothing else anywhere.
function Omerta.Weapons.Register(id, def)
    local ok, why = Omerta.Weapons.Validate(id, def)
    if not ok then error(why, 2) end
    if weapons_[id] then error("weapon '" .. id .. "' registered twice", 2) end

    def.id = id
    def.class = Omerta.Weapons.ClassFor(id)
    if def.external and byClass[def.external] then
        error("weapon '" .. id .. "' names external class '" .. def.external
            .. "', which '" .. byClass[def.external].id .. "' already claims", 2)
    end
    -- Our own class until resolution says otherwise, so a call site that reads
    -- it before boot gets the half that certainly exists rather than nil.
    def.activeClass = def.class
    def.spread = def.spread or 1
    def.recoil = def.recoil or 1
    def.reloadTime = def.reloadTime or 2.5
    def.automatic = def.automatic == true
    def.holdType = def.holdType or "revolver"
    weapons_[id] = def
    byItem[id] = def
    byClass[def.class] = def
    if def.external then byClass[def.external] = def end
    -- Resolved once, here, rather than on every draw: the curve is the default
    -- and the table entry is the exception, and after this line nothing else
    -- has to know which of the two a given gun used.
    def.equipTime = Omerta.Weapons.EquipDuration(def)

    -- The M9 item: how the weapon is carried, hidden, bought, dropped,
    -- searched off a body, and equipped. `weapon = id` is the link the equip
    -- seam follows; everything else is ordinary item data.
    Omerta.Items.Register(id, {
        name = def.name,
        category = "weapon",
        bulk = def.bulk,
        concealable = def.concealable == true,
        slot = def.slot,
        model = def.worldModel and def.worldModel[1] or nil,
        weapon = id,
    })

    -- The SWEP class the engine runs. Registered on both realms at load;
    -- everything behavioural lives on the shared base, so the generated class
    -- is nothing but the definition wearing an engine-shaped coat.
    --
    -- Registered even for a weapon that names an `external`, and that is the
    -- point rather than an oversight: it is the fallback, and a fallback that
    -- is only built when it turns out to be needed is a fallback nobody has
    -- ever run.
    if Omerta.InEngine then
        weapons.Register({
            Base = "weapon_omerta_base",
            PrintName = def.name,
            Spawnable = false,
            AdminOnly = true,
            UseHands = true,
            OmertaId = id,
            ViewModel = Omerta.Util.ResolveModel(def.viewModel),
            WorldModel = Omerta.Util.ResolveModel(def.worldModel),
            HoldType = def.holdType,
            Primary = {
                ClipSize = def.clip,
                DefaultClip = 0, -- given empty, always; rounds are items
                Automatic = def.automatic,
                Ammo = "none",   -- the engine's ammo pool is never used
            },
            Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" },
        }, def.class)
    end

    return def
end

function Omerta.Weapons.Get(id) return weapons_[id] end
function Omerta.Weapons.ForItem(itemId) return byItem[itemId] end

function Omerta.Weapons.All()
    local out = {}
    for _, def in pairs(weapons_) do out[#out + 1] = def end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

--------------------------------------------------------------------------------
-- Ballistics (pure)
--------------------------------------------------------------------------------

-- Seconds between shots. Clamped so a typo'd rate of fire produces a fast gun,
-- not a hitscan hose the tick can't represent.
function Omerta.Weapons.CycleDelay(rpm)
    return math.max(0.05, 60 / math.max(1, rpm or 1))
end

-- Degrees of cone into the number FireBullets wants.
function Omerta.Weapons.Cone(degrees)
    return math.tan(math.rad(math.max(0, degrees or 0)))
end

-- How much worse the cone gets for how you are standing. Multiplied onto the
-- weapon's own spread: running ruins a shot, crouching steadies it. Clamped at
-- both ends so no stance stack makes a rifle either surgical or useless.
function Omerta.Weapons.SpreadFactor(speed, crouching)
    local factor = 1 + (math.max(0, speed or 0) / 400)
    if crouching then factor = factor * 0.8 end
    return math.max(0.6, math.min(2.5, factor))
end

-- How many rounds a reload moves from pocket to clip. Pure, so the one piece
-- of arithmetic that touches both the clip and the inventory is pinned by
-- tests rather than trusted.
function Omerta.Weapons.PlanReload(clipSize, currentClip, available)
    local need = math.max(0, (clipSize or 0) - math.max(0, currentClip or 0))
    return math.min(need, math.max(0, available or 0))
end

-- The serial number stamped on a weapon, derived from its M9 instance id: no
-- storage, unique by construction, and it survives everything the instance
-- survives. M15 makes serials matter (a filed-off serial is a metadata flag
-- for that milestone); this is the seam it will read.
function Omerta.Weapons.Serial(instanceId)
    if not instanceId or instanceId <= 0 then return nil end
    return string.format("S%06d", instanceId)
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------
-- Three private messages, each to one player about their own hands. Nothing
-- here goes to a room: what OTHER people may see of a draw is the networked
-- boolean sv_weapons sets on the player, which says somebody is reaching and
-- nothing else.

-- The draw has begun, and this is the window it runs in. Sent ONCE — the
-- client counts against it locally, exactly as M19's bleed-out clock does. A
-- per-frame stream of a number both sides can compute is traffic for nothing,
-- and it steps in visible jerks besides.
Omerta.Net.Register("weapons.equipping", {
    realm = "server_to_client",
    schema = {
        { name = "instance", type = "uint", bits = 32 },
        -- MILLISECONDS, where injury's prompt carries whole seconds. A
        -- six-second treatment can afford the rounding and a 1.66-second draw
        -- cannot: rounded to 2 the bar would still be filling after the gun
        -- was already in the hand. 16 bits carries a full minute of draw.
        { name = "millis",   type = "uint", bits = 16 },
    },
    handler = function(payload)
        hook.Run("Omerta.WeaponEquipping", payload.instance, payload.millis)
    end,
})

-- And it is over. `completed` distinguishes the gun arriving from the draw
-- being interrupted: the client draws neither differently today, but they are
-- different facts, and collapsing them on the wire is how a future sound would
-- have to guess which one it was.
Omerta.Net.Register("weapons.equip_end", {
    realm = "server_to_client",
    schema = {
        { name = "instance",  type = "uint", bits = 32 },
        { name = "completed", type = "bool" },
    },
    handler = function(payload)
        hook.Run("Omerta.WeaponEquipEnded", payload.instance, payload.completed)
    end,
})

-- How many rounds of the held weapon's caliber are on this character, for the
-- contextual readout. Pushed rather than polled, and only when it changes:
-- what is in a pocket is server truth like everything else in M9, and the
-- client has no way to count it for itself.
Omerta.Net.Register("weapons.reserve", {
    realm = "server_to_client",
    schema = {
        { name = "count", type = "uint", bits = 16 },
    },
    handler = function(payload)
        hook.Run("Omerta.WeaponReserve", payload.count)
    end,
})
