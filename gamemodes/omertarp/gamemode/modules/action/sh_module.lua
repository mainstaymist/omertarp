Omerta.Module.Register({
    name = "action",
    -- `hud` for the plate and nothing else. This is deliberately the thinnest
    -- dependency list in the project: a primitive four milestones consume
    -- hands every one of them whatever it depends on, and an action that
    -- needed `injury` to exist could never have been what M14 promoted it to
    -- be. What an action is interrupted BY is registered from outside
    -- (Omerta.Action.RegisterInterrupt), which is how injury keeps its rule
    -- about going down without this module knowing injury exists.
    depends = { "hud" },
})
