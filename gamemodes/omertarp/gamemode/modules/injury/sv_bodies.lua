-- Bodies: putting somebody down, standing them back up, and carrying them.
--
-- The body is a REPRESENTATION. The truth is the character_injury row — which
-- is why a body can be destroyed by a map cleanup and respawned from the
-- database without anybody's condition changing.

Omerta.Injury = Omerta.Injury or {}
Omerta.Injury.Internal = Omerta.Injury.Internal or {}
local Internal = Omerta.Injury.Internal

local bodies = {}   -- characterId -> entity
local dragging = {} -- dragger SteamID64 -> { characterId, anchor, startedAt }

Internal.Bodies = bodies

function Omerta.Injury.BodyOf(characterId) return bodies[characterId] end

function Omerta.Injury.CharacterOfBody(ent)
    if not IsValid(ent) then return nil end
    return ent.OmertaCharacter
end

function Internal.ForgetBodyEntity(characterId)
    bodies[characterId] = nil
end

--------------------------------------------------------------------------------
-- Down and up
--------------------------------------------------------------------------------

-- The player's own entity is hidden and frozen rather than removed: removing
-- it would drop them out of the world entirely, and they still need to see and
-- hear what is being done to them.
function Internal.HoldPlayer(ply)
    if not IsValid(ply) then return end
    ply:Freeze(true)
    ply:SetNoDraw(true)
    ply:SetNotSolid(true)
    ply:SetMoveType(MOVETYPE_NONE)
end

function Internal.ReleaseView(ply)
    if not IsValid(ply) then return end
    ply:Freeze(false)
    ply:SetNoDraw(false)
    ply:SetNotSolid(false)
    ply:SetMoveType(MOVETYPE_WALK)
end

-- The body is a real ragdoll, not a prop lying at a fixed angle.
--
-- A scripted entity cannot BE a ragdoll — `base_anim` is a CBaseAnimating and
-- ragdoll bone data is a property of CRagdollProp — so the body is a genuine
-- prop_ragdoll that the module owns and tags. That also gives the client an
-- "eyes" attachment to hang the first-person camera on, which is the whole
-- reason a limp head looks like anything.
--
-- Marked with a networked boolean so a client can tell our bodies from the
-- map's furniture. It says "somebody is on the floor here", which is visible
-- from across the street anyway; it does NOT say who, and the character id
-- stays server-side exactly as before.
function Internal.SpawnBody(characterId, pos, yaw, model, sourcePly)
    if not Omerta.InEngine then return nil end
    if IsValid(bodies[characterId]) then bodies[characterId]:Remove() end

    local ent = ents.Create("prop_ragdoll")
    if not IsValid(ent) then return nil end

    ent:SetModel(Omerta.Util.ResolveModel(model, Internal.FALLBACK_MODEL))
    ent:SetPos(pos)
    ent:SetAngles(Angle(0, yaw or 0, 0))
    ent:Spawn()
    ent:Activate()

    ent.OmertaCharacter = characterId
    ent:SetNWBool("OmertaBody", true)

    -- Match the pose the character was standing in, then hand it their
    -- momentum, so somebody shot mid-sprint goes down travelling rather than
    -- appearing in a heap. Guarded: a model whose physics bones do not map
    -- cleanly should produce a plain ragdoll, not an error.
    if IsValid(sourcePly) then
        local velocity = sourcePly:GetVelocity()
        for i = 0, ent:GetPhysicsObjectCount() - 1 do
            local phys = ent:GetPhysicsObjectNum(i)
            if IsValid(phys) then
                local boneIndex = ent:TranslatePhysBoneToBone(i)
                if boneIndex then
                    local bonePos, boneAng = sourcePly:GetBonePosition(boneIndex)
                    if bonePos then phys:SetPos(bonePos) end
                    if boneAng then phys:SetAngles(boneAng) end
                end
                phys:SetVelocity(velocity)
                phys:Wake()
            end
        end
    end

    bodies[characterId] = ent
    return ent
end

Internal.FALLBACK_MODEL = "models/player/group01/male_01.mdl"

-- A body removed by a map cleanup is still on the floor as far as persistence
-- is concerned. prop_ragdoll has no OnRemove of ours, so the module watches
-- instead — same contract M9's dropped items have.
function Internal.RegisterBodyCleanup()
    hook.Add("EntityRemoved", "omerta.injury.body_removed", function(ent)
        local characterId = ent.OmertaCharacter
        if characterId and bodies[characterId] == ent then
            bodies[characterId] = nil
        end
    end)

    -- prop_ragdoll has no Use of its own, so the E shortcut is wired here.
    -- It goes through the same server-side path the interaction menu uses.
    hook.Add("PlayerUse", "omerta.injury.body_use", function(ply, ent)
        if not (IsValid(ent) and ent.OmertaCharacter) then return end
        Internal.HandleUse(ply, ent)
        return false -- consumed; do not also +use the world behind it
    end)
end

function Internal.PutDown(characterId, opts)
    opts = opts or {}
    local ply = Internal.PlayerFor(characterId)

    local pos, yaw, model
    if IsValid(ply) then
        pos = ply:GetPos()
        yaw = ply:EyeAngles().y
        model = ply:GetModel()
    end

    -- Reconnecting to an existing body: keep it exactly where it fell.
    local existing = bodies[characterId]
    if IsValid(existing) then
        pos, yaw = existing:GetPos(), existing:GetAngles().y
    end
    if not pos then return end

    if not IsValid(existing) then
        Internal.SpawnBody(characterId, pos, yaw, model, ply)
        local season = Omerta.Seasons.GetActive()
        if season then
            Internal.Repo.SaveBody(season.id, characterId, game.GetMap(), pos, yaw)
        end
    end

    if IsValid(ply) then
        Internal.HoldPlayer(ply)
        ply:SetPos(pos)
        if not opts.reconnected then
            Omerta.Chat.Notice(ply, "You go down.")
        end
    end
end

function Internal.StandUp(characterId)
    local body = bodies[characterId]
    local pos = IsValid(body) and body:GetPos() or nil

    Internal.DropIfDragged(characterId)
    Internal.RemoveBody(characterId, true)

    local ply = Internal.PlayerFor(characterId)
    if IsValid(ply) then
        Internal.ReleaseView(ply)
        if pos then ply:SetPos(pos + Vector(0, 0, 8)) end
        Omerta.Chat.Notice(ply, "You get to your feet.")
    end
end

function Internal.RemoveBody(characterId, alsoRow)
    local body = bodies[characterId]
    bodies[characterId] = nil
    if IsValid(body) then
        body.OmertaCharacter = nil -- so OnRemove does not re-enter
        body:Remove()
    end
    if alsoRow then Internal.Repo.RemoveBody(characterId) end
end

--------------------------------------------------------------------------------
-- Dragging
--------------------------------------------------------------------------------
-- Anyone can take hold of a body — you do not need to be anybody, and that is
-- deliberate: a passer-by pulling a stranger out of the road is a scene worth
-- having. What you cannot do is make it discreet.

-- cb(ok, err)
function Omerta.Injury.Grab(ply, characterId, cb)
    cb = cb or function() end
    if not IsValid(ply) then cb(false, "no one there") return end
    if Omerta.Injury.DraggedBy(ply) then cb(false, "your hands are full") return end
    if Omerta.Injury.IsPlayerDown(ply) then cb(false, "you cannot") return end

    local body = bodies[characterId]
    if not IsValid(body) then cb(false, "there is nothing to take hold of") return end
    if Internal.DraggerOf(characterId) then cb(false, "somebody already has them") end

    local anchor = body:GetPos()
    dragging[ply:SteamID64() or ""] = {
        characterId = characterId,
        anchor = anchor,
        startedAt = CurTime(),
    }
    Internal.WakeBody(body)

    Omerta.Net.Send("injury.dragging", {
        body = body:EntIndex(),
        x = math.floor(anchor.x), y = math.floor(anchor.y), z = math.floor(anchor.z),
    }, ply)
    Omerta.Log.Audit("injury.dragged", {
        actor = ply:SteamID64(), character_id = characterId, data = { grabbed = true },
    })
    cb(true)
end

-- cb(ok, err)
function Omerta.Injury.LetGo(ply, cb)
    cb = cb or function() end
    local entry = IsValid(ply) and dragging[ply:SteamID64() or ""]
    if not entry then cb(false, "you are not holding anybody") return end

    dragging[ply:SteamID64() or ""] = nil
    local body = bodies[entry.characterId]
    if IsValid(body) then
        Internal.Repo.MoveBody(entry.characterId, body:GetPos())
        -- Where a body ends up is the fact M15 will care about most.
        local season = Omerta.Seasons.GetActive()
        if season then
            local actor = Omerta.Characters.Get(ply)
            Internal.Repo.LogEvent({
                season_id = season.id, character_id = entry.characterId,
                from_state = "dragged", to_state = "released", cause = "moved",
                actor_character_id = actor and actor.id or Omerta.DB.NULL,
                at = os.time(),
            })
        end
    end

    if IsValid(ply) then
        Omerta.Net.Send("injury.dragging", { body = 0, x = 0, y = 0, z = 0 }, ply)
    end
    cb(true)
end

function Omerta.Injury.DraggedBy(ply)
    if not IsValid(ply) then return nil end
    local entry = dragging[ply:SteamID64() or ""]
    return entry and entry.characterId or nil
end

function Internal.DraggerOf(characterId)
    for sid, entry in pairs(dragging) do
        if entry.characterId == characterId then
            for _, ply in ipairs(player.GetAll()) do
                if ply:SteamID64() == sid then return ply end
            end
        end
    end
    return nil
end

function Internal.DropIfDragged(characterId)
    local dragger = Internal.DraggerOf(characterId)
    if IsValid(dragger) then Omerta.Injury.LetGo(dragger) end
end

-- A ragdoll has many physics objects, so "freeze" and "wake" are loops rather
-- than a single call. Kept together so the pair cannot drift.
function Internal.FreezeBody(body)
    if not IsValid(body) then return end
    for i = 0, body:GetPhysicsObjectCount() - 1 do
        local phys = body:GetPhysicsObjectNum(i)
        if IsValid(phys) then phys:EnableMotion(false) end
    end
end

function Internal.WakeBody(body, impulse)
    if not IsValid(body) then return end
    for i = 0, body:GetPhysicsObjectCount() - 1 do
        local phys = body:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:EnableMotion(true)
            phys:Wake()
            if impulse then phys:SetVelocity(impulse) end
        end
    end
end

-- Every drag is re-validated every tick, and the rope is what does the work.
-- A dragger who is killed, put down, disconnects, or simply walks too far
-- loses their grip — a client that stops sending anything does not get to keep
-- a body attached to it.
function Internal.TickDrags()
    -- Derived from the hauler's own speed rather than set as an absolute.
    -- A fixed number here silently couples to D-034: halving the walk speed
    -- once made the body faster than the man pulling it, so the rope could
    -- never go taut. Expressed as a fraction, the relationship holds whatever
    -- the movement config says.
    local drain = Omerta.Config.Get("injury.drag_drain_per_second")
    local scale = Omerta.Injury.HaulSpeed(
        Omerta.Config.Get("movement.walk_speed"),
        Omerta.Config.Get("injury.drag_speed_scale"),
        Omerta.Config.Get("injury.drag_catchup"))

    for sid, entry in pairs(dragging) do
        local dragger = nil
        for _, ply in ipairs(player.GetAll()) do
            if ply:SteamID64() == sid then dragger = ply break end
        end
        local body = bodies[entry.characterId]

        if not IsValid(dragger) or Omerta.Injury.IsPlayerDown(dragger) or not IsValid(body) then
            dragging[sid] = nil
        else
            local target = dragger:GetPos()
            local from = body:GetPos()
            local distance = from:Distance(target)

            if Omerta.Injury.DragBreaks(distance) then
                Omerta.Chat.Notice(dragger, "You lose your grip.")
                Omerta.Injury.LetGo(dragger)
            else
                local tension = Omerta.Injury.DragTension(distance)
                if tension > 0 then
                    -- Velocity toward the dragger rather than a force impulse:
                    -- a ragdoll given impulses tumbles and snags on scenery,
                    -- and a body being hauled should slide, not cartwheel.
                    local direction = (target - from)
                    direction.z = 0
                    direction:Normalize()
                    local speed = Omerta.Injury.DragSpeed(tension, scale)

                    for i = 0, body:GetPhysicsObjectCount() - 1 do
                        local phys = body:GetPhysicsObjectNum(i)
                        if IsValid(phys) then
                            local velocity = phys:GetVelocity()
                            phys:SetVelocity(Vector(direction.x * speed,
                                direction.y * speed, velocity.z))
                        end
                    end
                    if drain > 0 then Omerta.Stamina.Drain(dragger, drain * tension) end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Restore after a restart
--------------------------------------------------------------------------------

function Internal.LoadBodies()
    local season = Omerta.Seasons.GetActive()
    if not season then return end

    Internal.Repo.ListBodies(season.id, game.GetMap(), function(rows, err)
        if err then
            Omerta.Log.Error("injury", "could not load bodies: %s", err)
            return
        end
        local placed = 0
        for _, row in ipairs(rows) do
            -- Only for characters actually still down. A stale row for someone
            -- who has since been treated is cleaned up rather than resurrected.
            local state = Omerta.Injury.GetByCharacter(row.character_id)
            if Omerta.Injury.IsDown(state) then
                if Internal.SpawnBody(row.character_id,
                        Vector(row.pos_x, row.pos_y, row.pos_z + 8), row.ang_y) then
                    placed = placed + 1
                end
            else
                Internal.Repo.RemoveBody(row.character_id)
            end
        end
        if placed > 0 then
            Omerta.Log.Info("injury", "%d body/bodies still on the floor", placed)
        end
    end)
end

--------------------------------------------------------------------------------
-- Disconnect
--------------------------------------------------------------------------------

function Internal.RegisterDisconnect()
    hook.Add("PlayerDisconnected", "omerta.injury.disconnect", function(ply)
        -- Whatever they were carrying hits the floor.
        if Omerta.Injury.DraggedBy(ply) then Omerta.Injury.LetGo(ply) end
        dragging[ply:SteamID64() or ""] = nil

        -- Their own body stays exactly where it is, and its clock keeps
        -- running. This is the point of D-037 §4a: logging out while
        -- incapacitated is not an escape from a confirmed kill, it is the most
        -- reliable way to bleed to death.
    end)
end
