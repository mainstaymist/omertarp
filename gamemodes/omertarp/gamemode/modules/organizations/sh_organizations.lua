-- Institutions: the four families and the police department (GDD §4).
--
-- An institution is a DEFINITION in code; each season gets a fresh instance of
-- it with a fresh roster and a fresh leader. That is what "institutions persist
-- while characters, ranks and wealth reset" means once it reaches a schema.
--
-- Nothing here ever reaches a client except through the messages at the bottom
-- of this file. There is no faction networked variable and no GMod team: teams
-- are readable by every client, so a Marino team would publish the entire
-- criminal underworld to anyone with a Lua console. M6's audit treats a second
-- team as a leak precisely because of this.


Omerta.Organizations = Omerta.Organizations or {}
Omerta.Organizations.Internal = Omerta.Organizations.Internal or {}

Omerta.Organizations.TYPE = { FAMILY = "family", POLICE = "police" }
Omerta.Organizations.STATUS = { ACTIVE = "active", DORMANT = "dormant" }
Omerta.Organizations.MEMBER_STATUS = { ACTIVE = "active", LEFT = "left", EXPELLED = "expelled" }

local definitions = {}
local ordered = nil

--------------------------------------------------------------------------------
-- Definitions
--------------------------------------------------------------------------------

function Omerta.Organizations.ValidateDefinition(key, def)
    if type(key) ~= "string" or not key:find("^[a-z0-9_]+$") then
        return false, "organization key '" .. tostring(key) .. "' must be lowercase [a-z0-9_]"
    end
    if #key > 32 then return false, "organization key '" .. key .. "' is too long" end
    if type(def) ~= "table" then return false, "organization '" .. key .. "' needs a definition" end
    if type(def.name) ~= "string" or def.name == "" then
        return false, "organization '" .. key .. "' needs a name"
    end
    if def.type ~= Omerta.Organizations.TYPE.FAMILY and def.type ~= Omerta.Organizations.TYPE.POLICE then
        return false, "organization '" .. key .. "' needs type 'family' or 'police'"
    end
    if not Omerta.Organizations.GetLadder(def.ladder) then
        return false, "organization '" .. key .. "' names unknown ladder '" .. tostring(def.ladder) .. "'"
    end
    return true
end

function Omerta.Organizations.Define(key, def)
    local ok, why = Omerta.Organizations.ValidateDefinition(key, def)
    if not ok then error(why, 2) end
    if definitions[key] then error("organization '" .. key .. "' defined twice", 2) end

    def.key = key
    def.order = def.order or 100
    -- §4c: a public institution announces itself. Family membership does not.
    def.public = def.public == true
    definitions[key] = def
    ordered = nil
    return def
end

function Omerta.Organizations.GetDefinition(key) return definitions[key] end

-- Deterministic: by `order`, then key. The order decides which families are
-- active when fewer than all of them are (§4a).
function Omerta.Organizations.GetDefinitions()
    if ordered then return ordered end
    ordered = {}
    for _, def in pairs(definitions) do ordered[#ordered + 1] = def end
    table.sort(ordered, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)
    for i, def in ipairs(ordered) do def.index = i end
    return ordered
end

function Omerta.Organizations.GetByIndex(index)
    local list = Omerta.Organizations.GetDefinitions()
    return list[index]
end

function Omerta.Organizations.IndexOf(key)
    local def = definitions[key]
    if not def then return nil end
    Omerta.Organizations.GetDefinitions()
    return def.index
end

--------------------------------------------------------------------------------
-- The institutions
--------------------------------------------------------------------------------
-- Four families (GDD §4.1) in a fixed order, so "the first two" means the same
-- thing on every server and across every restart. How many are active at once
-- is configuration, not code (§4a).

Omerta.Organizations.Define("marino",  { name = "Marino Family",  type = "family", ladder = "family", order = 10 })
Omerta.Organizations.Define("falcone", { name = "Falcone Family", type = "family", ladder = "family", order = 20 })
Omerta.Organizations.Define("ricci",   { name = "Ricci Family",   type = "family", ladder = "family", order = 30 })
Omerta.Organizations.Define("bianchi", { name = "Bianchi Family", type = "family", ladder = "family", order = 40 })

Omerta.Organizations.Define("police", {
    name = "Metropolitan Police Department",
    type = "police", ladder = "police", public = true, order = 100,
})

--------------------------------------------------------------------------------
-- The uniform (§4c)
--------------------------------------------------------------------------------
-- Visibility is carried by the UNIFORM, not by the institution: an officer in
-- plain clothes is a stranger like anyone else, which is what makes plain
-- clothes worth wearing. The uniform is an ordinary M9 item, so it can be
-- taken off, left at home, stolen, or worn by somebody who should not have it.

Omerta.Organizations.UNIFORM_ITEM = "clothing.police_uniform"

Omerta.Items.Register(Omerta.Organizations.UNIFORM_ITEM, {
    name = "Police Uniform", category = "clothing", bulk = 3, slot = "outerwear",
    capacityBonus = 6,
    model = "models/props_c17/BriefCase001a.mdl",
})

--------------------------------------------------------------------------------
-- The rules (pure)
--------------------------------------------------------------------------------

-- Can `actorRank` change `targetRank` to `newRank` on this ladder?
-- Returns true, or false + reason.
--
-- Two rules do all the work, and both are absolute: you must strictly outrank
-- the person you are acting on, and you can never create a rank at or above
-- your own. Together they make "promote myself to Don" unrepresentable rather
-- than merely forbidden.
function Omerta.Organizations.CanSetRank(ladderId, actorRank, targetRank, newRank)
    local top = Omerta.Organizations.TopRank(ladderId)
    if top == 0 then return false, "unknown ladder" end
    if type(newRank) ~= "number" or newRank % 1 ~= 0 or newRank < 1 or newRank > top then
        return false, "that is not a rank"
    end
    if not actorRank then return false, "you are not a member" end
    if actorRank <= targetRank then
        return false, "they are not yours to promote or demote"
    end
    if newRank >= actorRank then
        return false, "you cannot make anyone your equal or your superior"
    end
    if newRank == targetRank then return false, "they already hold that rank" end

    local needed = newRank > targetRank
        and Omerta.Organizations.PERMISSIONS.PROMOTE
        or Omerta.Organizations.PERMISSIONS.DEMOTE
    if not Omerta.Organizations.Grants(ladderId, actorRank, needed) then
        return false, newRank > targetRank
            and "you cannot promote anyone" or "you cannot demote anyone"
    end
    return true
end

-- Who actually holds authority right now (Tech §19). Computed, never stored:
-- a derived value that is stored is a derived value that can be wrong, and an
-- "acting Don" row left behind by a crash is a family nobody can run.
--
--   members   — array of { character_id = , rank = }
--   leaderId  — the seated leader, or nil
--   available — fn(characterId) -> true when they are here to exercise it
-- Returns characterId, isActing.
function Omerta.Organizations.Internal.ComputeActing(ladderId, members, leaderId, available)
    local byId = {}
    local highest = nil
    for _, member in ipairs(members or {}) do
        byId[member.character_id] = member
        if not highest or member.rank > highest.rank then highest = member end
    end

    -- The leader holds their own authority whenever they are here. If nobody
    -- has been seated, the highest rank standing is the leader by default.
    local leader = leaderId and byId[leaderId] or highest
    if leader and available(leader.character_id) then
        return leader.character_id, false
    end

    -- Otherwise it descends: the most senior person present who is allowed to
    -- hold it. Nobody present means nobody holds it — an organization with no
    -- one in the room does not need a decision made.
    local best = nil
    for _, member in ipairs(members or {}) do
        if (not leader or member.character_id ~= leader.character_id)
                and available(member.character_id)
                and Omerta.Organizations.Grants(ladderId, member.rank,
                    Omerta.Organizations.PERMISSIONS.ACTING) then
            if not best or member.rank > best.rank then best = member end
        end
    end
    if best then return best.character_id, true end
    return nil, false
end

-- Which institutions are active when only some of them are (§4a). Police is
-- always active — a city has one police department whether or not anyone has
-- signed up for it.
function Omerta.Organizations.Internal.PlanActive(definitions, activeFamilies)
    local plan = {}
    local families = 0
    for _, def in ipairs(definitions) do
        if def.type == Omerta.Organizations.TYPE.POLICE then
            plan[def.key] = Omerta.Organizations.STATUS.ACTIVE
        else
            families = families + 1
            plan[def.key] = families <= activeFamilies
                and Omerta.Organizations.STATUS.ACTIVE
                or Omerta.Organizations.STATUS.DORMANT
        end
    end
    return plan
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------

Omerta.Net.Register("org.self", {
    realm = "server_to_client",
    schema = {
        { name = "org",  type = "uint", bits = 8 },  -- definition index, 0 = none
        { name = "rank", type = "uint", bits = 8 },
        -- A bitfield of the PERMISSIONS list, so the client can grey out a
        -- button it would only be refused for. The server re-checks anyway.
        { name = "perms", type = "uint", bits = 16 },
    },
    handler = function(payload)
        hook.Run("Omerta.MembershipUpdated", payload.org, payload.rank, payload.perms)
    end,
})

Omerta.Net.Register("org.roster_request", {
    realm = "client_to_server",
    schema = {},
    rate = { burst = 4, per = 10 },
    handler = function(ply)
        Omerta.Organizations.Internal.SendRoster(ply)
    end,
})

Omerta.Net.Register("org.roster_entry", {
    realm = "server_to_client",
    schema = {
        { name = "name",  type = "string", maxlen = 56 },
        { name = "rank",  type = "uint", bits = 8 },
        { name = "last",  type = "bool" },
        { name = "online", type = "bool" },
    },
    handler = function(payload)
        hook.Run("Omerta.RosterEntry", payload)
    end,
})

Omerta.Net.Register("org.invite", {
    realm = "server_to_client",
    schema = {
        { name = "from", type = "uint", bits = 16 },
        { name = "org",  type = "uint", bits = 8 },
        { name = "name", type = "string", maxlen = 56 },
    },
    handler = function(payload)
        hook.Run("Omerta.MembershipOffered", payload.from, payload.org, payload.name)
    end,
})

Omerta.Net.Register("org.invite_reply", {
    realm = "client_to_server",
    schema = { { name = "accept", type = "bool" } },
    rate = { burst = 5, per = 10 },
    handler = function(ply, payload)
        Omerta.Organizations.Internal.HandleInviteReply(ply, payload.accept)
    end,
})
