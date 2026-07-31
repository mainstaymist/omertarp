-- The front end on screen: the intro, the camera behind it, and the menu.
--
-- The menu stands exactly where the character creator used to appear, and
-- HOSTS it: creation is a screen of the menu, over the same drifting camera,
-- built from the same form component (M4's BuildCreationForm) — not a window
-- floating on top. The menu registers a CREATION GATE — the same seam M19's
-- death screen uses to hold the handover — and never releases it; entering
-- the city goes through creation, and a finished character closes everything.
--
-- Styled to the guide: ink plate rail, Oswald caps, the selected entry as the
-- brass inversion, the season line in the mono system voice.

Omerta.Menu = Omerta.Menu or {}
Omerta.Menu.Client = Omerta.Menu.Client or {}
local M = Omerta.Menu.Client

M.phase = nil       -- nil | "intro" | "menu"
M.screen = "root"   -- "root" | "creation" | "settings"
M.startedAt = 0
M.wanted = false    -- the server says this player has nobody to be
M.selection = 1

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
-- A BASS channel, like the death piano, and for the same reason: it must not
-- be silenced by anything that mutes the world.

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
-- never been told about, and in any case "must I watch the intro every time I
-- join" is the player's call. Operator-side control over the sequence is M27's.
CreateClientConVar("omerta_intro", "1", true, false)

local function beginFrontEnd()
    if M.phase then return end
    M.startedAt = CurTime()
    M.selection = 1
    M.screen = "root"
    M.phase = GetConVar("omerta_intro"):GetBool() and "intro" or "menu"
    startMusic()
    if M.phase == "menu" then Omerta.Menu.Client.Build() end
end

function Omerta.Menu.IsShowing()
    return M.phase ~= nil
end

-- Kept for a future "character exists, enter directly" path; today entering
-- the city always means making somebody first, on the creation screen.
function Omerta.Menu.Enter()
    if IsValid(frame) then frame:Remove() end
    frame = nil
    M.phase = nil
    M.wanted = false
    music.fadingOut = true
    Omerta.Characters.ReleaseCreation()
end

-- The gate. While the front end is up, nothing else may put a window on
-- screen; M4's creator waits exactly as it waits for the death sequence.
Omerta.Characters.RegisterCreationGate("menu", function()
    return M.phase ~= nil
end)

-- The server says there is nobody to be. The menu does not appear on that
-- signal alone, though: after a death the death sequence is still playing, and
-- the menu must be revealed BY its fade rather than appear on top of it — so
-- it waits until nothing else is holding the handover.
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
    local scale = Omerta.HUD.Scale()

    local black = Omerta.Menu.IntroWorldFade(elapsed)
    if black > 0 then
        surface.SetDrawColor(5, 5, 6, 255 * black)
        surface.DrawRect(0, 0, w, h)
    end

    local alpha = Omerta.Menu.IntroTitleAlpha(elapsed)
    if alpha > 0 then
        draw.SimpleText(string.upper(Omerta.Menu.TITLE), Omerta.HUD.Font("title"),
            w * 0.5, h * 0.46, Omerta.HUD.Colour("text", 255 * alpha),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(Omerta.Menu.SUBTITLE, Omerta.HUD.Font("body"),
            w * 0.5, h * 0.46 + 64 * scale,
            Omerta.HUD.Colour("secondary", 235 * alpha),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    if Omerta.Menu.MaySkip(elapsed) then
        draw.SimpleText(string.upper(Omerta.Menu.SKIP_PROMPT),
            Omerta.HUD.Font("mono"),
            w - Omerta.HUD.Space(5), h - Omerta.HUD.Space(5),
            Omerta.HUD.Colour("dim", 200),
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
-- An ink rail down the left over a scrim; the wordmark, the entries, and the
-- season in the mono voice at the foot. The selected entry is the brass
-- inversion — the same selection language as every list in the game.

local ROW_H, COLUMN_W = 52, 380

function Omerta.Menu.Client.Build()
    if IsValid(frame) then frame:Remove() end
    if M.phase ~= "menu" then return end

    local scale = Omerta.HUD.Scale()
    local rowH, columnW = ROW_H * scale, COLUMN_W * scale
    local margin = Omerta.HUD.Space(5)

    frame = vgui.Create("DFrame")
    frame:SetSize(ScrW(), ScrH())
    frame:SetPos(0, 0)
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    frame:MakePopup()

    frame.Paint = function(_, w, h)
        -- A scrim over the whole city, then the rail. On the creation screen
        -- the rail widens to hold the form.
        surface.SetDrawColor(6, 6, 7, 90)
        surface.DrawRect(0, 0, w, h)

        local railW = (M.screen == "creation" and 560 or 470) * scale
        surface.SetDrawColor(Omerta.HUD.Colour("plate",
            Omerta.HUD.Theme.ALPHA.focus * 255))
        surface.DrawRect(0, 0, railW, h)
        surface.SetDrawColor(Omerta.HUD.Colour("rule"))
        surface.DrawRect(railW, 0, 1, h)

        if M.screen == "creation" then
            draw.SimpleText("NEW ARRIVAL", Omerta.HUD.Font("mono"),
                margin, h * 0.5 - 300 * scale, Omerta.HUD.Colour("dim"),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
            draw.SimpleText("WHO ARE YOU", Omerta.HUD.Font("headline"),
                margin, h * 0.5 - 258 * scale, Omerta.HUD.Colour("text"),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        else
            draw.SimpleText(string.upper(Omerta.Menu.TITLE),
                Omerta.HUD.Font("title"), margin, h * 0.5 - rowH * 2.6,
                Omerta.HUD.Colour("text"), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
            draw.SimpleText(Omerta.Menu.SUBTITLE, Omerta.HUD.Font("label"),
                margin, h * 0.5 - rowH * 2.6 + 26 * scale,
                Omerta.HUD.Colour("secondary"), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        end

        -- The season is public: it is the city everybody is playing in. Soft
        -- reference — Omerta.Seasons is a server table; the client learns the
        -- season only if something has told it, and says so plainly if not.
        local seasons = Omerta.Seasons
        local season = seasons and seasons.GetActive and seasons.GetActive() or nil
        draw.SimpleText(string.upper(season and season.name or "The city"),
            Omerta.HUD.Font("mono"), margin, h - margin,
            Omerta.HUD.Colour("dim"), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    end

    function frame:Rebuild()
        for _, child in ipairs(self:GetChildren()) do
            if child.OmertaOwned then child:Remove() end
        end
        if M.screen == "creation" then
            Omerta.Menu.Client.BuildCreation(self)
        elseif M.screen == "settings" then
            Omerta.Menu.Client.BuildSettings(self)
        else
            Omerta.Menu.Client.BuildRoot(self)
        end
    end

    -- The keyboard drives the root as well as the mouse: this screen is the
    -- first thing a player touches and it should not require finding a cursor.
    frame.OnKeyCodePressed = function(self, key)
        if M.screen == "creation" then
            if key == KEY_ESCAPE then
                M.screen = "root"
                self:Rebuild()
            end
            return
        end
        if M.screen ~= "root" then return end
        local available = Omerta.Menu.Available()
        if key == KEY_UP or key == KEY_W then
            M.selection = Omerta.Menu.StepSelection(M.selection, -1, #available)
            surface.PlaySound("omertarp/ui/inventory-click.wav")
        elseif key == KEY_DOWN or key == KEY_S then
            M.selection = Omerta.Menu.StepSelection(M.selection, 1, #available)
            surface.PlaySound("omertarp/ui/inventory-click.wav")
        elseif key == KEY_ENTER or key == KEY_SPACE then
            local def = available[M.selection]
            if def then def.onSelect() end
        end
    end

    frame:Rebuild()
end

function Omerta.Menu.Client.BuildRoot(parent)
    local scale = Omerta.HUD.Scale()
    local rowH, columnW = ROW_H * scale, COLUMN_W * scale
    local margin = Omerta.HUD.Space(5)

    local list = vgui.Create("DPanel", parent)
    list.OmertaOwned = true
    list:SetPos(margin, ScrH() * 0.5 - rowH)
    list:SetSize(columnW, rowH * 6)
    list.Paint = nil

    local available = Omerta.Menu.Available()
    M.selection = math.min(math.max(1, M.selection), math.max(1, #available))

    for index, def in ipairs(available) do
        local row = vgui.Create("DButton", list)
        row:Dock(TOP)
        row:SetTall(rowH)
        row:SetText("")
        row.Paint = function(self, w, h)
            local selected = index == M.selection
            local colour
            if selected then
                surface.SetDrawColor(Omerta.HUD.Colour("brass"))
                surface.DrawRect(0, 0, w, h)
                colour = Omerta.HUD.Colour("ink")
            else
                if self:IsHovered() then
                    surface.SetDrawColor(Omerta.HUD.Colour("brass",
                        Omerta.HUD.Theme.ALPHA.wash * 255))
                    surface.DrawRect(0, 0, w, h)
                end
                colour = Omerta.HUD.Colour("secondary")
            end
            draw.SimpleText(string.upper(def.label), Omerta.HUD.Font("heading"),
                Omerta.HUD.Space(4), h * 0.5, colour,
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

--------------------------------------------------------------------------------
-- The creation screen
--------------------------------------------------------------------------------
-- M4's form, hosted in the widened rail; the booth on the city side of the
-- rule, in a plate tile; BACK under the form. The submit lives in the form.

function Omerta.Menu.Client.BuildCreation(parent)
    local scale = Omerta.HUD.Scale()
    local margin = Omerta.HUD.Space(5)
    local columnW = 560 * scale - margin * 2

    local column = vgui.Create("DPanel", parent)
    column.OmertaOwned = true
    column:SetPos(margin, ScrH() * 0.5 - 240 * scale)
    column:SetSize(columnW, 560 * scale)
    column.Paint = nil

    local boothSize = math.min(400 * scale, ScrH() * 0.5)
    local boothPanel = vgui.Create("DPanel", parent)
    boothPanel.OmertaOwned = true
    boothPanel:SetSize(boothSize, boothSize)
    boothPanel:SetPos(560 * scale + (ScrW() - 560 * scale - boothSize) * 0.5,
        (ScrH() - boothSize) * 0.5)
    boothPanel.Paint = function(_, w, h)
        surface.SetDrawColor(Omerta.HUD.Colour("plate", 200))
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(Omerta.HUD.Colour("rule"))
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText("PORTRAIT", Omerta.HUD.Font("mono"),
            Omerta.HUD.Space(3), Omerta.HUD.Space(3),
            Omerta.HUD.Colour("dim"), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local form = Omerta.Characters.BuildCreationForm(column, boothPanel)

    local back = Omerta.HUD.Button(column, "Back", "quiet", function()
        M.screen = "root"
        if IsValid(frame) then frame:Rebuild() end
    end)
    back:Dock(TOP)
    back:SetTall(40 * scale)
    back:DockMargin(0, Omerta.HUD.Space(3), 0, 0)

    form.Focus()
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------
-- Minimal on purpose: M26 owns the settings window, and this is the one
-- control that changes whether the rest of the game is readable at all.

function Omerta.Menu.Client.BuildSettings(parent)
    local scale = Omerta.HUD.Scale()
    local margin = Omerta.HUD.Space(5)
    local rowH = ROW_H * scale

    local list = vgui.Create("DPanel", parent)
    list.OmertaOwned = true
    list:SetPos(margin, ScrH() * 0.5 - rowH)
    list:SetSize(COLUMN_W * scale, rowH * 4)
    list.Paint = nil

    local label = Omerta.HUD.FieldLabel(list, "Interface scale")
    label:Dock(TOP)
    label:SetTall(24 * scale)

    local row = vgui.Create("DPanel", list)
    row:Dock(TOP)
    row:SetTall(rowH)
    row:DockMargin(0, Omerta.HUD.Space(1), 0, 0)
    row.Paint = nil

    for _, value in ipairs({ 0.75, 1, 1.25, 1.5 }) do
        local current = math.abs(Omerta.HUD.Scale() - value) < 0.01
        local button = Omerta.HUD.Button(row, value .. "x",
            current and "commit" or "quiet", function()
                RunConsoleCommand("omerta_ui_scale", tostring(value))
                -- Rebuilt on the next frame, once the fonts have been remade.
                timer.Simple(0.05, function()
                    if M.phase == "menu" then Omerta.Menu.Client.Build() end
                end)
            end)
        button:Dock(LEFT)
        button:SetWide(84 * scale)
        button:DockMargin(0, 0, Omerta.HUD.Space(1), 0)
    end

    local back = Omerta.HUD.Button(list, "Back", "quiet", function()
        M.screen = "root"
        if IsValid(frame) then frame:Rebuild() end
    end)
    back:Dock(TOP)
    back:SetTall(rowH * 0.8)
    back:DockMargin(0, Omerta.HUD.Space(4), 0, 0)
end

--------------------------------------------------------------------------------
-- What the menu offers
--------------------------------------------------------------------------------

Omerta.Menu.RegisterEntry("menu.enter", {
    label = "Enter the city",
    order = 10,
    onSelect = function()
        M.screen = "creation"
        if IsValid(frame) then frame:Rebuild() end
    end,
})

Omerta.Menu.RegisterEntry("menu.settings", {
    label = "Settings",
    order = 50,
    onSelect = function()
        M.screen = "settings"
        if IsValid(frame) then frame:Rebuild() end
    end,
})

Omerta.Menu.RegisterEntry("menu.leave", {
    label = "Leave",
    order = 90,
    onSelect = function() RunConsoleCommand("disconnect") end,
})
