-- M19 injury and incapacitation. The state machine is the design of the
-- milestone, so it is the thing that gets pinned hardest: which moves are
-- legal, what a clock expires into, and the two rulings in D-037 that a future
-- change would otherwise quietly reverse.

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
    "gamemodes/omertarp/gamemode/modules/inventory/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_currency.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_hunger.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_inventory.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_items.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_hunger.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_inventory.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_money.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sh_ladders.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sh_organizations.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sv_organizations.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sh_ledger.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sh_procurement.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sh_supplies.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sv_procurement.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sv_treasury.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sh_lines.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sh_phone.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sv_calls.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sv_phone.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/business/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/business/sh_business.lua",
    "gamemodes/omertarp/gamemode/modules/business/sh_rumours.lua",
    "gamemodes/omertarp/gamemode/modules/business/sh_venues.lua",
    "gamemodes/omertarp/gamemode/modules/business/sv_business.lua",
    "gamemodes/omertarp/gamemode/modules/business/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/business/sv_rumours.lua",
    "gamemodes/omertarp/gamemode/modules/business/sv_trade.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sh_injury.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sh_supplies.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_injury.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_bodies.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_treatment.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_actions.lua",
}

local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

--------------------------------------------------------------------------------
suite("injury.states")
--------------------------------------------------------------------------------

check("damage bands map to states, and being down is not climbed out of", function()
    loadModules()
    local F = Omerta.Injury.StateForHealth
    local S = Omerta.Injury.STATE
    assert(F(100, 100, S.HEALTHY) == S.HEALTHY, "untouched")
    assert(F(80, 100, S.HEALTHY) == S.HEALTHY, "grazed")
    assert(F(50, 100, S.HEALTHY) == S.INJURED, "hurt")
    assert(F(20, 100, S.HEALTHY) == S.CRITICAL, "bleeding badly")
    assert(F(0, 100, S.HEALTHY) == S.INCAPACITATED, "down")

    -- The band is only consulted while somebody is on their feet. Regenerating
    -- health must never stand an unconscious man up by itself.
    assert(F(100, 100, S.INCAPACITATED) == S.INCAPACITATED, "full health, still down")
    assert(F(100, 100, S.STABILIZED) == S.STABILIZED, "bandaged, still down")
    assert(F(100, 100, S.DEAD) == S.DEAD, "still dead")

    -- Thresholds are fractions, so a future max-health change does not
    -- silently re-tune every band.
    assert(F(100, 200, S.HEALTHY) == S.INJURED, "half of a bigger pool is still hurt")
end)

check("the legal-move table is the design, and it refuses the rest", function()
    loadModules()
    local T = Omerta.Injury.CanTransition
    local S = Omerta.Injury.STATE

    assert(T(S.HEALTHY, S.INCAPACITATED), "you can be put down from full health")
    assert(T(S.INCAPACITATED, S.STABILIZED), "a bandage helps")
    assert(T(S.INCAPACITATED, S.DEAD), "and the clock does not")
    assert(T(S.STABILIZED, S.RECOVERING), "treatment gets you up")

    -- Two steps, deliberately (D-037): stopping the bleeding is not standing up.
    assert(not T(S.STABILIZED, S.HEALTHY), "a bandage alone is not a cure")
    assert(not T(S.INCAPACITATED, S.INJURED), "you do not shake it off")

    -- Terminal means terminal. This is the guard that stops a later milestone
    -- quietly reviving a corpse.
    for _, state in ipairs(Omerta.Injury.ORDER) do
        assert(not T(S.DEAD, state), "nothing follows death: " .. state)
    end
    assert(not T(S.HEALTHY, S.HEALTHY), "staying put is not a transition")
end)

-- A corpse is the thing you most need to be able to move: hiding a body is
-- what M15's evidence and M20's funeral are both about. The first version
-- untagged the ragdoll on death, which made it inert — no dot, no tooltip,
-- nothing to take hold of, and no way to drag your own body away.
check("the dead are still helpless, so they can still be moved and searched", function()
    loadModules()
    local S = Omerta.Injury.STATE
    assert(Omerta.Injury.IsIncapable(S.DEAD), "a corpse must stay handleable")
    assert(Omerta.Injury.IsIncapable(S.INCAPACITATED))
    assert(Omerta.Injury.IsIncapable(S.STABILIZED))
    assert(not Omerta.Injury.IsIncapable(S.RECOVERING), "back on their feet")
    assert(not Omerta.Injury.IsIncapable(S.CRITICAL), "bleeding but still fighting")
end)

check("being down and being incapable are different questions", function()
    loadModules()
    local S = Omerta.Injury.STATE
    assert(Omerta.Injury.IsDown(S.INCAPACITATED) and Omerta.Injury.IsDown(S.STABILIZED))
    assert(not Omerta.Injury.IsDown(S.DEAD), "a corpse is not at your mercy, it is a corpse")
    assert(not Omerta.Injury.IsDown(S.RECOVERING) and not Omerta.Injury.IsDown(S.CRITICAL))
    -- Incapable covers both, which is what M14/M17 will actually ask.
    assert(Omerta.Injury.IsIncapable(S.DEAD) and Omerta.Injury.IsIncapable(S.INCAPACITATED))
    assert(not Omerta.Injury.IsIncapable(S.CRITICAL), "bleeding but still fighting")
end)

--------------------------------------------------------------------------------
suite("injury.clocks")
--------------------------------------------------------------------------------

-- D-037 §4b, ruled against the recommendation and pinned here so a later edit
-- has to be deliberate rather than accidental.
check("untreated incapacitation expires to death; stabilized does not", function()
    loadModules()
    local S = Omerta.Injury.STATE
    assert(Omerta.Injury.EXPIRES_TO[S.INCAPACITATED] == S.DEAD,
        "D-037: nobody helps you, you die")
    assert(Omerta.Injury.EXPIRES_TO[S.STABILIZED] == S.RECOVERING,
        "somebody stopped the bleeding, so the clock stops killing you")
    assert(Omerta.Injury.EXPIRES_TO[S.RECOVERING] == S.HEALTHY)
    assert(Omerta.Injury.EXPIRES_TO[S.HEALTHY] == nil, "health does not expire")
    assert(Omerta.Injury.EXPIRES_TO[S.DEAD] == nil, "death does not expire")
end)

-- Deadlines are absolute so a restart RESUMES them. A restart that reset the
-- bleed-out clock would rescue everybody who was about to die.
check("a deadline is a moment, not a countdown", function()
    loadModules()
    local E = Omerta.Injury.HasExpired
    assert(not E(1000, 999), "not yet")
    assert(E(1000, 1000), "exactly on the mark")
    assert(E(1000, 1001), "past it")
    assert(not E(nil, 99999), "no clock never expires")
    assert(not E(0, 99999), "nor does a zero one")

    local L = Omerta.Injury.SecondsLeft
    assert(L(1000, 940) == 60)
    assert(L(1000, 1200) == 0, "never negative")
    assert(L(nil, 100) == nil, "no clock, no answer")
end)

--------------------------------------------------------------------------------
suite("injury.recovery")
--------------------------------------------------------------------------------

-- §4c: losing a fight costs something afterwards, and the cost wears off.
check("the recovery penalty is worst on standing up and gone by the end", function()
    loadModules()
    local M = Omerta.Injury.RecoveryMultiplier
    assert(math.abs(M(1, 0.8) - 0.8) < 0.001, "worst at the moment you get up")
    assert(math.abs(M(0, 0.8) - 1) < 0.001, "gone once recovered")
    assert(math.abs(M(0.5, 0.8) - 0.9) < 0.001, "halfway back")
    -- Monotonic: recovering must never make you slower than a moment ago.
    local previous = 0
    for i = 10, 0, -1 do
        local value = M(i / 10, 0.8)
        assert(value >= previous, "the penalty has to ease, not oscillate")
        previous = value
    end
end)

check("a penalty of 1 is no penalty, so the ruling can be tuned to nothing", function()
    loadModules()
    local M = Omerta.Injury.RecoveryMultiplier
    assert(M(1, 1) == 1 and M(0.5, 1) == 1 and M(0, 1) == 1)
end)

check("how much of the window is left is clamped at both ends", function()
    loadModules()
    local R = Omerta.Injury.RemainingFraction
    assert(R(1000, 100, 900) == 1, "just started")
    assert(R(1000, 100, 950) == 0.5, "halfway")
    assert(R(1000, 100, 1000) == 0, "over")
    assert(R(1000, 100, 5000) == 0, "long over, never negative")
    assert(R(nil, 100, 500) == 0, "no clock")
    assert(R(1000, 0, 500) == 0, "no window")
end)

check("hauling a body is heavy, and only while you have hold of one", function()
    loadModules()
    local D = Omerta.Injury.DragSpeedMultiplier
    assert(D(false, 0.55) == 1, "empty handed")
    assert(D(true, 0.55) == 0.55, "loaded")
    assert(D(true, 0) > 0, "never a full stop — that reads as stuck, not laden")
end)

--------------------------------------------------------------------------------
suite("injury.drag")
--------------------------------------------------------------------------------

-- The rope. Slack first, then it goes taut and starts pulling, then it breaks.
check("the line is slack before it pulls at all", function()
    loadModules()
    local T = Omerta.Injury.DragTension
    local R = Omerta.Injury.DRAG
    assert(T(0) == 0, "standing on top of them")
    assert(T(R.SLACK) == 0, "still inside the slack")
    assert(T(R.SLACK + 1) > 0, "past the slack it starts to tighten")
    assert(T(R.TAUT) == 1, "fully taut")
    assert(T(R.TAUT * 4) == 1, "and no tighter than that")
end)

check("a grip that is stretched far enough fails", function()
    loadModules()
    local B = Omerta.Injury.DragBreaks
    local R = Omerta.Injury.DRAG
    assert(not B(R.SLACK), "not while there is slack")
    assert(not B(R.TAUT), "not merely because it is taut")
    assert(B(R.BREAK + 1), "but it does not hold forever")
    -- Breaking must be further than fully taut, or the rope snaps the instant
    -- it does any work and dragging is impossible.
    assert(R.BREAK > R.TAUT, "the rope has to be able to pull before it breaks")
end)

check("a body creeps at first and only really moves once you lean on it", function()
    loadModules()
    local S = Omerta.Injury.DragSpeed
    assert(S(0, 90) == 0, "a slack line moves nothing")
    assert(S(1, 90) == 90, "full tension, full speed")
    -- Eased, so light tension barely shifts them: linear here would make a
    -- body slide the moment you took a step.
    assert(S(0.5, 90) < 45, "half tension is less than half speed")
    local previous = -1
    for i = 0, 10 do
        local speed = S(i / 10, 90)
        assert(speed >= previous, "pulling harder must never move them slower")
        previous = speed
    end
end)

-- The rope has to be able to CLOSE a gap. The first tuning pinned the body to
-- exactly its hauler's pace ("a body must never outrun its hauler"), which
-- sounded like physics and was actually a ratchet: once anything — a kerb, a
-- doorframe, one missed tick — put the body behind, no speed existed to bring
-- it back, so the distance only grew and every drag ended in a lost grip.
-- Catchup above 1 is the headroom that lets the rope settle instead.
check("the rope settles taut, well short of breaking", function()
    loadModules()
    local R = Omerta.Injury.DRAG
    local catchup = Omerta.Config.Get("injury.drag_catchup")

    assert(catchup > 1,
        "no headroom: a body that falls behind can never close the gap again")

    -- Where the rope settles: the tension at which the body keeps exact pace
    -- with its hauler. DragSpeed eases as tension^1.5 and both sides scale
    -- with the walk speed, so the equilibrium is analytic and speed-free:
    -- catchup * t^1.5 = 1.
    local equilibrium = (1 / catchup) ^ (1 / 1.5)
    assert(equilibrium < 1,
        "the rope should not need to be fully taut just to keep pace")

    local settle = R.SLACK + equilibrium * (R.TAUT - R.SLACK)
    assert(settle < R.BREAK * 0.75,
        "steady hauling rides too close to the break for comfort")
end)

check("pulling a light part tows the weight attached to it", function()
    loadModules()
    local T = Omerta.Injury.TowFactor
    assert(T(80, 80) == 1, "holding all of the mass needs no compensation")
    assert(T(40, 80) == 2, "half the mass in hand, twice the shove")
    assert(T(2, 85) == 6, "capped: a hand is a handle, not a slingshot")
    assert(T(200, 80) == 1, "never below one, even when the masses read wrong")
    assert(T(nil, nil) == 1, "nonsense in, direct pull out")
end)

--------------------------------------------------------------------------------
suite("injury.wire")
--------------------------------------------------------------------------------

check("state codes round-trip and are frozen", function()
    loadModules()
    local S = Omerta.Injury.STATE
    for _, state in ipairs(Omerta.Injury.ORDER) do
        local index = Omerta.Injury.STATE_INDEX[state]
        assert(index, state .. " has no wire code")
        assert(Omerta.Injury.STATE_BY_INDEX[index] == state, state .. " does not round-trip")
    end
    -- Frozen values: a stale client reading a renumbered code would be told it
    -- is stabilized while it bleeds out.
    assert(Omerta.Injury.STATE_INDEX[S.HEALTHY] == 1)
    assert(Omerta.Injury.STATE_INDEX[S.DEAD] == 7)
end)

check("prompt sound codes are frozen", function()
    loadModules()
    -- The prompt carries a sound CODE; the client owns which file it means.
    -- Renumbering would make a stale client rustle at the wrong moments.
    assert(Omerta.Injury.PROMPT_SOUND.NONE == 0)
    assert(Omerta.Injury.PROMPT_SOUND.RUSTLE == 1)
end)

-- A timed action's clock reaches the client as a DURATION, and the unit it is
-- sent in decides whether the plate can be drawn at all. Floored whole seconds
-- rounded a fractional action to the wrong length and rounded a sub-second one
-- to nothing — a prompt whose window has already closed, which the controller
-- correctly never draws while the action itself runs and makes its noise.
check("the prompt clock is milliseconds, so no action rounds away", function()
    loadModules()
    local M = Omerta.Injury.PromptMillis
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
    local schema = Omerta.Net.GetRegistry()["injury.prompt"].schema
    local field = nil
    for _, entry in ipairs(schema) do
        assert(entry.name ~= "seconds",
            "whole seconds is the unit that made a short action invisible")
        if entry.name == "millis" then field = entry end
    end
    assert(field, "the prompt has to carry a clock")
    assert(field.bits >= 16, "8 bits cannot hold a duration in milliseconds")
end)

check("a condition is prose, never a number", function()
    loadModules()
    for _, state in ipairs(Omerta.Injury.ORDER) do
        local text = Omerta.Injury.Describe(state)
        if text then
            assert(not text:find("%d"), state .. " is described with a number (GDD §8)")
        end
    end
    -- Nothing to say about being well, so nothing goes on screen (M8).
    assert(Omerta.Injury.Describe(Omerta.Injury.STATE.HEALTHY) == nil)
    assert(Omerta.Injury.Describe("nonsense") == nil, "an unknown state says nothing")
end)

--------------------------------------------------------------------------------
suite("injury.flow")
--------------------------------------------------------------------------------

check("migration 12 creates the state, the bodies and the record", function()
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

    local wanted = {
        omerta_character_injury = false,
        omerta_bodies = false,
        omerta_injury_events = false,
    }
    for _, statement in ipairs(mock.log) do
        for name in pairs(wanted) do
            if statement:find("CREATE TABLE IF NOT EXISTS " .. name, 1, true) then
                wanted[name] = true
            end
        end
    end
    for name, seen in pairs(wanted) do assert(seen, name .. " DDL missing") end
end)

-- The deadline is the load-bearing column: absolute, so a restart resumes a
-- bleed-out instead of restarting it.
check("injury state stores a moment, not a countdown", function()
    loadModules()
    Omerta.Module.FinishLoading()
    local def = Omerta.DB.Internal.GetTableDef("character_injury")
    local sawExpires = false
    for _, col in ipairs(def.columns) do
        if col.name == "expires_at" then
            sawExpires = true
            assert(col.type == "timestamp",
                "a countdown would reset on restart and rescue everyone who was dying")
        end
        assert(col.name ~= "seconds_left" and col.name ~= "remaining",
            "a stored countdown is the bug this column exists to avoid")
    end
    assert(sawExpires, "no deadline column at all")
end)

-- The seams M17's arrest and M20's confirm kill register into. If these stop
-- existing, those milestones start editing this module instead.
check("later milestones have somewhere to register", function()
    loadModules()
    assert(type(Omerta.Injury.RegisterDownedAction) == "function")
    assert(type(Omerta.Injury.RegisterTreatment) == "function")
    assert(type(Omerta.Injury.RegisterDamageFilter) == "function")
    assert(type(Omerta.Injury.Die) == "function", "one death funnel, not two")
end)

check("M9 gained an openable seam rather than a second search path", function()
    loadModules()
    assert(type(Omerta.Inventory.RegisterOpenable) == "function",
        "searching a body must reuse M9's moves, not copy them")
end)

check("M5 can resolve a body as a person, and M7 can take a voice away", function()
    loadModules()
    assert(type(Omerta.Identity.RegisterSubjectProvider) == "function",
        "a body has to resolve through identity, not name itself")
    assert(type(Omerta.Chat.RegisterChannelFilter) == "function")
end)

--------------------------------------------------------------------------------
suite("injury.supplies")
--------------------------------------------------------------------------------

-- M9's catalogue promised "medical supplies to M19"; this is M19 keeping it
-- rather than editing M9's file.
check("a bandage exists, is carriable without thinking, and is bought not found", function()
    loadModules()
    local def = Omerta.Items.Get("medical.bandage")
    assert(def, "no bandage — nobody can be saved")
    assert(def.category == "medical")
    assert(def.stackable, "you should be able to carry a few")
    -- If carrying one were a real decision nobody would, and every gunshot
    -- would be fatal by default.
    assert(def.bulk <= 1, "too bulky to carry casually")

    local supply = Omerta.Procurement.Get("supply.bandages")
    assert(supply, "no supply line — a family cannot stock a clinic")
    assert(supply.item == "medical.bandage")
    assert(supply.price % Omerta.Money.SMALLEST == 0,
        "priced in coins that do not exist")
end)

-- M13 said outright that "a clinic without injuries (M19) is a room".
check("the clinic became a surgery", function()
    loadModules()
    local clinic = Omerta.Business.GetType("clinic")
    assert(clinic, "no clinic type")
    local medical = false
    for _, service in ipairs(clinic.services or {}) do
        if service == "medical" then medical = true end
    end
    assert(medical, "the clinic still cannot treat anybody")
end)

--------------------------------------------------------------------------------
suite("injury.presentation")
--------------------------------------------------------------------------------

-- The curves the client draws. They live in the shared file precisely so they
-- can be checked here — arithmetic in a cl_ file is arithmetic nothing tests.

check("the vignette closes in as the blood runs out, and never blacks out", function()
    loadModules()
    local V = Omerta.Injury.VignetteReach
    assert(V(0, 0) < V(0.5, 0), "halfway is tighter than the start")
    assert(V(0.5, 0) < V(1, 0), "the end is tighter than halfway")
    -- Eases in: barely there early, so being shot is not instantly a tunnel.
    assert(V(0.25, 0) < 0.3, "too aggressive too early")
    -- Never fully closed: a black screen would hide the body somebody is
    -- kneeling over, which is the one thing worth seeing.
    assert(V(1, 0) <= 0.95, "the screen must never fully close")
end)

-- The bug this pins: a symmetric sine spent half of every beat RETREATING, so
-- the screen read as breathing in and out rather than as the edges closing.
-- The pulse must only ever add.
check("the heartbeat pushes in and relaxes back, never below the base", function()
    loadModules()
    local V = Omerta.Injury.VignetteReach
    for step = 0, 10 do
        local progress = step / 10
        local base = V(progress, 0)
        local lowest = base
        for phase = 0, 62 do
            local reach = V(progress, phase / 10)
            assert(reach >= base - 0.0001,
                "the pulse pulled the vignette back below its base at " .. progress)
            lowest = math.min(lowest, reach)
        end
        assert(math.abs(lowest - base) < 0.0001, "the base is the floor of the beat")
    end
end)

-- Whatever the phase, a later moment is never more open than an earlier one.
check("the vignette never opens back up as time runs out", function()
    loadModules()
    local V = Omerta.Injury.VignetteReach
    local previous = -1
    for step = 0, 20 do
        -- Compared at the same point in the beat, so the comparison is of the
        -- base and not of where the heart happens to be.
        local reach = V(step / 20, 0)
        assert(reach >= previous, "the edges retreated between two moments")
        previous = reach
    end
end)

check("the heartbeat quickens as the end nears, and stays slow", function()
    loadModules()
    local P = Omerta.Injury.PulseRate
    assert(P(1) > P(0), "the beat has to quicken or it is just a throb")
    assert(P(0) > 0, "and it has to beat at all")
    -- Under one beat a second even at the very end. This is a heartbeat felt
    -- from the inside, not a strobe; the first version ran to three a second
    -- and read as a flicker.
    assert(P(1) < 1, "too fast to read as a pulse")
end)

check("the death camera holds before it pulls away", function()
    loadModules()
    local D = Omerta.Injury.DEATH
    assert(Omerta.Injury.DeathPhase(0) == "hold", "the camera must sit on the body first")
    assert(Omerta.Injury.DeathPhase(D.CUT_AT) == "rise", "then rise")
    local _, t = Omerta.Injury.DeathPhase(D.CUT_AT + D.RISE * 2)
    assert(t == 1, "and stop when it gets there, not keep climbing")
end)

-- The whole point of the rework: the camera moves while nobody can see it.
-- Cutting in vision read as a glitch.
check("the camera cuts behind black, never in vision", function()
    loadModules()
    local D = Omerta.Injury.DEATH
    local F = Omerta.Injury.DeathFade
    assert(math.abs(F(D.CUT_AT) - 1) < 0.0001,
        "the screen must be fully black at the cut")
    -- Which is also the first frame of the rise, so the two are the same
    -- instant by construction rather than by two numbers agreeing.
    assert(Omerta.Injury.DeathPhase(D.CUT_AT) == "rise")
end)

check("the shot fades back in, holds, then fades out for the words", function()
    loadModules()
    local D = Omerta.Injury.DEATH
    local F = Omerta.Injury.DeathFade
    -- The boundaries are sums and differences of decimals, so the ends land a
    -- float's-breadth off. Compared with a tolerance rather than contorting
    -- the curve to make an equality true.
    local function near(a, b, what) assert(math.abs(a - b) < 0.0001, what) end

    assert(F(0) == 0, "not black at the moment of death")
    assert(F(D.HOLD_OUT) == 0, "still watching from the head")
    near(F(D.VISIBLE_AT), 0, "back in vision on the top-down shot")
    near(F((D.VISIBLE_AT + D.FADE_AT) * 0.5), 0, "and stays visible through the climb")
    near(F(D.RISE_END), 1, "black again by the top of the climb")
    near(Omerta.Injury.DeathTextAlpha(D.RISE_END), 0,
        "the words must not start before the screen is black")
    near(Omerta.Injury.DeathTextAlpha(D.TEXT_AT + D.TEXT_OVER), 1, "fully readable")
end)

-- The climb is the last thing that happens to this character; it should not be
-- over before the fade back in has finished.
check("the climb is slow enough to be seen", function()
    loadModules()
    local D = Omerta.Injury.DEATH
    assert(D.RISE > D.FADE_IN * 2, "the shot would be over before it was visible")
    assert(D.FADE_AT > D.VISIBLE_AT, "there has to be a stretch you can actually watch")
end)

check("the rise eases out rather than sliding like a lift", function()
    loadModules()
    local E = Omerta.Injury.RiseEase
    assert(E(0) == 0 and E(1) == 1, "both ends are pinned")
    assert(E(0.5) > 0.5, "most of the distance is covered early")
    local previous = -1
    for i = 0, 10 do
        local value = E(i / 10)
        assert(value >= previous, "the camera must never travel backwards")
        previous = value
    end
end)

-- The loop seam: a quick dip at both ends so it is a breath, not a click.
check("the music dips at both ends of its loop", function()
    loadModules()
    local L = Omerta.Injury.LoopVolume
    assert(L(0, 60, 2) == 0, "silent at the very start")
    assert(L(2, 60, 2) == 1, "up to full after the fade")
    assert(L(30, 60, 2) == 1, "full through the middle")
    assert(L(59, 60, 2) == 0.5, "easing out at the end")
    assert(L(60, 60, 2) == 0, "silent at the seam")
    -- Degenerate inputs must not silence the track entirely.
    assert(L(0, 0, 2) == 1, "no length, no envelope")
    assert(L(1, 3, 2) == 1, "a fade longer than the track is ignored")
end)

check("the prompt after death does not promise a soul coming back", function()
    loadModules()
    -- D-012 and GDD §19.3: the next character inherits nothing. Wording that
    -- implied otherwise would be the UI contradicting the design.
    local prompt = Omerta.Injury.DEATH_PROMPT
    assert(type(prompt) == "string" and prompt ~= "")
    assert(not prompt:lower():find("respawn"), "respawn is the wrong idea entirely")
end)

--------------------------------------------------------------------------------
suite("injury.focus")
--------------------------------------------------------------------------------

check("vision blurs further out as the end nears, and starts already soft", function()
    loadModules()
    local B = Omerta.Injury.BlurAmount
    assert(B(0) < B(0.5) and B(0.5) < B(1), "focus has to keep going")
    -- Field-tested the other way first: a nearly-sharp start read as nothing
    -- having happened. Going down is a blow, and the world goes soft with it.
    assert(B(0) >= 2, "the world is already soft the moment you are down")
    assert(B(0) <= 3, "but not paused-menu soft — help arriving still has to be visible")
    -- Same squared shape as the vignette, so the two read as one effect.
    assert(B(0.5) - B(0) < B(1) - B(0.5), "the loss should accelerate")
end)

check("the pan starts above the body and climbs from there", function()
    loadModules()
    local D = Omerta.Injury.DEATH
    assert(D.START_HEIGHT > 0, "the shot has to begin off the floor")
    assert(D.HEIGHT > D.START_HEIGHT, "and it has to climb, not descend")
end)

--------------------------------------------------------------------------------
suite("injury.exit")
--------------------------------------------------------------------------------

-- Pressing a key used to cut straight to the creator, throwing the moment away
-- in one frame. The exit is its own small sequence now.
check("the words go before the black lifts", function()
    loadModules()
    local E = Omerta.Injury.EXIT
    local T, F = Omerta.Injury.ExitTextAlpha, Omerta.Injury.ExitFade

    assert(T(0) == 1, "the words are still there at the keypress")
    assert(T(E.TEXT) == 0, "and gone by the end of their fade")
    -- Solid black across the whole handover, so what is built behind it is
    -- revealed rather than appearing on top of it.
    assert(F(0) == 1 and F(E.TEXT) == 1, "the screen stays black while they go")
    assert(F(E.BUILD_AT) == 1, "still black at the moment the next screen builds")
    assert(F(E.TOTAL) == 0, "and clear by the end")
    assert(E.BUILD_AT > E.TEXT, "the next screen must not build over the words")
end)

check("the music goes out with them rather than stopping dead", function()
    loadModules()
    local E = Omerta.Injury.EXIT
    local M = Omerta.Injury.ExitMusic
    assert(M(0) == 1, "full volume at the keypress")
    assert(M(E.BUILD_AT) == 0, "silent by the handover")
    local previous = 2
    for i = 0, 10 do
        local v = M((i / 10) * E.BUILD_AT)
        assert(v <= previous, "the fade must not swell back up")
        previous = v
    end
end)

check("the sequence ends, rather than leaving the screen black forever", function()
    loadModules()
    assert(Omerta.Injury.ExitDone(Omerta.Injury.EXIT.TOTAL))
    assert(not Omerta.Injury.ExitDone(0))
end)

--------------------------------------------------------------------------------
suite("injury.hold")
--------------------------------------------------------------------------------

-- The hold point is what makes the mouse part of dragging: it follows where
-- the hauler is LOOKING, so turning swings the body round a corner.
check("the hold point sits in front of where you are looking", function()
    loadModules()
    local H = Omerta.Injury.HoldPoint
    local origin = Vector(0, 0, 0)

    local ahead = H(origin, Vector(1, 0, 0), 50)
    assert(math.abs(ahead.x - 50) < 0.001 and math.abs(ahead.y) < 0.001,
        "looking down +X should hold the rope down +X")

    local left = H(origin, Vector(0, 1, 0), 50)
    assert(math.abs(left.y - 50) < 0.001, "turning moves the hold point with you")
end)

-- Aiming at the sky must not lift a body off the ground.
check("looking up does not hoist the body", function()
    loadModules()
    local H = Omerta.Injury.HoldPoint
    local up = H(Vector(0, 0, 0), Vector(0.2, 0, 0.98), 50)
    assert(math.abs(up.z) < 0.001, "the hold point is flattened to the floor")
    -- Still a sensible horizontal distance rather than a collapsed point.
    assert(math.abs(up.x - 50) < 0.001, "and keeps its full reach")
end)

check("straight up is not a division by zero", function()
    loadModules()
    local up = Omerta.Injury.HoldPoint(Vector(0, 0, 0), Vector(0, 0, 1), 50)
    assert(up.z == 0 and up:Length() > 0, "a degenerate aim still yields a point")
end)

--------------------------------------------------------------------------------
suite("injury.search_intent")
--------------------------------------------------------------------------------

-- E over a body is one key with two meanings: go through their pockets, or stop
-- going through them. Which one it is, is the server's decision and this is the
-- rule it makes it with.

check("E on a body you are already searching stops the search", function()
    loadModules()
    local I = Omerta.Injury.SearchIntent
    assert(I(nil, 7) == "search", "nothing in progress: go through their pockets")
    assert(I({ characterId = 7, id = "injury.search_body" }, 7) == "cancel",
        "the same body again is a stop")
end)

check("stopping one thing does not stop another", function()
    loadModules()
    local I = Omerta.Injury.SearchIntent
    -- Busy with somebody ELSE. The refusal for that belongs to Perform, which
    -- owns the sentence the player reads, so the answer here is still "search".
    assert(I({ characterId = 9 }, 7) == "search", "a different body is not a stop")
    -- Anything timed on THIS body answers to the key, not only a search: an
    -- action you cannot back out of is one you started by accident.
    assert(I({ characterId = 7, id = "injury.stabilize" }, 7) == "cancel")
end)

check("one press cannot stop a search and start it again", function()
    loadModules()
    local I = Omerta.Injury.SearchIntent
    local lock = Omerta.Injury.SEARCH_RESTART_SECONDS
    assert(lock > 0, "there has to be a lock at all")

    -- The interaction path sends one message per press, but the engine's own
    -- +use fallback re-fires for as long as the key is held — so without this
    -- a hold would stop and restart the rummage several times a second and it
    -- would never finish.
    assert(I(nil, 7, 0) == "ignore", "the same hold does not restart it")
    assert(I(nil, 7, lock * 0.5) == "ignore", "nor does the rest of it")
    assert(I(nil, 7, lock) == "search", "a fresh press does")
    assert(I(nil, 7, lock + 10) == "search", "and so does one much later")
    assert(I(nil, 7, nil) == "search", "never having stopped is not a lock")

    -- The lock is short enough that changing your mind is not punished.
    assert(lock <= 1, "half a second is a mistake being prevented, not a cooldown")
end)

check("the lock never blocks a stop", function()
    loadModules()
    local I = Omerta.Injury.SearchIntent
    -- Two presses inside the lock window while a search runs: the second is
    -- still a stop. Refusing it would make the search uncancellable for exactly
    -- as long as the lock lasts, which is the bug wearing the fix's clothes.
    assert(I({ characterId = 7 }, 7, 0) == "cancel")
end)

check("a press over nothing is not a search", function()
    loadModules()
    local I = Omerta.Injury.SearchIntent
    assert(I(nil, nil) == "ignore", "no body, no verb")
    assert(I({ characterId = 7 }, nil) == "ignore")
end)

-- The other half of "one press, one meaning", and the one that was missing.
-- The suite pinned that a press cannot STOP and then START a search; nothing
-- pinned that it cannot START one and then STOP it, which is what two entry
-- paths landing on BeginSearch for a single press actually did — the plate was
-- told to appear and told to go away a tick later, before it had faded in far
-- enough to be seen, while the rummage carried on being audible.
check("one press cannot start a search and stop it again", function()
    loadModules()
    local I = Omerta.Injury.SearchIntent
    local lock = Omerta.Injury.SEARCH_RESTART_SECONDS
    local current = { characterId = 7, id = "injury.search_body" }

    assert(I(current, 7, nil, 0) == "ignore",
        "a stop arriving with the start is the same press counted twice")
    assert(I(current, 7, nil, 1 / 66) == "ignore", "a server tick later, still")
    assert(I(current, 7, nil, lock * 0.5) == "ignore", "and through the lock")

    -- A real second press still stops it. The lock is a duplicate filter, not
    -- a commitment: a search you cannot back out of is the bug this whole rule
    -- exists to prevent.
    assert(I(current, 7, nil, lock) == "cancel")
    assert(I(current, 7, nil, 30) == "cancel", "and much later")

    -- The two locks are the same number on purpose: one physical press, one
    -- meaning, whichever side of the action it lands on.
    assert(lock <= 1, "and short enough to be invisible in the hand")
end)

check("not knowing how long it has run is not a reason to refuse a stop", function()
    loadModules()
    local I = Omerta.Injury.SearchIntent
    -- Every caller that has the number passes it; one that does not must not
    -- silently make a search uncancellable.
    assert(I({ characterId = 7 }, 7) == "cancel")
    assert(I({ characterId = 7 }, 7, nil, nil) == "cancel")
end)

--------------------------------------------------------------------------------
suite("injury.use_edge")
--------------------------------------------------------------------------------

-- GM:PlayerUse reports a LEVEL — it fires again on every tick the key is held —
-- and sv_bodies' fallback fed each of those calls to BeginSearch as though it
-- were a fresh press. The gap between two calls is the only evidence the key
-- ever came up, so that is the rule.

check("holding the use key is one press, not one press per tick", function()
    loadModules()
    local F = Omerta.Injury.IsFreshUse
    assert(F(nil) == true, "the first use there has ever been is a press")
    assert(F(0) == false, "the same tick is not a second press")
    assert(F(1 / 66) == false, "nor is the next one")
    assert(F(1 / 22) == false, "nor is the next one on a slow tickrate")
    assert(F(Omerta.Injury.USE_EDGE_SECONDS) == true, "a gap is a release")
    assert(F(5) == true, "and much later is plainly a new press")
end)

check("the edge is wider than a tick and narrower than a decision", function()
    loadModules()
    local gap = Omerta.Injury.USE_EDGE_SECONDS
    -- Below a couple of ticks it stops detecting the release at all, which is
    -- the bug. Above a third of a second it starts eating deliberate presses.
    assert(gap > 2 * (1 / 22), "must survive a slow server's tick")
    assert(gap <= 0.35, "must not swallow a second press")
end)
