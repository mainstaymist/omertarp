-- Shared runner for in-engine self-test suites (server-side). Every data
-- milestone ships one (`omerta_db_selftest`, `omerta_accounts_selftest`, ...);
-- this is the one sequential runner they all use instead of each carrying a
-- copy.
--
-- steps: array of { name = string, fn = function(pass, fail) } where fn calls
-- exactly one of pass(detail?) / fail(reason). Steps run sequentially; each
-- gets a timeout so a lost callback cannot hang the suite.
--
-- Optional per-step flags:
--   required = true  a prerequisite: if it fails, the rest of the suite is
--                    skipped rather than run against a broken precondition.
--                    Continuing past a failed prerequisite produces garbage
--                    results and, worse, garbage rows.
--   always   = true  runs even after an abort — for cleanup steps, which must
--                    never be skipped or the next run inherits the mess.

Omerta.SelfTest = {}

function Omerta.SelfTest.Run(suiteName, steps, opts)
    Omerta.AssertServer("Omerta.SelfTest.Run")
    opts = opts or {}
    local stepTimeout = opts.timeout or 10
    local passed, failed, skipped = 0, 0, 0
    local aborting = false

    local function runStep(i)
        if i > #steps then
            local level = failed == 0 and Omerta.Log.Info or Omerta.Log.Error
            if skipped > 0 then
                level(suiteName, "==== RESULT: %d passed, %d failed, %d skipped ====",
                    passed, failed, skipped)
            else
                level(suiteName, "==== RESULT: %d passed, %d failed ====", passed, failed)
            end
            if opts.onDone then opts.onDone(passed, failed, skipped) end
            return
        end
        local step = steps[i]

        if aborting and not step.always then
            skipped = skipped + 1
            Omerta.Log.Warn(suiteName, "SKIP %s — prerequisite failed", step.name)
            runStep(i + 1)
            return
        end

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
                if step.required then
                    aborting = true
                    Omerta.Log.Error(suiteName,
                        "prerequisite failed — skipping remaining steps (cleanup still runs)")
                end
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
