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
-- The reveal
--------------------------------------------------------------------------------
-- Everything that pops up rises into place and sinks back out. ONE
-- implementation of it, installed on any panel with one line:
--
--     Omerta.HUD.Reveal(frame)
--
-- and dismissed with frame:Close(), which now plays the animation out and
-- removes the panel when it has finished rather than removing it immediately.
--
-- The curve, the two durations and the distance are in sh_hud.lua, where the
-- headless suite can reach them; this is the panel plumbing that drives them.
--
-- WHY IT WRAPS THE PANEL'S OWN PAINT AND THINK rather than owning them. This
-- was a private copy inside the inventory window for a while and it is now on
-- every window in the game; if installing it meant "and rewrite your Paint to
-- multiply every alpha by an eased value" then it would be a rewrite per
-- window, an opportunity per window to miss one draw call, and the next window
-- anybody adds would quietly not animate at all. A call site adds a line and
-- its existing paint code is untouched. The order that follows from that:
-- INSTALL LAST, after Paint and Think are set, because a Paint assigned
-- afterwards replaces the wrapper rather than being wrapped by it.
--
-- WHY THE FADE IS SetAlpha AND NOT AN ALPHA MULTIPLIER AROUND THE PAINT. A
-- panel's alpha cascades to its children through PaintTraverse, so one call
-- fades the window, its rows, its buttons and its text inputs together —
-- exactly what is wanted, and unreachable from a Paint wrapper, which can only
-- reach the panel's own drawing. A window whose plate faded while its rows
-- stayed solid was the first attempt at this and it looked broken.
--
-- WHY THE POSITION IS SET EVERY FRAME instead of being tweened: see the note in
-- sh_hud.lua. Several of these windows re-lay-out and re-centre themselves
-- while they are on screen, and a tween walks toward a coordinate the layout
-- has already abandoned. The cost of recomputing is that the panel must be told
-- where it now RESTS whenever a layout moves it — Panel:OmertaAnchor.
--
-- opts.rise overrides the travel in design pixels; opts.rise = 0 is a fade with
-- no movement, which is the honest answer for a panel that covers the whole
-- screen (see cl_menu.lua) — sliding one exposes a band of bare screen along
-- the edge it moved away from.

function Omerta.HUD.Reveal(panel, opts)
    if not IsValid(panel) then return panel end
    opts = opts or {}

    panel.OmertaAnim = 0        -- 0..1, the raw position
    panel.OmertaEased = 0       -- the smoothstepped one, for the panel's Paint
    panel.OmertaClosing = false
    panel.OmertaRise = (opts.rise or Omerta.HUD.REVEAL.RISE) * Omerta.HUD.Scale()
    panel.OmertaRestY = panel:GetY()

    -- Where the panel rests once it has finished rising. Captured here from
    -- wherever the call site has just placed it, and re-captured by whoever
    -- moves it afterwards — CALL THIS ONLY WHEN THE PANEL IS AT REST (straight
    -- after a Center() or a SetPos), never mid-animation, or the current offset
    -- is read as part of the resting place and every rebuild compounds it.
    function panel:OmertaAnchor()
        self.OmertaRestY = self:GetY()
        self:SetPos(self:GetX(), self.OmertaRestY
            + Omerta.HUD.RevealOffset(self.OmertaEased, self.OmertaRise))
    end

    -- Closing is a REQUEST, not a removal: the panel takes itself off screen
    -- once it has finished sinking. Idempotent, because a window can be
    -- dismissed twice in the tenth of a second it spends leaving — a click on
    -- the close button and the key that also closes it, say — and the second
    -- request must not restart the clock.
    function panel:OmertaClose()
        if self.OmertaClosing then return end
        self.OmertaClosing = true
    end

    -- :Close() is Derma's word for "the user dismissed this", and it is what
    -- DFrame's own close button calls. Routing it here is what makes the
    -- animation impossible to skip by accident: a window gets the play-out
    -- without its author having thought about it, and the close button in the
    -- corner behaves like every other way out.
    --
    -- :Remove() is deliberately NOT routed. Instant teardown is a real need —
    -- a window being rebuilt from scratch, or one taken down because the
    -- character it belonged to has died — and it needs a word of its own.
    -- Remove means gone now; Close means leave.
    function panel:Close()
        if self.OnClose then self:OnClose() end
        self:OmertaClose()
    end

    local paint = panel.Paint
    panel.Paint = function(self, w, h)
        -- Nothing at all on the frame it is created: the panel exists, is laid
        -- out and is measured, but has not begun arriving yet. Without this the
        -- first frame of every window is a full-opacity flash, because Paint
        -- runs before the first Think.
        if (self.OmertaEased or 0) <= 0 then return end
        if paint then paint(self, w, h) end
    end

    -- Note what `panel.Think` and `panel.Paint` resolve to before they are
    -- overwritten: an instance override if the call site set one, otherwise the
    -- CLASS method off the metatable. DFrame's own Think is what makes a window
    -- draggable and sizeable, so capturing and calling it is not politeness —
    -- it is the difference between wrapping a frame and quietly disabling half
    -- of it.
    local think = panel.Think
    panel.Think = function(self)
        if think then think(self) end
        -- A wrapped Think that removed the panel leaves nothing to animate,
        -- and every line below would be a method call on a dead panel.
        if not IsValid(self) then return end

        local position, finished = Omerta.HUD.StepReveal(self.OmertaAnim,
            self.OmertaClosing, FrameTime())
        self.OmertaAnim = position
        self.OmertaEased = Omerta.HUD.RevealEase(position)

        if finished then self:Remove() return end

        self:SetAlpha(255 * self.OmertaEased)
        -- A panel with no travel is never repositioned AT ALL, rather than
        -- being repositioned to where it already is: a full-screen frame's
        -- position belongs to whoever sized it to the screen, and this has no
        -- business writing to it sixty times a second to say nothing.
        if self.OmertaRise > 0 then
            self:SetPos(self:GetX(), self.OmertaRestY
                + Omerta.HUD.RevealOffset(self.OmertaEased, self.OmertaRise))
        end
    end

    -- Invisible and already displaced on the frame it is born, so there is no
    -- single frame of the window sitting finished at its resting place before
    -- the animation starts. That flash is the whole thing this exists to stop.
    panel:SetAlpha(0)
    if panel.OmertaRise > 0 then
        panel:SetPos(panel:GetX(), panel.OmertaRestY + panel.OmertaRise)
    end

    return panel
end

-- Is this window UP — as opposed to absent, or on its way out?
--
-- The distinction matters everywhere a module asks "is my window open" to
-- decide whether to rebuild it or make a new one, because a sinking panel is
-- still IsValid for a tenth of a second after the player dismissed it.
-- Rebuilding one puts fresh contents into a window that is already leaving, and
-- the window the player asked for never appears at all.
-- There is a THIRD way to be gone, and it caught the inventory: a panel that
-- has been Remove()d is not destroyed where it stands. GMod marks it and
-- deletes it at the end of the frame — which is exactly why
-- Panel:IsMarkedForDeletion exists as a question separate from IsValid. Such a
-- panel is still IsValid, and never set OmertaClosing because nothing animated
-- it, so both tests above pass on a window that is already dead. Any module
-- that keeps a pointer to a panel it removed would be told the window is up.
function Omerta.HUD.Revealed(panel)
    if not IsValid(panel) then return false end
    if panel.OmertaClosing == true then return false end
    if panel.IsMarkedForDeletion and panel:IsMarkedForDeletion() then return false end
    return true
end

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
    panel:SetPaintBackground(false)
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
-- The rustle
--------------------------------------------------------------------------------
-- Going through pockets, cloth over cloth. One BASS channel, seeked to a
-- random stretch of the 30-second bed so no two rummages sound identical,
-- stopped the instant whatever needed it ends. Owned here because searching
-- bodies (injury) and looting (inventory) both play it, and two copies of a
-- sound player is how one of them keeps playing.

local rustle = { channel = nil, stopAt = 0 }

function Omerta.HUD.StopRustle()
    if rustle.channel and rustle.channel:IsValid() then
        rustle.channel:Stop()
    end
    rustle.channel = nil
end

function Omerta.HUD.Rustle(duration)
    Omerta.HUD.StopRustle()
    duration = duration or 4
    rustle.stopAt = CurTime() + duration
    -- "noplay": opened paused so it can be seeked before it makes a sound.
    -- (NOT "noblock" — that flag silently fails for disk files.)
    sound.PlayFile("sound/omertarp/ui/searching-rustle.wav", "noplay", function(channel)
        if not (channel and channel:IsValid()) then return end
        if CurTime() > rustle.stopAt then channel:Stop() return end
        local length = channel:GetLength() or 0
        if length > duration + 1 then
            channel:SetTime(math.Rand(0, length - duration - 0.5))
        end
        channel:SetVolume(0.6)
        channel:Play()
        rustle.channel = channel
    end)
end

hook.Add("Think", "omerta.hud.rustle", function()
    if rustle.channel and CurTime() > rustle.stopAt then Omerta.HUD.StopRustle() end
end)

--------------------------------------------------------------------------------
-- Context menus
--------------------------------------------------------------------------------
-- The guide's item menu (§10): near-opaque ink plate, mono header naming the
-- item, options in text type, the hovered one inverted in brass, destructive
-- verbs alone under a rule in #8E2B22, always last.

function Omerta.HUD.Menu()
    local scale = Omerta.HUD.Scale()
    local menu = DermaMenu()
    -- Wide enough that the verbs are not squeezed against their own edges;
    -- the first two attempts at this were both reported as too narrow.
    menu:SetMinimumWidth(260 * scale)
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

-- The height of one verb, before scale. Generous on purpose: this is a menu
-- opened with the mouse already moving, over a row the player is aiming at,
-- and every pixel of it is a pixel they do not have to be precise about.
Omerta.HUD.MENU_OPTION_H = 42

-- opts.danger marks the irreversible: #8E2B22 text, never inverted.
--
-- Built with AddPanel over a plain DButton rather than with menu:AddOption,
-- and that is the fix for a bug that survived two attempts to solve it by
-- raising a number. DMenuOption lays ITSELF out — it re-derives its height
-- from its font every time the menu invalidates, which is immediately after
-- construction — so SetTall on one is a value that gets thrown away before
-- anything is drawn. The options were reported as cramped, the number went
-- from stock to 36 to 42, and nothing changed on screen, because none of the
-- three was ever the height being used.
--
-- A panel added with AddPanel is not laid out by anything but us. It keeps the
-- height it is given, which is the only reason this control can be made to
-- match the standard at all.
function Omerta.HUD.MenuOption(menu, label, onSelect, opts)
    opts = opts or {}
    local scale = Omerta.HUD.Scale()
    local option = vgui.Create("DButton", menu)
    option:SetText("")
    option:SetTall(Omerta.HUD.MENU_OPTION_H * scale)
    option.OmertaLabel = label or ""
    -- DMenu sizes itself to the widest thing in it, so a long verb has to
    -- declare its own width or the minimum silently becomes a maximum and the
    -- word is cut off at the plate edge.
    surface.SetFont(Omerta.HUD.Font("label"))
    option:SetWide(surface.GetTextSize(option.OmertaLabel) + 36 * scale)
    option.DoClick = function()
        -- Closed BEFORE the verb runs. Several of these open another window
        -- (split, examine) and a menu still standing over it is a menu the
        -- player has to dismiss before they can use what they asked for.
        CloseDermaMenus()
        surface.PlaySound("omertarp/ui/inventory-click.wav")
        if onSelect then onSelect() end
    end
    option.Paint = function(self, w, h)
        local hovered = self:IsHovered()
        local colour
        if opts.danger then
            -- Never inverted. Selection is brass fill with ink type, and
            -- lighting up the one verb that cannot be undone in the same
            -- language as "examine" is how it gets clicked by accident.
            if hovered then
                surface.SetDrawColor(Omerta.HUD.Colour("danger", 40))
                surface.DrawRect(0, 0, w, h)
            end
            colour = Omerta.HUD.Colour("danger", hovered and 255 or 220)
        elseif hovered then
            surface.SetDrawColor(Omerta.HUD.Colour("brass"))
            surface.DrawRect(0, 0, w, h)
            colour = Omerta.HUD.Colour("ink")
        else
            colour = Omerta.HUD.Colour("text")
        end
        draw.SimpleText(self.OmertaLabel, Omerta.HUD.Font("label"),
            18 * scale, h * 0.5, colour, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    menu:AddPanel(option)
    return option
end
