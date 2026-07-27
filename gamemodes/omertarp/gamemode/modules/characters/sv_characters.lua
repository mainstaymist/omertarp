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

local function sendState(ply, state)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    Omerta.Net.Send("characters.state", { state = state }, ply)
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
    sendState(ply, STATE.ACTIVE)
    if Omerta.InEngine then
        -- Their own name, so D-015's self-case can resolve it client-side.
        Omerta.Net.Send("characters.self", {
            id = character.id,
            first = character.first_name,
            last = character.last_name,
        }, ply)
    end
    Omerta.Log.Info("characters", "character #%d (%s %s) loaded for %s",
        character.id, character.first_name, character.last_name, sid)
    if Omerta.InEngine then hook.Run("Omerta.CharacterLoaded", ply, character) end
end
Internal.LoadInto = loadInto

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

    -- Load the player's living character once their account is available.
    hook.Add("Omerta.AccountLoaded", "omerta.characters.load", function(ply, account)
        local season = Omerta.Seasons.GetActive()
        if not season then sendState(ply, STATE.NO_SEASON) return end
        Internal.Repo.GetActiveFor(account.id, season.id, function(character, err)
            if err or not IsValid(ply) then return end
            if character then
                loadInto(ply, character)
            else
                sendState(ply, STATE.NEEDS_CREATION)
            end
        end)
    end)

    hook.Add("PlayerDisconnected", "omerta.characters.unload", function(ply)
        local sid = ply:SteamID64()
        if sid then cache[sid] = nil end
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
            for _, p in ipairs(player.GetAll()) do sendState(p, STATE.NEEDS_CREATION) end
        end)
    end)

    hook.Add("PlayerSpawn", "omerta.characters.gate", function(ply)
        timer.Simple(0, function()
            if not IsValid(ply) then return end
            if not Omerta.Characters.IsLoaded(ply) then gate(ply) end
        end)
    end)
    hook.Add("Omerta.CharacterLoaded", "omerta.characters.ungate", function(ply)
        ungate(ply)
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
