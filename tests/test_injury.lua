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
    "gamemodes/omertarp/gamemode/modules/hud/sh_gait.lua",
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
    "gamemodes/omertarp/gamemode/modules/injury/sh_injury_falls.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sh_supplies.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_falls.lua",
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

--------------------------------------------------------------------------------
suite("injury.falls")
--------------------------------------------------------------------------------

-- The fall curve is the thing in this milestone most likely to be retuned in
-- the field, which is exactly why the band edges are pinned to the unit. An
-- off-by-one at a threshold is the classic failure here: a leg that breaks one
-- unit early, or a height that is configured "safe" and is not.

check("how far you fell is how fast you arrived, converted exactly", function()
    loadModules()
    local H = Omerta.Injury.FallHeight
    -- h = v^2 / 2g, and nothing else.
    assert(H(600, 600) == 300, "600 units/second under 600 gravity is 300 units")
    assert(H(0, 600) == 0, "a step off nothing is nothing")
    assert(H(-400, 600) == 0, "travelling upward is not a fall")
    -- Halving gravity doubles the height a given speed represents, which is
    -- why the cvar is read at the moment of the fall rather than assumed.
    assert(H(600, 300) == 600, "low gravity, longer fall for the same impact")
    assert(H(600, 0) == H(600, Omerta.Injury.FALL_GRAVITY),
        "an impossible gravity falls back rather than dividing by zero")
    assert(H(nil, nil) == 0, "nonsense in, nothing out")
end)

-- The edges, one unit either side, on a curve with round numbers so the
-- assertions are readable. A configured height is the height at which the thing
-- the key is NAMED for happens.
check("the band edges are exact, and each threshold owns its own height", function()
    loadModules()
    local curve = Omerta.Injury.FallCurve(100, 200, 400, 30, 100)
    local B = function(h) return Omerta.Injury.FallBand(h, curve) end
    local BAND = Omerta.Injury.FALL_BAND

    assert(B(0) == BAND.NONE, "standing still is not falling")
    assert(B(99) == BAND.NONE, "one unit inside the safe height")
    assert(B(100) == BAND.LOW, "AT the safe height the band has opened")
    assert(B(199) == BAND.LOW, "one unit short of the break")
    assert(B(200) == BAND.MEDIUM, "AT the break height the leg goes")
    assert(B(399) == BAND.MEDIUM, "one unit short of going down")
    assert(B(400) == BAND.HIGH, "AT the down height you are on the floor")
    assert(B(400000) == BAND.HIGH, "and there is nothing worse to be")
end)

check("the damage climbs continuously across the bands, never in steps", function()
    loadModules()
    local curve = Omerta.Injury.FallCurve(100, 200, 400, 30, 100)
    local D = function(h) return Omerta.Injury.FallDamage(h, curve) end

    assert(D(50) == 0 and D(100) == 0, "nothing below the safe height, and nothing at it")
    assert(D(150) == 15, "half way through the low band is half the low damage")
    assert(D(200) == 30, "the knot is the configured number, exactly")
    assert(D(300) == 65, "half way through the medium band is half of what is left")
    assert(D(400) == 100, "and the second knot likewise")
    assert(D(4000) == 100, "clamped: past the down height nothing gets worse")

    -- The band edge must not be a cliff. One unit of height may not cost a
    -- meaningful amount of health, or the threshold becomes a bug report.
    assert(D(200) - D(199) <= 1, "a step at the break height")
    assert(D(400) - D(399) <= 1, "a step at the down height")

    local previous = -1
    for height = 0, 500, 1 do
        local value = D(height)
        assert(value >= previous, "falling further must never hurt less")
        previous = value
    end
end)

-- Omerta.Config validates each key against its own bounds and cannot see the
-- relationship between two of them. A mistyped config must degrade, not invert.
check("a nonsense configuration is straightened out rather than obeyed", function()
    loadModules()
    -- Break above down, and the light fall hurting more than the heavy one.
    local curve = Omerta.Injury.FallCurve(500, 900, 200, 80, 10)
    assert(curve.safe < curve.breakAt, "the safe height must come first")
    assert(curve.breakAt < curve.downAt, "and the break before the fall")
    assert(curve.downDamage >= curve.breakDamage,
        "a higher fall that hurt less would make jumping from further up the safe play")

    local previous = -1
    for height = 0, 1200, 10 do
        local value = Omerta.Injury.FallDamage(height, curve)
        assert(value >= previous, "the straightened curve still has to rise")
        previous = value
    end
end)

--------------------------------------------------------------------------------
suite("injury.falls_calibration")
--------------------------------------------------------------------------------

-- The shipped numbers, against M19's own bands (below 70% hurt, below 35%
-- critical, 0 down) the way the arsenal calibrates a weapon.

local function shippedCurve()
    return Omerta.Injury.Internal.FallCurve()
end

check("a low fall takes health and leaves the leg alone", function()
    loadModules()
    local curve = shippedCurve()
    local BAND = Omerta.Injury.FALL_BAND
    local S = Omerta.Injury.STATE

    local topOfLow = curve.breakAt - 1
    assert(Omerta.Injury.FallBand(topOfLow, curve) == BAND.LOW)

    -- The low band is not a free band: it opens at no damage and crosses into
    -- M19's injured band before it ends, so the worst survivable fall that
    -- leaves you walking properly still costs you something you can feel.
    assert(Omerta.Injury.FallDamage(curve.safe, curve) == 0, "the safe height is free")
    local worst = Omerta.Injury.FallDamage(topOfLow, curve)
    assert(worst > 0 and worst < 100, "a low fall is survivable and not free")
    assert(Omerta.Injury.StateForHealth(100 - worst, 100, S.HEALTHY) == S.INJURED,
        "the worst low fall should leave a full-health character hurt")

    -- And the crossing into hurt happens INSIDE the band, not on its edge: an
    -- outcome that depends on which way a comparison rounds is an outcome that
    -- gets reported as a bug (the arsenal's rule about the M1911, applied here).
    local crossing = nil
    for height = math.floor(curve.safe), math.floor(curve.breakAt) do
        local left = 100 - Omerta.Injury.FallDamage(height, curve)
        if Omerta.Injury.StateForHealth(left, 100, S.HEALTHY) == S.INJURED then
            crossing = height
            break
        end
    end
    assert(crossing, "a low fall never manages to hurt anybody")
    assert(curve.breakAt - crossing >= 10,
        "the hurt threshold sits on top of the break threshold; separate them")
end)

check("a medium fall costs more health AND the leg, and is survivable", function()
    loadModules()
    local curve = shippedCurve()
    local BAND = Omerta.Injury.FALL_BAND
    local S = Omerta.Injury.STATE

    assert(Omerta.Injury.FallBand(curve.breakAt, curve) == BAND.MEDIUM,
        "the leg goes at the height the key is named after")

    local atBreak = Omerta.Injury.FallDamage(curve.breakAt, curve)
    assert(atBreak > Omerta.Injury.FallDamage(curve.breakAt - 100, curve),
        "a medium fall has to cost more health than a low one")
    assert(Omerta.Injury.StateForHealth(100 - atBreak, 100, S.HEALTHY) == S.INJURED,
        "the cheapest medium fall should hurt without being critical")

    -- Survivable at full health across essentially the whole band. The last
    -- sliver of it rounds up into lethality because the curve is CONTINUOUS
    -- with the high band — that is the design, not an edge case, and it is
    -- what stops the boundary being a cliff.
    local nearTop = curve.downAt - (curve.downAt - curve.breakAt) * 0.05
    assert(Omerta.Injury.FallDamage(nearTop, curve) < 100,
        "a full-health character should survive all but the last stretch of the medium band")

    -- Somewhere in the middle it stops being survivable twice over.
    local critical = nil
    for height = math.floor(curve.breakAt), math.floor(curve.downAt) do
        local left = 100 - Omerta.Injury.FallDamage(height, curve)
        if Omerta.Injury.StateForHealth(left, 100, S.HEALTHY) == S.CRITICAL then
            critical = height
            break
        end
    end
    assert(critical, "no medium fall ever leaves anybody bleeding badly")
    assert(critical - curve.breakAt > 50 and curve.downAt - critical > 50,
        "the critical crossing should sit in the middle of the band, not on an edge")
end)

-- The project lead's requirement, in one check: "there will be a point where a
-- fall will incapacitate you even if you were full health if high enough."
check("a high enough fall puts a character down from full health", function()
    loadModules()
    local curve = shippedCurve()
    local BAND = Omerta.Injury.FALL_BAND

    -- FallBand is given a HEIGHT and nothing else. There is no health, no
    -- damage number and no player in its arguments, so there is nothing for a
    -- full health bar — or a damage filter, or a heavy coat — to argue with.
    assert(Omerta.Injury.FallBand(curve.downAt, curve) == BAND.HIGH,
        "the down height must be the height you go down at")
    assert(Omerta.Injury.FallBand(curve.downAt * 4, curve) == BAND.HIGH)

    -- And the arithmetic agrees with the rule rather than merely coexisting
    -- with it: at the same height the curve has taken a whole health bar, so
    -- the last unit of the medium band and the first of the high one are the
    -- same fall. An operator who lowers fall_down_damage breaks the agreement
    -- and not the guarantee — the module takes the terminal path directly.
    assert(Omerta.Injury.FallDamage(curve.downAt, curve) >= 100,
        "the curve and the band disagree about what a fatal fall costs")

    -- A high fall breaks the leg too, so somebody treated back onto their feet
    -- gets up still limping. A condition outliving a state is the point of it
    -- being a condition.
    assert(Omerta.Injury.FallBand(curve.downAt, curve) ~= BAND.LOW,
        "the high band must be past the break height, not beside it")
    assert(curve.downAt > curve.breakAt)
end)

-- Why this module cannot use GAMEMODE:GetFallDamage, asserted rather than
-- explained: the engine only reaches that hook above its own hardcoded safe
-- fall speed, so a threshold below it would be a config key that did nothing.
check("the safe height is below the engine's own, so the engine cannot report it", function()
    loadModules()
    local ENGINE_SAFE_SPEED = 580 -- PLAYER_MAX_SAFE_FALL_SPEED
    local engineFloor = Omerta.Injury.FallHeight(ENGINE_SAFE_SPEED,
        Omerta.Injury.FALL_GRAVITY)
    assert(Omerta.Config.Get("injury.fall_safe_height") < engineFloor,
        "the configured safe height is above the engine's, so this hook choice " ..
        "is no longer load-bearing — but OnPlayerHitGround is still the only " ..
        "one that sees every landing")
end)

--------------------------------------------------------------------------------
suite("injury.leg")
--------------------------------------------------------------------------------

check("a broken leg is a condition, not an eighth state", function()
    loadModules()
    -- Adding it to the ladder would multiply the transition table and break
    -- IsDown/IsIncapable/StateForHealth, all of which read the ladder as one
    -- linear situation. M19 §9 said impairments attach beside the states.
    for _, state in ipairs(Omerta.Injury.ORDER) do
        assert(state ~= "leg" and state ~= "broken_leg" and state ~= "limping",
            "a condition has been promoted into the state machine")
    end
    assert(Omerta.Injury.IMPAIRMENT.LEG == "leg", "the vocabulary is named, not boolean")
    assert(type(Omerta.Injury.BreakLeg) == "function")
    assert(type(Omerta.Injury.HealLeg) == "function")
    assert(type(Omerta.Injury.HasBrokenLeg) == "function")
end)

check("a broken leg survives a restart, because its deadline is a moment", function()
    loadModules()
    Omerta.Module.FinishLoading()
    local def = Omerta.DB.Internal.GetTableDef("character_impairments")
    assert(def, "impairments are not persisted at all — a reconnect would mend them")

    local sawExpires, sawKey = false, false
    for _, col in ipairs(def.columns) do
        if col.name == "expires_at" then
            sawExpires = true
            assert(col.type == "timestamp",
                "a stored countdown would restart on boot and mend every leg")
        end
        if col.name == "impairment" then sawKey = true end
        assert(col.name ~= "seconds_left" and col.name ~= "remaining",
            "a stored countdown is the bug this column exists to avoid")
    end
    assert(sawExpires, "no deadline column at all")
    assert(sawKey, "a named impairment is what makes the second one a row, not a migration")
end)

check("migration 14 creates the impairment record", function()
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

    local seen = false
    for _, statement in ipairs(mock.log) do
        if statement:find("CREATE TABLE IF NOT EXISTS omerta_character_impairments",
                1, true) then
            seen = true
        end
    end
    assert(seen, "impairments DDL missing")
end)

check("there are exactly three snaps, and every one is a file on disk", function()
    loadModules()
    assert(Omerta.Injury.LEG_BREAK_SOUNDS == 3, "the lead supplied three variations")

    local seen = {}
    for index = 1, Omerta.Injury.LEG_BREAK_SOUNDS do
        local path = Omerta.Injury.LegBreakSound(index)
        assert(not seen[path], "two variations resolve to the same file: " .. path)
        seen[path] = true
        -- A registered path and a played path that differ by one character is a
        -- sound nobody ever hears and nothing ever reports. Both come from this
        -- function; this is the check that the function is right about disk.
        local handle = io.open("gamemodes/omertarp/content/sound/" .. path, "rb")
        assert(handle, "no such sound file: " .. path)
        handle:close()
    end

    -- Out of range must land on something real rather than on a silent path.
    assert(Omerta.Injury.LegBreakSound(0) == Omerta.Injury.LegBreakSound(1))
    assert(Omerta.Injury.LegBreakSound(99) == Omerta.Injury.LegBreakSound(1))
    assert(Omerta.Injury.LegBreakSound(nil) == Omerta.Injury.LegBreakSound(1))
end)

check("the sound is played quietly rather than re-encoded", function()
    loadModules()
    local volume = Omerta.Config.Get("injury.leg_break_volume")
    assert(volume > 0 and volume < 1,
        "the files are loud; the fix is a volume an operator can turn back up")
end)

check("a broken leg gets a sentence, and never the loudest one", function()
    loadModules()
    local D = Omerta.Injury.Describe
    local S = Omerta.Injury.STATE

    assert(D(S.HEALTHY) == nil, "an unbroken healthy character still says nothing")
    assert(D(S.HEALTHY, true) == "Your leg is broken.")
    assert(D(S.INJURED, true) == "You are hurt. Your leg is broken.",
        "both are true and the player is entitled to both")
    -- Bleeding badly outranks a bone, and being on the floor outranks everything.
    assert(D(S.CRITICAL, true) == D(S.CRITICAL), "the leg is the least of it")
    assert(D(S.INCAPACITATED, true) == D(S.INCAPACITATED))
    assert(D(S.STABILIZED, true) == D(S.STABILIZED))
    assert(D(S.DEAD, true) == D(S.DEAD))

    for _, state in ipairs(Omerta.Injury.ORDER) do
        local text = D(state, true)
        assert(text == nil or not text:find("%d"), state .. " leaked a number")
    end
end)

--------------------------------------------------------------------------------
suite("injury.limp")
--------------------------------------------------------------------------------

-- "Walk slower then faster" — an uneven gait, not a flat penalty. The curve is
-- pinned here because the thing that makes it read as a limp rather than as lag
-- is its shape, and a shape is exactly what a later tuning pass can flatten
-- without noticing.

check("the gait phase comes from distance walked, so standing still cannot limp", function()
    loadModules()
    local P = Omerta.Injury.LimpPhase
    local stride = Omerta.Injury.LIMP.STRIDE

    assert(P(0, stride) == 0, "nobody has moved")
    assert(math.abs(P(stride * 0.5, stride) - 0.5) < 1e-9, "half a stride, half a cycle")
    assert(math.abs(P(stride, stride)) < 1e-9, "one stride is one whole cycle")
    assert(math.abs(P(stride * 7.25, stride) - 0.25) < 1e-9, "and it keeps wrapping")

    -- A stationary character produces the same phase forever, which is what
    -- makes "does not fire while standing still" a property rather than a
    -- special case. A clock-driven gait would rock somebody stood at a bar.
    assert(P(1234.5, stride) == P(1234.5, stride))
    assert(P(0, 0) == 0, "an impossible stride does not divide by zero")
end)

check("the stride goes slowest, then fastest, and back — once", function()
    loadModules()
    local L = Omerta.Injury.LimpSpeedMultiplier
    local mid, swing = 0.72, 0.22
    local push = Omerta.Injury.LIMP.PUSH_SHARE

    assert(math.abs(L(0, mid, swing) - (mid - swing)) < 1e-9,
        "the stride starts with the weight on the bad leg")
    assert(math.abs(L(push, mid, swing) - (mid + swing)) < 1e-9,
        "and is fastest pushing off the good one")
    assert(math.abs(L(1, mid, swing) - L(0, mid, swing)) < 1e-9,
        "the cycle has to join up, or every stride starts with a jolt")

    -- Exactly one rise and one fall. Anything else is jitter, and jitter is
    -- what reads as a dropped packet rather than as a leg.
    local previous = L(0, mid, swing)
    for i = 1, 100 do
        local value = L(push * i / 100, mid, swing)
        assert(value >= previous - 1e-9, "the shove has to be monotonic")
        previous = value
    end
    previous = L(push, mid, swing)
    for i = 1, 100 do
        local value = L(push + (1 - push) * i / 100, mid, swing)
        assert(value <= previous + 1e-9, "and the settle after it")
        previous = value
    end

    -- A limp is a SHORT shove and a LONG settle. Reversing those two is the
    -- difference between favouring a leg and skipping.
    assert(push < 0.5, "the shove must be the shorter half of the stride")
end)

check("the limp never stops anybody dead, however it is configured", function()
    loadModules()
    local L = Omerta.Injury.LimpSpeedMultiplier
    for i = 0, 40 do
        local phase = i / 40
        assert(L(phase, 0.72, 0.22) > 0, "a standing stop reads as stuck, not as a limp")
        -- Swing wider than the middle would take the multiplier through zero.
        assert(L(phase, 0.5, 5) > 0, "an absurd swing is clamped, not obeyed")
        assert(L(phase, 0.72, 0) == 0.72, "no swing is a flat penalty and no limp")
    end
end)

-- The seam is M8's, and the check that matters is that the limp survives it:
-- the speed floor is 25% of the walk, and a limp flattened against the floor is
-- a flat penalty wearing a limp's name.
check("the limp survives the movement floor, and stacks with recovering", function()
    loadModules()
    local mid = Omerta.Config.Get("injury.limp_speed_scale")
    local swing = Omerta.Config.Get("injury.limp_swing")
    local worstRecovery = Omerta.Config.Get("injury.recovery_speed_scale")
    local floor = Omerta.HUD.Internal.MIN_SPEED_FRACTION

    assert(swing > 0, "a swing of zero is a flat penalty and no limp at all")
    assert(mid - swing > floor,
        "the slow half of the stride is clamped away by the movement floor")
    assert((mid - swing) * worstRecovery > floor,
        "limping while recovering from a shooting clamps, so the limp disappears " ..
        "exactly when a player is most likely to have one")

    -- End to end against D-034's base: the two ends of one stride have to be
    -- different speeds after the flooring and the flooring's integer maths, or
    -- there is nothing to feel.
    local base = Omerta.HUD.Internal.BaseMovement()
    local L = Omerta.Injury.LimpSpeedMultiplier
    local slow = Omerta.HUD.Internal.MovementFor(base, L(0, mid, swing), false)
    local fast = Omerta.HUD.Internal.MovementFor(base,
        L(Omerta.Injury.LIMP.PUSH_SHARE, mid, swing), false)
    assert(fast > slow, "both ends of the stride land on the same walk speed")
    assert(fast - slow >= 10,
        "the difference between the two legs is too small to read as a limp")
end)

-- The limp was slowed on 2026-08-02 ("lower the runspeed when you have a broken
-- leg"). WHICH END of the stride moved is the whole ruling, so it is pinned
-- rather than left to whoever next edits the two numbers.
check("the limp is slower throughout, and not merely slower at its slowest", function()
    loadModules()
    local mid = Omerta.Config.Get("injury.limp_speed_scale")
    local swing = Omerta.Config.Get("injury.limp_swing")

    assert(mid == 0.68 and swing == 0.21, "the tuned pair")

    -- The AVERAGE came down. That is the request: a man on a broken leg covers
    -- less ground per second than he did, at every point of the stride.
    assert(mid < 0.72, "the middle of the gait did not move")
    assert(mid + swing < 0.94, "the good leg's push is slower than it was")
    assert(mid - swing < 0.50, "and so is the bad leg's settle")

    -- The SHAPE did not. The ratio between the shove and the settle is what the
    -- eye reads as a limp rather than as network lag (sh_injury_falls), and it
    -- was tuned in the field: 0.94/0.50 was 1.88, and this must stay near it.
    -- A limp that is slower ONLY at its slowest is a lurch, which is a different
    -- injury from the one the lead asked to slow down.
    local ratio = (mid + swing) / (mid - swing)
    assert(math.abs(ratio - 1.88) < 0.1,
        string.format("the gait changed shape, not just pace (ratio %.2f)", ratio))

    -- The slowest point of the stride is deliberately almost where it was: it is
    -- the moment the whole modifier stack is nearest M8's clamp, and anything
    -- flattened there stops being a limp at all.
    assert(mid - swing > 0.45, "the bottom of the stride fell further than intended")

    -- Compounding with the lowered jog is the other half of the answer: the
    -- multiplier moved 5.5%, the ground covered at a run moved far more.
    local jog = Omerta.Config.Get("movement.jog_speed")
    assert(math.floor(jog * mid) <= 120, "a limping run is not much slower than it was")
end)

-- THE CALIBRATION CHECK. Every registered speed modifier at once, every number
-- read from the module that owns it, and the answer taken end to end through
-- M8's seam rather than off the raw product — because the property being
-- protected is about SPEEDS a player can tell apart, and the seam floors and
-- rounds to integers before anybody feels anything.
--
-- The property: a starving, limping, overloaded man must still be measurably
-- faster than the clamp, so that three penalties read as three penalties
-- instead of all piling onto MIN_SPEED_FRACTION and reading as one crawl.
-- This is the check the 2026-08-02 pass had to spend headroom against, and it
-- is deliberately the thing that will fail first if anybody lowers any of the
-- three again.
check("every penalty at once still leaves a speed, not the clamp", function()
    loadModules()
    local M = Omerta.HUD.Internal.MovementFor
    local C = Omerta.HUD.Internal.CombineModifiers
    local MIN = Omerta.HUD.Internal.MIN_SPEED_FRACTION
    local base = Omerta.HUD.Internal.BaseMovement()

    local mid = Omerta.Config.Get("injury.limp_speed_scale")
    local swing = Omerta.Config.Get("injury.limp_swing")
    local L = Omerta.Injury.LimpSpeedMultiplier

    local starving = function() return Omerta.Hunger.SpeedMultiplier(0) end
    local overloaded = function()
        return Omerta.Inventory.OverloadSpeedMultiplier(3000, 2000,
            Omerta.Config.Get("inventory.overload_speed_floor"),
            Omerta.Config.Get("inventory.overload_reach"))
    end
    -- THE MIDDLE OF THE GAIT, taken from the curve rather than asserted: the
    -- warp puts the cosine on zero a quarter of the way through the shove, so
    -- this phase is exactly `mid` and stays exactly `mid` if the warp is ever
    -- retuned. The calibration is written against the AVERAGE of a stride; the
    -- two ends of it are handled at the bottom of this check.
    local average = Omerta.Injury.LIMP.PUSH_SHARE / 2
    local limping = function() return L(average, mid, swing) end

    assert(math.abs(limping() - mid) < 1e-9,
        "that phase is no longer the middle of the gait")
    assert(starving() == 0.75 and overloaded() == 0.55,
        "the two floors this calibration is written against have moved")

    local clamped = math.floor(base.walk * MIN)
    local function walkAt(...)
        local mods = {}
        for index, fn in ipairs({ ... }) do mods["m" .. index] = fn end
        return (M(base, C(mods, nil), false))
    end

    local none = walkAt()
    local one = walkAt(overloaded)
    local two = walkAt(overloaded, limping)
    local three = walkAt(overloaded, limping, starving)

    -- Four distinct speeds. This is the whole property: if any two of these are
    -- equal, a penalty has stopped being visible to the player.
    assert(none > one and one > two and two > three,
        string.format("%d / %d / %d / %d — a penalty is invisible",
            none, one, two, three))
    assert(three > clamped, string.format(
        "a starving, limping, overloaded man is on the %d clamp at %d",
        clamped, three))

    -- With real margin, not a rounding away from it. Three units of walk is
    -- about a fiftieth of the stack, and it is all there is: this is why the
    -- overload FLOOR was left alone when the reach was sharpened, and why the
    -- limp came down 0.04 and not 0.10.
    assert(three - clamped >= 3, string.format(
        "only %d unit(s) of headroom over the clamp", three - clamped))

    -- The jog is the number the project lead was actually complaining about, so
    -- it is worth stating what the worst case does to it: still moving, still
    -- above a clamped walk, and nowhere near the running animation.
    local _, _, jog = M(base, C({ o = overloaded, l = limping, h = starving }, nil), false)
    assert(jog > clamped, "the jog collapsed into the clamp")
    assert(Omerta.HUD.GaitAnimation(jog) == Omerta.HUD.GAIT.WALK,
        "a man in this state should not be playing a running animation")

    -- AND THE HONEST PART, in two halves.
    --
    -- FIRST: at the very bottom of a limping stride the stack does touch the
    -- clamp, and it did before this pass too — the threshold is
    -- 0.25 / (0.75 x 0.55) = 0.606 of a limp, which sits above the middle of the
    -- gait whatever the limp is tuned to. It is one instant of one stride for a
    -- man who is starving, crippled AND overloaded, and buying it back would
    -- cost one of the three penalties its whole magnitude.
    local worstInstant = walkAt(overloaded, function() return L(0, mid, swing) end,
        starving)
    assert(worstInstant == clamped,
        "the bottom of the stride is no longer where this calibration thinks")

    -- SECOND: there is a FOURTH registrant, M19's own recovery penalty, at its
    -- worst the moment somebody stands up from being put down. All four at once
    -- lands on the clamp as well — 0.75 x 0.68 x 0.55 x 0.8 = 0.224 — and that
    -- is stated here rather than left to be discovered, because it is the case
    -- that decides there is no room for a fifth penalty at all. It was equally
    -- clamped before the limp was lowered (0.238 against the same 0.25), so it
    -- is a standing property of the stack and not something this pass spent.
    local recovering = function()
        return Omerta.Config.Get("injury.recovery_speed_scale")
    end
    assert(walkAt(overloaded, limping, starving, recovering) == clamped,
        "four penalties at once no longer reach the clamp — the budget moved")
end)

check("the camera bobs with the legs, and not at all while standing still", function()
    loadModules()
    local B = Omerta.Injury.LimpBob
    local L = Omerta.Injury.LIMP

    local dip, roll = B(0, 0)
    assert(dip == 0 and roll == 0, "a stationary character must not be rocked")
    dip, roll = B(0.5, 0)
    assert(dip == 0 and roll == 0, "at any phase, still means still")

    -- Intensity comes from ground speed, so it arrives and leaves with movement
    -- rather than switching on.
    local I = Omerta.Injury.LimpIntensity
    assert(I(0) == 0, "not moving, not bobbing")
    assert(I(L.FULL_AT) == 1 and I(L.FULL_AT * 10) == 1, "clamped at full")
    assert(I(L.FULL_AT * 0.5) == 0.5, "and eases in with the pace")

    -- ONE-SIDED, like the heartbeat: the head only ever drops from the resting
    -- eye line and comes back. A symmetric bob lifts the camera on the good leg
    -- and reads as a bounce — a man enjoying himself, not one dragging a foot.
    local lowest, highest = 0, 0
    for i = 0, 100 do
        local d = B(i / 100, 1)
        lowest = math.min(lowest, d)
        highest = math.max(highest, d)
    end
    assert(highest <= 0, "the bob rises above the resting eye line")
    assert(math.abs(lowest + L.DIP) < 1e-9, "the full dip is never reached")

    -- Deepest where the gait is slowest, level where it pushes off: the camera
    -- and the speed are the same event seen twice, which is what stops the
    -- speed change reading as network lag.
    local atSlow = B(0, 1)
    local atFast = B(L.PUSH_SHARE, 1)
    assert(atSlow < atFast, "the head must sink onto the bad leg, not off it")
    assert(math.abs(atFast) < 1e-9, "and be level at the push")

    -- Slight. The screen belongs to the player.
    assert(L.DIP <= 4, "that is a ride, not a hint")
    assert(L.ROLL <= 3, "likewise")

    -- Continuous around the wrap, or every stride ends with a snap.
    assert(math.abs(select(1, B(1, 1)) - select(1, B(0, 1))) < 1e-9)
    assert(math.abs(select(2, B(1, 1)) - select(2, B(0, 1))) < 1e-9)
end)
