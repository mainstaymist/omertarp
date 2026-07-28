Omerta.Module.Register({
    name = "phone",
    -- `chat` for the voice seam and the text path, `inventory` for quarters,
    -- `treasury` (and through it `organizations`) because a private line is
    -- something a family buys.
    depends = { "chat", "inventory", "organizations", "treasury" },
})
