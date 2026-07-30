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
    -- The one visible difference between a coat in a bag and a coat on your
    -- back. Spelled out, because a player who cannot tell lost a fight over it.
    if entry.slot then name = name .. "  — equipped (" .. entry.slot.label .. ")" end
    return name, bulk
end

-- Everything you can do to an item hangs off the right mouse button. The row
-- of buttons this replaces needed a selection, went stale when the list
-- rebuilt underneath it, and grew a button per verb; a context menu asks the
-- entry itself what applies, every time it opens.
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

local function buildList(parent, entries, mine)
    local scale = Omerta.HUD.Scale()
    local list = vgui.Create("DListView", parent)
    list:SetMultiSelect(false)
    local itemColumn = list:AddColumn("Item")
    local bulkColumn = list:AddColumn("Bulk")
    bulkColumn:SetFixedWidth(60 * scale)
    list:SetHeaderHeight(24 * scale)
    list:SetDataHeight(26 * scale)
    -- The engine's default list font is tiny; these follow the HUD's.
    itemColumn.Header:SetFont(Omerta.HUD.Font("small"))
    bulkColumn.Header:SetFont(Omerta.HUD.Font("small"))

    for _, entry in ipairs(entries) do
        local name, bulk = describe(entry)
        local line = list:AddLine(name, bulk)
        line.OmertaEntry = entry
        for _, column in ipairs(line.Columns or {}) do
            column:SetFont(Omerta.HUD.Font("label"))
        end
    end

    list.OnRowRightClicked = function(_, _, line)
        openRowMenu(line.OmertaEntry, mine)
    end
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

    local body, footer

    function frame:Rebuild()
        if IsValid(body) then body:Remove() end

        body = vgui.Create("DPanel", frame)
        body:Dock(FILL)
        body:DockMargin(12 * scale, 8 * scale, 12 * scale, 4 * scale)
        body.Paint = nil

        -- The container is docked first: a FILL panel has to be the last one
        -- added or it claims the space its neighbour wanted.
        if state.container and state.container > 0 then
            local theirs = buildList(body, state.theirs, false)
            theirs:Dock(RIGHT)
            theirs:SetWide(frame:GetWide() * 0.42)
            theirs:DockMargin(8 * scale, 0, 0, 0)
        end

        local mine = buildList(body, state.mine, true)
        mine:Dock(FILL)

        if IsValid(footer) then footer:InvalidateLayout() end
    end

    -- Header: what you are carrying, what it costs you, and how hungry you are.
    local header = vgui.Create("DPanel", frame)
    header:Dock(TOP)
    header:SetTall(34 * scale)
    header:DockMargin(12 * scale, 4 * scale, 12 * scale, 0)
    header.Paint = function(_, w, h)
        draw.SimpleText("Pockets", Omerta.HUD.Font("body"), 0, h * 0.5,
            COLOURS.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local state_ = Omerta.Hunger.State(hunger)
        local colour = state_ == Omerta.Hunger.STATE.STARVING and COLOURS.warning or COLOURS.muted
        draw.SimpleText(Omerta.Hunger.Describe(hunger), Omerta.HUD.Font("label"),
            w, h * 0.5, colour, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
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
        surface.SetDrawColor(40, 38, 35)
        surface.DrawRect(0, h - 4, w, 3)
        surface.SetDrawColor(ratio > 0.9 and COLOURS.warning or COLOURS.line)
        surface.DrawRect(0, h - 4, w * ratio, 3)
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

-- The key is read directly rather than through a GM:Show* hook, which only
-- fires if the player happens to have the matching bind — on a fresh install
-- they frequently do not, and the inventory silently does nothing.
--
-- Q by default. The convar is ARCHIVED, so a client that ran the old F3
-- default keeps their saved value until they set it themselves:
-- omerta_inventory_key 27 (Q) in the console, or any KEY_ number they like.
CreateClientConVar("omerta_inventory_key", tostring(KEY_Q), true, false)

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
