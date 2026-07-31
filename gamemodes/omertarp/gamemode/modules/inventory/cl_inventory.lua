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
-- Your own pockets are two panes of that one plate, centred: the man on the
-- left with what he is running on written under him, the ledger on the right.
-- It rises into place and sinks back out over about a tenth of a second —
-- fast, because a window held open by a key is looked at in glances and an
-- animation you wait for every time becomes the most irritating thing here.
--
-- Held open by C (see the bottom of the file), which is why there is no close
-- button anywhere: chrome for closing would promise a different interaction
-- model than the one the game has.
--
-- Hunger is read HERE and nowhere else (D-016) — deliberately, like money in a
-- wallet. The single exception is the starvation warning below (D-019).

local Internal = Omerta.Inventory.Internal

local state = {
    -- The ENTITY index of whatever is open, or 0 for plain pockets. Not the
    -- container id: a body has no container id, and a body-loot stream that
    -- looked like a pockets refresh is what this window used to close itself on.
    container = 0,
    label = "",
    mine = {},
    theirs = {},
    bulkUsed = 0,
    bulkLimit = 0,
}

-- The soft focus behind the window. One material, reused: rebuilding it per
-- frame is what makes a blur expensive.
local BLUR = Material("pp/blurscreen")

local hunger = Omerta.Hunger.MAX
local frame = nil
local incoming = nil

-- Bumped by every stream the client accepts. The loot-all sequence waits on it
-- rather than on a timer: "did the server answer yet" is a question about the
-- data arriving, not about how long the wire took.
local streamSerial = 0

-- What the interaction registry currently offers on the thing being looted.
local lootActions = {}
local lootQueriedFor, lootQueriedAt = 0, 0

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

-- Two kinds of stream arrive here and they are not interchangeable.
--
-- A stream carrying 0 is a REFRESH of your own pockets — the server sends one
-- after every pick-up, every use, every drop. It may never open the window (a
-- pick-up that flashes the inventory at you is the bug that started this), and
-- if a loot plate is up it must not replace it: the pockets half is merged in
-- and the open container, its label and its contents are left alone.
--
-- A stream carrying an entity index is a LOOT PUSH — somebody searched
-- something — and that one is allowed to open the window if none is up.
--
-- Either way, a window that is already up rebuilds: the numbers it is showing
-- have just changed.
function Internal.EndStream(payload)
    if not incoming or incoming.container ~= payload.container then return end
    local arrived = incoming
    incoming = nil
    streamSerial = streamSerial + 1

    local looting = IsValid(frame) and state.container and state.container > 0

    if arrived.container == 0 then
        if looting then
            state.mine = arrived.mine
            state.bulkUsed = arrived.bulkUsed
            state.bulkLimit = arrived.bulkLimit
        else
            state = arrived
        end
        if IsValid(frame) then frame:Rebuild() end
        return
    end

    state = arrived
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

-- Whether the window currently owns the screen. Read by anything that draws a
-- HUD element the window would otherwise duplicate — the weapon-equip
-- progress in particular, which appears on the item's own row while the
-- pockets are open and as a plate on the HUD once they are not.
function Omerta.Inventory.IsOpen()
    return IsValid(frame) and not frame.OmertaClosing
end

-- Which verbs a body offers depends on its INJURY state, not on what is left
-- in its pockets — so the answer does not change because an item moved, and
-- asking on every rebuild would put Loot All's one-item-per-0.55s rebuild rate
-- (~1.8/s) up against the query bucket's 2/s refill for no new information.
-- Asked when the target changes, when an action has just changed the answer,
-- and otherwise at most every few seconds.
function Internal.QueryLootActions(force)
    local target = state.container or 0
    if target <= 0 then return end
    if not force and target == lootQueriedFor
        and CurTime() - lootQueriedAt < 3 then
        return
    end
    lootQueriedFor, lootQueriedAt = target, CurTime()
    Omerta.Net.Request("interaction.query", { target = target })
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
-- Everything hangs off the right mouse button, in the guide's item menu: verbs
-- in a list, the irreversible alone at the bottom under a rule. No header —
-- you right-clicked the row, so you already know what it is, and a line of
-- mono repeating it was one more thing to read past.

local function openRowMenu(entry, mine)
    if not entry then return end
    local A = Omerta.Inventory.ACTION
    local m = Omerta.HUD.Menu()

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
-- Taking everything
--------------------------------------------------------------------------------
-- LOOT ALL is a CLIENT SEQUENCE over the take that already exists, not a new
-- server verb: one item every 0.55 seconds, each with the rustle and a sweep
-- across the row being lifted. Emptying a coat instantly would skip both the
-- capacity check that makes carrying things a decision and the moment of
-- standing over somebody, which is the whole point of a body.
--
-- Refusals are the interesting case. A stack that does not fit comes back
-- unmoved, so the sequence would sweep the same row for ever; two goes at one
-- instance is enough to call it, and it moves on to the next thing rather than
-- stopping — the coat may still hold something small.

local LOOT_ALL_SECONDS = 0.55

local lootAll = {
    active = false,
    instance = nil,  -- the row being lifted right now
    startedAt = 0,
    asked = nil,     -- the stream serial at the moment we asked, while waiting
    askedUntil = 0,
    attempts = {},   -- instance -> asks that left it where it was
    skipped = {},    -- instance -> given up on
}

local function lootAllEntry(instance)
    for _, entry in ipairs(state.theirs) do
        if entry.instance == instance then return entry end
    end
    return nil
end

local function lootAllNext()
    for _, entry in ipairs(state.theirs) do
        if not lootAll.skipped[entry.instance] then return entry end
    end
    return nil
end

local function stopLootAll()
    if not lootAll.active then return end
    lootAll.active = false
    lootAll.instance = nil
    Omerta.HUD.StopRustle()
end

local function startLootAll()
    lootAll.active = true
    lootAll.instance = nil
    lootAll.startedAt = 0
    lootAll.asked = nil
    lootAll.askedUntil = 0
    lootAll.attempts = {}
    lootAll.skipped = {}
end

hook.Add("Think", "omerta.inventory.loot_all", function()
    if not lootAll.active then return end
    if not (IsValid(frame) and state.container and state.container > 0) then
        stopLootAll()
        return
    end

    -- A row is sweeping. It is asked for when the sweep runs out, never before:
    -- the bar is the reach, not a decoration over an action already sent.
    if lootAll.instance then
        if CurTime() < lootAll.startedAt + LOOT_ALL_SECONDS then return end
        local entry = lootAllEntry(lootAll.instance)
        lootAll.instance = nil
        if not entry then return end -- it left while we were reaching for it
        act(Omerta.Inventory.ACTION.TAKE, entry)
        lootAll.asked = streamSerial
        lootAll.askedUntil = CurTime() + 0.5
        return
    end

    -- Waiting on the answer. Judging a refusal before the reply lands would
    -- skip every item on the first laggy body somebody searches; the server
    -- answers a take either way, so the wait always ends.
    if lootAll.asked then
        if streamSerial == lootAll.asked and CurTime() < lootAll.askedUntil then return end
        lootAll.asked = nil
    end

    local entry = lootAllNext()
    if not entry then stopLootAll() return end

    local attempts = (lootAll.attempts[entry.instance] or 0) + 1
    if attempts > 2 then
        lootAll.skipped[entry.instance] = true
        return
    end
    lootAll.attempts[entry.instance] = attempts
    lootAll.instance = entry.instance
    lootAll.startedAt = CurTime()
    Omerta.HUD.Rustle(0.5)
end)

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

    -- Dragging between the columns is the direct form of Take and Store — the
    -- same two requests, sent from where the hand already is. Only in the loot
    -- plate, because only there is there somewhere to drag to.
    if state.container and state.container > 0 then
        row.OmertaEntry = entry
        row.OmertaMine = mine
        row:Droppable("omerta_loot")
    end

    row.Paint = function(self, w, h)
        local held = mine and isInHands(entry)
        local hovered = self:IsHovered()
        local taking = lootAll.instance == entry.instance

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

        -- A row the game is working on: LOOT ALL lifting it, or the character
        -- drawing the weapon it names. The row ITSELF is the progress bar,
        -- sweeping its full width, and the words grey out while it does —
        -- something mid-action is not something you can still act on.
        --
        -- Equipping shares the treatment deliberately. It is the same fact in
        -- both cases (this row is busy, for this long), and the progress comes
        -- from the server's own clock, which is what lets the bar hand off to
        -- the HUD plate and back without ever jumping.
        local drawingInstance, drawingProgress
        if mine and Omerta.Weapons and Omerta.Weapons.EquipProgress then
            drawingInstance, drawingProgress = Omerta.Weapons.EquipProgress()
        end
        local drawing = drawingInstance == entry.instance

        local progress
        if taking then
            progress = math.Clamp(
                (CurTime() - lootAll.startedAt) / LOOT_ALL_SECONDS, 0, 1)
        elseif drawing then
            progress = math.Clamp(drawingProgress or 0, 0, 1)
        end

        if progress then
            surface.SetDrawColor(Omerta.HUD.Colour("brass",
                Omerta.HUD.Theme.ALPHA.wash * 255))
            surface.DrawRect(0, 0, w * progress, h)
            surface.SetDrawColor(Omerta.HUD.Colour("brass"))
            surface.DrawRect(w * progress - 1, 0, 1, h)
        end

        local pad = 24 * scale
        local textColour = held and Omerta.HUD.Colour("ink") or Omerta.HUD.Colour("text")
        local faintColour = held and Omerta.HUD.Colour("ink", 175)
            or Omerta.HUD.Colour("secondary")
        if progress then
            textColour = Omerta.HUD.Colour("text", 115)
            faintColour = Omerta.HUD.Colour("secondary", 115)
        end

        -- Icon, tinted to the row's own language.
        local mat = iconFor(entry.def)
        local cell = 22 * scale
        local iw, ih = cell, cell
        local mw, mh = mat:Width(), mat:Height()
        if mw > 0 and mh > 0 then
            local fit = math.min(cell / mw, cell / mh)
            iw, ih = mw * fit, mh * fit
        end
        if progress then
            surface.SetDrawColor(Omerta.HUD.Colour("text", 115))
        else
            surface.SetDrawColor(held and Omerta.HUD.Colour("ink")
                or Omerta.HUD.Colour("text", 220))
        end
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
                held and Omerta.HUD.Colour("ink")
                    or Omerta.HUD.Colour(stateToken, taking and 115 or 255),
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
                    held and Omerta.HUD.Colour("ink")
                        or Omerta.HUD.Colour(stateToken, taking and 115 or 255),
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            else
                draw.SimpleText(entry.quantity, Omerta.HUD.Font("label"),
                    w - pad, h * 0.5, faintColour,
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
    end

    row.OnMousePressed = function(self, code)
        if code == MOUSE_RIGHT then openRowMenu(entry, mine) return end
        -- Droppable() hangs the drag off the panel's OWN mouse handling, which
        -- this override replaces — so the drag has to be started by hand, or
        -- nothing is ever picked up and the feature looks unimplemented.
        self:DragMousePress(code)
    end
    row.OnMouseReleased = function(self, code)
        self:DragMouseRelease(code)
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
    column.OmertaScroll = scroll

    -- The CANVAS receives, not the scroll panel: the canvas is what the rows
    -- actually live in, and a drop on the empty space under the last row has
    -- to count as a drop on the column.
    if state.container and state.container > 0 then
        scroll:GetCanvas():Receiver("omerta_loot", function(_, panels, dropped)
            if not dropped then return end
            local A = Omerta.Inventory.ACTION
            for _, panel in ipairs(panels) do
                -- A receiver can be handed the same panel more than once in one
                -- drop; acting twice would take an item and put it straight back.
                if IsValid(panel) and panel.OmertaEntry and not panel.OmertaDropped
                        and panel.OmertaMine ~= mine then
                    panel.OmertaDropped = true
                    act(mine and A.TAKE or A.STORE, panel.OmertaEntry)
                end
            end
        end)
    end

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
-- The man himself
--------------------------------------------------------------------------------
-- The left pane of the pockets plate: your body, and under it what you are
-- running on — in the ledger's own idiom rather than in bars, because a bar
-- invites reading a percentage and notches read as "a few left".

local NOTCHES = 10

-- One reading, drawn exactly as the bulk meter downstairs draws its ticks.
-- Returns the y the next row starts at, so a second reading is one more line
-- here and nothing else. (There are no levels or skills to hang on this yet —
-- when there are, they are a line each.)
local function notchRow(x, y, caption, fraction)
    local scale = Omerta.HUD.Scale()
    draw.SimpleText(caption, Omerta.HUD.Font("mono"), x, y,
        Omerta.HUD.Colour("dim"), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    local lit = math.floor(math.Clamp(fraction or 0, 0, 1) * NOTCHES + 0.5)
    for i = 1, NOTCHES do
        surface.SetDrawColor(Omerta.HUD.Colour("text",
            i <= lit and 235 or 235 * 0.18))
        surface.DrawRect(x + (i - 1) * 14 * scale, y + 20 * scale,
            12 * scale, 4 * scale)
    end
    return y + 40 * scale
end

local function buildCharacterPane(parent, w, h)
    local scale = Omerta.HUD.Scale()
    local pane = vgui.Create("DPanel", parent)
    pane:SetSize(w, h)

    local booth = vgui.Create("DModelPanel", pane)
    booth:SetPos(0, 24 * scale)
    booth:SetSize(w, h - 136 * scale)
    -- Framed to hold a standing man head to foot, from the front: a player
    -- model faces its own +X, so that is where the camera stands.
    booth:SetFOV(36)
    booth:SetCamPos(Vector(105, 0, 36))
    booth:SetLookAt(Vector(0, 0, 36))

    -- IDLE ONLY, on the lead's instruction. LayoutEntity is where DModelPanel
    -- advances whatever animation it was given, so the override IS the fix:
    -- the preview holds one frame of the idle and never mirrors the running,
    -- crouching or shooting the player is doing behind the window.
    function booth:LayoutEntity(ent)
        if not IsValid(ent) then return end
        local sequence = ent:LookupSequence("idle_all_01")
        ent:SetSequence(sequence >= 0 and sequence or 0)
    end

    -- It has to be YOUR body: a model set by clothing or by a new character
    -- would otherwise leave the pane showing the man you used to be, and a
    -- model panel is told about neither.
    function booth:OmertaFollowModel()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local model = ply:GetModel()
        if model and model ~= "" and model ~= self.OmertaModel then
            self.OmertaModel = model
            self:SetModel(model)
        end
    end
    booth:OmertaFollowModel()

    -- Twice a second is enough for something that changes when a coat goes on.
    booth.OmertaNextCheck = 0
    function booth:Think()
        if CurTime() < self.OmertaNextCheck then return end
        self.OmertaNextCheck = CurTime() + 0.5
        self:OmertaFollowModel()
    end

    pane.Paint = function(_, _, ph)
        local x, y = 24 * scale, ph - 96 * scale
        y = notchRow(x, y, "STAMINA", Omerta.HUD.Stamina())
        y = notchRow(x, y, "APPETITE", hunger / Omerta.Hunger.MAX)
    end
    return pane
end

--------------------------------------------------------------------------------
-- What else you can do to them
--------------------------------------------------------------------------------
-- E now runs a target's single default action and nothing else, so the verbs
-- that are not about moving items — treat, stabilize, finish — are offered
-- here, at the bottom of THEIR column, because everything in the list is
-- something done to them. The list is whatever the interaction registry says
-- right now; this file knows none of those verbs by name.

-- The same height the pockets footer takes, so the two bottoms of the plate
-- line up when both are showing.
local LOOT_ACTION_BAR = 64

local function buildLootActions()
    local column = IsValid(frame) and frame.OmertaLootColumn or nil
    if not IsValid(column) then return end

    local scale = Omerta.HUD.Scale()
    if IsValid(column.OmertaActions) then column.OmertaActions:Remove() end

    local bar = nil
    if #lootActions > 0 then
        bar = vgui.Create("DPanel", column)
        bar:SetSize(column:GetWide(), LOOT_ACTION_BAR * scale)
        bar:SetPos(0, column:GetTall() - LOOT_ACTION_BAR * scale)
        bar.Paint = function(_, bw)
            surface.SetDrawColor(Omerta.HUD.Colour("rule"))
            surface.DrawRect(0, 0, bw, 1)
        end

        local pad = 24 * scale
        local gap = 8 * scale
        local wide = math.floor((bar:GetWide() - pad * 2
            - gap * (#lootActions - 1)) / #lootActions)
        for i, option in ipairs(lootActions) do
            local button = Omerta.HUD.Button(bar, option.label, "quiet", function()
                Omerta.Net.Request("interaction.execute",
                    { target = state.container, action = option.index })
                -- Doing something to somebody changes what else can be done to
                -- them; ask again rather than leave a row of stale verbs.
                Internal.QueryLootActions(true)
            end)
            button:SetSize(wide, 32 * scale)
            button:SetPos(pad + (i - 1) * (wide + gap), 16 * scale)

            if option.label == "Finish" then
                -- Danger is never a fill at this size, and the kit has no
                -- danger button because nothing else has needed one: the quiet
                -- box keeps its shape and only the ink changes.
                button.OmertaLabel = ""
                button.PaintOver = function(self, bw, bh)
                    draw.SimpleText(string.upper(option.label),
                        Omerta.HUD.Font("verb"), bw * 0.5, bh * 0.5,
                        Omerta.HUD.Colour("danger", self:IsHovered() and 255 or 220),
                        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end
        end
    end

    column.OmertaActions = bar
    -- The rows give up the space the bar takes rather than scrolling under it.
    if IsValid(column.OmertaScroll) then
        column.OmertaScroll:DockMargin(0, 52 * scale, 0,
            (bar and LOOT_ACTION_BAR + 8 or 8) * scale)
        column:InvalidateLayout()
    end
end

hook.Add("Omerta.InteractionOptions", "omerta.inventory.loot_actions", function(payload)
    if not IsValid(frame) then return end
    if not (state.container and state.container > 0) then return end
    -- Options for anything else belong to whoever asked for them.
    if payload.target ~= state.container then return end

    lootActions = {}
    for n = 1, payload.count do
        local index, label = payload["i" .. n], payload["l" .. n]
        -- "Search" is this window. Offering it inside itself would reopen what
        -- is already open — and "Search (empty)" would report on a list the
        -- player is looking at.
        if index and index > 0 and label and label ~= ""
                and string.sub(label, 1, 6) ~= "Search" then
            lootActions[#lootActions + 1] = { index = index, label = label }
        end
    end
    buildLootActions()
end)

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

    -- The window RISES into place and sinks back out.
    --
    -- Held open by a key, it is on screen for a second or two at a time, and
    -- appearing in one frame read as a flash rather than as a thing being
    -- looked at. It is deliberately fast — 0.12s in, 0.1s out — because an
    -- animation you wait for on every glance becomes the most irritating
    -- thing in the game. `anim` runs 0..1; the frame's own position is set
    -- from it every frame rather than tweened by the panel system, so the
    -- close can run after Rebuild has moved it.
    frame.OmertaAnim = 0
    frame.OmertaClosing = false
    frame.OmertaRestY = nil

    local RISE = 42 * scale

    frame.Paint = function(self, w, h)
        local eased = self.OmertaAnim * self.OmertaAnim * (3 - 2 * self.OmertaAnim)

        -- The world softens behind it, gently: the player is still standing in
        -- the street and may need to see somebody walk into it.
        if eased > 0.01 then
            surface.SetMaterial(BLUR)
            surface.SetDrawColor(255, 255, 255, 255)
            for pass = 1, 2 do
                BLUR:SetFloat("$blur", (pass / 2) * 3 * eased)
                BLUR:Recompute()
                render.UpdateScreenEffectTexture()
                surface.DrawTexturedRect(-self:GetX(), -self:GetY(), ScrW(), ScrH())
            end
        end

        -- ONE plate, per the guide — never two floating windows.
        surface.SetDrawColor(Omerta.HUD.Colour("plate",
            Omerta.HUD.Theme.ALPHA.focus * 255 * eased))
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(Omerta.HUD.Colour("rule", 255 * eased))
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    -- Children inherit the fade by riding the frame's alpha; the rise is the
    -- frame's own position, so everything inside moves with it for free.
    frame.Think = function(self)
        local dt = FrameTime()
        if self.OmertaClosing then
            self.OmertaAnim = self.OmertaAnim - dt / 0.10
            if self.OmertaAnim <= 0 then
                self.OmertaAnim = 0
                self:Remove()
                return
            end
        elseif self.OmertaAnim < 1 then
            self.OmertaAnim = math.min(1, self.OmertaAnim + dt / 0.12)
        end

        local eased = self.OmertaAnim * self.OmertaAnim * (3 - 2 * self.OmertaAnim)
        self:SetAlpha(255 * eased)
        if self.OmertaRestY then
            self:SetPos(self:GetX(), self.OmertaRestY + RISE * (1 - eased))
        end
    end

    -- Closing is a request, not a removal: the frame takes itself off screen
    -- once it has finished sinking. Everything that used to call frame:Close()
    -- or frame:Remove() goes through here so the animation cannot be skipped.
    frame.OmertaClose = function(self)
        if self.OmertaClosing then return end
        self.OmertaClosing = true
    end

    local function rule(parent, x, height)
        local divider = vgui.Create("DPanel", parent)
        divider.OmertaOwned = true
        divider:SetSize(1, height)
        divider:SetPos(x, 0)
        divider.Paint = function(_, w, h)
            surface.SetDrawColor(Omerta.HUD.Colour("rule"))
            surface.DrawRect(0, 0, w, h)
        end
        return divider
    end

    function frame:Rebuild()
        for _, child in ipairs(self:GetChildren()) do
            if child.OmertaOwned then child:Remove() end
        end
        self.OmertaLootColumn = nil

        local looting = state.container and state.container > 0
        local width = (looting and 960 or 980) * scale
        local height = 560 * scale
        self:SetSize(width, height)

        if looting then
            self:Center()

            -- A new subject: the verbs offered on the last one mean nothing here.
            if self.OmertaTarget ~= state.container then
                self.OmertaTarget = state.container
                lootActions = {}
            end

            -- Two identical columns, one vertical rule between them.
            rule(self, width * 0.5, height)

            local usedUnits = math.floor(state.bulkUsed / Omerta.Inventory.BULK_SCALE + 0.5)
            local limitUnits = math.max(1,
                math.floor(state.bulkLimit / Omerta.Inventory.BULK_SCALE + 0.5))
            local mine = buildColumn(self, "Pockets",
                string.format("%d / %d", usedUnits, limitUnits),
                state.mine, true, false)
            mine.OmertaOwned = true
            mine:SetPos(0, 0)
            mine:SetSize(width * 0.5, height)

            local columnWide = width * 0.5 - 1
            local title = state.label ~= "" and state.label or "Container"
            local theirs = buildColumn(self, title, "C TO CLOSE",
                state.theirs, false, false)
            theirs.OmertaOwned = true
            theirs:SetPos(width * 0.5 + 1, 0)
            theirs:SetSize(columnWide, height)
            self.OmertaLootColumn = theirs

            -- Taking everything is a verb about their column, so it sits in
            -- their title row. Placed against the MEASURED note beside it: a
            -- fixed offset overlaps the moment the interface scale changes.
            surface.SetFont(Omerta.HUD.Font("mono"))
            local noteWide = surface.GetTextSize("C TO CLOSE")
            local lootAllButton = Omerta.HUD.Button(theirs, "Loot all", "quiet",
                startLootAll)
            lootAllButton:SetSize(104 * scale, 26 * scale)
            lootAllButton:SetPos(columnWide - 24 * scale - noteWide
                - 12 * scale - 104 * scale, 10 * scale)

            buildLootActions()
            Internal.QueryLootActions(false)
        else
            -- Centred, with the man on the left of the same plate. The first
            -- version shifted the whole thing right to make room for him,
            -- which put the ledger off-axis for the sake of a pane that was
            -- always going to be part of the same object.
            self:Center()

            local paneWide = math.floor(width * 0.38)
            local character = buildCharacterPane(self, paneWide, height)
            character.OmertaOwned = true
            character:SetPos(0, 0)

            rule(self, paneWide, height)

            local column = buildColumn(self, "Pockets", "HOLD C",
                state.mine, true, true)
            column.OmertaOwned = true
            column:SetPos(paneWide + 1, 0)
            column:SetSize(width - paneWide - 1, height)
            local footer = buildFooter(column)
            footer.OmertaOwned = true
        end

        -- Where the window rests once it has finished rising. Captured after
        -- the layout has placed it, because Think offsets from this and would
        -- otherwise compound its own offset on every rebuild.
        self.OmertaRestY = self:GetY()
    end

    frame:Rebuild()

    frame.OnRemove = function()
        frame = nil
        state.container = 0
        lootActions = {}
        stopLootAll()
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
-- held), stays up while you move things, and a press of C dismisses it. Which
-- window is which is remembered on the frame itself (OmertaHeld) rather than
-- inferred: a loot plate that the release of C could close would vanish under
-- the hand of anyone who had opened it while walking.
--
-- `pinned` is the console command's escape hatch: omerta_inventory holds the
-- window open with no key for staff and debugging, and toggles back off.
local pinned = false
local wasDown = false

concommand.Add("omerta_inventory", function()
    if IsValid(frame) and pinned then
        pinned = false
        frame:OmertaClose()
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

    -- A window that is sinking out counts as closed, so tapping C again
    -- during the animation reopens immediately rather than waiting for it to
    -- finish and then ignoring the press.
    local open = IsValid(frame) and not frame.OmertaClosing
    local looting = open and state.container and state.container > 0

    if looting then
        -- A press dismisses the loot plate; holding is not required while
        -- both hands are in somebody's coat.
        if pressed then frame:OmertaClose() end
        return
    end

    if down and not open then
        -- Shown immediately from the cached state so the window is ON the
        -- key, then refreshed; the stream rebuilds it when it lands.
        Omerta.Inventory.Show()
        frame.OmertaHeld = true
        Omerta.Inventory.Request(0)
    elseif not down and open and frame.OmertaHeld then
        frame:OmertaClose()
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
