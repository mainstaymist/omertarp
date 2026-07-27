-- Items repository: the only file in the gamemode that writes SQL about
-- items or character needs.
--
-- Two rules shape everything here:
--
--   * ONE ROW PER INSTANCE, ONE OWNER. An item's location is a column, not a
--     blob, so "who is holding a Thompson?" is a query and an item can never
--     be in two places at once.
--   * OWNERSHIP CHANGES ARE GUARDED. Every move names the owner it expects to
--     be moving FROM, so a move that has already happened cannot happen twice.
--     Duplication is the one economic bug that cannot be walked back.

Omerta.Inventory = Omerta.Inventory or {}
Omerta.Inventory.Internal = Omerta.Inventory.Internal or {}
local Internal = Omerta.Inventory.Internal
Internal.Repo = Internal.Repo or {}
local Repo = Internal.Repo

--------------------------------------------------------------------------------
-- Instances
--------------------------------------------------------------------------------

-- cb(id, err)
function Repo.Insert(row, cb)
    Omerta.DB.Insert("items", row, cb)
end

function Repo.GetByID(id, cb)
    Omerta.DB.QueryOne("SELECT * FROM {items} WHERE id = ?", { id }, cb)
end

function Repo.ListForOwner(ownerType, ownerId, cb)
    Omerta.DB.Query(
        "SELECT * FROM {items} WHERE owner_type = ? AND owner_id = ? ORDER BY id",
        { ownerType, ownerId },
        function(rows, err) cb(rows or {}, err) end)
end

-- Dropped items, so a restart does not destroy what somebody put on the floor.
function Repo.ListWorld(seasonId, cb)
    Omerta.DB.Query(
        "SELECT * FROM {items} WHERE owner_type = ? AND season_id = ? ORDER BY id",
        { Omerta.Inventory.OWNER.WORLD, seasonId },
        function(rows, err) cb(rows or {}, err) end)
end

-- Guarded move. The UPDATE names the owner we believe the item has right now,
-- so a stale request changes nothing; the read-back then reports what actually
-- happened, because the driver layer does not expose an affected-row count.
-- cb(moved, err)
function Repo.SetOwner(id, toType, toId, expectType, expectId, cb)
    Omerta.DB.Query(
        "UPDATE {items} SET owner_type = ?, owner_id = ?, equipped_slot = ? " ..
        "WHERE id = ? AND owner_type = ? AND owner_id = ?",
        { toType, toId, Omerta.DB.NULL, id, expectType, expectId },
        function(_, err)
            if err then cb(false, err) return end
            Repo.GetByID(id, function(row, rerr)
                if rerr then cb(false, rerr) return end
                if not row then cb(false, "item no longer exists") return end
                cb(row.owner_type == toType and row.owner_id == toId, nil, row)
            end)
        end)
end

function Repo.SetQuantity(id, quantity, cb)
    Omerta.DB.Query("UPDATE {items} SET quantity = ? WHERE id = ?", { quantity, id },
        function(_, err) if cb then cb(err == nil, err) end end)
end

function Repo.SetPosition(id, x, y, z, cb)
    Omerta.DB.Query(
        "UPDATE {items} SET pos_x = ?, pos_y = ?, pos_z = ? WHERE id = ?",
        { x, y, z, id },
        function(_, err) if cb then cb(err == nil, err) end end)
end

-- Guarded on the owner: equipping something you no longer hold does nothing.
function Repo.SetEquippedSlot(id, slot, ownerType, ownerId, cb)
    Omerta.DB.Query(
        "UPDATE {items} SET equipped_slot = ? WHERE id = ? AND owner_type = ? AND owner_id = ?",
        { slot == nil and Omerta.DB.NULL or slot, id, ownerType, ownerId },
        function(_, err) if cb then cb(err == nil, err) end end)
end

function Repo.Delete(id, cb)
    Omerta.DB.Query("DELETE FROM {items} WHERE id = ?", { id },
        function(_, err) if cb then cb(err == nil, err) end end)
end

function Repo.DeleteForOwner(ownerType, ownerId, cb)
    Omerta.DB.Query("DELETE FROM {items} WHERE owner_type = ? AND owner_id = ?",
        { ownerType, ownerId },
        function(_, err) if cb then cb(err == nil, err) end end)
end

--------------------------------------------------------------------------------
-- Multi-row changes
--------------------------------------------------------------------------------

-- Paying is never one statement: some stacks are spent whole, one is spent in
-- part, and change comes back as new stacks. Topping up an inventory is the
-- same shape. All of it happens inside a single transaction or none of it
-- does — a credit without its matching debit would mint money out of nothing.
--
--   updates    — { { id = , quantity = , expected = } }
--                quantity nil or 0 deletes the row; `expected` guards the
--                update against a stack that changed underneath us
--   insertions — full rows to insert
-- cb(ok, err)
function Repo.ApplyChanges(updates, insertions, cb)
    Omerta.DB.Transaction(function(tx)
        for _, update in ipairs(updates or {}) do
            if not update.quantity or update.quantity <= 0 then
                tx:Query("DELETE FROM {items} WHERE id = ?", { update.id })
            else
                tx:Query("UPDATE {items} SET quantity = ? WHERE id = ? AND quantity = ?",
                    { update.quantity, update.id, update.expected })
            end
        end
        for _, row in ipairs(insertions or {}) do
            tx:Insert("items", row)
        end
    end, cb)
end

--------------------------------------------------------------------------------
-- Character needs (hunger)
--------------------------------------------------------------------------------

function Repo.GetNeeds(characterId, cb)
    Omerta.DB.QueryOne("SELECT * FROM {character_needs} WHERE character_id = ?",
        { characterId }, cb)
end

function Repo.SaveNeeds(characterId, hunger, at, cb)
    Omerta.DB.Upsert("character_needs",
        { character_id = characterId, hunger = hunger, updated_at = at },
        { "character_id" }, cb)
end

function Repo.DeleteNeeds(characterId, cb)
    Omerta.DB.Query("DELETE FROM {character_needs} WHERE character_id = ?", { characterId },
        function(_, err) if cb then cb(err == nil, err) end end)
end
