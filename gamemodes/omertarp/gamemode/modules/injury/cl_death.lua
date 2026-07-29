-- The death screen: the fade, the words, and the music under them.
--
-- The camera work is in cl_view.lua; this is what is drawn over it, and the
-- sound that carries it. The two are deliberately separate — a camera that
-- cannot fail to move is worth more than one wired to a sound file that might
-- not have downloaded.

Omerta.Injury.Client = Omerta.Injury.Client or {}
local C = Omerta.Injury.Client

Omerta.Injury.SOUND = {
    TROMBONE = "omertarp/trombone-crescendo.wav",
    PIANO    = "sound/omertarp/death-piano.wav",
}

local TIMING = Omerta.Injury.DEATH_TIMING

--------------------------------------------------------------------------------
-- The music
--------------------------------------------------------------------------------

local channel = nil

local function stopMusic()
    if channel and channel:IsValid() then channel:Stop() end
    channel = nil
end

local requested = false

local function startMusic()
    -- `requested` rather than `channel`, because PlayFile is asynchronous: the
    -- Think hook would otherwise fire a fresh request every frame until the
    -- first one came back, and end up with a stack of overlapping pianos.
    if requested or channel then return end
    requested = true

    -- No flags. "noblock" is a streaming flag for PlayURL and is wrong for a
    -- file on disk — this is the sort of thing that silently returns nothing
    -- rather than erroring, which is why the music simply never arrived.
    sound.PlayFile(Omerta.Injury.SOUND.PIANO, "", function(built, errorId, errorName)
        requested = false
        if not built then
            -- A missing or undownloaded file costs the music, not the screen.
            Omerta.Log.Warn("injury", "death music did not load (%s: %s)",
                tostring(errorId), tostring(errorName))
            return
        end
        -- Died and moved on while it was loading.
        if not C.death then built:Stop() return end

        channel = built
        channel:EnableLooping(true)
        channel:SetVolume(0)
        channel:Play()
    end)
end

hook.Add("Think", "omerta.injury.death_music", function()
    if not C.death then stopMusic() return end
    local elapsed = CurTime() - C.death.startedAt

    -- The piano waits for the words. It arrives once they are fully there, so
    -- the trombone has the moment to itself.
    if elapsed >= TIMING.TEXT_AT + TIMING.TEXT_OVER then startMusic() end
    if not (channel and channel:IsValid()) then return end

    local since = elapsed - (TIMING.TEXT_AT + TIMING.TEXT_OVER)
    local entry = math.Clamp(since / TIMING.MUSIC_FADE, 0, 1)
    local loop = Omerta.Injury.LoopVolume(channel:GetTime(), channel:GetLength())
    channel:SetVolume(entry * loop)
end)

--------------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------------
-- Drawn outside the HUD controller on purpose. Every other element on screen
-- answers "does this deserve to be visible right now"; this one is the answer
-- to everything else, and it has to cover them rather than queue behind them.

hook.Add("HUDPaintBackground", "omerta.injury.death_screen", function()
    if not C.death then return end
    local elapsed = CurTime() - C.death.startedAt

    local black = Omerta.Injury.DeathFade(elapsed)
    if black > 0 then
        surface.SetDrawColor(0, 0, 0, 255 * black)
        surface.DrawRect(0, 0, ScrW(), ScrH())
    end

    local alpha = Omerta.Injury.DeathTextAlpha(elapsed)
    if alpha <= 0 then return end

    local scale = Omerta.HUD.Scale()
    draw.SimpleText(Omerta.Injury.DEATH_TITLE, Omerta.HUD.Font("headline"),
        ScrW() * 0.5, ScrH() * 0.5,
        Color(226, 214, 198, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- The prompt lags the title slightly, so the words land in order.
    local promptAlpha = math.Clamp((alpha - 0.45) / 0.55, 0, 1)
    if promptAlpha > 0 then
        draw.SimpleText(Omerta.Injury.DEATH_PROMPT, Omerta.HUD.Font("small"),
            ScrW() * 0.5, ScrH() * 0.5 + 30 * scale,
            Color(168, 152, 144, 235 * promptAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end)

--------------------------------------------------------------------------------
-- The trombone
--------------------------------------------------------------------------------
-- Fired the moment death lands, with no fade of its own: the file already
-- opens on one, and layering a second would flatten it.

hook.Add("Omerta.CharacterDiedLocally", "omerta.injury.death_sound", function()
    surface.PlaySound(Omerta.Injury.SOUND.TROMBONE)
end)

--------------------------------------------------------------------------------
-- Any key
--------------------------------------------------------------------------------

-- Held until the words are readable. A player who happened to be pressing
-- something as they died should not skip the moment by accident.
local function acceptingInput()
    if not C.death then return false end
    return Omerta.Injury.DeathTextAlpha(CurTime() - C.death.startedAt) >= 1
end

local function acknowledge()
    if not acceptingInput() then return end
    C.death = nil
    stopMusic()
    Omerta.Net.Request("injury.acknowledge_death", {})
    -- M4 has been holding the creation window since the moment of death.
    if Omerta.Characters.ReleaseCreation then Omerta.Characters.ReleaseCreation() end
end

hook.Add("PlayerButtonDown", "omerta.injury.death_any_key", function(ply, button)
    if ply ~= LocalPlayer() then return end
    if gui.IsGameUIVisible() or gui.IsConsoleVisible() then return end
    acknowledge()
end)

-- The creation window waits while the screen is showing. Registered here
-- rather than in M4, so M4 keeps knowing nothing about injuries.
Omerta.Characters.RegisterCreationGate("injury.death", function()
    return C.death ~= nil
end)
