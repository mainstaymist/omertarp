-- Server-authoritative institutions: rosters, promotion, succession.
--
-- The client asks; the server decides. Every rank change is checked against
-- the actor's own permissions and their own position on the ladder, so
-- "promote myself to Don" is not a thing that can be expressed, let alone
-- forbidden. Every membership event is audited, because "who let him in" is
-- the first question staff will ever ask about a leak.

local MODULE = Omerta.Module.Get("organizations")

Omerta.Organizations = Omerta.Organizations or {}
Omerta.Organizations.Internal = Omerta.Organizations.Internal or {}
local Internal = Omerta.Organizations.Internal
local P = Omerta.Organizations.PERMISSIONS
local STATUS = Omerta.Organizations.STATUS
local MEMBER = Omerta.Organizations.MEMBER_STATUS

Omerta.Config.Define("organizations.active_families", {
    type = "number", default = 2, min = 1, max = 4, scope = "server",
    description = "How many crime families are active at the start of a season (D-022).",
})
Omerta.Config.Define("organizations.acting_timeout", {
    type = "number", default = 300, min = 0, max = 3600, scope = "server",
    description = "Seconds a leader may be offline before authority descends (Tech §19).",
})
Omerta.Config.Define("organizations.induction_range", {
    type = "number", default = 256, min = 64, max = 1024, scope = "server",
    description = "How near you must be to an induction to be introduced by it (D-023).",
})
Omerta.Config.Define("organizations.invite_timeout", {
    type = "number", default = 60, min = 10, max = 300, scope = "server",
    description = "Seconds an offer of membership stays open.",
})

--------------------------------------------------------------------------------
-- Runtime state
--------------------------------------------------------------------------------

local instances = {}     -- key -> organization row
local instancesById = {} -- id -> organization row
local membership = {}    -- characterId -> membership row (connected characters)
local offlineSince = {}  -- characterId -> CurTime() when they left
local pendingInvites = {} -- target steamid64 -> { org, sponsor, rank, expires }

function Omerta.Organizations.Get(key) return instances[key] end
function Omerta.Organizations.GetById(id) return instancesById[id] end

function Omerta.Organizations.All()
    local out = {}
    for _, def in ipairs(Omerta.Organizations.GetDefinitions()) do
        if instances[def.key] then out[#out + 1] = instances[def.key] end
    end
    return out
end

function Omerta.Organizations.MembershipOf(characterId)
    return membership[characterId]
end

local function definitionFor(row)
    return row and Omerta.Organizations.GetDefinition(row.org_key or row.key) or nil
end

--------------------------------------------------------------------------------
-- Authority
--------------------------------------------------------------------------------

local function characterIsOnline(characterId)
    for _, ply in ipairs(player.GetAll()) do
        local character = Omerta.Characters.Get(ply)
        if character and character.id == characterId then return ply end
    end
    return nil
end

-- A leader who has just dropped out is still the leader: authority descends
-- only once they have been gone longer than the timeout, so a thirty-second
-- crash does not hand the family to the Underboss (Tech §19).
local function availabilityFor(org)
    local timeout = Omerta.Config.Get("organizations.acting_timeout")
    local now = Omerta.InEngine and CurTime() or 0
    return function(characterId)
        if characterIsOnline(characterId) then return true end
        if characterId ~= org.leader_character_id then return false end
        local since = offlineSince[characterId]
        return since ~= nil and (now - since) < timeout
    end
end

-- cb(characterId, isActing). Reads the roster, so it is asynchronous; the
-- permission path below uses the cached answer instead.
function Omerta.Organizations.ActingAuthority(orgId, cb)
    local org = instancesById[orgId]
    if not (org and definitionFor(org)) then cb(nil, false) return end
    Internal.Repo.ListMembers(orgId, function(members)
        local def = definitionFor(org)
        cb(Internal.ComputeActing(def.ladder, members, org.leader_character_id,
            availabilityFor(org)))
    end)
end

-- Recomputed whenever the roster or the connected set changes, so Can() stays
-- a synchronous question. orgId -> characterId currently acting (nil if the
-- seated leader is present or nobody qualifies).
local actingHolder = {}

local function refreshActing(orgId)
    local org = instancesById[orgId]
    if not org then return end
    -- A row whose institution is no longer defined (an old season, a family
    -- removed from a later version) has no ladder to descend and is skipped
    -- rather than crashing the timer that would visit it every 30 seconds.
    if not definitionFor(org) then return end
    Internal.Repo.ListMembers(orgId, function(members)
        local def = definitionFor(org)
        local holder, isActing = Internal.ComputeActing(def.ladder, members,
            org.leader_character_id, availabilityFor(org))
        actingHolder[orgId] = isActing and holder or nil
    end)
end

local function refreshAllActing()
    for id in pairs(instancesById) do refreshActing(id) end
end

-- The rank a character's permissions are computed at. Normally their own; if
-- they are currently holding authority for an absent leader, the highest rung
-- BELOW the leader's — deliberately limited, so an acting Capo can run the
-- family but cannot name a successor to it (Tech §19).
function Omerta.Organizations.EffectiveRank(characterId)
    local member = membership[characterId]
    if not member then return nil, nil end
    local def = definitionFor(member)
    if not def then return nil, nil end

    local rank = member.rank
    if actingHolder[member.organization_id] == characterId then
        rank = math.max(rank, Omerta.Organizations.TopRank(def.ladder) - 1)
    end
    return rank, def
end

-- The only question gameplay ever asks about an institution.
function Omerta.Organizations.Can(characterId, permission)
    local rank, def = Omerta.Organizations.EffectiveRank(characterId)
    if not rank then return false end
    return Omerta.Organizations.Grants(def.ladder, rank, permission)
end

function Omerta.Organizations.Leader(orgId)
    local org = instancesById[orgId]
    return org and org.leader_character_id or nil
end

--------------------------------------------------------------------------------
-- Uniforms (§4c, D-021)
--------------------------------------------------------------------------------

-- Visibility rides on the garment, not the badge. An officer who has left the
-- uniform at home is a stranger, which is exactly what makes plain clothes a
-- decision rather than a costume.
function Omerta.Organizations.IsInUniform(character)
    if not character then return false end
    local member = membership[character.id]
    if not member then return false end
    local def = definitionFor(member)
    if not (def and def.public) then return false end

    for _, row in ipairs(Omerta.Inventory.Get({ type = "character", id = character.id })) do
        if row.def_id == Omerta.Organizations.UNIFORM_ITEM and row.equipped_slot then
            return true
        end
    end
    return false
end

-- The title a stranger reads off a uniform: the rank, not the name.
function Omerta.Organizations.PublicTitleFor(character)
    if not Omerta.Organizations.IsInUniform(character) then return nil end
    local member = membership[character.id]
    local def = definitionFor(member)
    local rung = Omerta.Organizations.RankAt(def.ladder, member.rank)
    return rung and rung.name or nil
end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

-- Creates any institution this season is missing. Existing rows are left
-- exactly as they are, so a status a staff member changed by hand survives
-- every restart.
function Internal.EnsureInstances(season, cb)
    cb = cb or function() end
    Internal.Repo.ListForSeason(season.id, function(rows, err)
        if err then
            Omerta.Log.Error("organizations", "could not read institutions: %s", err)
            cb(false)
            return
        end

        local existing = {}
        for _, row in ipairs(rows) do existing[row.key] = row end

        local plan = Internal.PlanActive(Omerta.Organizations.GetDefinitions(),
            Omerta.Config.Get("organizations.active_families"))

        local missing = {}
        for _, def in ipairs(Omerta.Organizations.GetDefinitions()) do
            if not existing[def.key] then missing[#missing + 1] = def end
        end

        local function createNext(i)
            if i > #missing then
                Internal.LoadInstances(season, cb)
                return
            end
            local def = missing[i]
            Internal.Repo.Create(season.id, def.key, def.type, plan[def.key], os.time(),
                function(_, cerr)
                    if cerr then
                        Omerta.Log.Error("organizations", "could not create '%s': %s", def.key, cerr)
                    end
                    createNext(i + 1)
                end)
        end
        createNext(1)
    end)
end

function Internal.LoadInstances(season, cb)
    cb = cb or function() end
    Internal.Repo.ListForSeason(season.id, function(rows, err)
        if err then cb(false) return end
        instances, instancesById = {}, {}
        local active = 0
        for _, row in ipairs(rows) do
            instances[row.key] = row
            instancesById[row.id] = row
            if row.status == STATUS.ACTIVE then active = active + 1 end
        end
        Omerta.Log.Info("organizations", "%d institution(s) this season, %d active",
            #rows, active)
        refreshAllActing()
        cb(true)
    end)
end

function Internal.LoadMembership(ply, character, cb)
    cb = cb or function() end
    Internal.Repo.GetMembership(character.id, function(row, err)
        if err then
            Omerta.Log.Error("organizations", "membership load failed for #%d: %s",
                character.id, err)
            cb(false)
            return
        end
        membership[character.id] = row
        offlineSince[character.id] = nil
        if row then refreshActing(row.organization_id) end
        Internal.PushSelf(ply)
        cb(true)
    end)
end

--------------------------------------------------------------------------------
-- Telling a client about itself
--------------------------------------------------------------------------------

function Internal.PushSelf(ply)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    local character = Omerta.Characters.Get(ply)
    if not character then return end

    local member = membership[character.id]
    if not member then
        Omerta.Net.Send("org.self", { org = 0, rank = 0, perms = 0 }, ply)
        return
    end

    local def = definitionFor(member)
    local rank = Omerta.Organizations.EffectiveRank(character.id) or member.rank
    Omerta.Net.Send("org.self", {
        org = Omerta.Organizations.IndexOf(def.key) or 0,
        rank = member.rank,
        perms = Omerta.Organizations.PermissionBits(def.ladder, rank),
    }, ply)
end

-- The roster is the institution's own books. Reading it teaches a NAME, never
-- a face: it does not call Omerta.Identity.Learn, so a Don who reads that a
-- Tony Marino is a soldier still cannot pick him out of a crowd until someone
-- introduces them (D-014's knowledge/recognition split, applied literally).
function Internal.SendRoster(ply)
    local character = Omerta.Characters.Get(ply)
    if not character then return end
    local member = membership[character.id]
    if not member then return end
    if not Omerta.Organizations.Can(character.id, P.ROSTER) then
        Omerta.Chat.Notice(ply, "You are not senior enough to see who else is in.")
        return
    end

    Internal.Repo.ListMembers(member.organization_id, function(members)
        local def = definitionFor(member)
        if #members == 0 then return end

        for index, row in ipairs(members) do
            Omerta.Characters.GetByID(row.character_id, function(subject)
                local rung = Omerta.Organizations.RankAt(def.ladder, row.rank)
                if IsValid(ply) then
                    Omerta.Net.Send("org.roster_entry", {
                        name = subject
                            and (subject.first_name .. " " .. subject.last_name)
                            or "(unknown)",
                        rank = row.rank,
                        last = index == #members,
                        online = characterIsOnline(row.character_id) ~= nil,
                    }, ply)
                end
            end)
        end
    end)
end

--------------------------------------------------------------------------------
-- Joining
--------------------------------------------------------------------------------

-- D-009's transition matrix, applied where recruitment actually happens.
-- Returns true, or false + reason.
function Internal.MayJoin(def, path)
    if def.type == Omerta.Organizations.TYPE.POLICE then
        -- Cross-side transitions never occur within a season, so the police
        -- recruit only from players who chose that path at season start.
        if path ~= "police" then
            return false, "they did not join the force this season"
        end
        return true
    end
    if path == "police" then
        return false, "an officer cannot be brought into a family this season"
    end
    return true
end

function Omerta.Organizations.Invite(sponsorPly, targetPly, cb)
    cb = cb or function() end
    if not (Omerta.InEngine and IsValid(sponsorPly) and IsValid(targetPly)) then
        cb(false, "nobody there") return
    end

    local sponsor = Omerta.Characters.Get(sponsorPly)
    local target = Omerta.Characters.Get(targetPly)
    if not (sponsor and target) then cb(false, "both of you need a character") return end
    if sponsor.id == target.id then cb(false, "you are already in") return end

    local member = membership[sponsor.id]
    if not member then cb(false, "you are not in anything") return end
    if not Omerta.Organizations.Can(sponsor.id, P.INVITE) then
        cb(false, "that is not yours to offer") return
    end

    local org = instancesById[member.organization_id]
    if not org or org.status ~= STATUS.ACTIVE then cb(false, "your organization is not active") return end
    if membership[target.id] then cb(false, "they are spoken for") return end

    local def = definitionFor(member)
    local ok, why = Internal.MayJoin(def, Omerta.Seasons.GetPath(targetPly))
    if not ok then cb(false, why) return end

    pendingInvites[targetPly:SteamID64() or ""] = {
        organizationId = org.id,
        sponsorId = sponsor.id,
        sponsorSid = sponsorPly:SteamID64(),
        expires = CurTime() + Omerta.Config.Get("organizations.invite_timeout"),
    }
    Omerta.Net.Send("org.invite", {
        from = sponsorPly:EntIndex(),
        org = Omerta.Organizations.IndexOf(def.key) or 0,
        -- The sponsor is standing in front of them offering; their name is
        -- resolved through the recipient's own knowledge like any other line.
        name = Omerta.Identity.ResolveDisplayName(target, sponsor,
            Omerta.Identity.GetKnownName(target.id, sponsor.id)),
    }, targetPly)
    cb(true)
end

-- §4b, D-023: being made is an EVENT that happens in a room. Everyone from the
-- organization who is present learns the newcomer and the newcomer learns
-- them, through M5's ordinary machinery — no magical grant, and nothing at all
-- for the members who were not there.
local function induct(newPly, newChar, orgId)
    local range = Omerta.Config.Get("organizations.induction_range")
    local witnesses = 0
    for _, other in ipairs(player.GetAll()) do
        local otherChar = Omerta.Characters.Get(other)
        if otherChar and otherChar.id ~= newChar.id
                and membership[otherChar.id]
                and membership[otherChar.id].organization_id == orgId
                and newPly:GetPos():Distance(other:GetPos()) <= range then
            local newName = newChar.first_name .. " " .. newChar.last_name
            local otherName = otherChar.first_name .. " " .. otherChar.last_name
            Omerta.Identity.Learn(otherChar.id, newChar.id, newName, "introduction")
            Omerta.Identity.Learn(newChar.id, otherChar.id, otherName, "introduction")
            witnesses = witnesses + 1
        end
    end
    return witnesses
end

function Internal.HandleInviteReply(ply, accept)
    if not Omerta.InEngine then return end
    local sid = ply:SteamID64() or ""
    local invite = pendingInvites[sid]
    pendingInvites[sid] = nil
    if not (accept and invite) then return end
    if CurTime() > invite.expires then
        Omerta.Chat.Notice(ply, "That offer has expired.")
        return
    end

    local character = Omerta.Characters.Get(ply)
    if not character then return end
    if membership[character.id] then return end

    local org = instancesById[invite.organizationId]
    if not (org and org.status == STATUS.ACTIVE) then return end

    local def = definitionFor(org)
    local ok, why = Internal.MayJoin(def, Omerta.Seasons.GetPath(ply))
    if not ok then Omerta.Chat.Notice(ply, why) return end

    Internal.Repo.AddMember(org.id, character.id, 1, invite.sponsorId, os.time(),
        function(added, err)
        if not added then
            Omerta.Log.Error("organizations", "could not add member: %s", tostring(err))
            return
        end

        Omerta.Log.Audit("organization.joined", {
            actor = sid, character_id = character.id,
            data = { organization = def.key, rank = 1, sponsor = invite.sponsorId },
        })

        -- D-009: family recruitment is what performs the one-way independent
        -- to criminal transition. It happens here or it happens nowhere.
        if def.type == Omerta.Organizations.TYPE.FAMILY
                and Omerta.Seasons.GetPath(ply) == "independent" then
            Omerta.Seasons.ConvertToCriminal(ply)
        end

        Internal.LoadMembership(ply, character, function()
            local witnesses = induct(ply, character, org.id)
            Omerta.Chat.Notice(ply, "You are in. " .. def.name .. ".")
            if witnesses > 0 then
                Omerta.Log.Info("organizations", "%d member(s) witnessed the induction",
                    witnesses)
            end
            -- A public institution issues a uniform, because §4c's visibility
            -- rides on the garment and an officer without one is invisible.
            if def.public then Internal.IssueUniform(ply) end
        end)
    end)
end

function Internal.IssueUniform(ply)
    local item = Omerta.Organizations.UNIFORM_ITEM
    for _, row in ipairs(Omerta.Inventory.Get(ply)) do
        if row.def_id == item then return end
    end
    Omerta.Inventory.Add(ply, item, 1, { force = true }, function(ok, err)
        if not ok then
            Omerta.Log.Error("organizations", "uniform issue failed: %s", tostring(err))
        end
    end)
end

--------------------------------------------------------------------------------
-- Rank changes
--------------------------------------------------------------------------------

-- actorPly may be nil for staff actions, which bypass the ladder checks by
-- design and are audited as staff actions rather than as promotions.
function Omerta.Organizations.SetRank(actorPly, targetCharacterId, newRank, reason, cb)
    cb = cb or function() end

    local actor = actorPly and Omerta.Characters.Get(actorPly) or nil
    Internal.Repo.GetMembership(targetCharacterId, function(target, err)
        if err or not target then cb(false, err or "they are not in anything") return end

        local org = instancesById[target.organization_id]
        if not org then cb(false, "unknown organization") return end
        local def = definitionFor(org)

        if actor then
            local actorMember = membership[actor.id]
            if not actorMember or actorMember.organization_id ~= org.id then
                cb(false, "they are not one of yours") return
            end
            local actorRank = Omerta.Organizations.EffectiveRank(actor.id)
            local ok, why = Omerta.Organizations.CanSetRank(def.ladder, actorRank,
                target.rank, newRank)
            if not ok then cb(false, why) return end
        end

        Internal.Repo.SetRank(org.id, targetCharacterId, newRank, target.rank,
            function(changed, serr)
            if not changed then
                cb(false, serr or "their rank changed while you were deciding") return
            end
            Omerta.Log.Audit("organization.rank_changed", {
                actor = actorPly and actorPly:SteamID64() or "staff",
                character_id = targetCharacterId,
                data = { organization = def.key, old = target.rank, new = newRank,
                         reason = reason or "" },
            })

            -- A new top rank is a new seated leader: the ladder decides who
            -- runs the family, not a separate appointment nobody remembers.
            if newRank == Omerta.Organizations.TopRank(def.ladder) then
                Internal.Repo.SetLeader(org.id, targetCharacterId)
                org.leader_character_id = targetCharacterId
            end

            local targetPly = characterIsOnline(targetCharacterId)
            if targetPly then
                local character = Omerta.Characters.Get(targetPly)
                Internal.LoadMembership(targetPly, character, function()
                    local rung = Omerta.Organizations.RankAt(def.ladder, newRank)
                    Omerta.Chat.Notice(targetPly, newRank > target.rank
                        and ("You have been made " .. (rung and rung.name or "?") .. ".")
                        or ("You have been reduced to " .. (rung and rung.name or "?") .. "."))
                end)
            end
            refreshActing(org.id)
            cb(true)
        end)
    end)
end

local function leave(characterId, status, actorPly, reason, cb)
    cb = cb or function() end
    Internal.Repo.GetMembership(characterId, function(member, err)
        if err or not member then cb(false, err or "they are not in anything") return end
        local org = instancesById[member.organization_id]
        local def = definitionFor(org)

        Internal.Repo.SetMemberStatus(member.organization_id, characterId, status, os.time(),
            function(ok, serr)
            if not ok then cb(false, serr) return end

            Omerta.Log.Audit("organization." .. status, {
                actor = actorPly and actorPly:SteamID64() or "self",
                character_id = characterId,
                data = { organization = def and def.key or "?", rank = member.rank,
                         reason = reason or "" },
            })

            -- The seat empties with them. Acting authority takes over until
            -- somebody is promoted into it, which is a decision a person makes.
            if org and org.leader_character_id == characterId then
                Internal.Repo.SetLeader(org.id, nil)
                org.leader_character_id = nil
            end

            membership[characterId] = nil
            local ply = characterIsOnline(characterId)
            if ply then
                Internal.PushSelf(ply)
                -- D-009: leaving the force returns you to independent, one-way.
                if def and def.type == Omerta.Organizations.TYPE.POLICE then
                    Omerta.Seasons.LeavePolice(ply, status == MEMBER.EXPELLED)
                end
            end
            if org then refreshActing(org.id) end
            cb(true)
        end)
    end)
end

function Omerta.Organizations.Expel(actorPly, targetCharacterId, reason, cb)
    cb = cb or function() end
    local actor = actorPly and Omerta.Characters.Get(actorPly) or nil

    if not actor then
        leave(targetCharacterId, MEMBER.EXPELLED, actorPly, reason, cb)
        return
    end

    Internal.Repo.GetMembership(targetCharacterId, function(target, err)
        if err or not target then cb(false, err or "they are not in anything") return end
        local actorMember = membership[actor.id]
        if not actorMember or actorMember.organization_id ~= target.organization_id then
            cb(false, "they are not one of yours") return
        end
        if not Omerta.Organizations.Can(actor.id, P.EXPEL) then
            cb(false, "that is not yours to do") return
        end
        local actorRank = Omerta.Organizations.EffectiveRank(actor.id)
        if actorRank <= target.rank then
            cb(false, "they are not yours to throw out") return
        end
        leave(targetCharacterId, MEMBER.EXPELLED, actorPly, reason, cb)
    end)
end

function Omerta.Organizations.Resign(ply, cb)
    cb = cb or function() end
    local character = Omerta.Characters.Get(ply)
    if not character then cb(false, "no character") return end
    leave(character.id, MEMBER.LEFT, ply, "resigned", cb)
end

--------------------------------------------------------------------------------
-- Staff commands
--------------------------------------------------------------------------------

local function findPlayer(sid)
    for _, ply in ipairs(player.GetAll()) do
        if ply:SteamID64() == sid then return ply end
    end
    return nil
end

function Internal.RegisterCommands()
    concommand.Add("omerta_org_list", function(caller)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        for _, def in ipairs(Omerta.Organizations.GetDefinitions()) do
            local row = instances[def.key]
            Omerta.Log.Info("organizations", "  %-10s %-34s %s%s", def.key, def.name,
                row and row.status or "(not created)",
                row and row.leader_character_id
                    and (" — led by character #" .. row.leader_character_id) or "")
        end
    end)

    concommand.Add("omerta_org_open", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        local row = instances[args[1] or ""]
        if not row then
            Omerta.Log.Error("organizations", "usage: omerta_org_open <key> (see omerta_org_list)")
            return
        end
        Internal.Repo.SetStatus(row.id, STATUS.ACTIVE, function(ok, err)
            if not ok then Omerta.Log.Error("organizations", "%s", tostring(err)) return end
            row.status = STATUS.ACTIVE
            Omerta.Log.Info("organizations", "%s is open for business", row.key)
            Omerta.Log.Audit("organization.opened", {
                actor = IsValid(caller) and caller:SteamID64() or "console",
                data = { organization = row.key },
            })
        end)
    end)

    -- Q-1's bootstrap (D-022): staff seat the first leader of an empty
    -- institution. After that the ordinary rules apply and staff do not
    -- re-seed a running season.
    concommand.Add("omerta_org_seed", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        local row = instances[args[1] or ""]
        local ply = findPlayer(args[2] or "")
        if not (row and IsValid(ply)) then
            Omerta.Log.Error("organizations", "usage: omerta_org_seed <key> <steamID64 of a connected player>")
            return
        end
        local character = Omerta.Characters.Get(ply)
        if not character then Omerta.Log.Error("organizations", "they have no character") return end

        local def = definitionFor(row)
        local ok, why = Internal.MayJoin(def, Omerta.Seasons.GetPath(ply))
        if not ok then Omerta.Log.Error("organizations", "%s", why) return end

        local top = Omerta.Organizations.TopRank(def.ladder)
        Internal.Repo.AddMember(row.id, character.id, top, nil, os.time(), function(added, err)
            if not added then Omerta.Log.Error("organizations", "%s", tostring(err)) return end
            Internal.Repo.SetLeader(row.id, character.id)
            row.leader_character_id = character.id
            if def.type == Omerta.Organizations.TYPE.FAMILY
                    and Omerta.Seasons.GetPath(ply) == "independent" then
                Omerta.Seasons.ConvertToCriminal(ply)
            end
            Omerta.Log.Audit("organization.seeded", {
                actor = IsValid(caller) and caller:SteamID64() or "console",
                character_id = character.id,
                data = { organization = row.key, rank = top },
            })
            Internal.LoadMembership(ply, character, function()
                if def.public then Internal.IssueUniform(ply) end
                Omerta.Log.Info("organizations", "%s now leads %s", character.first_name, row.key)
            end)
        end)
    end)

    concommand.Add("omerta_org_roster", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        local row = instances[args[1] or ""]
        if not row then
            Omerta.Log.Error("organizations", "usage: omerta_org_roster <key>")
            return
        end
        local def = definitionFor(row)
        Internal.Repo.ListMembers(row.id, function(members)
            Omerta.Log.Info("organizations", "%s — %d member(s)", def.name, #members)
            for _, member in ipairs(members) do
                local rung = Omerta.Organizations.RankAt(def.ladder, member.rank)
                Omerta.Log.Info("organizations", "  character #%s — %s%s",
                    tostring(member.character_id), rung and rung.name or "?",
                    actingHolder[row.id] == member.character_id and " (acting)" or "")
            end
        end)
    end)
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function MODULE:OnLoad()
    Omerta.DB.DefineTable("organizations", {
        columns = {
            { name = "id",                  type = "id" },
            { name = "season_id",           type = "ref", null = false },
            -- org_key, not key: KEY is reserved in MySQL 8 and the DDL would
            -- not parse. The repository aliases it back so nothing above that
            -- layer has to know. Same reason for rank_index below.
            { name = "org_key",             type = "text", length = 32, null = false },
            { name = "type",                type = "text", length = 16, null = false },
            { name = "status",              type = "text", length = 16, null = false,
              default = "active" },
            { name = "leader_character_id", type = "ref" },
            { name = "created_at",          type = "timestamp", null = false },
        },
        unique = { { "season_id", "org_key" } },
        indexes = { { "season_id" } },
    })

    Omerta.DB.DefineTable("organization_members", {
        columns = {
            { name = "organization_id",      type = "ref", null = false },
            { name = "character_id",         type = "ref", null = false },
            { name = "rank_index",           type = "int", null = false, default = 1 },
            { name = "joined_at",            type = "timestamp", null = false },
            { name = "sponsor_character_id", type = "ref" },
            { name = "status",               type = "text", length = 16, null = false,
              default = "active" },
            { name = "left_at",              type = "timestamp" },
        },
        primary = { "organization_id", "character_id" },
        indexes = { { "character_id" }, { "organization_id", "rank_index" } },
    })

    Omerta.DB.AddMigration(8, "organizations and rosters", function(m)
        m:CreateTable("organizations")
        m:CreateTable("organization_members")
    end)

    -- §4c: the officer title resolves through M5, keyed off the uniform.
    Omerta.Identity.RegisterTitleProvider(function(subjectChar)
        return Omerta.Organizations.PublicTitleFor(subjectChar)
    end)

    Omerta.Interaction.Register("organizations.offer", {
        label = "Offer Membership",
        order = 15,
        targets = "player",
        range = 96,
        predicate = function(ply, target)
            local sponsor = Omerta.Characters.Get(ply)
            local subject = Omerta.Characters.Get(target)
            if not (sponsor and subject) then return false end
            if not Omerta.Organizations.Can(sponsor.id, P.INVITE) then return false end
            if membership[subject.id] then return false, "they are spoken for" end
            return true
        end,
        run = function(ply, target)
            Omerta.Organizations.Invite(ply, target, function(ok, err)
                if not ok then Omerta.Chat.Notice(ply, err) end
            end)
        end,
    })
end

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    Omerta.DB.WhenReady(function()
        local season = Omerta.Seasons.GetActive()
        if not season then
            Omerta.Log.Info("organizations",
                "no active season — institutions appear when one starts")
            return
        end
        Internal.EnsureInstances(season)
    end)

    hook.Add("Omerta.SeasonStarted", "omerta.organizations.season", function(season)
        Internal.EnsureInstances(season)
    end)

    hook.Add("Omerta.CharacterLoaded", "omerta.organizations.load", function(ply, character)
        Internal.LoadMembership(ply, character)
    end)

    hook.Add("PlayerDisconnected", "omerta.organizations.unload", function(ply)
        local character = Omerta.Characters.Get(ply)
        pendingInvites[ply:SteamID64() or ""] = nil
        if not character then return end
        -- The membership row stays in the database; only the cache forgets, and
        -- the clock starts on whether their authority descends.
        offlineSince[character.id] = CurTime()
        local member = membership[character.id]
        membership[character.id] = nil
        if member then refreshActing(member.organization_id) end
    end)

    -- Authority is a function of who is present, and who is present changes
    -- without anybody calling anything.
    timer.Create("omerta.organizations.acting", 30, 0, refreshAllActing)

    Internal.RegisterCommands()
end
