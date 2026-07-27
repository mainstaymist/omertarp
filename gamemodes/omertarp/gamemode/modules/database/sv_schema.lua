-- Schema DSL: table definitions in logical types, rendered to dialect-correct
-- DDL per driver, plus the result-type coercion registry that guarantees
-- backend-identical return types (M1 design review §4).
--
-- Everything in this file is pure (no engine calls), so the headless suite
-- covers it directly. Cross-file references (Internal.FormatValue) happen at
-- call time, never at include time — module files must not call siblings while
-- loading, because include order is alphabetical.

Omerta.DB = Omerta.DB or {}
Omerta.DB.Internal = Omerta.DB.Internal or {}
local Internal = Omerta.DB.Internal

-- Explicit NULL for params and row values (a bare nil breaks array length).
Omerta.DB.NULL = Omerta.DB.NULL or setmetatable({}, {
    __tostring = function() return "Omerta.DB.NULL" end,
})

-- Logical column types. Storage notes:
--   timestamp — unix epoch seconds as integer (no timezone/dialect parsing)
--   money     — integer cents (floats are wrong for money, always)
--   json/blob — opaque; callers encode/decode
local TYPE_INFO = {
    id        = { class = "number", sqlite = "INTEGER PRIMARY KEY AUTOINCREMENT",
                                    mysql  = "BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY", isKey = true },
    ref       = { class = "number", sqlite = "INTEGER", mysql = "BIGINT UNSIGNED" },
    int       = { class = "number", sqlite = "INTEGER", mysql = "INT" },
    bigint    = { class = "number", sqlite = "INTEGER", mysql = "BIGINT" },
    bool      = { class = "bool",   sqlite = "INTEGER", mysql = "TINYINT(1)" },
    timestamp = { class = "number", sqlite = "INTEGER", mysql = "BIGINT" },
    money     = { class = "number", sqlite = "INTEGER", mysql = "BIGINT" },
    json      = { class = "string", sqlite = "TEXT",    mysql = "MEDIUMTEXT" },
    blob      = { class = "string", sqlite = "BLOB",    mysql = "MEDIUMBLOB" },
    text      = { class = "string", sqlite = "TEXT" },  -- mysql special-cased on length
}

local IDENT = "^[a-z_][a-z0-9_]*$"

local tables = {}    -- name -> definition
local coercion = {}  -- column name -> class, or false when tables disagree

-- Returns true, or false + reason. Pure; exposed for tests.
function Internal.ValidateTableDef(name, def)
    if type(name) ~= "string" or not name:find(IDENT) then
        return false, "table name '" .. tostring(name) .. "' must match " .. IDENT
    end
    if type(def) ~= "table" or type(def.columns) ~= "table" or #def.columns == 0 then
        return false, "table '" .. name .. "' needs a non-empty columns array"
    end

    local seen, hasId = {}, false
    for i, col in ipairs(def.columns) do
        if type(col.name) ~= "string" or not col.name:find(IDENT) then
            return false, string.format("table '%s' column %d has a bad name", name, i)
        end
        if seen[col.name] then
            return false, string.format("table '%s' repeats column '%s'", name, col.name)
        end
        seen[col.name] = true
        local info = TYPE_INFO[col.type]
        if not info then
            return false, string.format("table '%s' column '%s' has unknown type '%s'",
                name, col.name, tostring(col.type))
        end
        if col.type == "id" then
            if hasId then return false, "table '" .. name .. "' declares two id columns" end
            hasId = true
        end
        if col.length ~= nil and (type(col.length) ~= "number" or col.length < 1) then
            return false, string.format("table '%s' column '%s' has a bad length", name, col.name)
        end
        if col.default ~= nil then
            local dt = type(col.default)
            if dt ~= "number" and dt ~= "string" and dt ~= "boolean" then
                return false, string.format("table '%s' column '%s' default must be a scalar", name, col.name)
            end
            -- MySQL (pre-8.0.13) cannot DEFAULT a TEXT column; require a length
            -- so it renders as VARCHAR on that dialect.
            if col.type == "text" and not col.length then
                return false, string.format(
                    "table '%s' column '%s': defaults on unbounded text are not portable — give it a length",
                    name, col.name)
            end
        end
    end

    if def.primary ~= nil then
        if hasId then return false, "table '" .. name .. "' has both an id column and a primary option" end
        if type(def.primary) ~= "table" or #def.primary == 0 then
            return false, "table '" .. name .. "' primary must be a non-empty column list"
        end
        for _, c in ipairs(def.primary) do
            if not seen[c] then
                return false, string.format("table '%s' primary references unknown column '%s'", name, c)
            end
        end
    end
    for _, group in ipairs(def.unique or {}) do
        for _, c in ipairs(group) do
            if not seen[c] then
                return false, string.format("table '%s' unique references unknown column '%s'", name, c)
            end
        end
    end
    for _, group in ipairs(def.indexes or {}) do
        for _, c in ipairs(group) do
            if not seen[c] then
                return false, string.format("table '%s' index references unknown column '%s'", name, c)
            end
        end
    end
    return true
end

-- Public API: declare a table's shape. Registers the definition and feeds the
-- coercion registry. Does not touch the database — creation happens through
-- migrations (M1 design review §4, §6).
function Omerta.DB.DefineTable(name, def)
    local ok, why = Internal.ValidateTableDef(name, def)
    if not ok then error(why, 2) end
    if tables[name] then error("table '" .. name .. "' defined twice", 2) end
    tables[name] = def

    for _, col in ipairs(def.columns) do
        local class = TYPE_INFO[col.type].class
        if coercion[col.name] == nil then
            coercion[col.name] = class
        elseif coercion[col.name] ~= class and coercion[col.name] ~= false then
            -- Two tables disagree about this column name's class: coercion for
            -- it would be a guess, so it is disabled and logged.
            coercion[col.name] = false
            Omerta.Log.Warn("db", "column name '%s' has conflicting types across tables; " ..
                "result coercion disabled for it", col.name)
        end
    end
end

function Internal.GetTableDef(name)
    return tables[name]
end

function Internal.CoercionClass(columnName)
    local class = coercion[columnName]
    if class == false then return nil end
    return class
end

--------------------------------------------------------------------------------
-- DDL rendering
--------------------------------------------------------------------------------

local function renderColumn(dialect, col)
    local info = TYPE_INFO[col.type]
    local sqlType
    if col.type == "text" and dialect == "mysql" then
        sqlType = (col.length and col.length <= 255) and ("VARCHAR(" .. col.length .. ")") or "TEXT"
    else
        sqlType = info[dialect]
    end

    local parts = { col.name, sqlType }
    if col.type ~= "id" then
        if col.null == false then parts[#parts + 1] = "NOT NULL" end
        if col.default ~= nil then
            parts[#parts + 1] = "DEFAULT " .. Internal.FormatValue(col.default, dialect)
        end
    end
    return table.concat(parts, " ")
end

-- Renders CREATE TABLE (+ index statements) for a registered table.
-- Returns an array of SQL statements — GMod's sql.Query runs one statement at
-- a time, so multi-statement strings are never produced.
-- Idempotent on both dialects: sqlite uses CREATE INDEX IF NOT EXISTS, mysql
-- declares its indexes inline in CREATE TABLE (mysql's CREATE INDEX has no
-- IF NOT EXISTS).
function Internal.RenderCreateTable(dialect, prefix, name)
    local def = tables[name]
    if not def then error("table '" .. tostring(name) .. "' is not defined", 2) end
    local full = prefix .. name

    local body = {}
    for _, col in ipairs(def.columns) do
        body[#body + 1] = renderColumn(dialect, col)
    end
    if def.primary then
        body[#body + 1] = "PRIMARY KEY (" .. table.concat(def.primary, ", ") .. ")"
    end
    for i, group in ipairs(def.unique or {}) do
        if dialect == "mysql" then
            body[#body + 1] = string.format("UNIQUE KEY uq_%s_%d (%s)", name, i, table.concat(group, ", "))
        else
            body[#body + 1] = "UNIQUE (" .. table.concat(group, ", ") .. ")"
        end
    end

    local statements = {}
    if dialect == "mysql" then
        for i, group in ipairs(def.indexes or {}) do
            body[#body + 1] = string.format("KEY idx_%s_%d (%s)", name, i, table.concat(group, ", "))
        end
        statements[1] = string.format(
            "CREATE TABLE IF NOT EXISTS %s (%s) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
            full, table.concat(body, ", "))
    else
        statements[1] = string.format("CREATE TABLE IF NOT EXISTS %s (%s)",
            full, table.concat(body, ", "))
        for i, group in ipairs(def.indexes or {}) do
            statements[#statements + 1] = string.format(
                "CREATE INDEX IF NOT EXISTS idx_%s_%d ON %s (%s)",
                name, i, full, table.concat(group, ", "))
        end
    end
    return statements
end

--------------------------------------------------------------------------------
-- Result-type coercion (M1 design review §4: identical return types on both
-- backends is a guarantee of this layer)
--------------------------------------------------------------------------------

-- GMod's sql library returns SQL NULL as the literal string "NULL" and cannot
-- distinguish it from a real 'NULL' text value. Converting it to nil is the
-- documented, uniform choice (matching MySQL, where NULL arrives as nil); the
-- corner case of a text column legitimately holding the four characters NULL
-- is accepted and documented.
Internal.SQLITE_NULL = "NULL"

-- Strict numeric shape for the unregistered-column heuristic: plain integers
-- and decimals only, so hex-looking or mixed strings are never touched.
local function looksNumeric(s)
    return s:find("^-?%d+$") ~= nil or s:find("^-?%d*%.%d+$") ~= nil
end

-- Coerces one value by declared class. Handles both directions:
-- sqlite strings -> numbers/bools, and mysql's TINYINT numbers -> bools.
function Internal.CoerceValue(class, v)
    if v == nil then return nil end
    if class == "number" then
        if type(v) == "string" then return tonumber(v) or v end
        return v
    elseif class == "bool" then
        if type(v) == "boolean" then return v end
        local n = tonumber(v)
        if n ~= nil then return n ~= 0 end
        return v
    end
    return v -- "string" class: leave untouched
end

-- Coerces a whole result row.
--   heuristic = true (sqlite): unregistered columns that look numeric become
--   numbers, so aggregates like COUNT(*) AS n match mysql's typing.
function Internal.CoerceRow(row, heuristic)
    local out = {}
    for k, v in pairs(row) do
        if heuristic and v == Internal.SQLITE_NULL then
            out[k] = nil
        else
            local class = Internal.CoercionClass(k)
            if class then
                out[k] = Internal.CoerceValue(class, v)
            elseif heuristic and type(v) == "string" and looksNumeric(v) then
                out[k] = tonumber(v)
            else
                out[k] = v
            end
        end
    end
    return out
end
