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

function Omerta.Inventory.GetSlot(id) return slots[id] end

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

-- Total bulk of a list of { def_id = , quantity = } rows, in hundredths.
-- Rows naming an unregistered item contribute nothing rather than erroring:
-- an item removed from a later version of the gamemode must not make an
-- existing character's inventory unopenable.
function Omerta.Inventory.SumBulk(rows)
    local total = 0
    for _, row in ipairs(rows or {}) do
        total = total + Omerta.Inventory.StackBulk(Omerta.Items.Get(row.def_id), row.quantity)
    end
    return total
end

function Omerta.Inventory.Fits(usedUnits, addUnits, limitUnits)
    return (usedUnits + addUnits) <= limitUnits
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
