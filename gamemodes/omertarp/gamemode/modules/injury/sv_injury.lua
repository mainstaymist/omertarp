-- The runtime: what state everyone is in, how damage moves them between
-- states, and the single funnel every death goes through.

local MODULE = Omerta.Module.Get("injury")

Omerta.Injury = Omerta.Injury or {}
Omerta.Injury.Internal = Omerta.Injury.Internal or {}
local Internal = Omerta.Injury.Internal
local S = Omerta.Injury.STATE

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

Omerta.Config.Define("injury.bleed_out_seconds", {
    type = "number", default = 300, min = 15, max = 3600, scope = "server",
    description = "How long an untreated incapacitated character lasts before " ..
        "dying (D-037). Long enough that rescue is real; raise it on a quiet server.",
})
Omerta.Config.Define("injury.stabilized_seconds", {
    type = "number", default = 900, min = 30, max = 7200, scope = "server",
    description = "How long a stabilized character lies there before coming round " ..
        "unaided. They are no longer dying, only helpless.",
})
Omerta.Config.Define("injury.recovering_seconds", {
    type = "number", default = 480, min = 10, max = 7200, scope = "server",
    description = "How long the after-effects of being put down last.",
})
Omerta.Config.Define("injury.recovery_speed_scale", {
    type = "number", default = 0.8, min = 0.25, max = 1, scope = "server",
    description = "Movement multiplier the moment you stand up; eases back to 1 " ..
        "across the recovery window (§4c).",
})
Omerta.Config.Define("injury.recovery_regen_scale", {
    type = "number", default = 0.55, min = 0.1, max = 1, scope = "server",
    description = "Stamina-recovery multiplier while recovering.",
})
Omerta.Config.Define("injury.drag_speed_scale", {
    type = "number", default = 0.55, min = 0.05, max = 1, scope = "server",
    description = "Movement multiplier while hauling a body. Moving one across " ..
        "a city should be a decision, not a detour.",
})
Omerta.Config.Define("injury.drag_drain_per_second", {
    type = "number", default = 6, min = 0, max = 50, scope = "server",
    description = "Stamina spent per second at full tension. Scaled by how hard " ..
        "you are actually pulling.",
})
Omerta.Config.Define("injury.drag_catchup", {
    type = "number", default = 1.35, min = 1.05, max = 2, scope = "server",
    description = "At full tension a body moves at this multiple of the hauler's " ..
        "own hauling speed. It must exceed 1: the excess is what lets a body " ..
        "that has fallen behind close the gap again, so the rope settles taut " ..
        "instead of ratcheting out to the break.",
})
Omerta.Config.Define("injury.search_seconds", {
    type = "number", default = 4, min = 0, max = 60, scope = "server",
    description = "How long going through a stranger's pockets takes the first " ..
        "time. Never again for the same body, by the same person.",
})
Omerta.Config.Define("injury.enabled", {
    type = "boolean", default = true, scope = "server",
    description = "Master switch. Off, lethal damage behaves as the engine intends " ..
        "— for a test server that does not want permadeath running.",
})

--------------------------------------------------------------------------------
-- Live state
--------------------------------------------------------------------------------
-- characterId -> { state, since, expiresAt, treatedBy, total }
-- `total` is the length of the current timed window, kept so the recovery
-- curve knows what fraction is left without re-reading config that may have
-- changed underneath it.

local states = {}
Internal.States = states

local damageFilters = {}

-- fn(ply, dmginfo) -> multiplier. Armour, a heavy coat, M14's weapon tuning.
function Omerta.Injury.RegisterDamageFilter(id, fn) damageFilters[id] = fn end

function Omerta.Injury.GetByCharacter(characterId)
    local entry = states[characterId]
    return entry and entry.state or S.HEALTHY
end

function Omerta.Injury.EntryFor(characterId) return states[characterId] end

function Omerta.Injury.Get(ply)
    local character = IsValid(ply) and Omerta.Characters.Get(ply)
    if not character then return S.HEALTHY end
    return Omerta.Injury.GetByCharacter(character.id)
end

function Omerta.Injury.IsPlayerDown(ply)
    return Omerta.Injury.IsDown(Omerta.Injury.Get(ply))
end

-- The player holding a given character, if they are connected. A body may
-- outlive its owner's connection, so every caller must cope with nil.
function Internal.PlayerFor(characterId)
    if not Omerta.InEngine then return nil end
    for _, ply in ipairs(player.GetAll()) do
        local character = Omerta.Characters.Get(ply)
        if character and character.id == characterId then return ply end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Networking a character their own condition
--------------------------------------------------------------------------------

function Internal.SendState(characterId)
    local ply = Internal.PlayerFor(characterId)
    if not IsValid(ply) then return end
    local entry = states[characterId]
    local state = entry and entry.state or S.HEALTHY
    local seconds = entry and Omerta.Injury.SecondsLeft(entry.expiresAt, os.time()) or nil

    local body = Omerta.Injury.BodyOf(characterId)
    Omerta.Net.Send("injury.body", {
        body = IsValid(body) and body:EntIndex() or 0,
    }, ply)

    Omerta.Net.Send("injury.state", {
        state = Omerta.Injury.STATE_INDEX[state] or 1,
        -- Clamped to the field, not to the truth: a long clock reads as "a
        -- while yet", which is all the character could judge anyway.
        seconds = math.min(4095, math.floor(seconds or 0)),
        -- The whole window, so a client reconnecting halfway through a bleed
        -- draws the right fraction instead of starting the bar over.
        total = math.min(4095, math.floor(entry and entry.total or 0)),
    }, ply)
end

--------------------------------------------------------------------------------
-- The one place state changes
--------------------------------------------------------------------------------

local function windowFor(state)
    if state == S.INCAPACITATED then return Omerta.Config.Get("injury.bleed_out_seconds") end
    if state == S.STABILIZED then return Omerta.Config.Get("injury.stabilized_seconds") end
    if state == S.RECOVERING then return Omerta.Config.Get("injury.recovering_seconds") end
    return nil
end

-- cb(ok, err). `opts` may carry cause, actorCharacterId, treatedBy, and
-- expiresAt (to RESUME a stored deadline rather than start a fresh one).
function Omerta.Injury.Set(characterId, state, opts, cb)
    cb = cb or function() end
    opts = opts or {}
    if not characterId then cb(false, "no character") return end
    if not Omerta.Injury.STATE_INDEX[state] then cb(false, "no such state") return end

    local entry = states[characterId]
    local from = entry and entry.state or S.HEALTHY

    if from == state then cb(true) return end
    if not Omerta.Injury.CanTransition(from, state) then
        -- Refused rather than applied. This is the guard that stops a future
        -- milestone quietly reviving a corpse.
        cb(false, "cannot go from " .. from .. " to " .. state)
        return
    end

    local now = os.time()
    local total = windowFor(state)
    local expiresAt = opts.expiresAt or (total and (now + total) or nil)
    if opts.expiresAt and total then total = math.max(1, opts.expiresAt - now) end

    states[characterId] = {
        state = state, since = now, expiresAt = expiresAt,
        treatedBy = opts.treatedBy, total = total,
    }

    local season = Omerta.Seasons.GetActive()
    Internal.Repo.SetState(characterId, state, now, expiresAt, opts.treatedBy, function(ok, err)
        if not ok then
            Omerta.Log.Error("injury", "could not persist state for #%d: %s",
                characterId, tostring(err))
        end
    end)
    if season then
        Internal.Repo.LogEvent({
            season_id = season.id,
            character_id = characterId,
            from_state = from,
            to_state = state,
            cause = opts.cause or "unknown",
            actor_character_id = opts.actorCharacterId or Omerta.DB.NULL,
            at = now,
        })
    end

    Omerta.Log.Audit("injury.state", {
        actor = opts.actorSteamId or "world",
        character_id = characterId,
        data = { from = from, to = state, cause = opts.cause },
    })

    Internal.OnStateChanged(characterId, from, state, opts)
    Internal.SendState(characterId)
    hook.Run("Omerta.InjuryChanged", characterId, from, state, opts)
    cb(true)
end

-- Everything physical that has to happen when a character crosses a boundary.
-- Kept apart from Set so the bookkeeping above stays readable.
function Internal.OnStateChanged(characterId, from, to, opts)
    if not Omerta.InEngine then return end

    local wasDown = Omerta.Injury.IsDown(from)
    local isDown = Omerta.Injury.IsDown(to)

    if isDown and not wasDown then
        Internal.PutDown(characterId, opts)
    elseif wasDown and not isDown and to ~= S.DEAD then
        Internal.StandUp(characterId)
    end

    if to == S.DEAD then Internal.OnDeath(characterId, opts) end
end

--------------------------------------------------------------------------------
-- The death funnel (D-037 §4d)
--------------------------------------------------------------------------------
-- EVERY death goes through here: the bleed-out timer today, M20's confirm-kill
-- interaction tomorrow. Two ways to die must not mean two cascades, because
-- the second one written will be the one missing a step.

-- cb(ok, err)
function Omerta.Injury.Die(characterId, cause, actorCharacterId, cb)
    return Omerta.Injury.Set(characterId, S.DEAD, {
        cause = cause or "unknown",
        actorCharacterId = actorCharacterId,
    }, cb)
end

function Internal.OnDeath(characterId, opts)
    -- The client is told BEFORE the status change, because SetStatus routes
    -- them straight to new-character creation and the death sequence needs to
    -- play first. The character is dead in the database either way; only the
    -- moment the form appears is being deferred, and M4's creation gate is
    -- what holds it.
    local ply = Internal.PlayerFor(characterId)
    local body = Omerta.Injury.BodyOf(characterId)
    if IsValid(ply) then
        local at = IsValid(body) and body:GetPos() or ply:GetPos()
        Omerta.Net.Send("injury.died", {
            body = IsValid(body) and body:EntIndex() or 0,
            x = math.floor(at.x), y = math.floor(at.y), z = math.floor(at.z),
        }, ply)
    end

    -- What M19 owns. Everything else listens.
    Omerta.Characters.SetStatus(characterId, Omerta.Characters.STATUS.DEAD,
        opts and opts.cause or "died", function(ok, err)
            if not ok then
                Omerta.Log.Error("injury", "could not mark #%d dead: %s",
                    characterId, tostring(err))
            end
        end)

    -- The body stays, AND stays a body.
    --
    -- The first version untagged the corpse here, which quietly made it inert:
    -- no dot, no tooltip, and nothing to take hold of. Hiding a body is the
    -- single most important thing anyone does with one — it is what M15's
    -- evidence and M20's funeral are both about — so a corpse keeps its tag,
    -- its entry and its row. What changes is the character's STATE, and every
    -- predicate reads that.
    if IsValid(body) then
        Internal.Repo.MoveBody(characterId, body:GetPos())
    end

    Omerta.Log.Audit("injury.died", {
        actor = opts and opts.actorSteamId or "world",
        character_id = characterId,
        data = { cause = opts and opts.cause, by = opts and opts.actorCharacterId },
    })

    -- M10 (rank removal, succession) can listen today; M21's newspaper and
    -- M22's archive listen when they exist. M20 owns the rest of Tech §18.
    hook.Run("Omerta.CharacterDied", characterId, opts and opts.cause,
        opts and opts.actorCharacterId)
end

-- The player has watched the end and pressed a key. Nothing about the
-- character changes here — it died when the clock ran out — this only releases
-- them into the new-character flow.
function Internal.AcknowledgeDeath(ply)
    if not IsValid(ply) then return end
    -- The hold is NOT lifted here, and that is the whole subtlety: the death
    -- already retired the character, and M4 gates a player who has nobody to
    -- be. Releasing them would hand control of a body back to somebody who is
    -- about to sit on the creation screen — walking, visible, playing as
    -- nobody. M4 lifts its own gate when a character loads; this only lets go
    -- of the camera.
    if Omerta.Characters.IsLoaded(ply) then Internal.ReleaseView(ply) end
    Omerta.Net.Send("injury.body", { body = 0 }, ply)
end

--------------------------------------------------------------------------------
-- Damage
--------------------------------------------------------------------------------

-- Pure enough to test: what the filters do to an amount.
function Internal.FilteredDamage(amount, ply, dmginfo)
    for _, fn in pairs(damageFilters) do
        local ok, multiplier = pcall(fn, ply, dmginfo)
        if ok and type(multiplier) == "number" and multiplier >= 0 then
            amount = amount * multiplier
        end
    end
    return amount
end

local function handleDamage(ply, dmginfo)
    if not Omerta.Config.Get("injury.enabled") then return end
    local character = Omerta.Characters.Get(ply)
    if not character then return end

    local state = Omerta.Injury.GetByCharacter(character.id)

    -- Already down: damage does not stack up more injury, because there is no
    -- worse state to reach that is not death, and death is a decision.
    if Omerta.Injury.IsIncapable(state) then
        dmginfo:SetDamage(0)
        return true
    end

    local amount = Internal.FilteredDamage(dmginfo:GetDamage(), ply, dmginfo)
    dmginfo:SetDamage(amount)

    local remaining = ply:Health() - amount
    if remaining > 0 then
        -- Survivable. Let the engine apply it; the post-hook reads the result.
        return
    end

    -- Lethal. This is the whole milestone: the engine must never see zero.
    dmginfo:SetDamage(0)
    ply:SetHealth(1)

    local attacker = dmginfo:GetAttacker()
    local attackerCharacter = IsValid(attacker) and attacker:IsPlayer()
        and Omerta.Characters.Get(attacker) or nil

    Omerta.Injury.Set(character.id, S.INCAPACITATED, {
        cause = Internal.CauseOf(dmginfo),
        actorCharacterId = attackerCharacter and attackerCharacter.id or nil,
        actorSteamId = IsValid(attacker) and attacker:IsPlayer()
            and attacker:SteamID64() or "world",
    })
    return true
end

function Internal.CauseOf(dmginfo)
    if not Omerta.InEngine then return "unknown" end
    if dmginfo:IsBulletDamage() then return "gunshot" end
    if dmginfo:IsDamageType(DMG_BURN) then return "fire" end
    if dmginfo:IsFallDamage() then return "fall" end
    if dmginfo:IsDamageType(DMG_CRUSH) then return "crush" end
    if dmginfo:IsDamageType(DMG_DROWN) then return "drowning" end
    if dmginfo:IsExplosionDamage() then return "explosion" end
    return "injury"
end

-- After the engine has applied survivable damage, reconcile the band.
local function reconcile(ply)
    local character = Omerta.Characters.Get(ply)
    if not character then return end
    local current = Omerta.Injury.GetByCharacter(character.id)
    local want = Omerta.Injury.StateForHealth(ply:Health(), ply:GetMaxHealth(), current)
    if want ~= current then
        Omerta.Injury.Set(character.id, want, { cause = "wounds" })
    end
end

--------------------------------------------------------------------------------
-- Timers
--------------------------------------------------------------------------------

function Internal.Tick()
    local now = os.time()
    for characterId, entry in pairs(states) do
        if Omerta.Injury.HasExpired(entry.expiresAt, now) then
            local to = Omerta.Injury.EXPIRES_TO[entry.state]
            if to then
                Omerta.Injury.Set(characterId, to, { cause = "untreated" })
            end
        end
    end

end

--------------------------------------------------------------------------------
-- Movement and stamina (§4c, through M8's seams)
--------------------------------------------------------------------------------

function Internal.RecoveryFactor(characterId, worst)
    local entry = states[characterId]
    if not entry or entry.state ~= S.RECOVERING then return 1 end
    local fraction = Omerta.Injury.RemainingFraction(entry.expiresAt, entry.total, os.time())
    return Omerta.Injury.RecoveryMultiplier(fraction, worst)
end

function Internal.RegisterModifiers()
    -- Tech §17: no ordinary movement while down. Enforced by holding the
    -- player entity (sv_bodies.lua) rather than by a speed of zero, because a
    -- speed of zero is something a client could argue with.
    -- Movement speed is M8's exclusive property; injury registers an opinion
    -- rather than setting speeds, exactly as M9's hunger does.
    Omerta.Stamina.RegisterSpeedModifier("injury", function(ply)
        local character = Omerta.Characters.Get(ply)
        if not character then return 1 end
        local state = Omerta.Injury.GetByCharacter(character.id)
        -- Down or dead: nothing to slow, movement is blocked outright.
        if Omerta.Injury.IsIncapable(state) then return 1 end

        local factor = Internal.RecoveryFactor(character.id,
            Omerta.Config.Get("injury.recovery_speed_scale"))
        return factor * Omerta.Injury.DragSpeedMultiplier(
            Omerta.Injury.DraggedBy(ply) ~= nil,
            Omerta.Config.Get("injury.drag_speed_scale"))
    end)

    Omerta.Stamina.RegisterRegenModifier("injury", function(ply)
        local character = Omerta.Characters.Get(ply)
        if not character then return 1 end
        return Internal.RecoveryFactor(character.id,
            Omerta.Config.Get("injury.recovery_regen_scale"))
    end)
end

--------------------------------------------------------------------------------
-- Communication while down (Tech §17: "limited local communication")
--------------------------------------------------------------------------------

function Internal.RegisterSpeechLimits()
    -- A man bleeding on the floor can manage a few words to whoever is
    -- kneeling over him. He cannot hold a conversation across the room, and he
    -- certainly cannot yell for help — which is what makes being found a
    -- matter of luck rather than volume.
    Omerta.Chat.RegisterChannelFilter("injury", function(ply, channelId)
        if not Omerta.Injury.IsPlayerDown(ply) then return end
        if channelId ~= "whisper" and channelId ~= "me" then
            return false, "You can barely speak."
        end
    end)

    Omerta.Chat.RegisterVoiceOverride("injury", function(listener, talker)
        if not Omerta.Injury.IsPlayerDown(talker) then return end
        -- Whisper range, and only that.
        local channel = Omerta.Chat.GetChannel("whisper")
        local range = channel and channel.range or 120
        if listener:GetPos():Distance(talker:GetPos()) > range then return false end
        return true
    end)
end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

function Internal.LoadStates()
    Internal.Repo.ListActive(function(rows, err)
        if err then
            Omerta.Log.Error("injury", "could not load injury states: %s", err)
            return
        end
        for _, row in ipairs(rows) do
            -- Restored, not restarted: expires_at is absolute, so a character
            -- who was thirty seconds from dying is still thirty seconds from
            -- dying after a restart.
            states[row.character_id] = {
                state = row.state,
                since = row.since,
                expiresAt = row.expires_at,
                treatedBy = row.treated_by_character_id,
                total = windowFor(row.state),
            }
        end
        if #rows > 0 then
            Omerta.Log.Info("injury", "%d character(s) still hurt from before the restart", #rows)
        end
        Internal.LoadBodies()
    end)
end

function MODULE:OnLoad()
    Omerta.DB.DefineTable("character_injury", {
        columns = {
            { name = "character_id",            type = "ref", null = false },
            { name = "state",                   type = "text", length = 16, null = false },
            { name = "since",                   type = "timestamp", null = false },
            -- Absolute, never a countdown. See sh_injury.lua.
            { name = "expires_at",              type = "timestamp" },
            { name = "treated_by_character_id", type = "ref" },
        },
        primary = { "character_id" },
        unique = { { "character_id" } },
        indexes = { { "state" } },
    })

    Omerta.DB.DefineTable("bodies", {
        columns = {
            { name = "id",           type = "id" },
            { name = "season_id",    type = "ref", null = false },
            { name = "character_id", type = "ref", null = false },
            { name = "map_name",     type = "text", length = 64, null = false },
            { name = "pos_x",        type = "int" },
            { name = "pos_y",        type = "int" },
            { name = "pos_z",        type = "int" },
            { name = "ang_y",        type = "int" },
            { name = "created_at",   type = "timestamp", null = false },
        },
        unique = { { "character_id" } },
        indexes = { { "season_id", "map_name" } },
    })

    Omerta.DB.DefineTable("injury_events", {
        columns = {
            { name = "id",                 type = "id" },
            { name = "season_id",          type = "ref", null = false },
            { name = "character_id",       type = "ref", null = false },
            { name = "from_state",         type = "text", length = 16, null = false },
            { name = "to_state",           type = "text", length = 16, null = false },
            { name = "cause",              type = "text", length = 32, null = false },
            { name = "actor_character_id", type = "ref" },
            { name = "at",                 type = "timestamp", null = false },
        },
        indexes = { { "character_id", "at" }, { "season_id", "at" } },
    })

    Omerta.DB.AddMigration(12, "injury states, bodies and injury events", function(m)
        m:CreateTable("character_injury")
        m:CreateTable("bodies")
        m:CreateTable("injury_events")
    end)
end

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    -- Mounting makes a file available to the SERVER; only this sends it to
    -- clients. Registered here, in the milestone that actually plays them,
    -- exactly as content/README.md asks.
    resource.AddFile("sound/omertarp/trombone-crescendo.wav")
    resource.AddFile("sound/omertarp/death-piano.wav")
    resource.AddFile("sound/omertarp/confirm.wav")
    resource.AddFile("sound/omertarp/ui/searching-rustle.wav")

    Internal.RegisterModifiers()
    Internal.RegisterSpeechLimits()
    Internal.RegisterInteractions()
    Internal.RegisterTreatments()
    Internal.RegisterSearch()
    Internal.RegisterSearchAction()
    Internal.RegisterBodyCleanup()
    Internal.RegisterIdentity()
    Internal.RegisterDisconnect()
    Internal.RegisterCommands()

    Omerta.Organizations.WhenReady(function() Internal.LoadStates() end)

    timer.Create("omerta.injury.tick", 1, 0, Internal.Tick)

    -- The rope is physics, so it runs every frame rather than every second: a
    -- body hauled at one update per second lurches.
    hook.Add("Think", "omerta.injury.drag", function()
        Internal.TickDrags()
        Internal.TickActions()
    end)

    -- Damage interception. EntityTakeDamage is the only hook that can stop the
    -- engine reaching zero health, which is the entire point of the milestone.
    hook.Add("EntityTakeDamage", "omerta.injury.damage", function(target, dmginfo)
        if not (IsValid(target) and target:IsPlayer()) then return end
        return handleDamage(target, dmginfo)
    end)

    hook.Add("PostEntityTakeDamage", "omerta.injury.reconcile", function(target, _, took)
        if not (took and IsValid(target) and target:IsPlayer()) then return end
        reconcile(target)
    end)

    -- A loaded character must never reach PlayerDeath. If one does, something
    -- bypassed the damage path and the state machine has silently failed for
    -- that case — so it is logged loudly rather than tidied away.
    hook.Add("PlayerDeath", "omerta.injury.should_not_happen", function(ply)
        if not Omerta.Config.Get("injury.enabled") then return end
        if Omerta.Characters.IsLoaded(ply) then
            Omerta.Log.Error("injury",
                "a loaded character reached PlayerDeath — damage bypassed the state machine")
        end
    end)

    hook.Add("Omerta.CharacterLoaded", "omerta.injury.restore", function(ply)
        local character = Omerta.Characters.Get(ply)
        if not character then return end
        Internal.SendState(character.id)
        -- Somebody reconnecting to a body already on the floor goes straight
        -- back into it, rather than standing up somewhere else.
        if Omerta.Injury.IsDown(Omerta.Injury.GetByCharacter(character.id)) then
            Internal.PutDown(character.id, { reconnected = true })
        end
    end)
end
