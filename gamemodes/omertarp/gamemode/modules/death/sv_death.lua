-- The act, and everything that follows it.

local MODULE = Omerta.Module.Get("death")

Omerta.Death = Omerta.Death or {}
Omerta.Death.Internal = Omerta.Death.Internal or {}
local Internal = Omerta.Death.Internal

Omerta.Config.Define("death.confirm_seconds", {
    type = "number", default = 7, min = 1, max = 60, scope = "server",
    description = "How long finishing somebody takes. Long on purpose: Tech §18 " ..
        "wants the act deliberate and visible, and a long act performed in the " ..
        "open is both.",
})
Omerta.Config.Define("death.confirm_range", {
    type = "number", default = 72, min = 32, max = 200, scope = "server",
    description = "How close you must be to finish somebody.",
})

--------------------------------------------------------------------------------
-- The act
--------------------------------------------------------------------------------

-- Returns true, or false + reason. The interaction, the self-test and any
-- later caller all ask through here.
function Omerta.Death.CanConfirm(ply, characterId)
    if not (IsValid(ply) and characterId) then return false, "no" end
    local actor = Omerta.Characters.Get(ply)
    if not actor then return false, "no character" end

    return Omerta.Death.CanFinish(
        Omerta.Injury.GetByCharacter(characterId),
        Omerta.Injury.GetByCharacter(actor.id),
        actor.id, characterId)
end

function Internal.RegisterAction()
    -- Registered into M19's downed-action seam, which was built for exactly
    -- this and has been empty since. M19 needs no change; that is the test of
    -- whether its seam was the right shape.
    Omerta.Injury.RegisterDownedAction("death.confirm", {
        label = "Finish",
        range = Omerta.Config.Get("death.confirm_range"),
        duration = Omerta.Config.Get("death.confirm_seconds"),
        order = 90, -- last in the list; it is not a casual choice

        predicate = function(ply, characterId)
            return Omerta.Death.CanConfirm(ply, characterId) == true
        end,

        onComplete = function(ply, characterId, cb)
            local actor = Omerta.Characters.Get(ply)
            -- Re-asked at the moment of completion, not only at the start: a
            -- target treated and stood up during the cast must not die because
            -- somebody began the act while they were still down.
            local allowed, why = Omerta.Death.CanConfirm(ply, characterId)
            if not allowed then
                Omerta.Chat.Notice(ply, why or "not now")
                Internal.Audit("death.attempt_failed", ply, characterId, why)
                cb(false, why)
                return
            end

            Internal.Audit("death.confirmed", ply, characterId, "completed")
            Omerta.Injury.Die(characterId, Omerta.Death.CAUSE.CONFIRMED,
                actor and actor.id or nil, cb)
        end,
    })
end

-- Every ATTEMPT, not only every success.
--
-- Tech §18 asks for enough visibility to support rules enforcement, and the
-- question staff are actually asked is "he kept trying" — which a log of
-- completions cannot answer.
function Internal.Audit(what, ply, characterId, detail)
    local actor = IsValid(ply) and Omerta.Characters.Get(ply) or nil
    Omerta.Log.Audit(what, {
        actor = IsValid(ply) and ply:SteamID64() or "world",
        character_id = characterId,
        data = { by = actor and actor.id or nil, detail = detail },
    })
end

--------------------------------------------------------------------------------
-- The cascade
--------------------------------------------------------------------------------
-- Runs off M19's hook, so it is identical whichever way somebody died — the
-- bleed-out clock and the act above both funnel through Omerta.Injury.Die.
-- Two ways to die must not mean two cascades, because the second one written
-- is the one missing a step.

-- Tech §18's list, in order, with who owns each.
--
--   1. status dead ................ M19 (already done before this runs)
--   2. remove organization rank ... here, via M10
--   3. trigger succession ......... falls out of 2 (D-038 §4b)
--   4. create death event ......... here
--   5. preserve body/evidence ..... M19 (the corpse stays, D-038 §4c)
--   6. newspaper eligibility ...... the event's `public` type flag; M21 reads
--   7. archive references ......... M22 reads the same event
--   8. new-character flow ......... M4, released by M19's death screen
function Internal.Cascade(characterId, cause, actorCharacterId)
    -- 2 and 3. The seat empties and acting authority descends; a permanent
    -- leader has to be appointed by somebody. Failure here is logged and does
    -- not stop the rest — a character who was in nothing is the ordinary case.
    Omerta.Organizations.RecordDeath(characterId, function(ok, err)
        if ok then
            Omerta.Log.Info("death", "#%d removed from their institution", characterId)
        end
    end)

    -- 4, 6 and 7: one row, read by three milestones.
    local body = Omerta.Injury.BodyOf(characterId)
    Omerta.Events.Create({
        type = "death.confirmed",
        subject_character_id = characterId,
        actor_character_id = actorCharacterId,
        pos = IsValid(body) and body:GetPos() or nil,
        data = { cause = cause or "unknown" },
    }, function(id, err)
        if not id then
            Omerta.Log.Error("death", "a death went unrecorded: %s", tostring(err))
            return
        end
        Omerta.Log.Info("death", "#%d died (%s) — event #%d",
            characterId, tostring(cause), id)
    end)
end

-- For anything that needs a death without the interaction: staff tooling,
-- M18's outcomes, a scripted event. Goes through the same funnel, so the
-- cascade below runs identically.
function Omerta.Death.Cascade(characterId, cause, actorCharacterId, cb)
    return Omerta.Injury.Die(characterId, cause or Omerta.Death.CAUSE.STAFF,
        actorCharacterId, cb)
end

--------------------------------------------------------------------------------
-- Staff
--------------------------------------------------------------------------------

function Internal.RegisterCommands()
    concommand.Add("omerta_death_kill", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        local characterId = tonumber(args[1] or "")
        if not characterId then
            Omerta.Log.Error("death", "usage: omerta_death_kill <characterId>")
            return
        end
        Omerta.Death.Cascade(characterId, Omerta.Death.CAUSE.STAFF, nil,
            function(ok, err)
                if not ok then Omerta.Log.Error("death", "%s", tostring(err)) return end
                Omerta.Log.Info("death", "#%d killed by staff", characterId)
            end)
    end)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function MODULE:OnLoad()
    -- Registered at load rather than enable, so M21 and M22 can look the type
    -- up before either of them has been enabled.
    Omerta.Events.Register("death.confirmed", {
        name = "Killing",
        -- Eligible for a newspaper. NOT a decision that any particular death
        -- gets printed — M21 owns that, because it depends on who saw it.
        public = true,
    })
end

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    Internal.RegisterAction()
    Internal.RegisterCommands()

    hook.Add("Omerta.CharacterDied", "omerta.death.cascade",
        function(characterId, cause, actorCharacterId)
            Internal.Cascade(characterId, cause, actorCharacterId)
        end)
end
