-- The front end on screen: the intro, the camera behind it, and the menu.
--
-- The same rail serves twice. As the FRONT END it appears when the server says
-- this player has nobody to be; as the PAUSE MENU it answers F1 during normal
-- play — same entries, same standard, but no intro, no music, and no orbit
-- camera, because pausing must not become a tour of the spawn vantage.
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
M.mode = "front"    -- "front" (the opening flow) | "pause" (F1 over live play)
M.screen = "root"   -- "root" | "creation" | "settings"
M.startedAt = 0
M.wanted = false    -- the server says this player has nobody to be
M.selection = 1

local frame = nil

-- The handover fade into the world. Declared up here because the state hook
-- below lifts it, and a local declared later would leave that hook writing to
-- a global of the same name instead — silently, and only at runtime.
local spawnFade = nil -- { phase = "out" | "hold" | "in", startedAt }

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

-- Has the death sequence just handed over to us?
--
-- It matters because the intro opens on a second of pure black, and arriving
-- there straight from the death screen's own black reads as the picture
-- breaking — the "flashes black switching to the main menu" in the field
-- report. A player who has just watched a character die does not need the
-- title card again either way.
local function afterDeath()
    local C = Omerta.Injury and Omerta.Injury.Client
    return C ~= nil and (C.leaving ~= nil or C.death ~= nil)
end

local function beginFrontEnd()
    if M.phase then return end
    M.startedAt = CurTime()
    M.selection = 1
    M.screen = "root"
    M.mode = "front"
    M.phase = (GetConVar("omerta_intro"):GetBool() and not afterDeath())
        and "intro" or "menu"
    startMusic()
    if M.phase == "menu" then Omerta.Menu.Client.Build() end
end

function Omerta.Menu.IsShowing()
    return M.phase ~= nil
end

--------------------------------------------------------------------------------
-- Pause
--------------------------------------------------------------------------------
-- F1 during play shows the same rail. Two things it deliberately does NOT do:
-- start the music, and touch the camera. Pausing must not become a free look
-- at the spawn vantage — so the background is the player's OWN view, blurred
-- where it stands, and the orbit is reserved for the front end.

local BLUR = Material("pp/blurscreen")

function Omerta.Menu.IsPaused()
    return M.phase ~= nil and M.mode == "pause"
end

local function openPause()
    if M.phase then return end
    M.mode = "pause"
    M.screen = "root"
    M.selection = 1
    M.startedAt = CurTime()
    M.phase = "menu"
    Omerta.Menu.Client.Build()
end

local function closePause()
    if not Omerta.Menu.IsPaused() then return end
    if IsValid(frame) then frame:Remove() end
    frame = nil
    M.phase = nil
    M.mode = "front"
    M.screen = "root"
end

function Omerta.Menu.TogglePause()
    if Omerta.Menu.IsPaused() then closePause() return end
    if M.phase or M.wanted then return end -- the front end owns the screen
    if afterDeath() then return end
    openPause()
end

-- F1 arrives as gm_showhelp. Swallowed either way, so the engine's own help
-- panel never appears over ours.
hook.Add("PlayerBindPress", "omerta.menu.pause", function(ply, bind, pressed)
    if bind ~= "gm_showhelp" then return end
    if not pressed then return true end
    if ply:IsTyping() or gui.IsGameUIVisible() or gui.IsConsoleVisible() then return true end
    Omerta.Menu.TogglePause()
    return true
end)

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
        M.mode = "front"
        music.fadingOut = true
        -- They are standing in the city now; lift the black off them.
        if spawnFade and spawnFade.phase ~= "in" then
            spawnFade = { phase = "in", startedAt = CurTime() }
        end
    end
end)

hook.Add("Think", "omerta.menu.think", function()
    -- Shot while paused. The death sequence owns the screen from the moment it
    -- starts, and a pause rail sitting over it would be the player reading a
    -- menu through their own death — so the pause gets out of the way.
    if Omerta.Menu.IsPaused() and afterDeath() then closePause() end

    -- Waiting to appear.
    if M.wanted and not M.phase and not Omerta.Characters.CreationHeld("menu") then
        beginFrontEnd()
    end

    if M.phase == "intro" and Omerta.Menu.IntroDone(CurTime() - M.startedAt) then
        M.phase = "menu"
        Omerta.Menu.Client.Build()
    end

    -- The menu believes it is up but its panel has gone. Nothing should be
    -- able to do that — but something did once (a material-system restart
    -- takes every VGUI panel with it), and the result was a player frozen at
    -- spawn with no interface and no error to explain it. A player who cannot
    -- see the menu cannot leave it, so this rebuilds rather than trusting that
    -- it will not happen again.
    if M.phase == "menu" and not IsValid(frame) then
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
    -- The front end only. Pause leaves the view exactly where the player left
    -- it, blurred in the frame's own paint.
    if not M.phase or M.mode == "pause" then return end
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
    -- Paused, the world is frozen behind a blur and the hands may stay in it.
    if M.phase and M.mode ~= "pause" then
        return Vector(0, 0, -10000), Angle(0, 0, 0)
    end
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
        -- Paused, the player's own view is the background — blurred, so it is
        -- plainly not a view they can play from, and darkened so the rail
        -- still reads over a bright street.
        if M.mode == "pause" then
            surface.SetMaterial(BLUR)
            surface.SetDrawColor(255, 255, 255, 255)
            for pass = 1, 3 do
                BLUR:SetFloat("$blur", (pass / 3) * 6)
                BLUR:Recompute()
                render.UpdateScreenEffectTexture()
                surface.DrawTexturedRect(0, 0, w, h)
            end
            surface.SetDrawColor(6, 6, 7, 90)
            surface.DrawRect(0, 0, w, h)
        else
            -- A scrim over the whole city, then the rail. On the creation
            -- screen the rail widens to hold the form.
            surface.SetDrawColor(6, 6, 7, 90)
            surface.DrawRect(0, 0, w, h)
        end

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

    -- The column runs from under the heading to the bottom margin, and the
    -- form docks its button row to the BOTTOM of it. Sized from the viewport
    -- rather than from a fixed height: the fixed one ran off the screen at
    -- 1.5x and took Confirm with it.
    local top = ScrH() * 0.5 - 258 * scale + Omerta.HUD.Space(4)
    local column = vgui.Create("DPanel", parent)
    column.OmertaOwned = true
    column:SetPos(margin, top)
    column:SetSize(columnW, ScrH() - top - margin)
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

    -- The form owns its own Back/Confirm row (docked to the column's bottom),
    -- so the fallback window gets the same one.
    local form = Omerta.Characters.BuildCreationForm(column, boothPanel, {
        onBack = function()
            M.screen = "root"
            if IsValid(frame) then frame:Rebuild() end
        end,
    })

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

    -- Tall enough for everything in it, and anchored high enough that it does
    -- not run off the bottom. The first version was four rows tall while the
    -- content came to six, and docked children simply clip: the multi-core
    -- toggle and the Back button were being drawn outside the panel, which
    -- reads exactly like a screen that failed to build.
    local list = vgui.Create("DPanel", parent)
    list.OmertaOwned = true
    list:SetPos(margin, math.max(margin, ScrH() * 0.5 - rowH * 3))
    list:SetSize(COLUMN_W * scale, math.min(rowH * 9, ScrH() - margin * 2))
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

    -- A toggle reads its convar and restyles: lit (commit) when on, quiet when
    -- off, so the state is the button rather than a word beside it.
    local function toggle(caption, convar, onApply)
        local label = Omerta.HUD.FieldLabel(list, caption)
        label:Dock(TOP)
        label:SetTall(24 * scale)
        label:DockMargin(0, Omerta.HUD.Space(4), 0, 0)

        local on = GetConVar(convar):GetBool()
        local button = Omerta.HUD.Button(list, on and "On" or "Off",
            on and "commit" or "quiet", function()
                local now = not GetConVar(convar):GetBool()
                RunConsoleCommand(convar, now and "1" or "0")
                if onApply then onApply(now) end
                if IsValid(frame) then frame:Rebuild() end
            end)
        button:Dock(TOP)
        button:SetTall(rowH * 0.8)
        button:DockMargin(0, Omerta.HUD.Space(1), 0, 0)
        button:SetWide(120 * scale)
    end

    toggle("Black and white", "omerta_blackwhite")
    toggle("Multi-core rendering", "omerta_mcore", Omerta.Menu.ApplyMulticore)

    local back = Omerta.HUD.Button(list, "Back", "quiet", function()
        M.screen = "root"
        if IsValid(frame) then frame:Rebuild() end
    end)
    back:Dock(TOP)
    back:SetTall(rowH * 0.8)
    back:DockMargin(0, Omerta.HUD.Space(4), 0, 0)
end

--------------------------------------------------------------------------------
-- Multi-core rendering
--------------------------------------------------------------------------------
-- The engine's experimental multithreaded renderer. Other frameworks ship it
-- on; this one does not, and the reason is worth writing down.
--
-- `mat_queue_mode` cannot be changed quietly: the engine tears down and
-- rebuilds the material system to apply it, which takes the VGUI panels with
-- it. The first version of this applied the setting from a Think hook the
-- moment LocalPlayer() became valid — which is the same moment the front-end
-- menu builds itself. The restart ate the menu, and the player was left
-- frozen at spawn with no interface and no error: exactly the symptom
-- reported. So:
--
--   * DEFAULT OFF, until it is proven on real clients.
--   * Never applied automatically. It is applied when a player asks for it,
--     from a screen where a rebuilt material system costs them nothing.
--
-- If it turns out to behave, the default is one character.
CreateClientConVar("omerta_mcore", "0", true, false)

function Omerta.Menu.ApplyMulticore(enabled)
    if enabled == nil then enabled = GetConVar("omerta_mcore"):GetBool() end
    RunConsoleCommand("gmod_mcore_test", enabled and "1" or "0")
    -- The queued material system is the half that actually threads the work;
    -- -1 lets the engine choose, which means off on most setups.
    RunConsoleCommand("mat_queue_mode", enabled and "2" or "-1")
end

--------------------------------------------------------------------------------
-- The handover into the world
--------------------------------------------------------------------------------
-- Confirming a character fades the screen to black, holds it, and lifts it
-- once the character is actually standing in the city. The hold is where M28's
-- intro cinematic will play — it is already the right shape for it, which is
-- why the fade is a small state machine rather than a timer.

local FADE_OUT, FADE_IN = 0.8, 1.2

function Omerta.Menu.BeginSpawnFade()
    spawnFade = { phase = "out", startedAt = CurTime() }
end

-- A refusal (the name was taken while they were reading the warning) must not
-- leave the player staring at black: the form is still there underneath, and
-- it has something to tell them.
hook.Add("Omerta.CharacterCreateFailed", "omerta.menu.fade_cancel", function()
    if spawnFade and spawnFade.phase ~= "in" then spawnFade = nil end
end)

function Omerta.Menu.Client.SpawnFadeAlpha()
    if not spawnFade then return 0 end
    local elapsed = CurTime() - spawnFade.startedAt
    if spawnFade.phase == "out" then
        if elapsed >= FADE_OUT then
            spawnFade.phase = "hold"
            return 1
        end
        return elapsed / FADE_OUT
    elseif spawnFade.phase == "hold" then
        return 1
    end
    if elapsed >= FADE_IN then
        spawnFade = nil
        return 0
    end
    return 1 - (elapsed / FADE_IN)
end

hook.Add("PostRenderVGUI", "omerta.menu.spawn_fade", function()
    local black = Omerta.Menu.Client.SpawnFadeAlpha()
    if black <= 0 then return end
    surface.SetDrawColor(5, 5, 6, 255 * black)
    surface.DrawRect(0, 0, ScrW(), ScrH())
end)

--------------------------------------------------------------------------------
-- What the menu offers
--------------------------------------------------------------------------------

-- Paused, the first thing on the list is the way back out of it.
Omerta.Menu.RegisterEntry("menu.resume", {
    label = "Resume",
    order = 5,
    visible = function() return Omerta.Menu.IsPaused() end,
    onSelect = function() Omerta.Menu.TogglePause() end,
})

Omerta.Menu.RegisterEntry("menu.enter", {
    label = "Enter the city",
    order = 10,
    visible = function() return not Omerta.Menu.IsPaused() end,
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
