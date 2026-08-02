-- The lens, drawn.
--
-- Why an always-on vignette is allowed to exist at all, and why it is not a HUD
-- element, is argued in sh_hud.lua beside the numbers. This file is only the
-- four rectangles and the one piece of state they need.
--
-- WHY HUDPaintBackground. It is the earliest of the HUD hooks, so this lands
-- under every element the controller draws and under every VGUI panel. That is
-- not an implementation convenience, it is the claim being made: a lens darkens
-- the PICTURE, and the interface — which the style guide describes as "a thing
-- printed on the world" — sits on the picture and stays exactly as legible as it
-- was. A vignette drawn on top of the HUD would be dimming the text, which is a
-- different thing entirely and a worse one.
--
-- It is also why nothing here consults Omerta.HUD.Suppressed(). Suppressors
-- exist to stop ELEMENTS drawing when something owns the screen; the one that
-- exists is the front-end menu, which covers the whole display with an opaque
-- panel that this is already behind.

Omerta.HUD = Omerta.HUD or {}

-- The player's own call, and archived. Some people are genuinely bothered by
-- edge darkening and nobody should have to edit a gamemode to turn off a mood.
CreateClientConVar("omerta_vignette", "1", true, false)

-- Read once and on change rather than per frame. Same reason the black-and-white
-- flag is cached in cl_hud: this is in the draw path, and a convar lookup there
-- is a real cost for a value that changes when somebody clicks a button.
local wanted = true

local function readWanted()
    wanted = GetConVar("omerta_vignette"):GetBool()
end
readWanted()
cvars.AddChangeCallback("omerta_vignette", readWanted, "omerta.hud.vignette")

-- Whether the edges currently belong to somebody else.
--
-- M19's bleed-out vignette grows in from these same four edges in deep red, and
-- two vignettes stacked on the same pixels is one too many. The ambient one
-- would darken the red it is supposed to be letting through, and "the world
-- closing in" would be starting from an edge that was already half closed —
-- which costs that element the only thing it has to say. So the lens gets out of
-- the way while somebody is bleeding out, and comes back when the bleeding
-- stops.
--
-- The death screen is in here for the same reason and a simpler one: it owns the
-- whole display and there is nothing underneath it worth spending a draw on.
--
-- Soft-referenced throughout. The hud module loads BEFORE injury, so this must
-- read the table at call time and cope with it not existing at all — a client
-- with no injury module gets a vignette that never yields, which is correct.
local function yielding()
    local C = Omerta.Injury and Omerta.Injury.Client
    if not C then return false end
    if C.death or C.leaving then return true end
    return type(C.IsDying) == "function" and C.IsDying() == true
end

-- Four edge gradients rather than one radial texture, exactly as M19's does and
-- for exactly its reasons: it needs no asset, so it cannot fail to load, and the
-- soft edges ARE the effect. The nested-rectangles version of that element was
-- tried in the field and rejected for reading as a picture mount around the
-- screen; a hard-edged frame would be a worse idea here, where the whole point
-- is that nobody notices a frame.
local GRADIENT_LEFT = Material("gui/gradient")
local GRADIENT_UP   = Material("gui/gradient_up")
local GRADIENT_DOWN = Material("gui/gradient_down")

-- 0..1, stepped by the shared fade so this crossfades with M19's element rather
-- than cutting to it. Held here rather than recomputed because a fade needs to
-- know where it had got to; it is the only state this file has.
local presence = 0

hook.Add("HUDPaintBackground", "omerta.hud.vignette", function()
    presence = Omerta.HUD.StepAlpha(presence, wanted and not yielding(),
        FrameTime(), Omerta.HUD.VIGNETTE.FADE)
    if presence <= 0 then return end

    local w, h = ScrW(), ScrH()
    local thickX, thickY, alpha = Omerta.HUD.VignetteBands(w, h, presence)
    -- Two reasons, and the second one matters much more than the first.
    --
    -- Below a whole unit of alpha there is nothing on screen to show for four
    -- textured rectangles. And Omerta.HUD.Colour accepts its alpha as EITHER
    -- 0..1 or 0..255 and tells them apart with `alpha <= 1` — so handing it a 1
    -- would be read as "fully opaque" and paint the edges solid black for a
    -- frame, at the exact moment the vignette is meant to be at its faintest.
    -- The comparison is therefore `<=`, not `<`: the ambiguous value is the one
    -- being excluded, not merely the invisible one.
    if alpha <= 1 then return end

    -- The palette's ink, through Colour, so this desaturates with everything
    -- else under Black and white and can never become a hand-picked grey. It is
    -- already the game's black, so the setting barely moves it — which is the
    -- correct amount for it to move.
    surface.SetDrawColor(Omerta.HUD.Colour("plate", alpha))

    surface.SetMaterial(GRADIENT_DOWN)
    surface.DrawTexturedRect(0, 0, w, thickY)
    surface.SetMaterial(GRADIENT_UP)
    surface.DrawTexturedRect(0, h - thickY, w, thickY)

    surface.SetMaterial(GRADIENT_LEFT)
    surface.DrawTexturedRect(0, 0, thickX, h)
    -- Mirrored U, so the same material serves the right-hand edge.
    surface.DrawTexturedRectUV(w - thickX, 0, thickX, h, 1, 0, 0, 1)
end)

-- How much lens is actually on screen right now, 0..1. Read by the self-test,
-- which needs to tell "off by setting" apart from "on, and currently handed over
-- to the bleed-out vignette" — those look identical from outside and only one of
-- them is a fault. There is deliberately no setter: a vignette has nothing to
-- set, and anything that wanted one would be using it to say something, which is
-- the line this effect is not allowed to cross.
function Omerta.HUD.VignettePresence()
    return presence
end
