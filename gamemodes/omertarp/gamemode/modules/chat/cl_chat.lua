-- The chat box: what people said, and the line you say it on.
--
-- The name in each message was resolved by the server for THIS listener, so
-- this file never decides who anyone is — it only draws what it was told. That
-- is why two players in the same room legitimately see different names on the
-- same sentence.
--
-- Until now the drawing was chat.AddText, which paints GMod's stock
-- orange-and-white box: rounded, permanent, and the loudest thing on a screen
-- the design wants EMPTY (GDD §8). Everything below replaces that rendering
-- and nothing else. What the server sends, who hears it and how far it carries
-- are untouched.
--
-- The design tokens come from the hud module, which is not in this module's
-- `depends` — it arrives transitively through identity. That has held since
-- M8 and the include order enforces it, but if identity ever stops depending
-- on hud, this file is what breaks, and it breaks at include time.

--------------------------------------------------------------------------------
-- Italic, for narration
--------------------------------------------------------------------------------
-- "Tiny Marino coughs" is an action, not a sentence anyone said out loud, and
-- the asterisks the old renderer prefixed were a workaround for a chat box
-- that could not change typeface. This one can.
--
-- The font is built HERE rather than added to the design system's role table:
-- cl_hud.lua builds one font per role in Omerta.HUD.Theme.TYPE and italic is
-- not a role, it is a variant of one. Size and face still come from the theme,
-- so the emote line tracks the standard and the accessibility scale exactly as
-- every other piece of type does.
--
-- There is no italic Germania One file — the family ships one weight (see
-- content/resource/fonts) — so the rasteriser synthesises the oblique. That is
-- the compromise cl_hud.lua refuses to make for WEIGHT, where a real file
-- exists and a faked bold looks like a mistake; a synthesised slant of a
-- display face is legible and unmistakably not upright, which is the whole
-- job here.

Omerta.Chat = Omerta.Chat or {}

local EMOTE_FONT = "Omerta.Chat.Emote"

local function buildFonts()
    local theme = Omerta.HUD.Theme
    local def = theme.TYPE.body
    surface.CreateFont(EMOTE_FONT, {
        font = theme.FACE[def.face] or theme.FACE.text,
        size = math.Round(theme.TypeSize("body") * Omerta.HUD.Scale()),
        italic = true,
        antialias = true,
    })
end

buildFonts()

-- Rebuilt on the accessibility scale exactly as cl_hud.lua rebuilds its own,
-- under a DIFFERENT identifier: cvars.AddChangeCallback keys by name, and
-- reusing "omerta.hud.fonts" would silently unhook the design system's own
-- rebuild and leave the whole interface at the old size.
cvars.AddChangeCallback("omerta_ui_scale", buildFonts, "omerta.chat.fonts")

--------------------------------------------------------------------------------
-- The history
--------------------------------------------------------------------------------
-- Bounded, and bounded in MESSAGES rather than in drawn lines: a transcript is
-- not a feature of this game. What has scrolled away is gone, the same way it
-- is gone for the character.

local MAX_MESSAGES = 10
local HOLD = 12       -- seconds a line stays fully present after arriving
local FADE = 2.2      -- seconds it takes to leave
local RISE = 0.12     -- the guide's 120ms in

-- Oldest first. Each entry is { at, text, token, role, italic } plus the
-- wrapping cache the draw pass fills in.
local history = {}

local typing = false
local typed = ""
local closedAt = 0

local function push(entry)
    entry.at = CurTime()
    history[#history + 1] = entry
    Omerta.Chat.TrimHistory(history, MAX_MESSAGES)
end

-- Full presence while the player is typing, and for one fade afterwards.
--
-- You cannot answer what you cannot read: opening the box brings back
-- everything still in the history, however long ago it was said, and lets go
-- of it gently when the box closes rather than snapping it away.
local function wakePresence()
    if typing then return 1 end
    if closedAt <= 0 then return 0 end
    return Omerta.Chat.LineAlpha(CurTime() - closedAt, 0, FADE, 0)
end

local function presenceOf(entry)
    local natural = Omerta.Chat.LineAlpha(CurTime() - entry.at, HOLD, FADE, RISE)
    local wake = wakePresence()
    return natural > wake and natural or wake
end

--------------------------------------------------------------------------------
-- Colour, from the channel, through the palette
--------------------------------------------------------------------------------
-- A channel carries its own {r,g,b} and later milestones' channels will too —
-- M11's radios, M12's phone. The standard allows six hex and nothing else, so
-- the declared colour is honoured by mapping it to the nearest NEUTRAL token
-- rather than by being drawn.
--
-- Brass and the danger red are deliberately absent from the candidates: the
-- accent marks the one selected thing and the red marks the irreversible, and
-- a channel that registered a gold would otherwise quietly claim the accent
-- for every sentence anyone spoke on it.
local function neutralTokens()
    local palette = Omerta.HUD.Theme.COLOUR
    return {
        { token = "text",      colour = palette.text },
        { token = "secondary", colour = palette.secondary },
        { token = "dim",       colour = palette.dim },
    }
end

local function tokenFor(channel)
    return Omerta.Chat.PaletteToken(channel.colour, neutralTokens()) or "text"
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------

hook.Add("Omerta.ChatReceived", "omerta.chat.render", function(payload)
    local channel = Omerta.Chat.GetByIndex(payload.channel)
    if not channel then return end

    local token = tokenFor(channel)

    if channel.system then
        -- The game talking, not a person: the small role and a quiet tone, so
        -- a refusal never looks like something a character in the room said.
        push({ text = payload.text, token = token, role = "small" })
        return
    end

    -- Narration. The signal is the CHANNEL, never the text: the wire carries
    -- the channel's index and sh_chat marks that channel `emote`, so the
    -- client never has to guess from a leading "/me" — which the server has
    -- already eaten anyway, and which somebody quoting a command in ordinary
    -- speech would otherwise trip.
    --
    -- The asterisks are gone with it. "** Tiny Marino coughs" was a stock chat
    -- box saying "this is not speech" in the only vocabulary it had; italics
    -- say it in the game's own.
    if channel.emote then
        push({
            text = payload.name .. " " .. payload.text,
            token = token, role = "body", italic = true,
        })
        return
    end

    -- 'Tony Marino says "Evening."' — one colour for the whole line. The
    -- stock box painted the speaker and the sentence in two different colours
    -- because it had nothing else to work with; the standard allows six hex
    -- and colours nothing but the selected and the irreversible. The quotes
    -- are what separate the man from his words, and always were.
    push({
        text = payload.name .. " " .. channel.label .. " \"" .. payload.text .. "\"",
        token = token, role = "body",
    })
end)

-- Everything else in the gamemode that speaks through GMod's chat.
--
-- organizations and business both call chat.AddText, and hiding CHudChat below
-- would swallow their lines without a word. Those modules belong to other
-- people this week, so the box takes ownership of the FUNCTION instead: same
-- text, drawn here, in the small secondary voice a notice deserves. The
-- engine's own copy is not fed — it is hidden, and a buffer nobody can see is
-- just a leak. Migrating those call sites onto Omerta.Chat.Notice would let
-- this override go.
function chat.AddText(...)
    local words = {}
    for _, part in ipairs({ ... }) do
        if type(part) == "string" then words[#words + 1] = part end
    end
    local text = table.concat(words)
    if text ~= "" then
        push({ text = text, token = "secondary", role = "small" })
    end
end

hook.Add("Omerta.CharactersState", "omerta.chat.reset", function()
    -- A new character does not inherit the last one's conversations.
    history = {}
    typed, closedAt = "", 0
end)

--------------------------------------------------------------------------------
-- Taking the input line
--------------------------------------------------------------------------------
-- The first version of this tried to keep the engine's own entry and read it
-- through ChatTextChanged, on the belief that hiding CHudChat suppressed the
-- DRAWING and left the entry working underneath. It does not. Hiding the
-- element hides the entry with it, and a hidden panel cannot take the
-- keyboard: the box opened, the channel chip appeared, and not one character
-- could be typed into it. Reported as "I can start the chat box, but I can't
-- type into it", which is exactly what that is.
--
-- So the keyboard is ours now. A popup panel holds a DTextEntry that is never
-- painted; the line on screen is still drawn by drawInput below, over the
-- world, with the hard outline every other piece of text in this game gets and
-- a DTextEntry cannot be made to draw. The entry exists to be typed into and
-- for nothing else.
--
-- What reaches the server is unchanged: `say` runs the same console command
-- the engine would have run, PlayerSay fires on the other side, and M7's
-- parser sees the identical string. Nothing about channels, range or logging
-- knows this file was rewritten.

-- Named inputPanel rather than input: `input` is the engine's keyboard
-- library, and a file-local of that name would shadow it for everything below.
local inputPanel = nil -- the popup panel, while the box is open
local entry = nil      -- the invisible DTextEntry inside it

-- Read by the inventory's C poll and the menu's F1 poll. Those read the
-- PHYSICAL key every frame precisely so that nothing can swallow the release
-- — which also means nothing stops them firing mid-sentence. Player:IsTyping
-- used to cover it and no longer can: the engine's box never opens now, so as
-- far as the engine is concerned nobody is ever typing.
function Omerta.Chat.IsTyping()
    return typing
end

local function closeChat()
    if IsValid(inputPanel) then inputPanel:Remove() end
    inputPanel, entry = nil, nil
    if typing then closedAt = CurTime() end
    typing, typed = false, ""
end

local function send(text)
    text = string.Trim(text or "")
    if text == "" then return end
    -- The console command, not a net message. `say` is what the engine would
    -- have issued, and going through it keeps this file out of the path
    -- between a player and the server: rate limiting, length capping and
    -- PlayerSay all behave exactly as they did.
    RunConsoleCommand("say", text)
end

local function openChat()
    if IsValid(inputPanel) then return end
    typing, typed = true, ""

    -- Sized to the screen so a stray click cannot reach the world while the
    -- keyboard is captured. Squeezing a gun off mid-sentence is a worse
    -- failure than a dead click.
    inputPanel = vgui.Create("EditablePanel")
    inputPanel:SetSize(ScrW(), ScrH())
    inputPanel:SetPos(0, 0)
    inputPanel:MakePopup()

    entry = vgui.Create("DTextEntry", inputPanel)
    entry:SetSize(1, 1)
    entry:SetPos(-8, -8) -- clipped away; it is typed into, never looked at
    entry.Paint = function() end
    entry:RequestFocus()

    entry.OnChange = function(self)
        typed = self:GetValue() or ""
    end

    entry.OnEnter = function(self)
        local text = self:GetValue()
        closeChat()
        send(text)
    end

    -- Escape has to be caught here. A popup panel that ignores it hands the
    -- key to the engine, which opens the game menu over a chat box that is
    -- still capturing the keyboard underneath.
    local baseKeys = entry.OnKeyCodeTyped
    entry.OnKeyCodeTyped = function(self, code)
        if code == KEY_ESCAPE then
            closeChat()
            return true
        end
        if baseKeys then return baseKeys(self, code) end
    end

    -- The keypress that opened the box belongs to the bind, not to the
    -- sentence. It is consumed a frame before the entry has focus in every
    -- case seen so far, but a leaked "y" at the head of every line is a
    -- cheap thing to make impossible.
    timer.Simple(0, function()
        if not IsValid(entry) then return end
        entry:SetText("")
        entry:SetCaretPos(0)
        typed = ""
    end)
end

-- Returning false from any listener is enough, and every listener on this hook
-- only ever returns false or nothing — so injury's death-time suppression and
-- the menu's cannot fight with this one whichever order they run in.
hook.Add("HUDShouldDraw", "omerta.chat.hide_engine", function(name)
    if name == "CHudChat" then return false end
end)

-- StartChat is the ONE place the box opens, and returning true suppresses the
-- engine's own entirely. Using it rather than PlayerBindPress on messagemode
-- means this works whatever the player has chat bound to, and whatever else
-- opens chat — a bind, chat.Open from another addon, the console.
hook.Add("StartChat", "omerta.chat.open", function()
    openChat()
    return true
end)

-- The engine's box is suppressed, so this only fires if something closed a
-- chat we did not open. Keeping ours in step with it costs one line.
hook.Add("FinishChat", "omerta.chat.close", closeChat)

-- Nobody types through their own death. The screen belongs to the moment, the
-- chat block hides itself for the same reason, and a captured keyboard behind
-- a death card is a player who cannot press the any-key it asks for.
hook.Add("Think", "omerta.chat.guard", function()
    if not typing then return end
    if not IsValid(LocalPlayer()) then closeChat() return end
    local C = Omerta.Injury and Omerta.Injury.Client
    if C and (C.death or C.leaving) then closeChat() return end
    -- Focus is the whole point of the panel; if anything takes it, the box is
    -- a lie. Cheap to check and it cannot loop, because RequestFocus on the
    -- panel that already has focus does nothing.
    if IsValid(entry) and not entry:HasFocus() then entry:RequestFocus() end
end)

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------
-- The OUTLINE, not the plate.
--
-- The guide gives a cluster of more than three lines an ink scrim, and a full
-- history is exactly that — but only sometimes. This block is one line as
-- often as it is eight, it changes height with every sentence anyone in the
-- street says, and it has to be able to reach nothing at all so an idle screen
-- is empty. A plate that resizes on every message and blinks into existence
-- when a stranger speaks is a rectangle flashing in the corner of the eye; the
-- scrim is for a cluster that arrives as one object and stays put, which is
-- what the verb menu and the timed-action prompt are. The hard 1px outline
-- keeps every line legible over any background at any count and lets the whole
-- block dissolve to nothing, which is the behaviour the milestone asks for.

local function fontFor(entry)
    if entry.italic then return EMOTE_FONT end
    return Omerta.HUD.Font(entry.role)
end

-- The same four-offset hard outline Omerta.HUD.Text applies, against a font
-- NAME rather than a role: the italic variant is not a design-system role and
-- must not become one, so it cannot go through the helper.
local function outlined(text, font, x, y, colour)
    local shadow = Color(0, 0, 0, colour.a or 255)
    draw.SimpleText(text, font, x + 1, y, shadow, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText(text, font, x - 1, y, shadow, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText(text, font, x, y + 1, shadow, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText(text, font, x, y - 1, shadow, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText(text, font, x, y, colour, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
end

local function measurerFor(font)
    return function(text)
        surface.SetFont(font)
        local wide = surface.GetTextSize(text)
        return wide
    end
end

local function lineHeight(font)
    surface.SetFont(font)
    -- An ascender and a descender: measuring the message itself gives a line
    -- of "no" less height than a line of "Tony", and the block would breathe
    -- as people talked.
    local _, tall = surface.GetTextSize("Ag")
    return tall
end

-- Cached against the column it was wrapped for, because re-measuring every
-- line of every message every frame is a text-size call per word per frame.
-- The scale is part of the key: the font changes with it, so the same column
-- holds a different number of words.
local function wrappedLines(entry, width, scale)
    if entry.wrapWidth ~= width or entry.wrapScale ~= scale then
        local font = fontFor(entry)
        entry.lines = Omerta.Chat.WrapText(entry.text, width, measurerFor(font))
        entry.tall = lineHeight(font)
        entry.wrapWidth, entry.wrapScale = width, scale
    end
    return entry.lines, entry.tall
end

-- What the player is about to speak on, decided by the same parser the server
-- will use on the text — so the box cannot promise a whisper the server then
-- treats as a shout. nil means the line will be refused rather than said.
local function pendingChannel()
    local id = Omerta.Chat.Parse(typed)
    return id and Omerta.Chat.GetChannel(id) or nil
end

local function drawInput(x, ruleY, width, alpha)
    local channel = pendingChannel()
    local scale = Omerta.HUD.Scale()
    local monoFont = Omerta.HUD.Font("mono")
    local bodyFont = Omerta.HUD.Font("body")
    local tall = lineHeight(bodyFont)
    local top = ruleY - Omerta.HUD.Space(1) - tall

    -- Brass while what has been typed will actually be spoken, a plain rule
    -- when it will not. The accent marks the active thing and this is the one
    -- active thing on the screen; a mistyped command losing it is the warning.
    surface.SetDrawColor(Omerta.HUD.Colour(channel and "brass" or "rule", 255 * alpha))
    surface.DrawRect(x, ruleY, width, 1)

    -- WHISPER / SAY / YELL / ME, from the registry itself, so a channel added
    -- by a later milestone names itself here without this file changing.
    local chip = channel and string.upper(channel.id) or "?"
    surface.SetFont(monoFont)
    local chipWide = surface.GetTextSize(chip)
    draw.SimpleText(chip, monoFont, x, ruleY - Omerta.HUD.Space(1),
        Omerta.HUD.Colour(channel and "brass" or "dim", 255 * alpha),
        TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)

    local textX = x + chipWide + Omerta.HUD.Space(3)
    local room = width - (chipWide + Omerta.HUD.Space(3))
    local measure = measurerFor(bodyFont)
    local shown = Omerta.Chat.ClipTail(typed, room, measure)
    if shown ~= typed then
        -- Measured a second time with the marker's own width reserved, so the
        -- scrolled line ends exactly where the column does.
        shown = "…" .. Omerta.Chat.ClipTail(typed, room - measure("…"), measure)
    end

    if shown ~= "" then
        outlined(shown, bodyFont, textX, top, Omerta.HUD.Colour("text", 255 * alpha))
    end

    -- A 1px mark where the next letter lands, breathing rather than blinking:
    -- the standard's motion is fade and nothing in this interface snaps.
    local pulse = 0.35 + 0.65 * (0.5 + 0.5 * math.cos(CurTime() * math.pi * 1.6))
    surface.SetDrawColor(Omerta.HUD.Colour("text", 255 * alpha * pulse))
    surface.DrawRect(textX + measure(shown) + 1 * scale, top, 1, tall)
end

Omerta.HUD.Register("chat", {
    order = 30,
    -- The per-line fade below does the real work; this is only the block's own
    -- arrival, at the guide's 120ms.
    fade = 0.12,
    visible = function()
        -- Chat goes at the moment of death, exactly as injury's own
        -- suppression does — once dead there is nothing to read and the screen
        -- belongs to the moment. Soft reference: a server without the injury
        -- module keeps its chat.
        local C = Omerta.Injury and Omerta.Injury.Client
        if C and (C.death or C.leaving) then return false end

        if typing or wakePresence() > 0 then return true end
        -- The newest line is the last to go, so it alone decides whether there
        -- is anything left on screen.
        local newest = history[#history]
        return newest ~= nil and presenceOf(newest) > 0
    end,
    draw = function(alpha)
        local scale = Omerta.HUD.Scale()
        local margin = Omerta.HUD.Space(5)
        local x = margin
        -- Never past a third of the view: a column that reaches the middle of
        -- the screen is a subtitle track, not a corner of one.
        local width = math.min(460 * scale, ScrW() * 0.34)

        -- Bottom-left, clear of the stamina ticks that sit on the screen-edge
        -- margin, growing UP so the newest sentence is always in the same
        -- place and the eye never has to hunt for it.
        local staminaStrip = 3 * scale
        local ruleY = ScrH() - margin - staminaStrip - Omerta.HUD.Space(2)

        -- The input row is reserved whether or not anyone is typing. Letting
        -- the messages sit lower when the box is shut would move every line
        -- under the eye at the exact moment somebody starts reading them.
        local rowTall = lineHeight(Omerta.HUD.Font("body")) + Omerta.HUD.Space(2)
        local y = ruleY - rowTall - Omerta.HUD.Space(2)

        if typing then drawInput(x, ruleY, width, alpha) end

        -- The hotbar is vertically centred on this same edge; stop before the
        -- block reaches it rather than drawing two things through each other.
        local ceiling = ScrH() * 0.42

        for index = #history, 1, -1 do
            local entry = history[index]
            local presence = presenceOf(entry) * alpha
            local lines, tall = wrappedLines(entry, width, scale)

            for line = #lines, 1, -1 do
                y = y - tall
                -- Text at near-zero alpha shimmers against the world and reads
                -- as a glitch rather than as a fade.
                if presence > 0.03 then
                    outlined(lines[line], fontFor(entry), x, y,
                        Omerta.HUD.Colour(entry.token, 255 * presence))
                end
            end

            y = y - Omerta.HUD.Space(1)
            if y < ceiling then break end
        end
    end,
})
