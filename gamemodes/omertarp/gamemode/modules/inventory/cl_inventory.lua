-- The inventory window, and the one thing hunger is ever allowed to say
-- unprompted.
--
-- This is a VGUI frame rather than a HUD element, for the same reason the
-- character-creation window is: it takes input, and the empty-screen rule is
-- about what is on screen when you have not asked for anything. Nothing here
-- draws unless the player opened it.
--
-- Hunger is read HERE and nowhere else (D-016) — deliberately, like money in a
-- wallet. The single exception is the starvation warning below (D-019).

local Internal = Omerta.Inventory.Internal

local state = {
    container = 0,
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
        Internal.Rebuild()
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
-- The window
--------------------------------------------------------------------------------

local COLOURS = {
    paper   = Color(232, 226, 210),
    ink     = Color(28, 26, 24),
    muted   = Color(96, 90, 82),
    panel   = Color(20, 19, 18, 242),
    line    = Color(70, 64, 56),
    warning = Color(178, 96, 84),
}

local function describe(entry)
    local bulk = Omerta.Inventory.FormatBulk(
        Omerta.Inventory.StackBulk(entry.def, entry.quantity))
    local name = entry.def.name
    if entry.quantity > 1 then name = name .. " x" .. entry.quantity end
    if entry.slot then name = name .. "  (" .. entry.slot.label .. ")" end
    return name, bulk
end

local function buildList(parent, entries, onSelect)
    local list = vgui.Create("DListView", parent)
    list:SetMultiSelect(false)
    list:AddColumn("Item")
    list:AddColumn("Bulk"):SetFixedWidth(56 * Omerta.HUD.Scale())
    list:SetHeaderHeight(22 * Omerta.HUD.Scale())
    list:SetDataHeight(22 * Omerta.HUD.Scale())

    for _, entry in ipairs(entries) do
        local name, bulk = describe(entry)
        local line = list:AddLine(name, bulk)
        line.OmertaEntry = entry
    end

    list.OnRowSelected = function(_, _, line) onSelect(line.OmertaEntry) end
    return list
end

function Internal.Rebuild()
    if not IsValid(frame) then return end
    frame:Rebuild()
end

function Omerta.Inventory.Show()
    if IsValid(frame) then frame:Remove() end

    local scale = Omerta.HUD.Scale()
    local width = math.min(ScrW() * 0.7, 720 * scale)
    local height = math.min(ScrH() * 0.75, 520 * scale)

    frame = vgui.Create("DFrame")
    frame:SetSize(width, height)
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(true)
    frame:MakePopup()

    -- While the window has keyboard focus the game's button hooks may not see
    -- the key, so the same key closes it from in here.
    frame.OnKeyCodePressed = function(self, key)
        if key == GetConVar("omerta_inventory_key"):GetInt() then self:Close() end
    end

    frame.Paint = function(_, w, h)
        draw.RoundedBox(4, 0, 0, w, h, COLOURS.panel)
        surface.SetDrawColor(COLOURS.line)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local selected = nil
    local body, actions, footer

    local function refreshActions()
        if not IsValid(actions) then return end
        actions:Clear()
        if not selected then return end

        local function button(label, fn)
            local btn = vgui.Create("DButton", actions)
            btn:SetText(label)
            btn:SetFont(Omerta.HUD.Font("label"))
            btn:SetTextColor(COLOURS.paper)
            btn:Dock(LEFT)
            btn:DockMargin(0, 0, 6 * scale, 0)
            btn:SetWide(96 * scale)
            btn.Paint = function(self, w, h)
                surface.SetDrawColor(self:IsHovered() and COLOURS.line or Color(38, 35, 32))
                surface.DrawRect(0, 0, w, h)
                surface.SetDrawColor(COLOURS.line)
                surface.DrawOutlinedRect(0, 0, w, h, 1)
            end
            btn.DoClick = fn
        end

        local A = Omerta.Inventory.ACTION
        if selected.mine then
            if selected.entry.def.feeds or selected.entry.def.onUse then
                button("Use", function() act(A.USE, selected.entry) end)
            end
            if selected.entry.def.slot then
                if selected.entry.slot then
                    button("Take Off", function() act(A.UNEQUIP, selected.entry) end)
                else
                    button("Equip", function() act(A.EQUIP, selected.entry) end)
                end
            end
            button("Drop", function() act(A.DROP, selected.entry) end)
            if state.container and state.container > 0 then
                button("Store", function() act(A.STORE, selected.entry) end)
            end
        else
            button("Take", function() act(A.TAKE, selected.entry) end)
        end
    end

    function frame:Rebuild()
        if IsValid(body) then body:Remove() end
        selected = nil

        body = vgui.Create("DPanel", frame)
        body:Dock(FILL)
        body:DockMargin(12 * scale, 8 * scale, 12 * scale, 4 * scale)
        body.Paint = nil

        -- The container is docked first: a FILL panel has to be the last one
        -- added or it claims the space its neighbour wanted.
        if state.container and state.container > 0 then
            local theirs = buildList(body, state.theirs, function(entry)
                selected = { entry = entry, mine = false }
                refreshActions()
            end)
            theirs:Dock(RIGHT)
            theirs:SetWide(frame:GetWide() * 0.42)
            theirs:DockMargin(8 * scale, 0, 0, 0)
        end

        local mine = buildList(body, state.mine, function(entry)
            selected = { entry = entry, mine = true }
            refreshActions()
        end)
        mine:Dock(FILL)

        if IsValid(footer) then footer:InvalidateLayout() end
        refreshActions()
    end

    -- Header: what you are carrying, what it costs you, and how hungry you are.
    local header = vgui.Create("DPanel", frame)
    header:Dock(TOP)
    header:SetTall(34 * scale)
    header:DockMargin(12 * scale, 4 * scale, 12 * scale, 0)
    header.Paint = function(_, w, h)
        draw.SimpleText("Pockets", Omerta.HUD.Font("body"), 0, h * 0.5 - 8 * scale,
            COLOURS.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        local state_ = Omerta.Hunger.State(hunger)
        local colour = state_ == Omerta.Hunger.STATE.STARVING and COLOURS.warning or COLOURS.muted
        draw.SimpleText(Omerta.Hunger.Describe(hunger), Omerta.HUD.Font("label"),
            w, h * 0.5 - 7 * scale, colour, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        surface.SetDrawColor(COLOURS.line)
        surface.DrawRect(0, h - 1, w, 1)
    end

    footer = vgui.Create("DPanel", frame)
    footer:Dock(BOTTOM)
    footer:SetTall(58 * scale)
    footer:DockMargin(12 * scale, 0, 12 * scale, 8 * scale)
    footer.Paint = function(_, w, h)
        local used = Omerta.Inventory.FormatBulk(state.bulkUsed)
        local limit = Omerta.Inventory.FormatBulk(state.bulkLimit)
        draw.SimpleText(string.format("Carrying %s of %s", used, limit),
            Omerta.HUD.Font("small"), 0, h - 18 * scale, COLOURS.muted,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        -- The cash line is a courtesy total of the coins and notes listed
        -- above; the money itself is the stacks, not this number.
        local cash = 0
        for _, entry in ipairs(state.mine) do
            local denom = Omerta.Money.DenominationOfItem(entry.def.id)
            if denom then cash = cash + denom.cents * entry.quantity end
        end
        draw.SimpleText(Omerta.Money.Format(cash), Omerta.HUD.Font("small"),
            w, h - 18 * scale, COLOURS.paper, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)

        -- A bar that shortens as well as reddens, so it does not depend on
        -- colour alone (Tech §8 accessibility).
        local ratio = state.bulkLimit > 0
            and math.min(1, state.bulkUsed / state.bulkLimit) or 0
        surface.SetDrawColor(40, 38, 35)
        surface.DrawRect(0, h - 4, w, 3)
        surface.SetDrawColor(ratio > 0.9 and COLOURS.warning or COLOURS.line)
        surface.DrawRect(0, h - 4, w * ratio, 3)
    end

    actions = vgui.Create("DPanel", footer)
    actions:Dock(TOP)
    actions:SetTall(28 * scale)
    actions.Paint = nil

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

-- The key is read directly rather than through GM:ShowSpare1, which only fires
-- if the player happens to have F3 bound to gm_showspare1 — on a fresh install
-- they frequently do not, and the inventory silently does nothing.
CreateClientConVar("omerta_inventory_key", tostring(KEY_F3), true, false)

hook.Add("PlayerButtonDown", "omerta.inventory.key", function(ply, button)
    if ply ~= LocalPlayer() then return end
    if button ~= GetConVar("omerta_inventory_key"):GetInt() then return end
    -- Not while they are typing, in the menu, or in the console: a key that
    -- opens a window mid-sentence is worse than no key at all.
    if ply:IsTyping() or gui.IsGameUIVisible() or gui.IsConsoleVisible() then return end
    Omerta.Inventory.Toggle()
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
        draw.SimpleText("Starving", Omerta.HUD.Font("body"),
            ScrW() * 0.5, ScrH() * 0.75,
            Color(178, 96, 84, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end,
})
