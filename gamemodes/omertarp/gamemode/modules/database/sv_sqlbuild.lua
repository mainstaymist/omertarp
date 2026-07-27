-- SQL construction: value escaping, ?-placeholder interpolation (sqlite path),
-- {table} prefix substitution, INSERT/UPSERT rendering, migration planning.
-- Pure — no engine calls — so the headless suite covers all of it.
--
-- Injection posture (M1 design review §7): these are the ONLY functions that
-- ever place a value into SQL text, and they exist solely for the sqlite
-- driver and DDL defaults. MySQL params travel through real prepared
-- statements and never pass through Interpolate at all.

Omerta.DB = Omerta.DB or {}
Omerta.DB.Internal = Omerta.DB.Internal or {}
local Internal = Omerta.DB.Internal

-- Escapes a string for use inside a single-quoted SQL literal.
-- NUL bytes are rejected outright (they truncate C strings downstream).
-- MySQL additionally treats backslash as an escape character in literals.
function Internal.EscapeString(s, dialect)
    if s:find("%z") then
        error("SQL string values may not contain NUL bytes", 2)
    end
    if dialect == "mysql" then
        s = s:gsub("\\", "\\\\")
    end
    return (s:gsub("'", "''"))
end

function Internal.FormatNumber(v)
    if v ~= v then error("NaN is not a valid SQL value", 2) end
    if v == math.huge or v == -math.huge then error("infinity is not a valid SQL value", 2) end
    if v % 1 == 0 and v >= -2^53 and v <= 2^53 then
        return string.format("%d", v)
    end
    return string.format("%.17g", v)
end

-- Renders one Lua value as a SQL literal. Accepted: string, number, boolean,
-- Omerta.DB.NULL. Anything else (tables, functions, bare nil) is an error —
-- a bare nil in a params array breaks the array's length, so NULL must be
-- explicit.
function Internal.FormatValue(v, dialect)
    if v == Omerta.DB.NULL then return "NULL" end
    local t = type(v)
    if t == "string" then return "'" .. Internal.EscapeString(v, dialect) .. "'" end
    if t == "number" then return Internal.FormatNumber(v) end
    if t == "boolean" then return v and "1" or "0" end
    error("unsupported SQL value type '" .. t .. "' (use Omerta.DB.NULL for NULL)", 2)
end

-- Validates a params array without rendering (used by the mysql driver, whose
-- prepared statements bind values themselves). Returns true or false + reason.
function Internal.ValidateParams(params)
    for i, v in ipairs(params) do
        local t = type(v)
        if v ~= Omerta.DB.NULL and t ~= "string" and t ~= "number" and t ~= "boolean" then
            return false, string.format("param %d has unsupported type '%s'", i, t)
        end
        if t == "string" and v:find("%z") then
            return false, string.format("param %d contains a NUL byte", i)
        end
        if t == "number" and (v ~= v or v == math.huge or v == -math.huge) then
            return false, string.format("param %d is NaN or infinite", i)
        end
    end
    return true
end

-- Substitutes ?-placeholders with escaped values, in order. Project
-- convention: SQL authored for this API contains ? ONLY as a placeholder
-- (never inside literals) — all SQL is written by us in repositories, so this
-- is enforceable by review and by the placeholder-count check here.
function Internal.Interpolate(sqlStr, params, dialect)
    params = params or {}
    local expected = select(2, sqlStr:gsub("%?", ""))
    if expected ~= #params then
        error(string.format("SQL has %d placeholder(s) but %d param(s) given: %s",
            expected, #params, sqlStr), 2)
    end
    local i = 0
    local out = sqlStr:gsub("%?", function()
        i = i + 1
        return Internal.FormatValue(params[i], dialect)
    end)
    return out
end

-- Replaces {name} with the configured table prefix: "{accounts}" -> "omerta_accounts".
-- Callers never write physical table names (M1 design review §4).
function Internal.SubstituteTables(sqlStr, prefix)
    return (sqlStr:gsub("{([a-z_][a-z0-9_]*)}", prefix .. "%1"))
end

--------------------------------------------------------------------------------
-- Statement builders. All return (sqlWithPlaceholders, paramsArray); table
-- names stay in {brace} form for the substitution step. Column order is
-- sorted so identical rows always render identical SQL.
--------------------------------------------------------------------------------

local function sortedColumns(row)
    local cols = {}
    for k, v in pairs(row) do
        if type(k) ~= "string" then error("row keys must be column-name strings", 3) end
        cols[#cols + 1] = k
    end
    if #cols == 0 then error("row has no columns", 3) end
    table.sort(cols)
    return cols
end

function Internal.BuildInsert(tableName, row)
    -- Every insert path (Insert, Upsert, UpsertIncrement, tx:Insert) funnels
    -- through here, so this is the one place a missing mandatory column can be
    -- caught before it becomes a wrong row.
    local ok, why = Internal.ValidateInsertRow(tableName, row)
    if not ok then error(why, 3) end

    local cols = sortedColumns(row)
    local marks, params = {}, {}
    for i, c in ipairs(cols) do
        marks[i] = "?"
        params[i] = row[c]
    end
    local sqlStr = string.format("INSERT INTO {%s} (%s) VALUES (%s)",
        tableName, table.concat(cols, ", "), table.concat(marks, ", "))
    return sqlStr, params
end

-- Upsert: insert, or update the non-key columns when `keys` collide.
-- Requires a unique constraint on `keys` (declared via DefineTable).
--   sqlite: INSERT .. ON CONFLICT(k) DO UPDATE SET c = excluded.c
--   mysql:  INSERT .. ON DUPLICATE KEY UPDATE c = VALUES(c)
function Internal.BuildUpsert(dialect, tableName, row, keys)
    if type(keys) ~= "table" or #keys == 0 then error("upsert needs a non-empty keys array", 2) end
    local isKey = {}
    for _, k in ipairs(keys) do
        if row[k] == nil then error("upsert key '" .. k .. "' missing from row", 2) end
        isKey[k] = true
    end

    local insertSql, params = Internal.BuildInsert(tableName, row)
    local updates = {}
    for _, c in ipairs(sortedColumns(row)) do
        if not isKey[c] then
            updates[#updates + 1] = (dialect == "mysql")
                and string.format("%s = VALUES(%s)", c, c)
                or  string.format("%s = excluded.%s", c, c)
        end
    end

    local sqlStr
    if dialect == "mysql" then
        if #updates == 0 then
            -- mysql requires at least one assignment; a self-assignment is a no-op
            updates[1] = string.format("%s = %s", keys[1], keys[1])
        end
        sqlStr = insertSql .. " ON DUPLICATE KEY UPDATE " .. table.concat(updates, ", ")
    else
        local clause = (#updates == 0) and "DO NOTHING"
            or ("DO UPDATE SET " .. table.concat(updates, ", "))
        sqlStr = string.format("%s ON CONFLICT(%s) %s",
            insertSql, table.concat(keys, ", "), clause)
    end
    return sqlStr, params
end

-- Atomic counter upsert (added by M2): insert the row with the counter at
-- `delta`, or add `delta` to the existing counter when `keyRow` collides.
-- Read-free, so two systems bumping the same counter in the same tick cannot
-- race. Requires a unique/primary constraint on keyRow's columns.
function Internal.BuildUpsertIncrement(dialect, tableName, keyRow, counter, delta)
    if type(counter) ~= "string" or not counter:find("^[a-z_][a-z0-9_]*$") then
        error("counter column name '" .. tostring(counter) .. "' is invalid", 2)
    end
    if type(delta) ~= "number" then error("delta must be a number", 2) end
    if keyRow[counter] ~= nil then error("counter '" .. counter .. "' cannot also be a key", 2) end

    local row, keys = {}, {}
    for k, v in pairs(keyRow) do
        row[k] = v
        keys[#keys + 1] = k
    end
    if #keys == 0 then error("upsert-increment needs a non-empty keyRow", 2) end
    table.sort(keys)
    row[counter] = delta

    local insertSql, params = Internal.BuildInsert(tableName, row)
    local sqlStr
    if dialect == "mysql" then
        sqlStr = string.format("%s ON DUPLICATE KEY UPDATE %s = %s + VALUES(%s)",
            insertSql, counter, counter, counter)
    else
        sqlStr = string.format("%s ON CONFLICT(%s) DO UPDATE SET %s = %s + excluded.%s",
            insertSql, table.concat(keys, ", "), counter, counter, counter)
    end
    return sqlStr, params
end

--------------------------------------------------------------------------------
-- Migration planning
--------------------------------------------------------------------------------

-- applied: array of version numbers already recorded in the database.
-- known:   array of { version, name } registered by the current code.
-- Returns the pending list sorted ascending, or nil + reason when the
-- database is ahead of the code (a downgrade — refuse rather than corrupt).
function Internal.PlanMigrations(applied, known)
    local knownByVersion = {}
    for _, m in ipairs(known) do
        if knownByVersion[m.version] then
            return nil, "migration version " .. m.version .. " registered twice"
        end
        knownByVersion[m.version] = m
    end

    local appliedSet = {}
    for _, v in ipairs(applied) do
        if not knownByVersion[v] then
            -- Naming what the code DOES know turns this from a dead end into a
            -- diagnosis. In practice it is almost never a real downgrade: it is
            -- a module that failed to load, taking its migration with it, and
            -- the gap between these two lists says which one.
            local versions = {}
            for _, m in ipairs(known) do versions[#versions + 1] = m.version end
            table.sort(versions)
            return nil, string.format(
                "database has applied migration %d which this code does not know — " ..
                "refusing to start. This code knows migration(s): %s. Either the server " ..
                "is running older code than the database was migrated with, or the module " ..
                "that registers migration %d did not load (check the 'loaded N module(s)' " ..
                "line earlier in this log).",
                v, #versions > 0 and table.concat(versions, ", ") or "none", v)
        end
        appliedSet[v] = true
    end

    local pending = {}
    for _, m in ipairs(known) do
        if not appliedSet[m.version] then pending[#pending + 1] = m end
    end
    table.sort(pending, function(a, b) return a.version < b.version end)
    return pending
end
