-- M2 accounts + audit: pure helpers, the UpsertIncrement builder, and the
-- full module flow (migration 1, repository, audit sink) against a mock
-- driver — the same technique that caught M1's queue bug before it shipped.

local DB_FILES = {
    "gamemodes/omertarp/gamemode/modules/database/sh_database.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_schema.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_sqlbuild.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_database.lua",
}
local ACCOUNT_FILES = {
    "gamemodes/omertarp/gamemode/modules/accounts/sh_accounts.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sv_accounts.lua",
}

-- Boots the two modules through the real lifecycle with a scripted driver:
-- registration -> OnLoad (schema + migration 1) -> mock install -> OnEnable
-- (database connects, migration 1 executes). Returns the mock.
local function bootAccounts(respond)
    ReloadCore()
    for _, f in ipairs(DB_FILES) do dofile(f) end
    for _, f in ipairs(ACCOUNT_FILES) do dofile(f) end
    Omerta.Module.FinishLoading()

    local mock = { dialect = "sqlite", heuristic = true, log = {}, txs = nil }
    function mock.Connect(_, cb) cb(nil) end
    function mock.RunQuery(sqlStr, params, cb)
        mock.log[#mock.log + 1] = sqlStr
        if sqlStr:find("SELECT version") then
            cb({}, nil)
        elseif respond then
            local rows, err, id = respond(sqlStr, params)
            cb(rows or {}, err, id)
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

    Omerta.Module.EnableAll()
    return mock
end

local function logContains(mock, needle)
    for _, s in ipairs(mock.log) do
        if s:find(needle, 1, true) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
suite("accounts.pure")
--------------------------------------------------------------------------------

local function loadPure()
    ReloadCore()
    for _, f in ipairs(DB_FILES) do dofile(f) end
    for _, f in ipairs(ACCOUNT_FILES) do dofile(f) end
end

check("upsert-increment renders per dialect with sorted params", function()
    loadPure()
    local B = Omerta.DB.Internal.BuildUpsertIncrement
    local s, p = B("sqlite", "account_stats", { account_id = 7, stat = "kills" }, "value", 3)
    assert(s:find("INSERT INTO {account_stats} (account_id, stat, value) VALUES (?, ?, ?)", 1, true), s)
    assert(s:find("ON CONFLICT(account_id, stat) DO UPDATE SET value = value + excluded.value", 1, true), s)
    assert(p[1] == 7 and p[2] == "kills" and p[3] == 3)
    local m = B("mysql", "account_stats", { account_id = 7, stat = "kills" }, "value", 3)
    assert(m:find("ON DUPLICATE KEY UPDATE value = value + VALUES(value)", 1, true), m)

    assert(not pcall(B, "sqlite", "t", {}, "value", 1), "empty keyRow must error")
    assert(not pcall(B, "sqlite", "t", { value = 1 }, "value", 1), "counter-as-key must error")
    assert(not pcall(B, "sqlite", "t", { a = 1 }, "value", "x"), "non-number delta must error")
end)

check("playtime delta math", function()
    loadPure()
    local D = Omerta.Accounts.Internal.PlaytimeDelta
    assert(D(100, nil, 160) == 60, "first flush counts from session start")
    assert(D(100, 150, 160) == 10, "later flushes count from last flush")
    assert(D(100, nil, 90) == 0, "clock going backwards never yields negative")
end)

check("retention cutoff math", function()
    loadPure()
    local R = Omerta.Accounts.Internal.RetentionCutoff
    assert(R(1000000, 0) == nil and R(1000000, nil) == nil, "retention off yields nil")
    assert(R(1000000, 2) == 1000000 - 2 * 86400)
end)

check("audit envelope maps to a row", function()
    loadPure()
    local row = Omerta.Accounts.Internal.AuditRow(
        { at = 5, event = "e", actor = nil, subject = "s", data = { marker = "x" } },
        Omerta.Util.Serialize)
    assert(row.at == 5 and row.event == "e")
    assert(row.actor == Omerta.DB.NULL, "missing actor becomes explicit NULL")
    assert(row.subject == "s")
    assert(type(row.data) == "string" and row.data:find("marker", 1, true), tostring(row.data))
end)

--------------------------------------------------------------------------------
suite("accounts.flow")
--------------------------------------------------------------------------------

check("migration 1 creates all four tables and is recorded", function()
    local mock = bootAccounts()
    assert(Omerta.DB.IsReady(), Omerta.DB.Status().phase)
    for _, t in ipairs({ "accounts", "account_flags", "account_stats", "audit" }) do
        assert(logContains(mock, "CREATE TABLE IF NOT EXISTS omerta_" .. t),
            "missing CREATE for " .. t)
    end
    assert(logContains(mock, "INSERT INTO omerta_migrations"), "migration not recorded")
end)

check("load-or-create: create path", function()
    local mock = bootAccounts(function(sqlStr)
        if sqlStr:find("SELECT %* FROM omerta_accounts") then return {} end
        if sqlStr:find("INSERT INTO omerta_accounts", 1, true) then return {}, nil, 42 end
        return {}
    end)
    local got, gotCreated
    Omerta.Accounts.Internal.Repo.LoadOrCreate("90000000000000001", 1000,
        function(account, err, created)
        assert(err == nil, tostring(err))
        got, gotCreated = account, created
    end)
    assert(gotCreated == true)
    assert(got.id == 42 and got.connections == 1 and got.playtime == 0)
    assert(next(got.flags) == nil and next(got.stats) == nil)
end)

check("load-or-create: load path bumps, coerces, and assembles", function()
    local mock = bootAccounts(function(sqlStr)
        if sqlStr:find("SELECT %* FROM omerta_accounts") then
            return { { id = "42", steamid64 = "90000000000000001", first_seen = "900",
                       last_seen = "950", playtime = "120", connections = "3" } }
        end
        if sqlStr:find("FROM omerta_account_flags", 1, true) then
            return { { flag = "watchlist", set_at = "910", set_by = "NULL", reason = "sus" } }
        end
        if sqlStr:find("FROM omerta_account_stats", 1, true) then
            return { { stat = "robberies", value = "5" } }
        end
        return {}
    end)
    local got
    Omerta.Accounts.Internal.Repo.LoadOrCreate("90000000000000001", 1000,
        function(account, err, created)
        assert(err == nil, tostring(err))
        assert(created == false)
        got = account
    end)
    assert(got.id == 42 and type(got.id) == "number", "id coerced")
    assert(got.connections == 4, "3 + this connection = 4, got " .. tostring(got.connections))
    assert(got.last_seen == 1000)
    assert(got.flags.watchlist and got.flags.watchlist.reason == "sus")
    assert(got.flags.watchlist.set_by == nil, "NULL set_by becomes nil")
    assert(got.stats.robberies == 5 and type(got.stats.robberies) == "number")
    assert(logContains(mock, "connections = connections + 1"), "bump SQL missing")
end)

check("flag upsert and stat increment reach the driver correctly", function()
    local mock = bootAccounts()
    Omerta.Accounts.Internal.Repo.SetFlag(42, "watchlist", "reason", "900", 111)
    assert(logContains(mock, "INSERT INTO omerta_account_flags"), "flag upsert missing")
    assert(logContains(mock, "ON CONFLICT(account_id, flag)"), "flag conflict clause missing")
    Omerta.Accounts.Internal.Repo.IncrementStat(42, "robberies", 3)
    assert(logContains(mock, "value = value + excluded.value"), "increment clause missing")
end)

check("audit sink persists envelopes through the repository", function()
    local mock = bootAccounts()
    Omerta.Log.SetAuditSink(function(envelope)
        Omerta.Accounts.Internal.Repo.InsertAudit(
            Omerta.Accounts.Internal.AuditRow(envelope, Omerta.Util.Serialize))
    end)
    Omerta.Log.Audit("test.event", { actor = "900", marker = "m2" })
    assert(logContains(mock, "INSERT INTO omerta_audit"), "audit insert missing")
end)

check("retention sweep issues the bounded delete", function()
    local mock = bootAccounts()
    Omerta.Accounts.Internal.Repo.SweepAudit(123456)
    assert(logContains(mock, "DELETE FROM omerta_audit WHERE at < ?"), "sweep SQL missing")
end)

check("selftest cleanup runs as one transaction", function()
    local mock = bootAccounts()
    local result
    Omerta.Accounts.Internal.Repo.DeleteAccountData(42, "900", function(ok) result = ok end)
    assert(result == true)
    assert(mock.txs and #mock.txs == 4, "expected 4 statements, got " .. tostring(mock.txs and #mock.txs))
end)
