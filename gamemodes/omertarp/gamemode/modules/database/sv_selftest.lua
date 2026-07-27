-- In-engine acceptance suite: `omerta_db_selftest` in the server console (or
-- as a superadmin). Runs the identical checks against whichever backend is
-- configured — the M1 acceptance bar is flipping db.backend, restarting, and
-- watching this pass unchanged on both (DECISIONS.md D-006).
--
-- Uses a throwaway table (omerta_selftest) created and dropped per run, so
-- repeated runs are clean and no gameplay data is touched.

if not Omerta.InEngine then return end

local defined = false

local function ensureDefined()
    if defined then return end
    defined = true
    Omerta.DB.DefineTable("selftest", {
        columns = {
            { name = "id",     type = "id" },
            { name = "label",  type = "text", length = 64, null = false },
            { name = "count",  type = "int", default = 0 },
            { name = "active", type = "bool", default = false },
            { name = "note",   type = "text" },
        },
        unique = { { "label" } },
    })
end

-- Each step: { name, fn(pass, fail) } where pass(detail?) / fail(reason).
local function buildSteps()
    local steps = {}
    local insertedId = nil

    steps[#steps + 1] = { name = "database ready", fn = function(pass, fail)
        local s = Omerta.DB.Status()
        if not s.ready then
            fail("phase=" .. s.phase .. (s.lastError and (" lastError=" .. s.lastError) or ""))
        else
            pass(s.backend .. " backend")
        end
    end }

    steps[#steps + 1] = { name = "reset + create table (schema DSL)", fn = function(pass, fail)
        local dialect = Omerta.DB.Status().backend
        local prefix = Omerta.Config.Get("db.table_prefix")
        -- Drop leftovers first: an earlier aborted run leaves the table (and
        -- its unique rows) behind, which would fail this run's inserts.
        local stmts = { "DROP TABLE IF EXISTS " .. prefix .. "selftest" }
        for _, s in ipairs(Omerta.DB.Internal.RenderCreateTable(dialect, prefix, "selftest")) do
            stmts[#stmts + 1] = s
        end
        local function runNext(i)
            if i > #stmts then pass(#stmts .. " statement(s)") return end
            Omerta.DB.Query(stmts[i], {}, function(_, err)
                if err then fail(err) else runNext(i + 1) end
            end)
        end
        runNext(1)
    end }

    steps[#steps + 1] = { name = "insert returns numeric id", fn = function(pass, fail)
        Omerta.DB.Insert("selftest", {
            label = "first", count = 7, active = true, note = Omerta.DB.NULL,
        }, function(id, err)
            if err then fail(err) return end
            if type(id) ~= "number" or id < 1 then fail("id was " .. tostring(id)) return end
            insertedId = id
            pass("id=" .. id)
        end)
    end }

    steps[#steps + 1] = { name = "type fidelity (number/bool/string/NULL)", fn = function(pass, fail)
        Omerta.DB.QueryOne("SELECT label, count, active, note FROM {selftest} WHERE id = ?",
            { insertedId }, function(row, err)
            if err then fail(err) return end
            if not row then fail("row missing") return end
            if type(row.label) ~= "string" or row.label ~= "first" then
                fail("label: " .. type(row.label) .. " " .. tostring(row.label)) return
            end
            if type(row.count) ~= "number" or row.count ~= 7 then
                fail("count: " .. type(row.count) .. " " .. tostring(row.count)) return
            end
            if type(row.active) ~= "boolean" or row.active ~= true then
                fail("active: " .. type(row.active) .. " " .. tostring(row.active)) return
            end
            if row.note ~= nil then
                fail("note should be nil, was " .. type(row.note) .. " " .. tostring(row.note)) return
            end
            pass()
        end)
    end }

    steps[#steps + 1] = { name = "injection attempt is inert", fn = function(pass, fail)
        local hostile = "Tony'); DROP TABLE omerta_selftest;--"
        Omerta.DB.Insert("selftest", { label = hostile, count = 1, active = false },
            function(id, err)
            if err then fail("insert: " .. err) return end
            Omerta.DB.QueryOne("SELECT label FROM {selftest} WHERE id = ?", { id },
                function(row, qerr)
                if qerr then fail("table damaged? " .. qerr) return end
                if not row or row.label ~= hostile then
                    fail("round-trip mismatch: " .. tostring(row and row.label)) return
                end
                pass("stored verbatim, table intact")
            end)
        end)
    end }

    steps[#steps + 1] = { name = "transaction commit", fn = function(pass, fail)
        Omerta.DB.Transaction(function(tx)
            tx:Insert("selftest", { label = "tx_a", count = 1, active = false })
            tx:Insert("selftest", { label = "tx_b", count = 2, active = true })
        end, function(ok, err)
            if not ok then fail(tostring(err)) return end
            Omerta.DB.QueryOne("SELECT COUNT(*) AS n FROM {selftest} WHERE label IN (?, ?)",
                { "tx_a", "tx_b" }, function(row, qerr)
                if qerr then fail(qerr) return end
                if not row or row.n ~= 2 then fail("expected 2, got " .. tostring(row and row.n)) return end
                if type(row.n) ~= "number" then fail("COUNT came back as " .. type(row.n)) return end
                pass()
            end)
        end)
    end }

    steps[#steps + 1] = { name = "transaction rollback", fn = function(pass, fail)
        Omerta.DB.Transaction(function(tx)
            tx:Insert("selftest", { label = "ghost", count = 1, active = false })
            tx:Query("THIS IS NOT VALID SQL")
        end, function(ok, err)
            if ok then fail("transaction with invalid SQL reported success") return end
            Omerta.DB.QueryOne("SELECT COUNT(*) AS n FROM {selftest} WHERE label = ?",
                { "ghost" }, function(row, qerr)
                if qerr then fail(qerr) return end
                if row and row.n ~= 0 then fail("ghost row survived rollback") return end
                pass("failed as expected, nothing committed")
            end)
        end)
    end }

    steps[#steps + 1] = { name = "upsert (insert then update)", fn = function(pass, fail)
        Omerta.DB.Upsert("selftest", { label = "up", count = 1, active = false }, { "label" },
            function(ok, err)
            if not ok then fail("first upsert: " .. tostring(err)) return end
            Omerta.DB.Upsert("selftest", { label = "up", count = 2, active = true }, { "label" },
                function(ok2, err2)
                if not ok2 then fail("second upsert: " .. tostring(err2)) return end
                Omerta.DB.Query("SELECT count, active FROM {selftest} WHERE label = ?",
                    { "up" }, function(rows, qerr)
                    if qerr then fail(qerr) return end
                    if #rows ~= 1 then fail("expected 1 row, got " .. #rows) return end
                    if rows[1].count ~= 2 or rows[1].active ~= true then
                        fail("update not applied: count=" .. tostring(rows[1].count)) return
                    end
                    pass()
                end)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "reconnect drill (close and rebuild connection)", fn = function(pass, fail)
        local driver = Omerta.DB.Internal.Drivers[Omerta.DB.Status().backend]
        if not driver.ForceDisconnect then
            pass("SKIPPED — single-connection backend (" .. driver.dialect .. ")")
            return
        end
        if not driver.ForceDisconnect() then
            pass("SKIPPED — this mysqloo build exposes no disconnect")
            return
        end
        -- A manual close emits no error: mysqloo parks queries started on a
        -- closed connection instead of failing them, so nothing would ever
        -- trigger the error-driven reconnect path (that path fires on real
        -- network losses, whose queries DO error). Deliver the notification a
        -- real loss would produce, then prove the layer rebuilds and flushes.
        Omerta.DB.Internal.OnConnectionLost()
        if Omerta.DB.IsReady() then
            fail("layer still ready after connection loss")
            return
        end
        -- Queues during the outage; must run after the rebuild completes.
        Omerta.DB.QueryOne("SELECT 1 AS one", {}, function(row, err)
            if err or not row or row.one ~= 1 then
                fail("outage-queued query failed: " .. tostring(err))
            else
                pass("outage-queued query ran after rebuild")
            end
        end)
    end }

    steps[#steps + 1] = { name = "cleanup (drop table)", fn = function(pass, fail)
        Omerta.DB.Query("DROP TABLE {selftest}", {}, function(_, err)
            if err then fail(err) else pass() end
        end)
    end }

    return steps
end

local function runSelftest()
    ensureDefined()
    local steps = buildSteps()
    local passed, failed = 0, 0

    local function runStep(i)
        if i > #steps then
            local level = failed == 0 and Omerta.Log.Info or Omerta.Log.Error
            level("db.selftest", "==== RESULT: %d passed, %d failed (%s backend) ====",
                passed, failed, Omerta.DB.Status().backend)
            return
        end
        local step = steps[i]
        local finished = false
        local function once(ok, detail)
            if finished then return end
            finished = true
            if ok then
                passed = passed + 1
                Omerta.Log.Info("db.selftest", "PASS %s%s", step.name,
                    detail and (" — " .. detail) or "")
            else
                failed = failed + 1
                Omerta.Log.Error("db.selftest", "FAIL %s — %s", step.name, tostring(detail))
            end
            runStep(i + 1)
        end
        -- 10s timeout per step so a lost callback cannot hang the suite.
        timer.Simple(10, function() once(false, "timed out after 10s") end)
        local ok, err = pcall(step.fn,
            function(detail) once(true, detail) end,
            function(reason) once(false, reason) end)
        if not ok then once(false, "step crashed: " .. tostring(err)) end
    end

    Omerta.Log.Info("db.selftest", "==== starting (%s backend) ====", Omerta.DB.Status().backend)
    runStep(1)
end

concommand.Add("omerta_db_selftest", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    runSelftest()
end)
