Omerta.Module.Register({
    name = "organizations",
    -- `inventory` because a uniform is an item (§4c); `identity` because
    -- induction is an introduction (§4b) and the officer title resolves
    -- through M5; `chat` because every refusal reaches the player as a notice.
    depends = { "characters", "identity", "interaction", "chat", "inventory" },
})
