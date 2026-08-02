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
--
-- AWAITING_ENTRY is the front end's state: this account HAS a living character
-- and is not in the city with it yet. It exists because the server has to be
-- able to tell the two apart — "you have somebody to be" and "you are standing
-- in the street as them" used to be one message, so a client could not know
-- whether to raise the menu or take it down, and the server could not repeat
-- the fact after a Lua refresh without also implying the player had just
-- spawned. Nothing is loaded and nothing is released while a player is in it.
Omerta.Characters.STATE = {
    NEEDS_CREATION = 1,
    ACTIVE         = 2,
    NO_SEASON      = 3,
    AWAITING_ENTRY = 4,
}

-- The three life paths a season can be played on (D-009). Declared above the
-- rosters because a roster now belongs to one.
Omerta.Characters.PATHS = { "criminal", "police", "independent" }

--------------------------------------------------------------------------------
-- Appearance rosters, per path
--------------------------------------------------------------------------------
-- Selectable models, by index. A client sends the INDEX; the server maps it.
-- Never accept a model path from a client — it would set arbitrary models on
-- players.
--
-- WHAT AN INDEX MEANS CHANGED, AND IT IS THE SECURITY-RELEVANT SENTENCE HERE.
-- The department dresses differently from everybody else, so the roster depends
-- on the path, and an index is only meaningful RELATIVE TO ONE. The client
-- still sends nothing but two numbers and the server still trusts neither: it
-- resolves the path first and looks the appearance up in THAT path's roster —
-- the roster of the path the character is actually being created with, never
-- whichever list the client believes it was showing. Index 7 is an officer and
-- is nobody at all to a criminal, and `Internal.ValidateSpec` in
-- sv_characters.lua is the one place that decides which of those it is.
--
-- The period pack, chosen by the project lead. This retires the HL2 citizens
-- D-005 allowed as placeholders: these are the first assets in the game that
-- actually look like the city the design describes, and the placeholder rule
-- was always "until the real thing exists".
--
-- What is STORED is the resolved model FILE, not this index (see sv_characters'
-- creation path), which is what makes editing these lists safe: a character
-- created against an older roster keeps the model they were made with rather
-- than silently becoming whoever now occupies that slot. That property is why
-- adding a second roster costs no migration.
--
-- BOTH PACKS ARE WORKSHOP CONTENT AND NEITHER IS MOUNTED BY THIS REPOSITORY. A
-- server without them renders these as errors. The gamemode's own dependencies
-- (the map, the weather system) are declared in modules/environment/
-- sv_content.lua; playermodel packs are a particular SERVER's content and go
-- one id per line in `data/omerta_workshop.txt` on that server, which is what
-- makes clients download them.
--
-- The default roster: the one criminals and independents choose from. Kept
-- under the name MODELS because it is what every other reader in the tree
-- already asks for, and because "the roster with nothing special about it" is
-- exactly what a default is.
Omerta.Characters.MODELS = {
    "models/sentry/sentryoldmob/mafia/sentrymobmale2pm.mdl",
    "models/sentry/sentryoldmob/mafia/sentrymobmale4pm.mdl",
    "models/sentry/sentryoldmob/mafia/sentrymobmale6pm.mdl",
    "models/sentry/sentryoldmob/mafia/sentrymobmale7pm.mdl",
    "models/sentry/sentryoldmob/mafia/sentrymobmale8pm.mdl",
    "models/sentry/sentryoldmob/mafia/sentrymobmale9pm.mdl",
}

-- Rosters that differ from the default, keyed by path name. A path with no
-- entry here uses MODELS, which is what lets criminal and independent share one
-- list without it being written out twice and drifting.
Omerta.Characters.PATH_MODELS = {
    -- The department, in the project lead's order. The file numbering skips 01
    -- and 03; that is the pack's, not a mistake here, and the ordinal a player
    -- sees comes from the position in this list rather than from the filename.
    police = {
        "models/humans/nypd1940/male_02.mdl",
        "models/humans/nypd1940/male_04.mdl",
        "models/humans/nypd1940/male_05.mdl",
        "models/humans/nypd1940/male_06.mdl",
        "models/humans/nypd1940/male_07.mdl",
        "models/humans/nypd1940/male_08.mdl",
        "models/humans/nypd1940/male_09.mdl",
    },
}

-- The roster a path chooses from. Takes a path NAME ("police") or an index into
-- PATHS, because the client holds the index and the server holds the name, and
-- neither should have to convert before asking.
--
-- NEVER RETURNS NIL, including for a path that does not exist. A caller that
-- got nil would have to decide what to do about it at every call site, and the
-- honest answer everywhere is "the ordinary list" — the one place where an
-- unknown path must be a refusal rather than a fallback is creation, and that
-- refusal is made against PATHS by the server before this is ever consulted.
function Omerta.Characters.ModelsFor(path)
    if type(path) == "number" then path = Omerta.Characters.PATHS[path] end
    return Omerta.Characters.PATH_MODELS[path] or Omerta.Characters.MODELS
end

-- THE ONE PLACE a number becomes a model. Returns the model file that a life
-- path and an index name together, or nil when the index is not on that path's
-- roster — a refusal, because that nil is what the server's rejection is built
-- on and a fallback to something plausible would quietly dress somebody in it.
function Omerta.Characters.ResolveModel(path, index)
    if type(index) ~= "number" or index % 1 ~= 0 then return nil end
    return Omerta.Characters.ModelsFor(path)[index]
end

-- What the creation screen calls each one.
--
-- The form used to label a model with its own filename, which was tolerable
-- while those read "male_01" and is not now that they read
-- "sentrymobmale7pm". A player choosing a face is not choosing a file, and the
-- number in the filename is an artist's ordering that means nothing to them.
--
-- Deliberately just numbers, and deliberately still just an ORDINAL now that
-- there are two rosters: the index is a position in whichever list is on
-- screen, so "Appearance 3" is the third face the player can see either way.
-- Naming them would be inventing characters the player has not made yet — the
-- name is the next field down and it is theirs to fill in — and calling the
-- police ones "Officer 3" would name a rank the department has not given them.
function Omerta.Characters.ModelLabel(index)
    return "Appearance " .. tostring(index)
end

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

-- The player, at the front end, saying they are coming in.
--
-- NO PAYLOAD: the message is the fact, and it has to be, because a payload here
-- would be a client naming the character it wants to be. The server resolves
-- the account, the season and the living character itself — the same resolution
-- the join runs — so this message can ask for nothing except "now".
--
-- The allowance is small for the same reason characters.ready's is: there are
-- two honest occasions to send it (choosing the entry, and choosing it again
-- after a refusal), and everything beyond that is somebody prodding the server.
Omerta.Net.Register("characters.enter", {
    realm = "client_to_server",
    schema = {},
    rate = { burst = 3, per = 10 },
    handler = function(ply)
        Omerta.Characters.Internal.OnEnterRequested(ply)
    end,
})

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
