-- Small pure utilities used by the core. Grown on demand only — no speculative
-- helpers. Everything here must run under plain Lua 5.1 (no engine calls) so
-- the headless test suite can exercise it.
--
-- ResolveModel is the one exception, and it takes an injectable validator so
-- that its logic is still covered headlessly; the engine call sits behind
-- Omerta.InEngine.

Omerta.Util = {}

--------------------------------------------------------------------------------
-- Model paths
--------------------------------------------------------------------------------
-- A model path is a string that either names a file the client has or does not,
-- and nothing in this repository can tell which — the content lives in the
-- game, not the source tree. A wrong one produces "Model missing" and an
-- invisible prop, which is a bad way to find out.
--
-- So every declared model goes through here: a list of candidates is tried in
-- order, the first one that actually exists wins, and a path that exists
-- nowhere degrades to a prop that certainly does, loudly.

-- Present in every Half-Life 2 install, which is the floor GMod guarantees.
Omerta.Util.FALLBACK_MODEL = "models/props_junk/wood_crate001a.mdl"

local warnedModels = {}

-- candidates may be a single path or an array of them, best first.
-- `isValid` is for the tests; in the engine it defaults to util.IsValidModel.
function Omerta.Util.ResolveModel(candidates, fallback, isValid)
    if type(candidates) == "string" then candidates = { candidates } end
    candidates = candidates or {}
    fallback = fallback or Omerta.Util.FALLBACK_MODEL

    if not isValid then
        -- Headless: there is no content to check against, so the declared
        -- first choice is taken at face value and the tests drive the rest.
        if not Omerta.InEngine then return candidates[1] or fallback end
        isValid = util.IsValidModel
    end

    for _, path in ipairs(candidates) do
        if path and isValid(path) then return path end
    end

    local named = candidates[1] and tostring(candidates[1]) or "(none declared)"
    if not warnedModels[named] then
        warnedModels[named] = true
        Omerta.Log.Warn("model", "'%s' does not exist — falling back to %s", named, fallback)
    end
    return fallback
end

--------------------------------------------------------------------------------
-- Deterministic serialization (for log/audit lines).
-- Keys are emitted in sorted order so identical tables always produce identical
-- strings. Depth-capped; not a persistence format — human-readable output only.
--------------------------------------------------------------------------------

local MAX_DEPTH = 6

local function serializeValue(v, depth)
    local t = type(v)
    if t == "string" then
        return string.format("%q", v)
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        if depth >= MAX_DEPTH then return "{...}" end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = tostring(k) .. "=" .. serializeValue(v[k], depth + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return "<" .. t .. ">"
end

function Omerta.Util.Serialize(value)
    return serializeValue(value, 0)
end

--------------------------------------------------------------------------------
-- Topological sort (module dependency ordering).
-- names:  array of node names (iteration order is the tiebreaker, so pass it
--         sorted for deterministic results)
-- depsOf: function(name) -> array of dependency names (may be nil/empty)
-- Returns ordered array, or nil + error message (missing dependency / cycle).
--------------------------------------------------------------------------------

function Omerta.Util.TopoSort(names, depsOf)
    local known = {}
    for _, n in ipairs(names) do known[n] = true end

    local order, state = {}, {} -- state: nil = unvisited, 1 = visiting, 2 = done
    local err

    local function visit(name, chain)
        if state[name] == 2 then return true end
        if state[name] == 1 then
            err = "circular dependency: " .. table.concat(chain, " -> ") .. " -> " .. name
            return false
        end
        state[name] = 1
        chain[#chain + 1] = name
        for _, dep in ipairs(depsOf(name) or {}) do
            if not known[dep] then
                err = string.format("'%s' depends on unknown module '%s'", name, dep)
                return false
            end
            if not visit(dep, chain) then return false end
        end
        chain[#chain] = nil
        state[name] = 2
        order[#order + 1] = name
        return true
    end

    for _, n in ipairs(names) do
        if not visit(n, {}) then return nil, err end
    end
    return order
end

--------------------------------------------------------------------------------
-- Token bucket (net-message rate limiting).
-- Pure: the caller supplies the current time, so tests control the clock and
-- the engine passes CurTime().
--------------------------------------------------------------------------------

function Omerta.Util.NewTokenBucket(burst, perSeconds)
    return {
        tokens = burst,
        burst = burst,
        rate = burst / perSeconds, -- tokens regained per second
        last = nil,
    }
end

-- Consumes one token if available. Returns true when the action is allowed.
function Omerta.Util.TokenBucketAllow(bucket, now)
    if bucket.last then
        bucket.tokens = math.min(bucket.burst, bucket.tokens + (now - bucket.last) * bucket.rate)
    end
    bucket.last = now
    if bucket.tokens >= 1 then
        bucket.tokens = bucket.tokens - 1
        return true
    end
    return false
end
