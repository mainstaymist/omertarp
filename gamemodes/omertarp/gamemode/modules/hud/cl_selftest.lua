-- In-engine acceptance suite: `omerta_hud_selftest`, run in a CLIENT console —
-- the HUD only exists there.
--
-- The headline check is the milestone's actual acceptance criterion: for a
-- healthy, idle character standing still and looking at nothing, the screen is
-- empty. That is checkable rather than eyeballed, and it stays checkable as
-- later milestones register elements.

local function buildSteps()
    local steps = {}

    steps[#steps + 1] = { name = "controller is present", required = true, fn = function(pass, fail)
        if not Omerta.HUD or not Omerta.HUD.GetElements then fail("HUD controller missing") return end
        local elements = Omerta.HUD.GetElements()
        if #elements == 0 then fail("no elements registered") return end
        local ids = {}
        for _, def in ipairs(elements) do ids[#ids + 1] = def.id end
        pass(#elements .. " elements: " .. table.concat(ids, ", "))
    end }

    steps[#steps + 1] = { name = "every element declares a condition", fn = function(pass, fail)
        for _, def in ipairs(Omerta.HUD.GetElements()) do
            -- An element without a condition would be permanent, which the
            -- design forbids outright.
            if type(def.visible) ~= "function" then
                fail("element '" .. def.id .. "' has no visible() — it would be permanent")
                return
            end
        end
        pass()
    end }

    -- The empty-screen rule, with its ONE permitted exception.
    --
    -- D-017 replaced the engine crosshair with a mark that appeared only over
    -- a target, and playing it proved that wrong: a centre that blinks in and
    -- out gives the eye nothing to rest on, and you cannot aim at a point that
    -- is not drawn. The dot is now always present and carries the same
    -- information by BRIGHTNESS instead — faint with nothing in reach, full
    -- when there is. It is the only element allowed to be on an idle screen,
    -- and this test still fails the moment a second one joins it.
    local IDLE_ALLOWED = { ["interactable"] = true }

    steps[#steps + 1] = { name = "the screen is empty when idle", fn = function(pass, fail)
        local unexpected = {}
        for _, id in ipairs(Omerta.HUD.VisibleElements()) do
            if not IDLE_ALLOWED[id] then unexpected[#unexpected + 1] = id end
        end
        if #unexpected > 0 then
            fail("on screen: " .. table.concat(unexpected, ", ") ..
                " — stand still, look at nothing, and re-run")
            return
        end
        pass("nothing but the crosshair")
    end }

    steps[#steps + 1] = { name = "fade maths", fn = function(pass, fail)
        local S = Omerta.HUD.StepAlpha
        if S(0, true, 0.1, 0.2) ~= 0.5 then fail("half a fade in should be 0.5") return end
        if S(1, true, 0.1, 0.2) ~= 1 then fail("visible must clamp at 1") return end
        if S(0.5, false, 0.1, 0.2) ~= 0 then fail("fading out should reach 0") return end
        if S(0, false, 0.1, 0.2) ~= 0 then fail("hidden must clamp at 0") return end
        if S(0, true, 0.1, 0) ~= 1 then fail("zero fade should be instant") return end
        pass()
    end }

    steps[#steps + 1] = { name = "scale clamps for accessibility", fn = function(pass, fail)
        local C = Omerta.HUD.ClampScale
        if C(0.1) ~= Omerta.HUD.SCALE_MIN then fail("below range should clamp up") return end
        if C(9) ~= Omerta.HUD.SCALE_MAX then fail("above range should clamp down") return end
        if C("nonsense") ~= 1 then fail("garbage should fall back to 1") return end
        if C(1.25) ~= 1.25 then fail("valid values pass through") return end
        pass("current scale " .. Omerta.HUD.Scale())
    end }

    steps[#steps + 1] = { name = "engine HUD is suppressed", fn = function(pass, fail)
        for _, name in ipairs({ "CHudHealth", "CHudBattery", "CHudAmmo", "CHudCrosshair" }) do
            if hook.Run("HUDShouldDraw", name) ~= false then
                fail(name .. " is still drawn")
                return
            end
        end
        pass("health, armour, ammo and crosshair are gone")
    end }

    return steps
end

concommand.Add("omerta_hud_selftest", function()
    Omerta.SelfTest.Run("hud.selftest", buildSteps())
end)
