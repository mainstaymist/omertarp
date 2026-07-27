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

local frame          -- creation window
local pendingCapture -- set while a booth capture is queued for the next frame

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

    local encoded = util.Base64Encode(jpeg, true)
    -- Info, not debug: this fires exactly once per character, and it is the
    -- only client-side evidence that the booth produced an image at all. The
    -- client's log level cannot currently be raised in-game, so a debug line
    -- here would be invisible precisely when it is needed.
    Omerta.Log.Info("characters", "portrait captured (%d bytes base64), uploading", #encoded)
    Omerta.Net.Request("characters.portrait_upload", { data = encoded })
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

hook.Add("Omerta.CharactersState", "omerta.characters.ui", function(state)
    if state == STATE.NEEDS_CREATION then
        buildFrame()
    elseif state == STATE.ACTIVE then
        if IsValid(frame) then frame:Remove() end
    elseif state == STATE.NO_SEASON then
        showMessage("No season is running. The city is closed until an administrator " ..
            "starts one.")
    end
end)
