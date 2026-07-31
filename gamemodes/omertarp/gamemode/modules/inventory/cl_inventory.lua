-- The inventory window, and the one thing hunger is ever allowed to say
-- unprompted.
--
-- Styled to the guide's §09/§10: A LEDGER, NOT A GRID OF BOXES — rows are how
-- a 1930s person would actually account for what they carry. One ink plate at
-- 94%, hairline rules, mono column captions; the item in your hands is the
-- brass-inverted row and worn things carry a brass WORN in the state column —
-- the same two selection languages as the HUD, nothing new to learn. Looting
-- is the same plate with two identical columns and one vertical rule between
-- them, because symmetry already says "these two are the same kind of thing".
--
-- Held open by C (see the bottom of the file), which is why there is no close
-- button anywhere: chrome for closing would promise a different interaction
-- model than the one the game has.
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
-- Icons
--------------------------------------------------------------------------------
-- The category icons (player-provided line art, white on transparency, so
-- they tint cleanly — the guide's tint is bone at rest, brass when selected).
-- An item may name its own with `icon = "icon_x"`; otherwise the category
-- decides, and anything unmapped reads as junk — which, in this city, is the
-- honest default.

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
-- What a row says about an item
--------------------------------------------------------------------------------

-- Is this entry the thing actually in the player's hands right now?
local function isInHands(entry)
    if not entry.slot then return false end
    local ply = LocalPlayer()
    local wep = IsValid(ply) and ply:GetActiveWeapon() or nil
    if not (IsValid(wep) and wep.OmertaId) then return false end
    return entry.def.weapon == wep.OmertaId
end

-- The STATE column, mono voice: what the row is doing for you right now.
-- Returns text, colourToken.
local function stateOf(entry)
    if isInHands(entry) then return "IN HANDS", "ink" end
    if entry.slot then
        local slot = entry.slot.id
        if slot == "outerwear" or slot == "headwear" then return "WORN", "brass" end
        return "CARRIED", "brass"
    end
    return "—", "dim"
end

--------------------------------------------------------------------------------
-- What you can do with a thing
--------------------------------------------------------------------------------
-- Everything hangs off the right mouse button, in the guide's item menu: mono
-- header naming the item, verbs below, the irreversible alone at the bottom
-- under a rule.

local function openRowMenu(entry, mine)
    if not entry then return end
    local A = Omerta.Inventory.ACTION
    local m = Omerta.HUD.Menu()
    Omerta.HUD.MenuHeader(m, entry.def.name)

    if not mine then
        Omerta.HUD.MenuOption(m, "Take", function() act(A.TAKE, entry) end)
        m:Open()
        return
    end

    if entry.def.slot then
        if entry.slot then
            Omerta.HUD.MenuOption(m, "Unequip", function() act(A.UNEQUIP, entry) end)
        else
            Omerta.HUD.MenuOption(m, "Equip", function() act(A.EQUIP, entry) end)
        end
    end
    if entry.def.feeds or entry.def.onUse then
        Omerta.HUD.MenuOption(m, "Use", function() act(A.USE, entry) end)
    end
    if entry.def.stackable and entry.quantity > 1 then
        Omerta.HUD.MenuOption(m, "Split…", function()
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
        Omerta.HUD.MenuOption(m, "Store", function() act(A.STORE, entry) end)
    end

    -- Dropping is how things leave the world's accounting: the guide's
    -- irreversible position — alone, last, under a rule, in the red.
    Omerta.HUD.MenuDivider(m)
    Omerta.HUD.MenuOption(m, "Drop", function() act(A.DROP, entry) end,
        { danger = true })

    m:Open()
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------
-- The ledger grid: icon 40 · item 1fr · qty 56 · bulk 72 · state 96 (scaled).
-- The row whose item is in your hands is the brass inversion.

local function buildRow(parent, entry, mine, wide)
    local scale = Omerta.HUD.Scale()
    local row = vgui.Create("DPanel", parent)
    row:SetTall(38 * scale)
    row:Dock(TOP)
    row:SetCursor("hand")

    row.Paint = function(self, w, h)
        local held = mine and isInHands(entry)
        local hovered = self:IsHovered()

        if held then
            surface.SetDrawColor(Omerta.HUD.Colour("brass"))
            surface.DrawRect(0, 0, w, h)
        elseif hovered then
            -- The guide's hover: a brass wash, and a 1px brass edge on the
            -- side the item would travel toward.
            surface.SetDrawColor(Omerta.HUD.Colour("brass",
                Omerta.HUD.Theme.ALPHA.wash * 255))
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(Omerta.HUD.Colour("brass"))
            if state.container and state.container > 0 then
                if mine then surface.DrawRect(w - 1, 0, 1, h)
                else surface.DrawRect(0, 0, 1, h) end
            end
        end

        local pad = 24 * scale
        local textColour = held and Omerta.HUD.Colour("ink") or Omerta.HUD.Colour("text")
        local faintColour = held and Omerta.HUD.Colour("ink", 175)
            or Omerta.HUD.Colour("secondary")

        -- Icon, tinted to the row's own language.
        local mat = iconFor(entry.def)
        local cell = 22 * scale
        local iw, ih = cell, cell
        local mw, mh = mat:Width(), mat:Height()
        if mw > 0 and mh > 0 then
            local fit = math.min(cell / mw, cell / mh)
            iw, ih = mw * fit, mh * fit
        end
        surface.SetDrawColor(held and Omerta.HUD.Colour("ink")
            or Omerta.HUD.Colour("text", 220))
        surface.SetMaterial(mat)
        surface.DrawTexturedRect(pad + (cell - iw) * 0.5, (h - ih) * 0.5, iw, ih)

        local x = pad + 40 * scale
        draw.SimpleText(entry.def.name, Omerta.HUD.Font("label"), x, h * 0.5,
            textColour, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        if wide then
            -- QTY · BULK · STATE, right-aligned columns.
            local stateText, stateToken = stateOf(entry)
            draw.SimpleText(stateText, Omerta.HUD.Font("mono"),
                w - pad, h * 0.5,
                held and Omerta.HUD.Colour("ink") or Omerta.HUD.Colour(stateToken),
                TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            draw.SimpleText(Omerta.Inventory.FormatBulk(
                    Omerta.Inventory.StackBulk(entry.def, entry.quantity)),
                Omerta.HUD.Font("label"), w - pad - 96 * scale, h * 0.5,
                faintColour, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            draw.SimpleText(entry.quantity, Omerta.HUD.Font("label"),
                w - pad - 168 * scale, h * 0.5,
                textColour, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        else
            -- The loot column keeps one right-hand value: state, or quantity.
            local stateText, stateToken = stateOf(entry)
            if stateText ~= "—" then
                draw.SimpleText(stateText, Omerta.HUD.Font("mono"), w - pad, h * 0.5,
                    held and Omerta.HUD.Colour("ink") or Omerta.HUD.Colour(stateToken),
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            else
                draw.SimpleText(entry.quantity, Omerta.HUD.Font("label"),
                    w - pad, h * 0.5, faintColour,
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
    end

    row.OnMousePressed = function(_, code)
        if code == MOUSE_RIGHT then openRowMenu(entry, mine) end
    end
    return row
end

local function styleScrollbar(scroll, scale)
    local bar = scroll:GetVBar()
    bar:SetWide(4 * scale)
    bar:SetHideButtons(true)
    bar.Paint = function(_, w, h)
        surface.SetDrawColor(Omerta.HUD.Colour("ruleFaint"))
        surface.DrawRect(0, 0, w, h)
    end
    bar.btnGrip.Paint = function(_, w, h)
        surface.SetDrawColor(Omerta.HUD.Colour("rule"))
        surface.DrawRect(0, 0, w, h)
    end
end

--------------------------------------------------------------------------------
-- Columns
--------------------------------------------------------------------------------

-- A titled column: Oswald caps title, mono note on the right, a rule under,
-- then the scrolling rows. Two of these side by side is looting.
local function buildColumn(parent, title, note, entries, mine, wide)
    local scale = Omerta.HUD.Scale()
    local column = vgui.Create("DPanel", parent)
    column.Paint = function(_, w, h)
        draw.SimpleText(string.upper(title), Omerta.HUD.Font("heading"),
            24 * scale, 34 * scale, Omerta.HUD.Colour("text"),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        if note then
            draw.SimpleText(note, Omerta.HUD.Font("mono"),
                w - 24 * scale, 32 * scale, Omerta.HUD.Colour("dim"),
                TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
        end
        surface.SetDrawColor(Omerta.HUD.Colour("rule"))
        surface.DrawRect(0, 44 * scale, w, 1)

        if wide then
            -- The ledger's column captions, once, in the system voice.
            local y = 62 * scale
            local pad = 24 * scale
            draw.SimpleText("ITEM", Omerta.HUD.Font("mono"), pad + 40 * scale, y,
                Omerta.HUD.Colour("dim"), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
            draw.SimpleText("QTY", Omerta.HUD.Font("mono"), w - pad - 168 * scale, y,
                Omerta.HUD.Colour("dim"), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
            draw.SimpleText("BULK", Omerta.HUD.Font("mono"), w - pad - 96 * scale, y,
                Omerta.HUD.Colour("dim"), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
            draw.SimpleText("STATE", Omerta.HUD.Font("mono"), w - pad, y,
                Omerta.HUD.Colour("dim"), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
            surface.SetDrawColor(Omerta.HUD.Colour("ruleFaint"))
            surface.DrawRect(0, 66 * scale, w, 1)
        end
    end

    local scroll = vgui.Create("DScrollPanel", column)
    scroll:Dock(FILL)
    scroll:DockMargin(0, (wide and 70 or 52) * scale, 0, 8 * scale)
    styleScrollbar(scroll, scale)

    for _, entry in ipairs(entries) do
        buildRow(scroll, entry, mine, wide)
    end
    if #entries == 0 then
        local empty = vgui.Create("DPanel", scroll)
        empty:SetTall(64 * scale)
        empty:Dock(TOP)
        empty.Paint = function(_, w, h)
            draw.SimpleText("EMPTY", Omerta.HUD.Font("mono"), w * 0.5, h * 0.5,
                Omerta.HUD.Colour("dim"), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    return column
end

-- The pockets footer: the bulk tick meter (the constraint gets the meter),
-- cash, and hunger as a WORD — the character feels it, they don't measure it.
local function buildFooter(parent)
    local scale = Omerta.HUD.Scale()
    local footer = vgui.Create("DPanel", parent)
    footer:Dock(BOTTOM)
    footer:SetTall(64 * scale)
    footer.Paint = function(_, w, h)
        local pad = 24 * scale
        surface.SetDrawColor(Omerta.HUD.Colour("rule"))
        surface.DrawRect(0, 0, w, 1)

        local usedUnits = math.floor(state.bulkUsed / Omerta.Inventory.BULK_SCALE + 0.5)
        local limitUnits = math.max(1,
            math.floor(state.bulkLimit / Omerta.Inventory.BULK_SCALE + 0.5))
        draw.SimpleText(string.format("POCKETS — %d OF %d", usedUnits, limitUnits),
            Omerta.HUD.Font("mono"), pad, 14 * scale,
            Omerta.HUD.Colour("dim"), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        -- The tick meter. Spent ticks stay lit; room is the dim remainder.
        local ticks = math.min(limitUnits, 24)
        local filled = math.floor(math.min(1, usedUnits / limitUnits) * ticks + 0.5)
        local tx = pad
        for i = 1, ticks do
            surface.SetDrawColor(Omerta.HUD.Colour("text",
                i <= filled and 235 or 235 * 0.18))
            surface.DrawRect(tx, h - 20 * scale, 12 * scale, 4 * scale)
            tx = tx + 14 * scale
        end

        -- The cash line is a courtesy total of the coins and notes listed
        -- above; the money itself is the stacks, not this number.
        local cash = 0
        for _, entry in ipairs(state.mine) do
            local denom = Omerta.Money.DenominationOfItem(entry.def.id)
            if denom then cash = cash + denom.cents * entry.quantity end
        end
        draw.SimpleText("ON HAND", Omerta.HUD.Font("mono"), w - pad - 130 * scale,
            12 * scale, Omerta.HUD.Colour("dim"), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        draw.SimpleText(Omerta.Money.Format(cash), Omerta.HUD.Font("subject"),
            w - pad - 130 * scale, h - 12 * scale,
            Omerta.HUD.Colour("text"), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)

        local hungerWord = Omerta.Hunger.Describe(hunger)
        local starving = Omerta.Hunger.State(hunger) == Omerta.Hunger.STATE.STARVING
        draw.SimpleText("APPETITE", Omerta.HUD.Font("mono"), w - pad, 12 * scale,
            Omerta.HUD.Colour("dim"), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        draw.SimpleText(hungerWord, Omerta.HUD.Font("subject"), w - pad, h - 12 * scale,
            Omerta.HUD.Colour(starving and "danger" or "brass"),
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    end
    return footer
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

function Omerta.Inventory.Show()
    if IsValid(frame) then frame:Remove() end

    local scale = Omerta.HUD.Scale()

    frame = vgui.Create("DFrame")
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    frame:MakePopup()
    -- Mouse only. The keyboard stays with the game, which is what lets the
    -- hold-to-view key work at all — and lets you keep walking while you
    -- rummage, which feels right for pockets.
    frame:SetKeyboardInputEnabled(false)

    -- ONE plate, per the guide — never two floating windows.
    frame.Paint = function(_, w, h)
        surface.SetDrawColor(Omerta.HUD.Colour("plate",
            Omerta.HUD.Theme.ALPHA.focus * 255))
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(Omerta.HUD.Colour("rule"))
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    function frame:Rebuild()
        for _, child in ipairs(self:GetChildren()) do
            if child.OmertaOwned then child:Remove() end
        end

        local looting = state.container and state.container > 0
        local width = (looting and 960 or 720) * scale
        local height = 560 * scale
        self:SetSize(width, height)
        self:Center()

        if looting then
            -- Two identical columns, one vertical rule between them.
            local divider = vgui.Create("DPanel", self)
            divider.OmertaOwned = true
            divider:SetSize(1, height)
            divider:SetPos(width * 0.5, 0)
            divider.Paint = function(_, w, h)
                surface.SetDrawColor(Omerta.HUD.Colour("rule"))
                surface.DrawRect(0, 0, w, h)
            end

            local usedUnits = math.floor(state.bulkUsed / Omerta.Inventory.BULK_SCALE + 0.5)
            local limitUnits = math.max(1,
                math.floor(state.bulkLimit / Omerta.Inventory.BULK_SCALE + 0.5))
            local mine = buildColumn(self, "Pockets",
                string.format("%d / %d", usedUnits, limitUnits),
                state.mine, true, false)
            mine.OmertaOwned = true
            mine:SetPos(0, 0)
            mine:SetSize(width * 0.5, height)

            local title = state.label ~= "" and state.label or "Container"
            local theirs = buildColumn(self, title, "C TO CLOSE",
                state.theirs, false, false)
            theirs.OmertaOwned = true
            theirs:SetPos(width * 0.5 + 1, 0)
            theirs:SetSize(width * 0.5 - 1, height)
        else
            local column = buildColumn(self, "Pockets", "HOLD C",
                state.mine, true, true)
            column.OmertaOwned = true
            column:SetPos(0, 0)
            column:SetSize(width, height)
            local footer = buildFooter(column)
            footer.OmertaOwned = true
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
-- Pockets are HELD OPEN, not toggled: the window is up exactly while C is
-- down, and gone the instant it is not — checking your pockets is a glance,
-- not a mode you enter and later remember to leave.
--
-- Implemented by POLLING the physical key, not by events. Every event-based
-- version of this was finicky in a different way: binds re-fire while held,
-- button-up is swallowed once a panel takes focus, and clicking a row made
-- the release vanish so the window stuck. input.IsKeyDown reads the actual
-- keyboard state every frame regardless of what has focus — the one source
-- that cannot miss the release.
--
-- LOOT is the exception. A container or body opens from a search (no key
-- held), stays up while you move things, and a press of C dismisses it.
--
-- `pinned` is the console command's escape hatch: omerta_inventory holds the
-- window open with no key for staff and debugging, and toggles back off.
local pinned = false
local wasDown = false

concommand.Add("omerta_inventory", function()
    if IsValid(frame) and pinned then
        pinned = false
        frame:Close()
        return
    end
    pinned = true
    Omerta.Inventory.Show()
    Omerta.Inventory.Request(0)
end)

hook.Add("Think", "omerta.inventory.hold", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    -- Not while typing, in the menu, or in the console: a key that opens a
    -- window mid-sentence is worse than no key at all.
    local down = input.IsKeyDown(KEY_C)
        and not (ply.IsTyping and ply:IsTyping())
        and not gui.IsGameUIVisible() and not gui.IsConsoleVisible()
    local pressed = down and not wasDown
    wasDown = down

    if pinned then
        if not IsValid(frame) then pinned = false end
        return
    end

    local open = IsValid(frame)
    local looting = open and state.container and state.container > 0

    if looting then
        -- A press dismisses the loot plate; holding is not required while
        -- both hands are in somebody's coat.
        if pressed then frame:Close() end
        return
    end

    if down and not open then
        -- Shown immediately from the cached state so the window is ON the
        -- key, then refreshed; the stream rebuilds it when it lands.
        Omerta.Inventory.Show()
        Omerta.Inventory.Request(0)
    elseif not down and open then
        frame:Close()
    end
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
            Omerta.HUD.Colour("text", 255 * alpha),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end,
})
