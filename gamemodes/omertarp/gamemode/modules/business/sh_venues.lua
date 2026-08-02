-- The business types.
--
-- GDD §11 lists seven. The speakeasy is the one that has to work, because the
-- other six are content once it is a framework — and most of them mean nothing
-- until later milestones exist. A funeral home without bodies is a room.
--
-- Prices are in cents and must be payable with coins in circulation (D-018).

local Define = Omerta.Business.DefineType

--------------------------------------------------------------------------------
-- The speakeasy — the MVP (Tech §11)
--------------------------------------------------------------------------------
-- Drink, a room to sit in, a barman who has heard things, and a counter with
-- money in it. Everything the design needs a social hub to be.

Define("speakeasy", {
    name = "Speakeasy",
    order = 10,
    tillCapacity = 400,
    stockCapacity = 1200,
    services = { "bar", "rumours" },
    -- Bought from M11's procurement in cases, sold here one at a time. The
    -- margin is the business.
    sells = {
        { item = "drink.whiskey",    price = 250 },
        { item = "drink.coffee",     price = 120 },
        { item = "food.sandwich",    price = 150 },
        { item = "misc.cigarettes",  price = 100 },
    },
    -- Where the newspaper lands and where a watcher would stand (Tech §11).
    -- Declared now, read by M21 and M15.
    newspaperSpawn = true,
    surveillance = true,
    -- AND THE REASON THE ROBBERY BLOCK IS WORTH HAVING AT ALL (M14). A
    -- speakeasy is robbable the day it is placed, like everywhere else with a
    -- till — but its barman does not telephone the police, because the bar is
    -- illegal and its owner would rather tell his family. One line of data, and
    -- a per-type consequence falls out of it.
    robbery = {
        clerk = { personalities = { "clerk.old_hand" } },
        alarm = { kind = "none", telephone = false, button = false },
        register = { openSeconds = 4, forceSeconds = 26, forceTool = "tool.crowbar" },
        float = { perHour = 0, ceiling = 0 },
    },
})

--------------------------------------------------------------------------------
-- The store — the place that exists to be robbed (M14)
--------------------------------------------------------------------------------
-- ROBBABILITY IS NOT A FLAG ON A SPECIAL KIND OF BUILDING. Every business with
-- a till is robbable and the type declares the terms; the `robbery` block below
-- is data on the type exactly as `sells` is, and a type that declares none gets
-- a conservative default from Omerta.Crime.RobberyBlock.
--
-- Adding a KIND of robbable place is one table, in version control, reviewable
-- and revertable. Adding AN INSTANCE of one is `omerta_business_place store —
-- The Corner Grocer` at the console, with no code change at all. Those are the
-- two different things "data-driven" has to mean here and they have two
-- different answers.

Define("store", {
    name = "General Store",
    order = 15,
    tillCapacity = 600,
    stockCapacity = 900,
    services = { "shop" },
    sells = {
        { item = "food.bread",      price = 90 },
        { item = "food.sandwich",   price = 150 },
        { item = "misc.cigarettes", price = 100 },
        { item = "misc.newspaper",  price = 25 },
    },
    newspaperSpawn = true,
    robbery = {
        clerk = { personalities = { "clerk.old_hand", "clerk.kid", "clerk.ex_soldier" } },
        -- A legitimate shop has a telephone and a button under the counter.
        alarm = { kind = "silent", telephone = true, button = true },
        register = { openSeconds = 4, forceSeconds = 22, forceTool = "tool.crowbar" },
        -- D-048: unowned only. The moment a player buys this shop, D-032
        -- governs its income and these two numbers stop being consulted.
        float = { perHour = 1200, ceiling = 4000 },
        fleeTo = "back",
    },
})

--------------------------------------------------------------------------------
-- The rest of GDD §11
--------------------------------------------------------------------------------
-- Registered so the framework is exercised by more than one shape, and so the
-- milestones that fill them in have somewhere to attach. Each sells what
-- already exists as an item; none of them has a mechanic of its own yet, and
-- pretending otherwise would be content dressed as a system.

Define("restaurant", {
    name = "Restaurant",
    order = 20,
    services = { "bar" },
    sells = {
        { item = "food.soup",     price = 180 },
        { item = "food.sandwich", price = 150 },
        { item = "food.bread",    price = 90 },
        { item = "drink.coffee",  price = 120 },
    },
    newspaperSpawn = true,
})

Define("social_club", {
    name = "Social Club",
    order = 30,
    services = { "bar", "rumours" },
    sells = {
        { item = "drink.coffee",    price = 100 },
        { item = "misc.cigarettes", price = 95 },
    },
    surveillance = true,
})

Define("tailor", {
    name = "Tailor",
    order = 40,
    services = { "shop" },
    -- The disguise milestone is what makes this interesting; for now it sells
    -- clothes that carry things (M9's capacity bonuses).
    sells = {
        { item = "clothing.suit_jacket", price = 3200 },
        { item = "clothing.overcoat",    price = 4000 },
        { item = "clothing.fedora",      price = 1400 },
    },
})

-- Placed now, meaningful later: a clinic without injuries (M19) and a funeral
-- home without bodies (M20) are rooms, and the honest thing is to say so
-- rather than invent a mechanic to justify the door.
Define("clinic", {
    name = "Clinic",
    order = 50,
    services = { "shop" },
    sells = {
        { item = "food.soup", price = 100 },
    },
})

Define("auto_shop", {
    name = "Auto Shop",
    order = 60,
    services = { "shop" },
    sells = {
        { item = "tool.crowbar",   price = 1800 },
        { item = "tool.lockpicks", price = 6000 },
    },
})

Define("funeral_home", {
    name = "Funeral Home",
    order = 70,
    services = { "shop" },
    sells = {
        { item = "misc.newspaper", price = 25 },
    },
})
