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
