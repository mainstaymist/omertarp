-- The base procurement catalogue.
--
-- Short on purpose, and every entry delivers something that already exists as
-- an item. Later milestones register their own: M12 the private telephone
-- line, M13 bar stock in bulk, M19 medical supplies, M14 the tools of a
-- burglary. Nothing here grants a statistic (Tech §10) — every one of these is
-- an object that has to be carried, concealed, used and eventually explained.
--
-- Prices are in cents and must be payable with coins in circulation, so they
-- are multiples of five.

local Register = Omerta.Procurement.Register

--------------------------------------------------------------------------------
-- Weapons
--------------------------------------------------------------------------------
-- Moved to the arsenal (modules/weapons/sh_weapons_arsenal.lua) when D-039
-- made the guns real: a weapon and its supply line live in one file, and the
-- treasury loads before the arsenal, so entries here could no longer validate
-- items the arsenal had not yet created. The prices and the reasoning behind
-- them moved with the entries, unchanged.

--------------------------------------------------------------------------------
-- Burglary
--------------------------------------------------------------------------------

Register("supply.crowbar", {
    name = "Crowbar", category = "burglary", price = 1200,
    item = "tool.crowbar", order = 10,
})

Register("supply.lockpicks", {
    name = "Set of Lockpicks", category = "burglary", price = 4500,
    item = "tool.lockpicks", order = 20,
})

--------------------------------------------------------------------------------
-- Disguises
--------------------------------------------------------------------------------
-- Clothing is procurement's quietest category and will become one of its most
-- important once concealment bites (D-014).

Register("supply.suit_jacket", {
    name = "Suit Jacket", category = "disguises", price = 2200,
    item = "clothing.suit_jacket", order = 10,
})

Register("supply.overcoat", {
    name = "Overcoat", category = "disguises", price = 2800,
    item = "clothing.overcoat", order = 20,
})

Register("supply.fedora", {
    name = "Fedora", category = "disguises", price = 900,
    item = "clothing.fedora", order = 30,
})

-- A police department buys its own uniforms; a family buying them would be a
-- different kind of story, and one that belongs to the disguise milestone
-- rather than to a catalogue entry.
Register("supply.police_uniform", {
    name = "Police Uniform", category = "disguises", price = 1500,
    item = "clothing.police_uniform", orgType = "police", order = 40,
})

--------------------------------------------------------------------------------
-- Business stock
--------------------------------------------------------------------------------
-- Bought in quantity, sold one at a time. M13's speakeasies draw from here.

Register("supply.whiskey_case", {
    name = "Case of Whiskey", category = "stock", price = 1400,
    item = "drink.whiskey", quantity = 10, order = 10,
})

Register("supply.coffee_sack", {
    name = "Sack of Coffee", category = "stock", price = 800,
    item = "drink.coffee", quantity = 10, order = 20,
})

Register("supply.cigarette_carton", {
    name = "Carton of Cigarettes", category = "stock", price = 600,
    item = "misc.cigarettes", quantity = 10, order = 30,
})

--------------------------------------------------------------------------------
-- Provisions
--------------------------------------------------------------------------------
-- Feeding your people is a small, dull, recurring cost, which is exactly what
-- makes it feel like running something.

Register("supply.sandwiches", {
    name = "Tray of Sandwiches", category = "stock", price = 300,
    item = "food.sandwich", quantity = 5, order = 40,
})

Register("supply.bread", {
    name = "Bread, by the loaf", category = "stock", price = 200,
    item = "food.bread", quantity = 5, order = 50,
})
