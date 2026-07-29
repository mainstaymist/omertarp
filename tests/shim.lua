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
-- A minimal Vector. Enough for the pure geometry the modules do — the drag
-- hold point today, and whatever M20's event positions and M15's evidence
-- placement need next. Deliberately not the whole engine type: anything that
-- needs more than this is doing engine work and belongs behind InEngine.
local VectorMeta = {}
VectorMeta.__index = VectorMeta

function Vector(x, y, z)
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VectorMeta)
end

function VectorMeta.__add(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function VectorMeta.__sub(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end

function VectorMeta.__mul(a, b)
    if type(a) == "number" then return Vector(b.x * a, b.y * a, b.z * a) end
    if type(b) == "number" then return Vector(a.x * b, a.y * b, a.z * b) end
    return Vector(a.x * b.x, a.y * b.y, a.z * b.z)
end

function VectorMeta.__eq(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end

function VectorMeta:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function VectorMeta:Length() return math.sqrt(self:LengthSqr()) end

function VectorMeta:Distance(other)
    return math.sqrt((self.x - other.x) ^ 2 + (self.y - other.y) ^ 2
        + (self.z - other.z) ^ 2)
end

-- Mutates in place, exactly as the engine's does. Callers rely on that.
function VectorMeta:Normalize()
    local length = self:Length()
    if length > 0 then
        self.x, self.y, self.z = self.x / length, self.y / length, self.z / length
    end
end

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
