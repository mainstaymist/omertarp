-- The base item catalogue.
--
-- This is deliberately short. M9 ships the things every other system needs to
-- exist before it can be built — money, something to eat, something to carry
-- it in, something to conceal and something that cannot be concealed — and
-- nothing else. Bar stock belongs to M13, evidence to M15, medical supplies to
-- M19, and each registers its own through Omerta.Items.Register.
--
-- Bulk is a rough measure of "how much room does this take, and can you hide
-- it": a Thompson at 22 against a base capacity of 20 is the design's own
-- example of a thing you cannot simply put in a pocket.

local Register = Omerta.Items.Register

--------------------------------------------------------------------------------
-- Currency (D-003, D-004)
--------------------------------------------------------------------------------
-- Coins weigh more than notes for the same reason they do in a pocket, which
-- is what makes a sack of quarters an actual burden rather than a number.

for _, denom in ipairs(Omerta.Money.DENOMINATIONS) do
    Register(denom.item, {
        name = denom.name,
        category = "money",
        bulk = denom.coin and 0.02 or 0.01,
        stackable = true,
        maxStack = 200,
        model = denom.coin and "models/props_lab/box01a.mdl"
                           or "models/props_junk/cardboard_box001a.mdl",
    })
end

--------------------------------------------------------------------------------
-- Food and drink (D-016, D-019)
--------------------------------------------------------------------------------
-- `feeds` is data, not behaviour: the USE handler reads it, so adding a meal
-- later is a table entry rather than a function.

Register("food.sandwich", {
    name = "Sandwich", category = "food", bulk = 0.5, feeds = 35,
    stackable = true, maxStack = 5,
    model = "models/props_junk/garbage_takeoutcarton001a.mdl",
})

Register("food.bread", {
    name = "Loaf of Bread", category = "food", bulk = 0.8, feeds = 22,
    stackable = true, maxStack = 5,
    model = "models/props_junk/garbage_takeoutcarton001a.mdl",
})

Register("food.soup", {
    name = "Bowl of Soup", category = "food", bulk = 0.6, feeds = 28,
    model = "models/props_junk/garbage_takeoutcarton001a.mdl",
})

Register("drink.coffee", {
    name = "Cup of Coffee", category = "drink", bulk = 0.3, feeds = 8,
    model = "models/props_junk/glassjug01.mdl",
})

Register("drink.whiskey", {
    name = "Glass of Whiskey", category = "drink", bulk = 0.3, feeds = 5,
    model = "models/props_junk/glassbottle01a.mdl",
})

--------------------------------------------------------------------------------
-- Clothing
--------------------------------------------------------------------------------
-- `capacityBonus` is what §4a's worked example describes: a coat is how you
-- carry something you could not otherwise carry. It applies only while worn,
-- which is why taking someone's coat is worth doing.
--
-- These do not change a character's model yet — appearance is the clothing and
-- disguise milestone's job (D-014). What they do here is carry and conceal.

Register("clothing.overcoat", {
    name = "Overcoat", category = "clothing", bulk = 4, slot = "outerwear",
    capacityBonus = 12,
    model = "models/props_c17/BriefCase001a.mdl",
})

Register("clothing.suit_jacket", {
    name = "Suit Jacket", category = "clothing", bulk = 2, slot = "outerwear",
    capacityBonus = 5,
    model = "models/props_c17/BriefCase001a.mdl",
})

Register("clothing.fedora", {
    name = "Fedora", category = "clothing", bulk = 0.6, slot = "headwear",
    model = "models/props_c17/BriefCase001a.mdl",
})

--------------------------------------------------------------------------------
-- Tools and arms
--------------------------------------------------------------------------------
-- These are inventory objects, not yet functioning weapons: firearms are the
-- combat milestone's business. What matters here is that a Thompson is too big
-- to hide, which is the fact M15's witnesses will later need.

Register("tool.crowbar", {
    name = "Crowbar", category = "tool", bulk = 3, slot = "melee",
    model = "models/weapons/w_crowbar.mdl",
})

Register("tool.lockpicks", {
    name = "Set of Lockpicks", category = "tool", bulk = 0.4,
    model = "models/props_c17/BriefCase001a.mdl",
})

Register("weapon.revolver", {
    name = "Revolver", category = "weapon", bulk = 4, slot = "sidearm",
    model = "models/weapons/w_pistol.mdl",
})

Register("weapon.thompson", {
    name = "Thompson", category = "weapon", bulk = 22, slot = "primary",
    concealable = false,
    model = "models/weapons/w_smg1.mdl",
})

--------------------------------------------------------------------------------
-- Everyday things
--------------------------------------------------------------------------------

Register("misc.cigarettes", {
    name = "Pack of Cigarettes", category = "misc", bulk = 0.2,
    stackable = true, maxStack = 10,
    model = "models/props_junk/cardboard_box001a.mdl",
})

Register("misc.newspaper", {
    name = "Newspaper", category = "misc", bulk = 0.3,
    model = "models/props_junk/cardboard_box001a.mdl",
})
