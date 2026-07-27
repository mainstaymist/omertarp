-- Identity service: knowledge cache, the introduction flow (D-013), and
-- per-observer name resolution over the wire.

local MODULE = Omerta.Module.Get("identity")

Omerta.Identity = Omerta.Identity or {}
Omerta.Identity.Internal = Omerta.Identity.Internal or {}
local Internal = Omerta.Identity.Internal

Omerta.Config.Define("identity.introduce_range", {
    type = "number", default = 96, min = 16, max = 256, scope = "server",
    description = "Maximum distance at which characters may introduce themselves.",
})
Omerta.Config.Define("identity.prompt_timeout", {
    type = "number", default = 20, min = 5, max = 120, scope = "server",
    description = "Seconds a reciprocation prompt stays valid (D-013).",
})

--------------------------------------------------------------------------------
-- Knowledge cache: characterId -> { [subjectId] = learnedName }
--------------------------------------------------------------------------------

local knowledge = {}

function Internal.CacheFor(characterId)
    return knowledge[characterId]
end

function Internal.LoadKnowledge(characterId, cb)
    Internal.Repo.LoadForObserver(characterId, function(rows, err)
        if err then
            Omerta.Log.Error("identity", "knowledge load failed for #%d: %s", characterId, err)
            if cb then cb(false) end
            return
        end
        local map = {}
        for _, row in ipairs(rows or {}) do
            map[row.subject_id] = row.learned_name
        end
        knowledge[characterId] = map
        if cb then cb(true) end
    end)
end

function Internal.UnloadKnowledge(characterId)
    knowledge[characterId] = nil
end

function Omerta.Identity.Knows(observerId, subjectId)
    local map = knowledge[observerId]
    return map ~= nil and map[subjectId] ~= nil
end

function Omerta.Identity.GetKnownName(observerId, subjectId)
    local map = knowledge[observerId]
    return map and map[subjectId] or nil
end

-- Records that `observer` now knows `subject` by `name`. Every disclosure is
-- audited (Tech §23) — with hidden identity central to the design, staff must
-- be able to answer "who knew, and how did they learn it?".
function Omerta.Identity.Learn(observerId, subjectId, name, source, cb)
    cb = cb or function() end
    if observerId == subjectId then cb(false, "a character always knows itself") return end
    if not Omerta.Identity.SOURCES[source] then cb(false, "unknown source '" .. tostring(source) .. "'") return end

    Internal.Repo.Learn(observerId, subjectId, name, source, os.time(), function(ok, err)
        if not ok then cb(false, err) return end
        if knowledge[observerId] then knowledge[observerId][subjectId] = name end
        Omerta.Log.Audit("identity.learned", {
            observer_character = observerId,
            subject_character = subjectId,
            name = name,
            source = source,
        })
        if Omerta.InEngine then
            hook.Run("Omerta.IdentityLearned", observerId, subjectId, name, source)
        end
        cb(true)
    end)
end

function Omerta.Identity.Forget(observerId, subjectId, cb)
    cb = cb or function() end
    Internal.Repo.Forget(observerId, subjectId, function(ok, err)
        if not ok then cb(false, err) return end
        if knowledge[observerId] then knowledge[observerId][subjectId] = nil end
        Omerta.Log.Audit("identity.forgotten", {
            observer_character = observerId, subject_character = subjectId,
        })
        cb(true)
    end)
end

--------------------------------------------------------------------------------
-- Resolution over the wire
--------------------------------------------------------------------------------

function Internal.SendResolved(ply, entIndex)
    if not Omerta.InEngine then return end
    local target = Entity(entIndex)
    local observer = Omerta.Characters.Get(ply)

    local function reply(name, known)
        Omerta.Net.Send("identity.name",
            { target = entIndex, name = name, known = known }, ply)
    end

    if not (IsValid(target) and target:IsPlayer()) or not observer then
        reply(Omerta.Identity.UNKNOWN, false)
        return
    end

    -- Distance is validated here, not trusted from the client: resolution must
    -- never become a way to enumerate people you cannot see.
    if ply:GetPos():Distance(target:GetPos()) > Omerta.Interaction.MAX_RANGE then
        reply(Omerta.Identity.UNKNOWN, false)
        return
    end

    local subject = Omerta.Characters.Get(target)
    if not subject then reply(Omerta.Identity.UNKNOWN, false) return end

    local knownName = Omerta.Identity.GetKnownName(observer.id, subject.id)
    local name, known = Omerta.Identity.ResolveDisplayName(observer, subject, knownName)
    reply(name, known)
end

-- Tells everyone nearby who knows this character to re-resolve them.
local function invalidateFor(observerPly, subjectPly)
    if not (Omerta.InEngine and IsValid(observerPly) and IsValid(subjectPly)) then return end
    Omerta.Net.Send("identity.invalidate", { target = subjectPly:EntIndex() }, observerPly)
end

--------------------------------------------------------------------------------
-- Introductions (D-013: one-way, with reciprocation offered)
--------------------------------------------------------------------------------

local pendingPrompts = {} -- recipientSteamID64 -> { fromSteamID64, expires }

function Internal.Introduce(ply, target)
    local from = Omerta.Characters.Get(ply)
    local to = Omerta.Characters.Get(target)
    if not (from and to) then return false, "no character" end

    -- Only the introducer's name is disclosed. The recipient gives nothing
    -- away unless they choose to (D-013).
    Omerta.Identity.Learn(to.id, from.id, from.first_name .. " " .. from.last_name,
        "introduction", function(ok)
        if not ok then return end
        invalidateFor(target, ply)

        if not Omerta.InEngine then return end
        -- Offer the recipient a one-keypress reciprocation.
        if not Omerta.Identity.Knows(from.id, to.id) then
            pendingPrompts[target:SteamID64()] = {
                from = ply:SteamID64(),
                expires = CurTime() + Omerta.Config.Get("identity.prompt_timeout"),
            }
            Omerta.Net.Send("identity.introduce_prompt", {
                from = ply:EntIndex(),
                name = from.first_name .. " " .. from.last_name,
            }, target)
        end
    end)
    return true
end

function Internal.HandleReply(ply, entIndex, accept)
    if not Omerta.InEngine then return end
    local sid = ply:SteamID64()
    local pending = pendingPrompts[sid]
    pendingPrompts[sid] = nil
    if not accept or not pending then return end
    if CurTime() > pending.expires then return end

    local other = Entity(entIndex)
    -- The prompt names a specific person; a reply pointing anywhere else is
    -- discarded rather than honoured.
    if not (IsValid(other) and other:IsPlayer() and other:SteamID64() == pending.from) then
        return
    end
    if ply:GetPos():Distance(other:GetPos()) > Omerta.Config.Get("identity.introduce_range") then
        return
    end

    local from = Omerta.Characters.Get(ply)
    local to = Omerta.Characters.Get(other)
    if not (from and to) then return end

    Omerta.Identity.Learn(to.id, from.id, from.first_name .. " " .. from.last_name,
        "introduction", function(ok)
        if ok then invalidateFor(other, ply) end
    end)
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function MODULE:OnLoad()
    Omerta.DB.DefineTable("identity_knowledge", {
        columns = {
            { name = "observer_id",  type = "ref", null = false },
            { name = "subject_id",   type = "ref", null = false },
            { name = "learned_name", type = "text", length = 56, null = false },
            { name = "source",       type = "text", length = 16, null = false },
            { name = "learned_at",   type = "timestamp", null = false },
            { name = "confidence",   type = "int", null = false, default = 100 },
            { name = "notes",        type = "text", length = 255 },
        },
        primary = { "observer_id", "subject_id" },
        indexes = { { "subject_id" } },
    })

    Omerta.DB.AddMigration(5, "identity knowledge", function(m)
        m:CreateTable("identity_knowledge")
    end)

    -- The framework's first consumer, and the template for every later one.
    Omerta.Interaction.Register("identity.introduce", {
        label = "Introduce Yourself",
        order = 10,
        targets = "player",
        range = 96,
        predicate = function(ply, target)
            local from = Omerta.Characters.Get(ply)
            local to = Omerta.Characters.Get(target)
            if not (from and to) then return false end
            -- Nothing to offer if they already know you.
            if Omerta.Identity.Knows(to.id, from.id) then
                return false, "they already know you"
            end
            return true
        end,
        run = function(ply, target) Internal.Introduce(ply, target) end,
    })
end

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    hook.Add("Omerta.CharacterLoaded", "omerta.identity.load", function(_, character)
        Internal.LoadKnowledge(character.id)
    end)

    hook.Add("PlayerDisconnected", "omerta.identity.unload", function(ply)
        local character = Omerta.Characters.Get(ply)
        if character then Internal.UnloadKnowledge(character.id) end
        pendingPrompts[ply:SteamID64() or ""] = nil
    end)

    -- Staff: inspect who knows a character, for investigating metagaming.
    -- Accepts a character id or a SteamID64, because a staff member holding a
    -- suspect has the latter, not the former.
    local function report(characterId)
        Internal.Repo.WhoKnows(characterId, function(rows, err)
            if err then Omerta.Log.Error("identity", "lookup failed: %s", err) return end
            Omerta.Log.Info("identity", "%d character(s) know #%d:", #(rows or {}), characterId)
            for _, row in ipairs(rows or {}) do
                Omerta.Log.Info("identity", "  character #%s knows them as '%s' (%s)",
                    tostring(row.observer_id), row.learned_name, row.source)
            end
        end)
    end

    concommand.Add("omerta_identity_who_knows", function(ply, _, args)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local arg = args[1]
        if not arg then
            Omerta.Log.Error("identity",
                "usage: omerta_identity_who_knows <characterId|steamID64>")
            return
        end

        -- SteamID64s are matched as TEXT: 17 digits exceed what Lua's integer
        -- formatting round-trips, so tonumber() would silently mangle them
        -- into a plausible-looking character id and answer the wrong question.
        if arg:find("^7656%d%d%d%d%d%d%d%d%d%d%d%d%d$") then
            local season = Omerta.Seasons.GetActive()
            if not season then
                Omerta.Log.Error("identity", "no active season — look the character up by id")
                return
            end
            Omerta.Accounts.GetBySteamID64(arg, function(account, aerr)
                if aerr then Omerta.Log.Error("identity", "lookup failed: %s", aerr) return end
                if not account then
                    Omerta.Log.Error("identity", "no account for SteamID64 %s", arg)
                    return
                end
                Omerta.Characters.Internal.Repo.GetActiveFor(account.id, season.id,
                    function(character)
                    if not character then
                        Omerta.Log.Error("identity",
                            "account #%d has no living character this season", account.id)
                        return
                    end
                    Omerta.Log.Info("identity", "%s is character #%d (%s %s)",
                        arg, character.id, character.first_name, character.last_name)
                    report(character.id)
                end)
            end)
            return
        end

        local id = tonumber(arg)
        if not id or id % 1 ~= 0 or id < 1 then
            Omerta.Log.Error("identity",
                "'%s' is neither a character id nor a SteamID64", arg)
            return
        end
        report(id)
    end)
end
