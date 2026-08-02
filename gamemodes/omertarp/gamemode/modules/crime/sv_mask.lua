-- The first concealment provider (D-047, implementing D-014).
--
-- Server only, and that is not an oversight: Omerta.Identity.IsConcealed is
-- consulted inside ResolveDisplayName, which only ever runs on the server. A
-- client is told one resolved name at a time for one person it is looking at,
-- and never learns why the answer was Unknown.

Omerta.Crime = Omerta.Crime or {}
Omerta.Crime.Internal = Omerta.Crime.Internal or {}
local Internal = Omerta.Crime.Internal

-- Whether this character has something over their face right now.
--
-- Reads the equipped row rather than a cached flag, for the reason M9 gives
-- about the ammo pool: a second copy of "what is this person wearing" is a
-- second thing that can be wrong, and the one that is wrong is always the
-- cached one. Taking a mask off is an M9 unequip and nothing here is told.
function Omerta.Crime.IsMasked(characterId)
    if not characterId then return false end
    local owner = { type = Omerta.Inventory.OWNER.CHARACTER, id = characterId }

    -- An inventory that has not loaded cannot be read, and guessing would mean
    -- guessing in the direction of "concealed" — which would hide a face the
    -- game has no evidence is covered.
    if not Omerta.Inventory.IsLoaded(owner) then return false end

    for _, row in ipairs(Omerta.Inventory.Get(owner) or {}) do
        if row.equipped_slot == Omerta.Crime.FACE_SLOT then
            local def = Omerta.Items.Get(row.def_id)
            if def and def.conceals then return true end
        end
    end
    return false
end

function Internal.RegisterConcealment()
    Omerta.Identity.RegisterConcealmentProvider(function(subjectChar)
        if not (subjectChar and subjectChar.id) then return false end
        return Omerta.Crime.IsMasked(subjectChar.id)
    end)
end
