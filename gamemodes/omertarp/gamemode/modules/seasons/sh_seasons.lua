-- Seasons module registration. All functionality is server-side (sv_ files);
-- clients learn season facts only through later systems that need to display
-- them (M4+). Empty shell in the client realm by design.

Omerta.Module.Register({
    name = "seasons",
    depends = { "database", "accounts" },
})
