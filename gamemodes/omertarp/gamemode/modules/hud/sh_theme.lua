-- THE DESIGN STANDARD: IBM's Carbon, adapted for a game screen.
--
-- Every colour, type size and gap in the interface comes from this file and
-- nowhere else. That is the whole point of it: the roadmap's UI standardization
-- pass (Track E) is a day's work if there is one table to change and a month if
-- forty files each picked their own greys — which is exactly what was starting
-- to happen.
--
-- WHY CARBON. It is a real, documented, open design system with published
-- tokens, an open-licence typeface, and a dark theme designed for exactly this
-- kind of dense, administrative information. It also happens to suit the game:
-- Carbon has NO ROUNDED CORNERS, a strict grid and a cold, high-contrast
-- palette, which reads as ledgers, case files and municipal paperwork rather
-- than as a phone app.
--
-- WHAT IS ADAPTED, AND WHY. Two deliberate departures, both flagged so they
-- can be argued with:
--
--   1. TYPE IS SCALED UP by GAME_SCALE below. Carbon's scale is authored for a
--      browser window an arm's length away, where 14px is comfortable. A game
--      HUD is read at a glance, across a room, over a moving 3D world. The
--      RATIOS are Carbon's; the absolute sizes are not.
--   2. THE BRAND FACE IS NOT IBM PLEX. Carbon reserves an expressive layer for
--      a product's own identity, and this game's identity is Germania One —
--      used ONLY for the wordmark and the death title. Everything else, every
--      panel and every label, is IBM Plex Sans.
--
-- Colours are raw {r,g,b} tables rather than Color objects because this is a
-- shared file: the headless suite loads it without the engine's Color, and
-- every draw call needs to apply its own alpha anyway.

Omerta.HUD = Omerta.HUD or {}
Omerta.HUD.Theme = Omerta.HUD.Theme or {}
local T = Omerta.HUD.Theme

T.NAME = "IBM Carbon (Gray 100), adapted"

--------------------------------------------------------------------------------
-- Colour tokens — Carbon Gray 100 (the dark theme)
--------------------------------------------------------------------------------
-- Named by ROLE, not by value: code says "border subtle", never "#393939", so
-- a re-theme never has to guess which greys meant which thing.

T.COLOUR = {
    -- Surfaces, in Carbon's layering order. Each layer sits on the one above.
    background      = { 22, 22, 22 },    -- #161616
    layer01         = { 38, 38, 38 },    -- #262626
    layer02         = { 57, 57, 57 },    -- #393939
    layer03         = { 82, 82, 82 },    -- #525252
    layerHover      = { 51, 51, 51 },    -- #333333
    layerSelected   = { 57, 57, 57 },    -- #393939
    field           = { 38, 38, 38 },    -- #262626

    -- Lines.
    borderSubtle    = { 57, 57, 57 },    -- #393939
    borderStrong    = { 111, 111, 111 }, -- #6f6f6f
    borderInteractive = { 69, 137, 255 },-- #4589ff

    -- Text.
    textPrimary     = { 244, 244, 244 }, -- #f4f4f4
    textSecondary   = { 198, 198, 198 }, -- #c6c6c6
    textHelper      = { 141, 141, 141 }, -- #8d8d8d
    textPlaceholder = { 111, 111, 111 }, -- #6f6f6f
    textDisabled    = { 109, 109, 109 },
    textOnColour    = { 255, 255, 255 },

    -- Action.
    interactive     = { 69, 137, 255 },  -- #4589ff
    linkPrimary     = { 120, 169, 255 }, -- #78a9ff
    buttonPrimary   = { 15, 98, 254 },   -- #0f62fe
    buttonPrimaryHover = { 3, 83, 233 }, -- #0353e9
    buttonDanger    = { 218, 30, 40 },   -- #da1e28
    buttonDangerHover = { 186, 27, 35 }, -- #ba1b23
    focus           = { 255, 255, 255 }, -- #ffffff

    -- Status.
    supportError    = { 250, 77, 86 },   -- #fa4d56
    supportSuccess  = { 66, 190, 101 },  -- #42be65
    supportWarning  = { 241, 194, 27 },  -- #f1c21b
    supportInfo     = { 69, 137, 255 },  -- #4589ff

    -- Pure black, for the full-screen moments that are not a panel.
    overlay         = { 0, 0, 0 },
}

--------------------------------------------------------------------------------
-- Spacing — Carbon's scale
--------------------------------------------------------------------------------
-- spacing-01 through spacing-13, in Carbon's own steps. Use the STEP, never a
-- number: `Space(5)` rather than `16 * scale`.

T.SPACING = { 2, 4, 8, 12, 16, 24, 32, 40, 48, 64, 80, 96, 160 }

--------------------------------------------------------------------------------
-- Type — Carbon's scale, at game distance
--------------------------------------------------------------------------------

-- See the header. Carbon's ratios, our absolute sizes.
T.GAME_SCALE = 1.7

-- Face names as the font FILES declare them (content/resource/fonts). A name
-- that does not match what is inside the TTF silently falls back to the engine
-- default, which is how a font ships broken and nobody notices for a week.
T.FACE = {
    sans     = "IBM Plex Sans",
    sansBold = "IBM Plex Sans SemiBold",
    brand    = "Germania One",
}

-- role -> { carbon token, px at Carbon's own scale, face, weight }
-- The four original roles keep their names, because every existing draw call
-- names them; `heading` and `title` are new.
T.TYPE = {
    small    = { token = "label-01",         size = 12, face = "sans",     weight = 400 },
    label    = { token = "body-compact-01",  size = 14, face = "sans",     weight = 400 },
    body     = { token = "body-02",          size = 16, face = "sans",     weight = 400 },
    heading  = { token = "heading-03",       size = 20, face = "sansBold", weight = 600 },
    headline = { token = "heading-04",       size = 28, face = "sansBold", weight = 600 },
    -- The expressive layer: the wordmark and the death title, and nothing else.
    title    = { token = "display-03",       size = 54, face = "brand",    weight = 400 },
}

--------------------------------------------------------------------------------
-- Pure helpers (headless-testable)
--------------------------------------------------------------------------------

-- A spacing step in pixels, before the accessibility scale. Steps outside the
-- scale clamp rather than erroring: a layout should never vanish because
-- somebody asked for spacing-14.
function T.Step(step)
    local scale = T.SPACING
    local index = math.max(1, math.min(#scale, math.floor(tonumber(step) or 1)))
    return scale[index] * T.GAME_SCALE
end

-- The pixel size of a type role, before the accessibility scale.
function T.TypeSize(role)
    local def = T.TYPE[role] or T.TYPE.body
    return def.size * T.GAME_SCALE
end
