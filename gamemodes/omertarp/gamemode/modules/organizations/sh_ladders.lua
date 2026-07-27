-- Rank ladders and the permissions each rung carries.
--
-- Ladders are DEFINITIONS — behaviour and balance — so they live in code and
-- in version control, like item definitions do. What is configurable (Tech §10
-- requires per-rank permissions to be) is which permissions a rung grants;
-- that is applied over these defaults from the config file.
--
-- Permissions are CUMULATIVE up the ladder: a Don can do everything a Soldier
-- can. Writing them any other way means every promotion has to remember to
-- re-grant what the rank below already had, and one day it will not.

Omerta.Organizations = Omerta.Organizations or {}

-- The complete vocabulary. A ladder granting anything outside this set is a
-- typo, and typos in a permission table fail open — so they are refused.
Omerta.Organizations.PERMISSIONS = {
    ROSTER         = "org.roster",          -- read the membership list
    INVITE         = "org.invite",          -- offer membership at the lowest rank
    RECOMMEND      = "org.recommend",       -- put someone forward for advancement
    PROMOTE        = "org.promote",
    DEMOTE         = "org.demote",
    EXPEL          = "org.expel",
    ACTING         = "org.acting",          -- may hold authority when the leader is away
    LEAD           = "org.lead",            -- is the seated leader
    APPOINT        = "org.appoint",         -- name a successor or a deputy
    TREASURY_VIEW  = "org.treasury_view",   -- M11
    TREASURY_SPEND = "org.treasury_spend",  -- M11
}

-- A fixed order, because the client is told its permissions as a bitfield and
-- a bit's meaning must not depend on the order pairs() happens to return.
-- Append only: inserting in the middle would change what a stale client reads.
Omerta.Organizations.PERMISSION_ORDER = {
    "org.roster", "org.invite", "org.recommend", "org.promote", "org.demote",
    "org.expel", "org.acting", "org.lead", "org.appoint",
    "org.treasury_view", "org.treasury_spend",
}

local VALID_PERMISSION = {}
for _, value in pairs(Omerta.Organizations.PERMISSIONS) do
    VALID_PERMISSION[value] = true
end

local ladders = {}

-- Returns true, or false + reason. Pure; exposed for the headless suite.
function Omerta.Organizations.ValidateLadder(id, ranks)
    if type(id) ~= "string" or not id:find("^[a-z0-9_]+$") then
        return false, "ladder id '" .. tostring(id) .. "' must be lowercase [a-z0-9_]"
    end
    if type(ranks) ~= "table" or #ranks == 0 then
        return false, "ladder '" .. id .. "' needs at least one rank"
    end

    local seen = {}
    for i, rank in ipairs(ranks) do
        if type(rank.key) ~= "string" or not rank.key:find("^[a-z0-9_]+$") then
            return false, string.format("ladder '%s' rank %d needs a lowercase key", id, i)
        end
        if seen[rank.key] then
            return false, string.format("ladder '%s' repeats rank key '%s'", id, rank.key)
        end
        seen[rank.key] = true
        if type(rank.name) ~= "string" or rank.name == "" then
            return false, string.format("ladder '%s' rank %d needs a name", id, i)
        end
        for _, permission in ipairs(rank.grants or {}) do
            if not VALID_PERMISSION[permission] then
                return false, string.format("ladder '%s' rank '%s' grants unknown permission '%s'",
                    id, rank.key, permission)
            end
        end
    end
    return true
end

function Omerta.Organizations.DefineLadder(id, ranks)
    local ok, why = Omerta.Organizations.ValidateLadder(id, ranks)
    if not ok then error(why, 2) end
    if ladders[id] then error("ladder '" .. id .. "' defined twice", 2) end

    for i, rank in ipairs(ranks) do
        rank.rank = i
        rank.grants = rank.grants or {}
    end
    ladders[id] = { id = id, ranks = ranks }
    return ladders[id]
end

function Omerta.Organizations.GetLadder(id) return ladders[id] end

function Omerta.Organizations.RankAt(ladderId, rank)
    local ladder = ladders[ladderId]
    if not ladder then return nil end
    return ladder.ranks[rank]
end

function Omerta.Organizations.TopRank(ladderId)
    local ladder = ladders[ladderId]
    return ladder and #ladder.ranks or 0
end

-- Every permission held at this rung, accumulated from the bottom up.
function Omerta.Organizations.PermissionsAt(ladderId, rank)
    local out = {}
    local ladder = ladders[ladderId]
    if not ladder then return out end
    for i = 1, math.min(rank or 0, #ladder.ranks) do
        for _, permission in ipairs(ladder.ranks[i].grants) do
            out[permission] = true
        end
    end
    return out
end

function Omerta.Organizations.Grants(ladderId, rank, permission)
    return Omerta.Organizations.PermissionsAt(ladderId, rank)[permission] == true
end

-- The same set as a bitfield, for the one message that tells a client what its
-- own character may do. It is a convenience for greying out buttons; the
-- server re-checks every action regardless of what the client believes.
function Omerta.Organizations.PermissionBits(ladderId, rank)
    local held = Omerta.Organizations.PermissionsAt(ladderId, rank)
    local bits = 0
    for i, permission in ipairs(Omerta.Organizations.PERMISSION_ORDER) do
        if held[permission] then bits = bits + 2 ^ (i - 1) end
    end
    return bits
end

--------------------------------------------------------------------------------
-- The ladders themselves
--------------------------------------------------------------------------------

local P = Omerta.Organizations.PERMISSIONS

-- GDD §4.1. The GDD lists "Independent" as rank 1; it is not a rung here,
-- because being independent is the ABSENCE of membership rather than a
-- position inside a family. There is no row for it, which is what makes
-- "is this character in a family" a single question with a single answer.
Omerta.Organizations.DefineLadder("family", {
    { key = "prospect",  name = "Prospect" },
    { key = "associate", name = "Associate" },
    -- "Senior members may provisionally recruit" (GDD §4.1).
    { key = "soldier",   name = "Soldier",    grants = { P.INVITE } },
    -- "Capos recommend formal advancement" — and a capo runs a crew, so a capo
    -- is the first rung that can read the roster (§4b).
    { key = "capo",      name = "Caporegime", grants = { P.ROSTER, P.RECOMMEND, P.ACTING,
                                                          P.TREASURY_VIEW } },
    -- spendLimit is in cents, and nil means no ceiling. Anything above a rung's
    -- limit needs a second person present who can cover it (M11 §4c), which is
    -- what puts two people at the safe arguing about money.
    { key = "underboss", name = "Underboss",  grants = { P.PROMOTE, P.DEMOTE, P.EXPEL,
                                                          P.TREASURY_SPEND },
                                              spendLimit = 25000 },
    { key = "don",       name = "Don",        grants = { P.LEAD, P.APPOINT } },
})

-- GDD §4.2. A police force is a bureaucracy: authority separates earlier and
-- the roster is not a secret to the people inside it.
Omerta.Organizations.DefineLadder("police", {
    { key = "patrol",       name = "Patrol Officer" },
    { key = "senior",       name = "Senior Officer", grants = { P.INVITE } },
    { key = "detective",    name = "Detective",      grants = { P.ROSTER } },
    { key = "sergeant",     name = "Sergeant",       grants = { P.RECOMMEND, P.ACTING } },
    { key = "lieutenant",   name = "Lieutenant",     grants = { P.PROMOTE, P.DEMOTE,
                                                                 P.TREASURY_VIEW } },
    { key = "captain",      name = "Captain",        grants = { P.EXPEL, P.TREASURY_SPEND },
                                                     spendLimit = 25000 },
    { key = "commissioner", name = "Commissioner",   grants = { P.LEAD, P.APPOINT } },
})
