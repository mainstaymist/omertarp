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
            -- The plain label unless the action knows something richer about
            -- THIS target right now — "Search (empty)". Best effort: a
            -- describe that errors or answers nothing falls back silently.
            local label = def.label
            if def.describe then
                local ok, described = pcall(def.describe, ply, target)
                if ok and type(described) == "string" and described ~= "" then
                    label = described
                end
            end
            payload["l" .. i] = string.sub(label, 1, 48)
        end
    end
    Omerta.Net.Send("interaction.options", payload, ply)
end

-- The tap path: E without the menu. Runs the first action that is available
-- AND flagged default — flagged, because running merely the first available
-- would make walking past a stranger with E introduce you to them.
function Internal.ExecuteDefault(ply, entIndex)
    local target, distance = Internal.ResolveTarget(ply, entIndex)
    if not target then return end

    for _, def in ipairs(Internal.Available(ply, target, distance)) do
        if def.default then
            local success, err = pcall(def.run, ply, target)
            if not success then
                Omerta.Log.Error("interaction", "default '%s' failed: %s", def.id, tostring(err))
            end
            return
        end
    end
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
