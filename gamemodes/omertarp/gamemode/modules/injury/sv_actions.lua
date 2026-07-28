-- Where a body meets the rest of the game: M5's interaction menu, M9's search,
-- M5's identity resolution, and the staff commands.

Omerta.Injury = Omerta.Injury or {}
Omerta.Injury.Internal = Omerta.Injury.Internal or {}
local Internal = Omerta.Injury.Internal
local S = Omerta.Injury.STATE

--------------------------------------------------------------------------------
-- The interaction menu
--------------------------------------------------------------------------------

function Internal.RegisterInteractions()
    Omerta.Interaction.Register("injury.carry", {
        label = "Pick Up", range = 96, order = 40,
        predicate = function(ply, target)
            local characterId = Omerta.Injury.CharacterOfBody(target)
            if not characterId then return false end
            if Omerta.Injury.CarriedBy(ply) then return false, "your hands are full" end
            return true
        end,
        run = function(ply, target)
            Omerta.Injury.Carry(ply, Omerta.Injury.CharacterOfBody(target),
                function(ok, err)
                    if not ok and err then Omerta.Chat.Notice(ply, err) end
                end)
        end,
    })

    Omerta.Interaction.Register("injury.drop", {
        label = "Put Down", range = 96, order = 41,
        predicate = function(ply, target)
            local characterId = Omerta.Injury.CharacterOfBody(target)
            return characterId ~= nil and Omerta.Injury.CarriedBy(ply) == characterId
        end,
        run = function(ply)
            Omerta.Injury.Drop(ply)
        end,
    })

    Omerta.Interaction.Register("injury.stabilize", {
        label = "Stabilize", range = 72, order = 42,
        predicate = function(ply, target)
            local characterId = Omerta.Injury.CharacterOfBody(target)
            if not characterId then return false end
            local def = Internal.Treatments["injury.stabilize"]
            return def and def.predicate(ply, characterId) == true
        end,
        run = function(ply, target)
            Omerta.Injury.Perform(ply, Omerta.Injury.CharacterOfBody(target),
                "injury.stabilize", function(ok, err)
                    if not ok and err then Omerta.Chat.Notice(ply, err) end
                end)
        end,
    })

    Omerta.Interaction.Register("injury.treat", {
        label = "Treat", range = 96, order = 43,
        predicate = function(ply, target)
            local characterId = Omerta.Injury.CharacterOfBody(target)
            if not characterId then return false end
            local def = Internal.Treatments["injury.treat"]
            return def and def.predicate(ply, characterId) == true
        end,
        run = function(ply, target)
            Omerta.Injury.Perform(ply, Omerta.Injury.CharacterOfBody(target),
                "injury.treat", function(ok, err)
                    if not ok and err then Omerta.Chat.Notice(ply, err) end
                end)
        end,
    })

    -- Searching a body. M9 owns what is in somebody's pockets; M19 only says
    -- that an unconscious man cannot stop you looking.
    Omerta.Interaction.Register("injury.search", {
        label = "Search", range = 72, order = 44,
        predicate = function(ply, target)
            local characterId = Omerta.Injury.CharacterOfBody(target)
            if not characterId then return false end
            local actor = Omerta.Characters.Get(ply)
            return actor ~= nil and actor.id ~= characterId
        end,
        run = function(ply, target)
            Internal.SearchBody(ply, Omerta.Injury.CharacterOfBody(target))
        end,
    })
end

-- USE on a body opens the same menu the interaction system would.
function Internal.HandleUse(ply, body)
    local characterId = Omerta.Injury.CharacterOfBody(body)
    if not characterId then return end
    if Omerta.Injury.CarriedBy(ply) == characterId then
        Omerta.Injury.Drop(ply)
        return
    end
    Omerta.Injury.Carry(ply, characterId, function(ok, err)
        if not ok and err then Omerta.Chat.Notice(ply, err) end
    end)
end

--------------------------------------------------------------------------------
-- Searching (M9 integration)
--------------------------------------------------------------------------------
-- A downed character's pockets ARE their inventory — not a copy of it, not a
-- box their things are moved into. M9 gained an openable seam for this in M19,
-- so searching a body reuses M9's transactional moves, capacity checks and
-- access predicate rather than inventing a second way to take things off
-- somebody. Two homes for one coat is how an item gets duplicated.

function Internal.RegisterSearch()
    Omerta.Inventory.RegisterOpenable("prop_ragdoll", function(_, ent)
        local characterId = Omerta.Injury.CharacterOfBody(ent)
        if not characterId then return nil end
        return { type = Omerta.Inventory.OWNER.CHARACTER, id = characterId }, 0
    end)

    Omerta.Inventory.RegisterContainerAccess("injury", function(ply, _, owner)
        if not (owner and owner.type == Omerta.Inventory.OWNER.CHARACTER) then
            return true -- not ours; no opinion
        end
        local characterId = owner.id
        local actor = Omerta.Characters.Get(ply)
        if actor and actor.id == characterId then return true end -- your own pockets

        -- Searchable is a property of being HELPLESS, not of having once been
        -- hurt. The moment they are back on their feet the answer changes.
        if not Omerta.Injury.IsDown(Omerta.Injury.GetByCharacter(characterId)) then
            return false, "they are not going to let you"
        end
        local body = Omerta.Injury.BodyOf(characterId)
        if not IsValid(body) then return false, "they are not there" end
        if ply:GetPos():Distance(body:GetPos()) > 96 then
            return false, "you are not close enough"
        end
        return true
    end)
end

function Internal.SearchBody(ply, characterId)
    local body = Omerta.Injury.BodyOf(characterId)
    if not IsValid(body) then return end
    Omerta.Log.Audit("injury.searched", {
        actor = ply:SteamID64(), character_id = characterId,
        data = { by = (Omerta.Characters.Get(ply) or {}).id },
    })
    Omerta.Inventory.Internal.HandleOpen(ply, body:EntIndex())
end

--------------------------------------------------------------------------------
-- Identity (M5 integration)
--------------------------------------------------------------------------------
-- A body is a person. Looking at one resolves through ResolveDisplayName, per
-- observer, exactly as looking at somebody standing up does — so you recognise
-- the man on the floor if and only if you would have recognised him upright,
-- and a masked body stays Unknown.

function Internal.RegisterIdentity()
    if not Omerta.Identity.RegisterSubjectProvider then return end
    Omerta.Identity.RegisterSubjectProvider("injury.body", function(ent, cb)
        local characterId = Omerta.Injury.CharacterOfBody(ent)
        if not characterId then return false end
        Omerta.Characters.GetByID(characterId, function(row) cb(row) end)
        return true
    end)
end

--------------------------------------------------------------------------------
-- Staff commands
--------------------------------------------------------------------------------

function Internal.RegisterCommands()
    concommand.Add("omerta_injury_state", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        local target = IsValid(caller) and caller or nil
        local characterId = tonumber(args[2] or "")

        if not characterId then
            local character = target and Omerta.Characters.Get(target)
            if not character then
                Omerta.Log.Error("injury", "usage: omerta_injury_state <state> [characterId]")
                return
            end
            characterId = character.id
        end

        local state = args[1]
        if not Omerta.Injury.STATE_INDEX[state or ""] then
            Omerta.Log.Error("injury", "states: %s", table.concat(Omerta.Injury.ORDER, ", "))
            return
        end

        Omerta.Injury.Set(characterId, state, { cause = "staff" }, function(ok, err)
            if not ok then Omerta.Log.Error("injury", "%s", tostring(err)) return end
            Omerta.Log.Info("injury", "#%d is now %s", characterId, state)
        end)
    end)

    concommand.Add("omerta_injury_list", function(caller)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        local now = os.time()
        local count = 0
        for characterId, entry in pairs(Internal.States) do
            count = count + 1
            local left = Omerta.Injury.SecondsLeft(entry.expiresAt, now)
            Omerta.Log.Info("injury", "  #%-4d %-14s %s%s",
                characterId, entry.state,
                left and string.format("%ds left", math.floor(left)) or "no clock",
                IsValid(Omerta.Injury.BodyOf(characterId)) and "  (body placed)" or "")
        end
        if count == 0 then Omerta.Log.Info("injury", "nobody is hurt") end
    end)

    concommand.Add("omerta_injury_history", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        local characterId = tonumber(args[1] or "")
        if not characterId then
            Omerta.Log.Error("injury", "usage: omerta_injury_history <characterId>")
            return
        end
        Internal.Repo.EventsFor(characterId, 20, function(rows)
            Omerta.Log.Info("injury", "#%d — %d event(s)", characterId, #rows)
            for i = #rows, 1, -1 do
                local row = rows[i]
                Omerta.Log.Info("injury", "  %s -> %-14s %-12s %s",
                    row.from_state, row.to_state, row.cause,
                    row.actor_character_id and ("by #" .. row.actor_character_id) or "")
            end
        end)
    end)
end
