-- Physical currency (D-003, D-004, D-018): money is not a number on a
-- character sheet, it is a set of stacks of specific notes and coins that can
-- be dropped, hidden, handed over and taken off a body.
--
-- Everything in this file is PURE. Composing an amount into notes and coins,
-- and choosing which of a wallet's actual notes and coins to hand over, is the
-- arithmetic the entire economy will run on for years, so it lives apart from
-- the database and is covered directly by the headless suite.
--
-- Amounts are ALWAYS integer cents. Floats are wrong for money, always.

Omerta.Money = Omerta.Money or {}
Omerta.Money.Internal = Omerta.Money.Internal or {}
local Internal = Omerta.Money.Internal

-- Ascending. `item` is the item definition id registered in sh_items.lua;
-- keeping the mapping here means the payphone (M12) asks for a quarter by
-- denomination rather than by knowing an item id.
Omerta.Money.DENOMINATIONS = {
    { cents = 5,     item = "money.cent5",     name = "Nickel",          coin = true },
    { cents = 10,    item = "money.cent10",    name = "Dime",            coin = true },
    { cents = 25,    item = "money.cent25",    name = "Quarter",         coin = true },
    { cents = 100,   item = "money.dollar1",   name = "One Dollar" },
    { cents = 500,   item = "money.dollar5",   name = "Five Dollars" },
    { cents = 2000,  item = "money.dollar20",  name = "Twenty Dollars" },
    { cents = 10000, item = "money.dollar100", name = "One Hundred Dollars" },
}

-- The smallest coin in circulation. Amounts that are not a multiple of this
-- cannot be *minted* (see Compose), though they can still be *paid* — the
-- payer overshoots and takes change, exactly as in life.
Omerta.Money.SMALLEST = 5

-- Exact-change search is a bounded dynamic program (Internal.ExactPayment).
-- Above this amount the greedy path is used instead: the cost to the payer is
-- identical either way, only the coins left in their pocket differ, and no
-- realistic purchase needs a $200 exact-change search.
Omerta.Money.MAX_EXACT_CENTS = 20000

local DENOMS = Omerta.Money.DENOMINATIONS

local byCents, byItem = {}, {}
for _, denom in ipairs(DENOMS) do
    byCents[denom.cents] = denom
    byItem[denom.item] = denom
end

function Omerta.Money.GetDenomination(cents) return byCents[cents] end
function Omerta.Money.DenominationOfItem(itemId) return byItem[itemId] end

--------------------------------------------------------------------------------
-- Presentation
--------------------------------------------------------------------------------

-- "$12.35". Always two decimal places, because a price written "$12.3" reads
-- as a bug to anyone who has ever seen money.
function Omerta.Money.Format(cents)
    cents = math.floor(tonumber(cents) or 0)
    local sign = cents < 0 and "-" or ""
    cents = math.abs(cents)
    return string.format("%s$%d.%02d", sign, math.floor(cents / 100), cents % 100)
end

--------------------------------------------------------------------------------
-- Wallets
--------------------------------------------------------------------------------
-- A "wallet" is a plain map of denomination cents -> count. It is deliberately
-- not an inventory: these functions must stay pure so they can be reasoned
-- about and tested without a database behind them.

function Omerta.Money.Total(wallet)
    local total = 0
    for cents, count in pairs(wallet or {}) do
        total = total + cents * count
    end
    return total
end

-- Mints an amount as the fewest possible notes and coins.
-- Returns a wallet, or nil + reason.
--
-- Greedy is optimal here because the denomination set is canonical (each
-- denomination is at least twice the previous, or a clean multiple of it);
-- that is a property of this specific set, not of greedy change-making in
-- general, so changing DENOMINATIONS means re-checking this claim.
function Omerta.Money.Compose(cents)
    if type(cents) ~= "number" or cents % 1 ~= 0 or cents < 0 then
        return nil, "amount must be a whole, non-negative number of cents"
    end
    if cents % Omerta.Money.SMALLEST ~= 0 then
        return nil, string.format("%s cannot be made from coins in circulation " ..
            "(amounts must be a multiple of %d cents)",
            Omerta.Money.Format(cents), Omerta.Money.SMALLEST)
    end

    local wallet, remaining = {}, cents
    for i = #DENOMS, 1, -1 do
        local denom = DENOMS[i].cents
        local count = math.floor(remaining / denom)
        if count > 0 then
            wallet[denom] = count
            remaining = remaining - count * denom
        end
    end
    return wallet
end

-- Rounds an amount to something that can actually be minted. Callers that
-- compute a fraction (a percentage cut, an interest payment) must round
-- EXPLICITLY through this rather than have Compose silently absorb the
-- remainder — losing cents quietly is how an economy stops adding up.
function Omerta.Money.Round(cents)
    local step = Omerta.Money.SMALLEST
    return math.floor((tonumber(cents) or 0) / step + 0.5) * step
end

--------------------------------------------------------------------------------
-- Paying with the money you actually have
--------------------------------------------------------------------------------

-- Exact payment from a limited wallet, by bounded dynamic programming over
-- 5-cent units. Returns a wallet to hand over, or nil when the amount cannot
-- be made exactly (or is too large to be worth searching).
--
-- Greedy alone is not enough: with a quarter and three dimes, paying 30 cents
-- greedily takes the quarter and then finds nothing worth 5, when three dimes
-- would have been exact.
function Internal.ExactPayment(wallet, target)
    if target % Omerta.Money.SMALLEST ~= 0 then return nil end
    if target > Omerta.Money.MAX_EXACT_CENTS then return nil end

    local unit = Omerta.Money.SMALLEST
    local goal = target / unit

    -- layers[i][v] — v units are payable using only the first i denominations.
    -- Keeping every layer is what makes the selection reconstructible below.
    local layers = { [0] = { [0] = true } }
    local budget = {}

    for i, denom in ipairs(DENOMS) do
        local step = denom.cents / unit
        local available = math.min(wallet[denom.cents] or 0, math.floor(goal / step))
        budget[i] = available

        local prev, current = layers[i - 1], {}
        -- used[v] is the fewest units of THIS denomination needed to reach v.
        -- Ascending order lets each answer build on the one `step` below it,
        -- which is what keeps a bounded count linear rather than quadratic.
        local used = {}
        for v = 0, goal do
            if prev[v] then
                used[v] = 0
                current[v] = true
            elseif v >= step and used[v - step] and used[v - step] < available then
                used[v] = used[v - step] + 1
                current[v] = true
            end
        end
        layers[i] = current
    end

    if not layers[#DENOMS][goal] then return nil end

    local selection, remaining = {}, goal
    for i = #DENOMS, 1, -1 do
        local step = DENOMS[i].cents / unit
        local count = 0
        -- Peel this denomination off until what is left was reachable without
        -- it. The bound is defence against a logic error, not an expected path.
        while not layers[i - 1][remaining] and count < budget[i] and remaining >= step do
            remaining = remaining - step
            count = count + 1
        end
        if not layers[i - 1][remaining] and remaining > 0 then return nil end
        if count > 0 then selection[DENOMS[i].cents] = count end
    end
    return selection
end

-- Largest-first, then the cheapest single overshoot. Returns the selection and
-- the total actually handed over (which may exceed the target).
function Internal.GreedyPayment(wallet, target)
    local selection, paid = {}, 0

    for i = #DENOMS, 1, -1 do
        local cents = DENOMS[i].cents
        local wanted = math.floor((target - paid) / cents)
        local take = math.min(wallet[cents] or 0, wanted)
        if take > 0 then
            selection[cents] = take
            paid = paid + take * cents
        end
    end
    if paid >= target then return selection, paid end

    -- Every denomination with units to spare is worth MORE than the shortfall
    -- — the pass above took as many as would fit — so the smallest one still
    -- available is the cheapest possible overshoot.
    local short = target - paid
    for i = 1, #DENOMS do
        local cents = DENOMS[i].cents
        local spare = (wallet[cents] or 0) - (selection[cents] or 0)
        if spare > 0 and cents >= short then
            selection[cents] = (selection[cents] or 0) + 1
            paid = paid + cents
            break
        end
    end
    return selection, paid
end

-- What to hand over to pay `target` from `wallet`.
-- Returns selection, changeDue — or nil, nil, reason.
--
-- The player is never asked to count (M9 §4b): an exact set is used when one
-- exists, otherwise they overpay and the change comes back. The NET cost is
-- exact in both cases.
function Omerta.Money.SelectPayment(wallet, target)
    if type(target) ~= "number" or target % 1 ~= 0 or target < 0 then
        return nil, nil, "amount must be a whole, non-negative number of cents"
    end
    if target == 0 then return {}, 0 end
    if Omerta.Money.Total(wallet) < target then return nil, nil, "not enough money" end

    local exact = Internal.ExactPayment(wallet, target)
    if exact then return exact, 0 end

    local selection, paid = Internal.GreedyPayment(wallet, target)
    if paid < target then
        -- Unreachable while Total >= target, but a wrong answer about money is
        -- worse than a refusal.
        return nil, nil, "cannot assemble that amount from these notes and coins"
    end
    return selection, paid - target
end
