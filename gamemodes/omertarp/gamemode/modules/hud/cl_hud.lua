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
    if def.rise ~= nil and (type(def.rise) ~= "number" or def.rise < 0) then
        error("HUD element '" .. id .. "' rise must be a distance in design px", 2)
    end
    def.id = id
    def.order = def.order or 100
    def.fade = def.fade or 0.3
    -- Travel, in design pixels, opt-IN and zero by default.
    --
    -- The default is the important half of this. Most of what the controller
    -- draws is an INSTRUMENT rather than an announcement — the crosshair, the
    -- stamina ticks, the hotbar, the ammunition count, the ladder of hints
    -- under the dot — and an instrument that moves is one the eye has to find
    -- again every time it appears. The hint ladder is the sharpest case: it is
    -- anchored to the crosshair by construction, so anything that slid it would
    -- be sliding it away from the thing it is describing. Rise is therefore
    -- something a plate has to ask for, and the plates that ask for it are the
    -- ones that genuinely POP UP: a timed action starting, a notice arriving.
    def.rise = def.rise or 0
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

-- A MULTIPLE of Omerta.HUD.SCALE_BASE, not an absolute size. 1 is the
-- interface as signed off; see sh_hud.lua for why the base exists.
CreateClientConVar("omerta_ui_scale", "1", true, false)

-- Anyone who tuned this before the rebase has an absolute scale stored in
-- their config, and read as a multiple it would hand them an interface half
-- again too big. Corrected once, here, at the moment the file loads — writing
-- the convar back so it is corrected in their config too rather than
-- reinterpreted on every read.
do
    local stored = GetConVar("omerta_ui_scale"):GetFloat()
    local migrated = Omerta.HUD.MigrateScale(stored)
    if math.abs(migrated - stored) > 0.001 then
        RunConsoleCommand("omerta_ui_scale", tostring(migrated))
    end
end

function Omerta.HUD.Scale()
    return Omerta.HUD.SCALE_BASE
        * Omerta.HUD.ClampScale(GetConVar("omerta_ui_scale"):GetFloat())
end

-- Sizes, faces and weights all come from the Carbon token table (sh_theme).
-- Nothing here decides what a heading looks like; it only builds what the
-- standard declares, at the player's accessibility scale.
local THEME = Omerta.HUD.Theme

local function buildFonts()
    local scale = Omerta.HUD.Scale()
    for role, def in pairs(THEME.TYPE) do
        -- The engine loads any TTF under resource/fonts by itself; the family
        -- name here only has to match the one inside the file. A client that
        -- somehow lacks it falls back to the engine default — legible, if
        -- charmless. Weights live in the FACE (Oswald Light, Archivo Medium),
        -- so no weight parameter: asking the rasteriser to synthesise one
        -- fakes exactly what the guide picked real files for.
        surface.CreateFont("Omerta.HUD." .. role, {
            font = THEME.FACE[def.face] or THEME.FACE.text,
            size = math.Round(THEME.TypeSize(role) * scale),
            antialias = true,
        })
    end
end
buildFonts()
cvars.AddChangeCallback("omerta_ui_scale", buildFonts, "omerta.hud.fonts")

function Omerta.HUD.Font(role)
    return "Omerta.HUD." .. (THEME.TYPE[role] and role or "body")
end

-- Whether the interface is being drawn in black and white. Declared here
-- because Colour is the chokepoint that has to honour it; the convar and the
-- change callback that maintain it live in the black-and-white section below,
-- next to the screen pass they belong with.
local monochrome = false

-- A themed colour as a drawable Color, with optional alpha (0..1 or 0..255).
-- Every call site names a ROLE — "brass", "rule" — so a re-theme is sh_theme,
-- never a search for hex values.
--
-- This is also the ONE place the black-and-white setting reaches the
-- interface. Every token in the game comes through here, so desaturating at
-- this point takes the HUD, the widget kit and every window together and
-- cannot be forgotten by a screen written next year.
function Omerta.HUD.Colour(token, alpha)
    local rgb = THEME.COLOUR[token] or THEME.COLOUR.text
    alpha = alpha or 255
    if alpha <= 1 then alpha = alpha * 255 end
    if monochrome then
        local luma = Omerta.HUD.Luma(rgb[1], rgb[2], rgb[3])
        return Color(luma, luma, luma, alpha)
    end
    return Color(rgb[1], rgb[2], rgb[3], alpha)
end

-- A Carbon spacing step in pixels, at the player's scale. Layout code asks for
-- Space(5), not for 16.
function Omerta.HUD.Space(step)
    return THEME.Step(step) * Omerta.HUD.Scale()
end

-- A window size, scaled, but never larger than the screen it has to sit on.
--
-- A design px constant times the scale is a promise about a monitor nobody
-- has agreed to. At 1x the loot window comes to 1680x980, which is a
-- comfortable window on the 1920x1080 this was tuned on and a window with its
-- right-hand column off the edge on a 1366x768 laptop — and the player whose
-- columns are missing has no way to know a slider would bring them back.
-- Every scaled window goes through here, so the scale sets the size it WANTS
-- and the screen keeps the final say.
function Omerta.HUD.Fit(width, height, margin)
    margin = margin or Omerta.HUD.Space(5)
    return math.min(width, ScrW() - margin * 2),
        math.min(height, ScrH() - margin * 2)
end

-- A filled circle, as a polygon.
--
-- The engine has no circle primitive, and draw.RoundedBox is not one: its
-- corners come from a texture, so below about a dozen pixels across it cannot
-- resolve the curve and renders a rounded square. Everything round in this
-- interface is small — a crosshair, a status pip — which is precisely the size
-- band where that fails, so the polygon is not an optimisation, it is the only
-- version that is actually round.
--
-- Segments scale with the radius: a 2px dot needs nothing like the vertices a
-- 40px ring does, and a fixed count is either wasteful at the bottom or
-- visibly faceted at the top.
function Omerta.HUD.Disc(cx, cy, radius, colour, segments)
    segments = segments or math.Clamp(math.ceil(radius * 4), 8, 64)
    local poly = {}
    for i = 1, segments do
        local angle = (i - 1) / segments * math.pi * 2
        poly[i] = { x = cx + math.cos(angle) * radius,
            y = cy + math.sin(angle) * radius }
    end
    draw.NoTexture()
    surface.SetDrawColor(colour)
    surface.DrawPoly(poly)
end

-- Every piece of text drawn over the WORLD goes through this. The guide's
-- world-layer rule: a 1px HARD outline — four black offsets at full alpha, no
-- blur — because a soft shadow disappears against mid-grey and an outline is
-- a shape and cannot. The 1px stays 1px at every scale; a 1.5px hairline is a
-- grey smear. Panels that paint their own plate keep using draw.SimpleText.
function Omerta.HUD.Text(text, role, x, y, colour, alignX, alignY)
    local font = Omerta.HUD.Font(role)
    local outline = Color(0, 0, 0, colour.a or 255)
    draw.SimpleText(text, font, x + 1, y, outline, alignX, alignY)
    draw.SimpleText(text, font, x - 1, y, outline, alignX, alignY)
    draw.SimpleText(text, font, x, y + 1, outline, alignX, alignY)
    draw.SimpleText(text, font, x, y - 1, outline, alignX, alignY)
    draw.SimpleText(text, font, x, y, colour, alignX, alignY)
end

-- A cluster plate: the guide's scrim for anything over three lines — ink at
-- 62%, one 1px rule on the side facing the screen edge. `edge` is "top",
-- "bottom", "left" or "right"; alpha multiplies the element's own fade.
function Omerta.HUD.Scrim(x, y, w, h, edge, alpha)
    alpha = alpha or 1
    local theme = Omerta.HUD.Theme
    surface.SetDrawColor(Omerta.HUD.Colour("plate", theme.ALPHA.scrim * 255 * alpha))
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(Omerta.HUD.Colour("rule", 255 * alpha))
    if edge == "top" then surface.DrawRect(x, y, w, 1)
    elseif edge == "bottom" then surface.DrawRect(x, y + h - 1, w, 1)
    elseif edge == "left" then surface.DrawRect(x, y, 1, h)
    elseif edge == "right" then surface.DrawRect(x + w - 1, y, 1, h)
    end
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
-- The body below the eyes — REMOVED, deliberately
--------------------------------------------------------------------------------
-- There used to be a ShouldDrawLocalPlayer hook here that drew the player's own
-- model once the pitch went past 42 degrees, so looking down found feet.
--
-- It does not work and it cannot be made to. ShouldDrawLocalPlayer draws the
-- WHOLE model at its world position, head included, and the first-person camera
-- sits inside that head — so looking down put the camera through the model's
-- own geometry and the reported result was "the playermodel appears and you
-- look through it". A real first-person body needs a separate rig with the head
-- bone scaled away and the arms driven off the viewmodel, which is an art and
-- animation job, not a hook.
--
-- The project lead has an addon that does it properly. This is left as a
-- comment rather than deleted silently so nobody re-adds the one-liner in good
-- faith six months from now.

--------------------------------------------------------------------------------
-- Black and white (a settings option, default off)
--------------------------------------------------------------------------------
-- Full desaturation with a touch more contrast, so the period look is a
-- choice a player can make rather than a filter imposed on everybody.

CreateClientConVar("omerta_blackwhite", "0", true, false)

-- The interface goes grey with the world.
--
-- RenderScreenspaceEffects runs on the 3D scene only — the HUD and every VGUI
-- panel are drawn afterwards and are untouched by it, which is why the world
-- went monochrome and the brass in the menus stayed gold. The fix belongs in
-- Omerta.HUD.Colour rather than in a second screen pass: every token in the
-- interface already goes through that one function, so desaturating there
-- catches the HUD, the widget kit and every window at once, and a screen pass
-- over the top would also flatten the model preview and any future portrait,
-- which are photographs of a world that is already grey.
--
-- Cached against a change callback rather than read per call: this runs
-- several hundred times a frame and a convar lookup in that path is a real
-- cost for a value that changes when somebody clicks a button.
local function readMonochrome()
    monochrome = GetConVar("omerta_blackwhite"):GetBool()
end
readMonochrome()
cvars.AddChangeCallback("omerta_blackwhite", readMonochrome, "omerta.hud.mono")

hook.Add("RenderScreenspaceEffects", "omerta.hud.blackwhite", function()
    if not monochrome then return end
    DrawColorModify({
        ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
        ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
        ["$pp_colour_brightness"] = 0,
        ["$pp_colour_contrast"] = 1.05,
        ["$pp_colour_colour"] = 0,
    })
end)

--------------------------------------------------------------------------------
-- The draw loop
--------------------------------------------------------------------------------

-- Something may own the whole screen for a moment — the front end does, while
-- the menu is up. A suppressor stops the controller drawing at all, rather
-- than every element learning about every full-screen state there will ever be.
local suppressors = {}

function Omerta.HUD.RegisterSuppressor(id, fn)
    suppressors[id] = fn
end

function Omerta.HUD.Suppressed()
    for _, fn in pairs(suppressors) do
        local ok, yes = pcall(fn)
        if ok and yes then return true end
    end
    return false
end

-- draw(alpha, rise) — `rise` is how far BELOW its resting place the element
-- should draw itself this frame, in real pixels, and is zero for everything
-- that did not ask for travel. An element opts in by adding it to whatever Y it
-- already computes; one that ignores the second argument keeps behaving exactly
-- as it did, which is why this could be added to a live controller at all.
--
-- The OFFSET is eased even though the alpha is not. The fade is linear because
-- StepAlpha is the state and reversing it mid-fade has to be free; movement
-- with a linear ramp reads as a mechanism rather than as a thing arriving, so
-- the curve is applied where it is seen and nowhere else. Both are driven from
-- the same 0..1, so a plate that starts fading out halfway in turns round and
-- sinks from exactly where it had got to.
hook.Add("HUDPaint", "omerta.hud.draw", function()
    if Omerta.HUD.Suppressed() then return end
    local dt = FrameTime()
    local scale = Omerta.HUD.Scale()
    for _, def in ipairs(Omerta.HUD.GetElements()) do
        local want = def.visible == nil or def.visible() == true
        alphas[def.id] = Omerta.HUD.StepAlpha(alphas[def.id] or 0, want, dt, def.fade)
        if alphas[def.id] > 0 then
            local rise = def.rise > 0
                and Omerta.HUD.RevealOffset(Omerta.HUD.RevealEase(alphas[def.id]),
                    def.rise * scale)
                or 0
            local ok, err = pcall(def.draw, alphas[def.id], rise)
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
    -- A notice is the definition of a thing that pops up: it was not there, an
    -- event happened, and now it is. Twelve rather than the full window rise —
    -- the stack sits at the screen margin with nothing to travel over, and a
    -- plate that came from further away than the corner it lives in would read
    -- as having been thrown at the player.
    rise = 12,
    visible = function()
        for i = #cues, 1, -1 do
            if CurTime() > cues[i].expires then table.remove(cues, i) end
        end
        return #cues > 0
    end,
    draw = function(alpha, rise)
        -- The guide's transient notices: plates stacking down from the
        -- top-left at the screen margin, newest first and loudest, older ones
        -- dropping to half presence — no counters, no queue indicator.
        local scale = Omerta.HUD.Scale()
        local margin = Omerta.HUD.Space(5)
        local width = 380 * scale
        local pad = Omerta.HUD.Space(3)
        -- The whole stack travels together, so notices already on screen do not
        -- jump when a new one arrives underneath them.
        local y = margin + rise

        surface.SetFont(Omerta.HUD.Font("body"))
        for index = #cues, 1, -1 do
            local cue = cues[index]
            local age = #cues - index -- 0 = newest
            local presence = (age == 0 and 1 or 0.5) * alpha
            local _, textTall = surface.GetTextSize(cue.text)
            local tall = textTall + pad * 2

            Omerta.HUD.Scrim(margin, y, width, tall, "top", presence)
            draw.SimpleText(cue.text, Omerta.HUD.Font("body"),
                margin + pad, y + pad,
                Omerta.HUD.Colour("text", 255 * presence),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            y = y + tall + Omerta.HUD.Space(3)
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

-- The character panel in the inventory draws the same value as notches; one
-- accessor, so the number has one home.
function Omerta.HUD.Stamina()
    return stamina
end

-- The guide's stamina: twelve discrete 9×3 ticks at the bottom-left margin,
-- spent ones dropping to 18% — they STAY, they don't slide. A bar invites
-- reading a percentage; ticks read as "a few breaths left". Quantising also
-- retires the smoothing problem: a tick either exists or it does not, so the
-- four-per-second server updates never look like a staircase.
local STAMINA_TICKS = 12

Omerta.HUD.Register("stamina", {
    order = 20,
    fade = 0.4,
    visible = function()
        if stamina < 0.35 then return true end          -- low
        return CurTime() - staminaChangedAt < 1.5 and stamina < 1 -- draining
    end,
    draw = function(alpha)
        local scale = Omerta.HUD.Scale()
        local margin = Omerta.HUD.Space(5)
        local w, h, gap = 9 * scale, 3 * scale, 2 * scale
        local x = margin
        local y = ScrH() - margin - h
        local filled = math.floor(math.Clamp(stamina, 0, 1) * STAMINA_TICKS + 0.5)

        for i = 1, STAMINA_TICKS do
            surface.SetDrawColor(Omerta.HUD.Colour("text",
                (i <= filled and 235 or 235 * 0.18) * alpha))
            surface.DrawRect(x, y, w, h)
            x = x + w + gap
        end
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
        -- Bone, not red: the guide colours nothing but the selected and the
        -- irreversible, and being hurt is a sentence, not an alarm.
        Omerta.HUD.Text(state, "body", ScrW() * 0.5, ScrH() * 0.72,
            Omerta.HUD.Colour("text", 255 * alpha),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
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

-- Extra lines under the dot, from whoever knows something about the target.
--
-- These used to be separate HUD elements each guessing a pixel offset, and
-- two modules guessing blind about the same spot is exactly how the identity
-- label ended up drawn through the body hint. Now ONE element owns the region
-- and stacks whatever applies: the label, then every registered hint, each
-- advanced by the measured height of the line above it.
-- fn(target) returns a line of text, or nil to stay quiet.
local targetHints = {}

function Omerta.HUD.RegisterTargetHint(id, fn)
    targetHints[id] = fn
end

-- The dot is ALWAYS there now, not only when something is in reach.
--
-- D-017 removed the engine crosshair and replaced it with a mark that appeared
-- on a target, which was principled and awful to play: a centre that blinks in
-- and out gives the eye nothing to rest on, and a player cannot aim a
-- conversation, let alone a revolver, at a point that is not drawn. It is
-- still not a reticle — it dims to a faint mark with nothing under it and
-- comes up to full when something is, so the information D-017 wanted is
-- carried by BRIGHTNESS rather than by presence.
--
-- It goes only where a mouse cursor takes over: with a window open, the
-- pointer is the centre of attention and two of them is one too many.
local function cursorHasScreen()
    return vgui.CursorVisible() or gui.IsGameUIVisible() or gui.IsConsoleVisible()
end

Omerta.HUD.Register("interactable", {
    order = 40,
    fade = 0.15,
    visible = function()
        if cursorHasScreen() then return false end
        local ply = LocalPlayer()
        if not (IsValid(ply) and ply:Alive()) then return false end
        -- Nothing to aim while on the floor or watching the death screen.
        local C = Omerta.Injury and Omerta.Injury.Client
        if C and (C.death or C.leaving or Omerta.Injury.IsDown(C.state)) then
            return false
        end
        return true
    end,
    draw = function(alpha)
        local scale = Omerta.HUD.Scale()
        -- A CIRCLE, with its own ring of ink. Small on purpose: this marks
        -- where you are looking, and anything bigger starts reading as an
        -- aiming reticle — which is a promise about gunplay this game does
        -- not make.
        -- A REAL circle, drawn as a polygon.
        --
        -- The first version used draw.RoundedBox with the corner radius set to
        -- half the box, on the assumption that a fully rounded square is a
        -- circle. It is not: RoundedBox builds its corners from a corner
        -- TEXTURE, and at a handful of pixels across the texture cannot
        -- resolve the curve — so it rendered as a rounded square, which is
        -- exactly what was reported. A polygon has no such floor and is
        -- honest at any size.
        local radius = 1.2 * scale
        local cx, cy = ScrW() * 0.5, ScrH() * 0.5
        -- Faint with nothing in reach, full when there is.
        local presence = interactableTarget() and 1 or 0.45
        -- The ink ring first, a pixel proud all round, so the dot survives
        -- being held against bone-coloured wall as well as against grass.
        Omerta.HUD.Disc(cx, cy, radius + 1, Color(0, 0, 0, 230 * alpha * presence))
        Omerta.HUD.Disc(cx, cy, radius,
            Omerta.HUD.Colour("text", 235 * alpha * presence))

        -- The ladder: one centred column under the dot. The SUBJECT anchor is
        -- fixed so its baseline never moves; everything below advances by the
        -- MEASURED height of the line above plus a grid step — fixed pixel
        -- offsets were the overlap bug at 1.5x, where the type outgrew them.
        local target = interactableTarget()
        local x = ScrW() * 0.5
        local y = cy + 22 * scale

        local function line(text, role, colour)
            Omerta.HUD.Text(text, role, x, y, colour, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            surface.SetFont(Omerta.HUD.Font(role))
            local _, tall = surface.GetTextSize(text)
            y = y + tall + Omerta.HUD.Space(1)
        end

        local title, subtitle = Omerta.HUD.LabelFor(target)
        if title then
            line(title, "subject", Omerta.HUD.Colour("text", 235 * alpha))
        end
        if subtitle then
            line(subtitle, "small", Omerta.HUD.Colour("secondary", 220 * alpha))
        end

        -- Deterministic order, so two hints never trade places frame to frame.
        local ids = {}
        for id in pairs(targetHints) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local ok, text = pcall(targetHints[id], target)
            if ok and type(text) == "string" and text ~= "" then
                line(text, "small", Omerta.HUD.Colour("secondary", 220 * alpha))
            end
        end
    end,
})
