-- Characters repository: the only file that writes SQL about characters.

Omerta.Characters = Omerta.Characters or {}
Omerta.Characters.Internal = Omerta.Characters.Internal or {}
local Internal = Omerta.Characters.Internal
Internal.Repo = Internal.Repo or {}
local Repo = Internal.Repo

-- cb(id, err). Relies on the unique(season_id, name_key) index for collision
-- detection: a read-then-write check would let two players submitting the
-- same name in the same tick both pass.
function Repo.Create(row, cb)
    Omerta.DB.Insert("characters", row, cb)
end

function Repo.GetByID(id, cb)
    Omerta.DB.QueryOne("SELECT * FROM {characters} WHERE id = ?", { id }, cb)
end

-- The account's living character for a season, if any.
function Repo.GetActiveFor(accountId, seasonId, cb)
    Omerta.DB.QueryOne(
        "SELECT * FROM {characters} WHERE account_id = ? AND season_id = ? AND status = ?",
        { accountId, seasonId, Omerta.Characters.STATUS.ALIVE }, cb)
end

function Repo.SetStatus(id, status, at, cb)
    Omerta.DB.Query(
        "UPDATE {characters} SET status = ?, retired_at = ? WHERE id = ? AND status = ?",
        { status, at, id, Omerta.Characters.STATUS.ALIVE },
        function(_, err) if cb then cb(err == nil, err) end end)
end

-- D-010: every living character retires when the season ends. One statement
-- rather than a per-character loop — a season may hold hundreds.
function Repo.RetireAllInSeason(seasonId, at, cb)
    Omerta.DB.Query(
        "UPDATE {characters} SET status = ?, retired_at = ? WHERE season_id = ? AND status = ?",
        { Omerta.Characters.STATUS.RETIRED, at, seasonId, Omerta.Characters.STATUS.ALIVE },
        function(_, err) if cb then cb(err == nil, err) end end)
end

--------------------------------------------------------------------------------
-- Portraits (D-011): base64 JPEG in a text column, immutable once set.
--------------------------------------------------------------------------------

-- The status guard makes the write one-shot: a second upload for the same
-- character updates nothing.
function Repo.SetPortrait(id, base64, at, cb)
    Omerta.DB.Query(
        "UPDATE {characters} SET portrait = ?, portrait_at = ? WHERE id = ? AND portrait IS NULL",
        { base64, at, id }, function(_, err) if cb then cb(err == nil, err) end end)
end

function Repo.GetPortrait(id, cb)
    Omerta.DB.QueryOne("SELECT portrait FROM {characters} WHERE id = ?", { id },
        function(row, err) cb(row and row.portrait or nil, err) end)
end

function Repo.ClearPortrait(id, cb)
    Omerta.DB.Query(
        "UPDATE {characters} SET portrait = ?, portrait_at = ? WHERE id = ?",
        { Omerta.DB.NULL, Omerta.DB.NULL, id },
        function(_, err) if cb then cb(err == nil, err) end end)
end

--------------------------------------------------------------------------------
-- Self-test cleanup only
--------------------------------------------------------------------------------

function Repo.DeleteForAccount(accountId, cb)
    Omerta.DB.Query("DELETE FROM {characters} WHERE account_id = ?", { accountId },
        function(_, err) if cb then cb(err == nil, err) end end)
end
