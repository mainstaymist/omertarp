suite("util.serialize")

check("deterministic key order", function()
    local a = Omerta.Util.Serialize({ b = 1, a = 2, c = { z = true, y = "s" } })
    local b = Omerta.Util.Serialize({ c = { y = "s", z = true }, a = 2, b = 1 })
    assert(a == b, a .. " ~= " .. b)
    assert(a == '{a=2, b=1, c={y="s", z=true}}', "unexpected output: " .. a)
end)

check("depth cap does not recurse forever", function()
    local t = {}
    t.self = t
    local s = Omerta.Util.Serialize(t)
    assert(s:find("{...}", 1, true), "expected depth cap marker in: " .. s)
end)

suite("util.toposort")

check("orders dependencies first", function()
    local deps = { a = { "b" }, b = { "c" }, c = {} }
    local order = assert(Omerta.Util.TopoSort({ "a", "b", "c" }, function(n) return deps[n] end))
    local pos = {}
    for i, n in ipairs(order) do pos[n] = i end
    assert(pos.c < pos.b and pos.b < pos.a, table.concat(order, ","))
end)

check("detects cycles", function()
    local deps = { a = { "b" }, b = { "a" } }
    local order, err = Omerta.Util.TopoSort({ "a", "b" }, function(n) return deps[n] end)
    assert(order == nil and err:find("circular"), tostring(err))
end)

check("detects missing dependencies", function()
    local order, err = Omerta.Util.TopoSort({ "a" }, function() return { "ghost" } end)
    assert(order == nil and err:find("unknown module"), tostring(err))
end)

suite("util.tokenbucket")

check("allows burst then throttles", function()
    local b = Omerta.Util.NewTokenBucket(3, 3)
    assert(Omerta.Util.TokenBucketAllow(b, 0.0))
    assert(Omerta.Util.TokenBucketAllow(b, 0.1))
    assert(Omerta.Util.TokenBucketAllow(b, 0.2))
    assert(not Omerta.Util.TokenBucketAllow(b, 0.3), "burst should be spent")
end)

check("refills over time", function()
    local b = Omerta.Util.NewTokenBucket(2, 2) -- 1 token/second
    assert(Omerta.Util.TokenBucketAllow(b, 0))
    assert(Omerta.Util.TokenBucketAllow(b, 0))
    assert(not Omerta.Util.TokenBucketAllow(b, 0))
    assert(Omerta.Util.TokenBucketAllow(b, 1.5), "should regain a token after 1.5s")
    assert(not Omerta.Util.TokenBucketAllow(b, 1.5))
end)

check("never exceeds burst after a long idle", function()
    local b = Omerta.Util.NewTokenBucket(2, 2)
    assert(Omerta.Util.TokenBucketAllow(b, 0))
    assert(Omerta.Util.TokenBucketAllow(b, 1000))
    assert(Omerta.Util.TokenBucketAllow(b, 1000))
    assert(not Omerta.Util.TokenBucketAllow(b, 1000), "refill must cap at burst")
end)

--------------------------------------------------------------------------------
suite("util.models")
--------------------------------------------------------------------------------

-- A model path names a file the client either has or does not, and nothing in
-- this repository can tell which — the content lives in the game. A wrong one
-- produced an invisible counter in M13, which is a bad way to find out.
check("the first candidate that actually exists wins", function()
    local R = Omerta.Util.ResolveModel
    local exists = { ["models/b.mdl"] = true, ["models/c.mdl"] = true }
    local function isValid(path) return exists[path] == true end

    assert(R({ "models/b.mdl" }, nil, isValid) == "models/b.mdl")
    -- The first choice is missing, so the next real one is taken.
    assert(R({ "models/a.mdl", "models/b.mdl" }, nil, isValid) == "models/b.mdl")
    assert(R({ "models/a.mdl", "models/c.mdl", "models/b.mdl" }, nil, isValid) == "models/c.mdl",
        "order is a preference, not a search")
end)

check("a path that exists nowhere degrades to one that does", function()
    local R = Omerta.Util.ResolveModel
    local function isValid() return false end

    assert(R({ "models/gone.mdl" }, nil, isValid) == Omerta.Util.FALLBACK_MODEL)
    assert(R({ "models/gone.mdl" }, "models/mine.mdl", isValid) == "models/mine.mdl",
        "an explicit fallback wins over the default")
    assert(R({}, nil, isValid) == Omerta.Util.FALLBACK_MODEL, "nothing declared")
    assert(R(nil, nil, isValid) == Omerta.Util.FALLBACK_MODEL, "nil declared")
end)

check("a single path is accepted as well as a list", function()
    local R = Omerta.Util.ResolveModel
    local function isValid(path) return path == "models/ok.mdl" end
    assert(R("models/ok.mdl", nil, isValid) == "models/ok.mdl",
        "callers with one model should not have to wrap it")
    assert(R("models/no.mdl", nil, isValid) == Omerta.Util.FALLBACK_MODEL)
end)
