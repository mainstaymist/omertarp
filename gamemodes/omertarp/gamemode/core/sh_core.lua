-- Root namespace and realm guards. Everything in the gamemode lives under the
-- single global `Omerta` so addon collisions stay unlikely and leak audits can
-- search networked state by one prefix.

Omerta = Omerta or {}
Omerta.Version = "0.1.0"

-- False under the headless test shim (tests/shim.lua sets OMERTA_TEST).
-- Engine-touching code (file IO, net library, hooks) must check this flag
-- instead of assuming Garry's Mod is present, so core logic stays unit-testable
-- under plain Lua 5.1.
Omerta.InEngine = (_G.OMERTA_TEST == nil)

function Omerta.AssertServer(what)
    if not SERVER then
        error((what or "this operation") .. " is server-only", 3)
    end
end

function Omerta.AssertClient(what)
    if not CLIENT then
        error((what or "this operation") .. " is client-only", 3)
    end
end
