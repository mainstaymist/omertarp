-- Bodies: putting somebody down, standing them back up, and carrying them.
--
-- The body is a REPRESENTATION. The truth is the character_injury row — which
-- is why a body can be destroyed by a map cleanup and respawned from the
-- database without anybody's condition changing.

Omerta.Injury = Omerta.Injury or {}
Omerta.Injury.Internal = Omerta.Injury.Internal or {}
local Internal = Omerta.Injury.Internal

local bodies = {}   -- characterId -> entity
local carrying = {} -- carrier SteamID64 -> characterId

Internal.Bodies = bodies

function Omerta.Injury.BodyOf(characterId) return bodies[characterId] end

function Omerta.Injury.CharacterOfBody(ent)
    if not IsValid(ent) then return nil end
    return ent.OmertaCharacter
end

function Omerta.Injury.CarriedBy(ply)
    if not IsValid(ply) then return nil end
    return carrying[ply:SteamID64() or ""]
end

function Internal.CarrierOf(characterId)
    for sid, carried in pairs(carrying) do
        if carried == characterId then
            for _, ply in ipairs(player.GetAll()) do
                if ply:SteamID64() == sid then return ply end
            end
        end
    end
    return nil
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

function Internal.SpawnBody(characterId, pos, yaw, model)
    if not Omerta.InEngine then return nil end
    if IsValid(bodies[characterId]) then bodies[characterId]:Remove() end

    local ent = ents.Create("omerta_body")
    if not IsValid(ent) then return nil end
    ent.OmertaCharacter = characterId
    ent.OmertaModel = model
    ent:SetPos(pos)
    ent:SetAngles(Angle(0, yaw or 0, 0))
    ent:Spawn()
    Omerta.Inventory.RestOnGround(ent, pos)
    bodies[characterId] = ent
    return ent
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
        Internal.SpawnBody(characterId, pos, yaw, model)
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

    Internal.DropIfCarried(characterId)
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
-- Carrying
--------------------------------------------------------------------------------

-- cb(ok, err)
function Omerta.Injury.Carry(ply, characterId, cb)
    cb = cb or function() end
    if not IsValid(ply) then cb(false, "no carrier") return end
    if Omerta.Injury.CarriedBy(ply) then cb(false, "your hands are full") return end
    if Omerta.Injury.IsPlayerDown(ply) then cb(false, "you cannot") return end

    local body = bodies[characterId]
    if not IsValid(body) then cb(false, "there is nothing to pick up") return end
    if Internal.CarrierOf(characterId) then cb(false, "somebody already has them") return end

    carrying[ply:SteamID64() or ""] = characterId
    body:SetMoveType(MOVETYPE_NONE)
    body:SetParent(ply)
    body:SetLocalPos(Vector(24, 0, 24))
    body:SetLocalAngles(Angle(85, 0, 0))

    Omerta.Net.Send("injury.carrying", { carrying = true }, ply)
    Omerta.Log.Audit("injury.carried", {
        actor = ply:SteamID64(), character_id = characterId,
        data = { picked_up = true },
    })
    cb(true)
end

-- cb(ok, err)
function Omerta.Injury.Drop(ply, cb)
    cb = cb or function() end
    local characterId = Omerta.Injury.CarriedBy(ply)
    if not characterId then cb(false, "you are not carrying anybody") return end

    carrying[ply:SteamID64() or ""] = nil
    local body = bodies[characterId]
    if IsValid(body) then
        body:SetParent(nil)
        body:SetMoveType(MOVETYPE_VPHYSICS)
        local pos = ply:GetPos() + ply:GetForward() * 32
        body:SetPos(pos)
        body:SetAngles(Angle(85, ply:EyeAngles().y, 0))
        Omerta.Inventory.RestOnGround(body, pos)
        Internal.Repo.MoveBody(characterId, body:GetPos())

        -- Where a body ends up is the fact M15 will care about most.
        local season = Omerta.Seasons.GetActive()
        if season then
            local actor = Omerta.Characters.Get(ply)
            Internal.Repo.LogEvent({
                season_id = season.id, character_id = characterId,
                from_state = "carried", to_state = "dropped", cause = "moved",
                actor_character_id = actor and actor.id or Omerta.DB.NULL,
                at = os.time(),
            })
        end
    end

    if IsValid(ply) then Omerta.Net.Send("injury.carrying", { carrying = false }, ply) end
    cb(true)
end

function Internal.DropIfCarried(characterId)
    local carrier = Internal.CarrierOf(characterId)
    if IsValid(carrier) then Omerta.Injury.Drop(carrier) end
end

-- Carrying is re-validated continuously, not once. A carrier who is killed,
-- put down, disconnects or is separated from the body drops it — a client that
-- simply stops sending anything does not get to keep a body attached to it.
function Internal.ValidateCarries()
    for sid, characterId in pairs(carrying) do
        local carrier = nil
        for _, ply in ipairs(player.GetAll()) do
            if ply:SteamID64() == sid then carrier = ply break end
        end
        if not IsValid(carrier) or Omerta.Injury.IsPlayerDown(carrier)
                or not IsValid(bodies[characterId]) then
            carrying[sid] = nil
            local body = bodies[characterId]
            if IsValid(body) then
                body:SetParent(nil)
                body:SetMoveType(MOVETYPE_VPHYSICS)
                Internal.Repo.MoveBody(characterId, body:GetPos())
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
                        Vector(row.pos_x, row.pos_y, row.pos_z), row.ang_y) then
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
        local carried = Omerta.Injury.CarriedBy(ply)
        if carried then Omerta.Injury.Drop(ply) end
        carrying[ply:SteamID64() or ""] = nil

        -- Their own body stays exactly where it is, and its clock keeps
        -- running. This is the point of D-037 §4a: logging out while
        -- incapacitated is not an escape from a confirmed kill, it is the most
        -- reliable way to bleed to death.
    end)
end
