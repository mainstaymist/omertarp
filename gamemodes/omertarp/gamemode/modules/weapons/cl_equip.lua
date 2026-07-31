-- Drawing a weapon, as the man drawing it sees it — and as everybody watching
-- him sees it.
--
-- The draw is server truth (sv_weapons owns the clock, the cancels and the row
-- that eventually changes); this file only draws what it is told. Two surfaces
-- want the same fact — the inventory row the player clicked, and the HUD when
-- that window is closed — so this file owns ONE reading of it and hands the
-- same numbers to both.

Omerta.Weapons = Omerta.Weapons or {}

-- The whole client state of a draw: which item, and the window it runs in, in
-- this client's own clock. The server sends that window ONCE when the draw
-- begins and the client counts against it locally, exactly as M19's bleed-out
-- clock does — streaming a number both sides can compute would be traffic for
-- nothing, and it would step in visible jerks besides.
--
-- This one table is also the entire reason the handoff between the inventory
-- row and the HUD plate is seamless. They are two READINGS of it, not two
-- clocks: close the window mid-draw and the plate picks up the fraction the
-- row was showing, reopen it and the row picks up the fraction the plate was
-- showing, because neither of them owns anything of their own to lose.
local current = nil -- { instance = , startedAt = , finishAt = }

-- A completion message that never arrived must not pin a full bar to the
-- screen forever. The server remains the authority on whether anything was
-- actually equipped; this only decides when the client stops drawing a thing
-- that has plainly finished.
local ORPHAN_GRACE = 1.5

-- The verb, in the game's voice. Drawn in caps at the call site, as every
-- display role in the theme is.
local VERB = "Drawing"

--------------------------------------------------------------------------------
-- The seam the inventory window reads
--------------------------------------------------------------------------------

-- Returns instanceId, fraction (0..1) while a draw is running; nil when none
-- is. KEEP THIS NAME AND SHAPE — the inventory window is written against it.
function Omerta.Weapons.EquipProgress()
    if not current then return nil end

    local now = CurTime()
    if now > current.finishAt + ORPHAN_GRACE then
        current = nil
        return nil
    end
    return current.instance,
        Omerta.Weapons.EquipFraction(current.startedAt, current.finishAt, now)
end

--------------------------------------------------------------------------------
-- What is on screen
--------------------------------------------------------------------------------

-- The inventory window draws the same draw better than the HUD can — on the
-- row, where the player is already looking. A missing IsOpen is read as "not
-- open" on purpose: this file must work the day it lands, whether or not the
-- accessor it prefers has landed with it, and pcall covers the day somebody
-- gives the window an opinion that errors.
local function inventoryIsOpen()
    local isOpen = Omerta.Inventory and Omerta.Inventory.IsOpen
    if type(isOpen) ~= "function" then return false end
    local ok, open = pcall(isOpen)
    return ok and open == true
end

if Omerta.InEngine then
    hook.Add("Omerta.WeaponEquipping", "omerta.weapons.drawing", function(instance, millis)
        local now = CurTime()
        current = {
            instance = instance,
            startedAt = now,
            finishAt = now + (millis or 0) / 1000,
        }
    end)

    hook.Add("Omerta.WeaponEquipEnded", "omerta.weapons.drawing_end", function(instance)
        -- Ended is ended, whichever way: a cancel and a completion both mean
        -- there is nothing left to draw. Which one it was is on the wire for a
        -- future sound to read; nothing on screen needs to know today.
        if current and current.instance == instance then current = nil end
    end)

    -- A character change is not an interruption anybody is told about — the
    -- old one simply stops existing — so the client drops what it was showing
    -- rather than waiting for a message that will never come.
    hook.Add("Omerta.CharactersState", "omerta.weapons.drawing_reset", function()
        current = nil
    end)

    -- The guide's §08 timed-action plate, the same one M19 uses for searching
    -- a body: a 320px scrim above the bottom edge, the verb in display caps,
    -- and a bare 2px progress line — no ticks, no number, no seconds
    -- remaining. Deliberately identical, position included: "something is
    -- happening and it takes this long" should look like one thing in this
    -- game, not like one thing per module that invented it.
    --
    -- Order 46 puts it beside injury's prompt at 45. They can only collide in
    -- one corner: mid-search of a body, having closed the inventory window
    -- after starting a draw. Sharing the region properly needs a plate stack
    -- the hud module does not have and this file has no business inventing.
    Omerta.HUD.Register("weapons.equip", {
        order = 46,
        fade = 0.2,
        visible = function()
            if inventoryIsOpen() then return false end
            return Omerta.Weapons.EquipProgress() ~= nil
        end,
        draw = function(alpha)
            local instance, fraction = Omerta.Weapons.EquipProgress()
            if not instance then return end

            local scale = Omerta.HUD.Scale()
            local width = 320 * scale
            local pad = 16 * scale
            local tall = 62 * scale
            local x = ScrW() * 0.5 - width * 0.5
            local y = ScrH() - 120 * scale - tall

            Omerta.HUD.Scrim(x, y, width, tall, "top", alpha)

            draw.SimpleText(string.upper(VERB), Omerta.HUD.Font("verb"),
                x + pad, y + 14 * scale,
                Omerta.HUD.Colour("text", 255 * alpha),
                TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            local by = y + tall - 16 * scale
            surface.SetDrawColor(Omerta.HUD.Colour("text", 0.18 * 255 * alpha))
            surface.DrawRect(x + pad, by, width - pad * 2, 2)
            surface.SetDrawColor(Omerta.HUD.Colour("text", 255 * alpha))
            surface.DrawRect(x + pad, by, (width - pad * 2) * fraction, 2)
        end,
    })

    -- What the street sees. A man reaching into his coat is visible from
    -- across it, so this is public by nature rather than by leak: the
    -- networked boolean says somebody is reaching and never what for, and the
    -- line says the same. Nobody watching learns which gun, whose it is, or
    -- how long is left — only that a decision is being made in front of them.
    --
    -- A target HINT rather than an element of its own, for the reason M19's
    -- body hint is one: the hud module stacks it under the identity label with
    -- measured spacing, which is what ended two modules guessing offsets and
    -- drawing through each other.
    Omerta.HUD.RegisterTargetHint("weapons.drawing", function(target)
        if not (IsValid(target) and target:IsPlayer()) then return nil end
        if target == LocalPlayer() then return nil end
        if not target:GetNWBool("OmertaDrawing", false) then return nil end
        return "Reaching for something…"
    end)
end
