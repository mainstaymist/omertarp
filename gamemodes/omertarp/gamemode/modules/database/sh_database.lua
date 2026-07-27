-- Database module registration.
--
-- All functionality lives in sv_ files and never reaches clients. This shared
-- stub exists because the module loader requires every module directory to
-- register a module named after itself in BOTH realms — on the client this
-- module is an empty shell by design.

local MODULE = Omerta.Module.Register({
    name = "database",
    depends = {},
})

function MODULE:OnEnable()
    if SERVER then
        Omerta.DB.Internal.Start()
    end
end
