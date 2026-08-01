-- Character creation UI and the D-011 portrait booth.
--
-- The form is a COMPONENT, not a window: Omerta.Characters.BuildCreationForm
-- builds the fields into whatever parent it is given, and the front-end menu
-- is where they normally live — creation is a screen OF the menu, over the
-- same drifting camera, in the same standard, rather than a floating box on
-- top of it. The full-screen fallback below exists only for a build without
-- the menu module, so M4 still works alone.
--
-- Everything visual comes from the design standard (sh_theme via cl_widgets):
-- Carbon text inputs, cyclers instead of stock dropdowns, one primary button.
--
-- The booth capture is the one genuinely fiddly part. A dedicated server has
-- no renderer, so the mugshot must be produced here and uploaded (D-011):
-- draw the character model to a known screen rectangle, capture that
-- rectangle as JPEG in a render hook, base64 it, and send.

local STATE = Omerta.Characters.STATE

local frame            -- the fallback window, when no menu owns the form
local pendingCapture   -- booth rectangle queued for capture on the next frame
local capturedPortrait -- base64 JPEG held until the character actually exists

local PORTRAIT_SIZE = 128
local PORTRAIT_QUALITY = 70

--------------------------------------------------------------------------------
-- Booth capture
--------------------------------------------------------------------------------

-- render.Capture reads the back buffer, so the model must be genuinely drawn
-- on screen at capture time. The booth panel is drawn normally by VGUI; we
-- capture its rectangle during PostRender, once, then upload.
local function requestCapture(panel)
    if pendingCapture then return end
    local x, y = panel:LocalToScreen(0, 0)
    pendingCapture = { x = x, y = y, w = panel:GetWide(), h = panel:GetTall() }
end

hook.Add("PostRender", "omerta.characters.portrait_capture", function()
    if not pendingCapture then return end
    local cap = pendingCapture
    pendingCapture = nil

    -- Square, centred on the booth, so the mugshot has consistent framing
    -- regardless of the player's resolution.
    local size = math.min(cap.w, cap.h)
    local ok, jpeg = pcall(render.Capture, {
        format = "jpeg",
        quality = PORTRAIT_QUALITY,
        x = math.floor(cap.x + (cap.w - size) * 0.5),
        y = math.floor(cap.y + (cap.h - size) * 0.5),
        w = size,
        h = size,
    })
    if not ok or not jpeg or jpeg == "" then
        Omerta.Log.Warn("characters", "portrait capture failed: %s", tostring(jpeg))
        return
    end

    -- Capture NOW (the booth is still on screen and will not be a moment
    -- later), but do not upload yet: creating a character costs the server two
    -- database round-trips, and an upload sent on this frame arrives before
    -- the character exists to attach it to. Held until the server confirms.
    capturedPortrait = util.Base64Encode(jpeg, true)
    -- Info, not debug: this fires exactly once per character, and it is the
    -- only client-side evidence that the booth produced an image at all.
    Omerta.Log.Info("characters", "portrait captured (%d bytes base64), awaiting character",
        #capturedPortrait)
end)

--------------------------------------------------------------------------------
-- The form
--------------------------------------------------------------------------------

-- Builds the creation form into `formParent` and the portrait booth into
-- `boothParent`, both supplied by whoever owns the screen. Laid out to the
-- guide's §11: mono field labels, the two names side by side over bare rules,
-- the life paths as PROSE (not stat blocks), one bone commit button, and the
-- permadeath warning as a plain sentence — the game does not raise its voice.
-- Returns { Focus = fn } so the owner can put the cursor in the first field.
function Omerta.Characters.BuildCreationForm(formParent, boothParent, opts)
    opts = opts or {}
    local scale = Omerta.HUD.Scale()
    local H = Omerta.HUD
    local fieldH, gap = 40 * scale, H.Space(4)

    -- The booth. This panel is also the portrait framing (D-011).
    local booth = vgui.Create("DModelPanel", boothParent)
    booth:Dock(FILL)
    booth:SetModel(Omerta.Characters.MODELS[1])
    booth:SetFOV(28)
    booth:SetCamPos(Vector(42, 0, 62))
    booth:SetLookAt(Vector(0, 0, 62)) -- head height: a mugshot, not a full body
    function booth:LayoutEntity() end -- no idle spin: the photo must be still

    -- GIVEN NAME · FAMILY NAME, side by side.
    local names = vgui.Create("DPanel", formParent)
    names:Dock(TOP)
    names:SetTall(fieldH + 26 * scale)
    names:DockMargin(0, gap, 0, 0)
    names:SetPaintBackground(false)

    local function nameField(side, caption)
        local half = vgui.Create("DPanel", names)
        half:Dock(side)
        half:SetPaintBackground(false)
        half.PerformLayout = function(self)
            self:SetWide((names:GetWide() - H.Space(4)) * 0.5)
        end
        local label = H.FieldLabel(half, caption)
        label:Dock(TOP)
        label:SetTall(22 * scale)
        local entry = H.TextEntry(half)
        entry:Dock(TOP)
        entry:SetTall(fieldH)
        entry:DockMargin(0, 4 * scale, 0, 0)
        return entry
    end
    -- "Last name", not "family name": in this game a Family is an institution
    -- you are sworn into, and a surname says nothing about which one.
    local firstEntry = nameField(LEFT, "Given name")
    local lastEntry = nameField(RIGHT, "Last name")

    -- Tab hops between the name boxes and wraps; the whole form is typeable
    -- end to end without touching the mouse.
    local fields = { firstEntry, lastEntry }
    for i, field in ipairs(fields) do
        local base = field.OnKeyCodeTyped
        field.OnKeyCodeTyped = function(self, key)
            if key == KEY_TAB then
                fields[(i % #fields) + 1]:RequestFocus()
                return true
            end
            if base then return base(self, key) end
        end
    end

    local function fieldLabel(text)
        local label = H.FieldLabel(formParent, text)
        label:Dock(TOP)
        label:SetTall(26 * scale)
        label:DockMargin(0, gap, 0, 4 * scale)
    end

    fieldLabel("Appearance")
    local models = {}
    for i in ipairs(Omerta.Characters.MODELS) do
        models[i] = { label = Omerta.Characters.ModelLabel(i), value = i }
    end
    local modelChoice = H.Cycler(formParent, models, 1, function(item)
        booth:SetModel(Omerta.Characters.MODELS[item.value]
            or Omerta.Characters.MODELS[1])
    end)
    modelChoice:Dock(TOP)
    modelChoice:SetTall(fieldH)

    fieldLabel("Path for this season")
    local pathChoice = H.ProseList(formParent, {
        { label = "Criminal", detail = "Eligible for family life. You cannot switch freely.", value = 1 },
        { label = "Police",   detail = "The department.", value = 2 },
        { label = "Independent", detail = "Civilian, business, trade.", value = 3 },
    }, 1)
    pathChoice:Dock(TOP)

    -- Server rejections and live validation both land here. The guide keeps
    -- red for marks, not sentences: refusals are bone text behind a 2px
    -- danger rule, acceptances are the name in brass.
    local status = vgui.Create("DPanel", formParent)
    status:Dock(TOP)
    status:SetTall(40 * scale)
    status:DockMargin(0, gap, 0, 0)
    status.OmertaText, status.OmertaBad = "", false
    status.Paint = function(self, w, h)
        if self.OmertaText == "" then return end
        local x = 0
        if self.OmertaBad then
            surface.SetDrawColor(H.Colour("danger"))
            surface.DrawRect(0, 4 * scale, 2, h - 8 * scale)
            x = 10 * scale
        end
        draw.SimpleText(self.OmertaText, H.Font("label"), x, h * 0.5,
            self.OmertaBad and H.Colour("text") or H.Colour("brass"),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- The commit row is docked to the BOTTOM of whatever column hosts the
    -- form, so it cannot be pushed off the screen by the fields above it —
    -- which is exactly how Confirm went missing at 1.5x. Back takes a third,
    -- Confirm the rest: the destructive-adjacent choice is the small one.
    local buttons = vgui.Create("DPanel", formParent)
    buttons:Dock(BOTTOM)
    buttons:SetTall(48 * scale)
    buttons:SetPaintBackground(false)

    local submit = H.Button(buttons, "Confirm", "commit")
    submit:Dock(FILL)

    if opts.onBack then
        local back = H.Button(buttons, "Back", "quiet", opts.onBack)
        back:Dock(LEFT)
        back:DockMargin(0, 0, H.Space(1), 0)
        back.PerformLayout = function(self)
            self:SetWide(buttons:GetWide() * 0.33)
        end
    end

    local warning = vgui.Create("DPanel", formParent)
    warning:Dock(BOTTOM)
    warning:SetTall(24 * scale)
    warning:DockMargin(0, gap, 0, 4 * scale)
    warning.Paint = function(_, w, h)
        draw.SimpleText("This character can die. There is no second copy.",
            H.Font("small"), 0, h * 0.5, H.Colour("dim"),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Live feedback using the same validator the server enforces. This is a
    -- courtesy only: the server revalidates everything on arrival.
    local function validate()
        local first, last = Omerta.Characters.ValidateName(
            firstEntry:GetValue(), lastEntry:GetValue())
        if not first then
            status.OmertaBad = true
            status.OmertaText = last or ""
            return nil
        end
        status.OmertaBad = false
        status.OmertaText = first .. " " .. last
        return first, last
    end
    firstEntry.OnChange = validate
    lastEntry.OnChange = validate

    local function reenable()
        if IsValid(submit) then
            submit:SetEnabled(true)
            submit:SetLabel("Confirm")
        end
    end

    -- What Confirm actually does, once the warning has been read and agreed.
    local function commit()
        local model = modelChoice:GetSelected()
        local path = pathChoice:GetSelected()
        submit:SetEnabled(false)
        submit:SetLabel("Creating…")
        -- The booth is still on screen; take the mugshot now, at creation,
        -- exactly once (D-011).
        requestCapture(booth)
        -- The black starts falling here rather than on the server's answer:
        -- the wait for two database round-trips is the least cinematic moment
        -- in the game, and the fade is where M28's opening will live.
        if Omerta.Menu and Omerta.Menu.BeginSpawnFade then
            Omerta.Menu.BeginSpawnFade()
        end
        Omerta.Net.Request("characters.create", {
            first = firstEntry:GetValue(),
            last = lastEntry:GetValue(),
            model = model and model.value or 1,
            skin = 0,
            path = path and path.value or 1,
        })
        timer.Simple(5, reenable)
    end

    submit.DoClick = function()
        local first, last = validate()
        if not first then return end
        surface.PlaySound("omertarp/ui/inventory-click.wav")
        -- Permadeath is the one rule the whole design rests on, so it is said
        -- once, plainly, at the only moment it can still be avoided — and the
        -- player has to reach past a Back button to accept it.
        Omerta.Characters.ConfirmModal(first .. " " .. last, commit)
    end

    -- Server rejections (name taken, bad path, no season) land here.
    hook.Add("Omerta.CharacterCreateFailed", "omerta.characters.ui_failed", function(reason)
        if not IsValid(status) then return end
        status.OmertaBad = true
        status.OmertaText = reason
        reenable()
    end)

    return {
        Focus = function()
            if IsValid(firstEntry) then firstEntry:RequestFocus() end
        end,
    }
end

--------------------------------------------------------------------------------
-- The confirmation
--------------------------------------------------------------------------------
-- Not a courtesy "are you sure": the one thing a new player cannot know from
-- the form is that this is the ONLY copy of this person, and that the name
-- goes with them. Said in prose, in the same rail grammar as everything else,
-- with Back holding the same third of the row it holds on the form behind it.

function Omerta.Characters.ConfirmModal(fullName, onConfirm)
    local scale = Omerta.HUD.Scale()
    local H = Omerta.HUD
    local width, height = 520 * scale, 260 * scale

    local modal = vgui.Create("DFrame")
    modal:SetSize(width, height)
    modal:Center()
    modal:SetTitle("")
    modal:ShowCloseButton(false)
    modal:SetDraggable(false)
    modal:MakePopup()
    modal.Paint = function(_, w, h)
        surface.SetDrawColor(H.Colour("plate", H.Theme.ALPHA.menu * 255))
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(H.Colour("rule"))
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText("NO SECOND COPY", H.Font("mono"),
            H.Space(5), H.Space(5), H.Colour("dim"),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    -- The full rise. This is the one modal in the game that interrupts, and
    -- arriving with a direction is exactly what stops it reading as the screen
    -- glitching over the form the player was mid-way through.
    H.Reveal(modal)

    local prose = vgui.Create("DLabel", modal)
    prose:SetPos(H.Space(5), H.Space(7) + 18 * scale)
    prose:SetSize(width - H.Space(5) * 2, height - H.Space(7) * 2 - 40 * scale)
    prose:SetFont(H.Font("label"))
    prose:SetTextColor(H.Colour("text"))
    prose:SetWrap(true)
    prose:SetContentAlignment(7)
    prose:SetText(fullName .. " cannot be remade. When they die, they are " ..
        "gone — everything they own, everyone who knows them, and this name, " ..
        "which no one will use again.")

    local buttons = vgui.Create("DPanel", modal)
    buttons:Dock(BOTTOM)
    buttons:DockMargin(H.Space(5), 0, H.Space(5), H.Space(5))
    buttons:SetTall(44 * scale)
    buttons:SetPaintBackground(false)

    local confirm = H.Button(buttons, "Confirm", "commit", function()
        -- Close, not Remove: the modal sinks out while the commit runs. The
        -- fade to black starts on this same click, so the two overlap and the
        -- warning is not simply deleted out from under the answer to it.
        modal:Close()
        onConfirm()
    end)
    confirm:Dock(FILL)

    local back = H.Button(buttons, "Back", "quiet", function() modal:Close() end)
    back:Dock(LEFT)
    back:DockMargin(0, 0, H.Space(1), 0)
    back.PerformLayout = function(self)
        self:SetWide(buttons:GetWide() * 0.33)
    end

    return modal
end

--------------------------------------------------------------------------------
-- The fallback window
--------------------------------------------------------------------------------
-- Only for a build without the menu module: same standard, same layout idea —
-- a full-screen scrim, the form in a left column, the booth on the right.

local function buildFrame()
    -- Remove, not Close: this window is being REPLACED (or a notice is being
    -- swapped for the form), and playing one out under the one arriving in its
    -- place would be two full-screen scrims cross-fading for no reason.
    if IsValid(frame) then frame:Remove() end

    local scale = Omerta.HUD.Scale()
    local H = Omerta.HUD
    local columnW = 470 * scale

    frame = vgui.Create("DFrame")
    frame:SetSize(ScrW(), ScrH())
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    frame:MakePopup()
    frame.Paint = function(_, w, h)
        surface.SetDrawColor(0, 0, 0, 170)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(H.Colour("plate", 0.94))
        surface.DrawRect(0, 0, columnW + H.Space(7) * 2, h)
        draw.SimpleText("NEW ARRIVAL", H.Font("mono"),
            H.Space(7), h * 0.2 - 58 * Omerta.HUD.Scale(), H.Colour("dim"),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        draw.SimpleText("WHO ARE YOU", H.Font("headline"),
            H.Space(7), h * 0.2 - H.Space(3), H.Colour("text"),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    end

    -- Fade only, no rise. This frame is the whole screen, and a full-screen
    -- panel cannot travel: the 42px it moves away from is 42px of bare world
    -- along the top edge, which reads as the interface having come loose. Same
    -- reasoning as the menu rail — see cl_menu.lua.
    H.Reveal(frame, { rise = 0 })

    local column = vgui.Create("DPanel", frame)
    column:SetPos(H.Space(7), ScrH() * 0.2)
    column:SetSize(columnW, ScrH() * 0.7)
    column:SetPaintBackground(false)

    local boothPanel = vgui.Create("DPanel", frame)
    local boothSize = math.min(420 * scale, ScrH() * 0.5)
    boothPanel:SetSize(boothSize, boothSize)
    boothPanel:SetPos(ScrW() - boothSize - H.Space(5), (ScrH() - boothSize) * 0.5)
    boothPanel.Paint = function(_, w, h)
        surface.SetDrawColor(H.Colour("plate", 235))
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(H.Colour("rule"))
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local form = Omerta.Characters.BuildCreationForm(column, boothPanel)
    form.Focus()
end

local function showMessage(text)
    if IsValid(frame) then frame:Remove() end
    -- Scaled like everything else. This box was written in raw pixels and got
    -- away with it while 1x meant 1x; now that the base is 1.75 an unscaled
    -- 460x130 is a box the type no longer fits inside.
    local scale = Omerta.HUD.Scale()
    frame = vgui.Create("DFrame")
    frame:SetSize(460 * scale, 130 * scale)
    frame:Center()
    frame:SetTitle("")
    frame:SetDraggable(false)
    frame:ShowCloseButton(false)
    frame:MakePopup()
    frame.Paint = function(_, w, h)
        surface.SetDrawColor(Omerta.HUD.Colour("plate", 245))
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(Omerta.HUD.Colour("rule"))
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    -- A box this small is a notice, and a notice is exactly the shape the
    -- reveal was written for.
    Omerta.HUD.Reveal(frame)

    local label = vgui.Create("DLabel", frame)
    label:SetPos(16 * scale, 30 * scale)
    label:SetSize(428 * scale, 80 * scale)
    label:SetFont(Omerta.HUD.Font("label"))
    label:SetTextColor(Omerta.HUD.Colour("secondary"))
    label:SetWrap(true)
    label:SetText(text)
end

--------------------------------------------------------------------------------
-- Server-driven state
--------------------------------------------------------------------------------

-- Something may want to hold the creation window back for a moment.
--
-- M19 was the first: a character who has just died is routed here immediately,
-- and a "make a new person" form appearing over the body of the old one is the
-- wrong beat entirely. A gate returns true while it wants to wait, and calls
-- the release function when it is done.
local creationGates = {}
local creationPending = false

function Omerta.Characters.RegisterCreationGate(id, fn)
    creationGates[id] = fn
end

-- Is anything holding the handover back — optionally ignoring one gate?
--
-- The exception is what lets two gates cooperate rather than deadlock: the
-- front-end menu holds creation itself, and needs to know whether anything
-- ELSE (the death sequence, mid-fade) is still holding before it puts itself
-- on screen.
function Omerta.Characters.CreationHeld(exceptId)
    for id, fn in pairs(creationGates) do
        if id ~= exceptId then
            local ok, held = pcall(fn)
            if ok and held then return true end
        end
    end
    return false
end

local function creationHeld()
    return Omerta.Characters.CreationHeld(nil)
end

-- Called by whoever was holding it once they are finished.
function Omerta.Characters.ReleaseCreation()
    if creationPending and not creationHeld() then
        creationPending = false
        buildFrame()
    end
end

hook.Add("Omerta.CharactersState", "omerta.characters.ui", function(state)
    if state == STATE.NEEDS_CREATION then
        -- The front end owns the flow when it exists: the menu appears (after
        -- whatever the death sequence is still doing), and creation is one of
        -- ITS screens. The fallback window is for a build without it.
        if Omerta.Menu ~= nil then return end
        if creationHeld() then creationPending = true return end
        creationPending = false
        buildFrame()
    elseif state == STATE.AWAITING_ENTRY then
        -- A character is waiting and the server is holding this player out of
        -- the city until somebody asks for them. The FRONT END is what normally
        -- asks — it meets every player on join and offers "Return to the city".
        -- In a build without the menu module there is nothing to meet them and
        -- nothing to press, and a frozen player with no interface is the worst
        -- failure this module has ever shipped, so ask immediately: M4 alone
        -- behaves exactly as it did before there was a front end.
        if Omerta.Menu ~= nil then return end
        Omerta.Net.Request("characters.enter", {})
    elseif state == STATE.ACTIVE then
        -- Close, not Remove: the character is standing in the city and the form
        -- (or the "no season" notice, which shares this window) is finished
        -- with, so it leaves rather than being switched off.
        if IsValid(frame) then frame:Close() end
        -- The character now exists server-side (it is cached before this
        -- message is sent), so the held mugshot has something to attach to.
        -- On an ordinary reconnect there is nothing held and nothing happens.
        if capturedPortrait then
            Omerta.Log.Info("characters", "uploading portrait (%d bytes base64)",
                #capturedPortrait)
            Omerta.Net.Request("characters.portrait_upload", { data = capturedPortrait })
            capturedPortrait = nil
        end
    elseif state == STATE.NO_SEASON then
        showMessage("No season is running. The city is closed until an administrator " ..
            "starts one.")
    end
end)

-- A rejected creation (name taken, bad path) leaves no character to own the
-- image, so discard it rather than attaching it to whatever comes next.
hook.Add("Omerta.CharacterCreateFailed", "omerta.characters.discard_portrait", function()
    capturedPortrait = nil
end)
