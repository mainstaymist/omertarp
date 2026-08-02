-- Server-authoritative inventory operations.
--
-- The client names an instance id and an action. The server decides everything
-- else — whether the item exists, whether they own it, how far away it is,
-- whether it fits, whether the action applies. An action the client was never
-- offered simply fails, and an instance id it does not own fails with it.

local MODULE = Omerta.Module.Get("inventory")

Omerta.Inventory = Omerta.Inventory or {}
Omerta.Inventory.Internal = Omerta.Inventory.Internal or {}
local Internal = Omerta.Inventory.Internal
local OWNER = Omerta.Inventory.OWNER

Omerta.Config.Define("inventory.base_capacity", {
    type = "number", default = 20, min = 1, max = 200, scope = "server",
    description = "Bulk a character can carry with nothing worn to help.",
})
Omerta.Config.Define("inventory.drop_range", {
    type = "number", default = 64, min = 16, max = 200, scope = "server",
    description = "How far in front of a character a dropped item lands.",
})
Omerta.Config.Define("inventory.max_stream", {
    type = "number", default = 200, min = 20, max = 255, scope = "server",
    description = "Most items sent in one inventory stream.",
})

-- The two halves of the overload penalty. Both are pacing numbers that will be
-- tuned against a real map, so both are configuration; the curve they feed and
-- the reasoning behind these defaults are in sh_inventory.lua's
-- OverloadSpeedMultiplier.
--
-- THE PENALTY WAS SHARPENED ON 2026-08-02 (project lead: "make the runspeed
-- lower when you are overloaded in your inventory") by moving the REACH from
-- 0.5 to 0.35 and leaving the floor alone. Both halves of that are deliberate:
--
--   * the floor was not the thing anybody was feeling. You cannot reach it by
--     picking things up, because the gate stops you the instant you are over —
--     the only way past the line is to REMOVE capacity, and the design's own
--     worked example (take the coat off with a Thompson under it) lands 30%
--     over, which sat at 0.73 on the old ramp and never went further. The
--     penalty a player actually meets lives on the ramp; the floor is where it
--     stops, and lowering a number nobody reaches would have read as no change.
--   * the same 30% now lands at 0.61, and the floor is reached at 35% over
--     instead of 50% — so an ordinary bad decision reaches it and an absurd one
--     is not needed. That is a sixth off the speed of the exact case the design
--     wrote down, from the number that governs it.
--   * the floor stays at 0.55 because it is not a feel number, it is the
--     CALIBRATION number. It multiplies against starvation and M19's limp, and
--     0.75 × 0.68 × 0.55 = 0.28 sits just above M8's MIN_SPEED_FRACTION of
--     0.25. Lowering it puts the three-penalty stack onto that clamp, where
--     three penalties stop being distinguishable from one.
Omerta.Config.Define("inventory.overload_speed_floor", {
    type = "number", default = 0.55, min = 0.2, max = 1, scope = "server",
    description = "The slowest an over-capacity character moves, as a " ..
        "movement multiplier. 1 turns the penalty off entirely.",
})
Omerta.Config.Define("inventory.overload_reach", {
    type = "number", default = 0.35, min = 0.05, max = 4, scope = "server",
    description = "How far over the limit — as a fraction of the limit — the " ..
        "movement penalty takes to ramp from nothing to its floor.",
})

--------------------------------------------------------------------------------
-- Owners
--------------------------------------------------------------------------------
-- Every public function accepts either a Player or an explicit
-- { type = , id = } descriptor, and normalises here. Nothing below this line
-- ever guesses what an owner is.

local function ownerKey(ownerType, ownerId)
    return ownerType .. ":" .. tostring(ownerId)
end

function Omerta.Inventory.OwnerOf(ply)
    local character = Omerta.Characters.Get(ply)
    if not character then return nil end
    return OWNER.CHARACTER, character.id
end

local function resolveOwner(owner)
    if owner == nil then return nil end
    if type(owner) == "table" and owner.type and owner.id then
        return owner.type, owner.id
    end
    if Omerta.InEngine and IsValid(owner) and owner.IsPlayer and owner:IsPlayer() then
        return Omerta.Inventory.OwnerOf(owner)
    end
    return nil
end

--------------------------------------------------------------------------------
-- Containers
--------------------------------------------------------------------------------
-- A container id is chosen by whichever system owns the container: M13's
-- businesses, M14's registers. M9 provides the mechanism and one admin-spawned
-- container for testing; it does not decide where safes live.

local containers = {}

function Omerta.Inventory.RegisterContainer(id, def)
    if type(id) ~= "number" or id % 1 ~= 0 or id < 1 then
        error("container id must be a positive whole number", 2)
    end
    def = def or {}
    def.id = id
    def.capacity = def.capacity or 100
    def.label = def.label or "Container"
    containers[id] = def
    return def
end

function Omerta.Inventory.GetContainer(id) return containers[id] end

-- Who may open what. M9 shipped with every container openable by anyone
-- standing at it, which is fine for a crate in an alley and impossible for a
-- family safe — so M11 registers a predicate here rather than forking the
-- open path. fn(ply, containerId) returns true, or false + reason.
local accessProviders = {}

function Omerta.Inventory.RegisterContainerAccess(id, fn)
    accessProviders[id] = fn
end

-- Returns true, or false + reason. A container with no opinion is open.
function Omerta.Inventory.MayOpen(ply, containerId, owner)
    for _, fn in pairs(accessProviders) do
        local ok, allowed, why = pcall(fn, ply, containerId, owner)
        -- A provider that errors refuses, rather than accidentally granting
        -- access to a safe because of a typo in somebody else's module.
        if not ok then return false, "that is locked" end
        if allowed == false then return false, why or "that is not yours to open" end
    end
    return true
end

--------------------------------------------------------------------------------
-- Capacity
--------------------------------------------------------------------------------

local capacityProviders = {}

-- The seam for anything that ever changes what a character can carry: bags,
-- coats, a wheelbarrow, an injury that stops them lifting.
-- fn(ownerType, ownerId, rows) returns bonus bulk (not units).
function Omerta.Inventory.RegisterCapacityProvider(id, fn)
    capacityProviders[id] = fn
end

-- Cache of loaded inventories: ownerKey -> { [instanceId] = row }
local cache = {}

local function cachedRows(ownerType, ownerId)
    local out = {}
    for _, row in pairs(cache[ownerKey(ownerType, ownerId)] or {}) do
        out[#out + 1] = row
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- Shared with sv_money.lua, which needs the same owner normalisation and the
-- same view of the cache without reaching into the database itself.
Internal.ResolveOwner = resolveOwner
Internal.CachedRows = cachedRows
Internal.OwnerKey = ownerKey

-- Public read of a loaded inventory. Returns an array of instance rows.
function Omerta.Inventory.Get(owner)
    local ownerType, ownerId = resolveOwner(owner)
    if not ownerType then return {} end
    return cachedRows(ownerType, ownerId)
end

function Omerta.Inventory.BulkUsed(owner)
    local ownerType, ownerId = resolveOwner(owner)
    if not ownerType then return 0 end
    return Omerta.Inventory.SumBulk(cachedRows(ownerType, ownerId))
end

-- In bulk UNITS (hundredths), matching SumBulk, so the two are comparable
-- without anyone remembering to scale.
function Omerta.Inventory.BulkLimit(owner)
    local ownerType, ownerId = resolveOwner(owner)
    if not ownerType then return 0 end

    if ownerType == OWNER.WORLD then return math.huge end
    if ownerType == OWNER.CONTAINER then
        local def = containers[ownerId]
        return (def and def.capacity or 0) * Omerta.Inventory.BULK_SCALE
    end

    local bulk = Omerta.Config.Get("inventory.base_capacity")
    local rows = cachedRows(ownerType, ownerId)
    for _, fn in pairs(capacityProviders) do
        local ok, bonus = pcall(fn, ownerType, ownerId, rows)
        if ok and type(bonus) == "number" then bulk = bulk + bonus end
    end
    return math.floor(bulk * Omerta.Inventory.BULK_SCALE)
end

-- Worn clothing is what lets you carry a thing you otherwise could not, which
-- is what makes taking someone's coat worth doing. The arithmetic itself is
-- pure and lives beside SumBulk, because the two are one ruling read from
-- opposite ends and must never be edited apart.
Omerta.Inventory.RegisterCapacityProvider("inventory.worn", function(_, _, rows)
    return Omerta.Inventory.WornCapacityBonus(rows)
end)

--------------------------------------------------------------------------------
-- Over the limit
--------------------------------------------------------------------------------
-- Being over capacity is allowed and it has consequences: nothing else can be
-- picked up, and the character moves slower, both until the load is back
-- within capacity. Nothing is ever refused in order to reach the state and
-- nothing is ever dropped for the player to get out of it — the ways out all
-- REMOVE bulk, and the gate below only ever looks at bulk being added.

-- Is this owner over their limit right now?
function Omerta.Inventory.Overloaded(owner)
    local ownerType, ownerId = resolveOwner(owner)
    if not ownerType or ownerType == OWNER.WORLD then return false end
    return Omerta.Inventory.IsOverloaded(
        Omerta.Inventory.SumBulk(cache[ownerKey(ownerType, ownerId)] or {}),
        Omerta.Inventory.BulkLimit({ type = ownerType, id = ownerId }))
end

-- The movement multiplier for an owner, from the live numbers. Read once per
-- movement tick per player through the speed modifier registered in OnEnable.
function Omerta.Inventory.OverloadSpeed(owner)
    local ownerType, ownerId = resolveOwner(owner)
    if not ownerType or ownerType == OWNER.WORLD then return 1 end
    return Omerta.Inventory.OverloadSpeedMultiplier(
        Omerta.Inventory.SumBulk(cache[ownerKey(ownerType, ownerId)] or {}),
        Omerta.Inventory.BulkLimit({ type = ownerType, id = ownerId }),
        Omerta.Config.Get("inventory.overload_speed_floor"),
        Omerta.Config.Get("inventory.overload_reach"))
end

-- THE ONE PLACE bulk is allowed into an inventory. Add mints new rows; Move
-- carries existing ones, which is every pick-up off the floor, every take from
-- a container or a body, and every hand-over; Money.Give credits cash through
-- the same question. Nothing else creates bulk, so nothing else needs a check
-- — and there is therefore no caller that can forget one.
-- Returns true, or false + the reason to tell the player.
function Internal.MayReceive(ownerType, ownerId, addUnits)
    if ownerType == OWNER.WORLD then return true end
    local ok, why, overloaded = Omerta.Inventory.MayReceive(
        Omerta.Inventory.SumBulk(cache[ownerKey(ownerType, ownerId)] or {}),
        addUnits,
        Omerta.Inventory.BulkLimit({ type = ownerType, id = ownerId }))
    if ok then return true end
    -- The overload refusal is written in the second person because that is
    -- overwhelmingly who it is about. A crate that has somehow ended up over
    -- its own capacity is told about in the crate's own terms instead.
    if overloaded and ownerType ~= OWNER.CHARACTER then
        return false, "there is no room in there"
    end
    return false, why
end

--------------------------------------------------------------------------------
-- In-flight locks
--------------------------------------------------------------------------------
-- Every operation takes a lock on the instance for as long as its database
-- round-trip lasts. Two requests naming the same item cannot interleave, so an
-- item cannot be dropped and handed over at the same time.
--
-- This assumes one game server owns a season's items. That is already true of
-- characters and identity knowledge; a second server sharing the database
-- would need row-level locking, and the guarded UPDATEs below are the reason
-- such a setup would fail loudly rather than duplicate.

local busy = {}

local function lock(instanceId)
    if busy[instanceId] then return false end
    busy[instanceId] = true
    return true
end

local function unlock(instanceId) busy[instanceId] = nil end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

function Omerta.Inventory.Load(owner, cb)
    local ownerType, ownerId = resolveOwner(owner)
    cb = cb or function() end
    if not ownerType then cb(false, "unknown owner") return end

    Internal.Repo.ListForOwner(ownerType, ownerId, function(rows, err)
        if err then
            Omerta.Log.Error("inventory", "load failed for %s: %s",
                ownerKey(ownerType, ownerId), err)
            cb(false, err)
            return
        end
        local map = {}
        for _, row in ipairs(rows) do map[row.id] = row end
        cache[ownerKey(ownerType, ownerId)] = map
        cb(true)
    end)
end

function Omerta.Inventory.Unload(owner)
    local ownerType, ownerId = resolveOwner(owner)
    if not ownerType then return end
    cache[ownerKey(ownerType, ownerId)] = nil
end

function Omerta.Inventory.IsLoaded(owner)
    local ownerType, ownerId = resolveOwner(owner)
    return ownerType ~= nil and cache[ownerKey(ownerType, ownerId)] ~= nil
end

--------------------------------------------------------------------------------
-- Adding (pure planner + execution)
--------------------------------------------------------------------------------

-- Works out how to add `quantity` of `def` given what the owner already holds:
-- top up partial stacks first, then open new ones. Pure, so the stacking rules
-- are covered headlessly rather than inferred from a screenshot.
-- Returns { updates = , insertions = } where insertions is a list of quantities.
function Internal.PlanAdd(rows, def, quantity)
    local plan = { updates = {}, insertions = {} }
    local remaining = math.floor(quantity)
    if remaining <= 0 then return plan end

    if def.stackable then
        for _, row in ipairs(rows) do
            if remaining <= 0 then break end
            -- Only unequipped, plain stacks merge: an item carrying metadata
            -- (a serial number, a mark) is not interchangeable with one that
            -- does not, and merging them would destroy that distinction.
            if row.def_id == def.id and not row.equipped_slot and not row.metadata
                    and row.quantity < def.maxStack then
                local room = def.maxStack - row.quantity
                local added = math.min(room, remaining)
                plan.updates[#plan.updates + 1] = {
                    id = row.id, quantity = row.quantity + added, expected = row.quantity,
                }
                remaining = remaining - added
            end
        end
    end

    while remaining > 0 do
        local size = math.min(def.maxStack, remaining)
        plan.insertions[#plan.insertions + 1] = size
        remaining = remaining - size
    end
    return plan
end

-- Adds items to an owner. cb(ok, err)
function Omerta.Inventory.Add(owner, defId, quantity, opts, cb)
    cb = cb or function() end
    opts = opts or {}
    quantity = math.floor(quantity or 1)

    local ownerType, ownerId = resolveOwner(owner)
    if not ownerType then cb(false, "unknown owner") return end
    if not Omerta.Inventory.IsLoaded({ type = ownerType, id = ownerId }) then
        cb(false, "inventory not loaded") return
    end

    local def = Omerta.Items.Get(defId)
    if not def then cb(false, "unknown item '" .. tostring(defId) .. "'") return end
    if quantity < 1 then cb(false, "quantity must be at least 1") return end

    local season = Omerta.Seasons.GetActive()
    if not season then cb(false, "no active season") return end

    -- `force` still bypasses, and only conservation uses it: the weapons
    -- module refunds a clip's rounds into the inventory when a gun is stripped,
    -- and a refusal there would destroy ammunition rather than refuse an
    -- acquisition. Nothing a player can ask for sets it.
    if not opts.force then
        local ok, why = Internal.MayReceive(ownerType, ownerId,
            Omerta.Inventory.StackBulk(def, quantity))
        if not ok then cb(false, why) return end
    end

    local plan = Internal.PlanAdd(cachedRows(ownerType, ownerId), def, quantity)
    local insertions = {}
    for _, size in ipairs(plan.insertions) do
        insertions[#insertions + 1] = {
            def_id = defId,
            season_id = season.id,
            owner_type = ownerType,
            owner_id = ownerId,
            quantity = size,
            serial = opts.serial or Omerta.DB.NULL,
            organization_id = opts.organizationId or Omerta.DB.NULL,
            metadata = opts.metadata or Omerta.DB.NULL,
            created_at = os.time(),
        }
    end

    Internal.Repo.ApplyChanges(plan.updates, insertions, function(ok, err)
        if not ok then cb(false, err) return end
        Omerta.Inventory.Load({ type = ownerType, id = ownerId }, function()
            cb(true)
        end)
    end)
end

--------------------------------------------------------------------------------
-- Removing
--------------------------------------------------------------------------------

-- cb(ok, err). Removing more than a stack holds removes the stack and reports
-- how many were actually taken, rather than pretending.
function Omerta.Inventory.Remove(instanceId, quantity, cb)
    cb = cb or function() end
    if not lock(instanceId) then cb(false, "that item is busy") return end

    Internal.Repo.GetByID(instanceId, function(row, err)
        if err or not row then unlock(instanceId) cb(false, err or "no such item") return end

        local take = math.min(quantity or row.quantity, row.quantity)
        local finish = function(ok, ferr)
            unlock(instanceId)
            if not ok then cb(false, ferr) return end
            Omerta.Inventory.Load({ type = row.owner_type, id = row.owner_id }, function()
                cb(true, nil, take)
            end)
        end

        if take >= row.quantity then
            Internal.Repo.Delete(instanceId, finish)
        else
            Internal.Repo.SetQuantity(instanceId, row.quantity - take, finish)
        end
    end)
end

--------------------------------------------------------------------------------
-- Splitting
--------------------------------------------------------------------------------

-- Part of a stack becomes a new stack in the same pocket. No bulk changes
-- hands, so there is no capacity question — only the guarded update, so a
-- stack that changed underneath the request splits nothing. cb(ok, err)
function Omerta.Inventory.Split(ply, instanceId, quantity, cb)
    cb = cb or function() end
    local ownerType, ownerId = resolveOwner(ply)
    if not ownerType then cb(false, "no character") return end

    local row = (cache[ownerKey(ownerType, ownerId)] or {})[instanceId]
    if not row then cb(false, "you are not carrying that") return end

    local def = Omerta.Items.Get(row.def_id)
    if not (def and def.stackable) then cb(false, "that does not divide") return end
    -- A marked stack (serial, metadata) is particular; copying its marks onto
    -- a second stack would forge them, and leaving them off would lose them.
    if row.serial or row.metadata then cb(false, "that one is particular") return end

    quantity = math.floor(tonumber(quantity) or 0)
    if quantity < 1 or quantity >= row.quantity then
        cb(false, "both stacks need something in them") return
    end

    local season = Omerta.Seasons.GetActive()
    if not season then cb(false, "no active season") return end
    if not lock(instanceId) then cb(false, "that item is busy") return end

    Internal.Repo.ApplyChanges(
        { { id = row.id, quantity = row.quantity - quantity, expected = row.quantity } },
        { {
            def_id = row.def_id,
            season_id = season.id,
            owner_type = ownerType,
            owner_id = ownerId,
            quantity = quantity,
            serial = Omerta.DB.NULL,
            organization_id = row.organization_id or Omerta.DB.NULL,
            metadata = Omerta.DB.NULL,
            created_at = os.time(),
        } },
        function(ok, err)
            unlock(instanceId)
            if not ok then cb(false, err) return end
            Omerta.Inventory.Load({ type = ownerType, id = ownerId }, function()
                cb(true)
            end)
        end)
end

--------------------------------------------------------------------------------
-- Moving
--------------------------------------------------------------------------------

-- The one operation everything else is built from. Guarded on the owner it
-- expects to move from, so the same request arriving twice moves the item once.
-- cb(ok, err)
function Omerta.Inventory.Move(instanceId, toOwner, cb)
    cb = cb or function() end
    local toType, toId = resolveOwner(toOwner)
    if not toType then cb(false, "unknown destination") return end
    if not lock(instanceId) then cb(false, "that item is busy") return end

    local function fail(why)
        unlock(instanceId)
        cb(false, why)
    end

    Internal.Repo.GetByID(instanceId, function(row, err)
        if err or not row then fail(err or "no such item") return end
        if row.owner_type == toType and row.owner_id == toId then
            fail("it is already there") return
        end

        local def = Omerta.Items.Get(row.def_id)
        if not def then fail("unknown item type") return end

        -- The destination is the only end that is ever checked. A move OUT of
        -- an overloaded inventory — dropping, storing, handing over — asks
        -- nothing of the source, which is what guarantees there is always a way
        -- back under the limit.
        if toType ~= OWNER.WORLD then
            if not Omerta.Inventory.IsLoaded({ type = toType, id = toId }) then
                fail("destination inventory is not loaded") return
            end
            local mayTake, why = Internal.MayReceive(toType, toId,
                Omerta.Inventory.StackBulk(def, row.quantity))
            if not mayTake then fail(why) return end
        end

        local fromType, fromId = row.owner_type, row.owner_id
        Internal.Repo.SetOwner(instanceId, toType, toId, fromType, fromId,
            function(moved, moveErr, newRow)
            unlock(instanceId)
            if moveErr then cb(false, moveErr) return end
            if not moved then cb(false, "that item is no longer where you left it") return end

            -- Both ends are reloaded: leaving a stale row in either cache is
            -- how an item appears to be in two places at once.
            Omerta.Inventory.Load({ type = fromType, id = fromId }, function()
                Omerta.Inventory.Load({ type = toType, id = toId }, function()
                    cb(true, nil, newRow)
                end)
            end)
        end)
    end)
end

--------------------------------------------------------------------------------
-- The world
--------------------------------------------------------------------------------

local worldEntities = {} -- instanceId -> entity

-- Where a prop placed by this player should stand: where they are looking,
-- on the surface under it. Taking the player's feet and adding an aim vector
-- puts the prop wherever the crosshair happened to be pointing, which is
-- usually a few inches into the floor.
function Omerta.Inventory.PlacementInFront(ply, distance)
    local start = ply:EyePos()
    local forward = util.TraceLine({
        start = start,
        endpos = start + ply:GetAimVector() * (distance or 96),
        filter = ply,
    })
    local ground = util.TraceLine({
        start = forward.HitPos + Vector(0, 0, 16),
        endpos = forward.HitPos - Vector(0, 0, 1024),
        filter = ply,
    })
    return ground.Hit and ground.HitPos or forward.HitPos
end

-- Lifts a spawned entity so its BASE sits on `pos`. A prop's origin is its
-- centre, so setting the position to a floor point buries half the model —
-- which is exactly what a safe placed at head height then dropped looks like.
-- Must run after Spawn, since the bounding box needs the model.
function Omerta.Inventory.RestOnGround(ent, pos)
    if not IsValid(ent) then return end
    ent:SetPos(pos - Vector(0, 0, ent:OBBMins().z))
end

function Internal.SpawnWorldItem(row, pos, ang)
    if not Omerta.InEngine then return nil end
    local def = Omerta.Items.Get(row.def_id)
    if not def then return nil end

    local ent = ents.Create("omerta_item")
    if not IsValid(ent) then return nil end
    -- The model has to be known before Spawn, because Initialize is what
    -- applies it; the networked fields are set afterwards, where they are
    -- guaranteed to reach clients.
    ent.OmertaInstance = row.id
    ent.OmertaModel = def.model
    ent:SetPos(pos)
    ent:SetAngles(ang or Angle(0, 0, 0))
    ent:Spawn()
    ent:Activate()
    ent:SetItem(row.id, def, row.quantity)

    worldEntities[row.id] = ent
    return ent
end

function Internal.WorldEntityFor(instanceId) return worldEntities[instanceId] end

function Internal.ForgetWorldEntity(instanceId) worldEntities[instanceId] = nil end

-- cb(ok, err)
function Omerta.Inventory.Drop(ply, instanceId, cb)
    cb = cb or function() end
    if not Omerta.InEngine or not IsValid(ply) then cb(false, "no player") return end

    local ownerType, ownerId = Omerta.Inventory.OwnerOf(ply)
    if not ownerType then cb(false, "no character") return end

    local row = (cache[ownerKey(ownerType, ownerId)] or {})[instanceId]
    if not row then cb(false, "you are not carrying that") return end
    local def = Omerta.Items.Get(row.def_id)
    local wasEquipped = row.equipped_slot ~= nil

    local forward = ply:GetAimVector()
    forward.z = 0
    forward:Normalize()
    local drop = ply:GetPos() + Vector(0, 0, 24)
        + forward * Omerta.Config.Get("inventory.drop_range")

    Omerta.Inventory.Move(instanceId, { type = OWNER.WORLD, id = 0 }, function(ok, err, newRow)
        if not ok then cb(false, err) return end
        -- Leaving your person is leaving your hands. The move itself already
        -- cleared the slot in the row; this tells whatever projected the row
        -- into the world (a weapon module's SWEP) to let go too. Without it,
        -- dropping an equipped revolver left the gun in the hands with no
        -- item underneath it.
        if wasEquipped then
            hook.Run("Omerta.ItemUnequipped", ply, row, def)
        end
        Internal.Repo.SetPosition(instanceId, math.floor(drop.x), math.floor(drop.y),
            math.floor(drop.z))
        Internal.SpawnWorldItem(newRow or row, drop, Angle(0, ply:EyeAngles().y, 0))
        cb(true)
    end)
end

-- cb(ok, err)
function Omerta.Inventory.PickUp(ply, ent, cb)
    cb = cb or function() end
    if not (Omerta.InEngine and IsValid(ply) and IsValid(ent)) then cb(false, "nothing there") return end
    if ent:GetClass() ~= "omerta_item" then cb(false, "that cannot be picked up") return end

    -- The entity is the authority on which instance this is; the client never
    -- learns a world item's instance id, so it cannot name one it has not
    -- walked up to.
    local instanceId = ent.OmertaInstance
    if not instanceId then cb(false, "that item is not real") return end

    local ownerType, ownerId = Omerta.Inventory.OwnerOf(ply)
    if not ownerType then cb(false, "no character") return end

    Omerta.Inventory.Move(instanceId, { type = ownerType, id = ownerId }, function(ok, err)
        if not ok then cb(false, err) return end
        worldEntities[instanceId] = nil
        if IsValid(ent) then ent:Remove() end
        cb(true)
    end)
end

--------------------------------------------------------------------------------
-- Handing something over
--------------------------------------------------------------------------------

-- Audited (Tech §23): "where did that gun come from" has to be answerable long
-- after everyone involved has forgotten.
function Omerta.Inventory.Transfer(fromPly, toPly, instanceId, cb)
    cb = cb or function() end
    local fromType, fromId = resolveOwner(fromPly)
    local toType, toId = resolveOwner(toPly)
    if not (fromType and toType) then cb(false, "both parties need a character") return end

    local row = (cache[ownerKey(fromType, fromId)] or {})[instanceId]
    if not row then cb(false, "you are not carrying that") return end
    local wasEquipped = row.equipped_slot ~= nil

    Omerta.Inventory.Move(instanceId, { type = toType, id = toId }, function(ok, err)
        if not ok then cb(false, err) return end
        -- Handing something over takes it out of your hands first, same as
        -- dropping it (the move cleared the slot; this clears the projection).
        if wasEquipped then
            hook.Run("Omerta.ItemUnequipped", fromPly, row, Omerta.Items.Get(row.def_id))
        end
        Omerta.Log.Audit("inventory.transfer", {
            from_character = fromId,
            to_character = toId,
            data = { item = row.def_id, quantity = row.quantity, instance = instanceId },
        })
        cb(true)
    end)
end

--------------------------------------------------------------------------------
-- Equipment
--------------------------------------------------------------------------------

function Omerta.Inventory.Equip(ply, instanceId, cb)
    cb = cb or function() end
    local ownerType, ownerId = resolveOwner(ply)
    if not ownerType then cb(false, "no character") return end

    local rows = cache[ownerKey(ownerType, ownerId)] or {}
    local row = rows[instanceId]
    if not row then cb(false, "you are not carrying that") return end

    local def = Omerta.Items.Get(row.def_id)
    if not (def and def.slot) then cb(false, "that cannot be worn or held") return end

    -- One thing per slot: whatever is in it comes off first, in the same
    -- sequence, so the two writes cannot leave two items in one slot.
    local occupying = nil
    for _, other in pairs(rows) do
        if other.equipped_slot == def.slot and other.id ~= instanceId then
            occupying = other.id
            break
        end
    end

    local function equip()
        Internal.Repo.SetEquippedSlot(instanceId, def.slot, ownerType, ownerId, function(ok, err)
            if not ok then cb(false, err) return end
            Omerta.Inventory.Load({ type = ownerType, id = ownerId }, function()
                -- The seam anything physical hangs off: a coat changes your
                -- capacity through the provider, but a weapon has to appear in
                -- your hands, and that is the weapons module's business, not
                -- this one's.
                hook.Run("Omerta.ItemEquipped", ply, row, def)
                cb(true)
            end)
        end)
    end

    if occupying then
        Internal.Repo.SetEquippedSlot(occupying, nil, ownerType, ownerId, function(ok, err)
            if not ok then cb(false, err) return end
            equip()
        end)
    else
        equip()
    end
end

function Omerta.Inventory.Unequip(ply, instanceId, cb)
    cb = cb or function() end
    local ownerType, ownerId = resolveOwner(ply)
    if not ownerType then cb(false, "no character") return end

    local row = (cache[ownerKey(ownerType, ownerId)] or {})[instanceId]
    if not row then cb(false, "you are not carrying that") return end
    if not row.equipped_slot then cb(false, "that is not equipped") return end

    -- Taking a coat off can put you over your limit and IT GOES THROUGH.
    -- Nothing is refused and nothing is dropped for you; what it costs is
    -- stated under "Over the limit" above — no picking anything else up, and
    -- slower on your feet, both until the load is back within capacity.
    -- Refusing would be worse: it would let a full inventory weld clothing on.
    --
    -- The two halves of the change land on ONE reload, which is what makes the
    -- numbers the client is next told consistent: in a single write the coat
    -- stops paying its capacityBonus and starts paying its own bulk, so the
    -- capacity line never shows one of those without the other.
    local def = Omerta.Items.Get(row.def_id)
    Internal.Repo.SetEquippedSlot(instanceId, nil, ownerType, ownerId, function(ok, err)
        if not ok then cb(false, err) return end
        Omerta.Inventory.Load({ type = ownerType, id = ownerId }, function()
            hook.Run("Omerta.ItemUnequipped", ply, row, def)
            cb(true)
        end)
    end)
end

--------------------------------------------------------------------------------
-- Using
--------------------------------------------------------------------------------

function Omerta.Inventory.Use(ply, instanceId, cb)
    cb = cb or function() end
    local ownerType, ownerId = resolveOwner(ply)
    if not ownerType then cb(false, "no character") return end

    local row = (cache[ownerKey(ownerType, ownerId)] or {})[instanceId]
    if not row then cb(false, "you are not carrying that") return end

    local def = Omerta.Items.Get(row.def_id)
    if not def then cb(false, "unknown item") return end

    -- Food is data: `feeds` on the definition, applied here. Adding a meal is
    -- a table entry, not a function.
    if def.feeds then
        Omerta.Hunger.Feed(ply, def.feeds)
        Omerta.Inventory.Remove(instanceId, 1, function(ok, err)
            if not ok then cb(false, err) return end
            Omerta.Chat.Notice(ply, "You eat the " .. string.lower(def.name) .. ".")
            cb(true)
        end)
        return
    end

    if def.onUse then
        local ok, err = pcall(def.onUse, ply, row, def)
        if not ok then
            Omerta.Log.Error("inventory", "onUse for '%s' failed: %s", def.id, tostring(err))
            cb(false, "that did not work")
            return
        end
        cb(true)
        return
    end

    cb(false, "there is nothing to do with that")
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------

-- Which container, if any, a player currently has open. The server remembers
-- so an action naming a container has to match something they actually opened
-- — and remembers the ENTITY too, so it can re-check every time they reach in
-- that they are still standing next to it.
local openContainer = {} -- steamid64 -> { id = , ent = , owner = { type, id } }

-- What can be opened, and what is inside it.
--
-- M9 shipped with `omerta_container` hardcoded here, which was right while a
-- crate was the only thing worth looking in. M19 needs to search a person, and
-- a person is not a crate — so the class check became a registration, exactly
-- as the access predicate did in M11. fn(ply, ent) returns an owner table
-- ({ type, id }), a display id, and optionally what the loot window should be
-- titled — or nil to decline.
local openables = {}

function Omerta.Inventory.RegisterOpenable(class, fn)
    openables[class] = fn
end

Omerta.Inventory.RegisterOpenable("omerta_container", function(_, ent)
    local containerId = ent.OmertaContainer
    if not containerId then return nil end
    local def = containers[containerId]
    return { type = OWNER.CONTAINER, id = containerId }, containerId,
        def and def.label or nil
end)

-- What this player may currently reach into, or nil. Range is re-tested on
-- every action: opening a crate and walking away must not leave the player
-- with a remote hand in it.
local function reachableOpen(ply)
    local open = openContainer[ply:SteamID64() or ""]
    if not open then return nil end
    if not IsValid(open.ent) then return nil end
    if ply:GetPos():Distance(open.ent:GetPos()) > Omerta.Interaction.MAX_RANGE then
        return nil
    end
    return open
end

local function sendInventory(ply, open)
    local ownerType, ownerId = Omerta.Inventory.OwnerOf(ply)
    if not ownerType then return end

    -- What travels as `container` is the ENTITY index, not the container id.
    -- A body has no container id — M19's openable answers 0 — so a stream from
    -- somebody's pockets was indistinguishable on the wire from a plain refresh
    -- of your own, and the client dutifully replaced the loot window with your
    -- pockets and then closed it. `open.id` stays the container id everything
    -- server-side is written against (MayOpen, capacity, access providers).
    if open and not IsValid(open.ent) then open = nil end
    local wire = open and open.ent:EntIndex() or 0

    local mine = cachedRows(ownerType, ownerId)
    local theirs = open and cachedRows(open.owner.type, open.owner.id) or {}
    local limit = Omerta.Config.Get("inventory.max_stream")

    -- What the thing being looted is holding, against what it can hold.
    --
    -- BulkLimit answers math.huge for a world owner and for anything with no
    -- declared capacity, which is every body — so an unlimited owner is
    -- reported as ZERO rather than as a number, and the client reads zero as
    -- "this has no limit to speak of" and says nothing. A coat on a corpse does
    -- not have a capacity the way a crate does, and inventing one for the sake
    -- of filling a column would be inventing a rule.
    local theirUsed, theirLimit = 0, 0
    if open then
        local capacity = Omerta.Inventory.BulkLimit(open.owner)
        if capacity and capacity < math.huge then
            theirUsed = math.min(Omerta.Inventory.SumBulk(theirs), 16777215)
            theirLimit = math.min(capacity, 16777215)
        end
    end

    Omerta.Net.Send("inventory.begin", {
        container = wire,
        label = open and string.sub(open.label or "Container", 1, 24) or "",
        count = math.min(#mine + #theirs, limit),
        bulk_used = Omerta.Inventory.SumBulk(mine),
        bulk_limit = math.min(Omerta.Inventory.BulkLimit(ply), 16777215),
        their_used = theirUsed,
        their_limit = theirLimit,
    }, ply)

    local sent = 0
    local function stream(rows, where)
        for _, row in ipairs(rows) do
            if sent >= limit then break end
            local index = Omerta.Items.IndexOf(row.def_id)
            if index then
                local slot = row.equipped_slot and Omerta.Inventory.GetSlot(row.equipped_slot)
                Omerta.Net.Send("inventory.item", {
                    instance = row.id,
                    def = index,
                    quantity = row.quantity,
                    slot = slot and slot.index or 0,
                    where = where,
                }, ply)
                sent = sent + 1
            end
        end
    end
    stream(mine, 1)
    stream(theirs, 2)

    Omerta.Net.Send("inventory.end", { container = wire }, ply)
end

Internal.SendInventory = sendInventory

-- Whether this player was over their limit the last time their pockets
-- changed. steamid64 -> bool.
local overloadedLast = {}

-- Said once on the way in and once on the way out, never in between. The
-- inventory window carries the state permanently (that is what the capacity
-- line is for) and a persistent HUD element is exactly what GDD §8 forbids —
-- but a player who is suddenly slower and suddenly cannot pick things up has
-- to be told which of their own actions did it, and the moment it happened is
-- the only moment that answers that.
function Internal.AnnounceOverload(ply)
    local sid = ply:SteamID64() or ""
    local now = Omerta.Inventory.Overloaded(ply)
    local was = overloadedLast[sid]
    if was == now then return end
    overloadedLast[sid] = now

    if now then
        Omerta.Chat.Notice(ply, "You are carrying more than you can manage. " ..
            "You are slower, and you cannot pick anything else up.")
    elseif was ~= nil then
        -- Only after a real transition. A player whose first refresh finds
        -- them comfortably under the limit is not congratulated for it.
        Omerta.Chat.Notice(ply, "Your load is manageable again.")
    end
end

-- Refreshes whoever currently has this owner's contents on screen. Every
-- operation that changed this player's pockets ends here, which makes it the
-- one honest place to notice that the load crossed the line.
function Internal.Refresh(ply)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    sendInventory(ply, reachableOpen(ply))
    Internal.AnnounceOverload(ply)
end

function Internal.HandleOpen(ply, target)
    if not Omerta.Characters.IsLoaded(ply) then return end
    local sid = ply:SteamID64() or ""

    if target == 0 then
        openContainer[sid] = nil
        sendInventory(ply, nil)
        return
    end

    local ent = Entity(target)
    if not IsValid(ent) then return end
    local resolve = openables[ent:GetClass()]
    if not resolve then return end
    -- Range is re-checked here, not trusted: opening something must never
    -- become a way to read it across the map.
    if ply:GetPos():Distance(ent:GetPos()) > Omerta.Interaction.MAX_RANGE then return end

    local owner, containerId, label = resolve(ply, ent)
    if not owner then return end

    local allowed, why = Omerta.Inventory.MayOpen(ply, containerId or owner.id, owner)
    if not allowed then
        Omerta.Chat.Notice(ply, why)
        return
    end

    local open = { id = containerId or 0, ent = ent, owner = owner, label = label }
    openContainer[sid] = open
    if Omerta.Inventory.IsLoaded(owner) then
        sendInventory(ply, open)
    else
        Omerta.Inventory.Load(owner, function()
            if IsValid(ply) then sendInventory(ply, open) end
        end)
    end
end

local function refuse(ply, why)
    if why then Omerta.Chat.Notice(ply, why) end
    Internal.Refresh(ply)
end

function Internal.HandleAction(ply, payload)
    if not Omerta.Characters.IsLoaded(ply) then return end

    local ownerType, ownerId = Omerta.Inventory.OwnerOf(ply)
    if not ownerType then return end

    local A = Omerta.Inventory.ACTION
    local action, instanceId = payload.action, payload.instance
    local open = reachableOpen(ply)

    local function done(ok, err)
        if not ok then refuse(ply, err) return end
        Internal.Refresh(ply)
    end

    -- Every branch below re-derives ownership from the server's own cache.
    -- The instance id in the payload is a nomination, never a permission.
    if action == A.USE then
        Omerta.Inventory.Use(ply, instanceId, done)
    elseif action == A.DROP then
        Omerta.Inventory.Drop(ply, instanceId, done)
    elseif action == A.EQUIP then
        Omerta.Inventory.Equip(ply, instanceId, done)
    elseif action == A.UNEQUIP then
        Omerta.Inventory.Unequip(ply, instanceId, done)
    elseif action == A.SPLIT then
        Omerta.Inventory.Split(ply, instanceId, payload.quantity, done)
    elseif action == A.TAKE then
        if not open then refuse(ply, "you cannot reach that") return end
        local row = (cache[ownerKey(open.owner.type, open.owner.id)] or {})[instanceId]
        if not row then refuse(ply, "that is not in there") return end
        Omerta.Inventory.Move(instanceId, { type = ownerType, id = ownerId }, done)
    elseif action == A.STORE then
        if not open then refuse(ply, "you cannot reach that") return end
        local row = (cache[ownerKey(ownerType, ownerId)] or {})[instanceId]
        if not row then refuse(ply, "you are not carrying that") return end
        Omerta.Inventory.Move(instanceId, open.owner, done)
    end
end

function Internal.CloseFor(ply)
    openContainer[ply:SteamID64() or ""] = nil
end

-- A fresh character is announced to from scratch: the last one's load says
-- nothing about this one's, and D-012 means it is a different person anyway.
function Internal.ForgetOverload(ply)
    overloadedLast[ply:SteamID64() or ""] = nil
end

--------------------------------------------------------------------------------
-- Staff commands
--------------------------------------------------------------------------------
-- Items have to come from somewhere before M11's procurement and M13's shops
-- exist. These are the somewhere, and they are superadmin-only.

local function findPlayer(token)
    if not token then return nil end
    for _, ply in ipairs(player.GetAll()) do
        if ply:SteamID64() == token then return ply end
    end
    return nil
end

function Internal.RegisterCommands()
    concommand.Add("omerta_item_give", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        local defId, quantity, target = args[1], tonumber(args[2]) or 1, args[3]
        local ply = target and findPlayer(target) or caller
        if not IsValid(ply) then
            Omerta.Log.Error("inventory",
                "usage: omerta_item_give <itemId> [quantity] [steamID64]%s",
                IsValid(caller) and ""
                    or " — from the server console the SteamID64 is required")
            return
        end
        if not Omerta.Items.Get(defId) then
            Omerta.Log.Error("inventory", "no such item '%s'", tostring(defId))
            return
        end
        Omerta.Inventory.Add(ply, defId, quantity, nil, function(ok, err)
            if not ok then Omerta.Log.Error("inventory", "give failed: %s", tostring(err)) return end
            Omerta.Log.Info("inventory", "gave %d x %s to %s", quantity, defId, ply:SteamID64())
            Internal.Refresh(ply)
        end)
    end)

    concommand.Add("omerta_money_give", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        local dollars = tonumber(args[1])
        local ply = args[2] and findPlayer(args[2]) or caller
        if not (dollars and IsValid(ply)) then
            Omerta.Log.Error("inventory", "usage: omerta_money_give <dollars> [steamID64]%s",
                IsValid(caller) and ""
                    or " — from the server console the SteamID64 is required")
            return
        end
        -- Entered in dollars because that is how a human thinks about it;
        -- rounded explicitly to something the mint can actually produce.
        local cents = Omerta.Money.Round(math.floor(dollars * 100 + 0.5))
        Omerta.Money.Give(ply, cents, function(ok, err)
            if not ok then Omerta.Log.Error("inventory", "give failed: %s", tostring(err)) return end
            Omerta.Log.Info("inventory", "gave %s to %s", Omerta.Money.Format(cents), ply:SteamID64())
            Internal.Refresh(ply)
        end)
    end)

    concommand.Add("omerta_container_spawn", function(caller, _, args)
        -- Needs somewhere to put it, so unlike the others this one cannot run
        -- from the server console. Say so rather than doing nothing.
        if not IsValid(caller) then
            Omerta.Log.Error("inventory",
                "omerta_container_spawn must be run in-game — it spawns the container in front of you")
            return
        end
        if not caller:IsSuperAdmin() then return end
        local id = tonumber(args[1])
        local capacity = tonumber(args[2]) or 100
        if not id or id % 1 ~= 0 or id < 1 then
            Omerta.Log.Error("inventory", "usage: omerta_container_spawn <id> [capacity]")
            return
        end
        Omerta.Inventory.RegisterContainer(id, { capacity = capacity, label = "Container" })

        local ent = ents.Create("omerta_container")
        if not IsValid(ent) then return end
        local pos = Omerta.Inventory.PlacementInFront(caller, 96)
        ent:SetPos(pos)
        ent:SetAngles(Angle(0, caller:EyeAngles().y, 0))
        ent.OmertaContainer = id
        ent:Spawn()
        Omerta.Inventory.RestOnGround(ent, pos)
        Omerta.Inventory.Load({ type = OWNER.CONTAINER, id = id })
        Omerta.Log.Info("inventory", "container #%d spawned with capacity %d", id, capacity)
    end)

    concommand.Add("omerta_model_audit", function(caller)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        Internal.AuditModels()
    end)

    concommand.Add("omerta_inventory_dump", function(caller)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        if not IsValid(caller) then return end
        local rows = Omerta.Inventory.Get(caller)
        Omerta.Log.Info("inventory", "%d stack(s), %s / %s bulk, %s in cash", #rows,
            Omerta.Inventory.FormatBulk(Omerta.Inventory.BulkUsed(caller)),
            Omerta.Inventory.FormatBulk(Omerta.Inventory.BulkLimit(caller)),
            Omerta.Money.Format(Omerta.Money.Count(caller)))
        for _, row in ipairs(rows) do
            local def = Omerta.Items.Get(row.def_id)
            Omerta.Log.Info("inventory", "  #%d %s x%d%s", row.id,
                def and def.name or row.def_id, row.quantity,
                row.equipped_slot and (" [" .. row.equipped_slot .. "]") or "")
        end
    end)
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function MODULE:OnLoad()
    Omerta.DB.DefineTable("items", {
        columns = {
            { name = "id",              type = "id" },
            { name = "def_id",          type = "text", length = 48, null = false },
            { name = "season_id",       type = "ref", null = false },
            -- character | container | world. World items carry owner_id 0
            -- rather than NULL: a real value keeps the composite index usable
            -- and keeps NULL comparison semantics out of every query.
            { name = "owner_type",      type = "text", length = 12, null = false },
            { name = "owner_id",        type = "ref", null = false, default = 0 },
            { name = "quantity",        type = "int", null = false, default = 1 },
            { name = "equipped_slot",   type = "text", length = 16 },
            -- Reserved, unenforced here: M15 gives serials meaning as evidence,
            -- M11 gives organization_id meaning as family property. Both exist
            -- now so neither needs a migration later.
            { name = "serial",          type = "text", length = 32 },
            { name = "organization_id", type = "ref" },
            { name = "metadata",        type = "json" },
            -- Where a dropped item lies, so a restart does not destroy it.
            { name = "pos_x",           type = "int" },
            { name = "pos_y",           type = "int" },
            { name = "pos_z",           type = "int" },
            { name = "created_at",      type = "timestamp", null = false },
        },
        indexes = { { "owner_type", "owner_id" }, { "season_id" }, { "serial" } },
    })

    Internal.DefineNeedsSchema()

    Omerta.DB.AddMigration(7, "items and character needs", function(m)
        m:CreateTable("items")
        m:CreateTable("character_needs")
    end)

    Omerta.Interaction.Register("inventory.pickup", {
        label = "Pick Up",
        order = 20,
        range = 96,
        default = true, -- E on a dropped item pockets it
        predicate = function(ply, target)
            if not (IsValid(target) and target:GetClass() == "omerta_item") then return false end
            if not Omerta.Characters.IsLoaded(ply) then return false end
            return true
        end,
        run = function(ply, target)
            Omerta.Inventory.PickUp(ply, target, function(ok, err)
                if not ok then Omerta.Chat.Notice(ply, err) return end
                Internal.Refresh(ply)
            end)
        end,
    })

    Omerta.Interaction.Register("inventory.search_container", {
        label = "Search",
        order = 30,
        range = 96,
        default = true, -- E on a container opens it
        -- A container known to hold nothing says so before you open it.
        describe = function(ply, target)
            local containerId = target.OmertaContainer
            local owner = containerId
                and { type = OWNER.CONTAINER, id = containerId }
            if owner and Omerta.Inventory.IsLoaded(owner)
                    and #Omerta.Inventory.Get(owner) == 0 then
                return "Search (empty)"
            end
        end,
        predicate = function(ply, target)
            if not (IsValid(target) and target:GetClass() == "omerta_container") then return false end
            return Omerta.Characters.IsLoaded(ply)
        end,
        run = function(ply, target)
            Internal.HandleOpen(ply, target:EntIndex())
        end,
    })
end

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    -- The category icons the inventory window draws. Pushed as files so a
    -- client has them before the first window opens.
    for _, icon in ipairs({ "ammo", "cigarettes", "clothes", "components",
            "food", "gun", "junk", "money", "tools" }) do
        resource.AddFile("materials/omertarp/icons/icon_" .. icon .. ".png")
    end

    hook.Add("Omerta.CharacterLoaded", "omerta.inventory.load", function(ply, character)
        Internal.ForgetOverload(ply)
        Omerta.Inventory.Load({ type = OWNER.CHARACTER, id = character.id }, function()
            -- Announced AFTER the rows exist: anything that restores physical
            -- state from equipment (the weapons module putting a revolver back
            -- in a hand) needs the inventory to actually be there first.
            if IsValid(ply) then
                hook.Run("Omerta.CharacterInventoryLoaded", ply, character)
            end
        end)
        Internal.LoadNeeds(ply, character)
    end)

    -- Being over the limit is slow. The number and its defence are in
    -- sh_inventory.lua's OverloadSpeedMultiplier; this is only the wiring.
    --
    -- Registered under its OWN id, beside hunger's and M19's leg rather than
    -- folded into either. The registry is keyed by id and MULTIPLIES what it
    -- finds, so a starving, limping, overloaded man is all three at once —
    -- where a second registration under an existing id would silently replace
    -- it. M8's MIN_SPEED_FRACTION is what stops the product reaching a crawl,
    -- and the floor above is picked so the ordinary combinations stay clear of
    -- it rather than piling onto it.
    Omerta.Stamina.RegisterSpeedModifier("inventory.overloaded", function(ply)
        if not Omerta.Characters.IsLoaded(ply) then return 1 end
        return Omerta.Inventory.OverloadSpeed(ply)
    end)

    hook.Add("PlayerDisconnected", "omerta.inventory.unload", function(ply)
        local character = Omerta.Characters.Get(ply)
        Internal.CloseFor(ply)
        Internal.UnloadNeeds(ply)
        Internal.ForgetOverload(ply)
        if character then
            Omerta.Inventory.Unload({ type = OWNER.CHARACTER, id = character.id })
        end
    end)

    -- Dropped items outlive a restart. Without this, "drop it and log off" is
    -- a way to destroy evidence that nobody would ever discover.
    Omerta.DB.WhenReady(function()
        local season = Omerta.Seasons.GetActive()
        if not season then return end
        Internal.Repo.ListWorld(season.id, function(rows, err)
            if err then
                Omerta.Log.Error("inventory", "world item restore failed: %s", err)
                return
            end
            local restored = 0
            for _, row in ipairs(rows) do
                if row.pos_x then
                    local pos = Vector(row.pos_x, row.pos_y, row.pos_z)
                    if Internal.SpawnWorldItem(row, pos) then restored = restored + 1 end
                end
            end
            if restored > 0 then
                Omerta.Log.Info("inventory", "restored %d dropped item(s) to the world", restored)
            end
        end)
    end)

    -- Every item's model is a path guessed in source against content that
    -- lives in the game. Checking them all once at boot turns "why is this
    -- crate invisible" into one line in the startup log.
    Internal.AuditModels()

    Internal.StartHunger()
    Internal.RegisterCommands()
end

-- Reports every registered item whose model does not exist. Also available as
-- omerta_model_audit, since content can change under a running server.
function Internal.AuditModels()
    if not Omerta.InEngine then return 0 end

    local missing = {}
    for _, def in ipairs(Omerta.Items.GetOrdered()) do
        if def.model and not util.IsValidModel(def.model) then
            missing[#missing + 1] = def.id .. " (" .. def.model .. ")"
        end
    end

    if #missing == 0 then
        Omerta.Log.Info("inventory", "all %d item models resolve",
            #Omerta.Items.GetOrdered())
    else
        Omerta.Log.Warn("inventory", "%d item model(s) do not exist and will " ..
            "fall back to a crate: %s", #missing, table.concat(missing, ", "))
    end
    return #missing
end
