-- Inventory, items and capacity (M9).
--
-- Item DEFINITIONS live in code, not in the database: a definition is
-- behaviour and balance, which belongs in version control where it can be
-- reviewed and rolled back. Only INSTANCES persist. Every later milestone
-- registers its own items through Omerta.Items.Register — this module never
-- learns what a Thompson or a bag of flour is for.
--
-- Capacity is bulk-based (M9 §4a, D-020): each item has a bulk, each owner has
-- a limit. Big things are hard to carry and impossible to hide, which is the
-- design's actual goal; a packing grid can be layered over this data model
-- later without changing a single row.


Omerta.Items = Omerta.Items or {}
Omerta.Inventory = Omerta.Inventory or {}
Omerta.Inventory.Internal = Omerta.Inventory.Internal or {}

-- Bulk is carried internally as an integer number of hundredths. A coin has to
-- weigh something, a Thompson has to weigh a lot, and floating-point sums of
-- 0.02 do not compare reliably against a limit — so the arithmetic is integer
-- and only the display divides.
Omerta.Inventory.BULK_SCALE = 100

Omerta.Inventory.OWNER = {
    CHARACTER = "character",
    CONTAINER = "container",
    WORLD     = "world",
}

-- Wire action codes (client -> server). Values are frozen: the client sends a
-- number, so renumbering these silently changes what a stale client asks for.
Omerta.Inventory.ACTION = {
    USE     = 1,
    DROP    = 2,
    EQUIP   = 3,
    UNEQUIP = 4,
    TAKE    = 5,  -- container -> me
    STORE   = 6,  -- me -> container
    SPLIT   = 7,  -- part of a stack becomes a new stack
}

local ID_PATTERN = "^[a-z0-9_%.]+$"

--------------------------------------------------------------------------------
-- Equipment slots
--------------------------------------------------------------------------------
-- Registered rather than hardcoded so the clothing milestone can add slots
-- without editing this file. Slot ids travel on the wire as indices, derived
-- from a deterministic sort, exactly as chat channels and interactions do.

local slots = {}
local slotOrder = nil

function Omerta.Inventory.RegisterSlot(id, def)
    if type(id) ~= "string" or not id:find(ID_PATTERN) then
        error("equipment slot id '" .. tostring(id) .. "' must be lowercase [a-z0-9_.]", 2)
    end
    if slots[id] then error("equipment slot '" .. id .. "' registered twice", 2) end
    if type(def) ~= "table" or type(def.label) ~= "string" or def.label == "" then
        error("equipment slot '" .. id .. "' needs a label", 2)
    end
    def.id = id
    def.order = def.order or 100
    slots[id] = def
    slotOrder = nil
    return def
end

function Omerta.Inventory.GetSlot(id)
    -- Indices are assigned by GetSlots' deterministic sort. Without forcing
    -- that here, a slot fetched before anything had called GetSlots carried
    -- index nil — which the inventory stream wrote as 0, "not equipped", so
    -- every client saw bare pockets whatever was actually worn or held.
    Omerta.Inventory.GetSlots()
    return slots[id]
end

function Omerta.Inventory.GetSlots()
    if slotOrder then return slotOrder end
    slotOrder = {}
    for _, def in pairs(slots) do slotOrder[#slotOrder + 1] = def end
    table.sort(slotOrder, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    for i, def in ipairs(slotOrder) do def.index = i end
    return slotOrder
end

function Omerta.Inventory.GetSlotByIndex(index)
    local list = Omerta.Inventory.GetSlots()
    return list[index]
end

Omerta.Inventory.RegisterSlot("primary",   { label = "Primary",   order = 10 })
Omerta.Inventory.RegisterSlot("sidearm",   { label = "Sidearm",   order = 20 })
Omerta.Inventory.RegisterSlot("melee",     { label = "Melee",     order = 30 })
Omerta.Inventory.RegisterSlot("outerwear", { label = "Outerwear", order = 40 })
Omerta.Inventory.RegisterSlot("headwear",  { label = "Headwear",  order = 50 })

--------------------------------------------------------------------------------
-- Item definitions
--------------------------------------------------------------------------------

local items = {}
local itemOrder = nil

-- Returns true, or false + reason. Pure; exposed for the headless suite.
function Omerta.Items.Validate(id, def)
    if type(id) ~= "string" or not id:find(ID_PATTERN) then
        return false, "item id '" .. tostring(id) .. "' must be lowercase [a-z0-9_.]"
    end
    if type(def) ~= "table" then return false, "item '" .. id .. "' needs a definition" end
    if type(def.name) ~= "string" or def.name == "" then
        return false, "item '" .. id .. "' needs a name"
    end
    if type(def.bulk) ~= "number" or def.bulk < 0 then
        return false, "item '" .. id .. "' needs a bulk of at least 0"
    end
    if type(def.category) ~= "string" or not def.category:find(ID_PATTERN) then
        return false, "item '" .. id .. "' needs a lowercase category"
    end
    if def.stackable ~= nil and type(def.stackable) ~= "boolean" then
        return false, "item '" .. id .. "' stackable must be a boolean"
    end
    if def.maxStack ~= nil and (type(def.maxStack) ~= "number"
            or def.maxStack % 1 ~= 0 or def.maxStack < 1) then
        return false, "item '" .. id .. "' maxStack must be a positive whole number"
    end
    if def.stackable == false and def.maxStack and def.maxStack > 1 then
        return false, "item '" .. id .. "' cannot be unstackable with a maxStack above 1"
    end
    if def.slot ~= nil and not slots[def.slot] then
        return false, "item '" .. id .. "' names unknown equipment slot '" .. tostring(def.slot) .. "'"
    end
    if def.onUse ~= nil and type(def.onUse) ~= "function" then
        return false, "item '" .. id .. "' onUse must be a function"
    end
    return true
end

-- The seam every later milestone uses: M11 registers procurement goods, M12
-- the payphone's coins, M13 bar stock, M15 evidence, M19 medical supplies.
function Omerta.Items.Register(id, def)
    local ok, why = Omerta.Items.Validate(id, def)
    if not ok then error(why, 2) end
    if items[id] then error("item '" .. id .. "' registered twice", 2) end

    def.id = id
    def.stackable = def.stackable == true
    def.maxStack = def.stackable and (def.maxStack or 100) or 1
    -- Concealable by default: most things fit under a coat. The exceptions
    -- (a Thompson, a body) say so explicitly.
    def.concealable = def.concealable ~= false
    items[id] = def
    itemOrder = nil
    return def
end

function Omerta.Items.Get(id) return items[id] end

-- Deterministic ordering by id, so both realms compute the same indices and
-- the wire only ever carries a number.
function Omerta.Items.GetOrdered()
    if itemOrder then return itemOrder end
    itemOrder = {}
    for _, def in pairs(items) do itemOrder[#itemOrder + 1] = def end
    table.sort(itemOrder, function(a, b) return a.id < b.id end)
    for i, def in ipairs(itemOrder) do def.index = i end
    return itemOrder
end

function Omerta.Items.GetByIndex(index)
    local list = Omerta.Items.GetOrdered()
    return list[index]
end

function Omerta.Items.IndexOf(id)
    local def = items[id]
    if not def then return nil end
    Omerta.Items.GetOrdered() -- assigns indices
    return def.index
end

--------------------------------------------------------------------------------
-- Bulk arithmetic (pure)
--------------------------------------------------------------------------------

-- Bulk of one unit, in integer hundredths.
function Omerta.Inventory.UnitBulk(def)
    if not def then return 0 end
    return math.floor(def.bulk * Omerta.Inventory.BULK_SCALE + 0.5)
end

-- Bulk of a stack, in integer hundredths.
function Omerta.Inventory.StackBulk(def, quantity)
    return Omerta.Inventory.UnitBulk(def) * math.max(0, math.floor(quantity or 0))
end

-- Total CARRIED bulk of a list of { def_id = , quantity = , equipped_slot = }
-- rows, in hundredths. Rows naming an unregistered item contribute nothing
-- rather than erroring: an item removed from a later version of the gamemode
-- must not make an existing character's inventory unopenable.
--
-- WHAT IS WORN COSTS NOTHING. An item sitting in an equipped slot is ON the
-- character rather than in their hands, so the only number it contributes is
-- its capacityBonus (WornCapacityBonus below, which is the other half of this
-- same rule). A coat you are wearing is therefore strictly good; a coat over
-- your arm costs its 4 — which is what makes taking one off a decision.
--
-- Iterated with pairs rather than ipairs so an owner's raw cache, which is
-- keyed by instance id rather than being an array, can be summed without first
-- being flattened and sorted. Both shapes iterate identically.
function Omerta.Inventory.SumBulk(rows)
    local total = 0
    for _, row in pairs(rows or {}) do
        if not row.equipped_slot then
            total = total + Omerta.Inventory.StackBulk(Omerta.Items.Get(row.def_id), row.quantity)
        end
    end
    return total
end

-- Capacity granted by what is worn, in BULK (not units) — the pure half of
-- sv_inventory's "inventory.worn" capacity provider.
--
-- It lives here beside SumBulk on purpose. The two are one ruling read from
-- opposite ends, and they move together: the frame a coat comes off it stops
-- paying this AND starts paying its own bulk up there. Kept apart, the pair
-- could be changed one at a time, and the failure would be a capacity line
-- that disagreed with itself for exactly as long as nobody looked.
function Omerta.Inventory.WornCapacityBonus(rows)
    local bonus = 0
    for _, row in pairs(rows or {}) do
        if row.equipped_slot then
            local def = Omerta.Items.Get(row.def_id)
            if def and def.capacityBonus then bonus = bonus + def.capacityBonus end
        end
    end
    return bonus
end

function Omerta.Inventory.Fits(usedUnits, addUnits, limitUnits)
    return (usedUnits + addUnits) <= limitUnits
end

--------------------------------------------------------------------------------
-- Over the limit (pure)
--------------------------------------------------------------------------------
-- Being over capacity is ALLOWED and it costs two things: nothing else can be
-- picked up, and the character moves slower. Both end the instant carried bulk
-- is back within capacity. The state is reachable in one move — taking a coat
-- off removes its capacityBonus and adds its own bulk at the same time — and
-- refusing that move would be worse, because it would let a full inventory
-- weld clothing on.

-- STRICTLY greater. Carrying exactly the limit is full, not over, and the two
-- must never be confused: one of them stops you picking anything up.
function Omerta.Inventory.IsOverloaded(usedUnits, limitUnits)
    return (tonumber(usedUnits) or 0) > (tonumber(limitUnits) or 0)
end

-- THE GATE. Every path that adds bulk to an owner asks this and nothing else.
-- Returns true, or false + the reason + whether the refusal was the overload
-- one (so a caller can word it differently for a crate than for a person).
--
-- Two refusals, deliberately distinct. "There is no room for that" invites you
-- to try something smaller; while you are overloaded nothing at all will fit,
-- however small, and a player told the wrong one of those will keep clicking.
--
-- Anything adding NO bulk passes either way, and that is what keeps an
-- overloaded man from being stuck for ever: dropping, handing over, storing
-- and eating all remain open, and every one of them is a way back under.
function Omerta.Inventory.MayReceive(usedUnits, addUnits, limitUnits)
    if (tonumber(addUnits) or 0) <= 0 then return true end
    if Omerta.Inventory.IsOverloaded(usedUnits, limitUnits) then
        return false, "you are carrying too much to pick anything else up", true
    end
    if not Omerta.Inventory.Fits(usedUnits, addUnits, limitUnits) then
        return false, "there is no room for that", false
    end
    return true
end

-- How much slower an overloaded character moves, as a multiplier. Exactly 1
-- while within the limit.
--
-- IT RAMPS RATHER THAN BEING FLAT, and that is the load-bearing choice. A flat
-- penalty makes one cigarette over the line cost precisely what a Thompson
-- over the line costs, so the whole difference between walking normally and
-- visibly labouring is one item and which way a comparison rounded — the
-- arsenal's own objection to the M1911's damage, and the reason M19's fall
-- curve keeps its break and its safe height seventeen units apart. Starting at
-- 1 exactly on the boundary also means crossing it is not an event: being a
-- hundredth of a bulk over is not a thing anybody should be able to feel.
--
-- THE FLOOR IS 0.55, chosen against the numbers already on this stack rather
-- than in the abstract. Starvation is 0.75; a limp runs 0.50 to 0.94 around
-- 0.72; modifiers MULTIPLY. At 0.55 a limping overloaded man moves at 0.40 of
-- base and a starving limping overloaded one at 0.30 — both still clear of
-- M8's MIN_SPEED_FRACTION of 0.25, so each penalty stays individually legible
-- instead of the whole stack landing on the clamp and reading as one
-- undifferentiated crawl. Much below 0.55 and the ordinary combinations sit on
-- that clamp; much above it and it is not a consequence.
--
-- THE REACH IS HALF YOUR CAPACITY AGAIN, expressed as a fraction of the limit
-- rather than an absolute bulk so it means the same thing to a man in a coat
-- as to one without. The design's own worked example — take the coat off with
-- a Thompson under it — lands about 30% over and therefore around 0.73: a
-- stagger, not a crawl. The floor is reserved for somebody who kept picking
-- things up after being told to stop.
function Omerta.Inventory.OverloadSpeedMultiplier(usedUnits, limitUnits, floor, reach)
    floor = tonumber(floor) or 1
    reach = tonumber(reach) or 0
    limitUnits = tonumber(limitUnits) or 0
    -- A limit of zero has no "how far over" to measure against; an owner with
    -- no capacity at all is not a character and is not walking anywhere.
    if limitUnits <= 0 then return 1 end

    local over = (tonumber(usedUnits) or 0) - limitUnits
    if over <= 0 then return 1 end
    if reach <= 0 then return floor end

    local depth = math.min(1, (over / limitUnits) / reach)
    return math.max(floor, 1 - depth * (1 - floor))
end

-- "4.5" — for display only; never feed this back into the arithmetic.
function Omerta.Inventory.FormatBulk(units)
    local scale = Omerta.Inventory.BULK_SCALE
    local whole = math.floor(units / scale)
    local frac = math.floor((units % scale) / 10)
    if frac == 0 then return tostring(whole) end
    return string.format("%d.%d", whole, frac)
end

--------------------------------------------------------------------------------
-- The pockets key (pure)
--------------------------------------------------------------------------------
-- C is POLLED rather than bound (cl_inventory.lua says why), and the poll has
-- to answer exactly one question per frame: open, close, or leave it alone.
--
-- That question has now been got wrong twice, both times in the same shape: a
-- window that is SINKING OUT is still a panel for a tenth of a second, and code
-- that asks "is there a window" instead of "is a window UP" gets the wrong
-- answer for that tenth of a second after every single dismissal. So the rule
-- lives here as arithmetic over a description of the window, where the headless
-- suite can pin it, rather than as three conditions in a Think hook where the
-- next person to touch it has to rediscover the distinction.
--
--   window   nil when there is no window at all, otherwise a table:
--              revealed  is it actually up? A CLOSING WINDOW COUNTS AS CLOSED.
--              looting   is it showing somebody else's pockets?
--              held      was it opened by holding the key?
--   down     is the key physically down AND allowed (not typing, not in a menu)
--   wasDown  was it, last frame
--
-- Returns "open", "close" or "none".
function Omerta.Inventory.HoldAction(window, down, wasDown)
    local pressed = down == true and wasDown ~= true
    local up = window ~= nil and window.revealed == true

    if up and window.looting then
        -- A loot plate is dismissed by a PRESS. It was opened by a search, so
        -- there was never a key held down that could let go of it — and while
        -- it is up, C does nothing else: opening your own pockets over the top
        -- of somebody's coat is the state bug 3 reported.
        return pressed and "close" or "none"
    end

    if up then
        -- Pockets are held open: up exactly while the key is down.
        if window.held and down ~= true then return "close" end
        return "none"
    end

    -- Opening is EDGE triggered, and that is load-bearing rather than tidy.
    -- The press that dismisses a loot plate is still physically down on the
    -- frame after, by which time the plate is sinking and therefore counts as
    -- closed; a level-triggered open answers that by putting the player's own
    -- pockets up in the plate's place, which reads exactly like the dismissal
    -- having failed. A fresh press is the honest signal for "now show me mine".
    return pressed and "open" or "none"
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------
-- A client is told its OWN inventory and any container it has legitimately
-- opened. Never anyone else's, and never the instance ids of items lying in
-- the world — those are addressed by entity, so an id cannot be guessed at.
--
-- The contents arrive as a begin/item.../end stream rather than one fixed-width
-- message: the schema validator has no repeat construct, and padding a message
-- out to a maximum inventory size would cost more than the extra headers.

Omerta.Net.Register("inventory.open", {
    realm = "client_to_server",
    -- 0 = my own inventory; otherwise the entity index of a container.
    schema = { { name = "target", type = "uint", bits = 16 } },
    rate = { burst = 6, per = 5 },
    handler = function(ply, payload)
        Omerta.Inventory.Internal.HandleOpen(ply, payload.target)
    end,
})

Omerta.Net.Register("inventory.begin", {
    realm = "server_to_client",
    schema = {
        { name = "container",  type = "uint", bits = 16 },
        -- What the second window is called — "Crate", "Body". Display only;
        -- it carries nothing the client could not already see by looking.
        { name = "label",      type = "string", maxlen = 24 },
        { name = "count",      type = "uint", bits = 8 },
        { name = "bulk_used",  type = "uint", bits = 24 },
        { name = "bulk_limit", type = "uint", bits = 24 },
    },
    handler = function(payload)
        Omerta.Inventory.Internal.BeginStream(payload)
    end,
})

Omerta.Net.Register("inventory.item", {
    realm = "server_to_client",
    schema = {
        { name = "instance", type = "uint", bits = 32 },
        { name = "def",      type = "uint", bits = 12 },
        { name = "quantity", type = "uint", bits = 16 },
        { name = "slot",     type = "uint", bits = 4 },  -- 0 = not equipped
        { name = "where",    type = "uint", bits = 2 },  -- 1 = mine, 2 = container
    },
    handler = function(payload)
        Omerta.Inventory.Internal.StreamItem(payload)
    end,
})

Omerta.Net.Register("inventory.end", {
    realm = "server_to_client",
    schema = { { name = "container", type = "uint", bits = 16 } },
    handler = function(payload)
        Omerta.Inventory.Internal.EndStream(payload)
    end,
})

Omerta.Net.Register("inventory.action", {
    realm = "client_to_server",
    schema = {
        { name = "action",   type = "uint", bits = 4 },
        { name = "instance", type = "uint", bits = 32 },
        { name = "target",   type = "uint", bits = 16 }, -- container entity, or 0
        { name = "quantity", type = "uint", bits = 16 }, -- 0 = the whole stack
    },
    rate = { burst = 10, per = 5 },
    handler = function(ply, payload)
        Omerta.Inventory.Internal.HandleAction(ply, payload)
    end,
})
