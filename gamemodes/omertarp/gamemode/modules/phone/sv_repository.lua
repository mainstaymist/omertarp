-- Phone repository: the only file that writes SQL about lines or calls.
--
-- There is no content column on a call and there must never be one. The design
-- has no place for stored recordings, and a table with nowhere to put them is
-- a stronger guarantee than a rule somebody has to remember.

Omerta.Phone = Omerta.Phone or {}
Omerta.Phone.Internal = Omerta.Phone.Internal or {}
local Internal = Omerta.Phone.Internal
Internal.Repo = Internal.Repo or {}
local Repo = Internal.Repo

--------------------------------------------------------------------------------
-- Lines
--------------------------------------------------------------------------------

function Repo.CreateLine(row, cb)
    Omerta.DB.Insert("phone_lines", row, cb)
end

function Repo.ListLines(seasonId, cb)
    Omerta.DB.Query("SELECT * FROM {phone_lines} WHERE season_id = ? ORDER BY id",
        { seasonId }, function(rows, err) cb(rows or {}, err) end)
end

function Repo.DeleteLine(id, cb)
    Omerta.DB.Query("DELETE FROM {phone_lines} WHERE id = ?", { id },
        function(_, err) if cb then cb(err == nil, err) end end)
end

--------------------------------------------------------------------------------
-- Call records
--------------------------------------------------------------------------------
-- Metadata only: which line called which line, when, for how long, and how it
-- ended. Never a word of what was said.

function Repo.RecordCall(row, cb)
    Omerta.DB.Insert("phone_calls", row, cb)
end

-- Both directions, newest first — a line's own history is "calls to or from
-- this number", not one column of it.
function Repo.CallsFor(lineId, limit, cb)
    Omerta.DB.Query(
        "SELECT * FROM {phone_calls} WHERE from_line = ? OR to_line = ? " ..
        "ORDER BY id DESC LIMIT " .. math.floor(math.max(1, math.min(limit or 20, 100))),
        { lineId, lineId }, function(rows, err) cb(rows or {}, err) end)
end

--------------------------------------------------------------------------------
-- Self-test cleanup only
--------------------------------------------------------------------------------

function Repo.DeleteCallsFor(lineId, cb)
    Omerta.DB.Query("DELETE FROM {phone_calls} WHERE from_line = ? OR to_line = ?",
        { lineId, lineId },
        function(_, err) if cb then cb(err == nil, err) end end)
end
