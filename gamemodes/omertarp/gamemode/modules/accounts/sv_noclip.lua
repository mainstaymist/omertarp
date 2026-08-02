-- Staff noclip.
--
-- The gamemode derives `base`, not sandbox, so nothing granted noclip to
-- anybody — GM:PlayerNoClip defaults to refusing, and V (GMod's default bind
-- for the `noclip` command) did nothing at all. Staff have to be able to get
-- to a room to look at it, and walking there through a door they are not
-- supposed to be able to open is worse than flying.
--
-- SUPERADMIN ONLY, and checked on every toggle rather than cached: a demotion
-- has to take effect without a reconnect.
--
-- INVISIBLE WHILE FLYING, which is the part that matters for this game rather
-- than for convenience. A watcher hovering over a robbery is a witness the
-- fiction never contained, and D-014's whole argument — that who saw you is a
-- real question with real consequences — falls apart if staff are standing in
-- the room being seen. So a noclipping admin is not drawn, casts no shadow, is
-- not solid, and cannot be traced against: M5's identity resolution, M8's
-- interactable dot and M14's observer set all work off traces and entity
-- checks, so becoming untraceable takes them out of every one of those
-- questions at once rather than in three places.

Omerta.Accounts = Omerta.Accounts or {}
Omerta.Accounts.Internal = Omerta.Accounts.Internal or {}
local Internal = Omerta.Accounts.Internal

-- What they looked like before, so putting them back does not guess.
local restore = {}

function Internal.EnterNoclip(ply)
    local sid = ply:SteamID64() or ""
    if restore[sid] then return end

    restore[sid] = {
        colour = ply:GetColor(),
        renderMode = ply:GetRenderMode(),
        collision = ply:GetCollisionGroup(),
    }

    -- SetNoDraw rather than a zero alpha alone: alpha leaves a visible weapon
    -- in the hands and a shadow on the floor, which is most of a man.
    ply:SetNoDraw(true)
    ply:DrawShadow(false)
    ply:SetRenderMode(RENDERMODE_TRANSALPHA)
    ply:SetColor(Color(255, 255, 255, 0))
    -- COLLISION_GROUP_WORLD keeps them out of every player trace — including
    -- the one M8 runs for the dot and the one M14 runs for the observer set —
    -- while still keeping them out of the void.
    ply:SetCollisionGroup(COLLISION_GROUP_WORLD)

    Omerta.Log.Audit("staff.noclip", {
        actor = ply:SteamID64(),
        data = { state = "on" },
    })
end

function Internal.LeaveNoclip(ply)
    local sid = ply:SteamID64() or ""
    local previous = restore[sid]
    restore[sid] = nil

    ply:SetNoDraw(false)
    ply:DrawShadow(true)
    ply:SetRenderMode(previous and previous.renderMode or RENDERMODE_NORMAL)
    ply:SetColor(previous and previous.colour or Color(255, 255, 255, 255))
    ply:SetCollisionGroup(previous and previous.collision or COLLISION_GROUP_PLAYER)

    if previous then
        Omerta.Log.Audit("staff.noclip", {
            actor = ply:SteamID64(),
            data = { state = "off" },
        })
    end
end

function Internal.RegisterNoclip()
    hook.Add("PlayerNoClip", "omerta.accounts.noclip", function(ply, desired)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return false end

        if desired then
            Internal.EnterNoclip(ply)
        else
            Internal.LeaveNoclip(ply)
        end
        return true
    end)

    -- Two ways out that are not a second V press, and both would otherwise
    -- leave somebody invisible: dying, and spawning into a fresh body. The
    -- engine drops noclip on spawn without telling PlayerNoClip about it.
    hook.Add("PlayerSpawn", "omerta.accounts.noclip_reset", function(ply)
        if restore[ply:SteamID64() or ""] then Internal.LeaveNoclip(ply) end
    end)

    hook.Add("PlayerDisconnected", "omerta.accounts.noclip_forget", function(ply)
        restore[ply:SteamID64() or ""] = nil
    end)
end
