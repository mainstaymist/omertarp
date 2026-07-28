-- The rumour mill (§4c, D-031).
--
-- The pool takes entries from two places: real events, and anybody who buys
-- the barman a drink and tells him something. **He never distinguishes them.**
-- That is the entire point — a rumour you hear is not evidence, and
-- disinformation becomes something you can purchase.
--
-- Selection and expiry are pure and live here; the money and the database are
-- next door.

Omerta.Rumours = Omerta.Rumours or {}
Omerta.Rumours.Internal = Omerta.Rumours.Internal or {}

Omerta.Rumours.SOURCE = {
    EVENT   = "event",    -- something actually happened (M14/M15 fill this)
    PLANTED = "planted",  -- somebody paid to have it said
}

Omerta.Rumours.MAX_LENGTH = 240

--------------------------------------------------------------------------------
-- Pure selection
--------------------------------------------------------------------------------

function Omerta.Rumours.Internal.IsLive(rumour, now)
    if not rumour then return false end
    return (rumour.expires_at or 0) > now
end

-- Picks one rumour for a listener: live, and not one they have already been
-- told, preferring the freshest. Deterministic given its inputs — the barman
-- is not random, he is just out of date.
--
--   heard — set of rumour ids this character has already been given
-- Returns a rumour, or nil.
function Omerta.Rumours.Internal.Pick(rumours, heard, now)
    local best = nil
    for _, rumour in ipairs(rumours or {}) do
        if Omerta.Rumours.Internal.IsLive(rumour, now) and not (heard or {})[rumour.id] then
            if not best or rumour.created_at > best.created_at
                    or (rumour.created_at == best.created_at and rumour.id > best.id) then
                best = rumour
            end
        end
    end
    return best
end

-- What the barman says when he has nothing. Not an error: a quiet week is a
-- piece of information too.
Omerta.Rumours.NOTHING = "Nothing worth repeating."

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------
-- One line at a time, to one listener, on request. There is no rumour feed and
-- no history: what you were told is something you have to remember, which is
-- the same rule identity and telephone numbers already follow.

Omerta.Net.Register("rumour.heard", {
    realm = "server_to_client",
    schema = { { name = "text", type = "string", maxlen = 240 } },
    handler = function(payload)
        hook.Run("Omerta.RumourHeard", payload.text)
    end,
})

Omerta.Net.Register("rumour.plant", {
    realm = "client_to_server",
    schema = { { name = "text", type = "string", maxlen = 240 } },
    rate = { burst = 3, per = 30 },
    handler = function(ply, payload)
        Omerta.Rumours.Internal.HandlePlant(ply, payload.text)
    end,
})
