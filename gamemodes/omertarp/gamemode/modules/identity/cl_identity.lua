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
    if IsValid(ent) and ent:IsPlayer() then return ent end
    return nil
end

surface.CreateFont("Omerta.Identity", {
    font = "Roboto", size = 21, weight = 500, antialias = true,
})
surface.CreateFont("Omerta.IdentityPrompt", {
    font = "Roboto", size = 18, weight = 500, antialias = true,
})

hook.Add("HUDPaint", "omerta.identity.label", function()
    local target = lookedAtPlayer()
    if not target then return end

    local index = target:EntIndex()
    local entry = resolved[index]

    -- Ask the server, at most every REQUEST_INTERVAL per entity. The server
    -- re-checks range and answers from THIS observer's knowledge only.
    local now = CurTime()
    if not entry and (lastRequest[index] or 0) + REQUEST_INTERVAL < now then
        lastRequest[index] = now
        Omerta.Net.Request("identity.resolve", { target = index })
    end
    if not entry then return end

    local colour = entry.known and Color(235, 230, 215) or Color(165, 165, 165, 210)
    draw.SimpleText(entry.name, "Omerta.Identity", ScrW() * 0.5, ScrH() * 0.5 + 40,
        colour, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end)

--------------------------------------------------------------------------------
-- Reciprocation prompt (D-013)
--------------------------------------------------------------------------------

hook.Add("Omerta.IntroducePrompt", "omerta.identity.prompt", function(from, name)
    prompt = { from = from, name = name, expires = CurTime() + 20 }
end)

hook.Add("HUDPaint", "omerta.identity.prompt_draw", function()
    if not prompt then return end
    if CurTime() > prompt.expires then prompt = nil return end

    local x, y = ScrW() * 0.5, ScrH() * 0.72
    draw.SimpleText(prompt.name .. " introduced themselves.", "Omerta.Identity", x, y,
        Color(235, 230, 215), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    draw.SimpleText("[E] give your name    [R] say nothing", "Omerta.IdentityPrompt",
        x, y + 26, Color(180, 180, 180, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end)

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
