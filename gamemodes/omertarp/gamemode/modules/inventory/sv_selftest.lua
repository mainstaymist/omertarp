-- In-engine acceptance suite: `omerta_inventory_selftest`.
--
-- Drives the whole milestone against synthetic owners: items in and out,
-- capacity refusal, what is worn costing nothing, the over-capacity state and
-- both of its consequences, a move between two owners, money given and spent
-- with change, hunger persisted, and a deliberately broken write proving that
-- a failed change leaves nothing behind. Cleans up after itself.

if not Omerta.InEngine then return end

-- Deliberately out of range of any real character or container id.
local FAKE_CHARACTER = 2000000002
local FAKE_CONTAINER = 2000000003

local CHAR = { type = "character", id = FAKE_CHARACTER }
local BOX = { type = "container", id = FAKE_CONTAINER }

local function buildSteps()
    local Internal = Omerta.Inventory.Internal
    local Repo = Internal.Repo
    local steps = {}

    steps[#steps + 1] = { name = "database and season ready", required = true, fn = function(pass, fail)
        if not Omerta.DB.IsReady() then fail("db phase=" .. Omerta.DB.Status().phase) return end
        if not Omerta.Seasons.GetActive() then fail("no active season") return end
        pass()
    end }

    steps[#steps + 1] = { name = "leftover cleanup from aborted runs", required = true,
        fn = function(pass, fail)
        Repo.DeleteForOwner(CHAR.type, CHAR.id, function(ok, err)
            if not ok then fail(tostring(err)) return end
            Repo.DeleteForOwner(BOX.type, BOX.id, function(ok2, err2)
                if not ok2 then fail(tostring(err2)) return end
                Repo.DeleteNeeds(FAKE_CHARACTER, function(ok3, err3)
                    if not ok3 then fail(tostring(err3)) return end
                    Omerta.Inventory.RegisterContainer(FAKE_CONTAINER, { capacity = 100 })
                    Omerta.Inventory.Load(CHAR, function()
                        Omerta.Inventory.Load(BOX, function() pass() end)
                    end)
                end)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "the item registry is populated and coherent", fn = function(pass, fail)
        for _, denom in ipairs(Omerta.Money.DENOMINATIONS) do
            if not Omerta.Items.Get(denom.item) then
                fail("no item for denomination " .. denom.cents) return
            end
        end
        local thompson = Omerta.Items.Get("weapon.thompson")
        if not thompson then fail("weapon.thompson is missing") return end
        if thompson.concealable then fail("a Thompson must not be concealable") return end

        -- Indices must round-trip, or the wire carries the wrong item.
        local list = Omerta.Items.GetOrdered()
        for i, def in ipairs(list) do
            if Omerta.Items.GetByIndex(i) ~= def then fail("index mismatch at " .. i) return end
            if Omerta.Items.IndexOf(def.id) ~= i then fail("IndexOf disagrees for " .. def.id) return end
        end
        pass(#list .. " items registered")
    end }

    steps[#steps + 1] = { name = "items are added, stacked and read back", fn = function(pass, fail)
        Omerta.Inventory.Add(CHAR, "misc.cigarettes", 3, nil, function(ok, err)
            if not ok then fail(tostring(err)) return end
            -- A second add of a stackable item must top up the first stack
            -- rather than open a new one.
            Omerta.Inventory.Add(CHAR, "misc.cigarettes", 2, nil, function(ok2, err2)
                if not ok2 then fail(tostring(err2)) return end
                local rows = Omerta.Inventory.Get(CHAR)
                if #rows ~= 1 then fail("expected 1 stack, got " .. #rows) return end
                if rows[1].quantity ~= 5 then
                    fail("expected a stack of 5, got " .. tostring(rows[1].quantity)) return
                end
                pass("one stack of 5")
            end)
        end)
    end }

    steps[#steps + 1] = { name = "capacity is enforced before anything is written", fn = function(pass, fail)
        -- A Thompson is bulk 22 against a base capacity of 20: it does not go
        -- in a pocket, which is the design's own worked example.
        Omerta.Inventory.Add(CHAR, "weapon.thompson", 1, nil, function(ok, err)
            if ok then fail("a Thompson should not fit in bare pockets") return end
            local rows = Omerta.Inventory.Get(CHAR)
            if #rows ~= 1 then fail("the refusal wrote something anyway: " .. #rows .. " rows") return end

            -- With a coat on, it does. Capacity is a consequence of what you
            -- are wearing, not a constant.
            Omerta.Inventory.Add(CHAR, "clothing.overcoat", 1, nil, function(ok2, err2)
                if not ok2 then fail(tostring(err2)) return end
                local coat
                for _, row in ipairs(Omerta.Inventory.Get(CHAR)) do
                    if row.def_id == "clothing.overcoat" then coat = row end
                end
                if not coat then fail("the coat is missing") return end
                local carriedWithCoatInHand = Omerta.Inventory.BulkUsed(CHAR)

                Omerta.Inventory.Equip(CHAR, coat.id, function(eok, eerr)
                    if not eok then fail("equip: " .. tostring(eerr)) return end

                    local limit = Omerta.Inventory.BulkLimit(CHAR)
                    local expected = (Omerta.Config.Get("inventory.base_capacity") + 12)
                        * Omerta.Inventory.BULK_SCALE
                    if limit ~= expected then
                        fail("coat gave " .. limit .. ", expected " .. expected) return
                    end

                    -- WHAT IS WORN COSTS NOTHING. Putting the coat on both
                    -- raised the limit by its 12 and dropped what is carried
                    -- by its own 4, and the second half is the one an
                    -- assertion about capacity alone would never notice.
                    local carriedWorn = Omerta.Inventory.BulkUsed(CHAR)
                    local coatBulk = Omerta.Inventory.UnitBulk(
                        Omerta.Items.Get("clothing.overcoat"))
                    if carriedWorn ~= carriedWithCoatInHand - coatBulk then
                        fail(string.format(
                            "wearing the coat should have shed %d of carried bulk: %d -> %d",
                            coatBulk, carriedWithCoatInHand, carriedWorn))
                        return
                    end

                    Omerta.Inventory.Add(CHAR, "weapon.thompson", 1, nil, function(ok3, err3)
                        if not ok3 then fail("with a coat on: " .. tostring(err3)) return end
                        pass("refused bare, accepted with a coat, and the coat is free")
                    end)
                end)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "an item moves between owners exactly once", fn = function(pass, fail)
        local thompson
        for _, row in ipairs(Omerta.Inventory.Get(CHAR)) do
            if row.def_id == "weapon.thompson" then thompson = row end
        end
        if not thompson then fail("no Thompson to move") return end

        Omerta.Inventory.Move(thompson.id, BOX, function(ok, err)
            if not ok then fail(tostring(err)) return end

            local mine, theirs = Omerta.Inventory.Get(CHAR), Omerta.Inventory.Get(BOX)
            for _, row in ipairs(mine) do
                if row.id == thompson.id then fail("it is still in the character's hands") return end
            end
            local found = false
            for _, row in ipairs(theirs) do
                if row.id == thompson.id then found = true end
            end
            if not found then fail("it never arrived in the container") return end

            -- The same move again must fail: an item that has already moved
            -- cannot move a second time, which is what prevents duplication.
            Omerta.Inventory.Move(thompson.id, BOX, function(ok2, err2)
                if ok2 then fail("a repeated move was allowed") return end
                pass("moved once, refused twice")
            end)
        end)
    end }

    -- Taking a coat off is the one move that can put somebody over, because it
    -- removes 12 of capacity and adds 4 of carried bulk at once. What follows
    -- has to be true or the state is a trap: nothing else goes in, and
    -- everything still comes out.
    steps[#steps + 1] = { name = "over the limit refuses a pick-up and permits a drop",
        fn = function(pass, fail)
        local coat, thompson
        for _, row in ipairs(Omerta.Inventory.Get(CHAR)) do
            if row.def_id == "clothing.overcoat" then coat = row end
        end
        for _, row in ipairs(Omerta.Inventory.Get(BOX)) do
            if row.def_id == "weapon.thompson" then thompson = row end
        end
        if not (coat and thompson) then fail("the coat or the Thompson is missing") return end
        if not coat.equipped_slot then fail("the coat should still be worn") return end

        -- Back into the coat's pockets, which is where the previous step left
        -- it fitting.
        Omerta.Inventory.Move(thompson.id, CHAR, function(mok, merr)
            if not mok then fail("taking the Thompson back: " .. tostring(merr)) return end

            Omerta.Inventory.Unequip(CHAR, coat.id, function(uok, uerr)
                -- The unequip GOES THROUGH. Refusing it would let a full
                -- inventory weld clothing on.
                if not uok then fail("the coat refused to come off: " .. tostring(uerr)) return end
                if not Omerta.Inventory.Overloaded(CHAR) then
                    fail(string.format("expected to be over: %d carried against %d",
                        Omerta.Inventory.BulkUsed(CHAR), Omerta.Inventory.BulkLimit(CHAR)))
                    return
                end

                local speed = Omerta.Inventory.OverloadSpeed(CHAR)
                if not (speed < 1 and speed > 0) then
                    fail("the movement penalty is " .. tostring(speed)) return
                end

                -- Nothing else goes in, however small — a newspaper is 0.3.
                Omerta.Inventory.Add(CHAR, "misc.newspaper", 1, nil, function(aok, aerr)
                    if aok then fail("an overloaded character picked something up") return end
                    if not (aerr and string.find(aerr, "carrying too much", 1, true)) then
                        fail("refused for the wrong reason: " .. tostring(aerr)) return
                    end

                    -- And everything still comes out. If this ever fails the
                    -- state is inescapable and the ruling is a bug.
                    Omerta.Inventory.Move(thompson.id, BOX, function(dok, derr)
                        if not dok then fail("could not put it down: " .. tostring(derr)) return end
                        if Omerta.Inventory.Overloaded(CHAR) then
                            fail("still over after putting the Thompson down") return
                        end
                        if Omerta.Inventory.OverloadSpeed(CHAR) ~= 1 then
                            fail("the penalty outlived the load") return
                        end
                        pass("refused a newspaper, allowed the Thompson back out")
                    end)
                end)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "money is given, counted and spent with change", fn = function(pass, fail)
        Omerta.Money.Give(CHAR, 1000, function(ok, err)
            if not ok then fail(tostring(err)) return end
            local total = Omerta.Money.Count(CHAR)
            if total ~= 1000 then fail("expected $10.00, got " .. Omerta.Money.Format(total)) return end
            if Omerta.Money.CountCoins(CHAR, 500) ~= 2 then
                fail("$10 should be two five-dollar notes") return
            end

            -- $7.25 out of two fives: they cannot pay it exactly, so they hand
            -- over both and take change. The NET cost has to be exact.
            Omerta.Money.Take(CHAR, 725, function(tok, terr, change)
                if not tok then fail(tostring(terr)) return end
                local left = Omerta.Money.Count(CHAR)
                if left ~= 275 then
                    fail("expected $2.75 left, got " .. Omerta.Money.Format(left)) return
                end
                if change ~= 275 then
                    fail("expected $2.75 change, got " .. Omerta.Money.Format(change)) return
                end
                -- And the quarter the payphone will ask for is really there.
                if Omerta.Money.CountCoins(CHAR, 25) ~= 3 then
                    fail("change should include three quarters") return
                end
                pass("paid $7.25 from two fives, $2.75 back")
            end)
        end)
    end }

    steps[#steps + 1] = { name = "a failed write changes nothing", fn = function(pass, fail)
        local before = #Omerta.Inventory.Get(CHAR)
        -- A row missing its mandatory columns: the transaction builder refuses
        -- it, so neither this insert nor the valid one beside it happens.
        Repo.ApplyChanges({}, {
            { def_id = "misc.newspaper", season_id = Omerta.Seasons.GetActive().id,
              owner_type = CHAR.type, owner_id = CHAR.id, quantity = 1,
              created_at = os.time() },
            { def_id = "misc.newspaper" },
        }, function(ok)
            if ok then fail("a malformed transaction reported success") return end
            Omerta.Inventory.Load(CHAR, function()
                local after = #Omerta.Inventory.Get(CHAR)
                if after ~= before then
                    fail("rows changed from " .. before .. " to " .. after) return
                end
                pass("nothing was written")
            end)
        end)
    end }

    steps[#steps + 1] = { name = "hunger persists and reads back", fn = function(pass, fail)
        -- 30 is below HUNGRY_BELOW (40) and above STARVING_BELOW (15), so it
        -- exercises the middle state rather than a boundary.
        Repo.SaveNeeds(FAKE_CHARACTER, 30, os.time(), function(ok, err)
            if not ok then fail(tostring(err)) return end
            Repo.GetNeeds(FAKE_CHARACTER, function(row, gerr)
                if gerr then fail(tostring(gerr)) return end
                if not row then fail("no needs row was written") return end
                if row.hunger ~= 30 then fail("read back " .. tostring(row.hunger)) return end
                if Omerta.Hunger.State(30) ~= Omerta.Hunger.STATE.HUNGRY then
                    fail("30 should read as hungry") return
                end
                if Omerta.Hunger.State(50) ~= Omerta.Hunger.STATE.FED then
                    fail("50 should read as fed") return
                end
                if Omerta.Hunger.State(9) ~= Omerta.Hunger.STATE.STARVING then
                    fail("9 should read as starving") return
                end
                pass("stored 30, hungry but not starving")
            end)
        end)
    end }

    steps[#steps + 1] = { name = "cleanup", always = true, fn = function(pass, fail)
        Repo.DeleteForOwner(CHAR.type, CHAR.id, function(ok, err)
            if not ok then fail(tostring(err)) return end
            Repo.DeleteForOwner(BOX.type, BOX.id, function(ok2, err2)
                if not ok2 then fail(tostring(err2)) return end
                Repo.DeleteNeeds(FAKE_CHARACTER, function(ok3, err3)
                    if not ok3 then fail(tostring(err3)) return end
                    Omerta.Inventory.Unload(CHAR)
                    Omerta.Inventory.Unload(BOX)
                    pass()
                end)
            end)
        end)
    end }

    return steps
end

concommand.Add("omerta_inventory_selftest", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    Omerta.SelfTest.Run("inventory.selftest", buildSteps())
end)
