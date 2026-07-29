-- M20 confirmed death and succession, plus the EventService it introduces
-- (D-038). The rulings are the thing that gets pinned hardest: a bandage buys
-- time and not immunity, the chair empties rather than seating anybody, and
-- what the dead were carrying stays where it fell.

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
    "gamemodes/omertarp/gamemode/modules/events/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/events/sh_events.lua",
    "gamemodes/omertarp/gamemode/modules/events/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/events/sv_events.lua",
    "gamemodes/omertarp/gamemode/modules/death/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/death/sh_death.lua",
    "gamemodes/omertarp/gamemode/modules/death/sv_death.lua",
}

local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

--------------------------------------------------------------------------------
suite("death.finishing")
--------------------------------------------------------------------------------

-- D-038 §4a, ruled as recommended and pinned here so a later change has to be
-- deliberate rather than accidental.
check("a bandage buys time, not immunity", function()
    loadModules()
    local F = Omerta.Death.CanFinish
    local S = Omerta.Injury.STATE
    assert(F(S.INCAPACITATED, S.HEALTHY, 1, 2), "a bleeding man can be finished")
    assert(F(S.STABILIZED, S.HEALTHY, 1, 2),
        "D-038 §4a: stabilizing stops the clock, it does not stop a knife")
end)

check("only the helpless can be finished", function()
    loadModules()
    local F = Omerta.Death.CanFinish
    local S = Omerta.Injury.STATE
    assert(not F(S.HEALTHY, S.HEALTHY, 1, 2), "somebody on their feet")
    assert(not F(S.CRITICAL, S.HEALTHY, 1, 2), "bleeding but still fighting")
    assert(not F(S.RECOVERING, S.HEALTHY, 1, 2), "back up")
end)

check("a corpse cannot be killed twice", function()
    loadModules()
    local F = Omerta.Death.CanFinish
    local S = Omerta.Injury.STATE
    local ok, why = F(S.DEAD, S.HEALTHY, 1, 2)
    assert(not ok, "the dead were finished again")
    assert(why and why:find("already"), "and the refusal should say why")
end)

-- Both directions of "you are in no state to do this".
check("the helpless cannot finish anybody, including themselves", function()
    loadModules()
    local F = Omerta.Death.CanFinish
    local S = Omerta.Injury.STATE
    assert(not F(S.INCAPACITATED, S.INCAPACITATED, 1, 2),
        "somebody on the floor reached over and finished somebody else")
    assert(not F(S.STABILIZED, S.DEAD, 1, 2), "a corpse finished somebody")
    assert(not F(S.INCAPACITATED, S.HEALTHY, 7, 7),
        "finished themselves — which is a route around the whole mechanic")
end)

check("the act is deliberate, which means slow", function()
    loadModules()
    -- Tech §18 asks for deliberate, logged, interruptible and visible. Only
    -- the first is a number, and a fast act is not a deliberate one.
    assert(Omerta.Config.Get("death.confirm_seconds") >= 3,
        "quick enough to be done in passing")
    assert(Omerta.Config.Get("death.confirm_range") <= 200,
        "it should require standing over them, not shouting across a street")
end)

check("every cause of death has a name rather than free text", function()
    loadModules()
    local C = Omerta.Death.CAUSE
    assert(C.CONFIRMED and C.BLED_OUT and C.STAFF)
    -- M21 picks a headline from this and M17 asks "was this a killing", so a
    -- typo'd string would be a story that never prints.
    assert(C.CONFIRMED ~= C.BLED_OUT, "the two ways to die must be distinguishable")
end)

--------------------------------------------------------------------------------
suite("death.events")
--------------------------------------------------------------------------------

check("an event type must be declared before it can be recorded", function()
    loadModules()
    local ok, why = Omerta.Events.Validate({ type = "nonsense.invented", season_id = 1 })
    assert(not ok, "an unregistered type was accepted")
    assert(why and why:find("unknown"), why)
end)

check("a killing is a registered, printable type", function()
    loadModules()
    Omerta.Module.FinishLoading()
    local def = Omerta.Events.GetType("death.confirmed")
    assert(def, "no death event type — nothing could ever print a killing")
    assert(def.public, "a killing must at least be ELIGIBLE for a newspaper")
end)

check("an event needs a season, because nothing outlives one", function()
    loadModules()
    Omerta.Module.FinishLoading()
    local ok = Omerta.Events.Validate({ type = "death.confirmed" })
    assert(not ok, "an event with no season was accepted")
    assert(Omerta.Events.Validate({ type = "death.confirmed", season_id = 1 }))
end)

-- Deliberately permissive past that: a fire has no subject and a promotion has
-- no position, and forcing placeholders into columns teaches later queries to
-- distrust them.
check("everything except type and season is optional", function()
    loadModules()
    Omerta.Module.FinishLoading()
    assert(Omerta.Events.Validate({ type = "death.confirmed", season_id = 1 }),
        "a bare event should be valid")
end)

expectError("a type cannot be registered twice", "registered twice", function()
    loadModules()
    Omerta.Events.Register("death.duplicate", { name = "One" })
    Omerta.Events.Register("death.duplicate", { name = "Two" })
end)

expectError("a type needs a readable name", "needs a name", function()
    loadModules()
    Omerta.Events.Register("death.nameless", {})
end)

check("migration 13 creates the event log with a place and a cursor", function()
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

    local saw = false
    for _, statement in ipairs(mock.log) do
        if statement:find("CREATE TABLE IF NOT EXISTS omerta_events", 1, true) then
            saw = true
        end
    end
    assert(saw, "events DDL missing")

    local def = Omerta.DB.Internal.GetTableDef("events")
    local columns = {}
    for _, col in ipairs(def.columns) do columns[col.name] = col end

    -- M15 needs to know where it happened, M21 needs to know whether it has
    -- been printed, and M22 needs both.
    assert(columns.pos_x, "an event with no place cannot be evidence")
    assert(columns.published_at, "no cursor for the newspaper")
    assert(columns.data and columns.data.type == "json", "no room for the details")
end)

--------------------------------------------------------------------------------
suite("death.succession")
--------------------------------------------------------------------------------

-- D-038 §4b: the chair empties, and M10's existing ladder does the rest.
check("dying is its own exit from a roster", function()
    loadModules()
    local status = Omerta.Organizations.MEMBER_STATUS
    assert(status.DIED, "no died status")
    assert(status.DIED ~= status.LEFT and status.DIED ~= status.EXPELLED,
        "a death must be distinguishable from walking out or being thrown out")
    assert(type(Omerta.Organizations.RecordDeath) == "function",
        "no death path — the chair would never empty")
end)

-- The behaviour M20 relies on and does not reimplement: with the seated leader
-- gone, authority descends to the most senior person who is actually present.
check("authority descends when the seated leader is not there", function()
    loadModules()
    local members = {
        { character_id = 1, rank = 6 },  -- the Don, now dead
        { character_id = 2, rank = 4 },  -- a Capo, standing right here
        { character_id = 3, rank = 2 },
    }
    local present = { [2] = true, [3] = true }
    local holder, isActing = Omerta.Organizations.Internal.ComputeActing(
        "family", members, 1, function(id) return present[id] == true end)

    assert(holder == 2, "the Capo should be holding it, got " .. tostring(holder))
    assert(isActing, "and holding it as ACTING, not as the seated leader")
end)

-- The consequence D-038 §4b names: an acting Capo runs the family but cannot
-- name a successor to it, so somebody with org.appoint has to be found.
check("an acting holder cannot appoint a successor", function()
    loadModules()
    local P = Omerta.Organizations.PERMISSIONS
    local top = Omerta.Organizations.TopRank("family")
    -- Acting sits one rung below the leader's, which is exactly what keeps
    -- APPOINT out of reach.
    assert(not Omerta.Organizations.Grants("family", top - 1, P.APPOINT),
        "an acting Capo could name the next Don — the vacuum has no shape")
    assert(Omerta.Organizations.Grants("family", top, P.APPOINT),
        "and the seated leader must be able to")
end)
