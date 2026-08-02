-- The register float (D-048).
--
-- D-032 ruled that a business earns from sales plus a small trickle ONLY WHILE A
-- REAL PERSON IS BEHIND THE COUNTER. A store with an NPC clerk has no real
-- person behind the counter, so under the rule as written it earns nothing and
-- there is nothing in the register to rob — the milestone's own acceptance test
-- could not run.
--
-- So an UNOWNED store accrues a small per-hour float, and that is the whole of
-- the extension. PLAYER-OWNED PREMISES ARE EXCLUDED ENTIRELY: if somebody owns
-- it, D-032 governs its income unchanged. That exclusion is what stops a family
-- buying a store and farming its own register.
--
-- THE HONEST COST, NAMED RATHER THAN BURIED: this is a new source of money. It
-- is bounded by a ceiling declared per business type, paused while an operation
-- is live and for a cooldown afterwards, audited per credit, and turned off
-- entirely with `crime.float_scale = 0`.

Omerta.Crime = Omerta.Crime or {}
Omerta.Crime.Internal = Omerta.Crime.Internal or {}
local Internal = Omerta.Crime.Internal

-- Whether this premises accrues at all, and how much it may hold. Pure over its
-- inputs, so the exclusion is a testable rule rather than a branch buried in a
-- timer.
--
-- Returns perHour, ceiling — both zero when nothing should accrue.
function Omerta.Crime.FloatTerms(typeDef, business)
    if not (typeDef and business) then return 0, 0 end

    -- The exclusion, first and unconditionally. Ownership is the whole test:
    -- an owned business is D-032's, whatever its type declares.
    if business.owner_organization_id or business.owner_character_id then
        return 0, 0
    end

    local block = Omerta.Crime.RobberyBlock(typeDef)
    local float = block.float or {}
    local perHour = math.max(0, tonumber(float.perHour) or 0)
    local ceiling = math.max(0, tonumber(float.ceiling) or 0)
    if perHour <= 0 or ceiling <= 0 then return 0, 0 end
    return perHour, ceiling
end

-- What to credit this tick, given what is already in the register. Pure.
--
-- `blocked` covers both pauses in one argument on purpose: a live robbery and a
-- post-robbery cooldown are the same answer — nothing accrues — and two
-- separate flags would be two places to forget one.
function Omerta.Crime.FloatCredit(perHour, ceiling, held, minutes, blocked)
    if blocked then return 0 end
    if perHour <= 0 or ceiling <= 0 then return 0 end
    if held >= ceiling then return 0 end

    local amount = Omerta.Money.Round(perHour * (minutes / 60))
    if amount <= 0 then return 0 end

    -- Never past the ceiling, and never a credit so small it rounds to nothing.
    amount = math.min(amount, Omerta.Money.Round(ceiling - held))
    if amount < Omerta.Money.SMALLEST then return 0 end
    return amount
end

function Internal.TickFloat()
    local scale = Omerta.Config.Get("crime.float_scale")
    if scale <= 0 then return end

    local minutes = Omerta.Config.Get("crime.float_minutes")

    for _, business in pairs(Omerta.Business.All()) do
        local typeDef = Omerta.Business.GetType(business.type_key)
        local perHour, ceiling = Omerta.Crime.FloatTerms(typeDef, business)
        if perHour > 0 then
            local till = Omerta.Business.Till(business.id)
            local held = Omerta.Money.Count(till)
            local blocked = Omerta.Crime.ForBusiness(business.id) ~= nil
                or Omerta.Crime.CooldownRemaining(business.id) > 0

            local amount = Omerta.Crime.FloatCredit(
                perHour * scale, ceiling, held, minutes, blocked)

            if amount > 0 and Omerta.Money.HasRoomFor(till, amount) then
                Omerta.Money.Give(till, amount, function(ok)
                    if not ok then return end
                    -- Audited per credit. The question staff will actually be
                    -- asked is where the money in an unowned till came from,
                    -- and a total cannot answer it.
                    Omerta.Log.Audit("crime.float", {
                        subject = business.id,
                        data = { cents = amount, held = held, ceiling = ceiling },
                    })
                end)
            end
        end
    end
end
