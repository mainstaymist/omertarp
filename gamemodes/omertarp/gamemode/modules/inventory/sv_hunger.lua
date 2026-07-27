-- Hunger, server side (D-016, D-019).
--
-- The value lives here, decays here, and is persisted here. The client is told
-- its own number so the inventory can print a word for it, and nothing else.

Omerta.Hunger = Omerta.Hunger or {}
Omerta.Inventory = Omerta.Inventory or {}
Omerta.Inventory.Internal = Omerta.Inventory.Internal or {}
local Internal = Omerta.Inventory.Internal

Omerta.Config.Define("hunger.decay_per_hour", {
    type = "number", default = 20, min = 1, max = 100, scope = "server",
    description = "Hunger points lost per hour of play (of 100).",
})
Omerta.Config.Define("hunger.save_interval", {
    type = "number", default = 120, min = 30, max = 900, scope = "server",
    description = "Seconds between writing hunger back to the database.",
})

-- steamid64 -> { value = , characterId = , dirty = , sent = }
local needs = {}

local function stateFor(ply)
    if not (Omerta.InEngine and IsValid(ply)) then return nil end
    return needs[ply:SteamID64() or ""]
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- 0..1, matching Omerta.Stamina.Get so the two read alike at call sites.
function Omerta.Hunger.Get(ply)
    local state = stateFor(ply)
    if not state then return 1 end
    return state.value / Omerta.Hunger.MAX
end

function Omerta.Hunger.GetRaw(ply)
    local state = stateFor(ply)
    return state and state.value or Omerta.Hunger.MAX
end

function Omerta.Hunger.Feed(ply, amount)
    local state = stateFor(ply)
    if not state then return end
    state.value = Omerta.Hunger.Apply(state.value, amount)
    state.dirty = true
    Internal.PushHunger(ply, state)
end

-- Staff and later systems (a starvation event, a prison ration).
function Omerta.Hunger.Set(ply, value)
    local state = stateFor(ply)
    if not state then return end
    state.value = Omerta.Hunger.Apply(0, value)
    state.dirty = true
    Internal.PushHunger(ply, state)
end

--------------------------------------------------------------------------------
-- Schema and persistence
--------------------------------------------------------------------------------

function Internal.DefineNeedsSchema()
    Omerta.DB.DefineTable("character_needs", {
        columns = {
            { name = "character_id", type = "ref", null = false },
            { name = "hunger",       type = "int", null = false, default = 100 },
            { name = "updated_at",   type = "timestamp", null = false },
        },
        primary = { "character_id" },
    })
end

function Internal.LoadNeeds(ply, character)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    local sid = ply:SteamID64() or ""
    needs[sid] = { value = Omerta.Hunger.MAX, characterId = character.id, dirty = false }

    Internal.Repo.GetNeeds(character.id, function(row, err)
        if err then
            Omerta.Log.Error("hunger", "load failed for character #%d: %s", character.id, err)
            return
        end
        local state = needs[sid]
        if not state or state.characterId ~= character.id then return end
        -- A character with no row has never eaten anything: they start full
        -- rather than starving, which is what "just arrived in the city" means.
        state.value = row and row.hunger or Omerta.Hunger.MAX
        Internal.PushHunger(ply, state)
    end)
end

local function save(sid, state, cb)
    if not (state and state.characterId) then if cb then cb(true) end return end
    state.dirty = false
    Internal.Repo.SaveNeeds(state.characterId, math.floor(state.value + 0.5), os.time(), cb)
end

function Internal.UnloadNeeds(ply)
    local sid = ply:SteamID64() or ""
    local state = needs[sid]
    if state then save(sid, state) end
    needs[sid] = nil
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------

function Internal.PushHunger(ply, state)
    if not (Omerta.InEngine and IsValid(ply) and state) then return end
    local rounded = math.floor(state.value + 0.5)
    if rounded == state.sent then return end
    state.sent = rounded
    Omerta.Net.Send("inventory.hunger", { value = rounded }, ply)
end

--------------------------------------------------------------------------------
-- Runtime
--------------------------------------------------------------------------------

local function tick(dt)
    local perHour = Omerta.Config.Get("hunger.decay_per_hour")
    for _, ply in ipairs(player.GetAll()) do
        local state = needs[ply:SteamID64() or ""]
        if state and Omerta.Characters.IsLoaded(ply) then
            local before = Omerta.Hunger.State(state.value)
            state.value = Omerta.Hunger.Step(state.value, dt, perHour)
            state.dirty = true

            -- The one thing hunger ever says unprompted (§4c). It fires on the
            -- transition only: a permanent warning would be the permanent HUD
            -- element the whole design exists to avoid.
            local after = Omerta.Hunger.State(state.value)
            if after ~= before and after == Omerta.Hunger.STATE.STARVING then
                Omerta.Chat.Notice(ply, "You are starving. You need to eat something.")
            end

            Internal.PushHunger(ply, state)
        end
    end
end

local function saveAll()
    for sid, state in pairs(needs) do
        if state.dirty then save(sid, state) end
    end
end

function Internal.StartHunger()
    if not Omerta.InEngine then return end

    local interval = 10
    timer.Create("omerta.inventory.hunger", interval, 0, function() tick(interval) end)
    timer.Create("omerta.inventory.hunger_save",
        Omerta.Config.Get("hunger.save_interval"), 0, saveAll)

    -- Hunger's effects reach the player through M8's stamina modifiers rather
    -- than by setting speeds directly. Two systems writing a player's run speed
    -- is how one silently undoes the other.
    Omerta.Stamina.RegisterSpeedModifier("hunger", function(ply)
        return Omerta.Hunger.SpeedMultiplier(Omerta.Hunger.GetRaw(ply))
    end)
    Omerta.Stamina.RegisterRegenModifier("hunger", function(ply)
        return Omerta.Hunger.RegenMultiplier(Omerta.Hunger.GetRaw(ply))
    end)

    hook.Add("ShutDown", "omerta.inventory.hunger_save", saveAll)
end
