-- The timed action (D-046).
--
-- This machinery was M19's and moved out of it when M14 became the third
-- milestone to want it. Everything pinned here was pinned in test_injury before
-- the move; what is new is the pair of rules the promotion actually introduced
-- — that the primitive validates before it starts, and that it does not know
-- what an injury is.
--
-- Begin, Cancel and Tick need a server, so they are exercised through the
-- shim's player rather than left to in-engine testing: the disconnect path is
-- the one the design review named as the reason not to write a second copy of
-- this, and a rule you only find out about in production is not a rule.

local MODULE_FILES = {
    "gamemodes/omertarp/gamemode/modules/action/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/action/sh_action.lua",
    "gamemodes/omertarp/gamemode/modules/action/sv_action.lua",
}

local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

-- Enough of a player for the primitive: an id, a position, and validity.
local nextId = 0
local function player(pos)
    nextId = nextId + 1
    local sid = string.format("7656119%010d", nextId)
    local p = {
        pos = pos or Vector(0, 0, 0),
        valid = true,
    }
    p.SteamID64 = function() return sid end
    p.GetPos = function() return p.pos end
    p.IsPlayer = function() return true end
    p.EntIndex = function() return nextId end
    return p
end

-- The primitive resolves the actor by scanning player.GetAll() every tick, so
-- the shim's roster is what decides whether somebody is still connected.
local roster = {}
local function connect(p) roster[#roster + 1] = p return p end
local function disconnect(p)
    for i, other in ipairs(roster) do
        if other == p then table.remove(roster, i) break end
    end
    p.valid = false
end

local function withWorld(fn)
    loadModules()
    roster = {}
    local realGetAll, realIsValid, realCurTime = player_GetAll, IsValid, CurTime
    local now = 100
    _G.player = { GetAll = function() return roster end }
    _G.IsValid = function(e) return type(e) == "table" and e.valid == true end
    _G.CurTime = function() return now end
    local advance = function(seconds) now = now + seconds end
    local ok, err = pcall(fn, advance)
    _G.IsValid, _G.CurTime = realIsValid, realCurTime
    if not ok then error(err, 0) end
end

--------------------------------------------------------------------------------
suite("action.wire")
--------------------------------------------------------------------------------

check("prompt sound codes are frozen", function()
    loadModules()
    -- The prompt carries a sound CODE; the client owns which file it means.
    -- Renumbering would make a stale client rustle at the wrong moments.
    assert(Omerta.Action.PROMPT_SOUND.NONE == 0)
    assert(Omerta.Action.PROMPT_SOUND.RUSTLE == 1)
end)

-- A timed action's clock reaches the client as a DURATION, and the unit it is
-- sent in decides whether the plate can be drawn at all. Floored whole seconds
-- rounded a fractional action to the wrong length and rounded a sub-second one
-- to nothing — a prompt whose window has already closed, which the controller
-- correctly never draws while the action itself runs and makes its noise.
check("the prompt clock is milliseconds, so no action rounds away", function()
    loadModules()
    local M = Omerta.Action.PromptMillis
    assert(M(4) == 4000, "the search")
    assert(M(6) == 6000 and M(10) == 10000, "the two treatments")

    -- The weapon draw's own reason (D-039, sh_weapons), applied here: a 1.66s
    -- action floored to 1 leaves the bar still filling after it finished, and
    -- rounded to 2 leaves it filling after the action is over.
    assert(M(1.66) == 1660)

    -- The one that produced a plate nobody ever saw. injury.search_seconds is
    -- configurable down to 0, so a half-second search was a setting away.
    assert(M(0.5) == 500, "half a second is half a second, not none")

    assert(M(0) == 0, "an instant action asks for no plate, honestly")
    assert(M(nil) == 0 and M(-3) == 0, "and never a negative window")
    assert(M(120) == 65535, "clamped to the 16 bits it is sent in")
end)

check("the prompt carries its clock in milliseconds on the wire", function()
    loadModules()
    local schema = Omerta.Net.GetRegistry()["action.prompt"].schema
    local field = nil
    for _, entry in ipairs(schema) do
        assert(entry.name ~= "seconds",
            "whole seconds is the unit that made a short action invisible")
        if entry.name == "millis" then field = entry end
    end
    assert(field, "the prompt has to carry a clock")
    assert(field.bits >= 16, "8 bits cannot hold a duration in milliseconds")
end)

-- The ceiling is not taste. PromptMillis clamps at 65535, so an action longer
-- than that reaches every client as a bar that finishes early while the server
-- is still counting — and the player is told the truth by neither.
check("an action longer than the wire can carry is refused, not clamped", function()
    loadModules()
    local spec = {
        id = "test.long", label = "Waiting",
        duration = Omerta.Action.MAX_SECONDS + 1,
        onComplete = function() end,
    }
    local ok, why = Omerta.Action.Validate(spec)
    assert(not ok, "a duration past the wire's range cannot be honoured")
    assert(why:find("wire carries"), "and the refusal should say why: " .. tostring(why))

    spec.duration = Omerta.Action.MAX_SECONDS
    assert(Omerta.Action.Validate(spec), "the ceiling itself is allowed")
    assert(Omerta.Action.PromptMillis(Omerta.Action.MAX_SECONDS) < 65535,
        "the ceiling has to sit inside the clamp, not on it")
end)

--------------------------------------------------------------------------------
suite("action.validation")
--------------------------------------------------------------------------------

check("an action needs an id, a label, a duration and something to do", function()
    loadModules()
    local V = Omerta.Action.Validate
    assert(not V(nil))
    assert(not V({ label = "X", duration = 1, onComplete = function() end }), "no id")
    assert(not V({ id = "Bad.Id", label = "X", duration = 1,
        onComplete = function() end }), "ids are lowercase")
    assert(not V({ id = "a.b", duration = 1, onComplete = function() end }), "no label")
    assert(not V({ id = "a.b", label = "X", onComplete = function() end }), "no duration")
    assert(not V({ id = "a.b", label = "X", duration = -1,
        onComplete = function() end }), "no negative duration")
    assert(not V({ id = "a.b", label = "X", duration = 1 }), "nothing to do")
    assert(V({ id = "a.b", label = "X", duration = 1, onComplete = function() end }))

    -- Zero is legal and deliberately so: a config that tunes an action down to
    -- nothing should produce an instant action, not a refused one.
    assert(V({ id = "a.b", label = "X", duration = 0, onComplete = function() end }))
end)

--------------------------------------------------------------------------------
suite("action.running")
--------------------------------------------------------------------------------

check("one action at a time, and the second is refused rather than queued", function()
    withWorld(function()
        local ply = connect(player())
        local spec = { id = "a.one", label = "One", duration = 5,
            onComplete = function() end }

        assert(Omerta.Action.Begin(ply, spec), "the first starts")
        assert(Omerta.Action.IsBusy(ply), "and holds the hands")

        local refused = nil
        Omerta.Action.Begin(ply, { id = "a.two", label = "Two", duration = 5,
            onComplete = function() end }, function(ok, err) refused = err end)
        assert(refused == "you are busy", "got: " .. tostring(refused))
        assert(Omerta.Action.InProgress(ply).id == "a.one", "the first survives")
    end)
end)

check("walking away interrupts you, and nothing is written", function()
    withWorld(function(advance)
        local ply = connect(player(Vector(0, 0, 0)))
        local completed, failure = false, nil
        Omerta.Action.Begin(ply, {
            id = "a.lever", label = "Levering", duration = 5,
            onComplete = function() completed = true end,
        }, function(ok, err) if not ok then failure = err end end)

        ply.pos = Vector(400, 0, 0)
        Omerta.Action.Tick()

        assert(failure == "you moved away", "got: " .. tostring(failure))
        assert(not Omerta.Action.IsBusy(ply), "the action is gone")

        -- The point of the whole shape: the clock ran out while nobody was
        -- there, and onComplete still never fired.
        advance(60)
        Omerta.Action.Tick()
        assert(not completed, "an abandoned action must not finish itself")
    end)
end)

check("the clock finishing is what runs the work", function()
    withWorld(function(advance)
        local ply = connect(player())
        local completed, result = false, nil
        Omerta.Action.Begin(ply, {
            id = "a.open", label = "Opening", duration = 5,
            data = { register = 7 },
            onComplete = function(actor, entry, done)
                completed = true
                assert(entry.data.register == 7, "the caller's bag comes back untouched")
                done(true)
            end,
        }, function(ok) result = ok end)

        advance(4)
        Omerta.Action.Tick()
        assert(not completed, "not yet")

        advance(2)
        Omerta.Action.Tick()
        assert(completed and result == true, "finished")
        assert(not Omerta.Action.IsBusy(ply), "and let go of the hands")
    end)
end)

-- THE ONE THE DESIGN REVIEW NAMED. A second copy of this machinery in
-- modules/crime/ was refused on the grounds that the second copy is always the
-- one that forgets to cancel on disconnect — so the first copy had better not.
check("a player who leaves does not leave an action running forever", function()
    withWorld(function(advance)
        local ply = connect(player())
        local completed, failure = false, nil
        Omerta.Action.Begin(ply, {
            id = "a.till", label = "Emptying", duration = 5,
            onComplete = function() completed = true end,
        }, function(ok, err) if not ok then failure = err end end)

        disconnect(ply)
        Omerta.Action.Tick()

        assert(failure == "you left", "the caller is told: " .. tostring(failure))
        assert(not completed, "and the work never runs")

        -- Nothing is left behind for the tick to trip over afterwards.
        advance(60)
        Omerta.Action.Tick()
        assert(not completed)
    end)
end)

--------------------------------------------------------------------------------
suite("action.interrupts")
--------------------------------------------------------------------------------

-- The primitive must not know what an injury is. Injury registers the rule that
-- going down stops your hands; M14 registers nothing of the sort and is not
-- affected by it. If this seam is ever inlined back into the primitive, four
-- milestones inherit a dependency on M19.
check("what stops an action is registered from outside", function()
    withWorld(function()
        local ply = connect(player())
        local floored = false
        Omerta.Action.RegisterInterrupt("test.down", function()
            if floored then return "you went down" end
            return nil
        end)

        local failure = nil
        Omerta.Action.Begin(ply, {
            id = "a.bandage", label = "Bandaging", duration = 5,
            onComplete = function() end,
        }, function(ok, err) if not ok then failure = err end end)

        Omerta.Action.Tick()
        assert(failure == nil, "nothing has happened yet")

        floored = true
        Omerta.Action.Tick()
        assert(failure == "you went down", "got: " .. tostring(failure))
    end)
end)

check("an action can withdraw its own permission mid-run", function()
    withWorld(function(advance)
        local ply = connect(player())
        local clerkAlive = true
        local completed, failure = false, nil
        Omerta.Action.Begin(ply, {
            id = "a.demand", label = "Holding him up", duration = 5,
            stillValid = function()
                if not clerkAlive then return false, "there is nobody to threaten" end
                return true
            end,
            onComplete = function() completed = true end,
        }, function(ok, err) if not ok then failure = err end end)

        clerkAlive = false
        advance(10)
        Omerta.Action.Tick()

        -- The deadline had already passed on this very tick. `stillValid` is
        -- checked FIRST on purpose: an action whose reason for existing died
        -- must not be paid out because the clock happened to agree.
        assert(failure == "there is nobody to threaten", "got: " .. tostring(failure))
        assert(not completed, "and it must not pay out")
    end)
end)
