-- The telephone, from the caller's side.
--
-- A dial pad when the receiver is up, a ringing cue when something near you
-- rings, and a line of text for the half of the conversation you can hear.
-- Nothing persistent: put the receiver down and the screen is empty again.

local state = { state = 0, number = "", seconds = 0, incoming = false }
local ringingUntil = 0
local heard = {}
local frame = nil

local COLOURS = {
    paper   = Color(232, 226, 210),
    muted   = Color(140, 132, 122),
    panel   = Color(20, 19, 18, 244),
    line    = Color(70, 64, 56),
    warning = Color(178, 96, 84),
}

local OFF_HOOK = 3

hook.Add("Omerta.PhoneState", "omerta.phone.state", function(payload)
    state = payload
    if state.state == 0 then
        if IsValid(frame) then frame:Remove() end
        heard = {}
        return
    end
    if IsValid(frame) then frame:Rebuild() else Omerta.Phone.Show() end
end)

hook.Add("Omerta.PhoneRinging", "omerta.phone.ring", function()
    ringingUntil = CurTime() + 3
    -- Tech §8: every audio cue has a visual one, and the visual one is not
    -- optional for a player who cannot hear the bell.
    Omerta.HUD.Cue("A telephone is ringing.", 3)
end)

hook.Add("Omerta.PhoneHeard", "omerta.phone.heard", function(number, text)
    heard[#heard + 1] = { number = number, text = text, at = CurTime() }
    if #heard > 12 then table.remove(heard, 1) end
    if IsValid(frame) then frame:Rebuild() end
end)

--------------------------------------------------------------------------------
-- The handset
--------------------------------------------------------------------------------

local function act(action)
    Omerta.Net.Request("phone.action", { action = action })
end

function Omerta.Phone.Show()
    if IsValid(frame) then frame:Remove() end
    local scale = Omerta.HUD.Scale()

    frame = vgui.Create("DFrame")
    frame:SetSize(math.min(ScrW() * 0.4, 380 * scale), math.min(ScrH() * 0.55, 400 * scale))
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
        local title, subtitle
        if state.state == OFF_HOOK then
            title = "Telephone"
            -- The number painted on the box: the one number a handset tells
            -- you, so somebody can call you back here (D-027).
            subtitle = "This line is " .. state.number
        elseif state.state == 1 then
            title = state.incoming and "Ringing" or "Calling " .. state.number
            subtitle = state.incoming and "Pick up, or leave it." or "It is ringing."
        elseif state.state == 2 then
            title = "Connected — " .. state.number
            subtitle = state.seconds > 0
                and (state.seconds .. " seconds of credit left")
                or "No credit — feed it a quarter."
        end
        draw.SimpleText(title or "", Omerta.HUD.Font("body"), 0, 0,
            COLOURS.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(subtitle or "", Omerta.HUD.Font("small"), 0, 26 * scale,
            (state.state == 2 and state.seconds > 0 and state.seconds < 15)
                and COLOURS.warning or COLOURS.muted,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        surface.SetDrawColor(COLOURS.line)
        surface.DrawRect(0, h - 1, w, 1)
    end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockMargin(14 * scale, 4 * scale, 14 * scale, 10 * scale)
    body.Paint = nil

    local function button(parent, label, fn, dock)
        local btn = vgui.Create("DButton", parent)
        btn:SetText(label)
        btn:SetFont(Omerta.HUD.Font("label"))
        btn:SetTextColor(COLOURS.paper)
        btn:Dock(dock or TOP)
        btn:DockMargin(0, 4 * scale, 0, 0)
        btn:SetTall(28 * scale)
        btn.Paint = function(self, w, h)
            surface.SetDrawColor(self:IsHovered() and COLOURS.line or Color(38, 35, 32))
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(COLOURS.line)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end
        btn.DoClick = fn
        return btn
    end

    function frame:Rebuild()
        body:Clear()

        if state.state == OFF_HOOK then
            -- No directory, no autocomplete, no recent calls (D-027). You dial
            -- a number you know, or you put the receiver down.
            local entry = vgui.Create("DTextEntry", body)
            entry:Dock(TOP)
            entry:SetTall(30 * scale)
            entry:SetPlaceholderText("number")
            entry:SetNumeric(true)
            entry:RequestFocus()

            local function dial()
                local number = entry:GetValue()
                if number and #number > 0 then
                    Omerta.Net.Request("phone.dial", { number = number })
                end
            end
            entry.OnEnter = dial
            button(body, "Dial", dial)
            button(body, "Hang Up", function() act(2) end)
            return
        end

        if state.state == 1 and state.incoming then
            button(body, "Answer", function() act(1) end)
        end
        if state.state == 2 then
            button(body, "Feed a Quarter", function() act(3) end)

            local said = vgui.Create("DTextEntry", body)
            said:Dock(TOP)
            said:DockMargin(0, 8 * scale, 0, 0)
            said:SetTall(28 * scale)
            said:SetPlaceholderText("say something")
            said.OnEnter = function(self)
                local text = self:GetValue()
                if text and #text > 0 then
                    Omerta.Net.Request("phone.say", { text = text })
                    self:SetValue("")
                end
            end

            local log = vgui.Create("DScrollPanel", body)
            log:Dock(FILL)
            log:DockMargin(0, 8 * scale, 0, 0)
            for _, entry in ipairs(heard) do
                local row = vgui.Create("DPanel", log)
                row:Dock(TOP)
                row:SetTall(20 * scale)
                row.Paint = function(_, w, h)
                    draw.SimpleText(entry.text, Omerta.HUD.Font("small"), 0, 3,
                        COLOURS.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                end
            end
        end
        button(body, "Hang Up", function() act(2) end)
    end

    frame:Rebuild()
    frame.OnRemove = function() frame = nil end
end

--------------------------------------------------------------------------------
-- The bell
--------------------------------------------------------------------------------
-- Contextual, like everything else: it is on screen while a telephone near you
-- is actually ringing, and gone the moment it stops.

Omerta.HUD.Register("phone.ringing", {
    order = 35,
    fade = 0.2,
    visible = function() return CurTime() < ringingUntil end,
    draw = function(alpha)
        draw.SimpleText("A telephone is ringing", Omerta.HUD.Font("label"),
            ScrW() * 0.5, ScrH() * 0.70,
            Color(235, 230, 215, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end,
})

-- D-017's dot lights up for a handset worth walking to.
Omerta.HUD.RegisterInteractableClass("omerta_phone")
