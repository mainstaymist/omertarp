-- Telephony (M12, D-003): payphones and location-bound private lines.
--
-- There are no personal telephones and there never will be. To reach somebody
-- you must know where they will be, or go and stand somewhere public and hope
-- — and the awkwardness of that is the feature.


Omerta.Phone = Omerta.Phone or {}
Omerta.Phone.Internal = Omerta.Phone.Internal or {}

Omerta.Phone.ACTION = {
    ANSWER = 1,
    HANGUP = 2,
    FEED   = 3,   -- put another coin in
}

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------
-- A client is told about ITS OWN call and nothing else. It is never told who
-- is on the other end beyond the number — a number is not a name (D-027), and
-- working out whose voice that is remains M5's problem and the caller's.

Omerta.Net.Register("phone.state", {
    realm = "server_to_client",
    schema = {
        { name = "state",   type = "uint", bits = 3 },   -- 0 idle, 1 ringing, 2 connected
        { name = "number",  type = "string", maxlen = 12 }, -- the far end's number
        { name = "seconds", type = "uint", bits = 12 },  -- credit left, payphones only
        { name = "incoming", type = "bool" },
    },
    handler = function(payload)
        hook.Run("Omerta.PhoneState", payload)
    end,
})

Omerta.Net.Register("phone.dial", {
    realm = "client_to_server",
    schema = { { name = "number", type = "string", maxlen = 12 } },
    -- Tight, because the dial pad is the one surface that could be used to
    -- sweep for private lines.
    rate = { burst = 4, per = 10 },
    handler = function(ply, payload)
        Omerta.Phone.Internal.HandleDial(ply, payload.number)
    end,
})

Omerta.Net.Register("phone.action", {
    realm = "client_to_server",
    schema = { { name = "action", type = "uint", bits = 3 } },
    rate = { burst = 8, per = 5 },
    handler = function(ply, payload)
        Omerta.Phone.Internal.HandleAction(ply, payload.action)
    end,
})

-- The text path is not a fallback bolted on; it is an equal way to hold the
-- conversation, because a call must be completable without a microphone
-- (Tech §8, S1 §4).
Omerta.Net.Register("phone.say", {
    realm = "client_to_server",
    schema = { { name = "text", type = "string", maxlen = 256 } },
    rate = { burst = 6, per = 6 },
    handler = function(ply, payload)
        Omerta.Phone.Internal.HandleSay(ply, payload.text)
    end,
})

Omerta.Net.Register("phone.heard", {
    realm = "server_to_client",
    schema = {
        { name = "number", type = "string", maxlen = 12 },
        { name = "text",   type = "string", maxlen = 256 },
    },
    handler = function(payload)
        hook.Run("Omerta.PhoneHeard", payload.number, payload.text)
    end,
})

-- A handset near you is ringing. Carries no number: whoever is calling has
-- not said who they are, and the telephone does not know either.
Omerta.Net.Register("phone.ring", {
    realm = "server_to_client",
    schema = { { name = "handset", type = "uint", bits = 16 } },
    handler = function(payload)
        hook.Run("Omerta.PhoneRinging", payload.handset)
    end,
})
