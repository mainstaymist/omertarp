-- A character on the floor: incapacitated, stabilized, or a corpse waiting to
-- be found.
--
-- D-037 §4a made this a real, persistent entity rather than a ragdolled
-- player, and the deciding argument was combat logging: with nothing in the
-- world representing you, the counterplay to being shot is Alt-F4. The body
-- stays when its owner disconnects, and its bleed-out clock keeps running.
--
-- The entity carries NOTHING identifying. The character id lives on the server
-- as `OmertaCharacter` and is never networked — that is M9's rule for item
-- instances and M12's for line numbers, and a body is the case where it
-- matters most, because a networked character id would hand every client in
-- the room a name the fiction says they have to earn.

AddCSLuaFile()

-- base_anim, not base_gmodentity: the latter is defined by SANDBOX and this
-- gamemode derives base.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Body"
ENT.Author = "Omertà RP"
ENT.Spawnable = false
ENT.AdminOnly = true

local FALLBACK_MODEL = "models/player/group01/male_01.mdl"

-- A body is a PERSON, and people are never labelled (D-033).
--
-- This function exists and deliberately returns nothing. The lint requires
-- every interactable class to define a label so that nobody registers one
-- without deciding what it says; this is the decision. Who the man on the
-- floor is resolves through M5's ResolveDisplayName, per observer, exactly as
-- it does for someone standing up — so you recognise him if and only if you
-- would have recognised him upright, and a masked body stays Unknown.
function ENT:OmertaLabel()
    return nil
end

if SERVER then
    function ENT:Initialize()
        self:SetModel(Omerta.Util.ResolveModel(self.OmertaModel, FALLBACK_MODEL))
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        self:SetCollisionGroup(COLLISION_GROUP_DEBRIS_TRIGGER)

        -- Lying down. A body that stands upright reads as a person, and the
        -- difference has to be legible from across the street.
        local angles = self:GetAngles()
        self:SetAngles(Angle(85, angles.y, 0))

        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:Wake() end
    end

    -- USE opens the same interaction path as the menu, which re-checks range
    -- and permission server-side. There is no shortcut around it.
    function ENT:Use(activator)
        if not (IsValid(activator) and activator:IsPlayer()) then return end
        if not (Omerta.Injury and Omerta.Injury.Internal.HandleUse) then return end
        Omerta.Injury.Internal.HandleUse(activator, self)
    end

    -- The database row outlives the entity: a body removed by a map cleanup is
    -- still on the floor as far as persistence is concerned, and comes back on
    -- the next restore. Same contract as M9's dropped items.
    function ENT:OnRemove()
        if self.OmertaCharacter and Omerta.Injury then
            Omerta.Injury.Internal.ForgetBodyEntity(self.OmertaCharacter)
        end
    end
else
    function ENT:Draw()
        self:DrawModel()
    end
end
