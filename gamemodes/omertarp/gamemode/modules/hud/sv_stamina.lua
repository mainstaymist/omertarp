-- Server-authoritative stamina. The client is told the value for display only;
-- the movement penalty is applied here, so a client that lies changes nothing.

local MODULE = Omerta.Module.Get("hud")

Omerta.Stamina = Omerta.Stamina or {}
Omerta.HUD = Omerta.HUD or {}
Omerta.HUD.Internal = Omerta.HUD.Internal or {}
local Internal = Omerta.HUD.Internal

-- Base movement (D-034). The engine's defaults are 200/400, which is far too
-- fast for the atmosphere: a character who crosses a street in two seconds
-- cannot be tailed, watched from a window, or approached — which quietly costs
-- the game the observation play the whole design is built around.
--
-- Configured rather than constant, so a server operator tunes the feel of the
-- city from data/omertarp/config/server.txt without touching code.
Omerta.Config.Define("movement.walk_speed", {
    type = "number", default = 100, min = 20, max = 600, scope = "server",
    description = "Normal movement speed. The engine default is 200.",
})
Omerta.Config.Define("movement.jog_speed", {
    type = "number", default = 200, min = 20, max = 1000, scope = "server",
    description = "Speed while holding sprint. The engine default is 400.",
})
Omerta.Config.Define("movement.jump_power", {
    type = "number", default = 200, min = 50, max = 500, scope = "server",
    description = "How hard a rested character jumps.",
})

-- 12 gives roughly eight seconds of flat sprint from full — 18 gave five and
-- change, which field-tested as running out before the corner you were
-- running for. The recovery rate is untouched: the wind still takes longer to
-- get back than to spend.
Omerta.Config.Define("stamina.drain_per_second", {
    type = "number", default = 12, min = 1, max = 100, scope = "server",
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
Omerta.Config.Define("stamina.jump_cost", {
    type = "number", default = 10, min = 0, max = 100, scope = "server",
    description = "Stamina spent on one jump (of 100).",
})
Omerta.Config.Define("stamina.exhausted_jump_scale", {
    type = "number", default = 0.55, min = 0, max = 1, scope = "server",
    description = "How high an exhausted character can jump, as a fraction.",
})

--------------------------------------------------------------------------------
-- Pure maths (headless-tested)
--------------------------------------------------------------------------------

-- `airborne` holds the value where it is: no drain, and crucially no RECOVERY.
--
-- Without it, the arc of a jump is free rest — you spend the cost on the way
-- up and earn it back before you land, so a bunny-hopper recovers faster than
-- somebody standing still. Catching your breath is something you do with your
-- feet on the ground.
function Internal.StepStamina(current, sprinting, dt, drainRate, regenRate, airborne)
    if airborne then return current end
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

-- Jumping is movement, so it is owned here rather than by whoever thinks of it
-- next. Someone out of breath does not vault a fence — but they are not pinned
-- to the floor either, so exhaustion scales the jump rather than removing it.
function Internal.JumpPower(base, factor, isExhausted, exhaustedScale)
    return math.max(1, math.floor(base * factor * (isExhausted and exhaustedScale or 1)))
end

-- The slowest a stack of modifiers may leave someone, as a FRACTION of the
-- configured walk speed rather than an absolute number.
--
-- This is load-bearing since D-034 halved the base. Against 200 the old
-- absolute floor of 50 bit at a combined modifier of 0.25; left absolute
-- against 100 it would bite at 0.5, silently halving the range available to
-- hunger, encumbrance and M19's injuries without anyone editing those systems.
-- Expressed as a fraction, the base moves and the calibration does not.
Internal.MIN_SPEED_FRACTION = 0.25

-- All three movement values together, because they are decided together: the
-- jog may never drop below the walk, and both share one modifier stack.
function Internal.MovementFor(base, factor, isExhausted)
    local walk = math.max(math.floor(base.walk * Internal.MIN_SPEED_FRACTION),
        math.floor(base.walk * factor))
    -- Exhaustion does not slow the walk, it takes the jog away: that is what
    -- makes it a limit on fleeing rather than a general punishment.
    local jog = isExhausted and walk or math.max(walk, math.floor(base.jog * factor))
    local jump = Internal.JumpPower(base.jump, factor, isExhausted, base.exhaustedJumpScale)
    return walk, jog, jump
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
local lastSpeeds = {} -- sid -> { walk = , jog = , jump = }

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

-- Read fresh each time rather than cached, so an operator editing the config
-- and reloading does not have to reconnect every player to see it.
function Internal.BaseMovement()
    return {
        walk = Omerta.Config.Get("movement.walk_speed"),
        jog = Omerta.Config.Get("movement.jog_speed"),
        jump = Omerta.Config.Get("movement.jump_power"),
        exhaustedJumpScale = Omerta.Config.Get("stamina.exhausted_jump_scale"),
    }
end

local function applySpeeds(ply, sid, isExhausted)
    local walk, jog, jump = Internal.MovementFor(Internal.BaseMovement(),
        Internal.CombineModifiers(speedModifiers, ply), isExhausted)

    -- SetRunSpeed is the engine's name for the sprint speed; the design calls
    -- it a jog, because at 200 that is what it is.
    local last = lastSpeeds[sid]
    if not last or last.walk ~= walk then ply:SetWalkSpeed(walk) end
    if not last or last.jog ~= jog then ply:SetRunSpeed(jog) end
    if not last or last.jump ~= jump then ply:SetJumpPower(jump) end
    lastSpeeds[sid] = { walk = walk, jog = jog, jump = jump }
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
                    * Internal.CombineModifiers(regenModifiers, ply),
                not ply:OnGround())
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

    -- The UI's typefaces travel with the gamemode: clients load any TTF under
    -- resource/fonts automatically once it is on disk, and AddFile is what
    -- puts it there. Owned by this module because the fonts are (cl_hud).
    --
    -- IBM Plex Sans is the Carbon standard's own face and carries the whole
    -- interface; Germania One is the expressive layer, and appears only on the
    -- wordmark and the death title.
    resource.AddFile("resource/fonts/IBMPlexSans-Regular.ttf")
    resource.AddFile("resource/fonts/IBMPlexSans-SemiBold.ttf")
    resource.AddFile("resource/fonts/GermaniaOne-Regular.ttf")

    -- The interface's own click. Owned here rather than by whichever module
    -- happened to need it first: it is a UI sound, and the hotbar, the menu
    -- and everything after them share it.
    resource.AddFile("sound/omertarp/ui/inventory-click.wav")

    local interval = 0.25
    timer.Create("omerta.hud.stamina", interval, 0, function() tick(interval) end)

    -- A jump costs stamina the moment it leaves the ground. KeyPress rather
    -- than the movement hook because it fires once per press; checking IN_JUMP
    -- every tick would bill somebody for holding the key down.
    hook.Add("KeyPress", "omerta.hud.stamina_jump", function(ply, key)
        if key ~= IN_JUMP then return end
        if not (ply:OnGround() and Omerta.Characters.IsLoaded(ply)) then return end
        Omerta.Stamina.Drain(ply, Omerta.Config.Get("stamina.jump_cost"))
    end)

    hook.Add("PlayerDisconnected", "omerta.hud.stamina_cleanup", function(ply)
        local sid = ply:SteamID64() or ""
        stamina[sid], exhausted[sid], lastSent[sid], lastSpeeds[sid] = nil, nil, nil, nil
    end)

    -- Spawning restores the engine's own player-class speeds, so the cache of
    -- "what we last applied" is stale the moment it happens. This was invisible
    -- until D-034: our numbers used to be the engine's numbers, so a spawn that
    -- silently reset them changed nothing. At 100/200 it would leave a
    -- respawned character walking at the default 200 until a modifier happened
    -- to change. Drop the cache and re-apply.
    hook.Add("PlayerSpawn", "omerta.hud.stamina_respeed", function(ply)
        local sid = ply:SteamID64() or ""
        lastSpeeds[sid] = nil
        if IsValid(ply) then applySpeeds(ply, sid, exhausted[sid] or false) end
    end)

    -- A fresh character starts rested.
    hook.Add("Omerta.CharacterLoaded", "omerta.hud.stamina_reset", function(ply)
        local sid = ply:SteamID64() or ""
        stamina[sid], exhausted[sid], lastSent[sid], lastSpeeds[sid] = 100, false, nil, nil
        if IsValid(ply) then applySpeeds(ply, sid, false) end
    end)
end
