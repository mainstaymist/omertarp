-- The counter, from the customer's side of it.
--
-- What appears here depends entirely on who you are: a customer sees a menu,
-- somebody on the books sees the state of the place, and whoever handles the
-- money sees the register. The server decides which; this file only draws what
-- it was sent.

local state = { business = 0, name = "", role = 0, is_open = false, till = 0, staffed = false }
local menu = { items = {}, receiving = nil }
local frame = nil

local ROLE_CUSTOMER, ROLE_STAFF, ROLE_MANAGER = 0, 1, 2

local COLOURS = {
    paper   = Color(232, 226, 210),
    muted   = Color(140, 132, 122),
    panel   = Color(20, 19, 18, 244),
    line    = Color(70, 64, 56),
    warning = Color(178, 96, 84),
    good    = Color(150, 170, 140),
}

hook.Add("Omerta.BusinessState", "omerta.business.state", function(payload)
    state = payload
    if IsValid(frame) then frame:Rebuild() else Omerta.Business.Show() end
end)

hook.Add("Omerta.BusinessMenu", "omerta.business.menu", function(payload)
    menu.receiving = menu.receiving or {}
    local def = Omerta.Items.GetByIndex(payload.item)
    if def then
        menu.receiving[#menu.receiving + 1] = {
            def = def, price = payload.price, stock = payload.stock,
        }
    end
    if payload.last then
        menu.items = menu.receiving
        menu.receiving = nil
        if IsValid(frame) then frame:Rebuild() end
    end
end)

-- A rumour arrives as one line and is never written down anywhere you can go
-- back to. Remembering it is your job (D-031).
hook.Add("Omerta.RumourHeard", "omerta.business.rumour", function(text)
    chat.AddText(COLOURS.muted, "You hear: ", COLOURS.paper, text)
end)

local function act(action, target)
    Omerta.Net.Request("business.action", { action = action, target = target or 0 })
end

function Omerta.Business.Show()
    if IsValid(frame) then frame:Remove() end
    local scale = Omerta.HUD.Scale()

    frame = vgui.Create("DFrame")
    frame:SetSize(math.min(ScrW() * 0.5, 480 * scale), math.min(ScrH() * 0.6, 440 * scale))
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
    header:SetTall(52 * scale)
    header:DockMargin(14 * scale, 6 * scale, 14 * scale, 4 * scale)
    header.Paint = function(_, w, h)
        draw.SimpleText(state.name, Omerta.HUD.Font("body"), 0, 0,
            COLOURS.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        local line = state.is_open and "Open" or "Closed"
        if state.is_open and not state.staffed then
            line = "Open, but nobody is behind the counter"
        end
        draw.SimpleText(line, Omerta.HUD.Font("small"), 0, 26 * scale,
            state.is_open and (state.staffed and COLOURS.good or COLOURS.warning)
                or COLOURS.muted,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        -- Only the people who handle the money are told what is in the till.
        if state.role >= ROLE_MANAGER then
            draw.SimpleText("Register: " .. Omerta.Money.Format(state.till),
                Omerta.HUD.Font("small"), w, 26 * scale,
                COLOURS.paper, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        end
        surface.SetDrawColor(COLOURS.line)
        surface.DrawRect(0, h - 1, w, 1)
    end

    local function button(parent, label, fn, dock)
        local btn = vgui.Create("DButton", parent)
        btn:SetText(label)
        btn:SetFont(Omerta.HUD.Font("label"))
        btn:SetTextColor(COLOURS.paper)
        btn:Dock(dock or TOP)
        btn:DockMargin(0, 4 * scale, 0, 0)
        btn:SetTall(26 * scale)
        btn.Paint = function(self, w, h)
            surface.SetDrawColor(self:IsHovered() and COLOURS.line or Color(38, 35, 32))
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(COLOURS.line)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end
        btn.DoClick = fn
        return btn
    end

    local body = vgui.Create("DScrollPanel", frame)
    body:Dock(FILL)
    body:DockMargin(14 * scale, 0, 14 * scale, 10 * scale)

    function frame:Rebuild()
        body:Clear()

        for _, entry in ipairs(menu.items) do
            local row = vgui.Create("DPanel", body)
            row:Dock(TOP)
            row:SetTall(28 * scale)
            row.Paint = function(_, w, h)
                draw.SimpleText(entry.def.name, Omerta.HUD.Font("label"), 0, 5,
                    entry.stock > 0 and COLOURS.paper or COLOURS.muted,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                draw.SimpleText(entry.stock > 0 and (entry.stock .. " left") or "none left",
                    Omerta.HUD.Font("small"), w * 0.55, 7,
                    COLOURS.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                draw.SimpleText(Omerta.Money.Format(entry.price), Omerta.HUD.Font("label"),
                    w - 66 * scale, 5, COLOURS.paper, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
            end

            if entry.stock > 0 and state.is_open and state.staffed then
                local buy = vgui.Create("DButton", row)
                buy:Dock(RIGHT)
                buy:SetWide(58 * scale)
                buy:SetText("Buy")
                buy:SetFont(Omerta.HUD.Font("small"))
                buy:SetTextColor(COLOURS.paper)
                buy.Paint = function(self, w, h)
                    surface.SetDrawColor(self:IsHovered() and COLOURS.line or Color(38, 35, 32))
                    surface.DrawRect(0, 2, w, h - 4)
                end
                buy.DoClick = function()
                    Omerta.Net.Request("business.buy", {
                        item = Omerta.Items.IndexOf(entry.def.id) or 0, quantity = 1,
                    })
                end
            end
        end

        -- Anybody can ask what is going around; it costs money and the barman
        -- has to be there.
        button(body, "Ask what's going around", function()
            act(Omerta.Business.ACTION.LISTEN)
        end)

        local plant = vgui.Create("DTextEntry", body)
        plant:Dock(TOP)
        plant:DockMargin(0, 4 * scale, 0, 0)
        plant:SetTall(26 * scale)
        plant:SetPlaceholderText("...and tell him something")
        plant.OnEnter = function(self)
            local text = self:GetValue()
            if text and #text > 0 then
                Omerta.Net.Request("rumour.plant", { text = text })
                self:SetValue("")
            end
        end

        if state.role >= ROLE_STAFF then
            button(body, state.is_open and "Close Up" or "Open Up", function()
                act(Omerta.Business.ACTION.TOGGLE)
            end)
        end
        if state.role >= ROLE_MANAGER then
            button(body, "Empty the Register", function()
                act(Omerta.Business.ACTION.COLLECT)
            end)
        end
    end

    frame:Rebuild()
    frame.OnRemove = function() frame = nil end
end

Omerta.HUD.RegisterInteractableClass("omerta_business")
