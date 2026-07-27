-- A container that holds items independently of any character: a crate, a
-- safe, a till.
--
-- M9 ships the mechanism and an admin command to place one for testing. Where
-- containers actually live, and who is allowed to open them, belongs to the
-- businesses milestone — which is why the container id is chosen by whoever
-- owns the container rather than allocated here.

AddCSLuaFile()

-- base_anim, not base_gmodentity: see omerta_item.lua.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Container"
ENT.Author = "Omertà RP"
ENT.Spawnable = false
ENT.AdminOnly = true

local MODEL = "models/props_junk/wood_crate001a.mdl"

if SERVER then
    function ENT:Initialize()
        self:SetModel(MODEL)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)

        -- Containers stay put. A safe that can be pushed down the street is a
        -- different feature, and not this one.
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    function ENT:Use(activator)
        if not (IsValid(activator) and activator:IsPlayer()) then return end
        if not Omerta.Inventory then return end
        Omerta.Inventory.Internal.HandleOpen(activator, self:EntIndex())
    end
else
    function ENT:Draw()
        self:DrawModel()
    end
end
