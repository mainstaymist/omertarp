-- M1 database layer: headless coverage of the pure logic (schema DSL, DDL
-- rendering, escaping/interpolation, coercion, migration planning) plus a
-- full boot-flow test against a scripted mock driver.

local DB_FILES = {
    "gamemodes/omertarp/gamemode/modules/database/sv_schema.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_sqlbuild.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_database.lua",
}

local function loadDB()
    ReloadCore()
    for _, f in ipairs(DB_FILES) do dofile(f) end
end

--------------------------------------------------------------------------------
suite("db.schema")
--------------------------------------------------------------------------------

check("valid definition renders on both dialects", function()
    loadDB()
    Omerta.DB.DefineTable("things", {
        columns = {
            { name = "id",    type = "id" },
            { name = "label", type = "text", length = 32, null = false },
            { name = "count", type = "int", default = 0 },
            { name = "active", type = "bool", default = false },
        },
        unique = { { "label" } },
        indexes = { { "count" } },
    })

    local sqlite = Omerta.DB.Internal.RenderCreateTable("sqlite", "omerta_", "things")
    assert(#sqlite == 2, "sqlite should be CREATE TABLE + CREATE INDEX, got " .. #sqlite)
    assert(sqlite[1]:find("CREATE TABLE IF NOT EXISTS omerta_things", 1, true), sqlite[1])
    assert(sqlite[1]:find("id INTEGER PRIMARY KEY AUTOINCREMENT", 1, true), sqlite[1])
    assert(sqlite[1]:find("label TEXT NOT NULL", 1, true), sqlite[1])
    assert(sqlite[1]:find("count INTEGER DEFAULT 0", 1, true), sqlite[1])
    assert(sqlite[1]:find("UNIQUE (label)", 1, true), sqlite[1])
    assert(sqlite[2]:find("CREATE INDEX IF NOT EXISTS idx_things_1 ON omerta_things (count)", 1, true), sqlite[2])

    local mysql = Omerta.DB.Internal.RenderCreateTable("mysql", "omerta_", "things")
    assert(#mysql == 1, "mysql renders indexes inline, got " .. #mysql .. " statements")
    assert(mysql[1]:find("BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY", 1, true), mysql[1])
    assert(mysql[1]:find("label VARCHAR(32) NOT NULL", 1, true), mysql[1])
    assert(mysql[1]:find("UNIQUE KEY uq_things_1 (label)", 1, true), mysql[1])
    assert(mysql[1]:find("KEY idx_things_1 (count)", 1, true), mysql[1])
    assert(mysql[1]:find("ENGINE=InnoDB DEFAULT CHARSET=utf8mb4", 1, true), mysql[1])
end)

check("composite primary key renders; long text becomes TEXT on mysql", function()
    loadDB()
    Omerta.DB.DefineTable("knowledge", {
        columns = {
            { name = "observer", type = "ref", null = false },
            { name = "subject",  type = "ref", null = false },
            { name = "notes",    type = "text", length = 4000 },
        },
        primary = { "observer", "subject" },
    })
    local mysql = Omerta.DB.Internal.RenderCreateTable("mysql", "p_", "knowledge")
    assert(mysql[1]:find("PRIMARY KEY (observer, subject)", 1, true), mysql[1])
    assert(mysql[1]:find("notes TEXT", 1, true), mysql[1])
end)

check("definition validation rejects the important mistakes", function()
    loadDB()
    local V = Omerta.DB.Internal.ValidateTableDef
    assert(not V("Bad-Name", { columns = { { name = "a", type = "int" } } }))
    assert(not V("t", { columns = {} }))
    assert(not V("t", { columns = { { name = "a", type = "wat" } } }))
    assert(not V("t", { columns = { { name = "a", type = "int" }, { name = "a", type = "int" } } }))
    assert(not V("t", { columns = { { name = "a", type = "id" }, { name = "b", type = "id" } } }))
    assert(not V("t", { columns = { { name = "a", type = "id" } }, primary = { "a" } }))
    assert(not V("t", { columns = { { name = "a", type = "int" } }, unique = { { "ghost" } } }))
    -- defaults on unbounded text are not portable to mysql
    assert(not V("t", { columns = { { name = "a", type = "text", default = "x" } } }))
    assert(V("t", { columns = { { name = "a", type = "text", length = 10, default = "x" } } }))
end)

expectError("duplicate DefineTable errors", "defined twice", function()
    loadDB()
    local def = { columns = { { name = "a", type = "int" } } }
    Omerta.DB.DefineTable("dup", def)
    Omerta.DB.DefineTable("dup", def)
end)

--------------------------------------------------------------------------------
suite("db.sqlbuild")
--------------------------------------------------------------------------------

check("string escaping: quotes doubled, mysql backslashes, NUL rejected", function()
    loadDB()
    local E = Omerta.DB.Internal.EscapeString
    assert(E("O'Brien", "sqlite") == "O''Brien")
    assert(E("a\\b", "sqlite") == "a\\b")          -- sqlite: backslash is literal
    assert(E("a\\b", "mysql") == "a\\\\b")          -- mysql: backslash escaped
    assert(not pcall(E, "bad\0byte", "sqlite"))
end)

check("value formatting: numbers, bools, NULL, rejections", function()
    loadDB()
    local F = Omerta.DB.Internal.FormatValue
    assert(F(42, "sqlite") == "42")
    assert(F(-7, "sqlite") == "-7")
    assert(F(2.5, "sqlite") == "2.5")
    assert(F(true, "sqlite") == "1" and F(false, "sqlite") == "0")
    assert(F(Omerta.DB.NULL, "sqlite") == "NULL")
    assert(F("it's", "sqlite") == "'it''s'")
    assert(not pcall(F, 0 / 0, "sqlite"))            -- NaN
    assert(not pcall(F, math.huge, "sqlite"))        -- inf
    assert(not pcall(F, {}, "sqlite"))               -- table
    assert(not pcall(F, nil, "sqlite"))              -- bare nil: use Omerta.DB.NULL
end)

check("interpolation replaces in order and counts placeholders", function()
    loadDB()
    local I = Omerta.DB.Internal.Interpolate
    local out = I("SELECT * FROM t WHERE a = ? AND b = ?", { "x'y", 5 }, "sqlite")
    assert(out == "SELECT * FROM t WHERE a = 'x''y' AND b = 5", out)
    assert(not pcall(I, "a = ?", {}, "sqlite"))          -- too few
    assert(not pcall(I, "a = ?", { 1, 2 }, "sqlite"))    -- too many
end)

check("injection through a value stays inert text", function()
    loadDB()
    local out = Omerta.DB.Internal.Interpolate(
        "INSERT INTO t (name) VALUES (?)", { "x'); DROP TABLE t;--" }, "sqlite")
    -- The hostile quote is doubled, so the value never closes the literal.
    assert(out == "INSERT INTO t (name) VALUES ('x''); DROP TABLE t;--')", out)
end)

check("table substitution applies the prefix", function()
    loadDB()
    local S = Omerta.DB.Internal.SubstituteTables
    assert(S("SELECT * FROM {accounts} JOIN {characters}", "omerta_")
        == "SELECT * FROM omerta_accounts JOIN omerta_characters")
    assert(S("no braces here ? {}", "omerta_") == "no braces here ? {}")
end)

check("insert builds sorted deterministic SQL", function()
    loadDB()
    local sqlStr, params = Omerta.DB.Internal.BuildInsert("things", {
        zeta = 1, alpha = "a", mid = true,
    })
    assert(sqlStr == "INSERT INTO {things} (alpha, mid, zeta) VALUES (?, ?, ?)", sqlStr)
    assert(params[1] == "a" and params[2] == true and params[3] == 1)
end)

check("upsert renders per dialect", function()
    loadDB()
    local row = { label = "up", count = 2 }
    local s = Omerta.DB.Internal.BuildUpsert("sqlite", "things", row, { "label" })
    assert(s:find("ON CONFLICT(label) DO UPDATE SET count = excluded.count", 1, true), s)
    local m = Omerta.DB.Internal.BuildUpsert("mysql", "things", row, { "label" })
    assert(m:find("ON DUPLICATE KEY UPDATE count = VALUES(count)", 1, true), m)
    -- all columns are keys: sqlite DO NOTHING, mysql self-assignment
    local s2 = Omerta.DB.Internal.BuildUpsert("sqlite", "things", { label = "x" }, { "label" })
    assert(s2:find("DO NOTHING", 1, true), s2)
    local m2 = Omerta.DB.Internal.BuildUpsert("mysql", "things", { label = "x" }, { "label" })
    assert(m2:find("UPDATE label = label", 1, true), m2)
    assert(not pcall(Omerta.DB.Internal.BuildUpsert, "sqlite", "things", { a = 1 }, { "missing" }))
end)

--------------------------------------------------------------------------------
suite("db.coerce")
--------------------------------------------------------------------------------

check("registered columns coerce by declared class, both directions", function()
    loadDB()
    Omerta.DB.DefineTable("people", {
        columns = {
            { name = "id",     type = "id" },
            { name = "cash",   type = "money" },
            { name = "hidden", type = "bool" },
            { name = "alias",  type = "text", length = 32 },
        },
    })
    local Internal = Omerta.DB.Internal
    -- sqlite direction: strings in
    local row = Internal.CoerceRow({ id = "3", cash = "1250", hidden = "1", alias = "42" }, true)
    assert(row.id == 3 and row.cash == 1250)
    assert(row.hidden == true, "bool from sqlite '1'")
    assert(row.alias == "42", "registered text protected from the numeric heuristic")
    -- mysql direction: TINYINT bools arrive as numbers
    local row2 = Internal.CoerceRow({ hidden = 0, cash = 99 }, false)
    assert(row2.hidden == false and row2.cash == 99)
end)

check("heuristic covers aggregates on sqlite only", function()
    loadDB()
    local Internal = Omerta.DB.Internal
    local r = Internal.CoerceRow({ n = "17", avg = "2.5", word = "17abc", hex = "0x10" }, true)
    assert(r.n == 17 and r.avg == 2.5)
    assert(r.word == "17abc", "mixed strings untouched")
    assert(r.hex == "0x10", "hex-looking strings untouched")
    local m = Internal.CoerceRow({ n = "17" }, false)
    assert(m.n == "17", "no heuristic on mysql rows")
end)

check("GMod's NULL-as-string becomes nil on sqlite rows", function()
    loadDB()
    local r = Omerta.DB.Internal.CoerceRow({ note = "NULL", label = "real" }, true)
    assert(r.note == nil and r.label == "real")
end)

check("conflicting column types across tables disable coercion for that name", function()
    loadDB()
    Omerta.DB.DefineTable("one", { columns = { { name = "code", type = "int" } } })
    Omerta.DB.DefineTable("two", { columns = { { name = "code", type = "text", length = 8 } } })
    assert(Omerta.DB.Internal.CoercionClass("code") == nil)
end)

--------------------------------------------------------------------------------
suite("db.migrate_plan")
--------------------------------------------------------------------------------

check("pending migrations sort ascending and skip applied", function()
    loadDB()
    local known = {
        { version = 3, name = "c" }, { version = 1, name = "a" }, { version = 2, name = "b" },
    }
    local pending = assert(Omerta.DB.Internal.PlanMigrations({ 1 }, known))
    assert(#pending == 2 and pending[1].version == 2 and pending[2].version == 3)
end)

check("database ahead of code is refused", function()
    loadDB()
    local pending, err = Omerta.DB.Internal.PlanMigrations({ 1, 99 }, { { version = 1, name = "a" } })
    assert(pending == nil and err:find("refusing"), tostring(err))
end)

check("duplicate registered versions are refused", function()
    loadDB()
    local pending, err = Omerta.DB.Internal.PlanMigrations({},
        { { version = 1, name = "a" }, { version = 1, name = "b" } })
    assert(pending == nil and err:find("twice"), tostring(err))
end)

--------------------------------------------------------------------------------
suite("db.mysqloo_binary")
--------------------------------------------------------------------------------

check("binary name resolves per platform and branch", function()
    ReloadCore()
    dofile("gamemodes/omertarp/gamemode/modules/database/sv_schema.lua")
    dofile("gamemodes/omertarp/gamemode/modules/database/sv_driver_mysql.lua")
    local N = Omerta.DB.Internal.MysqlooBinaryName
    assert(N(true, false)  == "gmsv_mysqloo_win32.dll",   N(true, false))
    assert(N(true, true)   == "gmsv_mysqloo_win64.dll",   N(true, true))
    -- upstream ships the linux builds with a .dll extension too
    assert(N(false, false) == "gmsv_mysqloo_linux.dll",   N(false, false))
    assert(N(false, true)  == "gmsv_mysqloo_linux64.dll", N(false, true))
end)

--------------------------------------------------------------------------------
suite("db.flow") -- full boot flow against a scripted mock driver
--------------------------------------------------------------------------------

-- Builds a mock driver and installs it as the "sqlite" driver (the default
-- backend), so Internal.Start() exercises the real lifecycle code.
local function mockDriver(opts)
    opts = opts or {}
    local mock = { dialect = "sqlite", heuristic = true, log = {}, txs = nil }
    function mock.Connect(_, cb)
        if opts.failConnect then cb("mock connect failure") else cb(nil) end
    end
    function mock.RunQuery(sqlStr, params, cb)
        mock.log[#mock.log + 1] = sqlStr
        if sqlStr:find("SELECT version") then
            cb(opts.appliedRows or {}, nil)
        elseif opts.respond then
            local rows, err, id = opts.respond(sqlStr, params)
            cb(rows, err, id)
        else
            cb({}, nil, 1)
        end
    end
    function mock.RunTransaction(stmts, cb)
        mock.txs = stmts
        cb(true, nil)
    end
    Omerta.DB.Internal.Drivers = Omerta.DB.Internal.Drivers or {}
    Omerta.DB.Internal.Drivers.sqlite = mock
    return mock
end

check("boot reaches ready, flushes queued work, fires WhenReady in order", function()
    loadDB()
    local mock = mockDriver()

    local events = {}
    Omerta.DB.WhenReady(function() events[#events + 1] = "ready_a" end)
    Omerta.DB.Query("SELECT * FROM {accounts}", {}, function(rows, err)
        events[#events + 1] = "queued_query"
        assert(err == nil and rows ~= nil)
    end)
    assert(Omerta.DB.Status().queued == 1, "query should queue before start")

    Omerta.DB.Internal.Start()

    assert(Omerta.DB.IsReady(), "phase: " .. Omerta.DB.Status().phase)
    assert(events[1] == "queued_query" and events[2] == "ready_a",
        "order was: " .. table.concat(events, ","))
    -- the queued query went out with the prefix applied
    local found = false
    for _, s in ipairs(mock.log) do
        if s == "SELECT * FROM omerta_accounts" then found = true end
    end
    assert(found, "prefixed SQL not seen by driver")
    -- WhenReady after ready fires immediately (deferred = immediate headless)
    local late = false
    Omerta.DB.WhenReady(function() late = true end)
    assert(late)
end)

check("registered migration executes and is recorded", function()
    loadDB()
    local mock = mockDriver()
    Omerta.DB.DefineTable("widgets", {
        columns = { { name = "id", type = "id" }, { name = "label", type = "text", length = 16 } },
    })
    Omerta.DB.AddMigration(1, "create widgets", function(m)
        m:CreateTable("widgets")
        m:Query("INSERT INTO {widgets} (label) VALUES (?)", { "seed" })
    end)

    Omerta.DB.Internal.Start()

    assert(Omerta.DB.IsReady())
    local sawCreate, sawSeed, sawRecord = false, false, false
    for _, s in ipairs(mock.log) do
        if s:find("CREATE TABLE IF NOT EXISTS omerta_widgets", 1, true) then sawCreate = true end
        if s:find("INSERT INTO omerta_widgets", 1, true) then sawSeed = true end
        if s:find("INSERT INTO omerta_migrations", 1, true) then sawRecord = true end
    end
    assert(sawCreate and sawSeed and sawRecord,
        "migration trail incomplete: " .. table.concat(mock.log, " | "))
end)

check("database ahead of code fails loudly and fails queued work", function()
    loadDB()
    mockDriver({ appliedRows = { { version = "99" } } })

    local failedWith
    Omerta.DB.Query("SELECT 1", {}, function(_, err) failedWith = err end)
    Omerta.DB.Internal.Start()

    local s = Omerta.DB.Status()
    assert(s.phase == "failed", s.phase)
    assert(s.lastError:find("refusing"), tostring(s.lastError))
    assert(failedWith and failedWith:find("failed state"), tostring(failedWith))
    -- and new work is rejected, not queued
    local rejected
    Omerta.DB.Query("SELECT 2", {}, function(_, err) rejected = err end)
    assert(rejected and rejected:find("failed"), tostring(rejected))
end)

check("results are coerced on the way out", function()
    loadDB()
    Omerta.DB.DefineTable("scores", {
        columns = { { name = "id", type = "id" }, { name = "points", type = "int" },
                    { name = "won", type = "bool" } },
    })
    mockDriver({ respond = function(sqlStr)
        if sqlStr:find("FROM omerta_scores", 1, true) then
            return { { id = "5", points = "120", won = "1", note = "NULL" } }, nil
        end
        return {}, nil
    end })

    Omerta.DB.Internal.Start()
    local got
    Omerta.DB.QueryOne("SELECT * FROM {scores}", {}, function(row) got = row end)
    assert(got and got.id == 5 and got.points == 120 and got.won == true and got.note == nil,
        "coercion failed")
end)

check("transactions collect substituted statements and report once", function()
    loadDB()
    local mock = mockDriver()
    Omerta.DB.Internal.Start()

    local result
    Omerta.DB.Transaction(function(tx)
        tx:Insert("widgets", { label = "a" })
        tx:Query("UPDATE {widgets} SET label = ? WHERE label = ?", { "b", "a" })
    end, function(ok, err) result = ok end)

    assert(result == true)
    assert(mock.txs and #mock.txs == 2, "expected 2 statements")
    assert(mock.txs[1].sql:find("INSERT INTO omerta_widgets", 1, true), mock.txs[1].sql)
    assert(mock.txs[2].sql:find("UPDATE omerta_widgets", 1, true), mock.txs[2].sql)
end)

check("connect failure lands in down, not a crash", function()
    loadDB()
    mockDriver({ failConnect = true })
    Omerta.DB.Internal.Start()
    local s = Omerta.DB.Status()
    assert(s.phase == "down", s.phase)
    assert(not Omerta.DB.IsReady())
end)

expectError("AddMigration validates its inputs", "positive integer", function()
    loadDB()
    Omerta.DB.AddMigration(0, "bad", function() end)
end)
