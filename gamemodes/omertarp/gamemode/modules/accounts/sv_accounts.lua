-- Accounts service: public API, cache, connect/disconnect flow, migration 1,
-- and the audit database sink (M2 design review §3, §6).
--
-- Lifecycle contract established here for every data-owning module:
--   OnLoad   — declare schema (DefineTable) and migrations (AddMigration);
--              runs before ANY module's OnEnable, so migrations are always
--              registered before the database connects.
--   OnEnable — hooks, timers, and DB work gated behind Omerta.DB.WhenReady.

local MODULE = Omerta.Module.Get("accounts")

Omerta.Accounts = Omerta.Accounts or {}
Omerta.Accounts.Internal = Omerta.Accounts.Internal or {}
local Internal = Omerta.Accounts.Internal

--------------------------------------------------------------------------------
-- Configuration (server scope)
--------------------------------------------------------------------------------

Omerta.Config.Define("accounts.load_timeout", {
    type = "number", default = 15, min = 1, scope = "server",
    description = "Seconds to wait for an account load before kicking the player.",
})
Omerta.Config.Define("accounts.kick_on_failure", {
    type = "boolean", default = true, scope = "server",
    description = "Kick players whose account cannot be loaded (disable for local development only).",
})
Omerta.Config.Define("accounts.flush_interval", {
    type = "number", default = 300, min = 10, scope = "server",
    description = "Seconds between periodic playtime/last-seen flushes for online players.",
})
Omerta.Config.Define("audit.retention_days", {
    type = "number", default = 0, min = 0, scope = "server",
    description = "Delete audit rows older than this many days (0 = keep forever).",
})

--------------------------------------------------------------------------------
-- Pure helpers (headless-tested)
--------------------------------------------------------------------------------

-- Seconds of playtime earned since the last write. lastFlushAt is nil before
-- the first flush of a session.
function Internal.PlaytimeDelta(sessionStartedAt, lastFlushAt, now)
    local since = math.max(sessionStartedAt, lastFlushAt or 0)
    return math.max(0, now - since)
end

-- Epoch cutoff below which audit rows are swept; nil when retention is off.
function Internal.RetentionCutoff(now, days)
    if not days or days <= 0 then return nil end
    return now - days * 86400
end

-- Maps an audit envelope (core/sh_log.lua shape) to an audit table row.
-- encode: table -> string (util.TableToJSON in-engine; tests inject one).
function Internal.AuditRow(envelope, encode)
    return {
        at = envelope.at,
        event = envelope.event,
        actor = envelope.actor or Omerta.DB.NULL,
        subject = envelope.subject or Omerta.DB.NULL,
        data = encode(envelope.data or {}) or "{}",
    }
end

--------------------------------------------------------------------------------
-- Cache and public API
--------------------------------------------------------------------------------

local cache = {} -- sid64 -> account (plus _session_started/_last_flush bookkeeping)

local FLAG_PATTERN = "^[a-z0-9_]+$"

local function cachedFor(ply)
    if not IsValid(ply) or ply.IsBot and ply:IsBot() then return nil end
    local sid = ply:SteamID64()
    return sid and cache[sid] or nil
end

function Omerta.Accounts.Get(ply)
    return cachedFor(ply)
end

function Omerta.Accounts.IsLoaded(ply)
    return cachedFor(ply) ~= nil
end

function Omerta.Accounts.GetBySteamID64(sid64, cb)
    Internal.Repo.FetchBySteamID64(sid64, cb)
end

function Omerta.Accounts.HasFlag(ply, flag)
    local account = cachedFor(ply)
    return account ~= nil and account.flags[flag] ~= nil
end

function Omerta.Accounts.GetStat(ply, stat)
    local account = cachedFor(ply)
    return account and (account.stats[stat] or 0) or 0
end

function Omerta.Accounts.SetFlag(ply, flag, reason, actorSid64, cb)
    local account = cachedFor(ply)
    if not account then if cb then cb(false, "account not loaded") end return end
    if not flag:find(FLAG_PATTERN) or #flag > 32 then
        error("flag name '" .. tostring(flag) .. "' must be [a-z0-9_], max 32 chars", 2)
    end
    local now = os.time()
    Internal.Repo.SetFlag(account.id, flag, reason, actorSid64, now, function(ok, err)
        if ok then
            account.flags[flag] = { set_at = now, set_by = actorSid64, reason = reason }
            Omerta.Log.Audit("account.flag_set", {
                actor = actorSid64, subject = account.steamid64,
                flag = flag, reason = reason,
            })
        end
        if cb then cb(ok, err) end
    end)
end

function Omerta.Accounts.ClearFlag(ply, flag, actorSid64, cb)
    local account = cachedFor(ply)
    if not account then if cb then cb(false, "account not loaded") end return end
    Internal.Repo.ClearFlag(account.id, flag, function(ok, err)
        if ok then
            account.flags[flag] = nil
            Omerta.Log.Audit("account.flag_clear", {
                actor = actorSid64, subject = account.steamid64, flag = flag,
            })
        end
        if cb then cb(ok, err) end
    end)
end

function Omerta.Accounts.AddStat(ply, stat, delta)
    local account = cachedFor(ply)
    if not account then return end
    if not stat:find(FLAG_PATTERN) or #stat > 32 then
        error("stat name '" .. tostring(stat) .. "' must be [a-z0-9_], max 32 chars", 2)
    end
    account.stats[stat] = (account.stats[stat] or 0) + delta
    Internal.Repo.IncrementStat(account.id, stat, delta)
end

--------------------------------------------------------------------------------
-- Connect / disconnect flow
--------------------------------------------------------------------------------

local function flushAccount(account, now)
    local delta = Internal.PlaytimeDelta(account._session_started, account._last_flush, now)
    if delta > 0 then
        account.playtime = account.playtime + delta
        account._last_flush = now
        Internal.Repo.AddPlaytime(account.id, delta, now)
    end
    return delta
end

-- Exposed for the lifecycle hooks below and for tests.
function Internal.OnPlayerConnected(ply)
    if not IsValid(ply) or ply:IsBot() then return end
    local sid = ply:SteamID64()
    if not sid then
        Omerta.Log.Warn("accounts", "player without SteamID64 — no account will load")
        return
    end

    local settled = false
    if Omerta.InEngine then
        timer.Simple(Omerta.Config.Get("accounts.load_timeout"), function()
            if settled or not IsValid(ply) then return end
            settled = true
            Omerta.Log.Error("accounts", "account load timed out for %s", sid)
            if Omerta.Config.Get("accounts.kick_on_failure") then
                ply:Kick("Your account could not be loaded. Please reconnect.")
            end
        end)
    end

    Omerta.DB.WhenReady(function()
        Internal.Repo.LoadOrCreate(sid, os.time(), function(account, err, created)
            if settled then return end
            settled = true
            if not account then
                Omerta.Log.Error("accounts", "account load failed for %s: %s", sid, tostring(err))
                if Omerta.InEngine and IsValid(ply)
                    and Omerta.Config.Get("accounts.kick_on_failure") then
                    ply:Kick("Your account could not be loaded. Please reconnect.")
                end
                return
            end
            if Omerta.InEngine and not IsValid(ply) then
                -- Left during the load: row bookkeeping already updated;
                -- nothing to cache.
                return
            end
            account._session_started = os.time()
            account._last_flush = nil
            cache[sid] = account
            Omerta.Log.Audit(created and "account.create" or "account.connect", {
                actor = sid, account_id = account.id, connections = account.connections,
            })
            Omerta.Log.Info("accounts", "account %d loaded for %s (%s)",
                account.id, sid, created and "created" or "connection " .. account.connections)
            hook.Run("Omerta.AccountLoaded", ply, account)
        end)
    end)
end

function Internal.OnPlayerDisconnected(ply)
    if not IsValid(ply) or ply:IsBot() then return end
    local sid = ply:SteamID64()
    local account = sid and cache[sid]
    if not account then return end
    hook.Run("Omerta.AccountUnloading", ply, account)
    local now = os.time()
    local sessionSeconds = now - account._session_started
    flushAccount(account, now)
    Omerta.Log.Audit("account.disconnect", {
        actor = sid, account_id = account.id, session_seconds = sessionSeconds,
    })
    cache[sid] = nil
end

function Internal.FlushAll(now)
    for _, account in pairs(cache) do
        flushAccount(account, now)
    end
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function MODULE:OnLoad()
    Omerta.DB.DefineTable("accounts", {
        columns = {
            { name = "id",          type = "id" },
            { name = "steamid64",   type = "text", length = 20, null = false },
            { name = "first_seen",  type = "timestamp", null = false },
            { name = "last_seen",   type = "timestamp", null = false },
            { name = "playtime",    type = "int", null = false, default = 0 },
            { name = "connections", type = "int", null = false, default = 0 },
        },
        unique = { { "steamid64" } },
    })
    Omerta.DB.DefineTable("account_flags", {
        columns = {
            { name = "account_id", type = "ref", null = false },
            { name = "flag",       type = "text", length = 32, null = false },
            { name = "set_at",     type = "timestamp", null = false },
            { name = "set_by",     type = "text", length = 20 },
            { name = "reason",     type = "text", length = 255 },
        },
        primary = { "account_id", "flag" },
    })
    Omerta.DB.DefineTable("account_stats", {
        columns = {
            { name = "account_id", type = "ref", null = false },
            { name = "stat",       type = "text", length = 32, null = false },
            { name = "value",      type = "bigint", null = false, default = 0 },
        },
        primary = { "account_id", "stat" },
    })
    Omerta.DB.DefineTable("audit", {
        columns = {
            { name = "id",      type = "id" },
            { name = "at",      type = "timestamp", null = false },
            { name = "event",   type = "text", length = 64, null = false },
            { name = "actor",   type = "text", length = 20 },
            { name = "subject", type = "text", length = 20 },
            { name = "data",    type = "json" },
        },
        indexes = { { "event" }, { "actor" }, { "at" } },
    })

    Omerta.DB.AddMigration(1, "accounts and audit foundation", function(m)
        m:CreateTable("accounts")
        m:CreateTable("account_flags")
        m:CreateTable("account_stats")
        m:CreateTable("audit")
    end)
end

function MODULE:OnEnable()
    -- Audit sink: the swap M0 promised — same envelope, call sites unchanged.
    -- Registered before anything else so even this module's own connect
    -- events persist. The DB layer queues writes until ready.
    if Omerta.InEngine then
        Omerta.Log.SetAuditSink(function(envelope)
            Internal.Repo.InsertAudit(Internal.AuditRow(envelope, util.TableToJSON))
        end)

        hook.Add("PlayerInitialSpawn", "omerta.accounts.connect", Internal.OnPlayerConnected)
        hook.Add("PlayerDisconnected", "omerta.accounts.disconnect", Internal.OnPlayerDisconnected)

        timer.Create("omerta.accounts.flush", Omerta.Config.Get("accounts.flush_interval"),
            0, function() Internal.FlushAll(os.time()) end)

        -- Retention: at ready and every 6 hours after.
        local function sweep()
            local cutoff = Internal.RetentionCutoff(os.time(),
                Omerta.Config.Get("audit.retention_days"))
            if cutoff then Internal.Repo.SweepAudit(cutoff) end
        end
        Omerta.DB.WhenReady(sweep)
        timer.Create("omerta.accounts.audit_sweep", 6 * 3600, 0, sweep)
    end
end
