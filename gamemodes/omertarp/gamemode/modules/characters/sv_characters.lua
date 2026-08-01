-- Characters service: creation, loading, status transitions, portraits,
-- networking, and the D-010 season-end retirement listener.

local MODULE = Omerta.Module.Get("characters")

Omerta.Characters = Omerta.Characters or {}
Omerta.Characters.Internal = Omerta.Characters.Internal or {}
Omerta.Portraits = Omerta.Portraits or {}
local Internal = Omerta.Characters.Internal
local STATUS = Omerta.Characters.STATUS
local STATE = Omerta.Characters.STATE

Omerta.Config.Define("characters.portrait_max_bytes", {
    type = "number", default = 49152, min = 1024, scope = "server",
    description = "Maximum base64 length accepted for a character portrait (D-011).",
})

--------------------------------------------------------------------------------
-- Pure validation (headless-tested)
--------------------------------------------------------------------------------

-- Validates a creation request's non-name fields. Returns spec, or nil+reason.
function Internal.ValidateSpec(modelIndex, skin, pathIndex)
    local model = Omerta.Characters.MODELS[modelIndex]
    if not model then return nil, "unknown model selection" end
    if type(skin) ~= "number" or skin % 1 ~= 0 or skin < 0 or skin > 15 then
        return nil, "invalid skin"
    end
    local path = Omerta.Characters.PATHS[pathIndex]
    if not path then return nil, "unknown path selection" end
    return { model = model, skin = skin, path = path }
end

-- Portrait bytes are untrusted (D-011): a modified client can send anything.
-- We can bound size and confirm it is genuinely a JPEG; offensive *content*
-- is a rules/staff matter, backed by the audit row and the wipe command.
-- decode: base64 -> binary (util.Base64Decode in-engine; injected in tests).
function Internal.ValidatePortrait(base64, maxBytes, decode)
    if type(base64) ~= "string" or base64 == "" then return nil, "no image data" end
    if #base64 > maxBytes then
        return nil, string.format("image too large (%d > %d)", #base64, maxBytes)
    end
    if base64:find("[^A-Za-z0-9+/=\r\n]") then return nil, "not valid base64" end
    local raw = decode(base64)
    if not raw or #raw < 4 then return nil, "image did not decode" end
    -- JPEG: SOI marker FF D8 FF.
    if raw:byte(1) ~= 0xFF or raw:byte(2) ~= 0xD8 or raw:byte(3) ~= 0xFF then
        return nil, "not a JPEG image"
    end
    return raw
end

--------------------------------------------------------------------------------
-- Cache and reads
--------------------------------------------------------------------------------

local cache = {} -- sid64 -> character

local function cachedFor(ply)
    if not IsValid(ply) or ply:IsBot() then return nil end
    local sid = ply:SteamID64()
    return sid and cache[sid] or nil
end

function Omerta.Characters.Get(ply) return cachedFor(ply) end
function Omerta.Characters.IsLoaded(ply) return cachedFor(ply) ~= nil end

function Omerta.Characters.GetByID(id, cb) Internal.Repo.GetByID(id, cb) end

--------------------------------------------------------------------------------
-- Applying a character to a player
--------------------------------------------------------------------------------

local function applyToPlayer(ply, character)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    ply:SetModel(character.model)
    ply:SetSkin(character.skin or 0)
    ply:Spawn()
end

-- The last state each connected player was told, by SteamID64. It exists for
-- the readiness handshake below: the server cannot tell whether a message it
-- aimed at a still-loading client arrived, so the only honest thing it can do
-- when that client finally announces itself is say the same thing again.
local told = {}

local STATE_NAMES = {
    [STATE.NEEDS_CREATION] = "needs a character",
    [STATE.ACTIVE] = "active",
    [STATE.NO_SEASON] = "no season",
    [STATE.AWAITING_ENTRY] = "has a character, waiting at the menu",
}

local function sendState(ply, state)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    local sid = ply:SteamID64()
    if sid then told[sid] = state end
    -- Logged because this single message is the only thing that raises the
    -- front end: if a player reports an empty screen, the first question is
    -- whether the server ever said anything, and the second is whether the
    -- client was listening when it did.
    Omerta.Log.Info("characters", "join: telling %s '%s'",
        sid or "?", STATE_NAMES[state] or tostring(state))
    Omerta.Net.Send("characters.state", { state = state }, ply)
end

-- Their own name, so D-015's self-case can resolve it client-side.
local function sendSelf(ply, character)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    Omerta.Net.Send("characters.self", {
        id = character.id,
        first = character.first_name,
        last = character.last_name,
    }, ply)
end

-- The joining client saying its Lua is up and listening (characters.ready).
--
-- This whole flow starts at PlayerInitialSpawn, which the engine fires while
-- the client is still loading, and a net message aimed at a client that is not
-- listening yet is simply gone: no queue, no retry, no error in either console.
-- The state is otherwise said exactly ONCE per session and it is the only
-- thing that puts the front end on screen — so losing that single message left
-- a player gated at spawn with no menu, no message and nothing to explain it.
--
-- Nothing is invented here. A state that has not been resolved yet is not
-- guessed at: the load already in flight will say it in a moment, and by then
-- the client is demonstrably listening.
function Internal.OnClientReady(ply)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    local sid = ply:SteamID64()

    -- Published for everyone else with something to say at join.
    --
    -- This is the ONLY moment on the server at which a joining client is known
    -- to be listening, and it was about to be reinvented: M3's season number has
    -- exactly the same problem this handshake was built for, and a second
    -- module-specific handshake would have been a second thing to get wrong in
    -- the same way. Fired before the early return below, because "there is
    -- nothing to tell you about your character yet" says nothing at all about
    -- whether another module has something to send.
    hook.Run("Omerta.ClientReady", ply)

    local state = sid and told[sid]
    if not state then
        -- Not a fault: the client got here first and the load will answer it.
        -- Logged anyway, because "the client was ready before the server had
        -- an answer" and "the server answered before the client was ready"
        -- look identical from a frozen spawn and this is what tells them apart.
        Omerta.Log.Info("characters", "join: %s is listening, nothing to tell it yet",
            sid or "?")
        return
    end
    Omerta.Log.Info("characters", "join: %s is listening, repeating its state", sid or "?")
    sendState(ply, state)
    local character = cachedFor(ply)
    if character then sendSelf(ply, character) end
end

-- Players without a character do not roam the map. Applied on spawn and on
-- losing a character (staff retirement, death, season end) alike.
local function gate(ply)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    ply:Freeze(true)
    ply:SetNoDraw(true)
    ply:GodEnable()
end

local function ungate(ply)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    ply:Freeze(false)
    ply:SetNoDraw(false)
    ply:GodDisable()
end
Internal.Gate, Internal.Ungate = gate, ungate

local function loadInto(ply, character)
    local sid = ply:SteamID64()
    cache[sid] = character
    applyToPlayer(ply, character)
    -- Lifting the gate is this module's own invariant, so it happens here
    -- rather than on a listener of this module's own hook. A shared dispatch is
    -- ordered by pairs() and any listener that errors takes the remainder of it
    -- with them — and the one thing that must never be lost is a player's
    -- ability to move. Doing it BEFORE the hook also settles the order against
    -- modules that apply holds of their own: somebody reconnecting onto the
    -- floor is put back down by M19 after this, not released by it.
    ungate(ply)
    sendState(ply, STATE.ACTIVE)
    sendSelf(ply, character)
    Omerta.Log.Info("characters", "character #%d (%s %s) loaded for %s",
        character.id, character.first_name, character.last_name, sid)
    if Omerta.InEngine then hook.Run("Omerta.CharacterLoaded", ply, character) end
end
Internal.LoadInto = loadInto

--------------------------------------------------------------------------------
-- Joining, and then coming in
--------------------------------------------------------------------------------
-- EVERY PLAYER IS MET BY THE FRONT END, whether or not they already have
-- somebody to be (project lead, 2026-08-01). That is a change to what joining
-- means on this server, and the shape of it matters more than it looks.
--
-- The obvious implementation is to load the character at join exactly as
-- before and let the client draw a menu over the top. That is wrong twice over:
-- the player is genuinely standing in the city while they read the menu —
-- shootable, findable, and dragged around by whatever the camera is doing —
-- and the release of the movement gate would then have to be undone and redone
-- from the client's side, which is not a thing a client may be trusted with.
--
-- So NOTHING HAPPENS AT JOIN. Finding a living character only ANNOUNCES it
-- (STATE.AWAITING_ENTRY); the row is not cached, no module is told a character
-- has arrived, and the ordinary PlayerSpawn gate holds the player exactly as it
-- holds somebody who has no character at all — same freeze, same SetNoDraw,
-- same god mode, one code path, nothing new that can leave a player stranded.
--
-- When they choose to come in, the SAME resolution runs again with `enter` set
-- and the character loads through the same loadInto it always did. That is what
-- keeps the release honest: the gate is lifted in one place, once, before
-- Omerta.CharacterLoaded fires — so M19 still puts somebody who logged off on
-- the floor back onto it, AFTER the release rather than before, which is the
-- ordering that hook comment has always depended on.
--
-- The resolution is re-run rather than remembered on purpose. A character can
-- be retired by staff or by a season ending between joining and pressing the
-- entry, and a remembered row would walk a retired character into the city.

-- Guards a second enter request arriving while the first one's queries are
-- still in flight; without it a double-click is two loadIntos and two
-- Omerta.CharacterLoaded fires. Cleared on disconnect with everything else.
local entering = {}

-- Resolve what this account is and tell the client. `enter` is the difference
-- between the two occasions: false announces a living character, true loads it.
-- `done` is called once, on every exit, so the in-flight guard cannot stick.
local function resolve(ply, account, enter, done)
    done = done or function() end
    -- Seasons.WhenReady rather than GetActive(): at boot the active season is
    -- itself the answer to a query, so a player who connects before it lands —
    -- which the listen-server host always does — would be told the city is
    -- closed and never told otherwise. M3 documents that trap for its own
    -- consumers; this is the same one, on the join path.
    Omerta.Seasons.WhenReady(function()
        if not IsValid(ply) then done() return end
        local season = Omerta.Seasons.GetActive()
        if not season then sendState(ply, STATE.NO_SEASON) done() return end
        Internal.Repo.GetActiveFor(account.id, season.id, function(character, err)
            if not IsValid(ply) then done() return end
            if err then
                -- Saying nothing is the worst outcome available: the gate has
                -- them frozen and a state message is the only way out of it.
                -- Creation re-reads this same row before it writes and loads
                -- whatever it finds, so pointing a player who may well have a
                -- character at the creation screen recovers into their own
                -- character rather than duplicating it.
                Omerta.Log.Error("characters",
                    "could not read the living character for account %d: %s",
                    account.id, tostring(err))
                sendState(ply, STATE.NEEDS_CREATION)
                done()
                return
            end
            if not character then
                sendState(ply, STATE.NEEDS_CREATION)
            elseif enter then
                loadInto(ply, character)
            else
                sendState(ply, STATE.AWAITING_ENTRY)
            end
            done()
        end)
    end)
end
Internal.Resolve = resolve

-- The front end saying the player is coming in (characters.enter).
--
-- Carries nothing and is trusted for nothing: it is a moment, not an
-- instruction. Everything about WHO they are is read back out of the database
-- here, on the server, under the same rules the join used.
function Internal.OnEnterRequested(ply)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    local sid = ply:SteamID64()
    if not sid then return end

    -- Already in the city. Nothing to do, and in particular nothing to
    -- re-release: a repeat of this message must never be a second ungate.
    if cache[sid] then return end
    if entering[sid] then return end

    local account = Omerta.Accounts.Get(ply)
    if not account then
        -- Their account has not finished loading, so there is nothing to look
        -- them up by yet. The join is still in flight and will tell them where
        -- they stand in a moment; the menu simply stays where it is.
        Omerta.Log.Info("characters",
            "enter: %s asked to come in before their account loaded", sid)
        return
    end

    entering[sid] = true
    resolve(ply, account, true, function() entering[sid] = nil end)
end

--------------------------------------------------------------------------------
-- Creation
--------------------------------------------------------------------------------

-- spec: { first, last, modelIndex, skin, pathIndex }. cb(character, err).
function Omerta.Characters.Create(ply, spec, cb)
    cb = cb or function() end
    local account = Omerta.Accounts.Get(ply)
    if not account then cb(nil, "account not loaded") return end

    local season = Omerta.Seasons.GetActive()
    if not season then cb(nil, "no active season") return end

    if cachedFor(ply) then cb(nil, "you already have a living character") return end

    local first, last, key = Omerta.Characters.ValidateName(spec.first, spec.last)
    if not first then cb(nil, last) return end -- `last` carries the reason

    local validated, why = Internal.ValidateSpec(spec.modelIndex, spec.skin, spec.pathIndex)
    if not validated then cb(nil, why) return end

    -- Q-3/D-012: one living character per account per season. The database
    -- check catches characters created in a previous session.
    Internal.Repo.GetActiveFor(account.id, season.id, function(existing, err)
        if err then cb(nil, err) return end
        if existing then
            loadInto(ply, existing)
            cb(nil, "you already have a living character")
            return
        end

        local now = os.time()
        Internal.Repo.Create({
            account_id = account.id,
            season_id = season.id,
            first_name = first,
            last_name = last,
            name_key = key,
            status = STATUS.ALIVE,
            model = validated.model,
            skin = validated.skin,
            created_at = now,
        }, function(id, cerr)
            if not id then
                -- The unique(season_id, name_key) index is the real collision
                -- guard, so a failed insert most likely means the name is taken.
                Omerta.Log.Warn("characters", "creation failed for %s: %s",
                    account.steamid64, tostring(cerr))
                cb(nil, "that name is already taken this season")
                return
            end

            local character = {
                id = id, account_id = account.id, season_id = season.id,
                first_name = first, last_name = last, name_key = key,
                status = STATUS.ALIVE, model = validated.model, skin = validated.skin,
                created_at = now,
            }

            -- The path choice runs through M3, so D-009's matrix validates it.
            -- Picking the path the account already holds is a no-op, not a
            -- refusal: a replacement character inherits its account's track
            -- (D-009), so only an actual change is worth attempting.
            if Omerta.Seasons.GetPath(ply) ~= validated.path then
                -- A genuine rejection (e.g. a criminal picking police) is
                -- logged but does not undo the character: the account simply
                -- keeps the track it already had.
                Omerta.Seasons.SetPath(ply, validated.path, function(ok, perr)
                    if not ok then
                        Omerta.Log.Warn("characters", "path '%s' refused for %s: %s",
                            validated.path, account.steamid64, tostring(perr))
                    end
                end)
            end

            Omerta.Log.Audit("character.created", {
                actor = account.steamid64, account_id = account.id,
                character_id = id, season_id = season.id,
                name = first .. " " .. last, path = validated.path,
            })
            loadInto(ply, character)
            if Omerta.InEngine then hook.Run("Omerta.CharacterCreated", ply, character) end
            cb(character)
        end)
    end)
end

--------------------------------------------------------------------------------
-- Status transitions
--------------------------------------------------------------------------------

local function uncacheById(characterId)
    for sid, character in pairs(cache) do
        if character.id == characterId then cache[sid] = nil return sid end
    end
end

function Omerta.Characters.SetStatus(characterId, status, reason, cb)
    cb = cb or function() end
    if status ~= STATUS.RETIRED and status ~= STATUS.DEAD then
        cb(false, "status must be retired or dead")
        return
    end
    Internal.Repo.SetStatus(characterId, status, os.time(), function(ok, err)
        if not ok then cb(false, err) return end
        local sid = uncacheById(characterId)
        Omerta.Log.Audit("character." .. status, {
            actor = sid, character_id = characterId, reason = reason,
        })
        if Omerta.InEngine then
            hook.Run("Omerta.CharacterRetired", characterId, reason)
            local ply = sid and player.GetBySteamID64 and player.GetBySteamID64(sid)
            if IsValid(ply) then
                -- Losing a character mid-session must also re-apply the gate,
                -- or a staff retirement leaves them walking around as nobody.
                gate(ply)
                sendState(ply, STATE.NEEDS_CREATION)
            end
        end
        cb(true)
    end)
end

function Omerta.Characters.Retire(characterId, reason, cb)
    Omerta.Characters.SetStatus(characterId, STATUS.RETIRED, reason or "retired", cb)
end

--------------------------------------------------------------------------------
-- Portraits (D-011)
--------------------------------------------------------------------------------

function Omerta.Portraits.Fetch(characterId, cb)
    Internal.Repo.GetPortrait(characterId, cb)
end

function Internal.StorePortrait(ply, base64)
    local character = cachedFor(ply)
    if not character then
        -- Silent drops here are indistinguishable from a capture that never
        -- happened, which makes the whole pipeline undiagnosable.
        Omerta.Log.Warn("characters",
            "portrait upload arrived for %s with no loaded character — discarded",
            IsValid(ply) and ply:SteamID64() or "?")
        return
    end
    if character.portrait_set then return end -- one-shot per session

    local account = Omerta.Accounts.Get(ply)
    local raw, why = Internal.ValidatePortrait(base64,
        Omerta.Config.Get("characters.portrait_max_bytes"), util.Base64Decode)
    if not raw then
        Omerta.Log.Warn("characters", "portrait rejected for character #%d: %s",
            character.id, why)
        Omerta.Log.Audit("character.portrait_rejected", {
            actor = account and account.steamid64, character_id = character.id, reason = why,
        })
        return
    end

    Internal.Repo.SetPortrait(character.id, base64, os.time(), function(ok, err)
        if not ok then
            Omerta.Log.Error("characters", "portrait store failed for #%d: %s",
                character.id, tostring(err))
            return
        end
        character.portrait_set = true
        Omerta.Log.Audit("character.portrait_set", {
            actor = account and account.steamid64,
            character_id = character.id, bytes = #base64,
        })
        Omerta.Log.Info("characters", "portrait stored for character #%d (%d bytes base64)",
            character.id, #base64)
    end)
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function MODULE:OnLoad()
    Omerta.DB.DefineTable("characters", {
        columns = {
            { name = "id",          type = "id" },
            { name = "account_id",  type = "ref", null = false },
            { name = "season_id",   type = "ref", null = false },
            { name = "first_name",  type = "text", length = 24, null = false },
            { name = "last_name",   type = "text", length = 24, null = false },
            { name = "name_key",    type = "text", length = 56, null = false },
            { name = "status",      type = "text", length = 16, null = false },
            { name = "model",       type = "text", length = 128, null = false },
            { name = "skin",        type = "int", null = false, default = 0 },
            { name = "bodygroups",  type = "json" },
            { name = "portrait",    type = "json" }, -- base64 JPEG (D-011)
            { name = "portrait_at", type = "timestamp" },
            { name = "created_at",  type = "timestamp", null = false },
            { name = "retired_at",  type = "timestamp" },
        },
        unique = { { "season_id", "name_key" } },
        indexes = { { "account_id" }, { "season_id" }, { "status" } },
    })

    Omerta.DB.AddMigration(3, "characters", function(m)
        m:CreateTable("characters")
    end)
end

function MODULE:OnEnable()
    -- Net messages are registered in sh_characters.lua: both realms need
    -- every definition, and this file is server-only.
    if not Omerta.InEngine then return end

    -- Work out where this account stands once their account is available, and
    -- say so. A living character is ANNOUNCED here, not loaded — the front end
    -- is about to go up in front of them and the city can wait until they say
    -- they are coming (see "Joining, and then coming in" above).
    hook.Add("Omerta.AccountLoaded", "omerta.characters.load", function(ply, account)
        resolve(ply, account, false)
    end)

    hook.Add("PlayerDisconnected", "omerta.characters.unload", function(ply)
        local sid = ply:SteamID64()
        if sid then cache[sid], told[sid], entering[sid] = nil, nil, nil end
    end)

    -- D-010: ending a season retires every living character in it.
    hook.Add("Omerta.SeasonEnded", "omerta.characters.retire_all", function(season)
        Internal.Repo.RetireAllInSeason(season.id, os.time(), function(ok, err)
            if not ok then
                Omerta.Log.Error("characters", "season-end retirement failed: %s", tostring(err))
                return
            end
            cache = {}
            Omerta.Log.Info("characters", "all living characters retired for season #%d", season.id)
            Omerta.Log.Audit("character.season_retirement", { season_id = season.id })
            -- Gated as well as told. Everyone in the city just stopped having
            -- a character, and SetStatus gates for exactly this reason on the
            -- single-player version of it (retirement, death) — without it a
            -- server full of people keeps walking around as nobody until each
            -- of them happens to respawn.
            for _, p in ipairs(player.GetAll()) do
                gate(p)
                sendState(p, STATE.NEEDS_CREATION)
            end
        end)
    end)

    hook.Add("PlayerSpawn", "omerta.characters.gate", function(ply)
        timer.Simple(0, function()
            if not IsValid(ply) then return end
            if not Omerta.Characters.IsLoaded(ply) then gate(ply) end
        end)
    end)

    -- Staff: what does the server actually believe about a connected player?
    --
    -- Written for a specific class of bug that keeps costing real time: a
    -- player standing frozen at spawn with nothing on screen and nothing in
    -- the log. Every stage of the join is asynchronous and any of them can end
    -- in silence, so this asks all of them at once and prints the answer.
    concommand.Add("omerta_whoami", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end

        local targets = {}
        if args[1] then
            for _, p in ipairs(player.GetAll()) do
                if p:SteamID64() == args[1] then targets[1] = p end
            end
        elseif IsValid(caller) then
            targets[1] = caller
        else
            targets = player.GetAll()
        end
        if #targets == 0 then
            Omerta.Log.Error("characters", "nobody by that SteamID64 is connected")
            return
        end

        for _, p in ipairs(targets) do
            local sid = p:SteamID64() or "?"
            local account = Omerta.Accounts and Omerta.Accounts.Get
                and Omerta.Accounts.Get(p) or nil
            local character = cachedFor(p)
            local season = Omerta.Seasons.GetActive()

            Omerta.Log.Info("characters", "%s (%s)", p:Nick(), sid)
            Omerta.Log.Info("characters", "  account   : %s",
                account and ("#" .. tostring(account.id)) or "NOT LOADED — the join stalled here")
            -- `label` is the column and there is no `name` — reading the wrong
            -- field here once made this command lie, which is the one thing it
            -- must never do. Title() reads label and formats it.
            Omerta.Log.Info("characters", "  season    : %s",
                season and ("#" .. season.id .. " " .. Omerta.Seasons.Title(season))
                    or "none active")
            Omerta.Log.Info("characters", "  character : %s",
                character and ("#" .. character.id .. " " ..
                    character.first_name .. " " .. character.last_name)
                    or "not in the city — see 'told'")
            Omerta.Log.Info("characters", "  told      : %s",
                told[sid] and (STATE_NAMES[told[sid]] or told[sid])
                    or "NOTHING — this is why the screen is empty")
            -- Frozen while loaded is a bug. Frozen while NOT loaded is the gate
            -- doing its job, and there are now two honest reasons to be in it:
            -- no character at all, or a character its owner has not walked into
            -- the city with yet. Both look identical from the outside, so the
            -- 'told' line above is what tells them apart.
            Omerta.Log.Info("characters", "  frozen    : %s%s",
                tostring(p:IsFlagSet(FL_FROZEN) or false),
                character and "" or "  (expected — not in the city)")
        end
    end)

    -- Staff: retire a character. Real moderation tool, and it saves editing
    -- SQL by hand to reset a test character.
    concommand.Add("omerta_character_retire", function(ply, _, args)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local id = tonumber(args[1])
        if not id or id % 1 ~= 0 or id < 1 then
            Omerta.Log.Error("characters",
                "usage: omerta_character_retire <characterId> [reason]")
            return
        end
        local reason = table.concat(args, " ", 2)
        if reason == "" then reason = "retired by staff" end

        Omerta.Characters.Retire(id, reason, function(ok, err)
            if ok then
                Omerta.Log.Info("characters", "character #%d retired (%s)", id, reason)
            else
                -- SetStatus only touches living characters, so the usual
                -- failure is "already retired or dead", not a fault.
                Omerta.Log.Error("characters",
                    "retire failed for #%d: %s", id, tostring(err) ~= "nil" and tostring(err)
                        or "no living character with that id")
            end
        end)
    end)

    -- Staff: wipe an abusive portrait (D-011).
    concommand.Add("omerta_portrait_clear", function(ply, _, args)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local id = tonumber(args[1])
        if not id then
            Omerta.Log.Error("characters", "usage: omerta_portrait_clear <characterId>")
            return
        end
        Internal.Repo.ClearPortrait(id, function(ok, err)
            if ok then
                Omerta.Log.Audit("character.portrait_cleared", {
                    actor = IsValid(ply) and ply:SteamID64() or "console", character_id = id,
                })
                Omerta.Log.Info("characters", "portrait cleared for character #%d", id)
            else
                Omerta.Log.Error("characters", "portrait clear failed: %s", tostring(err))
            end
        end)
    end)
end
