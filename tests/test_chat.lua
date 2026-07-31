-- M7 local text: parsing, sanitisation, the channel registry, range maths,
-- and — the point of the whole milestone — that the speaker's label is
-- resolved separately for each listener.

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
    "gamemodes/omertarp/gamemode/modules/characters/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sh_characters.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sv_characters.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sh_hud.lua",
    -- The Carbon token table: the chat box maps every channel's declared
    -- colour into it, so the mapping is asserted against the real palette
    -- rather than against a copy of it that could drift.
    "gamemodes/omertarp/gamemode/modules/hud/sh_theme.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sv_stamina.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sh_interaction.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sv_interaction.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sh_identity.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sv_identity.lua",
    "gamemodes/omertarp/gamemode/modules/chat/sh_module.lua",
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

-- The index is what goes on the wire, and GetOrdered is what assigns it. A
-- channel fetched before anything had ever ordered them carried a nil index,
-- which then failed validation inside net.Send — a crash lying in wait for
-- whichever code path happened to speak first. M11's treasury found it.
check("a channel is fully formed the first time it is asked for", function()
    loadModules()
    local system = Omerta.Chat.GetChannel("system")
    assert(system, "the system channel is missing")
    assert(type(system.index) == "number",
        "a channel must carry its wire index before anything else runs")

    -- True for every channel, not just the one that happened to be first.
    for _, id in ipairs({ "whisper", "say", "yell", "me", "system" }) do
        assert(type(Omerta.Chat.GetChannel(id).index) == "number", id .. " has no index")
    end
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
suite("chat.presentation")
--------------------------------------------------------------------------------
-- The chat box draws; these are the sums behind it. The drawing half is
-- client-only and unreachable here, which is exactly why the arithmetic is
-- not.

-- A stand-in for surface.GetTextSize: every glyph the same width, so the
-- expected line breaks can be counted by hand. Glyphs, not bytes — an "à" is
-- one character and two bytes, and measuring bytes would hide the very bug
-- these tests exist to catch.
local function fixedWidth(pixels)
    return function(text)
        local count = 0
        for _ in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            count = count + 1
        end
        return count * pixels
    end
end

check("wrapping breaks at spaces and fills the column", function()
    loadModules()
    local W = Omerta.Chat.WrapText
    local m = fixedWidth(10)

    -- "one two" is exactly 70px: the boundary must be inclusive, or every
    -- column silently loses its last character.
    local lines = W("one two three", 70, m)
    assert(#lines == 2, "expected 2 lines, got " .. #lines)
    assert(lines[1] == "one two", lines[1])
    assert(lines[2] == "three", lines[2])

    -- A message that fits stays one line, and no space is invented.
    lines = W("evening", 200, m)
    assert(#lines == 1 and lines[1] == "evening", tostring(lines[1]))
end)

check("a word wider than the column is cut, never mid-character", function()
    loadModules()
    local W = Omerta.Chat.WrapText
    local m = fixedWidth(10)

    -- Six characters at 10px into a 30px column.
    local lines = W("Omertà", 30, m)
    assert(#lines == 2, "expected 2 lines, got " .. #lines)
    assert(lines[1] == "Ome", lines[1])
    -- The accented character survived whole: a byte-wise cut would leave half
    -- of it on each line and draw two replacement glyphs.
    assert(lines[2] == "rtà", lines[2])
    assert(m(lines[2]) == 30, "the tail is three characters, not four bytes")

    -- The remainder of a broken word is a normal line again: whatever follows
    -- joins it if it fits, rather than the cut forcing a paragraph break.
    lines = W("aaaaa bb", 40, m)
    assert(#lines == 2 and lines[1] == "aaaa" and lines[2] == "a bb",
        table.concat(lines, "|"))
end)

check("wrapping copes with nothing to wrap", function()
    loadModules()
    local W = Omerta.Chat.WrapText
    local m = fixedWidth(10)
    assert(#W("", 100, m) == 0, "no text is no lines")
    assert(#W(nil, 100, m) == 0, "nil is no lines")
    -- A column of zero or nonsense width must not loop forever trying to fit
    -- a character into it.
    local lines = W("hello", 0, m)
    assert(#lines == 1 and lines[1] == "hello", "an absent column draws unwrapped")
end)

check("the input line scrolls from the end, on character boundaries", function()
    loadModules()
    local C = Omerta.Chat.ClipTail
    local m = fixedWidth(10)

    assert(C("abcdefghij", 100, m) == "abcdefghij", "what fits is untouched")
    assert(C("abcdefghij", 50, m) == "fghij", "the tail, not the head")
    assert(C("abcdefghij", 5, m) == "", "a column too small for one glyph")
    assert(C("", 50, m) == "", "nothing to show")

    -- Two bytes, one glyph: a byte-wise cut here produces a broken string.
    local tail = C("ààà", 20, m)
    assert(tail == "àà", tail)
    assert(m(tail) == 20, "measured in glyphs")
end)

check("a line rises, holds, fades, and then is gone", function()
    loadModules()
    local A = Omerta.Chat.LineAlpha

    assert(A(0, 12, 2, 0.1) == 0, "not yet arrived")
    assert(A(0.05, 12, 2, 0.1) == 0.5, "halfway in")
    assert(A(0.1, 12, 2, 0.1) == 1, "arrived")
    assert(A(6, 12, 2, 0.1) == 1, "holding")
    assert(A(12.1, 12, 2, 0.1) == 1, "the hold is measured after the rise")
    assert(A(13.1, 12, 2, 0.1) == 0.5, "halfway out")
    -- The zero at the end is the requirement: an idle screen returns to empty.
    assert(A(14.1, 12, 2, 0.1) == 0, "gone")
    assert(A(600, 12, 2, 0.1) == 0, "and stays gone")

    assert(A(-1, 12, 2, 0.1) == 0, "before it existed")
    assert(A(5, 0, 0, 0) == 0, "no hold and no fade is instantly gone")
    assert(A(0, 0, 0, 0) == 1, "the instant it arrives it is present")

    -- The same curve is reused with hold 0 to bring the history back down
    -- after the box closes: full, then one clean fade.
    assert(A(0, 0, 2, 0) == 1 and A(1, 0, 2, 0) == 0.5 and A(2, 0, 2, 0) == 0)
end)

check("history is bounded and drops the oldest first", function()
    loadModules()
    local T = Omerta.Chat.TrimHistory

    local list = {}
    for i = 1, 14 do list[#list + 1] = i end
    T(list, 10)
    assert(#list == 10, "expected 10, got " .. #list)
    assert(list[1] == 5 and list[10] == 14, "the newest are the ones kept")

    -- Under the bound nothing moves, and a garbage bound is ignored rather
    -- than emptying somebody's chat.
    local short = { 1, 2 }
    assert(#T(short, 10) == 2)
    assert(#T(short, nil) == 2, "a missing bound leaves the list alone")
end)

check("a channel's colour maps into the palette, never past it", function()
    loadModules()
    local palette = Omerta.HUD.Theme.COLOUR
    local candidates = {
        { token = "text",      colour = palette.text },
        { token = "secondary", colour = palette.secondary },
        { token = "dim",       colour = palette.dim },
    }
    local P = Omerta.Chat.PaletteToken
    local function tokenOf(id)
        return P(Omerta.Chat.GetChannel(id).colour, candidates)
    end

    -- Speech is bone; a whisper keeps the quieter grey it asked for.
    assert(tokenOf("say") == "text", tostring(tokenOf("say")))
    assert(tokenOf("yell") == "text", tostring(tokenOf("yell")))
    assert(tokenOf("whisper") == "secondary", tostring(tokenOf("whisper")))
    assert(tokenOf("system") == "secondary", tostring(tokenOf("system")))

    -- The accent is not on the menu. A later milestone registering a gold
    -- channel colour must not end up claiming brass for every sentence
    -- spoken on it — it lands on a neutral tone like everything else.
    assert(P({ 200, 169, 106 }, candidates) == "secondary",
        "brass-coloured input must resolve to a neutral token")

    -- Deterministic when two candidates are equidistant: pairs() order is
    -- undefined, so the array order decides and the answer is the same on
    -- every boot.
    local tie = {
        { token = "first", colour = { 0, 0, 0 } },
        { token = "second", colour = { 200, 200, 200 } },
    }
    assert(P({ 100, 100, 100 }, tie) == "first", "ties go to the earlier entry")
    assert(P({ 10, 10, 10 }, {}) == nil, "no candidates is no answer")
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
