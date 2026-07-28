-- Selling a drink.
--
-- The client sends an item and a quantity. The server looks up the price,
-- checks the stock actually exists, takes the money and hands over the goods —
-- all through M9's transactional path, so a sale is one event or none of it.

Omerta.Business = Omerta.Business or {}
Omerta.Business.Internal = Omerta.Business.Internal or {}
local Internal = Omerta.Business.Internal

--------------------------------------------------------------------------------
-- The menu
--------------------------------------------------------------------------------

-- How many of this item the stock room actually holds.
function Internal.StockOf(businessId, itemId)
    local total = 0
    for _, row in ipairs(Omerta.Inventory.Get(Omerta.Business.Stock(businessId))) do
        if row.def_id == itemId then total = total + row.quantity end
    end
    return total
end

function Internal.SendMenu(ply, business)
    local typeDef = Omerta.Business.GetType(business.type_key)
    if not (typeDef and #typeDef.sells > 0) then return end

    for i, entry in ipairs(typeDef.sells) do
        local index = Omerta.Items.IndexOf(entry.item)
        if index then
            Omerta.Net.Send("business.menu", {
                item = index,
                price = entry.price,
                stock = math.min(Internal.StockOf(business.id, entry.item), 65535),
                last = i == #typeDef.sells,
            }, ply)
        end
    end
end

--------------------------------------------------------------------------------
-- Buying
--------------------------------------------------------------------------------

-- cb(ok, err)
function Omerta.Business.Sell(customerPly, business, itemId, quantity, cb)
    cb = cb or function() end
    local customer = Omerta.Characters.Get(customerPly)
    if not customer then cb(false, "no character") return end

    local typeDef = Omerta.Business.GetType(business.type_key)
    if not typeDef then cb(false, "that place sells nothing") return end

    -- Re-derived from the definition, never taken from the client: the wire
    -- carries an item index and a count, and nothing that looks like a price.
    local entry = Internal.PriceOf(typeDef, itemId)
    local inStock = entry and Internal.StockOf(business.id, itemId) or 0

    local ok, why = Internal.CanSell(entry, quantity, inStock,
        Omerta.Money.Count(customerPly), business.is_open == true)
    if not ok then cb(false, why) return end

    -- Nobody behind the counter means nobody to serve you. The room does not
    -- sell drinks on its own (D-032).
    if not Internal.IsStaffed(business) then
        cb(false, "there is nobody behind the counter")
        return
    end

    local cost = entry.price * quantity
    local till = Omerta.Business.Till(business.id)

    if not Omerta.Money.HasRoomFor(till, cost) then
        cb(false, "the register is full — somebody needs to empty it")
        return
    end

    -- Money first, then goods, with the room for both checked beforehand —
    -- the same order and the same reasoning as M11's procurement.
    Omerta.Money.Pay(customerPly, till, cost, function(paid, perr)
        if not paid then cb(false, perr) return end

        Internal.TakeFromStock(business.id, itemId, quantity, function(taken, terr)
            if not taken then
                Omerta.Log.Error("business", "paid but not served: %s", tostring(terr))
                Omerta.Log.Audit("business.sale_failed", {
                    actor = customerPly:SteamID64(), character_id = customer.id,
                    data = { business = business.id, item = itemId, cost = cost,
                             reason = tostring(terr) },
                })
                cb(false, "something went wrong — this has been logged")
                return
            end

            Omerta.Inventory.Add(customerPly, itemId, quantity, nil, function(gave, gerr)
                if not gave then
                    -- They paid and the stock is gone; their hands are full.
                    -- Put it on the counter rather than into nothing.
                    Omerta.Inventory.Add(Omerta.Business.Stock(business.id), itemId, quantity,
                        { force = true })
                    Omerta.Money.Pay(till, customerPly, cost)
                    cb(false, gerr or "you cannot carry that")
                    return
                end
                Omerta.Log.Audit("business.sold", {
                    actor = customerPly:SteamID64(), character_id = customer.id,
                    data = { business = business.id, item = itemId,
                             quantity = quantity, cents = cost },
                })
                cb(true)
            end)
        end)
    end)
end

-- Removes `quantity` of an item from the stock room, across however many
-- stacks it takes. cb(ok, err)
function Internal.TakeFromStock(businessId, itemId, quantity, cb)
    local stock = Omerta.Business.Stock(businessId)
    local remaining = quantity

    local targets = {}
    for _, row in ipairs(Omerta.Inventory.Get(stock)) do
        if row.def_id == itemId and remaining > 0 then
            local take = math.min(row.quantity, remaining)
            targets[#targets + 1] = { id = row.id, take = take }
            remaining = remaining - take
        end
    end
    if remaining > 0 then cb(false, "the stock ran out while serving") return end

    local index = 0
    local function next_()
        index = index + 1
        if index > #targets then cb(true) return end
        Omerta.Inventory.Remove(targets[index].id, targets[index].take, function(ok, err)
            if not ok then cb(false, err) return end
            next_()
        end)
    end
    next_()
end

function Internal.HandleBuy(ply, itemIndex, quantity)
    local business = Internal.AtCounter(ply)
    if not business then return end

    local def = Omerta.Items.GetByIndex(itemIndex)
    if not def then return end

    Omerta.Business.Sell(ply, business, def.id, quantity, function(ok, err)
        if not ok and err then Omerta.Chat.Notice(ply, err) end
        Internal.SendState(ply, business)
    end)
end
