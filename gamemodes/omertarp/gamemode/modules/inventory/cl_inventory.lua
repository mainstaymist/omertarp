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

    -- A window that is SINKING OUT counts as gone, everywhere below. It is
    -- still IsValid for a tenth of a second after the player let go of C, and a
    -- loot push that arrived in that tenth used to rebuild the leaving window
    -- into a loot plate that then finished leaving — so searching a body
    -- immediately after closing your pockets showed nothing at all.
    local open = Omerta.Inventory.IsOpen()
    local looting = open and state.container and state.container > 0

    if arrived.container == 0 then
        if looting then
            state.mine = arrived.mine
            state.bulkUsed = arrived.bulkUsed
            state.bulkLimit = arrived.bulkLimit
        else
            state = arrived
        end
        if open then frame:Rebuild() end
        return
    end

    state = arrived
    if open then
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
    return Omerta.HUD.Revealed(frame)
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

-- Everything that belongs to looking in somebody else's pockets, put down. The
-- window is NOT touched: this is the session, not the panel, and the two end at
-- different moments — the panel spends a tenth of a second sinking out after
-- the session it was showing is over.
local function endLootSession()
    state.container = 0
    lootActions = {}
    stopLootAll()
end

hook.Add("Think", "omerta.inventory.loot_all", function()
    if not lootAll.active then return end
    -- A window that is sinking out counts as gone: a sequence that kept lifting
    -- items into a leaving window would go on asking the server for takes with
    -- nothing on screen to show for them.
    if not (Omerta.Inventory.IsOpen() and state.container and state.container > 0) then
        stopLootAll()
        return
    end

    -- Over the limit, nothing at all is going to move. The server refuses each
    -- take on its own account — this is not a client-side capacity check
    -- standing in for one — but sweeping every remaining row twice to be told
    -- so twice is twenty identical notices for no information.
    if Omerta.Inventory.IsOverloaded(state.bulkUsed, state.bulkLimit) then
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
            -- A WORN item costs no bulk, so its row says so with the same em
            -- dash the STATE column uses for "nothing here". Printing its bulk
            -- anyway would put a number in the ledger that is deliberately
            -- absent from the total underneath it, and a ledger whose column
            -- does not add up is worse than no column.
            --
            -- Equipped is not the test — worn is. A holstered gun is equipped
            -- and still costs every unit of its bulk, so its row prints the
            -- number like anything else you are carrying.
            local worn = entry.slot ~= nil and entry.slot.worn == true
            draw.SimpleText(worn and "—" or Omerta.Inventory.FormatBulk(
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
--
-- THE HEADER IS MEASURED, NOT GUESSED. It used to bottom-align the title on a
-- hardcoded 34px baseline, which was a fair guess at the heading's height
-- before the type scale gained its readability multiplier and stopped being one
-- afterwards: the heading's box is nearer 34 DESIGN px tall on its own, so the
-- words sat with their caps on the top edge of the plate with no margin at all
-- above them. Asking the font how tall it is costs one call at build time and
-- cannot go stale the next time a size moves.
--
-- `noteToken` is the colour of the note in the top right, "dim" unless the
-- caller has something to mark.
local function buildColumn(parent, title, note, entries, mine, wide, noteToken)
    local scale = Omerta.HUD.Scale()

    surface.SetFont(Omerta.HUD.Font("heading"))
    local _, titleTall = surface.GetTextSize("H")
    surface.SetFont(Omerta.HUD.Font("mono"))
    local _, captionTall = surface.GetTextSize("H")

    -- The title keeps the same margin above it that the column keeps at its
    -- left edge — the guide's screen-edge step, which is the one every other
    -- distance in this window is already measured from.
    local pad = Omerta.HUD.Space(5)
    local titleBottom = pad + titleTall
    local ruleY = titleBottom + Omerta.HUD.Space(3)
    local captionBottom = ruleY + 1 + captionTall
    local captionRuleY = captionBottom + Omerta.HUD.Space(1)
    local listTop = wide and (captionRuleY + Omerta.HUD.Space(1))
        or (ruleY + Omerta.HUD.Space(2))

    -- Where the rows start, published for anything that re-docks the list
    -- later: the loot action bar does, and a second copy of this number is how
    -- the two halves of the same column drift apart.
    local column = vgui.Create("DPanel", parent)
    column.OmertaListTop = listTop
    -- The middle of the title's own line, for anything that has to sit level
    -- with it. Loot All does.
    column.OmertaTitleMid = pad + titleTall * 0.5

    column.Paint = function(_, w, h)
        draw.SimpleText(string.upper(title), Omerta.HUD.Font("heading"),
            pad, titleBottom, Omerta.HUD.Colour("text"),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        if note then
            draw.SimpleText(note, Omerta.HUD.Font("mono"),
                w - pad, titleBottom, Omerta.HUD.Colour(noteToken or "dim"),
                TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
        end
        surface.SetDrawColor(Omerta.HUD.Colour("rule"))
        surface.DrawRect(0, ruleY, w, 1)

        if wide then
            -- The ledger's column captions, once, in the system voice.
            draw.SimpleText("ITEM", Omerta.HUD.Font("mono"), pad + 40 * scale,
                captionBottom,
                Omerta.HUD.Colour("dim"), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
            draw.SimpleText("QTY", Omerta.HUD.Font("mono"), w - pad - 168 * scale,
                captionBottom,
                Omerta.HUD.Colour("dim"), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
            draw.SimpleText("BULK", Omerta.HUD.Font("mono"), w - pad - 96 * scale,
                captionBottom,
                Omerta.HUD.Colour("dim"), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
            draw.SimpleText("STATE", Omerta.HUD.Font("mono"), w - pad,
                captionBottom,
                Omerta.HUD.Colour("dim"), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
            surface.SetDrawColor(Omerta.HUD.Colour("ruleFaint"))
            surface.DrawRect(0, captionRuleY, w, 1)
        end
    end

    local scroll = vgui.Create("DScrollPanel", column)
    scroll:Dock(FILL)
    scroll:DockMargin(0, listTop, 0, Omerta.HUD.Space(2))
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

        -- Over the limit is a state the player has to be able to read off the
        -- one line that already carries the constraint. THE SERVER DECIDED IT:
        -- both numbers arrived on the same stream, so this is a comparison of
        -- two facts, not a second opinion about capacity.
        --
        -- Red is a MARK, not a sentence. One word of the caption changes and
        -- the caption takes the danger ink — the same move the single word
        -- APPETITE makes on the other side of this footer when a character is
        -- starving. The tick meter keeps its own colour: a meter that is
        -- visibly full under a caption that says OVERLOADED is unambiguous,
        -- and two red things would be a paragraph.
        local over = Omerta.Inventory.IsOverloaded(state.bulkUsed, state.bulkLimit)
        draw.SimpleText(string.format("%s — %d OF %d",
                over and "OVERLOADED" or "POCKETS", usedUnits, limitUnits),
            Omerta.HUD.Font("mono"), pad, 14 * scale,
            Omerta.HUD.Colour(over and "danger" or "dim"),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

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
    -- Framed from the HIP UP, not head to foot. A player model faces its own
    -- +X, so that is where the camera stands.
    --
    -- The full-length shot spent most of the pane on trousers. What this pane
    -- is actually for is what the character is WEARING and what is in their
    -- hands — a coat going on, a gun coming out — and all of that happens
    -- above the belt. Cropping to it makes the same panel show it several
    -- times larger without taking a pixel from anything else.
    --
    -- The numbers are a framing, not magic: BOOTH_AT is the height the camera
    -- looks at on a standard ValveBiped rig (roughly sternum), and the
    -- distance sets how much of the body fits around it — halving the old
    -- distance halves the vertical coverage, which is the crop.
    local BOOTH_AT, BOOTH_DIST = 56, 58
    booth:SetFOV(36)
    booth:SetCamPos(Vector(BOOTH_DIST, 0, BOOTH_AT))
    booth:SetLookAt(Vector(0, 0, BOOTH_AT))

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
    local column = Omerta.Inventory.IsOpen() and frame.OmertaLootColumn or nil
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
    -- The top margin comes back off the column rather than being written out
    -- again here: two copies of where the list starts is how the header and the
    -- rows under it end up disagreeing by a few pixels.
    if IsValid(column.OmertaScroll) then
        column.OmertaScroll:DockMargin(0, column.OmertaListTop or 0, 0,
            bar and (LOOT_ACTION_BAR * scale + Omerta.HUD.Space(2))
                or Omerta.HUD.Space(2))
        column:InvalidateLayout()
    end
end

hook.Add("Omerta.InteractionOptions", "omerta.inventory.loot_actions", function(payload)
    if not Omerta.Inventory.IsOpen() then return end
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

-- A window's teardown: what has to be put down when a window goes away.
--
-- IDENTITY-CHECKED, because the panel being torn down is very often not the one
-- on screen. Panel:Remove does not destroy a panel where it stands: it marks it,
-- and the engine deletes it — running OnRemove — at the end of the frame. So a
-- REPLACED window's teardown lands after its replacement has been built and
-- stored, and a teardown that wrote `frame = nil` unconditionally erased the
-- pointer to a window that was already on screen. Nothing could then close it or
-- even find it, and the next press of C built another one over the top of it:
-- the duplicate that "stays and will not go away".
local function release(panel)
    if frame ~= panel then return end
    frame = nil
    endLootSession()
end

function Omerta.Inventory.Show()
    -- THE OUTGOING WINDOW STOPS BEING THE WINDOW BEFORE IT IS REMOVED, and that
    -- ordering is half the fix for both stuck-window reports (release above is
    -- the other half; either one alone still loses the race in one direction).
    -- Once `frame` no longer points at it, its late teardown is a no-op, and the
    -- window that IS on screen keeps its pointer and its loot session.
    --
    -- Remove, not Close: the window is being REPLACED. This is also the path
    -- that takes a sinking window off screen early — reopen your pockets in the
    -- tenth of a second one is leaving and the new window is on the key, with
    -- no wait for the old one to finish going.
    local outgoing = frame
    frame = nil
    if IsValid(outgoing) then outgoing:Remove() end

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
    -- looked at. This window is where the motion was invented; it is now
    -- Omerta.HUD.Reveal and every window in the game shares it, so what used to
    -- be forty lines here is one call below Paint. `self.OmertaEased` is the
    -- 0..1 curve the reveal is currently at, which this frame's own paint needs
    -- for something the shared fade cannot do for it: the STRENGTH of the blur
    -- behind it, which has to ramp rather than merely become more opaque.
    frame.Paint = function(self, w, h)
        local eased = self.OmertaEased or 0

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

    -- Installed after Paint, which is the rule: it wraps whatever is there.
    -- Children inherit the fade by riding the frame's alpha, and the rise is
    -- the frame's own position, so everything inside moves with it for free.
    Omerta.HUD.Reveal(frame)

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

        local looting = (state.container and state.container > 0) == true
        -- WHAT KIND OF WINDOW THIS IS, recorded on the window itself. The key
        -- poll reads this rather than the module's state, so the plate on screen
        -- and the rule that dismisses it cannot disagree about what is being
        -- shown — which is the disagreement bug 3 was made of.
        self.OmertaLooting = looting

        -- Wants the design size; takes the screen's answer. Two columns of
        -- loot at 1x come to more than a 1366-wide laptop has.
        local width, height = Omerta.HUD.Fit((looting and 960 or 980) * scale,
            560 * scale)
        self:SetSize(width, height)

        if looting then
            self:Center()

            -- Opened by a search, never by a key. A loot plate that arrived
            -- while C happened to be held must not vanish on the let-go, and
            -- rebuilding a held pockets window into one is exactly how it
            -- inherited a hold nobody made.
            self.OmertaHeld = false

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
            -- The loot plate has no footer, and it is the one window where
            -- "why will nothing move across" is the live question — so the
            -- pockets column's own note carries the mark instead.
            local over = Omerta.Inventory.IsOverloaded(state.bulkUsed, state.bulkLimit)
            local mine = buildColumn(self, "Pockets",
                string.format("%d / %d%s", usedUnits, limitUnits,
                    over and " OVER" or ""),
                state.mine, true, false, over and "danger" or nil)
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
            local buttonTall = 26 * scale
            lootAllButton:SetSize(104 * scale, buttonTall)
            -- Level with the title beside it, off the column's own measured
            -- header rather than off a second guess at where the title sits.
            lootAllButton:SetPos(columnWide - Omerta.HUD.Space(5) - noteWide
                - Omerta.HUD.Space(3) - 104 * scale,
                math.max(0, theirs.OmertaTitleMid - buttonTall * 0.5))

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

        -- Where the window rests once it has finished rising. Re-anchored after
        -- the layout has placed it — BOTH branches above re-centre the window,
        -- and the reveal offsets from the resting place, so a rebuild that did
        -- not say where the window now rests would leave it animating toward
        -- the position it had before the loot column appeared.
        self:OmertaAnchor()
    end

    frame:Rebuild()

    frame.OnRemove = function(self) release(self) end
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
-- window is which is remembered on the frame itself (OmertaLooting, OmertaHeld)
-- rather than inferred: a loot plate that the release of C could close would
-- vanish under the hand of anyone who had opened it while walking.
--
-- WHAT THE POLL DECIDES IS NOT DECIDED HERE. Omerta.Inventory.HoldAction is the
-- rule, pure and headless-tested, and this hook only gathers the facts it needs
-- and carries out the answer. The distinction that keeps being lost — a window
-- that is sinking out counts as CLOSED — is a line of that function with a test
-- against it, rather than a condition here that reads correct until somebody
-- swaps it for IsValid.
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
    endLootSession()
    Omerta.Inventory.Show()
    Omerta.Inventory.Request(0)
end)

hook.Add("Think", "omerta.inventory.hold", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    -- Not while typing, in the menu, or in the console: a key that opens a
    -- window mid-sentence is worse than no key at all.
    --
    -- Player:IsTyping is not enough on its own any more. M7 draws its own chat
    -- box and suppresses the engine's, so the engine believes nobody is ever
    -- typing — and the letter C is in a great many sentences.
    local chatting = (ply.IsTyping and ply:IsTyping())
        or (Omerta.Chat and Omerta.Chat.IsTyping and Omerta.Chat.IsTyping())
    -- ...and not while the player is not, in fact, standing in a street with
    -- pockets. The three conditions above are every full-screen state the
    -- ENGINE owns and none of the ones this gamemode owns, which is how the
    -- inventory came to open over the front end, over character creation and
    -- over the pause rail. Omerta.HUD.InWorld is that list, asked once, in a
    -- place the next screen to poll a key can ask it too.
    local inWorld = Omerta.HUD.InWorld()
    local down = input.IsKeyDown(KEY_C) and not chatting
        and not gui.IsGameUIVisible() and not gui.IsConsoleVisible()
        and inWorld
    local previous = wasDown
    wasDown = down

    -- LEAVING THE WORLD TAKES ANY WINDOW WITH IT. Refusing to open one is only
    -- half the answer: a player can be looking in their pockets when they are
    -- shot, or press F1 with somebody's coat open, and a window that survived
    -- either would sit over the death card — or over the pause rail — until
    -- they thought to press C at it.
    --
    -- WHATEVER IS UP, not only the held-open kind, and that is why this is here
    -- rather than a case in HoldAction. Pockets on a key would fall out of
    -- `down` going false on their own; a loot plate would not, because it was
    -- opened by a search and is dismissed by a press that will never come, and
    -- neither would a window pinned by the console command, which is pinned
    -- precisely so that no key can take it down. Closed rather than removed —
    -- it sinks out under whatever is arriving, like everything else that leaves.
    if not inWorld then
        pinned = false
        if IsValid(frame) and Omerta.HUD.Revealed(frame) then
            if frame.OmertaLooting then Omerta.Inventory.Request(0) end
            frame:OmertaClose()
        end
        return
    end

    if pinned then
        if not IsValid(frame) then pinned = false end
        return
    end

    -- The window, described for the rule. `revealed` is the one that matters:
    -- Omerta.HUD.Revealed answers "is it up", not "does it exist", so a window
    -- in the tenth of a second it spends sinking out is already gone here.
    local window = nil
    if IsValid(frame) then
        window = {
            revealed = Omerta.HUD.Revealed(frame),
            looting = frame.OmertaLooting == true,
            held = frame.OmertaHeld == true,
        }
    end

    local action = Omerta.Inventory.HoldAction(window, down, previous)

    if action == "close" then
        -- Telling the server a loot plate is gone is not politeness. The open
        -- container lives on the server until something replaces it, and every
        -- later refresh arrives carrying it — which reopens, unasked, the plate
        -- the player just dismissed. Asking for plain pockets says "I am not in
        -- that coat any more" in the one message that already means it.
        if frame.OmertaLooting then Omerta.Inventory.Request(0) end
        frame:OmertaClose()
    elseif action == "open" then
        -- Pockets, always: the poll never opens somebody else's. Whatever is
        -- left of a loot session goes first, so the cached state cannot build a
        -- loot layout under a key that is meant to hold pockets open.
        endLootSession()
        -- Shown immediately from the cached state so the window is ON the
        -- key, then refreshed; the stream rebuilds it when it lands.
        Omerta.Inventory.Show()
        frame.OmertaHeld = true
        Omerta.Inventory.Request(0)
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
