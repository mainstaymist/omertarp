-- Client side of the interaction framework: E does the obvious thing, and
-- holding E offers everything else.
--
-- A tap runs the target's DEFAULT action — decided server-side, so the client
-- never names an action it was not entitled to. Holding past a beat opens the
-- menu on whatever you are looking at; the mouse wheel moves the selection
-- (and is swallowed, so it never also switches weapons); releasing E runs the
-- highlighted option; looking away closes the menu without running anything,
-- which is also how you change your mind.
--
-- Contextual only, per the no-HUD rule (Tech §8): nothing is drawn unless the
-- key is actually held.

local HOLD = 0.28 -- seconds of held E before the menu opens

local menu = {
    target = nil,   -- the entity the press started on
    pressedAt = 0,
    held = false,   -- the menu is on screen
    options = {},
    hovered = 0,
}

local function reset()
    menu.target = nil
    menu.held = false
    menu.options = {}
    menu.hovered = 0
end

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

-- The hotbar asks this before it touches the mouse wheel: while the menu is
-- open the wheel belongs here, and the moment it closes the wheel goes back
-- to switching what is in your hands.
function Omerta.Interaction.IsMenuOpen()
    return menu.held
end

hook.Add("Omerta.InteractionOptions", "omerta.interaction.options", function(payload)
    if not (menu.target and IsValid(menu.target)) then return end
    if menu.target:EntIndex() ~= payload.target then return end
    menu.options = {}
    for i = 1, payload.count do
        menu.options[i] = { index = payload["i" .. i], label = payload["l" .. i] }
    end
    if #menu.options > 0 and menu.hovered == 0 then menu.hovered = 1 end
end)

hook.Add("PlayerBindPress", "omerta.interaction.bind", function(ply, bind, pressed)
    if bind == "+use" then
        if pressed then
            -- Only things the dot lights up for; a door or a valve keeps the
            -- engine's own use behaviour untouched.
            local target = Omerta.HUD.InteractableTarget()
            if not target then return end
            menu.target = target
            menu.pressedAt = CurTime()
            menu.held = false
            menu.options, menu.hovered = {}, 0
            -- Fetched NOW, so a held menu opens already populated instead of
            -- flashing "nothing to do" for a round trip.
            Omerta.Net.Request("interaction.query", { target = target:EntIndex() })
            return true
        end

        if not menu.target then return end
        if menu.held then
            local choice = menu.options[menu.hovered]
            if choice and IsValid(menu.target) then
                Omerta.Net.Request("interaction.execute", {
                    target = menu.target:EntIndex(),
                    action = choice.index,
                })
            end
        elseif IsValid(menu.target) and currentTarget() == menu.target then
            -- A tap. The server decides what the default IS; the client only
            -- reports that the obvious thing was asked for.
            Omerta.Net.Request("interaction.default", { target = menu.target:EntIndex() })
        end
        reset()
        return true
    end

    -- The mouse wheel arrives as the engine's weapon-switch binds — swallowed
    -- while the menu is up, so scrolling options never changes your hands.
    if menu.held and pressed and (bind == "invprev" or bind == "invnext") then
        if #menu.options > 0 then
            local delta = bind == "invprev" and -1 or 1
            menu.hovered = ((menu.hovered - 1 + delta) % #menu.options) + 1
        end
        return true
    end
end)

-- The menu is ABOUT the thing under your eyes, so it lives and dies with the
-- look: turning away closes it without executing — the cancel — and a held
-- press crosses into the menu only while still on its target.
hook.Add("Think", "omerta.interaction.watch", function()
    if not menu.target then return end
    if currentTarget() ~= menu.target then reset() return end
    if not menu.held and CurTime() - menu.pressedAt >= HOLD then
        menu.held = true
    end
end)

-- Registered with the HUD controller (M8): the menu is contextual by nature,
-- so it belongs to the same list as every other conditional element.
Omerta.HUD.Register("interaction.menu", {
    order = 60,
    fade = 0.12,
    visible = function() return menu.held end,
    draw = function(alpha)
        local scale = Omerta.HUD.Scale()
        local x, y = ScrW() * 0.5 + 24 * scale, ScrH() * 0.5 - 12 * scale

        if #menu.options == 0 then
            Omerta.HUD.Text("nothing to do", "label", x, y,
                Color(190, 190, 190, 150 * alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            return
        end

        for i, opt in ipairs(menu.options) do
            local selected = (i == menu.hovered)
            local text = (selected and "> " or "  ") .. opt.label
            Omerta.HUD.Text(text, "label", x, y + (i - 1) * 26 * scale,
                selected and Color(240, 235, 220, 255 * alpha)
                    or Color(170, 170, 170, 200 * alpha),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end,
})
