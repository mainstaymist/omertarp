-- V flies, for staff.
--
-- The server side of this is `sv_noclip.lua`, which owns the permission and the
-- invisibility. This half exists only because the key cannot be relied on: GMod
-- ships `bind v noclip` in its default config, but a player with an older
-- config, a custom one, or one from another server may have V on anything or on
-- nothing — and "press V" was the request, not "press whatever you have noclip
-- bound to".
--
-- SO IT DEFERS TO A REAL BINDING AND ONLY FILLS IN WHEN THERE IS NOT ONE. If V
-- already runs `noclip`, this does nothing at all: firing as well would toggle
-- twice in one press, which is a key that visibly does nothing and is far worse
-- than a key that does nothing quietly. Anyone who has deliberately moved
-- noclip onto another key keeps it there and keeps V free.

-- WHY THIS DOES NOT DECLARE ITS DEPENDENCIES, stated rather than left as an
-- oversight for somebody to "fix" into a boot failure: `accounts` cannot depend
-- on `hud` or `chat`, because both reach `characters`, and `characters` depends
-- on `accounts`. The graph is right — accounts is near the bottom and the
-- screen is near the top — and a staff key is the one thing that legitimately
-- reads upward. So both calls below are RUNTIME calls, made from Think long
-- after every module has been enabled, and both are guarded so a partly-loaded
-- client cannot error every frame.

local wasDown = false

hook.Add("Think", "omerta.accounts.noclip_key", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    -- Polled rather than hooked, for the reason cl_inventory gives about C: a
    -- bind can be taken away from us and a physical key cannot.
    --
    -- Every guard here is one the inventory already learned it needed. M7 draws
    -- its own chat box and suppresses the engine's, so `IsTyping` alone reports
    -- nobody is ever typing — and the letter V is in a great many sentences.
    local chatting = (ply.IsTyping and ply:IsTyping())
        or (Omerta.Chat and Omerta.Chat.IsTyping and Omerta.Chat.IsTyping())
    local inWorld = not (Omerta.HUD and Omerta.HUD.InWorld) or Omerta.HUD.InWorld()
    local down = input.IsKeyDown(KEY_V) and not chatting
        and not gui.IsGameUIVisible() and not gui.IsConsoleVisible()
        and inWorld

    local previous = wasDown
    wasDown = down
    if not (down and not previous) then return end

    -- The engine's own binding wins if there is one on this key.
    local bound = input.LookupBinding("noclip")
    if bound and bound:lower() == "v" then return end

    -- The server decides whether this is allowed; a non-staff player running it
    -- is refused by PlayerNoClip and nothing happens, which is the same answer
    -- typing it in the console gives.
    RunConsoleCommand("noclip")
end)
