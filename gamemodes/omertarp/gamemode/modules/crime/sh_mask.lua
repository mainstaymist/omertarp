-- One mask (D-047).
--
-- This milestone's own definition of done is a two-player MASKED store robbery,
-- and nothing in the game could conceal a face. D-014 shipped
-- Omerta.Identity.RegisterConcealmentProvider in M5 and no milestone has ever
-- registered one; the roadmap puts disguises in the content workstream, which
-- owns models rather than mechanics. There was no milestone that owned this.
--
-- So M14 becomes the first caller of a seam M5 cut empty, at the same size and
-- shape as M20's registration into RegisterDownedAction — and the same test of
-- whether the seam was cut correctly.
--
-- WHAT THIS DELIBERATELY IS NOT: a disguise system, appearance descriptors,
-- partial concealment, gloves, or anything M15 will want. A mask is on or it is
-- off, and while it is on you are Unknown to everybody including your own crew,
-- who must rely on voice. That is what D-014 already says and has never been
-- able to demonstrate.

Omerta.Crime = Omerta.Crime or {}

-- The slot. Registered here rather than in M9's own list because M9 has no
-- reason to know a face can be covered, and because the disguise milestone will
-- want this line where the rest of the concealment lives.
--
-- Slot indices are derived from a deterministic sort and travel on the wire, so
-- inserting one renumbers the slots after it. That is safe and worth stating:
-- what is PERSISTED is `equipped_slot` as text, and the index is only ever a
-- live client's shorthand. A restart re-derives it; nothing in the database
-- refers to it.
Omerta.Crime.FACE_SLOT = "face"

Omerta.Inventory.RegisterSlot(Omerta.Crime.FACE_SLOT, {
    label = "Face",
    order = 45,
    -- Worn, not carried: a thing on your face costs no bulk (D-020's rule).
    worn = true,
})

-- `conceals` is data rather than an id check, so the disguise milestone adds a
-- scarf, a hood and a false beard by writing three tables and touching nothing
-- in sv_mask.lua.
Omerta.Items.Register("clothing.mask", {
    name = "Cloth Mask",
    category = "clothing",
    bulk = 0.3,
    slot = Omerta.Crime.FACE_SLOT,
    conceals = true,
    model = "models/props_c17/BriefCase001a.mdl",
})

-- AND A WAY TO GET ONE, which is not a detail: the milestone's acceptance test
-- is a MASKED robbery, and an item nobody can obtain leaves it exactly as
-- unreachable as no item at all.
--
-- Through M11's procurement rather than a shop, because M11 already has a
-- `disguises` category that has been empty since it shipped — the same "the
-- seam was cut, nobody filled it" shape as the concealment provider itself. It
-- also puts the purchase in a family's books, which is the right place for a
-- crew buying four of them the week before a job.
--
-- Cheap on purpose. A mask is not a capability you gate behind money; the price
-- of wearing one is D-051's telephone call, not the cost of the cloth.
if SERVER and Omerta.Procurement then
    Omerta.Procurement.Register("supply.mask", {
        name = "Cloth Mask", category = "disguises",
        price = 400, order = 10,
        item = "clothing.mask", quantity = 1,
    })
end
