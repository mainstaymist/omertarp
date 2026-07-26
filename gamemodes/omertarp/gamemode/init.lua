-- Omertà RP — server bootstrap. Deliberately thin: everything lives in
-- core/ and modules/, included from shared.lua.

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")
