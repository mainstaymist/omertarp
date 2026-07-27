-- In-engine acceptance suite: `omerta_characters_selftest`. Operates on a
-- synthetic account against the live season using the repository directly —
-- no real player, no cache mutation — and removes everything it creates.

if not Omerta.InEngine then return end

local SID = "90000000000000004"
-- Smallest valid JPEG-ish payload: a real SOI marker plus filler. Enough to
-- exercise validation, storage, and retrieval without shipping a real image.
local FAKE_JPEG = string.char(0xFF, 0xD8, 0xFF) .. string.rep("A", 64)

local function buildSteps()
    local Repo = Omerta.Characters.Internal.Repo
    local ARepo = Omerta.Accounts.Internal.Repo
    local steps = {}

    local account, seasonId, characterId
    local base64 = util.Base64Encode(FAKE_JPEG, true)

    steps[#steps + 1] = { name = "database and season ready", fn = function(pass, fail)
        if not Omerta.DB.IsReady() then fail("db phase=" .. Omerta.DB.Status().phase) return end
        local season = Omerta.Seasons.GetActive()
        if not season then
            fail("no active season — run omerta_season_create/start first")
            return
        end
        seasonId = season.id
        pass("season #" .. seasonId)
    end }

    steps[#steps + 1] = { name = "leftover cleanup from aborted runs", fn = function(pass, fail)
        ARepo.FetchBySteamID64(SID, function(existing)
            if not existing then pass("nothing to clean") return end
            Repo.DeleteForAccount(existing.id, function()
                ARepo.DeleteAccountData(existing.id, SID, function() pass("removed stale rows") end)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "synthetic account", fn = function(pass, fail)
        ARepo.LoadOrCreate(SID, os.time(), function(a, err)
            if not a then fail(tostring(err)) return end
            account = a
            pass("account #" .. a.id)
        end)
    end }

    steps[#steps + 1] = { name = "create character", fn = function(pass, fail)
        local first, last, key = Omerta.Characters.ValidateName("Salvatore", "o'brien")
        if not first then fail(last) return end
        if last ~= "O'Brien" then fail("normalization wrong: " .. last) return end
        Repo.Create({
            account_id = account.id, season_id = seasonId,
            first_name = first, last_name = last, name_key = key,
            status = Omerta.Characters.STATUS.ALIVE,
            model = Omerta.Characters.MODELS[1], skin = 0, created_at = os.time(),
        }, function(id, err)
            if not id then fail(tostring(err)) return end
            characterId = id
            pass("#" .. id .. " " .. first .. " " .. last)
        end)
    end }

    steps[#steps + 1] = { name = "duplicate name in the same season is refused", fn = function(pass, fail)
        local first, last, key = Omerta.Characters.ValidateName("SALVATORE", "O'BRIEN")
        if key ~= "salvatore o'brien" then fail("key mismatch: " .. tostring(key)) return end
        Repo.Create({
            account_id = account.id, season_id = seasonId,
            first_name = first, last_name = last, name_key = key,
            status = Omerta.Characters.STATUS.ALIVE,
            model = Omerta.Characters.MODELS[1], skin = 0, created_at = os.time(),
        }, function(id)
            if id then fail("duplicate insert succeeded (unique index missing?)") return end
            pass("refused by the unique index")
        end)
    end }

    steps[#steps + 1] = { name = "active-character lookup finds it", fn = function(pass, fail)
        Repo.GetActiveFor(account.id, seasonId, function(character, err)
            if err then fail(err) return end
            if not character or character.id ~= characterId then
                fail("lookup returned " .. tostring(character and character.id)) return
            end
            if character.status ~= "alive" then fail("status " .. character.status) return end
            pass()
        end)
    end }

    steps[#steps + 1] = { name = "portrait validation rejects junk", fn = function(pass, fail)
        local ok = Omerta.Characters.Internal.ValidatePortrait(
            util.Base64Encode("not a jpeg at all", true), 49152, util.Base64Decode)
        if ok then fail("non-JPEG accepted") return end
        local ok2 = Omerta.Characters.Internal.ValidatePortrait(
            base64, 8, util.Base64Decode)
        if ok2 then fail("oversized image accepted") return end
        pass("magic bytes and size enforced")
    end }

    steps[#steps + 1] = { name = "portrait stores and reads back", fn = function(pass, fail)
        Repo.SetPortrait(characterId, base64, os.time(), function(ok, err)
            if not ok then fail(tostring(err)) return end
            Repo.GetPortrait(characterId, function(stored, gerr)
                if gerr then fail(gerr) return end
                if stored ~= base64 then
                    fail("round-trip mismatch (" .. tostring(stored and #stored) .. " bytes)")
                    return
                end
                pass(#base64 .. " bytes base64")
            end)
        end)
    end }

    steps[#steps + 1] = { name = "portrait is immutable once set", fn = function(pass, fail)
        local other = util.Base64Encode(FAKE_JPEG .. "B", true)
        Repo.SetPortrait(characterId, other, os.time(), function()
            Repo.GetPortrait(characterId, function(stored)
                if stored ~= base64 then fail("portrait was overwritten") return end
                pass("second upload ignored")
            end)
        end)
    end }

    steps[#steps + 1] = { name = "retire", fn = function(pass, fail)
        Repo.SetStatus(characterId, Omerta.Characters.STATUS.RETIRED, os.time(), function(ok, err)
            if not ok then fail(tostring(err)) return end
            Repo.GetActiveFor(account.id, seasonId, function(character)
                if character then fail("retired character still active") return end
                pass()
            end)
        end)
    end }

    steps[#steps + 1] = { name = "cleanup (all synthetic rows)", fn = function(pass, fail)
        Repo.DeleteForAccount(account.id, function(ok, err)
            if not ok then fail(tostring(err)) return end
            ARepo.DeleteAccountData(account.id, SID, function(ok2, err2)
                if not ok2 then fail(tostring(err2)) return end
                pass()
            end)
        end)
    end }

    return steps
end

concommand.Add("omerta_characters_selftest", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    Omerta.SelfTest.Run("characters.selftest", buildSteps())
end)
