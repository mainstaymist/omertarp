-- The demand, the register, and the handful.
--
-- M14 ADDS NO CLIENT → SERVER MESSAGE AT ALL. Every action a player takes in a
-- robbery is already somebody else's registered mechanism: the demand is an M5
-- interaction on the clerk, opening the register is an M5 interaction, taking
-- the money is the promoted timed action, and carrying it is M9. There is
-- nothing new for a client to send and therefore nothing new to validate.

Omerta.Crime = Omerta.Crime or {}
Omerta.Crime.Internal = Omerta.Crime.Internal or {}
local Internal = Omerta.Crime.Internal
local S = Omerta.Crime.STATE

--------------------------------------------------------------------------------
-- The demand
--------------------------------------------------------------------------------

function Internal.HandleUse(ply, clerk)
    Internal.Demand(ply, clerk)
end

function Internal.Demand(ply, clerk)
    if not (IsValid(clerk) and clerk.OmertaBusiness) then return end
    local business = Omerta.Business.Get(clerk.OmertaBusiness)
    if not business then return end

    local existing = Omerta.Crime.ForBusiness(business.id)
    if existing then
        -- Already happening. Walking in behind somebody else's demand makes you
        -- part of it — which is what the participants table is for, and what
        -- M17 will build a case out of.
        local character = Omerta.Characters.Get(ply)
        if character then Omerta.Crime.Join(existing, character.id) end
        Internal.Evaluate(existing, "entry")
        return
    end

    Omerta.Crime.Begin(ply, "robbery.store", business, clerk, function(operation, err)
        if not operation then
            if err then Omerta.Chat.Notice(ply, err) end
            return
        end

        Internal.Evaluate(operation, "demand")
    end)
end

--------------------------------------------------------------------------------
-- A shot changes the room
--------------------------------------------------------------------------------
-- W0's hook, consumed rather than reimplemented. This is the beat that makes a
-- warning shot a mistake: it raises pressure by a third of a gun and, past his
-- nerve, the personality's weights stop applying entirely.

function Internal.OnWeaponFired(ply, weaponId)
    if not IsValid(ply) then return end
    local character = Omerta.Characters.Get(ply)
    if not character then return end

    for _, operation in pairs(Internal.Live) do
        if operation.participants[character.id] then
            operation.shotsFired = (operation.shotsFired or 0) + 1
            Internal.Evaluate(operation, "shot." .. tostring(operation.shotsFired))
            Omerta.Crime.Observe(operation, "shot", ply:GetPos())
        end
    end
end

--------------------------------------------------------------------------------
-- Opening the register
--------------------------------------------------------------------------------

function Internal.RegisterInteractions()
    -- Holding him up. The verb the whole milestone hangs off, and it is an M5
    -- interaction like every other verb in the game.
    Omerta.Interaction.Register("crime.demand", {
        label = "Hold up", range = 128, order = 20, default = true,
        predicate = function(ply, target)
            if not (IsValid(target) and target.OmertaBusiness) then return false end
            if target:GetClass() ~= "omerta_clerk" then return false end
            local business = Omerta.Business.Get(target.OmertaBusiness)
            if not business then return false end
            if Omerta.Crime.ForBusiness(business.id) then return false end
            return Omerta.Crime.CanBegin(ply, business, target) == true
        end,
        run = function(ply, target) Internal.Demand(ply, target) end,
    })

    -- Emptying it. Registered on the COUNTER rather than the clerk, because the
    -- money is in the counter and a robbery where the second man works the till
    -- while the first holds the gun is the two-player scene this milestone
    -- exists to produce.
    -- DEFAULT, and ordered ahead of business.open on purpose. Both are
    -- registered on the counter and both are the E press; during a robbery the
    -- obvious thing to do at a till is empty it, not ask the shop what it
    -- sells. Their predicates are mutually exclusive with each other, so only
    -- the ordering against business.open matters.
    Omerta.Interaction.Register("crime.take", {
        label = "Empty the register", range = 96, order = 21, default = true,
        predicate = function(ply, target)
            local operation = Internal.OperationAtCounter(target)
            if not operation then return false end
            if not operation.registerOpen then return false end
            return true
        end,
        run = function(ply, target)
            Internal.Grab(ply, Internal.OperationAtCounter(target))
        end,
    })

    -- Levering it, when he would not open it. The crowbar W0 §6 left an object
    -- "until M14 wants it swung" — and M14 does not want it swung, it wants it
    -- LEVERED, which is a tool in a timed action rather than a melee base.
    Omerta.Interaction.Register("crime.force", {
        label = "Force the register", range = 96, order = 22, default = true,
        predicate = function(ply, target)
            local operation = Internal.OperationAtCounter(target)
            if not operation then return false end
            if operation.registerOpen then return false end
            local tool = (operation.robbery.register or {}).forceTool
            if not tool then return false end
            return Internal.HasItem(ply, tool)
        end,
        run = function(ply, target)
            Internal.Force(ply, Internal.OperationAtCounter(target))
        end,
    })
end

function Internal.OperationAtCounter(target)
    if not IsValid(target) then return nil end
    local businessId = target.OmertaBusiness
    if not businessId then return nil end
    local operation = Omerta.Crime.ForBusiness(businessId)
    if not operation then return nil end
    if not Omerta.Crime.IsLive(operation.state) then return nil end
    return operation
end

function Internal.HasItem(ply, itemId)
    for _, row in ipairs(Omerta.Inventory.Get(ply) or {}) do
        if row.def_id == itemId then return true end
    end
    return false
end

function Internal.Force(ply, operation)
    if not operation then return end
    local seconds = (operation.robbery.register or {}).forceSeconds or 22

    Omerta.Action.Begin(ply, {
        id = "crime.force", label = "Levering the register", duration = seconds,
        sound = Omerta.Action.PROMPT_SOUND.RUSTLE,
        -- M20's lesson applied to every step: ask at the start AND at
        -- completion. A robbery that ended while somebody was still working the
        -- crowbar must not pay out when the clock runs down.
        stillValid = function()
            if not Omerta.Crime.IsLive(operation.state) then
                return false, "it is over"
            end
            return true
        end,
        onComplete = function(actor, entry, done)
            operation.registerOpen = true
            operation.forced = true
            Omerta.Crime.Observe(operation, "forced", operation.pos)
            Omerta.Log.Audit("crime.forced", {
                actor = actor:SteamID64(), subject = operation.id,
            })
            done(true)
        end,
    }, function(ok, err)
        if not ok and err then Omerta.Chat.Notice(ply, err) end
    end)
end

--------------------------------------------------------------------------------
-- The handful
--------------------------------------------------------------------------------
-- A HANDFUL AT A TIME, and the reason is mechanical rather than aesthetic:
-- Money.Pay is all-or-nothing and refuses on capacity, so a robber whose pockets
-- are half full would otherwise get NOTHING.
--
-- It is also better in every direction. It puts the time in front of the
-- frightened man where the scene needs it, it makes interrupting a robbery
-- mid-take mean something, and it makes the second robber genuinely useful
-- rather than decorative.

function Internal.Grab(ply, operation)
    if not operation then return end
    if not operation.registerOpen then
        Omerta.Chat.Notice(ply, "it is shut")
        return
    end

    local seconds = (operation.robbery.register or {}).openSeconds or 4

    Omerta.Action.Begin(ply, {
        id = "crime.take", label = "Emptying the register", duration = seconds,
        sound = Omerta.Action.PROMPT_SOUND.RUSTLE,
        stillValid = function()
            if not Omerta.Crime.IsLive(operation.state) then
                return false, "it is over"
            end
            if not operation.registerOpen then return false, "it is shut" end
            return true
        end,
        onComplete = function(actor, entry, done)
            Internal.MoveHandful(actor, operation, done)
        end,
    }, function(ok, err)
        if not ok and err then Omerta.Chat.Notice(ply, err) end
    end)
end

function Internal.MoveHandful(ply, operation, done)
    done = done or function() end

    local source = Omerta.Crime.GetTakeSource(operation.typeDef.takeSource)
    if not source then done(false, "there is nothing here") return end

    local container = source.container(operation)
    if not container then done(false, "there is nothing here") return end

    local available = Omerta.Money.Count(container)
    if available <= 0 then
        done(false, "there is nothing left in it")
        return
    end

    local handful = Omerta.Money.Round(Omerta.Config.Get("crime.handful_cents"))
    local amount = Omerta.Crime.PlanGrab(available, handful, function(cents)
        return Omerta.Money.HasRoomFor(ply, cents) == true
    end)

    if amount <= 0 then
        -- BULK IS THE ANTI-EXPLOIT (D-020). A man with a Thompson across his
        -- back cannot pocket four hundred dollars in quarters — which is not a
        -- limitation to work around, it is the reason a big score needs a bag,
        -- a second man, or several trips in front of a frightened witness.
        done(false, "you cannot carry any more")
        return
    end

    -- M13's unauthorised half, and the same transactional path a sale uses.
    -- There is no mint here, so M9's duplication protections cover the robbery
    -- unchanged and without being told about it.
    Omerta.Business.EmptyTill(operation.business_id, ply, amount, function(ok, err)
        if not ok then done(false, err or "it would not come out") return end

        Omerta.Crime.Internal.Repo.AddTake(operation.id, amount)
        operation.take_cents = (operation.take_cents or 0) + amount

        Omerta.Log.Audit("crime.took", {
            actor = ply:SteamID64(), subject = operation.id,
            data = { cents = amount, business = operation.business_id },
        })
        Omerta.Crime.Observe(operation, "take", operation.pos)
        -- Deliberately NOT announced. You learn what you got by counting it in
        -- your inventory, exactly as D-018 and M9 already require of every
        -- other cent in the game.
        done(true)
    end)
end

--------------------------------------------------------------------------------
-- Where the money is
--------------------------------------------------------------------------------

function Internal.RegisterTakeSources()
    Omerta.Crime.RegisterTakeSource("business.till", {
        container = function(operation)
            return Omerta.Business.Till(operation.business_id)
        end,
    })
end
