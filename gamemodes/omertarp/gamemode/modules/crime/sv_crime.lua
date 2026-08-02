-- Wiring: configuration, the schema, the registrations, and the clock.

local MODULE = Omerta.Module.Get("crime")

Omerta.Crime = Omerta.Crime or {}
Omerta.Crime.Internal = Omerta.Crime.Internal or {}
local Internal = Omerta.Crime.Internal

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------
-- Every number here is a pacing decision that will be tuned against a real map,
-- which is why none of them is a constant.

Omerta.Config.Define("crime.cooldown_seconds", {
    type = "number", default = 3600, min = 0, max = 86400, scope = "server",
    description = "How long a premises is left alone after a robbery of any outcome (D-048).",
})

Omerta.Config.Define("crime.handful_cents", {
    type = "number", default = 12000, min = 100, max = 100000, scope = "server",
    description = "The most one grab at a register can lift, before bulk has its say.",
})

Omerta.Config.Define("crime.observer_range", {
    type = "number", default = 1400, min = 128, max = 8000, scope = "server",
    description = "How far away somebody could plausibly have seen it (the M15 hand-off).",
})

Omerta.Config.Define("crime.nerve_seconds", {
    type = "number", default = 20, min = 0, max = 600, scope = "server",
    description = "How often the clerk reconsiders while nothing else is happening.",
})

Omerta.Config.Define("crime.report_delay_seconds", {
    type = "number", default = 90, min = 0, max = 3600, scope = "server",
    description = "How long after the crew leaves the clerk gets to a telephone (D-051).",
})

Omerta.Config.Define("crime.discovery_seconds", {
    type = "number", default = 240, min = 0, max = 3600, scope = "server",
    description = "How long a dead clerk lies there before somebody finds him (D-052).",
})

Omerta.Config.Define("crime.float_scale", {
    type = "number", default = 1, min = 0, max = 4, scope = "server",
    description = "Multiplier on the unowned-store float. ZERO TURNS IT OFF ENTIRELY (D-048).",
})

Omerta.Config.Define("crime.float_minutes", {
    type = "number", default = 5, min = 1, max = 60, scope = "server",
    description = "How often an unowned register is topped up.",
})

--------------------------------------------------------------------------------
-- Event types
--------------------------------------------------------------------------------
-- `public` says only that the type is ELIGIBLE to reach a newspaper. Whether
-- any particular one is printable is M21's decision, because it depends on who
-- witnessed what.

function Internal.RegisterEvents()
    Omerta.Events.Register("crime.robbery", {
        name = "Robbery",
        -- Written at the demand, not at the resolution: a robbery cannot be
        -- hidden by finishing it badly.
        public = true,
    })

    Omerta.Events.Register("crime.clerk_killed", {
        name = "Shopkeeper killed",
        -- The loudest thing in the game (D-052). A murder committed during a
        -- robbery is the canonical thing the whole justice track exists to
        -- investigate.
        public = true,
    })
end

--------------------------------------------------------------------------------
-- Staff
--------------------------------------------------------------------------------

function Internal.RegisterCommands()
    -- Placing a clerk. Deliberately a staff command rather than a property of
    -- the business row: where the man stands is a content decision about a
    -- specific room, and M13 already places counters this way.
    concommand.Add("omerta_clerk_place", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        local business = Omerta.Business.Internal.AtCounter(caller)
        if not business then
            Omerta.Log.Info("crime", "stand at a counter first")
            return
        end
        local trace = caller:GetEyeTrace()
        local clerk = Omerta.Crime.SpawnClerk(business, trace.HitPos,
            Angle(0, caller:EyeAngles().y + 180, 0))
        Omerta.Log.Info("crime", "placed a clerk at %s (%s)",
            business.name, clerk and clerk.OmertaPersonality or "none")
    end)

    concommand.Add("omerta_crime_operations", function(caller)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        local count = 0
        for id, operation in pairs(Internal.Live) do
            count = count + 1
            Omerta.Log.Info("crime", "  #%-5d %-10s business %-4s took %s",
                id, operation.state, tostring(operation.business_id),
                Omerta.Money.Format(operation.take_cents or 0))
        end
        if count == 0 then Omerta.Log.Info("crime", "nothing is happening") end
    end)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function MODULE:OnLoad()
    Omerta.DB.DefineTable("crime_operations", {
        columns = {
            { name = "id",          type = "id" },
            { name = "season_id",   type = "ref", null = false },
            -- The durable fact the operation hangs off. M14 is the first
            -- milestone other than death to write one.
            { name = "event_id",    type = "ref", null = false },
            { name = "type_key",    type = "text", length = 32, null = false },
            { name = "business_id", type = "ref", null = false },
            { name = "state",       type = "text", length = 16, null = false },
            { name = "resolution",  type = "text", length = 16 },
            -- Server-side and never networked. A client that knew the clerk's
            -- seed would know his answer before asking.
            { name = "seed",        type = "int", null = false },
            { name = "map_name",    type = "text", length = 64, null = false },
            { name = "pos_x",       type = "int" },
            { name = "pos_y",       type = "int" },
            { name = "pos_z",       type = "int" },
            { name = "started_at",  type = "timestamp", null = false },
            { name = "state_at",    type = "timestamp", null = false },
            { name = "ended_at",    type = "timestamp" },
            -- ABSOLUTE, never a countdown. M19 learned this twice: a restart
            -- that reset the clock would make waiting for the nightly restart a
            -- robbery technique.
            { name = "deadline_at", type = "timestamp" },
            -- A RECORD, never a source of truth. Written after the
            -- transactional move has already succeeded, and nothing reads it to
            -- decide how much money exists — it is here because M21 wants to
            -- print "made off with about four hundred dollars" and M17 wants a
            -- figure to attach to an allegation, and neither can reconstruct it
            -- from item rows once the money has been spent.
            { name = "take_cents",  type = "int", null = false, default = 0 },
            { name = "data",        type = "json" },
        },
        indexes = {
            { "season_id", "state" },
            { "business_id" },
            { "event_id" },
        },
    })

    Omerta.DB.DefineTable("crime_participants", {
        columns = {
            { name = "operation_id", type = "ref", null = false },
            { name = "character_id", type = "ref", null = false },
            { name = "joined_at",    type = "timestamp", null = false },
            -- escaped | downed | dead | arrested | unknown
            { name = "outcome",      type = "text", length = 16, null = false },
        },
        primary = { "operation_id", "character_id" },
    })

    Omerta.DB.DefineTable("crime_alarms", {
        columns = {
            { name = "id",           type = "id" },
            { name = "season_id",    type = "ref", null = false },
            -- NULLABLE ON PURPOSE. A gunshot in an empty street at three in the
            -- morning is an alarm with no operation behind it, and M16 must not
            -- need two code paths to answer it.
            { name = "operation_id", type = "ref" },
            { name = "source",       type = "text", length = 16, null = false },
            { name = "severity",     type = "int", null = false, default = 1 },
            { name = "map_name",     type = "text", length = 64, null = false },
            { name = "pos_x",        type = "int" },
            { name = "pos_y",        type = "int" },
            { name = "pos_z",        type = "int" },
            { name = "raised_at",    type = "timestamp", null = false },
            -- M16's column, and here now for the same reason `published_at` was
            -- in the events table a milestone before M21 needed it.
            { name = "responded_at", type = "timestamp" },
            { name = "data",         type = "json" },
        },
        indexes = {
            { "season_id", "responded_at" },
            { "operation_id" },
        },
    })

    Omerta.DB.AddMigration(15, "crime operations, participants and alarms", function(m)
        m:CreateTable("crime_operations")
        m:CreateTable("crime_participants")
        m:CreateTable("crime_alarms")
    end)
end

function MODULE:OnEnable()
    Internal.RegisterEvents()
    Internal.RegisterTakeSources()
    Internal.RegisterConcealment()

    if not Omerta.InEngine then return end

    Internal.RegisterInteractions()
    Internal.RegisterCommands()

    -- W0's hook, consumed rather than reimplemented.
    hook.Add("Omerta.WeaponFired", "omerta.crime.shot", function(ply, weaponId)
        Internal.OnWeaponFired(ply, weaponId)
    end)

    -- A participant who goes down or dies has their outcome recorded, which is
    -- what makes "everybody who was in it is on the floor" a knowable fact
    -- rather than something the escape check has to keep guessing at.
    hook.Add("Omerta.InjuryChanged", "omerta.crime.outcome", function(characterId, _, state)
        for _, operation in pairs(Internal.Live) do
            if operation.participants[characterId] then
                if state == Omerta.Injury.STATE.DEAD then
                    Omerta.Crime.SetOutcome(operation, characterId, "dead")
                elseif Omerta.Injury.IsDown(state) then
                    Omerta.Crime.SetOutcome(operation, characterId, "downed")
                end
            end
        end
    end)

    timer.Create("omerta.crime.tick", 1, 0, Internal.TickOperations)
    timer.Create("omerta.crime.float",
        Omerta.Config.Get("crime.float_minutes") * 60, 0, Internal.TickFloat)

    -- D-050. Anything still live at boot is abandoned; everything physical
    -- stays exactly where it physically is.
    Omerta.Seasons.WhenReady(function() Internal.ResolveOrphans() end)
end
