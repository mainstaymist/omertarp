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

suite("module.planincludes")

-- Regression: file.Find returns nil (not an empty table) when a path does not
-- resolve — notably in the client realm. This used to reach table.sort and
-- crash the boot.
check("nil and empty listings produce an empty plan", function()
    local plan = assert(Omerta.Module.PlanIncludes("base", "demo", nil))
    assert(#plan == 0, "expected empty plan, got " .. #plan)
    plan = assert(Omerta.Module.PlanIncludes("base", "demo", {}))
    assert(#plan == 0, "expected empty plan, got " .. #plan)
end)

check("realm prefixes route correctly", function()
    local plan = assert(Omerta.Module.PlanIncludes("base", "demo", {
        "sh_a.lua", "sv_b.lua", "cl_c.lua",
    }))
    local byFile = {}
    for _, e in ipairs(plan) do byFile[e.file] = e end
    assert(byFile["sh_a.lua"].realm == "shared")
    assert(byFile["sv_b.lua"].realm == "server")
    assert(byFile["cl_c.lua"].realm == "client")
    assert(byFile["sh_a.lua"].path == "base/demo/sh_a.lua", byFile["sh_a.lua"].path)
end)

check("unprefixed files are rejected by name", function()
    local plan, why = Omerta.Module.PlanIncludes("base", "demo", { "sh_ok.lua", "rogue.lua" })
    assert(plan == nil, "expected rejection")
    assert(why:find("rogue.lua", 1, true), why)
    assert(why:find("realm prefix", 1, true), why)
end)

check("ordering is deterministic regardless of input order", function()
    local a = assert(Omerta.Module.PlanIncludes("base", "demo", { "sh_z.lua", "sh_a.lua", "cl_m.lua" }))
    local b = assert(Omerta.Module.PlanIncludes("base", "demo", { "cl_m.lua", "sh_a.lua", "sh_z.lua" }))
    for i = 1, #a do
        assert(a[i].file == b[i].file, "order differs at " .. i)
    end
    assert(a[1].file == "cl_m.lua" and a[2].file == "sh_a.lua" and a[3].file == "sh_z.lua",
        a[1].file .. "," .. a[2].file .. "," .. a[3].file)
end)
