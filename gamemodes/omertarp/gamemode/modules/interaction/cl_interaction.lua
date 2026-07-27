-- Client side of the interaction framework: hold the interact key to open a
-- context menu on whatever you are looking at.
--
-- Contextual only, per the no-HUD rule (Tech §8): nothing is drawn unless you
-- are actively holding the key. Plain visuals for now — M8 owns presentation.

local BIND = "+menu_context"       -- default: C
local menu = { open = false, target = nil, options = {}, hovered = 0 }

local function currentTarget()
    local ply = LocalPlayer()
    if not IsValid(ply) then return nil end
    local tr = util.TraceLine({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * Omerta.Interaction.MAX_RANGE,
        filter = ply,
    })
    return IsValid(tr.Entity) and tr.Entity or nil
end

local function openMenu()
    local target = currentTarget()
    if not target then return end
    menu.open = true
    menu.target = target
    menu.options = {}
    menu.hovered = 0
    Omerta.Net.Request("interaction.query", { target = target:EntIndex() })
end

local function closeMenu(execute)
    if execute and menu.hovered > 0 and menu.options[menu.hovered] and IsValid(menu.target) then
        Omerta.Net.Request("interaction.execute", {
            target = menu.target:EntIndex(),
            action = menu.options[menu.hovered].index,
        })
    end
    menu.open = false
    menu.target = nil
    menu.options = {}
    menu.hovered = 0
end

hook.Add("Omerta.InteractionOptions", "omerta.interaction.options", function(payload)
    if not menu.open or not IsValid(menu.target) then return end
    if menu.target:EntIndex() ~= payload.target then return end
    menu.options = {}
    for i = 1, payload.count do
        menu.options[i] = { index = payload["i" .. i], label = payload["l" .. i] }
    end
    if #menu.options > 0 then menu.hovered = 1 end
end)

hook.Add("PlayerBindPress", "omerta.interaction.bind", function(ply, bind, pressed)
    if bind ~= BIND then return end
    if pressed then openMenu() else closeMenu(true) end
    return true -- suppress the default context menu entirely
end)

-- Mouse wheel selects while the menu is held.
hook.Add("Think", "omerta.interaction.scroll", function()
    if not menu.open or #menu.options == 0 then return end
    local delta = 0
    if input.WasMousePressed(MOUSE_WHEEL_UP) then delta = -1 end
    if input.WasMousePressed(MOUSE_WHEEL_DOWN) then delta = 1 end
    if delta ~= 0 then
        menu.hovered = ((menu.hovered - 1 + delta) % #menu.options) + 1
    end
end)

-- Registered with the HUD controller (M8): the menu is contextual by nature,
-- so it belongs to the same list as every other conditional element.
Omerta.HUD.Register("interaction.menu", {
    order = 60,
    fade = 0.12,
    visible = function() return menu.open end,
    draw = function(alpha)
        local scale = Omerta.HUD.Scale()
        local x, y = ScrW() * 0.5 + 24 * scale, ScrH() * 0.5 - 12 * scale

        if #menu.options == 0 then
            draw.SimpleText("nothing to do", Omerta.HUD.Font("label"), x, y,
                Color(190, 190, 190, 150 * alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            return
        end

        for i, opt in ipairs(menu.options) do
            local selected = (i == menu.hovered)
            local text = (selected and "> " or "  ") .. opt.label
            draw.SimpleText(text, Omerta.HUD.Font("label"), x, y + (i - 1) * 22 * scale,
                selected and Color(240, 235, 220, 255 * alpha)
                    or Color(170, 170, 170, 200 * alpha),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end,
})
