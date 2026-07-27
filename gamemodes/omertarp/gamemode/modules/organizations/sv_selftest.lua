-- In-engine acceptance suite: `omerta_org_selftest`.
--
-- Drives a synthetic family through the whole promotion chain: members added,
-- ranks guarded against races, the rules refusing what they should, authority
-- descending when the leader is away, and an expulsion leaving history behind
-- rather than a hole. Cleans up after itself.

if not Omerta.InEngine then return end

local FAKE_KEY = "selftest_family"
-- Deliberately out of range of any real character id.
local DON, UNDERBOSS, CAPO, SOLDIER = 2100000001, 2100000002, 2100000003, 2100000004

local function buildSteps()
    local Internal = Omerta.Organizations.Internal
    local Repo = Internal.Repo
    local P = Omerta.Organizations.PERMISSIONS
    local orgId = nil

    local steps = {}

    steps[#steps + 1] = { name = "database and season ready", required = true, fn = function(pass, fail)
        if not Omerta.DB.IsReady() then fail("db phase=" .. Omerta.DB.Status().phase) return end
        if not Omerta.Seasons.GetActive() then fail("no active season") return end
        pass()
    end }

    steps[#steps + 1] = { name = "the season's institutions exist", fn = function(pass, fail)
        local all = Omerta.Organizations.All()
        if #all == 0 then fail("no institutions were created for this season") return end

        local active, families = 0, 0
        for _, row in ipairs(all) do
            if row.status == Omerta.Organizations.STATUS.ACTIVE then active = active + 1 end
            if row.type == Omerta.Organizations.TYPE.FAMILY then families = families + 1 end
        end
        if families ~= 4 then fail("expected 4 families, got " .. families) return end
        if not Omerta.Organizations.Get("police") then fail("no police department") return end
        pass(#all .. " institutions, " .. active .. " active")
    end }

    steps[#steps + 1] = { name = "ladders are coherent and cumulative", fn = function(pass, fail)
        for _, id in ipairs({ "family", "police" }) do
            local top = Omerta.Organizations.TopRank(id)
            if top < 2 then fail("ladder '" .. id .. "' is too short") return end
            if not Omerta.Organizations.Grants(id, top, P.LEAD) then
                fail("the top of '" .. id .. "' does not lead") return
            end
            if Omerta.Organizations.Grants(id, 1, P.PROMOTE) then
                fail("the bottom of '" .. id .. "' can promote") return
            end
            -- Cumulative: nothing held at a rung may be lost higher up.
            for rank = 2, top do
                local below = Omerta.Organizations.PermissionsAt(id, rank - 1)
                local here = Omerta.Organizations.PermissionsAt(id, rank)
                for permission in pairs(below) do
                    if not here[permission] then
                        fail(id .. " rank " .. rank .. " lost '" .. permission .. "'") return
                    end
                end
            end
        end
        pass()
    end }

    steps[#steps + 1] = { name = "leftover cleanup from aborted runs", required = true,
        fn = function(pass, fail)
        local season = Omerta.Seasons.GetActive()
        Repo.FindByKey(season.id, FAKE_KEY, function(row, err)
            if err then fail(tostring(err)) return end
            if not row then pass("nothing to clean") return end
            Repo.DeleteMembers(row.id, function(ok)
                if not ok then fail("could not clear members") return end
                Repo.DeleteOrganization(row.id, function(ok2)
                    if ok2 then pass("cleared a previous run") else fail("could not delete") end
                end)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "a family is created with a roster", required = true,
        fn = function(pass, fail)
        local season = Omerta.Seasons.GetActive()
        Repo.Create(season.id, FAKE_KEY, "family", "active", os.time(), function(id, err)
            if not id then fail(tostring(err)) return end
            orgId = id

            local roster = {
                { DON, 6 }, { UNDERBOSS, 5 }, { CAPO, 4 }, { SOLDIER, 3 },
            }
            local function addNext(i)
                if i > #roster then
                    Repo.SetLeader(orgId, DON, function(ok, serr)
                        if not ok then fail(tostring(serr)) return end
                        Repo.ListMembers(orgId, function(members)
                            if #members ~= 4 then
                                fail("expected 4 members, got " .. #members) return
                            end
                            -- Ordered by rank descending, so the Don is first.
                            if members[1].character_id ~= DON then
                                fail("the roster is not ordered by rank") return
                            end
                            pass("four members, the Don at the top")
                        end)
                    end)
                    return
                end
                Repo.AddMember(orgId, roster[i][1], roster[i][2], nil, os.time(),
                    function(ok, aerr)
                        if not ok then fail(tostring(aerr)) return end
                        addNext(i + 1)
                    end)
            end
            addNext(1)
        end)
    end }

    steps[#steps + 1] = { name = "the rank rules refuse what they should", fn = function(pass, fail)
        local C = Omerta.Organizations.CanSetRank

        -- An Underboss (5) promoting a Soldier (3) to Capo (4): allowed.
        if not C("family", 5, 3, 4) then fail("an underboss should be able to make a capo") return end

        -- Nobody makes an equal or a superior, whatever their rank.
        if C("family", 5, 3, 5) then fail("an underboss made an equal") return end
        if C("family", 5, 3, 6) then fail("an underboss made a Don") return end
        -- You cannot act on someone who outranks you, or on your own equal.
        if C("family", 4, 5, 3) then fail("a capo demoted an underboss") return end
        if C("family", 4, 4, 3) then fail("a capo acted on an equal") return end
        -- A Soldier has neither promote nor demote.
        if C("family", 3, 2, 1) then fail("a soldier demoted somebody") return end
        -- Ranks off the end of the ladder are not ranks.
        if C("family", 6, 3, 99) then fail("rank 99 was accepted") return end
        if C("family", 6, 3, 0) then fail("rank 0 was accepted") return end
        pass()
    end }

    steps[#steps + 1] = { name = "a promotion is guarded against a stale rank", fn = function(pass, fail)
        -- Promote the soldier to capo, believing they are a soldier: works.
        Repo.SetRank(orgId, SOLDIER, 4, 3, function(changed, err)
            if err then fail(tostring(err)) return end
            if not changed then fail("the promotion did not apply") return end

            -- The same promotion again, still believing rank 3: must not apply,
            -- because they are no longer a soldier. This is what stops two
            -- racing promotions from landing somebody two rungs up.
            Repo.SetRank(orgId, SOLDIER, 5, 3, function(changed2, err2)
                if err2 then fail(tostring(err2)) return end
                if changed2 then fail("a stale promotion was applied") return end
                Repo.GetMembership(SOLDIER, function(member)
                    if not member or member.rank ~= 4 then
                        fail("rank ended at " .. tostring(member and member.rank)) return
                    end
                    pass("promoted once, the stale repeat refused")
                end)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "authority descends when the leader is away", fn = function(pass, fail)
        Repo.ListMembers(orgId, function(members)
            local Compute = Internal.ComputeActing

            -- Everyone present: the Don holds his own authority.
            local holder, acting = Compute("family", members, DON, function() return true end)
            if holder ~= DON or acting then fail("the Don should hold it himself") return end

            -- The Don away: it goes to the Underboss, and is marked acting.
            holder, acting = Compute("family", members, DON,
                function(id) return id ~= DON end)
            if holder ~= UNDERBOSS or not acting then
                fail("expected the underboss to be acting, got " .. tostring(holder)) return
            end

            -- Both away: the highest authorised Capo, with limited authority.
            holder, acting = Compute("family", members, DON,
                function(id) return id ~= DON and id ~= UNDERBOSS end)
            if holder ~= CAPO or not acting then
                fail("expected a capo to be acting, got " .. tostring(holder)) return
            end

            -- Nobody in the room: nobody holds it. An organization with no one
            -- present does not need a decision made.
            holder = Compute("family", members, DON, function() return false end)
            if holder ~= nil then fail("somebody held authority from an empty room") return end
            pass("Don, then underboss, then capo, then nobody")
        end)
    end }

    steps[#steps + 1] = { name = "leaving is history, not deletion", fn = function(pass, fail)
        Repo.SetMemberStatus(orgId, SOLDIER, Omerta.Organizations.MEMBER_STATUS.EXPELLED,
            os.time(), function(ok, err)
            if not ok then fail(tostring(err)) return end

            Repo.GetMembership(SOLDIER, function(member)
                if member then fail("an expelled member still reads as a member") return end
                Repo.ListMembers(orgId, function(members)
                    if #members ~= 3 then
                        fail("expected 3 remaining, got " .. #members) return
                    end
                    -- The row is still there: who was in the family in week two
                    -- has to stay answerable.
                    Repo.GetMemberRow(orgId, SOLDIER, function(row)
                        if not row then fail("the history row was deleted") return end
                        if row.status ~= "expelled" then
                            fail("status reads " .. tostring(row.status)) return
                        end
                        if not row.left_at or row.left_at == 0 then
                            fail("no departure time was recorded") return
                        end
                        pass("expelled, and still on the books")
                    end)
                end)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "cleanup", always = true, fn = function(pass, fail)
        if not orgId then pass("nothing was created") return end
        Repo.DeleteMembers(orgId, function(ok, err)
            if not ok then fail(tostring(err)) return end
            Repo.DeleteOrganization(orgId, function(ok2, err2)
                if ok2 then pass() else fail(tostring(err2)) end
            end)
        end)
    end }

    return steps
end

concommand.Add("omerta_org_selftest", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    Omerta.SelfTest.Run("organizations.selftest", buildSteps())
end)
