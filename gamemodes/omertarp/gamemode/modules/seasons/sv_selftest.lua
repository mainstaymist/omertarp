-- In-engine acceptance suite: `omerta_seasons_selftest` (server console or
-- superadmin). Designed to be INCAPABLE of touching the live season's state:
-- it creates a season that stays in setup forever, exercises path transitions
-- with synthetic accounts against whatever season is genuinely active
-- (skipping those steps with a clear message when none is), and removes every
-- row it created. Real Start/End paths are covered headless and by staff use.

if not Omerta.InEngine then return end

local SELFTEST_LABEL = "__selftest__"
local SID_A = "90000000000000002"
local SID_B = "90000000000000003"

local function buildSteps()
    local SRepo = Omerta.Seasons.Internal.Repo
    local ARepo = Omerta.Accounts.Internal.Repo
    local steps = {}

    local setupSeasonId
    local accountA, accountB -- synthetic account objects (never cached, no ply)

    steps[#steps + 1] = { name = "database ready", required = true, fn = function(pass, fail)
        if not Omerta.DB.IsReady() then fail("phase=" .. Omerta.DB.Status().phase) return end
        if Omerta.Seasons.Internal.Failed then fail("seasons module is in failed state") return end
        pass()
    end }

    steps[#steps + 1] = { name = "leftover cleanup from aborted runs", fn = function(pass, fail)
        SRepo.DeleteSelftestSeason(SELFTEST_LABEL, function(ok, err)
            if not ok then fail(tostring(err)) return end
            local function cleanAccount(sid, done)
                ARepo.FetchBySteamID64(sid, function(account)
                    if not account then done() return end
                    SRepo.DeletePathsForAccount(account.id, function()
                        ARepo.DeleteAccountData(account.id, sid, function() done() end)
                    end)
                end)
            end
            cleanAccount(SID_A, function() cleanAccount(SID_B, function() pass() end) end)
        end)
    end }

    steps[#steps + 1] = { name = "create a setup season (never started)", fn = function(pass, fail)
        Omerta.Seasons.Create({ label = SELFTEST_LABEL, actor = "selftest" }, function(id, err)
            if not id then fail(tostring(err)) return end
            setupSeasonId = id
            pass("id=" .. id)
        end)
    end }

    steps[#steps + 1] = { name = "setup season reads back", fn = function(pass, fail)
        SRepo.GetSeason(setupSeasonId, function(season, err)
            if err then fail(err) return end
            if not season or season.state ~= "setup" or season.label ~= SELFTEST_LABEL then
                fail("bad row: " .. tostring(season and season.state)) return
            end
            if season.started_at ~= nil then fail("setup season has started_at") return end
            pass()
        end)
    end }

    steps[#steps + 1] = { name = "lifecycle guard: ending a setup season is refused", fn = function(pass, fail)
        Omerta.Seasons.End(setupSeasonId, "selftest", function(ok, err)
            if ok then fail("ending a setup season succeeded") return end
            if not tostring(err):find("only an active season", 1, true) then
                fail("wrong refusal: " .. tostring(err)) return
            end
            pass("refused as designed")
        end)
    end }

    -- Path steps require a genuinely active season; they use the transition
    -- entry point directly with synthetic account objects (no player, so no
    -- hooks fire and nothing touches the online cache).
    local function needActive(fn)
        return function(pass, fail)
            if not Omerta.Seasons.GetActive() then
                pass("SKIPPED — no active season (start one and re-run for full coverage)")
                return
            end
            fn(pass, fail)
        end
    end

    steps[#steps + 1] = { name = "synthetic accounts", fn = needActive(function(pass, fail)
        ARepo.LoadOrCreate(SID_A, os.time(), function(a, err)
            if not a then fail(tostring(err)) return end
            accountA = a
            ARepo.LoadOrCreate(SID_B, os.time(), function(b, berr)
                if not b then fail(tostring(berr)) return end
                accountB = b
                pass()
            end)
        end)
    end) }

    steps[#steps + 1] = { name = "initial choice: independent", fn = needActive(function(pass, fail)
        Omerta.Seasons.Internal.ApplyTransition(accountA, nil, "independent", "initial_choice",
            function(ok, err)
            if not ok then fail(tostring(err)) return end
            SRepo.GetPathRow(accountA.id, Omerta.Seasons.GetActive().id, function(row, rerr)
                if rerr then fail(rerr) return end
                if not row or row.path ~= "independent" then
                    fail("row: " .. tostring(row and row.path)) return
                end
                pass()
            end)
        end)
    end) }

    steps[#steps + 1] = { name = "recruitment converts independent to criminal", fn = needActive(function(pass, fail)
        Omerta.Seasons.Internal.ApplyTransition(accountA, nil, "criminal", "family_recruitment",
            function(ok, err)
            if not ok then fail(tostring(err)) return end
            SRepo.GetPathRow(accountA.id, Omerta.Seasons.GetActive().id, function(row, rerr)
                if rerr then fail(rerr) return end
                if not row or row.path ~= "criminal" then
                    fail("row: " .. tostring(row and row.path)) return
                end
                pass()
            end)
        end)
    end) }

    steps[#steps + 1] = { name = "criminal -> police is refused", fn = needActive(function(pass, fail)
        Omerta.Seasons.Internal.ApplyTransition(accountA, nil, "police", "initial_choice",
            function(ok, err)
            if ok then fail("cross-side transition succeeded") return end
            pass("refused: " .. tostring(err))
        end)
    end) }

    steps[#steps + 1] = { name = "police resignation becomes independent", fn = needActive(function(pass, fail)
        Omerta.Seasons.Internal.ApplyTransition(accountB, nil, "police", "initial_choice",
            function(ok, err)
            if not ok then fail(tostring(err)) return end
            Omerta.Seasons.Internal.ApplyTransition(accountB, nil, "independent", "police_resignation",
                function(ok2, err2)
                if not ok2 then fail(tostring(err2)) return end
                pass()
            end)
        end)
    end) }

    steps[#steps + 1] = { name = "cleanup (all synthetic rows)", always = true, fn = function(pass, fail)
        SRepo.DeleteSelftestSeason(SELFTEST_LABEL, function(ok, err)
            if not ok then fail(tostring(err)) return end
            local function cleanAccount(account, sid, done)
                if not account then done() return end
                SRepo.DeletePathsForAccount(account.id, function()
                    ARepo.DeleteAccountData(account.id, sid, function() done() end)
                end)
            end
            cleanAccount(accountA, SID_A, function()
                cleanAccount(accountB, SID_B, function() pass() end)
            end)
        end)
    end }

    return steps
end

concommand.Add("omerta_seasons_selftest", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    Omerta.SelfTest.Run("seasons.selftest", buildSteps())
end)
