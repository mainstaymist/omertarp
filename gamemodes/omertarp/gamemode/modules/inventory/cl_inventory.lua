-- The inventory window, and the one thing hunger is ever allowed to say
-- unprompted.
--
-- This is a VGUI frame rather than a HUD element, for the same reason the
-- character-creation window is: it takes input, and the empty-screen rule is
-- about what is on screen when you have not asked for anything. Nothing here
-- draws unless the player opened it.
--
-- The table is OURS, not the engine's: DListView is sandbox furniture — grey
-- headers, six-point text, selection semantics nothing here wants — so rows
-- are plain panels painted in the UI's own idiom, with the category icons.
-- Looting shows two windows: your pockets on the left, whatever you are into
-- on the right, each its own framed thing.
--
-- Hunger is read HERE and nowhere else (D-016) — deliberately, like money in a
-- wallet. The single exception is the starvation warning below (D-019).

local Internal = Omerta.Inventory.Internal

local state = {
    container = 0,
    label = "",
    mine = {},
    theirs = {},
    bulkUsed = 0,
    bulkLimit = 0,
}

local hunger = Omerta.Hunger.MAX
local frame = nil
local incoming = nil

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------
-- The contents arrive as begin / item... / end. A stream that is interrupted
-- simply never replaces the state, so a half-arrived inventory is never shown.

function Internal.BeginStream(payload)
    incoming = {
        container = payload.container,
        label = payload.label or "",
        mine = {},
        theirs = {},
        bulkUsed = payload.bulk_used,
        bulkLimit = payload.bulk_limit,
    }
end

function Internal.StreamItem(payload)
    if not incoming then return end
    local def = Omerta.Items.GetByIndex(payload.def)
    if not def then return end

    local entry = {
        instance = payload.instance,
        def = def,
        quantity = payload.quantity,
        slot = payload.slot > 0 and Omerta.Inventory.GetSlotByIndex(payload.slot) or nil,
    }
    local list = payload.where == 2 and incoming.theirs or incoming.mine
    list[#list + 1] = entry
end

function Internal.EndStream(payload)
    if not incoming or incoming.container ~= payload.container then return end
    state = incoming
    incoming = nil

    if IsValid(frame) then
        frame:Rebuild()
    else
        Omerta.Inventory.Show()
    end
end

--------------------------------------------------------------------------------
-- Asking
--------------------------------------------------------------------------------

function Omerta.Inventory.Request(containerEntIndex)
    Omerta.Net.Request("inventory.open", { target = containerEntIndex or 0 })
end

function Omerta.Inventory.Toggle()
    if IsValid(frame) then
        frame:Close()
        return
    end
    Omerta.Inventory.Request(0)
end

local function act(action, entry, quantity)
    if not entry then return end
    Omerta.Net.Request("inventory.action", {
        action = action,
        instance = entry.instance,
        target = state.container or 0,
        quantity = quantity or 0,
    })
end

--------------------------------------------------------------------------------
-- The look
--------------------------------------------------------------------------------

-- Every colour here is a Carbon token (sh_theme). Nothing in this file picks
-- a value; it picks a ROLE, and the standard decides what that looks like.
local C = Omerta.HUD.Colour
local COLOURS = {
    paper   = C("textPrimary"),
    muted   = C("textSecondary"),
    faint   = C("textPlaceholder"),
    panel   = C("background", 246),
    strip   = C("layer01"),
    row     = C("layer01", 235),
    rowHot  = C("layerHover"),
    line    = C("borderSubtle"),
    accent  = C("linkPrimary"),
    warning = C("supportError"),
}

-- The category icons (player-provided line art, white on transparency, so
-- they tint cleanly). An item may name its own with `icon = "icon_x"`;
-- otherwise the category decides, and anything unmapped reads as junk —
-- which, in this city, is the honest default.
local CATEGORY_ICON = {
    weapon         = "icon_gun",
    ammo           = "icon_ammo",
    clothing       = "icon_clothes",
    food           = "icon_food",
    drink          = "icon_food",
    money          = "icon_money",
    tool           = "icon_tools",
    misc           = "icon_junk",
    medical        = "icon_components",
    communications = "icon_components",
}

local iconCache = {}

local function iconFor(def)
    local name = def.icon or CATEGORY_ICON[def.category] or "icon_junk"
    if not iconCache[name] then
        iconCache[name] = Material("omertarp/icons/" .. name .. ".png", "smooth")
    end
    return iconCache[name]
end

--------------------------------------------------------------------------------
-- What you can do with a thing
--------------------------------------------------------------------------------
-- Everything hangs off the right mouse button. A context menu asks the entry
-- itself what applies, every time it opens, so it can never go stale.

local function openRowMenu(entry, mine)
    if not entry then return end
    local A = Omerta.Inventory.ACTION
    local m = DermaMenu()

    local function option(label, fn)
        local opt = m:AddOption(label, fn)
        opt:SetFont(Omerta.HUD.Font("label"))
        return opt
    end

    if not mine then
        option("Take", function() act(A.TAKE, entry) end)
        m:Open()
        return
    end

    if entry.def.slot then
        if entry.slot then
            option("Unequip", function() act(A.UNEQUIP, entry) end)
        else
            option("Equip", function() act(A.EQUIP, entry) end)
        end
    end
    if entry.def.feeds or entry.def.onUse then
        option("Use", function() act(A.USE, entry) end)
    end
    if entry.def.stackable and entry.quantity > 1 then
        option("Split…", function()
            Derma_StringRequest("Split " .. entry.def.name,
                "How many go to the new stack?",
                tostring(math.floor(entry.quantity / 2)),
                function(text)
                    local count = math.floor(tonumber(text) or 0)
                    if count >= 1 and count < entry.quantity then
                        act(A.SPLIT, entry, count)
                    end
                end)
        end)
    end
    if state.container and state.container > 0 then
        option("Store", function() act(A.STORE, entry) end)
    end
    option("Drop", function() act(A.DROP, entry) end)

    m:Open()
end

--------------------------------------------------------------------------------
-- Rows and windows
--------------------------------------------------------------------------------

local function buildRow(parent, entry, mine)
    local scale = Omerta.HUD.Scale()
    local row = vgui.Create("DPanel", parent)
    row:SetTall(36 * scale)
    row:Dock(TOP)
    row:DockMargin(0, 0, 0, 2)
    row:SetCursor("hand")

    row.Paint = function(self, w, h)
        local colour = self:IsHovered() and COLOURS.rowHot or COLOURS.row
        surface.SetDrawColor(colour.r, colour.g, colour.b, colour.a)
        surface.DrawRect(0, 0, w, h)

        -- The icon, tinted paper, fitted to a square cell without squashing.
        local mat = iconFor(entry.def)
        local cell = h - 10 * scale
        local iw, ih = cell, cell
        local mw, mh = mat:Width(), mat:Height()
        if mw > 0 and mh > 0 then
            local fit = math.min(cell / mw, cell / mh)
            iw, ih = mw * fit, mh * fit
        end
        surface.SetDrawColor(225, 219, 203, 235)
        surface.SetMaterial(mat)
        surface.DrawTexturedRect(8 * scale + (cell - iw) * 0.5, (h - ih) * 0.5, iw, ih)

        local name = entry.def.name
        if entry.quantity > 1 then name = name .. "  x" .. entry.quantity end
        draw.SimpleText(name, Omerta.HUD.Font("label"),
            8 * scale + cell + 10 * scale, h * 0.5,
            COLOURS.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        draw.SimpleText(Omerta.Inventory.FormatBulk(
                Omerta.Inventory.StackBulk(entry.def, entry.quantity)),
            Omerta.HUD.Font("small"), w - 10 * scale, h * 0.5,
            COLOURS.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

        -- The one visible difference between a coat in a bag and a coat on
        -- your back.
        if entry.slot then
            draw.SimpleText("equipped — " .. entry.slot.label,
                Omerta.HUD.Font("small"), w - 52 * scale, h * 0.5,
                COLOURS.accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    row.OnMousePressed = function(_, code)
        if code == MOUSE_RIGHT then openRowMenu(entry, mine) end
    end
    return row
end

local function styleScrollbar(scroll, scale)
    local bar = scroll:GetVBar()
    bar:SetWide(6 * scale)
    bar:SetHideButtons(true)
    bar.Paint = function(_, w, h)
        surface.SetDrawColor(28, 26, 24, 160)
        surface.DrawRect(0, 0, w, h)
    end
    bar.btnGrip.Paint = function(_, w, h)
        surface.SetDrawColor(COLOURS.line.r, COLOURS.line.g, COLOURS.line.b, 220)
        surface.DrawRect(0, 0, w, h)
    end
end

-- One framed window: title strip, optional right-hand line in the strip,
-- optional footer, scrolling list. Two of these side by side is looting.
local function buildWindow(parent, title, rightLine, withFooter)
    local scale = Omerta.HUD.Scale()
    local titleH = 34 * scale

    local win = vgui.Create("DPanel", parent)
    win.Paint = function(_, w, h)
        surface.SetDrawColor(COLOURS.panel.r, COLOURS.panel.g, COLOURS.panel.b, COLOURS.panel.a)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(COLOURS.strip.r, COLOURS.strip.g, COLOURS.strip.b, 255)
        surface.DrawRect(0, 0, w, titleH)
        surface.SetDrawColor(COLOURS.line.r, COLOURS.line.g, COLOURS.line.b, 255)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        surface.DrawRect(0, titleH - 1, w, 1)

        draw.SimpleText(title, Omerta.HUD.Font("body"), 12 * scale, titleH * 0.5,
            COLOURS.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if rightLine then
            local text, colour = rightLine()
            if text then
                draw.SimpleText(text, Omerta.HUD.Font("label"),
                    w - 12 * scale, titleH * 0.5,
                    colour or COLOURS.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
    end

    if withFooter then
        local footer = vgui.Create("DPanel", win)
        footer:Dock(BOTTOM)
        footer:SetTall(44 * scale)
        footer:DockMargin(10 * scale, 0, 10 * scale, 8 * scale)
        footer.Paint = function(_, w, h)
            local used = Omerta.Inventory.FormatBulk(state.bulkUsed)
            local limit = Omerta.Inventory.FormatBulk(state.bulkLimit)
            draw.SimpleText(string.format("Carrying %s of %s", used, limit),
                Omerta.HUD.Font("small"), 0, h - 28 * scale, COLOURS.muted,
                TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            -- The cash line is a courtesy total of the coins and notes listed
            -- above; the money itself is the stacks, not this number.
            local cash = 0
            for _, entry in ipairs(state.mine) do
                local denom = Omerta.Money.DenominationOfItem(entry.def.id)
                if denom then cash = cash + denom.cents * entry.quantity end
            end
            draw.SimpleText(Omerta.Money.Format(cash), Omerta.HUD.Font("small"),
                w, h - 28 * scale, COLOURS.paper, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)

            -- A bar that shortens as well as reddens, so it does not depend on
            -- colour alone (Tech §8 accessibility).
            local ratio = state.bulkLimit > 0
                and math.min(1, state.bulkUsed / state.bulkLimit) or 0
            surface.SetDrawColor(40, 38, 35, 255)
            surface.DrawRect(0, h - 4, w, 3)
            local fill = ratio > 0.9 and COLOURS.warning or COLOURS.line
            surface.SetDrawColor(fill.r, fill.g, fill.b, 255)
            surface.DrawRect(0, h - 4, w * ratio, 3)
        end
    end

    local scroll = vgui.Create("DScrollPanel", win)
    scroll:Dock(FILL)
    scroll:DockMargin(8 * scale, titleH + 8 * scale, 8 * scale, 8 * scale)
    styleScrollbar(scroll, scale)
    win.Scroll = scroll

    return win, titleH
end

local function fillWindow(win, entries, mine)
    for _, entry in ipairs(entries) do
        buildRow(win.Scroll, entry, mine)
    end
    if #entries == 0 then
        local empty = vgui.Create("DPanel", win.Scroll)
        empty:SetTall(64 * Omerta.HUD.Scale())
        empty:Dock(TOP)
        empty.Paint = function(_, w, h)
            draw.SimpleText("Empty", Omerta.HUD.Font("label"), w * 0.5, h * 0.5,
                COLOURS.faint, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
end

local function hungerLine()
    local state_ = Omerta.Hunger.State(hunger)
    local colour = state_ == Omerta.Hunger.STATE.STARVING and COLOURS.warning or COLOURS.muted
    return Omerta.Hunger.Describe(hunger), colour
end

local function closeButton(win, titleH)
    local scale = Omerta.HUD.Scale()
    local btn = vgui.Create("DButton", win)
    btn:SetText("")
    btn:SetSize(titleH, titleH)
    btn.PerformLayout = function(self)
        self:SetPos(self:GetParent():GetWide() - self:GetWide(), 0)
    end
    btn.Paint = function(self, w, h)
        draw.SimpleText("X", Omerta.HUD.Font("label"), w * 0.5, h * 0.5,
            self:IsHovered() and COLOURS.paper or COLOURS.muted,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btn.DoClick = function()
        if IsValid(frame) then frame:Close() end
    end
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

function Omerta.Inventory.Show()
    if IsValid(frame) then frame:Remove() end

    local scale = Omerta.HUD.Scale()
    local winW = math.min(ScrW() * 0.42, 470 * scale)
    local height = math.min(ScrH() * 0.78, 560 * scale)
    local gap = 10 * scale

    frame = vgui.Create("DFrame")
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    frame:MakePopup()
    -- The windows are the chrome; the frame is an invisible holder.
    frame.Paint = nil

    -- The same key closes it from in here: a focused panel eats binds, so the
    -- key is read directly. KEY_C is the engine's default for +menu_context,
    -- which is what opens this window.
    frame.OnKeyCodePressed = function(self, key)
        if key == KEY_C then self:Close() end
    end

    function frame:Rebuild()
        for _, child in ipairs(self:GetChildren()) do
            if child.OmertaWindow then child:Remove() end
        end

        local looting = state.container and state.container > 0
        local wantW = looting and (winW * 2 + gap) or winW
        if math.abs(self:GetWide() - wantW) > 1 or self:GetTall() ~= height then
            self:SetSize(wantW, height)
            self:Center()
        end

        local mine = buildWindow(self, "Pockets", hungerLine, true)
        mine.OmertaWindow = true
        mine:SetPos(0, 0)
        mine:SetSize(winW, height)
        fillWindow(mine, state.mine, true)

        -- The X lives on the rightmost window's title strip, wherever the
        -- right edge currently is.
        if looting then
            local title = state.label ~= "" and state.label or "Container"
            local theirs, titleH = buildWindow(self, title, nil, false)
            theirs.OmertaWindow = true
            theirs:SetPos(winW + gap, 0)
            theirs:SetSize(winW, height)
            fillWindow(theirs, state.theirs, false)
            closeButton(theirs, titleH)
        else
            closeButton(mine, 34 * scale)
        end
    end

    frame:Rebuild()

    frame.OnRemove = function()
        frame = nil
        state.container = 0
    end
end

--------------------------------------------------------------------------------
-- Opening it
--------------------------------------------------------------------------------

concommand.Add("omerta_inventory", function() Omerta.Inventory.Toggle() end)

-- C opens the pockets, and it TOGGLES — one press to open, one to close.
--
-- This used to hang off the +menu_context bind, which was wrong in a way that
-- only shows up in the hand: PlayerBindPress fires repeatedly while a bind is
-- HELD, so the window toggled every frame and stayed open only while the key
-- was down, like a sandbox context menu. A physical key-down event fires
-- exactly once per press, which is what a toggle needs.
--
-- The bind is still swallowed below so the engine does nothing of its own
-- with C.
hook.Add("PlayerButtonDown", "omerta.inventory.key", function(ply, button)
    if ply ~= LocalPlayer() then return end
    if button ~= KEY_C then return end
    -- Not while typing, in the menu, or in the console: a key that opens a
    -- window mid-sentence is worse than no key at all.
    if ply:IsTyping() or gui.IsGameUIVisible() or gui.IsConsoleVisible() then return end
    Omerta.Inventory.Toggle()
end)

hook.Add("PlayerBindPress", "omerta.inventory.suppress_context", function(_, bind)
    if bind == "+menu_context" then return true end
end)

-- D-017's dot now lights up for things worth walking over to.
Omerta.HUD.RegisterInteractableClass("omerta_item")
Omerta.HUD.RegisterInteractableClass("omerta_container")

--------------------------------------------------------------------------------
-- Hunger
--------------------------------------------------------------------------------

hook.Add("Omerta.HungerUpdated", "omerta.inventory.hunger", function(value)
    hunger = value
end)

-- §4c, D-019: silent while merely hungry. It appears only once starvation is
-- actually costing the player something, because being degraded by an
-- invisible number is not consequence — it is a bug wearing a costume.
Omerta.HUD.Register("hunger", {
    order = 15,
    fade = 0.6,
    visible = function()
        return Omerta.Hunger.State(hunger) == Omerta.Hunger.STATE.STARVING
    end,
    draw = function(alpha)
        Omerta.HUD.Text("Starving", "body",
            ScrW() * 0.5, ScrH() * 0.75,
            Color(178, 96, 84, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end,
})
