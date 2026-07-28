Omerta.Module.Register({
    name = "treasury",
    -- `organizations` for the owner and the ladder, `inventory` because the
    -- safe is a container full of real money, `chat` because every refusal
    -- reaches the player as a notice.
    depends = { "organizations", "inventory", "chat" },
})
