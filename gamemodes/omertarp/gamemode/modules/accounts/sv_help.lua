-- omerta_help: the staff card index.
--
-- Every console command the gamemode registers, with what it does and how to
-- call it — because the alternative is the project lead grepping the source
-- mid-playtest to remember how to seed a family, which actually happened.
--
-- This table is kept honest BY A LINT TEST, not by discipline: the headless
-- suite scans the tree for concommand.Add("omerta_…") and fails if a command
-- exists that this file does not describe. Add a command, describe it here,
-- or the suite goes red.
--
-- Lives in accounts because staffing does (audit, superadmin gates); it is a
-- directory, not a framework — one table, one command.

-- This file deliberately does NOT define a module lifecycle method.
--
-- It used to define MODULE:OnEnable, and that one line froze every player on
-- the server. `MODULE` is the module's shared definition table, files inside a
-- module are included alphabetically, and sv_help sorts after sv_accounts — so
-- this file's OnEnable REPLACED the one that registers PlayerInitialSpawn.
-- Accounts stopped loading, no character state was ever sent, and every player
-- sat gated at spawn looking at an empty screen with nothing in the log.
--
-- A console command needs no lifecycle: registering it at file scope is both
-- simpler and impossible to get wrong this way. There is now a lint test that
-- fails the suite if two files in one module define the same lifecycle method.

-- [command] = { usage (arguments only, "" for none), what it does, area }.
-- `client = true` marks commands that must be run from a CLIENT console.
local COMMANDS = {
    -- Seasons
    ["omerta_season_create"] = { usage = "", what = "Create the next season. Takes no name — seasons are numbered, and the number is one past the highest that has existed.", area = "Seasons" },
    ["omerta_season_start"] = { usage = "<id>", what = "Start a season; the city opens.", area = "Seasons" },
    ["omerta_season_end"] = { usage = "<id>", what = "End a season.", area = "Seasons" },
    ["omerta_season_list"] = { usage = "", what = "List all seasons.", area = "Seasons" },
    ["omerta_season_status"] = { usage = "", what = "The active season, if any.", area = "Seasons" },

    -- Characters
    ["omerta_character_retire"] = { usage = "<characterId>", what = "Retire a character.", area = "Characters" },
    ["omerta_whoami"] = { usage = "[steamID64]", what = "What the server believes about a connected player: account, season, character, what state it told them, whether they are frozen. The first thing to run when somebody is stuck at spawn.", area = "Characters" },
    ["omerta_portrait_clear"] = { usage = "<characterId>", what = "Delete a character's portrait.", area = "Characters" },

    -- Giving (pre-economy faucets)
    ["omerta_item_give"] = { usage = "<itemId> [quantity] [steamID64]", what = "Give items (e.g. weapon.revolver, ammo.38, medical.bandage, drink.whiskey).", area = "Giving" },
    ["omerta_money_give"] = { usage = "<dollars> [steamID64]", what = "Mint cash into a pocket.", area = "Giving" },
    ["omerta_container_spawn"] = { usage = "<id> [capacity]", what = "Spawn a persistent container in front of you.", area = "Giving" },

    -- Inventory
    ["omerta_inventory"] = { usage = "", what = "Pin the inventory window open without holding C (client console).", area = "Inventory", client = true },
    ["omerta_inventory_dump"] = { usage = "", what = "Print your own stacks, bulk and cash.", area = "Inventory" },
    ["omerta_model_audit"] = { usage = "", what = "Report item models that do not resolve.", area = "Inventory" },

    -- Organizations
    ["omerta_org_list"] = { usage = "", what = "List this season's institutions and their keys.", area = "Organizations" },
    ["omerta_org_sync"] = { usage = "", what = "Create this season's institution rows if missing.", area = "Organizations" },
    ["omerta_org_seed"] = { usage = "<orgKey> <steamID64>", what = "Seat a connected player at the top of an institution.", area = "Organizations" },
    ["omerta_org_roster"] = { usage = "<orgKey>", what = "Print an institution's roster.", area = "Organizations" },
    ["omerta_org_open"] = { usage = "", what = "Open the organization window (client console).", area = "Organizations", client = true },
    ["omerta_organization"] = { usage = "", what = "Open the organization window (client console).", area = "Organizations", client = true },

    -- Treasury
    ["omerta_treasury_place"] = { usage = "<orgKey>", what = "Spawn an institution's safe in front of you.", area = "Treasury" },
    ["omerta_treasury"] = { usage = "", what = "Open the treasury window at a safe (client console).", area = "Treasury", client = true },
    ["omerta_treasury_books"] = { usage = "<orgKey>", what = "Print a treasury's ledger.", area = "Treasury" },

    -- Business
    ["omerta_business_place"] = { usage = "<typeKey>", what = "Place a business where you stand (e.g. clinic, speakeasy).", area = "Business" },
    ["omerta_business_list"] = { usage = "", what = "List placed businesses.", area = "Business" },
    ["omerta_business_stockroom"] = { usage = "<businessId>", what = "Spawn a business's stock container.", area = "Business" },

    -- Phone
    ["omerta_phone_place"] = { usage = "", what = "Place a payphone in front of you.", area = "Phone" },
    ["omerta_phone_list"] = { usage = "", what = "List telephone lines.", area = "Phone" },
    ["omerta_phone_records"] = { usage = "<number>", what = "Print a line's call records.", area = "Phone" },

    -- Injury and death
    ["omerta_injury_state"] = { usage = "<state> [characterId]", what = "Force an injury state (healthy, injured, critical, incapacitated, stabilized, recovering, dead).", area = "Injury" },
    ["omerta_injury_list"] = { usage = "", what = "Everyone currently hurt, with clocks.", area = "Injury" },
    ["omerta_injury_leg"] = { usage = "<break|heal> [characterId]", what = "Break or set a leg without finding a roof to jump off. Breaking plays the snap and starts the limp; healing is what a doctor at a clinic does. Defaults to breaking your own.", area = "Injury" },
    ["omerta_injury_history"] = { usage = "<characterId>", what = "A character's injury event history.", area = "Injury" },
    ["omerta_death_kill"] = { usage = "<characterId>", what = "Staff-kill a character through the death funnel.", area = "Injury" },
    ["omerta_events"] = { usage = "[count]", what = "Recent durable events (death.confirmed and the rest).", area = "Injury" },

    -- Weapons
    ["omerta_weapons_list"] = { usage = "", what = "The arsenal: ids, classes, damage, calibers.", area = "Weapons" },

    -- Identity
    ["omerta_identity_who_knows"] = { usage = "<characterId>", what = "Who knows this character, and as what.", area = "Identity" },

    -- Diagnostics
    ["omerta_help"] = { usage = "[area]", what = "This list, or one area of it.", area = "Diagnostics" },
    ["omerta_env"] = { usage = "", what = "The world outside: which weather/time provider was detected, the time, whether it is night, the weather, and the map name. Runs from either console — the server's answer and a client's may differ, which is itself the useful part.", area = "Diagnostics" },
    ["omerta_leak_audit"] = { usage = "", what = "Scan networked state for identity leaks (M6).", area = "Diagnostics" },
    ["omerta_leak_audit_client"] = { usage = "", what = "The client half of the leak audit (client console).", area = "Diagnostics", client = true },
    ["omerta_demo_ping"] = { usage = "", what = "M0's loopback proof.", area = "Diagnostics" },
    ["omerta_db_selftest"] = { usage = "", what = "Database CRUD/transaction/migration suite.", area = "Selftests" },
    ["omerta_accounts_selftest"] = { usage = "", what = "Accounts self-test.", area = "Selftests" },
    ["omerta_seasons_selftest"] = { usage = "", what = "Seasons self-test.", area = "Selftests" },
    ["omerta_characters_selftest"] = { usage = "", what = "Characters self-test.", area = "Selftests" },
    ["omerta_identity_selftest"] = { usage = "", what = "Identity self-test.", area = "Selftests" },
    ["omerta_hud_selftest"] = { usage = "", what = "HUD self-test (client console).", area = "Selftests", client = true },
    ["omerta_chat_selftest"] = { usage = "", what = "Chat self-test.", area = "Selftests" },
    ["omerta_inventory_selftest"] = { usage = "", what = "Inventory self-test.", area = "Selftests" },
    ["omerta_org_selftest"] = { usage = "", what = "Organizations self-test.", area = "Selftests" },
    ["omerta_treasury_selftest"] = { usage = "", what = "Treasury self-test.", area = "Selftests" },
    ["omerta_business_selftest"] = { usage = "", what = "Business self-test.", area = "Selftests" },
    ["omerta_phone_selftest"] = { usage = "", what = "Phone self-test.", area = "Selftests" },
    ["omerta_injury_selftest"] = { usage = "", what = "Injury self-test.", area = "Selftests" },
    ["omerta_death_selftest"] = { usage = "", what = "Confirmed-death self-test.", area = "Selftests" },
}

-- Exposed for the lint test: the suite compares this against every
-- concommand.Add in the tree.
Omerta.Accounts = Omerta.Accounts or {}
Omerta.Accounts.HELP = COMMANDS

local AREA_ORDER = {
    "Seasons", "Characters", "Giving", "Inventory", "Organizations",
    "Treasury", "Business", "Phone", "Injury", "Weapons", "Identity",
    "Diagnostics", "Selftests",
}

if Omerta.InEngine then
    concommand.Add("omerta_help", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end

        local filter = args[1] and string.lower(args[1]) or nil
        for _, area in ipairs(AREA_ORDER) do
            if not filter or string.lower(area) == filter then
                Omerta.Log.Info("help", "%s", string.upper(area))
                -- Sorted within the area, so the list reads the same every time.
                local names = {}
                for name, def in pairs(COMMANDS) do
                    if def.area == area then names[#names + 1] = name end
                end
                table.sort(names)
                for _, name in ipairs(names) do
                    local def = COMMANDS[name]
                    Omerta.Log.Info("help", "  %-28s %s%s%s", name,
                        def.usage ~= "" and (def.usage .. " — ") or "",
                        def.what,
                        def.client and "  [client console]" or "")
                end
            end
        end
        if not filter then
            Omerta.Log.Info("help", "omerta_help <area> narrows this down.")
        end
    end)
end
