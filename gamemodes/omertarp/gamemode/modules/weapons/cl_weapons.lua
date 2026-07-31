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

local function activeOmertaWeapon()
    local ply = LocalPlayer()
    if not IsValid(ply) then return nil end
    local wep = ply:GetActiveWeapon()
    if not (IsValid(wep) and wep.OmertaId) then return nil end
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

Omerta.HUD.Register("weapons.rounds", {
    order = 21,
    fade = 0.3,
    visible = function()
        return activeOmertaWeapon() ~= nil and CurTime() < shownUntil
    end,
    draw = function(alpha)
        local wep = activeOmertaWeapon()
        if not wep then return end
        local def = wep:Def()
        local clip = wep:Clip1()
        local scale = Omerta.HUD.Scale()
        local margin = Omerta.HUD.Space(5)
        local x = ScrW() - margin
        local y = ScrH() - margin

        -- The guide's ammunition block, bottom-right: the count as the big
        -- tabular number, the context under it in the system voice. No low
        -- colour — the words carry it, and the guide colours nothing but the
        -- selected and the irreversible.
        local context
        if clip <= 0 then
            context = "EMPTY · PRESS R"
        else
            context = "IN THE " .. string.upper(def and def.chamber or "magazine")
        end

        Omerta.HUD.Text(context, "mono", x, y,
            Omerta.HUD.Colour("secondary", 235 * alpha),
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
        Omerta.HUD.Text(clip, "count", x, y - 20 * scale,
            Omerta.HUD.Colour("text", 245 * alpha),
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    end,
})
