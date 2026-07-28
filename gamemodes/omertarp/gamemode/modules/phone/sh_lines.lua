-- Telephone lines and the life of a call, as pure functions.
--
-- A number belongs to a PLACE, not a person (D-003). That distinction is the
-- reason telephony is its own system rather than a property of a character,
-- and it is why none of this file knows what a character is.
--
-- Everything here is pure and covered by the headless suite: the state machine
-- a call walks through, the arithmetic that decides the exact tick the coins
-- run out, and the routing table S1 derived.

Omerta.Phone = Omerta.Phone or {}
Omerta.Phone.Internal = Omerta.Phone.Internal or {}

Omerta.Phone.KIND = { PAYPHONE = "payphone", PRIVATE = "private" }

Omerta.Phone.STATE = {
    IDLE      = "idle",
    RINGING   = "ringing",     -- placed, waiting for an answer
    CONNECTED = "connected",
    ENDED     = "ended",
}

Omerta.Phone.OUTCOME = {
    ANSWERED   = "answered",
    UNANSWERED = "unanswered",
    CUT_OFF    = "cut_off",     -- the coins ran out mid-sentence
    HUNG_UP    = "hung_up",
}

-- Four digits. Short enough to shout across a bar and to write on a scrap of
-- paper, which are the two ways a number is ever going to travel (D-027).
Omerta.Phone.NUMBER_MIN = 1000
Omerta.Phone.NUMBER_MAX = 9999

function Omerta.Phone.ValidNumber(number)
    if type(number) ~= "string" then return false end
    if not number:find("^%d%d%d%d$") then return false end
    local n = tonumber(number)
    return n >= Omerta.Phone.NUMBER_MIN and n <= Omerta.Phone.NUMBER_MAX
end

-- What is written on the outside of the box, for anyone to read.
--
-- A payphone has its number painted on it (D-027) — that is how you tell
-- somebody where to call you back, and it is why a payphone is a place people
-- wait at. A private line has nothing written on it: its number travels only by
-- being told, which is the entire reason knowing one is worth anything. Putting
-- that number on the entity would hand every passer-by a directory, which §4a
-- exists to prevent.
--
-- Pure, and the single place the rule is decided — the handset asks it rather
-- than deciding for itself.
function Omerta.Phone.PublicNumberFor(kind, number)
    if kind ~= Omerta.Phone.KIND.PAYPHONE then return nil end
    if not Omerta.Phone.ValidNumber(number) then return nil end
    return number
end

-- The lowest free number. Deterministic rather than random so a line placed
-- and replaced during setup keeps the number staff just wrote down.
-- `taken` is a set of number strings. Returns a number string, or nil.
function Omerta.Phone.Internal.AllocateNumber(taken)
    for n = Omerta.Phone.NUMBER_MIN, Omerta.Phone.NUMBER_MAX do
        local candidate = tostring(n)
        if not taken[candidate] then return candidate end
    end
    return nil
end

--------------------------------------------------------------------------------
-- The state machine
--------------------------------------------------------------------------------
-- Written as a table rather than a chain of ifs, because the interesting part
-- of a call is the abnormal exits and a table makes the missing ones visible.

local TRANSITIONS = {
    idle = {
        dial = Omerta.Phone.STATE.RINGING,
    },
    ringing = {
        answer  = Omerta.Phone.STATE.CONNECTED,
        hangup  = Omerta.Phone.STATE.ENDED,
        timeout = Omerta.Phone.STATE.ENDED,
    },
    connected = {
        hangup   = Omerta.Phone.STATE.ENDED,
        no_coins = Omerta.Phone.STATE.ENDED,
        -- Deliberately absent: you cannot answer a call twice, and you cannot
        -- time out of one that somebody already picked up.
    },
    ended = {},
}

-- Returns the next state, or nil when the event does not apply.
function Omerta.Phone.Internal.NextState(state, event)
    local row = TRANSITIONS[state]
    return row and row[event] or nil
end

-- How a call that ended by `event` from `state` should be recorded.
function Omerta.Phone.Internal.OutcomeFor(state, event)
    if event == "no_coins" then return Omerta.Phone.OUTCOME.CUT_OFF end
    if event == "timeout" then return Omerta.Phone.OUTCOME.UNANSWERED end
    if state == Omerta.Phone.STATE.RINGING then return Omerta.Phone.OUTCOME.UNANSWERED end
    return Omerta.Phone.OUTCOME.HUNG_UP
end

--------------------------------------------------------------------------------
-- Coins (D-003)
--------------------------------------------------------------------------------
-- A payphone is not billed, it is FED. The call lasts exactly as long as the
-- coins do, and it stops mid-sentence when they run out — which is the mechanic
-- D-003 asked for rather than a fee with a friendly name.

-- Returns seconds remaining after `dt`, floored at zero.
function Omerta.Phone.Internal.StepCredit(remaining, dt)
    return math.max(0, (remaining or 0) - (dt or 0))
end

-- Whether the call should die on this tick: out of credit, and no coin left to
-- feed it. Separated from StepCredit so the decision is testable without a
-- clock.
function Omerta.Phone.Internal.ShouldCutOff(remaining, coinsAvailable)
    return remaining <= 0 and (coinsAvailable or 0) <= 0
end

--------------------------------------------------------------------------------
-- Voice routing (S1 §2)
--------------------------------------------------------------------------------
-- The whole design in one function. Two people on the same connected call hear
-- each other flat, at any distance. Everybody else defers to M7's distance
-- rule, which is why a bystander hears only the half of the conversation
-- spoken in front of them (D-028) and nothing of the far end.
--
-- Returns canHear, is3D — or nil to defer.

function Omerta.Phone.Internal.VoiceDecision(listenerCall, talkerCall)
    if not (listenerCall and talkerCall) then return nil end
    if listenerCall.id ~= talkerCall.id then return nil end
    if listenerCall.state ~= Omerta.Phone.STATE.CONNECTED then return nil end
    -- Non-positional: the voice arrives from the earpiece, not from across
    -- the map. Volume is not adjustable per pair (S1 §4), so a bad line is
    -- not something this can promise.
    return true, false
end
