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
