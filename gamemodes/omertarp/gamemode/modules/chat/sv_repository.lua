-- Chat repository. A table of its own rather than the audit log: chat volume
-- would bury the sensitive-action trail M2 exists to preserve.

Omerta.Chat = Omerta.Chat or {}
Omerta.Chat.Internal = Omerta.Chat.Internal or {}
local Internal = Omerta.Chat.Internal
Internal.Repo = Internal.Repo or {}
local Repo = Internal.Repo

function Repo.Log(row, cb)
    Omerta.DB.Insert("chat_log", row, cb)
end

-- "What was said near here, and when" — the query staff need when
-- investigating a metagaming report.
function Repo.RecentFor(characterId, limit, cb)
    Omerta.DB.Query(
        "SELECT at, channel, text FROM {chat_log} WHERE character_id = ? ORDER BY id DESC LIMIT " ..
            tostring(math.floor(limit)),
        { characterId }, cb)
end

function Repo.Sweep(cutoff, cb)
    Omerta.DB.Query("DELETE FROM {chat_log} WHERE at < ?", { cutoff },
        function(_, err) if cb then cb(err == nil, err) end end)
end

function Repo.DeleteForCharacter(characterId, cb)
    Omerta.DB.Query("DELETE FROM {chat_log} WHERE character_id = ?", { characterId },
        function(_, err) if cb then cb(err == nil, err) end end)
end
