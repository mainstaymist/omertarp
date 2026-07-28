Omerta.Module.Register({
    name = "inventory",
    -- `chat` is a real dependency, not an incidental one: every refusal the
    -- server issues ("there is no room for that") reaches the player through
    -- Omerta.Chat.Notice, since there is no error box to put it in.
    depends = { "characters", "interaction", "hud", "chat" },
})
