-- Medicine, and everything else you can do to somebody on the floor.
--
-- Two steps, deliberately (D-037): a bandage STOPS THE BLEEDING and buys time;
-- it does not get anybody up. Only treatment reaches Recovering. That is what
-- makes both the stabilization item and M13's clinic worth having — one saves
-- a life in an alley, the other ends the situation.

Omerta.Injury = Omerta.Injury or {}
Omerta.Injury.Internal = Omerta.Injury.Internal or {}
local Internal = Omerta.Injury.Internal
local S = Omerta.Injury.STATE

local treatments = {}    -- id -> definition
local downedActions = {} -- id -> definition (M17's arrest, M20's confirm kill)
local inProgress = {}    -- actor SteamID64 -> { until, characterId, id }

Internal.Treatments = treatments
Internal.DownedActions = downedActions

--------------------------------------------------------------------------------
-- Registration seams
--------------------------------------------------------------------------------

local function validate(kind, id, def)
    if type(id) ~= "string" or not id:find("^[a-z0-9_%.]+$") then
        error(kind .. " id '" .. tostring(id) .. "' must be lowercase [a-z0-9_.]", 3)
    end
    if type(def) ~= "table" then error(kind .. " '" .. id .. "' needs a definition", 3) end
    if type(def.label) ~= "string" or def.label == "" then
        error(kind .. " '" .. id .. "' needs a label", 3)
    end
    if type(def.onComplete) ~= "function" then
        error(kind .. " '" .. id .. "' needs an onComplete", 3)
    end
    def.id = id
    def.duration = def.duration or 5
    def.order = def.order or 100
    return def
end

-- A way of making somebody better. M11's medical supplies and M13's clinic
-- register here; so will any future surgeon.
function Omerta.Injury.RegisterTreatment(id, def)
    if treatments[id] then error("treatment '" .. id .. "' registered twice", 2) end
    treatments[id] = validate("treatment", id, def)
    return treatments[id]
end

-- Anything else you can do to somebody at your mercy. M17's arrest and M20's
-- confirm kill are both this shape: a predicate, a duration, an effect.
-- Neither needs this module changed.
function Omerta.Injury.RegisterDownedAction(id, def)
    if downedActions[id] then error("downed action '" .. id .. "' registered twice", 2) end
    downedActions[id] = validate("downed action", id, def)
    return downedActions[id]
end

--------------------------------------------------------------------------------
-- Timed actions
--------------------------------------------------------------------------------
-- Everything done to a body takes time and can be interrupted, which is what
-- makes standing over someone a commitment rather than a click. Tech §18 will
-- require exactly this of M20's confirm kill; building it here means M20
-- inherits it instead of reinventing it.

function Internal.IsBusy(ply)
    local entry = inProgress[ply:SteamID64() or ""]
    return entry and entry.finishAt > CurTime()
end

function Internal.Begin(ply, def, characterId, cb)
    local sid = ply:SteamID64() or ""
    inProgress[sid] = {
        finishAt = CurTime() + def.duration,
        characterId = characterId,
        id = def.id,
        startPos = ply:GetPos(),
        cb = cb,
    }
    Omerta.Net.Send("injury.prompt", {
        text = def.label .. "…",
        seconds = math.min(255, math.floor(def.duration)),
    }, ply)

    -- The person it is being done to is told too. Being operated on without
    -- knowing it is happening is the one thing worse than being operated on.
    local target = Internal.PlayerFor(characterId)
    if IsValid(target) then
        Omerta.Net.Send("injury.prompt", {
            text = "Somebody is working on you.",
            seconds = math.min(255, math.floor(def.duration)),
        }, target)
    end
end

function Internal.Cancel(ply, reason)
    local sid = ply:SteamID64() or ""
    local entry = inProgress[sid]
    if not entry then return end
    inProgress[sid] = nil
    if entry.cb then entry.cb(false, reason or "interrupted") end
    if IsValid(ply) then
        Omerta.Net.Send("injury.prompt", { text = "", seconds = 0 }, ply)
    end
end

-- Called every tick from the module's timer.
function Internal.TickActions()
    local now = CurTime()
    for sid, entry in pairs(inProgress) do
        local ply = nil
        for _, candidate in ipairs(player.GetAll()) do
            if candidate:SteamID64() == sid then ply = candidate break end
        end

        if not IsValid(ply) then
            inProgress[sid] = nil
        elseif ply:GetPos():Distance(entry.startPos) > 64 then
            -- Walking away is how you interrupt yourself.
            Internal.Cancel(ply, "you moved away")
        elseif Omerta.Injury.IsPlayerDown(ply) then
            Internal.Cancel(ply, "you went down")
        elseif now >= entry.finishAt then
            inProgress[sid] = nil
            local def = treatments[entry.id] or downedActions[entry.id]
            if def then
                def.onComplete(ply, entry.characterId, function(ok, err)
                    if entry.cb then entry.cb(ok, err) end
                end)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Performing one
--------------------------------------------------------------------------------

-- cb(ok, err)
function Omerta.Injury.Perform(ply, characterId, actionId, cb)
    cb = cb or function() end
    if not IsValid(ply) then cb(false, "no actor") return end
    if Internal.IsBusy(ply) then cb(false, "you are busy") return end

    local def = treatments[actionId] or downedActions[actionId]
    if not def then cb(false, "there is nothing you can do") return end

    local body = Omerta.Injury.BodyOf(characterId)
    if not IsValid(body) then cb(false, "they are not there") return end

    -- Range is re-checked against the body's REAL position, not the client's
    -- claim — and a carried body is the first target in the game that moves
    -- while you are acting on it.
    if ply:GetPos():Distance(body:GetPos()) > (def.range or 96) then
        cb(false, "you are not close enough") return
    end

    if def.predicate then
        local ok, why = def.predicate(ply, characterId)
        if not ok then cb(false, why or "not now") return end
    end

    Internal.Begin(ply, def, characterId, cb)
end

-- What this player may do to this body, right now. Server-side truth; the
-- client is only ever offered what the server would actually accept.
function Internal.AvailableFor(ply, characterId)
    local out = {}
    for _, source in ipairs({ treatments, downedActions }) do
        for _, def in pairs(source) do
            local allowed = true
            if def.predicate then allowed = def.predicate(ply, characterId) == true end
            if allowed then out[#out + 1] = def end
        end
    end
    table.sort(out, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    return out
end

--------------------------------------------------------------------------------
-- The treatments M19 ships
--------------------------------------------------------------------------------

function Internal.RegisterTreatments()
    -- Stops the bleeding. Does not get anybody up.
    Omerta.Injury.RegisterTreatment("injury.stabilize", {
        label = "Stabilize", range = 72, duration = 6, order = 10,
        predicate = function(ply, characterId)
            local state = Omerta.Injury.GetByCharacter(characterId)
            if state ~= S.INCAPACITATED then return false, "they are not bleeding" end
            local actor = Omerta.Characters.Get(ply)
            if not actor then return false, "no character" end
            -- You cannot bandage yourself while unconscious, which is what
            -- keeps being down a situation rather than an inconvenience.
            if actor.id == characterId then return false, "you cannot reach" end
            if not Internal.HasSupplies(ply) then
                return false, "you have nothing to dress a wound with"
            end
            return true
        end,
        onComplete = function(ply, characterId, cb)
            Internal.ConsumeSupplies(ply, function()
                local actor = Omerta.Characters.Get(ply)
                Omerta.Injury.Set(characterId, S.STABILIZED, {
                    cause = "stabilized",
                    treatedBy = actor and actor.id or nil,
                    actorCharacterId = actor and actor.id or nil,
                    actorSteamId = ply:SteamID64(),
                }, cb)
                Omerta.Chat.Notice(ply, "The bleeding stops. They still need a doctor.")
            end)
        end,
    })

    -- The way back to your feet. Available at a clinic, because that is what a
    -- clinic is for — M13 registered the type and deferred the meaning here.
    Omerta.Injury.RegisterTreatment("injury.treat", {
        label = "Treat", range = 96, duration = 10, order = 20,
        predicate = function(ply, characterId)
            local state = Omerta.Injury.GetByCharacter(characterId)
            if not Omerta.Injury.IsDown(state) then return false, "they need no treatment" end
            local actor = Omerta.Characters.Get(ply)
            if not actor or actor.id == characterId then return false, "you cannot reach" end
            if not Internal.AtClinic(ply) then
                return false, "this needs a doctor's table"
            end
            return true
        end,
        onComplete = function(ply, characterId, cb)
            local actor = Omerta.Characters.Get(ply)
            Omerta.Injury.Set(characterId, S.RECOVERING, {
                cause = "treated",
                treatedBy = actor and actor.id or nil,
                actorCharacterId = actor and actor.id or nil,
                actorSteamId = ply:SteamID64(),
            }, cb)
        end,
    })
end

-- M11's procurement already lists medical supplies; M19 names the item it
-- expects and degrades gracefully until somebody registers one.
Internal.SUPPLY_ITEM = "medical.bandage"

-- The player goes straight into Get, which normalises a Player itself.
-- OwnerOf returns a type/id PAIR, not a descriptor — feeding its first return
-- back into Get read every pocket as empty (the same bug reloading had).
function Internal.HasSupplies(ply)
    if not (Omerta.Items and Omerta.Items.Get(Internal.SUPPLY_ITEM)) then return false end
    for _, row in ipairs(Omerta.Inventory.Get(ply) or {}) do
        if row.def_id == Internal.SUPPLY_ITEM then return true end
    end
    return false
end

function Internal.ConsumeSupplies(ply, cb)
    cb = cb or function() end
    for _, row in ipairs(Omerta.Inventory.Get(ply) or {}) do
        if row.def_id == Internal.SUPPLY_ITEM then
            Omerta.Inventory.Remove(row.id, 1, function() cb() end)
            return
        end
    end
    cb()
end

-- A clinic is a business with the medical service. M13's framework answers
-- this; M19 adds no concept of a building.
function Internal.AtClinic(ply)
    if not (Omerta.Business and Omerta.Business.Internal.AtCounter) then return false end
    local business = Omerta.Business.Internal.AtCounter(ply)
    if not business then return false end
    local typeDef = Omerta.Business.GetType(business.type_key)
    if not typeDef then return false end
    for _, service in ipairs(typeDef.services or {}) do
        if service == "medical" then return true end
    end
    return false
end
