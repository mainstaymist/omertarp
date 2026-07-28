-- Business repository: the only file that writes SQL about premises, their
-- staff, or the rumour mill.
--
-- There is no ledger table here on purpose. A business's takings become a
-- treasury line the moment somebody collects them (D-032), so Tech §11's
-- "income/expense ledger" is M11's books rather than a second, parallel set
-- that could disagree with them.

Omerta.Business = Omerta.Business or {}
Omerta.Business.Internal = Omerta.Business.Internal or {}
local Internal = Omerta.Business.Internal
Internal.Repo = Internal.Repo or {}
local Repo = Internal.Repo

--------------------------------------------------------------------------------
-- Premises
--------------------------------------------------------------------------------

function Repo.Create(row, cb)
    Omerta.DB.Insert("businesses", row, cb)
end

function Repo.ListForSeason(seasonId, cb)
    Omerta.DB.Query("SELECT * FROM {businesses} WHERE season_id = ? ORDER BY id",
        { seasonId }, function(rows, err) cb(rows or {}, err) end)
end

function Repo.SetOpen(id, isOpen, cb)
    Omerta.DB.Query("UPDATE {businesses} SET is_open = ? WHERE id = ?", { isOpen, id },
        function(_, err) if cb then cb(err == nil, err) end end)
end

function Repo.Delete(id, cb)
    Omerta.DB.Query("DELETE FROM {businesses} WHERE id = ?", { id },
        function(_, err) if cb then cb(err == nil, err) end end)
end

--------------------------------------------------------------------------------
-- Staff
--------------------------------------------------------------------------------

function Repo.ListStaff(businessId, cb)
    Omerta.DB.Query("SELECT * FROM {business_staff} WHERE business_id = ?", { businessId },
        function(rows, err) cb(rows or {}, err) end)
end

function Repo.Hire(businessId, characterId, role, now, cb)
    Omerta.DB.Upsert("business_staff", {
        business_id = businessId,
        character_id = characterId,
        role = role,
        hired_at = now,
    }, { "business_id", "character_id" }, cb)
end

function Repo.Fire(businessId, characterId, cb)
    Omerta.DB.Query("DELETE FROM {business_staff} WHERE business_id = ? AND character_id = ?",
        { businessId, characterId },
        function(_, err) if cb then cb(err == nil, err) end end)
end

function Repo.DeleteStaff(businessId, cb)
    Omerta.DB.Query("DELETE FROM {business_staff} WHERE business_id = ?", { businessId },
        function(_, err) if cb then cb(err == nil, err) end end)
end

--------------------------------------------------------------------------------
-- Rumours
--------------------------------------------------------------------------------

function Repo.AddRumour(row, cb)
    Omerta.DB.Insert("rumours", row, cb)
end

function Repo.LiveRumours(seasonId, now, cb)
    Omerta.DB.Query(
        "SELECT * FROM {rumours} WHERE season_id = ? AND expires_at > ? " ..
        "ORDER BY created_at DESC LIMIT 100",
        { seasonId, now }, function(rows, err) cb(rows or {}, err) end)
end

-- Expired rumours are deleted rather than kept: a rumour nobody repeats any
-- more is not history, it is noise. Who planted it survives in the audit log,
-- which is where the question "who started that" actually gets answered.
function Repo.SweepRumours(now, cb)
    Omerta.DB.Query("DELETE FROM {rumours} WHERE expires_at <= ?", { now },
        function(_, err) if cb then cb(err == nil, err) end end)
end

function Repo.DeleteRumoursFor(businessId, cb)
    Omerta.DB.Query("DELETE FROM {rumours} WHERE business_id = ?", { businessId },
        function(_, err) if cb then cb(err == nil, err) end end)
end
