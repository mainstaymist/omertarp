-- In-engine acceptance suite: `omerta_identity_selftest`. Creates two
-- synthetic characters against the live season, exercises learning and
-- per-observer isolation, and removes everything it made.

if not Omerta.InEngine then return end

local SID_A = "90000000000000005"
local SID_B = "90000000000000006"

local function buildSteps()
    local IRepo = Omerta.Identity.Internal.Repo
    local CRepo = Omerta.Characters.Internal.Repo
    local ARepo = Omerta.Accounts.Internal.Repo
    local steps = {}

    local seasonId, accA, accB, charA, charB

    local function makeCharacter(account, first, last, cb)
        local f, l, key = Omerta.Characters.ValidateName(first, last)
        CRepo.Create({
            account_id = account.id, season_id = seasonId,
            first_name = f, last_name = l, name_key = key,
            status = Omerta.Characters.STATUS.ALIVE,
            model = Omerta.Characters.MODELS[1], skin = 0, created_at = os.time(),
        }, cb)
    end

    local function purge(sid, done)
        ARepo.FetchBySteamID64(sid, function(account)
            if not account then done() return end
            -- Knowledge references characters, so clear it per character first.
            CRepo.GetActiveFor(account.id, seasonId, function(character)
                local function finish()
                    CRepo.DeleteForAccount(account.id, function()
                        ARepo.DeleteAccountData(account.id, sid, function() done() end)
                    end)
                end
                if character then IRepo.DeleteAllFor(character.id, finish) else finish() end
            end)
        end)
    end

    steps[#steps + 1] = { name = "database and season ready", required = true, fn = function(pass, fail)
        if not Omerta.DB.IsReady() then fail("db phase=" .. Omerta.DB.Status().phase) return end
        local season = Omerta.Seasons.GetActive()
        if not season then fail("no active season — create and start one first") return end
        seasonId = season.id
        pass("season #" .. seasonId)
    end }

    steps[#steps + 1] = { name = "leftover cleanup from aborted runs", fn = function(pass)
        purge(SID_A, function() purge(SID_B, function() pass() end) end)
    end }

    steps[#steps + 1] = { name = "two synthetic characters", fn = function(pass, fail)
        ARepo.LoadOrCreate(SID_A, os.time(), function(a, aerr)
            if not a then fail(tostring(aerr)) return end
            accA = a
            makeCharacter(a, "Selftest", "Alpha", function(idA, cerrA)
                if not idA then fail(tostring(cerrA)) return end
                charA = idA
                ARepo.LoadOrCreate(SID_B, os.time(), function(b, berr)
                    if not b then fail(tostring(berr)) return end
                    accB = b
                    makeCharacter(b, "Selftest", "Beta", function(idB, cerrB)
                        if not idB then fail(tostring(cerrB)) return end
                        charB = idB
                        pass("#" .. idA .. " and #" .. idB)
                    end)
                end)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "both start out unknown to each other", fn = function(pass, fail)
        local name, known = Omerta.Identity.ResolveDisplayName(
            { id = charA }, { id = charB, first_name = "Selftest", last_name = "Beta" }, nil)
        if known or name ~= Omerta.Identity.UNKNOWN then
            fail("resolved to '" .. name .. "'") return
        end
        pass()
    end }

    steps[#steps + 1] = { name = "A learns B (one-way, D-013)", fn = function(pass, fail)
        Omerta.Identity.Internal.LoadKnowledge(charA, function()
        Omerta.Identity.Internal.LoadKnowledge(charB, function()
            Omerta.Identity.Learn(charA, charB, "Selftest Beta", "introduction", function(ok, err)
                if not ok then fail(tostring(err)) return end
                if not Omerta.Identity.Knows(charA, charB) then
                    fail("A should know B") return
                end
                -- The point of one-way: B learned nothing.
                if Omerta.Identity.Knows(charB, charA) then
                    fail("B must NOT know A after a one-way introduction") return
                end
                pass("A knows B; B still does not know A")
            end)
        end) end)
    end }

    steps[#steps + 1] = { name = "resolution uses the observer's own knowledge", fn = function(pass, fail)
        local subject = { id = charB, first_name = "Selftest", last_name = "Beta" }
        local nameA = Omerta.Identity.ResolveDisplayName({ id = charA }, subject,
            Omerta.Identity.GetKnownName(charA, charB))
        if nameA ~= "Selftest Beta" then fail("A saw '" .. nameA .. "'") return end

        local subjectA = { id = charA, first_name = "Selftest", last_name = "Alpha" }
        local nameB = Omerta.Identity.ResolveDisplayName({ id = charB }, subjectA,
            Omerta.Identity.GetKnownName(charB, charA))
        if nameB ~= Omerta.Identity.UNKNOWN then fail("B saw '" .. nameB .. "'") return end
        pass()
    end }

    steps[#steps + 1] = { name = "knowledge survives a reload from the database", fn = function(pass, fail)
        Omerta.Identity.Internal.UnloadKnowledge(charA)
        Omerta.Identity.Internal.LoadKnowledge(charA, function(ok)
            if not ok then fail("reload failed") return end
            if Omerta.Identity.GetKnownName(charA, charB) ~= "Selftest Beta" then
                fail("knowledge did not persist") return
            end
            pass()
        end)
    end }

    steps[#steps + 1] = { name = "concealment defeats recognition (D-014)", fn = function(pass, fail)
        local subject = { id = charB, first_name = "Selftest", last_name = "Beta", __concealed = true }
        Omerta.Identity.RegisterConcealmentProvider(function(c) return c.__concealed == true end)
        local name = Omerta.Identity.ResolveDisplayName({ id = charA }, subject, "Selftest Beta")
        if name ~= Omerta.Identity.UNKNOWN then
            fail("a concealed face resolved to '" .. name .. "'") return
        end
        -- Knowledge itself is untouched.
        if not Omerta.Identity.Knows(charA, charB) then fail("knowledge was lost") return end
        pass("unknown while concealed, knowledge intact")
    end }

    steps[#steps + 1] = { name = "who-knows lookup", fn = function(pass, fail)
        IRepo.WhoKnows(charB, function(rows, err)
            if err then fail(err) return end
            local found = false
            for _, row in ipairs(rows or {}) do
                if row.observer_id == charA then found = true end
            end
            if not found then fail("A missing from B's observers") return end
            pass(#rows .. " observer(s)")
        end)
    end }

    steps[#steps + 1] = { name = "forget", fn = function(pass, fail)
        Omerta.Identity.Forget(charA, charB, function(ok, err)
            if not ok then fail(tostring(err)) return end
            if Omerta.Identity.Knows(charA, charB) then fail("still known") return end
            pass()
        end)
    end }

    steps[#steps + 1] = { name = "cleanup (all synthetic rows)", always = true, fn = function(pass)
        if charA then Omerta.Identity.Internal.UnloadKnowledge(charA) end
        if charB then Omerta.Identity.Internal.UnloadKnowledge(charB) end
        purge(SID_A, function() purge(SID_B, function() pass() end) end)
    end }

    return steps
end

concommand.Add("omerta_identity_selftest", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    Omerta.SelfTest.Run("identity.selftest", buildSteps())
end)
