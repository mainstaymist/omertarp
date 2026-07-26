suite("module")

-- The module registry is global state; each check boots from scratch.

check("lifecycle runs in dependency order", function()
    ReloadCore()
    local calls = {}
    Omerta.Module.Register({
        name = "beta",
        depends = { "alpha" },
        OnLoad = function() calls[#calls + 1] = "load:beta" end,
        OnEnable = function() calls[#calls + 1] = "enable:beta" end,
    })
    Omerta.Module.Register({
        name = "alpha",
        OnLoad = function() calls[#calls + 1] = "load:alpha" end,
        OnEnable = function() calls[#calls + 1] = "enable:alpha" end,
    })
    Omerta.Module.FinishLoading()
    Omerta.Module.EnableAll()
    local got = table.concat(calls, ",")
    assert(got == "load:alpha,load:beta,enable:alpha,enable:beta", got)
end)

check("enable is idempotent and reload reaches modules", function()
    ReloadCore()
    local enables, reloads = 0, 0
    Omerta.Module.Register({
        name = "solo",
        OnEnable = function() enables = enables + 1 end,
        OnReload = function() reloads = reloads + 1 end,
    })
    Omerta.Module.FinishLoading()
    Omerta.Module.EnableAll()
    Omerta.Module.EnableAll()
    Omerta.Module.ReloadAll()
    assert(enables == 1, "OnEnable ran " .. enables .. " times")
    assert(reloads == 1, "OnReload ran " .. reloads .. " times")
end)

expectError("duplicate registration errors", "registered twice", function()
    ReloadCore()
    Omerta.Module.Register({ name = "twice" })
    Omerta.Module.Register({ name = "twice" })
end)

expectError("circular dependencies fail loading", "circular", function()
    ReloadCore()
    Omerta.Module.Register({ name = "x", depends = { "y" } })
    Omerta.Module.Register({ name = "y", depends = { "x" } })
    Omerta.Module.FinishLoading()
end)

expectError("missing dependencies fail loading", "unknown module", function()
    ReloadCore()
    Omerta.Module.Register({ name = "lonely", depends = { "nobody" } })
    Omerta.Module.FinishLoading()
end)

expectError("a module failing OnLoad fails the boot", "failed in OnLoad", function()
    ReloadCore()
    Omerta.Module.Register({
        name = "broken",
        OnLoad = function() error("kaboom") end,
    })
    Omerta.Module.FinishLoading()
end)
