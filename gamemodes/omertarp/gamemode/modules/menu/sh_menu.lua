-- The front end: the intro, and the menu it hands over to.
--
-- This is the first sixty seconds of the game, which the roadmap calls out as
-- one of the two things first impressions are made of. It is also a PLACEHOLDER
-- SET, deliberately: M27 and M28 own the finished versions, and both have open
-- rulings (below). What ships here is the system — a timeline, a camera, a menu
-- whose entries are registered rather than listed — so those milestones fill in
-- data rather than building machinery.
--
-- Open rulings this implementation assumes an answer to, so they can be argued
-- with rather than discovered later:
--
--   * M28 asks whether clients receive the 30.9 MB intro WAV or a ~4 MB MP3.
--     ASSUMED: not yet either. `menu.send_music` defaults to OFF, so the track
--     plays for anyone who has the file and nobody pays 30 MB for their first
--     impression until it is compressed.
--   * M28 asks whether the sequence is scene-driven or music-driven. ASSUMED:
--     scene-driven — the timeline below is the authority and the music rides
--     under it, because a cinematic cut to a fixed track cannot be skipped
--     gracefully, and skipping is a requirement.
--   * M27 describes three camera modes selected by configuration. ASSUMED: one
--     mode (a slow orbit) plus the registration seam for the others, since the
--     shots are per-map authoring work that lands with the map (Q-9).
--
-- Everything here is pure so the timeline can be pinned headlessly, exactly as
-- M19's death sequence is.

Omerta.Menu = Omerta.Menu or {}
Omerta.Menu.Internal = Omerta.Menu.Internal or {}

--------------------------------------------------------------------------------
-- The words
--------------------------------------------------------------------------------
-- Constants rather than data, for now. M27's Omerta.Data (D-036) is where a
-- server operator will eventually author these; two edits is the cost of
-- changing them until then.

Omerta.Menu.TITLE = "OMERTÀ"
Omerta.Menu.SUBTITLE = "There are no witnesses."
Omerta.Menu.SKIP_PROMPT = "any key to skip"

--------------------------------------------------------------------------------
-- The intro timeline
--------------------------------------------------------------------------------
-- Black, then the words, then the world. The world arrives LAST and alone: a
-- title card cross-fading into a camera move reads as a slideshow, where a
-- clean hand-off reads as a film starting.

Omerta.Menu.INTRO = {
    BLACK     = 1.0,  -- nothing at all, so the music has the first moment
    TITLE_IN  = 2.2,  -- the words arriving
    TITLE_HOLD= 3.0,  -- and sitting there
    TITLE_OUT = 1.6,  -- and going
    REVEAL    = 1.8,  -- the black lifting off the city
    MUSIC_IN  = 3.0,  -- the track easing up under all of it
}

local I = Omerta.Menu.INTRO

-- Derived, so the phases cannot drift out of step with each other.
I.TITLE_AT   = I.BLACK
I.TITLE_FULL = I.TITLE_AT + I.TITLE_IN
I.TITLE_END  = I.TITLE_FULL + I.TITLE_HOLD
I.TITLE_GONE = I.TITLE_END + I.TITLE_OUT
I.DONE       = I.TITLE_GONE + I.REVEAL

-- How present the words are, 0..1.
function Omerta.Menu.IntroTitleAlpha(elapsed)
    elapsed = elapsed or 0
    if elapsed <= I.TITLE_AT then return 0 end
    if elapsed < I.TITLE_FULL then
        return math.Clamp((elapsed - I.TITLE_AT) / I.TITLE_IN, 0, 1)
    end
    if elapsed < I.TITLE_END then return 1 end
    return 1 - math.Clamp((elapsed - I.TITLE_END) / I.TITLE_OUT, 0, 1)
end

-- How black the screen is over the world, 0..1. Solid until the words have
-- gone, then lifts.
function Omerta.Menu.IntroWorldFade(elapsed)
    elapsed = elapsed or 0
    if elapsed < I.TITLE_GONE then return 1 end
    return 1 - math.Clamp((elapsed - I.TITLE_GONE) / I.REVEAL, 0, 1)
end

-- The track easing in from nothing.
function Omerta.Menu.IntroMusic(elapsed)
    return math.Clamp((elapsed or 0) / I.MUSIC_IN, 0, 1)
end

function Omerta.Menu.IntroDone(elapsed)
    return (elapsed or 0) >= I.DONE
end

-- A skip is only offered once the words are fully up: a player still holding a
-- key from the loading screen should not lose the opening by accident, which
-- is the same rule the death screen's acknowledgement follows.
function Omerta.Menu.MaySkip(elapsed)
    return (elapsed or 0) >= I.TITLE_FULL
end

--------------------------------------------------------------------------------
-- The camera
--------------------------------------------------------------------------------
-- A slow orbit around a point somebody chose. Pure numbers rather than vectors,
-- so the movement is testable without the engine's maths types.

Omerta.Menu.ORBIT = {
    RADIUS = 340,
    HEIGHT = 210,
    SPEED  = 2.6,   -- degrees per second; slow enough to read as drift
    PITCH  = 16,
    FOV    = 62,
}

-- Returns dx, dy, yaw — an offset from the vantage point and the yaw that
-- looks back at it. Wrapped to 0..360 so a client left on the menu for an hour
-- is doing the same arithmetic as one that just joined.
function Omerta.Menu.OrbitPoint(elapsed, radius, speed)
    radius = radius or Omerta.Menu.ORBIT.RADIUS
    speed = speed or Omerta.Menu.ORBIT.SPEED
    local degrees = ((elapsed or 0) * speed) % 360
    local radians = math.rad(degrees)
    -- Looking inward: the camera stands on the circle and faces the middle.
    return math.cos(radians) * radius, math.sin(radians) * radius,
        (degrees + 180) % 360
end

--------------------------------------------------------------------------------
-- Menu entries
--------------------------------------------------------------------------------
-- Registered, not listed. M26's settings and M27's character selection are the
-- next two, and neither should need this file changed to appear.

local entries = {}
local ordered = nil

function Omerta.Menu.RegisterEntry(id, def)
    if type(id) ~= "string" or not id:find("^[a-z0-9_%.]+$") then
        error("menu entry id '" .. tostring(id) .. "' must be lowercase [a-z0-9_.]", 2)
    end
    if entries[id] then error("menu entry '" .. id .. "' registered twice", 2) end
    if type(def) ~= "table" then error("menu entry '" .. id .. "' needs a definition", 2) end
    if type(def.label) ~= "string" or def.label == "" then
        error("menu entry '" .. id .. "' needs a label", 2)
    end
    if type(def.onSelect) ~= "function" then
        error("menu entry '" .. id .. "' needs an onSelect", 2)
    end
    def.id = id
    def.order = def.order or 100
    entries[id] = def
    ordered = nil
    return def
end

function Omerta.Menu.GetEntry(id) return entries[id] end

-- Deterministic: by order, then id. A menu whose items move between sessions
-- is a menu nobody can use without reading it every time.
function Omerta.Menu.GetOrdered()
    if ordered then return ordered end
    ordered = {}
    for _, def in pairs(entries) do ordered[#ordered + 1] = def end
    table.sort(ordered, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    return ordered
end

-- What is actually offered right now. An entry may decline to appear.
function Omerta.Menu.Available()
    local out = {}
    for _, def in ipairs(Omerta.Menu.GetOrdered()) do
        local shown = true
        if def.visible then
            local ok, want = pcall(def.visible)
            shown = ok and want ~= false
        end
        if shown then out[#out + 1] = def end
    end
    return out
end

-- Moving the highlight. Wraps in both directions; an empty list stays at zero
-- rather than returning an index into nothing.
function Omerta.Menu.StepSelection(current, delta, count)
    count = math.floor(count or 0)
    if count <= 0 then return 0 end
    current = math.floor(current or 0)
    if current < 1 then return delta >= 0 and 1 or count end
    return ((current - 1 + delta) % count) + 1
end
