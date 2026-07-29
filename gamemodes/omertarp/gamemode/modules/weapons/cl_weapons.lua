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
    order = 21, -- beside stamina, in the band the eye already checks
    fade = 0.3,
    visible = function()
        return activeOmertaWeapon() ~= nil and CurTime() < shownUntil
    end,
    draw = function(alpha)
        local wep = activeOmertaWeapon()
        if not wep then return end
        local def = wep:Def()
        local clip = wep:Clip1()

        local text
        if clip <= 0 then
            text = "Empty — press R"
        elseif clip == 1 then
            text = "1 round"
        else
            text = clip .. " rounds"
        end

        -- Reddens as it runs dry, same convention as the stamina bar: readable
        -- without relying on colour alone, since the number is right there.
        local low = def and clip <= math.max(1, math.floor(def.clip * 0.25))
        draw.SimpleText(text, Omerta.HUD.Font("small"),
            ScrW() * 0.5, ScrH() * 0.815,
            Color(low and 205 or 210, low and 120 or 205, low and 110 or 185, 220 * alpha),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end,
})
