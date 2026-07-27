-- In-engine acceptance suite: `omerta_accounts_selftest` (server console or
-- superadmin). Uses a synthetic SteamID64 — no real player involved — and
-- removes every row it created, including its audit trail.

if not Omerta.InEngine then return end

local FAKE_SID = "90000000000000001"

local function buildSteps()
    local Repo = Omerta.Accounts.Internal.Repo
    local steps = {}
    local accountId = nil

    steps[#steps + 1] = { name = "database ready", fn = function(pass, fail)
        if Omerta.DB.IsReady() then pass(Omerta.DB.Status().backend .. " backend")
        else fail("phase=" .. Omerta.DB.Status().phase) end
    end }

    steps[#steps + 1] = { name = "leftover cleanup from aborted runs", fn = function(pass, fail)
        Repo.FetchBySteamID64(FAKE_SID, function(account, err)
            if err then fail(err) return end
            if not account then pass("nothing to clean") return end
            Repo.DeleteAccountData(account.id, FAKE_SID, function(ok, derr)
                if ok then pass("removed stale rows") else fail(tostring(derr)) end
            end)
        end)
    end }

    steps[#steps + 1] = { name = "first load creates the account", fn = function(pass, fail)
        Repo.LoadOrCreate(FAKE_SID, os.time(), function(account, err, created)
            if err then fail(err) return end
            if not created then fail("expected create path") return end
            if type(account.id) ~= "number" or account.connections ~= 1 then
                fail("id=" .. tostring(account.id) .. " connections=" .. tostring(account.connections))
                return
            end
            accountId = account.id
            pass("id=" .. account.id)
        end)
    end }

    steps[#steps + 1] = { name = "second load bumps connections", fn = function(pass, fail)
        Repo.LoadOrCreate(FAKE_SID, os.time(), function(account, err, created)
            if err then fail(err) return end
            if created then fail("created twice") return end
            if account.id ~= accountId then fail("id changed") return end
            if account.connections ~= 2 then
                fail("connections=" .. tostring(account.connections)) return
            end
            pass()
        end)
    end }

    steps[#steps + 1] = { name = "flag set and read back", fn = function(pass, fail)
        Repo.SetFlag(accountId, "selftest_flag", "self-test reason", FAKE_SID, os.time(),
            function(ok, err)
            if not ok then fail(tostring(err)) return end
            Repo.FetchBySteamID64(FAKE_SID, function(account, ferr)
                if ferr then fail(ferr) return end
                local f = account and account.flags.selftest_flag
                if not f or f.reason ~= "self-test reason" or f.set_by ~= FAKE_SID then
                    fail("flag not round-tripped") return
                end
                pass()
            end)
        end)
    end }

    steps[#steps + 1] = { name = "flag clear", fn = function(pass, fail)
        Repo.ClearFlag(accountId, "selftest_flag", function(ok, err)
            if not ok then fail(tostring(err)) return end
            Repo.FetchBySteamID64(FAKE_SID, function(account, ferr)
                if ferr then fail(ferr) return end
                if account.flags.selftest_flag ~= nil then fail("flag survived clear") return end
                pass()
            end)
        end)
    end }

    steps[#steps + 1] = { name = "stat increments accumulate atomically", fn = function(pass, fail)
        Repo.IncrementStat(accountId, "selftest_counter", 3, function(ok, err)
            if not ok then fail(tostring(err)) return end
            Repo.IncrementStat(accountId, "selftest_counter", 4, function(ok2, err2)
                if not ok2 then fail(tostring(err2)) return end
                Repo.FetchBySteamID64(FAKE_SID, function(account, ferr)
                    if ferr then fail(ferr) return end
                    local v = account and account.stats.selftest_counter
                    if v ~= 7 then fail("value=" .. tostring(v)) return end
                    if type(v) ~= "number" then fail("value is " .. type(v)) return end
                    pass("3 + 4 = 7")
                end)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "playtime accrues", fn = function(pass, fail)
        Repo.AddPlaytime(accountId, 60, os.time(), function(ok, err)
            if not ok then fail(tostring(err)) return end
            Repo.FetchBySteamID64(FAKE_SID, function(account, ferr)
                if ferr then fail(ferr) return end
                if account.playtime ~= 60 then
                    fail("playtime=" .. tostring(account.playtime)) return
                end
                pass()
            end)
        end)
    end }

    steps[#steps + 1] = { name = "audit event persists and reads back", fn = function(pass, fail)
        Omerta.Log.Audit("selftest.event", { actor = FAKE_SID, marker = "m2" })
        -- The sink inserts through the async DB layer; give it a tick.
        timer.Simple(0.5, function()
            Omerta.DB.QueryOne(
                "SELECT event, data FROM {audit} WHERE actor = ? AND event = ? ORDER BY id DESC",
                { FAKE_SID, "selftest.event" }, function(row, err)
                if err then fail(err) return end
                if not row then fail("audit row missing") return end
                if type(row.data) ~= "string" or not row.data:find("m2", 1, true) then
                    fail("data payload missing: " .. tostring(row.data)) return
                end
                pass()
            end)
        end)
    end }

    steps[#steps + 1] = { name = "cleanup (all synthetic rows)", fn = function(pass, fail)
        Repo.DeleteAccountData(accountId, FAKE_SID, function(ok, err)
            if not ok then fail(tostring(err)) return end
            Repo.FetchBySteamID64(FAKE_SID, function(account, ferr)
                if ferr then fail(ferr) return end
                if account ~= nil then fail("account row survived cleanup") return end
                pass()
            end)
        end)
    end }

    return steps
end

concommand.Add("omerta_accounts_selftest", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    Omerta.SelfTest.Run("accounts.selftest", buildSteps())
end)
