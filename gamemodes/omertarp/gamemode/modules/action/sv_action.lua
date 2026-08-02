-- Running one.
--
-- One action per player at a time, always. That is the rule that makes standing
-- over somebody a commitment rather than a click, and it is why `IsBusy` is
-- part of the public surface rather than an internal detail: everything that
-- offers a verb has to be able to ask whether the player is already spending
-- their hands on something else.

local MODULE = Omerta.Module.Get("action")

Omerta.Action = Omerta.Action or {}
Omerta.Action.Internal = Omerta.Action.Internal or {}
local Internal = Omerta.Action.Internal

local inProgress = {}  -- actor SteamID64 -> entry
local interrupts = {}  -- id -> fn(ply, entry) -> reason | nil

Internal.InProgressTable = inProgress
Internal.Interrupts = interrupts

--------------------------------------------------------------------------------
-- Interrupts
--------------------------------------------------------------------------------
-- WHAT STOPS AN ACTION IS REGISTERED FROM OUTSIDE.
--
-- The version of this that lived in `injury` called `Omerta.Injury.IsPlayerDown`
-- inline, which was correct there and would have been a dependency inversion
-- here: a primitive M15, M16, M17 and C4 all consume cannot know that injury
-- exists. Injury registers its own rule instead, and the day a milestone adds
-- another reason your hands stop working, it registers that one too and this
-- file does not change.
--
-- fn(ply, entry) returns a reason string to cancel, or nil to allow.
function Omerta.Action.RegisterInterrupt(id, fn)
    if type(id) ~= "string" or id == "" then
        error("an interrupt needs an id", 2)
    end
    if type(fn) ~= "function" then
        error("interrupt '" .. id .. "' needs a function", 2)
    end
    if interrupts[id] then error("interrupt '" .. id .. "' registered twice", 2) end
    interrupts[id] = fn
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

-- What this player is in the middle of, or nil. Read by anything that has to
-- tell "do it again" from "stop doing it" — E over a body being the first.
function Omerta.Action.InProgress(ply)
    if not IsValid(ply) then return nil end
    local entry = inProgress[ply:SteamID64() or ""]
    if not (entry and entry.finishAt > CurTime()) then return nil end
    return entry
end

function Omerta.Action.IsBusy(ply)
    return Omerta.Action.InProgress(ply) ~= nil
end

--------------------------------------------------------------------------------
-- Beginning and ending
--------------------------------------------------------------------------------

-- The plate, or nothing at all outside the engine.
--
-- Guarded here rather than at each of the five call sites, and guarded for the
-- same reason Omerta.Chat.Notice is: the rules this module enforces are worth
-- testing headlessly, and a primitive that cannot be driven without a running
-- server is a primitive whose disconnect path only gets exercised in
-- production. Which is the exact failure the review refused a second copy over.
local function prompt(ply, text, millis, sound)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    Omerta.Net.Send("action.prompt", {
        text = text,
        millis = millis or 0,
        sound = sound or Omerta.Action.PROMPT_SOUND.NONE,
    }, ply)
end

local function clearPrompt(ply)
    prompt(ply, "", 0, Omerta.Action.PROMPT_SOUND.NONE)
end

-- cb(ok, err). Returns true if it started.
--
-- spec:
--   id            required, lowercase, for identification and logs
--   label         required, the words on the plate
--   duration      required, seconds
--   onComplete    required, fn(ply, entry, done) — `done(ok, err)` finishes it
--   sound         optional PROMPT_SOUND code
--   moveTolerance optional, how far the actor may drift (default 64)
--   stillValid    optional fn(ply, entry) -> true | false, reason — ticked
--   notify        optional { ply = <other>, text = "…" }, for the person it is
--                 being done TO
--   data          optional bag, carried on the entry and handed back untouched
function Omerta.Action.Begin(ply, spec, cb)
    cb = cb or function() end
    if not IsValid(ply) then cb(false, "no actor") return false end

    local ok, why = Omerta.Action.Validate(spec)
    if not ok then
        -- Loud, like a refused event: an action that silently failed to start
        -- is indistinguishable from one the player never pressed.
        Omerta.Log.Error("action", "refused to begin: %s", tostring(why))
        cb(false, why)
        return false
    end

    if Omerta.Action.IsBusy(ply) then cb(false, "you are busy") return false end

    local now = CurTime()
    local entry = {
        -- Kept alongside finishAt because "how long has this been running" is a
        -- question the E-over-a-body rule has to answer, and deriving it from
        -- the deadline would mean re-reading the definition's duration at a
        -- call site that has no business knowing it.
        startedAt = now,
        finishAt = now + spec.duration,
        id = spec.id,
        startPos = ply:GetPos(),
        spec = spec,
        data = spec.data,
        cb = cb,
    }
    inProgress[ply:SteamID64() or ""] = entry

    local millis = Omerta.Action.PromptMillis(spec.duration)
    prompt(ply, spec.label .. "…", millis, spec.sound)

    -- The person it is being done to is told too. Being operated on without
    -- knowing it is happening is the one thing worse than being operated on.
    if spec.notify then
        prompt(spec.notify.ply, spec.notify.text, millis)
    end

    return true
end

function Omerta.Action.Cancel(ply, reason)
    if not IsValid(ply) then return end
    local sid = ply:SteamID64() or ""
    local entry = inProgress[sid]
    if not entry then return end
    inProgress[sid] = nil

    clearPrompt(ply)
    -- And the other half of the room. A plate that says somebody is working on
    -- you, left up after they stopped, is a lie the client has no way to catch.
    if entry.spec.notify then clearPrompt(entry.spec.notify.ply) end

    if entry.cb then entry.cb(false, reason or "interrupted") end
end

--------------------------------------------------------------------------------
-- The clock
--------------------------------------------------------------------------------

function Omerta.Action.Tick()
    local now = CurTime()
    for sid, entry in pairs(inProgress) do
        -- Resolved from the id every tick rather than held on the entry: a
        -- stored entity would keep a disconnected player's table alive, and
        -- worse, a reconnect inside the window would leave the action pointing
        -- at the corpse of the old one.
        local ply = nil
        for _, candidate in ipairs(player.GetAll()) do
            if candidate:SteamID64() == sid then ply = candidate break end
        end

        if not IsValid(ply) then
            -- THE DISCONNECT CASE, HANDLED RATHER THAN LEAKED. This is the one
            -- the design review named when it refused a second copy of this
            -- machinery, so it is the one that gets a comment: dropping the
            -- entry without telling the caller leaves whatever the action was
            -- part of — an operation, a treatment, a lever on a register —
            -- waiting forever for a completion that cannot arrive.
            inProgress[sid] = nil
            if entry.spec.notify then clearPrompt(entry.spec.notify.ply) end
            if entry.cb then entry.cb(false, "you left") end
        elseif ply:GetPos():Distance(entry.startPos)
                > (entry.spec.moveTolerance or 64) then
            -- Walking away is how you interrupt yourself.
            Omerta.Action.Cancel(ply, "you moved away")
        else
            local stop = nil
            if entry.spec.stillValid then
                local valid, reason = entry.spec.stillValid(ply, entry)
                if not valid then stop = reason or "not any more" end
            end
            for _, fn in pairs(interrupts) do
                if stop then break end
                stop = fn(ply, entry)
            end

            if stop then
                Omerta.Action.Cancel(ply, stop)
            elseif now >= entry.finishAt then
                inProgress[sid] = nil
                if entry.spec.notify then clearPrompt(entry.spec.notify.ply) end
                entry.spec.onComplete(ply, entry, function(done, err)
                    if entry.cb then entry.cb(done ~= false, err) end
                end)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    -- Every frame, not every second: an action's deadline is a moment and a bar
    -- that finishes a tick late is a bar the player watched finish early. This
    -- is the rate injury drove it at and the reason has not changed.
    hook.Add("Think", "omerta.action.tick", function()
        Omerta.Action.Tick()
    end)

    -- A player who leaves mid-action is caught by the tick above, but only on
    -- the next frame and only by a linear scan. Catching the disconnect itself
    -- is cheaper and, more importantly, it is the one moment we still know
    -- which SteamID64 the entry belonged to.
    hook.Add("PlayerDisconnected", "omerta.action.disconnect", function(ply)
        local sid = IsValid(ply) and ply:SteamID64() or nil
        local entry = sid and inProgress[sid]
        if not entry then return end
        inProgress[sid] = nil
        if entry.spec.notify then clearPrompt(entry.spec.notify.ply) end
        if entry.cb then entry.cb(false, "you left") end
    end)
end
