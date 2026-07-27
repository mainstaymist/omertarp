-- Client rendering of local speech.
--
-- The name in each line was resolved by the server for THIS listener, so this
-- file never decides who anyone is — it only draws what it was told. That is
-- why two players in the same room legitimately see different names on the
-- same sentence.

local function colourOf(channel)
    local c = channel.colour
    return Color(c[1], c[2], c[3])
end

hook.Add("Omerta.ChatReceived", "omerta.chat.render", function(payload)
    local channel = Omerta.Chat.GetByIndex(payload.channel)
    if not channel then return end

    local colour = colourOf(channel)

    if channel.system then
        chat.AddText(colour, payload.text)
        return
    end

    if channel.emote then
        -- Narration, not speech: "** Tony Marino lights a cigarette."
        chat.AddText(colour, "** " .. payload.name .. " " .. payload.text)
        return
    end

    -- "Tony Marino says \"Evening.\"" — quotes keep speech visually distinct
    -- from emotes and suit the period.
    chat.AddText(
        colour, payload.name .. " " .. channel.label .. " ",
        Color(255, 255, 255), "\"" .. payload.text .. "\""
    )
end)
