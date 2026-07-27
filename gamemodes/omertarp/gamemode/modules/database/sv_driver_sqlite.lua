-- SQLite driver: GMod's built-in synchronous `sql` library, presented through
-- the same async interface as MySQL.
--
-- THE deliberate quirk (M1 design review §6): every callback is deferred to
-- the next tick. GMod's sql library completes synchronously; if callbacks
-- fired inline here but a tick later on MySQL, gameplay code could grow an
-- accidental dependency on same-tick completion that only breaks after
-- switching backends. Identical timing behavior is part of the abstraction.
--
-- Driver interface (consumed by sv_database.lua):
--   dialect            "sqlite"
--   heuristic          true  — apply numeric coercion to unregistered columns
--   Connect(cfg, cb)          cb(err)
--   RunQuery(sql, params, cb) cb(rows, err, insertId)   sql already prefixed
--   RunTransaction(stmts, cb) cb(ok, err)               stmts = { {sql, params}, ... }

Omerta.DB = Omerta.DB or {}
Omerta.DB.Internal = Omerta.DB.Internal or {}
local Internal = Omerta.DB.Internal
Internal.Drivers = Internal.Drivers or {}

local DRIVER = {
    dialect = "sqlite",
    heuristic = true,
}

function DRIVER.Connect(_, cb)
    -- Nothing to connect: sv.db is always there. Deferred like everything else.
    Internal.Defer(function() cb(nil) end)
end

local function isInsert(sqlStr)
    return sqlStr:find("^%s*[Ii][Nn][Ss][Ee][Rr][Tt]") ~= nil
end

-- Interpolates and runs one statement synchronously.
-- Returns rows, err, insertId (raw — coercion happens centrally).
local function runNow(sqlStr, params)
    local ok, rendered = pcall(Internal.Interpolate, sqlStr, params, "sqlite")
    if not ok then return nil, tostring(rendered) end

    local res = sql.Query(rendered)
    if res == false then
        return nil, sql.LastError()
    end

    local insertId
    if isInsert(rendered) then
        insertId = tonumber(sql.QueryValue("SELECT last_insert_rowid()"))
    end
    return res or {}, nil, insertId
end

function DRIVER.RunQuery(sqlStr, params, cb)
    local rows, err, insertId = runNow(sqlStr, params)
    Internal.Defer(function() cb(rows, err, insertId) end)
end

function DRIVER.RunTransaction(statements, cb)
    sql.Query("BEGIN TRANSACTION")
    for _, stmt in ipairs(statements) do
        local _, err = runNow(stmt.sql, stmt.params)
        if err then
            sql.Query("ROLLBACK")
            Internal.Defer(function() cb(false, err) end)
            return
        end
    end
    local res = sql.Query("COMMIT")
    if res == false then
        local err = sql.LastError()
        sql.Query("ROLLBACK")
        Internal.Defer(function() cb(false, err) end)
        return
    end
    Internal.Defer(function() cb(true, nil) end)
end

Internal.Drivers.sqlite = DRIVER
