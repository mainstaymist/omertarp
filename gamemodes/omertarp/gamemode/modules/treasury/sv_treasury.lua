-- The treasury: a safe with money in it, and a set of books beside it.
--
-- The safe is the authority on how much money exists. Every movement is an M9
-- transactional transfer of real notes and coins, so the duplication
-- protections built there cover the treasury for free and there is no second
-- place money can be created. The ledger records what SHOULD be in there, and
-- the two are allowed to disagree — that disagreement is embezzlement, or a
-- robbery, or a Don who has been quietly skimming (D-024).

local MODULE = Omerta.Module.Get("treasury")

Omerta.Treasury = Omerta.Treasury or {}
Omerta.Treasury.Internal = Omerta.Treasury.Internal or {}
local Internal = Omerta.Treasury.Internal
local P = Omerta.Organizations.PERMISSIONS
local OWNER = Omerta.Inventory.OWNER

Omerta.Config.Define("treasury.limit_multiplier", {
    type = "number", default = 1, min = 0.1, max = 100, scope = "server",
    description = "Scales every rank's spending limit without editing the ladder.",
})
Omerta.Config.Define("treasury.safe_capacity", {
    type = "number", default = 2000, min = 100, max = 100000, scope = "server",
    description = "Bulk a treasury safe holds (money is bulky in quantity).",
})
Omerta.Config.Define("treasury.range", {
    type = "number", default = 128, min = 32, max = 512, scope = "server",
    description = "How close you must be to the safe to move money.",
})

-- organizationId -> running ledger balance in cents. Authoritative for the
-- books during a session; reconciled from the last written line at boot.
local ledgerBalance = {}
-- organizationId -> true while a movement is mid-flight, so two withdrawals
-- cannot interleave between the cash move and the ledger line.
local busy = {}
local safeEntities = {}

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

function Omerta.Treasury.Of(organizationId)
    return { type = OWNER.CONTAINER, id = Omerta.Treasury.ContainerId(organizationId) }
end

function Omerta.Treasury.Count(organizationId)
    return Omerta.Money.Count(Omerta.Treasury.Of(organizationId))
end

function Omerta.Treasury.LedgerBalance(organizationId)
    return ledgerBalance[organizationId] or 0
end

function Omerta.Treasury.History(organizationId, limit, cb)
    Internal.Repo.History(organizationId, limit, cb)
end

--------------------------------------------------------------------------------
-- Access
--------------------------------------------------------------------------------

local function membershipAt(ply)
    local character = Omerta.Characters.Get(ply)
    if not character then return nil end
    local member = Omerta.Organizations.MembershipOf(character.id)
    if not member then return nil end
    return character, member, Omerta.Organizations.GetDefinition(member.org_key)
end

-- Physical presence, re-derived server-side every time. The safe's location is
-- the whole point of §4a: procurement is a place you go.
local function atSafe(ply, organizationId)
    local ent = safeEntities[organizationId]
    if not IsValid(ent) then return false, "there is no safe to stand at" end
    if ply:GetPos():Distance(ent:GetPos()) > Omerta.Config.Get("treasury.range") then
        return false, "you are not at the safe"
    end
    return true
end

function Internal.RegisterAccess()
    Omerta.Inventory.RegisterContainerAccess("treasury", function(ply, containerId)
        local orgId = Omerta.Treasury.OrganizationOf(containerId)
        if not orgId then return true end -- not a treasury; no opinion

        local character, member = membershipAt(ply)
        if not (character and member) then return false, "that is not yours to open" end
        if member.organization_id ~= orgId then return false, "that is not yours to open" end
        if not Omerta.Organizations.Can(character.id, P.TREASURY_VIEW) then
            return false, "you are not senior enough to open it"
        end
        return true
    end)
end

--------------------------------------------------------------------------------
-- Movements
--------------------------------------------------------------------------------

local function writeLine(organizationId, opts, cb)
    local season = Omerta.Seasons.GetActive()
    if not season then cb(false, "no active season") return end

    local before = Omerta.Treasury.LedgerBalance(organizationId)
    local line = Internal.BuildLine({
        organizationId = organizationId,
        seasonId = season.id,
        at = os.time(),
        characterId = opts.characterId,
        approverId = opts.approverId,
        delta = opts.delta,
        balanceBefore = before,
        counted = Omerta.Treasury.Count(organizationId),
        reason = opts.reason,
        category = opts.category,
        note = opts.note,
    })

    Internal.Repo.Append(line, function(id, err)
        if not id then cb(false, err) return end
        ledgerBalance[organizationId] = line.balance_after
        Omerta.Log.Audit("treasury." .. opts.reason, {
            actor = opts.actorSid,
            character_id = opts.characterId,
            data = {
                organization_id = organizationId,
                delta = opts.delta,
                balance_after = line.balance_after,
                counted_after = line.counted_after,
                approver = opts.approverId,
                note = opts.note,
            },
        })
        cb(true)
    end)
end

-- cb(ok, err)
function Omerta.Treasury.Deposit(ply, organizationId, cents, reason, cb)
    cb = cb or function() end
    local character, member = membershipAt(ply)
    if not (character and member and member.organization_id == organizationId) then
        cb(false, "that is not your treasury") return
    end
    local near, why = atSafe(ply, organizationId)
    if not near then cb(false, why) return end
    if type(cents) ~= "number" or cents % 1 ~= 0 or cents <= 0 then
        cb(false, "that is not an amount") return
    end
    if busy[organizationId] then cb(false, "somebody else is at the books") return end
    busy[organizationId] = true

    -- Anybody may put money IN. Contributing to the family is not a privilege.
    Omerta.Money.Pay(ply, Omerta.Treasury.Of(organizationId), cents, function(ok, perr)
        if not ok then busy[organizationId] = nil cb(false, perr) return end
        writeLine(organizationId, {
            characterId = character.id,
            actorSid = ply:SteamID64(),
            delta = cents,
            reason = reason or Omerta.Treasury.REASONS.DEPOSIT,
        }, function(wrote, werr)
            busy[organizationId] = nil
            cb(wrote, werr)
        end)
    end)
end

-- approverPly may be nil. cb(ok, err)
function Omerta.Treasury.Withdraw(ply, organizationId, cents, reason, approverPly, cb)
    cb = cb or function() end
    local character, member, def = membershipAt(ply)
    if not (character and member and member.organization_id == organizationId) then
        cb(false, "that is not your treasury") return
    end
    local near, why = atSafe(ply, organizationId)
    if not near then cb(false, why) return end

    local multiplier = Omerta.Config.Get("treasury.limit_multiplier")
    local actorRank = Omerta.Organizations.EffectiveRank(character.id)

    -- The approver has to be a real, present, senior member who is not you.
    local approverRank, approverId = nil, nil
    if IsValid(approverPly) then
        local approverChar, approverMember = membershipAt(approverPly)
        if not (approverChar and approverMember
                and approverMember.organization_id == organizationId) then
            cb(false, "they are not one of yours") return
        end
        if approverChar.id == character.id then
            cb(false, "you cannot approve your own withdrawal") return
        end
        local approverNear = atSafe(approverPly, organizationId)
        if not approverNear then cb(false, "they are not at the safe") return end
        approverRank = Omerta.Organizations.EffectiveRank(approverChar.id)
        approverId = approverChar.id
    end

    local allowed, refusal = Omerta.Treasury.CanSpend(def.ladder, actorRank, cents,
        approverRank, multiplier)
    if not allowed then cb(false, refusal) return end

    if Omerta.Treasury.Count(organizationId) < cents then
        cb(false, "there is not that much in the safe") return
    end
    if busy[organizationId] then cb(false, "somebody else is at the books") return end
    busy[organizationId] = true

    Omerta.Money.Pay(Omerta.Treasury.Of(organizationId), ply, cents, function(ok, perr)
        if not ok then busy[organizationId] = nil cb(false, perr) return end
        writeLine(organizationId, {
            characterId = character.id,
            actorSid = ply:SteamID64(),
            approverId = approverId,
            delta = -cents,
            reason = reason or Omerta.Treasury.REASONS.WITHDRAWAL,
        }, function(wrote, werr)
            busy[organizationId] = nil
            cb(wrote, werr)
        end)
    end)
end

-- Used by procurement: money leaves the safe and does not arrive anywhere a
-- player is holding, because it went to a supplier.
function Internal.Spend(ply, organizationId, cents, category, note, cb)
    if busy[organizationId] then cb(false, "somebody else is at the books") return end
    busy[organizationId] = true

    local character = Omerta.Characters.Get(ply)
    Omerta.Money.Take(Omerta.Treasury.Of(organizationId), cents, function(ok, err)
        if not ok then busy[organizationId] = nil cb(false, err) return end
        writeLine(organizationId, {
            characterId = character.id,
            actorSid = ply:SteamID64(),
            delta = -cents,
            reason = Omerta.Treasury.REASONS.PROCUREMENT,
            category = category,
            note = note,
        }, function(wrote, werr)
            busy[organizationId] = nil
            cb(wrote, werr)
        end)
    end)
end

Internal.MembershipAt = membershipAt
Internal.AtSafe = atSafe
Internal.SafeEntities = safeEntities

--------------------------------------------------------------------------------
-- Safes
--------------------------------------------------------------------------------

function Internal.EnsureContainer(organizationId)
    local containerId = Omerta.Treasury.ContainerId(organizationId)
    Omerta.Inventory.RegisterContainer(containerId, {
        capacity = Omerta.Config.Get("treasury.safe_capacity"),
        label = "Treasury",
    })
    Omerta.Inventory.Load({ type = OWNER.CONTAINER, id = containerId })
    return containerId
end

function Internal.SpawnSafe(organizationId, pos, ang)
    if not Omerta.InEngine then return nil end
    if IsValid(safeEntities[organizationId]) then safeEntities[organizationId]:Remove() end

    local ent = ents.Create("omerta_container")
    if not IsValid(ent) then return nil end
    ent.OmertaContainer = Omerta.Treasury.ContainerId(organizationId)
    ent:SetPos(pos)
    ent:SetAngles(ang or Angle(0, 0, 0))
    ent:Spawn()
    safeEntities[organizationId] = ent
    return ent
end

function Internal.LoadSafes()
    Internal.Repo.ListSafes(game.GetMap(), function(rows, err)
        if err then
            Omerta.Log.Error("treasury", "could not load safes: %s", err)
            return
        end
        local placed = 0
        for _, row in ipairs(rows) do
            local org = Omerta.Organizations.GetById(row.organization_id)
            if org then
                Internal.EnsureContainer(row.organization_id)
                if Internal.SpawnSafe(row.organization_id,
                        Vector(row.pos_x, row.pos_y, row.pos_z)) then
                    placed = placed + 1
                end
            end
        end
        if placed > 0 then
            Omerta.Log.Info("treasury", "%d safe(s) restored to the map", placed)
        end
    end)
end

function Internal.LoadBalances()
    for _, org in ipairs(Omerta.Organizations.All()) do
        Internal.EnsureContainer(org.id)
        Internal.Repo.LastBalance(org.id, function(balance)
            ledgerBalance[org.id] = balance or 0
        end)
    end
end

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------

function Internal.SendState(ply)
    local character, member, def = membershipAt(ply)
    if not (character and member) then return end

    local mayView = Omerta.Organizations.Can(character.id, P.TREASURY_VIEW)
    local rank = Omerta.Organizations.EffectiveRank(character.id)
    local limit = Omerta.Treasury.LimitFor(def.ladder, rank,
        Omerta.Config.Get("treasury.limit_multiplier"))

    Omerta.Net.Send("treasury.state", {
        counted = mayView and math.floor(Omerta.Treasury.Count(member.organization_id)) or 0,
        ledger = mayView and math.floor(Omerta.Treasury.LedgerBalance(member.organization_id)) or 0,
        limit = math.floor(limit or 0),
        unlimited = limit == nil,
        may_view = mayView,
    }, ply)

    -- The catalogue this particular buyer may order from.
    local available = Omerta.Procurement.Available(def.type, def.ladder, rank)
    for i, entry in ipairs(available) do
        Omerta.Net.Send("procure.entry", {
            entry = entry.index,
            last = i == #available,
        }, ply)
    end
end

-- The books, for those whose rank earns them. Names are resolved from the
-- character record, not from what this reader personally knows — the ledger is
-- the institution's own record. Reading it teaches a NAME and never a face,
-- exactly as M10's roster does (D-023).
function Internal.SendHistory(ply, organizationId)
    Internal.Repo.History(organizationId, 20, function(rows, err)
        if err or #rows == 0 then return end

        local resolved, remaining = {}, 0
        local function flush()
            for i, row in ipairs(rows) do
                if IsValid(ply) then
                    Omerta.Net.Send("treasury.line", {
                        at = math.max(0, math.floor(row.at)),
                        delta = math.floor(row.delta),
                        balance = math.floor(row.balance_after),
                        who = resolved[row.character_id] or "someone",
                        approver = row.approver_character_id
                            and (resolved[row.approver_character_id] or "someone") or "",
                        reason = row.reason .. (row.note and (" — " .. row.note) or ""),
                        last = i == #rows,
                    }, ply)
                end
            end
        end

        -- Gather every name the batch mentions before sending, so the lines
        -- arrive in one burst rather than interleaved by lookup latency.
        local wanted = {}
        for _, row in ipairs(rows) do
            wanted[row.character_id] = true
            if row.approver_character_id then wanted[row.approver_character_id] = true end
        end
        for id in pairs(wanted) do remaining = remaining + 1 end
        if remaining == 0 then flush() return end

        for id in pairs(wanted) do
            Omerta.Characters.GetByID(id, function(character)
                resolved[id] = character
                    and (character.first_name .. " " .. character.last_name) or "someone"
                remaining = remaining - 1
                if remaining == 0 then flush() end
            end)
        end
    end)
end

function Internal.HandleOpen(ply)
    local character, member = membershipAt(ply)
    if not (character and member) then return end
    local near = atSafe(ply, member.organization_id)
    if not near then return end
    Internal.SendState(ply)
    if Omerta.Organizations.Can(character.id, P.TREASURY_VIEW) then
        Internal.SendHistory(ply, member.organization_id)
    end
end

function Internal.HandleAction(ply, payload)
    local character, member = membershipAt(ply)
    if not (character and member) then return end

    local function done(ok, err)
        if not ok and err then Omerta.Chat.Notice(ply, err) end
        Internal.SendState(ply)
    end

    if payload.action == 1 then
        Omerta.Treasury.Deposit(ply, member.organization_id, payload.amount, nil, done)
    elseif payload.action == 2 then
        -- An approver is whoever from the organization is standing at the safe
        -- with the authority to cover it. Found server-side: the client never
        -- nominates who signed for the money.
        local approver = nil
        if Omerta.InEngine then
            for _, other in ipairs(player.GetAll()) do
                if other ~= ply then
                    local otherChar, otherMember = membershipAt(other)
                    if otherChar and otherMember
                            and otherMember.organization_id == member.organization_id
                            and atSafe(other, member.organization_id)
                            and Omerta.Organizations.Can(otherChar.id, P.TREASURY_SPEND) then
                        approver = other
                        break
                    end
                end
            end
        end
        Omerta.Treasury.Withdraw(ply, member.organization_id, payload.amount, nil, approver, done)
    end
end

--------------------------------------------------------------------------------
-- Staff commands
--------------------------------------------------------------------------------

function Internal.RegisterCommands()
    concommand.Add("omerta_treasury_place", function(caller, _, args)
        if not IsValid(caller) then
            Omerta.Log.Error("treasury",
                "omerta_treasury_place must be run in-game — it puts the safe in front of you")
            return
        end
        if not caller:IsSuperAdmin() then return end

        local org = Omerta.Organizations.Get(args[1] or "")
        if not org then
            Omerta.Log.Error("treasury",
                "no institution '%s' this season — run omerta_org_list", tostring(args[1]))
            return
        end

        local pos = caller:GetPos() + caller:GetAimVector() * 72 + Vector(0, 0, 8)
        Internal.EnsureContainer(org.id)
        if not Internal.SpawnSafe(org.id, pos, Angle(0, caller:EyeAngles().y, 0)) then
            Omerta.Log.Error("treasury", "could not spawn the safe")
            return
        end
        Internal.Repo.SaveSafe(org.id, game.GetMap(), math.floor(pos.x), math.floor(pos.y),
            math.floor(pos.z), os.time(), function(ok, err)
            if not ok then Omerta.Log.Error("treasury", "%s", tostring(err)) return end
            Omerta.Log.Info("treasury", "%s safe placed and remembered", org.key)
            Omerta.Log.Audit("treasury.safe_placed", {
                actor = caller:SteamID64(),
                data = { organization = org.key, map = game.GetMap() },
            })
        end)
    end)

    concommand.Add("omerta_treasury_books", function(caller, _, args)
        if IsValid(caller) and not caller:IsSuperAdmin() then return end
        local org = Omerta.Organizations.Get(args[1] or "")
        if not org then
            Omerta.Log.Error("treasury", "usage: omerta_treasury_books <key>")
            return
        end
        local counted = Omerta.Treasury.Count(org.id)
        local books = Omerta.Treasury.LedgerBalance(org.id)
        Omerta.Log.Info("treasury", "%s — safe holds %s, books say %s (%s)",
            org.key, Omerta.Money.Format(counted), Omerta.Money.Format(books),
            Omerta.Treasury.DescribeDiscrepancy(counted, books))

        Internal.Repo.History(org.id, 15, function(rows)
            for i = #rows, 1, -1 do
                local row = rows[i]
                Omerta.Log.Info("treasury", "  %s %-12s by #%s%s -> %s",
                    row.delta >= 0 and "+" or "-",
                    Omerta.Money.Format(math.abs(row.delta)),
                    tostring(row.character_id),
                    row.approver_character_id
                        and (" (approved by #" .. row.approver_character_id .. ")") or "",
                    Omerta.Money.Format(row.balance_after))
            end
        end)
    end)
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------

function MODULE:OnLoad()
    Omerta.DB.DefineTable("treasury_ledger", {
        columns = {
            { name = "id",                    type = "id" },
            { name = "organization_id",       type = "ref", null = false },
            { name = "season_id",             type = "ref", null = false },
            { name = "at",                    type = "timestamp", null = false },
            { name = "character_id",          type = "ref", null = false },
            { name = "approver_character_id", type = "ref" },
            { name = "delta",                 type = "money", null = false },
            { name = "balance_after",         type = "money", null = false },
            -- What was actually in the safe at that moment, recorded beside
            -- the books so a discrepancy has a date rather than merely being
            -- noticed one day.
            { name = "counted_after",         type = "money" },
            { name = "reason",                type = "text", length = 32, null = false },
            { name = "category",              type = "text", length = 24 },
            { name = "note",                  type = "text", length = 160 },
        },
        indexes = { { "organization_id", "at" }, { "season_id" }, { "character_id" } },
    })

    Omerta.DB.DefineTable("treasury_safes", {
        columns = {
            { name = "organization_id", type = "ref", null = false },
            { name = "map_name",        type = "text", length = 64, null = false },
            { name = "pos_x",           type = "int", null = false, default = 0 },
            { name = "pos_y",           type = "int", null = false, default = 0 },
            { name = "pos_z",           type = "int", null = false, default = 0 },
            { name = "placed_at",       type = "timestamp", null = false },
        },
        primary = { "organization_id" },
    })

    Omerta.DB.AddMigration(9, "treasury ledger and safes", function(m)
        m:CreateTable("treasury_ledger")
        m:CreateTable("treasury_safes")
    end)

    Internal.RegisterAccess()
end

function MODULE:OnEnable()
    if not Omerta.InEngine then return end

    -- Organizations.WhenReady, not Seasons.WhenReady and certainly not a timer:
    -- a safe belongs to an institution, and M10's own startup is two queries
    -- deep. Waiting a fixed tick would work on a fast database and fail on a
    -- slow one, which is the worst kind of bug to own.
    Omerta.Organizations.WhenReady(function()
        Internal.LoadBalances()
        Internal.LoadSafes()
    end)

    hook.Add("Omerta.SeasonStarted", "omerta.treasury.season", function()
        ledgerBalance = {}
        Omerta.Organizations.WhenReady(Internal.LoadBalances)
    end)

    Internal.RegisterCommands()
end
