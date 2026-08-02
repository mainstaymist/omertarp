-- Premises: placed, owned, staffed, opened, and robbed later.

local MODULE = Omerta.Module.Get("business")

Omerta.Business = Omerta.Business or {}
Omerta.Business.Internal = Omerta.Business.Internal or {}
local Internal = Omerta.Business.Internal
local ROLE = Omerta.Business.ROLE
local OWNER = Omerta.Inventory.OWNER

Omerta.Config.Define("business.range", {
    type = "number", default = 110, min = 32, max = 400,
    scope = "server",
    description = "How close you must be to the counter to buy or run the place.",
})
Omerta.Config.Define("business.trickle_per_minute", {
    type = "number", default = 40, min = 0, max = 2000, scope = "server",
    description = "Cents the room itself takes per minute while open AND staffed (D-032).",
})
Omerta.Config.Define("business.rumour_price", {
    type = "number", default = 500, min = 0, max = 100000, scope = "server",
    description = "What it costs to have the barman repeat something (D-031).",
})
Omerta.Config.Define("business.rumour_hours", {
    type = "number", default = 24, min = 1, max = 336, scope = "server",
    description = "How long a rumour stays worth repeating.",
})

local businesses = {}      -- id -> row (with .counter, .stockEntity)
local byCounter = {}       -- entity index -> business
local staffRoles = {}      -- businessId -> { [characterId] = role }

Internal.Businesses = businesses

function Omerta.Business.Get(id) return businesses[id] end

function Omerta.Business.All()
    local out = {}
    for _, business in pairs(businesses) do out[#out + 1] = business end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

--------------------------------------------------------------------------------
-- Who is standing here, and what may they do
--------------------------------------------------------------------------------

function Internal.AtCounter(ply)
    if not (Omerta.InEngine and IsValid(ply)) then return nil end
    local range = Omerta.Config.Get("business.range")
    for _, business in pairs(businesses) do
        if IsValid(business.counter)
                and ply:GetPos():Distance(business.counter:GetPos()) <= range then
            return business
        end
    end
    return nil
end

function Omerta.Business.RoleFor(business, characterId)
    if not (business and characterId) then return nil end

    local membership = Omerta.Organizations.MembershipOf(characterId)
    if membership then
        -- A soldier in the family that owns a bar is not automatically behind
        -- its counter. "Handles our money" is already a rank permission, so it
        -- is the same question asked once rather than a second ladder.
        membership = {
            organization_id = membership.organization_id,
            canHandleMoney = Omerta.Organizations.Can(characterId,
                Omerta.Organizations.PERMISSIONS.TREASURY_VIEW),
        }
    end
    return Internal.RoleOf(business, characterId,
        membership, (staffRoles[business.id] or {})[characterId])
end

local function roleIndex(role)
    if role == ROLE.OWNER then return 3 end
    if role == ROLE.MANAGER then return 2 end
    if role == ROLE.STAFF then return 1 end
    return 0
end

-- Is anybody actually behind the counter? The trickle and the menu both
-- depend on it (D-032): an unstaffed business earns nothing at all.
function Internal.IsStaffed(business)
    if not Omerta.InEngine then return false end
    for _, ply in ipairs(player.GetAll()) do
        local character = Omerta.Characters.Get(ply)
        if character and Internal.AtCounter(ply) == business then
            local role = Omerta.Business.RoleFor(business, character.id)
            if Internal.MayServe(role) then return true end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Q-12 (D-030)
--------------------------------------------------------------------------------

-- The sets the pure rule needs, gathered from who is actually connected.
function Internal.OnlineSides()
    local organizations, characters = {}, {}
    if not Omerta.InEngine then return organizations, characters end
    for _, ply in ipairs(player.GetAll()) do
        local character = Omerta.Characters.Get(ply)
        if character then
            characters[character.id] = true
            local membership = Omerta.Organizations.MembershipOf(character.id)
            if membership then organizations[membership.organization_id] = true end
        end
    end
    return organizations, characters
end

-- Exposed for M14, which is where forced entry will consult it. M13 has no
-- forcing path of its own; the rule exists here because this is where premises
-- and ownership live.
function Omerta.Business.IsForceable(businessId)
    local business = businesses[businessId]
    if not business then return false end
    local organizations, characters = Internal.OnlineSides()
    return Internal.IsForceable(business, organizations, characters)
end

--------------------------------------------------------------------------------
-- Containers
--------------------------------------------------------------------------------

function Internal.EnsureContainers(business)
    local typeDef = Omerta.Business.GetType(business.type_key)
    if not typeDef then return end

    local till = Omerta.Business.TillId(business.id)
    local stock = Omerta.Business.StockId(business.id)
    Omerta.Inventory.RegisterContainer(till,
        { capacity = typeDef.tillCapacity, label = business.name .. " till" })
    Omerta.Inventory.RegisterContainer(stock,
        { capacity = typeDef.stockCapacity, label = business.name .. " stock" })
    Omerta.Inventory.Load({ type = OWNER.CONTAINER, id = till })
    Omerta.Inventory.Load({ type = OWNER.CONTAINER, id = stock })
end

function Omerta.Business.Till(businessId)
    return { type = OWNER.CONTAINER, id = Omerta.Business.TillId(businessId) }
end

function Omerta.Business.Stock(businessId)
    return { type = OWNER.CONTAINER, id = Omerta.Business.StockId(businessId) }
end

function Internal.RegisterAccess()
    Omerta.Inventory.RegisterContainerAccess("business", function(ply, containerId)
        local businessId = Omerta.Business.OfContainer(containerId)
        if not businessId then return true end -- not ours; no opinion

        local business = businesses[businessId]
        if not business then return false, "that is locked" end

        local character = Omerta.Characters.Get(ply)
        if not character then return false, "that is not yours to open" end

        local role = Omerta.Business.RoleFor(business, character.id)
        local _, kind = Omerta.Business.OfContainer(containerId)
        if kind == "till" and not Internal.MaySeeTill(role) then
            return false, "the register is not yours to open"
        end
        if not Internal.MayServe(role) then return false, "that is not yours to open" end
        return true
    end)
end

--------------------------------------------------------------------------------
-- Placement
--------------------------------------------------------------------------------

function Internal.SpawnCounter(business, pos, ang, restOnGround)
    if not Omerta.InEngine then return nil end
    if IsValid(business.counter) then
        byCounter[business.counter:EntIndex()] = nil
        business.counter:Remove()
    end

    local ent = ents.Create("omerta_business")
    if not IsValid(ent) then return nil end
    ent.OmertaBusiness = business.id
    ent:SetPos(pos)
    ent:SetAngles(ang or Angle(0, 0, 0))
    ent:Spawn()
    -- After Spawn, where networked variables are guaranteed to reach clients.
    -- The sign over the door, and nothing behind it.
    ent:SetPublicName(business.name or "")
    ent:SetTypeKey(business.type_key or "")
    if restOnGround then Omerta.Inventory.RestOnGround(ent, pos) end
    business.counter = ent
    byCounter[ent:EntIndex()] = business
    return ent
end

function Internal.SpawnStockroom(business, pos, ang, restOnGround)
    if not Omerta.InEngine then return nil end
    if IsValid(business.stockEntity) then business.stockEntity:Remove() end

    local ent = ents.Create("omerta_container")
    if not IsValid(ent) then return nil end
    ent.OmertaContainer = Omerta.Business.StockId(business.id)
    ent:SetPos(pos)
    ent:SetAngles(ang or Angle(0, 0, 0))
    ent:Spawn()
    if restOnGround then Omerta.Inventory.RestOnGround(ent, pos) end
    business.stockEntity = ent
    return ent
end

-- cb(business, err)
function Omerta.Business.Create(typeKey, name, owner, pos, opts, cb)
    cb = cb or function() end
    opts = opts or {}

    local typeDef = Omerta.Business.GetType(typeKey)
    if not typeDef then cb(nil, "there is no such kind of business") return end

    -- `opts.unowned` is M14's, and it is deliberately an EXPLICIT OPT-IN rather
    -- than a relaxation of the rule. ValidateOwner refuses "neither" because a
    -- premises with no owner has no access control, and that was right for
    -- every business M13 could place. A store that exists to be robbed is the
    -- first one that genuinely has no owner (D-048), and the honest way to say
    -- so is to say so at the call site — not to weaken the check for
    -- everything that will ever be placed after it.
    if not opts.unowned then
        local ok, why = Internal.ValidateOwner(owner.organizationId, owner.characterId)
        if not ok then cb(nil, why) return end
    elseif owner.organizationId or owner.characterId then
        cb(nil, "an unowned business cannot have an owner") return
    end

    local season = Omerta.Seasons.GetActive()
    if not season then cb(nil, "no active season") return end

    Internal.Repo.Create({
        season_id = season.id,
        type_key = typeKey,
        name = name,
        owner_organization_id = owner.organizationId or Omerta.DB.NULL,
        owner_character_id = owner.characterId or Omerta.DB.NULL,
        map_name = game.GetMap(),
        pos_x = math.floor(pos.x), pos_y = math.floor(pos.y), pos_z = math.floor(pos.z),
        is_open = false,
        created_at = os.time(),
    }, function(id, err)
        if not id then cb(nil, err) return end

        local business = {
            id = id, type_key = typeKey, name = name,
            owner_organization_id = owner.organizationId,
            owner_character_id = owner.characterId,
            map_name = game.GetMap(), is_open = false,
        }
        businesses[id] = business
        Internal.EnsureContainers(business)
        Internal.SpawnCounter(business, pos, opts.angle, opts.restOnGround)

        Omerta.Log.Audit("business.created", {
            actor = opts.actor or "staff",
            data = { business = id, type = typeKey, name = name,
                     organization = owner.organizationId, character = owner.characterId },
        })
        cb(business)
    end)
end

function Internal.LoadBusinesses()
    local season = Omerta.Seasons.GetActive()
    if not season then return end

    Internal.Repo.ListForSeason(season.id, function(rows, err)
        if err then
            Omerta.Log.Error("business", "could not load premises: %s", err)
            return
        end
        local placed = 0
        for _, row in ipairs(rows) do
            businesses[row.id] = row
            Internal.EnsureContainers(row)
            if row.map_name == game.GetMap() and row.pos_x then
                if Internal.SpawnCounter(row, Vector(row.pos_x, row.pos_y, row.pos_z)) then
                    placed = placed + 1
                end
            end
            Internal.Repo.ListStaff(row.id, function(staff)
                local map = {}
                for _, entry in ipairs(staff) do map[entry.character_id] = entry.role end
                staffRoles[row.id] = map
            end)
        end
        if #rows > 0 then
            Omerta.Log.Info("business", "%d premises this season, %d on this map", #rows, placed)
        end
    end)
end

--------------------------------------------------------------------------------
-- Running the place
--------------------------------------------------------------------------------

function Omerta.Business.SetOpen(ply, business, isOpen, cb)
    cb = cb or function() end
    local character = Omerta.Characters.Get(ply)
    if not character then cb(false, "no character") return end

    local role = Omerta.Business.RoleFor(business, character.id)
    if not Internal.MayServe(role) then cb(false, "that is not yours to open") return end

    Internal.Repo.SetOpen(business.id, isOpen, function(ok, err)
        if not ok then cb(false, err) return end
        business.is_open = isOpen
        Omerta.Log.Audit("business." .. (isOpen and "opened" or "closed"), {
            actor = ply:SteamID64(), character_id = character.id,
            data = { business = business.id },
        })
        cb(true)
    end)
end

function Omerta.Business.Hire(actorPly, business, targetPly, cb)
    cb = cb or function() end
    local actor = Omerta.Characters.Get(actorPly)
    local target = Omerta.Characters.Get(targetPly)
    if not (actor and target) then cb(false, "both of you need a character") return end
    if actor.id == target.id then cb(false, "you already work here") return end

    if not Internal.MayHire(Omerta.Business.RoleFor(business, actor.id)) then
        cb(false, "that is not yours to offer") return
    end

    Internal.Repo.Hire(business.id, target.id, ROLE.STAFF, os.time(), function(ok, err)
        if not ok then cb(false, err) return end
        staffRoles[business.id] = staffRoles[business.id] or {}
        staffRoles[business.id][target.id] = ROLE.STAFF
        -- A staff role is not an organization rank and grants nothing outside
        -- these walls; conflating them would let hiring become promotion.
        Omerta.Log.Audit("business.hired", {
            actor = actorPly:SteamID64(), character_id = target.id,
            data = { business = business.id, role = ROLE.STAFF },
        })
        Omerta.Chat.Notice(targetPly, "You are on the books at " .. business.name .. ".")
        cb(true)
    end)
end

-- The most robbable moment in the economy: cash out of the till, into a
-- treasury or a pocket, carried by a person (D-032).
function Omerta.Business.CollectTill(ply, business, cb)
    cb = cb or function() end
    local character = Omerta.Characters.Get(ply)
    if not character then cb(false, "no character") return end
    if not Internal.MaySeeTill(Omerta.Business.RoleFor(business, character.id)) then
        cb(false, "the register is not yours to empty") return
    end

    local till = Omerta.Business.Till(business.id)
    local amount = Omerta.Money.Count(till)
    if amount <= 0 then cb(false, "the register is empty") return end

    Omerta.Business.EmptyTill(business.id, ply, amount, function(ok, err)
        if not ok then cb(false, err) return end
        Omerta.Log.Audit("business.collected", {
            actor = ply:SteamID64(), character_id = character.id,
            data = { business = business.id, cents = amount },
        })
        Omerta.Chat.Notice(ply, "You take " .. Omerta.Money.Format(amount) ..
            " out of the register.")
        cb(true, nil, amount)
    end)
end

-- THE UNAUTHORISED HALF, and the one function M14 needed M13 to gain.
--
-- CollectTill above is now a role-checked caller of this; a robbery is an
-- unchecked one. That split is M20's RecordDeath shape exactly, and it is the
-- third time that shape has been the right answer: the same transactional path,
-- a different reason for being allowed to walk it.
--
-- The alternative was to make M9's MayOpen grant access to a robber, and MayOpen
-- is refusal-only by design — a registered predicate can veto and none can
-- grant. Forcing a grant through it would mean teaching M9's access model about
-- crime.
--
-- No mint: this moves money that was already in the register, through the same
-- function a sale uses, so M9's duplication protections cover it unchanged.
-- cb(ok, err)
function Omerta.Business.EmptyTill(businessId, toOwner, cents, cb)
    cb = cb or function() end
    local business = Omerta.Business.Get(businessId)
    if not business then cb(false, "there is nothing here") return end

    cents = Omerta.Money.Round(cents or 0)
    if cents <= 0 then cb(false, "there is nothing in it") return end

    Omerta.Money.Pay(Omerta.Business.Till(businessId), toOwner, cents, cb)
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------

function Internal.SendState(ply, business)
    if not (Omerta.InEngine and IsValid(ply)) then return end
    local character = Omerta.Characters.Get(ply)
    if not character then return end

    local role = Omerta.Business.RoleFor(business, character.id)
    local maySeeTill = Internal.MaySeeTill(role)

    Omerta.Net.Send("business.state", {
        business = business.id,
        name = business.name,
        role = roleIndex(role),
        is_open = business.is_open == true,
        -- A customer is never told the takings.
        till = maySeeTill and math.floor(Omerta.Money.Count(Omerta.Business.Till(business.id))) or 0,
        staffed = Internal.IsStaffed(business),
    }, ply)

    Internal.SendMenu(ply, business)
end

-- THE COUNTER NEEDED AN INTERACTION, NOT JUST AN ENT:Use.
--
-- M13 built the counter on the engine's +use and M8 later registered
-- `omerta_business` as an interactable class. Those two are incompatible and
-- nobody noticed until M14 put a second thing in the same room: registering the
-- class makes the client SWALLOW the E press and route it to
-- interaction.default, so ENT:Use stopped being reached at all and pressing E
-- on a counter did nothing whatsoever.
--
-- The fix is the architecture the project already settled on — every player
-- action is an M5 interaction — rather than un-registering the class, which
-- would take the dot off the one object in the room you are meant to walk to.
-- ENT:Use stays as the fallback for anyone who reaches it another way; both
-- paths land on HandleOpen, so there is no second set of checks to drift.
function Internal.RegisterInteractions()
    Omerta.Interaction.Register("business.open", {
        label = "Talk to the counter",
        range = Omerta.Config.Get("business.range"),
        order = 30,
        default = true,
        describe = function(ply, target)
            local business = byCounter[target:EntIndex()]
            if not business then return nil end
            return business.is_open and "Buy something" or "Look at the counter"
        end,
        predicate = function(ply, target)
            return byCounter[target:EntIndex()] ~= nil
        end,
        run = function(ply, target)
            Internal.HandleOpen(ply, target:EntIndex())
        end,
    })
end

function Internal.HandleOpen(ply, entIndex)
    local business = byCounter[entIndex]
    if not business then return end
    if Internal.AtCounter(ply) ~= business then return end
    Internal.SendState(ply, business)
end

function Internal.HandleAction(ply, action, target)
    local business = Internal.AtCounter(ply)
    if not business then return end
    local A = Omerta.Business.ACTION

    local function done(ok, err)
        if not ok and err then Omerta.Chat.Notice(ply, err) end
        Internal.SendState(ply, business)
    end

    if action == A.TOGGLE then
        Omerta.Business.SetOpen(ply, business, not business.is_open, done)
    elseif action == A.COLLECT then
        Omerta.Business.CollectTill(ply, business, done)
    elseif action == A.LISTEN then
        Internal.ServeRumour(ply, business)
    elseif action == A.HIRE then
        local other = Entity(target)
        if IsValid(other) and other:IsPlayer() then
            Omerta.Business.Hire(ply, business, other, done)
        end
    end
end

--------------------------------------------------------------------------------
-- The trickle (D-032)
--------------------------------------------------------------------------------
-- Small enough that it never beats a real customer. It exists so that standing
-- behind a bar is worth doing, which is the role GDD §4.3 promises independents
-- and never explains how to fill.

function Internal.Trickle()
    local perMinute = Omerta.Config.Get("business.trickle_per_minute")
    if perMinute <= 0 then return end
    local amount = Omerta.Money.Round(perMinute)
    if amount <= 0 then return end

    for _, business in pairs(businesses) do
        if business.is_open and Internal.IsStaffed(business) then
            local till = Omerta.Business.Till(business.id)
            if Omerta.Money.HasRoomFor(till, amount) then
                Omerta.Money.Give(till, amount)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Staff commands
--------------------------------------------------------------------------------

function Internal.RegisterCommands()
    concommand.Add("omerta_business_place", function(caller, _, args)
        if not IsValid(caller) then
            Omerta.Log.Error("business",
                "omerta_business_place must be run in-game — it puts the counter in front of you")
            return
        end
        if not caller:IsSuperAdmin() then return end

        local typeKey, ownerArg = args[1], args[2]
        local name = table.concat(args, " ", 3)
        if not (typeKey and ownerArg and name ~= "") then
            Omerta.Log.Error("business",
                "usage: omerta_business_place <type> <orgKey|me|nobody> <name>")
            return
        end
        if not Omerta.Business.GetType(typeKey) then
            Omerta.Log.Error("business", "no such type '%s'", typeKey)
            return
        end

        local owner = {}
        local unowned = ownerArg == "nobody"
        if unowned then
            -- M14's store. An unowned premises has no access control and no
            -- D-030 protection, which is exactly what makes it worth walking
            -- into with a gun.
            owner = {}
        elseif ownerArg == "me" then
            local character = Omerta.Characters.Get(caller)
            if not character then Omerta.Log.Error("business", "you have no character") return end
            owner.characterId = character.id
        else
            local org = Omerta.Organizations.Get(ownerArg)
            if not org then
                Omerta.Log.Error("business", "no institution '%s' — run omerta_org_list", ownerArg)
                return
            end
            owner.organizationId = org.id
        end

        local pos = Omerta.Inventory.PlacementInFront(caller, 110)
        Omerta.Business.Create(typeKey, name, owner, pos, {
            angle = Angle(0, caller:EyeAngles().y, 0),
            restOnGround = true,
            actor = caller:SteamID64(),
            unowned = unowned,
        }, function(business, err)
            if not business then Omerta.Log.Error("business", "%s", tostring(err)) return end
            Omerta.Log.Info("business", "#%d %s (%s) placed — now put the stock room down " ..
                "with omerta_business_stockroom %d", business.id, business.name,
                typeKey, business.id)
        end)
    end)

    concommand.Add("omerta_business_stockroom", function(caller, _, args)
        if not IsValid(caller) or not caller:IsSuperAdmin() then return end
        local business = businesses[tonumber(args[1] or "") or -1]
        if not business then
            Omerta.Log.Error("business", "usage: omerta_business_stockroom <id>")
            return
        end
        local pos = Omerta.Inventory.PlacementInFront(caller, 96)
        if Internal.SpawnStockroom(business, pos, Angle(0, caller:EyeAngles().y, 0), true) then
            Omerta.Log.Info("business", "stock room placed for %s", business.name)
        end
    end)

    concommand.Add("omerta_business_list", function(caller)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        local all = Omerta.Business.All()
        if #all == 0 then Omerta.Log.Info("business", "no premises") return end
        for _, business in ipairs(all) do
            local owner = business.owner_organization_id
                and ("org #" .. business.owner_organization_id)
                or ("character #" .. tostring(business.owner_character_id))
            Omerta.Log.Info("business", "  #%d %-22s %-12s %s  till %s%s",
                business.id, business.name, business.type_key, owner,
                Omerta.Money.Format(Omerta.Money.Count(Omerta.Business.Till(business.id))),
                business.is_open and "  (open)" or "")
        end
    end)
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function MODULE:OnLoad()
    Omerta.DB.DefineTable("businesses", {
        columns = {
            { name = "id",                    type = "id" },
            { name = "season_id",             type = "ref", null = false },
            { name = "type_key",              type = "text", length = 32, null = false },
            { name = "name",                  type = "text", length = 64, null = false },
            -- Exactly one of these is set. The code refuses both and refuses
            -- neither; "who owns this" having two answers is how access
            -- control quietly stops working.
            { name = "owner_organization_id", type = "ref" },
            { name = "owner_character_id",    type = "ref" },
            { name = "map_name",              type = "text", length = 64, null = false },
            { name = "pos_x",                 type = "int" },
            { name = "pos_y",                 type = "int" },
            { name = "pos_z",                 type = "int" },
            { name = "is_open",               type = "bool", null = false, default = false },
            { name = "created_at",            type = "timestamp", null = false },
        },
        indexes = { { "season_id" }, { "owner_organization_id" } },
    })

    Omerta.DB.DefineTable("business_staff", {
        columns = {
            { name = "business_id",  type = "ref", null = false },
            { name = "character_id", type = "ref", null = false },
            { name = "role",         type = "text", length = 16, null = false },
            { name = "hired_at",     type = "timestamp", null = false },
        },
        primary = { "business_id", "character_id" },
        indexes = { { "character_id" } },
    })

    Omerta.DB.DefineTable("rumours", {
        columns = {
            { name = "id",                      type = "id" },
            { name = "season_id",               type = "ref", null = false },
            { name = "text",                    type = "text", length = 240, null = false },
            { name = "source",                  type = "text", length = 16, null = false },
            { name = "planted_by_character_id", type = "ref" },
            { name = "business_id",             type = "ref" },
            { name = "created_at",              type = "timestamp", null = false },
            { name = "expires_at",              type = "timestamp", null = false },
        },
        indexes = { { "season_id", "expires_at" } },
    })

    Omerta.DB.AddMigration(11, "businesses, staff and rumours", function(m)
        m:CreateTable("businesses")
        m:CreateTable("business_staff")
        m:CreateTable("rumours")
    end)

    Internal.RegisterAccess()
end

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    Omerta.Organizations.WhenReady(function()
        Internal.LoadBusinesses()
        Internal.LoadRumours()
    end)

    timer.Create("omerta.business.trickle", 60, 0, Internal.Trickle)
    timer.Create("omerta.business.rumour_sweep", 600, 0, function()
        Internal.Repo.SweepRumours(os.time())
    end)

    Internal.RegisterCommands()
    Internal.RegisterInteractions()
end
