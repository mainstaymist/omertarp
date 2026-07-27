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

--------------------------------------------------------------------------------
-- Runtime
--------------------------------------------------------------------------------

local stamina = {}   -- sid -> 0..100
local exhausted = {} -- sid -> bool
local lastSent = {}  -- sid -> last value networked

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
                Omerta.Config.Get("stamina.regen_per_second"))
            stamina[sid] = current

            local nowExhausted = Internal.StepExhausted(exhausted[sid] or false, current,
                Omerta.Config.Get("stamina.exhausted_below"),
                Omerta.Config.Get("stamina.recovered_above"))
            if nowExhausted ~= (exhausted[sid] or false) then
                exhausted[sid] = nowExhausted
                -- Taking the run speed away is what actually stops the sprint;
                -- the client's key is irrelevant.
                ply:SetRunSpeed(nowExhausted and ply:GetWalkSpeed() or 400)
            end

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
        stamina[sid], exhausted[sid], lastSent[sid] = nil, nil, nil
    end)

    -- A fresh character starts rested.
    hook.Add("Omerta.CharacterLoaded", "omerta.hud.stamina_reset", function(ply)
        local sid = ply:SteamID64() or ""
        stamina[sid], exhausted[sid], lastSent[sid] = 100, false, nil
        if IsValid(ply) then ply:SetRunSpeed(400) end
    end)
end
