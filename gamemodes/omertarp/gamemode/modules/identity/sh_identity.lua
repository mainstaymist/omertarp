-- Identity: everyone is Unknown until introduced (D-013, D-014).
--
-- The resolution rule and the concealment seam live here because the client
-- needs the vocabulary; the KNOWLEDGE itself never leaves the server. A client
-- is told one resolved name at a time, for one person it is currently looking
-- at, and can never enumerate.

Omerta.Module.Register({
    name = "identity",
    depends = { "database", "characters", "interaction" },
})

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

    -- D-014: concealment defeats recognition before knowledge is consulted.
    if Omerta.Identity.IsConcealed(subjectChar) then
        return Omerta.Identity.UNKNOWN, false
    end

    if knownName and knownName ~= "" then return knownName, true end
    return Omerta.Identity.UNKNOWN, false
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
