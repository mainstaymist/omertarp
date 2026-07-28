-- A dropped item lying in the world.
--
-- The entity carries the item DEFINITION index — everyone standing in the
-- alley can see that there is a crate on the floor — but never the instance
-- id. That stays on the server, so picking something up is addressed by
-- "the entity I am looking at" rather than by a number a client could invent.

AddCSLuaFile()

-- base_anim, not base_gmodentity: the latter is defined by SANDBOX, and this
-- gamemode derives base. Deriving from an entity that does not exist fails at
-- load and takes the whole class with it.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Item"
ENT.Author = "Omertà RP"
ENT.Spawnable = false
ENT.AdminOnly = true

local FALLBACK_MODEL = "models/props_junk/cardboard_box001a.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "DefIndex")
    self:NetworkVar("Int", 1, "StackSize")
end

-- The client asks the shared item registry what this is; the definition never
-- travels over the wire because both realms already have it.
function ENT:GetItemDef()
    local index = self:GetDefIndex()
    if index <= 0 then return nil end
    return Omerta and Omerta.Items and Omerta.Items.GetByIndex(index) or nil
end

-- What somebody standing over it can read. Nothing new is published here: the
-- definition and the stack size were already on the wire, because the model on
-- the floor gives both away anyway.
function ENT:OmertaLabel()
    local def = self:GetItemDef()
    if not def then return nil end
    local stack = self:GetStackSize()
    return def.name, stack > 1 and ("x" .. stack) or nil
end

if SERVER then
    -- Called after Spawn. `OmertaModel` is set by the spawner beforehand,
    -- because Initialize is what applies the model.
    function ENT:SetItem(instanceId, def, quantity)
        self.OmertaInstance = instanceId
        self:SetDefIndex(Omerta.Items.IndexOf(def.id) or 0)
        self:SetStackSize(math.min(quantity or 1, 65535))
    end

    function ENT:Initialize()
        -- An item definition's model is a guess made in source; resolving it
        -- here means a wrong one is a warning and a crate, not an invisible
        -- object somebody spends an evening looking for.
        self:SetModel(Omerta.Util.ResolveModel(self.OmertaModel, FALLBACK_MODEL))
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)

        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:Wake() end
    end

    -- Picking up goes through the interaction menu, which re-checks range and
    -- ownership server-side. USE is wired to the same path rather than a
    -- shortcut around it.
    function ENT:Use(activator)
        if not (IsValid(activator) and activator:IsPlayer()) then return end
        if not Omerta.Inventory then return end
        Omerta.Inventory.PickUp(activator, self, function(ok, err)
            if not ok and err then Omerta.Chat.Notice(activator, err) end
        end)
    end

    -- The database row outlives the entity: an item removed by a map cleanup
    -- is still lying in the world as far as persistence is concerned, and
    -- comes back on the next restore.
    function ENT:OnRemove()
        if self.OmertaInstance and Omerta.Inventory then
            Omerta.Inventory.Internal.ForgetWorldEntity(self.OmertaInstance)
        end
    end
else
    function ENT:Draw()
        self:DrawModel()
    end
end
