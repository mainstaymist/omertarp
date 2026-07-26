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
--   * `depends` orders LIFECYCLE calls, not file inclusion. Include-time code
--     must only define things; cross-module references belong in OnEnable and
--     later, by which point every module is loaded.
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

-- Includes every module directory under basePath with realm-correct handling,
-- verifies registration, then runs OnLoad in dependency order.
-- Engine-only: the headless tests register modules directly and call
-- FinishLoading() themselves.
function Omerta.Module.IncludeAll(basePath)
    if not Omerta.InEngine then return end

    local _, dirs = file.Find(basePath .. "/*", "LUA")
    table.sort(dirs)

    for _, dir in ipairs(dirs) do
        local before = defs[dir] ~= nil
        if before then
            error("module directory '" .. dir .. "' collides with an already-registered module")
        end

        local files = file.Find(basePath .. "/" .. dir .. "/*.lua", "LUA")
        table.sort(files)
        for _, f in ipairs(files) do
            local path = basePath .. "/" .. dir .. "/" .. f
            if f:find("^sh_") then
                if SERVER then AddCSLuaFile(path) end
                include(path)
            elseif f:find("^sv_") then
                if SERVER then include(path) end -- never AddCSLuaFile'd
            elseif f:find("^cl_") then
                if SERVER then AddCSLuaFile(path) else include(path) end
            else
                error(string.format(
                    "module file '%s/%s' has no realm prefix (sh_/sv_/cl_)", dir, f))
            end
        end

        if not defs[dir] then
            error("module directory '" .. dir .. "' did not register a module named '" .. dir .. "'")
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
