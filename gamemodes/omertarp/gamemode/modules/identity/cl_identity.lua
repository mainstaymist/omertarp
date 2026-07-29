-- Client display of identity: a contextual label for whoever you are looking
-- at, and the reciprocation prompt.
--
-- Explicitly NOT a nameplate (Tech §6): nothing is drawn above anyone's head,
-- nothing persists, and the label only appears for the single person under
-- your crosshair, within range.

local LABEL_RANGE = 256
local REQUEST_INTERVAL = 0.4

-- entIndex -> { name, known, at }. Cleared aggressively: a stale name must
-- never outlive its subject.
local resolved = {}
local lastRequest = {}
local prompt = nil -- { from, name, expires }

local function clearAll() resolved = {}; lastRequest = {} end
hook.Add("Omerta.CharactersState", "omerta.identity.clear", clearAll)
hook.Add("OnReloaded", "omerta.identity.clear_reload", clearAll)

hook.Add("Omerta.IdentityResolved", "omerta.identity.store", function(entIndex, name, known)
    resolved[entIndex] = { name = name, known = known, at = CurTime() }
end)

hook.Add("Omerta.IdentityInvalidated", "omerta.identity.invalidate", function(entIndex)
    resolved[entIndex] = nil
    lastRequest[entIndex] = nil
end)

hook.Add("EntityRemoved", "omerta.identity.forget_entity", function(ent)
    if not IsValid(ent) then return end
    local i = ent:EntIndex()
    resolved[i] = nil
    lastRequest[i] = nil
end)

local function lookedAtPlayer()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return nil end
    local tr = util.TraceLine({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * LABEL_RANGE,
        filter = ply,
    })
    local ent = tr.Entity
    if not IsValid(ent) then return nil end
    if ent:IsPlayer() then return ent end
    -- Not a player, but possibly still a person. M19's bodies claim themselves
    -- through this predicate; the server does the actual resolving, per
    -- observer, so a body you would not recognise standing up stays Unknown.
    for _, fn in pairs(Omerta.Identity.Internal.LabelPredicates or {}) do
        local ok, matched = pcall(fn, ent)
        if ok and matched then return ent end
    end
    return nil
end

-- Registered with the HUD controller (M8) rather than hooking HUDPaint
-- directly, so the empty-screen rule stays inspectable in one place and this
-- label gains fading and accessibility scaling for free.
local current = nil -- the entry for whoever is under the crosshair right now

Omerta.HUD.Register("identity.label", {
    order = 30,
    fade = 0.2,
    visible = function()
        current = nil
        local target = lookedAtPlayer()
        if not target then return false end

        local index = target:EntIndex()
        -- Ask the server, at most every REQUEST_INTERVAL per entity. The server
        -- re-checks range and answers from THIS observer's knowledge only.
        local now = CurTime()
        if not resolved[index] and (lastRequest[index] or 0) + REQUEST_INTERVAL < now then
            lastRequest[index] = now
            Omerta.Net.Request("identity.resolve", { target = index })
        end
        current = resolved[index]
        return current ~= nil
    end,
    draw = function(alpha)
        if not current then return end
        local colour = current.known and Color(235, 230, 215, 255 * alpha)
            or Color(165, 165, 165, 210 * alpha)
        draw.SimpleText(current.name, Omerta.HUD.Font("body"),
            ScrW() * 0.5, ScrH() * 0.5 + 40 * Omerta.HUD.Scale(),
            colour, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end,
})

--------------------------------------------------------------------------------
-- Reciprocation prompt (D-013)
--------------------------------------------------------------------------------

hook.Add("Omerta.IntroducePrompt", "omerta.identity.prompt", function(from, name)
    prompt = { from = from, name = name, expires = CurTime() + 20 }
end)

Omerta.HUD.Register("identity.prompt", {
    order = 50,
    fade = 0.25,
    visible = function()
        if prompt and CurTime() > prompt.expires then prompt = nil end
        return prompt ~= nil
    end,
    draw = function(alpha)
        if not prompt then return end
        local scale = Omerta.HUD.Scale()
        local x, y = ScrW() * 0.5, ScrH() * 0.66
        draw.SimpleText(prompt.name .. " introduced themselves.", Omerta.HUD.Font("body"),
            x, y, Color(235, 230, 215, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText("[E] give your name    [R] say nothing", Omerta.HUD.Font("label"),
            x, y + 26 * scale, Color(180, 180, 180, 220 * alpha),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end,
})

hook.Add("PlayerBindPress", "omerta.identity.prompt_reply", function(_, bind, pressed)
    if not prompt or not pressed then return end
    local accept
    if bind == "+use" then accept = true
    elseif bind == "+reload" then accept = false
    else return end

    Omerta.Net.Request("identity.introduce_reply", { to = prompt.from, accept = accept })
    prompt = nil
    return true -- swallow the keypress so it does not also use/reload
end)
