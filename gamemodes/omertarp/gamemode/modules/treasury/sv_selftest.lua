-- In-engine acceptance suite: `omerta_treasury_selftest`.
--
-- Drives a synthetic institution's safe: money in, money out, the ledger
-- tracking it, an over-limit refusal, a purchase that turns cash into goods,
-- and the discrepancy that appears when somebody takes money without writing
-- it down. Cleans up after itself.

if not Omerta.InEngine then return end

local FAKE_ORG = 2200000001
local FAKE_CHARACTER = 2200000002

local function buildSteps()
    local Internal = Omerta.Treasury.Internal
    local Repo = Internal.Repo
    local safe = Omerta.Treasury.Of(FAKE_ORG)
    local steps = {}

    steps[#steps + 1] = { name = "database and season ready", required = true, fn = function(pass, fail)
        if not Omerta.DB.IsReady() then fail("db phase=" .. Omerta.DB.Status().phase) return end
        if not Omerta.Seasons.GetActive() then fail("no active season") return end
        pass()
    end }

    steps[#steps + 1] = { name = "leftover cleanup from aborted runs", required = true,
        fn = function(pass, fail)
        Repo.DeleteLedgerFor(FAKE_ORG, function(ok, err)
            if not ok then fail(tostring(err)) return end
            Omerta.Inventory.Internal.Repo.DeleteForOwner(safe.type, safe.id, function(ok2, err2)
                if not ok2 then fail(tostring(err2)) return end
                Omerta.Inventory.RegisterContainer(safe.id, { capacity = 2000, label = "Treasury" })
                Omerta.Inventory.Load(safe, function() pass() end)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "the catalogue is coherent and buys only objects",
        fn = function(pass, fail)
        local list = Omerta.Procurement.GetOrdered()
        if #list == 0 then fail("the catalogue is empty") return end
        for i, entry in ipairs(list) do
            if Omerta.Procurement.GetByIndex(i) ~= entry then
                fail("index mismatch at " .. i) return
            end
            if entry.price % Omerta.Money.SMALLEST ~= 0 then
                fail(entry.id .. " is priced in coins that do not exist") return
            end
            if entry.item and not Omerta.Items.Get(entry.item) then
                fail(entry.id .. " delivers an item that does not exist") return
            end
        end
        -- Tech §10's guardrail, checked rather than trusted.
        local ok = Omerta.Procurement.Validate("test.stat", {
            name = "Muscle", category = "medical", price = 100, item = "food.bread",
            health = 25,
        })
        if ok then fail("an entry granting health was accepted") return end
        pass(#list .. " entries")
    end }

    steps[#steps + 1] = { name = "spending limits and approval", fn = function(pass, fail)
        local C = Omerta.Treasury.CanSpend
        local L = Omerta.Treasury.LimitFor

        -- A Soldier (3) cannot take money out at all; an Underboss (5) can, up
        -- to a ceiling; a Don (6) has none.
        if L("family", 3) ~= 0 then fail("a soldier should not be able to spend") return end
        if L("family", 5) == nil or L("family", 5) <= 0 then
            fail("an underboss should have a ceiling, got " .. tostring(L("family", 5))) return
        end
        if L("family", 6) ~= nil then fail("a Don should have no ceiling") return end

        local limit = L("family", 5)
        if not C("family", 5, limit, nil) then fail("at the ceiling should be allowed") return end
        if C("family", 5, limit + 500, nil) then fail("above the ceiling, alone, was allowed") return end
        if not C("family", 5, limit + 500, 6) then fail("a Don should be able to approve it") return end
        if C("family", 5, limit + 500, 3) then fail("a soldier approved a withdrawal") return end
        if C("family", 3, 100, 6) then fail("a soldier spent with approval") return end
        pass("ceiling holds, approval lifts it")
    end }

    steps[#steps + 1] = { name = "money goes into the safe and the books follow",
        required = true, fn = function(pass, fail)
        -- Seeded directly, standing in for a deposit by a player: the money
        -- has to be real M9 cash either way.
        Omerta.Money.Give(safe, 50000, function(ok, err)
            if not ok then fail(tostring(err)) return end
            local counted = Omerta.Treasury.Count(FAKE_ORG)
            if counted ~= 50000 then
                fail("safe holds " .. Omerta.Money.Format(counted)) return
            end

            local season = Omerta.Seasons.GetActive()
            local line = Internal.BuildLine({
                organizationId = FAKE_ORG, seasonId = season.id, at = os.time(),
                characterId = FAKE_CHARACTER, delta = 50000, balanceBefore = 0,
                counted = counted, reason = Omerta.Treasury.REASONS.DEPOSIT,
            })
            if line.balance_after ~= 50000 then
                fail("balance_after reads " .. tostring(line.balance_after)) return
            end
            Repo.Append(line, function(id, aerr)
                if not id then fail(tostring(aerr)) return end
                Repo.LastBalance(FAKE_ORG, function(balance)
                    if balance ~= 50000 then
                        fail("the books read " .. Omerta.Money.Format(balance)) return
                    end
                    pass("$500.00 in, and written down")
                end)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "cash buys goods, and both halves land", fn = function(pass, fail)
        local entry = Omerta.Procurement.Get("supply.revolver")
        if not entry then fail("supply.revolver is missing") return end

        Omerta.Money.Take(safe, entry.price, function(ok, err)
            if not ok then fail(tostring(err)) return end
            Omerta.Procurement.Internal.Deliver(FAKE_ORG, entry, 1, function(ok2, err2)
                if not ok2 then fail(tostring(err2)) return end

                local counted = Omerta.Treasury.Count(FAKE_ORG)
                if counted ~= 50000 - entry.price then
                    fail("safe holds " .. Omerta.Money.Format(counted) .. " after paying") return
                end
                local found = nil
                for _, row in ipairs(Omerta.Inventory.Get(safe)) do
                    if row.def_id == entry.item then found = row end
                end
                if not found then fail("the revolver never arrived") return end
                -- M9 left organization_id on every item for this moment: bought
                -- goods belong to the institution, not to whoever fetched them.
                if found.organization_id ~= FAKE_ORG then
                    fail("the revolver is not tagged to the family, got "
                        .. tostring(found.organization_id)) return
                end
                pass("paid " .. Omerta.Money.Format(entry.price) .. ", revolver in the safe")
            end)
        end)
    end }

    steps[#steps + 1] = { name = "the books and the safe can disagree", fn = function(pass, fail)
        -- Somebody takes money without writing it down. This is not a bug to
        -- be prevented; it is the mechanic §4a exists to make possible.
        Omerta.Money.Take(safe, 10000, function(ok, err)
            if not ok then fail(tostring(err)) return end
            Repo.LastBalance(FAKE_ORG, function(books)
                local counted = Omerta.Treasury.Count(FAKE_ORG)
                local gap = Omerta.Treasury.Discrepancy(counted, books)
                if gap >= 0 then
                    fail("expected the safe to be short, gap is " .. gap) return
                end
                local described = Omerta.Treasury.DescribeDiscrepancy(counted, books)
                if not described:find("missing") then
                    fail("the discrepancy reads '" .. described .. "'") return
                end
                pass(described)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "the ledger reads back in order", fn = function(pass, fail)
        Repo.History(FAKE_ORG, 10, function(rows, err)
            if err then fail(tostring(err)) return end
            if #rows < 1 then fail("no ledger lines were written") return end
            -- Newest first, and every line carries who moved it.
            for _, row in ipairs(rows) do
                if not row.character_id then fail("a line has no actor") return end
                if row.balance_after == nil then fail("a line has no resulting balance") return end
            end
            pass(#rows .. " line(s)")
        end)
    end }

    steps[#steps + 1] = { name = "cleanup", always = true, fn = function(pass, fail)
        Repo.DeleteLedgerFor(FAKE_ORG, function(ok, err)
            if not ok then fail(tostring(err)) return end
            Omerta.Inventory.Internal.Repo.DeleteForOwner(safe.type, safe.id, function(ok2, err2)
                if not ok2 then fail(tostring(err2)) return end
                Omerta.Inventory.Unload(safe)
                pass()
            end)
        end)
    end }

    return steps
end

concommand.Add("omerta_treasury_selftest", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    Omerta.SelfTest.Run("treasury.selftest", buildSteps())
end)
