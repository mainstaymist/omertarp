-- Server-authoritative stamina. The client is told the value for display only;
-- the movement penalty is applied here, so a client that lies changes nothing.

local MODULE = Omerta.Module.Get("hud")

Omerta.Stamina = Omerta.Stamina or {}
Omerta.HUD = Omerta.HUD or {}
Omerta.HUD.Internal = Omerta.HUD.Internal or {}
local Internal = Omerta.HUD.Internal

Omerta.Config.Define("stamina.drain_per_second", {
    type = "number", default = 18, min = 1, max = 100, scope = "server",
    description = "Stamina points lost per second while sprinting (of 100).",
})
Omerta.Config.Define("stamina.regen_per_second", {
    type = "number", default = 11, min = 1, max = 100, scope = "server",
    description = "Stamina points recovered per second while not sprinting.",
})
Omerta.Config.Define("stamina.exhausted_below", {
    type = "number", default = 5, min = 0, max = 50, scope = "server",
    description = "Below this, the character cannot sprint until recovered.",
})
Omerta.Config.Define("stamina.recovered_above", {
    type = "number", default = 25, min = 1, max = 100, scope = "server",
    description = "Exhaustion lifts once stamina climbs back above this.",
})

--------------------------------------------------------------------------------
-- Pure maths (headless-tested)
--------------------------------------------------------------------------------

function Internal.StepStamina(current, sprinting, dt, drainRate, regenRate)
    if sprinting then
        return math.max(0, current - drainRate * dt)
    end
    return math.min(100, current + regenRate * dt)
end

-- Exhaustion is hysteretic on purpose: a single threshold would flicker the
-- sprint on and off every frame at the boundary.
function Internal.StepExhausted(wasExhausted, stamina, exhaustedBelow, recoveredAbove)
    if wasExhausted then return stamina < recoveredAbove end
    return stamina <= exhaustedBelow
end

-- Modifiers multiply rather than add, so two systems that each halve a value
-- quarter it instead of cancelling out. A modifier that errors or returns
-- nonsense is ignored rather than allowed to freeze the player in place.
function Internal.CombineModifiers(modifiers, ply)
    local product = 1
    for _, fn in pairs(modifiers or {}) do
        local ok, value = pcall(fn, ply)
        if ok and type(value) == "number" and value > 0 then
            product = product * value
        end
    end
    return product
end

--------------------------------------------------------------------------------
-- Runtime
--------------------------------------------------------------------------------

local stamina = {}   -- sid -> 0..100
local exhausted = {} -- sid -> bool
local lastSent = {}  -- sid -> last value networked
local lastSpeeds = {} -- sid -> { walk = , run = }

Internal.BASE_WALK_SPEED = 200
Internal.BASE_RUN_SPEED = 400

--------------------------------------------------------------------------------
-- Movement speed
--------------------------------------------------------------------------------
-- This module is the SINGLE owner of a character's movement speed. M9's hunger
-- was the second system to want a say, and two systems calling SetRunSpeed is
-- how one silently undoes the other — so anything that slows a character down
-- registers a multiplier here instead.

local speedModifiers = {}
local regenModifiers = {}

-- fn(ply) returns a multiplier; 1 means "no opinion".
function Omerta.Stamina.RegisterSpeedModifier(id, fn) speedModifiers[id] = fn end
function Omerta.Stamina.RegisterRegenModifier(id, fn) regenModifiers[id] = fn end

local function applySpeeds(ply, sid, isExhausted)
    local factor = Internal.CombineModifiers(speedModifiers, ply)
    local walk = math.max(50, math.floor(Internal.BASE_WALK_SPEED * factor))
    -- Exhaustion does not slow the walk, it takes the run away: that is what
    -- makes it a limit on fleeing rather than a general punishment.
    local run = isExhausted and walk
        or math.max(walk, math.floor(Internal.BASE_RUN_SPEED * factor))

    local last = lastSpeeds[sid]
    if not last or last.walk ~= walk then ply:SetWalkSpeed(walk) end
    if not last or last.run ~= run then ply:SetRunSpeed(run) end
    lastSpeeds[sid] = { walk = walk, run = run }
end

function Omerta.Stamina.Get(ply)
    if not IsValid(ply) then return 1 end
    return (stamina[ply:SteamID64() or ""] or 100) / 100
end

-- For later systems: carrying a body (M19), fleeing (M14), forced exertion.
function Omerta.Stamina.Drain(ply, amount)
    if not IsValid(ply) then return end
    local sid = ply:SteamID64() or ""
    stamina[sid] = math.max(0, (stamina[sid] or 100) - amount)
end

local function isSprinting(ply)
    return ply:KeyDown(IN_SPEED)
        and ply:OnGround()
        and ply:GetVelocity():Length2D() > 100
end

local function tick(dt)
    for _, ply in ipairs(player.GetAll()) do
        if Omerta.Characters.IsLoaded(ply) then
            local sid = ply:SteamID64() or ""
            local current = stamina[sid] or 100

            local sprinting = isSprinting(ply) and not exhausted[sid]
            current = Internal.StepStamina(current, sprinting, dt,
                Omerta.Config.Get("stamina.drain_per_second"),
                Omerta.Config.Get("stamina.regen_per_second")
                    * Internal.CombineModifiers(regenModifiers, ply))
            stamina[sid] = current

            local nowExhausted = Internal.StepExhausted(exhausted[sid] or false, current,
                Omerta.Config.Get("stamina.exhausted_below"),
                Omerta.Config.Get("stamina.recovered_above"))
            exhausted[sid] = nowExhausted

            -- Applied every tick, not only on the exhaustion transition: a
            -- modifier can change without stamina changing at all.
            applySpeeds(ply, sid, nowExhausted)

            -- Networked on meaningful change only: a per-tick stream would be
            -- pure noise for a value drawn as a fading bar.
            local rounded = math.floor(current + 0.5)
            if rounded ~= lastSent[sid] then
                lastSent[sid] = rounded
                Omerta.Net.Send("hud.stamina", { value = rounded }, ply)
            end
        end
    end
end

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    local interval = 0.25
    timer.Create("omerta.hud.stamina", interval, 0, function() tick(interval) end)

    hook.Add("PlayerDisconnected", "omerta.hud.stamina_cleanup", function(ply)
        local sid = ply:SteamID64() or ""
        stamina[sid], exhausted[sid], lastSent[sid], lastSpeeds[sid] = nil, nil, nil, nil
    end)

    -- A fresh character starts rested.
    hook.Add("Omerta.CharacterLoaded", "omerta.hud.stamina_reset", function(ply)
        local sid = ply:SteamID64() or ""
        stamina[sid], exhausted[sid], lastSent[sid], lastSpeeds[sid] = 100, false, nil, nil
        if IsValid(ply) then applySpeeds(ply, sid, false) end
    end)
end
