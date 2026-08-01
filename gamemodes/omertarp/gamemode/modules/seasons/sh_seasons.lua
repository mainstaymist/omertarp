-- Seasons: the shared half.
--
-- The service is server-side and stays there — a season's rows, its lifecycle
-- and every path decision are the server's business. What crosses to the client
-- is ONE NUMBER, because the front end names the city everybody is playing in
-- and a season number is as public as the map name.
--
-- SEASONS ARE NUMBERED, NOT NAMED (project lead, 2026-08-01: "seasons wont be
-- named they will be numbered so I dont have to keep typing 'Season 10'"). The
-- number lives in the `label` column — sv_seasons.lua's Create says why that
-- column was kept rather than replaced — and the two functions that read it
-- live here, shared, so a server log line and the client's front end cannot
-- end up disagreeing about what season #10 is called.

Omerta.Seasons = Omerta.Seasons or {}

--------------------------------------------------------------------------------
-- Reading a season's number (headless-tested)
--------------------------------------------------------------------------------

-- The number a season row carries, or nil.
--
-- A READ, not a parse. The label column holds the number and nothing else, so
-- this accepts a plain run of digits and refuses everything else. A season from
-- before the numbering (whatever an operator typed) and the self-test's own
-- `__selftest__` row therefore have NO number, and saying so is far better than
-- recovering a "10" out of the middle of a sentence — the moment a name is
-- parsed for a number, "Season 10" and "The 10th of Never" become the same
-- thing and the sequence starts handing out duplicates.
--
-- Accepts the column as either a string or a number, because a text column is
-- read back as a string on one backend and can arrive as a number on the other.
function Omerta.Seasons.NumberOf(season)
    if type(season) ~= "table" then return nil end
    local label = season.label
    if type(label) == "number" then label = tostring(label) end
    if type(label) ~= "string" then return nil end
    if not label:match("^%d+$") then return nil end
    local number = tonumber(label)
    if not number or number < 1 then return nil end
    return number
end

-- Which season this is by COUNT — the Nth ever created — for a season whose
-- label is not a number and cannot be read as one.
--
-- Ordered by id rather than by created_at: ids are handed out by the database
-- in creation order and are unique, where two seasons created in the same
-- second would tie on a timestamp and sort differently on two backends. A
-- season that is not in the list has no ordinal rather than a guessed one.
--
-- Pure, and takes the rows it is asked about, so the headless suite can pin
-- the gap case without a database.
function Omerta.Seasons.OrdinalOf(rows, seasonId)
    if type(rows) ~= "table" or not seasonId then return nil end

    local ids = {}
    for _, row in ipairs(rows) do
        if row and row.id then ids[#ids + 1] = row.id end
    end
    table.sort(ids)

    for index, id in ipairs(ids) do
        if id == seasonId then return index end
    end
    return nil
end

-- What a season is called, on screen and in the log. A legacy named season
-- keeps its name: it is what the operator called it and what omerta_season_list
-- has always shown them.
function Omerta.Seasons.Title(season)
    local number = Omerta.Seasons.NumberOf(season)
    if number then return "Season " .. number end
    if type(season) == "table" and season.label ~= nil then
        return tostring(season.label)
    end
    return "no season"
end

--------------------------------------------------------------------------------
-- The one season fact a client is given
--------------------------------------------------------------------------------
-- The number of the running season, and nothing else. Zero on the wire means
-- "no season is running", which the front end says plainly rather than
-- inventing one.
--
-- A NUMBER rather than the label string, deliberately: M6's leak audit reviews
-- every string field the server sends to clients, and a season has no business
-- being the exception that teaches people the audit cries wolf. It is also the
-- only shape the front end actually wants — "SEASON 10" is assembled at the
-- draw call from the same Title() the server logs with.

Omerta.Net.Register("seasons.number", {
    realm = "server_to_client",
    schema = { { name = "number", type = "uint", bits = 16 } },
    handler = function(payload)
        Omerta.Seasons.Number = payload.number > 0 and payload.number or nil
        hook.Run("Omerta.SeasonNumber", Omerta.Seasons.Number)
    end,
})

-- The running season's number in EITHER realm: the server refreshes it whenever
-- the active season changes, the client is told. nil means no season is running
-- — never a guess, and never a stale number from the season before last.
function Omerta.Seasons.GetNumber()
    return Omerta.Seasons.Number
end
