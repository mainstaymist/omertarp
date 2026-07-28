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

-- Regression: plain alphabetical ordering put cl_ before sh_, so on the
-- client a UI file ran before the shared file defining its constants.
check("shared files load first, then realm files, deterministically", function()
    local input = { "sv_z.lua", "cl_m.lua", "sh_z.lua", "sh_a.lua", "sv_a.lua", "cl_a.lua" }
    local a = assert(Omerta.Module.PlanIncludes("base", "demo", input))
    local order = {}
    for i, e in ipairs(a) do order[i] = e.file end
    local got = table.concat(order, ",")
    assert(got == "sh_a.lua,sh_z.lua,cl_a.lua,cl_m.lua,sv_a.lua,sv_z.lua", got)

    -- Same set in a different input order yields the same plan.
    local shuffled = { "cl_m.lua", "sv_a.lua", "sh_a.lua", "sv_z.lua", "cl_a.lua", "sh_z.lua" }
    local b = assert(Omerta.Module.PlanIncludes("base", "demo", shuffled))
    for i = 1, #a do
        assert(a[i].file == b[i].file, "order differs at " .. i)
    end
end)

--------------------------------------------------------------------------------
suite("module.include_order")
--------------------------------------------------------------------------------

-- `depends` used to govern only the lifecycle while files were included by
-- directory name. That worked for eleven milestones by luck — every module
-- happened to sort after the ones it needed — and then `business` did not.

check("a registration is read out of source without running it", function()
    ReloadCore()
    local P = Omerta.Module.ParseRegistration

    local name, depends = P([[
Omerta.Module.Register({
    name = "business",
    depends = { "organizations", "treasury", "inventory", "chat" },
})
]])
    assert(name == "business", tostring(name))
    assert(#depends == 4 and depends[1] == "organizations", "depends did not parse")

    -- No dependencies at all.
    name, depends = P('Omerta.Module.Register({ name = "database", depends = {} })')
    assert(name == "database" and #depends == 0)

    -- Depends omitted entirely.
    name, depends = P('Omerta.Module.Register({ name = "solo" })')
    assert(name == "solo" and #depends == 0)
end)

check("comments inside the block cannot be mistaken for the declaration", function()
    ReloadCore()
    local name, depends = Omerta.Module.ParseRegistration([[
Omerta.Module.Register({
    name = "phone",
    -- `chat` for the voice seam. Not depends = { "nonsense" } but prose.
    depends = { "chat", "inventory" },
})
]])
    assert(name == "phone", tostring(name))
    assert(#depends == 2 and depends[1] == "chat" and depends[2] == "inventory",
        "a comment was parsed as the declaration")
end)

check("a file that registers nothing parses to nothing", function()
    ReloadCore()
    local P = Omerta.Module.ParseRegistration
    assert(P("local x = 1") == nil)
    assert(P("") == nil)
    assert(P(nil) == nil)
    -- A registration with no name is not a registration.
    assert(P('Omerta.Module.Register({ depends = { "x" } })') == nil)
end)

check("directories are ordered so a module follows what it depends on", function()
    ReloadCore()
    -- Deliberately alphabetical-hostile: `business` sorts first and needs
    -- almost everything. This is the real graph that broke the boot.
    local order, err = Omerta.Module.PlanDirectoryOrder({
        { dir = "business",  name = "business",  depends = { "inventory", "treasury" } },
        { dir = "chat",      name = "chat",      depends = {} },
        { dir = "inventory", name = "inventory", depends = { "chat" } },
        { dir = "treasury",  name = "treasury",  depends = { "inventory" } },
    })
    assert(order, tostring(err))

    local position = {}
    for i, dir in ipairs(order) do position[dir] = i end
    assert(position.chat < position.inventory, "chat must come before inventory")
    assert(position.inventory < position.treasury, "inventory before treasury")
    assert(position.treasury < position.business, "treasury before business")
    assert(position.business == 4, "business should be last, got " .. position.business)
end)

check("the order is deterministic across equally-valid arrangements", function()
    ReloadCore()
    local first = Omerta.Module.PlanDirectoryOrder({
        { dir = "b", name = "b", depends = {} },
        { dir = "a", name = "a", depends = {} },
        { dir = "c", name = "c", depends = {} },
    })
    local second = Omerta.Module.PlanDirectoryOrder({
        { dir = "c", name = "c", depends = {} },
        { dir = "b", name = "b", depends = {} },
        { dir = "a", name = "a", depends = {} },
    })
    assert(table.concat(first, ",") == table.concat(second, ","),
        "scan order should not change the include order")
    assert(first[1] == "a", "independent modules keep alphabetical order")
end)

check("a dependency on something absent is left to the lifecycle to report", function()
    ReloadCore()
    -- Ordering ignores it; FinishLoading refuses it with better context.
    local order = Omerta.Module.PlanDirectoryOrder({
        { dir = "lonely", name = "lonely", depends = { "nothing_here" } },
    })
    assert(order and order[1] == "lonely", "ordering should not fail on this")
end)

check("a circular dependency is refused rather than guessed at", function()
    ReloadCore()
    local order, err = Omerta.Module.PlanDirectoryOrder({
        { dir = "a", name = "a", depends = { "b" } },
        { dir = "b", name = "b", depends = { "a" } },
    })
    assert(order == nil, "a cycle must not produce an order")
    assert(err and err:find("circular"), tostring(err))
end)

check("unreadable directories go last instead of stopping the boot", function()
    ReloadCore()
    local order = Omerta.Module.PlanDirectoryOrder({
        { dir = "mystery" },
        { dir = "chat", name = "chat", depends = {} },
    })
    assert(order[1] == "chat" and order[2] == "mystery",
        "an unscannable directory should sort last and fail on its own terms")
end)
