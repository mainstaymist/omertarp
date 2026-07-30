-- The server half of the front end: what the operator may configure, and what
-- clients are sent for it.

local MODULE = Omerta.Module.Get("menu")

Omerta.Menu = Omerta.Menu or {}

-- Whether a player sees the opening is a CLIENT convar (omerta_intro), not a
-- server config: forcing it from here would mean networking a value the client
-- reads before it has one, and "must I watch this every time I join" is the
-- player's call anyway. Operator-side control over the sequence is M27's.

-- The open M28 ruling, made safe rather than made up.
--
-- The intro track is 30.9 MB of uncompressed WAV. Registering it means every
-- player downloads it before their first impression of the game — which is the
-- exact cost M28's review exists to weigh, and not a cost to incur silently by
-- shipping a default. OFF means the music plays for anybody who already has
-- the file (developers, and any client that has mounted the gamemode) and
-- nobody else waits for it.
Omerta.Config.Define("menu.send_music", {
    type = "boolean", default = false, scope = "server",
    description = "Send the 30.9 MB intro track to every client on join. " ..
        "Leave off until it is compressed (M28) — this is a first-impression " ..
        "download standing between a new player and the game.",
})

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    if Omerta.Config.Get("menu.send_music") then
        resource.AddFile("sound/omertarp/cry-me-a-river.wav")
        Omerta.Log.Warn("menu", "sending the 30.9 MB intro track to every " ..
            "client on join — compress it (M28) before this reaches players")
    end
end
