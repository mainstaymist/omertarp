-- What the player sees of their own gun: a round count that appears when it
-- would be looked at, and is gone the rest of the time.
--
-- The engine's ammo HUD went in M8 with everything else permanent. This is its
-- contextual replacement: a character can count the rounds they have loaded —
-- that is knowledge the fiction grants — but a counter pinned to the screen is
-- exactly the omniscient furniture GDD §8 removed. So it fades in on the
-- moments that mean "I am thinking about my gun" (drawing it, firing it,
-- reloading it) and fades back out.

Omerta.Weapons = Omerta.Weapons or {}

local shownUntil = 0
local lastClass, lastClip = nil, -1

-- What is left in the coat. The clip is predicted and free to read, but rounds
-- in a pocket are M9 inventory rows the client is not continuously told about
-- — so the server sends this number when it changes, and the readout simply
-- shows the last thing it was told.
local reserve = 0

hook.Add("Omerta.WeaponReserve", "omerta.weapons.reserve", function(count)
    reserve = count or 0
end)

-- By CLASS, not by `wep.OmertaId`.
--
-- Our own generated classes carry the id on the class table, so both realms
-- see it — but a weapon running a third party's class carries it only on the
-- server entity, where giveOne stamps it, and a plain Lua field is not
-- networked. The arsenal is shared data and maps BOTH classes to the same
-- definition, so asking what class is in the hand is the reading that works
-- whichever half of the pair won.
local function activeOmertaWeapon()
    local ply = LocalPlayer()
    if not IsValid(ply) then return nil end
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return nil end
    if not Omerta.Weapons.ForClass(wep:GetClass()) then return nil end
    return wep
end

-- Change detection rather than events: the clip is already networked for
-- prediction, so watching it costs nothing and misses nothing.
hook.Add("Think", "omerta.weapons.readout", function()
    local wep = activeOmertaWeapon()
    if not wep then
        lastClass, lastClip = nil, -1
        return
    end
    local class, clip = wep:GetClass(), wep:Clip1()
    if class ~= lastClass or clip ~= lastClip then
        lastClass, lastClip = class, clip
        shownUntil = CurTime() + 2.5
    end
end)

-- The ammunition block, bottom right. It is present the whole time a gun is
-- in the hands rather than for a few seconds after touching it: a drawn
-- weapon is a decision the player is actively living with, and how many
-- rounds are in it is the single fact that decision turns on. It fades in as
-- the gun comes up and out as it goes away, so putting it away still returns
-- the screen to empty.
Omerta.HUD.Register("weapons.rounds", {
    order = 21,
    fade = 0.35,
    visible = function()
        return activeOmertaWeapon() ~= nil
    end,
    draw = function(alpha)
        local wep = activeOmertaWeapon()
        if not wep then return end
        -- `wep:Clip1()`, never `wep:Def()`. Def is a method on OUR base and a
        -- third party's SWEP does not have it; Clip1 is engine and every
        -- weapon does. Nothing here needed the definition anyway.
        local clip = wep:Clip1()
        local scale = Omerta.HUD.Scale()
        local margin = Omerta.HUD.Space(5)
        local x = ScrW() - margin
        local y = ScrH() - margin

        -- LOADED / reserve, and in that order — loaded on the LEFT.
        --
        -- The first version had them the wrong way round. Both are
        -- right-aligned against the screen margin, so drawing the loaded count
        -- there and hanging the reserve off its left edge put the big number
        -- last and read as "/ 0  6" — a magazine of nothing beside a number
        -- with no label. It is one phrase and it reads left to right: what is
        -- in the gun, then what is left for it.
        --
        -- The reserve keeps the right-hand anchor because it is the piece that
        -- changes width least often; growing the loaded count pushes leftward,
        -- away from the edge, instead of shoving the whole block about.
        local loaded = tostring(clip)
        local trailing = "/ " .. reserve
        surface.SetFont(Omerta.HUD.Font("label"))
        local trailingWide = surface.GetTextSize(trailing)

        Omerta.HUD.Text(trailing, "label", x, y - 2 * scale,
            Omerta.HUD.Colour("secondary", 150 * alpha),
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
        Omerta.HUD.Text(loaded, "count",
            x - trailingWide - 6 * scale, y,
            Omerta.HUD.Colour("text", 245 * alpha),
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)

        -- The line under it only speaks when it has something to say: an
        -- empty gun, or an empty gun with nothing to feed it.
        local note
        if clip <= 0 and reserve <= 0 then
            note = "NOTHING LEFT"
        elseif clip <= 0 then
            note = "EMPTY · PRESS R"
        end
        if note then
            Omerta.HUD.Text(note, "mono", x, y - 34 * scale,
                Omerta.HUD.Colour(reserve <= 0 and "danger" or "secondary", 235 * alpha),
                TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
        end
    end,
})
