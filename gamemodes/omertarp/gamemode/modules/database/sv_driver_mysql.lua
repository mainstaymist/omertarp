-- MySQL/MariaDB driver over the mysqloo binary module.
--
-- Params travel through real prepared statements — values never enter SQL
-- text on this backend. The module is require()d only when this backend is
-- actually selected, and a missing module FAILS THE BOOT LOUDLY rather than
-- silently falling back to SQLite and writing a month of data into the wrong
-- database (M1 design review §6).
--
-- Driver interface: see sv_driver_sqlite.lua.

Omerta.DB = Omerta.DB or {}
Omerta.DB.Internal = Omerta.DB.Internal or {}
local Internal = Omerta.DB.Internal
Internal.Drivers = Internal.Drivers or {}

local DRIVER = {
    dialect = "mysql",
    heuristic = false, -- mysqloo already returns real numbers
}

local db -- mysqloo database object

-- The binary this server needs, by platform and branch. Pure (arguments in,
-- name out) so the headless suite covers every combination; the caller reads
-- the actual platform from the engine.
-- Note the Linux builds are also named .dll — that is upstream's convention,
-- not a mistake.
function Internal.MysqlooBinaryName(isWindows, is64)
    local arch
    if isWindows then
        arch = is64 and "win64" or "win32"
    else
        arch = is64 and "linux64" or "linux"
    end
    return "gmsv_mysqloo_" .. arch .. ".dll"
end

function DRIVER.Connect(cfg, cb)
    if not mysqloo then
        -- Check for the file first: a bare require() on a missing module also
        -- prints GMod's own "Couldn't include file" error, which buries the
        -- real message in a two-error cascade.
        local binary = Internal.MysqlooBinaryName(system.IsWindows(), jit.arch == "x64")
        if not file.Exists("bin/" .. binary, "LUA") then
            -- Synchronous point (module OnEnable): error here fails the boot,
            -- deliberately — a database-backed gamemode that cannot reach its
            -- database should refuse to run rather than appear healthy.
            error(string.format(
                "db.backend is 'mysql' but the mysqloo binary module is not installed.\n" ..
                "         Expected file: garrysmod/lua/bin/%s\n" ..
                "         Download:      https://github.com/FredyH/MySQLOO/releases\n" ..
                "         Alternative:   set db.backend to \"sqlite\" in " ..
                "data/omertarp/config/server.txt", binary))
        end

        local ok, err = pcall(require, "mysqloo")
        if not ok or not mysqloo then
            error(string.format(
                "db.backend is 'mysql' and garrysmod/lua/bin/%s exists, but it failed to load: %s\n" ..
                "         This usually means the binary is for the wrong platform or branch " ..
                "(this server is %s, %s).",
                binary, tostring(err),
                system.IsWindows() and "Windows" or "Linux",
                jit.arch == "x64" and "64-bit" or "32-bit"))
        end
    end

    db = mysqloo.connect(cfg.host, cfg.user, cfg.password, cfg.name, cfg.port)

    db.onConnected = function()
        -- Character names carry accents (Omertà, D-002 setting) — utf8mb4 end
        -- to end, matching the DDL's table charset.
        db:setCharacterSet("utf8mb4")
        cb(nil)
    end
    db.onConnectionFailed = function(_, err)
        cb(tostring(err))
    end
    db:connect()
end

-- Binds one params array onto a prepared query by Lua type.
local function bindParams(q, params)
    for i, v in ipairs(params) do
        if v == Omerta.DB.NULL then q:setNull(i)
        elseif type(v) == "boolean" then q:setBoolean(i, v)
        elseif type(v) == "number" then q:setNumber(i, v)
        else q:setString(i, v)
        end
    end
end

function DRIVER.RunQuery(sqlStr, params, cb)
    params = params or {}
    local okParams, why = Internal.ValidateParams(params)
    if not okParams then
        cb(nil, why)
        return
    end

    local ok, q = pcall(db.prepare, db, sqlStr)
    if not ok then
        cb(nil, "prepare failed: " .. tostring(q))
        return
    end

    bindParams(q, params)
    q.onSuccess = function(query, data)
        cb(data or {}, nil, query:lastInsert())
    end
    q.onError = function(_, err)
        cb(nil, tostring(err))
    end
    q:start()
end

function DRIVER.RunTransaction(statements, cb)
    local tx = db:createTransaction()
    for _, stmt in ipairs(statements) do
        local okParams, why = Internal.ValidateParams(stmt.params or {})
        if not okParams then
            cb(false, why)
            return
        end
        local ok, q = pcall(db.prepare, db, stmt.sql)
        if not ok then
            cb(false, "prepare failed: " .. tostring(q))
            return
        end
        bindParams(q, stmt.params or {})
        tx:addQuery(q)
    end
    tx.onSuccess = function() cb(true, nil) end
    tx.onError = function(_, err) cb(false, tostring(err)) end -- mysqloo rolls back
    tx:start()
end

-- Used by the self-test's reconnect step. Guarded: mysqloo builds differ.
function DRIVER.ForceDisconnect()
    if db and db.disconnect then
        db:disconnect(false)
        return true
    end
    return false
end

-- Central layer asks this to classify errors as connection loss (M1 design
-- review §6: failed queries are NOT retried — a write may have applied before
-- the drop — but the connection gets rebuilt for future ones).
function DRIVER.IsDisconnectError(err)
    err = string.lower(err or "")
    return err:find("lost connection", 1, true) ~= nil
        or err:find("gone away", 1, true) ~= nil
        or err:find("not connected", 1, true) ~= nil
        or err:find("can't connect", 1, true) ~= nil
end

Internal.Drivers.mysql = DRIVER
