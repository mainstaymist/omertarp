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
    -- Dragging is shelved, not deleted: the grab/letgo registrations that
    -- lived here are gone until the mechanic is worked out, but sv_bodies'
    -- Grab/LetGo/TickDrags and the sh_injury drag maths stay — the headless
    -- tests cover the pure rules, so bringing it back is a re-registration,
    -- not a rebuild.

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
    -- that an unconscious man cannot stop you looking, and that it takes a
    -- moment to go through them. This is the E press on a body — with dragging
    -- shelved, search is the one obvious thing to do to somebody on the floor.
    Omerta.Interaction.Register("injury.search", {
        label = "Search", range = 72, order = 44, default = true,
        -- Best effort: a corpse whose pockets happen to be loaded and empty
        -- says so up front, sparing the four-second rummage for nothing. An
        -- unloaded inventory keeps the plain label — the search finds out.
        describe = function(ply, target)
            local characterId = Omerta.Injury.CharacterOfBody(target)
            local owner = characterId
                and { type = Omerta.Inventory.OWNER.CHARACTER, id = characterId }
            if owner and Omerta.Inventory.IsLoaded(owner)
                    and #Omerta.Inventory.Get(owner) == 0 then
                return "Search (empty)"
            end
        end,
        predicate = function(ply, target)
            local characterId = Omerta.Injury.CharacterOfBody(target)
            if not characterId then return false end
            local actor = Omerta.Characters.Get(ply)
            return actor ~= nil and actor.id ~= characterId
        end,
        run = function(ply, target)
            Internal.BeginSearch(ply, Omerta.Injury.CharacterOfBody(target))
        end,
    })
end

-- USE on a body searches it — the engine +use fallback lands on the same
-- BeginSearch path the interaction default takes, so there is no shortcut
-- around the checks either way in.
function Internal.HandleUse(ply, body)
    local characterId = Omerta.Injury.CharacterOfBody(body)
    if not characterId then return end
    Internal.BeginSearch(ply, characterId)
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
        -- The window title. "Body", nothing more: WHOSE body is identity's
        -- question and stays answered per observer.
        return { type = Omerta.Inventory.OWNER.CHARACTER, id = characterId }, 0, "Body"
    end)

    Omerta.Inventory.RegisterContainerAccess("injury", function(ply, _, owner)
        if not (owner and owner.type == Omerta.Inventory.OWNER.CHARACTER) then
            return true -- not ours; no opinion
        end
        local characterId = owner.id
        local actor = Omerta.Characters.Get(ply)
        if actor and actor.id == characterId then return true end -- your own pockets

        -- Searchable is a property of being HELPLESS, not of having once been
        -- hurt. The moment they are back on their feet the answer changes —
        -- and a corpse is as helpless as it gets, so the dead are included.
        if not Omerta.Injury.IsIncapable(Omerta.Injury.GetByCharacter(characterId)) then
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

-- Who has already been through whose pockets, this session.
--
-- Going through a stranger's coat takes a moment the first time. It does not
-- take a moment the second time, because you already know what is in there —
-- and making somebody wait again for information they have would be a tax on
-- the interface rather than a cost in the fiction.
local searched = {} -- actorCharacterId -> { [targetCharacterId] = true }

function Internal.HasSearched(actorId, targetId)
    return (searched[actorId] or {})[targetId] == true
end

function Internal.RememberSearch(actorId, targetId)
    searched[actorId] = searched[actorId] or {}
    searched[actorId][targetId] = true
end

-- Anything taken off a body changes what is in the pockets, so the next person
-- through them starts from scratch. Only the person who did the taking keeps
-- their knowledge.
function Internal.ForgetSearches(targetId, exceptActorId)
    for actorId, targets in pairs(searched) do
        if actorId ~= exceptActorId then targets[targetId] = nil end
    end
end

-- When each actor last deliberately stopped. See Omerta.Injury.SearchIntent:
-- one press of the key must not stop a search and start it again, and the
-- engine's +use fallback re-fires for as long as the key is held.
local stoppedAt = {} -- actor SteamID64 -> CurTime()

function Internal.BeginSearch(ply, characterId)
    local actor = Omerta.Characters.Get(ply)
    if not (actor and characterId) then return end

    -- E is one key with two meanings on the same body: go through their
    -- pockets, or stop. The server decides which — the client only ever says
    -- "I pressed E on that", exactly as it did before.
    local sid = ply:SteamID64() or ""
    local last = stoppedAt[sid]
    local intent = Omerta.Injury.SearchIntent(Internal.InProgress(ply), characterId,
        last and (CurTime() - last) or nil)

    if intent == "ignore" then return end
    if intent == "cancel" then
        stoppedAt[sid] = CurTime()
        -- The same path walking away takes: the action is dropped before its
        -- clock runs out, so onComplete never fires and nothing was written.
        Internal.Cancel(ply, "you stop searching")
        return
    end

    if Internal.HasSearched(actor.id, characterId) then
        Internal.SearchBody(ply, characterId)
        return
    end

    Omerta.Injury.Perform(ply, characterId, "injury.search_body", function(ok, err)
        if not ok and err then Omerta.Chat.Notice(ply, err) end
    end)
end

function Internal.RegisterSearchAction()
    Omerta.Injury.RegisterDownedAction("injury.search_body", {
        label = "Searching", range = 96,
        -- The rummage is audible to the one doing it: the prompt carries a
        -- sound code and the client plays a stretch of the rustle bed.
        sound = Omerta.Injury.PROMPT_SOUND.RUSTLE,
        duration = Omerta.Config.Get("injury.search_seconds"), order = 44,
        predicate = function(ply, characterId)
            local actor = Omerta.Characters.Get(ply)
            if not (actor and actor.id ~= characterId) then return false end
            return Omerta.Injury.IsIncapable(Omerta.Injury.GetByCharacter(characterId))
        end,
        onComplete = function(ply, characterId, cb)
            local actor = Omerta.Characters.Get(ply)
            if actor then Internal.RememberSearch(actor.id, characterId) end
            Internal.SearchBody(ply, characterId)
            cb(true)
        end,
    })
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
