-- M5 identity and interaction: the resolution rule (the single most important
-- rule in the project), the interaction registry and availability filtering,
-- and knowledge persistence against the mock driver.

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
    "gamemodes/omertarp/gamemode/modules/hud/sh_hud.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sv_stamina.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sh_interaction.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sv_interaction.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sh_identity.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sv_identity.lua",
}

local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

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

local function char(id, first, last)
    return { id = id, first_name = first or "Tony", last_name = last or "Marino" }
end

--------------------------------------------------------------------------------
suite("identity.resolution")
--------------------------------------------------------------------------------

-- The single most important rule in the project.
check("unknown by default; known only to those who learned it", function()
    loadModules()
    local R = Omerta.Identity.ResolveDisplayName
    local observer, subject = char(1, "Vincent", "Costa"), char(2, "Tony", "Marino")

    local name, known = R(observer, subject, nil)
    assert(name == "Unknown" and known == false, name)

    name, known = R(observer, subject, "Tony Marino")
    assert(name == "Tony Marino" and known == true, name)

    -- Empty string is not knowledge.
    name, known = R(observer, subject, "")
    assert(name == "Unknown" and known == false, name)
end)

check("a character always knows itself", function()
    loadModules()
    local me = char(7, "Salvatore", "Marino")
    local name, known = Omerta.Identity.ResolveDisplayName(me, me, nil)
    assert(name == "Salvatore Marino" and known, name)
end)

check("missing subject resolves to Unknown rather than erroring", function()
    loadModules()
    local name, known = Omerta.Identity.ResolveDisplayName(char(1), nil, "whatever")
    assert(name == "Unknown" and known == false)
end)

-- D-014: knowledge is permanent, recognition is situational.
check("concealment defeats recognition but never erases knowledge", function()
    loadModules()
    local observer, subject = char(1), char(2, "Tony", "Marino")
    subject.masked = true
    Omerta.Identity.RegisterConcealmentProvider(function(c) return c.masked == true end)

    local name, known = Omerta.Identity.ResolveDisplayName(observer, subject, "Tony Marino")
    assert(name == "Unknown" and known == false, "a mask must defeat recognition: " .. name)

    -- Unmasked, the same knowledge applies again.
    subject.masked = false
    name, known = Omerta.Identity.ResolveDisplayName(observer, subject, "Tony Marino")
    assert(name == "Tony Marino" and known, name)
end)

check("you recognize yourself even concealed", function()
    loadModules()
    local me = char(7, "Salvatore", "Marino")
    me.masked = true
    Omerta.Identity.RegisterConcealmentProvider(function(c) return c.masked == true end)
    local name = Omerta.Identity.ResolveDisplayName(me, me, nil)
    assert(name == "Salvatore Marino", name)
end)

--------------------------------------------------------------------------------
suite("interaction.registry")
--------------------------------------------------------------------------------

check("registration validates its inputs", function()
    loadModules()
    local R = Omerta.Interaction.Register
    assert(not pcall(R, "Bad Id", { label = "x", range = 10 }), "uppercase/space id")
    assert(not pcall(R, "no.label", { range = 10 }), "missing label")
    assert(not pcall(R, "no.range", { label = "x" }), "missing range")
    assert(not pcall(R, "big.range", { label = "x", range = 9999 }), "range over the ceiling")
    R("fine.action", { label = "Fine", range = 64 })
    assert(not pcall(R, "fine.action", { label = "Fine", range = 64 }), "duplicate id")
end)

check("ordering is deterministic and indices are stable", function()
    loadModules()
    Omerta.Interaction.Register("z.late", { label = "Z", range = 64, order = 50 })
    Omerta.Interaction.Register("a.early", { label = "A", range = 64, order = 10 })
    Omerta.Interaction.Register("m.same", { label = "M", range = 64, order = 50 })

    local list = Omerta.Interaction.GetOrdered()
    -- identity.introduce (order 10) registers during OnLoad, which has not run
    -- here, so only these three are present; sorted by order then id.
    assert(list[1].id == "a.early", list[1].id)
    assert(list[2].id == "m.same" and list[3].id == "z.late",
        list[2].id .. "," .. list[3].id)
    for i, def in ipairs(list) do
        assert(def.index == i, "index not assigned")
        assert(Omerta.Interaction.GetByIndex(i) == def, "index lookup mismatch")
    end
end)

check("availability filters by range, target type and predicate", function()
    loadModules()
    local CanUse = Omerta.Interaction.CanUse
    local playerTarget = { IsPlayer = function() return true end }
    local propTarget = { IsPlayer = function() return false end }

    local def = Omerta.Interaction.Register("test.act", {
        label = "Act", range = 100, targets = "player",
    })
    assert(CanUse(def, {}, playerTarget, 50))
    assert(not CanUse(def, {}, playerTarget, 150), "beyond range must fail")
    assert(not CanUse(def, {}, propTarget, 50), "wrong target type must fail")
    assert(not CanUse(nil, {}, playerTarget, 10), "unknown action must fail")

    local gated = Omerta.Interaction.Register("test.gated", {
        label = "Gated", range = 100, targets = "any",
        predicate = function() return false, "nope" end,
    })
    local ok, reason = CanUse(gated, {}, playerTarget, 10)
    assert(not ok and reason == "nope", tostring(reason))
end)

--------------------------------------------------------------------------------
suite("identity.flow")
--------------------------------------------------------------------------------

check("migration 5 creates the knowledge table with its composite key", function()
    local mock = boot()
    assert(Omerta.DB.IsReady())
    assert(logContains(mock, "CREATE TABLE IF NOT EXISTS omerta_identity_knowledge"), "DDL missing")
    assert(logContains(mock, "PRIMARY KEY (observer_id, subject_id)"), "composite key missing")
end)

check("the introduce action is registered and gated on prior knowledge", function()
    boot()
    local def = Omerta.Interaction.Get("identity.introduce")
    assert(def, "identity.introduce should be registered in OnLoad")
    assert(def.targets == "player" and def.range == 96, "unexpected action shape")
end)

check("learning records knowledge one way only", function()
    local mock = boot()
    Omerta.Identity.Internal.LoadKnowledge(1, function() end)
    Omerta.Identity.Internal.LoadKnowledge(2, function() end)

    local ok
    Omerta.Identity.Learn(1, 2, "Tony Marino", "introduction", function(o) ok = o end)
    assert(ok == true)
    assert(Omerta.Identity.Knows(1, 2), "observer should know subject")
    assert(not Omerta.Identity.Knows(2, 1), "D-013: the subject learns nothing")
    assert(Omerta.Identity.GetKnownName(1, 2) == "Tony Marino")
    assert(logContains(mock, "INSERT INTO omerta_identity_knowledge"), "upsert missing")
    assert(logContains(mock, "ON CONFLICT(observer_id, subject_id)"), "conflict clause missing")
end)

check("learning validates source and rejects self-knowledge", function()
    boot()
    local err
    Omerta.Identity.Learn(1, 2, "Tony", "telepathy", function(_, e) err = e end)
    assert(err and err:find("unknown source"), tostring(err))

    Omerta.Identity.Learn(3, 3, "Me", "introduction", function(_, e) err = e end)
    assert(err and err:find("always knows itself"), tostring(err))
end)

check("knowledge loads from the database into the cache", function()
    boot(function(sqlStr)
        if sqlStr:find("FROM omerta_identity_knowledge WHERE observer_id", 1, true) then
            return { { subject_id = "2", learned_name = "Tony Marino", source = "introduction" },
                     { subject_id = "3", learned_name = "Vincent Costa", source = "rumor" } }
        end
        return nil
    end)
    local loaded
    Omerta.Identity.Internal.LoadKnowledge(1, function(ok) loaded = ok end)
    assert(loaded == true)
    assert(Omerta.Identity.GetKnownName(1, 2) == "Tony Marino")
    assert(Omerta.Identity.GetKnownName(1, 3) == "Vincent Costa")
    assert(Omerta.Identity.GetKnownName(1, 4) == nil, "must not invent knowledge")
end)

check("forgetting clears both database and cache", function()
    local mock = boot()
    Omerta.Identity.Internal.LoadKnowledge(1, function() end)
    Omerta.Identity.Learn(1, 2, "Tony Marino", "introduction", function() end)
    assert(Omerta.Identity.Knows(1, 2))

    local ok
    Omerta.Identity.Forget(1, 2, function(o) ok = o end)
    assert(ok == true)
    assert(not Omerta.Identity.Knows(1, 2), "cache should be cleared")
    assert(logContains(mock, "DELETE FROM omerta_identity_knowledge"), "delete missing")
end)

check("unloading a character drops only that character's knowledge", function()
    boot()
    Omerta.Identity.Internal.LoadKnowledge(1, function() end)
    Omerta.Identity.Internal.LoadKnowledge(2, function() end)
    Omerta.Identity.Learn(1, 5, "A", "introduction", function() end)
    Omerta.Identity.Learn(2, 5, "A", "introduction", function() end)

    Omerta.Identity.Internal.UnloadKnowledge(1)
    assert(not Omerta.Identity.Knows(1, 5), "unloaded cache should be empty")
    assert(Omerta.Identity.Knows(2, 5), "other observers must be untouched")
end)
