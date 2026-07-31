-- THE DESIGN STANDARD — direction 1a "Carbon" from the project's style guide
-- (docs/design/style-guide/, exported from Claude Design 2026-07-31).
--
-- Ink plates, hairline rules, condensed sign-painter caps: "the UI behaves
-- like a thing printed on the world, not a thing floating above it." Every
-- colour, size and gap in the interface comes from this file and nowhere
-- else; a screen that hand-picks a grey is the drift Track E's
-- standardization pass exists to catch.
--
-- The guide's load-bearing rules, verbatim where possible:
--
--   * SIX HEX. Ink, rule, bone, secondary, brass, and the irreversible red.
--     Bone-warm white instead of #FFF so the UI reads as ink and paper, not
--     glass. Brass marks the ONE thing under the cursor; #8E2B22 is reserved
--     for what cannot be undone. Nothing else is ever coloured.
--   * THREE VOICES. Oswald (300/400) for titles, labels and verbs — all caps.
--     Archivo (400/500) for names, body and quantities. IBM Plex Mono for the
--     SYSTEM voice: small caps annotations like "TAB TO CLOSE".
--   * 4PX GRID. Only 4·8·12·16·24·32·48 exist. Corner radius 0, everywhere,
--     no exceptions. Every rule and border is 1px — never 2, never doubled.
--     Screen-edge margin is 24px.
--   * LEGIBILITY BY LAYER. World text gets a 1px hard black outline (four
--     offsets, no blur — a soft shadow disappears against mid-grey, a hard
--     outline is a shape and cannot). Clusters of more than three lines sit
--     on an ink scrim at 62% with one 1px rule on the side facing the screen
--     edge. Focus windows go to 94%.
--   * SELECTION IS INVERSION. The selected row fills with brass and its text
--     turns ink — the only inversion in the game. Commit buttons fill with
--     bone. Nothing glows.
--   * MOTION IS FADE. 120ms in, 220ms out, no slide, no scale.
--   * AT 1.5x the 4px unit scales; the 1px rule and the 1px outline do not —
--     a 1.5px hairline is a grey smear.
--
-- Colours are raw {r,g,b} tables rather than Color objects because this is a
-- shared file: the headless suite loads it without the engine's Color, and
-- every draw call applies its own alpha anyway.

Omerta.HUD = Omerta.HUD or {}
Omerta.HUD.Theme = Omerta.HUD.Theme or {}
local T = Omerta.HUD.Theme

T.NAME = "Omertà Carbon (style guide 1a)"

--------------------------------------------------------------------------------
-- Colour — six hex, plus the derived tones the guide itself uses
--------------------------------------------------------------------------------

T.COLOUR = {
    -- The six.
    plate     = { 10, 10, 11 },     -- #0A0A0B ink — plates, scrims, text-on-brass
    rule      = { 58, 54, 47 },     -- #3A362F every 1px rule and border
    text      = { 238, 234, 225 },  -- #EEEAE1 bone — text and icon tint
    secondary = { 154, 148, 138 },  -- #9A948A secondary text
    brass     = { 200, 169, 106 },  -- #C8A96A the one thing under the cursor
    danger    = { 142, 43, 34 },    -- #8E2B22 what cannot be undone

    -- Derived tones the guide's own mocks rely on.
    dim       = { 111, 105, 95 },   -- #6f695f the mono system voice
    ruleFaint = { 35, 34, 30 },     -- #23221e internal hairlines inside plates
    ink       = { 10, 10, 11 },     -- alias: text on brass or bone fills
}

-- Surface opacities, by layer (0..1). The guide names all three.
T.ALPHA = {
    scrim = 0.62,   -- cluster layer: verb menu, hotbar, timed action, notices
    focus = 0.94,   -- focus windows: inventory, treasury, creation
    menu  = 0.97,   -- context menus, floating above a focus window
    wash  = 0.14,   -- brass hover wash on rows
}

--------------------------------------------------------------------------------
-- Space — the 4px grid
--------------------------------------------------------------------------------
-- Only these exist. Step(5) = 24 is the screen-edge margin.

T.SPACING = { 4, 8, 12, 16, 24, 32, 48 }

--------------------------------------------------------------------------------
-- Type — three faces, sizes straight from the guide (real 1080p values)
--------------------------------------------------------------------------------

-- Family names as the TTFs declare them (content/resource/fonts). A name that
-- does not match what is inside the file silently falls back to the engine
-- default, which is how a font ships broken and nobody notices for a week.
--
-- The guide's Oswald/Archivo pairing was tried in-engine and rejected by the
-- project lead (2026-07-31): Germania One is the game's face and it returned,
-- carrying every role the guide gave the other two. The mono system voice
-- stays IBM Plex Mono — tiny caps annotations want a mono, and Germania has
-- no such register.
T.FACE = {
    display      = "Germania One",
    displayLight = "Germania One",
    text         = "Germania One",
    textMedium   = "Germania One",
    mono         = "IBM Plex Mono",
    monoMedium   = "IBM Plex Mono Medium",
}

-- The guide's px values are authored for a browser at reading distance; on a
-- live screen at a couch's distance they field-tested as "way too small"
-- (project lead, twice). The RATIOS are the guide's; the absolute sizes are
-- the guide's times this. The 1px rules and outlines are untouched by it.
T.READABILITY = 1.3

-- role -> { px, face }. Display roles are drawn ALL CAPS at the call site
-- (the engine cannot track letters, so the guide's tracking is approximated).
T.TYPE = {
    mono     = { size = 13, face = "monoMedium" },   -- the system voice, caps
    small    = { size = 14, face = "text" },         -- hint line
    label    = { size = 15, face = "text" },         -- rows, verbs in menus
    body     = { size = 15, face = "text" },         -- prose
    subject  = { size = 20, face = "text" },         -- what you are looking at
    prose    = { size = 22, face = "text" },         -- full-screen sentences
    heading  = { size = 26, face = "display" },      -- window titles, caps
    verb     = { size = 16, face = "display" },      -- timed-action headers, caps
    count    = { size = 30, face = "textMedium" },   -- the ammunition number
    headline = { size = 46, face = "displayLight" }, -- death title, caps
    title    = { size = 62, face = "displayLight" }, -- the wordmark; the dead's name
}

--------------------------------------------------------------------------------
-- Pure helpers (headless-tested)
--------------------------------------------------------------------------------

-- A spacing step in pixels, before the accessibility scale. Steps outside the
-- scale clamp rather than erroring: a layout should never vanish because
-- somebody asked for spacing-9.
function T.Step(step)
    local scale = T.SPACING
    local index = math.max(1, math.min(#scale, math.floor(tonumber(step) or 1)))
    return scale[index]
end

-- The pixel size of a type role, before the accessibility scale.
function T.TypeSize(role)
    local def = T.TYPE[role] or T.TYPE.body
    return def.size * T.READABILITY
end
