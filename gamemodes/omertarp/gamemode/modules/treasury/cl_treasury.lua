-- The safe, from the other side of the door.
--
-- Opened by standing at your institution's safe; there is no key for it
-- anywhere else, because the location is the point (§4a). What it shows
-- depends entirely on rank: a member who cannot view the books is told the
-- window exists and nothing else.

local state = { counted = 0, ledger = 0, limit = 0, unlimited = false, may_view = false }
local catalogue = { entries = {}, receiving = nil }
local history = { lines = {}, receiving = nil }
local frame = nil

local COLOURS = {
    paper   = Color(232, 226, 210),
    muted   = Color(140, 132, 122),
    panel   = Color(20, 19, 18, 244),
    line    = Color(70, 64, 56),
    warning = Color(178, 96, 84),
    good    = Color(150, 170, 140),
}

hook.Add("Omerta.TreasuryState", "omerta.treasury.state", function(payload)
    state = payload
    if IsValid(frame) then frame:Rebuild() else Omerta.Treasury.Show() end
end)

hook.Add("Omerta.ProcurementEntry", "omerta.treasury.catalogue", function(payload)
    catalogue.receiving = catalogue.receiving or {}
    local entry = Omerta.Procurement.GetByIndex(payload.entry)
    if entry then catalogue.receiving[#catalogue.receiving + 1] = entry end
    if payload.last then
        catalogue.entries = catalogue.receiving
        catalogue.receiving = nil
        if IsValid(frame) then frame:Rebuild() end
    end
end)

hook.Add("Omerta.TreasuryLine", "omerta.treasury.history", function(payload)
    history.receiving = history.receiving or {}
    history.receiving[#history.receiving + 1] = payload
    if payload.last then
        history.lines = history.receiving
        history.receiving = nil
        if IsValid(frame) then frame:Rebuild() end
    end
end)

local function act(action, amount)
    Omerta.Net.Request("treasury.action", { action = action, amount = math.floor(amount) })
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

function Omerta.Treasury.Show()
    if IsValid(frame) then frame:Remove() end
    local scale = Omerta.HUD.Scale()

    frame = vgui.Create("DFrame")
    frame:SetSize(math.min(ScrW() * 0.6, 620 * scale), math.min(ScrH() * 0.7, 500 * scale))
    frame:Center()
    frame:SetTitle("")
    frame:MakePopup()
    frame.Paint = function(_, w, h)
        draw.RoundedBox(4, 0, 0, w, h, COLOURS.panel)
        surface.SetDrawColor(COLOURS.line)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local header = vgui.Create("DPanel", frame)
    header:Dock(TOP)
    header:SetTall(64 * scale)
    header:DockMargin(14 * scale, 6 * scale, 14 * scale, 4 * scale)
    header.Paint = function(_, w, h)
        draw.SimpleText("The Safe", Omerta.HUD.Font("body"), 0, 0,
            COLOURS.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        if not state.may_view then
            draw.SimpleText("You are not senior enough to count it.",
                Omerta.HUD.Font("label"), 0, 26 * scale,
                COLOURS.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        else
            draw.SimpleText("In the safe: " .. Omerta.Money.Format(state.counted),
                Omerta.HUD.Font("label"), 0, 26 * scale,
                COLOURS.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            -- The books beside the cash, and the gap between them named. This
            -- is the whole reason the treasury is a safe and not a number.
            local gap = state.counted - state.ledger
            draw.SimpleText("The books say: " .. Omerta.Money.Format(state.ledger),
                Omerta.HUD.Font("small"), 0, 46 * scale,
                COLOURS.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            if gap ~= 0 then
                draw.SimpleText(Omerta.Treasury.DescribeDiscrepancy(state.counted, state.ledger),
                    Omerta.HUD.Font("small"), w, 46 * scale,
                    gap < 0 and COLOURS.warning or COLOURS.good,
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
            end
        end

        draw.SimpleText(state.unlimited and "No limit on what you may take"
                or ("You may take up to " .. Omerta.Money.Format(state.limit) .. " alone"),
            Omerta.HUD.Font("small"), w, 4,
            COLOURS.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        surface.SetDrawColor(COLOURS.line)
        surface.DrawRect(0, h - 1, w, 1)
    end

    local controls = vgui.Create("DPanel", frame)
    controls:Dock(TOP)
    controls:SetTall(34 * scale)
    controls:DockMargin(14 * scale, 4 * scale, 14 * scale, 6 * scale)
    controls.Paint = nil

    -- Entered in dollars because that is how a human thinks about it; the
    -- server rounds to something the mint can actually produce.
    local amount = vgui.Create("DTextEntry", controls)
    amount:Dock(LEFT)
    amount:SetWide(120 * scale)
    amount:SetPlaceholderText("dollars")
    amount:SetNumeric(true)

    local function button(parent, label, fn, wide)
        local btn = vgui.Create("DButton", parent)
        btn:SetText(label)
        btn:SetFont(Omerta.HUD.Font("label"))
        btn:SetTextColor(COLOURS.paper)
        btn:Dock(LEFT)
        btn:DockMargin(6 * scale, 0, 0, 0)
        btn:SetWide(wide or 96 * scale)
        btn.Paint = function(self, w, h)
            surface.SetDrawColor(self:IsHovered() and COLOURS.line or Color(38, 35, 32))
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(COLOURS.line)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end
        btn.DoClick = fn
        return btn
    end

    local function enteredCents()
        local dollars = tonumber(amount:GetValue())
        if not dollars or dollars <= 0 then return nil end
        return Omerta.Money.Round(math.floor(dollars * 100 + 0.5))
    end

    button(controls, "Put In", function()
        local cents = enteredCents()
        if cents then act(1, cents) end
    end)
    button(controls, "Take Out", function()
        local cents = enteredCents()
        if cents then act(2, cents) end
    end)

    local body = vgui.Create("DScrollPanel", frame)
    body:Dock(FILL)
    body:DockMargin(14 * scale, 0, 14 * scale, 10 * scale)

    local function heading(text)
        local panel = vgui.Create("DPanel", body)
        panel:Dock(TOP)
        panel:SetTall(24 * scale)
        panel:DockMargin(0, 6 * scale, 0, 0)
        panel.Paint = function(_, w, h)
            draw.SimpleText(text, Omerta.HUD.Font("small"), 0, 6,
                COLOURS.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            surface.SetDrawColor(COLOURS.line)
            surface.DrawRect(0, h - 1, w, 1)
        end
    end

    function frame:Rebuild()
        body:Clear()

        -- The books first, because what the family has been doing with its
        -- money is more interesting than what it could buy next.
        if state.may_view and #history.lines > 0 then
            heading("The Books")
            for _, line in ipairs(history.lines) do
                local row = vgui.Create("DPanel", body)
                row:Dock(TOP)
                row:SetTall(22 * scale)
                row.Paint = function(_, w, h)
                    local who = line.who
                    if line.approver ~= "" then who = who .. " / " .. line.approver end
                    draw.SimpleText(who, Omerta.HUD.Font("small"), 0, 4,
                        COLOURS.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    draw.SimpleText(line.reason, Omerta.HUD.Font("small"), w * 0.42, 4,
                        COLOURS.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    draw.SimpleText((line.delta >= 0 and "+" or "-")
                            .. Omerta.Money.Format(math.abs(line.delta)),
                        Omerta.HUD.Font("small"), w, 4,
                        line.delta >= 0 and COLOURS.good or COLOURS.paper,
                        TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
                end
            end
        end

        if #catalogue.entries == 0 then return end

        local lastCategory = nil
        for _, entry in ipairs(catalogue.entries) do
            if entry.category ~= lastCategory then
                lastCategory = entry.category
                heading(Omerta.Procurement.CATEGORIES[entry.category] or entry.category)
            end

            local row = vgui.Create("DPanel", body)
            row:Dock(TOP)
            row:SetTall(28 * scale)
            row.Paint = function(_, w, h)
                local name = entry.name
                if entry.quantity > 1 then name = name .. "  (" .. entry.quantity .. ")" end
                draw.SimpleText(name, Omerta.HUD.Font("label"), 0, 5,
                    COLOURS.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                -- Priced against what you may spend alone, so an order that
                -- needs somebody else's word reads as such before you click.
                local affordableAlone = state.unlimited or entry.price <= state.limit
                draw.SimpleText(Omerta.Money.Format(entry.price), Omerta.HUD.Font("label"),
                    w - 76 * scale, 5,
                    affordableAlone and COLOURS.paper or COLOURS.warning,
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
            end

            local order = vgui.Create("DButton", row)
            order:Dock(RIGHT)
            order:SetWide(66 * scale)
            order:SetText("Order")
            order:SetFont(Omerta.HUD.Font("small"))
            order:SetTextColor(COLOURS.paper)
            order.Paint = function(self, w, h)
                surface.SetDrawColor(self:IsHovered() and COLOURS.line or Color(38, 35, 32))
                surface.DrawRect(0, 2, w, h - 4)
            end
            order.DoClick = function()
                Omerta.Net.Request("procure.order", { entry = entry.index, quantity = 1 })
            end
        end
    end

    frame:Rebuild()
    frame.OnRemove = function() frame = nil end
end

concommand.Add("omerta_treasury", function()
    Omerta.Net.Request("treasury.open", {})
end)
