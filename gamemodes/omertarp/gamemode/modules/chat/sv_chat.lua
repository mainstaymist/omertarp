-- Server side of local communication: audience, per-recipient resolution,
-- voice audibility, logging and retention.

local MODULE = Omerta.Module.Get("chat")

Omerta.Chat = Omerta.Chat or {}
Omerta.Chat.Internal = Omerta.Chat.Internal or {}
local Internal = Omerta.Chat.Internal

Omerta.Config.Define("chat.max_length", {
    type = "number", default = 256, min = 32, max = 256, scope = "server",
    description = "Maximum characters in a chat message.",
})
Omerta.Config.Define("chat.voice_range", {
    type = "number", default = 500, min = 64, max = 4096, scope = "server",
    description = "Distance at which spatial voice becomes inaudible.",
})
Omerta.Config.Define("chat.retention_days", {
    type = "number", default = 14, min = 0, scope = "server",
    description = "Delete chat log rows older than this many days (0 = keep forever).",
})

--------------------------------------------------------------------------------
-- Pure helpers (headless-tested)
--------------------------------------------------------------------------------

function Internal.InRange(speakerPos, listenerPos, range)
    if not range then return false end
    return speakerPos:Distance(listenerPos) <= range
end

function Internal.RetentionCutoff(now, days)
    if not days or days <= 0 then return nil end
    return now - days * 86400
end

--------------------------------------------------------------------------------
-- Delivery
--------------------------------------------------------------------------------

local buckets = {} -- steamid64 -> token bucket

local function allowedToSpeak(ply)
    local sid = ply:SteamID64() or "?"
    local bucket = buckets[sid]
    if not bucket then
        bucket = Omerta.Util.NewTokenBucket(4, 6)
        buckets[sid] = bucket
    end
    return Omerta.Util.TokenBucketAllow(bucket, CurTime())
end

-- Sends one line to one player, resolved for them alone.
local function deliver(listener, speakerEntity, channel, name, text)
    Omerta.Net.Send("chat.message", {
        speaker = IsValid(speakerEntity) and speakerEntity:EntIndex() or 0,
        channel = channel.index,
        name = name,
        text = text,
    }, listener)
end

-- Tells one player something directly, with no speaker and no audience.
function Omerta.Chat.Notice(ply, text)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    deliver(ply, nil, Omerta.Chat.GetChannel("system"), "", text)
end

-- The core: validate, find the audience, resolve the speaker's label
-- separately for each listener, deliver, log.
function Omerta.Chat.Send(ply, channelId, text)
    if not Omerta.InEngine then return false, "not in engine" end

    local channel = Omerta.Chat.GetChannel(channelId)
    if not channel or channel.system then return false, "unknown channel" end

    local speakerChar = Omerta.Characters.Get(ply)
    if not speakerChar then
        Omerta.Chat.Notice(ply, "You have no character; you cannot speak.")
        return false, "no character"
    end
    if channel.canUse and not channel.canUse(ply) then
        return false, "channel unavailable"
    end

    local clean, why = Omerta.Chat.Sanitize(text, Omerta.Config.Get("chat.max_length"))
    if not clean then return false, why end

    if not allowedToSpeak(ply) then
        Omerta.Chat.Notice(ply, "You are speaking too quickly.")
        return false, "rate limited"
    end

    local speakerPos = ply:GetPos()
    local recipients = 0

    for _, listener in ipairs(player.GetAll()) do
        -- The speaker always hears themselves; everyone else must be in range
        -- and have a character of their own to hear with.
        local isSpeaker = listener == ply
        local listenerChar = Omerta.Characters.Get(listener)
        if isSpeaker or (listenerChar and
                Internal.InRange(speakerPos, listener:GetPos(), channel.range)) then
            -- The whole point of M5, in one call: each listener gets the name
            -- their own character has earned, and D-014 concealment applies
            -- because resolution runs through ResolveDisplayName.
            local known = listenerChar
                and Omerta.Identity.GetKnownName(listenerChar.id, speakerChar.id) or nil
            local name = Omerta.Identity.ResolveDisplayName(listenerChar, speakerChar, known)
            deliver(listener, ply, channel, name, clean)
            recipients = recipients + 1
        end
    end

    local season = Omerta.Seasons.GetActive()
    if season then
        Internal.Repo.Log({
            at = os.time(),
            season_id = season.id,
            character_id = speakerChar.id,
            channel = channel.id,
            text = clean,
            pos_x = math.floor(speakerPos.x),
            pos_y = math.floor(speakerPos.y),
            pos_z = math.floor(speakerPos.z),
            recipients = recipients,
        })
    end

    hook.Run("Omerta.ChatSent", ply, channel, clean, recipients)
    return true
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function MODULE:OnLoad()
    Omerta.DB.DefineTable("chat_log", {
        columns = {
            { name = "id",           type = "id" },
            { name = "at",           type = "timestamp", null = false },
            { name = "season_id",    type = "ref", null = false },
            { name = "character_id", type = "ref", null = false },
            { name = "channel",      type = "text", length = 16, null = false },
            { name = "text",         type = "text", length = 256, null = false },
            { name = "pos_x",        type = "int" },
            { name = "pos_y",        type = "int" },
            { name = "pos_z",        type = "int" },
            { name = "recipients",   type = "int", null = false, default = 0 },
        },
        indexes = { { "character_id" }, { "at" }, { "season_id" } },
    })

    Omerta.DB.AddMigration(6, "chat log", function(m)
        m:CreateTable("chat_log")
    end)
end

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    -- GMod's chat box is the input; its default behaviour is a GLOBAL
    -- broadcast, which would undo M5 and M6 in a single line of text.
    -- Returning "" suppresses it entirely and we deliver our own copies.
    hook.Add("PlayerSay", "omerta.chat.say", function(ply, raw)
        local channelId, text, why = Omerta.Chat.Parse(raw)
        if not channelId then
            if why then Omerta.Chat.Notice(ply, why) end
            return ""
        end
        Omerta.Chat.Send(ply, channelId, text)
        return ""
    end)

    -- Voice: audible by distance alone, always 3D, never global. Called for
    -- every listener/talker pair, so it stays a distance comparison.
    hook.Add("PlayerCanHearPlayersVoice", "omerta.chat.voice", function(listener, talker)
        if not (IsValid(listener) and IsValid(talker)) then return false end
        if not Omerta.Characters.IsLoaded(talker) then return false end
        if not Omerta.Characters.IsLoaded(listener) then return false end
        local range = Omerta.Config.Get("chat.voice_range")
        return listener:GetPos():Distance(talker:GetPos()) <= range, true
    end)

    hook.Add("PlayerDisconnected", "omerta.chat.bucket_cleanup", function(ply)
        buckets[ply:SteamID64() or "?"] = nil
    end)

    local function sweep()
        local cutoff = Internal.RetentionCutoff(os.time(),
            Omerta.Config.Get("chat.retention_days"))
        if cutoff then Internal.Repo.Sweep(cutoff) end
    end
    Omerta.DB.WhenReady(sweep)
    timer.Create("omerta.chat.retention", 6 * 3600, 0, sweep)
end
