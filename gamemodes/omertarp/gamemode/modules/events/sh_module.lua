Omerta.Module.Register({
    name = "events",
    -- `seasons` because every event belongs to one and nothing outlives its
    -- season. Deliberately nothing else: this is a service four milestones
    -- consume, and a dependency here is a dependency all of them inherit.
    depends = { "seasons" },
})
