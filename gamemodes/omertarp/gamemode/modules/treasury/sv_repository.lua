-- Treasury repository: the only file that writes SQL about the books or the
-- safes they belong to.
--
-- The ledger is APPEND-ONLY. There is deliberately no update and no delete —
-- a correction is another line. A ledger you can edit is not a ledger, and
-- every question staff and M15 will ask about money assumes this.

Omerta.Treasury = Omerta.Treasury or {}
Omerta.Treasury.Internal = Omerta.Treasury.Internal or {}
local Internal = Omerta.Treasury.Internal
Internal.Repo = Internal.Repo or {}
local Repo = Internal.Repo

--------------------------------------------------------------------------------
-- The books
--------------------------------------------------------------------------------

-- cb(id, err)
function Repo.Append(row, cb)
    Omerta.DB.Insert("treasury_ledger", row, cb)
end

-- The running balance as of the last line, or 0 for a fresh treasury.
function Repo.LastBalance(orgId, cb)
    Omerta.DB.QueryOne(
        "SELECT balance_after FROM {treasury_ledger} WHERE organization_id = ? " ..
        "ORDER BY id DESC LIMIT 1",
        { orgId }, function(row, err) cb(row and row.balance_after or 0, err) end)
end

function Repo.History(orgId, limit, cb)
    Omerta.DB.Query(
        "SELECT * FROM {treasury_ledger} WHERE organization_id = ? ORDER BY id DESC LIMIT " ..
        math.floor(math.max(1, math.min(limit or 20, 100))),
        { orgId }, function(rows, err) cb(rows or {}, err) end)
end

--------------------------------------------------------------------------------
-- Where the safe stands
--------------------------------------------------------------------------------
-- A safe that moves to the map origin on restart is not a safe.

function Repo.SaveSafe(orgId, mapName, x, y, z, at, cb)
    Omerta.DB.Upsert("treasury_safes", {
        organization_id = orgId,
        map_name = mapName,
        pos_x = x, pos_y = y, pos_z = z,
        placed_at = at,
    }, { "organization_id" }, cb)
end

function Repo.ListSafes(mapName, cb)
    Omerta.DB.Query("SELECT * FROM {treasury_safes} WHERE map_name = ?", { mapName },
        function(rows, err) cb(rows or {}, err) end)
end

function Repo.DeleteSafe(orgId, cb)
    Omerta.DB.Query("DELETE FROM {treasury_safes} WHERE organization_id = ?", { orgId },
        function(_, err) if cb then cb(err == nil, err) end end)
end

--------------------------------------------------------------------------------
-- Self-test cleanup only
--------------------------------------------------------------------------------
-- The only DELETE against the ledger in the entire gamemode, and it exists so
-- the acceptance suite does not leave synthetic money in the books.

function Repo.DeleteLedgerFor(orgId, cb)
    Omerta.DB.Query("DELETE FROM {treasury_ledger} WHERE organization_id = ?", { orgId },
        function(_, err) if cb then cb(err == nil, err) end end)
end
