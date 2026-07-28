-- Identity: everyone is Unknown until introduced (D-013, D-014).
--
-- The resolution rule and the concealment seam live here because the client
-- needs the vocabulary; the KNOWLEDGE itself never leaves the server. A client
-- is told one resolved name at a time, for one person it is currently looking
-- at, and can never enumerate.


Omerta.Identity = Omerta.Identity or {}

Omerta.Identity.UNKNOWN = "Unknown"

Omerta.Identity.SOURCES = {
    introduction  = true,
    document      = true,
    police_record = true,
    rumor         = true,
    staff         = true,
}

--------------------------------------------------------------------------------
-- Concealment seam (D-014)
--------------------------------------------------------------------------------
-- Knowledge is permanent; RECOGNITION is situational. A concealed face
-- resolves as Unknown to everyone — including people who know the character,
-- including their own crew, who must rely on voice.
--
-- No clothing system exists yet, so no provider is registered and this returns
-- false. The disguise milestone registers one and the rule starts biting with
-- no change to resolution.

local concealmentProviders = {}

function Omerta.Identity.RegisterConcealmentProvider(fn)
    concealmentProviders[#concealmentProviders + 1] = fn
end

function Omerta.Identity.IsConcealed(subjectChar)
    for _, fn in ipairs(concealmentProviders) do
        if fn(subjectChar) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Public title seam (D-021)
--------------------------------------------------------------------------------
-- Some things a stranger CAN read off you. A uniform is a deliberate public
-- announcement: you do not know the officer's name, but you know they are an
-- officer. Nothing in the base game grants a title; M10 registers the police
-- uniform, and it keys off the garment rather than the institution, so an
-- officer in plain clothes is a stranger like anyone else.

local titleProviders = {}

-- What character, if any, an entity represents.
--
-- Players are the obvious answer and the only one M5 needed. M19's bodies are
-- the second: a man on the floor is still a person, and looking at him must
-- resolve through exactly this path rather than through a name painted on an
-- entity. Providers are asked in registration order; the first to claim the
-- entity wins.
local subjectProviders = {}

-- fn(ent, cb) -> true if this provider claims the entity (and will call cb
-- with the character row, or nil), false/nil to decline.
function Omerta.Identity.RegisterSubjectProvider(id, fn)
    subjectProviders[id] = fn
end

function Omerta.Identity.ResolveSubject(ent, cb)
    for _, fn in pairs(subjectProviders) do
        local ok, claimed = pcall(fn, ent, cb)
        if ok and claimed then return true end
    end
    return false
end

function Omerta.Identity.RegisterTitleProvider(fn)
    titleProviders[#titleProviders + 1] = fn
end

function Omerta.Identity.PublicTitle(subjectChar)
    for _, fn in ipairs(titleProviders) do
        local title = fn(subjectChar)
        if title then return title end
    end
    return nil
end

--------------------------------------------------------------------------------
-- The resolution rule
--------------------------------------------------------------------------------
-- Pure, and the single place the rule is expressed (Tech §6).
--   knownName: what THIS observer has learned about this subject, or nil.
-- Returns the display name and whether it is a real identification.
function Omerta.Identity.ResolveDisplayName(observerChar, subjectChar, knownName)
    if not subjectChar then return Omerta.Identity.UNKNOWN, false end

    -- You always know yourself, mask or not.
    if observerChar and observerChar.id == subjectChar.id then
        return subjectChar.first_name .. " " .. subjectChar.last_name, true
    end

    local title = Omerta.Identity.PublicTitle(subjectChar)

    -- D-014: concealment defeats recognition before knowledge is consulted.
    -- A mask hides a face, not a uniform — so a title still reads.
    if Omerta.Identity.IsConcealed(subjectChar) then
        return title or Omerta.Identity.UNKNOWN, false
    end

    if knownName and knownName ~= "" then
        return title and (title .. " " .. knownName) or knownName, true
    end
    return title or Omerta.Identity.UNKNOWN, false
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------
-- Resolution is per-observer, on demand, one entity at a time, distance
-- checked server-side. Nothing is ever pushed preemptively: telling a client
-- the names it knows would let it infer who is online.

Omerta.Net.Register("identity.resolve", {
    realm = "client_to_server",
    schema = { { name = "target", type = "uint", bits = 16 } },
    rate = { burst = 15, per = 5 },
    handler = function(ply, payload)
        Omerta.Identity.Internal.SendResolved(ply, payload.target)
    end,
})

Omerta.Net.Register("identity.name", {
    realm = "server_to_client",
    schema = {
        { name = "target", type = "uint", bits = 16 },
        { name = "name",   type = "string", maxlen = 56 },
        { name = "known",  type = "bool" },
    },
    handler = function(payload)
        hook.Run("Omerta.IdentityResolved", payload.target, payload.name, payload.known)
    end,
})

Omerta.Net.Register("identity.invalidate", {
    realm = "server_to_client",
    schema = { { name = "target", type = "uint", bits = 16 } },
    handler = function(payload)
        hook.Run("Omerta.IdentityInvalidated", payload.target)
    end,
})

-- The reciprocate prompt (D-013): the recipient of an introduction is offered
-- the chance to introduce themselves back. Declining is always permitted.
Omerta.Net.Register("identity.introduce_prompt", {
    realm = "server_to_client",
    schema = {
        { name = "from", type = "uint", bits = 16 },
        { name = "name", type = "string", maxlen = 56 },
    },
    handler = function(payload)
        hook.Run("Omerta.IntroducePrompt", payload.from, payload.name)
    end,
})

Omerta.Net.Register("identity.introduce_reply", {
    realm = "client_to_server",
    schema = {
        { name = "to",     type = "uint", bits = 16 },
        { name = "accept", type = "bool" },
    },
    rate = { burst = 5, per = 10 },
    handler = function(ply, payload)
        Omerta.Identity.Internal.HandleReply(ply, payload.to, payload.accept)
    end,
})
