-- In-engine acceptance suite: `omerta_phone_selftest`.
--
-- Installs two synthetic lines, walks a call through its whole life without a
-- player touching it, and confirms the record that comes out the other end
-- carries metadata and nothing else. Cleans up after itself.

if not Omerta.InEngine then return end

local A_NUMBER, B_NUMBER = "9901", "9902"

local function buildSteps()
    local Internal = Omerta.Phone.Internal
    local Repo = Internal.Repo
    local lineA, lineB = nil, nil
    local steps = {}

    steps[#steps + 1] = { name = "database and season ready", required = true, fn = function(pass, fail)
        if not Omerta.DB.IsReady() then fail("db phase=" .. Omerta.DB.Status().phase) return end
        if not Omerta.Seasons.GetActive() then fail("no active season") return end
        pass()
    end }

    steps[#steps + 1] = { name = "leftover cleanup from aborted runs", required = true,
        fn = function(pass, fail)
        local pending = 0
        local failed = nil
        for _, number in ipairs({ A_NUMBER, B_NUMBER }) do
            local existing = Omerta.Phone.Find(number)
            if existing then
                pending = pending + 1
                Repo.DeleteCallsFor(existing.id, function()
                    Repo.DeleteLine(existing.id, function(ok, err)
                        if not ok then failed = err end
                        if IsValid(existing.entity) then existing.entity:Remove() end
                        Internal.ForgetLine(existing)
                        pending = pending - 1
                        if pending == 0 then
                            if failed then fail(tostring(failed)) else pass("cleared") end
                        end
                    end)
                end)
            end
        end
        if pending == 0 then pass("nothing to clean") end
    end }

    steps[#steps + 1] = { name = "numbers are validated and allocated in order",
        fn = function(pass, fail)
        local V = Omerta.Phone.ValidNumber
        if not V("1000") or not V("9999") then fail("valid numbers were refused") return end
        if V("999") or V("10000") or V("12a4") or V("") then
            fail("an invalid number was accepted") return
        end
        local allocated = Internal.AllocateNumber({ ["1000"] = true, ["1001"] = true })
        if allocated ~= "1002" then fail("allocated " .. tostring(allocated)) return end
        pass()
    end }

    steps[#steps + 1] = { name = "the call state machine refuses what it should",
        fn = function(pass, fail)
        local N = Internal.NextState
        local S = Omerta.Phone.STATE
        if N(S.IDLE, "dial") ~= S.RINGING then fail("dialling should ring") return end
        if N(S.RINGING, "answer") ~= S.CONNECTED then fail("answering should connect") return end
        if N(S.RINGING, "timeout") ~= S.ENDED then fail("an unanswered call should end") return end
        if N(S.CONNECTED, "no_coins") ~= S.ENDED then fail("running out should end it") return end
        -- The abnormal ones: you cannot answer a call twice, and a connected
        -- call cannot time out.
        if N(S.CONNECTED, "answer") ~= nil then fail("answered twice") return end
        if N(S.CONNECTED, "timeout") ~= nil then fail("a live call timed out") return end
        if N(S.ENDED, "hangup") ~= nil then fail("hung up an ended call") return end
        pass()
    end }

    steps[#steps + 1] = { name = "two lines are installed", required = true,
        fn = function(pass, fail)
        local season = Omerta.Seasons.GetActive()
        local here = Vector(0, 0, 0)
        Omerta.Phone.Install(Omerta.Phone.KIND.PAYPHONE, A_NUMBER, "selftest_map", here,
            { actor = "selftest" }, function(a, err)
            if not a then fail(tostring(err)) return end
            lineA = a
            Omerta.Phone.Install(Omerta.Phone.KIND.PRIVATE, B_NUMBER, "selftest_map", here,
                { actor = "selftest" }, function(b, berr)
                if not b then fail(tostring(berr)) return end
                lineB = b
                if not (Omerta.Phone.Find(A_NUMBER) and Omerta.Phone.Find(B_NUMBER)) then
                    fail("the lines are not reachable by number") return
                end
                if season == nil then fail("no season") return end
                pass(A_NUMBER .. " and " .. B_NUMBER)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "a number is taken only once", fn = function(pass, fail)
        Omerta.Phone.Install(Omerta.Phone.KIND.PAYPHONE, A_NUMBER, "selftest_map",
            Vector(0, 0, 0), {}, function(line, err)
            if line then fail("a duplicate number was installed") return end
            if not (err and err:find("taken")) then fail("wrong refusal: " .. tostring(err)) return end
            pass()
        end)
    end }

    steps[#steps + 1] = { name = "coins decide exactly when a call dies", fn = function(pass, fail)
        local Step, Cut = Internal.StepCredit, Internal.ShouldCutOff
        if Step(45, 1) ~= 44 then fail("a second should cost a second") return end
        if Step(0.5, 1) ~= 0 then fail("credit should floor at zero") return end
        -- Out of credit but a quarter in your pocket: the call continues.
        if Cut(0, 1) then fail("a call died with a coin still available") return end
        -- Out of credit and out of coins: mid-sentence, as intended.
        if not Cut(0, 0) then fail("a call survived with no credit and no coins") return end
        if Cut(10, 0) then fail("a call with credit was cut off") return end
        pass()
    end }

    steps[#steps + 1] = { name = "voice reaches the far end and nobody else",
        fn = function(pass, fail)
        local D = Internal.VoiceDecision
        local S = Omerta.Phone.STATE
        local call = { id = 7, state = S.CONNECTED }
        local other = { id = 8, state = S.CONNECTED }

        -- Two people on the same connected call hear each other, flat.
        local canHear, is3D = D(call, call)
        if canHear ~= true or is3D ~= false then
            fail("participants should hear each other non-positionally") return
        end
        -- A bystander is not on the call, so the decision defers to distance —
        -- which is how they hear only the half spoken in front of them.
        if D(nil, call) ~= nil then fail("a bystander should defer to distance") return end
        if D(call, nil) ~= nil then fail("and so should the other direction") return end
        -- Two different calls never bleed into one another.
        if D(call, other) ~= nil then fail("separate calls were joined") return end
        -- A ringing call is not a connected one.
        if D({ id = 7, state = S.RINGING }, { id = 7, state = S.RINGING }) ~= nil then
            fail("a ringing call carried voice") return
        end
        pass()
    end }

    steps[#steps + 1] = { name = "a record is metadata and nothing else", fn = function(pass, fail)
        local season = Omerta.Seasons.GetActive()
        Repo.RecordCall({
            season_id = season.id,
            from_line = lineA.id, to_line = lineB.id,
            started_at = os.time() - 30, ended_at = os.time(),
            seconds = 30, coins_spent = 25,
            outcome = Omerta.Phone.OUTCOME.ANSWERED,
        }, function(id, err)
            if not id then fail(tostring(err)) return end
            Repo.CallsFor(lineB.id, 5, function(rows, rerr)
                if rerr then fail(tostring(rerr)) return end
                if #rows ~= 1 then fail("read back " .. #rows .. " record(s)") return end
                local row = rows[1]
                if row.seconds ~= 30 or row.outcome ~= "answered" then
                    fail("the record does not match what was written") return
                end
                -- There must be nowhere for a recording to live.
                for key in pairs(row) do
                    if key == "content" or key == "transcript" or key == "audio" then
                        fail("a call record has a content column: " .. key) return
                    end
                end
                pass("30 seconds, answered, no content")
            end)
        end)
    end }

    steps[#steps + 1] = { name = "cleanup", always = true, fn = function(pass, fail)
        local pending, failed = 0, nil
        for _, line in ipairs({ lineA, lineB }) do
            if line then
                pending = pending + 1
                Repo.DeleteCallsFor(line.id, function()
                    Repo.DeleteLine(line.id, function(ok, err)
                        if not ok then failed = err end
                        if IsValid(line.entity) then line.entity:Remove() end
                        Internal.ForgetLine(line)
                        pending = pending - 1
                        if pending == 0 then
                            if failed then fail(tostring(failed)) else pass() end
                        end
                    end)
                end)
            end
        end
        if pending == 0 then pass("nothing to clean") end
    end }

    return steps
end

concommand.Add("omerta_phone_selftest", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    Omerta.SelfTest.Run("phone.selftest", buildSteps())
end)
