-- The barman, and what he has heard.
--
-- Two things feed the pool: events that actually happened, and things people
-- paid him to say. He does not distinguish them, and neither does anyone
-- listening (D-031). That is what makes a rumour worth hearing and worth
-- doubting at the same time.

Omerta.Rumours = Omerta.Rumours or {}
Omerta.Rumours.Internal = Omerta.Rumours.Internal or {}
Omerta.Business = Omerta.Business or {}
Omerta.Business.Internal = Omerta.Business.Internal or {}

local Internal = Omerta.Business.Internal
local Rumours = Omerta.Rumours.Internal

local pool = {}   -- array of live rumours
local heard = {}  -- characterId -> { [rumourId] = true }

function Internal.LoadRumours()
    local season = Omerta.Seasons.GetActive()
    if not season then return end

    Internal.Repo.LiveRumours(season.id, os.time(), function(rows, err)
        if err then
            Omerta.Log.Error("business", "could not load rumours: %s", err)
            return
        end
        pool = rows
        if #rows > 0 then
            Omerta.Log.Info("business", "%d rumour(s) still going round", #rows)
        end
    end)
end

--------------------------------------------------------------------------------
-- Adding
--------------------------------------------------------------------------------

-- The seam M14's events and M15's witnesses call. Neither needs to know a
-- barman exists. cb(id, err)
function Omerta.Rumours.Add(text, source, opts, cb)
    cb = cb or function() end
    opts = opts or {}

    local season = Omerta.Seasons.GetActive()
    if not season then cb(nil, "no active season") return end

    -- Sanitised through M7's path: this is player-readable text and, when
    -- planted, player-authored — the same surface chat is.
    local clean = Omerta.Chat.Sanitize(text, Omerta.Rumours.MAX_LENGTH)
    if not clean then cb(nil, "there is nothing to repeat") return end

    local now = os.time()
    local row = {
        season_id = season.id,
        text = clean,
        source = source,
        planted_by_character_id = opts.characterId or Omerta.DB.NULL,
        business_id = opts.businessId or Omerta.DB.NULL,
        created_at = now,
        expires_at = now + math.floor(Omerta.Config.Get("business.rumour_hours") * 3600),
    }

    Internal.Repo.AddRumour(row, function(id, err)
        if not id then cb(nil, err) return end
        row.id = id
        pool[#pool + 1] = row
        cb(id)
    end)
end

-- Paying the barman. The money is real and the audit line names the author,
-- even though nobody in-game can tell a planted rumour from a true one —
-- because "who started that" is occasionally a question about rule-breaking
-- rather than about the fiction.
function Omerta.Rumours.Plant(ply, business, text, cb)
    cb = cb or function() end
    local character = Omerta.Characters.Get(ply)
    if not character then cb(false, "no character") return end
    if not business then cb(false, "there is nobody to tell") return end

    local price = Omerta.Money.Round(Omerta.Config.Get("business.rumour_price"))
    if price > 0 and Omerta.Money.Count(ply) < price then
        cb(false, "he wants " .. Omerta.Money.Format(price) .. " for that")
        return
    end

    local function record()
        Omerta.Rumours.Add(text, Omerta.Rumours.SOURCE.PLANTED, {
            characterId = character.id,
            businessId = business.id,
        }, function(id, err)
            if not id then cb(false, err) return end
            Omerta.Log.Audit("rumour.planted", {
                actor = ply:SteamID64(), character_id = character.id,
                data = { business = business.id, rumour = id, cents = price, text = text },
            })
            Omerta.Chat.Notice(ply, "He nods slowly. It will be going round by morning.")
            cb(true)
        end)
    end

    if price <= 0 then record() return end
    Omerta.Money.Pay(ply, Omerta.Business.Till(business.id), price, function(paid, perr)
        if not paid then cb(false, perr) return end
        record()
    end)
end

--------------------------------------------------------------------------------
-- Hearing one
--------------------------------------------------------------------------------

function Omerta.Rumours.Draw(characterId)
    return Rumours.Pick(pool, heard[characterId], os.time())
end

function Internal.ServeRumour(ply, business)
    local character = Omerta.Characters.Get(ply)
    if not character then return end

    local typeDef = Omerta.Business.GetType(business.type_key)
    local serves = false
    for _, service in ipairs(typeDef and typeDef.services or {}) do
        if service == "rumours" then serves = true end
    end
    if not serves then
        Omerta.Chat.Notice(ply, "Nobody here is in the business of talking.")
        return
    end
    if not Internal.IsStaffed(business) then
        Omerta.Chat.Notice(ply, "There is nobody behind the counter.")
        return
    end

    local rumour = Omerta.Rumours.Draw(character.id)
    if not rumour then
        Omerta.Net.Send("rumour.heard", { text = Omerta.Rumours.NOTHING }, ply)
        return
    end

    -- Remembered per listener, so the barman does not repeat himself. What you
    -- were told is something YOU have to remember — there is no rumour log,
    -- for the same reason there is no directory and no roster.
    heard[character.id] = heard[character.id] or {}
    heard[character.id][rumour.id] = true

    Omerta.Net.Send("rumour.heard", { text = rumour.text }, ply)
end

function Rumours.HandlePlant(ply, text)
    local business = Internal.AtCounter(ply)
    Omerta.Rumours.Plant(ply, business, text, function(ok, err)
        if not ok and err then Omerta.Chat.Notice(ply, err) end
    end)
end

function Internal.ForgetListener(characterId)
    heard[characterId] = nil
end

-- Exposed for the self-test, which needs to drive the pool without a barman.
Rumours.Pool = function() return pool end
Rumours.Reset = function() pool = {} heard = {} end
