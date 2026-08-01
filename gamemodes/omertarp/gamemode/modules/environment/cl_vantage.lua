-- Where the front-end camera stands, per map.
--
-- The menu already owns the registry and the fallback (modules/menu/cl_menu.lua
-- — an unknown map gets a slow orbit around wherever the player happens to be,
-- which is always somewhere the map intends people to stand). What was missing
-- was somewhere to AUTHOR a vantage that is not the menu's own source file, so
-- that adding one is a data edit made by whoever is looking at the map rather
-- than a code edit made in a file three other systems are also editing.
--
-- This is that place. One row per map in VANTAGES below; nothing else changes,
-- here or anywhere.
--
-- Registered from OnEnable rather than at file scope, and this module does not
-- depend on `menu`: the loader includes modules in dependency order and
-- `environment` sorts before `menu`, so Omerta.Menu.RegisterVantage does not
-- exist yet while this file is being read. OnEnable runs after every module
-- has loaded, which is late enough, and the soft check below means a build
-- without the menu still boots rather than nil-indexing on the way up.

Omerta.Environment = Omerta.Environment or {}

--------------------------------------------------------------------------------
-- The data
--------------------------------------------------------------------------------
-- Keyed by the map filename EXACTLY as game.GetMap() reports it: no "maps/"
-- prefix and no ".bsp" suffix (e.g. "gm_construct").
--
-- A row may carry any of:
--   pos     Vector   the point the camera orbits — the only required field
--   radius  number   how far out it sits          (menu default: ORBIT.RADIUS)
--   height  number   how far above pos            (menu default: ORBIT.HEIGHT)
--   pitch   number   downward tilt, degrees       (menu default: ORBIT.PITCH)
--   speed   number   degrees per second           (menu default: ORBIT.SPEED)
--   fov     number                                (menu default: ORBIT.FOV)
--
-- ============================================================================
-- rp_unioncity — the map, now named, and STILL WITHOUT A POSITION.
--
-- The filename is confirmed (the lead read it off a running server). The shot
-- is not, and cannot be from here: `pos` is a point in a world nobody working
-- on this file has stood in, and there is no way to pick one by reasoning. A
-- guessed vector is worse than none — it puts the opening camera inside a wall
-- or under the map, which is a bug that looks like the menu being broken,
-- where no row at all is the fallback orbit doing exactly what it was written
-- for.
--
-- The fallback is not a placeholder, either: it orbits the player's own
-- position, and a player at the menu is standing on the map's spawn — which on
-- a city map is a deliberately chosen, deliberately presentable place. It will
-- look fine. Authoring a row buys a BETTER shot, not a working one.
--
-- To author it: stand where the camera should orbit, `getpos` in console, and
-- add ONE row —
--
--     ["rp_unioncity"] = { pos = Vector(-1200, 640, 320), radius = 260,
--                          height = 90, pitch = 8, speed = 4 },
--
-- The framing fields are all optional; the menu's ORBIT defaults are sane and
-- worth trying before tuning any of them.
-- ============================================================================

local VANTAGES = {
}

--------------------------------------------------------------------------------
-- Handing them over
--------------------------------------------------------------------------------

function Omerta.Environment.RegisterVantages()
    Omerta.AssertClient("Omerta.Environment.RegisterVantages")

    local menu = Omerta.Menu
    if not menu or not menu.RegisterVantage then
        -- Not an error. The front end is a module like any other and a build
        -- without it is a build with no camera to place.
        Omerta.Log.Debug("environment", "no front end to register vantages with")
        return
    end

    local count = 0
    for map, def in pairs(VANTAGES) do
        menu.RegisterVantage(map, def)
        count = count + 1
    end

    if not Omerta.InEngine then return end

    local here = game.GetMap()
    if VANTAGES[here] then
        Omerta.Log.Debug("environment", "front-end vantage registered for '%s'", here)
    else
        -- Info, once, on the client. This is the line that turns "the menu
        -- camera is just spinning round my head" from a bug report into a
        -- known and deliberate state with an obvious fix attached.
        Omerta.Log.Info("environment", "no front-end vantage for map '%s' " ..
            "(%d registered) — the menu falls back to an orbit; author one in " ..
            "modules/environment/cl_vantage.lua", here, count)
    end
end
