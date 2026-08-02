-- What the player sees of their own gun: a round count that appears when it
-- would be looked at, and is gone the rest of the time.
--
-- The engine's ammo HUD went in M8 with everything else permanent. This is its
-- contextual replacement: a character can count the rounds they have loaded —
-- that is knowledge the fiction grants — but a counter pinned to the screen is
-- exactly the omniscient furniture GDD §8 removed. So it fades in on the
-- moments that mean "I am thinking about my gun" (drawing it, firing it,
-- reloading it) and fades back out.
--
-- It also holds the one thing this module has to take AWAY from the engine: the
-- sandbox context menu, and with it the C key. See the section at the foot of
-- the file.

Omerta.Weapons = Omerta.Weapons or {}

local shownUntil = 0
local lastClass, lastClip = nil, -1

-- What is left in the coat. The clip is predicted and free to read, but rounds
-- in a pocket are M9 inventory rows the client is not continuously told about
-- — so the server sends this number when it changes, and the readout simply
-- shows the last thing it was told.
local reserve = 0

hook.Add("Omerta.WeaponReserve", "omerta.weapons.reserve", function(count)
    reserve = count or 0
end)

-- By CLASS, not by `wep.OmertaId`.
--
-- Our own generated classes carry the id on the class table, so both realms
-- see it — but a weapon running a third party's class carries it only on the
-- server entity, where giveOne stamps it, and a plain Lua field is not
-- networked. The arsenal is shared data and maps BOTH classes to the same
-- definition, so asking what class is in the hand is the reading that works
-- whichever half of the pair won.
local function activeOmertaWeapon()
    local ply = LocalPlayer()
    if not IsValid(ply) then return nil end
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return nil end
    if not Omerta.Weapons.ForClass(wep:GetClass()) then return nil end
    return wep
end

-- Change detection rather than events: the clip is already networked for
-- prediction, so watching it costs nothing and misses nothing.
hook.Add("Think", "omerta.weapons.readout", function()
    local wep = activeOmertaWeapon()
    if not wep then
        lastClass, lastClip = nil, -1
        return
    end
    local class, clip = wep:GetClass(), wep:Clip1()
    if class ~= lastClass or clip ~= lastClip then
        lastClass, lastClip = class, clip
        shownUntil = CurTime() + 2.5
    end
end)

-- The ammunition block, bottom right. It is present the whole time a gun is
-- in the hands rather than for a few seconds after touching it: a drawn
-- weapon is a decision the player is actively living with, and how many
-- rounds are in it is the single fact that decision turns on. It fades in as
-- the gun comes up and out as it goes away, so putting it away still returns
-- the screen to empty.
Omerta.HUD.Register("weapons.rounds", {
    order = 21,
    fade = 0.35,
    visible = function()
        return activeOmertaWeapon() ~= nil
    end,
    draw = function(alpha)
        local wep = activeOmertaWeapon()
        if not wep then return end
        -- `wep:Clip1()`, never `wep:Def()`. Def is a method on OUR base and a
        -- third party's SWEP does not have it; Clip1 is engine and every
        -- weapon does. Nothing here needed the definition anyway.
        local clip = wep:Clip1()
        local scale = Omerta.HUD.Scale()
        local margin = Omerta.HUD.Space(5)
        local x = ScrW() - margin
        local y = ScrH() - margin

        -- LOADED / reserve, and in that order — loaded on the LEFT.
        --
        -- The first version had them the wrong way round. Both are
        -- right-aligned against the screen margin, so drawing the loaded count
        -- there and hanging the reserve off its left edge put the big number
        -- last and read as "/ 0  6" — a magazine of nothing beside a number
        -- with no label. It is one phrase and it reads left to right: what is
        -- in the gun, then what is left for it.
        --
        -- The reserve keeps the right-hand anchor because it is the piece that
        -- changes width least often; growing the loaded count pushes leftward,
        -- away from the edge, instead of shoving the whole block about.
        local loaded = tostring(clip)
        local trailing = "/ " .. reserve
        surface.SetFont(Omerta.HUD.Font("label"))
        local trailingWide = surface.GetTextSize(trailing)

        Omerta.HUD.Text(trailing, "label", x, y - 2 * scale,
            Omerta.HUD.Colour("secondary", 150 * alpha),
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
        Omerta.HUD.Text(loaded, "count",
            x - trailingWide - 6 * scale, y,
            Omerta.HUD.Colour("text", 245 * alpha),
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)

        -- The line under it only speaks when it has something to say: an
        -- empty gun, or an empty gun with nothing to feed it.
        local note
        if clip <= 0 and reserve <= 0 then
            note = "NOTHING LEFT"
        elseif clip <= 0 then
            note = "EMPTY · PRESS R"
        end
        if note then
            Omerta.HUD.Text(note, "mono", x, y - 34 * scale,
                Omerta.HUD.Colour(reserve <= 0 and "danger" or "secondary", 235 * alpha),
                TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
        end
    end,
})

--------------------------------------------------------------------------------
-- The context menu, and the C key it takes
--------------------------------------------------------------------------------
-- C IS THE INVENTORY. GMod's default binding for it is `+menu_context`, which
-- opens the sandbox context menu, and a mounted weapon framework hangs its
-- customisation menu off that — so pressing C opened somebody else's attachment
-- window over the top of the pockets.
--
-- THE POSITION, STATED PLAINLY: THIS GAMEMODE HAS NO CONTEXT MENU. Not "not
-- yet", and not "not on that key". There is no spawn menu, no toolgun, no props
-- to configure, no entity whose properties a player may edit, and no permission
-- model under which any of that would be allowed — D-033 is a ban on omniscient
-- information and the sandbox context menu is a window onto the whole map's
-- entities. So this is not a workaround for a key clash that happens to be
-- convenient; suppressing it wholesale is the correct behaviour for this
-- gamemode and would be right even if no weapon framework were installed. The
-- clash is what made somebody notice, not what makes it right.
--
-- NOTHING HERE READS OR CALLS ARC9 (D-043/D-044's rule, and the reason three
-- unverified class strings never became a maintenance problem). Both hooks
-- below are base Garry's Mod and both are about OUR gamemode's own facilities:
-- one refuses to open a menu we do not have, the other refuses to run a command
-- we do not want run. Whether an addon is listening to either is not asked and
-- does not need to be.
--
-- BOTH HOOKS, AND WHY IN THAT ORDER.
--
-- ContextMenuOpen is the GATE and it is the real answer. It is asked at the
-- moment something tries to open the menu, by whatever is trying — the bind, a
-- console command typed by hand, an addon calling the open path itself — so it
-- cannot be raced. Hook execution order in GMod is undefined (the hook table is
-- iterated with pairs), and a gate that is CONSULTED does not care what order
-- anything registered in, because it is asked as part of the act rather than
-- alongside it. Anything that opens THROUGH the context menu is stopped here,
-- including anything hanging off OnContextMenuOpen, which never fires.
--
-- PlayerBindPress swallowing the bind is the belt to that brace, and it is
-- deliberately second because it is strictly weaker. It covers the case where a
-- framework never touches the context menu at all and simply listens for the
-- same bind — but if that listener happens to be iterated before ours it has
-- already acted by the time we return true, and no ordering we can express
-- fixes that. As a sole mechanism it would be a guess about somebody else's
-- code; as a second one it costs a string compare and closes the case where the
-- context menu is not involved.
--
-- Together they also close the case the gate alone leaves open: with no context
-- menu to open, `+menu_context` would otherwise still run and do whatever else
-- it does. Now the command does not run and the menu would refuse anyway.
--
-- THIS CANNOT BREAK THE INVENTORY, and the reason is worth being explicit about
-- because the two look like they are fighting over one key and are not.
-- cl_inventory.lua polls the PHYSICAL key with input.IsKeyDown(KEY_C); this
-- suppresses a COMMAND named +menu_context. They are different questions about
-- different things, and neither can answer the other's. Returning true from
-- PlayerBindPress stops a bind from running its command; it does not stop the
-- key from being down, and input.IsKeyDown does not consult the bind table at
-- all. A player who rebinds the context menu onto some other key still opens
-- their pockets with C, and still gets no context menu.
--
-- The spawn menu (Q, `+menu`) is deliberately NOT touched here. It is the same
-- argument and it is not the same report, and a second suppression added on
-- spec is a second thing to explain when somebody eventually wants a staff
-- tool. If it needs doing it is one more hook, in this section, with its own
-- sentence.
hook.Add("ContextMenuOpen", "omerta.weapons.no_context", function()
    return false
end)

hook.Add("PlayerBindPress", "omerta.weapons.no_context_bind", function(_, bind)
    -- Matched as a SUBSTRING rather than compared to "+menu_context". A bind
    -- arrives here with its sign attached and the release half of a +command is
    -- reported by some builds as `-menu_context`; matching the command's name
    -- catches both halves and cannot catch anything else, since no other bind
    -- in the engine contains that string. Everything unmatched returns nil and
    -- is left alone — this hook must never be the reason another bind stops
    -- working.
    if type(bind) == "string" and bind:find("menu_context", 1, true) then
        return true
    end
end)
