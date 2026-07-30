-- The front end on screen: the intro, the camera behind it, and the menu.
--
-- The menu stands exactly where the character creator used to appear, and hands
-- over to it. That is why it needs no new plumbing in M4: it registers a
-- CREATION GATE — the same seam M19's death screen uses to hold the handover —
-- and releases it when the player chooses to go in.

Omerta.Menu = Omerta.Menu or {}
Omerta.Menu.Client = Omerta.Menu.Client or {}
local M = Omerta.Menu.Client

M.phase = nil       -- nil | "intro" | "menu"
M.startedAt = 0
M.wanted = false    -- the server says this player has nobody to be
M.selection = 1
M.settings = false

local frame = nil

--------------------------------------------------------------------------------
-- Where the camera stands
--------------------------------------------------------------------------------
-- Per-map authoring work that lands WITH the map (Q-9), so this is a registry
-- with a fallback rather than a hardcoded shot. M27 replaces the fallback with
-- server-authored data; until then every map gets a slow orbit around wherever
-- the player happens to be, which is always somewhere the map intends people
-- to stand.

local vantages = {}

function Omerta.Menu.RegisterVantage(map, def)
    vantages[map] = def
end

local function vantage()
    local def = vantages[game.GetMap()]
    if def then return def end

    local ply = LocalPlayer()
    local anchor = IsValid(ply) and (ply:GetPos() + Vector(0, 0, 64)) or Vector(0, 0, 0)
    return { pos = anchor }
end

--------------------------------------------------------------------------------
-- The music
--------------------------------------------------------------------------------
-- A BASS channel, like the death piano, and for the same reason: it must not be
-- silenced by anything that mutes the world.

local music = { channel = nil, requested = false, fadingOut = false, out = 1 }

local function stopMusic()
    if music.channel and music.channel:IsValid() then music.channel:Stop() end
    music.channel, music.requested, music.fadingOut, music.out = nil, false, false, 1
end

local function startMusic()
    if music.requested or music.channel then return end
    music.requested = true
    -- No flags: "noblock" is a streaming flag for PlayURL and silently returns
    -- nothing for a file on disk (the bug that kept the death piano quiet).
    sound.PlayFile("sound/omertarp/cry-me-a-river.wav", "", function(built, id, name)
        music.requested = false
        if not built then
            -- Expected until the track is compressed and sent (menu.send_music):
            -- a client that never received it simply gets a silent opening.
            Omerta.Log.Debug("menu", "intro music unavailable (%s: %s)",
                tostring(id), tostring(name))
            return
        end
        if not M.phase then built:Stop() return end
        music.channel = built
        built:EnableLooping(true)
        built:SetVolume(0)
        built:Play()
    end)
end

--------------------------------------------------------------------------------
-- Showing and leaving
--------------------------------------------------------------------------------

-- Whether this player wants the opening. A CLIENT convar, not a server config:
-- Omerta.Config is defined in sv_ files and errors on a key the client has
-- never heard of, and in any case "must I watch the intro every time I join"
-- is the player's call. Operator-side control over the sequence is M27's.
CreateClientConVar("omerta_intro", "1", true, false)

local function beginFrontEnd()
    if M.phase then return end
    M.startedAt = CurTime()
    M.selection = 1
    M.settings = false
    M.phase = GetConVar("omerta_intro"):GetBool() and "intro" or "menu"
    startMusic()
    if M.phase == "menu" then Omerta.Menu.Client.Build() end
end

-- Handing over: the menu lets go of the gate and M4 builds its window.
function Omerta.Menu.Enter()
    if IsValid(frame) then frame:Remove() end
    frame = nil
    M.phase = nil
    M.wanted = false
    music.fadingOut = true
    Omerta.Characters.ReleaseCreation()
end

function Omerta.Menu.IsShowing()
    return M.phase ~= nil
end

-- The gate. While the front end is up, nothing else may put a window on
-- screen; M4's creator waits exactly as it waits for the death sequence.
Omerta.Characters.RegisterCreationGate("menu", function()
    return M.phase ~= nil
end)

-- The server says there is nobody to be. The menu does not appear on that
-- signal alone, though: after a death the death sequence is still playing, and
-- the menu must be revealed BY its fade rather than appear on top of it — so it
-- waits until nothing else is holding the handover.
hook.Add("Omerta.CharactersState", "omerta.menu.state", function(state)
    if state == Omerta.Characters.STATE.NEEDS_CREATION then
        M.wanted = true
    elseif state == Omerta.Characters.STATE.ACTIVE then
        M.wanted = false
        if IsValid(frame) then frame:Remove() end
        frame, M.phase = nil, nil
        music.fadingOut = true
    end
end)

hook.Add("Think", "omerta.menu.think", function()
    -- Waiting to appear.
    if M.wanted and not M.phase and not Omerta.Characters.CreationHeld("menu") then
        beginFrontEnd()
    end

    if M.phase == "intro" and Omerta.Menu.IntroDone(CurTime() - M.startedAt) then
        M.phase = "menu"
        Omerta.Menu.Client.Build()
    end

    if music.channel and music.channel:IsValid() then
        if music.fadingOut then
            music.out = math.max(0, music.out - FrameTime() / 1.4)
            music.channel:SetVolume(music.out)
            if music.out <= 0 then stopMusic() end
        else
            music.channel:SetVolume(Omerta.Menu.IntroMusic(CurTime() - M.startedAt))
        end
    end
end)

--------------------------------------------------------------------------------
-- The camera
--------------------------------------------------------------------------------

hook.Add("CalcView", "omerta.menu.view", function(ply, pos, angles, fov)
    if not M.phase then return end
    local O = Omerta.Menu.ORBIT
    local spot = vantage()
    local dx, dy, yaw = Omerta.Menu.OrbitPoint(CurTime() - M.startedAt,
        spot.radius or O.RADIUS, spot.speed or O.SPEED)

    return {
        origin = spot.pos + Vector(dx, dy, spot.height or O.HEIGHT),
        angles = Angle(spot.pitch or O.PITCH, yaw, 0),
        fov = spot.fov or O.FOV,
        drawviewer = false,
    }
end)

-- Nothing of the world's interface belongs on the front end.
Omerta.HUD.RegisterSuppressor("menu", function() return M.phase ~= nil end)

hook.Add("HUDShouldDraw", "omerta.menu.hide_hud", function(name)
    if M.phase and name == "CHudChat" then return false end
end)

hook.Add("CalcViewModelView", "omerta.menu.no_viewmodel", function()
    if M.phase then return Vector(0, 0, -10000), Angle(0, 0, 0) end
end)

--------------------------------------------------------------------------------
-- The intro, drawn
--------------------------------------------------------------------------------
-- PostRenderVGUI, like the death screen: the black has to cover VGUI and then
-- lift off it, and anything drawn in a HUD hook sits behind panels.

hook.Add("PostRenderVGUI", "omerta.menu.intro", function()
    if M.phase ~= "intro" then return end
    local elapsed = CurTime() - M.startedAt
    local w, h = ScrW(), ScrH()

    local black = Omerta.Menu.IntroWorldFade(elapsed)
    if black > 0 then
        surface.SetDrawColor(0, 0, 0, 255 * black)
        surface.DrawRect(0, 0, w, h)
    end

    local alpha = Omerta.Menu.IntroTitleAlpha(elapsed)
    if alpha > 0 then
        draw.SimpleText(Omerta.Menu.TITLE, Omerta.HUD.Font("title"),
            w * 0.5, h * 0.46, Omerta.HUD.Colour("textPrimary", 255 * alpha),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(Omerta.Menu.SUBTITLE, Omerta.HUD.Font("body"),
            w * 0.5, h * 0.46 + Omerta.HUD.Space(7),
            Omerta.HUD.Colour("textHelper", 255 * alpha),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    if Omerta.Menu.MaySkip(elapsed) then
        draw.SimpleText(Omerta.Menu.SKIP_PROMPT, Omerta.HUD.Font("small"),
            w - Omerta.HUD.Space(6), h - Omerta.HUD.Space(6),
            Omerta.HUD.Colour("textPlaceholder", 160),
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    end
end)

hook.Add("PlayerButtonDown", "omerta.menu.skip", function(ply, button)
    if M.phase ~= "intro" or ply ~= LocalPlayer() then return end
    if gui.IsGameUIVisible() or gui.IsConsoleVisible() then return end
    if not Omerta.Menu.MaySkip(CurTime() - M.startedAt) then return end
    M.phase = "menu"
    Omerta.Menu.Client.Build()
end)

--------------------------------------------------------------------------------
-- The menu, built
--------------------------------------------------------------------------------
-- Carbon: no rounded corners, one accent, a selected row marked by a 3px bar
-- rather than by a colour wash.

local ROW_H, COLUMN_W = 56, 420

function Omerta.Menu.Client.Build()
    if IsValid(frame) then frame:Remove() end

    local scale = Omerta.HUD.Scale()
    local rowH, columnW = ROW_H * scale, COLUMN_W * scale
    local left = Omerta.HUD.Space(10)

    frame = vgui.Create("DFrame")
    frame:SetSize(ScrW(), ScrH())
    frame:SetPos(0, 0)
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    frame:MakePopup()
    frame.Paint = function(_, w, h)
        -- A scrim, not a panel: the city stays visible behind the words, and
        -- the type stays readable over whatever the camera drifts past.
        surface.SetDrawColor(0, 0, 0, 150)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(Omerta.HUD.Colour("background", 205))
        surface.DrawRect(0, 0, left + columnW + Omerta.HUD.Space(6), h)

        draw.SimpleText(Omerta.Menu.TITLE, Omerta.HUD.Font("title"),
            left, h * 0.5 - rowH * 3.4,
            Omerta.HUD.Colour("textPrimary"), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(Omerta.Menu.SUBTITLE, Omerta.HUD.Font("label"),
            left, h * 0.5 - rowH * 2.5,
            Omerta.HUD.Colour("textHelper"), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- The season is public: it is the city everybody is playing in.
        local season = Omerta.Seasons.GetActive and Omerta.Seasons.GetActive()
        draw.SimpleText(season and season.name or "The city is closed",
            Omerta.HUD.Font("small"), left, h - Omerta.HUD.Space(6),
            Omerta.HUD.Colour("textPlaceholder"), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    end

    local list = vgui.Create("DPanel", frame)
    list:SetPos(left, ScrH() * 0.5 - rowH)
    list:SetSize(columnW, rowH * 5)
    list.Paint = nil
    frame.List = list

    function frame:Rebuild()
        list:Clear()
        if M.settings then Omerta.Menu.Client.BuildSettings(list, rowH) return end

        local available = Omerta.Menu.Available()
        M.selection = math.min(math.max(1, M.selection), math.max(1, #available))

        for index, def in ipairs(available) do
            local row = vgui.Create("DButton", list)
            row:Dock(TOP)
            row:SetTall(rowH)
            row:SetText("")
            row.Paint = function(self, w, h)
                local selected = index == M.selection
                if selected or self:IsHovered() then
                    surface.SetDrawColor(Omerta.HUD.Colour(
                        selected and "layerSelected" or "layerHover", 235))
                    surface.DrawRect(0, 0, w, h)
                end
                if selected then
                    -- Carbon marks the active thing with a bar, not a glow.
                    surface.SetDrawColor(Omerta.HUD.Colour("interactive"))
                    surface.DrawRect(0, 0, 3 * scale, h)
                end
                draw.SimpleText(def.label, Omerta.HUD.Font("heading"),
                    Omerta.HUD.Space(5), h * 0.5,
                    Omerta.HUD.Colour(selected and "textPrimary" or "textSecondary"),
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            row.OnCursorEntered = function()
                M.selection = index
            end
            row.DoClick = function()
                M.selection = index
                surface.PlaySound("omertarp/ui/inventory-click.wav")
                def.onSelect()
            end
        end
    end

    -- The keyboard drives it as well as the mouse: this screen is the first
    -- thing a player touches and it should not require finding a cursor.
    frame.OnKeyCodePressed = function(self, key)
        local available = M.settings and {} or Omerta.Menu.Available()
        if key == KEY_UP or key == KEY_W then
            M.selection = Omerta.Menu.StepSelection(M.selection, -1, #available)
            surface.PlaySound("omertarp/ui/inventory-click.wav")
        elseif key == KEY_DOWN or key == KEY_S then
            M.selection = Omerta.Menu.StepSelection(M.selection, 1, #available)
            surface.PlaySound("omertarp/ui/inventory-click.wav")
        elseif key == KEY_ENTER or key == KEY_SPACE then
            local def = available[M.selection]
            if def then def.onSelect() end
        elseif key == KEY_ESCAPE and M.settings then
            M.settings = false
            self:Rebuild()
        end
    end

    frame:Rebuild()
end

-- Minimal on purpose: M26 owns the settings window, and this is the one control
-- that changes whether the rest of the game is readable at all.
function Omerta.Menu.Client.BuildSettings(list, rowH)
    local scale = Omerta.HUD.Scale()

    local label = vgui.Create("DPanel", list)
    label:Dock(TOP)
    label:SetTall(rowH * 0.7)
    label.Paint = function(_, w, h)
        draw.SimpleText("Interface scale", Omerta.HUD.Font("label"),
            Omerta.HUD.Space(5), h * 0.5, Omerta.HUD.Colour("textHelper"),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local row = vgui.Create("DPanel", list)
    row:Dock(TOP)
    row:SetTall(rowH)
    row.Paint = nil

    for _, value in ipairs({ 0.75, 1, 1.25, 1.5 }) do
        local button = vgui.Create("DButton", row)
        button:Dock(LEFT)
        button:SetWide(90 * scale)
        button:DockMargin(0, 0, 2, 0)
        button:SetText("")
        button.Paint = function(self, w, h)
            local current = math.abs(Omerta.HUD.Scale() - value) < 0.01
            surface.SetDrawColor(Omerta.HUD.Colour(
                current and "buttonPrimary" or (self:IsHovered() and "layerHover" or "layer01")))
            surface.DrawRect(0, 0, w, h)
            draw.SimpleText(value .. "x", Omerta.HUD.Font("label"), w * 0.5, h * 0.5,
                Omerta.HUD.Colour(current and "textOnColour" or "textSecondary"),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        button.DoClick = function()
            RunConsoleCommand("omerta_ui_scale", tostring(value))
            surface.PlaySound("omertarp/ui/inventory-click.wav")
            -- Rebuilt on the next frame, once the fonts have been remade.
            timer.Simple(0.05, function()
                if M.phase == "menu" then Omerta.Menu.Client.Build() end
            end)
        end
    end

    local back = vgui.Create("DButton", list)
    back:Dock(TOP)
    back:SetTall(rowH)
    back:DockMargin(0, Omerta.HUD.Space(5), 0, 0)
    back:SetText("")
    back.Paint = function(self, w, h)
        if self:IsHovered() then
            surface.SetDrawColor(Omerta.HUD.Colour("layerHover", 235))
            surface.DrawRect(0, 0, w, h)
        end
        draw.SimpleText("Back", Omerta.HUD.Font("heading"),
            Omerta.HUD.Space(5), h * 0.5, Omerta.HUD.Colour("textSecondary"),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    back.DoClick = function()
        M.settings = false
        if IsValid(frame) then frame:Rebuild() end
    end
end

--------------------------------------------------------------------------------
-- What the menu offers
--------------------------------------------------------------------------------

Omerta.Menu.RegisterEntry("menu.enter", {
    label = "Enter the city",
    order = 10,
    onSelect = function() Omerta.Menu.Enter() end,
})

Omerta.Menu.RegisterEntry("menu.settings", {
    label = "Settings",
    order = 50,
    onSelect = function()
        M.settings = true
        if IsValid(frame) then frame:Rebuild() end
    end,
})

Omerta.Menu.RegisterEntry("menu.leave", {
    label = "Leave",
    order = 90,
    onSelect = function() RunConsoleCommand("disconnect") end,
})
