-- In-engine acceptance suite: `omerta_business_selftest`.
--
-- Builds a synthetic speakeasy, stocks it, sells a drink into the till,
-- empties the register, and puts a rumour into circulation — then takes it all
-- back out again.

if not Omerta.InEngine then return end

local FAKE_CHARACTER = 2300000001

local function buildSteps()
    local Internal = Omerta.Business.Internal
    local Repo = Internal.Repo
    local business = nil
    local steps = {}

    steps[#steps + 1] = { name = "database and season ready", required = true, fn = function(pass, fail)
        if not Omerta.DB.IsReady() then fail("db phase=" .. Omerta.DB.Status().phase) return end
        if not Omerta.Seasons.GetActive() then fail("no active season") return end
        pass()
    end }

    steps[#steps + 1] = { name = "the venue types are coherent", fn = function(pass, fail)
        local types = Omerta.Business.GetTypes()
        if #types < 1 then fail("no business types are defined") return end
        for _, def in ipairs(types) do
            for _, entry in ipairs(def.sells) do
                if not Omerta.Items.Get(entry.item) then
                    fail(def.key .. " sells a missing item: " .. tostring(entry.item)) return
                end
                if entry.price % Omerta.Money.SMALLEST ~= 0 then
                    fail(def.key .. " prices " .. entry.item .. " in coins that do not exist")
                    return
                end
            end
        end
        if not Omerta.Business.GetType("speakeasy") then fail("no speakeasy") return end
        pass(#types .. " types")
    end }

    steps[#steps + 1] = { name = "ownership takes exactly one answer", fn = function(pass, fail)
        local V = Internal.ValidateOwner
        if not V(3, nil) then fail("an organization should be able to own one") return end
        if not V(nil, 7) then fail("so should a person") return end
        if V(3, 7) then fail("two owners were accepted") return end
        if V(nil, nil) then fail("no owner was accepted") return end
        pass()
    end }

    steps[#steps + 1] = { name = "a speakeasy is created and stocked", required = true,
        fn = function(pass, fail)
        Omerta.Business.Create("speakeasy", "Selftest Room",
            { characterId = FAKE_CHARACTER }, Vector(0, 0, 0), { actor = "selftest" },
            function(created, err)
            if not created then fail(tostring(err)) return end
            business = created

            Omerta.Inventory.Add(Omerta.Business.Stock(business.id), "drink.whiskey", 4, nil,
                function(ok, aerr)
                if not ok then fail(tostring(aerr)) return end
                local inStock = Internal.StockOf(business.id, "drink.whiskey")
                if inStock ~= 4 then fail("stock reads " .. inStock) return end
                pass("four whiskies behind the bar")
            end)
        end)
    end }

    steps[#steps + 1] = { name = "the owner may see the register; a stranger may not",
        fn = function(pass, fail)
        local owner = Omerta.Business.RoleFor(business, FAKE_CHARACTER)
        if owner ~= Omerta.Business.ROLE.OWNER then
            fail("the owner reads as " .. tostring(owner)) return
        end
        if not Internal.MaySeeTill(owner) then fail("an owner cannot see their own till") return end

        local stranger = Omerta.Business.RoleFor(business, FAKE_CHARACTER + 99)
        if stranger ~= nil then fail("a stranger has a role: " .. tostring(stranger)) return end
        if Internal.MaySeeTill(stranger) then fail("a stranger can see the till") return end
        if Internal.MayServe(stranger) then fail("a stranger can serve") return end
        pass()
    end }

    steps[#steps + 1] = { name = "a sale is refused when it should be", fn = function(pass, fail)
        local typeDef = Omerta.Business.GetType("speakeasy")
        local entry = Internal.PriceOf(typeDef, "drink.whiskey")
        if not entry then fail("whiskey is not on the menu") return end

        local C = Internal.CanSell
        if C(entry, 1, 4, entry.price, false) then fail("sold while closed") return end
        if C(entry, 1, 0, entry.price, true) then fail("sold what was not there") return end
        if C(entry, 1, 4, entry.price - 5, true) then fail("sold to somebody short") return end
        if C(nil, 1, 4, 100000, true) then fail("sold something off the menu") return end
        if C(entry, 0, 4, 100000, true) then fail("sold zero") return end
        if not C(entry, 2, 4, entry.price * 2, true) then fail("a good sale was refused") return end
        pass()
    end }

    steps[#steps + 1] = { name = "money reaches the till and stock leaves the shelf",
        fn = function(pass, fail)
        local typeDef = Omerta.Business.GetType("speakeasy")
        local entry = Internal.PriceOf(typeDef, "drink.whiskey")
        local till = Omerta.Business.Till(business.id)

        -- Stands in for a customer paying: the money has to be real either way.
        Omerta.Money.Give(till, entry.price, function(ok, err)
            if not ok then fail(tostring(err)) return end
            Internal.TakeFromStock(business.id, "drink.whiskey", 1, function(took, terr)
                if not took then fail(tostring(terr)) return end
                if Internal.StockOf(business.id, "drink.whiskey") ~= 3 then
                    fail("stock did not fall") return
                end
                if Omerta.Money.Count(till) ~= entry.price then
                    fail("the till holds " .. Omerta.Money.Format(Omerta.Money.Count(till)))
                    return
                end
                pass("one whiskey out, " .. Omerta.Money.Format(entry.price) .. " in")
            end)
        end)
    end }

    steps[#steps + 1] = { name = "premises are forceable only while the owner is online",
        fn = function(pass, fail)
        local F = Internal.IsForceable
        local orgOwned = { owner_organization_id = 4 }
        local personOwned = { owner_character_id = FAKE_CHARACTER }

        if F(orgOwned, {}, {}) then fail("an empty family was forceable") return end
        if not F(orgOwned, { [4] = true }, {}) then
            fail("a family with somebody online was not forceable") return
        end
        if F(personOwned, {}, {}) then fail("an offline owner was forceable") return end
        if not F(personOwned, {}, { [FAKE_CHARACTER] = true }) then
            fail("an online owner was not forceable") return
        end
        -- Online, not present: standing somewhere else does not protect you.
        if not F(orgOwned, { [4] = true }, {}) then fail("presence was required") return end
        pass("offline is safe, online is a target")
    end }

    steps[#steps + 1] = { name = "a rumour goes into circulation and comes back out",
        fn = function(pass, fail)
        Omerta.Rumours.Add("The Falcones are short of money.",
            Omerta.Rumours.SOURCE.PLANTED,
            { characterId = FAKE_CHARACTER, businessId = business.id }, function(id, err)
            if not id then fail(tostring(err)) return end

            local drawn = Omerta.Rumours.Draw(FAKE_CHARACTER + 1)
            if not drawn then fail("nothing came back out") return end
            if not drawn.text:find("Falcones") then
                fail("the wrong rumour came back: " .. tostring(drawn.text)) return
            end

            -- Expiry is what stops the pool becoming a permanent record.
            local Live = Omerta.Rumours.Internal.IsLive
            if Live({ expires_at = 100 }, 200) then fail("an expired rumour is still live") return end
            if not Live({ expires_at = 300 }, 200) then fail("a live rumour reads as expired") return end
            pass()
        end)
    end }

    steps[#steps + 1] = { name = "cleanup", always = true, fn = function(pass, fail)
        if not business then pass("nothing was created") return end
        local till, stock = Omerta.Business.Till(business.id), Omerta.Business.Stock(business.id)

        Repo.DeleteRumoursFor(business.id, function()
            Repo.DeleteStaff(business.id, function()
                Omerta.Inventory.Internal.Repo.DeleteForOwner(till.type, till.id, function()
                    Omerta.Inventory.Internal.Repo.DeleteForOwner(stock.type, stock.id, function()
                        Repo.Delete(business.id, function(ok, err)
                            if IsValid(business.counter) then business.counter:Remove() end
                            if IsValid(business.stockEntity) then business.stockEntity:Remove() end
                            Internal.Businesses[business.id] = nil
                            Omerta.Inventory.Unload(till)
                            Omerta.Inventory.Unload(stock)
                            Omerta.Rumours.Internal.Reset()
                            if ok then pass() else fail(tostring(err)) end
                        end)
                    end)
                end)
            end)
        end)
    end }

    return steps
end

concommand.Add("omerta_business_selftest", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    Omerta.SelfTest.Run("business.selftest", buildSteps())
end)
