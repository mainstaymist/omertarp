-- Seasons service: lifecycle, the one-active invariant, path selection with
-- the D-009 transition matrix, caches, hooks, and staff commands (M3 design
-- review). Follows the M2 lifecycle contract: OnLoad declares schema and
-- migration 2; OnEnable does engine work behind WhenReady.

local MODULE = Omerta.Module.Get("seasons")

Omerta.Seasons = Omerta.Seasons or {}
Omerta.Seasons.Internal = Omerta.Seasons.Internal or {}
local Internal = Omerta.Seasons.Internal

Omerta.Config.Define("seasons.default_length_days", {
    type = "number", default = 28, min = 1, scope = "server",
    description = "Planned season length; sets ends_at when a season starts (a schedule, never a trigger).",
})

--------------------------------------------------------------------------------
-- Pure rules (headless-tested)
--------------------------------------------------------------------------------

local PATHS = { criminal = true, police = true, independent = true }

-- D-009: the entire allegiance ruleset lives in this table. Row = current
-- path ("none" before any choice); cell = set of reasons that permit the move.
-- Anything absent is forbidden — including every criminal<->police direction,
-- which would launder a season of one side's knowledge into the other.
local TRANSITIONS = {
    none = {
        criminal    = { initial_choice = true },
        police      = { initial_choice = true },
        independent = { initial_choice = true },
    },
    independent = {
        criminal = { family_recruitment = true },
    },
    police = {
        independent = { police_resignation = true, police_expulsion = true },
    },
    criminal = {},
}

-- Returns true, or false + reason. current may be nil (no choice yet).
function Internal.CanTransition(current, target, reason)
    if not PATHS[target] then
        return false, "unknown path '" .. tostring(target) .. "'"
    end
    if current ~= nil and not PATHS[current] then
        return false, "unknown current path '" .. tostring(current) .. "'"
    end
    if current == target then
        return false, "already on the " .. target .. " path"
    end
    local cell = TRANSITIONS[current or "none"][target]
    if not cell or not cell[reason] then
        return false, string.format("transition %s -> %s (%s) is not permitted",
            current or "none", target, tostring(reason))
    end
    return true
end

function Internal.CanLifecycle(state, action)
    if action == "start" then
        if state ~= "setup" then
            return false, "only a setup season can start (state: " .. tostring(state) .. ")"
        end
    elseif action == "end" then
        if state ~= "active" then
            return false, "only an active season can end (state: " .. tostring(state) .. ")"
        end
    else
        return false, "unknown lifecycle action '" .. tostring(action) .. "'"
    end
    return true
end

-- Staff convenience: resolve "the season I obviously mean" when no id is
-- given. Only unambiguous when exactly one season is in setup — otherwise
-- refuse and let the operator look at the list.
-- Returns id, or nil + reason.
function Internal.PickSoleSetupSeason(rows)
    local setup = {}
    for _, row in ipairs(rows) do
        if row.state == "setup" then setup[#setup + 1] = row end
    end
    if #setup == 0 then
        return nil, "no season is waiting in setup — create one first"
    end
    if #setup > 1 then
        local ids = {}
        for _, row in ipairs(setup) do ids[#ids + 1] = row.id end
        return nil, "several seasons are in setup (ids: " .. table.concat(ids, ", ") ..
            ") — name the one you mean"
    end
    return setup[1].id
end

-- The number the next season gets: one past the highest that has existed.
--
-- Derived from the seasons table itself, never from reading a number back out
-- of a name. Two facts are combined and the larger wins:
--
--   * THE HIGHEST NUMBER ANY SEASON CARRIES (Omerta.Seasons.NumberOf). This is
--     what survives a gap: delete season 4 of 1,2,3,4 and the next is still 5,
--     because 5 is what comes after the highest that ever existed. Reusing 4
--     would put two different seasons under one number in the audit log, which
--     is the one thing a season number is for.
--   * HOW MANY ROWS THERE ARE AT ALL. This is what survives a live database
--     full of NAMED seasons from before the numbering. Nine names and no
--     numbers produce #10 — the ruling in its own words, "just make the season
--     creation make the 10th season" — rather than starting again at 1
--     underneath nine seasons of history.
--
-- Both move in the only direction that matters: creating a season raises at
-- least one of them, so a number is never handed out twice while the rows that
-- carry it are still there.
function Internal.NextSeasonNumber(rows)
    rows = rows or {}
    local highest = 0
    for _, row in ipairs(rows) do
        local number = Omerta.Seasons.NumberOf(row)
        if number and number > highest then highest = number end
    end
    if #rows > highest then highest = #rows end
    return highest + 1
end

-- Boot invariant: at most one active season may exist in the table.
function Internal.CheckActiveInvariant(rows)
    local active = {}
    for _, row in ipairs(rows) do
        if row.state == "active" then active[#active + 1] = row.id end
    end
    if #active > 1 then
        return false, "multiple active seasons in the database (ids: " ..
            table.concat(active, ", ") .. ") — refusing all season operations"
    end
    return true
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local activeSeason = nil
Internal.Failed = false

local function runHook(name, ...)
    if Omerta.InEngine then hook.Run(name, ...) end
end

local function guard(cb)
    if Internal.Failed then
        if cb then cb(false, "seasons module is in a failed state (see server log)") end
        return false
    end
    return true
end

--------------------------------------------------------------------------------
-- Public API — reads
--------------------------------------------------------------------------------

function Omerta.Seasons.GetActive()
    return activeSeason
end

--------------------------------------------------------------------------------
-- Readiness
--------------------------------------------------------------------------------
-- Omerta.DB.WhenReady is not enough for anything that needs the ACTIVE SEASON
-- at boot. This module's own WhenReady callback runs a query, so a module
-- registering a later DB callback still sees GetActive() == nil — its callback
-- runs first and the answer has not arrived yet. M10 hit exactly that and
-- created no institutions; M11's treasuries and M13's businesses would have hit
-- it next.
--
-- Callbacks fire once the season state is RESOLVED, which includes resolving to
-- "there is no season" and to "the module failed" — a consumer left waiting
-- forever is worse than one told there is nothing.

local seasonsResolved = false
local readyCallbacks = {}

function Omerta.Seasons.WhenReady(fn)
    if seasonsResolved then
        -- Deferred rather than immediate, so a late registration behaves like
        -- an early one and never runs re-entrantly inside its caller.
        Omerta.DB.Internal.Defer(fn)
        return
    end
    readyCallbacks[#readyCallbacks + 1] = fn
end

function Internal.Resolved()
    if seasonsResolved then return end
    seasonsResolved = true
    local pending = readyCallbacks
    readyCallbacks = {}
    for _, fn in ipairs(pending) do
        local ok, err = pcall(fn)
        if not ok then
            Omerta.Log.Error("seasons", "a readiness callback failed: %s", tostring(err))
        end
    end
end

function Omerta.Seasons.GetPath(ply)
    local account = Omerta.Accounts.Get(ply)
    return account and account.season_path or nil
end

--------------------------------------------------------------------------------
-- Telling clients the number
--------------------------------------------------------------------------------
-- The front end names the city ("THE CITY · SEASON 10"), so the number has to
-- reach a client. Nothing else about a season does.
--
-- Sent on two occasions, and both are necessary:
--
--   * WHEN A CLIENT SAYS IT IS LISTENING. The join flow begins while the client
--     is still loading, and a net message aimed at a client that is not
--     listening yet is simply gone — no queue, no retry, no error in either
--     console. M4 learned that the expensive way and answered it with the
--     characters.ready handshake; Omerta.ClientReady is that same moment,
--     published so this module does not have to invent a second one.
--   * WHEN THE RUNNING SEASON CHANGES underneath everybody. Written out to
--     player.GetAll() by hand because Omerta.Net has no broadcast on purpose.
--
-- Omerta.Seasons.Number is refreshed on the server either way, so GetNumber()
-- answers in both realms rather than being a client-only curiosity.

-- A season that predates numbering still has a number: its ORDINAL.
--
-- The first version read the number off the label and stopped there, so any
-- season created before this change carried none and the front end read a bare
-- "THE CITY" forever. That was reported from the field on the first season
-- anybody actually had, which makes it the common case rather than the edge
-- one: numbering arrived after the seasons did.
--
-- The fallback counts rather than parses. "Season 10", "The Long Winter" and
-- an empty label are all equally unparseable and all equally the Nth season
-- that has existed, and the row order is a fact the database already keeps.
-- The label itself is left alone: it is what the operator typed, it is what
-- omerta_season_list has always shown them, and rewriting somebody's data to
-- make a display line easier is not a trade this project makes.
local function refreshNumber(done)
    done = done or function() end

    if not activeSeason then
        Omerta.Seasons.Number = nil
        done()
        return
    end

    local direct = Omerta.Seasons.NumberOf(activeSeason)
    if direct then
        Omerta.Seasons.Number = direct
        done()
        return
    end

    Internal.Repo.GetAllSeasons(function(rows, err)
        if err then
            -- Not fatal, and deliberately not silent: the city keeps running
            -- under a nameless number rather than refusing to start over a
            -- caption.
            Omerta.Log.Warn("seasons", "could not derive season number: %s", tostring(err))
        else
            Omerta.Seasons.Number = Omerta.Seasons.OrdinalOf(rows, activeSeason.id)
        end
        done()
    end)
end

local function tellNumber(targets)
    refreshNumber(function()
        if not Omerta.InEngine or targets == nil then return end
        -- Re-checked after the round trip, not before it: the answer may have
        -- come back from the database a tick after somebody disconnected, and
        -- Net.Send to a player who has gone is an error rather than a no-op.
        local live = {}
        if type(targets) == "table" then
            for _, ply in ipairs(targets) do
                if IsValid(ply) then live[#live + 1] = ply end
            end
        elseif IsValid(targets) then
            live[1] = targets
        end
        if #live == 0 then return end
        Omerta.Net.Send("seasons.number", { number = Omerta.Seasons.Number or 0 }, live)
    end)
end

local function tellEveryone()
    if not Omerta.InEngine then refreshNumber() return end
    tellNumber(player.GetAll())
end

--------------------------------------------------------------------------------
-- Path transitions (all funnel through applyTransition; there is no bypass)
--------------------------------------------------------------------------------

-- account: the M2 account object (cache-authoritative for season_path).
-- ply may be nil (self-test synthetic accounts) — hooks fire only with a ply.
local function applyTransition(account, ply, target, reason, cb)
    if not guard(cb) then return end
    if not activeSeason then
        if cb then cb(false, "no active season") end
        return
    end
    local current = account.season_path
    local ok, why = Internal.CanTransition(current, target, reason)
    if not ok then
        if cb then cb(false, why) end
        return
    end
    Internal.Repo.SetPath(account.id, activeSeason.id, target, os.time(), function(sok, err)
        if not sok then
            if cb then cb(false, err) end
            return
        end
        account.season_path = target
        if current == nil then
            Omerta.Log.Audit("season.path_chosen", {
                actor = account.steamid64, account_id = account.id,
                season_id = activeSeason.id, path = target,
            })
        else
            Omerta.Log.Audit("season.path_changed", {
                actor = account.steamid64, account_id = account.id,
                season_id = activeSeason.id, old = current, new = target, reason = reason,
            })
        end
        if cb then cb(true) end
        if ply then
            if current == nil then
                runHook("Omerta.PathChosen", ply, target)
            else
                runHook("Omerta.PathChanged", ply, current, target, reason)
            end
        end
    end)
end
Internal.ApplyTransition = applyTransition -- self-test entry (synthetic accounts)

local function transitionForPlayer(ply, target, reason, cb)
    local account = Omerta.Accounts.Get(ply)
    if not account then
        if cb then cb(false, "account not loaded") end
        return
    end
    applyTransition(account, ply, target, reason, cb)
end

function Omerta.Seasons.SetPath(ply, path, cb)
    transitionForPlayer(ply, path, "initial_choice", cb)
end

-- M10's recruitment flow calls this when a family formally takes in an
-- independent (D-009: one-way).
function Omerta.Seasons.ConvertToCriminal(ply, cb)
    transitionForPlayer(ply, "criminal", "family_recruitment", cb)
end

-- M10's department flow calls this on resignation or expulsion (D-009:
-- one-way; an ex-officer can never join a family this season).
function Omerta.Seasons.LeavePolice(ply, expelled, cb)
    transitionForPlayer(ply, "independent",
        expelled and "police_expulsion" or "police_resignation", cb)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

-- Creating a season takes no name.
--
-- WHY THE `label` COLUMN STAYED. It now holds the number as its text ("10"),
-- and that is the whole change: no migration 14, no second column that can
-- disagree with the first, and every existing reader — the boot log, whoami,
-- omerta_season_list, the self-test's `DELETE ... WHERE label = ? AND state = ?`
-- guard that stops it ever touching a real season — keeps working against the
-- same field it always read. Dropping it would have meant a migration on both
-- dialects, a NOT NULL to relax, and a rewrite of all of those, to buy nothing
-- a numeric string in the same column does not already buy. It also keeps the
-- seasons a live database already has: they hold their names, read as their
-- names, and simply carry no number (Omerta.Seasons.NumberOf).
--
-- An explicit label is still accepted and there is exactly ONE caller that
-- passes one — the in-engine self-test, which names its row `__selftest__` so
-- its cleanup can delete that row and nothing else. Staff never type a label.
function Omerta.Seasons.Create(opts, cb)
    if not guard(cb) then return end
    opts = opts or {}
    cb = cb or function() end

    local ruleset = opts.ruleset_version or "1"

    local function insert(label)
        Internal.Repo.CreateSeason(label, ruleset, os.time(), function(id, err)
            if not id then cb(nil, err) return end
            Omerta.Log.Audit("season.created", {
                actor = opts.actor, season_id = id, label = label,
            })
            Omerta.Log.Info("seasons", "season #%d created — %s (setup)",
                id, Omerta.Seasons.Title({ label = label }))
            cb(id)
        end)
    end

    if opts.label ~= nil then
        if type(opts.label) ~= "string" or opts.label == "" or #opts.label > 64 then
            cb(nil, "season label must be a non-empty string of at most 64 characters")
            return
        end
        insert(opts.label)
        return
    end

    -- The number is worked out from the seasons that already exist, on the
    -- server, at the moment of creation. Nobody is asked for it and nobody may
    -- supply it: a number handed in from anywhere else is a number that can
    -- collide with one already in the audit log.
    Internal.Repo.GetAllSeasons(function(rows, err)
        if err then cb(nil, err) return end
        insert(tostring(Internal.NextSeasonNumber(rows)))
    end)
end

function Omerta.Seasons.Start(seasonId, actorSid, cb)
    if not guard(cb) then return end
    if activeSeason then
        if cb then cb(false, "season #" .. activeSeason.id .. " is already active") end
        return
    end
    Internal.Repo.GetSeason(seasonId, function(season, err)
        if not season then
            if cb then cb(false, err or ("no season #" .. tostring(seasonId))) end
            return
        end
        local ok, why = Internal.CanLifecycle(season.state, "start")
        if not ok then
            if cb then cb(false, why) end
            return
        end
        local now = os.time()
        local endsAt = now + Omerta.Config.Get("seasons.default_length_days") * 86400
        Internal.Repo.StartSeason(season.id, now, endsAt, function(sok, serr)
            if not sok then
                if cb then cb(false, serr) end
                return
            end
            season.state, season.started_at, season.ends_at = "active", now, endsAt
            activeSeason = season
            -- The city everybody is standing in just changed; the front end
            -- says which one, so everybody is told which one.
            tellEveryone()
            Omerta.Log.Audit("season.started", { actor = actorSid, season_id = season.id })
            Omerta.Log.Info("seasons", "season #%d started — %s (planned end %s)",
                season.id, Omerta.Seasons.Title(season), os.date("%Y-%m-%d", endsAt))
            if cb then cb(true) end
            runHook("Omerta.SeasonStarted", season)
        end)
    end)
end

function Omerta.Seasons.End(seasonId, actorSid, cb)
    if not guard(cb) then return end
    Internal.Repo.GetSeason(seasonId, function(season, err)
        if not season then
            if cb then cb(false, err or ("no season #" .. tostring(seasonId))) end
            return
        end
        local ok, why = Internal.CanLifecycle(season.state, "end")
        if not ok then
            if cb then cb(false, why) end
            return
        end
        local now = os.time()
        Internal.Repo.EndSeason(season.id, now, function(sok, serr)
            if not sok then
                if cb then cb(false, serr) end
                return
            end
            season.state, season.ended_at = "ended", now
            if activeSeason and activeSeason.id == season.id then
                activeSeason = nil
                -- Online players' cached paths belonged to the ended season.
                if Omerta.InEngine then
                    for _, p in ipairs(player.GetAll()) do
                        local account = Omerta.Accounts.Get(p)
                        if account then account.season_path = nil end
                    end
                end
            end
            tellEveryone()
            Omerta.Log.Audit("season.ended", { actor = actorSid, season_id = season.id })
            Omerta.Log.Info("seasons", "season #%d ended — %s",
                season.id, Omerta.Seasons.Title(season))
            if cb then cb(true) end
            runHook("Omerta.SeasonEnded", season)
        end)
    end)
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function MODULE:OnLoad()
    Omerta.DB.DefineTable("seasons", {
        columns = {
            { name = "id",              type = "id" },
            { name = "label",           type = "text", length = 64, null = false },
            { name = "state",           type = "text", length = 16, null = false },
            { name = "ruleset_version", type = "text", length = 32, null = false, default = "1" },
            { name = "created_at",      type = "timestamp", null = false },
            { name = "started_at",      type = "timestamp" },
            { name = "ends_at",         type = "timestamp" },
            { name = "ended_at",        type = "timestamp" },
            { name = "summary",         type = "json" }, -- M23 fills at archive time
        },
        indexes = { { "state" } },
    })
    Omerta.DB.DefineTable("account_seasons", {
        columns = {
            { name = "account_id", type = "ref", null = false },
            { name = "season_id",  type = "ref", null = false },
            { name = "path",       type = "text", length = 16, null = false },
            { name = "chosen_at",  type = "timestamp", null = false },
        },
        primary = { "account_id", "season_id" },
        indexes = { { "season_id" } },
    })

    Omerta.DB.AddMigration(2, "seasons and path selection", function(m)
        m:CreateTable("seasons")
        m:CreateTable("account_seasons")
    end)
end

function MODULE:OnEnable()
    Omerta.DB.WhenReady(function()
        Internal.Repo.GetAllSeasons(function(rows, err)
            if err then
                Internal.Failed = true
                Omerta.Log.Error("seasons", "SEASONS FAILED — could not load seasons: %s", err)
                Internal.Resolved()
                return
            end
            local ok, why = Internal.CheckActiveInvariant(rows)
            if not ok then
                Internal.Failed = true
                Omerta.Log.Error("seasons", "SEASONS FAILED — %s", why)
                Internal.Resolved()
                return
            end
            for _, row in ipairs(rows) do
                if row.state == "active" then activeSeason = row end
            end
            -- Nobody to send it to at boot; the handshake below catches every
            -- client that arrives afterwards, including the listen-server host.
            refreshNumber()
            if activeSeason then
                Omerta.Log.Info("seasons", "active season: #%d — %s",
                    activeSeason.id, Omerta.Seasons.Title(activeSeason))
            else
                Omerta.Log.Info("seasons",
                    "no active season — character creation will be unavailable until one is started " ..
                    "(omerta_season_create / omerta_season_start)")
            end
            Internal.Resolved()
        end)
    end)

    if not Omerta.InEngine then return end

    -- First consumer of M2's extension point: carry the player's path for the
    -- active season onto the cached account object.
    -- The number, the moment the client is demonstrably able to hear it.
    -- Behind WhenReady because a client can beat the boot query: without it a
    -- listen-server host is told "no season" once, permanently, which is the
    -- exact trap M3 documents for its own consumers.
    hook.Add("Omerta.ClientReady", "omerta.seasons.number", function(ply)
        Omerta.Seasons.WhenReady(function()
            if IsValid(ply) then tellNumber(ply) end
        end)
    end)

    hook.Add("Omerta.AccountLoaded", "omerta.seasons.path", function(ply, account)
        if not activeSeason then return end
        Internal.Repo.GetPathRow(account.id, activeSeason.id, function(row)
            if row and IsValid(ply) then account.season_path = row.path end
        end)
    end)

    -- Staff commands (server console or superadmin), all audited via the API.
    local function staffOnly(ply)
        return not IsValid(ply) or ply:IsSuperAdmin()
    end
    local function actorOf(ply)
        return IsValid(ply) and ply:SteamID64() or "console"
    end

    concommand.Add("omerta_season_status", function(ply)
        if not staffOnly(ply) then return end
        if Internal.Failed then
            Omerta.Log.Error("seasons", "status: FAILED state — see boot log")
        elseif activeSeason then
            Omerta.Log.Info("seasons", "status: season #%d (%s) active since %s, planned end %s",
                activeSeason.id, Omerta.Seasons.Title(activeSeason),
                os.date("%Y-%m-%d", activeSeason.started_at or 0),
                os.date("%Y-%m-%d", activeSeason.ends_at or 0))
        else
            Omerta.Log.Info("seasons", "status: no active season")
        end
    end)

    -- No arguments. A name typed here used to become the season's identity;
    -- seasons are numbered now and the number is the server's to work out, so
    -- anything typed after the command is said back rather than silently
    -- dropped — somebody who types "omerta_season_create Season 11" has an
    -- expectation about what season they just made and deserves to be corrected.
    concommand.Add("omerta_season_create", function(ply, _, args)
        if not staffOnly(ply) then return end
        if args[1] then
            Omerta.Log.Warn("seasons", "omerta_season_create takes no arguments — " ..
                "seasons are numbered, not named; ignoring '%s'", table.concat(args, " "))
        end
        Omerta.Seasons.Create({ actor = actorOf(ply) }, function(id, err)
            if not id then Omerta.Log.Error("seasons", "create failed: %s", tostring(err)) end
        end)
    end)

    concommand.Add("omerta_season_list", function(ply)
        if not staffOnly(ply) then return end
        Internal.Repo.GetAllSeasons(function(rows, err)
            if err then Omerta.Log.Error("seasons", "list failed: %s", err) return end
            if #rows == 0 then Omerta.Log.Info("seasons", "no seasons exist yet") return end
            Omerta.Log.Info("seasons", "%d season(s):", #rows)
            for _, row in ipairs(rows) do
                local when = row.state == "active"
                        and ("started " .. os.date("%Y-%m-%d", row.started_at or 0) ..
                             ", planned end " .. os.date("%Y-%m-%d", row.ends_at or 0))
                    or row.state == "ended"
                        and ("ended " .. os.date("%Y-%m-%d", row.ended_at or 0))
                    or ("created " .. os.date("%Y-%m-%d", row.created_at or 0))
                Omerta.Log.Info("seasons", "  #%d  %-8s  %s  (%s)",
                    row.id, row.state, Omerta.Seasons.Title(row), when)
            end
        end)
    end)

    concommand.Add("omerta_season_start", function(ply, _, args)
        if not staffOnly(ply) then return end
        local function start(id)
            Omerta.Seasons.Start(id, actorOf(ply), function(ok, err)
                if not ok then Omerta.Log.Error("seasons", "start failed: %s", tostring(err)) end
            end)
        end
        local id = tonumber(args[1])
        if id then start(id) return end
        -- No id given: start the sole season in setup, if there is exactly one.
        Internal.Repo.GetAllSeasons(function(rows, err)
            if err then Omerta.Log.Error("seasons", "start failed: %s", err) return end
            local sole, why = Internal.PickSoleSetupSeason(rows)
            if not sole then
                Omerta.Log.Error("seasons", "%s (usage: omerta_season_start [id]; " ..
                    "see omerta_season_list)", why)
                return
            end
            start(sole)
        end)
    end)

    concommand.Add("omerta_season_end", function(ply, _, args)
        if not staffOnly(ply) then return end
        local id = tonumber(args[1])
        if not id then Omerta.Log.Error("seasons", "usage: omerta_season_end <id>") return end
        Omerta.Seasons.End(id, actorOf(ply), function(ok, err)
            if not ok then Omerta.Log.Error("seasons", "end failed: %s", tostring(err)) end
        end)
    end)
end
