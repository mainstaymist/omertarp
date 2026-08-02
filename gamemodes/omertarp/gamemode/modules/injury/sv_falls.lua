-- Falling, breaking a leg, and walking on it afterwards. The runtime.
--
-- Three things live here and they are one feature:
--
--   1. A fall is worth what it was: how far you fell decides the damage, and
--      past a certain height it decides that you are on the floor whatever your
--      health was.
--   2. A fall past a lower height breaks a leg, which is a CONDITION that
--      outlives the fall — it persists across a reconnect and a restart, and it
--      is cured by a doctor or by time.
--   3. A broken leg limps, through M8's speed seam, and the client draws the
--      camera to match.
--
-- HOW THIS REACHES INCAPACITATION, because D-037 is binding on the point. Low
-- and medium falls are ORDINARY DAMAGE: they go into ply:TakeDamageInfo as
-- DMG_FALL, land in M19's own EntityTakeDamage handler, pass through every
-- registered damage filter, and reach Omerta.Injury.Set through the same funnel
-- a bullet does. A hurt man killed by a two-storey drop goes down by exactly
-- the path a hurt man shot in the chest goes down by, and the injury_events row
-- says "fall" because Internal.CauseOf reads the damage type.
--
-- The HIGH band is the one deliberate exception and it is stated rather than
-- arrived at: at that height the character is put down by calling the same
-- terminal Set(INCAPACITATED) the damage handler itself calls, with the same
-- clamp of health to 1, instead of by handing the arithmetic a number and
-- hoping. The reason is the damage filters. RegisterDamageFilter exists for
-- "armour, a heavy coat, M14's weapon tuning", and a multiplier of 0.5 on a
-- fall from six storeys would quietly delete the project lead's requirement
-- that "there will be a point where a fall will incapacitate you even if you
-- were full health". A coat may soften a fall. It may not catch one.

-- This file deliberately defines NO module lifecycle method. `MODULE` is one
-- shared table per module and files are included alphabetically, so a second
-- `function MODULE:OnEnable()` anywhere in modules/injury would replace
-- sv_injury.lua's rather than add to it — the accident that once froze every
-- player on the server, and now a lint. Everything below is exposed as a
-- function on Internal and called from the one lifecycle that exists.

Omerta.Injury = Omerta.Injury or {}
Omerta.Injury.Internal = Omerta.Injury.Internal or {}
local Internal = Omerta.Injury.Internal
local S = Omerta.Injury.STATE

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------
-- Every number a designer would want to move is here, not buried in a function.
-- The heights are in world units, where a Half-Life 2 player is 72 tall and a
-- storey on most maps is about 128 — so these are distances somebody can pace
-- out in the map rather than magic constants.
--
-- HOW THE DAMAGE WAS CHOSEN, against M19's own bands (below 70% of 100 is
-- injured, below 35% critical, 0 is down) and in the style the arsenal set:
--
--   safe 150 — a full storey is free. You can step off a loading dock, a bar,
--     a low roof or a stairwell landing and keep walking. This is a long way
--     under the ENGINE's own safe-fall speed of 580 units/second (about 280
--     units of height), which is exactly why this module cannot use
--     GAMEMODE:GetFallDamage: the engine never calls it for anything gentler
--     than that, so half of the range the lead asked for would be unreachable.
--     OnPlayerHitGround sees every landing, so the threshold is genuinely ours.
--
--   break 340 / 34 damage — two and a half storeys, and 34 is one Model 10
--     round. A full-health character who takes this fall lands on 66, which is
--     inside M19's injured band, and gets up limping. That is the intended
--     shape of the medium fall: it costs you real health AND it costs you the
--     leg, and neither alone would have been a consequence worth avoiding.
--     Deliberately NOT tuned so the low band tops out at exactly 30 (which
--     leaves 70, the injured boundary itself): the arsenal's rule about the
--     M1911 applies here word for word — an outcome that depends on which way a
--     comparison rounds is an outcome that gets reported as a bug. The crossing
--     into "hurt" happens around 323 units, seventeen short of the break, so
--     the two thresholds are visibly separate events.
--
--   down 700 / 100 damage — five and a half storeys. The damage reaches a full
--     health bar exactly where the band does, so the arithmetic and the rule
--     agree instead of merely coexisting; the suite asserts that they do. The
--     rule is what actually fires (see the header), and the agreement is what
--     stops the last stretch of the medium band feeling like a different game
--     from the first stretch of the high one.
--
--   Between the knots the damage climbs continuously — 0.179 points per unit
--     below the break, 0.183 above it — so the whole thing is very nearly one
--     straight line, which is what "these falls are still linear" asks for. A
--     fall that crosses into critical (66 damage, 34 left) happens at about
--     515 units, in the middle of the medium band and nowhere near either edge.

Omerta.Config.Define("injury.fall_safe_height", {
    type = "number", default = 150, min = 0, max = 4000, scope = "server",
    description = "Falls shorter than this, in world units, cost nothing at " ..
        "all. A storey is roughly 128.",
})
Omerta.Config.Define("injury.fall_break_height", {
    type = "number", default = 340, min = 1, max = 6000, scope = "server",
    description = "Fall this far and the leg breaks. Below it a fall only " ..
        "takes health.",
})
Omerta.Config.Define("injury.fall_down_height", {
    type = "number", default = 700, min = 2, max = 10000, scope = "server",
    description = "Fall this far and you are incapacitated whatever your " ..
        "health was, and no armour or damage filter changes that.",
})
Omerta.Config.Define("injury.fall_break_damage", {
    type = "number", default = 34, min = 0, max = 200, scope = "server",
    description = "Health lost by a fall exactly at the break height. The " ..
        "damage ramps to this from nothing at the safe height, and on from " ..
        "here to fall_down_damage.",
})
Omerta.Config.Define("injury.fall_down_damage", {
    type = "number", default = 100, min = 1, max = 500, scope = "server",
    description = "Health lost by a fall exactly at the down height. Keep it " ..
        "at or above a full health bar so the curve and the band agree.",
})

Omerta.Config.Define("injury.leg_break_seconds", {
    type = "number", default = 600, min = 30, max = 7200, scope = "server",
    description = "How long a broken leg takes to knit unaided. A doctor at a " ..
        "clinic sets it immediately; otherwise you walk it off.",
})
Omerta.Config.Define("injury.leg_break_volume", {
    type = "number", default = 0.35, min = 0, max = 1, scope = "server",
    description = "How loudly the bone breaks. The files are loud on purpose " ..
        "and are played quietly rather than re-encoded, so raising this is a " ..
        "config change and not an asset pass.",
})

Omerta.Config.Define("injury.limp_speed_scale", {
    type = "number", default = 0.72, min = 0.3, max = 1, scope = "server",
    description = "The middle of a limping gait, as a movement multiplier. " ..
        "The stride swings either side of it (injury.limp_swing).",
})
Omerta.Config.Define("injury.limp_swing", {
    type = "number", default = 0.22, min = 0, max = 0.6, scope = "server",
    description = "How uneven the limp is: the multiplier runs from " ..
        "scale-swing on the bad leg to scale+swing on the good one, once per " ..
        "stride. Zero is a flat penalty and no limp at all.",
})

--------------------------------------------------------------------------------
-- Schema
--------------------------------------------------------------------------------
-- A SEPARATE TABLE RATHER THAN A COLUMN ON character_injury, which is what M19
-- §9 sketched. Two reasons, and the second is the one that decided it:
--
--   * Tech §17's impairments are a LIST. A table keyed (character, impairment)
--     takes the second and the third for free; a column takes a migration each.
--   * The migration runner offers exactly two primitives, CreateTable and
--     Query, and only CreateTable knows the difference between the dialects.
--     An ALTER TABLE would have to hardcode a column type that means the same
--     thing on MySQL and SQLite, and would then have to be kept out of the way
--     of a fresh database that had already created the column from the table
--     definition. D-008 makes MySQL the backend of record and the suite
--     exercises both; a new table is the one shape that is honestly identical
--     on each.
--
-- The deadline is ABSOLUTE, like every other clock in this module, so a restart
-- resumes a broken leg instead of healing it. A restart that mended bones would
-- make "wait for the nightly restart" an orthopaedic procedure.
--
-- Called from MODULE:OnLoad in sv_injury.lua. A module may define each
-- lifecycle method exactly once and sv_injury.lua already owns both, so this
-- file exposes functions and that file calls them (lint.module_lifecycle).
function Internal.DefineFallSchema()
    Omerta.DB.DefineTable("character_impairments", {
        columns = {
            { name = "character_id", type = "ref", null = false },
            { name = "impairment",   type = "text", length = 24, null = false },
            { name = "since",        type = "timestamp", null = false },
            -- NULL would mean "until somebody fixes it". Nothing writes that
            -- today; the column allows it so a permanent impairment needs no
            -- migration when Tech §17 arrives.
            { name = "expires_at",   type = "timestamp" },
        },
        primary = { "character_id", "impairment" },
        unique = { { "character_id", "impairment" } },
        indexes = { { "expires_at" } },
    })

    Omerta.DB.AddMigration(14, "lasting impairments (a broken leg)", function(m)
        m:CreateTable("character_impairments")
    end)
end

--------------------------------------------------------------------------------
-- Live state
--------------------------------------------------------------------------------

local legs = {}  -- characterId -> { since, expiresAt }
local gait = {}  -- SteamID64 -> units walked, for the gait phase
Internal.Legs = legs

function Omerta.Injury.HasBrokenLeg(characterId)
    return characterId ~= nil and legs[characterId] ~= nil
end

function Omerta.Injury.LegBrokenUntil(characterId)
    local entry = characterId and legs[characterId]
    return entry and entry.expiresAt or nil
end

function Omerta.Injury.HasBrokenLegPlayer(ply)
    local character = IsValid(ply) and Omerta.Characters.Get(ply)
    return character ~= nil and Omerta.Injury.HasBrokenLeg(character.id)
end

-- Their own condition, and nobody else's. Same rule injury.state follows.
function Internal.SendLeg(characterId)
    local ply = Internal.PlayerFor(characterId)
    if not IsValid(ply) then return end
    local entry = legs[characterId]
    local seconds = entry
        and (Omerta.Injury.SecondsLeft(entry.expiresAt, os.time()) or 0) or 0
    Omerta.Net.Send("injury.leg", {
        broken = entry ~= nil,
        seconds = math.min(65535, math.floor(seconds)),
    }, ply)
end

--------------------------------------------------------------------------------
-- Breaking and mending
--------------------------------------------------------------------------------

function Internal.PlayLegBreak(ply)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    local volume = Omerta.Config.Get("injury.leg_break_volume")
    if volume <= 0 then return end
    -- Three variations, one at random, so the same fall twice does not sound
    -- like the same event twice.
    local path = Omerta.Injury.LegBreakSound(
        math.random(1, Omerta.Injury.LEG_BREAK_SOUNDS))
    -- Emitted from the person it happened to, at conversation range rather than
    -- across the street: a bone going is something the people standing over you
    -- hear, and it is the only thing in this feature a bystander learns without
    -- being told — which is the right amount, and the same amount the ragdoll
    -- hitting the floor already gives away.
    ply:EmitSound(path, 68, 100, volume, CHAN_BODY)
end

-- cb(ok, err). `opts` may carry cause, actorCharacterId, seconds, expiresAt.
function Omerta.Injury.BreakLeg(characterId, opts, cb)
    cb = cb or function() end
    opts = opts or {}
    if not characterId then cb(false, "no character") return end

    local state = Omerta.Injury.GetByCharacter(characterId)
    if state == S.DEAD then cb(false, "they are past caring") return end

    local now = os.time()
    local window = tonumber(opts.seconds)
        or Omerta.Config.Get("injury.leg_break_seconds")
    local expiresAt = tonumber(opts.expiresAt) or (now + window)

    local existing = legs[characterId]
    if existing then
        -- Already broken. The clock takes the LATER of the two deadlines and
        -- the leg is not broken a second time: two breaks are one broken leg,
        -- and a fresh injury must never shorten the one already healing. No
        -- second snap either — the same leg does not announce itself twice.
        existing.expiresAt = math.max(existing.expiresAt or 0, expiresAt)
        Internal.Repo.SetImpairment(characterId, Omerta.Injury.IMPAIRMENT.LEG,
            existing.since, existing.expiresAt)
        Internal.SendLeg(characterId)
        cb(true)
        return
    end

    legs[characterId] = { since = now, expiresAt = expiresAt }
    Internal.Repo.SetImpairment(characterId, Omerta.Injury.IMPAIRMENT.LEG,
        now, expiresAt, function(ok, err)
            if not ok then
                Omerta.Log.Error("injury", "could not persist a broken leg for #%d: %s",
                    characterId, tostring(err))
            end
        end)

    -- The same append-only record every other thing that happens to a body
    -- goes into, in the vocabulary the drag already uses (from "dragged" to
    -- "released"). M15 will want to know somebody was walking badly on the
    -- night in question.
    local season = Omerta.Seasons.GetActive()
    if season then
        Internal.Repo.LogEvent({
            season_id = season.id,
            character_id = characterId,
            from_state = Omerta.Injury.IMPAIRMENT.LEG,
            to_state = "broken",
            cause = opts.cause or "unknown",
            actor_character_id = opts.actorCharacterId or Omerta.DB.NULL,
            at = now,
        })
    end
    Omerta.Log.Audit("injury.leg_broken", {
        actor = opts.actorSteamId or "world",
        character_id = characterId,
        data = { cause = opts.cause, until_at = expiresAt },
    })

    local ply = Internal.PlayerFor(characterId)
    Internal.PlayLegBreak(ply)
    if IsValid(ply) then
        Omerta.Chat.Notice(ply, "Something gives in your leg.")
    end
    Internal.SendLeg(characterId)
    hook.Run("Omerta.InjuryLegBroken", characterId, opts.cause)
    cb(true)
end

-- cb(ok, err)
function Omerta.Injury.HealLeg(characterId, reason, cb)
    cb = cb or function() end
    if not (characterId and legs[characterId]) then cb(false, "nothing to set") return end

    legs[characterId] = nil
    Internal.Repo.ClearImpairment(characterId, Omerta.Injury.IMPAIRMENT.LEG)

    local season = Omerta.Seasons.GetActive()
    if season then
        Internal.Repo.LogEvent({
            season_id = season.id,
            character_id = characterId,
            from_state = Omerta.Injury.IMPAIRMENT.LEG,
            to_state = "mended",
            cause = reason or "unknown",
            actor_character_id = Omerta.DB.NULL,
            at = os.time(),
        })
    end

    local ply = Internal.PlayerFor(characterId)
    if IsValid(ply) then
        gait[ply:SteamID64() or ""] = nil
        Omerta.Chat.Notice(ply, reason == "treated"
            and "The doctor sets your leg."
            or "Your leg feels like your own again.")
    end
    Internal.SendLeg(characterId)
    hook.Run("Omerta.InjuryLegMended", characterId, reason)
    cb(true)
end

-- Driven from Internal.Tick, once a second, alongside every other deadline in
-- the module. Removing the current key inside pairs() is defined behaviour.
function Internal.TickLegs()
    local now = os.time()
    for characterId, entry in pairs(legs) do
        if Omerta.Injury.HasExpired(entry.expiresAt, now) then
            Omerta.Injury.HealLeg(characterId, "knitted")
        end
    end
end

--------------------------------------------------------------------------------
-- The fall itself
--------------------------------------------------------------------------------

function Internal.FallCurve()
    return Omerta.Injury.FallCurve(
        Omerta.Config.Get("injury.fall_safe_height"),
        Omerta.Config.Get("injury.fall_break_height"),
        Omerta.Config.Get("injury.fall_down_height"),
        Omerta.Config.Get("injury.fall_break_damage"),
        Omerta.Config.Get("injury.fall_down_damage"))
end

-- Read fresh rather than cached: sv_gravity is a live cvar and a map or an
-- operator may move it, and a curve calibrated in height has to convert with
-- the gravity the fall actually happened under.
function Internal.Gravity()
    if not Omerta.InEngine then return Omerta.Injury.FALL_GRAVITY end
    local cvar = GetConVar("sv_gravity")
    local value = cvar and cvar:GetFloat() or 0
    if value <= 0 then return Omerta.Injury.FALL_GRAVITY end
    return value
end

function Internal.HandleLanding(ply, inWater, onFloater, speed)
    if not Omerta.Config.Get("injury.enabled") then return end
    -- Water breaks a fall and so does whatever a floater is. Both are the
    -- engine telling us the landing was not on ground.
    if inWater or onFloater then return end

    local character = Omerta.Characters.Get(ply)
    if not character then return end

    -- Already at somebody's mercy: the state machine has no worse place to put
    -- them that is not death, and death is a decision. Same rule the damage
    -- handler applies one line into its own body.
    if Omerta.Injury.IsIncapable(Omerta.Injury.GetByCharacter(character.id)) then
        return
    end

    local curve = Internal.FallCurve()
    local height = Omerta.Injury.FallHeight(speed, Internal.Gravity())
    local band = Omerta.Injury.FallBand(height, curve)
    local BAND = Omerta.Injury.FALL_BAND
    if band == BAND.NONE then return end

    -- The leg first, so somebody put down by the same fall wakes up with it —
    -- which is the point of a condition outliving a state.
    if band ~= BAND.LOW then
        Omerta.Injury.BreakLeg(character.id, { cause = "fall" })
    end

    if band == BAND.HIGH then
        -- The terminal path, taken directly. See this file's header for why the
        -- guarantee is not left to arithmetic. The health clamp is the damage
        -- handler's own: the engine must never see zero.
        ply:SetHealth(1)
        Omerta.Injury.Set(character.id, S.INCAPACITATED, {
            cause = "fall",
            actorSteamId = "world",
        })
        return
    end

    local amount = Omerta.Injury.FallDamage(height, curve)
    if amount <= 0 then return end

    -- Ordinary damage, through the ordinary door. DMG_FALL is what makes
    -- Internal.CauseOf write "fall" into injury_events, and routing it through
    -- TakeDamageInfo is what lets a filter soften it and lets a man who was
    -- already hurt be put down by it — both through code that already exists.
    local dmg = DamageInfo()
    dmg:SetDamage(amount)
    dmg:SetDamageType(DMG_FALL)
    dmg:SetAttacker(game.GetWorld())
    dmg:SetInflictor(game.GetWorld())
    ply:TakeDamageInfo(dmg)
end

--------------------------------------------------------------------------------
-- The limp
--------------------------------------------------------------------------------

function Internal.GaitDistance(ply)
    if not IsValid(ply) then return 0 end
    return gait[ply:SteamID64() or ""] or 0
end

-- Called every frame from the module's Think, because a gait is physics: a
-- phase advanced four times a second from four samples of a velocity would
-- measure a different walk from the one being walked.
function Internal.TickGait()
    if not Omerta.InEngine then return end
    -- Nobody in the city is limping, which is the usual case: this runs every
    -- frame, so the usual case has to cost one table lookup and not a walk of
    -- the player list. Stale entries are cleared where a leg stops being broken
    -- (HealLeg, death, disconnect) rather than by sweeping for them here.
    if not next(legs) then return end
    local dt = FrameTime()
    if not dt or dt <= 0 then return end

    for _, ply in ipairs(player.GetAll()) do
        -- Airborne, the phase HOLDS. The arc of a jump is not a step, and this
        -- is the same rule — and the same reasoning — that stopped a
        -- bunny-hopper resting mid-jump in §14d.
        if Omerta.Injury.HasBrokenLegPlayer(ply) and ply:OnGround() then
            local sid = ply:SteamID64() or ""
            local moved = ply:GetVelocity():Length2D() * dt
            -- Reduced modulo the stride as it accumulates, not once at the end.
            -- The number therefore never grows, so a float cannot lose
            -- precision over a session and there is no wrap point at which the
            -- gait would skip — which an arbitrary large modulus would have
            -- given it, once every few hours of walking, for nothing.
            gait[sid] = ((gait[sid] or 0) + moved) % Omerta.Injury.LIMP.STRIDE
        end
    end
end

-- A SECOND modifier under its own id, not folded into the existing "injury"
-- one. The registry is keyed by id and multiplies what it finds, so two
-- registrations compose (a man recovering from a shooting AND limping is both)
-- where a second registration under the same id would silently replace the
-- recovery penalty — the same class of accident MODULE:OnEnable has caused
-- twice on this project.
function Internal.RegisterLimp()
    Omerta.Stamina.RegisterSpeedModifier("injury.leg", function(ply)
        local character = Omerta.Characters.Get(ply)
        if not character then return 1 end
        if not Omerta.Injury.HasBrokenLeg(character.id) then return 1 end
        -- Down or dead: movement is blocked outright by holding the player
        -- entity, so a multiplier here would be arguing with a frozen man.
        if Omerta.Injury.IsIncapable(Omerta.Injury.GetByCharacter(character.id)) then
            return 1
        end
        return Omerta.Injury.LimpSpeedMultiplier(
            Omerta.Injury.LimpPhase(Internal.GaitDistance(ply)),
            Omerta.Config.Get("injury.limp_speed_scale"),
            Omerta.Config.Get("injury.limp_swing"))
    end)
end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

function Internal.LoadImpairments()
    Internal.Repo.ListImpairments(function(rows, err)
        if err then
            Omerta.Log.Error("injury", "could not load impairments: %s", err)
            return
        end
        local now, live = os.time(), 0
        for _, row in ipairs(rows) do
            if row.impairment == Omerta.Injury.IMPAIRMENT.LEG then
                local dead = Omerta.Injury.GetByCharacter(row.character_id) == S.DEAD
                if dead or Omerta.Injury.HasExpired(row.expires_at, now) then
                    -- It knitted while the server was down, or the character it
                    -- belonged to did not need it any more. Absolute deadlines
                    -- cut both ways and that is the point of them.
                    Internal.Repo.ClearImpairment(row.character_id, row.impairment)
                else
                    legs[row.character_id] = {
                        since = row.since, expiresAt = row.expires_at,
                    }
                    live = live + 1
                end
            end
        end
        if live > 0 then
            Omerta.Log.Info("injury", "%d broken leg(s) still knitting", live)
        end
    end)
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------
-- Called from MODULE:OnEnable in sv_injury.lua, for the lifecycle reason given
-- at DefineFallSchema.

function Internal.RegisterFalls()
    if not Omerta.InEngine then return end

    for index = 1, Omerta.Injury.LEG_BREAK_SOUNDS do
        util.PrecacheSound(Omerta.Injury.LegBreakSound(index))
    end

    Internal.RegisterLimp()

    -- EVERY landing, not only the ones the engine thinks are worth damage.
    -- CBasePlayer only reaches GetFallDamage above its own hardcoded safe-fall
    -- speed of 580 units/second — about 280 units of height — so a threshold
    -- set below that through GetFallDamage would be a config key that silently
    -- did nothing. OnPlayerHitGround is called for the lot.
    hook.Add("OnPlayerHitGround", "omerta.injury.fall",
        function(ply, inWater, onFloater, speed)
            if not (IsValid(ply) and ply:IsPlayer()) then return end
            Internal.HandleLanding(ply, inWater, onFloater, speed)
        end)

    -- And the engine's own fall damage is turned off, so the two cannot both
    -- bill the same landing. Belt and braces on top of the hook above rather
    -- than an alternative to it: whichever way this engine orders the two
    -- calls, exactly one number reaches the player and it is ours. With the
    -- master switch off this returns nothing and the engine goes back to
    -- behaving as it intends, which is what that switch promises.
    hook.Add("GetFallDamage", "omerta.injury.no_engine_fall", function()
        if not Omerta.Config.Get("injury.enabled") then return end
        return 0
    end)

    hook.Add("PlayerDisconnected", "omerta.injury.gait_cleanup", function(ply)
        -- The gait, not the leg. Their body stays on the floor and their leg
        -- stays broken; only the phase they happened to be mid-stride at is
        -- forgotten, and it is measured from movement so it rebuilds itself.
        gait[ply:SteamID64() or ""] = nil
    end)

    -- A condition does not outlive the person carrying it. Cleared directly
    -- rather than through HealLeg, which would announce a mending to somebody
    -- who has just died and write a "mended" row over the top of the death.
    -- D-012 settles the rest: what comes next is a different person, and the
    -- row is keyed to a character.
    hook.Add("Omerta.CharacterDied", "omerta.injury.leg_dies_with_them",
        function(characterId)
            local ply = Internal.PlayerFor(characterId)
            if IsValid(ply) then gait[ply:SteamID64() or ""] = nil end
            if not legs[characterId] then return end
            legs[characterId] = nil
            Internal.Repo.ClearImpairment(characterId, Omerta.Injury.IMPAIRMENT.LEG)
        end)

    Internal.RegisterLegCommand()
end

function Internal.RegisterLegCommand()
    concommand.Add("omerta_injury_leg", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end

        local action = string.lower(args[1] or "break")
        local characterId = tonumber(args[2] or "")
        if not characterId then
            local character = IsValid(caller) and Omerta.Characters.Get(caller)
            if not character then
                Omerta.Log.Error("injury", "usage: omerta_injury_leg <break|heal> [characterId]")
                return
            end
            characterId = character.id
        end

        if action == "heal" or action == "set" then
            Omerta.Injury.HealLeg(characterId, "staff", function(ok, err)
                Omerta.Log.Info("injury", "#%d leg: %s", characterId,
                    ok and "mended" or tostring(err))
            end)
            return
        end
        if action ~= "break" then
            Omerta.Log.Error("injury", "usage: omerta_injury_leg <break|heal> [characterId]")
            return
        end

        Omerta.Injury.BreakLeg(characterId, {
            cause = "staff",
            actorSteamId = IsValid(caller) and caller:SteamID64() or "console",
        }, function(ok, err)
            Omerta.Log.Info("injury", "#%d leg: %s", characterId,
                ok and "broken" or tostring(err))
        end)
    end)
end
