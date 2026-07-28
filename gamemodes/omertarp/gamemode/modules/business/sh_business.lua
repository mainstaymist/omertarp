-- Businesses: the rooms everything else happens in.
--
-- A business is an owned, located, named thing with a till you can rob and a
-- stock room you can empty. Types are definitions in code, like items and
-- institutions, because what a speakeasy *is* belongs in version control.

Omerta.Module.Register({
    name = "business",
    depends = { "organizations", "treasury", "inventory", "chat" },
})

Omerta.Business = Omerta.Business or {}
Omerta.Business.Internal = Omerta.Business.Internal or {}

-- Container ids, namespaced away from M11's treasuries and from anything a
-- later system allocates by hand.
Omerta.Business.TILL_BASE = 2000000
Omerta.Business.STOCK_BASE = 3000000

function Omerta.Business.TillId(businessId) return Omerta.Business.TILL_BASE + businessId end
function Omerta.Business.StockId(businessId) return Omerta.Business.STOCK_BASE + businessId end

function Omerta.Business.OfContainer(containerId)
    if containerId > Omerta.Business.STOCK_BASE then
        return containerId - Omerta.Business.STOCK_BASE, "stock"
    end
    if containerId > Omerta.Business.TILL_BASE then
        return containerId - Omerta.Business.TILL_BASE, "till"
    end
    return nil
end

Omerta.Business.ROLE = {
    OWNER   = "owner",
    MANAGER = "manager",
    STAFF   = "staff",
}

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

local types = {}
local ordered = nil

function Omerta.Business.ValidateType(key, def)
    if type(key) ~= "string" or not key:find("^[a-z0-9_]+$") then
        return false, "business type '" .. tostring(key) .. "' must be lowercase [a-z0-9_]"
    end
    if type(def) ~= "table" then return false, "type '" .. key .. "' needs a definition" end
    if type(def.name) ~= "string" or def.name == "" then
        return false, "type '" .. key .. "' needs a name"
    end
    if def.tillCapacity ~= nil and (type(def.tillCapacity) ~= "number" or def.tillCapacity <= 0) then
        return false, "type '" .. key .. "' has a bad till capacity"
    end
    for _, entry in ipairs(def.sells or {}) do
        if not Omerta.Items.Get(entry.item) then
            return false, string.format("type '%s' sells unknown item '%s'", key, tostring(entry.item))
        end
        if type(entry.price) ~= "number" or entry.price <= 0
                or entry.price % Omerta.Money.SMALLEST ~= 0 then
            return false, string.format("type '%s' prices '%s' in coins that do not exist",
                key, tostring(entry.item))
        end
    end
    return true
end

function Omerta.Business.DefineType(key, def)
    local ok, why = Omerta.Business.ValidateType(key, def)
    if not ok then error(why, 2) end
    if types[key] then error("business type '" .. key .. "' defined twice", 2) end

    def.key = key
    def.sells = def.sells or {}
    def.tillCapacity = def.tillCapacity or 400
    def.stockCapacity = def.stockCapacity or 1200
    def.order = def.order or 100
    types[key] = def
    ordered = nil
    return def
end

function Omerta.Business.GetType(key) return types[key] end

function Omerta.Business.GetTypes()
    if ordered then return ordered end
    ordered = {}
    for _, def in pairs(types) do ordered[#ordered + 1] = def end
    table.sort(ordered, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)
    return ordered
end

--------------------------------------------------------------------------------
-- Ownership (pure)
--------------------------------------------------------------------------------

-- Exactly one owner. "Who owns this" having two answers is how access control
-- quietly stops working, so it is refused at the point of creation rather than
-- resolved by precedence later.
-- Returns true, or false + reason.
function Omerta.Business.Internal.ValidateOwner(organizationId, characterId)
    if organizationId and characterId then
        return false, "a business is owned by an organization or a person, never both"
    end
    if not organizationId and not characterId then
        return false, "a business needs an owner"
    end
    return true
end

-- What this character may do here. Pure over its inputs so the whole table is
-- testable without a server.
--   membership — the character's organization membership row, or nil
--   staffRole  — their row in this business's roster, or nil
-- Returns "owner" | "manager" | "staff" | nil.
function Omerta.Business.Internal.RoleOf(business, characterId, membership, staffRole)
    if business.owner_character_id and business.owner_character_id == characterId then
        return Omerta.Business.ROLE.OWNER
    end
    if business.owner_organization_id and membership
            and membership.organization_id == business.owner_organization_id then
        -- Owning the place is not the same as running it: a soldier in the
        -- family that owns a bar is not automatically behind its counter.
        -- Anything above the shop floor needs the treasury permission, which
        -- is already how M10 says "this person handles our money".
        if membership.canHandleMoney then return Omerta.Business.ROLE.MANAGER end
        return staffRole and Omerta.Business.ROLE.STAFF or nil
    end
    return staffRole or nil
end

function Omerta.Business.Internal.MaySeeTill(role)
    return role == Omerta.Business.ROLE.OWNER or role == Omerta.Business.ROLE.MANAGER
end

function Omerta.Business.Internal.MayServe(role)
    return role ~= nil
end

function Omerta.Business.Internal.MayHire(role)
    return role == Omerta.Business.ROLE.OWNER or role == Omerta.Business.ROLE.MANAGER
end

--------------------------------------------------------------------------------
-- Offline protection (Q-12, D-030)
--------------------------------------------------------------------------------

-- Premises are live only while somebody from the OWNING SIDE is online — not
-- present, online. A family with nobody logged in cannot be forced; a family
-- with three people logged in is a target whether or not any of them is
-- standing in the room.
--
-- This rewards presence rather than punishing absence, and it puts a person on
-- the other end of every raid. M13 exposes the rule and M14 is where forced
-- entry actually consults it; the police warrant path (M17) is exempt by
-- design, because that is what a warrant is.
--
--   onlineOrganizationIds — set of organization ids with a connected member
--   onlineCharacterIds    — set of connected character ids
function Omerta.Business.Internal.IsForceable(business, onlineOrganizationIds, onlineCharacterIds)
    if business.owner_organization_id then
        return onlineOrganizationIds[business.owner_organization_id] == true
    end
    if business.owner_character_id then
        return onlineCharacterIds[business.owner_character_id] == true
    end
    return false
end

--------------------------------------------------------------------------------
-- Trade (pure)
--------------------------------------------------------------------------------

-- What a type sells, priced. Returns the entry, or nil.
function Omerta.Business.Internal.PriceOf(typeDef, itemId)
    for _, entry in ipairs(typeDef.sells or {}) do
        if entry.item == itemId then return entry end
    end
    return nil
end

-- Whether a sale can go ahead, given what is in stock and what the customer
-- has. Returns true, or false + reason.
function Omerta.Business.Internal.CanSell(entry, quantity, inStock, customerCents, isOpen)
    if not entry then return false, "that is not on the menu" end
    if not isOpen then return false, "the place is closed" end
    if type(quantity) ~= "number" or quantity % 1 ~= 0 or quantity < 1 or quantity > 20 then
        return false, "that is not a quantity"
    end
    if inStock < quantity then
        return false, inStock == 0 and "there is none left" or ("only " .. inStock .. " left")
    end
    if customerCents < entry.price * quantity then return false, "you cannot afford that" end
    return true
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------

Omerta.Net.Register("business.open", {
    realm = "client_to_server",
    schema = { { name = "business", type = "uint", bits = 16 } }, -- entity index
    rate = { burst = 6, per = 5 },
    handler = function(ply, payload)
        Omerta.Business.Internal.HandleOpen(ply, payload.business)
    end,
})

Omerta.Net.Register("business.state", {
    realm = "server_to_client",
    schema = {
        { name = "business", type = "uint", bits = 24 },
        { name = "name",     type = "string", maxlen = 64 },
        { name = "role",     type = "uint", bits = 3 },  -- 0 customer, 1 staff, 2 manager, 3 owner
        { name = "is_open",  type = "bool" },
        { name = "till",     type = "uint", bits = 32 }, -- 0 unless you may see it
        { name = "staffed",  type = "bool" },
    },
    handler = function(payload)
        hook.Run("Omerta.BusinessState", payload)
    end,
})

Omerta.Net.Register("business.menu", {
    realm = "server_to_client",
    schema = {
        { name = "item",  type = "uint", bits = 12 },  -- item definition index
        { name = "price", type = "uint", bits = 32 },
        { name = "stock", type = "uint", bits = 16 },
        { name = "last",  type = "bool" },
    },
    handler = function(payload)
        hook.Run("Omerta.BusinessMenu", payload)
    end,
})

Omerta.Net.Register("business.buy", {
    realm = "client_to_server",
    schema = {
        { name = "item",     type = "uint", bits = 12 },
        { name = "quantity", type = "uint", bits = 8 },
    },
    rate = { burst = 8, per = 6 },
    handler = function(ply, payload)
        Omerta.Business.Internal.HandleBuy(ply, payload.item, payload.quantity)
    end,
})

Omerta.Net.Register("business.action", {
    realm = "client_to_server",
    schema = {
        { name = "action", type = "uint", bits = 4 },  -- 1 open/close, 2 collect, 3 listen
        { name = "target", type = "uint", bits = 16 }, -- a player, for hiring
    },
    rate = { burst = 8, per = 6 },
    handler = function(ply, payload)
        Omerta.Business.Internal.HandleAction(ply, payload.action, payload.target)
    end,
})

Omerta.Business.ACTION = { TOGGLE = 1, COLLECT = 2, LISTEN = 3, HIRE = 4, PLANT = 5 }
