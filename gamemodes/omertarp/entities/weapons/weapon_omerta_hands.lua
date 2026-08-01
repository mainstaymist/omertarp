-- Bare hands: the holster.
--
-- A weapon in this game can only be PUT AWAY by switching to something else,
-- because the engine has no concept of holding nothing — so every character
-- carries this at all times and it is slot 1 of the hotbar. It draws no
-- viewmodel and fires nothing; holding it is the visible fact that nothing is
-- drawn, which is a fact other players are entitled to read off a silhouette
-- (GDD: what you carry openly is public).
--
-- Empty hands are not idle hands: left click knocks on a door. The rule for
-- that lives in modules/interaction/sh_knock.lua, not here.
--
-- Not an M9 item on purpose. Hands cannot be dropped, searched off a body or
-- bought, so an inventory row for them would be a row that lies.

AddCSLuaFile()

SWEP.PrintName = "Hands"
SWEP.Author = "Omertà RP"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.UseHands = true

SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = ""

SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

SWEP.HoldType = "normal"

function SWEP:Initialize()
    self:SetHoldType("normal")
end

function SWEP:Deploy()
    self:SetHoldType("normal")
    return true
end

function SWEP:Holster()
    return true
end

-- How long before the fist can swing again. INPUT DEBOUNCE, not a game rule:
-- without it a held mouse button calls into the module every tick. The rule
-- that stops a knock overlapping itself is the module's per-door lockout, and
-- it is deliberately not this number — tying the swing to the length of the
-- sound would quietly turn a per-DOOR lockout into a per-PLAYER one, locking
-- somebody out of the door beside the one they just tried.
local SWING_DELAY = 0.4

-- Left click with empty hands knocks.
--
-- This function owns exactly one fact: the attack button went down. What a
-- knock IS, what may be knocked on, how loud it is and how often it may happen
-- all live in modules/interaction/sh_knock.lua — a SWEP that decided any of
-- that would be a game rule hidden inside a viewmodel.
--
-- The engine runs this on the server too (the predicted attack path, same as
-- weapon_omerta_base's shot), so "I clicked" reaches the server without a net
-- message and the server decides everything else. The client half returns
-- immediately: a client must not be able to make the noise itself.
function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + SWING_DELAY)
    if CLIENT then return end
    if not (Omerta and Omerta.Knock and Omerta.Knock.Attempt) then return end
    Omerta.Knock.Attempt(self:GetOwner())
end

function SWEP:SecondaryAttack() end

-- Nothing to see: empty hands are drawn by the player model, not a viewmodel.
function SWEP:PreDrawViewModel()
    return true
end

function SWEP:DrawWorldModel() end
