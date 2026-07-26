-- Schema-validated configuration with a hard shared/server-secret split.
--
-- Rules enforced here:
--   * Every key is declared with Define() before use; Get() on an undeclared
--     key is an error, never nil.
--   * scope = "server" keys may only be Defined in server realm (put the
--     Define in an sv_ file or a SERVER block) — so secret values, like M1's
--     database credentials, physically never exist client-side.
--   * Server operators override values in data/omertarp/config/server.txt
--     (a sandboxed Lua file returning a table). Unknown keys, type errors,
--     and malformed files FAIL THE BOOT LOUDLY: a silently-defaulted config
--     (e.g. a mistyped database backend) is worse than a down server.
--   * Shared-scope keys cannot be overridden from the file yet: replicating
--     overrides to clients is deferred (see the M0 design review), and a
--     server-only change to a shared value would desync the realms.

Omerta.Config = {}

local defs = {}
local values = {}
local finalized = false

local VALID_TYPES = { number = true, string = true, boolean = true }
local VALID_SCOPES = { shared = true, server = true }

-- Pure value validation, exposed for the headless tests.
-- Returns true, or false + reason.
function Omerta.Config.ValidateValue(def, value)
    if type(value) ~= def.type then
        return false, string.format("expected %s, got %s", def.type, type(value))
    end
    if def.type == "number" then
        if def.min and value < def.min then return false, "below minimum " .. def.min end
        if def.max and value > def.max then return false, "above maximum " .. def.max end
    end
    if def.choices then
        for _, c in ipairs(def.choices) do
            if value == c then return true end
        end
        return false, "not one of the allowed choices"
    end
    return true
end

function Omerta.Config.Define(key, def)
    if finalized then
        error("config key '" .. key .. "' defined after Finalize()", 2)
    end
    if type(key) ~= "string" or not key:find("^[%w_]+%.[%w_%.]+$") then
        error("config key '" .. tostring(key) .. "' must look like 'module.key'", 2)
    end
    if defs[key] then
        error("config key '" .. key .. "' defined twice", 2)
    end
    if not VALID_TYPES[def.type] then
        error("config key '" .. key .. "' has invalid type '" .. tostring(def.type) .. "'", 2)
    end
    def.scope = def.scope or "shared"
    if not VALID_SCOPES[def.scope] then
        error("config key '" .. key .. "' has invalid scope '" .. tostring(def.scope) .. "'", 2)
    end
    if def.scope == "server" and not SERVER then
        error("server-scope config key '" .. key .. "' defined in client realm", 2)
    end
    local ok, why = Omerta.Config.ValidateValue(def, def.default)
    if not ok then
        error("config key '" .. key .. "' has invalid default: " .. why, 2)
    end
    defs[key] = def
    values[key] = def.default
end

function Omerta.Config.Get(key)
    local def = defs[key]
    if not def then
        error("unknown config key '" .. tostring(key) .. "'", 2)
    end
    return values[key]
end

-- Applies a table of overrides (the parsed config file). Pure with respect to
-- the engine, so the tests drive it directly. Errors loudly on any problem.
function Omerta.Config.ApplyOverrides(overrides, sourceName)
    sourceName = sourceName or "config overrides"
    if type(overrides) ~= "table" then
        error(sourceName .. " must return a table", 2)
    end
    local count = 0
    for key, value in pairs(overrides) do
        local def = defs[key]
        if not def then
            error(sourceName .. " sets unknown config key '" .. tostring(key) .. "'")
        end
        if def.scope ~= "server" then
            error(sourceName .. " overrides shared-scope key '" .. key ..
                "': shared overrides are unsupported until config replication ships")
        end
        local ok, why = Omerta.Config.ValidateValue(def, value)
        if not ok then
            error(sourceName .. " sets invalid value for '" .. key .. "': " .. why)
        end
        values[key] = value
        count = count + 1
    end
    return count
end

local CONFIG_PATH = "omertarp/config/server.txt"

local function loadOverrideFile()
    if not (SERVER and Omerta.InEngine) then return nil end
    if not file.Exists(CONFIG_PATH, "DATA") then return nil end

    local code = file.Read(CONFIG_PATH, "DATA")
    local chunk = CompileString(code, CONFIG_PATH, false)
    if type(chunk) == "string" then
        error("config file " .. CONFIG_PATH .. " failed to parse: " .. chunk)
    end
    setfenv(chunk, {}) -- config files are data: no engine access, no globals
    local ok, result = pcall(chunk)
    if not ok then
        error("config file " .. CONFIG_PATH .. " failed to run: " .. tostring(result))
    end
    return result
end

function Omerta.Config.Finalize()
    if finalized then return end
    local overrides = loadOverrideFile()
    if overrides then
        local n = Omerta.Config.ApplyOverrides(overrides, CONFIG_PATH)
        Omerta.Log.Info("config", "applied %d override(s) from %s", n, CONFIG_PATH)
    end
    finalized = true

    -- Core applies its own keys once values are final.
    if SERVER then
        Omerta.Log.SetLevelByName(Omerta.Config.Get("log.level"))
    end
end

-- Core's own configuration.
if SERVER then
    Omerta.Config.Define("log.level", {
        type = "string",
        default = "info",
        choices = { "debug", "info", "warn", "error" },
        scope = "server",
        description = "Minimum server log level (debug|info|warn|error).",
    })
end
