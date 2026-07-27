-- Money as physical objects, server side.
--
-- Every economic source in the game — a treasury payout (M11), a bar sale
-- (M13), the proceeds of a robbery (M14) — goes through Give and Take. There
-- is no other way to create or destroy money, which is what makes "where did
-- this come from" answerable and makes conjuring it impossible.
--
-- The arithmetic lives in sh_currency.lua and is pure. This file is the part
-- that touches rows.

Omerta.Money = Omerta.Money or {}
Omerta.Money.Internal = Omerta.Money.Internal or {}

local Inventory = Omerta.Inventory.Internal
local MoneyInternal = Omerta.Money.Internal

--------------------------------------------------------------------------------
-- Counting
--------------------------------------------------------------------------------

-- A wallet view of an owner's cash: denomination cents -> count.
function Omerta.Money.Wallet(owner)
    local ownerType, ownerId = Inventory.ResolveOwner(owner)
    local wallet = {}
    if not ownerType then return wallet end

    for _, row in ipairs(Inventory.CachedRows(ownerType, ownerId)) do
        local denom = Omerta.Money.DenominationOfItem(row.def_id)
        if denom then
            wallet[denom.cents] = (wallet[denom.cents] or 0) + row.quantity
        end
    end
    return wallet
end

function Omerta.Money.Count(owner)
    return Omerta.Money.Total(Omerta.Money.Wallet(owner))
end

-- What M12's payphone asks: not "can you afford a call" but "have you got a
-- quarter" (D-003).
function Omerta.Money.CountCoins(owner, cents)
    return Omerta.Money.Wallet(owner)[cents] or 0
end

--------------------------------------------------------------------------------
-- Planning (pure)
--------------------------------------------------------------------------------

-- Turns a denomination selection into row-level updates against real stacks.
-- Returns updates, or nil + reason when the stacks do not actually hold what
-- the wallet view claimed.
function MoneyInternal.PlanSpend(rows, selection)
    local updates = {}
    local outstanding = {}
    for cents, count in pairs(selection) do outstanding[cents] = count end

    for _, row in ipairs(rows) do
        local denom = Omerta.Money.DenominationOfItem(row.def_id)
        local want = denom and outstanding[denom.cents]
        if want and want > 0 then
            local take = math.min(want, row.quantity)
            updates[#updates + 1] = {
                id = row.id,
                quantity = row.quantity - take,   -- 0 deletes the row
                expected = row.quantity,
            }
            outstanding[denom.cents] = want - take
        end
    end

    for cents, remaining in pairs(outstanding) do
        if remaining > 0 then
            return nil, string.format("short of %d x %s", remaining, Omerta.Money.Format(cents))
        end
    end
    return updates
end

-- The row list as it will look once a set of updates has been applied: rows
-- reduced to zero disappear, the rest carry their new quantity. Pure, and the
-- reason change can be planned against a wallet that has not been spent yet.
function MoneyInternal.ApplyUpdates(rows, updates)
    local newQuantity = {}
    for _, update in ipairs(updates) do newQuantity[update.id] = update.quantity end

    local out = {}
    for _, row in ipairs(rows) do
        local quantity = newQuantity[row.id]
        if quantity == nil then
            out[#out + 1] = row
        elseif quantity > 0 then
            local copy = {}
            for key, value in pairs(row) do copy[key] = value end
            copy.quantity = quantity
            out[#out + 1] = copy
        end
    end
    return out
end

-- Turns a wallet into rows to insert, merging into partial stacks where there
-- are any. Returns updates, insertions.
function MoneyInternal.PlanCredit(rows, wallet, ownerType, ownerId, seasonId, now)
    local updates, insertions = {}, {}
    -- Each denomination is planned against the rows as they will be after the
    -- previous denomination's plan, but denominations never share a stack, so
    -- one pass over the original rows is exact.
    for _, denom in ipairs(Omerta.Money.DENOMINATIONS) do
        local count = wallet[denom.cents]
        if count and count > 0 then
            local def = Omerta.Items.Get(denom.item)
            local plan = Inventory.PlanAdd(rows, def, count)
            for _, update in ipairs(plan.updates) do updates[#updates + 1] = update end
            for _, size in ipairs(plan.insertions) do
                insertions[#insertions + 1] = {
                    def_id = denom.item,
                    season_id = seasonId,
                    owner_type = ownerType,
                    owner_id = ownerId,
                    quantity = size,
                    serial = Omerta.DB.NULL,
                    organization_id = Omerta.DB.NULL,
                    metadata = Omerta.DB.NULL,
                    created_at = now,
                }
            end
        end
    end
    return updates, insertions
end

--------------------------------------------------------------------------------
-- Giving and taking
--------------------------------------------------------------------------------

local function bulkOfWallet(wallet)
    local units = 0
    for cents, count in pairs(wallet) do
        local denom = Omerta.Money.GetDenomination(cents)
        if denom then
            units = units + Omerta.Inventory.StackBulk(Omerta.Items.Get(denom.item), count)
        end
    end
    return units
end

-- Room for an amount, without moving anything. Callers that must not lose
-- money (a treasury payout, a shop's change drawer) check this first.
function Omerta.Money.HasRoomFor(owner, cents)
    local wallet = Omerta.Money.Compose(cents)
    if not wallet then return false end
    local ownerType, ownerId = Inventory.ResolveOwner(owner)
    if not ownerType then return false end
    if ownerType == Omerta.Inventory.OWNER.WORLD then return true end

    local used = Omerta.Inventory.SumBulk(Inventory.CachedRows(ownerType, ownerId))
    return Omerta.Inventory.Fits(used, bulkOfWallet(wallet), Omerta.Inventory.BulkLimit(owner))
end

-- Mints an amount into an owner's hands as notes and coins. cb(ok, err)
function Omerta.Money.Give(owner, cents, cb)
    cb = cb or function() end

    local wallet, why = Omerta.Money.Compose(cents)
    if not wallet then cb(false, why) return end

    local ownerType, ownerId = Inventory.ResolveOwner(owner)
    if not ownerType then cb(false, "unknown owner") return end
    if not Omerta.Inventory.IsLoaded({ type = ownerType, id = ownerId }) then
        cb(false, "inventory not loaded") return
    end

    local season = Omerta.Seasons.GetActive()
    if not season then cb(false, "no active season") return end

    local rows = Inventory.CachedRows(ownerType, ownerId)
    if ownerType ~= Omerta.Inventory.OWNER.WORLD then
        local used = Omerta.Inventory.SumBulk(rows)
        if not Omerta.Inventory.Fits(used, bulkOfWallet(wallet),
                Omerta.Inventory.BulkLimit({ type = ownerType, id = ownerId })) then
            cb(false, "there is no room to carry that much")
            return
        end
    end

    local updates, insertions = MoneyInternal.PlanCredit(rows, wallet, ownerType, ownerId,
        season.id, os.time())

    Inventory.Repo.ApplyChanges(updates, insertions, function(ok, err)
        if not ok then cb(false, err) return end
        Omerta.Inventory.Load({ type = ownerType, id = ownerId }, function() cb(true) end)
    end)
end

-- Takes an amount, making change if the exact notes are not available.
-- cb(ok, err, changeGiven)
function Omerta.Money.Take(owner, cents, cb)
    cb = cb or function() end
    if type(cents) ~= "number" or cents % 1 ~= 0 or cents < 0 then
        cb(false, "amount must be a whole number of cents") return
    end
    if cents == 0 then cb(true, nil, 0) return end

    local ownerType, ownerId = Inventory.ResolveOwner(owner)
    if not ownerType then cb(false, "unknown owner") return end
    if not Omerta.Inventory.IsLoaded({ type = ownerType, id = ownerId }) then
        cb(false, "inventory not loaded") return
    end

    local season = Omerta.Seasons.GetActive()
    if not season then cb(false, "no active season") return end

    local wallet = Omerta.Money.Wallet({ type = ownerType, id = ownerId })
    local selection, change, why = Omerta.Money.SelectPayment(wallet, cents)
    if not selection then cb(false, why) return end

    local rows = Inventory.CachedRows(ownerType, ownerId)
    local updates, planErr = MoneyInternal.PlanSpend(rows, selection)
    if not updates then cb(false, planErr) return end

    -- The change comes straight back in the same transaction. Paying and being
    -- given change are one event, not two: half of it succeeding would either
    -- destroy money or create it.
    local insertions = {}
    if change > 0 then
        -- Planned against the wallet AS IT WILL BE once the payment is made,
        -- so change never tries to merge into a stack that is about to be
        -- spent, and one row never needs two conflicting UPDATEs.
        local creditUpdates, creditInsertions = MoneyInternal.PlanCredit(
            MoneyInternal.ApplyUpdates(rows, updates), Omerta.Money.Compose(change),
            ownerType, ownerId, season.id, os.time())

        local positionOf = {}
        for i, update in ipairs(updates) do positionOf[update.id] = i end
        for _, credit in ipairs(creditUpdates) do
            local at = positionOf[credit.id]
            if at then
                -- Same row, spent and then topped up: one statement with the
                -- final quantity, still guarded on the quantity we first read.
                updates[at].quantity = credit.quantity
            else
                updates[#updates + 1] = credit
            end
        end
        insertions = creditInsertions
    end

    Inventory.Repo.ApplyChanges(updates, insertions, function(ok, err)
        if not ok then cb(false, err) return end
        Omerta.Inventory.Load({ type = ownerType, id = ownerId }, function()
            cb(true, nil, change)
        end)
    end)
end

--------------------------------------------------------------------------------
-- Paying somebody
--------------------------------------------------------------------------------

-- Hand-to-hand and over-the-counter payment. cb(ok, err)
function Omerta.Money.Pay(fromOwner, toOwner, cents, cb)
    cb = cb or function() end
    if Omerta.Money.Count(fromOwner) < cents then cb(false, "not enough money") return end

    -- Checked BEFORE anything moves: taking first and discovering the
    -- recipient has no room would leave the money nowhere.
    if not Omerta.Money.HasRoomFor(toOwner, cents) then
        cb(false, "they cannot carry that much")
        return
    end

    Omerta.Money.Take(fromOwner, cents, function(ok, err)
        if not ok then cb(false, err) return end
        Omerta.Money.Give(toOwner, cents, function(gaveOk, giveErr)
            if not gaveOk then
                -- The room check above makes this close to unreachable; if it
                -- ever fires, the audit line is the only record of where the
                -- money went, so it is written loudly.
                Omerta.Log.Error("money", "payment credited nothing: %s", tostring(giveErr))
                Omerta.Log.Audit("money.lost", {
                    data = { cents = cents, reason = tostring(giveErr) },
                })
                cb(false, giveErr)
                return
            end
            local _, fromId = Inventory.ResolveOwner(fromOwner)
            local _, toId = Inventory.ResolveOwner(toOwner)
            Omerta.Log.Audit("money.paid", {
                from_character = fromId, to_character = toId,
                data = { cents = cents },
            })
            cb(true)
        end)
    end)
end
