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
--
-- ART, AND WHICH REALM SEES WHAT (docs/review/06_weapon_art_port.md, Phase 2).
-- A weapon may declare an `anim` block in the arsenal naming the sequence that
-- belongs to each event below; the rules for reading one live in
-- modules/weapons/sh_weapons_anim.lua and the fallbacks are the ACT_VM_*
-- activities this file has always used. Which half of the game each piece
-- drives, because they are genuinely different audiences:
--
--   THE VIEWMODEL is the first-person model, and NOBODY BUT ITS OWNER EVER
--   SEES IT. Every named sequence this file plays goes there. Draw, holster,
--   fire and the dry click are set from the shared, predicted attack path, so
--   the owning client sets its own and the server sets the copy it networks;
--   idle is re-asserted client-side only (see Think); the reload is set by the
--   server, because the server is the only realm that knows a reload was
--   allowed to happen at all.
--
--   THE WORLD MODEL is what everybody else sees, and it is NOT animated by
--   any of this. What an observer reads off a man firing is his hold type
--   (arsenal data), his gesture — ShootEffects sends PLAYER_ATTACK1 and
--   sv_weapons sends PLAYER_RELOAD, both server-side and public — and the
--   sound, which is emitted on the weapon entity in the world and so is heard
--   by everyone in earshot rather than by the shooter alone. The holstered
--   props on a back or a hip are static prop_dynamics and are untouched.

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

-- Every animation this base plays goes through these two, and both are no-ops
-- for a weapon whose arsenal entry has no `anim` block — which is every weapon
-- in the arsenal today. That is the promise that the placeholder guns are
-- untouched by any of this, and it is one line rather than a branch at each
-- call site.
function SWEP:PlayAnim(event, opts)
    local def = self:Def()
    -- Guarded the way SWEP:Reload is: this file is loaded by the ENGINE from
    -- entities/weapons, not by the module loader, so it must not assume the
    -- module has finished building itself on the frame a weapon first deploys.
    if not (def and Omerta.Weapons.Internal.PlayAnim) then return 0 end
    return Omerta.Weapons.Internal.PlayAnim(self, def, event, opts) or 0
end

-- Sound is NOT gated on an animation block: a weapon may want its own gunshot
-- without naming a single sequence, and the fallbacks resolve to exactly what
-- this file emitted before the block existed.
function SWEP:AnimSound(event)
    local def = self:Def()
    if not (def and Omerta.Weapons.Internal.PlayAnimSound) then return end
    Omerta.Weapons.Internal.PlayAnimSound(self, def, event)
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType or "revolver")
end

-- The gun is live the moment it is in the hand. The draw sequence plays over
-- the top and gates NOTHING, deliberately: W0's equip ceremony already charged
-- the player a second and a half of visible, interruptible commitment for this
-- gun, and it ran to completion before the weapon existed to be animated.
-- Charging a second delay for the art would be billing twice for the same
-- reach. If the dumped draw turns out to be long enough to look wrong against
-- the ceremony, the lever is that weapon's `equipTime` in the arsenal — a
-- number about how long drawing takes — and not a stretch of somebody's
-- animation, which is a number about how it looks.
function SWEP:Deploy()
    self:SetHoldType(self.HoldType or "revolver")
    self.OmertaAnimUntil = CurTime() + self:PlayAnim("draw")
    return true
end

--------------------------------------------------------------------------------
-- Firing
--------------------------------------------------------------------------------

function SWEP:CanPrimaryAttack()
    local def = self:Def()
    if not def then return false end

    if self:Clip1() <= 0 then
        -- The dry click is information: the character can feel an empty gun,
        -- and so can anybody standing near enough to hear it. The sound
        -- resolves to "Weapon_Pistol.Empty" for a weapon that declares none,
        -- which is what this line said literally before it was data.
        self:AnimSound("dry")
        -- A model with a dryfire sequence may name one; nothing in the arsenal
        -- does yet, and until one does this is a no-op.
        self:PlayAnim("dry")
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

    -- Resolves to `def.sound`, then to "Weapon_Pistol.Single" — the two things
    -- this line said before it was data — and to a ported weapon's own gunshot
    -- when its arsenal entry names one.
    self:AnimSound("fire")

    -- ShootEffects FIRST, then the named sequence. ShootEffects is the engine's
    -- own bundle — the muzzle flash, PLAYER_ATTACK1 on the player model where
    -- the rest of the street can see it, and ACT_VM_PRIMARYATTACK on the
    -- viewmodel — and the activity it sends is precisely what a third party's
    -- model will not answer. So it runs unchanged for its other two thirds, and
    -- the sequence overrides the third, in that order.
    self:ShootEffects()

    -- The shot that EMPTIES the gun is its own animation on a model that has
    -- one (a slide locking back); a model that draws no distinction inherits
    -- `fire` and nothing here has to know which kind it is.
    self.OmertaAnimUntil = CurTime()
        + self:PlayAnim(self:Clip1() <= 0 and "fire_empty" or "fire")

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
-- Idle
--------------------------------------------------------------------------------
-- A viewmodel that has finished its fire or its reload sits on the last frame
-- of it forever unless something puts it back to idle. HL2 models get that for
-- free from their activity mapping; a model driven by name does not, so the
-- base has to do it.
--
-- CLIENT ONLY, and that is the deliberate half. The viewmodel is a first-person
-- object rendered by exactly one machine, idle has no server consequence
-- whatever, and a per-tick sweep on the server asserting sequences nobody there
-- can see is cost for nothing. The server never sets idle, so there is nothing
-- for the client's local sequence to fight: after the server's last networked
-- sequence (a reload) finishes, the client's own assertion simply stands.
--
-- Two guards keep it cheap. `settle` inside PlayAnim makes re-asserting a
-- sequence that is already running free, and the busy clock below means it is
-- not even attempted while something else is playing. GetNextPrimaryFire is
-- already networked for prediction, so the client knows about a server-side
-- reload lockout without being told a second time.
function SWEP:Think()
    if not CLIENT then return end
    local def = self:Def()
    if not (def and type(def.anim) == "table") then return end

    local now = CurTime()
    local busy = math.max(self.OmertaAnimUntil or 0, self:GetNextPrimaryFire() or 0)
    if now < busy then return end

    self:PlayAnim("idle", { settle = true })
    -- Re-checked twice a second at worst, rather than every frame.
    self.OmertaAnimUntil = now + 0.5
end

--------------------------------------------------------------------------------
-- Holstering
--------------------------------------------------------------------------------

function SWEP:Holster()
    -- Putting a gun away is not instant on a model that animates it, but this
    -- base does not gate the switch on the animation and should not start
    -- here: the engine owns weapon switching, W0's design says holding the
    -- hands IS having nothing drawn, and a Holster that can refuse is a
    -- character who cannot let go of a gun. The sequence plays into the
    -- switch; if the pack's holster animation turns out to be worth waiting
    -- for, that is a feel decision for Track E and a different change.
    self:PlayAnim("holster")
    return true
end
