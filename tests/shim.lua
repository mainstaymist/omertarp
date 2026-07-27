-- Minimal environment for running Omertà RP core files under plain Lua 5.1.
-- Sets the flags core checks (OMERTA_TEST disables every engine touchpoint)
-- and provides a loader that mimics the gamemode's fixed core include order.

OMERTA_TEST = true
SERVER = true
CLIENT = false

local CORE_FILES = {
    "core/sh_core.lua",
    "core/sh_util.lua",
    "core/sh_log.lua",
    "core/sh_selftest.lua",
    "core/sh_config.lua",
    "core/sh_net.lua",
    "core/sh_module.lua",
}

local gamemodePath = "gamemodes/omertarp/gamemode/"

-- (Re)loads the core from scratch: every registry resets, so each test suite
-- starts from a clean boot.
function ReloadCore()
    Omerta = nil
    for _, f in ipairs(CORE_FILES) do
        dofile(gamemodePath .. f)
    end
end
