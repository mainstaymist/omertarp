-- Shared runner for in-engine self-test suites (server-side). Every data
-- milestone ships one (`omerta_db_selftest`, `omerta_accounts_selftest`, ...);
-- this is the one sequential runner they all use instead of each carrying a
-- copy.
--
-- steps: array of { name = string, fn = function(pass, fail) } where fn calls
-- exactly one of pass(detail?) / fail(reason). Steps run sequentially; each
-- gets a timeout so a lost callback cannot hang the suite.

Omerta.SelfTest = {}

function Omerta.SelfTest.Run(suiteName, steps, opts)
    Omerta.AssertServer("Omerta.SelfTest.Run")
    opts = opts or {}
    local stepTimeout = opts.timeout or 10
    local passed, failed = 0, 0

    local function runStep(i)
        if i > #steps then
            local level = failed == 0 and Omerta.Log.Info or Omerta.Log.Error
            level(suiteName, "==== RESULT: %d passed, %d failed ====", passed, failed)
            if opts.onDone then opts.onDone(passed, failed) end
            return
        end
        local step = steps[i]
        local finished = false
        local function once(ok, detail)
            if finished then return end
            finished = true
            if ok then
                passed = passed + 1
                Omerta.Log.Info(suiteName, "PASS %s%s", step.name,
                    detail and (" — " .. detail) or "")
            else
                failed = failed + 1
                Omerta.Log.Error(suiteName, "FAIL %s — %s", step.name, tostring(detail))
            end
            runStep(i + 1)
        end
        if Omerta.InEngine then
            timer.Simple(stepTimeout, function()
                once(false, "timed out after " .. stepTimeout .. "s")
            end)
        end
        local ok, err = pcall(step.fn,
            function(detail) once(true, detail) end,
            function(reason) once(false, reason) end)
        if not ok then once(false, "step crashed: " .. tostring(err)) end
    end

    Omerta.Log.Info(suiteName, "==== starting ====")
    runStep(1)
end
