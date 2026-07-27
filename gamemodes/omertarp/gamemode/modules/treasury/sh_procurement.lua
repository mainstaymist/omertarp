-- Procurement: the catalogue an institution orders from.
--
-- Entries are DEFINITIONS in code, like items and ladders, because a price is
-- balance. What an entry may do is deliberately narrow: it delivers an ITEM,
-- or it runs a service function. Tech §10's guardrail — that family wealth
-- must never modify health, damage, speed or armour — is enforced here rather
-- than trusted, because it is the rule most likely to be broken by somebody in
-- a hurry two years from now.

Omerta.Module.Register({
    name = "treasury",
    -- `organizations` for the owner and the ladder, `inventory` because the
    -- safe is a container full of real money, `chat` because every refusal
    -- reaches the player as a notice.
    depends = { "organizations", "inventory", "chat" },
})

Omerta.Procurement = Omerta.Procurement or {}
Omerta.Treasury = Omerta.Treasury or {}
Omerta.Treasury.Internal = Omerta.Treasury.Internal or {}

-- Container ids for treasuries are namespaced away from anything a later
-- system might allocate by hand (M9 lets each system choose its own).
Omerta.Treasury.CONTAINER_BASE = 1000000

function Omerta.Treasury.ContainerId(organizationId)
    return Omerta.Treasury.CONTAINER_BASE + organizationId
end

function Omerta.Treasury.OrganizationOf(containerId)
    if containerId <= Omerta.Treasury.CONTAINER_BASE then return nil end
    return containerId - Omerta.Treasury.CONTAINER_BASE
end

Omerta.Procurement.CATEGORIES = {
    communications = "Communications",
    weapons        = "Weapons",
    ammunition     = "Ammunition",
    medical        = "Medical",
    disguises      = "Disguises",
    burglary       = "Burglary",
    storage        = "Storage",
    stock          = "Business Stock",
    intelligence   = "Intelligence",
    legal          = "Legal Services",
}

-- Tech §10: "Avoid directly modifying health, damage, speed, or armor through
-- family wealth." Written as a refusal rather than a comment — money buys
-- advantage through what it puts in your hands, never through a number
-- attached to your character.
local FORBIDDEN_FIELDS = {
    health = true, maxHealth = true, armor = true, armour = true,
    speed = true, runSpeed = true, walkSpeed = true, damage = true,
}

local entries = {}
local ordered = nil

-- Returns true, or false + reason. Pure; exposed for the headless suite.
function Omerta.Procurement.Validate(id, def)
    if type(id) ~= "string" or not id:find("^[a-z0-9_%.]+$") then
        return false, "procurement id '" .. tostring(id) .. "' must be lowercase [a-z0-9_.]"
    end
    if type(def) ~= "table" then return false, "entry '" .. id .. "' needs a definition" end
    if type(def.name) ~= "string" or def.name == "" then
        return false, "entry '" .. id .. "' needs a name"
    end
    if not Omerta.Procurement.CATEGORIES[def.category] then
        return false, "entry '" .. id .. "' has unknown category '" .. tostring(def.category) .. "'"
    end
    if type(def.price) ~= "number" or def.price % 1 ~= 0 or def.price <= 0 then
        return false, "entry '" .. id .. "' needs a whole positive price in cents"
    end
    if def.price % Omerta.Money.SMALLEST ~= 0 then
        return false, string.format("entry '%s' is priced at %s, which cannot be paid " ..
            "with coins in circulation", id, Omerta.Money.Format(def.price))
    end
    if def.item ~= nil and not Omerta.Items.Get(def.item) then
        return false, "entry '" .. id .. "' delivers unknown item '" .. tostring(def.item) .. "'"
    end
    if def.item == nil and type(def.onPurchase) ~= "function" then
        return false, "entry '" .. id .. "' delivers nothing and does nothing"
    end
    if def.quantity ~= nil and (type(def.quantity) ~= "number"
            or def.quantity % 1 ~= 0 or def.quantity < 1) then
        return false, "entry '" .. id .. "' has a bad quantity"
    end
    if def.orgType ~= nil and def.orgType ~= Omerta.Organizations.TYPE.FAMILY
            and def.orgType ~= Omerta.Organizations.TYPE.POLICE then
        return false, "entry '" .. id .. "' restricts to unknown organization type"
    end
    for field in pairs(FORBIDDEN_FIELDS) do
        if def[field] ~= nil then
            return false, string.format(
                "entry '%s' sets '%s' — procurement buys objects, never statistics (Tech §10)",
                id, field)
        end
    end
    return true
end

function Omerta.Procurement.Register(id, def)
    local ok, why = Omerta.Procurement.Validate(id, def)
    if not ok then error(why, 2) end
    if entries[id] then error("procurement entry '" .. id .. "' registered twice", 2) end

    def.id = id
    def.quantity = def.quantity or 1
    def.permission = def.permission or Omerta.Organizations.PERMISSIONS.TREASURY_SPEND
    def.order = def.order or 100
    entries[id] = def
    ordered = nil
    return def
end

function Omerta.Procurement.Get(id) return entries[id] end

-- Deterministic ordering, so both realms compute the same indices and the wire
-- carries a number.
function Omerta.Procurement.GetOrdered()
    if ordered then return ordered end
    ordered = {}
    for _, def in pairs(entries) do ordered[#ordered + 1] = def end
    table.sort(ordered, function(a, b)
        if a.category ~= b.category then return a.category < b.category end
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    for i, def in ipairs(ordered) do def.index = i end
    return ordered
end

function Omerta.Procurement.GetByIndex(index)
    local list = Omerta.Procurement.GetOrdered()
    return list[index]
end

-- What a given buyer may order. Pure over its inputs, so the filtering rules
-- are tested rather than inferred from a screenshot.
function Omerta.Procurement.Available(orgType, ladderId, rank)
    local out = {}
    for _, def in ipairs(Omerta.Procurement.GetOrdered()) do
        local allowed = true
        if def.orgType and def.orgType ~= orgType then allowed = false end
        if allowed and not Omerta.Organizations.Grants(ladderId, rank, def.permission) then
            allowed = false
        end
        if allowed and def.minRank and rank < def.minRank then allowed = false end
        if allowed then out[#out + 1] = def end
    end
    return out
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------
-- Everything below goes only to a member standing at their own safe, and only
-- as far as their rank permits: a Soldier is never told what the family is
-- worth.

Omerta.Net.Register("treasury.open", {
    realm = "client_to_server",
    schema = {},
    rate = { burst = 6, per = 5 },
    handler = function(ply)
        Omerta.Treasury.Internal.HandleOpen(ply)
    end,
})

Omerta.Net.Register("treasury.state", {
    realm = "server_to_client",
    schema = {
        { name = "counted",   type = "uint", bits = 32 },  -- cash actually present
        -- SIGNED, and it has to be: money that enters the safe without being
        -- written down and is then spent drives the books negative. That is
        -- not a corrupt state, it is the discrepancy D-024 exists to show.
        { name = "ledger",    type = "int",  bits = 32 },  -- what the books say
        { name = "limit",     type = "uint", bits = 32 },  -- yours; 0 means none allowed
        { name = "unlimited", type = "bool" },
        { name = "may_view",  type = "bool" },
    },
    handler = function(payload)
        hook.Run("Omerta.TreasuryState", payload)
    end,
})

Omerta.Net.Register("treasury.action", {
    realm = "client_to_server",
    schema = {
        { name = "action", type = "uint", bits = 3 },   -- 1 deposit, 2 withdraw
        { name = "amount", type = "uint", bits = 32 },  -- cents
    },
    rate = { burst = 8, per = 10 },
    handler = function(ply, payload)
        Omerta.Treasury.Internal.HandleAction(ply, payload)
    end,
})

Omerta.Net.Register("procure.entry", {
    realm = "server_to_client",
    schema = {
        { name = "entry", type = "uint", bits = 12 },
        { name = "last",  type = "bool" },
    },
    handler = function(payload)
        hook.Run("Omerta.ProcurementEntry", payload)
    end,
})

Omerta.Net.Register("procure.order", {
    realm = "client_to_server",
    schema = {
        { name = "entry",    type = "uint", bits = 12 },
        { name = "quantity", type = "uint", bits = 8 },
    },
    rate = { burst = 6, per = 10 },
    handler = function(ply, payload)
        Omerta.Procurement.Internal.HandleOrder(ply, payload.entry, payload.quantity)
    end,
})

Omerta.Net.Register("treasury.line", {
    realm = "server_to_client",
    schema = {
        { name = "at",       type = "uint", bits = 32 },
        { name = "delta",    type = "int",  bits = 32 },
        { name = "balance",  type = "int",  bits = 32 },  -- signed, as above
        { name = "who",      type = "string", maxlen = 56 },
        { name = "approver", type = "string", maxlen = 56 },
        { name = "reason",   type = "string", maxlen = 64 },
        { name = "last",     type = "bool" },
    },
    handler = function(payload)
        hook.Run("Omerta.TreasuryLine", payload)
    end,
})

Omerta.Procurement.Internal = Omerta.Procurement.Internal or {}
