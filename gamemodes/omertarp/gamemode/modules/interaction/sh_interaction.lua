-- Interaction framework: target something, get the actions you may perform on
-- it, perform one. Deliberately generic — identity registers "Introduce
-- Yourself" here, and M9/M13/M14/M19/M20 will register Search, Buy, Rob,
-- Treat and Confirm Kill without this module learning anything about them.
--
-- Server authority: the client's trace only nominates a target. The server
-- re-traces, re-checks range, re-runs the predicate, and only then executes.
-- An action id the client was never offered simply fails its predicate.


Omerta.Interaction = Omerta.Interaction or {}

local MAX_OPTIONS = 8   -- also the client menu's practical limit
local MAX_RANGE = 256   -- hard ceiling; individual actions may be shorter

Omerta.Interaction.MAX_OPTIONS = MAX_OPTIONS
Omerta.Interaction.MAX_RANGE = MAX_RANGE

local registry = {}   -- id -> definition
local ordered = nil   -- cached sort of registry, invalidated on Register

-- Actions are keyed by a small integer on the wire, so the id list must be
-- identical on both realms: registration happens in shared files, and the
-- numeric index is derived from a deterministic sort of the string ids.
function Omerta.Interaction.Register(id, def)
    if type(id) ~= "string" or not id:find("^[a-z0-9_%.]+$") then
        error("interaction id '" .. tostring(id) .. "' must be lowercase [a-z0-9_.]", 2)
    end
    if registry[id] then error("interaction '" .. id .. "' registered twice", 2) end
    if type(def) ~= "table" then error("interaction '" .. id .. "' needs a definition", 2) end
    if type(def.label) ~= "string" or def.label == "" then
        error("interaction '" .. id .. "' needs a label", 2)
    end
    if type(def.range) ~= "number" or def.range <= 0 or def.range > MAX_RANGE then
        error("interaction '" .. id .. "' needs a range in 1.." .. MAX_RANGE, 2)
    end
    -- `default = true` opts an action into the TAP path: pressing E runs the
    -- first default-flagged action available, no menu. Opt-in, because "first
    -- available" would make walking past a stranger with E introduce you to
    -- them by accident — anything social or irreversible stays behind the
    -- held menu.
    if def.default ~= nil and type(def.default) ~= "boolean" then
        error("interaction '" .. id .. "' default must be a boolean", 2)
    end
    -- `describe(ply, target)` may return a richer label at offer time —
    -- "Search (empty)" on a container known to hold nothing. Falls back to
    -- the plain label on nil or error.
    if def.describe ~= nil and type(def.describe) ~= "function" then
        error("interaction '" .. id .. "' describe must be a function", 2)
    end
    def.id = id
    def.order = def.order or 100
    def.targets = def.targets or "any"
    registry[id] = def
    ordered = nil
    return def
end

function Omerta.Interaction.Get(id) return registry[id] end

-- Deterministic ordering: by `order`, then id. Both realms compute the same
-- list, so the wire only carries indices.
function Omerta.Interaction.GetOrdered()
    if ordered then return ordered end
    ordered = {}
    for _, def in pairs(registry) do ordered[#ordered + 1] = def end
    table.sort(ordered, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    for i, def in ipairs(ordered) do def.index = i end
    return ordered
end

function Omerta.Interaction.GetByIndex(index)
    local list = Omerta.Interaction.GetOrdered()
    return list[index]
end

-- Pure availability test, exposed for headless coverage.
-- Returns true, or false + reason.
function Omerta.Interaction.CanUse(def, ply, target, distance)
    if not def then return false, "unknown action" end
    if distance > def.range then return false, "too far away" end
    if def.targets == "player" and not (target.IsPlayer and target:IsPlayer()) then
        return false, "target is not a person"
    end
    if def.predicate then
        local ok, reason = def.predicate(ply, target)
        if not ok then return false, reason or "not available" end
    end
    return true
end

--------------------------------------------------------------------------------
-- Networking (registered shared: both realms need every definition)
--------------------------------------------------------------------------------

Omerta.Net.Register("interaction.query", {
    realm = "client_to_server",
    schema = { { name = "target", type = "uint", bits = 16 } },
    rate = { burst = 10, per = 5 },
    handler = function(ply, payload)
        Omerta.Interaction.Internal.SendOptions(ply, payload.target)
    end,
})

Omerta.Net.Register("interaction.options", {
    realm = "server_to_client",
    schema = {
        { name = "target", type = "uint", bits = 16 },
        { name = "count",  type = "uint", bits = 4 },
        -- Fixed-width option slots: the schema validator has no repeat
        -- construct, so unused slots carry index 0 and an empty label.
        { name = "i1", type = "uint", bits = 8 }, { name = "l1", type = "string", maxlen = 48 },
        { name = "i2", type = "uint", bits = 8 }, { name = "l2", type = "string", maxlen = 48 },
        { name = "i3", type = "uint", bits = 8 }, { name = "l3", type = "string", maxlen = 48 },
        { name = "i4", type = "uint", bits = 8 }, { name = "l4", type = "string", maxlen = 48 },
        { name = "i5", type = "uint", bits = 8 }, { name = "l5", type = "string", maxlen = 48 },
        { name = "i6", type = "uint", bits = 8 }, { name = "l6", type = "string", maxlen = 48 },
        { name = "i7", type = "uint", bits = 8 }, { name = "l7", type = "string", maxlen = 48 },
        { name = "i8", type = "uint", bits = 8 }, { name = "l8", type = "string", maxlen = 48 },
    },
    handler = function(payload)
        hook.Run("Omerta.InteractionOptions", payload)
    end,
})

Omerta.Net.Register("interaction.execute", {
    realm = "client_to_server",
    schema = {
        { name = "target", type = "uint", bits = 16 },
        { name = "action", type = "uint", bits = 8 },
    },
    rate = { burst = 5, per = 5 },
    handler = function(ply, payload)
        Omerta.Interaction.Internal.Execute(ply, payload.target, payload.action)
    end,
})

-- The tap: run whatever this target's default action is, server-decided. The
-- client never names an action, so there is nothing for a stale menu or a
-- dishonest client to smuggle through.
Omerta.Net.Register("interaction.default", {
    realm = "client_to_server",
    schema = { { name = "target", type = "uint", bits = 16 } },
    rate = { burst = 8, per = 5 },
    handler = function(ply, payload)
        Omerta.Interaction.Internal.ExecuteDefault(ply, payload.target)
    end,
})
