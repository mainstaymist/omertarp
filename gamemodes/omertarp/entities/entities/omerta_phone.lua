-- A telephone: a payphone bolted to a wall, or a private line on a desk.
--
-- The entity carries nothing but its own existence. Which line it is, who is
-- calling it, and what is being said all live on the server — a handset that
-- told clients its number would hand every passer-by a directory, which §4a
-- exists to prevent.

AddCSLuaFile()

-- base_anim, not base_gmodentity: the latter is defined by SANDBOX and this
-- gamemode derives base.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Telephone"
ENT.Author = "Omertà RP"
ENT.Spawnable = false
ENT.AdminOnly = true

local MODELS = {
    "models/props_lab/citizenradio.mdl",
    "models/props_c17/consolebox01a.mdl",
}

-- Only what is legible from arm's length. `PublicNumber` is empty on a private
-- line and stays that way: the server fills it from Omerta.Phone.PublicNumberFor,
-- which is where that rule is decided and tested.
function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "Kind")
    self:NetworkVar("String", 1, "PublicNumber")
end

function ENT:OmertaLabel()
    local KIND = Omerta and Omerta.Phone and Omerta.Phone.KIND
    if KIND and self:GetKind() == KIND.PAYPHONE then
        local number = self:GetPublicNumber()
        return "Payphone", number ~= "" and ("No. " .. number) or nil
    end
    return "Telephone", nil
end

if SERVER then
    function ENT:Initialize()
        self:SetModel(Omerta.Util.ResolveModel(MODELS))
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)

        -- Telephones stay where they were installed.
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    -- Picking up the receiver. Everything it can mean — answer this, dial
    -- that, you are not close enough — is decided on the server.
    function ENT:Use(activator)
        if not (IsValid(activator) and activator:IsPlayer()) then return end
        if not (Omerta.Phone and Omerta.Phone.Internal.PickUp) then return end
        Omerta.Phone.Internal.PickUp(activator)
    end
else
    function ENT:Draw()
        self:DrawModel()
    end
end
