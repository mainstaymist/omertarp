-- Bare hands: the holster.
--
-- A weapon in this game can only be PUT AWAY by switching to something else,
-- because the engine has no concept of holding nothing — so every character
-- carries this at all times and it is slot 1 of the hotbar. It draws no
-- viewmodel, swings nothing and fires nothing; holding it is the visible fact
-- that nothing is drawn, which is a fact other players are entitled to read
-- off a silhouette (GDD: what you carry openly is public).
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

function SWEP:PrimaryAttack() end
function SWEP:SecondaryAttack() end

-- Nothing to see: empty hands are drawn by the player model, not a viewmodel.
function SWEP:PreDrawViewModel()
    return true
end

function SWEP:DrawWorldModel() end
