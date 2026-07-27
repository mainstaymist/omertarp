-- Accounts repository: the ONLY file that writes SQL about accounts.
-- Gameplay never calls this directly — it calls Omerta.Accounts (sv_accounts),
-- which calls here. This is the repository pattern every later data-owning
-- milestone copies (M1 review §9, M2 review §12).
--
-- Everything is async through Omerta.DB; callbacks receive (result, err).

Omerta.Accounts = Omerta.Accounts or {}
Omerta.Accounts.Internal = Omerta.Accounts.Internal or {}
local Internal = Omerta.Accounts.Internal
Internal.Repo = Internal.Repo or {}
local Repo = Internal.Repo

-- Assembles the in-memory account shape from its three tables.
local function loadFlagsAndStats(account, cb)
    Omerta.DB.Query("SELECT flag, set_at, set_by, reason FROM {account_flags} WHERE account_id = ?",
        { account.id }, function(flagRows, err)
        if err then cb(nil, err) return end
        account.flags = {}
        for _, r in ipairs(flagRows) do
            account.flags[r.flag] = { set_at = r.set_at, set_by = r.set_by, reason = r.reason }
        end
        Omerta.DB.Query("SELECT stat, value FROM {account_stats} WHERE account_id = ?",
            { account.id }, function(statRows, serr)
            if serr then cb(nil, serr) return end
            account.stats = {}
            for _, r in ipairs(statRows) do
                account.stats[r.stat] = r.value
            end
            cb(account, nil)
        end)
    end)
end

-- cb(account, err, created). Bumps last_seen/connections on the load path;
-- creates with connections = 1 on the create path.
function Repo.LoadOrCreate(sid64, now, cb)
    Omerta.DB.QueryOne("SELECT * FROM {accounts} WHERE steamid64 = ?", { sid64 },
        function(row, err)
        if err then cb(nil, err) return end

        if row then
            Omerta.DB.Query(
                "UPDATE {accounts} SET last_seen = ?, connections = connections + 1 WHERE id = ?",
                { now, row.id }, function(_, uerr)
                if uerr then cb(nil, uerr) return end
                row.last_seen = now
                row.connections = row.connections + 1
                loadFlagsAndStats(row, function(account, ferr)
                    cb(account, ferr, false)
                end)
            end)
            return
        end

        Omerta.DB.Insert("accounts", {
            steamid64 = sid64,
            first_seen = now,
            last_seen = now,
            playtime = 0,
            connections = 1,
        }, function(id, ierr)
            if ierr then cb(nil, ierr) return end
            cb({
                id = id, steamid64 = sid64,
                first_seen = now, last_seen = now,
                playtime = 0, connections = 1,
                flags = {}, stats = {},
            }, nil, true)
        end)
    end)
end

-- cb(account, err) — read-only lookup, no bumps, no caching. account is nil
-- when the SteamID64 has never connected.
function Repo.FetchBySteamID64(sid64, cb)
    Omerta.DB.QueryOne("SELECT * FROM {accounts} WHERE steamid64 = ?", { sid64 },
        function(row, err)
        if err then cb(nil, err) return end
        if not row then cb(nil, nil) return end
        loadFlagsAndStats(row, cb)
    end)
end

function Repo.AddPlaytime(accountId, seconds, now, cb)
    Omerta.DB.Query(
        "UPDATE {accounts} SET playtime = playtime + ?, last_seen = ? WHERE id = ?",
        { seconds, now, accountId }, function(_, err) if cb then cb(err == nil, err) end end)
end

function Repo.SetFlag(accountId, flag, reason, bySid64, now, cb)
    Omerta.DB.Upsert("account_flags", {
        account_id = accountId,
        flag = flag,
        set_at = now,
        set_by = bySid64 or Omerta.DB.NULL,
        reason = reason or Omerta.DB.NULL,
    }, { "account_id", "flag" }, cb)
end

function Repo.ClearFlag(accountId, flag, cb)
    Omerta.DB.Query("DELETE FROM {account_flags} WHERE account_id = ? AND flag = ?",
        { accountId, flag }, function(_, err) if cb then cb(err == nil, err) end end)
end

function Repo.IncrementStat(accountId, stat, delta, cb)
    Omerta.DB.UpsertIncrement("account_stats",
        { account_id = accountId, stat = stat }, "value", delta, cb)
end

function Repo.InsertAudit(row, cb)
    Omerta.DB.Insert("audit", row, cb)
end

function Repo.SweepAudit(cutoff, cb)
    Omerta.DB.Query("DELETE FROM {audit} WHERE at < ?", { cutoff },
        function(_, err) if cb then cb(err == nil, err) end end)
end

-- Self-test cleanup only: removes one account's rows across all four tables.
function Repo.DeleteAccountData(accountId, sid64, cb)
    Omerta.DB.Transaction(function(tx)
        tx:Query("DELETE FROM {account_flags} WHERE account_id = ?", { accountId })
        tx:Query("DELETE FROM {account_stats} WHERE account_id = ?", { accountId })
        tx:Query("DELETE FROM {accounts} WHERE id = ?", { accountId })
        tx:Query("DELETE FROM {audit} WHERE actor = ?", { sid64 })
    end, cb)
end
