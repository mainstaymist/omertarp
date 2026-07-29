-- The death screen: the fade, the words, and the music under them.
--
-- The camera work is in cl_view.lua; this is what is drawn over it, and the
-- sound that carries it. The two are deliberately separate — a camera that
-- cannot fail to move is worth more than one wired to a sound file that might
-- not have downloaded.

Omerta.Injury.Client = Omerta.Injury.Client or {}
local C = Omerta.Injury.Client

-- Both play through sound.PlayFile rather than surface.PlaySound, so both sit
-- on BASS channels that EntityEmitSound cannot silence. The death screen mutes
-- the world; it must not mute itself.
Omerta.Injury.SOUND = {
    TROMBONE = "sound/omertarp/trombone-crescendo.wav",
    PIANO    = "sound/omertarp/death-piano.wav",
    -- Acknowledgement of the keypress. `load` warns and carries on if the file
    -- is not there, so the transition works silently until it is dropped in.
    CONFIRM  = "sound/omertarp/confirm.wav",
}

local TIMING = Omerta.Injury.DEATH_TIMING

--------------------------------------------------------------------------------
-- The music
--------------------------------------------------------------------------------

local channel = nil     -- the looping piano
local sting = nil       -- the one-shot trombone
local requested = false

local function stopAll()
    if channel and channel:IsValid() then channel:Stop() end
    if sting and sting:IsValid() then sting:Stop() end
    channel, sting, requested = nil, nil, false
end

-- cb(channel) on success. Warns and does nothing on failure: a file that did
-- not download costs the sound, never the screen.
local function load(path, cb)
    -- No flags. "noblock" is a streaming flag for PlayURL and is wrong for a
    -- file on disk — it silently returns nothing rather than erroring, which
    -- is how the piano came to never play at all.
    sound.PlayFile(path, "", function(built, errorId, errorName)
        if not built then
            Omerta.Log.Warn("injury", "death audio '%s' did not load (%s: %s)",
                path, tostring(errorId), tostring(errorName))
            return
        end
        cb(built)
    end)
end

local function startMusic()
    -- `requested` rather than `channel`, because PlayFile is asynchronous: the
    -- Think hook would otherwise fire a fresh request every frame until the
    -- first came back, and end up with a stack of overlapping pianos.
    if requested or channel then return end
    requested = true
    load(Omerta.Injury.SOUND.PIANO, function(built)
        requested = false
        if not C.death then built:Stop() return end
        channel = built
        channel:EnableLooping(true)
        channel:SetVolume(0)
        channel:Play()
    end)
end

hook.Add("Think", "omerta.injury.death_music", function()
    if not (C.death or C.leaving) then stopAll() return end

    if C.leaving then
        -- Going out. Nothing new starts once the player has pressed a key.
        if channel and channel:IsValid() then
            local out = Omerta.Injury.ExitMusic(CurTime() - C.leaving.startedAt)
            channel:SetVolume(C.leaving.volume * out)
        end
        return
    end

    local elapsed = CurTime() - C.death.startedAt

    -- The piano waits for the words. It arrives once they are fully there, so
    -- the trombone has the moment to itself.
    if elapsed >= TIMING.TEXT_AT + TIMING.TEXT_OVER then startMusic() end
    if not (channel and channel:IsValid()) then return end

    local since = elapsed - (TIMING.TEXT_AT + TIMING.TEXT_OVER)
    local entry = math.Clamp(since / TIMING.MUSIC_FADE, 0, 1)
    local loop = Omerta.Injury.LoopVolume(channel:GetTime(), channel:GetLength())
    C.leavingVolume = entry * loop
    channel:SetVolume(C.leavingVolume)
end)

--------------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------------
-- Drawn outside the HUD controller on purpose. Every other element on screen
-- answers "does this deserve to be visible right now"; this one is the answer
-- to everything else, and it has to cover them rather than queue behind them.

-- PostRenderVGUI rather than HUDPaintBackground: the exit has to cover the
-- character creator and then lift OFF it, and anything drawn in a HUD hook
-- sits behind VGUI panels. Drawing the whole screen here keeps both halves in
-- one place and one layer.
hook.Add("PostRenderVGUI", "omerta.injury.death_screen", function()
    if C.leaving then
        local elapsed = CurTime() - C.leaving.startedAt
        local black = Omerta.Injury.ExitFade(elapsed)
        if black > 0 then
            surface.SetDrawColor(0, 0, 0, 255 * black)
            surface.DrawRect(0, 0, ScrW(), ScrH())
        end

        local fading = Omerta.Injury.ExitTextAlpha(elapsed)
        if fading > 0 then
            local scale = Omerta.HUD.Scale()
            draw.SimpleText(Omerta.Injury.DEATH_TITLE, Omerta.HUD.Font("headline"),
                ScrW() * 0.5, ScrH() * 0.5,
                Color(226, 214, 198, 255 * fading), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(Omerta.Injury.DEATH_PROMPT, Omerta.HUD.Font("small"),
                ScrW() * 0.5, ScrH() * 0.5 + 30 * scale,
                Color(168, 152, 144, 235 * fading), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return
    end

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
    load(Omerta.Injury.SOUND.TROMBONE, function(built)
        if not C.death then built:Stop() return end
        sting = built
        sting:SetVolume(1)
        sting:Play()
    end)
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

C.leaving = nil -- { startedAt, volume, built }

local function acknowledge()
    if not acceptingInput() then return end

    -- The keypress is answered before anything else happens, so it registers
    -- as a decision rather than as the screen simply vanishing.
    load(Omerta.Injury.SOUND.CONFIRM, function(built)
        built:SetVolume(1)
        built:Play()
    end)

    C.leaving = {
        startedAt = CurTime(),
        volume = C.leavingVolume or 1,
        built = false,
        -- The camera is frozen where the climb left it. Snapping back to the
        -- player entity is invisible behind black, but the first frame of the
        -- reveal would show it.
        view = C.lastDeathView,
    }
    C.death = nil
    Omerta.Net.Request("injury.acknowledge_death", {})
end

hook.Add("Think", "omerta.injury.death_leaving", function()
    if not C.leaving then return end
    local elapsed = CurTime() - C.leaving.startedAt

    -- The next screen is built while the black is still solid, so it is
    -- REVEALED by the fade rather than appearing on top of it. M4 has been
    -- holding the creation window since the moment of death.
    if not C.leaving.built and elapsed >= Omerta.Injury.EXIT.BUILD_AT then
        C.leaving.built = true
        if Omerta.Characters.ReleaseCreation then Omerta.Characters.ReleaseCreation() end
    end

    if Omerta.Injury.ExitDone(elapsed) then
        C.leaving = nil
        C.leavingVolume = nil
        stopAll()
    end
end)

hook.Add("PlayerButtonDown", "omerta.injury.death_any_key", function(ply, button)
    if ply ~= LocalPlayer() then return end
    if gui.IsGameUIVisible() or gui.IsConsoleVisible() then return end
    acknowledge()
end)

-- The creation window waits while the screen is showing. Registered here
-- rather than in M4, so M4 keeps knowing nothing about injuries.
-- Held through the exit as well as the death screen: the window is released
-- deliberately, at the moment the black is solid, by the sequence above.
Omerta.Characters.RegisterCreationGate("injury.death", function()
    if C.death then return true end
    return C.leaving ~= nil and not C.leaving.built
end)
