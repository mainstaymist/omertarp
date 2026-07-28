-- M12 telephony. The call state machine, the coin arithmetic that decides the
-- exact tick a call dies, and the routing table S1 derived — the three things
-- the whole milestone rests on, all pure.

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
    "gamemodes/omertarp/gamemode/modules/inventory/sh_currency.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_hunger.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_inventory.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_items.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_hunger.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_inventory.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_money.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sh_ladders.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sh_organizations.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sv_organizations.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sh_ledger.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sh_procurement.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sh_supplies.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sv_procurement.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sv_treasury.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sh_lines.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sh_phone.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sv_calls.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sv_phone.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sv_repository.lua",
}


local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

--------------------------------------------------------------------------------
suite("phone.numbers")
--------------------------------------------------------------------------------

check("a number is four digits and nothing else", function()
    loadModules()
    local V = Omerta.Phone.ValidNumber
    assert(V("1000") and V("5551") and V("9999"))
    assert(not V("999"), "too short")
    assert(not V("10000"), "too long")
    assert(not V("0999"), "below the range")
    assert(not V("12a4"), "not digits")
    assert(not V(""), "empty")
    assert(not V(nil), "nil")
    assert(not V(5551), "a number is a string on the wire, not an integer")
end)

-- Deterministic rather than random, so a line placed and replaced during setup
-- keeps the number staff just wrote on a piece of paper.
check("allocation takes the lowest free number", function()
    loadModules()
    local A = Omerta.Phone.Internal.AllocateNumber
    assert(A({}) == "1000")
    assert(A({ ["1000"] = true }) == "1001")
    assert(A({ ["1000"] = true, ["1001"] = true, ["1003"] = true }) == "1002",
        "a gap should be filled before moving on")
end)

--------------------------------------------------------------------------------
suite("phone.state_machine")
--------------------------------------------------------------------------------

check("a call walks the states it should", function()
    loadModules()
    local N = Omerta.Phone.Internal.NextState
    local S = Omerta.Phone.STATE
    assert(N(S.IDLE, "dial") == S.RINGING)
    assert(N(S.RINGING, "answer") == S.CONNECTED)
    assert(N(S.RINGING, "hangup") == S.ENDED)
    assert(N(S.RINGING, "timeout") == S.ENDED)
    assert(N(S.CONNECTED, "hangup") == S.ENDED)
    assert(N(S.CONNECTED, "no_coins") == S.ENDED)
end)

-- The interesting part of a call is the abnormal exits, which is why the
-- transitions are a table: the missing ones are visible.
check("and refuses the ones it should not", function()
    loadModules()
    local N = Omerta.Phone.Internal.NextState
    local S = Omerta.Phone.STATE
    assert(N(S.CONNECTED, "answer") == nil, "a call cannot be answered twice")
    assert(N(S.CONNECTED, "timeout") == nil, "a live call cannot time out")
    assert(N(S.IDLE, "answer") == nil, "there is nothing to answer")
    assert(N(S.ENDED, "hangup") == nil, "an ended call stays ended")
    assert(N(S.ENDED, "answer") == nil)
    assert(N("nonsense", "dial") == nil, "an unknown state goes nowhere")
end)

check("how a call ended is recorded from where it was", function()
    loadModules()
    local O = Omerta.Phone.Internal.OutcomeFor
    local S, OUT = Omerta.Phone.STATE, Omerta.Phone.OUTCOME
    assert(O(S.CONNECTED, "no_coins") == OUT.CUT_OFF, "the coins ran out")
    assert(O(S.RINGING, "timeout") == OUT.UNANSWERED, "nobody picked up")
    assert(O(S.RINGING, "hangup") == OUT.UNANSWERED, "the caller gave up")
    assert(O(S.CONNECTED, "hangup") == OUT.HUNG_UP, "somebody put it down")
end)

--------------------------------------------------------------------------------
suite("phone.coins")
--------------------------------------------------------------------------------

-- D-003 asks for quarters that run out mid-sentence, not a fee.
check("credit ticks down and floors at zero", function()
    loadModules()
    local S = Omerta.Phone.Internal.StepCredit
    assert(S(45, 1) == 44)
    assert(S(45, 0) == 45, "no time, no cost")
    assert(S(0.5, 1) == 0, "it floors rather than going negative")
    assert(S(0, 5) == 0)
    assert(S(nil, 1) == 0, "a call with no credit is not a crash")
end)

check("a call dies only when the credit AND the pocket are empty", function()
    loadModules()
    local C = Omerta.Phone.Internal.ShouldCutOff
    assert(not C(10, 0), "credit left, no coins — keep going")
    assert(not C(0, 1), "no credit, but a quarter to feed it — keep going")
    assert(not C(0, 4), "and several")
    assert(C(0, 0), "nothing left of either — mid-sentence")
    assert(C(0, nil), "an absent pocket counts as empty")
end)

--------------------------------------------------------------------------------
suite("phone.voice")
--------------------------------------------------------------------------------

-- S1 §2's routing table, which is the entire design in one function.
check("participants hear each other flat; everyone else defers to distance", function()
    loadModules()
    local D = Omerta.Phone.Internal.VoiceDecision
    local S = Omerta.Phone.STATE
    local call = { id = 7, state = S.CONNECTED }

    local canHear, is3D = D(call, call)
    assert(canHear == true, "participants must hear each other")
    assert(is3D == false, "and not positionally — it comes from the earpiece")

    -- A bystander is on no call, so nothing is decided and M7's distance rule
    -- applies. That is how they hear the near half and not the far one.
    assert(D(nil, call) == nil, "a bystander listening to a caller defers")
    assert(D(call, nil) == nil, "a caller listening to a bystander defers")
    assert(D(nil, nil) == nil, "two bystanders defer")
end)

check("separate calls never bleed together", function()
    loadModules()
    local D = Omerta.Phone.Internal.VoiceDecision
    local S = Omerta.Phone.STATE
    assert(D({ id = 7, state = S.CONNECTED }, { id = 8, state = S.CONNECTED }) == nil,
        "two calls in the same room are two calls")
end)

check("a ringing call carries no voice yet", function()
    loadModules()
    local D = Omerta.Phone.Internal.VoiceDecision
    local S = Omerta.Phone.STATE
    local ringing = { id = 7, state = S.RINGING }
    assert(D(ringing, ringing) == nil, "you cannot be heard before it is answered")
end)

--------------------------------------------------------------------------------
suite("phone.wire")
--------------------------------------------------------------------------------

check("the client is told its own call and nothing else", function()
    loadModules()
    Omerta.Module.FinishLoading()
    local registry = Omerta.Net.GetRegistry()

    for _, name in ipairs({ "phone.dial", "phone.action", "phone.say" }) do
        assert(registry[name] and registry[name].realm == "client_to_server",
            name .. " should be inbound")
    end
    for _, name in ipairs({ "phone.state", "phone.heard", "phone.ring" }) do
        assert(registry[name] and registry[name].realm == "server_to_client",
            name .. " should be outbound")
    end

    -- A ringing handset carries no number: whoever is calling has not said who
    -- they are, and the telephone does not know either.
    for _, field in ipairs(registry["phone.ring"].schema) do
        assert(field.type ~= "string", "a ring must not carry text")
    end
end)

check("the module declares its dependencies", function()
    loadModules()
    Omerta.Module.FinishLoading()
    local def = Omerta.Module.Get("phone")
    assert(def, "the phone module did not register")
    for _, dep in ipairs({ "chat", "inventory", "organizations", "treasury" }) do
        local found = false
        for _, d in ipairs(def.depends or {}) do
            if d == dep then found = true end
        end
        assert(found, "missing dependency on " .. dep)
    end
end)

--------------------------------------------------------------------------------
suite("phone.flow")
--------------------------------------------------------------------------------

check("migration 10 creates lines and call records, and no content column", function()
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

    local sawLines, sawCalls = false, false
    for _, s in ipairs(mock.log) do
        if s:find("CREATE TABLE IF NOT EXISTS omerta_phone_lines", 1, true) then sawLines = true end
        if s:find("CREATE TABLE IF NOT EXISTS omerta_phone_calls", 1, true) then sawCalls = true end
    end
    assert(sawLines, "phone_lines DDL missing")
    assert(sawCalls, "phone_calls DDL missing")

    -- There must be nowhere to put a recording. A table without the column is
    -- a stronger guarantee than a rule somebody has to remember.
    local def = Omerta.DB.Internal.GetTableDef("phone_calls")
    for _, col in ipairs(def.columns) do
        assert(col.name ~= "content" and col.name ~= "transcript" and col.name ~= "audio",
            "a call record must never have somewhere to store what was said")
    end
end)

check("a private line is something a family buys", function()
    loadModules()
    Omerta.Module.FinishLoading()
    local entry = Omerta.Procurement.Get("supply.private_line")
    assert(entry, "the private line was never registered as procurement")
    assert(entry.category == "communications")
    assert(entry.item == nil, "a line is a service, not an object in the safe")
    assert(type(entry.onPurchase) == "function", "and it has to do something")
end)
