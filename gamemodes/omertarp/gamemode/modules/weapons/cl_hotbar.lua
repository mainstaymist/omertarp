-- The hotbar: what is on your person that can be in your hands. Four slots,
-- one item each, down the left of the screen — replacing the engine's weapon
-- selector, which is sandbox furniture (six columns of stacked tools) in a
-- game where a person carries at most a coat's worth.
--
-- Slot 1 is always your hands (the holster — see weapon_omerta_hands). The
-- rest are M9's carry slots a weapon can occupy: primary, sidearm, melee.
-- M9 enforces one item per slot, which is why the bar cannot overflow.
--
-- Contextual, like the round counter: it appears while you are choosing and
-- fades once you have chosen (GDD §8 — no permanent furniture). Switching is
-- immediate; there is no "press attack to confirm" ceremony.

Omerta.Weapons = Omerta.Weapons or {}

local shownUntil = 0
local SHOW_FOR = 2.2

-- Which bar position an equipment slot occupies. Hands own position 1.
local SLOT_POSITION = { primary = 2, sidearm = 3, melee = 4 }
local SLOT_LABEL = { "Hands", "Primary", "Sidearm", "Melee" }

local function buildSlots()
    local ply = LocalPlayer()
    if not IsValid(ply) then return nil end

    local slots = {}
    for i = 1, 4 do slots[i] = { label = SLOT_LABEL[i] } end

    local hands = ply:GetWeapon(Omerta.Weapons.HANDS)
    if IsValid(hands) then
        slots[1].wep, slots[1].name = hands, "Hands"
    end

    for _, wep in ipairs(ply:GetWeapons()) do
        if wep.OmertaId then
            local def = Omerta.Weapons.Get(wep.OmertaId)
            local position = def and SLOT_POSITION[def.slot]
            if position then
                slots[position].wep, slots[position].name = wep, def.name
            end
        end
    end
    return slots
end

local function activeIndex(slots)
    local ply = LocalPlayer()
    local active = IsValid(ply) and ply:GetActiveWeapon() or nil
    if IsValid(active) then
        for i = 1, 4 do
            if slots[i].wep == active then return i end
        end
    end
    return 0
end

local function selectSlot(index)
    local slots = buildSlots()
    if not slots then return end
    shownUntil = CurTime() + SHOW_FOR
    local slot = slots[index]
    if slot and IsValid(slot.wep) then
        input.SelectWeapon(slot.wep)
    end
end

-- The wheel walks to the next slot that actually holds something, wrapping.
local function step(delta)
    local slots = buildSlots()
    if not slots then return end
    shownUntil = CurTime() + SHOW_FOR
    local from = activeIndex(slots)
    if from == 0 then from = 1 end
    for offset = 1, 3 do
        local i = ((from - 1 + delta * offset) % 4) + 1
        if IsValid(slots[i].wep) then
            input.SelectWeapon(slots[i].wep)
            return
        end
    end
end

hook.Add("PlayerBindPress", "omerta.weapons.hotbar", function(ply, bind, pressed)
    if not pressed then return end
    -- The C menu owns the wheel while it is open; it swallows these binds
    -- itself, and this stands aside so hook order can never matter.
    if Omerta.Interaction.IsMenuOpen and Omerta.Interaction.IsMenuOpen() then return end
    -- On the floor or dead you choose nothing — and the death screen's
    -- "press any key" must not be eaten here.
    local C = Omerta.Injury and Omerta.Injury.Client
    if C and Omerta.Injury.IsIncapable(C.state) then return end

    if bind == "invnext" then step(1) return true end
    if bind == "invprev" then step(-1) return true end

    local slot = bind:match("^slot(%d+)$")
    if slot then
        local index = tonumber(slot)
        if index >= 1 and index <= 4 then selectSlot(index) end
        return true -- 5 through 0 are swallowed: there is nothing there
    end
end)

-- Equipping from the inventory (or being disarmed) changes the answer without
-- a bind ever firing, so the bar also shows itself when the active weapon
-- changes for any reason at all.
local lastActive = nil
hook.Add("Think", "omerta.weapons.hotbar_watch", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local active = ply:GetActiveWeapon()
    local class = IsValid(active) and active:GetClass() or ""
    if class ~= lastActive then
        if lastActive ~= nil then shownUntil = CurTime() + SHOW_FOR end
        lastActive = class
    end
end)

local COLOURS = {
    panel  = Color(20, 19, 18),
    paper  = Color(232, 226, 210),
    muted  = Color(120, 113, 103),
    line   = Color(70, 64, 56),
    active = Color(198, 178, 130),
}

Omerta.HUD.Register("weapons.hotbar", {
    order = 22,
    fade = 0.25,
    visible = function()
        return CurTime() < shownUntil
    end,
    draw = function(alpha)
        local slots = buildSlots()
        if not slots then return end
        local scale = Omerta.HUD.Scale()
        local active = activeIndex(slots)

        local width, rowH, gap = 172 * scale, 36 * scale, 6 * scale
        local x = 24 * scale
        local y = (ScrH() - (4 * rowH + 3 * gap)) * 0.5

        for i = 1, 4 do
            local slot = slots[i]
            local held = IsValid(slot.wep)
            local isActive = i == active

            surface.SetDrawColor(COLOURS.panel.r, COLOURS.panel.g, COLOURS.panel.b,
                (isActive and 235 or held and 185 or 110) * alpha)
            surface.DrawRect(x, y, width, rowH)
            local border = isActive and COLOURS.active or COLOURS.line
            surface.SetDrawColor(border.r, border.g, border.b,
                (isActive and 235 or 130) * alpha)
            surface.DrawOutlinedRect(x, y, width, rowH, 1)

            draw.SimpleText(i, Omerta.HUD.Font("small"),
                x + 10 * scale, y + rowH * 0.5,
                Color(COLOURS.muted.r, COLOURS.muted.g, COLOURS.muted.b, 220 * alpha),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            -- A held slot names its item; an empty one dimly names itself, so
            -- the bar reads as places things could be rather than a mystery.
            local text = held and slot.name or slot.label
            local colour = isActive and COLOURS.paper
                or held and Color(200, 193, 180) or COLOURS.muted
            draw.SimpleText(text, Omerta.HUD.Font("label"),
                x + 26 * scale, y + rowH * 0.5,
                Color(colour.r, colour.g, colour.b, (held and 235 or 140) * alpha),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            y = y + rowH + gap
        end
    end,
})
