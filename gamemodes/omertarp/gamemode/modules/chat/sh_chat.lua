-- Local text: ranged speech where every listener resolves the speaker through
-- their OWN knowledge (M5). The same sentence reads "Tony Marino says…" to
-- someone who has met him and "Unknown says…" to everyone else in earshot.
--
-- Channels are a registry so M11's radios and M12's phone calls can add their
-- own delivery rules without this module learning about equipment.


Omerta.Chat = Omerta.Chat or {}

-- Colours are plain {r,g,b} rather than Color objects: this file is shared and
-- must stay loadable headless, where the engine's Color does not exist.
local registry = {}
local ordered = nil

function Omerta.Chat.RegisterChannel(id, def)
    if type(id) ~= "string" or not id:find("^[a-z_]+$") then
        error("chat channel id '" .. tostring(id) .. "' must be lowercase letters", 2)
    end
    if registry[id] then error("chat channel '" .. id .. "' registered twice", 2) end
    if type(def.label) ~= "string" then error("channel '" .. id .. "' needs a label", 2) end
    if def.range ~= nil and (type(def.range) ~= "number" or def.range <= 0) then
        error("channel '" .. id .. "' has an invalid range", 2)
    end
    def.id = id
    def.order = def.order or 100
    def.colour = def.colour or { 220, 220, 220 }
    registry[id] = def
    ordered = nil
    return def
end

--------------------------------------------------------------------------------
-- Voice routing seam (S1)
--------------------------------------------------------------------------------
-- There is exactly ONE PlayerCanHearPlayersVoice hook in this gamemode, and
-- there has to be: hook.Run returns the first non-nil result and listener order
-- is undefined, so a second hook would make call audio depend on which happened
-- to run first. The symptom would not be a crash but intermittently inaudible
-- telephone calls, which is close to undiagnosable from a player report.
--
-- Anything that wants a say registers here instead. fn(listener, talker)
-- returns (canHear, is3D) to decide, or nil to defer to distance.

local voiceOverrides = {}

-- Who may use which channel right now. Registered rather than hardcoded, so
-- M19 can take a dying man's voice down to a whisper without this module
-- learning what an injury is.
-- fn(ply, channelId) returns false + reason to refuse; anything else allows.
local channelFilters = {}

function Omerta.Chat.RegisterChannelFilter(id, fn)
    channelFilters[id] = fn
end

-- Returns true, or false + reason. A filter that errors refuses, rather than
-- accidentally granting speech because of a typo in somebody else's module.
function Omerta.Chat.MayUseChannel(ply, channelId)
    for _, fn in pairs(channelFilters) do
        local ok, allowed, why = pcall(fn, ply, channelId)
        if not ok then return false, "you cannot speak" end
        if allowed == false then return false, why end
    end
    return true
end

function Omerta.Chat.RegisterVoiceOverride(id, fn)
    voiceOverrides[id] = fn
end

-- Returns canHear, is3D — or nil when nobody has an opinion.
function Omerta.Chat.VoiceOverride(listener, talker)
    for _, fn in pairs(voiceOverrides) do
        local ok, canHear, is3D = pcall(fn, listener, talker)
        -- A provider that errors defers rather than silencing anyone.
        if ok and canHear ~= nil then return canHear, is3D end
    end
    return nil
end

-- GetOrdered is what assigns `index`, and the index is what goes on the wire.
-- Returning a channel before that has ever run hands the caller a definition
-- with a nil index, which then fails validation inside net.Send — a crash that
-- waits for whichever code path happens to speak first. Ordering here makes a
-- channel always fully formed.
function Omerta.Chat.GetChannel(id)
    Omerta.Chat.GetOrdered()
    return registry[id]
end

-- Deterministic ordering so the wire can carry a small index rather than a
-- channel name, computed identically in both realms.
function Omerta.Chat.GetOrdered()
    if ordered then return ordered end
    ordered = {}
    for _, def in pairs(registry) do ordered[#ordered + 1] = def end
    table.sort(ordered, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    for i, def in ipairs(ordered) do def.index = i end
    return ordered
end

function Omerta.Chat.GetByIndex(index)
    local list = Omerta.Chat.GetOrdered()
    return list[index]
end

--------------------------------------------------------------------------------
-- Default channels
--------------------------------------------------------------------------------
-- Ranges are deliberately distinct: controlling who can hear you is a mechanic
-- in a game about operational security, not a convenience.

Omerta.Chat.RegisterChannel("whisper", {
    label = "whispers", prefix = "/w", range = 120, order = 10,
    colour = { 150, 150, 165 },
})

Omerta.Chat.RegisterChannel("say", {
    label = "says", prefix = nil, range = 400, order = 20,
    colour = { 235, 230, 215 },
})

Omerta.Chat.RegisterChannel("yell", {
    label = "yells", prefix = "/y", range = 800, order = 30,
    colour = { 245, 215, 190 },
})

Omerta.Chat.RegisterChannel("me", {
    label = "", prefix = "/me", range = 400, order = 40, emote = true,
    colour = { 200, 185, 220 },
})

-- Not player-usable: the pipe for telling one person something directly
-- ("you have no character"), reusing the same delivery path.
Omerta.Chat.RegisterChannel("system", {
    label = "", prefix = nil, range = nil, order = 90, system = true,
    colour = { 190, 160, 160 },
})

--------------------------------------------------------------------------------
-- Pure text handling (headless-tested; the server enforces, the client mirrors)
--------------------------------------------------------------------------------

-- Strips control characters, collapses whitespace, trims, caps length.
-- Returns text, or nil + reason.
function Omerta.Chat.Sanitize(text, maxLength)
    if type(text) ~= "string" then return nil, "no message" end

    local out = {}
    for i = 1, #text do
        local b = text:byte(i)
        -- Keep printable ASCII and every UTF-8 byte; drop control characters,
        -- which is how colour codes and layout tricks would arrive.
        if b >= 32 and b ~= 127 then out[#out + 1] = string.char(b) end
    end
    local s = table.concat(out)
    s = s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")

    if s == "" then return nil, "empty message" end
    if #s > maxLength then s = s:sub(1, maxLength) end
    return s
end

-- Splits a raw chat line into a channel id and its message.
-- Plain text is ordinary speech; an unrecognised /command is refused rather
-- than being spoken aloud, since "/wanted dead or alive" should not become a
-- shout if someone fat-fingers a command.
function Omerta.Chat.Parse(raw)
    if type(raw) ~= "string" then return nil, nil, "no message" end
    local trimmed = raw:gsub("^%s+", "")

    if trimmed:sub(1, 1) == "/" then
        local word = trimmed:match("^(/%a+)")
        if not word then return nil, nil, "unknown command" end
        for _, def in ipairs(Omerta.Chat.GetOrdered()) do
            if def.prefix and def.prefix:lower() == word:lower() then
                local rest = trimmed:sub(#word + 1):gsub("^%s+", "")
                return def.id, rest
            end
        end
        return nil, nil, "unknown command '" .. word .. "'"
    end

    return "say", trimmed
end

--------------------------------------------------------------------------------
-- Presentation maths (headless-tested)
--------------------------------------------------------------------------------
-- The chat box draws; the arithmetic behind it does not. It lives here for the
-- same reason sh_hud.lua holds the HUD controller's fade curve — the drawing
-- half is client-only and the headless suite cannot reach it, and this is the
-- half that has the off-by-ones in it.
--
-- Nothing below knows what a font or a colour is: each takes the measurement
-- or the palette it needs as an argument. A wrap computed from a fixed
-- character count is wrong at every accessibility scale, and a hardcoded grey
-- is exactly the drift the standardization pass exists to catch.

-- One UTF-8 character per iteration. Lua 5.1 has no utf8 library and this text
-- is player-authored: Sanitize deliberately keeps every non-ASCII byte so
-- "Omertà" survives, and slicing between the two bytes of an "à" would put a
-- replacement glyph on screen.
local UTF8_CHAR = "[%z\1-\127\194-\244][\128-\191]*"

-- Breaks text into lines no wider than maxWidth, measured with the caller's
-- own measure(string) — in engine that is surface.GetTextSize against the real
-- font. Returns an array of lines, never nil.
function Omerta.Chat.WrapText(text, maxWidth, measure)
    if type(text) ~= "string" or text == "" then return {} end
    if type(maxWidth) ~= "number" or maxWidth <= 0 then return { text } end

    local lines, current = {}, nil

    -- A single word wider than the whole column — a pasted address, a wall of
    -- one letter — has to be cut mid-word or it draws off the edge of the
    -- screen. Returns the remainder, which the next word may still join.
    local function breakWord(word)
        local piece = ""
        for char in word:gmatch(UTF8_CHAR) do
            if piece ~= "" and measure(piece .. char) > maxWidth then
                lines[#lines + 1] = piece
                piece = char
            else
                piece = piece .. char
            end
        end
        if piece == "" then return nil end
        return piece
    end

    for word in text:gmatch("%S+") do
        local candidate = current and (current .. " " .. word) or word
        if measure(candidate) <= maxWidth then
            current = candidate
        else
            if current then lines[#lines + 1] = current end
            current = (measure(word) <= maxWidth) and word or breakWord(word)
        end
    end
    if current then lines[#lines + 1] = current end

    -- Whitespace-only input has no words to place; drawing it unchanged beats
    -- returning nothing at all.
    if #lines == 0 then lines[1] = text end
    return lines
end

-- The tail of text that fits in maxWidth, for a field that scrolls instead of
-- wrapping. The input line is ONE row that never changes height: a field that
-- grew as you typed would push the conversation you are answering up the
-- screen, which is the one moment it must not move.
function Omerta.Chat.ClipTail(text, maxWidth, measure)
    if type(text) ~= "string" or text == "" then return "" end
    if type(maxWidth) ~= "number" or maxWidth <= 0 then return "" end
    if measure(text) <= maxWidth then return text end

    -- Character starts, ascending, so the first tail that fits is the longest.
    for start in text:gmatch("()" .. UTF8_CHAR) do
        local tail = text:sub(start)
        if measure(tail) <= maxWidth then return tail end
    end
    return ""
end

-- A line's presence 0..1, `age` seconds after it arrived: `rise` seconds
-- coming in, `hold` seconds at full, `fade` seconds going, nothing afterwards.
--
-- The nothing afterwards is the point. GDD §8 wants the persistent screen
-- empty, and a chat box that never leaves is a permanent HUD element wearing a
-- different hat.
function Omerta.Chat.LineAlpha(age, hold, fade, rise)
    if type(age) ~= "number" or age < 0 then return 0 end
    rise = rise or 0
    if rise > 0 and age < rise then return age / rise end

    local settled = age - rise
    if settled <= (hold or 0) then return 1 end
    if not fade or fade <= 0 then return 0 end

    local left = 1 - (settled - (hold or 0)) / fade
    if left <= 0 then return 0 end
    return left
end

-- Keeps the newest `max` entries, dropping from the front. Bounded because a
-- transcript is not a feature of this game: what has scrolled away is gone,
-- the same way it is gone for the character.
function Omerta.Chat.TrimHistory(list, max)
    if type(max) ~= "number" or max < 0 then return list end
    while #list > max do table.remove(list, 1) end
    return list
end

-- Maps a channel's declared {r,g,b} onto the nearest token in `candidates`, by
-- perceived luminance.
--
-- A channel names its own colour and later milestones' channels will too —
-- M11's radios, M12's phone. The design standard allows six hex and nothing
-- else, so the declaration is honoured by translating it rather than by being
-- drawn: a quiet channel stays quiet, a bright one stays bright, and no new
-- grey enters the interface.
--
-- Candidates are an ORDERED array of { token, colour }. Ordered, not a map,
-- because pairs() order is undefined and a tie would then resolve to a
-- different token from one boot to the next.
function Omerta.Chat.PaletteToken(rgb, candidates)
    local function luminance(colour)
        colour = colour or {}
        return 0.299 * (colour[1] or 0) + 0.587 * (colour[2] or 0)
            + 0.114 * (colour[3] or 0)
    end

    local want = luminance(rgb)
    local best, bestDistance = nil, nil
    for _, candidate in ipairs(candidates or {}) do
        local distance = math.abs(luminance(candidate.colour) - want)
        if not bestDistance or distance < bestDistance then
            best, bestDistance = candidate.token, distance
        end
    end
    return best
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------
-- One message per listener, each carrying the name THAT listener is entitled
-- to see (M7 review §4). The `name` field is a reviewed outbound name field —
-- see M6's audit allowlist.

Omerta.Net.Register("chat.message", {
    realm = "server_to_client",
    schema = {
        { name = "speaker", type = "uint", bits = 16 },
        { name = "channel", type = "uint", bits = 4 },
        { name = "name",    type = "string", maxlen = 56 },
        { name = "text",    type = "string", maxlen = 256 },
    },
    handler = function(payload)
        hook.Run("Omerta.ChatReceived", payload)
    end,
})
