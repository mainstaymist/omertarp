-- The bridge to somebody else's SWEP, and the ammunition accounting that keeps
-- D-004 true across it.
--
-- WHAT THIS FILE IS DEFENDING. D-004 says rounds are ITEMS and the engine's
-- ammo pool is never used. W0 built the whole base around that: weapons are
-- given empty, reloading moves rows into the clip through M9's transactional
-- Remove, and there is no path on which ammunition appears. An ARC9 or a TFA
-- SWEP owns its own reloading and takes ammunition FROM THE ENGINE POOL, which
-- is exactly the thing D-004 refuses to trust.
--
-- The resolution is not to hand the pool over. It is to make the pool a
-- PROJECTION: the M9 rows remain the only truth, the server writes the pool
-- from them, re-writes it four times a second, and charges the inventory for
-- every round that leaves it. A third-party gun then reloads from what looks
-- to it like an ordinary ammo pool, and every round it takes was a real object
-- in a real pocket a moment earlier.
--
-- THE ONE RULE FOR EVERY CASE WE CANNOT SEE. Neither addon is installed on the
-- machine this was written on and there was no network to fetch them, so this
-- file was written without reading a single line of either. Wherever the
-- accounting is ambiguous it resolves the SAME way — the player ends up with
-- FEWER rounds than they might have had, never more. A bridge that guesses
-- generously is a duplication bug with extra steps, and duplication is the one
-- failure M9 was built to make impossible.
--
-- No MODULE lifecycle method lives here. This file sorts before sv_weapons.lua
-- and MODULE is one shared table, so defining OnEnable here would silently
-- REPLACE the one that installs every hook in the module — the incident
-- sv_help.lua carries the scar tissue for, and a lint test now fails over.
-- Everything below is a function sv_weapons.lua's OnEnable calls.

local MODULE = Omerta.Module.Get("weapons")

Omerta.Weapons = Omerta.Weapons or {}
Omerta.Weapons.Internal = Omerta.Weapons.Internal or {}
local Internal = Omerta.Weapons.Internal

Omerta.Config.Define("weapons.external", {
    type = "boolean", default = true, scope = "server",
    description = "Use the third-party SWEP classes the arsenal names, when the " ..
        "server actually has them. Off, every weapon uses our own base — the " ..
        "operator's recourse if an addon misbehaves on a live server.",
})

--------------------------------------------------------------------------------
-- Which class each weapon is actually using
--------------------------------------------------------------------------------

-- Said once per weapon per boot, and only for the ones that fell back. A
-- server that has the addons prints nothing at all; a server that does not
-- gets one line naming the class it is missing, which is the only sentence
-- that answers "why does my Thompson look like an SMG".
function Internal.ResolveExternalClasses(announce)
    local allow = Omerta.Config.Get("weapons.external")
    local count, fellBack = Omerta.Weapons.ResolveExternal(nil, allow)

    if announce and count > 0 then
        if not allow then
            Omerta.Log.Info("weapons", "weapons.external is off — %d weapon(s) " ..
                "using our own base by configuration", count)
        else
            for _, def in ipairs(fellBack) do
                Omerta.Log.Warn("weapons", "'%s' names SWEP '%s', which this server " ..
                    "does not have — falling back to '%s'. Install the addon, or " ..
                    "ignore this and play with our own base.",
                    def.id, def.external, def.class)
            end
        end
    end
    return count
end

--------------------------------------------------------------------------------
-- Per-player, per-weapon bookkeeping
--------------------------------------------------------------------------------
-- Two numbers per player and two per weapon entity. That is the entire state
-- of the bridge, deliberately: anything richer would be a second inventory,
-- which is the mistake D-004 exists to prevent.
--
--   pool.type    — the engine ammo type we are currently projecting into
--   pool.count   — what we last set it to (the baseline a draw is measured from)
--   pool.pending — rounds already charged whose M9 Remove has not landed yet
--
--   wep.OmertaClipSeen  — the magazine we last settled on
--   wep.OmertaCommitted — and therefore the most we are willing to refund

local pools = {} -- SteamID64 -> { type =, count =, pending = }

local function keyFor(ply)
    return IsValid(ply) and (ply:SteamID64() or "") or ""
end

function Internal.ForgetExternal(ply)
    pools[keyFor(ply)] = nil
end

-- The held weapon, if it is one of ours running somebody else's class.
local function activeExternal(ply)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return nil end
    local def = Omerta.Weapons.ForClass(wep:GetClass())
    if not (def and Omerta.Weapons.IsExternal(def)) then return nil end
    return wep, def
end

-- Every pool read and write goes through these two, because a SWEP whose
-- source we have not read is entitled to have opinions about its own ammo type
-- and we are not entitled to error over them.
local function ammoTypeOf(wep)
    local ok, id = pcall(wep.GetPrimaryAmmoType, wep)
    if not ok or type(id) ~= "number" or id < 0 then return nil end
    return id
end

local function clipOf(wep)
    local ok, count = pcall(wep.Clip1, wep)
    if not ok or type(count) ~= "number" then return 0 end
    return count
end

--------------------------------------------------------------------------------
-- The projection
--------------------------------------------------------------------------------

-- Run at give, at strip, and four times a second from the reconcile timer —
-- which is also what makes it run "on any inventory change", since a round
-- entering or leaving a pocket by any route at all is visible to the next
-- sweep a quarter second later. There is no inventory-changed hook to be
-- precise against and inventing one for this would be M9's business, not ours.
function Internal.SyncExternal(ply)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    local key = keyFor(ply)
    local state = pools[key]

    local wep, def = activeExternal(ply)
    if not wep then
        -- Nothing of ours in the hands: the projection is withdrawn entirely.
        -- Leaving a pool standing while the gun is away is how a player fills
        -- one, switches to something else and keeps it.
        if state and state.type then
            ply:SetAmmo(0, state.type)
        end
        pools[key] = nil
        return
    end

    local ammoType = ammoTypeOf(wep)
    if not ammoType then
        -- The SWEP does not answer for its own ammunition. We cannot project
        -- into a pool we cannot name, so the magazine accounting below is all
        -- there is — and it is the strict half anyway.
        Internal.WarnOnce(def.id, "ammotype",
            "'%s' (%s) does not answer GetPrimaryAmmoType — its reloading " ..
            "cannot be backed by the inventory; the magazine is still clamped",
            def.id, def.external)
    end

    -- A different caliber than we were projecting: put the old pool down
    -- before picking the new one up, or a player with two guns keeps both.
    if state and state.type and state.type ~= ammoType then
        ply:SetAmmo(0, state.type)
        state = nil
    end
    state = state or { type = ammoType, count = 0, pending = 0 }
    state.type = ammoType

    -- Rounds already charged whose Remove has not landed do not exist any
    -- more, whatever the rows still say. Without this the next sweep re-reads
    -- them as available and projects them back into the pool.
    local reserve = math.max(0, Internal.ReserveOf(ply, def.ammo) - (state.pending or 0))
    local pool = ammoType and ply:GetAmmoCount(ammoType) or 0
    local clip = clipOf(wep)

    local plan = Omerta.Weapons.PlanPoolSync(
        reserve, wep.OmertaClipSeen or 0, state.count or 0, clip, pool)

    -- The magazine first: whatever the inventory could not pay for comes back
    -- out of it before anything else is written anywhere.
    if plan.clip ~= clip then
        pcall(wep.SetClip1, wep, plan.clip)
    end
    wep.OmertaClipSeen = plan.clip
    wep.OmertaCommitted = plan.clip

    if ammoType then ply:SetAmmo(plan.pool, ammoType) end
    state.count = plan.pool
    pools[key] = state

    if plan.spend > 0 then
        state.pending = (state.pending or 0) + plan.spend
        Internal.ConsumeItems(ply, def.ammo, plan.spend, function(ok, err)
            local live = pools[keyFor(ply)]
            if live then
                live.pending = math.max(0, (live.pending or 0) - plan.spend)
            end
            if not ok then
                -- The pool was already lowered, so nothing was gained; the
                -- rounds are simply still in the pocket and the next sweep
                -- projects them again. Worth a line, never a rollback.
                Omerta.Log.Error("weapons", "could not charge %d round(s) of %s " ..
                    "for '%s': %s", plan.spend, def.ammo, def.id, tostring(err))
            end
            Internal.PushReserve(ply)
        end)
    end
end

-- A fresh third-party SWEP arrives with opinions: a DefaultClip we did not
-- set, and in some bases a handful of pool ammunition handed over on Give. All
-- of it is invented, so all of it goes.
--
-- Twice, a tick apart, because a SWEP is entitled to set itself up in
-- Initialize, in Deploy, or on its first Think, and we cannot read which of
-- those either addon does. Zeroing something that is already zero costs
-- nothing; missing the one that is not costs a free magazine per draw.
function Internal.ExternalAfterGive(ply, wep, def)
    if not (Omerta.InEngine and IsValid(ply) and IsValid(wep)) then return end
    if not Omerta.Weapons.IsExternal(def) then return end

    local function settle()
        if not (IsValid(ply) and IsValid(wep)) then return end
        pcall(wep.SetClip1, wep, 0)
        local ammoType = ammoTypeOf(wep)
        if ammoType then ply:SetAmmo(0, ammoType) end
        wep.OmertaClipSeen = 0
        wep.OmertaCommitted = 0
        local state = pools[keyFor(ply)]
        if state then state.count = 0 end
        Internal.SyncExternal(ply)
    end

    settle()
    timer.Simple(0, settle)
end

-- What goes back in the pocket when a third party's gun leaves a hand. The
-- pool is NOT refunded and must not be: it was a projection of rows that were
-- never removed, so putting it back would be minting the same rounds twice.
function Internal.ExternalBeforeStrip(ply, wep, def)
    if not (Omerta.InEngine and IsValid(ply) and IsValid(wep)) then return end
    local ammoType = ammoTypeOf(wep)
    if ammoType then ply:SetAmmo(0, ammoType) end
    local state = pools[keyFor(ply)]
    if state and state.type == ammoType then state.count = 0 end
end

--------------------------------------------------------------------------------
-- The seams a third party's SWEP does not know it owes us
--------------------------------------------------------------------------------
-- EntityFireBullets, once, for both of them.
--
-- It is the right seam rather than a convenient one: it runs BEFORE any damage
-- exists, so M19's EntityTakeDamage interception and its damage filters see
-- our number rather than the addon's, and hook ordering between the two never
-- has to be reasoned about. (GMod iterates hooks with pairs; a bridge that
-- corrected the damage in EntityTakeDamage would be correct or not depending
-- on table order, which is not a thing to build lethality on.)
--
-- Our own base does not come through here — it runs the hook itself in
-- PrimaryAttack — so the guard on IsExternal is what stops M14 receiving every
-- shot twice.

function Internal.OnExternalFireBullets(ent, data)
    if not (SERVER and IsValid(ent) and ent:IsPlayer()) then return end
    local wep, def = activeExternal(ent)
    if not wep then return end

    -- The arsenal's number, imposed. D-039 makes `weapons.damage_scale` the
    -- one lethality knob and W0 made "damage this project can reason about" a
    -- founding reason for a base of our own; letting an addon's damage through
    -- would quietly retire both, along with M19's calibration against it.
    -- What is lost with it is the addon's own ballistics — range falloff,
    -- penetration, per-limb multipliers — and that is written down in the
    -- design review rather than discovered.
    local damage = def.damage * Omerta.Config.Get("weapons.damage_scale")
    data.Damage = damage
    data.Force = damage * 0.15

    -- The loudest fact in the design (W0 §3), and the reason M14's review is
    -- already written against it. A gun somebody else wrote does not call it,
    -- so it is called here — for the trigger pull, not per pellet, which is
    -- what FireBullets means.
    hook.Run("Omerta.WeaponFired", ent, def.id, wep)

    -- The magazine moved; settle before the player can act on it rather than
    -- up to a quarter second later.
    Internal.SyncExternal(ent)

    return true -- apply the changes
end

--------------------------------------------------------------------------------

local warned = {}

function Internal.WarnOnce(id, topic, format, ...)
    local key = tostring(id) .. "." .. tostring(topic)
    if warned[key] then return end
    warned[key] = true
    Omerta.Log.Warn("weapons", format, ...)
end

-- Installed from sv_weapons.lua's OnEnable, which is the module's ONE
-- lifecycle method. See this file's header for why that matters.
function Internal.InstallExternal()
    if not Omerta.InEngine then return end

    Internal.ResolveExternalClasses(true)

    hook.Add("EntityFireBullets", "omerta.weapons.external_fire", function(ent, data)
        return Internal.OnExternalFireBullets(ent, data)
    end)

    -- The addon may not have registered its classes yet.
    --
    -- Our OnEnable runs from GM:Initialize, and an addon is free to build
    -- itself later. Resolution is a handful of table lookups; doing it twice
    -- costs nothing and removes a whole class of "it works on my listen
    -- server". The same recheck sh_environment.lua does, for the same reason.
    hook.Add("InitPostEntity", "omerta.weapons.external_recheck", function()
        Internal.ResolveExternalClasses(false)
        for _, ply in ipairs(player.GetAll()) do
            Internal.Reconcile(ply)
        end
    end)
end

-- A Lua auto-refresh rebuilds the registry, so the choice has to be made again
-- — otherwise a developer who has just mounted the ARC9 pack and refreshed is
-- still holding our own SMG. MODULE:OnReload is not defined anywhere else in
-- this module; sv_weapons.lua owns OnEnable and this owns OnReload, which is
-- one definition each and satisfies the lint.
function MODULE:OnReload()
    Internal.ResolveExternalClasses(true)
end
