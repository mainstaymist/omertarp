-- M7 local text: parsing, sanitisation, the channel registry, range maths,
-- and — the point of the whole milestone — that the speaker's label is
-- resolved separately for each listener.

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
    "gamemodes/omertarp/gamemode/modules/chat/sh_chat.lua",
    "gamemodes/omertarp/gamemode/modules/chat/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/chat/sv_chat.lua",
}

local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

--------------------------------------------------------------------------------
suite("chat.parse")
--------------------------------------------------------------------------------

check("plain text is speech; prefixes select their channel", function()
    loadModules()
    local P = Omerta.Chat.Parse

    local id, text = P("evening, gentlemen")
    assert(id == "say" and text == "evening, gentlemen", tostring(id))

    id, text = P("/w keep it down")
    assert(id == "whisper" and text == "keep it down", tostring(id) .. "/" .. tostring(text))

    id, text = P("/y GET DOWN")
    assert(id == "yell" and text == "GET DOWN", tostring(id))

    id, text = P("/me lights a cigarette")
    assert(id == "me" and text == "lights a cigarette", tostring(id))

    -- Case-insensitive prefixes, and leading whitespace tolerated.
    assert(P("/W quietly") == "whisper")
    assert(P("   hello") == "say")
end)

check("an unknown command is refused, never spoken aloud", function()
    loadModules()
    -- If this fell through to speech, "/wanted dead or alive" would be
    -- broadcast to the room by a mistyped command.
    local id, _, why = Omerta.Chat.Parse("/wanted dead or alive")
    assert(id == nil, "should refuse")
    assert(why and why:find("unknown command"), tostring(why))

    id = Omerta.Chat.Parse("/")
    assert(id == nil, "a bare slash should refuse")
end)

check("sanitisation strips control characters and bounds length", function()
    loadModules()
    local S = Omerta.Chat.Sanitize
    assert(S("hello there", 256) == "hello there")
    assert(S("hello\1\2\27 there", 256) == "hello there", "control characters must go")
    assert(S("  spaced   out  ", 256) == "spaced out", "whitespace collapses")
    assert(S("", 256) == nil, "empty is refused")
    assert(S("    ", 256) == nil, "whitespace-only is refused")
    assert(S(nil, 256) == nil, "nil is refused")
    assert(#S(string.rep("a", 500), 256) == 256, "length is capped")
    -- Accented characters survive: it is Omertà RP.
    assert(S("Omertà", 256) == "Omertà")
end)

--------------------------------------------------------------------------------
suite("chat.channels")
--------------------------------------------------------------------------------

check("default channels exist with sane, widening ranges", function()
    loadModules()
    local whisper = Omerta.Chat.GetChannel("whisper")
    local say = Omerta.Chat.GetChannel("say")
    local yell = Omerta.Chat.GetChannel("yell")
    assert(whisper and say and yell)
    assert(whisper.range < say.range and say.range < yell.range,
        "whisper must be quieter than say, and say than yell")
    assert(Omerta.Chat.GetChannel("me").emote == true, "/me is narration")
    assert(Omerta.Chat.GetChannel("system").system == true, "system is not player-usable")
end)

check("indices are stable and reversible", function()
    loadModules()
    local list = Omerta.Chat.GetOrdered()
    assert(#list == 5, "expected 5 channels, got " .. #list)
    for i, def in ipairs(list) do
        assert(def.index == i, "index not assigned for " .. def.id)
        assert(Omerta.Chat.GetByIndex(i) == def, "reverse lookup failed at " .. i)
    end
    -- Ordering is by `order` then id, so whisper (10) precedes say (20).
    assert(list[1].id == "whisper" and list[2].id == "say", list[1].id .. "," .. list[2].id)
end)

check("registration validates its inputs", function()
    loadModules()
    local R = Omerta.Chat.RegisterChannel
    assert(not pcall(R, "Bad Id", { label = "x" }), "bad id")
    assert(not pcall(R, "nolabel", {}), "missing label")
    assert(not pcall(R, "badrange", { label = "x", range = -5 }), "negative range")
    assert(not pcall(R, "say", { label = "duplicate" }), "duplicate id")
    -- A later milestone's channel registers cleanly (M11 radios, M12 phones).
    R("radio", { label = "says over the radio", range = nil, order = 50 })
    assert(Omerta.Chat.GetChannel("radio"), "extension channel should register")
end)

--------------------------------------------------------------------------------
suite("chat.delivery")
--------------------------------------------------------------------------------

check("range test is inclusive at the boundary", function()
    loadModules()
    local pos = function(x) return { Distance = function(_, other) return math.abs(x - other.x) end, x = x } end
    local InRange = Omerta.Chat.Internal.InRange
    assert(InRange(pos(0), pos(100), 400), "well inside")
    assert(InRange(pos(0), pos(400), 400), "exactly at the edge should be audible")
    assert(not InRange(pos(0), pos(401), 400), "beyond the edge is silence")
    assert(not InRange(pos(0), pos(10), nil), "a channel with no range is not proximity-based")
end)

-- The milestone's whole purpose: one sentence, different labels per listener.
check("the speaker's label is resolved per listener", function()
    loadModules()
    local speaker = { id = 2, first_name = "Tony", last_name = "Marino" }
    local acquainted = { id = 1 }
    local stranger = { id = 3 }

    local R = Omerta.Identity.ResolveDisplayName
    assert(R(acquainted, speaker, "Tony Marino") == "Tony Marino", "a listener who knows him")
    assert(R(stranger, speaker, nil) == "Unknown", "a listener who does not")
    assert(R(speaker, speaker, nil) == "Tony Marino", "the speaker hears himself by name")

    -- D-014: a concealed speaker is Unknown even to those who know him.
    speaker.masked = true
    Omerta.Identity.RegisterConcealmentProvider(function(c) return c.masked == true end)
    assert(R(acquainted, speaker, "Tony Marino") == "Unknown", "a mask defeats recognition")
end)

check("retention cutoff maths", function()
    loadModules()
    local C = Omerta.Chat.Internal.RetentionCutoff
    assert(C(1000000, 0) == nil and C(1000000, nil) == nil, "retention off")
    assert(C(1000000, 14) == 1000000 - 14 * 86400)
end)

--------------------------------------------------------------------------------
suite("chat.flow")
--------------------------------------------------------------------------------

check("migration 6 creates the chat log", function()
    loadModules()
    Omerta.Module.FinishLoading()
    local mock = { dialect = "sqlite", heuristic = true, log = {}, nextInsertId = 1 }
    function mock.Connect(_, cb) cb(nil) end
    function mock.RunQuery(sqlStr, _, cb)
        mock.log[#mock.log + 1] = sqlStr
        if sqlStr:find("SELECT version") then cb({}, nil) return end
        local id = mock.nextInsertId
        mock.nextInsertId = mock.nextInsertId + 1
        cb({}, nil, id)
    end
    function mock.RunTransaction(_, cb) cb(true, nil) end
    Omerta.DB.Internal.Drivers = Omerta.DB.Internal.Drivers or {}
    Omerta.DB.Internal.Drivers.sqlite = mock
    Omerta.Module.EnableAll()

    local found = false
    for _, s in ipairs(mock.log) do
        if s:find("CREATE TABLE IF NOT EXISTS omerta_chat_log", 1, true) then found = true end
    end
    assert(found, "chat_log DDL missing")

    -- A logged line carries position and audience size for investigations.
    Omerta.Chat.Internal.Repo.Log({
        at = 1, season_id = 1, character_id = 5, channel = "say",
        text = "hello", pos_x = 1, pos_y = 2, pos_z = 3, recipients = 4,
    })
    local logged = false
    for _, s in ipairs(mock.log) do
        if s:find("INSERT INTO omerta_chat_log", 1, true) then logged = true end
    end
    assert(logged, "chat log insert missing")
end)
