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

check("carrying a body is heavy, and only while you are carrying one", function()
    loadModules()
    local C = Omerta.Injury.CarrySpeedMultiplier
    assert(C(false, 0.45) == 1, "empty handed")
    assert(C(true, 0.45) == 0.45, "loaded")
    assert(C(true, 0) > 0, "never a full stop — that reads as being stuck, not laden")
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
    local phase = Omerta.Injury.DeathPhase(0)
    assert(phase == "hold", "the camera must sit on the body first")
    assert(Omerta.Injury.DeathPhase(D.HOLD) == "rise", "then rise")
    local _, t = Omerta.Injury.DeathPhase(D.HOLD + D.RISE * 2)
    assert(t == 1, "and stop when it gets there, not keep climbing")
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

check("the screen blacks out before the words arrive", function()
    loadModules()
    local T = Omerta.Injury.DEATH_TIMING
    assert(Omerta.Injury.DeathFade(0) == 0, "not black at the moment of death")
    assert(Omerta.Injury.DeathFade(T.BLACK_AT) == 1, "black on schedule")
    assert(Omerta.Injury.DeathTextAlpha(T.BLACK_AT) == 0,
        "the words must not start before the screen is black")
    assert(Omerta.Injury.DeathTextAlpha(T.TEXT_AT + T.TEXT_OVER) == 1, "fully readable")
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
