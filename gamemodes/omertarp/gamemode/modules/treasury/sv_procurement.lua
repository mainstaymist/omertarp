-- Buying things with the family's money.
--
-- §4b: an abstract supplier. Money leaves the safe, goods appear in it, and
-- the fiction is that your people know a guy. Delivery goes through one
-- function so that making it take ten minutes later is a config value rather
-- than a rewrite.

Omerta.Procurement = Omerta.Procurement or {}
Omerta.Procurement.Internal = Omerta.Procurement.Internal or {}

local Treasury = Omerta.Treasury.Internal
local Internal = Omerta.Procurement.Internal
local P = Omerta.Organizations.PERMISSIONS

--------------------------------------------------------------------------------
-- Delivery
--------------------------------------------------------------------------------

-- The seam §4b describes. Today it completes immediately; a delay, a courier
-- or a supplier NPC replaces the body of this function and nothing above it
-- changes. cb(ok, err)
function Internal.Deliver(organizationId, entry, quantity, cb)
    local safe = Omerta.Treasury.Of(organizationId)
    local total = entry.quantity * quantity

    if not entry.item then cb(true) return end

    Omerta.Inventory.Add(safe, entry.item, total, {
        -- Bought goods belong to the institution, not to whoever fetched them.
        -- M9 left this column on every item for exactly this moment.
        organizationId = organizationId,
    }, cb)
end

--------------------------------------------------------------------------------
-- Buying
--------------------------------------------------------------------------------

-- Finds a member at the safe, other than the buyer, who can cover an amount.
-- Server-side: the client never nominates who signed for the money.
local function approverAt(ply, organizationId, buyerCharacterId)
    if not Omerta.InEngine then return nil end
    for _, other in ipairs(player.GetAll()) do
        if other ~= ply then
            local otherChar, otherMember = Treasury.MembershipAt(other)
            if otherChar and otherMember
                    and otherMember.organization_id == organizationId
                    and otherChar.id ~= buyerCharacterId
                    and Treasury.AtSafe(other, organizationId)
                    and Omerta.Organizations.Can(otherChar.id, P.TREASURY_SPEND) then
                return other, otherChar
            end
        end
    end
    return nil
end

-- cb(ok, err)
function Omerta.Procurement.Buy(ply, organizationId, entryId, quantity, cb)
    cb = cb or function() end
    quantity = math.floor(quantity or 1)
    if quantity < 1 or quantity > 100 then cb(false, "that is not a quantity") return end

    local character, member, def = Treasury.MembershipAt(ply)
    if not (character and member and member.organization_id == organizationId) then
        cb(false, "that is not your treasury") return
    end
    local near, why = Treasury.AtSafe(ply, organizationId)
    if not near then cb(false, why) return end

    local entry = Omerta.Procurement.Get(entryId)
    if not entry then cb(false, "there is no such thing to order") return end

    -- Re-derived, never trusted: an entry the client was never offered fails
    -- the same filter that decided not to offer it.
    local rank = Omerta.Organizations.EffectiveRank(character.id)
    local allowedHere = false
    for _, candidate in ipairs(Omerta.Procurement.Available(def.type, def.ladder, rank)) do
        if candidate.id == entryId then allowedHere = true break end
    end
    if not allowedHere then cb(false, "that is not yours to order") return end

    local cost = entry.price * quantity
    local multiplier = Omerta.Config.Get("treasury.limit_multiplier")

    local approverPly, approverChar = approverAt(ply, organizationId, character.id)
    local approverRank = approverChar
        and Omerta.Organizations.EffectiveRank(approverChar.id) or nil

    local mayspend, refusal = Omerta.Treasury.CanSpend(def.ladder, rank, cost,
        approverRank, multiplier)
    if not mayspend then cb(false, refusal) return end

    if Omerta.Treasury.Count(organizationId) < cost then
        cb(false, "there is not that much in the safe") return
    end

    -- Room is checked BEFORE the money moves. Paying first and discovering the
    -- safe is full would leave the family with neither the cash nor the goods.
    if entry.item then
        local safe = { type = Omerta.Inventory.OWNER.CONTAINER,
                       id = Omerta.Treasury.ContainerId(organizationId) }
        local itemDef = Omerta.Items.Get(entry.item)
        local used = Omerta.Inventory.SumBulk(Omerta.Inventory.Get(safe))
        local adding = Omerta.Inventory.StackBulk(itemDef, entry.quantity * quantity)
        if not Omerta.Inventory.Fits(used, adding, Omerta.Inventory.BulkLimit(safe)) then
            cb(false, "there is no room in the safe for that")
            return
        end
    end

    local note = string.format("%s x%d", entry.name, quantity)
    Treasury.Spend(ply, organizationId, cost, entry.category, note, function(spent, serr)
        if not spent then cb(false, serr) return end

        Internal.Deliver(organizationId, entry, quantity, function(delivered, derr)
            if not delivered then
                -- The room check above makes this close to unreachable. If it
                -- ever fires, the audit line is the only record of money that
                -- bought nothing, so it is written loudly.
                Omerta.Log.Error("treasury", "procurement paid but did not deliver: %s",
                    tostring(derr))
                Omerta.Log.Audit("treasury.delivery_failed", {
                    actor = ply:SteamID64(), character_id = character.id,
                    data = { organization_id = organizationId, entry = entryId,
                             cost = cost, reason = tostring(derr) },
                })
                cb(false, "the goods never arrived — this has been logged")
                return
            end

            if entry.onPurchase then
                local ok, err = pcall(entry.onPurchase, organizationId, ply, quantity)
                if not ok then
                    Omerta.Log.Error("treasury", "onPurchase for '%s' failed: %s",
                        entryId, tostring(err))
                end
            end

            Omerta.Chat.Notice(ply, string.format("%s — %s, paid from the treasury%s.",
                note, Omerta.Money.Format(cost),
                approverChar and " and approved" or ""))
            cb(true)
        end)
    end)
end

function Internal.HandleOrder(ply, entryIndex, quantity)
    local entry = Omerta.Procurement.GetByIndex(entryIndex)
    if not entry then return end
    local _, member = Treasury.MembershipAt(ply)
    if not member then return end

    Omerta.Procurement.Buy(ply, member.organization_id, entry.id, quantity,
        function(ok, err)
            if not ok and err then Omerta.Chat.Notice(ply, err) end
            Treasury.SendState(ply)
        end)
end
