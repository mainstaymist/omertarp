suite("net.schema")

check("valid schema accepted", function()
    local ok, why = Omerta.Net.ValidateSchema({
        { name = "flag", type = "bool" },
        { name = "count", type = "uint", bits = 8, max = 100 },
        { name = "label", type = "string", maxlen = 32 },
    })
    assert(ok, tostring(why))
end)

check("rejects unnamed, duplicate, and untyped fields", function()
    assert(not Omerta.Net.ValidateSchema({ { type = "bool" } }))
    assert(not Omerta.Net.ValidateSchema({
        { name = "a", type = "bool" }, { name = "a", type = "bool" },
    }))
    assert(not Omerta.Net.ValidateSchema({ { name = "a", type = "vector" } }))
end)

check("rejects missing bits and maxlen", function()
    assert(not Omerta.Net.ValidateSchema({ { name = "n", type = "uint" } }))
    assert(not Omerta.Net.ValidateSchema({ { name = "n", type = "uint", bits = 64 } }))
    assert(not Omerta.Net.ValidateSchema({ { name = "s", type = "string" } }))
end)

suite("net.values")

check("type and range validation", function()
    local uintField = { name = "n", type = "uint", bits = 8, min = 1, max = 10 }
    assert(Omerta.Net.ValidateValue(uintField, 5))
    assert(not Omerta.Net.ValidateValue(uintField, 0))    -- below min
    assert(not Omerta.Net.ValidateValue(uintField, 11))   -- above max
    assert(not Omerta.Net.ValidateValue(uintField, 2.5))  -- not an integer
    assert(not Omerta.Net.ValidateValue(uintField, "5"))  -- wrong type

    local strField = { name = "s", type = "string", maxlen = 4 }
    assert(Omerta.Net.ValidateValue(strField, "abcd"))
    assert(not Omerta.Net.ValidateValue(strField, "abcde")) -- too long

    local boolField = { name = "b", type = "bool" }
    assert(Omerta.Net.ValidateValue(boolField, true))
    assert(not Omerta.Net.ValidateValue(boolField, 1))
end)

suite("net.register")

check("registration validates and stores definitions headless", function()
    Omerta.Net.Register("test.msg", {
        realm = "client_to_server",
        schema = { { name = "x", type = "uint", bits = 4 } },
        handler = function() end,
    })
end)

expectError("duplicate names rejected", "registered twice", function()
    local def = {
        realm = "client_to_server",
        schema = {},
        handler = function() end,
    }
    Omerta.Net.Register("test.dup", def)
    Omerta.Net.Register("test.dup", def)
end)

expectError("uppercase names rejected", "lowercase", function()
    Omerta.Net.Register("Test.Bad", {
        realm = "client_to_server", schema = {}, handler = function() end,
    })
end)

expectError("bad realm rejected", "needs realm", function()
    Omerta.Net.Register("test.badrealm", {
        realm = "sideways", schema = {}, handler = function() end,
    })
end)

expectError("missing handler rejected", "handler", function()
    Omerta.Net.Register("test.nohandler", {
        realm = "client_to_server", schema = {},
    })
end)
