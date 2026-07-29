-- All SQL for the event log. Gameplay calls the service, never this.

Omerta.Events = Omerta.Events or {}
Omerta.Events.Internal = Omerta.Events.Internal or {}
Omerta.Events.Internal.Repo = Omerta.Events.Internal.Repo or {}
local Repo = Omerta.Events.Internal.Repo

-- cb(id, err)
function Repo.Insert(row, cb)
    Omerta.DB.Insert("events", row, cb)
end

function Repo.Get(id, cb)
    Omerta.DB.QueryOne("SELECT * FROM {events} WHERE id = ?", { id }, cb)
end

function Repo.ForCharacter(characterId, limit, cb)
    Omerta.DB.Query(
        "SELECT * FROM {events} WHERE subject_character_id = ? OR actor_character_id = ? " ..
        "ORDER BY id DESC LIMIT " .. math.floor(math.max(1, math.min(limit or 50, 200))),
        { characterId, characterId }, function(rows, err) cb(rows or {}, err) end)
end

-- The cursor M21 pages through. Ascending, because a newspaper reads forward
-- from where it left off rather than backwards from now.
function Repo.Since(afterId, limit, cb)
    Omerta.DB.Query(
        "SELECT * FROM {events} WHERE id > ? ORDER BY id ASC LIMIT " ..
            math.floor(math.max(1, math.min(limit or 50, 200))),
        { afterId or 0 }, function(rows, err) cb(rows or {}, err) end)
end

function Repo.MarkPublished(id, at, cb)
    cb = cb or function() end
    Omerta.DB.Query("UPDATE {events} SET published_at = ? WHERE id = ?", { at, id },
        function(_, err) cb(err == nil, err) end)
end
