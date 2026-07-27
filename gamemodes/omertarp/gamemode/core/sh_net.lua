-- Net-message registry: the only way this gamemode sends or receives network
-- messages. The wrapper makes the security posture structural:
--
--   * every message is declared with a direction, a typed payload schema, and
--     (for client->server) a rate limit — there is no raw net.Receive path in
--     module code;
--   * client->server payloads are validated field-by-field BEFORE the handler
--     runs; failing messages are dropped and audited, never partially applied;
--   * server->client sends require an explicit target list. There is no
--     broadcast convenience on purpose: under the information philosophy
--     almost nothing should ever go to everyone (Tech §2), so "send to all"
--     must be written out by hand at the call site.
--
-- Schema fields are ordered arrays (the wire format): supported types are
--   bool | uint {bits} | int {bits} | float {min?, max?} | string {maxlen}
-- uint/int may also carry min/max for range validation on read.

Omerta.Net = {}

local PREFIX = "omerta/"
local DEFAULT_RATE = { burst = 8, per = 4 } -- 8 messages, refilled over 4s

local defs = {}
local buckets = {} -- [steamid64][name] = token bucket (server realm)

local FIELD_TYPES = { bool = true, uint = true, int = true, float = true, string = true }

-- Pure schema-declaration validation, exposed for the headless tests.
-- Returns true, or false + reason.
function Omerta.Net.ValidateSchema(schema)
    if type(schema) ~= "table" then return false, "schema must be a table" end
    local seen = {}
    for i, field in ipairs(schema) do
        if type(field.name) ~= "string" or field.name == "" then
            return false, "field " .. i .. " has no name"
        end
        if seen[field.name] then
            return false, "duplicate field '" .. field.name .. "'"
        end
        seen[field.name] = true
        if not FIELD_TYPES[field.type] then
            return false, "field '" .. field.name .. "' has invalid type '" .. tostring(field.type) .. "'"
        end
        if (field.type == "uint" or field.type == "int") then
            local bits = field.bits
            if type(bits) ~= "number" or bits < 1 or bits > 32 then
                return false, "field '" .. field.name .. "' needs bits in 1..32"
            end
        end
        if field.type == "string" then
            if type(field.maxlen) ~= "number" or field.maxlen < 1 then
                return false, "field '" .. field.name .. "' needs a positive maxlen"
            end
        end
    end
    return true
end

-- Pure per-field value validation (write- and read-side), exposed for tests.
-- Returns true, or false + reason.
function Omerta.Net.ValidateValue(field, value)
    if field.type == "bool" then
        if type(value) ~= "boolean" then return false, "expected boolean" end
    elseif field.type == "string" then
        if type(value) ~= "string" then return false, "expected string" end
        if #value > field.maxlen then return false, "string exceeds maxlen " .. field.maxlen end
    else
        if type(value) ~= "number" then return false, "expected number" end
        if field.type ~= "float" and value % 1 ~= 0 then return false, "expected integer" end
        if field.type == "uint" and value < 0 then return false, "expected unsigned" end
        if field.min and value < field.min then return false, "below minimum " .. field.min end
        if field.max and value > field.max then return false, "above maximum " .. field.max end
    end
    return true
end

-- Validation is a SEPARATE pass, run before net.Start rather than during the
-- write. Erroring halfway through a started message leaves it open, and the
-- engine then discards the next unrelated message to make room — so one bad
-- payload used to break a second system that had done nothing wrong.
-- Write-side failures are OUR bugs, so this still errors at the call site.
local function assertPayload(def, payload)
    payload = payload or {}
    for _, field in ipairs(def.schema) do
        local ok, why = Omerta.Net.ValidateValue(field, payload[field.name])
        if not ok then
            error(string.format("net '%s': bad value for '%s': %s", def.name, field.name, why), 4)
        end
    end
end

local function writePayload(def, payload)
    payload = payload or {}
    for _, field in ipairs(def.schema) do
        local value = payload[field.name]
        if field.type == "bool" then net.WriteBool(value)
        elseif field.type == "uint" then net.WriteUInt(value, field.bits)
        elseif field.type == "int" then net.WriteInt(value, field.bits)
        elseif field.type == "float" then net.WriteFloat(value)
        elseif field.type == "string" then net.WriteString(value)
        end
    end
end

-- Read-side failures are the REMOTE side's problem: return nil + reason so the
-- caller can drop and audit instead of erroring.
local function readPayload(def)
    local payload = {}
    for _, field in ipairs(def.schema) do
        local value
        if field.type == "bool" then value = net.ReadBool()
        elseif field.type == "uint" then value = net.ReadUInt(field.bits)
        elseif field.type == "int" then value = net.ReadInt(field.bits)
        elseif field.type == "float" then value = net.ReadFloat()
        elseif field.type == "string" then value = net.ReadString()
        end
        local ok, why = Omerta.Net.ValidateValue(field, value)
        if not ok then
            return nil, string.format("field '%s': %s", field.name, why)
        end
        payload[field.name] = value
    end
    return payload
end

local function serverReceive(def, ply)
    local id = ply:SteamID64() or "unknown"
    buckets[id] = buckets[id] or {}
    local bucket = buckets[id][def.name]
    if not bucket then
        bucket = Omerta.Util.NewTokenBucket(def.rate.burst, def.rate.per)
        buckets[id][def.name] = bucket
    end
    if not Omerta.Util.TokenBucketAllow(bucket, CurTime()) then
        Omerta.Log.Audit("net.ratelimit", { actor = id, data = { message = def.name } })
        return
    end

    local payload, why = readPayload(def)
    if not payload then
        Omerta.Log.Audit("net.reject", { actor = id, data = { message = def.name, reason = why } })
        return
    end

    local ok, err = pcall(def.handler, ply, payload)
    if not ok then
        Omerta.Log.Error("net", "handler for '%s' failed: %s", def.name, tostring(err))
    end
end

local function clientReceive(def)
    local payload, why = readPayload(def)
    if not payload then
        Omerta.Log.Warn("net", "dropped malformed '%s': %s", def.name, why)
        return
    end
    local ok, err = pcall(def.handler, payload)
    if not ok then
        Omerta.Log.Error("net", "handler for '%s' failed: %s", def.name, tostring(err))
    end
end

function Omerta.Net.Register(name, def)
    if type(name) ~= "string" or not name:find("^[a-z0-9_%.]+$") then
        error("net message name '" .. tostring(name) .. "' must be lowercase [a-z0-9_.]", 2)
    end
    if defs[name] then
        error("net message '" .. name .. "' registered twice", 2)
    end
    if def.realm ~= "client_to_server" and def.realm ~= "server_to_client" then
        error("net message '" .. name .. "' needs realm 'client_to_server' or 'server_to_client'", 2)
    end
    local ok, why = Omerta.Net.ValidateSchema(def.schema or {})
    if not ok then
        error("net message '" .. name .. "' has a bad schema: " .. why, 2)
    end
    if type(def.handler) ~= "function" then
        error("net message '" .. name .. "' needs a handler function", 2)
    end

    defs[name] = {
        name = name,
        realm = def.realm,
        schema = def.schema or {},
        rate = def.rate or DEFAULT_RATE,
        handler = def.handler,
    }

    if not Omerta.InEngine then return end

    if SERVER then
        util.AddNetworkString(PREFIX .. name)
        if def.realm == "client_to_server" then
            net.Receive(PREFIX .. name, function(_, ply) serverReceive(defs[name], ply) end)
        end
    elseif def.realm == "server_to_client" then
        net.Receive(PREFIX .. name, function() clientReceive(defs[name]) end)
    end
end

-- Server -> specific client(s). `targets` is a Player or an array of Players,
-- and is required — see the header comment for why there is no broadcast.
function Omerta.Net.Send(name, payload, targets)
    Omerta.AssertServer("Omerta.Net.Send")
    local def = defs[name]
    if not def or def.realm ~= "server_to_client" then
        error("'" .. tostring(name) .. "' is not a registered server_to_client message", 2)
    end
    if targets == nil then
        error("Omerta.Net.Send requires explicit targets (no implicit broadcast)", 2)
    end
    assertPayload(def, payload)
    net.Start(PREFIX .. name)
    writePayload(def, payload)
    net.Send(targets)
end

-- Client -> server.
function Omerta.Net.Request(name, payload)
    Omerta.AssertClient("Omerta.Net.Request")
    local def = defs[name]
    if not def or def.realm ~= "client_to_server" then
        error("'" .. tostring(name) .. "' is not a registered client_to_server message", 2)
    end
    assertPayload(def, payload)
    net.Start(PREFIX .. name)
    writePayload(def, payload)
    net.SendToServer()
end

-- Read-only view of the registry, so the M6 leak audit can inspect what we
-- send without being able to alter it.
function Omerta.Net.GetRegistry()
    local out = {}
    for name, def in pairs(defs) do
        out[name] = { name = name, realm = def.realm, schema = def.schema }
    end
    return out
end

if SERVER and Omerta.InEngine then
    hook.Add("PlayerDisconnected", "omerta.net.bucket_cleanup", function(ply)
        buckets[ply:SteamID64() or "unknown"] = nil
    end)
end
