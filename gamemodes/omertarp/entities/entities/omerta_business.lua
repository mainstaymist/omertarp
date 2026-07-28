-- The counter: where you buy a drink, and where whoever is running the place
-- opens up, empties the register and hires a hand.
--
-- It carries no state a client can read. What you are allowed to see here is
-- decided per person, on the server, every time you walk up to it.

AddCSLuaFile()

-- base_anim, not base_gmodentity: the latter is defined by SANDBOX and this
-- gamemode derives base.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Counter"
ENT.Author = "Omertà RP"
ENT.Spawnable = false
ENT.AdminOnly = true

-- Best first. There is no FurnitureCounter in Half-Life 2 — the first version
-- of this shipped one and produced an invisible counter — so the list is what
-- makes a wrong guess survivable rather than something to discover in-game.
local MODELS = {
    "models/props_c17/FurnitureTable001a.mdl",
    "models/props_interiors/pot_rack01a.mdl",
    "models/props_c17/furnituredresser001a.mdl",
}

if SERVER then
    function ENT:Initialize()
        self:SetModel(Omerta.Util.ResolveModel(MODELS))
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)

        -- A counter that can be pushed down the street is a different feature.
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    function ENT:Use(activator)
        if not (IsValid(activator) and activator:IsPlayer()) then return end
        if not (Omerta.Business and self.OmertaBusiness) then return end
        Omerta.Business.Internal.HandleOpen(activator, self:EntIndex())
    end
else
    function ENT:Draw()
        self:DrawModel()
    end
end
