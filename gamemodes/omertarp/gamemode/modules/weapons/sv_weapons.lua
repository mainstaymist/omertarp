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
-- Where a gun rides when it is not in a hand
--------------------------------------------------------------------------------
-- THE SIDEARM'S NUMBERS ARE EYEBALLED. They were set by hanging a w_357 off a
-- citizen model and looking at it, not measured against anything, and Track E's
-- art pass owns them properly. That is exactly why they are one table with one
-- comment rather than six constants buried in the function that spawns the
-- props: a pass over the hang of a Thompson should be a pass over six numbers
-- in one place — which is what the primary's pass, below, turned out to be.
--
-- THE PRIMARY'S ARE NOT EYEBALLED ANY MORE, and could not be: nobody who can
-- edit this file can see the result. They are derived from a stated frame and a
-- stated field observation, and every one of them says what it is for. The
-- derivation is directly below and it is as much the deliverable as the numbers
-- — a number nobody can check is worth nothing without the reasoning that says
-- how to check it.
--
-- Plain number triples rather than Vector/Angle literals because this file
-- loads under the headless suite, where neither type exists.
--
--------------------------------------------------------------------------------
-- THE FRAME THESE NUMBERS ARE IN, WHICH IS THE ONLY THING THAT MAKES THEM
-- READABLE AT ALL
--------------------------------------------------------------------------------
-- SetLocalPos and SetLocalAngles on a bone-following prop are in the BONE's
-- frame, not the world's and not the player's. A ValveBiped bone's axes are
-- whatever the rig's author left them as, and for the spine chain they are not
-- x-forward/z-up — so "3" in the third slot is not "3 units up" and no amount of
-- staring at the numbers will say what it is.
--
-- The frame below was DERIVED, not looked up, and the derivation is the one
-- measurement anybody has taken of it: the field report on the values these
-- replace. Those were pos {-7, 1, 3}, ang {12, 0, 165}, and the gun they
-- produced was reported as "on the player's left buttcheek pointing down and
-- inside the player". Read that backwards:
--
--   * ang {12, 0, ...} points the prop's forward almost exactly along the
--     bone's +X, because pitch and yaw alone decide forward and 12 degrees is
--     nearly none. That forward was observed pointing DOWN. So on Spine2,
--     BONE +X RUNS DOWN THE SPINE, toward the pelvis.
--
--   * pos -7 on that axis is therefore 7 units UP — the shoulder blades. A
--     28-unit weapon hanging muzzle-down from there descends through the torso
--     and comes out around the backside, which is precisely the gun that was
--     reported, and it also explains "inside the player" without needing a
--     second mistake to explain it.
--
--   * that leaves +1 and +3 on the other two axes to account for "left" and for
--     the clipping. +3 is the better candidate for the three units of LEFT that
--     were actually visible, and +1 for one unit of depth that was nowhere near
--     enough to clear a back. So: BONE +Z IS THE MODEL'S LEFT, BONE +Y IS OUT OF
--     THE BACK. (Those two, with +X down, are a right-handed set, which is the
--     one thing here that is arithmetic rather than inference.)
--
-- So, for ValveBiped.Bip01_Spine2, and for the numbers below:
--
--     pos[1]  +down the spine       pos[2]  +out of the back   pos[3]  +left
--     ang[1]  pitch, about pos[2]   ang[2]  yaw               ang[3]  roll
--
-- THE PART THAT IS INFERRED RATHER THAN OBSERVED is which of pos[2] and pos[3]
-- is depth and which is lateral — the report only ever said "left" and "inside",
-- and 1 and 3 are both small. So it is written down here as a claim with its two
-- possible failures NAMED, because a wrong number that says how it is wrong
-- costs one look and a one-line edit, and a wrong number that says nothing costs
-- another round trip to somebody with the game open.
--
--   * The gun rides on the back but canted to the player's LEFT. Then the
--     lateral axis is mirrored and everything else stands: negate the cant,
--     which with the cant carried in the pitch means 150 -> 210 (still muzzle
--     up, tilted the other way).
--
--   * The gun stands OFF the back at an angle, or lies flat but sunk into it.
--     Then pos[2] and pos[3] have swapped jobs: depth is the third slot and
--     lateral is the second, so the pitch is tilting the muzzle out of the back
--     instead of across it. That is a two-line fix and both lines are here —
--     pos { 6, 0, -5 }, ang { 180, 30, 180 }: pitch 180 is straight up the
--     spine and the 30 degrees of cant moves into the yaw.
--
-- Nothing outside those two can be wrong, because pos[1] and the pitch flip are
-- pinned by the observation above rather than inferred from it.
--------------------------------------------------------------------------------
local HOLSTER = {
    -- CENTRE OF THE BACK, RUNNING DIAGONALLY UP TO THE RIGHT, MUZZLE UP.
    -- (Project lead, 2026-08-02, replacing "muzzle down past the left hip",
    -- which is the pose the numbers above produced and nobody wanted.)
    --
    -- Spine2 is the upper back on every ValveBiped rig, which is every player
    -- model the gamemode ships. The bone does not move.
    --
    --   pos[1] = 6   SIX UNITS DOWN THE SPINE from Spine2, so the weapon's
    --     receiver — which is roughly where a w_ model's origin sits — lands at
    --     the middle of the back. With the muzzle up, the gun grows UPWARD from
    --     its origin: a Thompson's twenty-odd units of barrel then reach the top
    --     of the shoulder rather than a foot above the player's head, and its
    --     stock hangs to about the belt. This is the number that depends on the
    --     MODEL's length, so it is the number to revisit when §4b's ruling
    --     changes what model is hanging there.
    --
    --   pos[2] = 5   FIVE UNITS OUT OF THE BACK, and this is the fix for
    --     "inside the player". It was 1, which put the prop's centre-line
    --     inside the torso and left the gun to clip its way out. Spine2 to the
    --     skin of the back is about four units on a citizen frame; five puts
    --     the gun a unit proud of the coat, which is where a sling holds it.
    --     Too small and it sinks; too large and it floats. It is the one number
    --     here that is a body measurement rather than a geometric one.
    --
    --   pos[3] = 0   DEAD CENTRE. The lead asked for the centre of the back and
    --     this is that request, whole: the mount point is on the spine and every
    --     bit of the diagonal comes from the ANGLES. That decomposition is the
    --     point — a mount is a place and a cant is a rotation, and mixing the
    --     two is how the old numbers ended up with a lateral offset AND a roll
    --     both half-doing the same job.
    --
    --   ang[1] = 150  PITCH, and it is doing two things at once, which is why
    --     it moved so far from 12. Under the frame above, pitch 12 pointed the
    --     muzzle down the spine; 180 minus a pitch reverses it. So 180 would be
    --     straight up the spine, and 180 - 30 = 150 is straight up the spine
    --     TILTED 30 DEGREES TOWARD THE MODEL'S RIGHT. That tilt is the diagonal:
    --     butt low and left, muzzle high and right, which is how a long gun
    --     actually rides on a back. Thirty degrees rather than forty-five
    --     because a Thompson is long and the steeper the cant the further the
    --     muzzle swings off the shoulder into open air.
    --
    --   ang[2] = 0    YAW, unused and deliberately left at zero. With the cant
    --     expressed as pitch, yaw would only swing the muzzle away from the
    --     player's back — which is the one direction nothing about a slung
    --     weapon wants to go. A second non-zero rotation here would make the
    --     pose impossible to reason about from the numbers, which is the state
    --     this table was in.
    --
    --   ang[3] = 180  ROLL: which way up the weapon lies against the back. Roll
    --     never changes where the muzzle points, only how the gun is spun about
    --     its own barrel, so it is free to be chosen for one thing — keeping the
    --     FLAT of the weapon against the player. At 180 the thin axis faces out
    --     of the back (so the gun stands off the body as little as pos[2]
    --     allows) and the magazine and grip hang toward the right flank rather
    --     than digging into the left shoulder blade, which is what 0 does. It
    --     was already 165, so this is the one number that was very nearly right.
    primary = {
        bone = "ValveBiped.Bip01_Spine2",
        pos  = { 6, 5, 0 },
        ang  = { 150, 0, 180 },
    },
    -- On the right hip, pointing at the ground, where a holster sits.
    --
    -- UNTOUCHED, deliberately. The field report names one thing wrong and it is
    -- the primary; the sidearm was not mentioned, which is the only evidence
    -- anybody has about it and it says it is fine. A thigh bone is a different
    -- frame from a spine bone besides — the derivation above is about Spine2 and
    -- claims nothing at all about R_Thigh — so "improving" these numbers by
    -- analogy would be replacing a pose somebody has actually looked at with one
    -- nobody has, which is the wrong direction to move.
    sidearm = {
        bone = "ValveBiped.Bip01_R_Thigh",
        pos  = { 2, 4, 1 },
        ang  = { -80, 8, 0 },
    },
    -- No melee entry on purpose: nothing in the arsenal occupies that slot
    -- yet, and inventing where a knife hangs before there is a knife is
    -- guessing at an art pass twice over.
}

-- Mirrors sv_treatment's rule exactly, and deliberately: two systems that both
-- mean "you walked away from what you were doing" must not disagree about how
-- far away that is.
local LEAVE_DISTANCE = 64

-- How often the holster props and the reserve count are reconciled. A quarter
-- second rather than every frame: both answer questions that change when a
-- player presses a key, and a frame's lag on a gun appearing on a back is
-- invisible where a per-frame rebuild across every player is not.
local RECONCILE_INTERVAL = 0.25

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
    -- The class the weapon is actually running: ours, or the third party's the
    -- arsenal named and this server turned out to have. Everything below is
    -- written against the resolved answer rather than against `def.class`, and
    -- that is the entire cost of the seam on this path.
    local class = Omerta.Weapons.ClassOf(def)
    if ply:HasWeapon(class) then return end

    local wep = ply:Give(class)
    if IsValid(wep) then
        wep.OmertaInstance = row.id
        -- Set on the ENTITY for an external class, where our own generated
        -- classes carry it on the class table. It is what the reconcile, the
        -- holster props and M15's provenance all read, and a third party's
        -- SWEP has no reason to mind an extra Lua field.
        wep.OmertaId = def.id
        -- Given EMPTY, always. Rounds are items; the clip is filled by
        -- reloading from what the character actually carries.
        --
        -- Through the bridge's setter rather than straight, because a base we
        -- have never read is entitled to have opinions about SetClip1 and an
        -- addon's opinion must not be able to error out of a give.
        if Internal.SetClipSafely then
            Internal.SetClipSafely(wep, 0)
        else
            wep:SetClip1(0)
        end
        if Internal.ExternalAfterGive then
            Internal.ExternalAfterGive(ply, wep, def)
        end
    end

    -- The readout is right the moment the gun appears, rather than a quarter
    -- second later when the reconcile timer next looks.
    Internal.PushReserve(ply)
end

-- Rounds in the clip go back into the pocket they came from. `force` skips the
-- room check deliberately: this ammunition was on the character's person a
-- moment ago, inside the gun, so refusing it now would delete real objects.
--
-- For a third party's SWEP the amount is clamped to what the bridge last
-- vouched for (`RefundableClip`): `Clip1` on a magazine model we have never
-- read is a number we did not write, and refunding a number we did not write
-- is how strip-and-re-equip mints ammunition.
local function refundClip(ply, wep, def)
    if not (IsValid(ply) and IsValid(wep) and def) then return end
    -- Puts the projected pool down. Harmless for our own weapons, which have
    -- no engine ammo type at all (D-004: `Ammo = "none"`), so there is one
    -- path here rather than two.
    if Internal.ExternalBeforeStrip then
        Internal.ExternalBeforeStrip(ply, wep, def)
    end
    local held = select(2, pcall(wep.Clip1, wep))
    local rounds = Omerta.Weapons.RefundableClip(held, wep.OmertaCommitted,
        Omerta.Weapons.IsExternal(def))
    if Internal.SetClipSafely then
        Internal.SetClipSafely(wep, 0)
    else
        wep:SetClip1(0)
    end
    wep.OmertaClipSeen, wep.OmertaCommitted = 0, 0
    if rounds <= 0 then return end
    Omerta.Inventory.Add(ply, def.ammo, rounds, { force = true }, function(ok, err)
        if not ok then
            Omerta.Log.Error("weapons", "could not refund %d round(s) of %s: %s",
                rounds, def.ammo, tostring(err))
        end
    end)
end

local function stripOne(ply, def)
    if not (IsValid(ply) and def) then return end
    local class = Omerta.Weapons.ClassOf(def)
    local wep = ply:GetWeapon(class)
    if IsValid(wep) then
        refundClip(ply, wep, def)
        ply:StripWeapon(class)
        -- Empty hands hold no caliber, so the count that was on screen a
        -- moment ago is now about a gun the character no longer has.
        Internal.PushReserve(ply)
        if Internal.SyncExternal then Internal.SyncExternal(ply) end
    end
end

-- The full reconciliation: hands match equipped rows, exactly. Run whenever
-- the answer could have changed wholesale — a character load, standing back
-- up — where the per-item hooks below handle the ordinary single changes.
function Internal.Reconcile(ply)
    if not IsValid(ply) then return end
    local character = Omerta.Characters.Get(ply)
    if not character then return end

    -- Hands before anything else: they are the holster. Stripping a weapon
    -- with nothing to switch to leaves the engine holding NULL, and "put it
    -- away" needs somewhere for away to be.
    if not ply:HasWeapon(Omerta.Weapons.HANDS) then
        ply:Give(Omerta.Weapons.HANDS)
    end

    local desired = {} -- class -> { row, def }
    if not Omerta.Injury.IsPlayerDown(ply) then
        for _, row in ipairs(Omerta.Inventory.Get(ply) or {}) do
            if row.equipped_slot then
                local def = Omerta.Weapons.ForItem(row.def_id)
                -- Keyed by the RESOLVED class. Keying by ours would strip a
                -- third party's SWEP on the first sweep after giving it, one
                -- quarter second later, forever.
                if def then
                    desired[Omerta.Weapons.ClassOf(def)] = { row = row, def = def }
                end
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

    -- The holster props are NOT settled here; see their own section for why
    -- the reconcile timer is their only owner.
    Internal.PushReserve(ply)
    if Internal.SyncExternal then Internal.SyncExternal(ply) end
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
        local found = nil
        for _, row in ipairs(Omerta.Inventory.Get(ply) or {}) do
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

    -- The player goes straight into Get, which normalises a Player itself.
    -- OwnerOf returns a type/id PAIR, not a descriptor — feeding its first
    -- return back into Get is how reloading once read every pocket as empty.
    local available = 0
    for _, row in ipairs(Omerta.Inventory.Get(ply) or {}) do
        if row.def_id == def.ammo then available = available + row.quantity end
    end

    local take = Omerta.Weapons.PlanReload(def.clip, wep:Clip1(), available)
    if take <= 0 then
        -- ONE refusal per press, not one per frame.
        --
        -- The engine calls SWEP:Reload every tick for as long as +reload is
        -- held, and a successful reload is throttled by its own animation
        -- lockout — but this path returns before that lockout is set, so
        -- holding R with empty pockets filled the chat with the same sentence
        -- sixty times a second.
        --
        -- The press edge is derived from the CALL PATTERN rather than from the
        -- key, because there is nowhere server-side that sees the key go up: a
        -- SWEP has no Think here, and adding a per-frame sweep over every
        -- player to watch one bit would cost more than the message it is
        -- suppressing. Held, the calls arrive a tick apart; released and
        -- pressed again, there is a gap. A gap wider than several ticks is a
        -- new press, and tapping R twice deliberately still says it twice.
        local now = CurTime()
        local fresh = now - (wep.OmertaLastReloadCall or 0) > 0.2
        wep.OmertaLastReloadCall = now
        if fresh and wep:Clip1() < def.clip then
            local ammoDef = Omerta.Items.Get(def.ammo)
            Omerta.Chat.Notice(ply, "You are out of "
                .. string.lower(ammoDef and ammoDef.name or "ammunition") .. ".")
        end
        return
    end
    wep.OmertaLastReloadCall = CurTime()

    -- WHICH RELOAD THIS IS, decided once and used for both halves — the clock
    -- the server enforces and the animation that has to fit inside it. The clip
    -- is still the PRE-reload one on this line, which is what makes the
    -- question answerable: an empty gun is one whose working parts are locked
    -- back, and it is slower to bring back into the fight than a topped-up one.
    --
    -- A gun whose art draws no distinction, or that has never been read, has
    -- one duration and one sequence, and ReloadDuration/AnimEntry each answer
    -- with it — so nothing on this path has to know which kind of weapon it is
    -- holding.
    local empty = wep:Clip1() <= 0
    local event = empty and "reload_empty" or "reload"
    local seconds = Omerta.Weapons.ReloadDuration(def, empty)

    wep.OmertaReloadUntil = CurTime() + seconds
    wep:SetNextPrimaryFire(CurTime() + seconds)

    -- The activity first, exactly as before, so a weapon with no animation
    -- block is byte-for-byte the weapon it was. Then the named sequence, which
    -- overrides it and only exists for a weapon that asked.
    --
    -- SERVER-SIDE, and it has to be: the client presses R, but whether a reload
    -- HAPPENS is decided here, against rows in a pocket. A client that animated
    -- its own reload would animate the ones that were refused.
    --
    -- `fit` is where the two clocks meet, and a reload is one of the only two
    -- events that HAS one: the number above wins — it is a balance number
    -- argued for in the arsenal and it gates real inventory work — and the
    -- animation is stretched to it with SetPlaybackRate. Firing is the opposite
    -- case and is never fitted at all; both arguments are in
    -- sh_weapons_anim.lua's ANIM_RATE header.
    wep:SendWeaponAnim(ACT_VM_RELOAD)
    Internal.PlayAnim(wep, def, event, { fit = seconds })
    -- The foley is a WORLD sound on the weapon entity, so everybody in earshot
    -- gets it. Nothing today declares one, and a weapon that declares none is
    -- silent here exactly as it is now.
    Internal.PlayAnimSound(wep, def, event)

    -- The public half, and the only thing an observer sees of a reload: the
    -- gesture on the player model. Unchanged.
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
        -- Rounds left the pockets either way; the readout has to say so.
        Internal.PushReserve(ply)
    end)
end

--------------------------------------------------------------------------------
-- What is left in the pocket
--------------------------------------------------------------------------------
-- The counterpart to the clip: a character can count the rounds they are
-- carrying for the gun in their hand, which is knowledge the fiction grants,
-- and cl_weapons decides when that is worth showing. Pushed rather than
-- polled, because what is in a pocket is M9's truth and the client has nothing
-- to count it with.

local lastReserve = {} -- SteamID64 -> the number last sent

-- Rounds of one caliber on this character.
--
-- The player goes STRAIGHT into Get, which normalises a Player itself.
-- OwnerOf returns a type/id PAIR, not a descriptor — the trap this file
-- already documents once above, and the reason reloading read every pocket as
-- empty for a week.
function Internal.ReserveOf(ply, ammoId)
    if not (IsValid(ply) and ammoId) then return 0 end
    local total = 0
    for _, row in ipairs(Omerta.Inventory.Get(ply) or {}) do
        if row.def_id == ammoId then total = total + row.quantity end
    end
    return total
end

-- Rounds of the HELD weapon's caliber, on this character. Nothing else is a
-- reserve: the .45 in a coat is not this revolver's ammunition, and saying
-- otherwise would make the readout a lie exactly when it matters.
--
-- Resolved by CLASS rather than by `wep.OmertaId`, because a third party's
-- SWEP carries no class-table id of ours — the entity field giveOne stamps is
-- server-side only, and this same reading is wanted on the client.
function Internal.ReserveFor(ply)
    if not IsValid(ply) then return 0 end
    local wep = ply:GetActiveWeapon()
    local def = IsValid(wep) and Omerta.Weapons.ForClass(wep:GetClass())
    if not def then return 0 end
    return Internal.ReserveOf(ply, def.ammo)
end

function Internal.PushReserve(ply)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    local key = ply:SteamID64() or ""
    -- Clamped to what the wire carries. A pocket holding more than 65535
    -- rounds is a bug somewhere else, and the message must not be the thing
    -- that errors over it.
    local count = math.min(65535, Internal.ReserveFor(ply))

    -- Only on a change. A single reload has three honest reasons to ask (the
    -- consume callback, the give, the reconcile timer) and they mostly agree,
    -- so without this the cheapest message in the module becomes the loudest.
    if lastReserve[key] == count then return end
    lastReserve[key] = count
    Omerta.Net.Send("weapons.reserve", { count = count }, ply)
end

function Internal.ForgetReserve(ply)
    lastReserve[ply:SteamID64() or ""] = nil
end

--------------------------------------------------------------------------------
-- Drawing: the equip that takes time
--------------------------------------------------------------------------------
-- M9's Equip is instant, and for a coat or a hat that is right — putting a hat
-- on is not a thing anybody needs to be able to interrupt. A gun is different:
-- getting one out from under a coat is a commitment the street can watch, and
-- the second it costs is the whole point.
--
-- Nothing here writes a row. Until the timer runs out the character owns an
-- unequipped item and holds nothing, so every cancel below is free — there is
-- no half-equipped state to unwind and no way for an interrupted draw to leave
-- a gun anywhere.

local equipping = {} -- SteamID64 -> { ply, instanceId, weaponId, startedAt, finishAt, startPos, cb }

local function keyFor(ply)
    return IsValid(ply) and (ply:SteamID64() or "") or ""
end

-- The row a draw is about, or nil once it stops being theirs to draw.
local function rowFor(ply, instanceId)
    for _, row in ipairs(Omerta.Inventory.Get(ply) or {}) do
        if row.id == instanceId then return row end
    end
    return nil
end

-- Public: everything that ends a draw early ends it here — the tick, the
-- disconnect, going down, and a second request replacing the first.
function Internal.CancelEquip(ply, reason)
    local key = keyFor(ply)
    local entry = equipping[key]
    if not entry then return end
    equipping[key] = nil

    if IsValid(ply) then
        -- The public half goes down first. A man who has stopped reaching must
        -- stop looking like he is reaching whatever else fails afterwards.
        ply:SetNWBool("OmertaDrawing", false)
        Omerta.Net.Send("weapons.equip_end",
            { instance = entry.instanceId, completed = false }, ply)
    end
    -- The caller is M9's action handler, which turns this into a notice and a
    -- refresh — the same refusal path a full pocket or a locked crate takes.
    if entry.cb then entry.cb(false, reason or "you stop") end
end

function Internal.BeginEquip(ply, instanceId, weapon, cb)
    -- Draws never stack. A second request — the same gun twice, or the other
    -- one — REPLACES the first, so leaning on the equip button ends with one
    -- draw running rather than a queue of them all landing at once. The
    -- refusal the first request gets says which of the two happened, because
    -- "you started over" and "you changed your mind" read as different
    -- mistakes to the person who made one.
    local running = equipping[keyFor(ply)]
    Internal.CancelEquip(ply, running and running.instanceId == instanceId
        and "you start over" or "you reach for something else")

    local duration = Omerta.Weapons.EquipDuration(weapon)
    local now = CurTime()
    equipping[keyFor(ply)] = {
        ply = ply,
        instanceId = instanceId,
        weaponId = weapon.id,
        startedAt = now,
        finishAt = now + duration,
        -- Where the commitment was made, so walking out of it is measurable
        -- against a point rather than against a moving player.
        startPos = ply:GetPos(),
        cb = cb,
    }

    -- Deliberately PUBLIC state, and the only public thing a draw produces: a
    -- man reaching into his coat is visible from across the street, so the
    -- fact is already in the world. It says somebody is reaching — never what
    -- for, never whose gun, never an instance id — so it carries nothing D-033
    -- keeps server-side, and the hint other clients draw off it is the same
    -- information a witness would have anyway.
    ply:SetNWBool("OmertaDrawing", true)

    Omerta.Net.Send("weapons.equipping", {
        instance = instanceId,
        millis = math.min(65535, math.floor(duration * 1000 + 0.5)),
    }, ply)
end

local function completeEquip(ply, entry)
    equipping[keyFor(ply)] = nil
    if IsValid(ply) then
        ply:SetNWBool("OmertaDrawing", false)
        Omerta.Net.Send("weapons.equip_end",
            { instance = entry.instanceId, completed = true }, ply)
    end
    -- And now the real thing: M9's own Equip, with its row write, its one-per-
    -- slot rule and the ItemEquipped seam that puts the SWEP in the hand. The
    -- delay is a gate in front of that door, never a second version of it.
    Internal.RealEquip(ply, entry.instanceId, entry.cb or function() end)
end

-- Called every frame from the module's Think, exactly as sv_treatment's
-- timed actions are. The four ways a draw dies are the four ways a treatment
-- does, plus the one a treatment cannot have: the thing being reached for
-- leaving the character's pockets.
function Internal.TickEquips()
    local now = CurTime()
    for key, entry in pairs(equipping) do
        local ply = entry.ply
        if not IsValid(ply) then
            equipping[key] = nil
        elseif ply:GetPos():Distance(entry.startPos) > LEAVE_DISTANCE then
            Internal.CancelEquip(ply, "you moved away")
        elseif Omerta.Injury.IsIncapable(Omerta.Injury.Get(ply)) then
            -- IsIncapable, not IsPlayerDown: IsDown is incapacitated-or-
            -- stabilized only, and a draw that survived its owner dying would
            -- complete into a row belonging to a character who no longer has
            -- hands. The state change hook cancels first in practice; this is
            -- the guarantee, not the mechanism.
            Internal.CancelEquip(ply, "you went down")
        elseif not rowFor(ply, entry.instanceId) then
            -- Dropped, handed over, or taken off them mid-reach. A draw is
            -- about one particular object and that object has gone.
            Internal.CancelEquip(ply, "it is not yours to draw")
        elseif now >= entry.finishAt then
            completeEquip(ply, entry)
        end
    end
end

-- The interception.
--
-- M9's Equip is the ONE door every path to an equipped row goes through — the
-- inventory action today, a quick-draw bind or a staff tool tomorrow — so
-- wrapping it is what makes "a weapon takes time" true everywhere rather than
-- true in the inventory window. Coats, hats and food are handed straight
-- through untouched: only a definition carrying `weapon` waits.
--
-- Rejected: a new hook in M9. The seam would have to mean "something may defer
-- an equip and finish it later", which is a larger idea than weapons needs and
-- would leave the inventory module carrying a concept of a pending action it
-- has no other use for. Wrapping keeps the whole notion of a draw inside the
-- module that has one.
function Internal.InstallEquipDelay()
    -- Once, ever. A Lua auto-refresh re-runs OnEnable, and a wrapper around
    -- the wrapper would make every draw take two of everything.
    if Internal.RealEquip then return end
    Internal.RealEquip = Omerta.Inventory.Equip

    Omerta.Inventory.Equip = function(ply, instanceId, cb)
        cb = cb or function() end
        if not IsValid(ply) then return Internal.RealEquip(ply, instanceId, cb) end

        local row = rowFor(ply, instanceId)
        local def = row and Omerta.Items.Get(row.def_id)
        local weapon = def and def.weapon and Omerta.Weapons.Get(def.weapon)
        -- Not a weapon, not theirs, or already worn: the ordinary path answers
        -- all three better than a guess here would, refusal wording included.
        if not weapon or row.equipped_slot then
            return Internal.RealEquip(ply, instanceId, cb)
        end
        -- A man on the floor is not reaching for anything, and neither is a
        -- dead one. Said here rather than left to the tick so the refusal is
        -- immediate and legible.
        if Omerta.Injury.IsIncapable(Omerta.Injury.Get(ply)) then
            cb(false, "you cannot reach it from down here")
            return
        end

        Internal.BeginEquip(ply, instanceId, weapon, cb)
    end
end

--------------------------------------------------------------------------------
-- Holstered weapons, on the body
--------------------------------------------------------------------------------
-- A gun that is equipped but not in the hands hangs where it would hang: a
-- Thompson across the back, a revolver on the right hip. This is the other
-- half of concealment being meaningful — D-014 lets a coat hide a sidearm, and
-- a slung Thompson is the design's own example of a thing everybody in the
-- street can read off you before you say a word.
--
-- Server-created props, parented to the player, so every client sees the same
-- thing without being told anything: the props ARE the message, and no net
-- traffic carries what anybody is carrying.
--
-- The reconcile timer is their ONLY owner, deliberately. The equip hook was
-- the obvious place to hang this and it is the wrong one: `Give` puts a weapon
-- in the list, and whether it also becomes the ACTIVE weapon is the engine's
-- decision, taken around the same frame — so refreshing on the event raced it
-- and flickered a revolver onto a hip that already had it in hand. Asking the
-- settled answer four times a second is both simpler and correct, and a
-- quarter second of lag on a gun appearing on a back is not a thing anybody
-- can see.

local holsters = {}      -- SteamID64 -> array of prop entities
local holsterState = {}  -- SteamID64 -> the signature those props were built for

local function clearHolsters(ply)
    local key = keyFor(ply)
    for _, ent in ipairs(holsters[key] or {}) do
        if IsValid(ent) then ent:Remove() end
    end
    holsters[key] = nil
    holsterState[key] = nil
end

local function attachHolster(ply, weapon)
    local spec = weapon and HOLSTER[weapon.slot or ""]
    if not spec then return nil end

    -- A model whose skeleton has no such bone gets nothing rather than a prop
    -- welded to the origin, which is what a bone index of nil produces.
    local bone = ply:LookupBone(spec.bone)
    if not bone then return nil end

    -- What the arsenal declares this weapon hangs on a body AS (D-039: adding a
    -- weapon is data, and that includes what it looks like on a back).
    --
    -- Through HolsterModel rather than off `weapon.worldModel` directly, and
    -- that indirection is the whole of what this change is allowed to do about
    -- the port plan's §4b. `worldModel` also decides what our own generated SWEP
    -- renders in a hand and what a dropped weapon lies on the pavement as, and
    -- §4b's ruling is about none of those — so the field it will move is now a
    -- field of its own. Today nothing declares one and the answer is still
    -- `worldModel`, unchanged, which is the point: the ruling stays open and
    -- lands as a data edit whichever way it goes.
    --
    -- A weapon whose model does not resolve gets NOTHING: ResolveModel's
    -- fallback is a wooden crate, and a crate strapped to a man's shoulder is a
    -- worse lie than an empty shoulder.
    local model = Omerta.Util.ResolveModel(Omerta.Weapons.HolsterModel(weapon))
    if not model or model == Omerta.Util.FALLBACK_MODEL then return nil end

    local ent = ents.Create("prop_dynamic")
    if not IsValid(ent) then return nil end
    ent:SetModel(model)
    ent:SetPos(ply:GetPos())
    ent:Spawn()

    -- Scenery, not an object. It must not stop a bullet meant for the man
    -- wearing it, block the interaction trace that looks him in the face, or
    -- be pickable up off his back.
    ent:SetSolid(SOLID_NONE)
    ent:SetMoveType(MOVETYPE_NONE)
    ent:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    ent:SetOwner(ply)

    -- FollowBone, not SetParent(ply, index).
    --
    -- SetParent's second argument is an ATTACHMENT index, and a player model's
    -- attachments are eyes, anim_attachment_head and forward — there is no
    -- "back" or "hip" among them, so parenting that way leaves a Thompson
    -- floating at the model's origin. EF_BONEMERGE was rejected for the
    -- neighbouring reason: it merges the prop's skeleton INTO the parent's,
    -- which is right for clothing built on the player rig and nonsense for a
    -- gun, which shares no bone names with a man. A clientside model was
    -- rejected too — it would need the carried state networked to every client
    -- to be built from, which is the exact traffic a server prop avoids by
    -- simply existing.
    ent:SetParent(ply)
    ent:FollowBone(ply, bone)
    ent:SetLocalPos(Vector(spec.pos[1], spec.pos[2], spec.pos[3]))
    ent:SetLocalAngles(Angle(spec.ang[1], spec.ang[2], spec.ang[3]))
    return ent
end

-- What SHOULD be hanging off this player, as one comparable string.
--
-- Derived from the WEAPONS the player holds rather than from the equipped
-- rows, because those SWEPs are already the reconciled projection of the rows
-- — so the props cannot disagree with the hands, including while down, when
-- there are no weapons at all.
local function holsterSignature(ply)
    -- Belt and braces with the strip: going down and dying both empty the
    -- hands through Reconcile, which would empty this by itself, but a gun
    -- left hanging on a corpse because one strip was missed is the kind of
    -- thing players screenshot.
    if Omerta.Injury.IsIncapable(Omerta.Injury.Get(ply)) then return "" end

    local active = ply:GetActiveWeapon()
    local activeClass = IsValid(active) and active:GetClass() or ""
    local ids = {}
    for _, wep in ipairs(ply:GetWeapons()) do
        -- What is in the hands is not on the hip. Compared by class rather
        -- than by entity so a weapon re-given mid-frame cannot read as two.
        --
        -- Resolved by class for the same reason the hotbar and the readout
        -- are: one rule for "is this gun one of ours", so a weapon running a
        -- third party's SWEP hangs off a back exactly as our own does.
        local def = wep:GetClass() ~= activeClass
            and Omerta.Weapons.ForClass(wep:GetClass()) or nil
        if def then ids[#ids + 1] = def.id end
    end
    table.sort(ids) -- deterministic, or an unchanged loadout rebuilds forever
    return table.concat(ids, ",")
end

function Internal.RefreshHolsters(ply)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    local key = keyFor(ply)
    local signature = holsterSignature(ply)
    -- The comparison is the whole optimisation: props are torn down and rebuilt
    -- only when the answer actually changed, so the timer below costs one
    -- string per player per quarter second.
    if holsterState[key] == signature then return end

    clearHolsters(ply)
    holsterState[key] = signature
    if signature == "" then return end

    local made = {}
    for id in string.gmatch(signature, "[^,]+") do
        local ent = attachHolster(ply, Omerta.Weapons.Get(id))
        if IsValid(ent) then made[#made + 1] = ent end
    end
    holsters[key] = made
end

--------------------------------------------------------------------------------
-- Reading somebody else's model
--------------------------------------------------------------------------------

-- Every sequence in a model, by name, with how long it runs.
--
-- Spawned, read and removed inside one call. A `prop_dynamic` is used rather
-- than a ClientsideModel because this has to work from a dedicated server's
-- console, where there is no renderer at all — and the sequence table is
-- model data, not a rendering of it.
--
-- Names, not indices. An index is a position in a table that shifts the next
-- time the artist adds an animation; a name that stops existing can be
-- reported. Everything the port builds will be keyed by name for that reason,
-- so the dump prints what the port will consume.
function Internal.DumpSequences(model)
    if not Omerta.InEngine then return end

    if not util.IsValidModel(model) then
        Omerta.Log.Info("weapons", "  model is not mounted on this server: %s", model)
        return
    end

    local probe = ents.Create("prop_dynamic")
    if not IsValid(probe) then return end
    probe:SetModel(model)
    probe:Spawn()

    local count = probe:GetSequenceCount() or 0
    if count <= 0 then
        -- The interesting negative result, and worth saying in full: a model
        -- with no sequences of its own is one whose motion comes from
        -- somewhere else, which is the case the port cannot absorb cheaply.
        Omerta.Log.Info("weapons", "  NO SEQUENCES — this model is animated " ..
            "from outside itself (procedural bones), not from baked animation")
        probe:Remove()
        return
    end

    -- The bodygroups, before the sequences, because they are short and because
    -- they are now load-bearing: the arsenal builds holster props out of these
    -- `c_` viewmodels (the port plan's §4b option (a)), and a `c_` model
    -- standing on its own as a prop shows whatever its reference pose has in it
    -- — commonly a pair of arms. If one of the groups below turns the arms off,
    -- that is a data edit in the arsenal and the problem is solved; if there is
    -- no such group, the honest answer is real `w_` models and we know that too.
    --
    -- Printed rather than acted on. Which SUBMODEL of a group is "no arms" is
    -- not something a name tells us, and the port does not guess.
    local groups = probe:GetBodyGroups() or {}
    if #groups > 0 then
        Omerta.Log.Info("weapons", "  %d bodygroup(s):", #groups)
        for _, group in ipairs(groups) do
            Omerta.Log.Info("weapons", "    [%d] %-24s %d submodel(s)",
                tonumber(group.id) or -1, tostring(group.name),
                tonumber(group.num) or 0)
        end
    else
        Omerta.Log.Info("weapons", "  no bodygroups — nothing on this model can " ..
            "be switched off, so what it renders as a prop is what it renders")
    end

    Omerta.Log.Info("weapons", "  %d sequence(s):", count)
    for index = 0, count - 1 do
        local name = probe:GetSequenceName(index) or "?"
        -- Guarded: a sequence with no duration is legal and returns nil on
        -- some models, and a nil into a format string kills the whole dump on
        -- the one weapon somebody was trying to inspect.
        local ok, duration = pcall(probe.SequenceDuration, probe, index)
        Omerta.Log.Info("weapons", "    [%3d] %-32s %.3fs",
            index, name, (ok and tonumber(duration)) or 0)
    end

    probe:Remove()
end

--------------------------------------------------------------------------------
-- The hooks that keep hands and rows agreeing
--------------------------------------------------------------------------------

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    -- Which class each weapon actually runs, and the hooks a SWEP we did not
    -- write owes the rest of the game. Installed here rather than at file
    -- scope because resolution asks the engine what is registered, and
    -- OnEnable is the first moment every addon has finished registering.
    if Internal.InstallExternal then Internal.InstallExternal() end

    -- Hands from the first breath, not only once the inventory loads: the
    -- holster has to exist before there is anything to holster into it.
    hook.Add("PlayerSpawn", "omerta.weapons.hands", function(ply)
        if IsValid(ply) and not ply:HasWeapon(Omerta.Weapons.HANDS) then
            ply:Give(Omerta.Weapons.HANDS)
        end
    end)

    -- Equipping a WEAPON is a timed, interruptible draw; everything else M9
    -- can equip stays instant. Installed here rather than at file scope
    -- because it wraps another module's function, and OnEnable is the first
    -- moment every module is guaranteed to have finished defining its own.
    Internal.InstallEquipDelay()

    -- Draws are per-frame business, the way M19's timed actions are: a
    -- once-a-second check would let a man walk two strides out of a
    -- commitment before anything noticed.
    hook.Add("Think", "omerta.weapons.drawing", function()
        Internal.TickEquips()
    end)

    -- What hangs off a body and what the round readout says both follow from
    -- state nothing announces — a weapon becoming the active one is a keypress
    -- the engine handles by itself. So they are reconciled on a timer against
    -- the answer rather than hung off events that do not exist.
    -- The third-party bridge rides the SAME sweep, and deliberately: the
    -- engine's ammo pool is a projection of the M9 rows and it is re-written
    -- from them here, so a round entering or leaving a pocket by ANY route —
    -- picked up, bought, dropped, searched off a body — reaches the pool
    -- within a quarter second without M9 needing a hook it has no other use
    -- for. Give, strip and every shot fired settle it immediately besides.
    timer.Create("omerta.weapons.carried", RECONCILE_INTERVAL, 0, function()
        for _, ply in ipairs(player.GetAll()) do
            Internal.RefreshHolsters(ply)
            Internal.PushReserve(ply)
            if Internal.SyncExternal then Internal.SyncExternal(ply) end
        end
    end)

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
        -- Forgotten first, then pushed: the de-duplication remembers what this
        -- CONNECTION was last told, and a new character behind the same
        -- connection is a different set of pockets. Without this a man who
        -- died holding thirty rounds and came back with thirty of his own
        -- would be sent nothing at all, and a fresh empty one would keep the
        -- dead man's number on screen.
        Internal.ForgetReserve(ply)
        Internal.Reconcile(ply)
        Internal.PushReserve(ply)
    end)

    -- Going down empties the hands — the gun lands in the inventory where a
    -- search can find it, which is what makes disarming somebody a matter of
    -- putting them on the floor. Standing back up refills them.
    hook.Add("Omerta.InjuryChanged", "omerta.weapons.injury", function(characterId, from, to)
        local ply = Omerta.Injury.Internal.PlayerFor(characterId)
        if not IsValid(ply) then return end
        if Omerta.Injury.IsIncapable(to) then
            -- Immediately, rather than on the next tick: going down is the one
            -- interruption that is also somebody else's action, and it should
            -- land on the same frame the bullet did.
            Internal.CancelEquip(ply, "you went down")
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
            local def = Omerta.Weapons.ForClass(wep:GetClass())
            if def then refundClip(ply, wep, def) end
        end

        -- A draw interrupted by the front door. Nothing was written, so this
        -- only drops the entry and lets go of the player it was holding.
        Internal.CancelEquip(ply, "you left")
        -- Props parented to a leaving player are the engine's to clean up, but
        -- the tables that remember them are ours, and a SteamID64 that never
        -- comes back would keep its entry for the life of the server.
        clearHolsters(ply)
        Internal.ForgetReserve(ply)
        if Internal.ForgetExternal then Internal.ForgetExternal(ply) end
    end)

    -- The class column answers the question an operator who has just installed
    -- an addon actually has, which is "did it take" — so it prints what each
    -- weapon is RUNNING, and says when that is not what the arsenal asked for.

    -- Which weapon classes this server actually has.
    --
    -- "That class is not registered" has two completely different causes and
    -- they need completely different work: the addon is missing from the
    -- server, or the addon is there and the class is spelled differently from
    -- what somebody typed. A Workshop page title is not a class name, and a
    -- pack's guns are rarely named the way its description names them.
    --
    -- Listing what IS here tells the two apart in one command. No matches on
    -- "arc9" means the pack is genuinely absent; a list of arc9_* classes that
    -- does not include the one we asked for means the arsenal has a typo, and
    -- the fix is one data edit rather than a server rebuild.
    concommand.Add("omerta_weapon_classes", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end

        local filter = string.lower(args[1] or "")
        local found = 0
        for _, swep in ipairs(weapons.GetList() or {}) do
            local class = swep.ClassName or ""
            -- Ours are listed by omerta_weapons_list and would only bury the
            -- answer; this command exists to look at everybody else's.
            if class ~= "" and not class:find("^weapon_omerta_")
                and (filter == "" or string.lower(class):find(filter, 1, true)) then
                found = found + 1
                Omerta.Log.Info("weapons", "  %-40s %s",
                    class, tostring(swep.PrintName or ""))
            end
        end

        if found == 0 then
            Omerta.Log.Info("weapons", "no third-party weapon class matches '%s' " ..
                "— that pack is not mounted on this server", args[1] or "")
        else
            Omerta.Log.Info("weapons", "%d class(es) matching '%s'",
                found, args[1] or "")
        end
    end)

    -- What is actually inside somebody else's viewmodel.
    --
    -- The port plan (docs/review/06_weapon_art_port.md) turns on one question
    -- that cannot be answered by reading their Lua: are the animations BAKED
    -- SEQUENCES we can simply play, or does the addon drive bones procedurally
    -- every frame? A weapon whose feel is baked is a data-entry job; one whose
    -- feel is procedural means reimplementing a chunk of somebody else's
    -- framework, and those are different decisions.
    --
    -- A model spawned server-side answers it directly. `SEQUENCES` prints every
    -- animation the model actually contains with its name, duration and frame
    -- rate — which is also exactly what the reload timing and the equip
    -- ceremony have to line up against, so the same output serves both the
    -- decision and the work that follows it.
    --
    -- Takes a WEAPON CLASS, and reads the viewmodel off the registered SWEP
    -- table rather than being handed a path: the point is to inspect what a
    -- class really uses, and a path typed by hand is a path that can be wrong
    -- in a way nobody notices.
    concommand.Add("omerta_weapon_dump", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end

        local class = args[1]
        if not class or class == "" then
            Omerta.Log.Info("weapons", "usage: omerta_weapon_dump <weapon class>")
            return
        end

        local swep = weapons.Get(class)
        if not swep then
            Omerta.Log.Info("weapons", "no weapon class '%s' is registered — " ..
                "the addon is not mounted on the SERVER (resource.AddWorkshop " ..
                "only feeds clients)", class)
            return
        end

        -- Both, because they are frequently different models and the world one
        -- is what a holstered gun on somebody's back will be.
        for _, pair in ipairs({
            { "viewmodel", swep.ViewModel },
            { "worldmodel", swep.WorldModel },
        }) do
            local label, path = pair[1], pair[2]
            if not path or path == "" then
                Omerta.Log.Info("weapons", "%s: %s declares none", class, label)
            else
                Omerta.Log.Info("weapons", "%s %s: %s", class, label, path)
                Internal.DumpSequences(path)
            end
        end

        -- Read back and reported rather than assumed: ARC9 viewmodels usually
        -- carry their own hands, which decides whether our base should be
        -- drawing c_arms over the top of them.
        Omerta.Log.Info("weapons", "%s: UseHands=%s ViewModelFOV=%s HoldType=%s",
            class, tostring(swep.UseHands), tostring(swep.ViewModelFOV),
            tostring(swep.HoldType))
    end)

    concommand.Add("omerta_weapons_list", function(caller)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        for _, def in ipairs(Omerta.Weapons.All()) do
            local note = ""
            if def.external and not Omerta.Weapons.IsExternal(def) then
                note = "  (wanted " .. def.external .. ")"
            end
            Omerta.Log.Info("weapons", "  %-20s %-26s dmg %-3d clip %-2d  %s%s",
                def.id, Omerta.Weapons.ClassOf(def), def.damage, def.clip,
                def.ammo, note)
        end
    end)
end
