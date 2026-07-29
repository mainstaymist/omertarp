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
local ammo = {}         -- ammo item id -> ammo definition

local ID_PATTERN = "^[a-z0-9_%.]+$"

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
    return true
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
    def.spread = def.spread or 1
    def.recoil = def.recoil or 1
    def.reloadTime = def.reloadTime or 2.5
    def.automatic = def.automatic == true
    def.holdType = def.holdType or "revolver"
    weapons_[id] = def
    byItem[id] = def

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
