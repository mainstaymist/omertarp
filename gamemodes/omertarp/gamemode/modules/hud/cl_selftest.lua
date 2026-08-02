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

    -- THE ONE THING ON A PERMANENT SCREEN THAT IS NOT AN ELEMENT, named here
    -- rather than excused in the assertion above.
    --
    -- The lens vignette is always drawn. It is allowed to be, because it is
    -- atmosphere and not information: it has no state, answers no question, and
    -- a player who studies it learns nothing — it is the lens the picture is
    -- taken through rather than something printed on top of it. sh_hud.lua
    -- argues that in full.
    --
    -- The argument is only worth anything if it is checked, and this is the
    -- check. What it defends is not the vignette, it is the door the vignette
    -- came through: "atmosphere, not information" must never become the excuse
    -- that lets a permanent ammunition ring or a permanent compass onto an idle
    -- screen. So the rule is stated as a property — a lens is NOT registered
    -- with the controller, is bounded to something felt rather than seen, and
    -- draws literally nothing when it is switched off. Anything that carries
    -- information fails all three the moment it tries, because it needs a
    -- visible() condition and a place in the stack, which is the controller.
    steps[#steps + 1] = { name = "the vignette is a lens, not an element", fn = function(pass, fail)
        for _, def in ipairs(Omerta.HUD.GetElements()) do
            -- M19's bleed-out vignette is conditional and belongs to the
            -- controller; anything else by that name has joined the idle screen.
            if def.id:find("vignette", 1, true) and def.id ~= "injury.vignette" then
                fail("'" .. def.id .. "' is a registered element — a permanent " ..
                    "one is exactly what the rule above forbids")
                return
            end
        end

        local V = Omerta.HUD.VIGNETTE
        if not V or not Omerta.HUD.VignetteBands then
            fail("the lens is missing")
            return
        end
        if V.EDGE > 0.2 then
            fail(math.Round(V.EDGE * 100) .. "% at the edge — slight means a " ..
                "picture with weight, not a vignette you can see")
            return
        end

        local _, _, off = Omerta.HUD.VignetteBands(ScrW(), ScrH(), 0)
        if off ~= 0 then
            fail("switched off, it must draw nothing at all")
            return
        end

        -- The live presence as well as the setting, because they legitimately
        -- disagree: the lens hands the edges to M19's bleed-out vignette while
        -- somebody is dying, so "on, 0% present" is a correct answer given from
        -- the floor rather than a fault.
        local live = Omerta.HUD.VignettePresence
            and Omerta.HUD.VignettePresence() or 0
        pass(string.format("%s, %d%% at the edge, %d%% present right now",
            GetConVar("omerta_vignette"):GetBool() and "on" or "off",
            math.Round(V.EDGE * 100), math.Round(live * 100)))
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
