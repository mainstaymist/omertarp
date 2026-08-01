-- The Workshop items the world is made of, and getting them onto clients.
--
-- ONE table, because a workshop id is the ONLY thing about these two addons
-- that this repository is able to state as a fact. The lead gave us two
-- numbers. A number is exact and verifiable — it resolves to one item and
-- always the same one — so registering it is safe even though we cannot say
-- what it contains. Every other property (the addon's name, the map's
-- filename, the weather system's Lua API) is unverified and appears in this
-- file only as prose, clearly marked, never as a string any code depends on.
--
-- That distinction is the whole reason the table has a `believed` field beside
-- the id instead of a helpful-looking `name` field. A `name` would be read by
-- the next person as a fact, and then written into a comparison by the person
-- after that.
--
-- WHAT THIS DOES AND DOES NOT DO: resource.AddWorkshop makes CLIENTS download
-- and mount the item when they join. It does NOT mount anything on the server.
-- The server needs both items in its own Workshop collection (host_workshop_-
-- collection) or mounted locally, or it will be running a map it does not have
-- and calling into an addon that was never loaded. That is server
-- configuration and a gamemode cannot do it — it is recorded here because this
-- is the file somebody reads when the client half works and the server half
-- does not.

Omerta.Environment = Omerta.Environment or {}

Omerta.Environment.WORKSHOP = {
    {
        id = "1656078410",
        believed = "the city map",
        -- The map's FILENAME is CONFIRMED: the project lead read it off a
        -- running server. That is what game.GetMap() returns, what changelevel
        -- takes, and what a front-end vantage is keyed by.
        --
        -- The Workshop TITLE is still unknown and does not matter — nothing
        -- keys off it, and the id is exact. Recorded as a fact only because a
        -- map filename is the one thing here that other code legitimately
        -- compares against.
        map = "rp_unioncity",
        unverified = "workshop title unconfirmed (Steam unreachable); filename confirmed in the field",
    },
    {
        id = "1132466603",
        believed = "the weather and time-of-day system",
        -- UNVERIFIED. Most likely StormFox, which exists in two incompatible
        -- generations with different APIs — so "most likely StormFox" is not
        -- enough to build against, and nothing does: everything that reads it
        -- goes through Omerta.Environment's provider seam, which detects by
        -- feature at runtime and degrades to a clear day when it finds nothing
        -- it recognises (D-043).
        unverified = "name, generation and Lua API unconfirmed (Steam unreachable)",
    },
}

function Omerta.Environment.MountContent()
    Omerta.AssertServer("Omerta.Environment.MountContent")
    if not Omerta.InEngine then return end

    for _, item in ipairs(Omerta.Environment.WORKSHOP) do
        resource.AddWorkshop(item.id)
        Omerta.Log.Info("environment",
            "clients will download workshop %s (believed: %s)", item.id, item.believed)
    end

    -- Said once, at Info rather than Warn, because it is not a fault — it is
    -- the half of the job that lives outside this repository, and the boot log
    -- is where an operator is actually looking when the map fails to load.
    Omerta.Log.Info("environment",
        "resource.AddWorkshop only makes CLIENTS download these — the server " ..
        "must carry both in its own collection (host_workshop_collection) or " ..
        "have them mounted locally")
end
