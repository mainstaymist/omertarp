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
-- happened to sort after the ones it needed — and then `business` did not,
-- sorting before inventory, organizations and treasury.
--
-- The fix is a two-phase include: every module's sh_module.lua goes first, so
-- the whole graph is known, and everything else follows in dependency order.
-- An earlier attempt parsed `depends` out of the source instead, which worked
-- on the server and silently did nothing on the client, where gamemode Lua
-- lives in a cache that file.Read cannot see. Hence: no reading, just an
-- ordering pass over what has already registered.

check("the registration file is not included a second time", function()
    ReloadCore()
    -- Phase 1 already ran it; planning it again would register the module twice
    -- and abort the boot.
    local plan = Omerta.Module.PlanIncludes("base", "business", {
        "sh_module.lua", "sh_business.lua", "sv_business.lua", "cl_business.lua",
    })
    for _, entry in ipairs(plan) do
        assert(entry.file ~= Omerta.Module.REGISTRATION_FILE,
            "sh_module.lua must not be planned in phase 2")
    end
    assert(#plan == 3, "expected the other three files, got " .. #plan)
end)

check("a module directory with only a registration file plans nothing", function()
    ReloadCore()
    local plan = Omerta.Module.PlanIncludes("base", "empty", { "sh_module.lua" })
    assert(plan and #plan == 0, "a registration-only module has nothing left to include")
end)

check("an unprefixed file is still refused", function()
    ReloadCore()
    local plan, why = Omerta.Module.PlanIncludes("base", "x", { "sh_module.lua", "helpers.lua" })
    assert(plan == nil, "an unprefixed file must still be an error")
    assert(why and why:find("realm prefix"), tostring(why))
end)

-- Include order and lifecycle order come from the same topological sort now,
-- so they cannot drift apart. This drives the real shape that broke the boot.
check("include order follows dependencies, not the alphabet", function()
    ReloadCore()
    Omerta.Module.Register({ name = "business", depends = { "inventory", "treasury" } })
    Omerta.Module.Register({ name = "chat", depends = {} })
    Omerta.Module.Register({ name = "inventory", depends = { "chat" } })
    Omerta.Module.Register({ name = "treasury", depends = { "inventory" } })
    Omerta.Module.FinishLoading()

    local order = Omerta.Module.GetOrder()
    local position = {}
    for i, name in ipairs(order) do position[name] = i end

    assert(position.chat < position.inventory, "chat must come before inventory")
    assert(position.inventory < position.treasury, "inventory before treasury")
    assert(position.treasury < position.business, "treasury before business")
    assert(position.business == 4, "business sorts first alphabetically and must load last")
end)

check("independent modules keep a stable, alphabetical order", function()
    ReloadCore()
    Omerta.Module.Register({ name = "cc", depends = {} })
    Omerta.Module.Register({ name = "aa", depends = {} })
    Omerta.Module.Register({ name = "bb", depends = {} })
    Omerta.Module.FinishLoading()
    assert(table.concat(Omerta.Module.GetOrder(), ",") == "aa,bb,cc",
        "registration order must not decide include order")
end)

-- The strongest test of the ordering: boot the real module graph exactly as
-- the server does. Phase 1 registers everything, phase 2 includes every shared
-- and server file in the resolved order. If a module reaches for a dependency
-- that has not loaded, this fails here rather than in a server console.
check("the real module graph includes cleanly in dependency order", function()
    local base = "gamemodes/omertarp/gamemode/modules"
    local dirs = {}
    local pipe = io.popen("ls -1 " .. base .. " 2>/dev/null")
    if pipe then
        for d in pipe:lines() do dirs[#dirs + 1] = d end
        pipe:close()
    end
    assert(#dirs > 0, "no module directories found")

    ReloadCore()
    for _, d in ipairs(dirs) do dofile(base .. "/" .. d .. "/sh_module.lua") end
    Omerta.Module.FinishLoading()

    local order = Omerta.Module.GetOrder()
    assert(#order == #dirs, "every directory should have registered exactly one module")

    for _, d in ipairs(order) do
        local files = {}
        local listing = io.popen("ls -1 " .. base .. "/" .. d .. "/sh_*.lua " ..
            base .. "/" .. d .. "/sv_*.lua 2>/dev/null")
        if listing then
            for path in listing:lines() do files[#files + 1] = path end
            listing:close()
        end
        -- Shared before server, alphabetical within each, matching PlanIncludes.
        table.sort(files, function(a, b)
            local ra = a:find("/sh_") and 1 or 2
            local rb = b:find("/sh_") and 1 or 2
            if ra ~= rb then return ra < rb end
            return a < b
        end)
        for _, path in ipairs(files) do
            if not path:find("sh_module%.lua$") then
                local ok, err = pcall(dofile, path)
                assert(ok, "including " .. path .. " failed: " .. tostring(err))
            end
        end
    end
end)
