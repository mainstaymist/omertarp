Omerta.Module.Register({
    name = "injury",
    -- `characters` for status and the death cascade, `interaction` for every
    -- action performed on a body, `identity` because a body is a person and
    -- resolves like one, `hud` for the indicator and the movement modifiers,
    -- `inventory` for stabilization items and searching, `chat` because every
    -- refusal reaches the player as a notice, `business` for the clinic.
    depends = { "characters", "interaction", "identity", "hud", "inventory", "chat", "business" },
})
