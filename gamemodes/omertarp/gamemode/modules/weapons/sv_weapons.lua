-- The server half: how a weapon gets into a hand, out of one, and reloaded.
--
-- The rule that shapes all of it: THE M9 ITEM IS THE TRUTH. The SWEP in a
-- player's hands is a projection of an equipped inventory row, the way M19's
-- ragdoll is a projection of an injury row — given when the row says so,
-- stripped when it stops saying so, and never the thing itself. That is what
-- makes a weapon searchable off a body, buyable through a treasury, droppable
-- in a river, and impossible to duplicate by any client behaviour at all.

local MODULE = Omerta.Module.Get("weapons")

Omerta.Weapons = Omerta.Weapons or {}
Omerta.Weapons.Internal = Omerta.Weapons.Internal or {}
local Internal = Omerta.Weapons.Internal

Omerta.Config.Define("weapons.damage_scale", {
    type = "number", default = 1, min = 0.1, max = 3, scope = "server",
    description = "Multiplier on every weapon's damage. The tuning knob for how " ..
        "lethal the city is, without editing the arsenal.",
})

--------------------------------------------------------------------------------
-- Giving and stripping
--------------------------------------------------------------------------------

-- The item instance a held weapon came from, for M15's serials and for knowing
-- which rounds to refund where.
function Omerta.Weapons.InstanceOf(wep)
    return IsValid(wep) and wep.OmertaInstance or nil
end

local function giveOne(ply, row, def)
    if not (IsValid(ply) and row and def) then return end
    -- A downed character holds nothing; the row stays equipped and the weapon
    -- arrives when they stand up, through the same reconcile.
    if Omerta.Injury.IsPlayerDown(ply) then return end
    if ply:HasWeapon(def.class) then return end

    local wep = ply:Give(def.class)
    if IsValid(wep) then
        wep.OmertaInstance = row.id
        -- Given EMPTY, always. Rounds are items; the clip is filled by
        -- reloading from what the character actually carries.
        wep:SetClip1(0)
    end
end

-- Rounds in the clip go back into the pocket they came from. `force` skips the
-- room check deliberately: this ammunition was on the character's person a
-- moment ago, inside the gun, so refusing it now would delete real objects.
local function refundClip(ply, wep, def)
    local rounds = IsValid(wep) and wep:Clip1() or 0
    if rounds <= 0 or not IsValid(ply) then return end
    wep:SetClip1(0)
    Omerta.Inventory.Add(ply, def.ammo, rounds, { force = true }, function(ok, err)
        if not ok then
            Omerta.Log.Error("weapons", "could not refund %d round(s) of %s: %s",
                rounds, def.ammo, tostring(err))
        end
    end)
end

local function stripOne(ply, def)
    if not (IsValid(ply) and def) then return end
    local wep = ply:GetWeapon(def.class)
    if IsValid(wep) then
        refundClip(ply, wep, def)
        ply:StripWeapon(def.class)
    end
end

-- The full reconciliation: hands match equipped rows, exactly. Run whenever
-- the answer could have changed wholesale — a character load, standing back
-- up — where the per-item hooks below handle the ordinary single changes.
function Internal.Reconcile(ply)
    if not IsValid(ply) then return end
    local character = Omerta.Characters.Get(ply)
    if not character then return end

    local desired = {} -- class -> { row, def }
    if not Omerta.Injury.IsPlayerDown(ply) then
        local owner = Omerta.Inventory.OwnerOf(ply)
        for _, row in ipairs(Omerta.Inventory.Get(owner) or {}) do
            if row.equipped_slot then
                local def = Omerta.Weapons.ForItem(row.def_id)
                if def then desired[def.class] = { row = row, def = def } end
            end
        end
    end

    -- Strip what should not be there (ours only — the physgun is not our
    -- business), then give what should.
    for _, wep in ipairs(ply:GetWeapons()) do
        local id = wep.OmertaId
        if id and not desired[wep:GetClass()] then
            stripOne(ply, Omerta.Weapons.Get(id))
        end
    end
    for _, want in pairs(desired) do
        giveOne(ply, want.row, want.def)
    end
end

--------------------------------------------------------------------------------
-- Reloading
--------------------------------------------------------------------------------
-- Rounds move from inventory rows into the clip, server-side, through M9's
-- transactional Remove. There is no client message for this beyond the engine
-- reload key, and nothing a client says changes what it is carrying.

-- Consume `count` of an item across however many stacks hold it. Rows are
-- re-read after every removal, because Remove reshapes the stacks.
function Internal.ConsumeItems(ply, defId, count, cb)
    local remaining = count
    local function step()
        if remaining <= 0 then cb(true) return end
        if not IsValid(ply) then cb(false, "gone") return end
        local owner = Omerta.Inventory.OwnerOf(ply)
        local found = nil
        for _, row in ipairs(Omerta.Inventory.Get(owner) or {}) do
            if row.def_id == defId then found = row break end
        end
        if not found then cb(remaining < count, "out") return end
        local take = math.min(remaining, found.quantity)
        Omerta.Inventory.Remove(found.id, take, function(ok, err)
            if not ok then cb(false, err) return end
            remaining = remaining - take
            step()
        end)
    end
    step()
end

function Internal.Reload(ply, wep)
    if not (IsValid(ply) and IsValid(wep)) then return end
    local def = wep:Def()
    if not def then return end

    -- One reload at a time; the animation is the lockout.
    if (wep.OmertaReloadUntil or 0) > CurTime() then return end

    local owner = Omerta.Inventory.OwnerOf(ply)
    local available = 0
    for _, row in ipairs(Omerta.Inventory.Get(owner) or {}) do
        if row.def_id == def.ammo then available = available + row.quantity end
    end

    local take = Omerta.Weapons.PlanReload(def.clip, wep:Clip1(), available)
    if take <= 0 then
        if wep:Clip1() < def.clip then
            local ammoDef = Omerta.Items.Get(def.ammo)
            Omerta.Chat.Notice(ply, "You are out of "
                .. string.lower(ammoDef and ammoDef.name or "ammunition") .. ".")
        end
        return
    end

    wep.OmertaReloadUntil = CurTime() + def.reloadTime
    wep:SetNextPrimaryFire(CurTime() + def.reloadTime)
    wep:SendWeaponAnim(ACT_VM_RELOAD)
    ply:SetAnimation(PLAYER_RELOAD)

    Internal.ConsumeItems(ply, def.ammo, take, function(ok, err)
        if not ok then
            Omerta.Log.Error("weapons", "reload consume failed: %s", tostring(err))
            return
        end
        -- The rounds are already out of the pocket; they arrive in the clip
        -- when the hands finish, and a weapon stripped mid-reload refunds them
        -- through the ordinary strip path because the clip is set first.
        if IsValid(wep) and IsValid(ply) and wep:GetOwner() == ply then
            wep:SetClip1(wep:Clip1() + take)
        elseif IsValid(ply) then
            -- Stripped between keypress and consume: nothing holds the rounds
            -- now, so they go straight back.
            Omerta.Inventory.Add(ply, def.ammo, take, { force = true })
        end
    end)
end

--------------------------------------------------------------------------------
-- The hooks that keep hands and rows agreeing
--------------------------------------------------------------------------------

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    -- The single-change paths: M9 announces an equip, the weapon appears.
    hook.Add("Omerta.ItemEquipped", "omerta.weapons.equip", function(ply, row, def)
        local weapon = def and def.weapon and Omerta.Weapons.Get(def.weapon)
        if weapon then giveOne(ply, row, weapon) end
    end)

    hook.Add("Omerta.ItemUnequipped", "omerta.weapons.unequip", function(ply, row, def)
        local weapon = def and def.weapon and Omerta.Weapons.Get(def.weapon)
        if weapon then stripOne(ply, weapon) end
    end)

    -- The wholesale paths: a fresh character's hands are rebuilt from their
    -- rows once the rows actually exist.
    hook.Add("Omerta.CharacterInventoryLoaded", "omerta.weapons.restore", function(ply)
        Internal.Reconcile(ply)
    end)

    -- Going down empties the hands — the gun lands in the inventory where a
    -- search can find it, which is what makes disarming somebody a matter of
    -- putting them on the floor. Standing back up refills them.
    hook.Add("Omerta.InjuryChanged", "omerta.weapons.injury", function(characterId, from, to)
        local ply = Omerta.Injury.Internal.PlayerFor(characterId)
        if not IsValid(ply) then return end
        if Omerta.Injury.IsIncapable(to) then
            Internal.Reconcile(ply) -- desired set is empty while down
        elseif Omerta.Injury.IsDown(from) then
            Internal.Reconcile(ply)
        end
    end)

    -- Rounds in a clip survive a disconnect by going back into the inventory,
    -- which does persist. Without this, quit-and-rejoin quietly destroys up to
    -- a clip of ammunition per weapon.
    hook.Add("PlayerDisconnected", "omerta.weapons.refund", function(ply)
        for _, wep in ipairs(ply:GetWeapons()) do
            if wep.OmertaId then
                refundClip(ply, wep, Omerta.Weapons.Get(wep.OmertaId))
            end
        end
    end)

    concommand.Add("omerta_weapons_list", function(caller)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        for _, def in ipairs(Omerta.Weapons.All()) do
            Omerta.Log.Info("weapons", "  %-20s %-22s dmg %-3d clip %-2d  %s",
                def.id, def.class, def.damage, def.clip, def.ammo)
        end
    end)
end
