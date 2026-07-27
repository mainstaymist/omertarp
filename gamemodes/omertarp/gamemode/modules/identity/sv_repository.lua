-- Identity repository: the only file that writes SQL about who knows whom.

Omerta.Identity = Omerta.Identity or {}
Omerta.Identity.Internal = Omerta.Identity.Internal or {}
local Internal = Omerta.Identity.Internal
Internal.Repo = Internal.Repo or {}
local Repo = Internal.Repo

-- Upsert, because learning a name you already know is not an error — it may
-- arrive from a better source (a police record confirming a rumor).
function Repo.Learn(observerId, subjectId, name, source, now, cb)
    Omerta.DB.Upsert("identity_knowledge", {
        observer_id = observerId,
        subject_id = subjectId,
        learned_name = name,
        source = source,
        learned_at = now,
        confidence = 100,
    }, { "observer_id", "subject_id" }, cb)
end

-- Everything one character knows. Bounded by how many people they have
-- actually met, so loading it whole on spawn is cheap.
function Repo.LoadForObserver(observerId, cb)
    Omerta.DB.Query(
        "SELECT subject_id, learned_name, source FROM {identity_knowledge} WHERE observer_id = ?",
        { observerId }, cb)
end

function Repo.Forget(observerId, subjectId, cb)
    Omerta.DB.Query(
        "DELETE FROM {identity_knowledge} WHERE observer_id = ? AND subject_id = ?",
        { observerId, subjectId }, function(_, err) if cb then cb(err == nil, err) end end)
end

-- "Who knows me?" — for staff investigation and, later, witness protection.
function Repo.WhoKnows(subjectId, cb)
    Omerta.DB.Query(
        "SELECT observer_id, learned_name, source FROM {identity_knowledge} WHERE subject_id = ?",
        { subjectId }, cb)
end

--------------------------------------------------------------------------------
-- Self-test cleanup only
--------------------------------------------------------------------------------

function Repo.DeleteAllFor(characterId, cb)
    Omerta.DB.Query(
        "DELETE FROM {identity_knowledge} WHERE observer_id = ? OR subject_id = ?",
        { characterId, characterId },
        function(_, err) if cb then cb(err == nil, err) end end)
end
