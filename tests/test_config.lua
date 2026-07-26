suite("config")

check("defaults are returned", function()
    Omerta.Config.Define("test.number", { type = "number", default = 5, min = 1, max = 10, scope = "server" })
    assert(Omerta.Config.Get("test.number") == 5)
end)

expectError("get of unknown key errors", "unknown config key", function()
    Omerta.Config.Get("test.missing")
end)

expectError("duplicate definition errors", "defined twice", function()
    Omerta.Config.Define("test.dup", { type = "boolean", default = false })
    Omerta.Config.Define("test.dup", { type = "boolean", default = true })
end)

expectError("bad key shape errors", "must look like", function()
    Omerta.Config.Define("nodot", { type = "boolean", default = false })
end)

expectError("invalid default errors", "invalid default", function()
    Omerta.Config.Define("test.badnum", { type = "number", default = 99, min = 1, max = 10 })
end)

expectError("choices are enforced on defaults", "invalid default", function()
    Omerta.Config.Define("test.badchoice", { type = "string", default = "nope", choices = { "a", "b" } })
end)

check("overrides apply to server-scope keys", function()
    Omerta.Config.Define("test.srv", { type = "number", default = 1, scope = "server" })
    local n = Omerta.Config.ApplyOverrides({ ["test.srv"] = 7 }, "test data")
    assert(n == 1 and Omerta.Config.Get("test.srv") == 7)
end)

expectError("overrides reject unknown keys", "unknown config key", function()
    Omerta.Config.ApplyOverrides({ ["test.ghost"] = 1 }, "test data")
end)

expectError("overrides reject shared-scope keys", "shared-scope", function()
    Omerta.Config.Define("test.shared", { type = "number", default = 1, scope = "shared" })
    Omerta.Config.ApplyOverrides({ ["test.shared"] = 2 }, "test data")
end)

expectError("overrides reject wrong types", "invalid value", function()
    Omerta.Config.Define("test.typed", { type = "number", default = 1, scope = "server" })
    Omerta.Config.ApplyOverrides({ ["test.typed"] = "not a number" }, "test data")
end)

expectError("define after finalize errors", "after Finalize", function()
    Omerta.Config.Finalize()
    Omerta.Config.Define("test.late", { type = "boolean", default = false })
end)

suite("config.realms")

check("server-scope define is rejected client-side", function()
    -- Simulate the client realm for this one check.
    SERVER = false
    CLIENT = true
    ReloadCore()
    local ok, err = pcall(function()
        Omerta.Config.Define("test.secret", { type = "string", default = "x", scope = "server" })
    end)
    SERVER = true
    CLIENT = false
    ReloadCore()
    assert(not ok, "expected an error")
    assert(tostring(err):find("client realm"), tostring(err))
end)
