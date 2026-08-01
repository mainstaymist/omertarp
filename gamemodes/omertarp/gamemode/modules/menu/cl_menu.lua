-- The front end on screen: the intro, the camera behind it, and the menu.
--
-- The same rail serves twice. As the FRONT END it meets EVERY player who joins;
-- as the PAUSE MENU it answers F1 during normal play — same entries, same
-- standard, but no intro, no music, and no orbit camera, because pausing must
-- not become a tour of the spawn vantage.
--
-- EVERY player: somebody who already has a character is met by the menu too
-- (project lead, 2026-08-01), and is held out of the city until they choose to
-- walk into it. The rail therefore has two ways in, at the same place in the
-- list and never both at once — "Enter the city" for somebody who has nobody to
-- be, "Return to the city" for somebody who has. The first goes to creation;
-- the second says one word to the server and lets it do the rest.
--
-- The menu stands exactly where the character creator used to appear, and
-- HOSTS it: creation is a screen of the menu, over the same drifting camera,
-- built from the same form component (M4's BuildCreationForm) — not a window
-- floating on top. The menu registers a CREATION GATE — the same seam M19's
-- death screen uses to hold the handover — and never releases it; a new arrival
-- goes through creation, and a finished character closes everything.
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
M.wanted = false    -- the server says this player is not in the city
M.awaiting = false  -- ...and they already have somebody to be waiting for them
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
    -- Close, not Remove: the pause rail fades out rather than blinking away.
    -- The local reference is deliberately KEPT while it does — Build() clears
    -- whatever is there before making a new one, and a handle we had thrown
    -- away would leave the outgoing rail on screen underneath the incoming one.
    if IsValid(frame) then frame:Close() end
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

-- F1 is POLLED, not bound, for the same reason the inventory key is: the
-- moment the menu takes the mouse it also takes the keyboard, and
-- PlayerBindPress stops firing — so the bind could open the menu and then
-- never hear the keypress that was meant to close it. Reading the physical
-- key works whatever has focus.
--
-- The bind is still swallowed below so the engine's own help panel never
-- opens behind ours.
local f1WasDown = false

hook.Add("Think", "omerta.menu.pause_key", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    -- M7's chat box suppresses the engine's, so Player:IsTyping no longer
    -- knows when somebody is mid-sentence; ask the module that does.
    local chatting = (ply.IsTyping and ply:IsTyping())
        or (Omerta.Chat and Omerta.Chat.IsTyping and Omerta.Chat.IsTyping())
    local down = input.IsKeyDown(KEY_F1) and not chatting
        and not gui.IsGameUIVisible() and not gui.IsConsoleVisible()
    local pressed = down and not f1WasDown
    f1WasDown = down

    if pressed then Omerta.Menu.TogglePause() end
end)

hook.Add("PlayerBindPress", "omerta.menu.pause", function(_, bind)
    if bind == "gm_showhelp" then return true end
end)

-- Walking into the city with a character that already exists.
--
-- This is a REQUEST, and it is all the client is allowed to be: it names
-- nobody, carries nothing, and cannot release anything. The server re-reads the
-- account, the season and the living character, lifts the movement gate itself,
-- and answers with STATE.ACTIVE — which is what actually takes this screen
-- down, in the state hook below. Tearing the menu down here instead would put
-- the player in front of a world they had not been let into yet.
--
-- The black falls on the keypress rather than on the answer, exactly as
-- confirming a character does: the wait is a database round trip and a spawn,
-- which is the least cinematic moment available, and the fade is where M28's
-- opening will live for the people it is actually for.
function Omerta.Menu.Enter()
    if not M.awaiting then return end
    -- NOT THE CINEMATIC (project lead: "though not the cinematic of course").
    -- The intro is the title card on the way IN to the menu and everybody gets
    -- it; the cinematic is the arrival, and somebody who has been living here
    -- since Tuesday is not arriving. Nothing plays in the hold today, so this
    -- is a fact recorded at the one place that knows it rather than a behaviour
    -- — M28 reads it instead of having to work out, from the far side of a
    -- fade, which of the two kinds of entry it is looking at.
    Omerta.Menu.BeginSpawnFade({ cinematic = false })
    Omerta.Net.Request("characters.enter", {})
end

-- The gate. While the front end is up, nothing else may put a window on
-- screen; M4's creator waits exactly as it waits for the death sequence.
Omerta.Characters.RegisterCreationGate("menu", function()
    return M.phase ~= nil
end)

-- The server says this player is not in the city. Two ways to not be in it —
-- with nobody to be, and with somebody waiting — and the front end goes up for
-- both; only the way OUT of the rail differs.
--
-- The menu does not appear on that signal alone, though: after a death the
-- death sequence is still playing, and the menu must be revealed BY its fade
-- rather than appear on top of it — so it waits until nothing else is holding
-- the handover.
--
-- NO_SEASON is deliberately not in here. A city that is closed has nothing for
-- an "Enter" to do, and a rail whose first entry cannot work is worse than the
-- plain notice M4 already shows for it.
hook.Add("Omerta.CharactersState", "omerta.menu.state", function(state)
    local STATE = Omerta.Characters.STATE
    if state == STATE.NEEDS_CREATION or state == STATE.AWAITING_ENTRY then
        M.wanted = true
        M.awaiting = state == STATE.AWAITING_ENTRY
        -- A refusal must not leave somebody staring at black. If they asked to
        -- come in and the answer was "you have no character" — staff retired it
        -- while they read the menu, a season ended — the fade is cancelled and
        -- the rail is still underneath, now offering creation instead.
        if state == STATE.NEEDS_CREATION and spawnFade and spawnFade.phase ~= "in" then
            spawnFade = nil
        end
        -- The rail's first entry has just changed identity; rebuild so the
        -- player is not reading the other one's label. Only on the root: this
        -- message can arrive again at any time (the readiness handshake repeats
        -- it, a staff retirement sends it) and rebuilding the creation screen
        -- underneath somebody would throw away the name they were typing.
        if M.phase == "menu" and M.screen == "root" and IsValid(frame) then
            frame:Rebuild()
        end
    elseif state == STATE.ACTIVE then
        M.wanted, M.awaiting = false, false
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

--------------------------------------------------------------------------------
-- The masthead, and the floor underneath it
--------------------------------------------------------------------------------
-- THE ONE PLACE THAT SAYS WHERE THE RAIL'S CONTENT BEGINS.
--
-- Two lines of type sit at the top of the rail — the wordmark over the tagline
-- on the root and on settings, "NEW ARRIVAL" over "WHO ARE YOU" on creation —
-- and everything else in the rail hangs below them. There used to be four
-- opinions about where "below" was: the paint that draws the words, the root
-- list, the creation column, and Settings, which had no opinion at all and
-- centred itself on the screen. That is how INTERFACE SCALE ended up printed
-- across "There are no witnesses."
--
-- So the words and the floor under them are worked out together, once, here,
-- and every screen asks. A screen that measures the wordmark for itself is a
-- screen that will one day be laid over it again.
--
-- Returns { eyebrow, title, subtitle, contentTop, contentCeiling } — the first
-- three are text baselines for TEXT_ALIGN_BOTTOM draws (nil where that line
-- does not exist), and the last two are the two numbers a screen needs:
--
--   contentTop      where content RESTS, which is where it belongs.
--   contentCeiling  the smallest Y it may ever be pushed to — one step under
--                   the last line of the masthead. A tall screen may borrow the
--                   space between the two to fit itself; nothing may cross the
--                   ceiling, because the wordmark is the thing all of this
--                   exists to stop being drawn over.
--
-- Creation keeps a taller block than the root's. It is not a stylistic
-- preference: its column runs from contentTop to the bottom margin and hosts a
-- form with two name fields, two pickers, a status line and a docked button
-- row, and the last time that column was made shorter than the form it holds,
-- Confirm went off the bottom of the screen at 1.5x. The root's own block sits
-- lower because a list of four entries wants to be nearer the middle of the
-- screen than the top of it.
function Omerta.Menu.Client.Masthead()
    local scale = Omerta.HUD.Scale()
    local middle = ScrH() * 0.5

    if M.screen == "creation" then
        local top = middle - 258 * scale + Omerta.HUD.Space(4)
        return {
            eyebrow = middle - 300 * scale,
            title = middle - 258 * scale,
            -- Creation's column already begins immediately under its heading,
            -- so there is nothing between rest and ceiling for it to borrow.
            contentTop = top,
            contentCeiling = top,
        }
    end

    local title = middle - ROW_H * scale * 2.6
    local subtitle = title + 26 * scale
    return {
        title = title,
        subtitle = subtitle,
        contentTop = middle - ROW_H * scale,
        contentCeiling = subtitle + Omerta.HUD.Space(1),
    }
end

function Omerta.Menu.Client.Build()
    if IsValid(frame) then frame:Remove() end
    if M.phase ~= "menu" then return end

    local scale = Omerta.HUD.Scale()
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

        -- Drawn from the same block every screen lays itself out against, so
        -- the words and what sits under them cannot drift apart.
        local head = Omerta.Menu.Client.Masthead()
        if M.screen == "creation" then
            draw.SimpleText("NEW ARRIVAL", Omerta.HUD.Font("mono"),
                margin, head.eyebrow, Omerta.HUD.Colour("dim"),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
            draw.SimpleText("WHO ARE YOU", Omerta.HUD.Font("headline"),
                margin, head.title, Omerta.HUD.Colour("text"),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        else
            draw.SimpleText(string.upper(Omerta.Menu.TITLE),
                Omerta.HUD.Font("title"), margin, head.title,
                Omerta.HUD.Colour("text"), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
            draw.SimpleText(Omerta.Menu.SUBTITLE, Omerta.HUD.Font("label"),
                margin, head.subtitle,
                Omerta.HUD.Colour("secondary"), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        end

        -- The city, and which season of it. Both are public — it is the city
        -- everybody is playing in — and the season is a NUMBER now, sent to the
        -- client by M3 as one uint and nothing else.
        --
        -- Soft reference throughout: Omerta.Seasons is mostly a server table,
        -- so a client that has not been told the number yet (or is on a server
        -- with no season running) reads "THE CITY" and says nothing it does not
        -- know. The number never comes from `label` on this side — the client
        -- has never seen that column, which is exactly why it cannot read the
        -- wrong field of it.
        local seasons = Omerta.Seasons
        local number = seasons and seasons.GetNumber and seasons.GetNumber() or nil
        draw.SimpleText(string.upper(number and ("The city · Season " .. number)
                or "The city"),
            Omerta.HUD.Font("mono"), margin, h - margin,
            Omerta.HUD.Colour("dim"), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    end

    -- THE PAUSE RAIL IS REVEALED; THE FRONT END IS NOT. Both are this same
    -- panel, and they are not the same kind of thing.
    --
    -- The front end is not a popup — it is the screen the game OPENS on, over a
    -- drifting camera, and it is revealed by the intro's black lifting off it
    -- (or, after a death, by the death sequence handing over). It has no
    -- "before" to arrive from: there is nothing on screen for it to appear in
    -- front of, so an entrance animation would be the interface announcing
    -- itself to a player who has not yet been given anything else to look at,
    -- and it would run UNDER the intro's own fade, where it cannot be seen
    -- anyway. Fading the opening screen in a second time is not polish, it is
    -- two fades fighting.
    --
    -- Pause genuinely pops up: the player is standing in the street, presses
    -- F1, and something arrives over the top of what they were doing. That is
    -- exactly the moment the reveal exists for, and it is worth the tenth of a
    -- second on the way back out for the same reason it is worth it on the
    -- inventory — the way out of a pause is a thing done hundreds of times.
    --
    -- NO RISE, EITHER WAY. This frame is the whole screen. Moving a full-screen
    -- panel 42px up means 42px of bare, unblurred world along the top edge for
    -- the length of the animation, which does not read as a window arriving —
    -- it reads as the interface having come unstuck from the screen. The rail
    -- inside it could be made to travel on its own, but that is a second
    -- animation with its own state, driven from a different place than every
    -- other window in the game, to buy motion on the one screen that is already
    -- moving (the camera is orbiting behind it). The fade is the whole reveal
    -- here, which the shared helper supports as rise = 0.
    if M.mode == "pause" then
        Omerta.HUD.Reveal(frame, { rise = 0 })
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
        -- Every screen of the rail that is not the root is backed out of the
        -- same way, so the way out is never a button you have to find. On
        -- settings that is also the guarantee that the screen cannot trap
        -- somebody whose column has run past the bottom edge.
        if M.screen == "creation" or M.screen == "settings" then
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
    list:SetPos(margin, Omerta.Menu.Client.Masthead().contentTop)
    list:SetSize(columnW, rowH * 6)
    list:SetPaintBackground(false)

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
    local top = Omerta.Menu.Client.Masthead().contentTop
    local column = vgui.Create("DPanel", parent)
    column.OmertaOwned = true
    column:SetPos(margin, top)
    column:SetSize(columnW, ScrH() - top - margin)
    column:SetPaintBackground(false)

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

-- Laid out by HAND, top down, rather than by docking.
--
-- The docked version put every control in the column and let the layout engine
-- decide where they landed, and it kept getting it wrong in ways that read as
-- a broken screen: a panel too short clipped the last two controls off the
-- end, then seven scale buttons sharing a fixed rail overflowed it and ran
-- through each other. Both are the same mistake — asking a container to
-- arrange things whose total size nobody had actually added up.
--
-- So this walks a cursor down the column, and every control says how tall it
-- is on the way past. The panel is then exactly as tall as what is in it,
-- which is a thing that cannot be off by a row.
--
-- WHERE the column starts is no longer this screen's business. It used to
-- centre itself on the screen, which is a perfectly good answer to a question
-- nobody asked — the rail has a masthead, and centring walked the first caption
-- straight over the tagline. It asks Masthead() like every other screen now.
function Omerta.Menu.Client.BuildSettings(parent)
    local scale = Omerta.HUD.Scale()
    local margin = Omerta.HUD.Space(5)
    local rowH = ROW_H * scale
    local labelH = 24 * scale
    local gap = Omerta.HUD.Space(1)
    local block = Omerta.HUD.Space(4) -- between one setting and the next

    local list = vgui.Create("DPanel", parent)
    list.OmertaOwned = true
    -- SetPaintBackground, not `Paint = nil`. Clearing the field only removes
    -- the instance override — the lookup then finds DPanel's own Paint on the
    -- class table and draws the stock Derma background underneath everything.
    list:SetPaintBackground(false)

    local width = COLUMN_W * scale
    local y = 0

    local function caption(text)
        local label = Omerta.HUD.FieldLabel(list, text)
        label:SetPos(0, y)
        label:SetSize(width, labelH)
        y = y + labelH + gap
    end

    -- One cycler rather than a button per step.
    --
    -- Seven values do not fit across a column as seven buttons — that is what
    -- was overlapping — and they will not fit as eight or nine either, so
    -- widening the rail only moves the failure. The cycler shows the value
    -- that is set and steps either side of it, which is the same control at
    -- any number of steps and the one the design system already has for this.
    caption("Interface scale")

    local steps = Omerta.HUD.SCALE_STEPS
    local stored = Omerta.HUD.ClampScale(GetConVar("omerta_ui_scale"):GetFloat())
    local items, chosen = {}, 1
    for index, value in ipairs(steps) do
        items[index] = { label = value .. "x", value = value }
        if math.abs(stored - value) < 0.01 then chosen = index end
    end

    local cycler = Omerta.HUD.Cycler(list, items, chosen, function(item)
        RunConsoleCommand("omerta_ui_scale", tostring(item.value))
        -- Rebuilt a frame later, once the fonts have been remade at the new
        -- size — rebuilding now would lay the screen out with the old ones.
        timer.Simple(0.05, function()
            if M.phase == "menu" then Omerta.Menu.Client.Build() end
        end)
    end)
    cycler:SetPos(0, y)
    cycler:SetSize(width, rowH)
    y = y + rowH + block

    -- A toggle reads its convar and restyles: lit (commit) when on, quiet when
    -- off, so the state is the button rather than a word beside it.
    -- A toggle reads its convar and restyles: lit when on, quiet when off, so
    -- the state IS the button rather than a word beside it.
    --
    -- It follows the convar rather than rebuilding on the click, and that is
    -- the fix for a reported bug: RunConsoleCommand does not set a convar, it
    -- QUEUES a console command, which the engine runs at the end of the frame.
    -- Rebuilding on the next line therefore re-read the OLD value and drew the
    -- old button, while the setting itself applied perfectly — "the button
    -- doesn't change but the setting works, and it's right when I come back",
    -- exactly as reported.
    --
    -- Watching the value instead of predicting it is also correct for the case
    -- nobody thought about: the convar changed from the console, or by another
    -- screen, while this one is open.
    local function toggle(text, convar, onApply)
        caption(text)
        local built = GetConVar(convar):GetBool()
        local button = Omerta.HUD.Button(list, built and "On" or "Off",
            built and "commit" or "quiet", function()
                local now = not GetConVar(convar):GetBool()
                RunConsoleCommand(convar, now and "1" or "0")
                if onApply then onApply(now) end
            end)
        button:SetPos(0, y)
        button:SetSize(140 * scale, rowH * 0.8)
        -- One comparison per frame on a screen with three controls on it. The
        -- rebuild is what restyles the button, because a Button bakes its
        -- style at construction — and it lands the frame after the console
        -- command actually ran, which is the whole point.
        button.Think = function()
            if GetConVar(convar):GetBool() == built then return end
            if IsValid(frame) then frame:Rebuild() end
        end
        y = y + rowH * 0.8 + block
    end

    toggle("Black and white", "omerta_blackwhite")
    toggle("Multi-core rendering", "omerta_mcore", Omerta.Menu.ApplyMulticore)

    local back = Omerta.HUD.Button(list, "Back", "quiet", function()
        M.screen = "root"
        if IsValid(frame) then frame:Rebuild() end
    end)
    back:SetPos(0, y)
    back:SetSize(140 * scale, rowH * 0.8)
    y = y + rowH * 0.8

    -- Sized to what is actually in it, and placed under the masthead.
    --
    -- The old clamp centred the column and then pulled it off the bottom edge,
    -- which is what printed INTERFACE SCALE across the tagline. This one moves
    -- between the masthead's two numbers and no further: it rests at
    -- contentTop, and only if the column will not otherwise reach the bottom
    -- margin — which happens on a 1080p screen at the largest interface scale,
    -- where three settings and a Back button come to more than half the height
    -- of the display — does it borrow upward, stopping dead at contentCeiling.
    -- Past that the column simply runs long, and ESCAPE (above) is the way out
    -- rather than a Back button dragged over the wordmark to be reachable.
    local head = Omerta.Menu.Client.Masthead()
    list:SetSize(width, y)
    list:SetPos(margin, math.max(head.contentCeiling,
        math.min(head.contentTop, ScrH() - margin - y)))
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

-- opts.cinematic says whether the hold is an ARRIVAL — somebody's first moment
-- in the city, which is what M28's opening is for — or merely the cover over a
-- round trip. Defaults to true, because the caller that has always existed is
-- character creation and that IS an arrival; "Return to the city" passes false
-- (project lead: "though not the cinematic of course").
--
-- Recorded rather than acted on: nothing plays in the hold today. It is put
-- here because THIS is the only place that knows which of the two it is, and a
-- flag written at the moment the fact is true is worth more than M28 trying to
-- infer it later from the far side of a black screen.
function Omerta.Menu.BeginSpawnFade(opts)
    opts = opts or {}
    spawnFade = {
        phase = "out",
        startedAt = CurTime(),
        cinematic = opts.cinematic ~= false,
    }
end

-- A refusal (the name was taken while they were reading the warning) must not
-- leave the player staring at black: the form is still there underneath, and
-- it has something to tell them.
hook.Add("Omerta.CharacterCreateFailed", "omerta.menu.fade_cancel", function()
    if spawnFade and spawnFade.phase ~= "in" then spawnFade = nil end
end)

-- The hold is bounded. It covers a round trip, and a round trip that never
-- comes back must not leave somebody staring at a black screen they cannot
-- press anything through — which is now reachable in a way it was not before:
-- "Return to the city" starts the fade and then waits on a server that could,
-- in principle, have nothing to say (an account still loading, a season ending
-- in the same second). After this the black lifts and puts them back on the
-- rail they pressed it from, which is a screen with a way out on it.
--
-- A CEILING, not a duration. M28's opening plays inside this hold and will want
-- longer; raising it then is one number, and it is a number that exists.
local HOLD_MAX = 8

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
        if elapsed >= FADE_OUT + HOLD_MAX then
            Omerta.Log.Warn("menu", "the handover into the world went unanswered " ..
                "for %d seconds — lifting the black rather than holding it", HOLD_MAX)
            spawnFade = { phase = "in", startedAt = CurTime(), cinematic = false }
        end
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

-- THE WAY IN, which is two entries because there are two kinds of player in
-- front of this rail and only one kind of first item.
--
-- They share an order and are mutually exclusive, so the way into the city is
-- always the top line of the list whoever is reading it — the muscle memory a
-- front end is allowed to have. What differs is the promise each one makes:
-- "Enter" leads to a form and a name that cannot be taken back, "Return" leads
-- straight through the door to somebody who is already standing behind it. One
-- label for both would have made the irreversible one look like the routine one.
Omerta.Menu.RegisterEntry("menu.enter", {
    label = "Enter the city",
    order = 10,
    visible = function() return not Omerta.Menu.IsPaused() and not M.awaiting end,
    onSelect = function()
        M.screen = "creation"
        if IsValid(frame) then frame:Rebuild() end
    end,
})

Omerta.Menu.RegisterEntry("menu.return", {
    label = "Return to the city",
    order = 10,
    visible = function() return not Omerta.Menu.IsPaused() and M.awaiting end,
    onSelect = function() Omerta.Menu.Enter() end,
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
