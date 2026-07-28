-- Lines as things that exist in the world: created, numbered, placed, and
-- still there after a restart.

local MODULE = Omerta.Module.Get("phone")

Omerta.Phone = Omerta.Phone or {}
Omerta.Phone.Internal = Omerta.Phone.Internal or {}
local Internal = Omerta.Phone.Internal

--------------------------------------------------------------------------------
-- Handsets
--------------------------------------------------------------------------------

function Internal.SpawnHandset(line, pos, ang, restOnGround)
    if not Omerta.InEngine then return nil end
    if IsValid(line.entity) then line.entity:Remove() end

    local ent = ents.Create("omerta_phone")
    if not IsValid(ent) then return nil end
    ent.OmertaLine = line.id
    ent:SetPos(pos)
    ent:SetAngles(ang or Angle(0, 0, 0))
    ent:Spawn()
    if restOnGround then Omerta.Inventory.RestOnGround(ent, pos) end
    line.entity = ent
    return ent
end

-- cb(line, err)
function Omerta.Phone.Install(kind, number, mapName, pos, opts, cb)
    cb = cb or function() end
    opts = opts or {}

    local season = Omerta.Seasons.GetActive()
    if not season then cb(nil, "no active season") return end

    number = number or Internal.AllocateNumber(Internal.TakenNumbers())
    if not (number and Omerta.Phone.ValidNumber(number)) then
        cb(nil, "no free numbers") return
    end
    if Omerta.Phone.Find(number) then cb(nil, "that number is taken") return end

    Internal.Repo.CreateLine({
        season_id = season.id,
        number = number,
        kind = kind,
        organization_id = opts.organizationId or Omerta.DB.NULL,
        map_name = mapName,
        pos_x = math.floor(pos.x), pos_y = math.floor(pos.y), pos_z = math.floor(pos.z),
        label = opts.label or Omerta.DB.NULL,
        created_at = os.time(),
    }, function(id, err)
        if not id then cb(nil, err) return end
        local line = Internal.RegisterLine({
            id = id, number = number, kind = kind,
            organizationId = opts.organizationId,
            label = opts.label, mapName = mapName,
        })
        Internal.SpawnHandset(line, pos, opts.angle, opts.restOnGround)
        Omerta.Log.Audit("phone.installed", {
            actor = opts.actor or "staff",
            data = { number = number, kind = kind, organization = opts.organizationId },
        })
        cb(line)
    end)
end

function Internal.LoadLines()
    local season = Omerta.Seasons.GetActive()
    if not season then return end

    Internal.Repo.ListLines(season.id, function(rows, err)
        if err then
            Omerta.Log.Error("phone", "could not load lines: %s", err)
            return
        end
        local placed = 0
        for _, row in ipairs(rows) do
            local line = Internal.RegisterLine({
                id = row.id, number = row.number, kind = row.kind,
                organizationId = row.organization_id, label = row.label,
                mapName = row.map_name,
            })
            -- A line installed on another map still exists as a number; it
            -- simply has no handset to stand at here.
            if row.map_name == game.GetMap() and row.pos_x then
                if Internal.SpawnHandset(line, Vector(row.pos_x, row.pos_y, row.pos_z)) then
                    placed = placed + 1
                end
            end
        end
        if #rows > 0 then
            Omerta.Log.Info("phone", "%d line(s) this season, %d handset(s) on this map",
                #rows, placed)
        end
    end)
end

--------------------------------------------------------------------------------
-- Staff commands
--------------------------------------------------------------------------------

function Internal.RegisterCommands()
    concommand.Add("omerta_phone_place", function(caller, _, args)
        if not IsValid(caller) then
            Omerta.Log.Error("phone",
                "omerta_phone_place must be run in-game — it puts the handset in front of you")
            return
        end
        if not caller:IsSuperAdmin() then return end

        local kind = args[1] or Omerta.Phone.KIND.PAYPHONE
        if kind ~= Omerta.Phone.KIND.PAYPHONE and kind ~= Omerta.Phone.KIND.PRIVATE then
            Omerta.Log.Error("phone", "usage: omerta_phone_place <payphone|private> [number]")
            return
        end
        local number = args[2]
        if number and not Omerta.Phone.ValidNumber(number) then
            Omerta.Log.Error("phone", "a number is four digits, %d to %d",
                Omerta.Phone.NUMBER_MIN, Omerta.Phone.NUMBER_MAX)
            return
        end

        local pos = Omerta.Inventory.PlacementInFront(caller, 110)
        Omerta.Phone.Install(kind, number, game.GetMap(), pos, {
            angle = Angle(0, caller:EyeAngles().y, 0),
            restOnGround = true,
            actor = caller:SteamID64(),
        }, function(line, err)
            if not line then Omerta.Log.Error("phone", "%s", tostring(err)) return end
            Omerta.Log.Info("phone", "%s installed — the number is %s", kind, line.number)
        end)
    end)

    concommand.Add("omerta_phone_list", function(caller)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        local count = 0
        for _, line in pairs(Internal.Lines) do
            count = count + 1
            Omerta.Log.Info("phone", "  %s  %-9s %s%s", line.number, line.kind,
                line.label or "", IsValid(line.entity) and "" or "  (no handset here)")
        end
        if count == 0 then Omerta.Log.Info("phone", "no lines installed") end
    end)

    -- §4c, D-029: nobody reads records in-game. Staff can, because staff can
    -- read everything; the authority a detective needs is M18's to design.
    concommand.Add("omerta_phone_records", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        local line = Omerta.Phone.Find(args[1] or "")
        if not line then
            Omerta.Log.Error("phone", "usage: omerta_phone_records <number>")
            return
        end
        Internal.Repo.CallsFor(line.id, 20, function(rows)
            Omerta.Log.Info("phone", "%s — %d record(s)", line.number, #rows)
            for i = #rows, 1, -1 do
                local row = rows[i]
                local from = Omerta.Phone.LineById(row.from_line)
                local to = Omerta.Phone.LineById(row.to_line)
                Omerta.Log.Info("phone", "  %s -> %s  %ds  %s",
                    from and from.number or "?", to and to.number or "?",
                    row.seconds, row.outcome)
            end
        end)
    end)
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function MODULE:OnLoad()
    Omerta.DB.DefineTable("phone_lines", {
        columns = {
            { name = "id",              type = "id" },
            { name = "season_id",       type = "ref", null = false },
            { name = "number",          type = "text", length = 12, null = false },
            { name = "kind",            type = "text", length = 12, null = false },
            { name = "organization_id", type = "ref" },
            { name = "map_name",        type = "text", length = 64, null = false },
            { name = "pos_x",           type = "int" },
            { name = "pos_y",           type = "int" },
            { name = "pos_z",           type = "int" },
            { name = "label",           type = "text", length = 64 },
            { name = "created_at",      type = "timestamp", null = false },
        },
        unique = { { "season_id", "number" } },
        indexes = { { "season_id" } },
    })

    -- NOTE: there is no content column, and there must never be one. A table
    -- with nowhere to put a recording is a stronger guarantee than a rule
    -- somebody has to remember not to break.
    Omerta.DB.DefineTable("phone_calls", {
        columns = {
            { name = "id",                type = "id" },
            { name = "season_id",         type = "ref", null = false },
            { name = "from_line",         type = "ref", null = false },
            { name = "to_line",           type = "ref", null = false },
            { name = "from_character_id", type = "ref" },
            { name = "to_character_id",   type = "ref" },
            { name = "started_at",        type = "timestamp", null = false },
            { name = "ended_at",          type = "timestamp" },
            { name = "seconds",           type = "int", null = false, default = 0 },
            { name = "coins_spent",       type = "money", null = false, default = 0 },
            { name = "outcome",           type = "text", length = 16, null = false },
        },
        indexes = { { "from_line", "started_at" }, { "to_line", "started_at" }, { "season_id" } },
    })

    Omerta.DB.AddMigration(10, "telephone lines and call records", function(m)
        m:CreateTable("phone_lines")
        m:CreateTable("phone_calls")
    end)

    -- A private line is bought, and it is installed where the family already
    -- keeps its money — the safe is the premises (M11's seam, used as intended).
    Omerta.Procurement.Register("supply.private_line", {
        name = "Private Telephone Line", category = "communications",
        price = 25000, order = 10,
        onPurchase = function(organizationId, ply)
            local safe = Omerta.Treasury.Internal.SafeEntities[organizationId]
            if not IsValid(safe) then
                Omerta.Chat.Notice(ply, "There is nowhere to install it — place the safe first.")
                return
            end
            local pos = safe:GetPos() + safe:GetForward() * 40 + Vector(0, 0, 8)
            local org = Omerta.Organizations.GetById(organizationId)
            Omerta.Phone.Install(Omerta.Phone.KIND.PRIVATE, nil, game.GetMap(), pos, {
                organizationId = organizationId,
                label = org and org.key or nil,
                actor = ply:SteamID64(),
            }, function(line, err)
                if not line then
                    Omerta.Chat.Notice(ply, "The installation failed: " .. tostring(err))
                    return
                end
                Omerta.Chat.Notice(ply, "The line is in. The number is " .. line.number .. ".")
            end)
        end,
    })
end

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    Internal.RegisterVoice()

    Omerta.Organizations.WhenReady(function()
        Internal.LoadLines()
    end)

    local interval = 1
    timer.Create("omerta.phone.tick", interval, 0, function() Internal.Tick(interval) end)

    hook.Add("PlayerDisconnected", "omerta.phone.drop", function(ply)
        Internal.DropPlayer(ply)
    end)

    Internal.RegisterCommands()
end
