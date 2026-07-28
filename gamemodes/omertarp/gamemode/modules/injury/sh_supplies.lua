-- Medical supplies.
--
-- M9's catalogue said "medical supplies to M19, and each registers its own",
-- so this is M19 keeping that promise rather than editing M9's file.
--
-- Deliberately one item. A bandage stops somebody bleeding to death and does
-- nothing else — it does not get them up, which is the two-step D-037 asked
-- for and the reason a clinic is worth walking to.

local Register = Omerta.Items.Register

Register("medical.bandage", {
    name = "Bandages",
    category = "medical",
    -- Small enough to keep on you without thinking about it. That matters: if
    -- carrying one were a real decision, nobody would, and every gunshot would
    -- be fatal by default.
    bulk = 0.3,
    stackable = true,
    maxStack = 10,
    model = "models/props_junk/garbage_newspaper001a.mdl",
    -- No onUse. You cannot bandage yourself while unconscious, and bandaging
    -- somebody else goes through the interaction so that it takes time, can be
    -- interrupted, and is visible to anyone watching.
})

--------------------------------------------------------------------------------
-- Where they come from
--------------------------------------------------------------------------------
-- GDD §10 lists medical supplies among the things a family treasury buys, and
-- M11 built the catalogue for exactly this. Registered here so the item and
-- its supply line stay in one file.

if SERVER and Omerta.Procurement then
    Omerta.Procurement.Register("supply.bandages", {
        name = "Case of Bandages", category = "medical",
        price = 1200, order = 20,
        item = "medical.bandage", quantity = 10,
    })
end

--------------------------------------------------------------------------------
-- The clinic finally does something
--------------------------------------------------------------------------------
-- M13 registered the type and said outright that "a clinic without injuries
-- (M19) is a room". M19 is the injuries, so the room becomes a surgery — by
-- adding a service to the existing definition rather than by M19 learning what
-- a building is.

if Omerta.Business and Omerta.Business.GetType then
    local clinic = Omerta.Business.GetType("clinic")
    if clinic then
        clinic.services = clinic.services or {}
        local hasMedical = false
        for _, service in ipairs(clinic.services) do
            if service == "medical" then hasMedical = true end
        end
        if not hasMedical then clinic.services[#clinic.services + 1] = "medical" end

        clinic.sells = clinic.sells or {}
        clinic.sells[#clinic.sells + 1] = { item = "medical.bandage", price = 200 }
    end
end
