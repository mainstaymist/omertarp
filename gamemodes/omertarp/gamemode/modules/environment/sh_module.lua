Omerta.Module.Register({
    name = "environment",
    -- Nothing, deliberately.
    --
    -- This is a service later milestones read (D-043 names M15's witnesses,
    -- M16's NPCs and D-014's recognition as the candidates), and `events`
    -- already wrote down the reason a service declares no dependencies: a
    -- dependency here is a dependency every consumer inherits.
    --
    -- The one thing it touches outside itself is the front end's per-map
    -- vantage registry, and it reaches that from OnEnable — which runs after
    -- every module has finished loading — rather than by depending on `menu`.
    -- A weather seam that cannot boot without the main menu would be the wrong
    -- shape, and would drag characters/hud/seasons/database behind it into
    -- every gameplay module that later asks whether it is raining.
    depends = {},
})
