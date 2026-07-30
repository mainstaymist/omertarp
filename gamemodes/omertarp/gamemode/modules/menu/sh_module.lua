Omerta.Module.Register({
    name = "menu",
    -- `characters` because the menu is what stands in front of character
    -- creation and hands over to it, `hud` for the design tokens and fonts,
    -- `seasons` because the menu names the season the city is running.
    depends = { "characters", "hud", "seasons" },
})
