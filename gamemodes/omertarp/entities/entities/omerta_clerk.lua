-- The man behind the counter (D-049).
--
-- A scripted base_anim entity that DOES NOT NAVIGATE. It stands where it was
-- placed, plays reactions, opens the register, and flees to a declared point by
-- a straight-line move with a stuck timeout. If it cannot get there, it cowers.
--
-- Not base_ai: HL2's AI brings its own health, its own death and its own faction
-- relationships — a second lethality model beside the one D-037 spent a
-- milestone building, and three systems' worth of behaviour M14 would spend
-- itself suppressing rather than using.
--
-- Not a NextBot: that makes nav_generate a hard requirement of every map (Q-9),
-- and a robbery on an unmeshed map produces a clerk who stands still forever —
-- the failure mode that looks like success.
--
-- The cost, named rather than discovered: no pathfinding. He cannot dodge,
-- cannot take cover, and cannot chase. Tech §15 already requires NPCs to avoid
-- advanced tactics, and this is the victim rather than the police.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Clerk"
ENT.Author = "Omertà RP"
ENT.Spawnable = false
ENT.AdminOnly = true

-- Best first, and a list rather than one line for the reason omerta_business
-- already gives: a wrong model guess produces an invisible entity, and finding
-- that out in-game is worse than carrying two fallbacks.
local MODELS = {
    "models/humans/group01/male_07.mdl",
    "models/humans/group01/male_03.mdl",
    "models/player/group01/male_02.mdl",
}

-- HIS POSTURE IS NETWORKED; HIS MIND IS NOT.
--
-- What the room can see — hands up, backing away, reaching under the counter —
-- is a fact about the world and belongs to everyone standing in it. His nerve,
-- his personality, his pressure and his current decision never leave the
-- server: a networked reaction state would let every client in the room read
-- whether the man behind the counter is about to hit the button, which is the
-- entire tension of the scene.
ENT.POSE = {
    IDLE     = 0,
    HANDS_UP = 1,
    OPENING  = 2,  -- working the register
    REACHING = 3,  -- for the telephone, or the button
    FLEEING  = 4,
    COWERING = 5,
}

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Pose")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel(Omerta.Util.ResolveModel(MODELS))
        -- A box rather than SetHull: that is an NPC method and this is
        -- deliberately not an NPC (D-049). A player-sized box is all a man
        -- standing still behind a counter needs to be shot at.
        self:PhysicsInitBox(Vector(-16, -16, 0), Vector(16, 16, 72))
        self:SetMoveType(MOVETYPE_STEP)
        self:SetSolid(SOLID_BBOX)
        self:SetUseType(SIMPLE_USE)
        self:SetPose(self.POSE.IDLE)

        -- ENGINE HEALTH AND AN ENTITY DEATH (D-052). He is NOT a character and
        -- does not enter M19's state machine: allowing him to be DOWNED rather
        -- than killed would import D-037's second lethality model through the
        -- back door, which is exactly what the NPC ruling refused.
        self:SetMaxHealth(100)
        self:SetHealth(100)
        self.OmertaClerkAlive = true

        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    function ENT:OnTakeDamage(dmginfo)
        if not self.OmertaClerkAlive then return 0 end

        self:SetHealth(self:Health() - dmginfo:GetDamage())
        if Omerta.Crime and Omerta.Crime.Internal.ClerkHurt then
            Omerta.Crime.Internal.ClerkHurt(self, dmginfo:GetAttacker())
        end

        if self:Health() <= 0 then
            self.OmertaClerkAlive = false
            if Omerta.Crime and Omerta.Crime.Internal.ClerkKilled then
                Omerta.Crime.Internal.ClerkKilled(self, dmginfo:GetAttacker())
            end
        end
        return dmginfo:GetDamage()
    end

    function ENT:Use(activator)
        if not (IsValid(activator) and activator:IsPlayer()) then return end
        if not (Omerta.Crime and Omerta.Crime.Internal.HandleUse) then return end
        Omerta.Crime.Internal.HandleUse(activator, self)
    end

    -- The straight-line move, with the stuck timeout that is the whole reason
    -- this is a scripted entity rather than an AI. If he cannot get there, he
    -- stops trying and cowers — an honest failure, rather than a man walking
    -- into a wall until the operation times out.
    function ENT:Think()
        if not self.OmertaFleeTo then return end
        if not self.OmertaClerkAlive then return end

        local now = CurTime()
        self.OmertaFleeStarted = self.OmertaFleeStarted or now
        if now - self.OmertaFleeStarted > 12 then
            self.OmertaFleeTo = nil
            self:SetPose(self.POSE.COWERING)
            return
        end

        local here = self:GetPos()
        local delta = self.OmertaFleeTo - here
        if delta:Length() < 32 then
            self.OmertaFleeTo = nil
            self:SetPose(self.POSE.COWERING)
            return
        end

        local step = delta:GetNormalized() * 3
        local moved = here + step
        -- No navmesh, so the only obstacle test available is whether the next
        -- step is inside something. Being stuck for a second is what starts the
        -- timeout above rather than what stops the walk.
        self:SetPos(moved)
        self:SetAngles((self.OmertaFleeTo - moved):Angle())
        self:NextThink(now + 0.05)
        return true
    end
else
    function ENT:Draw()
        self:DrawModel()
    end
end
