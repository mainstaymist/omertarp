-- In-engine acceptance suite: `omerta_injury_selftest`.
--
-- Drives a synthetic character through the whole state machine, including the
-- part D-037 made permanent, then cleans up after itself. The headline check
-- is the milestone's entire claim: lethal damage leaves you IN THE WORLD.

if not Omerta.InEngine then return end

local FAKE_CHARACTER = 2300000001
local S = Omerta.Injury.STATE

local function buildSteps()
    local Internal = Omerta.Injury.Internal
    local Repo = Internal.Repo
    local steps = {}

    steps[#steps + 1] = { name = "database and season ready", required = true,
        fn = function(pass, fail)
        if not Omerta.DB.IsReady() then fail("db phase=" .. Omerta.DB.Status().phase) return end
        if not Omerta.Seasons.GetActive() then fail("no active season") return end
        pass()
    end }

    steps[#steps + 1] = { name = "leftover cleanup from aborted runs", required = true,
        fn = function(pass)
        Internal.States[FAKE_CHARACTER] = nil
        Internal.RemoveBody(FAKE_CHARACTER, true)
        pass()
    end }

    -- The design of the milestone, in one table.
    steps[#steps + 1] = { name = "the legal-move table says what it should",
        fn = function(pass, fail)
        if not Omerta.Injury.CanTransition(S.HEALTHY, S.INCAPACITATED) then
            fail("you cannot be put down") return
        end
        if not Omerta.Injury.CanTransition(S.INCAPACITATED, S.STABILIZED) then
            fail("a bandage does nothing") return
        end
        -- Two steps on purpose: stopping the bleeding is not standing up.
        if Omerta.Injury.CanTransition(S.STABILIZED, S.HEALTHY) then
            fail("a bandage alone puts somebody back on their feet") return
        end
        if Omerta.Injury.CanTransition(S.DEAD, S.RECOVERING)
                or Omerta.Injury.CanTransition(S.DEAD, S.HEALTHY) then
            fail("the dead can be revived") return
        end
        pass()
    end }

    steps[#steps + 1] = { name = "D-037: the clock runs to death, not to an ambulance",
        fn = function(pass, fail)
        if Omerta.Injury.EXPIRES_TO[S.INCAPACITATED] ~= S.DEAD then
            fail("untreated incapacitation does not kill") return
        end
        if Omerta.Injury.EXPIRES_TO[S.STABILIZED] ~= S.RECOVERING then
            fail("a stabilized character never comes round") return
        end
        if Omerta.Config.Get("injury.bleed_out_seconds") < 60 then
            fail("the window is under a minute — being found is luck, not play") return
        end
        pass(Omerta.Config.Get("injury.bleed_out_seconds") .. "s to bleed out")
    end }

    steps[#steps + 1] = { name = "a condition is never described with a number",
        fn = function(pass, fail)
        for _, state in ipairs(Omerta.Injury.ORDER) do
            local text = Omerta.Injury.Describe(state)
            if text and text:find("%d") then
                fail(state .. " is described with a number (GDD §8)") return
            end
        end
        pass()
    end }

    steps[#steps + 1] = { name = "a character walks the states and the row follows",
        fn = function(pass, fail)
        Omerta.Injury.Set(FAKE_CHARACTER, S.INCAPACITATED, { cause = "selftest" },
            function(ok, err)
            if not ok then fail(tostring(err)) return end
            Omerta.Injury.Set(FAKE_CHARACTER, S.STABILIZED, { cause = "selftest" },
                function(ok2, err2)
                if not ok2 then fail(tostring(err2)) return end
                Repo.GetState(FAKE_CHARACTER, function(row)
                    if not row then fail("nothing persisted") return end
                    if row.state ~= S.STABILIZED then
                        fail("persisted " .. tostring(row.state)) return
                    end
                    if not row.expires_at then
                        fail("no deadline stored — a restart would heal them") return
                    end
                    pass()
                end)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "an illegal transition is refused, not applied",
        fn = function(pass, fail)
        -- Currently stabilized; healthy is not reachable without treatment.
        Omerta.Injury.Set(FAKE_CHARACTER, S.HEALTHY, { cause = "selftest" },
            function(ok)
            if ok then fail("a stabilized character stood up unaided") return end
            if Omerta.Injury.GetByCharacter(FAKE_CHARACTER) ~= S.STABILIZED then
                fail("the refused move changed the state anyway") return
            end
            pass()
        end)
    end }

    steps[#steps + 1] = { name = "treatment reaches recovering", fn = function(pass, fail)
        Omerta.Injury.Set(FAKE_CHARACTER, S.RECOVERING, { cause = "selftest" },
            function(ok, err)
            if not ok then fail(tostring(err)) return end
            local entry = Omerta.Injury.EntryFor(FAKE_CHARACTER)
            if not (entry and entry.expiresAt) then fail("no recovery clock") return end
            pass()
        end)
    end }

    steps[#steps + 1] = { name = "§4c: recovery costs something, and it decays",
        fn = function(pass, fail)
        local worst = Omerta.Config.Get("injury.recovery_speed_scale")
        local atStart = Omerta.Injury.RecoveryMultiplier(1, worst)
        local atEnd = Omerta.Injury.RecoveryMultiplier(0, worst)
        if atStart >= 1 then fail("standing up costs nothing") return end
        if math.abs(atEnd - 1) > 0.001 then fail("the penalty never wears off") return end
        pass(string.format("%.2f -> 1.00", atStart))
    end }

    steps[#steps + 1] = { name = "every state change is on the record",
        fn = function(pass, fail)
        Repo.EventsFor(FAKE_CHARACTER, 20, function(rows)
            if #rows < 3 then
                fail("only " .. #rows .. " event(s) for four transitions") return
            end
            for _, row in ipairs(rows) do
                if not row.to_state or row.to_state == "" then
                    fail("an event has no destination") return
                end
            end
            pass(#rows .. " event(s)")
        end)
    end }

    steps[#steps + 1] = { name = "the seams M17 and M20 register into exist",
        fn = function(pass, fail)
        if type(Omerta.Injury.RegisterDownedAction) ~= "function" then
            fail("no downed-action seam") return
        end
        if type(Omerta.Injury.Die) ~= "function" then
            fail("no death funnel — M20 would have to build its own") return
        end
        if not (Internal.Treatments["injury.stabilize"]
                and Internal.Treatments["injury.treat"]) then
            fail("M19's own treatments are not registered") return
        end
        pass()
    end }

    steps[#steps + 1] = { name = "a body is searched through M9, not a second path",
        fn = function(pass, fail)
        if type(Omerta.Inventory.RegisterOpenable) ~= "function" then
            fail("M9 has no openable seam") return
        end
        pass()
    end }

    -- §4a: a body is a PERSON. It must never name itself, and the character it
    -- belongs to must never leave the server.
    steps[#steps + 1] = { name = "a body publishes nothing about who it is",
        fn = function(pass, fail)
        -- Bodies are prop_ragdolls now, tagged with a boolean that says
        -- "somebody is on the floor here" — visible from across the street
        -- anyway — and nothing else.
        for _, ent in ipairs(ents.FindByClass("prop_ragdoll")) do
            if ent.OmertaCharacter then
                for _, key in ipairs({ "OmertaCharacter", "CharacterId", "Character" }) do
                    if ent:GetNWInt(key, -1) ~= -1 or ent:GetNWString(key, "") ~= "" then
                        fail("a body networks " .. key) return
                    end
                end
            end
        end
        pass()
    end }

    -- The presentation curves. Cheap to check, and the kind of thing that
    -- silently inverts when somebody retunes a number.
    steps[#steps + 1] = { name = "the screen closes in, and the clock empties",
        fn = function(pass, fail)
        local V = Omerta.Injury.VignetteReach
        if V(0, 0) >= V(1, 0) then fail("the vignette does not close in") return end
        if V(1, 0) > 0.95 then fail("the vignette would black the screen out") return end
        if Omerta.Injury.PulseRate(1) <= Omerta.Injury.PulseRate(0) then
            fail("the heartbeat does not quicken") return
        end
        local F = Omerta.Injury.DeathFade
        if F(0) ~= 0 then fail("the death fade starts already black") return end
        if F(60) ~= 1 then fail("the death fade never finishes") return end
        pass()
    end }

    steps[#steps + 1] = { name = "cleanup", always = true, fn = function(pass)
        Internal.States[FAKE_CHARACTER] = nil
        Internal.RemoveBody(FAKE_CHARACTER, true)
        Omerta.DB.Query("DELETE FROM {character_injury} WHERE character_id = ?",
            { FAKE_CHARACTER }, function()
            Omerta.DB.Query("DELETE FROM {injury_events} WHERE character_id = ?",
                { FAKE_CHARACTER }, function() pass() end)
        end)
    end }

    return steps
end

concommand.Add("omerta_injury_selftest", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    Omerta.SelfTest.Run("injury.selftest", buildSteps())
end)
