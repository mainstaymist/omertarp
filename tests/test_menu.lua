-- The front end: the intro timeline, the menu camera, and the entry list.
--
-- All of it is arithmetic and ordering, which is exactly the part that cannot
-- be checked by looking at the screen — a title card that is one frame short
-- of black at the cut looks fine in motion and is wrong.

local MODULE_FILES = {
    "gamemodes/omertarp/gamemode/modules/hud/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sh_hud.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sh_theme.lua",
    "gamemodes/omertarp/gamemode/modules/menu/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/menu/sh_menu.lua",
}

local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

--------------------------------------------------------------------------------
suite("menu.intro")
--------------------------------------------------------------------------------

check("the opening is black, then the words, then the city", function()
    loadModules()
    local I = Omerta.Menu.INTRO
    local title = Omerta.Menu.IntroTitleAlpha
    local world = Omerta.Menu.IntroWorldFade

    assert(title(0) == 0, "nothing at all to begin with")
    assert(title(I.TITLE_AT) == 0, "the words start after the silence")
    assert(title(I.TITLE_FULL) == 1, "and are fully there once they arrive")
    assert(title(I.TITLE_END) == 1, "they hold")
    assert(title(I.TITLE_GONE) == 0, "and then they are gone")

    -- The hand-off is the point: the world must not begin arriving until the
    -- words have finished leaving, or the two cross-fade and it reads as a
    -- slideshow rather than as a film starting.
    assert(world(I.TITLE_END) == 1, "still solid black while the words fade")
    assert(world(I.TITLE_GONE) == 1, "and at the moment they finish")
    assert(world(I.DONE) == 0, "the city is fully there by the end")
    assert(world(I.TITLE_GONE + I.REVEAL * 0.5) < 1, "and arrives in between")
end)

check("the intro ends, and can be skipped once it can be read", function()
    loadModules()
    local I = Omerta.Menu.INTRO
    assert(not Omerta.Menu.IntroDone(I.DONE - 0.1), "not before the reveal finishes")
    assert(Omerta.Menu.IntroDone(I.DONE), "and done at the end")

    -- A player still holding a key from the loading screen must not lose the
    -- opening to it — the same rule the death screen's acknowledgement follows.
    assert(not Omerta.Menu.MaySkip(0), "a held key at frame zero skips nothing")
    assert(Omerta.Menu.MaySkip(I.TITLE_FULL), "once the words are up, it is a choice")
end)

check("the music comes up from nothing", function()
    loadModules()
    local music = Omerta.Menu.IntroMusic
    assert(music(0) == 0, "silence at the cut")
    assert(music(Omerta.Menu.INTRO.MUSIC_IN) == 1, "full by the end of its fade")
    assert(music(1000) == 1, "and never louder than that")
end)

--------------------------------------------------------------------------------
suite("menu.camera")
--------------------------------------------------------------------------------

check("the camera orbits its vantage and always looks back at it", function()
    loadModules()
    local orbit = Omerta.Menu.OrbitPoint

    local dx, dy, yaw = orbit(0, 100, 10)
    assert(math.abs(dx - 100) < 0.001 and math.abs(dy) < 0.001, "starts due east of it")
    assert(math.abs(yaw - 180) < 0.001, "facing back inward")

    -- A quarter turn at 10 deg/s is nine seconds.
    local qx, qy = orbit(9, 100, 10)
    assert(math.abs(qx) < 0.001 and math.abs(qy - 100) < 0.001, "a quarter of the way round")

    -- The radius is the radius, wherever it is in the turn.
    for t = 0, 40, 3 do
        local x, y = orbit(t, 250, 6)
        local distance = math.sqrt(x * x + y * y)
        assert(math.abs(distance - 250) < 0.001, "the orbit stays circular at t=" .. t)
    end

    -- Wrapped, so a client left on the menu overnight does the same arithmetic
    -- as one that just joined.
    local _, _, late = orbit(100000, 100, 7)
    assert(late >= 0 and late < 360, "the yaw stays a real bearing")
end)

--------------------------------------------------------------------------------
suite("menu.entries")
--------------------------------------------------------------------------------

check("entries are registered, ordered and validated", function()
    loadModules()
    local R = Omerta.Menu.RegisterEntry
    R("test.b", { label = "B", order = 20, onSelect = function() end })
    R("test.a", { label = "A", order = 10, onSelect = function() end })
    R("test.c", { label = "C", order = 10, onSelect = function() end })

    local ordered = Omerta.Menu.GetOrdered()
    assert(#ordered == 3, "all three are there")
    -- By order, then id: a menu whose items move between sessions is a menu
    -- nobody can use without reading it every time.
    assert(ordered[1].id == "test.a" and ordered[2].id == "test.c"
        and ordered[3].id == "test.b", "order, then id")

    assert(not pcall(R, "Test.D", { label = "D", onSelect = function() end }), "bad id")
    assert(not pcall(R, "test.d", { onSelect = function() end }), "no label")
    assert(not pcall(R, "test.d", { label = "D" }), "no action")
    assert(not pcall(R, "test.a", { label = "A", onSelect = function() end }), "twice")
end)

check("an entry may decline to appear", function()
    loadModules()
    Omerta.Menu.RegisterEntry("test.always", { label = "Always", order = 10,
        onSelect = function() end })
    Omerta.Menu.RegisterEntry("test.never", { label = "Never", order = 20,
        onSelect = function() end, visible = function() return false end })
    -- A predicate that errors must not take the menu down with it; the entry
    -- simply does not appear.
    Omerta.Menu.RegisterEntry("test.broken", { label = "Broken", order = 30,
        onSelect = function() end, visible = function() error("nope") end })

    local available = Omerta.Menu.Available()
    assert(#available == 1 and available[1].id == "test.always",
        "only the one that wants to be there")
end)

check("the highlight wraps in both directions", function()
    loadModules()
    local step = Omerta.Menu.StepSelection
    assert(step(1, 1, 3) == 2, "down")
    assert(step(3, 1, 3) == 1, "and round")
    assert(step(1, -1, 3) == 3, "up from the top wraps to the bottom")
    -- An empty list has no selection to move, and must not index into nothing.
    assert(step(1, 1, 0) == 0, "nothing to select")
    assert(step(0, 1, 3) == 1, "a fresh menu starts at the top")
end)

--------------------------------------------------------------------------------
suite("menu.theme")
--------------------------------------------------------------------------------

check("the design standard defines every role the interface asks for", function()
    loadModules()
    local T = Omerta.HUD.Theme
    -- Every role named anywhere in the UI. A missing one silently falls back
    -- to body text, which looks like a design decision rather than a bug.
    for _, role in ipairs({ "small", "label", "body", "heading", "headline", "title" }) do
        assert(T.TYPE[role], "no type role '" .. role .. "'")
        assert(T.TypeSize(role) > 0, role .. " has no size")
        assert(T.FACE[T.TYPE[role].face], role .. " names a face that does not exist")
    end
    -- Carbon's scale, read at game distance rather than browser distance.
    assert(T.TypeSize("body") > T.TypeSize("label"), "body is larger than a label")
    assert(T.TypeSize("title") > T.TypeSize("headline"), "the wordmark is the largest")
end)

check("spacing comes from the scale and never from a guess", function()
    loadModules()
    local T = Omerta.HUD.Theme
    assert(T.Step(1) < T.Step(5) and T.Step(5) < T.Step(10), "the scale ascends")
    -- Out-of-range steps clamp: a layout should never vanish because somebody
    -- asked for spacing-14.
    assert(T.Step(99) == T.Step(#T.SPACING), "clamped at the top")
    assert(T.Step(0) == T.Step(1), "and at the bottom")
end)
