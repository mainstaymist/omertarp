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

function DRIVER.Connect(cfg, cb)
    if not mysqloo then
        -- Synchronous point (module OnEnable): error here fails the boot.
        local ok, err = pcall(require, "mysqloo")
        if not ok or not mysqloo then
            error("db.backend is 'mysql' but the mysqloo binary module could not be loaded " ..
                "(install gmsv_mysqloo for your platform): " .. tostring(err))
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
