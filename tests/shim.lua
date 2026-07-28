-- Minimal environment for running Omertà RP core files under plain Lua 5.1.
-- Sets the flags core checks (OMERTA_TEST disables every engine touchpoint)
-- and provides a loader that mimics the gamemode's fixed core include order.

OMERTA_TEST = true
SERVER = true
CLIENT = false

local CORE_FILES = {
    "core/sh_core.lua",
    "core/sh_util.lua",
    "core/sh_log.lua",
    "core/sh_selftest.lua",
    "core/sh_config.lua",
    "core/sh_net.lua",
    "core/sh_module.lua",
}

local gamemodePath = "gamemodes/omertarp/gamemode/"

-- Minimal engine stubs. Only what module code touches on paths that are NOT
-- guarded by Omerta.InEngine — chiefly IsValid, used in player-cache lookups.
-- Everything genuinely engine-bound stays behind the InEngine flag and never
-- runs here.
-- GMod adds these to the math table; the pure presentation curves use them.
function math.Clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function Lerp(t, from, to)
    return from + (to - from) * t
end

function IsValid(x)
    if x == nil or x == false then return false end
    if type(x) == "table" and x.__invalid then return false end
    return true
end

-- Minimal hook system. Module code registers listeners only when InEngine, so
-- this exists mainly so unguarded hook.Run calls do not crash headless runs;
-- tests that want listener behaviour drive the listener function directly.
hook = { _tbl = {} }
function hook.Add(event, name, fn)
    hook._tbl[event] = hook._tbl[event] or {}
    hook._tbl[event][name] = fn
end
function hook.Remove(event, name)
    if hook._tbl[event] then hook._tbl[event][name] = nil end
end
function hook.Run(event, ...)
    for _, fn in pairs(hook._tbl[event] or {}) do fn(...) end
end

-- (Re)loads the core from scratch: every registry resets, so each test suite
-- starts from a clean boot.
function ReloadCore()
    Omerta = nil
    for _, f in ipairs(CORE_FILES) do
        dofile(gamemodePath .. f)
    end
end
