-- Writing and reading events.

local MODULE = Omerta.Module.Get("events")

Omerta.Events = Omerta.Events or {}
Omerta.Events.Internal = Omerta.Events.Internal or {}
local Internal = Omerta.Events.Internal

--------------------------------------------------------------------------------
-- Writing
--------------------------------------------------------------------------------

-- cb(eventId, err). `pos` is optional; `data` is an arbitrary table, encoded
-- opaquely — the column is a bag for whatever the type needs, and nothing
-- queries inside it.
function Omerta.Events.Create(spec, cb)
    cb = cb or function() end

    spec = spec or {}
    if not spec.season_id then
        local season = Omerta.Seasons.GetActive()
        if season then spec.season_id = season.id end
    end

    local ok, why = Omerta.Events.Validate(spec)
    if not ok then
        -- Loud: an event that failed to record is a fact the city will never
        -- find out, and silently dropping one would be indistinguishable from
        -- it never having happened.
        Omerta.Log.Error("events", "refused to record an event: %s", tostring(why))
        cb(nil, why)
        return
    end

    local pos = spec.pos
    Internal.Repo.Insert({
        season_id = spec.season_id,
        type = spec.type,
        subject_character_id = spec.subject_character_id or Omerta.DB.NULL,
        actor_character_id = spec.actor_character_id or Omerta.DB.NULL,
        map_name = spec.map_name or (Omerta.InEngine and game.GetMap() or "unknown"),
        pos_x = pos and math.floor(pos.x) or Omerta.DB.NULL,
        pos_y = pos and math.floor(pos.y) or Omerta.DB.NULL,
        pos_z = pos and math.floor(pos.z) or Omerta.DB.NULL,
        at = spec.at or os.time(),
        data = Internal.Encode(spec.data),
        published_at = Omerta.DB.NULL,
    }, function(id, err)
        if not id then
            Omerta.Log.Error("events", "could not record '%s': %s",
                tostring(spec.type), tostring(err))
            cb(nil, err)
            return
        end
        hook.Run("Omerta.EventRecorded", id, spec.type, spec)
        cb(id)
    end)
end

-- Encoding is injected in tests, exactly as M2's audit rows are.
function Internal.Encode(data)
    if not data then return Omerta.DB.NULL end
    if Omerta.InEngine then return util.TableToJSON(data) end
    return Internal.TestEncode and Internal.TestEncode(data) or ""
end

function Internal.Decode(text)
    if not text or text == "" then return nil end
    if Omerta.InEngine then return util.JSONToTable(text) end
    return Internal.TestDecode and Internal.TestDecode(text) or nil
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

local function hydrate(row)
    if not row then return nil end
    row.data = Internal.Decode(row.data)
    return row
end

function Omerta.Events.Get(id, cb)
    Internal.Repo.Get(id, function(row, err) cb(hydrate(row), err) end)
end

function Omerta.Events.ForCharacter(characterId, limit, cb)
    Internal.Repo.ForCharacter(characterId, limit, function(rows, err)
        for _, row in ipairs(rows) do hydrate(row) end
        cb(rows, err)
    end)
end

-- M21's cursor: everything after an id, oldest first.
function Omerta.Events.Since(afterId, limit, cb)
    Internal.Repo.Since(afterId, limit, function(rows, err)
        for _, row in ipairs(rows) do hydrate(row) end
        cb(rows, err)
    end)
end

function Omerta.Events.MarkPublished(id, cb)
    Internal.Repo.MarkPublished(id, os.time(), cb)
end

--------------------------------------------------------------------------------
-- Staff
--------------------------------------------------------------------------------

function Internal.RegisterCommands()
    concommand.Add("omerta_events", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        local after = tonumber(args[1] or "") or 0
        Omerta.Events.Since(after, 25, function(rows)
            if #rows == 0 then Omerta.Log.Info("events", "nothing after #%d", after) return end
            for _, row in ipairs(rows) do
                Omerta.Log.Info("events", "  #%-5d %-20s subject %-6s actor %-6s %s",
                    row.id, row.type,
                    tostring(row.subject_character_id or "-"),
                    tostring(row.actor_character_id or "-"),
                    os.date("%Y-%m-%d %H:%M", row.at))
            end
        end)
    end)
end

function MODULE:OnLoad()
    Omerta.DB.DefineTable("events", {
        columns = {
            { name = "id",                   type = "id" },
            { name = "season_id",            type = "ref", null = false },
            { name = "type",                 type = "text", length = 48, null = false },
            { name = "subject_character_id", type = "ref" },
            { name = "actor_character_id",   type = "ref" },
            { name = "map_name",             type = "text", length = 64, null = false },
            { name = "pos_x",                type = "int" },
            { name = "pos_y",                type = "int" },
            { name = "pos_z",                type = "int" },
            { name = "at",                   type = "timestamp", null = false },
            -- Opaque. The type decides what goes in; nothing queries inside it.
            { name = "data",                 type = "json" },
            -- M21's, and reserved now rather than added later: a migration
            -- against a table this central is more disruptive than a column
            -- that sits empty for a milestone.
            { name = "published_at",         type = "timestamp" },
        },
        indexes = {
            { "season_id", "at" },
            { "subject_character_id" },
            { "type" },
        },
    })

    Omerta.DB.AddMigration(13, "durable event log", function(m)
        m:CreateTable("events")
    end)
end

function MODULE:OnEnable()
    if not Omerta.InEngine then return end
    Internal.RegisterCommands()
end
