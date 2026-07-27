-- Omertà RP — shared bootstrap.
-- Thin by design: establishes the gamemode table, includes the core in a fixed
-- order, then hands everything else to the module loader (core/sh_module.lua).

GM.Name   = "Omertà RP"
GM.Author = "Omertà RP project"

DeriveGamemode("base")

-- Paths are rooted at the gamemode folder because that is what the "LUA"
-- search path expects for gamemode content (gamemodes/ is a search root).
-- Fail with a clear message rather than concatenating nil into every path.
if not GM.FolderName or GM.FolderName == "" then
    error("Omertà RP: the gamemode folder name is unset — the gamemode must be " ..
        "installed as garrysmod/gamemodes/<name>/ with a matching <name>.txt")
end

local prefix = GM.FolderName .. "/gamemode/"

-- Core load order is explicit and must stay minimal: each file may depend only
-- on the ones above it. Everything beyond core is a module under modules/.
local CORE_FILES = {
    "core/sh_core.lua",
    "core/sh_util.lua",
    "core/sh_log.lua",
    "core/sh_selftest.lua",
    "core/sh_config.lua",
    "core/sh_net.lua",
    "core/sh_module.lua",
}

for _, f in ipairs(CORE_FILES) do
    if SERVER then AddCSLuaFile(prefix .. f) end
    include(prefix .. f)
end

Omerta.Module.IncludeAll(prefix .. "modules")

-- IMPORTANT for every hook in this project: the `GM` global is only valid
-- while the gamemode files are being included. Once loading finishes the
-- engine clears it, so inside a hook body use `self` (or GAMEMODE) — never
-- `GM`, which is nil by then.
function GM:Initialize()
    Omerta.Config.Finalize()
    Omerta.Module.EnableAll()
    Omerta.Log.Info("core", "%s %s initialized (%s realm)",
        self.Name, Omerta.Version, SERVER and "server" or "client")

    if self.BaseClass and self.BaseClass.Initialize then
        self.BaseClass.Initialize(self)
    end
end

-- Lua auto-refresh reruns the whole gamemode load (all registries rebuild),
-- but GM:Initialize does not run again — so finalize/enable must be repeated
-- here before modules get their OnReload.
function GM:OnReloaded()
    Omerta.Config.Finalize()
    Omerta.Module.EnableAll()
    Omerta.Module.ReloadAll()
    Omerta.Log.Info("core", "reloaded")
end
