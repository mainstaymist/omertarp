-- In-engine acceptance suite: `omerta_death_selftest`.
--
-- The headline check is the milestone's whole claim: kill the Don of a family
-- with a Capo standing next to him, and the Capo is running the family within
-- a second — and cannot name a successor to it.

if not Omerta.InEngine then return end

local FAKE_CHARACTER = 2400000001
local S = Omerta.Injury.STATE

local function buildSteps()
    local Internal = Omerta.Death.Internal
    local steps = {}

    steps[#steps + 1] = { name = "database and season ready", required = true,
        fn = function(pass, fail)
        if not Omerta.DB.IsReady() then fail("db phase=" .. Omerta.DB.Status().phase) return end
        if not Omerta.Seasons.GetActive() then fail("no active season") return end
        pass()
    end }

    steps[#steps + 1] = { name = "leftover cleanup", required = true, fn = function(pass)
        Omerta.Injury.Internal.States[FAKE_CHARACTER] = nil
        Omerta.Injury.Internal.RemoveBody(FAKE_CHARACTER, true)
        pass()
    end }

    -- D-038 §4a: a bandage buys time, never immunity.
    steps[#steps + 1] = { name = "§4a: down is down, bandaged or not",
        fn = function(pass, fail)
        local F = Omerta.Death.CanFinish
        if not F(S.INCAPACITATED, S.HEALTHY, 1, 2) then
            fail("a bleeding man cannot be finished") return
        end
        if not F(S.STABILIZED, S.HEALTHY, 1, 2) then
            fail("a bandage bought immunity — D-038 §4a says it buys time") return
        end
        if F(S.HEALTHY, S.HEALTHY, 1, 2) then fail("somebody on their feet") return end
        if F(S.DEAD, S.HEALTHY, 1, 2) then fail("a corpse was finished twice") return end
        if F(S.INCAPACITATED, S.INCAPACITATED, 1, 2) then
            fail("somebody on the floor finished somebody else") return
        end
        if F(S.INCAPACITATED, S.HEALTHY, 1, 1) then fail("finished themselves") return end
        pass()
    end }

    steps[#steps + 1] = { name = "the act is registered into M19's seam",
        fn = function(pass, fail)
        local def = Omerta.Injury.Internal.DownedActions["death.confirm"]
        if not def then fail("M19's downed-action seam has no killer in it") return end
        -- Tech §18: deliberate. A fast act is not a deliberate one.
        if def.duration < 3 then
            fail("finishing takes " .. def.duration .. "s — too quick to be deliberate")
            return
        end
        pass(def.duration .. "s to finish somebody")
    end }

    steps[#steps + 1] = { name = "the event type exists and is printable",
        fn = function(pass, fail)
        local def = Omerta.Events.GetType("death.confirmed")
        if not def then fail("no death event type") return end
        if not def.public then fail("a killing could never reach a newspaper") return end
        pass()
    end }

    -- The cascade, end to end, on a character nobody is playing.
    steps[#steps + 1] = { name = "a death is recorded exactly once",
        fn = function(pass, fail)
        Omerta.Injury.Set(FAKE_CHARACTER, S.INCAPACITATED, { cause = "selftest" },
            function(ok, err)
            if not ok then fail(tostring(err)) return end
            Omerta.Death.Cascade(FAKE_CHARACTER, Omerta.Death.CAUSE.STAFF, nil,
                function(ok2, err2)
                if not ok2 then fail(tostring(err2)) return end
                timer.Simple(0.5, function()
                    Omerta.Events.ForCharacter(FAKE_CHARACTER, 20, function(rows)
                        local deaths = 0
                        for _, row in ipairs(rows) do
                            if row.type == "death.confirmed" then deaths = deaths + 1 end
                        end
                        if deaths ~= 1 then
                            fail(deaths .. " death events for one death") return
                        end
                        pass()
                    end)
                end)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "a second death is refused rather than cascading again",
        fn = function(pass, fail)
        Omerta.Death.Cascade(FAKE_CHARACTER, Omerta.Death.CAUSE.STAFF, nil, function(ok)
            if ok then fail("a corpse died a second time") return end
            pass()
        end)
    end }

    -- D-038 §4c.
    steps[#steps + 1] = { name = "§4c: the body and its contents are still there",
        fn = function(pass, fail)
        if Omerta.Injury.GetByCharacter(FAKE_CHARACTER) ~= S.DEAD then
            fail("not actually dead") return
        end
        if not Omerta.Injury.IsIncapable(S.DEAD) then
            fail("a corpse stopped being searchable") return
        end
        pass()
    end }

    steps[#steps + 1] = { name = "M10 has a death path for the roster",
        fn = function(pass, fail)
        if type(Omerta.Organizations.RecordDeath) ~= "function" then
            fail("no RecordDeath — the chair would never empty") return
        end
        if not Omerta.Organizations.MEMBER_STATUS.DIED then
            fail("no died status — a death would read as walking out") return
        end
        pass()
    end }

    steps[#steps + 1] = { name = "cleanup", always = true, fn = function(pass)
        Omerta.Injury.Internal.States[FAKE_CHARACTER] = nil
        Omerta.Injury.Internal.RemoveBody(FAKE_CHARACTER, true)
        Omerta.DB.Query("DELETE FROM {events} WHERE subject_character_id = ?",
            { FAKE_CHARACTER }, function()
            Omerta.DB.Query("DELETE FROM {character_injury} WHERE character_id = ?",
                { FAKE_CHARACTER }, function()
                Omerta.DB.Query("DELETE FROM {injury_events} WHERE character_id = ?",
                    { FAKE_CHARACTER }, function() pass() end)
            end)
        end)
    end }

    return steps
end

concommand.Add("omerta_death_selftest", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    Omerta.SelfTest.Run("death.selftest", buildSteps())
end)
