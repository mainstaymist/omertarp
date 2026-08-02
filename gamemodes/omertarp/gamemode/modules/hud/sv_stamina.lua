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
--
-- There are THREE gaits: the walk, the fast walk on ALT, and the jog on sprint
-- (100 / 130 / 175). All three are decided in one place, Internal.MovementFor,
-- from one modifier stack, and all three are written to the player by
-- applySpeeds and by nothing else.
Omerta.Config.Define("movement.walk_speed", {
    type = "number", default = 100, min = 20, max = 600, scope = "server",
    description = "Normal movement speed. The engine default is 200.",
})
-- LOWERED FROM D-034's 200 (2026-08-02, project lead: "lower the runspeed
-- overall by a little bit"). 175 rather than a rounder number, argued against
-- the one figure that constrains it — the engine's 150:
--
--   * 150 is where the base gamemode stops playing the walk animation and
--     starts playing the run (sh_gait.lua). A jog has to stay clearly above it
--     or a running man stops LOOKING like one, and 175 keeps 25 units of that
--     clearance. Anything under about 160 would put a healthy character on the
--     wrong side of it the moment any modifier at all touched him.
--   * it leaves the fast walk somewhere to live. Walk 100, fast walk 130, jog
--     175: three gaits with real gaps, and the two the eye can actually read —
--     a change of pace at 100→130, a change of animation at 130→175 — fall
--     where they should.
--   * as a ratio it takes the jog from twice the walk to one and three
--     quarters. The stamina drain did not move, so the same thirteen seconds of
--     wind now buys 12.5% less ground: the "a chase is a decision" pressure
--     D-034 wanted, applied once more without touching the drain rate.
--
-- The WALK is deliberately NOT lowered. D-034's argument is about how long a
-- character takes to cross a street in front of somebody watching from a
-- window, and that is the walk — it is already the number that decision picked.
-- Slowing it further would tax every ordinary trip across a room to answer a
-- complaint that was about the run.
Omerta.Config.Define("movement.jog_speed", {
    type = "number", default = 175, min = 20, max = 1000, scope = "server",
    description = "Speed while holding sprint. The engine default is 400.",
})

-- THE THIRD GAIT (2026-08-02, project lead: holding ALT should be a fast walk
-- "without initiating the running animation").
--
-- Source only really has two gaits, and the honest way to get a third is to
-- notice that the engine has three SPEEDS — walk, slow-walk (+walk, bound to
-- ALT) and sprint — and only two ANIMATIONS, chosen purely by ground speed.
-- So the third gait is the slow-walk slot, set FASTER than the walk instead of
-- slower, at a speed the animation code still reads as a walk. Nothing has to
-- police the animation, and nothing on the client decides anything: the server
-- sets all three speeds and the engine's own movement code picks between them
-- from the key that is held.
--
-- 1.3 puts it at 130 against D-034's walk of 100 — a third quicker, which is
-- the difference between strolling and being somewhere to be, and 20 units
-- clear of the 150 line so that a slope or a shove cannot tip it into a run.
-- Held to that line by Omerta.HUD.FastWalkSpeed however high it is set.
Omerta.Config.Define("movement.fast_walk_scale", {
    type = "number", default = 1.3, min = 1, max = 3, scope = "server",
    description = "How much quicker than a walk holding ALT is, as a multiple " ..
        "of movement.walk_speed. Capped so the gait never reaches the speed " ..
        "at which the engine plays the running animation. 1 turns it off.",
})
Omerta.Config.Define("movement.jump_power", {
    type = "number", default = 200, min = 50, max = 500, scope = "server",
    description = "How hard a rested character jumps.",
})

-- Roughly thirteen seconds of flat sprint from full. It has come down twice
-- from 18 — five seconds, then eight — and both were still short of a chase
-- being a decision rather than an interruption. The recovery rate is
-- untouched: wind still takes longer to get back than to spend, which is
-- what keeps a sprint a cost at all.
Omerta.Config.Define("stamina.drain_per_second", {
    type = "number", default = 7.5, min = 1, max = 100, scope = "server",
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

-- Every movement value together, because they are decided together: they share
-- one modifier stack, and THE GAITS ARE ORDERED — walk <= fast walk <= jog, at
-- every factor, exhausted or not. That ordering is a rule and not an accident
-- of the defaults: a key that makes a character slower than not pressing it is
-- the one outcome a player reads as broken rather than as a penalty.
function Internal.MovementFor(base, factor, isExhausted)
    local walk = math.max(math.floor(base.walk * Internal.MIN_SPEED_FRACTION),
        math.floor(base.walk * factor))

    -- The fast walk takes the same modifier stack as everything else: holding
    -- ALT is a way of walking, not a way out of being starved, overloaded or
    -- lame. Floored at the walk so the clamp above propagates into it — a
    -- character pinned to the movement floor is pinned in every gait.
    local fastWalk = math.max(walk,
        math.floor((base.fastWalk or base.walk) * factor))

    -- Exhaustion does not slow the walk, it takes the JOG away: that is what
    -- makes it a limit on fleeing rather than a general punishment. It collapses
    -- to the fast walk rather than to the walk, because the fast walk costs no
    -- stamina and is not a run — a man who has blown his wind can still put his
    -- back into walking, and taking that away as well would mean ALT silently
    -- stops working at the exact moment a player is mashing keys.
    local jog = isExhausted and fastWalk
        or math.max(fastWalk, math.floor(base.jog * factor))

    local jump = Internal.JumpPower(base.jump, factor, isExhausted, base.exhaustedJumpScale)
    return walk, fastWalk, jog, jump
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
local lastSpeeds = {} -- sid -> { walk = , fastWalk = , jog = , jump = }

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
    local walk = Omerta.Config.Get("movement.walk_speed")
    return {
        walk = walk,
        -- Derived rather than configured directly, so the cap that keeps it out
        -- of the running animation is applied once, here, and an operator
        -- cannot reach past it by typing a bigger number.
        fastWalk = Omerta.HUD.FastWalkSpeed(walk,
            Omerta.Config.Get("movement.fast_walk_scale")),
        jog = Omerta.Config.Get("movement.jog_speed"),
        jump = Omerta.Config.Get("movement.jump_power"),
        exhaustedJumpScale = Omerta.Config.Get("stamina.exhausted_jump_scale"),
    }
end

local function applySpeeds(ply, sid, isExhausted)
    local walk, fastWalk, jog, jump = Internal.MovementFor(Internal.BaseMovement(),
        Internal.CombineModifiers(speedModifiers, ply), isExhausted)

    -- Three engine slots, three gaits, and the ENGINE picks between them from
    -- the key the player is holding — we never watch IN_WALK ourselves. That is
    -- what keeps the fast walk server-authoritative for free: a client can hold
    -- whatever it likes, and every speed it could possibly select was written
    -- by this function from this modifier stack.
    --
    -- SetRunSpeed is the engine's name for the sprint speed; the design calls it
    -- a jog, because at 175 that is what it is. SetSlowWalkSpeed is the +walk
    -- (ALT) slot, which the engine intends to be SLOWER than the walk and which
    -- we deliberately set faster — see movement.fast_walk_scale.
    local last = lastSpeeds[sid]
    if not last or last.walk ~= walk then ply:SetWalkSpeed(walk) end
    if not last or last.fastWalk ~= fastWalk then ply:SetSlowWalkSpeed(fastWalk) end
    if not last or last.jog ~= jog then ply:SetRunSpeed(jog) end
    if not last or last.jump ~= jump then ply:SetJumpPower(jump) end
    lastSpeeds[sid] = { walk = walk, fastWalk = fastWalk, jog = jog, jump = jump }
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

-- IN_SPEED, not speed: the fast walk (ALT) is deliberately outside this, so it
-- costs no wind and cannot exhaust anybody. That is what makes it a gait rather
-- than a cheaper sprint — the only thing stamina has ever governed is the jog.
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
    -- Two voices: Germania One is the game's face (the guide's Oswald/Archivo
    -- pairing was tried and rejected in the field), IBM Plex Mono is the small
    -- caps system voice.
    resource.AddFile("resource/fonts/GermaniaOne-Regular.ttf")
    resource.AddFile("resource/fonts/IBMPlexMono-Regular.ttf")
    resource.AddFile("resource/fonts/IBMPlexMono-Medium.ttf")

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
    -- silently reset them changed nothing. At 100/130/175 it would leave a
    -- respawned character walking at the default 200 — and, worse for the third
    -- gait, holding ALT at the engine's own SLOW walk — until a modifier
    -- happened to change. Drop the cache and re-apply.
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
