-- The provider that is always there.
--
-- A server with no weather addon — which includes every development server,
-- every server whose operator forgot the collection, and this repository's own
-- headless test run — still has to be able to ask what time it is. This is the
-- answer it gets: a clear day at noon, forever.
--
-- It deliberately defines NO answer functions at all. It could define five
-- that return the clear-day constants and read slightly more explicitly, and
-- that was rejected: with none defined, a server that has no addon takes
-- exactly the same code path as a server whose addon could not answer one
-- particular question. One fallback, exercised constantly, instead of two that
-- can drift apart — and the tests that pin the degrade-to-clear-day behaviour
-- are then pinning the path a half-working addon uses too.
--
-- `priority = 0` and `always = true` together mean it is considered last and
-- accepted unconditionally, so it is the floor rather than a competitor. A new
-- provider file only has to declare a priority above zero to outrank it.

Omerta.Environment = Omerta.Environment or {}

Omerta.Environment.RegisterProvider("null", {
    priority = 0,
    always = true,
    believed = "no weather system detected — a clear day at noon, forever",
})
