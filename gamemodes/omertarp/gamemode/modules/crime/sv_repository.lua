-- All SQL for operations, participants and alarms. Gameplay calls the service,
-- never this.

Omerta.Crime = Omerta.Crime or {}
Omerta.Crime.Internal = Omerta.Crime.Internal or {}
Omerta.Crime.Internal.Repo = Omerta.Crime.Internal.Repo or {}
local Repo = Omerta.Crime.Internal.Repo

--------------------------------------------------------------------------------
-- Operations
--------------------------------------------------------------------------------

function Repo.Insert(row, cb)
    Omerta.DB.Insert("crime_operations", row, cb)
end

function Repo.Get(id, cb)
    Omerta.DB.QueryOne("SELECT * FROM {crime_operations} WHERE id = ?", { id }, cb)
end

function Repo.SetState(id, state, resolution, at, endedAt, cb)
    cb = cb or function() end
    Omerta.DB.Query(
        "UPDATE {crime_operations} SET state = ?, resolution = ?, state_at = ?, ended_at = ? " ..
        "WHERE id = ?",
        { state, resolution or Omerta.DB.NULL, at, endedAt or Omerta.DB.NULL, id },
        function(_, err) cb(err == nil, err) end)
end

function Repo.AddTake(id, cents, cb)
    cb = cb or function() end
    -- Accumulated in SQL rather than read-modify-written, because two robbers
    -- working the same register are two callers racing on the same row. The
    -- column is a RECORD (M21 wants a figure to print) and never a source of
    -- truth about how much money exists.
    Omerta.DB.Query(
        "UPDATE {crime_operations} SET take_cents = take_cents + ? WHERE id = ?",
        { cents, id }, function(_, err) cb(err == nil, err) end)
end

-- Everything still live. The boot path's whole input (D-050).
function Repo.Live(cb)
    Omerta.DB.Query(
        "SELECT * FROM {crime_operations} WHERE state IN (?, ?, ?)",
        { Omerta.Crime.STATE.PLANNED, Omerta.Crime.STATE.ACTIVE, Omerta.Crime.STATE.ALARMED },
        function(rows, err) cb(rows or {}, err) end)
end

-- The cooldown query: when this premises was last turned over, whatever the
-- outcome was. An abandoned robbery still frightened everybody in the room.
function Repo.LastForBusiness(businessId, cb)
    Omerta.DB.QueryOne(
        "SELECT * FROM {crime_operations} WHERE business_id = ? ORDER BY id DESC LIMIT 1",
        { businessId }, cb)
end

function Repo.ForBusiness(businessId, limit, cb)
    Omerta.DB.Query(
        "SELECT * FROM {crime_operations} WHERE business_id = ? ORDER BY id DESC LIMIT " ..
            math.floor(math.max(1, math.min(limit or 25, 200))),
        { businessId }, function(rows, err) cb(rows or {}, err) end)
end

--------------------------------------------------------------------------------
-- Participants
--------------------------------------------------------------------------------

function Repo.AddParticipant(row, cb)
    cb = cb or function() end
    Omerta.DB.Insert("crime_participants", row, function(_, err) cb(err == nil, err) end)
end

function Repo.SetOutcome(operationId, characterId, outcome, cb)
    cb = cb or function() end
    Omerta.DB.Query(
        "UPDATE {crime_participants} SET outcome = ? WHERE operation_id = ? AND character_id = ?",
        { outcome, operationId, characterId }, function(_, err) cb(err == nil, err) end)
end

function Repo.Participants(operationId, cb)
    Omerta.DB.Query(
        "SELECT * FROM {crime_participants} WHERE operation_id = ?",
        { operationId }, function(rows, err) cb(rows or {}, err) end)
end

--------------------------------------------------------------------------------
-- Alarms
--------------------------------------------------------------------------------

function Repo.InsertAlarm(row, cb)
    Omerta.DB.Insert("crime_alarms", row, cb)
end

-- M16's queue. Everything nobody has answered yet, oldest first — because a
-- response queue that served the newest call first would be a queue that never
-- reached the bottom of itself.
function Repo.PendingAlarms(limit, cb)
    Omerta.DB.Query(
        "SELECT * FROM {crime_alarms} WHERE responded_at IS NULL ORDER BY id ASC LIMIT " ..
            math.floor(math.max(1, math.min(limit or 50, 200))),
        {}, function(rows, err) cb(rows or {}, err) end)
end

function Repo.MarkResponded(id, at, cb)
    cb = cb or function() end
    Omerta.DB.Query("UPDATE {crime_alarms} SET responded_at = ? WHERE id = ?",
        { at, id }, function(_, err) cb(err == nil, err) end)
end

function Repo.AlarmsFor(operationId, cb)
    Omerta.DB.Query("SELECT * FROM {crime_alarms} WHERE operation_id = ?",
        { operationId }, function(rows, err) cb(rows or {}, err) end)
end
