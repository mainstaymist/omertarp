-- Headless test runner for the Omertà RP core.
-- Usage (from the repository root):  lua tests/run_tests.lua
-- Exits non-zero on any failure, so CI can gate on it.

dofile("tests/shim.lua")

local passed, failed = 0, 0
local currentSuite = "?"

function suite(name)
    currentSuite = name
    ReloadCore() -- every suite starts from a clean boot
end

function check(label, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("FAIL [%s] %s: %s", currentSuite, label, tostring(err)))
    end
end

function expectError(label, pattern, fn)
    check(label, function()
        local ok, err = pcall(fn)
        assert(not ok, "expected an error, got none")
        assert(tostring(err):find(pattern, 1, true),
            "error did not mention '" .. pattern .. "': " .. tostring(err))
    end)
end

local TEST_FILES = {
    "tests/test_util.lua",
    "tests/test_config.lua",
    "tests/test_module.lua",
    "tests/test_net.lua",
    "tests/test_database.lua",
    "tests/test_accounts.lua",
    "tests/test_seasons.lua",
    "tests/test_characters.lua",
    "tests/test_identity.lua",
    "tests/test_hud.lua",
    "tests/test_menu.lua",
    "tests/test_chat.lua",
    "tests/test_inventory.lua",
    "tests/test_organizations.lua",
    "tests/test_treasury.lua",
    "tests/test_phone.lua",
    "tests/test_business.lua",
    "tests/test_population.lua",
    "tests/test_action.lua",
    "tests/test_injury.lua",
    "tests/test_death.lua",
    "tests/test_weapons.lua",
    "tests/test_knock.lua",
    "tests/test_environment.lua",
    "tests/test_lint.lua",
}

for _, f in ipairs(TEST_FILES) do
    dofile(f)
end

print(string.format("tests: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
