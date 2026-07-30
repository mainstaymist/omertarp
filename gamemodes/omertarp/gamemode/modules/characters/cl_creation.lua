-- Character creation UI and the D-011 portrait booth.
--
-- Deliberately plain: functional layout, no art pass. D-005 puts gameplay
-- before art, and the whole screen will be revisited when M8's UI framework
-- and the period art direction (D-002) land.
--
-- The booth capture is the one genuinely fiddly part. A dedicated server has
-- no renderer, so the mugshot must be produced here and uploaded (D-011):
-- draw the character model to a known screen rectangle, capture that
-- rectangle as JPEG in a render hook, base64 it, and send.

local STATE = Omerta.Characters.STATE

local frame            -- creation window
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
    -- only client-side evidence that the booth produced an image at all. The
    -- client's log level cannot currently be raised in-game, so a debug line
    -- here would be invisible precisely when it is needed.
    Omerta.Log.Info("characters", "portrait captured (%d bytes base64), awaiting character",
        #capturedPortrait)
end)

--------------------------------------------------------------------------------
-- Creation window
--------------------------------------------------------------------------------

local function buildFrame()
    if IsValid(frame) then frame:Remove() end

    frame = vgui.Create("DFrame")
    frame:SetSize(720, 460)
    frame:Center()
    frame:SetTitle("Omertà RP — Who are you?")
    frame:SetDraggable(false)
    frame:ShowCloseButton(false)
    frame:MakePopup()

    -- Left: the booth. This panel is also the portrait framing (D-011).
    local booth = vgui.Create("DModelPanel", frame)
    booth:SetPos(12, 34)
    booth:SetSize(PORTRAIT_SIZE * 2, PORTRAIT_SIZE * 2)
    booth:SetModel(Omerta.Characters.MODELS[1])
    booth:SetFOV(28)
    booth:SetCamPos(Vector(42, 0, 62))
    booth:SetLookAt(Vector(0, 0, 62)) -- head height: a mugshot, not a full body
    function booth:LayoutEntity() end -- no idle spin: the photo must be still

    local right, y = 280, 40
    local function label(text)
        local l = vgui.Create("DLabel", frame)
        l:SetPos(right, y)
        l:SetSize(400, 18)
        l:SetText(text)
        y = y + 20
        return l
    end
    local function entry()
        local e = vgui.Create("DTextEntry", frame)
        e:SetPos(right, y)
        e:SetSize(400, 24)
        y = y + 30
        return e
    end

    label("First name")
    local firstEntry = entry()
    label("Last name")
    local lastEntry = entry()

    -- The form is typeable end to end: Tab hops between the name boxes (and
    -- wraps), and the first is focused the moment the window opens, below.
    -- Explicit rather than the panel system's tab ordering, which does not
    -- survive MakePopup reliably.
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

    label("Appearance")
    local modelChoice = vgui.Create("DComboBox", frame)
    modelChoice:SetPos(right, y)
    modelChoice:SetSize(400, 24)
    for i, mdl in ipairs(Omerta.Characters.MODELS) do
        modelChoice:AddChoice(mdl:match("([^/]+)%.mdl$") or mdl, i, i == 1)
    end
    modelChoice.OnSelect = function(_, _, _, data)
        booth:SetModel(Omerta.Characters.MODELS[data] or Omerta.Characters.MODELS[1])
    end
    y = y + 32

    label("Path for this season (you cannot switch freely)")
    local pathChoice = vgui.Create("DComboBox", frame)
    pathChoice:SetPos(right, y)
    pathChoice:SetSize(400, 24)
    pathChoice:AddChoice("Criminal — eligible for family life", 1, true)
    pathChoice:AddChoice("Police — the department", 2)
    pathChoice:AddChoice("Independent — civilian, business, trade", 3)
    y = y + 36

    local status = vgui.Create("DLabel", frame)
    status:SetPos(right, y)
    status:SetSize(400, 40)
    status:SetWrap(true)
    status:SetText("")
    y = y + 46

    local submit = vgui.Create("DButton", frame)
    submit:SetPos(right, y)
    submit:SetSize(400, 32)
    submit:SetText("Enter the city")

    -- Live feedback using the same validator the server enforces. This is a
    -- courtesy only: the server revalidates everything on arrival.
    local function validate()
        local first, last = Omerta.Characters.ValidateName(
            firstEntry:GetValue(), lastEntry:GetValue())
        if not first then
            status:SetTextColor(Color(200, 120, 120))
            status:SetText(last or "")
            return nil
        end
        status:SetTextColor(Color(140, 170, 140))
        status:SetText(first .. " " .. last)
        return first, last
    end
    firstEntry.OnChange = validate
    lastEntry.OnChange = validate

    local function reenable()
        if IsValid(submit) then
            submit:SetEnabled(true)
            submit:SetText("Enter the city")
        end
    end

    submit.DoClick = function()
        if not validate() then return end
        local _, modelIndex = modelChoice:GetSelected()
        local _, pathIndex = pathChoice:GetSelected()
        submit:SetEnabled(false)
        submit:SetText("Creating…")
        -- The booth is still on screen; take the mugshot now, at creation,
        -- exactly once (D-011).
        requestCapture(booth)
        Omerta.Net.Request("characters.create", {
            first = firstEntry:GetValue(),
            last = lastEntry:GetValue(),
            model = modelIndex or 1,
            skin = 0,
            path = pathIndex or 1,
        })
        timer.Simple(5, reenable)
    end

    -- Server rejections (name taken, bad path, no season) land here.
    hook.Add("Omerta.CharacterCreateFailed", "omerta.characters.ui_failed", function(reason)
        if not IsValid(status) then return end
        status:SetTextColor(Color(200, 120, 120))
        status:SetText(reason)
        reenable()
    end)

    -- Last, so nothing built after it steals the focus back.
    firstEntry:RequestFocus()
end

local function showMessage(text)
    if IsValid(frame) then frame:Remove() end
    frame = vgui.Create("DFrame")
    frame:SetSize(420, 120)
    frame:Center()
    frame:SetTitle("Omertà RP")
    frame:SetDraggable(false)
    frame:ShowCloseButton(false)
    frame:MakePopup()
    local l = vgui.Create("DLabel", frame)
    l:SetPos(16, 40)
    l:SetSize(388, 60)
    l:SetWrap(true)
    l:SetText(text)
end

--------------------------------------------------------------------------------
-- Server-driven state
--------------------------------------------------------------------------------

-- Something may want to hold the creation window back for a moment.
--
-- M19 is the first: a character who has just died is routed here immediately,
-- and a "make a new person" form appearing over the body of the old one is the
-- wrong beat entirely. A gate returns true while it wants to wait, and calls
-- the release function when it is done.
local creationGates = {}
local creationPending = false

function Omerta.Characters.RegisterCreationGate(id, fn)
    creationGates[id] = fn
end

local function creationHeld()
    for _, fn in pairs(creationGates) do
        local ok, held = pcall(fn)
        if ok and held then return true end
    end
    return false
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
        if creationHeld() then creationPending = true return end
        creationPending = false
        buildFrame()
    elseif state == STATE.ACTIVE then
        if IsValid(frame) then frame:Remove() end
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
