-- Leveled, channeled logging plus the audit sink stub.
--
-- The audit envelope shape written here is the contract M2 will persist to the
-- database: call sites never change when the sink gains storage.

Omerta.Log = {}

local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
local LEVEL_NAMES = { "DEBUG", "INFO", "WARN", "ERROR" }

local currentLevel = LEVELS.INFO

function Omerta.Log.SetLevelByName(name)
    local lvl = LEVELS[string.upper(name or "")]
    if not lvl then
        error("unknown log level '" .. tostring(name) .. "'", 2)
    end
    currentLevel = lvl
end

local function emit(level, channel, fmt, ...)
    if level < currentLevel then return end
    local msg = fmt
    if select("#", ...) > 0 then msg = string.format(fmt, ...) end
    local line = string.format("[Omerta][%s][%s] %s", LEVEL_NAMES[level], channel, msg)
    print(line)

    -- Server keeps a daily plain-text log on disk until M2 provides real
    -- storage. Never runs headless.
    if SERVER and Omerta.InEngine then
        file.CreateDir("omertarp/logs")
        file.Append("omertarp/logs/" .. os.date("%Y-%m-%d") .. ".txt",
            os.date("[%H:%M:%S]") .. line .. "\n")
    end
end

function Omerta.Log.Debug(channel, fmt, ...) emit(LEVELS.DEBUG, channel, fmt, ...) end
function Omerta.Log.Info(channel, fmt, ...)  emit(LEVELS.INFO,  channel, fmt, ...) end
function Omerta.Log.Warn(channel, fmt, ...)  emit(LEVELS.WARN,  channel, fmt, ...) end
function Omerta.Log.Error(channel, fmt, ...) emit(LEVELS.ERROR, channel, fmt, ...) end

-- Audit sink (server-only). `info` may carry `actor` and `subject`
-- (SteamID64 / character identifiers once those exist) plus arbitrary event
-- data. The console line always emits; a registered sink additionally
-- persists the same envelope (M2's accounts module installs the database
-- sink — the swap M0 promised, with zero call-site changes).
local auditSink = nil

function Omerta.Log.SetAuditSink(fn)
    Omerta.AssertServer("Omerta.Log.SetAuditSink")
    auditSink = fn
end

function Omerta.Log.Audit(event, info)
    Omerta.AssertServer("Omerta.Log.Audit")
    local envelope = {
        event = event,
        at = os.time(),
        actor = info and info.actor,
        subject = info and info.subject,
        data = info,
    }
    emit(LEVELS.INFO, "audit", "%s %s", event, Omerta.Util.Serialize(envelope))
    if auditSink then
        local ok, err = pcall(auditSink, envelope)
        if not ok then
            emit(LEVELS.ERROR, "audit", "sink failed for '%s': %s", event, tostring(err))
        end
    end
    return envelope
end
