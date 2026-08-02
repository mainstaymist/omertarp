-- M14 crime, store robbery and NPC victims.
--
-- The five rulings are the thing that gets pinned hardest, because they are
-- what a later change would otherwise quietly reverse: the float is unowned-only
-- (D-048), the restart abandons rather than resumes (D-050), the mask cuts both
-- ways (D-051), and killing the clerk does not seal the register (D-052).
--
-- The reaction model gets the most attention of anything here, for a reason the
-- design review states plainly: a robbery you cannot get better at is a slot
-- machine with a gun in it. Determinism is the property that makes it learnable,
-- so determinism is what is tested.

local MODULE_FILES = {
    "gamemodes/omertarp/gamemode/modules/database/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/database/sh_database.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_schema.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_sqlbuild.lua",
    "gamemodes/omertarp/gamemode/modules/database/sv_database.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sh_accounts.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/accounts/sv_accounts.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sh_seasons.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/seasons/sv_seasons.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sh_characters.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/characters/sv_characters.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sh_gait.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sh_hud.lua",
    "gamemodes/omertarp/gamemode/modules/hud/sv_stamina.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sh_interaction.lua",
    "gamemodes/omertarp/gamemode/modules/interaction/sv_interaction.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sh_identity.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/identity/sv_identity.lua",
    "gamemodes/omertarp/gamemode/modules/chat/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/chat/sh_chat.lua",
    "gamemodes/omertarp/gamemode/modules/chat/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/chat/sv_chat.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_currency.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_hunger.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_inventory.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sh_items.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_hunger.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_inventory.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_money.lua",
    "gamemodes/omertarp/gamemode/modules/inventory/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sh_ladders.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sh_organizations.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sv_organizations.lua",
    "gamemodes/omertarp/gamemode/modules/organizations/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sh_ledger.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sh_procurement.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sh_supplies.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sv_procurement.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/treasury/sv_treasury.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sh_lines.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sh_phone.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sv_calls.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sv_phone.lua",
    "gamemodes/omertarp/gamemode/modules/phone/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/business/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/business/sh_business.lua",
    "gamemodes/omertarp/gamemode/modules/business/sh_rumours.lua",
    "gamemodes/omertarp/gamemode/modules/business/sh_venues.lua",
    "gamemodes/omertarp/gamemode/modules/business/sv_business.lua",
    "gamemodes/omertarp/gamemode/modules/business/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/business/sv_rumours.lua",
    "gamemodes/omertarp/gamemode/modules/business/sv_trade.lua",
    "gamemodes/omertarp/gamemode/modules/action/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/action/sh_action.lua",
    "gamemodes/omertarp/gamemode/modules/action/sv_action.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sh_injury.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sh_injury_falls.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sh_supplies.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_falls.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_injury.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_bodies.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_treatment.lua",
    "gamemodes/omertarp/gamemode/modules/injury/sv_actions.lua",
    "gamemodes/omertarp/gamemode/modules/events/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/events/sh_events.lua",
    "gamemodes/omertarp/gamemode/modules/events/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/events/sv_events.lua",
    "gamemodes/omertarp/gamemode/modules/death/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/death/sh_death.lua",
    "gamemodes/omertarp/gamemode/modules/death/sv_death.lua",
    "gamemodes/omertarp/gamemode/modules/weapons/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/weapons/sh_weapons.lua",
    "gamemodes/omertarp/gamemode/modules/weapons/sh_weapons_anim.lua",
    "gamemodes/omertarp/gamemode/modules/weapons/sh_weapons_arsenal.lua",
    "gamemodes/omertarp/gamemode/modules/weapons/sv_external.lua",
    "gamemodes/omertarp/gamemode/modules/weapons/sv_weapons.lua",
    "gamemodes/omertarp/gamemode/modules/crime/sh_module.lua",
    "gamemodes/omertarp/gamemode/modules/crime/sh_crime.lua",
    "gamemodes/omertarp/gamemode/modules/crime/sh_reactions.lua",
    "gamemodes/omertarp/gamemode/modules/crime/sh_mask.lua",
    "gamemodes/omertarp/gamemode/modules/crime/sv_repository.lua",
    "gamemodes/omertarp/gamemode/modules/crime/sv_mask.lua",
    "gamemodes/omertarp/gamemode/modules/crime/sv_operations.lua",
    "gamemodes/omertarp/gamemode/modules/crime/sv_alarm.lua",
    "gamemodes/omertarp/gamemode/modules/crime/sv_clerk.lua",
    "gamemodes/omertarp/gamemode/modules/crime/sv_take.lua",
    "gamemodes/omertarp/gamemode/modules/crime/sv_float.lua",
    "gamemodes/omertarp/gamemode/modules/crime/sv_crime.lua",
}

local function loadModules()
    ReloadCore()
    for _, f in ipairs(MODULE_FILES) do dofile(f) end
end

local function personality(id) return Omerta.Crime.GetPersonality(id) end

--------------------------------------------------------------------------------
suite("crime.states")
--------------------------------------------------------------------------------

check("the legal-move table is the design, and it refuses the rest", function()
    loadModules()
    local T = Omerta.Crime.CanTransition
    local S = Omerta.Crime.STATE

    assert(T(S.ACTIVE, S.ALARMED), "an alarm can be raised mid-job")
    assert(T(S.ACTIVE, S.ESCAPED), "or you get out clean")
    assert(T(S.ALARMED, S.ESCAPED), "AN ALARM DOES NOT END ANYTHING")
    assert(T(S.ACTIVE, S.FAILED) and T(S.ALARMED, S.FAILED))

    -- M17's two states attach with no migration, and only from a finished job.
    assert(T(S.ESCAPED, S.INVESTIGATING) and T(S.FAILED, S.INVESTIGATING))
    assert(T(S.INVESTIGATING, S.CLOSED))

    -- Neither terminal state is a verdict, and neither reverses.
    assert(not T(S.ESCAPED, S.ACTIVE), "a finished robbery does not restart")
    assert(not T(S.FAILED, S.ESCAPED), "and failure is not upgraded")
    assert(not T(S.CLOSED, S.INVESTIGATING), "a closed case stays closed")
    assert(not T(S.ALARMED, S.ACTIVE), "the alarm cannot be unrung")
    assert(not T(S.ACTIVE, S.ACTIVE), "and nothing transitions to itself")
end)

-- `planned` exists in the enum and M14 never enters it. Tech §16 says in as many
-- words not to require a planning UI for small crimes; C4's bank job is where a
-- plan becomes a real object, and it should not have to migrate an enum to say
-- so. Same discipline that put published_at in the events table a milestone
-- before M21 needed it.
check("planned is declared and unreachable, and that is deliberate", function()
    loadModules()
    local S = Omerta.Crime.STATE
    assert(S.PLANNED == "planned", "the state exists for C4")
    assert(Omerta.Crime.CanTransition(S.PLANNED, S.ACTIVE),
        "and the move out of it is legal, so C4 needs no migration")

    -- Nothing in M14 can reach it: there is no transition INTO planned at all.
    for from in pairs(S) do
        assert(not Omerta.Crime.CanTransition(S[from], S.PLANNED),
            "nothing may enter planned")
    end
end)

--------------------------------------------------------------------------------
suite("crime.robbable")
--------------------------------------------------------------------------------

-- D-030 GAINS A THIRD CASE and it is the one that makes the milestone work.
-- M13's rule answers false when a business has no owner, which was correct for a
-- milestone with no unowned businesses and is exactly wrong for a store that
-- exists to be robbed.
check("an unowned store is always robbable; an owned one still obeys D-030", function()
    loadModules()
    local typeDef = Omerta.Business.GetType("store")
    local unowned = { id = 1, type_key = "store" }
    local owned = { id = 2, type_key = "store", owner_character_id = 7 }

    -- D-030 exists to stop players being punished for logging off. An unowned
    -- store has no players to punish, so IsForceable's answer is irrelevant.
    assert(Omerta.Crime.IsRobbable(typeDef, unowned, false, false, 0),
        "an unowned store is robbable whoever is online")

    -- And M13's assertions on owned premises stay green.
    assert(not Omerta.Crime.IsRobbable(typeDef, owned, false, false, 0),
        "an owned store with nobody online is protected, exactly as before")
    assert(Omerta.Crime.IsRobbable(typeDef, owned, true, false, 0),
        "and forceable when the owning side is online")
end)

check("a robbery already under way, and a cooldown, both refuse", function()
    loadModules()
    local typeDef = Omerta.Business.GetType("store")
    local store = { id = 1, type_key = "store" }

    local ok, why = Omerta.Crime.IsRobbable(typeDef, store, false, true, 0)
    assert(not ok and why, "one at a time")

    ok, why = Omerta.Crime.IsRobbable(typeDef, store, false, false, 600)
    assert(not ok, "and not again inside the cooldown")
    -- The words are about the ROOM, never about a timer: no client is ever told
    -- a number, and "come back in 43 minutes" is a number.
    assert(not why:find("%d"), "the refusal must not leak a clock: " .. why)
end)

--------------------------------------------------------------------------------
suite("crime.robbery_block")
--------------------------------------------------------------------------------

-- A type that declares no `robbery` block still gets one. Robbability as an
-- opt-in flag would make a funeral home invisible to the crime system until
-- somebody remembered to tick a box.
check("every type has a robbery block, declared or defaulted", function()
    loadModules()
    for _, typeDef in ipairs(Omerta.Business.GetTypes()) do
        local block = Omerta.Crime.RobberyBlock(typeDef)
        assert(block.clerk and #block.clerk.personalities > 0,
            typeDef.key .. " has nobody behind the counter")
        assert(block.register and block.register.openSeconds,
            typeDef.key .. " has no register terms")
        assert(block.alarm ~= nil, typeDef.key .. " has no alarm terms")
    end
end)

-- The conservative direction matters more than the default's contents: a place
-- that has not said it can call the police must not be able to.
check("the default invents no capability the content author did not declare", function()
    loadModules()
    local block = Omerta.Crime.RobberyBlock({ key = "funeral_home", name = "X" })
    assert(block.alarm.telephone == false, "no telephone by default")
    assert(block.alarm.button == false, "no button by default")
    assert(block.float.perHour == 0, "and no money appears by default")
end)

-- The reason the block is worth having at all: a per-type consequence falling
-- out of one line of data.
check("the speakeasy is robbable and its barman does not telephone the police", function()
    loadModules()
    local block = Omerta.Crime.RobberyBlock(Omerta.Business.GetType("speakeasy"))
    assert(block.alarm.telephone == false,
        "the bar is illegal and its owner would rather tell his family")
    assert(block.register.openSeconds > 0, "and it is robbable like anywhere else")

    local store = Omerta.Crime.RobberyBlock(Omerta.Business.GetType("store"))
    assert(store.alarm.telephone == true, "a legitimate shop does call")
end)

--------------------------------------------------------------------------------
suite("crime.pressure")
--------------------------------------------------------------------------------

check("what is pointed at him is read off the arsenal, not a new field", function()
    loadModules()
    local C = Omerta.Crime.ThreatClass
    -- W0 already wrote the distinction down: a thing you cannot hide under a
    -- coat is a long gun, and that is exactly what a shopkeeper can see.
    assert(C(Omerta.Weapons.Get("weapon.thompson")) == "long")
    assert(C(Omerta.Weapons.Get("weapon.revolver")) == "handgun")
    assert(C(Omerta.Weapons.Get("weapon.m1911")) == "handgun")
    assert(C({ slot = "melee" }) == "melee")
    assert(C(nil) == nil, "empty hands are not a weapon class")

    local P = Omerta.Crime.WEAPON_PRESSURE
    assert(P.long > P.handgun and P.handgun > P.melee,
        "a Thompson is a different conversation")
end)

check("pressure rises with the room and never goes below nothing", function()
    loadModules()
    local F = Omerta.Crime.Pressure

    local base = F({ armed = true, weaponClass = "handgun", weaponsVisible = 1 })
    assert(F({ armed = true, weaponClass = "long", weaponsVisible = 1 }) > base,
        "a bigger gun")
    assert(F({ armed = true, weaponClass = "handgun", weaponsVisible = 3 }) > base,
        "more of them")
    assert(F({ armed = true, weaponClass = "handgun", weaponsVisible = 1,
        shotsFired = 1 }) > base, "a shot")
    assert(F({ armed = true, weaponClass = "handgun", weaponsVisible = 1,
        victimHurt = true }) > base, "being hit")
    assert(F({ armed = true, weaponClass = "handgun", weaponsVisible = 1,
        elapsed = 60 }) > base, "and standing there")

    -- Witnesses cut the other way, and the alarm going means help is coming.
    assert(F({ armed = true, weaponClass = "handgun", weaponsVisible = 1,
        bystanders = 3 }) < base, "a room with people in it")
    assert(F({ armed = true, weaponClass = "handgun", weaponsVisible = 1,
        alarmRaised = true }) < base, "help is on its way")

    assert(F({}) >= 0 and F({ bystanders = 99, alarmRaised = true }) >= 0,
        "pressure is never negative")

    -- Counted, not unbounded: the fourth onlooker is not braver than the third
    -- and the fifth shot does not frighten him more than the third.
    assert(F({ bystanders = 3 }) == F({ bystanders = 30 }), "onlookers are counted")
    assert(F({ shotsFired = 3 }) == F({ shotsFired = 30 }), "so are shots")
end)

check("a milestone can add a factor without this file changing", function()
    loadModules()
    local before = Omerta.Crime.Pressure({ armed = true, weaponClass = "handgun" })
    Omerta.Crime.RegisterReactionInput("test.neighbourhood", function() return 0.5 end)
    local after = Omerta.Crime.Pressure({ armed = true, weaponClass = "handgun" })
    assert(math.abs((after - before) - 0.5) < 0.0001, "the seam feeds pressure")
end)

--------------------------------------------------------------------------------
suite("crime.reaction")
--------------------------------------------------------------------------------

-- THE PROPERTY THE WHOLE MODEL IS BUILT AROUND. A robber cannot re-roll a
-- stubborn clerk by backing off and demanding again inside the same job.
check("the same seed and situation always produce the same decision", function()
    loadModules()
    local who = personality("clerk.old_hand")
    local situation = { armed = true, weaponClass = "handgun", weaponsVisible = 1 }

    for _, seed in ipairs({ 1, 4242, 99999, 2147480000 }) do
        local first = Omerta.Crime.Reaction(situation, who, seed, "demand")
        for _ = 1, 5 do
            assert(Omerta.Crime.Reaction(situation, who, seed, "demand") == first,
                "asking again must not re-roll him")
        end
    end
end)

check("different seeds are different men, and the beat is part of the roll", function()
    loadModules()
    local who = personality("clerk.old_hand")

    -- Rolls, rather than reactions: a decision is the max of five drives, so two
    -- seeds routinely agree on the obvious answer. What must differ is the dice.
    local seen = {}
    for seed = 1, 40 do
        seen[Omerta.Crime.Roll(seed, "demand", "comply")] = true
    end
    local count = 0
    for _ in pairs(seen) do count = count + 1 end
    assert(count > 30, "forty seeds should not collapse to a handful of rolls")

    -- And the same operation asked about two different things gets two
    -- independent rolls.
    assert(Omerta.Crime.Roll(7, "demand", "comply") ~= Omerta.Crime.Roll(7, "shot", "comply"),
        "a shot is not the demand asked twice")
end)

check("the roll is in range and takes strings and numbers alike", function()
    loadModules()
    for seed = 1, 200 do
        local r = Omerta.Crime.Roll(seed, "beat", "comply")
        assert(r >= 0 and r < 1, "out of range: " .. tostring(r))
    end
    assert(Omerta.Crime.Roll(1, 2, "three") >= 0, "mixed parts are fine")
end)

-- PAST HIS NERVE HE STOPS BEING A RATIONAL ACTOR. This is what makes a warning
-- shot a genuinely bad idea rather than a stronger version of a good one.
check("above his nerve the personality's weights stop applying", function()
    loadModules()
    local who = personality("clerk.old_hand")

    local calm = { armed = true, weaponClass = "handgun", weaponsVisible = 1 }
    local bedlam = {
        armed = true, weaponClass = "long", weaponsVisible = 2,
        shotsFired = 3, victimHurt = true, elapsed = 120,
    }

    local drives = select(2, Omerta.Crime.Reaction(calm, who, 11, "demand"))
    assert(drives.flee == 0, "a calm room gives him no reason to run")

    local panicked = select(2, Omerta.Crime.Reaction(bedlam, who, 11, "demand"))
    assert(panicked.flee > 0, "past his nerve, running starts to score")

    -- And it outgrows everything else, whatever kind of man he is: nothing else
    -- in the table grows with excess pressure.
    for _, id in ipairs({ "clerk.old_hand", "clerk.kid", "clerk.ex_soldier" }) do
        local extreme = {
            armed = true, weaponClass = "long", weaponsVisible = 3,
            shotsFired = 3, victimHurt = true, bystanderHurt = true, elapsed = 300,
        }
        local reaction = Omerta.Crime.Reaction(extreme, personality(id), 5, "shot")
        assert(reaction == Omerta.Crime.REACTION.FLEE,
            id .. " should be running by now, got " .. tostring(reaction))
    end
end)

check("the kid breaks before the ex-soldier does", function()
    loadModules()
    -- The whole reason personalities are data: which door you walk through is
    -- worth knowing, and it has to be visible in the numbers.
    assert(personality("clerk.kid").nerve < personality("clerk.old_hand").nerve)
    assert(personality("clerk.old_hand").nerve < personality("clerk.ex_soldier").nerve)
    assert(personality("clerk.ex_soldier").duty > personality("clerk.old_hand").duty,
        "the ex-soldier cares about somebody else's money")
    assert(personality("clerk.ex_soldier").alarmAppetite
        > personality("clerk.kid").alarmAppetite, "and reaches for the button")
end)

check("he does not lunge for the button with two guns on him", function()
    loadModules()
    local O = Omerta.Crime.AlarmOpportunity
    assert(O({ weaponsVisible = 1, elapsed = 0 }) > O({ weaponsVisible = 3, elapsed = 0 }),
        "every extra gun is another pair of eyes")
    assert(O({ weaponsVisible = 1, elapsed = 60 }) > O({ weaponsVisible = 1, elapsed = 0 }),
        "time is what gives him a chance")
    assert(O({ alarmRaised = true, elapsed = 300 }) == 0,
        "an alarm already going is not reached for twice")
    assert(O({ weaponsVisible = 1, victimHurt = true }) < O({ weaponsVisible = 1 }),
        "a man who has been hit is not reaching for anything")
end)

--------------------------------------------------------------------------------
suite("crime.mask")
--------------------------------------------------------------------------------

-- D-051, and the exact shape of the trade: IT BUYS COMPLIANCE IN THE ROOM AND
-- BUYS AN ALARM BEHIND YOUR BACK.
check("a mask buys compliance now and costs a telephone call later", function()
    loadModules()
    local who = personality("clerk.old_hand")
    local bare = { armed = true, weaponClass = "handgun", weaponsVisible = 1 }
    local masked = { armed = true, weaponClass = "handgun", weaponsVisible = 1, masked = true }

    local R = Omerta.Crime.REACTION
    assert(Omerta.Crime.Drives(masked, who)[R.COMPLY]
        > Omerta.Crime.Drives(bare, who)[R.COMPLY],
        "he believes he will live through this")

    assert(Omerta.Crime.ReportChance(masked, who) > Omerta.Crime.ReportChance(bare, who),
        "and he has nothing left to fear once you have gone")
end)

-- The ruling trimmed the rationale and the trim is load-bearing: an earlier
-- draft had the unmasked robber read as INTENDING MURDER, which is speculative
-- interior reasoning about an NPC. The trade stands without it, and nothing in
-- the model should encode it.
check("nothing models what the clerk thinks the robber came to do", function()
    loadModules()
    local source = io.open("gamemodes/omertarp/gamemode/modules/crime/sh_reactions.lua"):read("*a")
    for _, term in ipairs({ "intent", "murderous", "willing_to_kill", "meansToKill" }) do
        assert(not source:find(term),
            "the simplified rationale forbids a '" .. term .. "' term")
    end
end)

check("report chance stays a probability whatever is thrown at it", function()
    loadModules()
    local who = personality("clerk.ex_soldier")
    local everything = {
        masked = true, victimHurt = true, shotsFired = 4, bystanderHurt = true,
    }
    local chance = Omerta.Crime.ReportChance(everything, who)
    assert(chance >= 0 and chance <= 1, "got " .. tostring(chance))
    assert(Omerta.Crime.ReportChance({ complied = true },
        personality("clerk.kid")) >= 0, "and never negative")
end)

-- D-052. A man does not report his own murder; somebody finds him.
check("a dead clerk is a certainty, not a probability", function()
    loadModules()
    assert(Omerta.Crime.ReportChance({ clerkDead = true }, personality("clerk.kid")) == 1,
        "the quiet kid's murder still comes out")
    assert(Omerta.Crime.ReportChance({ clerkDead = true, masked = true },
        personality("clerk.old_hand")) == 1, "and a mask does not help with that")
end)

check("the mask is one item, one slot, one provider — and obtainable", function()
    loadModules()
    local item = Omerta.Items.Get("clothing.mask")
    assert(item and item.conceals == true, "the mask conceals")
    assert(item.slot == Omerta.Crime.FACE_SLOT)

    local slot = Omerta.Inventory.GetSlot(Omerta.Crime.FACE_SLOT)
    assert(slot and slot.worn == true, "a thing on your face costs no bulk")

    -- An item nobody can obtain leaves the milestone's acceptance test exactly
    -- as unreachable as no item at all.
    local supply = Omerta.Procurement.Get("supply.mask")
    assert(supply and supply.item == "clothing.mask", "and there is a way to get one")
    assert(supply.category == "disguises",
        "into the category M11 cut and nobody has filled since")
end)

--------------------------------------------------------------------------------
suite("crime.take")
--------------------------------------------------------------------------------

-- A HANDFUL AT A TIME, and the reason is mechanical: Money.Pay is all-or-nothing
-- and refuses on capacity, so a robber whose pockets are half full would
-- otherwise get NOTHING.
check("the take is a handful, and it halves down to what fits", function()
    loadModules()
    local everything = function() return true end

    assert(Omerta.Crime.PlanGrab(40000, 12000, everything) == 12000,
        "a full register gives a handful")
    assert(Omerta.Crime.PlanGrab(3000, 12000, everything) == 3000,
        "and a nearly empty one gives what is in it")

    -- Bulk is the anti-exploit (D-020): a man with a Thompson across his back
    -- takes what he can carry rather than standing there empty handed.
    local room = 2000
    local partial = Omerta.Crime.PlanGrab(40000, 12000, function(c) return c <= room end)
    assert(partial > 0 and partial <= room, "got " .. tostring(partial))

    assert(Omerta.Crime.PlanGrab(40000, 12000, function() return false end) == 0,
        "no room at all is no take at all")
    assert(Omerta.Crime.PlanGrab(0, 12000, everything) == 0, "an empty register")
    assert(Omerta.Crime.PlanGrab(1, 12000, everything) == 0,
        "and less than the smallest coin is nothing")
end)

-- Rejected: proceeds as a balance change or as newly minted cash. D-024's
-- argument for the third time — and it is what makes an interrupted robbery need
-- no rollback at all.
check("there is no way to grant money, only to move it", function()
    loadModules()
    assert(Omerta.Crime.Reward == nil, "no Reward")
    assert(Omerta.Crime.PayOut == nil, "no PayOut")
    assert(Omerta.Crime.Distribute == nil, "no Distribute")
    assert(type(Omerta.Business.EmptyTill) == "function",
        "M13 gained the unauthorised half instead")
end)

--------------------------------------------------------------------------------
suite("crime.float")
--------------------------------------------------------------------------------

-- D-048. The exclusion is the whole ruling: if somebody owns it, D-032 governs
-- its income unchanged, and that is what stops a family buying a store and
-- farming its own register.
check("a player-owned store accrues nothing, whatever its type declares", function()
    loadModules()
    local typeDef = Omerta.Business.GetType("store")
    assert(typeDef.robbery.float.perHour > 0, "the type does declare a float")

    local perHour = Omerta.Crime.FloatTerms(typeDef, { id = 1, type_key = "store" })
    assert(perHour > 0, "an unowned store accrues")

    assert(Omerta.Crime.FloatTerms(typeDef,
        { id = 2, type_key = "store", owner_character_id = 5 }) == 0,
        "a personally owned one does not")
    assert(Omerta.Crime.FloatTerms(typeDef,
        { id = 3, type_key = "store", owner_organization_id = 2 }) == 0,
        "and neither does a family's")
end)

check("the float stops at the ceiling and pauses for the robbery", function()
    loadModules()
    local C = Omerta.Crime.FloatCredit

    assert(C(1200, 4000, 0, 60, false) > 0, "an empty register fills")
    assert(C(1200, 4000, 4000, 60, false) == 0, "a full one does not")
    assert(C(1200, 4000, 3990, 60, false) <= 10, "and never past the ceiling")

    -- Paused while it is happening AND for the cooldown afterwards, which is
    -- what stops the same store being farmed efficiently.
    assert(C(1200, 4000, 0, 60, true) == 0, "nothing accrues while it is blocked")

    -- One config value turns the whole thing off, which is the escape hatch the
    -- ruling asked for when it accepted a new source of money.
    assert(C(0, 4000, 0, 60, false) == 0, "float_scale = 0 mints nothing")
end)

--------------------------------------------------------------------------------
suite("crime.clock")
--------------------------------------------------------------------------------

-- Absolute timestamps, never countdowns. M19 learned this twice, and here it
-- would make waiting for the nightly restart a robbery technique.
check("the escape window and the ceiling are absolute, and survive a reload", function()
    loadModules()
    local typeDef = Omerta.Crime.GetOperationType("robbery.store")

    assert(not Omerta.Crime.HasEscaped(typeDef, nil, 1000),
        "somebody still in the building is not an escape")
    assert(not Omerta.Crime.HasEscaped(typeDef, 1000, 1010), "not yet")
    assert(Omerta.Crime.HasEscaped(typeDef, 1000, 1000 + typeDef.escapeSeconds), "clear")

    -- The ceiling is what makes the machine TOTAL: no operation can sit open
    -- forever holding a clerk in a compliance state nobody is present to end.
    local deadline = Omerta.Crime.DeadlineFor(typeDef, 5000)
    assert(deadline == 5000 + typeDef.maxSeconds)
    assert(not Omerta.Crime.HasExpired({ deadline_at = deadline }, deadline - 1))
    assert(Omerta.Crime.HasExpired({ deadline_at = deadline }, deadline))

    -- A row read back out of the database answers identically, which is the
    -- property a countdown would not have had.
    assert(Omerta.Crime.HasExpired({ deadline_at = deadline }, deadline + 100000),
        "a restart does not buy anybody more time")
end)

--------------------------------------------------------------------------------
suite("crime.rumour")
--------------------------------------------------------------------------------

-- The one thing M14 puts in front of other players. It is built, never composed
-- from player input, so it cannot carry an injected name.
check("the rumour builder has no vocabulary for a person", function()
    loadModules()
    for _, shape in ipairs({ "robbery", "murder", "alarmed", "failed" }) do
        local text = Omerta.Crime.RumourText(shape, "The Corner Grocer", 3)
        assert(type(text) == "string" and #text > 0, shape .. " says nothing")
        assert(text:find("The Corner Grocer", 1, true), shape .. " forgot the place")
        -- The strongest form of the guarantee: there is no parameter a
        -- character could be passed in through, so this is checking the shape
        -- of the function rather than filtering its output.
        assert(not text:find("Tony"), "no name reached the text")
    end

    -- A place with no name still produces a sentence rather than a hole.
    local anonymous = Omerta.Crime.RumourText("robbery", nil, 1)
    assert(anonymous:find("street"), "got: " .. anonymous)
    assert(not anonymous:find("nil"), "and never the word nil")
end)

--------------------------------------------------------------------------------
suite("crime.schema")
--------------------------------------------------------------------------------

check("migration 15 creates the operations, participants and alarms", function()
    loadModules()
    Omerta.Module.FinishLoading()

    local mock = { dialect = "sqlite", heuristic = true, log = {}, nextInsertId = 1 }
    function mock.Connect(_, cb) cb(nil) end
    function mock.RunQuery(sqlStr, _, cb)
        mock.log[#mock.log + 1] = sqlStr
        if sqlStr:find("SELECT version") then cb({}, nil) return end
        local id = mock.nextInsertId
        mock.nextInsertId = mock.nextInsertId + 1
        cb({}, nil, id)
    end
    function mock.RunTransaction(_, cb) cb(true, nil) end
    Omerta.DB.Internal.Drivers = Omerta.DB.Internal.Drivers or {}
    Omerta.DB.Internal.Drivers.sqlite = mock
    Omerta.Module.EnableAll()

    local wanted = {
        omerta_crime_operations = false,
        omerta_crime_participants = false,
        omerta_crime_alarms = false,
    }
    for _, statement in ipairs(mock.log) do
        for table_ in pairs(wanted) do
            if statement:find("CREATE TABLE IF NOT EXISTS " .. table_, 1, true) then
                wanted[table_] = true
            end
        end
    end
    for table_, saw in pairs(wanted) do
        assert(saw, table_ .. " DDL missing")
    end
end)

--------------------------------------------------------------------------------
suite("crime.seams")
--------------------------------------------------------------------------------

-- M16's, M15's and C4's, all shipped empty on purpose — in the shape M19 shipped
-- RegisterDownedAction for M20. If M16 can be built entirely as a registration
-- into RegisterResponder, the seam was cut correctly.
check("the seams the neighbours fill exist and are empty", function()
    loadModules()
    assert(type(Omerta.Crime.RegisterResponder) == "function", "M16's")
    assert(type(Omerta.Crime.RegisterObserverSink) == "function", "M15's")
    assert(type(Omerta.Crime.RegisterReactionInput) == "function", "the disguise milestone's")
    assert(type(Omerta.Crime.RegisterOperationType) == "function", "C4's")
    assert(type(Omerta.Crime.RegisterTakeSource) == "function", "C4's vault")

    assert(next(Omerta.Crime.Internal.Responders) == nil,
        "M14 registers no responder — the police are M16's whole milestone")
    assert(next(Omerta.Crime.Internal.ObserverSinks) == nil,
        "and stores no witness: M14 owns the moment, M15 owns the memory")
end)

check("an alarm can exist with no robbery behind it", function()
    loadModules()
    Omerta.Module.FinishLoading()
    -- A gunshot in an empty street at three in the morning. M16 must not need
    -- two code paths to answer it, which is why operation_id is nullable.
    local schema = Omerta.DB.Internal.GetTableDef("crime_alarms")
    assert(schema, "no alarms table")
    for _, column in ipairs(schema.columns) do
        if column.name == "operation_id" then
            assert(column.null ~= false, "operation_id must be nullable")
        end
        if column.name == "responded_at" then
            assert(column.null ~= false, "M16's column starts empty")
        end
    end
end)

--------------------------------------------------------------------------------
suite("crime.regressions")
--------------------------------------------------------------------------------

-- A nil value is not a key in Lua, so a merge that walked only the DEFAULT keys
-- silently dropped every field the defaults had no opinion about — which is
-- every field a content author is most likely to add. The store's declared flee
-- point was the first casualty and would have been invisible: the clerk simply
-- backs away from the counter instead, which looks like a design choice.
check("a declared field the defaults never mention survives the merge", function()
    loadModules()
    local block = Omerta.Crime.RobberyBlock(Omerta.Business.GetType("store"))
    assert(block.fleeTo == "back", "got: " .. tostring(block.fleeTo))

    -- And anything a later milestone adds comes through the same way.
    local invented = Omerta.Crime.RobberyBlock({ robbery = { vaultSeconds = 90 } })
    assert(invented.vaultSeconds == 90, "C4's block must not be filtered")
    assert(invented.register.openSeconds, "while the defaults still fill in")
end)

-- D-048 needs unowned premises to exist, and M13's ValidateOwner refuses
-- "neither" for a good reason: a premises with no owner has no access control.
-- The opt-in is explicit at the call site rather than a relaxation of the rule.
check("unowned is opted into, not allowed by default", function()
    loadModules()
    local V = Omerta.Business.Internal.ValidateOwner
    assert(not V(nil, nil), "the rule itself is unchanged")

    -- And the opt-in is mutually exclusive with actually having an owner, so
    -- `unowned = true` can never quietly discard one.
    local refused = nil
    Omerta.Business.Create("store", "X", { characterId = 4 }, Vector(0, 0, 0),
        { unowned = true }, function(_, err) refused = err end)
    assert(refused and refused:find("cannot have an owner"), tostring(refused))
end)

-- The reaction model reads what a shopkeeper can SEE. If a weapon ever loses
-- its `concealable` field the classifier must not silently call a Thompson a
-- handgun, so the arsenal is checked for the fields the mapping depends on.
check("every weapon can be classified by what it is", function()
    loadModules()
    for _, def in ipairs(Omerta.Weapons.All()) do
        local class = Omerta.Crime.ThreatClass(def)
        assert(Omerta.Crime.WEAPON_PRESSURE[class],
            def.id .. " classified as '" .. tostring(class) .. "', which has no pressure")
    end
end)
