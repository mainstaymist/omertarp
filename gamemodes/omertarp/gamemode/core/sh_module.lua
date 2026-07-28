-- Module system: discovery, realm-correct inclusion, dependency-ordered
-- lifecycle. Every gameplay system from M1 onward is a directory under
-- modules/ that registers itself here.
--
-- Conventions enforced:
--   * one directory per module; the directory name IS the module name, and a
--     module with exactly that name must be registered by the time the
--     directory's files finish including;
--   * files are realm-prefixed: sh_ (shared), sv_ (server-only, never sent to
--     clients), cl_ (client). Any other prefix is a boot error — realm
--     ambiguity is how server code leaks;
--   * within a module, sh_ files are included BEFORE cl_/sv_ files, so realm
--     files may use their module's shared definitions at include time;
--   * every module directory has an sh_module.lua containing nothing but its
--     Register call. It is included first, for every module, so the whole
--     dependency graph is known before any real code runs;
--   * `depends` then orders BOTH file inclusion and lifecycle calls, so a
--     module may use anything it declares at include time — and nothing it
--     does not.
--
-- Lifecycle (each hook optional):
--   OnLoad(self)   — after all modules' files are included, dependency order
--   OnEnable(self) — after every module's OnLoad ran; safe to use other modules
--   OnReload(self) — after a Lua auto-refresh rebuilt the registries

Omerta.Module = {}

local defs = {}
local order = nil
local enabled = false

function Omerta.Module.Register(def)
    if type(def) ~= "table" or type(def.name) ~= "string" or def.name == "" then
        error("Omerta.Module.Register needs a table with a name", 2)
    end
    if defs[def.name] then
        error("module '" .. def.name .. "' registered twice", 2)
    end
    def.depends = def.depends or {}
    defs[def.name] = def
    return def
end

function Omerta.Module.Get(name)
    return defs[name]
end

function Omerta.Module.IsEnabled(name)
    return enabled and defs[name] ~= nil
end

-- The resolved dependency order — the same list used to include files and to
-- call lifecycle hooks, which is why they cannot drift apart. Nil until
-- FinishLoading has run.
function Omerta.Module.GetOrder()
    if not order then return nil end
    local copy = {}
    for i, name in ipairs(order) do copy[i] = name end
    return copy
end

local function resolveOrder()
    local names = {}
    for name in pairs(defs) do names[#names + 1] = name end
    table.sort(names) -- deterministic tiebreak for the topological sort

    local sorted, err = Omerta.Util.TopoSort(names, function(name)
        return defs[name].depends
    end)
    if not sorted then
        error("module dependency resolution failed: " .. err)
    end
    return sorted
end

local function callLifecycle(hookName)
    for _, name in ipairs(order) do
        local def = defs[name]
        if def[hookName] then
            local ok, err = pcall(def[hookName], def)
            if not ok then
                -- A broken module is a broken boot: modules are load-bearing,
                -- and a half-initialized system must not limp onward.
                error(string.format("module '%s' failed in %s: %s", name, hookName, tostring(err)))
            end
        end
    end
end

-- Pure planning half of module discovery: decides what to do with a directory
-- listing without touching the engine, so the headless tests can cover the
-- realm-routing rules that actually break in practice.
--
-- fileNames may be nil (file.Find returns nil, not an empty table, when a path
-- does not resolve — notably on the client, where gamemode Lua lives in the
-- Lua cache rather than on disk).
--
-- Returns an ordered array of { path, file, realm } where realm is
-- "shared" | "server" | "client", or nil + reason for an unprefixed file.
local REALM_ORDER = { shared = 1, client = 2, server = 3 }

-- sh_module.lua is deliberately absent from the plan: it was already included
-- in phase 1, before anything else, so the dependency graph could be known.
-- Including it again would register the module twice.
Omerta.Module.REGISTRATION_FILE = "sh_module.lua"

function Omerta.Module.PlanIncludes(basePath, dirName, fileNames)
    local plan = {}
    for _, f in ipairs(fileNames or {}) do
        local realm
        if f == Omerta.Module.REGISTRATION_FILE then realm = nil -- already included
        elseif f:find("^sh_") then realm = "shared"
        elseif f:find("^sv_") then realm = "server"
        elseif f:find("^cl_") then realm = "client"
        else
            return nil, string.format(
                "module file '%s/%s' has no realm prefix (sh_/sv_/cl_)", dirName, f)
        end
        if realm then
            plan[#plan + 1] = {
                path = basePath .. "/" .. dirName .. "/" .. f,
                file = f,
                realm = realm,
            }
        end
    end

    -- Shared files load FIRST, not alphabetically: sh_ files define the
    -- contracts (constants, shared rules, net registrations) that cl_ and sv_
    -- files legitimately use at include time. Plain alphabetical ordering put
    -- cl_ before sh_ and broke exactly that on the client.
    -- Alphabetical within each realm keeps the result deterministic.
    table.sort(plan, function(a, b)
        local ra, rb = REALM_ORDER[a.realm], REALM_ORDER[b.realm]
        if ra ~= rb then return ra < rb end
        return a.file < b.file
    end)
    return plan
end

-- Engine edge: include a planned file with the realm rules applied.
-- sv_ files are never AddCSLuaFile'd, so server logic cannot reach a client.
local function executePlanEntry(entry)
    if not file.Exists(entry.path, "LUA") then
        -- A precise error beats GMod's generic "Couldn't include file" followed
        -- by a cascade of nil-index errors from half-loaded core.
        error(string.format("module file '%s' not found in the LUA search path (%s realm)",
            entry.path, SERVER and "server" or "client"))
    end
    if entry.realm == "shared" then
        if SERVER then AddCSLuaFile(entry.path) end
        include(entry.path)
    elseif entry.realm == "server" then
        if SERVER then include(entry.path) end
    elseif entry.realm == "client" then
        if SERVER then AddCSLuaFile(entry.path) else include(entry.path) end
    end
end

-- Discovers every module directory under basePath, includes its files with
-- realm-correct handling, verifies registration, then runs OnLoad in
-- dependency order.
-- Engine-only: the headless tests register modules directly and call
-- FinishLoading() themselves.
function Omerta.Module.IncludeAll(basePath)
    if not Omerta.InEngine then return end

    -- file.Find returns nil rather than an empty table when the path does not
    -- resolve; normalize at the edge so discovery can never crash the boot.
    local _, dirs = file.Find(basePath .. "/*", "LUA")
    dirs = dirs or {}
    table.sort(dirs)

    if #dirs == 0 then
        Omerta.Log.Warn("module",
            "no module directories found under '%s' (%s realm) — nothing will load",
            basePath, SERVER and "server" or "client")
    else
        Omerta.Log.Debug("module", "discovered %d directory/ies under '%s': %s",
            #dirs, basePath, table.concat(dirs, ", "))
    end

    -- PHASE 1: registration only.
    --
    -- Every module directory carries an sh_module.lua containing nothing but
    -- its Omerta.Module.Register call, so the whole graph can be known before
    -- any real code runs. Order does not matter here — these files declare and
    -- do nothing else.
    --
    -- This exists because `depends` used to govern only the lifecycle while
    -- files were included by directory name. That worked for eleven milestones
    -- purely because every module happened to sort after the ones it needed,
    -- and then `business` did not (b before inventory, organizations,
    -- treasury). Shared files legitimately use their dependencies at include
    -- time — an item catalogue calls Omerta.Items.Register — so the include
    -- order has to match the declared one.
    for _, dir in ipairs(dirs) do
        local path = basePath .. "/" .. dir .. "/sh_module.lua"
        if not file.Exists(path, "LUA") then
            error(string.format("module directory '%s' has no sh_module.lua — " ..
                "every module declares its name and dependencies there", dir))
        end
        if SERVER then AddCSLuaFile(path) end
        include(path)
        if not defs[dir] then
            error("module directory '" .. dir .. "' did not register a module named '" .. dir .. "'")
        end
    end

    -- PHASE 2: everything else, in dependency order. resolveOrder is the same
    -- topological sort the lifecycle uses, so include order and lifecycle
    -- order cannot drift apart.
    dirs = resolveOrder()
    Omerta.Log.Debug("module", "include order: %s", table.concat(dirs, ", "))

    for _, dir in ipairs(dirs) do
        local files = file.Find(basePath .. "/" .. dir .. "/*.lua", "LUA")
        local plan, why = Omerta.Module.PlanIncludes(basePath, dir, files)
        if not plan then error(why) end

        for _, entry in ipairs(plan) do
            executePlanEntry(entry)
        end
    end

    Omerta.Module.FinishLoading()
end

-- Resolves dependency order and runs OnLoad. Split out so the headless tests
-- can drive the lifecycle without the engine's file APIs.
function Omerta.Module.FinishLoading()
    order = resolveOrder()
    callLifecycle("OnLoad")
    Omerta.Log.Info("module", "loaded %d module(s): %s", #order, table.concat(order, ", "))
end

function Omerta.Module.EnableAll()
    if enabled then return end
    if not order then
        error("Omerta.Module.EnableAll called before modules finished loading")
    end
    callLifecycle("OnEnable")
    enabled = true
end

function Omerta.Module.ReloadAll()
    if not enabled then return end
    callLifecycle("OnReload")
end
