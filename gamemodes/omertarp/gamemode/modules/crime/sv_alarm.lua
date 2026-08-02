-- The alarm: a fact about a PLACE, never about a person.
--
-- Alarms are their own table and are not owned by robberies. `operation_id` is
-- nullable on purpose: a gunshot in an empty street at three in the morning is
-- an alarm with no operation behind it, and M16 must not need two code paths to
-- answer it. One queue, one responder seam, whatever raised it.
--
-- NO ALARM IS ANNOUNCED TO ANYBODY, INCLUDING THE ROBBERS. The clerk going for
-- the telephone is an animation, visible in the room, and the only way to know
-- it happened. Whether the police are coming is something you find out when they
-- arrive. This is the single most tempting violation in the milestone and it
-- would be one Omerta.HUD.Cue — so it is written down as a rule rather than
-- left as discipline.

Omerta.Crime = Omerta.Crime or {}
Omerta.Crime.Internal = Omerta.Crime.Internal or {}
local Internal = Omerta.Crime.Internal
local S = Omerta.Crime.STATE

Omerta.Crime.ALARM_SOURCE = {
    BUTTON    = "button",     -- under the counter
    TELEPHONE = "telephone",  -- he got to it, or he called afterwards
    DISCOVERY = "discovery",  -- somebody found what was left (D-052)
    GUNSHOT   = "gunshot",
}

--------------------------------------------------------------------------------
-- The responder seam (M16)
--------------------------------------------------------------------------------
-- M14 ships this with nothing registered, deliberately, in the shape M19
-- shipped RegisterDownedAction for M20. If M16 can be built entirely as a
-- registration into it, the seam was cut correctly; if M16 has to edit
-- modules/crime/, it was not — and I would rather find that out here than
-- in M17.

local responders = {}

function Omerta.Crime.RegisterResponder(id, fn)
    if type(id) ~= "string" or id == "" then error("a responder needs an id", 2) end
    if type(fn) ~= "function" then error("responder '" .. id .. "' needs a function", 2) end
    if responders[id] then error("responder '" .. id .. "' registered twice", 2) end
    responders[id] = fn
end

Internal.Responders = responders

--------------------------------------------------------------------------------
-- Raising one
--------------------------------------------------------------------------------

-- cb(alarmId, err)
function Omerta.Crime.RaiseAlarm(spec, cb)
    cb = cb or function() end
    spec = spec or {}

    local season = Omerta.Seasons.GetActive()
    if not season then cb(nil, "no active season") return end
    if not spec.source then cb(nil, "an alarm needs a source") return end

    local pos = spec.pos
    Internal.Repo.InsertAlarm({
        season_id = season.id,
        operation_id = spec.operation_id or Omerta.DB.NULL,
        source = spec.source,
        severity = spec.severity or 1,
        map_name = Omerta.InEngine and game.GetMap() or "unknown",
        pos_x = pos and math.floor(pos.x) or Omerta.DB.NULL,
        pos_y = pos and math.floor(pos.y) or Omerta.DB.NULL,
        pos_z = pos and math.floor(pos.z) or Omerta.DB.NULL,
        raised_at = spec.at or os.time(),
        -- M16's column, empty for a milestone. A migration against the table
        -- M16 is built on is more disruptive than a column that sits unused.
        responded_at = Omerta.DB.NULL,
        data = Omerta.DB.NULL,
    }, function(id, err)
        if not id then
            Omerta.Log.Error("crime", "could not record an alarm: %s", tostring(err))
            cb(nil, err)
            return
        end

        Omerta.Log.Audit("crime.alarm", {
            subject = spec.operation_id,
            data = { alarm = id, source = spec.source, severity = spec.severity or 1 },
        })

        for _, fn in pairs(responders) do fn(id, spec) end
        cb(id)
    end)
end

function Omerta.Crime.PendingAlarms(cb)
    Internal.Repo.PendingAlarms(50, cb)
end

function Omerta.Crime.MarkResponded(alarmId, cb)
    Internal.Repo.MarkResponded(alarmId, os.time(), cb)
end

--------------------------------------------------------------------------------
-- An alarm inside an operation
--------------------------------------------------------------------------------

-- Moves the operation to `alarmed` and records the fact. AN ALARM DOES NOT END
-- ANYTHING — the crew can still walk out with the money and often does. What it
-- changes is who is waiting outside.
function Internal.AlarmOperation(operation, source)
    if not operation then return end
    Omerta.Crime.RaiseAlarm({
        operation_id = operation.id,
        source = source,
        severity = operation.clerkDead and 3 or 2,
        pos = operation.pos,
    })
    -- Recorded on the operation as well as in the state, because the state moves
    -- on to escaped or failed and the rumour still needs to know the police were
    -- called. Reading it back off the state would have said "no" every time.
    operation.alarmed = true
    if operation.state == S.ACTIVE then
        Omerta.Crime.Resolve(operation, S.ALARMED, nil)
    end
    Omerta.Crime.Observe(operation, "alarm", operation.pos)
end

--------------------------------------------------------------------------------
-- Afterwards (D-051)
--------------------------------------------------------------------------------
-- The post-resolution evaluation the mask ruling required. Once the crew has
-- gone, the question is no longer what the clerk dares do — it is what he
-- chooses to say, and a mask makes him likelier to say it.
--
-- Delayed rather than instant, because the whole point of the trade is that the
-- call happens BEHIND YOUR BACK. An alarm that fired the moment you stepped
-- outside would be an alarm you could watch for.

function Internal.OnResolved(operation)
    Internal.ReleaseClerk(operation)
    Internal.PostRumour(operation)

    -- A place that cannot telephone cannot telephone. The bar is illegal and
    -- its owner would rather tell his family — one line of data, a per-type
    -- consequence, and the reason the robbery block is worth having at all.
    local block = operation.robbery or {}
    local alarmBlock = block.alarm or {}

    if operation.clerkDead then
        -- D-052: a guaranteed alarm or discovery on a FIXED TIMER regardless of
        -- what he did or did not reach for. A man does not report his own
        -- murder; somebody finds him.
        local delay = Omerta.Config.Get("crime.discovery_seconds")
        timer.Simple(delay, function()
            Omerta.Crime.RaiseAlarm({
                operation_id = operation.id,
                source = Omerta.Crime.ALARM_SOURCE.DISCOVERY,
                severity = 3, pos = operation.pos,
            })
        end)
        return
    end

    if not alarmBlock.telephone then return end
    if not operation.clerkAlive then return end

    local personality = operation.personality
    if not personality then return end

    local chance = Omerta.Crime.ReportChance({
        masked = operation.anyMasked,
        victimHurt = operation.clerkHurt,
        shotsFired = operation.shotsFired,
        bystanderHurt = operation.bystanderHurt,
        complied = operation.complied,
    }, personality)

    if Omerta.Crime.Roll(operation.seed, "report") >= chance then return end

    local delay = Omerta.Config.Get("crime.report_delay_seconds")
    timer.Simple(delay, function()
        Omerta.Crime.RaiseAlarm({
            operation_id = operation.id,
            source = Omerta.Crime.ALARM_SOURCE.TELEPHONE,
            severity = 2, pos = operation.pos,
        })
    end)
end

--------------------------------------------------------------------------------
-- The rumour (D-031)
--------------------------------------------------------------------------------
-- The one thing M14 puts in front of other players, and the first event-sourced
-- entry the pool has ever had. M13 built Rumours.Add with an `event` source for
-- exactly this and nothing but M13's own self-test has called it that way.
--
-- The text comes from a pure builder that has no parameter a character could be
-- put into, which is a stronger guarantee than remembering not to.

function Internal.PostRumour(operation)
    if not Omerta.Rumours then return end

    local business = Omerta.Business.Get(operation.business_id)
    local shape = "robbery"
    if operation.clerkDead then
        shape = "murder"
    elseif operation.state == S.FAILED then
        shape = "failed"
    elseif operation.alarmed then
        shape = "alarmed"
    end

    local text = Omerta.Crime.RumourText(shape, business and business.name or nil,
        operation.seed)
    Omerta.Rumours.Add(text, Omerta.Rumours.SOURCE.EVENT, {
        -- The place, and deliberately nothing else. No characterId is passed —
        -- not because it would be filtered out downstream, but because a rumour
        -- is what the street is saying and the street does not have one.
        businessId = operation.business_id,
    })
end
