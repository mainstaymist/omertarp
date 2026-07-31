-- Characters module: registration plus the shared rules the client needs for
-- live feedback and the server enforces for real (Tech §3, GDD §5).
--
-- The client's copy of ValidateName exists so the creation UI can grey out a
-- bad name before submitting. It is a courtesy, never a gate: the server runs
-- the same function on arrival and the database's unique index has the final
-- word on collisions.


Omerta.Characters = Omerta.Characters or {}

Omerta.Characters.STATUS = { ALIVE = "alive", RETIRED = "retired", DEAD = "dead" }

-- Client state codes for the characters.state message (§5 of the review).
Omerta.Characters.STATE = {
    NEEDS_CREATION = 1,
    ACTIVE         = 2,
    NO_SEASON      = 3,
}

-- Selectable models, by index. A client sends the INDEX; the server maps it.
-- Never accept a model path from a client — it would set arbitrary models on
-- players. Placeholder roster per D-005 (existing props/models first, custom
-- period assets only once gameplay is settled).
Omerta.Characters.MODELS = {
    "models/player/group01/male_01.mdl",
    "models/player/group01/male_02.mdl",
    "models/player/group01/male_03.mdl",
    "models/player/group01/male_04.mdl",
    "models/player/group01/male_05.mdl",
    "models/player/group01/male_06.mdl",
    "models/player/group01/male_07.mdl",
    "models/player/group01/male_08.mdl",
    "models/player/group01/male_09.mdl",
    "models/player/group01/female_01.mdl",
    "models/player/group01/female_02.mdl",
    "models/player/group01/female_03.mdl",
    "models/player/group01/female_04.mdl",
    "models/player/group01/female_06.mdl",
}

Omerta.Characters.PATHS = { "criminal", "police", "independent" }

local NAME_MIN, NAME_MAX = 2, 24

-- Counts UTF-8 characters by ignoring continuation bytes (0b10xxxxxx), so
-- accented names (Omertà's setting is Italian-American) measure by letters
-- rather than bytes. Works in plain Lua 5.1, where no utf8 library exists.
local function utf8len(s)
    local n = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 128 or b >= 192 then n = n + 1 end
    end
    return n
end
Omerta.Characters.UTF8Len = utf8len

-- Title-cases a word, but only when the player typed it in one case
-- throughout: "SALVATORE" and "salvatore" both become "Salvatore", while
-- "McDonald" and "DiMeo" keep the capitalization they clearly intended.
local function normalizeCase(word)
    local hasLower = word:find("%l") ~= nil
    local hasUpper = word:find("%u") ~= nil
    if hasLower and hasUpper then return word end
    local out = word:lower()
    -- Capitalize the first letter and any letter after ' or -, so O'Brien and
    -- Lo-Bianco come out right.
    out = out:gsub("^(%l)", string.upper)
    out = out:gsub("(['%-])(%l)", function(sep, ch) return sep .. ch:upper() end)
    return out
end

-- Validates and normalizes one name part. Returns normalized, or nil + reason.
local function validatePart(raw, label)
    if type(raw) ~= "string" then return nil, label .. " name is required" end

    -- Control characters are checked on the RAW input, before any
    -- normalization: a newline or tab in a name field is a rejection, not
    -- something to quietly fold into a space (Tech §3).
    for i = 1, #raw do
        local b = raw:byte(i)
        if b < 32 or b == 127 then
            return nil, label .. " name contains control characters"
        end
    end

    -- Normalize spacing only: trim, collapse runs.
    local s = raw:gsub(" +", " "):gsub("^ ", ""):gsub(" $", "")
    if s == "" then return nil, label .. " name is required" end

    for i = 1, #s do
        local b = s:byte(i)
        -- Permitted: ASCII letters, apostrophe, hyphen, space, and any byte
        -- >= 128 (UTF-8 accented letters). Everything else — digits, markup,
        -- punctuation — is rejected.
        if b < 128 then
            local c = s:sub(i, i)
            if not (c:find("%a") or c == "'" or c == "-" or c == " ") then
                return nil, label .. " name may only contain letters, apostrophes and hyphens"
            end
        end
    end

    local len = utf8len(s)
    if len < NAME_MIN then
        return nil, label .. " name must be at least " .. NAME_MIN .. " characters"
    end
    if len > NAME_MAX then
        return nil, label .. " name must be at most " .. NAME_MAX .. " characters"
    end
    if not s:find("%a") and not s:find("[\128-\255]") then
        return nil, label .. " name must contain letters"
    end
    -- No leading/trailing punctuation, and no doubled punctuation.
    if s:find("^[' %-]") or s:find("[' %-]$") then
        return nil, label .. " name must start and end with a letter"
    end
    if s:find("[' %-][' %-]") then
        return nil, label .. " name has repeated punctuation"
    end

    local parts = {}
    for word in s:gmatch("[^ ]+") do parts[#parts + 1] = normalizeCase(word) end
    return table.concat(parts, " ")
end

-- Validates a full name. Returns first, last, key — or nil, reason.
-- `key` is the season-unique index value: lowercased "first last".
function Omerta.Characters.ValidateName(first, last)
    local f, ferr = validatePart(first, "First")
    if not f then return nil, ferr end
    local l, lerr = validatePart(last, "Last")
    if not l then return nil, lerr end
    return f, l, (f .. " " .. l):lower()
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------
-- Registered here, in the shared realm, because BOTH sides need every
-- definition: the receiver to validate and dispatch, the sender to write the
-- payload. Handlers only ever run in their receiving realm, so each closure
-- may safely reference realm-specific functions.

Omerta.Net.Register("characters.state", {
    realm = "server_to_client",
    schema = { { name = "state", type = "uint", bits = 3 } },
    handler = function(payload)
        hook.Run("Omerta.CharactersState", payload.state)
    end,
})

-- The client announcing that its Lua is up and listening, so the server can
-- repeat a state it may have said into a void. See Internal.OnClientReady in
-- sv_characters.lua for why that is necessary at all; the short version is
-- that the join flow begins before the client can receive anything, and the
-- state is otherwise said once and never again.
--
-- No payload: the message IS the fact. The allowance is small because a client
-- has only two occasions to make the announcement — joining, and being rebuilt
-- by a Lua refresh — and anything beyond that is somebody prodding the server.
Omerta.Net.Register("characters.ready", {
    realm = "client_to_server",
    schema = {},
    rate = { burst = 3, per = 10 },
    handler = function(ply)
        Omerta.Characters.Internal.OnClientReady(ply)
    end,
})

if CLIENT and Omerta.InEngine then
    local function announce()
        Omerta.Net.Request("characters.ready", {})
    end

    -- InitPostEntity is the first moment the client is certainly able to hear
    -- the server: the gamemode's Lua is loaded, the entities exist and the
    -- loading screen is done with. Announcing any earlier would announce into
    -- the same void the server was already shouting into.
    hook.Add("InitPostEntity", "omerta.characters.ready", announce)

    -- A Lua auto-refresh rebuilds the client's entire gamemode state, the front
    -- end with it, long after InitPostEntity has been and gone. Without this a
    -- developer who saves a file mid-session lands in exactly the silence this
    -- handshake exists to end: gated at spawn, no menu, nothing in the console.
    hook.Add("OnReloaded", "omerta.characters.ready_reload", announce)
end

-- A player's own character details. Safe to send: it is their own data, and
-- D-015 needs it so their own Nick() can return their own name. Never carries
-- anyone else's character.
Omerta.Net.Register("characters.self", {
    realm = "server_to_client",
    schema = {
        { name = "id",    type = "uint", bits = 32 },
        { name = "first", type = "string", maxlen = 24 },
        { name = "last",  type = "string", maxlen = 24 },
    },
    handler = function(payload)
        Omerta.Characters.SetLocal({
            id = payload.id, first_name = payload.first, last_name = payload.last,
        })
    end,
})

Omerta.Net.Register("characters.create_failed", {
    realm = "server_to_client",
    schema = { { name = "reason", type = "string", maxlen = 128 } },
    handler = function(payload)
        hook.Run("Omerta.CharacterCreateFailed", payload.reason)
    end,
})

Omerta.Net.Register("characters.create", {
    realm = "client_to_server",
    schema = {
        { name = "first", type = "string", maxlen = 48 },
        { name = "last",  type = "string", maxlen = 48 },
        { name = "model", type = "uint", bits = 8 },
        { name = "skin",  type = "uint", bits = 4 },
        { name = "path",  type = "uint", bits = 3 },
    },
    rate = { burst = 3, per = 10 },
    handler = function(ply, payload)
        Omerta.Characters.Create(ply, {
            first = payload.first, last = payload.last,
            modelIndex = payload.model, skin = payload.skin,
            pathIndex = payload.path,
        }, function(character, err)
            if not character and err then
                Omerta.Net.Send("characters.create_failed", { reason = err }, ply)
            end
        end)
    end,
})

Omerta.Net.Register("characters.portrait_upload", {
    realm = "client_to_server",
    schema = { { name = "data", type = "string", maxlen = 65000 } },
    rate = { burst = 2, per = 30 },
    handler = function(ply, payload)
        Omerta.Characters.Internal.StorePortrait(ply, payload.data)
    end,
})

Omerta.Net.Register("characters.portrait_request", {
    realm = "client_to_server",
    schema = { { name = "id", type = "uint", bits = 32 } },
    rate = { burst = 10, per = 10 },
    handler = function(ply, payload)
        Omerta.Portraits.Fetch(payload.id, function(base64)
            Omerta.Net.Send("characters.portrait_data",
                { id = payload.id, data = base64 or "" }, ply)
        end)
    end,
})

Omerta.Net.Register("characters.portrait_data", {
    realm = "server_to_client",
    schema = {
        { name = "id",   type = "uint", bits = 32 },
        { name = "data", type = "string", maxlen = 65000 },
    },
    handler = function(payload)
        -- M21 (newspaper) and M22 (archive) consume this; an empty string
        -- means "no portrait on file" and callers fall back to a silhouette.
        hook.Run("Omerta.PortraitReceived", payload.id,
            payload.data ~= "" and payload.data or nil)
    end,
})
