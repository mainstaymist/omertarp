Omerta.Module.Register({
    name = "crime",
    -- The milestone that consumes everything and is consumed by nothing yet,
    -- so it resolves last. `business` already pulls in organizations, treasury
    -- and phone, which is why they are not restated here.
    --
    -- `action` is the timed action M14 promoted out of injury (D-046) — the
    -- register work runs on it. `events` because an operation is keyed to a
    -- durable EventID and M14 is the first writer other than death. `identity`
    -- for the concealment provider D-047 registers.
    depends = {
        "action", "events", "business", "inventory", "weapons",
        "injury", "interaction", "identity", "hud", "chat",
    },
})
