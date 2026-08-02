-- In-engine acceptance suite: `omerta_crime_selftest`.
--
-- Builds a synthetic store with a synthetic clerk and a stocked register, then
-- drives the whole loop: demand, comply, take, escape — and asserts the thing
-- the headless suite structurally cannot, which is that THE TILL IS LIGHTER BY
-- PRECISELY WHAT THE ROBBER IS HEAVIER BY.
--
-- Everything it builds, it takes back out again.

if not Omerta.InEngine then return end

local S = Omerta.Crime.STATE

-- A robbery needs a robber, and there is no synthesising one: the whole loop is
-- range checks, inventories and pockets. So the suite asks for a real player and
-- says so plainly when there is not one, rather than half-running.
local function anyPlayer()
    for _, ply in ipairs(player.GetAll()) do
        if Omerta.Characters.Get(ply) then return ply end
    end
    return nil
end

local function buildSteps()
    local Internal = Omerta.Crime.Internal
    local business, clerk, operation = nil, nil, nil
    local steps = {}

    steps[#steps + 1] = { name = "database and season ready", required = true, fn = function(pass, fail)
        if not Omerta.DB.IsReady() then fail("db phase=" .. Omerta.DB.Status().phase) return end
        if not Omerta.Seasons.GetActive() then fail("no active season") return end
        pass()
    end }

    steps[#steps + 1] = { name = "the personalities are three different men", fn = function(pass, fail)
        local all = Omerta.Crime.Personalities()
        if #all < 3 then fail("only " .. #all .. " personalities") return end
        for _, who in ipairs(all) do
            for _, field in ipairs({ "nerve", "compliance", "duty", "alarmAppetite" }) do
                if type(who[field]) ~= "number" then
                    fail(who.id .. " has no " .. field) return
                end
            end
        end
        pass(#all .. " clerks")
    end }

    -- Every venue's declared personalities must actually exist. A typo here
    -- produces a clerk who falls back to the old hand and a shop that is
    -- quietly the wrong shop forever.
    steps[#steps + 1] = { name = "every venue names clerks that exist", fn = function(pass, fail)
        for _, typeDef in ipairs(Omerta.Business.GetTypes()) do
            local block = Omerta.Crime.RobberyBlock(typeDef)
            for _, id in ipairs(block.clerk.personalities) do
                if not Omerta.Crime.GetPersonality(id) then
                    fail(typeDef.key .. " wants a '" .. id .. "' who does not exist") return
                end
            end
            local tool = (block.register or {}).forceTool
            if tool and not Omerta.Items.Get(tool) then
                fail(typeDef.key .. " is levered with a nonexistent '" .. tool .. "'") return
            end
        end
        pass()
    end }

    steps[#steps + 1] = { name = "a store, unowned, with a clerk", required = true, fn = function(pass, fail)
        local here = Vector(0, 0, 0)
        Omerta.Business.Create("store", "Selftest Grocer", {}, here,
            { unowned = true }, function(created, err)
                if not created then fail(tostring(err)) return end
                business = created
                clerk = Omerta.Crime.SpawnClerk(business, here + Vector(48, 0, 0))
                if not IsValid(clerk) then fail("no clerk") return end
                pass("business #" .. business.id .. ", " .. tostring(clerk.OmertaPersonality))
            end)
    end }

    -- D-048, in the world rather than in the pure function: the float only
    -- reaches a register nobody owns.
    steps[#steps + 1] = { name = "the float fills an unowned register", fn = function(pass, fail)
        local till = Omerta.Business.Till(business.id)
        Omerta.Money.Give(till, 40000, function(ok, err)
            if not ok then fail(tostring(err)) return end

            local perHour = Omerta.Crime.FloatTerms(
                Omerta.Business.GetType("store"), business)
            if perHour <= 0 then fail("an unowned store should accrue") return end

            -- And the moment it is owned, D-032 takes it back.
            local owned = { id = business.id, type_key = "store", owner_character_id = 1 }
            if Omerta.Crime.FloatTerms(Omerta.Business.GetType("store"), owned) ~= 0 then
                fail("an owned store must not accrue") return
            end
            pass(Omerta.Money.Format(Omerta.Money.Count(till)) .. " in the register")
        end)
    end }

    steps[#steps + 1] = { name = "the operation opens with an event behind it", required = true, fn = function(pass, fail)
        local ply = anyPlayer()
        if not IsValid(ply) then fail("run this from in-game: a robbery needs a robber") return end

        Omerta.Crime.Begin(ply, "robbery.store", business, clerk, function(created, err)
            if not created then fail(tostring(err)) return end
            operation = created
            if not operation.event_id then fail("no event was written") return end
            if operation.state ~= S.ACTIVE then fail("state " .. operation.state) return end
            if not operation.personality then fail("no clerk personality attached") return end
            if not operation.robbery then fail("no robbery block attached") return end
            pass("operation #" .. operation.id .. " on event #" .. operation.event_id)
        end)
    end }

    -- The whole point of the milestone, asserted as arithmetic.
    steps[#steps + 1] = { name = "the till is lighter by what the robber is heavier by", fn = function(pass, fail)
        local ply = anyPlayer()
        local till = Omerta.Business.Till(business.id)
        local tillBefore = Omerta.Money.Count(till)
        local pocketBefore = Omerta.Money.Count(ply)

        operation.registerOpen = true
        Internal.MoveHandful(ply, operation, function(ok, err)
            if not ok then fail(tostring(err)) return end

            local moved = tillBefore - Omerta.Money.Count(till)
            local gained = Omerta.Money.Count(ply) - pocketBefore
            if moved <= 0 then fail("nothing left the register") return end
            if moved ~= gained then
                -- If these ever disagree, money was created or destroyed, and
                -- that is the one failure M9 was built to make impossible.
                fail(string.format("the till lost %s and the coat gained %s",
                    Omerta.Money.Format(moved), Omerta.Money.Format(gained)))
                return
            end
            if operation.take_cents ~= moved then
                fail("the recorded take disagrees with the money that moved") return
            end
            pass(Omerta.Money.Format(moved) .. " moved, nothing minted")
        end)
    end }

    -- D-052: the register does not seal when the man beside it dies.
    steps[#steps + 1] = { name = "a dead clerk does not lock the register", fn = function(pass, fail)
        local ply = anyPlayer()
        operation.clerkDead = true
        operation.clerkAlive = false
        operation.registerOpen = true

        local till = Omerta.Business.Till(business.id)
        if Omerta.Money.Count(till) <= 0 then
            Omerta.Money.Give(till, 20000, function() end)
        end

        Internal.MoveHandful(ply, operation, function(ok, err)
            if not ok then
                fail("the money should still come out: " .. tostring(err)) return
            end
            pass("it still empties")
        end)
    end }

    steps[#steps + 1] = { name = "an alarm is one row, and nobody is told", fn = function(pass, fail)
        Omerta.Crime.RaiseAlarm({
            operation_id = operation.id,
            source = Omerta.Crime.ALARM_SOURCE.BUTTON,
            severity = 2, pos = operation.pos,
        }, function(alarmId, err)
            if not alarmId then fail(tostring(err)) return end
            Internal.Repo.AlarmsFor(operation.id, function(rows)
                if #rows ~= 1 then fail(#rows .. " alarm rows, expected 1") return end
                if rows[1].responded_at ~= nil then
                    fail("responded_at should be M16's to fill") return
                end
                pass("alarm #" .. alarmId .. ", unanswered")
            end)
        end)
    end }

    -- No client was told anything at any point. Stated as an assertion about
    -- the wire rather than as a comment, because this is the line the whole
    -- information design stands on.
    steps[#steps + 1] = { name = "the milestone added no client-facing message", fn = function(pass, fail)
        for name, def in pairs(Omerta.Net.GetRegistry()) do
            if name:find("^crime%.") then
                fail("crime registered a net message: " .. name) return
            end
        end
        pass("nothing about a robbery reaches a screen")
    end }

    steps[#steps + 1] = { name = "it resolves, and the premises goes quiet", fn = function(pass, fail)
        Omerta.Crime.Resolve(operation, S.ESCAPED, Omerta.Crime.RESOLUTION.CLEAR,
            function(ok, err)
                if not ok then fail(tostring(err)) return end
                if Omerta.Crime.ForBusiness(business.id) then
                    fail("the operation is still live on the premises") return
                end
                if Omerta.Crime.CooldownRemaining(business.id) <= 0 then
                    fail("no cooldown was set") return
                end
                -- And a second robbery inside the cooldown is refused.
                local can = Omerta.Crime.IsRobbable(
                    Omerta.Business.GetType("store"), business, true, false,
                    Omerta.Crime.CooldownRemaining(business.id))
                if can then fail("the same shop was robbable again immediately") return end
                pass("escaped, and shut for now")
            end)
    end }

    -- D-050, simulated: a live operation meets a restart. The row ends
    -- abandoned and everything physical stays exactly where it physically is.
    steps[#steps + 1] = { name = "a restart abandons rather than resumes", fn = function(pass, fail)
        local ply = anyPlayer()
        local pocketBefore = Omerta.Money.Count(ply)

        Internal.Cooldowns[business.id] = nil
        Omerta.Crime.Begin(ply, "robbery.store", business, clerk, function(created, err)
            if not created then fail(tostring(err)) return end
            local id = created.id

            -- The boot path, run against a row that is still live.
            Internal.Live[id] = nil
            Internal.Cooldowns[business.id] = nil
            Omerta.Crime.Internal.ResolveOrphans()

            timer.Simple(0.5, function()
                Internal.Repo.Get(id, function(row)
                    if not row then fail("the operation vanished") return end
                    if row.state ~= S.FAILED then
                        fail("state " .. tostring(row.state) .. ", expected failed") return
                    end
                    if row.resolution ~= Omerta.Crime.RESOLUTION.ABANDONED then
                        fail("resolution " .. tostring(row.resolution)) return
                    end
                    if not row.event_id then fail("the event was lost") return end
                    -- NOTHING TO RECONCILE. The proceeds are physical, so an
                    -- abandoned robbery is just some notes that moved.
                    if Omerta.Money.Count(ply) ~= pocketBefore then
                        fail("the restart moved money") return
                    end
                    pass("abandoned, event kept, pockets untouched")
                end)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "cleanup", required = true, fn = function(pass, fail)
        local till = Omerta.Business.Till(business.id)
        local stock = Omerta.Business.Stock(business.id)

        if IsValid(clerk) then clerk:Remove() end
        Omerta.Crime.Internal.Clerks[business.id] = nil
        Omerta.Crime.Internal.Cooldowns[business.id] = nil
        for id, live in pairs(Omerta.Crime.Internal.Live) do
            if live.business_id == business.id then
                Omerta.Crime.Internal.Live[id] = nil
            end
        end

        Omerta.Money.Take(till, Omerta.Money.Count(till), function()
            Omerta.Business.Internal.Repo.Delete(business.id, function()
                if IsValid(business.counter) then business.counter:Remove() end
                if IsValid(business.stockEntity) then business.stockEntity:Remove() end
                Omerta.Business.Internal.Businesses[business.id] = nil
                Omerta.Inventory.Unload(till)
                Omerta.Inventory.Unload(stock)
                pass()
            end)
        end)
    end }

    return steps
end

concommand.Add("omerta_crime_selftest", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    Omerta.SelfTest.Run("crime.selftest", buildSteps())
end)
