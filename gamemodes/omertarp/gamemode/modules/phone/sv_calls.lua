-- Calls: dialling, ringing, answering, and the quarters running out.
--
-- The server owns the call entirely. A client sends a number and later some
-- text; everything else — whether that line exists, whether they are standing
-- at a handset, who is ringing, who hears whom — is decided here.

Omerta.Phone = Omerta.Phone or {}
Omerta.Phone.Internal = Omerta.Phone.Internal or {}
local Internal = Omerta.Phone.Internal
local STATE = Omerta.Phone.STATE

Omerta.Config.Define("phone.seconds_per_coin", {
    type = "number", default = 45, min = 5, max = 600, scope = "server",
    description = "Seconds of call a single quarter buys at a payphone (D-003).",
})
Omerta.Config.Define("phone.ring_seconds", {
    type = "number", default = 25, min = 5, max = 120, scope = "server",
    description = "How long a handset rings before the call gives up.",
})
Omerta.Config.Define("phone.range", {
    type = "number", default = 96, min = 32, max = 256, scope = "server",
    description = "How close you must be to a handset to use or answer it.",
})

-- The coin a payphone eats. D-003 asks for quarters specifically, and M9's
-- denominations are the reason that is a real question rather than a flavour
-- note.
Omerta.Phone.COIN = 25

local lines = {}      -- number -> line
local linesById = {}  -- id -> line
local calls = {}      -- callId -> call
local callOf = {}     -- steamid64 -> call
local nextCallId = 1

Internal.Lines = lines
Internal.LinesById = linesById

function Omerta.Phone.Find(number) return lines[number] end
function Omerta.Phone.LineById(id) return linesById[id] end

function Omerta.Phone.CallOf(ply)
    if not (Omerta.InEngine and IsValid(ply)) then return nil end
    return callOf[ply:SteamID64() or ""]
end

function Internal.RegisterLine(line)
    lines[line.number] = line
    linesById[line.id] = line
    return line
end

function Internal.ForgetLine(line)
    if not line then return end
    lines[line.number] = nil
    linesById[line.id] = nil
end

function Internal.TakenNumbers()
    local taken = {}
    for number in pairs(lines) do taken[number] = true end
    return taken
end

--------------------------------------------------------------------------------
-- Standing at a telephone
--------------------------------------------------------------------------------

function Internal.HandsetAt(ply)
    if not (Omerta.InEngine and IsValid(ply)) then return nil end
    local range = Omerta.Config.Get("phone.range")
    local best, bestDistance = nil, nil
    for _, line in pairs(lines) do
        if IsValid(line.entity) then
            local distance = ply:GetPos():Distance(line.entity:GetPos())
            if distance <= range and (not bestDistance or distance < bestDistance) then
                best, bestDistance = line, distance
            end
        end
    end
    return best
end

local function playersNear(line)
    local out = {}
    if not IsValid(line.entity) then return out end
    local range = Omerta.Config.Get("phone.range")
    for _, ply in ipairs(player.GetAll()) do
        if Omerta.Characters.IsLoaded(ply)
                and ply:GetPos():Distance(line.entity:GetPos()) <= range then
            out[#out + 1] = ply
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- Telling participants where they stand
--------------------------------------------------------------------------------

-- 3 is "off the hook and nothing dialled yet" — not a call state, which is
-- why it is not in Omerta.Phone.STATE. It exists only so the client knows to
-- show a dial pad.
Omerta.Phone.OFF_HOOK = 3

local function stateIndex(state)
    if state == STATE.RINGING then return 1 end
    if state == STATE.CONNECTED then return 2 end
    return 0
end

function Internal.PushState(call)
    if not Omerta.InEngine then return end
    for sid, ply in pairs(call.participants) do
        if IsValid(ply) then
            local far = call.caller == ply and call.toLine or call.fromLine
            Omerta.Net.Send("phone.state", {
                state = stateIndex(call.state),
                number = far and far.number or "",
                seconds = math.floor(math.max(0, math.min(call.credit or 0, 4095))),
                incoming = call.caller ~= ply,
            }, ply)
        end
        if not IsValid(ply) then call.participants[sid] = nil end
    end
end

local function clearState(ply)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    Omerta.Net.Send("phone.state", {
        state = 0, number = "", seconds = 0, incoming = false,
    }, ply)
end

--------------------------------------------------------------------------------
-- The life of a call
--------------------------------------------------------------------------------

local function attach(call, ply)
    if not IsValid(ply) then return end
    call.participants[ply:SteamID64() or ""] = ply
    callOf[ply:SteamID64() or ""] = call
end

local function detachAll(call)
    for sid in pairs(call.participants) do callOf[sid] = nil end
end

-- cb(ok, err)
function Omerta.Phone.Dial(ply, number, cb)
    cb = cb or function() end
    if not Omerta.InEngine then cb(false, "not in engine") return end
    if Omerta.Phone.CallOf(ply) then cb(false, "you are already on a call") return end

    local from = Internal.HandsetAt(ply)
    if not from then cb(false, "you are not at a telephone") return end

    if not Omerta.Phone.ValidNumber(number) then cb(false, "that is not a number") return end
    local to = lines[number]

    -- An unassigned number rings nothing and says so exactly as a real one
    -- would, so the dial pad cannot be used to sweep the map for private lines.
    if not to or to.id == from.id then
        Omerta.Chat.Notice(ply, "The line rings, and rings, and nobody answers.")
        cb(false, "no such line")
        return
    end
    if to.busy or from.busy then cb(false, "the line is engaged") return end

    -- A payphone needs a coin before it will do anything at all.
    local credit = 0
    if from.kind == Omerta.Phone.KIND.PAYPHONE then
        if Omerta.Money.CountCoins(ply, Omerta.Phone.COIN) < 1 then
            cb(false, "you need a quarter")
            return
        end
    end

    local call = {
        id = nextCallId,
        state = STATE.RINGING,
        fromLine = from,
        toLine = to,
        caller = ply,
        credit = credit,
        startedAt = os.time(),
        startedClock = CurTime(),
        connectedAt = nil,
        seconds = 0,
        coinsSpent = 0,
        participants = {},
        callerCharacter = (Omerta.Characters.Get(ply) or {}).id,
    }
    nextCallId = nextCallId + 1
    calls[call.id] = call
    from.busy, to.busy = call, call
    attach(call, ply)

    -- Everybody standing at the far handset hears it ring. They are not told
    -- the number: whoever is calling has not said who they are, and the
    -- telephone does not know either.
    for _, near in ipairs(playersNear(to)) do
        Omerta.Net.Send("phone.ring", { handset = to.entity:EntIndex() }, near)
    end

    Internal.PushState(call)
    Omerta.Log.Audit("phone.dialled", {
        actor = ply:SteamID64(), character_id = call.callerCharacter,
        data = { from = from.number, to = to.number },
    })
    cb(true)
end

function Omerta.Phone.Answer(ply, cb)
    cb = cb or function() end
    local at = Internal.HandsetAt(ply)
    if not at then cb(false, "you are not at a telephone") return end

    local call = at.busy
    if not (call and call.state == STATE.RINGING and call.toLine.id == at.id) then
        cb(false, "nothing is ringing") return
    end
    if Omerta.Phone.CallOf(ply) then cb(false, "you are already on a call") return end

    local next_ = Internal.NextState(call.state, "answer")
    if not next_ then cb(false, "you cannot answer that") return end

    call.state = next_
    call.connectedAt = CurTime()
    call.answerer = ply
    call.answererCharacter = (Omerta.Characters.Get(ply) or {}).id
    attach(call, ply)

    -- The first coin goes in when the call actually connects, not when it is
    -- placed — a payphone that ate a quarter for an unanswered ring would be
    -- a fee, and D-003 asked for something you feed.
    if call.fromLine.kind == Omerta.Phone.KIND.PAYPHONE then
        Internal.FeedCoin(call.caller, call)
    end

    Internal.PushState(call)
    cb(true)
end

-- Consumes one quarter and adds its worth of time. cb(ok)
function Internal.FeedCoin(ply, call)
    if not (IsValid(ply) and call) then return false end
    if call.fromLine.kind ~= Omerta.Phone.KIND.PAYPHONE then return false end
    if Omerta.Money.CountCoins(ply, Omerta.Phone.COIN) < 1 then return false end

    -- Real coins, through M9's transactional path: a call is paid for with the
    -- same quarters that could have bought a sandwich.
    Omerta.Money.Take(ply, Omerta.Phone.COIN, function(ok)
        if not ok then return end
        call.credit = (call.credit or 0) + Omerta.Config.Get("phone.seconds_per_coin")
        call.coinsSpent = call.coinsSpent + Omerta.Phone.COIN
        Internal.PushState(call)
    end)
    return true
end

function Omerta.Phone.Hangup(ply, cb)
    cb = cb or function() end
    local call = Omerta.Phone.CallOf(ply)
    if not call then cb(false, "you are not on a call") return end
    Internal.EndCall(call, "hangup")
    cb(true)
end

function Internal.EndCall(call, event)
    if not call or call.state == STATE.ENDED then return end

    local outcome = Internal.OutcomeFor(call.state, event)
    local previous = call.state
    call.state = Internal.NextState(previous, event) or STATE.ENDED

    if call.connectedAt then
        call.seconds = math.floor(CurTime() - call.connectedAt)
    end

    for _, ply in pairs(call.participants) do clearState(ply) end
    detachAll(call)
    call.fromLine.busy, call.toLine.busy = nil, nil
    calls[call.id] = nil

    local season = Omerta.Seasons.GetActive()
    if season then
        Internal.Repo.RecordCall({
            season_id = season.id,
            from_line = call.fromLine.id,
            to_line = call.toLine.id,
            from_character_id = call.callerCharacter or Omerta.DB.NULL,
            to_character_id = call.answererCharacter or Omerta.DB.NULL,
            started_at = call.startedAt,
            ended_at = os.time(),
            seconds = call.seconds,
            coins_spent = call.coinsSpent,
            outcome = outcome,
        })
    end

    Omerta.Log.Audit("phone.ended", {
        character_id = call.callerCharacter,
        data = { from = call.fromLine.number, to = call.toLine.number,
                 seconds = call.seconds, outcome = outcome },
    })
end

--------------------------------------------------------------------------------
-- Talking
--------------------------------------------------------------------------------

-- The text path (S1 §4). It mirrors voice exactly: the far end hears it down
-- the line, and everybody standing next to the speaker hears the near half
-- spoken aloud — which is the same asymmetry §4b gives voice, so a mic-less
-- player is not playing a different game.
function Internal.HandleSay(ply, text)
    local call = Omerta.Phone.CallOf(ply)
    if not call or call.state ~= STATE.CONNECTED then return end

    local clean = Omerta.Chat.Sanitize(text, Omerta.Config.Get("chat.max_length"))
    if not clean then return end

    -- Spoken aloud in the room, through M7 — rate limiting, logging and range
    -- all come along with it.
    Omerta.Chat.Send(ply, "say", clean)

    local near = call.caller == ply and call.fromLine or call.toLine
    for _, other in pairs(call.participants) do
        if IsValid(other) and other ~= ply then
            Omerta.Net.Send("phone.heard", { number = near.number, text = clean }, other)
        end
    end
end

-- Lifting the receiver. Answering a ringing handset and opening a dial pad are
-- the same gesture in life, so they are the same one here and the server works
-- out which it was.
function Internal.PickUp(ply)
    if Omerta.Phone.CallOf(ply) then return end

    local at = Internal.HandsetAt(ply)
    if not at then
        Omerta.Chat.Notice(ply, "You are not close enough to the telephone.")
        return
    end

    if at.busy and at.busy.state == STATE.RINGING and at.busy.toLine.id == at.id then
        Omerta.Phone.Answer(ply, function(ok, err)
            if not ok and err then Omerta.Chat.Notice(ply, err) end
        end)
        return
    end
    if at.busy then Omerta.Chat.Notice(ply, "The line is engaged.") return end

    Omerta.Net.Send("phone.state", {
        state = Omerta.Phone.OFF_HOOK,
        -- Your own number, because it is written on the box in front of you
        -- (D-027) — this is the one number a handset may tell you.
        number = at.number,
        seconds = 0,
        incoming = false,
    }, ply)
end

function Internal.HandleDial(ply, number)
    Omerta.Phone.Dial(ply, number, function(ok, err)
        if not ok and err then Omerta.Chat.Notice(ply, err) end
    end)
end

function Internal.HandleAction(ply, action)
    local A = Omerta.Phone.ACTION
    if action == A.ANSWER then
        Omerta.Phone.Answer(ply, function(ok, err)
            if not ok and err then Omerta.Chat.Notice(ply, err) end
        end)
    elseif action == A.HANGUP then
        Omerta.Phone.Hangup(ply)
    elseif action == A.FEED then
        local call = Omerta.Phone.CallOf(ply)
        if call and not Internal.FeedCoin(ply, call) then
            Omerta.Chat.Notice(ply, "You have no quarters.")
        end
    end
end

--------------------------------------------------------------------------------
-- The clock
--------------------------------------------------------------------------------

function Internal.Tick(dt)
    local ringFor = Omerta.Config.Get("phone.ring_seconds")

    for _, call in pairs(calls) do
        if call.state == STATE.RINGING then
            if CurTime() - call.startedClock > ringFor then
                Internal.EndCall(call, "timeout")
            end
        elseif call.state == STATE.CONNECTED then
            if call.fromLine.kind == Omerta.Phone.KIND.PAYPHONE then
                call.credit = Internal.StepCredit(call.credit, dt)

                if call.credit <= 0 then
                    local coins = IsValid(call.caller)
                        and Omerta.Money.CountCoins(call.caller, Omerta.Phone.COIN) or 0
                    if Internal.ShouldCutOff(call.credit, coins) then
                        -- Mid-sentence, exactly as intended.
                        Internal.EndCall(call, "no_coins")
                    else
                        Internal.FeedCoin(call.caller, call)
                    end
                else
                    Internal.PushState(call)
                end
            end
        end
    end
end

function Internal.DropPlayer(ply)
    local call = Omerta.Phone.CallOf(ply)
    if call then Internal.EndCall(call, "hangup") end
end

--------------------------------------------------------------------------------
-- Voice (S1)
--------------------------------------------------------------------------------

function Internal.RegisterVoice()
    -- Registered as an OVERRIDE on M7's single hook, never as a second hook:
    -- hook ordering is undefined and the symptom would be intermittently
    -- inaudible calls (S1 §3).
    Omerta.Chat.RegisterVoiceOverride("phone", function(listener, talker)
        return Internal.VoiceDecision(Omerta.Phone.CallOf(listener),
            Omerta.Phone.CallOf(talker))
    end)
end
