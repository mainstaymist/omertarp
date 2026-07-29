Omerta.Module.Register({
    name = "death",
    -- `injury` for the funnel and the downed-action seam, `organizations` for
    -- the roster and the chair, `events` for the durable record, `chat` because
    -- every refusal reaches the player as a notice.
    depends = { "injury", "organizations", "events", "chat" },
})
