-- Hidden population: the suppressions that stop the engine and the default
-- gamemode from handing out what M5 made players earn.
--
-- This module mostly DELETES. Its correctness is measured by what a player
-- cannot find, which is why it ships with an audit (sv_population.lua) rather
-- than trusting that the suppressions stay installed.

Omerta.Module.Register({
    name = "population",
    depends = { "characters", "identity" },
})

Omerta.Population = Omerta.Population or {}

-- Every player sits on one team, always. Faction never touches the team API
-- (Tech §4): team counts are client-readable, so a faction-shaped team layout
-- would publish the size of the police force to anyone who asked.
Omerta.Population.TEAM_CITIZEN = 1

--------------------------------------------------------------------------------
-- D-015: Player:Nick() / Name() / GetName()
--------------------------------------------------------------------------------
-- These return the Steam name, so any stray print — ours, an addon's, an admin
-- mod's — would leak a real-world identity that can be correlated with a
-- character. They now return "Unknown" for everyone, except that on the client
-- your own methods return your own character's name.
--
-- The true Steam name stays reachable server-side via Omerta.Population.RealName
-- for logs, audit rows and staff tooling. This is not airtight: Nick() is a Lua
-- method and the engine still knows the truth (M6 §7).

if Omerta.InEngine then
    local PLAYER = FindMetaTable("Player")

    -- Captured once. Guarded so a Lua refresh cannot overwrite the original
    -- with our own replacement and lose the real name permanently.
    PLAYER.OmertaSteamName = PLAYER.OmertaSteamName or PLAYER.Nick

    local function displayName(self)
        if CLIENT and self == LocalPlayer() then
            local own = Omerta.Characters.GetLocal()
            if own then return own.first_name .. " " .. own.last_name end
        end
        return Omerta.Identity.UNKNOWN
    end

    PLAYER.Nick = displayName
    PLAYER.Name = displayName
    PLAYER.GetName = displayName
end
