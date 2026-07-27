-- Organizations repository: the only file that writes SQL about institutions
-- or their rosters.
--
-- Membership history is kept rather than deleted. "Who was in the Marino
-- family in week two" has to stay answerable — M15 will ask it about a
-- suspect and M21 about a funeral — so leaving is a status change and a
-- timestamp, never a DELETE.
--
-- STORAGE NAMES DIFFER FROM DOMAIN NAMES, deliberately and only here:
-- `key` and `rank` are reserved words, so the columns are `org_key` and
-- `rank_index`. The translation back happens in LUA, not in SQL — a reserved
-- word is just as reserved when it is an alias (`SELECT org_key AS key` is a
-- syntax error on MariaDB), and mapping in Lua is dialect-proof besides.
-- Confining the translation to this file is exactly what a repository is for:
-- nothing above it ever learns the database had an opinion about vocabulary.

Omerta.Organizations = Omerta.Organizations or {}
Omerta.Organizations.Internal = Omerta.Organizations.Internal or {}
local Internal = Omerta.Organizations.Internal
Internal.Repo = Internal.Repo or {}
local Repo = Internal.Repo

local function toOrg(row)
    if not row then return nil end
    row.key = row.org_key
    return row
end

local function toOrgs(rows)
    for _, row in ipairs(rows or {}) do toOrg(row) end
    return rows or {}
end

local function toMember(row)
    if not row then return nil end
    row.rank = row.rank_index
    return row
end

local function toMembers(rows)
    for _, row in ipairs(rows or {}) do toMember(row) end
    return rows or {}
end

--------------------------------------------------------------------------------
-- Institutions
--------------------------------------------------------------------------------

-- Called only for institutions this season does not have yet, so a gamemode
-- update that adds a fifth family gives the running season one without a
-- migration. An INSERT rather than an upsert on purpose: re-running it must
-- never overwrite a status a staff member set by hand. cb(id, err)
function Repo.Create(seasonId, key, orgType, status, now, cb)
    Omerta.DB.Insert("organizations", {
        season_id = seasonId,
        org_key = key,
        type = orgType,
        status = status,
        created_at = now,
    }, cb)
end

function Repo.ListForSeason(seasonId, cb)
    Omerta.DB.Query("SELECT * FROM {organizations} WHERE season_id = ? ORDER BY id",
        { seasonId }, function(rows, err) cb(toOrgs(rows), err) end)
end

function Repo.FindByKey(seasonId, key, cb)
    Omerta.DB.QueryOne("SELECT * FROM {organizations} WHERE season_id = ? AND org_key = ?",
        { seasonId, key }, function(row, err) cb(toOrg(row), err) end)
end

function Repo.SetStatus(orgId, status, cb)
    Omerta.DB.Query("UPDATE {organizations} SET status = ? WHERE id = ?", { status, orgId },
        function(_, err) if cb then cb(err == nil, err) end end)
end

function Repo.SetLeader(orgId, characterId, cb)
    Omerta.DB.Query("UPDATE {organizations} SET leader_character_id = ? WHERE id = ?",
        { characterId or Omerta.DB.NULL, orgId },
        function(_, err) if cb then cb(err == nil, err) end end)
end

--------------------------------------------------------------------------------
-- Membership
--------------------------------------------------------------------------------

-- A character's current membership, if any. Season scoping comes for free:
-- characters belong to one season and so do organizations.
function Repo.GetMembership(characterId, cb)
    Omerta.DB.QueryOne(
        "SELECT m.organization_id, m.character_id, m.rank_index, m.joined_at, " ..
        "m.sponsor_character_id, m.status, m.left_at, " ..
        "o.org_key, o.type, o.season_id, o.leader_character_id " ..
        "FROM {organization_members} m " ..
        "JOIN {organizations} o ON o.id = m.organization_id " ..
        "WHERE m.character_id = ? AND m.status = ?",
        { characterId, Omerta.Organizations.MEMBER_STATUS.ACTIVE },
        function(row, err) cb(toMember(row), err) end)
end

function Repo.ListMembers(orgId, cb)
    Omerta.DB.Query(
        "SELECT * FROM {organization_members} " ..
        "WHERE organization_id = ? AND status = ? ORDER BY rank_index DESC, joined_at",
        { orgId, Omerta.Organizations.MEMBER_STATUS.ACTIVE },
        function(rows, err) cb(toMembers(rows), err) end)
end

-- Any status, including those who have left. The self-test uses it to prove
-- that an expulsion leaves history behind rather than a hole.
function Repo.GetMemberRow(orgId, characterId, cb)
    Omerta.DB.QueryOne(
        "SELECT * FROM {organization_members} " ..
        "WHERE organization_id = ? AND character_id = ?", { orgId, characterId },
        function(row, err) cb(toMember(row), err) end)
end

-- cb(ok, err). Upsert rather than insert so a character who was expelled and
-- later taken back in reuses their row — the primary key is the pair, and a
-- second row for the same pair is not a thing that should be able to exist.
function Repo.AddMember(orgId, characterId, rank, sponsorId, now, cb)
    Omerta.DB.Upsert("organization_members", {
        organization_id = orgId,
        character_id = characterId,
        rank_index = rank,
        joined_at = now,
        sponsor_character_id = sponsorId or Omerta.DB.NULL,
        status = Omerta.Organizations.MEMBER_STATUS.ACTIVE,
        left_at = Omerta.DB.NULL,
    }, { "organization_id", "character_id" }, cb)
end

-- Guarded on the rank we believe they hold, so two promotions racing each
-- other cannot both apply and land the target two rungs up. The driver gives
-- no affected-row count, so the outcome is confirmed by reading it back.
function Repo.SetRank(orgId, characterId, rank, expectedRank, cb)
    Omerta.DB.Query(
        "UPDATE {organization_members} SET rank_index = ? " ..
        "WHERE organization_id = ? AND character_id = ? AND rank_index = ? AND status = ?",
        { rank, orgId, characterId, expectedRank, Omerta.Organizations.MEMBER_STATUS.ACTIVE },
        function(_, err)
            if err then cb(false, err) return end
            Omerta.DB.QueryOne(
                "SELECT rank_index FROM {organization_members} " ..
                "WHERE organization_id = ? AND character_id = ?",
                { orgId, characterId },
                function(row, rerr)
                    if rerr then cb(false, rerr) return end
                    cb(row ~= nil and row.rank_index == rank, nil)
                end)
        end)
end

function Repo.SetMemberStatus(orgId, characterId, status, leftAt, cb)
    Omerta.DB.Query(
        "UPDATE {organization_members} SET status = ?, left_at = ? " ..
        "WHERE organization_id = ? AND character_id = ?",
        { status, leftAt, orgId, characterId },
        function(_, err) if cb then cb(err == nil, err) end end)
end

--------------------------------------------------------------------------------
-- Self-test cleanup only
--------------------------------------------------------------------------------

function Repo.DeleteMembers(orgId, cb)
    Omerta.DB.Query("DELETE FROM {organization_members} WHERE organization_id = ?", { orgId },
        function(_, err) if cb then cb(err == nil, err) end end)
end

function Repo.DeleteOrganization(orgId, cb)
    Omerta.DB.Query("DELETE FROM {organizations} WHERE id = ?", { orgId },
        function(_, err) if cb then cb(err == nil, err) end end)
end
