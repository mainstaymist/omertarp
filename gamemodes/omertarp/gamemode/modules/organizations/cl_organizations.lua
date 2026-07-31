-- Client side of institutions: the offer of membership, and the roster for
-- those senior enough to read one.
--
-- The client is told its OWN membership and nothing else. There is no list of
-- who is in which family, no colour on anyone's name, and no way to ask —
-- unless your rank earns you the books (§4b).

local Internal = Omerta.Organizations.Internal

local self_ = { org = 0, rank = 0, perms = 0 }
local offer = nil
local roster = { entries = {}, receiving = nil }
local frame = nil

--------------------------------------------------------------------------------
-- What we are
--------------------------------------------------------------------------------

hook.Add("Omerta.MembershipUpdated", "omerta.organizations.self", function(org, rank, perms)
    self_ = { org = org, rank = rank, perms = perms }
    -- Revealed, not IsValid: a window that is sinking out is on its way to
    -- being gone and refilling it puts fresh rows into something the player has
    -- already dismissed.
    if Omerta.HUD.Revealed(frame) then frame:Rebuild() end
end)

function Omerta.Organizations.Membership()
    if self_.org == 0 then return nil end
    local def = Omerta.Organizations.GetByIndex(self_.org)
    if not def then return nil end
    return {
        definition = def,
        rank = self_.rank,
        rung = Omerta.Organizations.RankAt(def.ladder, self_.rank),
    }
end

-- Mirrors the server's own question, for greying out a button. The server
-- re-checks everything regardless of what this returns.
function Omerta.Organizations.Holds(permission)
    for i, key in ipairs(Omerta.Organizations.PERMISSION_ORDER) do
        if key == permission then
            return math.floor(self_.perms / 2 ^ (i - 1)) % 2 == 1
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Being offered a place
--------------------------------------------------------------------------------

hook.Add("Omerta.MembershipOffered", "omerta.organizations.offer", function(from, org, name)
    local def = Omerta.Organizations.GetByIndex(org)
    if not def then return end
    offer = { from = from, name = name, org = def, expires = CurTime() + 60 }
end)

Omerta.HUD.Register("organizations.offer", {
    order = 45,
    fade = 0.25,
    visible = function()
        if offer and CurTime() > offer.expires then offer = nil end
        return offer ~= nil
    end,
    draw = function(alpha)
        if not offer then return end
        local scale = Omerta.HUD.Scale()
        local x, y = ScrW() * 0.5, ScrH() * 0.62
        draw.SimpleText(offer.name .. " offers you a place in the " .. offer.org.name .. ".",
            Omerta.HUD.Font("body"), x, y,
            Color(235, 230, 215, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText("[E] accept    [R] decline", Omerta.HUD.Font("label"),
            x, y + 26 * scale, Color(180, 180, 180, 220 * alpha),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end,
})

hook.Add("PlayerBindPress", "omerta.organizations.offer_reply", function(_, bind, pressed)
    if not offer or not pressed then return end
    local accept
    if bind == "+use" then accept = true
    elseif bind == "+reload" then accept = false
    else return end

    Omerta.Net.Request("org.invite_reply", { accept = accept })
    offer = nil
    return true -- swallow it so it does not also use or reload
end)

--------------------------------------------------------------------------------
-- The books
--------------------------------------------------------------------------------

hook.Add("Omerta.RosterEntry", "omerta.organizations.roster", function(payload)
    if not roster.receiving then
        roster.receiving = {}
    end
    roster.receiving[#roster.receiving + 1] = payload
    if payload.last then
        roster.entries = roster.receiving
        roster.receiving = nil
        if Omerta.HUD.Revealed(frame) then frame:Rebuild() end
    end
end)

local COLOURS = {
    paper = Color(232, 226, 210),
    muted = Color(140, 132, 122),
    panel = Color(20, 19, 18, 242),
    line  = Color(70, 64, 56),
}

function Omerta.Organizations.Show()
    local membership = Omerta.Organizations.Membership()
    if not membership then
        chat.AddText(COLOURS.muted, "You belong to nothing.")
        return
    end
    -- Remove, not Close: the window is being replaced, not dismissed.
    if IsValid(frame) then frame:Remove() end

    local scale = Omerta.HUD.Scale()
    frame = vgui.Create("DFrame")
    frame:SetSize(math.min(ScrW() * 0.5, 460 * scale), math.min(ScrH() * 0.6, 420 * scale))
    frame:Center()
    frame:SetTitle("")
    frame:MakePopup()
    frame.Paint = function(_, w, h)
        draw.RoundedBox(4, 0, 0, w, h, COLOURS.panel)
        surface.SetDrawColor(COLOURS.line)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    -- The books rise into place and sink back out, and the corner close button
    -- plays the way out because :Close() routes through the reveal.
    Omerta.HUD.Reveal(frame)

    local header = vgui.Create("DPanel", frame)
    header:Dock(TOP)
    header:SetTall(46 * scale)
    header:DockMargin(12 * scale, 4 * scale, 12 * scale, 4 * scale)
    header.Paint = function(_, w, h)
        local m = Omerta.Organizations.Membership()
        if not m then return end
        draw.SimpleText(m.definition.name, Omerta.HUD.Font("body"), 0, 2,
            COLOURS.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(m.rung and m.rung.name or "?", Omerta.HUD.Font("label"),
            0, 24 * scale, COLOURS.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        surface.SetDrawColor(COLOURS.line)
        surface.DrawRect(0, h - 1, w, 1)
    end

    local body = vgui.Create("DScrollPanel", frame)
    body:Dock(FILL)
    body:DockMargin(12 * scale, 0, 12 * scale, 10 * scale)

    function frame:Rebuild()
        body:Clear()
        local m = Omerta.Organizations.Membership()
        if not m then return end

        if not Omerta.Organizations.Holds(Omerta.Organizations.PERMISSIONS.ROSTER) then
            local note = vgui.Create("DPanel", body)
            note:Dock(TOP)
            note:SetTall(48 * scale)
            note.Paint = function(_, w, h)
                -- Not an error. Most members are not supposed to know.
                draw.SimpleText("You know the people you have met.",
                    Omerta.HUD.Font("label"), 0, h * 0.5 - 8 * scale,
                    COLOURS.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end
            return
        end

        for _, entry in ipairs(roster.entries) do
            local row = vgui.Create("DPanel", body)
            row:Dock(TOP)
            row:SetTall(24 * scale)
            row.Paint = function(_, w, h)
                local rung = Omerta.Organizations.RankAt(m.definition.ladder, entry.rank)
                draw.SimpleText(entry.name, Omerta.HUD.Font("label"), 0, 2,
                    entry.online and COLOURS.paper or COLOURS.muted,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                draw.SimpleText(rung and rung.name or "?", Omerta.HUD.Font("small"), w, 4,
                    COLOURS.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
            end
        end
    end

    frame:Rebuild()
    if Omerta.Organizations.Holds(Omerta.Organizations.PERMISSIONS.ROSTER) then
        Omerta.Net.Request("org.roster_request", {})
    end
    frame.OnRemove = function() frame = nil end
end

concommand.Add("omerta_organization", function() Omerta.Organizations.Show() end)
