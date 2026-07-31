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

-- The switch is audible. Only a switch: pressing the slot you already hold,
-- or scrolling with nothing else to scroll to, stays silent.
local function switchTo(wep)
    local ply = LocalPlayer()
    if not IsValid(wep) then return end
    if IsValid(ply) and ply:GetActiveWeapon() == wep then return end
    input.SelectWeapon(wep)
    surface.PlaySound("omertarp/ui/inventory-click.wav")
end

local function selectSlot(index)
    local slots = buildSlots()
    if not slots then return end
    shownUntil = CurTime() + SHOW_FOR
    local slot = slots[index]
    if slot then switchTo(slot.wep) end
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
            switchTo(slots[i].wep)
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

-- The guide's §07 hotbar: a single column of 52px slot squares with 4px
-- gutters, left-centre. Each slot is a scrim square with a 1px rule, its
-- number in the corner in the system voice, and its item's icon tinted bone.
-- ONLY the held slot gets the brass border, the brass number and the caption
-- underneath — so "what is in my hands" is answerable without counting.
-- Empty slots sit at 45%.

local SLOT_ICON = {
    [2] = "icon_gun",   -- primary
    [3] = "icon_gun",   -- sidearm
    [4] = "icon_tools", -- melee
}

local iconCache = {}

local function slotIcon(index)
    local name = SLOT_ICON[index]
    if not name then return nil end
    if not iconCache[name] then
        iconCache[name] = Material("omertarp/icons/" .. name .. ".png", "smooth")
    end
    return iconCache[name]
end

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

        local size = 52 * scale
        local gap = Omerta.HUD.Space(1)
        local x = Omerta.HUD.Space(5)
        local y = (ScrH() - (4 * size + 3 * gap)) * 0.5
        local theme = Omerta.HUD.Theme

        for i = 1, 4 do
            local slot = slots[i]
            local held = IsValid(slot.wep)
            local isActive = i == active
            local presence = (isActive and 1 or held and 0.72 or 0.45) * alpha

            surface.SetDrawColor(Omerta.HUD.Colour("plate",
                theme.ALPHA.scrim * 255 * presence))
            surface.DrawRect(x, y, size, size)
            surface.SetDrawColor(Omerta.HUD.Colour(isActive and "brass" or "rule",
                255 * presence))
            surface.DrawOutlinedRect(x, y, size, size, 1)

            draw.SimpleText(i, Omerta.HUD.Font("mono"),
                x + 4 * scale, y + 3 * scale,
                Omerta.HUD.Colour(isActive and "brass" or "secondary", 235 * presence),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            local mat = held and slotIcon(i) or nil
            if mat then
                local cell = 24 * scale
                local iw, ih = cell, cell
                local mw, mh = mat:Width(), mat:Height()
                if mw > 0 and mh > 0 then
                    local fit = math.min(cell / mw, cell / mh)
                    iw, ih = mw * fit, mh * fit
                end
                surface.SetDrawColor(Omerta.HUD.Colour(isActive and "brass" or "text",
                    235 * presence))
                surface.SetMaterial(mat)
                surface.DrawTexturedRect(x + (size - iw) * 0.5, y + (size - ih) * 0.5, iw, ih)
            end

            y = y + size + gap
        end

        -- The caption: the held thing's name, and the fact it is in hands.
        local heldSlot = slots[active]
        if heldSlot and IsValid(heldSlot.wep) then
            Omerta.HUD.Text(heldSlot.name or heldSlot.label, "small",
                x, y + 2 * scale,
                Omerta.HUD.Colour("text", 235 * alpha),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            Omerta.HUD.Text("in hands", "small", x, y + 20 * scale,
                Omerta.HUD.Colour("secondary", 220 * alpha),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end,
})
