-- In-engine acceptance suite: `omerta_chat_selftest`. Exercises the channel
-- registry, sanitisation, and the chat log's write/read/sweep cycle against a
-- synthetic character id, cleaning up after itself.

if not Omerta.InEngine then return end

-- Deliberately out of range of any real character id.
local FAKE_CHARACTER = 2000000001

local function buildSteps()
    local Repo = Omerta.Chat.Internal.Repo
    local steps = {}

    steps[#steps + 1] = { name = "database and season ready", required = true, fn = function(pass, fail)
        if not Omerta.DB.IsReady() then fail("db phase=" .. Omerta.DB.Status().phase) return end
        if not Omerta.Seasons.GetActive() then fail("no active season") return end
        pass()
    end }

    steps[#steps + 1] = { name = "leftover cleanup from aborted runs", fn = function(pass, fail)
        Repo.DeleteForCharacter(FAKE_CHARACTER, function(ok, err)
            if ok then pass() else fail(tostring(err)) end
        end)
    end }

    steps[#steps + 1] = { name = "channels are registered with stable indices", fn = function(pass, fail)
        for _, id in ipairs({ "whisper", "say", "yell", "me", "system" }) do
            if not Omerta.Chat.GetChannel(id) then fail("missing channel '" .. id .. "'") return end
        end
        local list = Omerta.Chat.GetOrdered()
        for i, def in ipairs(list) do
            if Omerta.Chat.GetByIndex(i) ~= def then fail("index mismatch at " .. i) return end
        end
        -- Ranges must widen from whisper to yell or the mechanic is backwards.
        if not (Omerta.Chat.GetChannel("whisper").range
                < Omerta.Chat.GetChannel("say").range
                and Omerta.Chat.GetChannel("say").range
                < Omerta.Chat.GetChannel("yell").range) then
            fail("channel ranges are not ordered whisper < say < yell") return
        end
        pass(#list .. " channels")
    end }

    steps[#steps + 1] = { name = "parsing and sanitisation", fn = function(pass, fail)
        local id, text = Omerta.Chat.Parse("hello there")
        if id ~= "say" or text ~= "hello there" then fail("plain text should be say") return end

        id, text = Omerta.Chat.Parse("/w quietly")
        if id ~= "whisper" or text ~= "quietly" then fail("/w should whisper") return end

        id, text = Omerta.Chat.Parse("/me lights a cigarette")
        if id ~= "me" or text ~= "lights a cigarette" then fail("/me should emote") return end

        -- An unknown command must not be shouted aloud by accident.
        id = Omerta.Chat.Parse("/wanted dead or alive")
        if id ~= nil then fail("unknown command should be refused, got " .. tostring(id)) return end

        local clean = Omerta.Chat.Sanitize("hello\1\2 there  ", 256)
        if clean ~= "hello there" then fail("sanitise gave '" .. tostring(clean) .. "'") return end
        if Omerta.Chat.Sanitize("   ", 256) ~= nil then fail("whitespace should be empty") return end
        pass()
    end }

    steps[#steps + 1] = { name = "chat log writes and reads back", fn = function(pass, fail)
        Repo.Log({
            at = os.time(), season_id = Omerta.Seasons.GetActive().id,
            character_id = FAKE_CHARACTER, channel = "say",
            text = "selftest line", pos_x = 1, pos_y = 2, pos_z = 3, recipients = 2,
        }, function(id, err)
            if not id then fail(tostring(err)) return end
            Repo.RecentFor(FAKE_CHARACTER, 5, function(rows, rerr)
                if rerr then fail(rerr) return end
                if #rows ~= 1 or rows[1].text ~= "selftest line" then
                    fail("read back " .. #rows .. " row(s)") return
                end
                pass()
            end)
        end)
    end }

    steps[#steps + 1] = { name = "retention sweep removes old rows only", fn = function(pass, fail)
        -- One ancient row alongside the fresh one above.
        Repo.Log({
            at = 1000, season_id = Omerta.Seasons.GetActive().id,
            character_id = FAKE_CHARACTER, channel = "say",
            text = "ancient line", pos_x = 0, pos_y = 0, pos_z = 0, recipients = 0,
        }, function(id, err)
            if not id then fail(tostring(err)) return end
            Repo.Sweep(2000, function(ok, serr)
                if not ok then fail(tostring(serr)) return end
                Repo.RecentFor(FAKE_CHARACTER, 5, function(rows)
                    if #rows ~= 1 then
                        fail("expected 1 surviving row, got " .. #rows) return
                    end
                    if rows[1].text ~= "selftest line" then
                        fail("the wrong row survived: " .. tostring(rows[1].text)) return
                    end
                    pass("old row removed, recent kept")
                end)
            end)
        end)
    end }

    steps[#steps + 1] = { name = "cleanup", always = true, fn = function(pass, fail)
        Repo.DeleteForCharacter(FAKE_CHARACTER, function(ok, err)
            if ok then pass() else fail(tostring(err)) end
        end)
    end }

    return steps
end

concommand.Add("omerta_chat_selftest", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    Omerta.SelfTest.Run("chat.selftest", buildSteps())
end)
