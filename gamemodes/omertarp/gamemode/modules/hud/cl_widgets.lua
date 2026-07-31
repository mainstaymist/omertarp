-- The widget kit: the controls every window is built FROM, in the style
-- guide's own construction (docs/design/style-guide, direction 1a).
--
-- sh_theme says what the interface looks like; this file says how a button, a
-- text input, a picker and a context menu are CONSTRUCTED — once. A new screen
-- composes these and inherits the standard; a screen that hand-rolls a button
-- is the drift Track E's standardization pass exists to catch.
--
-- The guide's construction rules, written down rather than remembered:
--   * Square corners, 1px rules, the 4px grid. Nothing else exists.
--   * COMMIT buttons fill with bone (#EEEAE1) and speak ink, in Oswald caps —
--     "STEP INTO THE CITY". Quiet buttons are a 1px rule box with secondary
--     caps. Danger is never a fill at this size; it is #8E2B22 text, last in
--     the list, under a rule, so the hand has to travel to reach it.
--   * SELECTION is the brass inversion: #C8A96A fill, ink text. It marks the
--     one thing under the cursor and appears nowhere else.
--   * Text inputs are a bare bottom rule — brass while focused — with the
--     mono voice as their label. No boxes around text.

Omerta.HUD = Omerta.HUD or {}

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------
-- style: "commit" (bone fill, ink Oswald caps) or "quiet" (rule box,
-- secondary Oswald caps). Old names accepted so call sites read naturally:
-- "primary" = commit, "ghost" = quiet.

function Omerta.HUD.Button(parent, label, style, onClick)
    style = (style == "primary" or style == "commit") and "commit" or "quiet"
    local button = vgui.Create("DButton", parent)
    button:SetText("")
    button.OmertaLabel = string.upper(label or "")
    button.DoClick = function()
        surface.PlaySound("omertarp/ui/inventory-click.wav")
        if onClick then onClick() end
    end
    button.Paint = function(self, w, h)
        local text
        if style == "commit" then
            local fill = self:IsEnabled() and "text" or "secondary"
            surface.SetDrawColor(Omerta.HUD.Colour(fill, self:IsHovered() and 255 or 235))
            surface.DrawRect(0, 0, w, h)
            text = Omerta.HUD.Colour("ink")
        else
            if self:IsHovered() then
                surface.SetDrawColor(Omerta.HUD.Colour("brass",
                    Omerta.HUD.Theme.ALPHA.wash * 255))
                surface.DrawRect(0, 0, w, h)
            end
            surface.SetDrawColor(Omerta.HUD.Colour("rule"))
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            text = Omerta.HUD.Colour(self:IsHovered() and "text" or "secondary")
        end
        draw.SimpleText(self.OmertaLabel, Omerta.HUD.Font("verb"),
            w * 0.5, h * 0.5, text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    function button:SetLabel(text) self.OmertaLabel = string.upper(text or "") end
    return button
end

--------------------------------------------------------------------------------
-- Text inputs
--------------------------------------------------------------------------------
-- The guide's field: value over a bare bottom rule, brass while the field has
-- focus. No box, no fill.

function Omerta.HUD.TextEntry(parent)
    local entry = vgui.Create("DTextEntry", parent)
    entry:SetFont(Omerta.HUD.Font("subject"))
    entry:SetPaintBackground(false)
    entry:SetTextColor(Omerta.HUD.Colour("text"))
    entry:SetCursorColor(Omerta.HUD.Colour("text"))
    entry:SetHighlightColor(Omerta.HUD.Colour("rule"))
    entry:SetPlaceholderColor(Omerta.HUD.Colour("dim"))
    entry.Paint = function(self, w, h)
        surface.SetDrawColor(Omerta.HUD.Colour(self:HasFocus() and "brass" or "rule"))
        surface.DrawRect(0, h - 1, w, 1)
        self:DrawTextEntryText(Omerta.HUD.Colour("text"),
            Omerta.HUD.Colour("brass"), Omerta.HUD.Colour("text"))
    end
    return entry
end

-- The mono system voice above an input: "GIVEN NAME". Always caps.
function Omerta.HUD.FieldLabel(parent, text)
    local label = vgui.Create("DPanel", parent)
    label.OmertaText = string.upper(text or "")
    label.Paint = function(self, w, h)
        draw.SimpleText(self.OmertaText, Omerta.HUD.Font("mono"), 0, h,
            Omerta.HUD.Colour("dim"), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    end
    return label
end

--------------------------------------------------------------------------------
-- The cycler
--------------------------------------------------------------------------------
-- One value showing, arrows either side, over the same bottom rule an input
-- uses. Chosen over a dropdown deliberately — the engine's DComboBox opens a
-- stock Derma menu that cannot be fully skinned, and a half-styled control is
-- worse than a differently-shaped styled one.

function Omerta.HUD.Cycler(parent, items, index, onChange)
    local scale = Omerta.HUD.Scale()
    local panel = vgui.Create("DPanel", parent)
    index = math.Clamp(index or 1, 1, math.max(1, #items))

    panel.Paint = function(_, w, h)
        surface.SetDrawColor(Omerta.HUD.Colour("rule"))
        surface.DrawRect(0, h - 1, w, 1)
        local item = items[index]
        draw.SimpleText(item and item.label or "", Omerta.HUD.Font("label"),
            w * 0.5, h * 0.5, Omerta.HUD.Colour("text"),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local function step(delta)
        if #items == 0 then return end
        index = ((index - 1 + delta) % #items) + 1
        surface.PlaySound("omertarp/ui/inventory-click.wav")
        if onChange then onChange(items[index], index) end
    end

    local function arrow(glyph, side, delta)
        local button = vgui.Create("DButton", panel)
        button:Dock(side)
        button:SetWide(36 * scale)
        button:SetText("")
        button.DoClick = function() step(delta) end
        button.Paint = function(self, w, h)
            if self:IsHovered() then
                surface.SetDrawColor(Omerta.HUD.Colour("brass",
                    Omerta.HUD.Theme.ALPHA.wash * 255))
                surface.DrawRect(0, 0, w, h)
            end
            draw.SimpleText(glyph, Omerta.HUD.Font("label"), w * 0.5, h * 0.5,
                Omerta.HUD.Colour(self:IsHovered() and "text" or "secondary"),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    arrow("<", LEFT, -1)
    arrow(">", RIGHT, 1)

    function panel:GetSelected() return items[index], index end
    return panel
end

--------------------------------------------------------------------------------
-- Prose choices
--------------------------------------------------------------------------------
-- The guide's life-path list: stacked options, each a title and a line of
-- prose, the chosen one inverted in brass. A radio group that reads like a
-- paragraph, not a form.

function Omerta.HUD.ProseList(parent, items, index, onChange)
    local scale = Omerta.HUD.Scale()
    local panel = vgui.Create("DPanel", parent)
    panel.Paint = nil
    index = math.Clamp(index or 1, 1, math.max(1, #items))

    for i, item in ipairs(items) do
        local row = vgui.Create("DButton", panel)
        row:Dock(TOP)
        row:SetTall(52 * scale)
        row:SetText("")
        row.Paint = function(self, w, h)
            local chosen = i == index
            if chosen then
                surface.SetDrawColor(Omerta.HUD.Colour("brass"))
                surface.DrawRect(0, 0, w, h)
            elseif self:IsHovered() then
                surface.SetDrawColor(Omerta.HUD.Colour("brass",
                    Omerta.HUD.Theme.ALPHA.wash * 255))
                surface.DrawRect(0, 0, w, h)
            end
            if i > 1 and not chosen then
                surface.SetDrawColor(Omerta.HUD.Colour("ruleFaint"))
                surface.DrawRect(0, 0, w, 1)
            end
            local pad = 14 * scale
            draw.SimpleText(item.label, Omerta.HUD.Font("label"), pad, 8 * scale,
                Omerta.HUD.Colour(chosen and "ink" or "text"),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            if item.detail then
                draw.SimpleText(item.detail, Omerta.HUD.Font("small"), pad, h - 8 * scale,
                    chosen and Omerta.HUD.Colour("ink", 175) or Omerta.HUD.Colour("dim"),
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
            end
        end
        row.DoClick = function()
            index = i
            surface.PlaySound("omertarp/ui/inventory-click.wav")
            if onChange then onChange(item, i) end
        end
    end

    panel:SetTall(#items * 52 * scale)
    function panel:GetSelected() return items[index], index end
    return panel
end

--------------------------------------------------------------------------------
-- Context menus
--------------------------------------------------------------------------------
-- The guide's item menu (§10): near-opaque ink plate, mono header naming the
-- item, options in text type, the hovered one inverted in brass, destructive
-- verbs alone under a rule in #8E2B22, always last.

function Omerta.HUD.Menu()
    local scale = Omerta.HUD.Scale()
    local menu = DermaMenu()
    menu:SetMinimumWidth(176 * scale)
    menu.Paint = function(_, w, h)
        surface.SetDrawColor(Omerta.HUD.Colour("plate",
            Omerta.HUD.Theme.ALPHA.menu * 255))
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(Omerta.HUD.Colour("rule"))
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
    return menu
end

-- The mono header row: what this menu is about. Not selectable.
function Omerta.HUD.MenuHeader(menu, text)
    local scale = Omerta.HUD.Scale()
    local header = vgui.Create("DPanel", menu)
    header:SetTall(30 * scale)
    header.OmertaText = string.upper(text or "")
    header.Paint = function(self, w, h)
        draw.SimpleText(self.OmertaText, Omerta.HUD.Font("mono"),
            14 * scale, h * 0.5, Omerta.HUD.Colour("dim"),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetDrawColor(Omerta.HUD.Colour("ruleFaint"))
        surface.DrawRect(0, h - 1, w, 1)
    end
    menu:AddPanel(header)
    return header
end

function Omerta.HUD.MenuDivider(menu)
    local divider = vgui.Create("DPanel", menu)
    divider:SetTall(1)
    divider.Paint = function(_, w, h)
        surface.SetDrawColor(Omerta.HUD.Colour("ruleFaint"))
        surface.DrawRect(0, 0, w, h)
    end
    menu:AddPanel(divider)
    return divider
end

-- opts.danger marks the irreversible: #8E2B22 text, never inverted.
function Omerta.HUD.MenuOption(menu, label, onSelect, opts)
    opts = opts or {}
    local option = menu:AddOption(label, onSelect)
    option:SetFont(Omerta.HUD.Font("label"))
    option.Paint = function(self, w, h)
        local hovered = self:IsHovered()
        if hovered and not opts.danger then
            surface.SetDrawColor(Omerta.HUD.Colour("brass"))
            surface.DrawRect(0, 0, w, h)
            self:SetTextColor(Omerta.HUD.Colour("ink"))
        elseif opts.danger then
            if hovered then
                surface.SetDrawColor(Omerta.HUD.Colour("danger", 40))
                surface.DrawRect(0, 0, w, h)
            end
            self:SetTextColor(Omerta.HUD.Colour("danger",
                hovered and 255 or 220))
        else
            self:SetTextColor(Omerta.HUD.Colour("text"))
        end
    end
    return option
end
