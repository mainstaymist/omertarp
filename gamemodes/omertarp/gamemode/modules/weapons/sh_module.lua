Omerta.Module.Register({
    name = "weapons",
    -- `inventory` because a weapon IS an item — carried, concealed, equipped,
    -- searched off a body — `treasury` because families buy them through
    -- procurement, `chat` because refusals reach the player as notices.
    depends = { "inventory", "treasury", "chat" },
})
