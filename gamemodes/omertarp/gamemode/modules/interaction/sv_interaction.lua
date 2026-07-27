-- Server side of the interaction framework: resolve the nominated target,
-- re-validate everything the client claimed, execute.

Omerta.Interaction = Omerta.Interaction or {}
Omerta.Interaction.Internal = Omerta.Interaction.Internal or {}
local Internal = Omerta.Interaction.Internal

-- Resolves a client-supplied entity index into a legitimate target.
-- Returns entity, distance — or nil, reason.
function Internal.ResolveTarget(ply, entIndex)
    local target = Entity(entIndex)
    if not IsValid(target) then return nil, "no such target" end
    if target == ply then return nil, "cannot interact with yourself" end
    local distance = ply:GetPos():Distance(target:GetPos())
    if distance > Omerta.Interaction.MAX_RANGE then return nil, "too far away" end
    return target, distance
end

-- Computes the actions this player may currently perform on this target.
function Internal.Available(ply, target, distance)
    local available = {}
    for _, def in ipairs(Omerta.Interaction.GetOrdered()) do
        if Omerta.Interaction.CanUse(def, ply, target, distance) then
            available[#available + 1] = def
            if #available >= Omerta.Interaction.MAX_OPTIONS then break end
        end
    end
    return available
end
Omerta.Interaction.GetAvailable = Internal.Available

function Internal.SendOptions(ply, entIndex)
    local target, distance = Internal.ResolveTarget(ply, entIndex)
    local payload = { target = entIndex, count = 0 }
    -- Fixed-width slots: fill the unused ones so the schema validates.
    for i = 1, Omerta.Interaction.MAX_OPTIONS do
        payload["i" .. i] = 0
        payload["l" .. i] = ""
    end

    if target then
        local available = Internal.Available(ply, target, distance)
        payload.count = #available
        for i, def in ipairs(available) do
            payload["i" .. i] = def.index
            payload["l" .. i] = def.label
        end
    end
    Omerta.Net.Send("interaction.options", payload, ply)
end

function Internal.Execute(ply, entIndex, actionIndex)
    local target, distance = Internal.ResolveTarget(ply, entIndex)
    if not target then return end

    local def = Omerta.Interaction.GetByIndex(actionIndex)
    -- Full re-validation: the client may send any index it likes, including
    -- one it was never offered.
    local ok, reason = Omerta.Interaction.CanUse(def, ply, target, distance)
    if not ok then
        Omerta.Log.Debug("interaction", "%s refused '%s': %s",
            ply:SteamID64() or "?", def and def.id or ("#" .. tostring(actionIndex)), reason)
        return
    end

    local success, err = pcall(def.run, ply, target)
    if not success then
        Omerta.Log.Error("interaction", "action '%s' failed: %s", def.id, tostring(err))
    end
end
