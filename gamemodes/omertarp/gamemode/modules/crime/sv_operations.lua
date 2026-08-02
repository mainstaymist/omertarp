-- The operation: the durable record that says a crime is under way.
--
-- The row is the truth and the in-memory copy is a cache over it, exactly as
-- M13's businesses and M19's injuries already are. Tech §16's last two states
-- are M17's and are measured in DAYS; an operation that lived only in RAM could
-- not be investigated after a restart, and M15 would have nothing durable to
-- hang a witness off.

Omerta.Crime = Omerta.Crime or {}
Omerta.Crime.Internal = Omerta.Crime.Internal or {}
local Internal = Omerta.Crime.Internal
local S = Omerta.Crime.STATE

local live = {}        -- operation id -> operation (cache over the row)
local byBusiness = {}  -- business id -> operation
local cooldowns = {}   -- business id -> os.time() the cooldown ends

Internal.Live = live
Internal.Cooldowns = cooldowns

--------------------------------------------------------------------------------
-- The observer seam (M15)
--------------------------------------------------------------------------------
-- At each notable beat M14 computes the set of people who could plausibly have
-- seen it and hands the set over. M14 STORES NONE OF IT AND INVENTS NO
-- DESCRIPTOR VOCABULARY — that is the cut. M14 owns the MOMENT, M15 owns the
-- MEMORY, and inventing a descriptor here would mean writing M15's rules in
-- M14's tables.
--
-- Shipped with nothing registered, in the shape M19 shipped RegisterDownedAction
-- for M20. If M15 can be built entirely as a registration into this, the seam
-- was cut correctly.

local observerSinks = {}

function Omerta.Crime.RegisterObserverSink(id, fn)
    if type(id) ~= "string" or id == "" then error("an observer sink needs an id", 2) end
    if type(fn) ~= "function" then error("observer sink '" .. id .. "' needs a function", 2) end
    if observerSinks[id] then error("observer sink '" .. id .. "' registered twice", 2) end
    observerSinks[id] = fn
end

Internal.ObserverSinks = observerSinks

-- Who could plausibly have seen this. Range, line of sight, and not being one
-- of the crew. Nothing is stored and nothing reaches a client.
function Omerta.Crime.Observe(operation, beat, pos)
    if not Omerta.InEngine then return end
    if next(observerSinks) == nil then return end

    pos = pos or operation.pos
    local range = Omerta.Config.Get("crime.observer_range")
    local observers = {}

    for _, ply in ipairs(player.GetAll()) do
        local character = Omerta.Characters.Get(ply)
        if character and not operation.participants[character.id] then
            if ply:GetPos():Distance(pos) <= range then
                local trace = util.TraceLine({
                    start = ply:EyePos(), endpos = pos, filter = ply,
                    mask = MASK_VISIBLE,
                })
                if not trace.Hit or trace.Fraction > 0.9 then
                    observers[#observers + 1] = character.id
                end
            end
        end
    end

    if #observers == 0 then return end
    for _, fn in pairs(observerSinks) do
        fn(operation, beat, observers, pos)
    end
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

function Omerta.Crime.Get(id) return live[id] end
function Omerta.Crime.ForBusiness(businessId) return byBusiness[businessId] end

function Omerta.Crime.CooldownRemaining(businessId)
    local until_ = cooldowns[businessId]
    if not until_ then return 0 end
    return math.max(0, until_ - os.time())
end

--------------------------------------------------------------------------------
-- Beginning one
--------------------------------------------------------------------------------

-- Everything the demand is validated against, asked here so the interaction's
-- predicate and its run path cannot drift apart. M20's lesson applies to every
-- step of this milestone: ask at the start AND at completion.
--
-- Returns true, or false + reason.
function Omerta.Crime.CanBegin(ply, business, clerk)
    if not IsValid(ply) then return false, "no actor" end
    local character = Omerta.Characters.Get(ply)
    if not character then return false, "no character" end

    -- A man on the floor is not holding anybody up.
    if Omerta.Injury.IsIncapable(Omerta.Injury.GetByCharacter(character.id)) then
        return false, "you are in no condition"
    end
    if not business then return false, "there is nothing here" end
    if not (IsValid(clerk) and clerk.OmertaClerkAlive ~= false) then
        return false, "there is nobody to threaten"
    end

    local typeDef = Omerta.Business.GetType(business.type_key)
    if not typeDef then return false, "there is nothing here" end

    return Omerta.Crime.IsRobbable(
        typeDef, business,
        Omerta.Business.IsForceable(business.id),
        byBusiness[business.id] ~= nil,
        Omerta.Crime.CooldownRemaining(business.id))
end

-- cb(operation, err)
function Omerta.Crime.Begin(ply, typeKey, business, clerk, cb)
    cb = cb or function() end

    local ok, why = Omerta.Crime.CanBegin(ply, business, clerk)
    if not ok then cb(nil, why) return end

    local typeDef = Omerta.Crime.GetOperationType(typeKey)
    if not typeDef then cb(nil, "there is nothing to do here") return end

    local character = Omerta.Characters.Get(ply)
    local season = Omerta.Seasons.GetActive()
    if not season then cb(nil, "no active season") return end

    local now = os.time()
    local pos = IsValid(clerk) and clerk:GetPos() or ply:GetPos()

    -- THE EVENT IS WRITTEN AT THE DEMAND, NOT AT THE RESOLUTION. A robbery
    -- cannot be hidden by finishing it badly: an operation that is abandoned,
    -- crashed out of or disconnected from has already been recorded.
    Omerta.Events.Create({
        type = "crime.robbery",
        season_id = season.id,
        actor_character_id = character.id,
        pos = pos,
        data = { business = business.id, type = typeKey },
    }, function(eventId, eventErr)
        if not eventId then cb(nil, eventErr or "the city did not notice") return end

        local row = {
            season_id = season.id,
            event_id = eventId,
            type_key = typeKey,
            business_id = business.id,
            state = S.ACTIVE,
            resolution = Omerta.DB.NULL,
            -- Drawn ONCE, here, and never leaving the server. A client that
            -- knew the clerk's seed would know his answer before asking.
            seed = math.random(1, 2147483000),
            map_name = Omerta.InEngine and game.GetMap() or "unknown",
            pos_x = math.floor(pos.x), pos_y = math.floor(pos.y), pos_z = math.floor(pos.z),
            started_at = now,
            state_at = now,
            ended_at = Omerta.DB.NULL,
            deadline_at = Omerta.Crime.DeadlineFor(typeDef, now),
            take_cents = 0,
            data = Omerta.DB.NULL,
        }

        Internal.Repo.Insert(row, function(id, err)
            if not id then cb(nil, err or "it did not happen") return end

            row.id = id
            row.pos = pos
            row.typeDef = typeDef
            row.participants = {}
            row.shotsFired = 0
            row.clearSince = nil
            row.complied = false
            row.clerk = clerk
            -- FURNISHED HERE RATHER THAN BY THE CALLER. The demand path used to
            -- attach the robbery block and the personality after Begin returned,
            -- which left every other way of starting one — the self-test today,
            -- C4's bank later — holding a half-built operation that the take and
            -- the alarm both read fields off.
            row.robbery = Omerta.Crime.RobberyBlock(Omerta.Business.GetType(business.type_key))
            row.personality = Omerta.Crime.GetPersonality(
                IsValid(clerk) and clerk.OmertaPersonality or nil)
                or Omerta.Crime.GetPersonality(row.robbery.clerk.personalities[1])
            row.clerkAlive = true

            live[id] = row
            byBusiness[business.id] = row

            Omerta.Crime.Join(row, character.id)
            Omerta.Log.Audit("crime.began", {
                actor = ply:SteamID64(), subject = business.id,
                data = { operation = id, event = eventId, type = typeKey },
            })
            Omerta.Crime.Observe(row, "demand", pos)
            cb(row)
        end)
    end)
end

--------------------------------------------------------------------------------
-- Who is in the room
--------------------------------------------------------------------------------

function Omerta.Crime.Join(operation, characterId)
    if not (operation and characterId) then return end
    if operation.participants[characterId] then return end
    operation.participants[characterId] = "unknown"
    Internal.Repo.AddParticipant({
        operation_id = operation.id,
        character_id = characterId,
        joined_at = os.time(),
        outcome = "unknown",
    })
    Omerta.Log.Audit("crime.joined", {
        subject = operation.id, data = { character = characterId },
    })
end

function Omerta.Crime.SetOutcome(operation, characterId, outcome)
    if not (operation and characterId) then return end
    if not operation.participants[characterId] then return end
    operation.participants[characterId] = outcome
    Internal.Repo.SetOutcome(operation.id, characterId, outcome)
end

--------------------------------------------------------------------------------
-- Ending one
--------------------------------------------------------------------------------

-- cb(ok, err)
function Omerta.Crime.Resolve(operation, state, resolution, cb)
    cb = cb or function() end
    if not operation then cb(false, "no operation") return end

    if not Omerta.Crime.CanTransition(operation.state, state) then
        -- Loud rather than ignored: an illegal transition is a bug in whoever
        -- asked for it, and swallowing it would leave an operation stuck live.
        Omerta.Log.Error("crime", "refused %s -> %s on operation #%d",
            tostring(operation.state), tostring(state), operation.id or -1)
        cb(false, "that is not a move")
        return
    end

    local now = os.time()
    local terminal = Omerta.Crime.IsTerminal(state)
    operation.state = state
    operation.resolution = resolution
    operation.state_at = now
    if terminal then operation.ended_at = now end

    Internal.Repo.SetState(operation.id, state, resolution, now, terminal and now or nil)
    Omerta.Log.Audit("crime.resolved", {
        subject = operation.id,
        data = {
            state = state, resolution = resolution,
            take = operation.take_cents, business = operation.business_id,
        },
    })

    if terminal then
        -- The outcome per person, not just per job. M17 builds a case out of
        -- this table and "who got away" is the first question it asks.
        if state == S.ESCAPED then
            for characterId, outcome in pairs(operation.participants) do
                if outcome == "unknown" then
                    Omerta.Crime.SetOutcome(operation, characterId, "escaped")
                end
            end
        end

        live[operation.id] = nil
        if byBusiness[operation.business_id] == operation then
            byBusiness[operation.business_id] = nil
        end
        -- The cooldown is a fact about the PREMISES, not about the crew, and it
        -- runs from however the job ended. An abandoned robbery still emptied a
        -- till and still frightened everybody in the room (§13.1).
        cooldowns[operation.business_id] =
            now + Omerta.Config.Get("crime.cooldown_seconds")
        Internal.OnResolved(operation)
    end

    cb(true)
end

--------------------------------------------------------------------------------
-- The clock
--------------------------------------------------------------------------------
-- Everything here is derived from ABSOLUTE timestamps. Nothing counts down, so
-- nothing is reset by a restart — a rule M19 learned twice, and one that here
-- would otherwise make waiting for the nightly restart a robbery technique.

function Internal.TickOperations()
    local now = os.time()
    for _, operation in pairs(live) do
        if Omerta.Crime.HasExpired(operation, now) then
            -- The ceiling. This is what makes the machine total: no operation
            -- can sit open forever holding a clerk in a compliance state that
            -- nobody is present to end.
            Omerta.Crime.Resolve(operation, S.FAILED, Omerta.Crime.RESOLUTION.ABANDONED)
        else
            Internal.TickEscape(operation, now)
            Internal.TickNerve(operation, now)
        end
    end
end

-- Clear of the premises for the configured window, every live participant.
function Internal.TickEscape(operation, now)
    if not Omerta.InEngine then return end

    local anyLive, allClear = false, true
    for characterId in pairs(operation.participants) do
        local ply = Internal.PlayerFor(characterId)
        if IsValid(ply) then
            local down = Omerta.Injury.IsIncapable(Omerta.Injury.GetByCharacter(characterId))
            if not down then
                anyLive = true
                if ply:GetPos():Distance(operation.pos) < operation.typeDef.escapeDistance then
                    allClear = false
                end
            end
        end
    end

    if not anyLive then
        -- Everybody who was in it is on the floor, dead, or gone. The crew
        -- failed; the money is wherever it physically is.
        Omerta.Crime.Resolve(operation, S.FAILED, Omerta.Crime.RESOLUTION.STOPPED)
        return
    end

    if not allClear then
        operation.clearSince = nil
        return
    end

    operation.clearSince = operation.clearSince or now
    if Omerta.Crime.HasEscaped(operation.typeDef, operation.clearSince, now) then
        Omerta.Crime.Resolve(operation, S.ESCAPED, Omerta.Crime.RESOLUTION.CLEAR)
    end
end

-- The nerve-decay beat. Standing in front of a gun does not get calmer, and
-- this is the evaluation that lets a clerk who was complying decide, thirty
-- seconds in, that nobody is watching him after all.
function Internal.TickNerve(operation, now)
    local every = Omerta.Config.Get("crime.nerve_seconds")
    if every <= 0 then return end
    operation.lastNerveAt = operation.lastNerveAt or operation.started_at
    if now - operation.lastNerveAt < every then return end
    operation.lastNerveAt = now
    Internal.Evaluate(operation, "decay")
end

--------------------------------------------------------------------------------
-- The boot path (D-050)
--------------------------------------------------------------------------------
-- Any operation still live at boot resolves to failed/abandoned. The event, the
-- alarm, the participants, the evidence and every physical proceed already
-- moved are preserved; the LIVE SCENE is not restored.
--
-- This is safe for one specific reason and it is the design paying off:
-- PHYSICAL PROCEEDS MEAN THERE IS NOTHING TO RECONCILE. If the take were a
-- balance change, an abandoned operation would need a rollback and a rollback
-- would need a rule about half-completed thefts. Because the money is items, an
-- interrupted robbery is just some notes that moved. Nothing is owed to anybody.
--
-- M19's precedent cuts the same way: a restart must not heal anybody, and it
-- must not launder anything either.
function Internal.ResolveOrphans()
    Internal.Repo.Live(function(rows)
        for _, row in ipairs(rows) do
            Internal.Repo.SetState(row.id, S.FAILED, Omerta.Crime.RESOLUTION.ABANDONED,
                os.time(), os.time())
            Omerta.Log.Audit("crime.abandoned", {
                subject = row.id,
                data = {
                    reason = "restart", business = row.business_id,
                    -- Recorded because it is the interesting number: what the
                    -- crew got away with before the lights went out, which is
                    -- still in somebody's pockets and is not being taken back.
                    take = row.take_cents,
                },
            })
        end
        if #rows > 0 then
            Omerta.Log.Info("crime", "%d operation(s) abandoned across the restart", #rows)
        end
    end)
end

function Internal.PlayerFor(characterId)
    if not Omerta.InEngine then return nil end
    for _, ply in ipairs(player.GetAll()) do
        local character = Omerta.Characters.Get(ply)
        if character and character.id == characterId then return ply end
    end
    return nil
end
