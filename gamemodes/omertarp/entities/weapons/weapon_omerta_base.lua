-- The one place fire behaviour lives (Q-10, D-039).
--
-- Every weapon in the game is a generated class whose only content is an
-- OmertaId; ALL behaviour is here, reading the definition that id names. That
-- is the ruling made structural: adding a weapon touches data, and changing
-- how shooting works touches exactly one file.
--
-- Server authority: the client predicts the shot for feel — the engine's
-- shared prediction is why firing doesn't stutter — but damage is decided by
-- the server's bullet, ammo is counted by the server, reloading consumes
-- server-side items, and every shot the server fires runs the
-- Omerta.WeaponFired hook. A client that lies changes its own muzzle flash.

AddCSLuaFile()

SWEP.PrintName = "Omertà Weapon"
SWEP.Author = "Omertà RP"
SWEP.Spawnable = false
SWEP.AdminOnly = true
SWEP.UseHands = true

SWEP.OmertaId = nil       -- set by each generated class
SWEP.OmertaInstance = nil -- the M9 item instance in hand; server-only

SWEP.Primary = { ClipSize = 0, DefaultClip = 0, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

function SWEP:Def()
    return Omerta.Weapons and Omerta.Weapons.Get(self.OmertaId) or nil
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType or "revolver")
end

function SWEP:Deploy()
    self:SetHoldType(self.HoldType or "revolver")
    return true
end

--------------------------------------------------------------------------------
-- Firing
--------------------------------------------------------------------------------

function SWEP:CanPrimaryAttack()
    local def = self:Def()
    if not def then return false end

    if self:Clip1() <= 0 then
        -- The dry click is information: the character can feel an empty gun.
        self:EmitSound("Weapon_Pistol.Empty")
        self:SetNextPrimaryFire(CurTime() + 0.4)
        return false
    end
    return true
end

function SWEP:PrimaryAttack()
    if not self:CanPrimaryAttack() then return end
    local def = self:Def()
    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    self:SetNextPrimaryFire(CurTime() + Omerta.Weapons.CycleDelay(def.rpm))
    self:TakePrimaryAmmo(1)

    -- Stance is part of the shot: running ruins it, crouching steadies it.
    local cone = Omerta.Weapons.Cone(def.spread
        * Omerta.Weapons.SpreadFactor(owner:GetVelocity():Length2D(), owner:Crouching()))

    -- The client's number is cosmetic (its bullet draws the tracer and the
    -- impact it predicts); the wound is the SERVER's bullet, scaled by the
    -- operator's tuning knob, landing in M19's damage interception like any
    -- other harm in the world.
    local damage = def.damage
    if SERVER then damage = damage * Omerta.Config.Get("weapons.damage_scale") end

    owner:FireBullets({
        Num = 1,
        Src = owner:GetShootPos(),
        Dir = owner:GetAimVector(),
        Spread = Vector(cone, cone, 0),
        Tracer = 1,
        Force = damage * 0.15,
        Damage = damage,
    })

    self:EmitSound(def.sound or "Weapon_Pistol.Single")
    self:ShootEffects()

    -- Recoil only on the predicted first run, or the kick doubles.
    if IsFirstTimePredicted() then
        owner:ViewPunch(Angle(-def.recoil, math.Rand(-0.3, 0.3) * def.recoil, 0))
    end

    -- The loudest fact in the design. M15's witnesses, M16's alarm and any
    -- future heat all hang off this one hook; none of them need this file
    -- changed to exist.
    if SERVER then
        hook.Run("Omerta.WeaponFired", owner, def.id, self)
    end
end

-- No secondary at MVP. Ironsights are a presentation question for Track E's
-- pass over feel, not a mechanic this base should invent on its own.
function SWEP:SecondaryAttack() end

--------------------------------------------------------------------------------
-- Reloading
--------------------------------------------------------------------------------
-- Rounds are ITEMS (D-004). The engine's ammo pool is never used: reloading
-- moves rounds from the owner's M9 inventory into the clip, on the server,
-- through the same transactional paths everything else uses. A client cannot
-- invent ammunition because there is nothing client-side to invent it with.

function SWEP:Reload()
    if CLIENT then return end
    if not (Omerta.Weapons and Omerta.Weapons.Internal.Reload) then return end
    Omerta.Weapons.Internal.Reload(self:GetOwner(), self)
end

--------------------------------------------------------------------------------
-- Holstering
--------------------------------------------------------------------------------

function SWEP:Holster()
    return true
end
