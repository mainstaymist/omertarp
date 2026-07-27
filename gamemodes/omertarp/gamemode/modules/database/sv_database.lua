-- The database public API (M1 design review §3) and its engine-side flow:
-- configuration, connection lifecycle, readiness gating, the bounded query
-- queue, migrations, transactions, statistics.
--
-- Repositories call these functions; gameplay calls repositories; nobody
-- else writes SQL. Which driver sits underneath is decided by one config
-- value and is invisible from here up.

Omerta.DB = Omerta.DB or {}
Omerta.DB.Internal = Omerta.DB.Internal or {}
local Internal = Omerta.DB.Internal

--------------------------------------------------------------------------------
-- Configuration (all server scope: never replicated, credentials never leave)
--------------------------------------------------------------------------------

Omerta.Config.Define("db.backend", {
    type = "string", default = "sqlite", choices = { "sqlite", "mysql" },
    scope = "server", description = "Database backend. The one value that switches everything.",
})
Omerta.Config.Define("db.host", {
    type = "string", default = "127.0.0.1", scope = "server", description = "MySQL host.",
})
Omerta.Config.Define("db.port", {
    type = "number", default = 3306, min = 1, max = 65535, scope = "server", description = "MySQL port.",
})
Omerta.Config.Define("db.name", {
    type = "string", default = "omertarp", scope = "server", description = "MySQL database name.",
})
Omerta.Config.Define("db.user", {
    type = "string", default = "omertarp", scope = "server", description = "MySQL user.",
})
Omerta.Config.Define("db.password", {
    type = "string", default = "", scope = "server", description = "MySQL password.",
})
Omerta.Config.Define("db.table_prefix", {
    type = "string", default = "omerta_", scope = "server",
    description = "Prefix for all tables (GMod's sv.db is shared by every addon).",
})
Omerta.Config.Define("db.slow_query_ms", {
    type = "number", default = 100, min = 1, scope = "server",
    description = "Warn when a query takes longer than this many milliseconds.",
})
Omerta.Config.Define("db.log_queries", {
    type = "boolean", default = false, scope = "server",
    description = "Debug-log every SQL statement (development only).",
})
Omerta.Config.Define("db.queue_max", {
    type = "number", default = 256, min = 1, scope = "server",
    description = "Maximum operations queued while the database is unavailable.",
})

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- Phases: idle -> connecting -> migrating -> ready
--         ready -> down -> connecting (reconnect loop)
--         any   -> failed (migration refusal: loud, terminal until restart)
local phase = "idle"
local driver = nil
local prefix = "omerta_"
local queue = {}          -- functions to run once ready
local readyCallbacks = {}
local migrations = {}     -- { version, name, fn } in registration order
local reconnectAttempts = 0
local stats = { queries = 0, errors = 0, lastError = nil }

-- One deferral helper for the whole module: next tick in-engine, immediate
-- under the headless shim (documented difference; tests know).
function Internal.Defer(fn)
    if Omerta.InEngine then
        timer.Simple(0, fn)
    else
        fn()
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function Omerta.DB.IsReady()
    return phase == "ready"
end

function Omerta.DB.Status()
    return {
        backend = driver and driver.dialect or Omerta.Config.Get("db.backend"),
        phase = phase,
        connected = phase == "ready" or phase == "migrating",
        ready = phase == "ready",
        queries = stats.queries,
        errors = stats.errors,
        lastError = stats.lastError,
        queued = #queue,
    }
end

-- Runs fn once connected AND migrated; immediately (deferred) if already
-- ready. Modules call this from OnEnable — never query at load time.
function Omerta.DB.WhenReady(fn)
    if phase == "ready" then
        Internal.Defer(fn)
    else
        readyCallbacks[#readyCallbacks + 1] = fn
    end
end

-- Registers a migration. fn(m) DECLARES statements via m:CreateTable(name)
-- and m:Query(sql, params); execution happens later, in version order.
-- Declarative collection keeps the runner simple and migrations resumable —
-- required because MySQL DDL cannot roll back (design review §6).
function Omerta.DB.AddMigration(version, name, fn)
    if type(version) ~= "number" or version % 1 ~= 0 or version < 1 then
        error("migration version must be a positive integer", 2)
    end
    for _, m in ipairs(migrations) do
        if m.version == version then
            error("migration version " .. version .. " registered twice", 2)
        end
    end
    if type(name) ~= "string" or name == "" then error("migration needs a name", 2) end
    if type(fn) ~= "function" then error("migration needs a function", 2) end
    migrations[#migrations + 1] = { version = version, name = name, fn = fn }
end

-- The queue accepts work while connecting/migrating/down; beyond the cap (or
-- after a terminal failure) operations fail loudly through their callbacks —
-- silently dropped writes are worse than errors (design review §6).
local function whenUsable(op, failCb)
    if phase == "ready" then
        op()
    elseif phase == "failed" then
        failCb("database is in a failed state (see server log)")
    elseif #queue >= Omerta.Config.Get("db.queue_max") then
        failCb("database queue overflow (" .. #queue .. " queued)")
    else
        -- Both outcomes are kept: becomeReady runs op, enterFailed runs fail.
        queue[#queue + 1] = { op = op, fail = failCb }
    end
end

local function finishQuery(sqlStr, started, cb, rows, err, insertId)
    stats.queries = stats.queries + 1
    if err then
        stats.errors = stats.errors + 1
        stats.lastError = err
        Omerta.Log.Error("db", "query failed: %s | %s", err, sqlStr)
        if driver.IsDisconnectError and driver.IsDisconnectError(err) then
            Internal.OnConnectionLost()
        end
        cb(nil, err)
        return
    end
    if Omerta.InEngine and started then
        local ms = (SysTime() - started) * 1000
        if ms > Omerta.Config.Get("db.slow_query_ms") then
            Omerta.Log.Warn("db", "slow query (%.0f ms): %s", ms, sqlStr)
        end
    end
    local coerced = {}
    for i, row in ipairs(rows) do
        coerced[i] = Internal.CoerceRow(row, driver.heuristic)
    end
    cb(coerced, nil, insertId)
end

local function defaultCb(_, err)
    -- Errors are already logged in finishQuery; this keeps fire-and-forget
    -- writes from swallowing them silently.
end

-- cb(rows, err) — rows is an array of row tables with backend-identical types.
function Omerta.DB.Query(sqlStr, params, cb)
    cb = cb or defaultCb
    local final = Internal.SubstituteTables(sqlStr, prefix)
    whenUsable(function()
        if Omerta.Config.Get("db.log_queries") then
            Omerta.Log.Debug("db", "query: %s", final)
        end
        local started = Omerta.InEngine and SysTime() or nil
        driver.RunQuery(final, params or {}, function(rows, err, insertId)
            finishQuery(final, started, cb, rows, err, insertId)
        end)
    end, function(why)
        stats.errors = stats.errors + 1
        stats.lastError = why
        Omerta.Log.Error("db", "query rejected: %s | %s", why, final)
        Internal.Defer(function() cb(nil, why) end)
    end)
end

-- cb(row, err) — row is nil when nothing matched.
function Omerta.DB.QueryOne(sqlStr, params, cb)
    Omerta.DB.Query(sqlStr, params, function(rows, err)
        cb(rows and rows[1] or nil, err)
    end)
end

-- cb(insertedId, err)
function Omerta.DB.Insert(tableName, row, cb)
    cb = cb or defaultCb
    local sqlStr, params = Internal.BuildInsert(tableName, row)
    Omerta.DB.Query(sqlStr, params, function(rows, err, insertId)
        cb(err == nil and insertId or nil, err)
    end)
end

-- cb(ok, err) — insert, or update the non-key columns when keys collide.
-- Requires a unique constraint on keys (declare it via DefineTable).
function Omerta.DB.Upsert(tableName, row, keys, cb)
    cb = cb or defaultCb
    whenUsable(function()
        local ok, sqlOrErr, params = pcall(Internal.BuildUpsert, driver.dialect, tableName, row, keys)
        if not ok then
            Internal.Defer(function() cb(false, tostring(sqlOrErr)) end)
            return
        end
        Omerta.DB.Query(sqlOrErr, params, function(_, err)
            cb(err == nil, err)
        end)
    end, function(why)
        Internal.Defer(function() cb(false, why) end)
    end)
end

-- cb(ok, err) — atomic counter: insert with counter = delta, or add delta to
-- the existing row's counter when keyRow collides (M2 addition; see the M1
-- review §9 driver-boundary extension point). Requires a unique/primary
-- constraint on keyRow's columns.
function Omerta.DB.UpsertIncrement(tableName, keyRow, counter, delta, cb)
    cb = cb or defaultCb
    whenUsable(function()
        local ok, sqlOrErr, params = pcall(Internal.BuildUpsertIncrement,
            driver.dialect, tableName, keyRow, counter, delta)
        if not ok then
            Internal.Defer(function() cb(false, tostring(sqlOrErr)) end)
            return
        end
        Omerta.DB.Query(sqlOrErr, params, function(_, err)
            cb(err == nil, err)
        end)
    end, function(why)
        Internal.Defer(function() cb(false, why) end)
    end)
end

-- All-or-nothing writes (money, items, deaths, promotions, evidence —
-- Tech §22). fn(tx) declares statements; cb(ok, err) reports once.
-- Write-only in M1: tx statements return no rows.
function Omerta.DB.Transaction(fn, cb)
    cb = cb or function(ok, err)
        if not ok then Omerta.Log.Error("db", "transaction failed: %s", tostring(err)) end
    end

    local statements = {}
    local tx = {
        Query = function(_, sqlStr, params)
            statements[#statements + 1] = {
                sql = Internal.SubstituteTables(sqlStr, prefix),
                params = params or {},
            }
        end,
        Insert = function(_, tableName, row)
            local sqlStr, params = Internal.BuildInsert(tableName, row)
            statements[#statements + 1] = {
                sql = Internal.SubstituteTables(sqlStr, prefix),
                params = params,
            }
        end,
    }

    local ok, err = pcall(fn, tx)
    if not ok then
        Internal.Defer(function() cb(false, "transaction builder failed: " .. tostring(err)) end)
        return
    end
    if #statements == 0 then
        Internal.Defer(function() cb(true, nil) end)
        return
    end

    whenUsable(function()
        driver.RunTransaction(statements, function(txOk, txErr)
            stats.queries = stats.queries + #statements
            if not txOk then
                stats.errors = stats.errors + 1
                stats.lastError = txErr
                Omerta.Log.Error("db", "transaction failed: %s", tostring(txErr))
                if driver.IsDisconnectError and driver.IsDisconnectError(txErr) then
                    Internal.OnConnectionLost()
                end
            end
            cb(txOk, txErr)
        end)
    end, function(why)
        Internal.Defer(function() cb(false, why) end)
    end)
end

--------------------------------------------------------------------------------
-- Lifecycle: connect -> migrate -> ready, with reconnect-on-loss
--------------------------------------------------------------------------------

-- Runs raw statements sequentially through the driver (no queue — this IS the
-- path that makes the queue usable).
local function runSequence(statements, index, done)
    if index > #statements then done(nil) return end
    local stmt = statements[index]
    driver.RunQuery(stmt.sql, stmt.params or {}, function(_, err)
        if err then done(err) return end
        runSequence(statements, index + 1, done)
    end)
end

local function enterFailed(why)
    phase = "failed"
    stats.lastError = why
    Omerta.Log.Error("db", "DATABASE FAILED — the server cannot persist anything: %s", why)
    local drained = queue
    queue = {}
    for _, entry in ipairs(drained) do
        -- Fail queued work loudly rather than holding it forever.
        pcall(entry.fail, "database entered failed state: " .. why)
    end
end

local function becomeReady()
    phase = "ready"
    reconnectAttempts = 0
    Omerta.Log.Info("db", "ready (%s backend, %d queued operation(s) to flush)",
        driver.dialect, #queue)
    local flush = queue
    queue = {}
    for _, entry in ipairs(flush) do entry.op() end
    local cbs = readyCallbacks
    readyCallbacks = {}
    for _, fn in ipairs(cbs) do
        local ok, err = pcall(fn)
        if not ok then Omerta.Log.Error("db", "WhenReady callback failed: %s", tostring(err)) end
    end
end

local function runMigrations()
    phase = "migrating"

    -- Bootstrap the bookkeeping table directly (it cannot migrate itself).
    local bootstrap = {}
    for _, s in ipairs(Internal.RenderCreateTable(driver.dialect, prefix, "migrations")) do
        bootstrap[#bootstrap + 1] = { sql = s }
    end

    runSequence(bootstrap, 1, function(err)
        if err then enterFailed("migrations bootstrap: " .. err) return end

        driver.RunQuery("SELECT version FROM " .. prefix .. "migrations", {}, function(rows, verr)
            if verr then enterFailed("reading applied migrations: " .. verr) return end

            local applied = {}
            for _, row in ipairs(rows or {}) do
                applied[#applied + 1] = tonumber(row.version)
            end
            local pending, perr = Internal.PlanMigrations(applied, migrations)
            if not pending then enterFailed(perr) return end
            if #pending == 0 then becomeReady() return end

            local function applyNext(i)
                if i > #pending then becomeReady() return end
                local m = pending[i]
                Omerta.Log.Info("db", "applying migration %d: %s", m.version, m.name)

                -- Collect the migration's statements declaratively.
                local statements = {}
                local ctx = {
                    CreateTable = function(_, name)
                        for _, s in ipairs(Internal.RenderCreateTable(driver.dialect, prefix, name)) do
                            statements[#statements + 1] = { sql = s }
                        end
                    end,
                    Query = function(_, sqlStr, params)
                        statements[#statements + 1] = {
                            sql = Internal.SubstituteTables(sqlStr, prefix),
                            params = params or {},
                        }
                    end,
                }
                local ok, cerr = pcall(m.fn, ctx)
                if not ok then enterFailed("migration " .. m.version .. " builder: " .. tostring(cerr)) return end

                runSequence(statements, 1, function(serr)
                    if serr then
                        enterFailed(string.format("migration %d (%s): %s", m.version, m.name, serr))
                        return
                    end
                    local recSql, recParams = Internal.BuildInsert("migrations", {
                        version = m.version, name = m.name, applied_at = os.time(),
                    })
                    driver.RunQuery(Internal.SubstituteTables(recSql, prefix), recParams, function(_, rerr)
                        if rerr then
                            enterFailed("recording migration " .. m.version .. ": " .. rerr)
                            return
                        end
                        applyNext(i + 1)
                    end)
                end)
            end
            applyNext(1)
        end)
    end)
end

local function connect()
    phase = "connecting"
    local cfg = {
        host = Omerta.Config.Get("db.host"),
        port = Omerta.Config.Get("db.port"),
        name = Omerta.Config.Get("db.name"),
        user = Omerta.Config.Get("db.user"),
        password = Omerta.Config.Get("db.password"),
    }
    driver.Connect(cfg, function(err)
        if err then
            reconnectAttempts = reconnectAttempts + 1
            local delay = math.min(2 ^ reconnectAttempts, 60)
            Omerta.Log.Error("db", "connection failed (attempt %d, retrying in %ds): %s",
                reconnectAttempts, delay, err)
            phase = "down"
            if Omerta.InEngine then
                timer.Simple(delay, connect)
            end
            return
        end
        Omerta.Log.Info("db", "connected (%s)", driver.dialect)
        -- Re-running migrations after a reconnect is safe: applied versions
        -- are skipped and DDL is idempotent.
        runMigrations()
    end)
end

-- Failed queries are never retried — a write may have applied before the
-- connection dropped, and re-running it could double-execute. The connection
-- is rebuilt for future operations only.
function Internal.OnConnectionLost()
    if phase ~= "ready" then return end
    Omerta.Log.Warn("db", "connection lost — reconnecting; new work queues until ready")
    connect()
end

-- Called from the module's OnEnable (after Config.Finalize). Also declares
-- M1's only table here — at runtime, not include time, because DefineTable
-- lives in sv_schema.lua and module files must never call siblings while
-- including (alphabetical load order).
function Internal.Start()
    if phase ~= "idle" then return end

    -- M1's only table: migration bookkeeping (design review §4).
    Omerta.DB.DefineTable("migrations", {
        columns = {
            { name = "version",    type = "int", null = false },
            { name = "name",       type = "text", length = 128, null = false },
            { name = "applied_at", type = "timestamp", null = false },
        },
        primary = { "version" },
    })

    local backend = Omerta.Config.Get("db.backend")
    driver = Internal.Drivers[backend]
    if not driver then
        error("db.backend '" .. backend .. "' has no driver")
    end
    prefix = Omerta.Config.Get("db.table_prefix")
    Omerta.Log.Info("db", "starting (%s backend, prefix '%s')", backend, prefix)
    connect()
end
