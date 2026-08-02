Omerta.Module.Register({
    name = "business",
    -- `interaction` because the counter is an M5 interaction: it was built on
    -- the engine's +use, which stopped being reachable the day M8 registered
    -- omerta_business as an interactable class and the client began swallowing
    -- the E press.
    depends = { "organizations", "treasury", "inventory", "chat", "interaction" },
})
