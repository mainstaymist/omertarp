-- M3 seasons: the D-009 transition matrix exhaustively, lifecycle rules, the
-- one-active invariant, and the full module flow (migration 2, lifecycle,
-- path transitions) against a mock driver.

local MODULE_FILES = {
    "gamemodes/omertarp/gamemode/modules/database/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/database/sh_database.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_schema.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_sqlbuild.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_database.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sh_accounts.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sv_accounts.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sh_seasons.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sv_seasons.lua",
}

local function bootSeasons(respond)
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
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
suite("seasons.rules")
--------------------------------------------------------------------------------

local function loadRules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

check("the D-009 transition matrix, every cell", function()
    loadRules()
    local Can = Omerta.Seasons.Internal.CanTransition
    local froms = { "none", "criminal", "police", "independent" }
    local targets = { "criminal", "police", "independent" }
    local reasons = { "initial_choice", "family_recruitment",
                      "police_resignation", "police_expulsion", "bogus_reason" }

    local function allowed(from, to, reason)
        if from == "none" then return reason == "initial_choice" end
        if from == "independent" and to == "criminal" then return reason == "family_recruitment" end
        if from == "police" and to == "independent" then
            return reason == "police_resignation" or reason == "police_expulsion"
        end
        return false
    end

    for _, from in ipairs(froms) do
        for _, to in ipairs(targets) do
            for _, reason in ipairs(reasons) do
                local current = from ~= "none" and from or nil
                local got = Can(current, to, reason) == true
                local want = allowed(from, to, reason) and from ~= to
                assert(got == want, string.format("%s -> %s (%s): got %s, want %s",
                    from, to, reason, tostring(got), tostring(want)))
            end
        end
    end
    -- degenerate inputs
    assert(not Can(nil, "wizard", "initial_choice"), "unknown target must fail")
    assert(not Can("criminal", "criminal", "initial_choice"), "same-path must fail")
end)

check("lifecycle rules", function()
    loadRules()
    local Can = Omerta.Seasons.Internal.CanLifecycle
    assert(Can("setup", "start"))
    assert(not Can("active", "start"))
    assert(not Can("ended", "start"))
    assert(Can("active", "end"))
    assert(not Can("setup", "end"))
    assert(not Can("ended", "end"))
    assert(not Can("active", "explode"))
end)

check("sole-setup-season resolution for argument-less staff commands", function()
    loadRules()
    local Pick = Omerta.Seasons.Internal.PickSoleSetupSeason
    assert(Pick({ { id = 3, state = "setup" } }) == 3)
    -- ignores seasons that are not waiting in setup
    assert(Pick({ { id = 1, state = "ended" }, { id = 2, state = "active" },
                  { id = 3, state = "setup" } }) == 3)
    local id, why = Pick({ { id = 1, state = "ended" } })
    assert(id == nil and why:find("no season is waiting"), tostring(why))
    id, why = Pick({ { id = 1, state = "setup" }, { id = 2, state = "setup" } })
    assert(id == nil and why:find("several seasons"), tostring(why))
    assert(why:find("1, 2", 1, true), "ambiguity message should name the ids: " .. why)
end)

-- Seasons are numbered, not named (project lead, 2026-08-01). The number is
-- pure arithmetic over the rows that exist — existing seasons in, next number
-- out — which is the whole reason it is worth pinning here: the alternative is
-- discovering the sequence was wrong a season after it mattered.
check("a season's number is read off the label, never parsed out of a name", function()
    loadRules()
    local NumberOf = Omerta.Seasons.NumberOf
    assert(NumberOf({ label = "10" }) == 10, "a numbered season is its number")
    assert(NumberOf({ label = 10 }) == 10, "and reads the same if the backend hands back a number")
    assert(NumberOf({ label = "1" }) == 1)

    -- Everything that is not a plain run of digits has NO number. Recovering
    -- one from the middle of a name is the exact mistake the ruling refuses:
    -- "Season 10" and "The 10th of Never" would become the same season.
    assert(NumberOf({ label = "Season 10" }) == nil, "a name is not a number")
    assert(NumberOf({ label = "The Winter of Knives" }) == nil)
    assert(NumberOf({ label = "__selftest__" }) == nil, "the self-test's own row")
    assert(NumberOf({ label = "0" }) == nil, "there is no season zero")
    assert(NumberOf({ label = "" }) == nil)
    assert(NumberOf({ label = "10a" }) == nil and NumberOf({ label = " 10" }) == nil)
    assert(NumberOf({}) == nil and NumberOf(nil) == nil, "degenerate input answers nil")

    -- What it is called follows from that, in one place, for the server log and
    -- the client's front end alike.
    assert(Omerta.Seasons.Title({ label = "10" }) == "Season 10")
    assert(Omerta.Seasons.Title({ label = "The Winter of Knives" }) == "The Winter of Knives",
        "a legacy named season keeps the name the operator gave it")
    assert(Omerta.Seasons.Title(nil) == "no season")
end)

check("a season that predates numbering still has a number", function()
    loadRules()
    local Ordinal = Omerta.Seasons.OrdinalOf

    -- The case the field actually hit. Numbering arrived AFTER the seasons
    -- did, so the season everybody was running had a typed label, read as no
    -- number at all, and the front end showed a bare "THE CITY".
    local rows = { { id = 7, label = "The Long Winter" } }
    assert(Ordinal(rows, 7) == 1, "the only season that has ever existed is #1")

    -- Ordered by id, not by position in the result set: a backend is free to
    -- return rows in whatever order it likes.
    local three = { { id = 9 }, { id = 2 }, { id = 5 } }
    assert(Ordinal(three, 2) == 1)
    assert(Ordinal(three, 5) == 2)
    assert(Ordinal(three, 9) == 3)

    -- A deleted season shifts the ones after it, and that is correct for a
    -- COUNT: this is "which season is this" for a caption, not the identity
    -- the audit log keys on. Numbering new seasons never reuses a number
    -- (see the check below); reading an old one is a different question.
    assert(Ordinal({ { id = 2 }, { id = 9 } }, 9) == 2)

    assert(Ordinal(three, 4) == nil, "a season not in the list has no ordinal")
    assert(Ordinal(nil, 1) == nil)
    assert(Ordinal(three, nil) == nil)
end)

check("the next season's number is one past the highest that has existed", function()
    loadRules()
    local Next = Omerta.Seasons.Internal.NextSeasonNumber

    -- An empty database starts at one.
    assert(Next({}) == 1, "the first season is season one")
    assert(Next(nil) == 1, "and nothing at all is still the first season")

    assert(Next({ { label = "1" } }) == 2)
    assert(Next({ { label = "1" }, { label = "2" }, { label = "3" } }) == 4)

    -- A GAP does not get filled. Season 4 of 1,2,4 existed and was removed;
    -- handing 4 out again would put two seasons under one number in the audit
    -- log, which is the one thing a season number is for.
    assert(Next({ { label = "1" }, { label = "2" }, { label = "4" } }) == 5,
        "one past the highest, not the first hole")
    -- Order is irrelevant: it is a maximum, not a walk.
    assert(Next({ { label = "4" }, { label = "1" } }) == 5)

    -- NON-NUMERIC LEGACY LABELS still advance the sequence. A live database
    -- full of named seasons must not restart at 1 underneath its own history —
    -- nine seasons that happened produce the tenth, which is the ruling in the
    -- project lead's own words.
    local named = {}
    for i = 1, 9 do named[i] = { label = "The Winter of Knives " .. i } end
    assert(Next(named) == 10, "nine seasons of history make the next one the tenth")
    assert(Next({ { label = "__selftest__" } }) == 2)

    -- Mixed: the larger of "highest number" and "how many rows" wins, so
    -- neither a renumbered database nor a renamed one can go backwards.
    assert(Next({ { label = "The Winter of Knives" }, { label = "7" } }) == 8,
        "the highest number wins when it is ahead of the count")
    local mixed = { { label = "1" }, { label = "2" } }
    for i = 3, 12 do mixed[i] = { label = "a name" } end
    assert(Next(mixed) == 13, "and the count wins when it is ahead of the numbers")
end)

check("one-active invariant checker", function()
    loadRules()
    local Check = Omerta.Seasons.Internal.CheckActiveInvariant
    assert(Check({}))
    assert(Check({ { id = 1, state = "ended" }, { id = 2, state = "active" } }))
    local ok, why = Check({ { id = 1, state = "active" }, { id = 2, state = "active" } })
    assert(not ok and why:find("multiple active"), tostring(why))
end)

--------------------------------------------------------------------------------
suite("seasons.flow")
--------------------------------------------------------------------------------

-- Omerta.DB.WhenReady is not enough for anything that needs the active season
-- at boot: this module's own DB callback runs a query, so a consumer's DB
-- callback fires BEFORE the answer arrives. M10 hit that and created no
-- institutions; these pin the contract that replaced it.
check("a readiness callback sees the active season, not a nil one", function()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
    Omerta.Module.FinishLoading()

    local mock = { dialect = "sqlite", heuristic = true, log = {} }
    function mock.Connect(_, cb) cb(nil) end
    function mock.RunQuery(sqlStr, _, cb)
        mock.log[#mock.log + 1] = sqlStr
        if sqlStr:find("SELECT version") then cb({}, nil) return end
        if sqlStr:find("FROM omerta_seasons", 1, true) and not sqlStr:find("WHERE", 1, true) then
            cb({ { id = "7", state = "active", label = "season seven",
                   ruleset_version = "1", created_at = "100" } }, nil)
            return
        end
        cb({}, nil, 1)
    end
    function mock.RunTransaction(_, cb) cb(true, nil) end
    Omerta.DB.Internal.Drivers = Omerta.DB.Internal.Drivers or {}
    Omerta.DB.Internal.Drivers.sqlite = mock

    -- Registered BEFORE the boot, exactly as a consuming module's OnEnable does.
    local sawSeason, ran = nil, false
    Omerta.Seasons.WhenReady(function()
        ran = true
        sawSeason = Omerta.Seasons.GetActive()
    end)

    -- A plain DB callback registered at the same moment is the broken version,
    -- kept here so the difference is visible rather than asserted in a comment.
    local dbCallbackSaw = "not run"
    Omerta.DB.WhenReady(function() dbCallbackSaw = Omerta.Seasons.GetActive() end)

    Omerta.Module.EnableAll()

    assert(ran, "the readiness callback never fired")
    assert(sawSeason and sawSeason.id == 7, "it should see season #7, got "
        .. tostring(sawSeason and sawSeason.id))
    assert(dbCallbackSaw == nil, "a DB callback should still see nil — that is the bug")
end)

check("a callback still fires when there is no season, and when it is late", function()
    local mock = bootSeasons()
    assert(Omerta.Seasons.GetActive() == nil, "this boot has no season")

    -- Nothing to report is still an answer: a consumer left waiting forever is
    -- worse than one told there is nothing.
    local ranLate = false
    Omerta.Seasons.WhenReady(function() ranLate = true end)
    assert(ranLate, "a callback registered after resolution must still fire")
    assert(mock ~= nil)
end)

check("boot applies migration 2 and lands idle with no season", function()
    local mock = bootSeasons()
    assert(Omerta.DB.IsReady())
    assert(logContains(mock, "CREATE TABLE IF NOT EXISTS omerta_seasons"), "seasons DDL missing")
    assert(logContains(mock, "CREATE TABLE IF NOT EXISTS omerta_account_seasons"), "paths DDL missing")
    assert(not Omerta.Seasons.Internal.Failed)
    assert(Omerta.Seasons.GetActive() == nil)
end)

check("two active seasons in the database disable the module", function()
    bootSeasons(function(sqlStr)
        if sqlStr:find("FROM omerta_seasons", 1, true) and not sqlStr:find("WHERE", 1, true) then
            return { { id = "1", state = "active", label = "a" },
                     { id = "2", state = "active", label = "b" } }
        end
        return {}
    end)
    assert(Omerta.Seasons.Internal.Failed == true, "invariant breach must fail the module")
    assert(Omerta.Seasons.GetActive() == nil)
    local refused
    Omerta.Seasons.Create({ label = "x" }, function(_, err) refused = err end)
    assert(refused and refused:find("failed state"), tostring(refused))
end)

check("creating a season asks for no name and writes the next number", function()
    local inserted
    bootSeasons(function(sqlStr, params)
        if sqlStr:find("INSERT INTO omerta_seasons", 1, true) then
            inserted = params
            return {}, nil, 12
        end
        if sqlStr:find("FROM omerta_seasons", 1, true) and not sqlStr:find("WHERE", 1, true) then
            -- A database with history in it: one numbered season, one from
            -- before the numbering, and a gap where a third was removed.
            return { { id = "1", state = "ended", label = "1" },
                     { id = "2", state = "ended", label = "The Winter of Knives" },
                     { id = "5", state = "ended", label = "9" } }
        end
        return {}
    end)

    local createdId, err
    Omerta.Seasons.Create({ actor = "test" }, function(id, why) createdId, err = id, why end)
    assert(createdId == 12, "create should report the new row: " .. tostring(err))

    local carried = false
    for _, value in ipairs(inserted or {}) do
        if value == "10" then carried = true end
    end
    assert(carried, "the insert should carry the label '10' — one past the highest " ..
        "that existed (9), not the row count (3)")

    -- The self-test still names its own row, because its cleanup deletes by
    -- label and must never be able to reach a real season.
    Omerta.Seasons.Create({ label = "__selftest__" }, function() end)
    local named = false
    for _, value in ipairs(inserted or {}) do
        if value == "__selftest__" then named = true end
    end
    assert(named, "an explicit label must still be honoured")

    local refused
    Omerta.Seasons.Create({ label = 7 }, function(_, why) refused = why end)
    -- Plain find: the hyphen in "non-empty" is a pattern quantifier otherwise.
    assert(refused and refused:find("non-empty string", 1, true), tostring(refused))
end)

check("create -> start -> end lifecycle with guards", function()
    local state5 = "setup"
    local mock = bootSeasons(function(sqlStr, params)
        if sqlStr:find("INSERT INTO omerta_seasons", 1, true) then return {}, nil, 5 end
        if sqlStr:find("FROM omerta_seasons WHERE id", 1, true) then
            if params[1] == 5 then
                return { { id = "5", label = "s1", state = state5,
                           ruleset_version = "1", created_at = "100" } }
            end
            if params[1] == 6 then
                return { { id = "6", label = "s2", state = "setup",
                           ruleset_version = "1", created_at = "100" } }
            end
            return {}
        end
        if sqlStr:find("UPDATE omerta_seasons SET state", 1, true) then
            state5 = params[1]
            return {}
        end
        return {}
    end)

    local createdId
    Omerta.Seasons.Create({ label = "s1" }, function(id) createdId = id end)
    assert(createdId == 5)

    local started
    Omerta.Seasons.Start(5, "test", function(ok, err) started = ok or err end)
    assert(started == true, tostring(started))
    local active = Omerta.Seasons.GetActive()
    assert(active and active.id == 5 and active.state == "active")
    assert(active.ends_at - active.started_at == 28 * 86400, "default length wrong")

    local second
    Omerta.Seasons.Start(6, "test", function(ok, err) second = err end)
    assert(second and second:find("already active"), tostring(second))

    local ended
    Omerta.Seasons.End(5, "test", function(ok, err) ended = ok or err end)
    assert(ended == true, tostring(ended))
    assert(Omerta.Seasons.GetActive() == nil)

    local again
    Omerta.Seasons.End(5, "test", function(ok, err) again = err end)
    assert(again and again:find("only an active season"), tostring(again))

    assert(logContains(mock, "UPDATE omerta_seasons SET state"), "state updates missing")
end)

check("path transitions persist, cache, and refuse correctly", function()
    local state5 = "setup"
    local mock = bootSeasons(function(sqlStr, params)
        if sqlStr:find("INSERT INTO omerta_seasons", 1, true) then return {}, nil, 5 end
        if sqlStr:find("FROM omerta_seasons WHERE id", 1, true) then
            return { { id = "5", label = "s1", state = state5,
                       ruleset_version = "1", created_at = "100" } }
        end
        if sqlStr:find("UPDATE omerta_seasons SET state", 1, true) then
            state5 = params[1]
            return {}
        end
        return {}
    end)

    local account = { id = 42, steamid64 = "90000000000000002", season_path = nil }

    -- No active season yet: refused.
    local noSeason
    Omerta.Seasons.Internal.ApplyTransition(account, nil, "independent", "initial_choice",
        function(ok, err) noSeason = err end)
    assert(noSeason and noSeason:find("no active season"), tostring(noSeason))

    Omerta.Seasons.Create({ label = "s1" }, function() end)
    Omerta.Seasons.Start(5, "test", function() end)
    assert(Omerta.Seasons.GetActive() ~= nil)

    local ok1
    Omerta.Seasons.Internal.ApplyTransition(account, nil, "independent", "initial_choice",
        function(ok) ok1 = ok end)
    assert(ok1 == true and account.season_path == "independent")
    assert(logContains(mock, "INSERT INTO omerta_account_seasons"), "path upsert missing")
    assert(logContains(mock, "ON CONFLICT(account_id, season_id)"), "path conflict clause missing")

    local ok2
    Omerta.Seasons.Internal.ApplyTransition(account, nil, "criminal", "family_recruitment",
        function(ok) ok2 = ok end)
    assert(ok2 == true and account.season_path == "criminal")

    local refused
    Omerta.Seasons.Internal.ApplyTransition(account, nil, "police", "initial_choice",
        function(ok, err) refused = err end)
    assert(refused and refused:find("not permitted"), tostring(refused))
    assert(account.season_path == "criminal", "refusal must not mutate the cache")
end)
