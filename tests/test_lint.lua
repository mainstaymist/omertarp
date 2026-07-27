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

suite("lint.sql_aliases")

-- A reserved word is just as reserved when it is a column ALIAS: renaming a
-- column to org_key and then writing `SELECT org_key AS key` reintroduces the
-- exact syntax error the rename was meant to avoid, and only on the real
-- backend — every SQLite test still passes. Translate in Lua instead.
local RESERVED_ALIASES = {
    key = true, rank = true, order = true, group = true, table = true,
    index = true, ["primary"] = true, ["default"] = true, range = true,
    rows = true, system = true, lead = true, read = true, ["int"] = true,
    ["select"] = true, ["from"] = true, ["where"] = true, ["and"] = true,
    ["or"] = true, ["like"] = true, ["match"] = true, ["over"] = true,
}

check("no SQL aliases a column to a reserved word", function()
    local offenders = {}
    local pipe = io.popen("find gamemodes -name '*.lua' 2>/dev/null")
    if pipe then
        for path in pipe:lines() do
            local lineNumber = 0
            for line in io.lines(path) do
                lineNumber = lineNumber + 1
                local code = line:gsub("%-%-.*$", "")
                -- The frontier pattern is load-bearing: without it the "as" in
                -- "has key" matches and the linter cries wolf.
                for alias in code:gmatch("%f[%a][Aa][Ss]%s+([%a_][%w_]*)") do
                    if RESERVED_ALIASES[alias:lower()] then
                        offenders[#offenders + 1] = path .. ":" .. lineNumber .. " (" .. alias .. ")"
                    end
                end
            end
        end
        pipe:close()
    end

    assert(#offenders == 0,
        "SQL aliases a reserved word (map it in Lua instead) at " ..
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
