-- The books: spending authority, and the arithmetic of an append-only ledger.
--
-- Everything here is pure. Who may spend how much, who has to agree, and what
-- a ledger line says are the questions an institution's money will be argued
-- over for years, so they live apart from the database and are covered by the
-- headless suite.
--
-- Amounts are always integer cents (D-018).

Omerta.Treasury = Omerta.Treasury or {}
Omerta.Treasury.Internal = Omerta.Treasury.Internal or {}

Omerta.Treasury.REASONS = {
    DEPOSIT     = "deposit",
    WITHDRAWAL  = "withdrawal",
    PROCUREMENT = "procurement",
    CORRECTION  = "correction",
}

--------------------------------------------------------------------------------
-- Spending authority (M11 §4c, D-025)
--------------------------------------------------------------------------------

-- What one rung may spend alone, in cents.
--   0   — this rank cannot spend at all
--   nil — no ceiling
--
-- The limit is whatever the rung AT THIS RANK declares; it is not inherited the
-- way permissions are. That is deliberate: a Don declaring no limit means "no
-- ceiling", and inheriting the Underboss's ceiling upward would mean the head
-- of the family could spend less than the books allow him to authorise.
function Omerta.Treasury.LimitFor(ladderId, rank, multiplier)
    if not Omerta.Organizations.Grants(ladderId, rank,
            Omerta.Organizations.PERMISSIONS.TREASURY_SPEND) then
        return 0
    end
    local rung = Omerta.Organizations.RankAt(ladderId, rank)
    if not rung or rung.spendLimit == nil then return nil end
    return math.floor(rung.spendLimit * (multiplier or 1))
end

-- Can this actor move this much, and if not, is there an approver who covers it?
-- approverRank may be nil (nobody offering to sign).
-- Returns true, or false + reason.
--
-- Callers must separately refuse an approver who IS the actor; that is an
-- identity question, not a rank one, and keeping it out of here leaves this
-- function about ranks alone.
function Omerta.Treasury.CanSpend(ladderId, actorRank, amount, approverRank, multiplier)
    if type(amount) ~= "number" or amount % 1 ~= 0 or amount <= 0 then
        return false, "that is not an amount"
    end

    local limit = Omerta.Treasury.LimitFor(ladderId, actorRank, multiplier)
    if limit == 0 then return false, "you cannot take money out of the treasury" end
    if limit == nil or amount <= limit then return true end

    if approverRank == nil then
        return false, string.format("that is above what you may take alone (%s) — " ..
            "somebody senior has to approve it", Omerta.Money.Format(limit))
    end

    local approverLimit = Omerta.Treasury.LimitFor(ladderId, approverRank, multiplier)
    if approverLimit == 0 then return false, "they cannot approve a withdrawal" end
    if approverLimit ~= nil and amount > approverLimit then
        return false, "they cannot approve that much either"
    end
    return true
end

--------------------------------------------------------------------------------
-- Ledger lines (pure)
--------------------------------------------------------------------------------

-- Builds the row for one movement. `counted` is what was actually in the safe
-- afterwards — recorded beside the books at every movement, so a discrepancy
-- has a date rather than merely being noticed one day (D-024).
function Omerta.Treasury.Internal.BuildLine(opts)
    return {
        organization_id       = opts.organizationId,
        season_id             = opts.seasonId,
        at                    = opts.at,
        character_id          = opts.characterId,
        approver_character_id = opts.approverId or Omerta.DB.NULL,
        delta                 = opts.delta,
        balance_after         = opts.balanceBefore + opts.delta,
        counted_after         = opts.counted or Omerta.DB.NULL,
        reason                = opts.reason,
        category              = opts.category or Omerta.DB.NULL,
        note                  = opts.note or Omerta.DB.NULL,
    }
end

-- The books and the safe, side by side. A positive discrepancy means there is
-- more cash present than the books account for; a negative one means somebody
-- has taken money without writing it down.
function Omerta.Treasury.Discrepancy(counted, ledgerBalance)
    return (counted or 0) - (ledgerBalance or 0)
end

function Omerta.Treasury.DescribeDiscrepancy(counted, ledgerBalance)
    local gap = Omerta.Treasury.Discrepancy(counted, ledgerBalance)
    if gap == 0 then return "the books balance" end
    if gap > 0 then return Omerta.Money.Format(gap) .. " more than the books say" end
    return Omerta.Money.Format(-gap) .. " missing"
end
