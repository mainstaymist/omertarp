-- Spawning him, asking him, and killing him.
--
-- The engine half of the reaction model, and it decides nothing: every question
-- it asks is answered by the pure functions in sh_reactions.lua. What lives here
-- is the entity, the poses, the flee point and the consequences of a death.

Omerta.Crime = Omerta.Crime or {}
Omerta.Crime.Internal = Omerta.Crime.Internal or {}
local Internal = Omerta.Crime.Internal
local R = Omerta.Crime.REACTION
local S = Omerta.Crime.STATE

local clerks = {}  -- business id -> entity

Internal.Clerks = clerks

--------------------------------------------------------------------------------
-- Placing one
--------------------------------------------------------------------------------

function Omerta.Crime.ClerkFor(businessId)
    local ent = clerks[businessId]
    return IsValid(ent) and ent or nil
end

function Omerta.Crime.SpawnClerk(business, pos, ang)
    if not Omerta.InEngine then return nil end
    if IsValid(clerks[business.id]) then clerks[business.id]:Remove() end

    local typeDef = Omerta.Business.GetType(business.type_key)
    local block = Omerta.Crime.RobberyBlock(typeDef)

    local ent = ents.Create("omerta_clerk")
    if not IsValid(ent) then return nil end
    ent.OmertaBusiness = business.id
    ent:SetPos(pos)
    ent:SetAngles(ang or Angle(0, 0, 0))
    ent:Spawn()

    -- WHICH CLERK IS DRAWN ONCE AND STAYS DRAWN. A shop whose personality
    -- re-rolled every robbery would be a shop nobody could learn, and learning
    -- which door you are walking through is what the whole reaction model is
    -- for. Derived from the business id so it survives a restart without a
    -- column: the same shop has the same man in it every night.
    local names = block.clerk.personalities
    local index = (business.id % #names) + 1
    ent.OmertaPersonality = names[index]

    -- The declared flee point, exactly as M13 already declares newspaperSpawn
    -- and surveillance. Resolved to a position now rather than at the moment of
    -- panic, because a lookup that fails mid-flee is a man who stops dead.
    ent.OmertaFleePoint = Internal.ResolveFleePoint(business, block.fleeTo)

    clerks[business.id] = ent
    return ent
end

-- Named points on the premises. M14 adds no point system: it reads M13's, and
-- falls back to "behind him, away from the counter" when the type declared
-- nothing — which is a worse flee than a declared one and better than none.
function Internal.ResolveFleePoint(business, name)
    if not Omerta.InEngine then return nil end
    local counter = business.counter
    if not IsValid(counter) then return nil end
    if Omerta.Business.PointFor then
        local point = Omerta.Business.PointFor(business, name)
        if point then return point end
    end
    return counter:GetPos() - counter:GetAngles():Forward() * 160
end

--------------------------------------------------------------------------------
-- Asking him
--------------------------------------------------------------------------------

-- The situation, assembled from the world. Everything here is a fact the man
-- could actually perceive: what is pointed at him, how many of them there are,
-- whether their faces are covered, how long this has been going on.
function Internal.Situation(operation, extra)
    local situation = {
        armed = false,
        weaponClass = nil,
        weaponsVisible = 0,
        masked = false,
        shotsFired = operation.shotsFired or 0,
        victimHurt = operation.clerkHurt == true,
        bystanderHurt = operation.bystanderHurt == true,
        bystanders = 0,
        alarmRaised = operation.state == S.ALARMED,
        elapsed = os.time() - (operation.started_at or os.time()),
    }

    if not Omerta.InEngine then
        for key, value in pairs(extra or {}) do situation[key] = value end
        return situation
    end

    -- MASKED MEANS ANY OF THEM. He is not doing a headcount of faces; one
    -- covered face is what tells him this is meant to end with him alive.
    for characterId in pairs(operation.participants) do
        local ply = Internal.PlayerFor(characterId)
        if IsValid(ply) then
            if Omerta.Crime.IsMasked(characterId) then situation.masked = true end
            local weapon = ply:GetActiveWeapon()
            local def = IsValid(weapon) and Omerta.Weapons
                and Omerta.Weapons.ForClass(weapon:GetClass())
            if def then
                situation.armed = true
                situation.weaponsVisible = situation.weaponsVisible + 1
                -- The heaviest thing in the room is the thing he is looking at.
                local class = Omerta.Crime.ThreatClass(def)
                local pressure = Omerta.Crime.WEAPON_PRESSURE[class or ""] or 0
                local current = Omerta.Crime.WEAPON_PRESSURE[situation.weaponClass or ""] or -1
                if pressure > current then situation.weaponClass = class end
            end
        end
    end

    for _, ply in ipairs(player.GetAll()) do
        local character = Omerta.Characters.Get(ply)
        if character and not operation.participants[character.id] then
            if ply:GetPos():Distance(operation.pos) <= Omerta.Config.Get("crime.observer_range") then
                situation.bystanders = situation.bystanders + 1
            end
        end
    end

    for key, value in pairs(extra or {}) do situation[key] = value end
    return situation
end

-- ONE EVALUATION, ON AN EVENT. The demand, a shot, somebody new through the
-- door, being struck, and the fixed nerve-decay step. Never a tick — pressure
-- accumulates across evaluations and the function itself is stateless.
function Internal.Evaluate(operation, beat, extra)
    local personality = operation.personality
    if not personality then return nil end
    if operation.clerkDead then return nil end

    local situation = Internal.Situation(operation, extra)
    local reaction = Omerta.Crime.Reaction(situation, personality, operation.seed, beat)

    operation.reaction = reaction
    operation.anyMasked = operation.anyMasked or situation.masked == true

    Internal.Perform(operation, reaction, situation)
    return reaction
end

function Internal.Perform(operation, reaction, situation)
    local clerk = operation.clerk
    if not IsValid(clerk) then return end

    if reaction == R.COMPLY then
        operation.complied = true
        operation.registerOpen = true
        clerk:SetPose(clerk.POSE.HANDS_UP)

    elseif reaction == R.STALL then
        clerk:SetPose(clerk.POSE.HANDS_UP)

    elseif reaction == R.RESIST then
        -- The register never opens. Forcing it is the crowbar's job and it
        -- takes the time the type declared.
        operation.registerOpen = false
        clerk:SetPose(clerk.POSE.IDLE)

    elseif reaction == R.ALARM then
        clerk:SetPose(clerk.POSE.REACHING)
        local block = operation.robbery or {}
        local alarmBlock = block.alarm or {}
        -- Which one he reaches for is the PREMISES' property, not his.
        local source = alarmBlock.button and Omerta.Crime.ALARM_SOURCE.BUTTON
            or (alarmBlock.telephone and Omerta.Crime.ALARM_SOURCE.TELEPHONE or nil)
        -- A place with neither is a place where reaching for it achieves
        -- nothing, and he finds that out the same way the player does.
        if source then Internal.AlarmOperation(operation, source) end

    elseif reaction == R.FLEE then
        operation.registerOpen = false
        clerk.OmertaFleeTo = clerk.OmertaFleePoint
        clerk.OmertaFleeStarted = CurTime()
        clerk:SetPose(clerk.POSE.FLEEING)
        Omerta.Crime.Observe(operation, "flee", operation.pos)
    end
end

--------------------------------------------------------------------------------
-- Hurting him, and killing him (D-052)
--------------------------------------------------------------------------------

function Internal.ClerkHurt(clerk, attacker)
    local operation = clerk.OmertaBusiness and Omerta.Crime.ForBusiness(clerk.OmertaBusiness)
    if not operation then return end
    operation.clerkHurt = true
    Internal.JoinAttacker(operation, attacker)
    Internal.Evaluate(operation, "struck")
end

-- What killing him costs is everything except the money: its own event, a
-- guaranteed alarm on a fixed timer, major evidence, front-page eligibility and
-- substantially worse legal consequences. It is meant to be WORSE THAN THE MONEY
-- IS GOOD — a tuning statement made now rather than discovered when somebody
-- works out that a dead witness is a cheap witness.
function Internal.ClerkKilled(clerk, attacker)
    -- EVERYTHING IS READ OFF THE ENTITY BEFORE IT STOPS BEING ONE. The first
    -- version of this made the ragdoll, removed the clerk, and then asked the
    -- removed clerk where it had been — which is a NULL entity by then, so the
    -- murder event was recorded at the origin of the map.
    local businessId = clerk.OmertaBusiness
    local pos = clerk:GetPos()
    local model = clerk:GetModel()
    local ang = clerk:GetAngles()

    clerk.OmertaFleeTo = nil
    clerk.OmertaClerkAlive = false

    local body = Internal.RagdollFor(model, pos, ang)
    if businessId then clerks[businessId] = nil end

    -- Deferred by a frame rather than removed inside the damage handler: the
    -- engine is still walking this entity's damage path, and taking it out from
    -- under itself is the kind of crash that only happens on a live server.
    timer.Simple(0, function() if IsValid(clerk) then clerk:Remove() end end)

    local operation = businessId and Omerta.Crime.ForBusiness(businessId)
    local season = Omerta.Seasons.GetActive()
    local attackerCharacter = IsValid(attacker) and attacker:IsPlayer()
        and Omerta.Characters.Get(attacker) or nil

    -- ITS OWN EVENT, always — even with no operation behind it. Shooting a
    -- shopkeeper nobody was robbing is still a murder, and M21 and M17 need it
    -- whether or not a robbery was in progress.
    Omerta.Events.Create({
        type = "crime.clerk_killed",
        season_id = season and season.id or nil,
        actor_character_id = attackerCharacter and attackerCharacter.id or nil,
        pos = IsValid(body) and body:GetPos() or pos,
        data = { business = businessId, operation = operation and operation.id or nil },
    })

    Omerta.Log.Audit("crime.clerk_killed", {
        actor = IsValid(attacker) and attacker.SteamID64 and attacker:SteamID64() or nil,
        subject = businessId,
        data = { operation = operation and operation.id or nil },
    })

    if not operation then
        -- No robbery, so no operation to resolve — but somebody still has to
        -- find him.
        local delay = Omerta.Config.Get("crime.discovery_seconds")
        timer.Simple(delay, function()
            Omerta.Crime.RaiseAlarm({
                source = Omerta.Crime.ALARM_SOURCE.DISCOVERY,
                severity = 3, pos = pos,
            })
        end)
        return
    end

    operation.clerkDead = true
    operation.clerkAlive = false
    operation.clerk = nil
    Internal.JoinAttacker(operation, attacker)
    Omerta.Crime.Observe(operation, "killed", operation.pos)

    -- AND THE REGISTER STAYS EXACTLY AS IT WAS. Killing him does not stop the
    -- crew emptying it: a rule that sealed the money because the man beside it
    -- is dead would exist to punish rather than to model. The operation
    -- continues and resolves normally.
end

function Internal.RagdollFor(model, pos, ang)
    if not Omerta.InEngine then return nil end
    local body = ents.Create("prop_ragdoll")
    if not IsValid(body) then return nil end
    body:SetModel(model)
    body:SetPos(pos)
    body:SetAngles(ang)
    body:Spawn()
    -- Marked so M15 can find it and so nothing mistakes it for an M19 body:
    -- looking at this resolves to nobody, because there is nobody to resolve.
    body:SetNWBool("OmertaClerkBody", true)
    return body
end

-- Somebody who shoots the clerk during a robbery is in the robbery, whether or
-- not they made the demand. Being in the room with a gun out is participation
-- and the participants table is what M17 builds a case from.
function Internal.JoinAttacker(operation, attacker)
    if not (IsValid(attacker) and attacker:IsPlayer()) then return end
    local character = Omerta.Characters.Get(attacker)
    if character then Omerta.Crime.Join(operation, character.id) end
end

--------------------------------------------------------------------------------
-- Letting him go
--------------------------------------------------------------------------------

function Internal.ReleaseClerk(operation)
    local clerk = operation.clerk
    if not IsValid(clerk) then return end
    clerk.OmertaFleeTo = nil
    clerk:SetPose(clerk.POSE.IDLE)
end
