-- All SQL for M19 lives here. Gameplay code calls these methods and never
-- writes a query, per the project's hard rule.

Omerta.Injury = Omerta.Injury or {}
Omerta.Injury.Internal = Omerta.Injury.Internal or {}
Omerta.Injury.Internal.Repo = Omerta.Injury.Internal.Repo or {}
local Repo = Omerta.Injury.Internal.Repo

--------------------------------------------------------------------------------
-- Character state
--------------------------------------------------------------------------------
-- One row per character, upserted on character_id. The row is the truth; the
-- body entity is only a representation of it.

-- cb(ok, err)
function Repo.SetState(characterId, state, since, expiresAt, treatedBy, cb)
    Omerta.DB.Upsert("character_injury", {
        character_id = characterId,
        state = state,
        since = since,
        expires_at = expiresAt or Omerta.DB.NULL,
        treated_by_character_id = treatedBy or Omerta.DB.NULL,
    }, { "character_id" }, cb)
end

-- cb(row, err); row is nil when the character has never been hurt.
function Repo.GetState(characterId, cb)
    Omerta.DB.QueryOne(
        "SELECT * FROM {character_injury} WHERE character_id = ?",
        { characterId }, cb)
end

-- Everyone who is not healthy — the dead included.
--
-- Loaded once at boot so timers RESUME rather than restart: a restart that
-- resets the bleed-out clock would rescue everyone who was about to die,
-- making "wait for the nightly restart" a medical procedure. The dead are in
-- the list because their corpses have to come back too; a city where the dead
-- vanish on restart is one where nobody can prove anything happened.
function Repo.ListActive(cb)
    Omerta.DB.Query(
        "SELECT * FROM {character_injury} WHERE state <> ?",
        { Omerta.Injury.STATE.HEALTHY },
        function(rows, err) cb(rows or {}, err) end)
end

--------------------------------------------------------------------------------
-- Impairments
--------------------------------------------------------------------------------
-- A broken leg, and whatever Tech §17 adds after it. One row per (character,
-- impairment), so the second impairment is a row rather than a migration.
--
-- `expires_at` is absolute, like every other clock in this module: a restart
-- resumes a leg that was halfway to knitting instead of mending it, and one
-- that finished knitting while the server was down is cleared on load rather
-- than resurrected.

-- cb(ok, err)
function Repo.SetImpairment(characterId, impairment, since, expiresAt, cb)
    Omerta.DB.Upsert("character_impairments", {
        character_id = characterId,
        impairment = impairment,
        since = since,
        expires_at = expiresAt or Omerta.DB.NULL,
    }, { "character_id", "impairment" }, cb)
end

-- cb(ok, err)
function Repo.ClearImpairment(characterId, impairment, cb)
    cb = cb or function() end
    Omerta.DB.Query(
        "DELETE FROM {character_impairments} WHERE character_id = ? AND impairment = ?",
        { characterId, impairment }, function(_, err) cb(err == nil, err) end)
end

-- Every impairment there is. Read once at boot; the caller decides which are
-- still live. Unfiltered because "what is still running" is a question about
-- the clock, and the clock belongs to the module rather than to the query.
function Repo.ListImpairments(cb)
    Omerta.DB.Query("SELECT * FROM {character_impairments}", {},
        function(rows, err) cb(rows or {}, err) end)
end

--------------------------------------------------------------------------------
-- Bodies
--------------------------------------------------------------------------------

-- cb(ok, err)
function Repo.SaveBody(seasonId, characterId, mapName, pos, yaw, cb)
    Omerta.DB.Upsert("bodies", {
        season_id = seasonId,
        character_id = characterId,
        map_name = mapName,
        pos_x = math.floor(pos.x), pos_y = math.floor(pos.y), pos_z = math.floor(pos.z),
        ang_y = math.floor(yaw or 0),
        created_at = os.time(),
    }, { "character_id" }, cb)
end

function Repo.MoveBody(characterId, pos, cb)
    cb = cb or function() end
    Omerta.DB.Query(
        "UPDATE {bodies} SET pos_x = ?, pos_y = ?, pos_z = ? WHERE character_id = ?",
        { math.floor(pos.x), math.floor(pos.y), math.floor(pos.z), characterId },
        function(_, err) cb(err == nil, err) end)
end

function Repo.RemoveBody(characterId, cb)
    cb = cb or function() end
    Omerta.DB.Query("DELETE FROM {bodies} WHERE character_id = ?", { characterId },
        function(_, err) cb(err == nil, err) end)
end

function Repo.ListBodies(seasonId, mapName, cb)
    Omerta.DB.Query(
        "SELECT * FROM {bodies} WHERE season_id = ? AND map_name = ?",
        { seasonId, mapName }, function(rows, err) cb(rows or {}, err) end)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
-- Append-only, and the reason this milestone has a table it could technically
-- live without. M15 will want to know a body was moved, M17 who treated whom,
-- M21 that a shooting happened, and M24 will be asked "who put him down and
-- who picked him up". Reconstructing that from an audit log written for a
-- different purpose is how you end up unable to answer it.

function Repo.LogEvent(row, cb)
    Omerta.DB.Insert("injury_events", row, cb or function() end)
end

function Repo.EventsFor(characterId, limit, cb)
    Omerta.DB.Query(
        "SELECT * FROM {injury_events} WHERE character_id = ? ORDER BY id DESC LIMIT " ..
            math.floor(math.max(1, math.min(limit or 20, 100))),
        { characterId }, function(rows, err) cb(rows or {}, err) end)
end
