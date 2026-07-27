-- M4 characters: name validation (the rules players live with), creation-spec
-- and portrait validation, and the full creation/retirement flow against the
-- mock driver.

local MODULE_FILES = {
    "gamemodes/omertarp/gamemode/modules/database/sh_database.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_schema.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_sqlbuild.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_database.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sh_accounts.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sv_accounts.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sh_seasons.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sv_seasons.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sh_characters.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sv_characters.lua",
}

local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

-- Boots all four modules with a scripted driver, and (unless suppressed)
-- brings a season to active so character creation is permitted.
local function boot(respond)
    loadModules()
    Omerta.Module.FinishLoading()

    local mock = { dialect = "sqlite", heuristic = true, log = {}, nextInsertId = 1 }
    function mock.Connect(_, cb) cb(nil) end
    function mock.RunQuery(sqlStr, params, cb)
        mock.log[#mock.log + 1] = sqlStr
        if sqlStr:find("SELECT version") then cb({}, nil) return end
        if respond then
            local rows, err, id = respond(sqlStr, params, mock)
            if rows ~= nil or err ~= nil or id ~= nil then cb(rows or {}, err, id) return end
        end
        local id = mock.nextInsertId
        mock.nextInsertId = mock.nextInsertId + 1
        cb({}, nil, id)
    end
    function mock.RunTransaction(stmts, cb) mock.txs = stmts; cb(true, nil) end
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
suite("characters.names")
--------------------------------------------------------------------------------

check("accepts and normalizes ordinary names", function()
    loadModules()
    local V = Omerta.Characters.ValidateName
    local f, l, key = V("salvatore", "MARINO")
    assert(f == "Salvatore" and l == "Marino", tostring(f) .. " " .. tostring(l))
    assert(key == "salvatore marino", key)

    -- Deliberate capitalization is preserved; single-case input is title-cased.
    assert(select(2, V("Tony", "McDonald")) == "McDonald", "mixed case must survive")
    assert(select(2, V("Tony", "mcdonald")) == "Mcdonald")
    assert(select(2, V("Tony", "o'brien")) == "O'Brien", "letter after apostrophe")
    assert(select(2, V("Tony", "lo-bianco")) == "Lo-Bianco", "letter after hyphen")
    assert(select(2, V("Tony", "lo bianco")) == "Lo Bianco", "multi-word surnames allowed")
    -- Whitespace is normalized, not rejected.
    assert(select(1, V("  tony  ", "marino")) == "Tony")
end)

check("accented names are accepted and measured by character", function()
    loadModules()
    local V = Omerta.Characters.ValidateName
    local f = V("José", "Marino")
    assert(f ~= nil, "accented first name should pass")
    -- 4 characters, 5 bytes: byte-length checks would misjudge these.
    assert(Omerta.Characters.UTF8Len("José") == 4, Omerta.Characters.UTF8Len("José"))
end)

check("rejects the dangerous and the silly", function()
    loadModules()
    local V = Omerta.Characters.ValidateName
    local function rejects(first, last, label)
        local ok, reason = V(first, last)
        assert(ok == nil, (label or (tostring(first) .. "/" .. tostring(last))) ..
            " should be rejected")
        assert(type(reason) == "string" and #reason > 0, "reason required")
    end
    rejects("Tony2", "Marino", "digits")
    rejects("<b>Tony</b>", "Marino", "markup")
    rejects("Tony\nMarino", "Smith", "control characters")
    rejects("T", "Marino", "too short")
    rejects(string.rep("a", 25), "Marino", "too long")
    rejects("'Tony", "Marino", "leading punctuation")
    rejects("Tony-", "Marino", "trailing punctuation")
    rejects("To--ny", "Marino", "doubled punctuation")
    rejects("", "Marino", "empty")
    rejects("   ", "Marino", "whitespace only")
    rejects(nil, "Marino", "missing")
    rejects("Tony", 42, "non-string")
end)

--------------------------------------------------------------------------------
suite("characters.validation")
--------------------------------------------------------------------------------

check("creation spec validation", function()
    loadModules()
    local V = Omerta.Characters.Internal.ValidateSpec
    local spec = V(1, 0, 1)
    assert(spec and spec.model == Omerta.Characters.MODELS[1] and spec.path == "criminal")
    assert(V(3, 2, 3).path == "independent")
    assert(V(999, 0, 1) == nil, "unknown model index must fail")
    assert(V(1, 0, 99) == nil, "unknown path index must fail")
    assert(V(1, -1, 1) == nil, "negative skin must fail")
    assert(V(1, 1.5, 1) == nil, "fractional skin must fail")
end)

check("portrait validation enforces size, base64 and JPEG magic", function()
    loadModules()
    local V = Omerta.Characters.Internal.ValidatePortrait

    -- Inputs are base64 TEXT; the decoder is injected so the test does not
    -- depend on an engine base64 implementation.
    local jpegBytes = string.char(0xFF, 0xD8, 0xFF) .. "payload"
    local pngBytes = string.char(0x89) .. "PNG" .. "payload"
    local encoded = "QUJDREVGRw=="  -- valid base64 charset; decoder decides bytes

    local function decodeTo(bytes) return function() return bytes end end

    assert(V(encoded, 1000, decodeTo(jpegBytes)) ~= nil, "valid JPEG should pass")
    assert(V("", 1000, decodeTo(jpegBytes)) == nil, "empty")
    assert(V(nil, 1000, decodeTo(jpegBytes)) == nil, "nil")
    assert(V(encoded, 4, decodeTo(jpegBytes)) == nil, "over the byte cap")
    assert(V("not base64 !!", 1000, decodeTo(jpegBytes)) == nil, "invalid base64 charset")
    assert(V(encoded, 1000, decodeTo(pngBytes)) == nil, "PNG must be rejected")
    assert(V(encoded, 1000, decodeTo("AAAA")) == nil, "wrong magic bytes")
    assert(V(encoded, 1000, decodeTo("")) == nil, "empty decode")
    assert(V(encoded, 1000, function() return nil end) == nil, "undecodable")
end)

--------------------------------------------------------------------------------
suite("characters.flow")
--------------------------------------------------------------------------------

-- A fake player: enough surface for the account and season caches.
local function fakePlayer(sid)
    return {
        SteamID64 = function() return sid end,
        IsBot = function() return false end,
    }
end

-- Brings a season to active and loads an account into the M2 cache, returning
-- the player handle and the account.
local function activeSeasonAndAccount(mock, sid)
    Omerta.Seasons.Create({ label = "S" }, function() end)
    Omerta.Seasons.Start(1, "test", function() end)
    local ply = fakePlayer(sid)
    Omerta.Accounts.Internal.OnPlayerConnected(ply)
    return ply, Omerta.Accounts.Get(ply)
end

local function seasonResponder(state)
    return function(sqlStr, params, mock)
        if sqlStr:find("INSERT INTO omerta_seasons", 1, true) then return {}, nil, 1 end
        if sqlStr:find("FROM omerta_seasons WHERE id", 1, true) then
            return { { id = "1", label = "S", state = state.value,
                       ruleset_version = "1", created_at = "100" } }
        end
        if sqlStr:find("UPDATE omerta_seasons SET state", 1, true) then
            state.value = params[1]
            return {}
        end
        return nil
    end
end

check("migration 3 creates the characters table with its unique index", function()
    local mock = boot()
    assert(Omerta.DB.IsReady())
    assert(logContains(mock, "CREATE TABLE IF NOT EXISTS omerta_characters"), "DDL missing")
    assert(logContains(mock, "UNIQUE (season_id, name_key)"), "season-unique index missing")
end)

check("creation refuses without an active season", function()
    boot()
    local ply = fakePlayer("90000000000000010")
    Omerta.Accounts.Internal.OnPlayerConnected(ply)
    local err
    Omerta.Characters.Create(ply, { first = "Tony", last = "Marino",
        modelIndex = 1, skin = 0, pathIndex = 1 }, function(_, e) err = e end)
    assert(err == "no active season", tostring(err))
end)

check("creation validates, persists, sets the path, and caches", function()
    local state = { value = "setup" }
    local mock = boot(seasonResponder(state))
    local ply = activeSeasonAndAccount(mock, "90000000000000011")

    local created, err
    Omerta.Characters.Create(ply, { first = "salvatore", last = "o'brien",
        modelIndex = 2, skin = 1, pathIndex = 3 }, function(c, e) created, err = c, e end)

    assert(created, "creation failed: " .. tostring(err))
    assert(created.first_name == "Salvatore" and created.last_name == "O'Brien")
    assert(created.name_key == "salvatore o'brien")
    assert(created.model == Omerta.Characters.MODELS[2] and created.skin == 1)
    assert(created.status == "alive")
    assert(Omerta.Characters.Get(ply) == created, "character should be cached")
    assert(logContains(mock, "INSERT INTO omerta_characters"), "insert missing")
    -- The path went through M3's matrix, not around it.
    assert(Omerta.Seasons.GetPath(ply) == "independent", tostring(Omerta.Seasons.GetPath(ply)))
end)

check("a bad name never reaches the database", function()
    local state = { value = "setup" }
    local mock = boot(seasonResponder(state))
    local ply = activeSeasonAndAccount(mock, "90000000000000012")
    local before = #mock.log

    local err
    Omerta.Characters.Create(ply, { first = "Tony99", last = "Marino",
        modelIndex = 1, skin = 0, pathIndex = 1 }, function(_, e) err = e end)
    assert(err and err:find("letters"), tostring(err))
    for i = before + 1, #mock.log do
        assert(not mock.log[i]:find("INSERT INTO omerta_characters", 1, true),
            "invalid name produced an insert")
    end
end)

check("one living character per account (D-012)", function()
    local state = { value = "setup" }
    local existing = false
    local mock = boot(function(sqlStr, params, m)
        local seasonRows = seasonResponder(state)(sqlStr, params, m)
        if seasonRows ~= nil then return seasonRows end
        if sqlStr:find("FROM omerta_characters WHERE account_id", 1, true) and existing then
            return { { id = "7", account_id = params[1], season_id = params[2],
                       first_name = "Tony", last_name = "Marino", name_key = "tony marino",
                       status = "alive", model = Omerta.Characters.MODELS[1], skin = "0",
                       created_at = "100" } }
        end
        return nil
    end)
    local ply = activeSeasonAndAccount(mock, "90000000000000013")

    existing = true
    local err
    Omerta.Characters.Create(ply, { first = "Vincent", last = "Costa",
        modelIndex = 1, skin = 0, pathIndex = 1 }, function(_, e) err = e end)
    assert(err and err:find("already have a living character"), tostring(err))
    -- The existing character is loaded instead of stranding the player.
    local loaded = Omerta.Characters.Get(ply)
    assert(loaded and loaded.id == 7, "existing character should have been loaded")
end)

check("insert failure is reported as a taken name", function()
    local state = { value = "setup" }
    local mock = boot(function(sqlStr, params, m)
        local seasonRows = seasonResponder(state)(sqlStr, params, m)
        if seasonRows ~= nil then return seasonRows end
        if sqlStr:find("INSERT INTO omerta_characters", 1, true) then
            return nil, "UNIQUE constraint failed: omerta_characters.name_key"
        end
        return nil
    end)
    local ply = activeSeasonAndAccount(mock, "90000000000000014")

    local err
    Omerta.Characters.Create(ply, { first = "Tony", last = "Marino",
        modelIndex = 1, skin = 0, pathIndex = 1 }, function(_, e) err = e end)
    assert(err and err:find("already taken"), tostring(err))
    assert(Omerta.Characters.Get(ply) == nil, "failed creation must not cache")
end)

check("season end retires every living character (D-010)", function()
    local state = { value = "setup" }
    local mock = boot(seasonResponder(state))
    local ply = activeSeasonAndAccount(mock, "90000000000000015")
    Omerta.Characters.Create(ply, { first = "Tony", last = "Marino",
        modelIndex = 1, skin = 0, pathIndex = 1 }, function() end)
    assert(Omerta.Characters.Get(ply) ~= nil)

    -- Drive the listener directly: hook.Run is engine-only.
    Omerta.Characters.Internal.Repo.RetireAllInSeason(1, os.time(), function(ok) end)
    assert(logContains(mock, "UPDATE omerta_characters SET status = ?"), "bulk retire missing")
end)

check("retire and status transitions are guarded", function()
    local mock = boot()
    local bad
    Omerta.Characters.SetStatus(5, "alive", "nope", function(ok, err) bad = err end)
    assert(bad and bad:find("retired or dead"), tostring(bad))

    local ok
    Omerta.Characters.Retire(5, "test", function(o) ok = o end)
    assert(ok == true)
    assert(logContains(mock, "UPDATE omerta_characters SET status = ?"), "status update missing")
end)
