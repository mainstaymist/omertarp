-- The HUD controller: the ONE place anything is drawn on the persistent
-- screen. Elements declare a condition; the controller fades them in when it
-- becomes true and out when it stops being true, and draws nothing otherwise.

local elements = {}
local ordered = nil
local alphas = {}

function Omerta.HUD.Register(id, def)
    if type(id) ~= "string" or not id:find("^[a-z0-9_%.]+$") then
        error("HUD element id '" .. tostring(id) .. "' must be lowercase [a-z0-9_.]", 2)
    end
    if elements[id] then error("HUD element '" .. id .. "' registered twice", 2) end
    if type(def.draw) ~= "function" then
        error("HUD element '" .. id .. "' needs a draw function", 2)
    end
    if def.visible ~= nil and type(def.visible) ~= "function" then
        error("HUD element '" .. id .. "' visible must be a function", 2)
    end
    def.id = id
    def.order = def.order or 100
    def.fade = def.fade or 0.3
    elements[id] = def
    alphas[id] = 0
    ordered = nil
    return def
end

function Omerta.HUD.Unregister(id)
    elements[id] = nil
    alphas[id] = nil
    ordered = nil
end

function Omerta.HUD.GetElements()
    if ordered then return ordered end
    ordered = {}
    for _, def in pairs(elements) do ordered[#ordered + 1] = def end
    table.sort(ordered, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    return ordered
end

-- What is on screen right now, and why. The M8 self-test asserts this is empty
-- for a healthy idle character — the milestone's actual acceptance criterion.
function Omerta.HUD.VisibleElements()
    local visible = {}
    for _, def in ipairs(Omerta.HUD.GetElements()) do
        if def.visible and def.visible() then visible[#visible + 1] = def.id end
    end
    return visible
end

--------------------------------------------------------------------------------
-- Scale and fonts (accessibility)
--------------------------------------------------------------------------------

CreateClientConVar("omerta_ui_scale", "1", true, false)

function Omerta.HUD.Scale()
    return Omerta.HUD.ClampScale(GetConVar("omerta_ui_scale"):GetFloat())
end

-- `headline` is deliberately the only size above body text. It exists for the
-- two moments the game raises its voice — bleeding out, and dying — and adding
-- a third would start the drift the empty-screen rule exists to prevent.
--
-- Sized up ~20% from the first pass, which looked right in screenshots and
-- was unreadable at a playing distance.
local FONT_SIZES = { headline = 46, body = 26, label = 23, small = 20 }

local function buildFonts()
    local scale = Omerta.HUD.Scale()
    for role, size in pairs(FONT_SIZES) do
        -- Germania One (OFL; the file and its licence ship in
        -- content/resource/fonts, pushed to clients by the hud module).
        -- The engine loads any TTF under resource/fonts on its own — the
        -- family name here just has to match the one inside the file. A
        -- client that somehow lacks it falls back to the engine default,
        -- which is legible if charmless.
        surface.CreateFont("Omerta.HUD." .. role, {
            font = "Germania One", size = math.Round(size * scale), weight = 400,
            antialias = true,
        })
    end
end
buildFonts()
cvars.AddChangeCallback("omerta_ui_scale", buildFonts, "omerta.hud.fonts")

function Omerta.HUD.Font(role)
    return "Omerta.HUD." .. (FONT_SIZES[role] and role or "body")
end

--------------------------------------------------------------------------------
-- Suppression of the engine's own HUD
--------------------------------------------------------------------------------
-- M6 removed what leaked identity; these are the rest of GDD §8's list. The
-- crosshair goes too (D-017) — an indicator for interactable targets replaces
-- it below. HUDDrawTargetID is included because it draws player names.

local HIDDEN = {
    CHudHealth = true,
    CHudBattery = true,
    CHudAmmo = true,
    CHudSecondaryAmmo = true,
    CHudCrosshair = true,
    CHudSuitPower = true,
    -- The sandbox weapon selector. The weapons module draws its own four-slot
    -- hotbar in the HUD's own idiom; two selectors answering one wheel would
    -- fight over it.
    CHudWeaponSelection = true,
}

hook.Add("HUDShouldDraw", "omerta.hud.suppress", function(name)
    if HIDDEN[name] then return false end
end)

hook.Add("HUDDrawTargetID", "omerta.hud.no_targetid", function() return false end)

--------------------------------------------------------------------------------
-- The draw loop
--------------------------------------------------------------------------------

hook.Add("HUDPaint", "omerta.hud.draw", function()
    local dt = FrameTime()
    for _, def in ipairs(Omerta.HUD.GetElements()) do
        local want = def.visible == nil or def.visible() == true
        alphas[def.id] = Omerta.HUD.StepAlpha(alphas[def.id] or 0, want, dt, def.fade)
        if alphas[def.id] > 0 then
            local ok, err = pcall(def.draw, alphas[def.id])
            if not ok then
                -- A broken element must not take the whole screen down with it.
                Omerta.Log.Error("hud", "element '%s' failed to draw: %s", def.id, tostring(err))
                Omerta.HUD.Unregister(def.id)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Cues: every audio signal must have a visual counterpart (Tech §8)
--------------------------------------------------------------------------------

local cues = {}

function Omerta.HUD.Cue(text, duration)
    cues[#cues + 1] = { text = text, expires = CurTime() + (duration or 4) }
end

Omerta.HUD.Register("cues", {
    order = 90,
    fade = 0.2,
    visible = function()
        for i = #cues, 1, -1 do
            if CurTime() > cues[i].expires then table.remove(cues, i) end
        end
        return #cues > 0
    end,
    draw = function(alpha)
        local y = ScrH() * 0.30
        for _, cue in ipairs(cues) do
            draw.SimpleText(cue.text, Omerta.HUD.Font("body"), ScrW() * 0.5, y,
                Color(235, 225, 205, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            y = y + 30 * Omerta.HUD.Scale()
        end
    end,
})

--------------------------------------------------------------------------------
-- Stamina (Tech §8: fade in below threshold or during drain)
--------------------------------------------------------------------------------

local stamina, staminaChangedAt = 1, 0

hook.Add("Omerta.StaminaUpdated", "omerta.hud.stamina", function(value)
    if value < stamina then staminaChangedAt = CurTime() end
    stamina = value
end)

Omerta.HUD.Register("stamina", {
    order = 20,
    fade = 0.4,
    visible = function()
        if stamina < 0.35 then return true end          -- low
        return CurTime() - staminaChangedAt < 1.5 and stamina < 1 -- draining
    end,
    draw = function(alpha)
        local scale = Omerta.HUD.Scale()
        local w, h = 160 * scale, 3 * scale
        local x, y = (ScrW() - w) * 0.5, ScrH() * 0.78
        surface.SetDrawColor(20, 20, 20, 140 * alpha)
        surface.DrawRect(x, y, w, h)
        -- Reddens as it empties: readable without relying on colour alone,
        -- since the bar also shortens.
        local warn = stamina < 0.35
        surface.SetDrawColor(warn and 190 or 210, warn and 120 or 205, warn and 110 or 185,
            230 * alpha)
        surface.DrawRect(x, y, w * math.max(0, math.min(1, stamina)), h)
    end,
})

--------------------------------------------------------------------------------
-- Injury seam — M19 fills this in
--------------------------------------------------------------------------------
-- Ships invisible: no provider, no element. The same seam pattern D-014 used
-- for concealment, so M19 needs no changes here.

local injuryProvider = nil

function Omerta.HUD.RegisterInjuryProvider(fn)
    injuryProvider = fn
end

Omerta.HUD.Register("injury", {
    order = 10,
    fade = 0.5,
    visible = function()
        return injuryProvider ~= nil and injuryProvider() ~= nil
    end,
    draw = function(alpha)
        local state = injuryProvider and injuryProvider()
        if not state then return end
        draw.SimpleText(state, Omerta.HUD.Font("body"), ScrW() * 0.5, ScrH() * 0.72,
            Color(200, 110, 100, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end,
})

--------------------------------------------------------------------------------
-- Interactable indicator (D-017, replacing the crosshair)
--------------------------------------------------------------------------------

-- Players are always potentially interactable (M5). Everything else registers
-- its class, which is how M9's dropped items and containers light the dot up
-- without this file learning what an item is.
local interactableClasses = {}
local interactablePredicates = {}

function Omerta.HUD.RegisterInteractableClass(class)
    interactableClasses[class] = true
end

-- For things whose class is not their own: M19's bodies are prop_ragdolls, and
-- lighting the dot up for every ragdoll on the map would point at furniture.
-- fn(ent) returns true if this particular entity is worth walking to.
function Omerta.HUD.RegisterInteractablePredicate(id, fn)
    interactablePredicates[id] = fn
end

local function traceForTarget()
    local ply = LocalPlayer()
    if not (IsValid(ply) and ply:Alive()) then return nil end
    local tr = util.TraceLine({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * Omerta.Interaction.MAX_RANGE,
        filter = ply,
    })
    if not IsValid(tr.Entity) then return nil end
    if tr.Entity:IsPlayer() then return tr.Entity end
    if interactableClasses[tr.Entity:GetClass()] then return tr.Entity end
    for _, fn in pairs(interactablePredicates) do
        local ok, matched = pcall(fn, tr.Entity)
        if ok and matched then return tr.Entity end
    end
    return nil
end

-- Cached for the frame. `visible` and `draw` both need the answer and a trace
-- is not free; more importantly, tracing twice can return two different
-- entities in one frame, which is how a label ends up describing something the
-- player is no longer looking at.
local cachedFrame, cachedTarget = -1, nil

local function interactableTarget()
    local frame = FrameNumber()
    if cachedFrame ~= frame then
        cachedFrame, cachedTarget = frame, traceForTarget()
    end
    return cachedTarget
end

-- What the player is looking at right now, or nil. Exposed so a module can
-- add a hint about its own entity without running a second trace — and so the
-- answer is the same one the dot is using.
function Omerta.HUD.InteractableTarget()
    return interactableTarget()
end

Omerta.HUD.Register("interactable", {
    order = 40,
    fade = 0.15,
    visible = function() return interactableTarget() ~= nil end,
    draw = function(alpha)
        local scale = Omerta.HUD.Scale()
        local size = 3 * scale
        surface.SetDrawColor(235, 230, 215, 170 * alpha)
        surface.DrawRect(ScrW() * 0.5 - size * 0.5, ScrH() * 0.5 - size * 0.5, size, size)

        -- Under the dot rather than over it: the thing you are looking at stays
        -- unobstructed, and the eye is already there.
        local title, subtitle = Omerta.HUD.LabelFor(interactableTarget())
        if not title then return end

        local y = ScrH() * 0.5 + 14 * scale
        draw.SimpleText(title, Omerta.HUD.Font("label"), ScrW() * 0.5, y,
            Color(235, 230, 215, 235 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        if subtitle then
            draw.SimpleText(subtitle, Omerta.HUD.Font("small"), ScrW() * 0.5,
                y + 26 * scale,
                Color(190, 184, 170, 205 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end,
})
