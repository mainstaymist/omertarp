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
--
-- WHAT THE FIELD SAID, 2026-08-02: THE MENU STILL OPENS. Both gates above were
-- installed and the customisation window still comes up on C, over the
-- inventory. That is not a tuning problem, it is a proof: something that
-- survives ContextMenuOpen answering false and survives the bind never running
-- is not going through the context menu and is not going through the bind. It
-- is on PlayerButtonDown, which is a NOTIFICATION — the engine tells every
-- listener a key went down and reads nothing back, so there is no value we can
-- return that stops it. The third hook this section could have grown would have
-- been the third thing that does not work.
--
-- So the gates stay (they are correct for this gamemode on their own terms, and
-- they are what stops the context menu being opened by any OTHER route), and
-- the listener is removed by name instead. The sweep is below; why removing a
-- hook by name is allowed where CALLING somebody's function is not is argued in
-- full at "Somebody else's HOOK" in sh_weapons.lua, and the short version is
-- that a name that matches nothing removes nothing and leaves today's behaviour
-- — which is a state we are already in.

-- Both gates and the sweep answer to ONE setting, so "turn it off" means all of
-- it rather than two thirds of it. Client-side because every hook here is
-- client-side: the menu is a panel, and the key that opens it is pressed on the
-- machine the panel would appear on.
CreateClientConVar("omerta_context_suppress", "1", true, false)

-- And WHOSE hooks. A setting rather than a constant because the identifier is
-- the one thing here nobody has read: if the pack spells itself differently, or
-- a second framework arrives, this is a console line rather than a patch. The
-- default is the pack the arsenal names.
--
-- An empty value sweeps NOTHING (PlanHookRemoval refuses it), which is the
-- safe way to switch the sweep off while leaving the gates on.
CreateClientConVar("omerta_context_match", "arc9", true, false)

local function suppressionOn()
    local cvar = GetConVar("omerta_context_suppress")
    return cvar == nil or cvar:GetInt() ~= 0
end

-- What was taken out, kept so it can be put back. The FUNCTION is stored beside
-- the name because that is the only way a removal is reversible — and storing a
-- function is not calling one. Nothing in this file ever calls what it holds;
-- the only thing done with it is handing it to hook.Add again.
local removedHooks = {}
local announced = {}

local function sweepForeignHooks()
    if not suppressionOn() then return end
    local matchCvar = GetConVar("omerta_context_match")
    local plan = Omerta.Weapons.PlanHookRemoval(hook.GetTable(),
        Omerta.Weapons.HOOK_SWEEP_EVENTS,
        matchCvar and matchCvar:GetString() or "")

    for _, entry in ipairs(plan) do
        hook.Remove(entry.event, entry.id)
        removedHooks[#removedHooks + 1] = entry

        -- INFO, not silence, and not a warning either: this is a deliberate act
        -- on somebody else's code and the operator is entitled to see it happen
        -- rather than wonder why an addon's key stopped working. Once per
        -- identifier — a framework that re-registers on every spawn would
        -- otherwise print the same line all night.
        local key = entry.event .. "|" .. entry.id
        if not announced[key] then
            announced[key] = true
            Omerta.Log.Info("weapons", "removed hook '%s' from %s — it is not " ..
                "ours and this gamemode has no context menu (omerta_context_suppress 0 " ..
                "puts it back)", entry.id, entry.event)
        end
    end
end

local function restoreForeignHooks()
    if #removedHooks == 0 then return end
    for _, entry in ipairs(removedHooks) do
        hook.Add(entry.event, entry.id, entry.fn)
        Omerta.Log.Info("weapons", "restored hook '%s' on %s", entry.id, entry.event)
    end
    removedHooks = {}
    announced = {}
end

-- Swept repeatedly, and that is not belt and braces. An addon is free to
-- register its hooks whenever it likes — at file scope, on InitPostEntity, on
-- the first spawn, or on a Lua refresh — and a one-shot sweep at load would win
-- or lose depending on include order, which is exactly the class of bug this
-- module keeps being bitten by. A walk of five events costs a handful of table
-- lookups, so it simply runs again.
hook.Add("InitPostEntity", "omerta.weapons.hook_sweep", sweepForeignHooks)
timer.Create("omerta.weapons.hook_sweep", 5, 0, sweepForeignHooks)
sweepForeignHooks()

cvars.AddChangeCallback("omerta_context_suppress", function(_, _, new)
    if tonumber(new) == 0 then restoreForeignHooks() else sweepForeignHooks() end
end, "omerta.weapons.context")

-- Changing WHO is swept has to put the old set back first, or a corrected
-- pattern would leave the previous pattern's casualties removed with no record
-- of which setting took them.
cvars.AddChangeCallback("omerta_context_match", function()
    restoreForeignHooks()
    sweepForeignHooks()
end, "omerta.weapons.context_match")

--------------------------------------------------------------------------------
-- omerta_hook_dump: what is actually listening
--------------------------------------------------------------------------------
-- Two gates were installed against the C menu on reasoning alone and neither
-- worked. This is the command that would have said so in one line, so it ships
-- before the fix rather than after it: every listener on the events a keypress
-- can travel through, by identifier, with the ones the sweep would take marked.
--
-- It reports Think and HUDPaint as well, which the sweep never touches, because
-- "nothing is listening on any input event" is a real answer and it means the
-- addon is polling the keyboard from a per-frame hook instead. A dump that only
-- showed what we were prepared to remove would have quietly agreed with
-- whatever we already believed.
concommand.Add("omerta_hook_dump", function(caller, _, args)
    if IsValid(caller) and not caller:IsSuperAdmin() then return end

    local matchCvar = GetConVar("omerta_context_match")
    local match = matchCvar and matchCvar:GetString() or ""
    local filter = args[1] and args[1] ~= "" and args[1] or nil

    -- What the sweep WOULD take, right now, computed by the same function the
    -- sweep uses so the two can never disagree about what is marked.
    local sweeping = {}
    for _, entry in ipairs(Omerta.Weapons.PlanHookRemoval(hook.GetTable(),
        Omerta.Weapons.HOOK_SWEEP_EVENTS, match)) do
        sweeping[entry.event .. "|" .. entry.id] = true
    end

    local hooks = hook.GetTable()
    for _, event in ipairs(Omerta.Weapons.HOOK_DUMP_EVENTS) do
        if not filter or event:lower() == filter:lower() then
            local listeners = hooks[event]
            local names = {}
            for id in pairs(type(listeners) == "table" and listeners or {}) do
                -- An identifier may be a panel or an entity rather than a
                -- string. Printed as what it is, because "there is a listener
                -- here that cannot be matched by name" is the single most
                -- useful thing this command can say about one.
                names[#names + 1] = type(id) == "string" and id
                    or ("<" .. type(id) .. " " .. tostring(id) .. ">")
            end
            table.sort(names)

            Omerta.Log.Info("weapons", "%s: %d listener(s)", event, #names)
            for _, name in ipairs(names) do
                Omerta.Log.Info("weapons", "    %-44s%s", name,
                    sweeping[event .. "|" .. name] and "  [SWEPT]" or "")
            end
        end
    end

    Omerta.Log.Info("weapons", "matching '%s'; suppression is %s. %d hook(s) " ..
        "removed this session.", match, suppressionOn() and "ON" or "OFF",
        #removedHooks)
end)

hook.Add("ContextMenuOpen", "omerta.weapons.no_context", function()
    if not suppressionOn() then return end
    return false
end)

hook.Add("PlayerBindPress", "omerta.weapons.no_context_bind", function(_, bind)
    if not suppressionOn() then return end
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
