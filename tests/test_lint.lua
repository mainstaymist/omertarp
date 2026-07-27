suite("lint.gm_global")

-- The `GM` global is only valid while the gamemode's files are being included;
-- the engine clears it once loading finishes. Referencing it inside a hook body
-- therefore indexes nil at runtime — this crashed the first in-engine boot
-- (shared.lua's Initialize logging GM.Name instead of self.Name).
--
-- Heuristic: legitimate GM references sit at column 0 (top-level field
-- assignments and `function GM:Hook()` definitions). Any *indented* reference
-- is inside a block, which means it runs after load. Line comments are
-- stripped first; keep "GM." out of string literals so this stays quiet.

local function gamemodeLuaFiles()
    local list = {}
    local pipe = io.popen("find gamemodes -name '*.lua' 2>/dev/null")
    if not pipe then return list end
    for line in pipe:lines() do list[#list + 1] = line end
    pipe:close()
    return list
end

check("the GM global is never used inside a block", function()
    local files = gamemodeLuaFiles()
    assert(#files > 0, "linter found no gamemode Lua files to scan")

    local offenders = {}
    for _, path in ipairs(files) do
        local lineNumber = 0
        for line in io.lines(path) do
            lineNumber = lineNumber + 1
            local code = line:gsub("%-%-.*$", "") -- drop line comments
            if code:find("^%s+.*%f[%w]GM[%.:%[]") then
                offenders[#offenders + 1] = path .. ":" .. lineNumber
            end
        end
    end

    assert(#offenders == 0,
        "GM used inside a block (use self/GAMEMODE instead) at " ..
        table.concat(offenders, ", "))
end)

suite("lint.entity_bases")

-- Scripted entities may only derive from bases the ENGINE provides. The
-- tempting ones (base_gmodentity, base_gmodentity's relatives) are defined by
-- SANDBOX, and this gamemode derives base — so deriving from them fails at
-- load with "Trying to derive entity X from non existant entity Y", taking the
-- whole class with it and every feature built on it.
local SANDBOX_BASES = {
    base_gmodentity = true,
    base_wire_entity = true,
}

check("entities derive only from engine bases, never sandbox ones", function()
    local offenders = {}
    local pipe = io.popen("find gamemodes -path '*/entities/*' -name '*.lua' 2>/dev/null")
    if pipe then
        for path in pipe:lines() do
            local lineNumber = 0
            for line in io.lines(path) do
                lineNumber = lineNumber + 1
                local code = line:gsub("%-%-.*$", "")
                local base = code:match("ENT%.Base%s*=%s*[\"']([%w_]+)[\"']")
                if base and SANDBOX_BASES[base] then
                    offenders[#offenders + 1] = path .. ":" .. lineNumber .. " (" .. base .. ")"
                end
            end
        end
        pipe:close()
    end

    assert(#offenders == 0,
        "entity derives from a sandbox base (use base_anim/base_entity) at " ..
        table.concat(offenders, ", "))
end)
