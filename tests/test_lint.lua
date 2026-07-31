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

suite("lint.module_registration")

-- Every module directory carries an sh_module.lua containing nothing but its
-- Register call. The loader includes those first, for every module, so the
-- dependency graph is known before any real code runs and directories can be
-- included in the order they declare. A module missing one, or registering
-- under the wrong name, breaks that ordering at boot — on the client first,
-- where the failure is hardest to read.
check("every module directory registers itself in sh_module.lua", function()
    local dirs = {}
    local pipe = io.popen("find gamemodes/*/gamemode/modules -mindepth 1 -maxdepth 1 -type d 2>/dev/null")
    if pipe then
        for line in pipe:lines() do dirs[#dirs + 1] = line end
        pipe:close()
    end
    assert(#dirs > 0, "linter found no module directories to scan")

    local offenders = {}
    for _, dir in ipairs(dirs) do
        local expected = dir:match("([^/]+)$")
        local handle = io.open(dir .. "/sh_module.lua", "r")
        if not handle then
            offenders[#offenders + 1] = expected .. " (no sh_module.lua)"
        else
            local source = handle:read("*a")
            handle:close()
            if not source:find('name%s*=%s*"' .. expected .. '"') then
                offenders[#offenders + 1] = expected .. " (registers a different name)"
            end
        end
    end

    assert(#offenders == 0,
        "module registration is missing or misnamed at " .. table.concat(offenders, ", "))
end)

-- The registration file declares and does nothing else. Anything it touched
-- would run before every other module had even registered, which is the exact
-- ordering problem the two-phase include exists to remove.
check("a registration file does nothing but register", function()
    local offenders = {}
    local pipe = io.popen("find gamemodes/*/gamemode/modules -name sh_module.lua 2>/dev/null")
    if pipe then
        for path in pipe:lines() do
            local handle = io.open(path, "r")
            if handle then
                local lineNumber = 0
                local inBlock = false
                for line in handle:lines() do
                    lineNumber = lineNumber + 1
                    local code = line:gsub("%-%-.*$", ""):gsub("%s+$", "")
                    if code:find("Omerta%.Module%.Register") then inBlock = true end
                    if inBlock and code:find("^%}%)") then inBlock = false
                    elseif not inBlock and code ~= "" and code:find("Omerta%.") then
                        offenders[#offenders + 1] = path .. ":" .. lineNumber
                    end
                end
                handle:close()
            end
        end
        pipe:close()
    end

    assert(#offenders == 0,
        "a registration file does more than register at " .. table.concat(offenders, ", "))
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

suite("lint.entity_labels")

-- The interaction dot names what it is pointing at, and the name comes from the
-- entity's own OmertaLabel. Registering a class as interactable without giving
-- it one produces a dot that lights up over an unidentifiable object — a
-- regression nothing else catches, because both halves keep working alone.
check("every interactable class labels itself", function()
    local classes = {}
    local pipe = io.popen("find gamemodes -name '*.lua' 2>/dev/null")
    assert(pipe, "linter could not scan for interactable classes")
    for path in pipe:lines() do
        for line in io.lines(path) do
            local code = line:gsub("%-%-.*$", "")
            local class = code:match('RegisterInteractableClass%s*%(%s*"([%w_]+)"')
            if class then classes[class] = path end
        end
    end
    pipe:close()
    assert(next(classes), "linter found no interactable classes to scan")

    local offenders = {}
    for class, registeredIn in pairs(classes) do
        local handle = io.open("gamemodes/omertarp/entities/entities/" .. class .. ".lua", "r")
        if not handle then
            offenders[#offenders + 1] = class .. " (no entity file; registered in " ..
                registeredIn .. ")"
        else
            local source = handle:read("*a")
            handle:close()
            if not source:find("function ENT:OmertaLabel", 1, true) then
                offenders[#offenders + 1] = class .. " (no OmertaLabel)"
            end
        end
    end

    assert(#offenders == 0,
        "interactable class without a label at " .. table.concat(offenders, ", "))
end)

-- A label is drawn for everybody in range, so anything it can reach has already
-- left the server. An entity that networks a container id, a line id or an
-- owner is publishing exactly what M9/M11/M12 keep server-side on purpose.
check("no entity networks a private identifier", function()
    local FORBIDDEN = {
        Container = true, ContainerId = true, Line = true, LineId = true,
        Owner = true, OwnerId = true, Business = true, BusinessId = true,
        Organization = true, OrganizationId = true, Instance = true,
        InstanceId = true, Character = true, CharacterId = true,
        Number = true, -- PublicNumber is fine; a bare Number is the private one
    }

    local offenders = {}
    local pipe = io.popen("find gamemodes -path '*/entities/*' -name '*.lua' 2>/dev/null")
    if pipe then
        for path in pipe:lines() do
            local lineNumber = 0
            for line in io.lines(path) do
                lineNumber = lineNumber + 1
                local code = line:gsub("%-%-.*$", "")
                local name = code:match('NetworkVar%s*%([^,]+,%s*%d+%s*,%s*"([%w_]+)"')
                if name and FORBIDDEN[name] then
                    offenders[#offenders + 1] = path .. ":" .. lineNumber .. " (" .. name .. ")"
                end
            end
        end
        pipe:close()
    end

    assert(#offenders == 0,
        "entity networks a private identifier (keep it on the server) at " ..
        table.concat(offenders, ", "))
end)

suite("lint.module_lifecycle")

-- The seventh load-order incident, and the most expensive so far: two files in
-- ONE module both defining `function MODULE:OnEnable()`.
--
-- `MODULE` is the module's single definition table and files are included
-- alphabetically, so the later file does not add to the earlier one — it
-- REPLACES it, silently. When sv_help.lua joined the accounts module it took
-- out the OnEnable that registers PlayerInitialSpawn, so no account ever
-- loaded, no character state was ever sent, and every player on the server sat
-- frozen at spawn looking at an empty screen with nothing in the log to say
-- why. Nothing errored; the boot looked perfect.
--
-- A module may define each lifecycle method exactly once, in one file.
check("no module defines a lifecycle method twice", function()
    local dirs = {}
    local pipe = io.popen("find gamemodes/*/gamemode/modules -mindepth 1 -maxdepth 1 -type d 2>/dev/null")
    assert(pipe, "linter could not scan for modules")
    for line in pipe:lines() do dirs[#dirs + 1] = line end
    pipe:close()
    assert(#dirs > 0, "linter found no modules to scan")

    local offenders = {}
    for _, dir in ipairs(dirs) do
        local seen = {} -- method -> first file that defined it
        local files = io.popen("ls " .. dir .. "/*.lua 2>/dev/null")
        if files then
            for path in files:lines() do
                for line in io.lines(path) do
                    local code = line:gsub("%-%-.*$", "")
                    local method = code:match("^function%s+MODULE:([%w_]+)%s*%(")
                    if method then
                        local name = path:match("([^/]+)$")
                        if seen[method] then
                            offenders[#offenders + 1] = string.format(
                                "%s defines MODULE:%s in both %s and %s",
                                dir:match("([^/]+)$"), method, seen[method], name)
                        else
                            seen[method] = name
                        end
                    end
                end
            end
            files:close()
        end
    end

    assert(#offenders == 0,
        "a later file silently replaces the earlier one — move the work into " ..
        "the existing lifecycle, or do it at file scope: " ..
        table.concat(offenders, "; "))
end)

suite("lint.help_coverage")

-- omerta_help exists so staff can find commands without grepping the source.
-- A directory that misses entries is worse than none — it teaches people it
-- is complete. So the machine checks it: every concommand.Add("omerta_…") in
-- the tree must be described in accounts/sv_help.lua.
check("every console command is described in omerta_help", function()
    local registered = {}
    local pipe = io.popen("grep -rhoP 'concommand\\.Add\\(\"omerta_[a-z_]+' " ..
        "gamemodes/*/gamemode gamemodes/*/entities 2>/dev/null")
    assert(pipe, "linter could not scan for commands")
    for line in pipe:lines() do
        local name = line:match("(omerta_[a-z_]+)")
        if name then registered[name] = true end
    end
    pipe:close()
    assert(next(registered), "linter found no commands to check")

    local handle = io.open("gamemodes/omertarp/gamemode/modules/accounts/sv_help.lua", "r")
    assert(handle, "sv_help.lua is missing")
    local source = handle:read("*a")
    handle:close()

    local missing = {}
    for name in pairs(registered) do
        if not source:find('%["' .. name .. '"%]') then
            missing[#missing + 1] = name
        end
    end
    table.sort(missing)
    assert(#missing == 0,
        "commands missing from omerta_help (describe them in sv_help.lua): " ..
        table.concat(missing, ", "))
end)

suite("lint.include_order")

-- The fifth load-order bug on this project, made into something a machine
-- checks rather than something a person remembers.
--
-- Files inside a module are included shared first, then CLIENT, then server,
-- alphabetically within each realm. So cl_death.lua loads before cl_injury.lua
-- and sv_injury.lua before sv_repository.lua. A file-scope
--
--     local C = Omerta.Injury.Client
--
-- therefore captures nil whenever the file that creates that table sorts
-- later, and nothing goes wrong until the first hook fires — at which point it
-- errors once per frame.
--
-- The safe idiom, which every shipped module already uses for Internal, is to
-- create the table in the same file before capturing it:
--
--     Omerta.Injury.Client = Omerta.Injury.Client or {}
--     local C = Omerta.Injury.Client
--
-- so whichever file loads first makes it and the rest share the same table.
-- This lint models the loader's own ordering and flags every capture that is
-- neither guarded that way nor satisfied by an earlier file.

local REALM_ORDER = { sh = 1, cl = 2, sv = 3 }

local function includeRank(fileName)
    local prefix = fileName:sub(1, 2)
    return (REALM_ORDER[prefix] or 9) * 1000, fileName
end

local function moduleDirs()
    local dirs = {}
    local pipe = io.popen("find gamemodes/*/gamemode/modules -mindepth 1 -maxdepth 1 -type d 2>/dev/null")
    if pipe then
        for line in pipe:lines() do dirs[#dirs + 1] = line end
        pipe:close()
    end
    return dirs
end

local function filesIn(dir)
    local files = {}
    local pipe = io.popen("ls " .. dir .. "/*.lua 2>/dev/null")
    if pipe then
        for path in pipe:lines() do
            files[#files + 1] = { path = path, name = path:match("([^/]+)$") }
        end
        pipe:close()
    end
    table.sort(files, function(a, b)
        local ra = REALM_ORDER[a.name:sub(1, 2)] or 9
        local rb = REALM_ORDER[b.name:sub(1, 2)] or 9
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    return files
end

check("no file captures a table that has not been created yet", function()
    local dirs = moduleDirs()
    assert(#dirs > 0, "linter found no module directories to scan")

    local offenders = {}
    for _, dir in ipairs(dirs) do
        local files = filesIn(dir)

        -- Pass one: which file first creates each namespace path, and which
        -- files guard it with the `or {}` idiom.
        local createdAt, guardedIn = {}, {}
        for index, file in ipairs(files) do
            for line in io.lines(file.path) do
                local code = line:gsub("%-%-.*$", "")
                local lhs, rhs = code:match("^([%w_%.]+)%s*=%s*(.-)$")
                if lhs and lhs:find("%.") then
                    if not createdAt[lhs] then createdAt[lhs] = index end
                    if rhs:find(lhs .. "%s+or%s*{}", 1) or rhs:find("^" .. lhs:gsub("%.", "%%.") .. "%s+or") then
                        guardedIn[file.name .. "|" .. lhs] = true
                    end
                end
            end
        end

        -- Pass two: every file-scope capture, checked against that.
        for index, file in ipairs(files) do
            local lineNumber = 0
            for line in io.lines(file.path) do
                lineNumber = lineNumber + 1
                local code = line:gsub("%-%-.*$", "")
                local path = code:match("^local%s+[%w_]+%s*=%s*([%w_%.]+)%s*$")
                -- Needs at least two dots to be a module sub-table rather than
                -- a plain global, and must not be a call.
                if path and select(2, path:gsub("%.", "")) >= 2 then
                    local origin = createdAt[path]
                    local guarded = guardedIn[file.name .. "|" .. path]
                    if origin and origin > index and not guarded then
                        offenders[#offenders + 1] = string.format(
                            "%s:%d captures %s, created later in %s",
                            file.path, lineNumber, path, files[origin].name)
                    end
                end
            end
        end
    end

    assert(#offenders == 0,
        "file-scope capture of a not-yet-created table (add `X = X or {}` first) at " ..
        table.concat(offenders, "; "))
end)
