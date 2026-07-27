-- Seasons repository: the only file that writes SQL about seasons and
-- account-season path records. Called by sv_seasons.lua, never by gameplay.

Omerta.Seasons = Omerta.Seasons or {}
Omerta.Seasons.Internal = Omerta.Seasons.Internal or {}
local Internal = Omerta.Seasons.Internal
Internal.Repo = Internal.Repo or {}
local Repo = Internal.Repo

function Repo.CreateSeason(label, rulesetVersion, now, cb)
    Omerta.DB.Insert("seasons", {
        label = label,
        state = "setup",
        ruleset_version = rulesetVersion,
        created_at = now,
    }, cb)
end

function Repo.GetSeason(id, cb)
    Omerta.DB.QueryOne("SELECT * FROM {seasons} WHERE id = ?", { id }, cb)
end

function Repo.GetAllSeasons(cb)
    Omerta.DB.Query("SELECT * FROM {seasons}", {}, cb)
end

-- The WHERE state clauses make both mutations idempotence-safe: a stale or
-- duplicated command cannot re-start an ended season or re-end a setup one.
function Repo.StartSeason(id, startedAt, endsAt, cb)
    Omerta.DB.Query(
        "UPDATE {seasons} SET state = ?, started_at = ?, ends_at = ? WHERE id = ? AND state = ?",
        { "active", startedAt, endsAt, id, "setup" },
        function(_, err) cb(err == nil, err) end)
end

function Repo.EndSeason(id, endedAt, cb)
    Omerta.DB.Query(
        "UPDATE {seasons} SET state = ?, ended_at = ? WHERE id = ? AND state = ?",
        { "ended", endedAt, id, "active" },
        function(_, err) cb(err == nil, err) end)
end

function Repo.GetPathRow(accountId, seasonId, cb)
    Omerta.DB.QueryOne(
        "SELECT path, chosen_at FROM {account_seasons} WHERE account_id = ? AND season_id = ?",
        { accountId, seasonId }, cb)
end

function Repo.SetPath(accountId, seasonId, path, now, cb)
    Omerta.DB.Upsert("account_seasons", {
        account_id = accountId,
        season_id = seasonId,
        path = path,
        chosen_at = now,
    }, { "account_id", "season_id" }, cb)
end

--------------------------------------------------------------------------------
-- Self-test cleanup only
--------------------------------------------------------------------------------

-- Guarded by label AND state so it can never delete a real season.
function Repo.DeleteSelftestSeason(label, cb)
    Omerta.DB.Query("DELETE FROM {seasons} WHERE label = ? AND state = ?",
        { label, "setup" }, function(_, err) if cb then cb(err == nil, err) end end)
end

function Repo.DeletePathsForAccount(accountId, cb)
    Omerta.DB.Query("DELETE FROM {account_seasons} WHERE account_id = ?",
        { accountId }, function(_, err) if cb then cb(err == nil, err) end end)
end
