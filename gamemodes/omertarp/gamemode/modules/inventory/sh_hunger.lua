-- Hunger (D-016, D-019). Deliberately slow and deliberately quiet: a full
-- stomach lasts hours of play, the value is read in the inventory rather than
-- worn on the screen, and the only thing that ever appears unprompted is the
-- starvation warning — because degrading a player for something they were
-- given no chance to notice is not consequence, it is a bug.
--
-- It NEVER kills. Permanent death is a deliberate act (GDD §19.2).
--
-- The maths is pure and lives here so the headless suite covers it.

Omerta.Hunger = Omerta.Hunger or {}

Omerta.Hunger.MAX = 100

-- Below this, appetite starts to cost you: recovery slows.
Omerta.Hunger.HUNGRY_BELOW = 40
-- Below this, it costs you visibly: you move slower, and you are told.
Omerta.Hunger.STARVING_BELOW = 15

Omerta.Hunger.STATE = {
    FED      = "fed",
    HUNGRY   = "hungry",
    STARVING = "starving",
}

function Omerta.Hunger.State(value)
    value = tonumber(value) or Omerta.Hunger.MAX
    if value < Omerta.Hunger.STARVING_BELOW then return Omerta.Hunger.STATE.STARVING end
    if value < Omerta.Hunger.HUNGRY_BELOW then return Omerta.Hunger.STATE.HUNGRY end
    return Omerta.Hunger.STATE.FED
end

-- One step of decay. Bounded at zero: starvation plateaus, it does not deepen
-- forever and it does not kill.
function Omerta.Hunger.Step(current, dt, perHour)
    current = tonumber(current) or Omerta.Hunger.MAX
    local drained = current - (perHour or 0) * (dt / 3600)
    return math.max(0, math.min(Omerta.Hunger.MAX, drained))
end

-- The pure half of feeding. The server's Omerta.Hunger.Feed(ply, amount) is
-- the API callers use; this is the arithmetic underneath it, kept separate so
-- the bounds are tested without a player to hand.
function Omerta.Hunger.Apply(current, amount)
    return math.max(0, math.min(Omerta.Hunger.MAX,
        (tonumber(current) or 0) + (tonumber(amount) or 0)))
end

-- Effects. Both are multipliers so they compose with anything else that ever
-- slows a character down, rather than each system assigning speeds directly.

function Omerta.Hunger.SpeedMultiplier(value)
    if Omerta.Hunger.State(value) == Omerta.Hunger.STATE.STARVING then return 0.75 end
    return 1
end

function Omerta.Hunger.RegenMultiplier(value)
    local state = Omerta.Hunger.State(value)
    if state == Omerta.Hunger.STATE.STARVING then return 0.4 end
    if state == Omerta.Hunger.STATE.HUNGRY then return 0.7 end
    return 1
end

-- Human-readable, for the inventory panel. No bar, no percentage: a character
-- knows whether they are hungry, not that they are at 37%.
function Omerta.Hunger.Describe(value)
    value = tonumber(value) or Omerta.Hunger.MAX
    if value < Omerta.Hunger.STARVING_BELOW then return "Starving" end
    if value < Omerta.Hunger.HUNGRY_BELOW then return "Hungry" end
    if value < 75 then return "Peckish" end
    return "Well fed"
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------
-- Private to its owner, following M8's stamina precedent exactly: a networked
-- variable would be readable by every client and would publish who is starving
-- — which is to say who has been hiding somewhere without food.

Omerta.Net.Register("inventory.hunger", {
    realm = "server_to_client",
    schema = { { name = "value", type = "uint", bits = 7 } }, -- 0..100
    handler = function(payload)
        hook.Run("Omerta.HungerUpdated", payload.value)
    end,
})
