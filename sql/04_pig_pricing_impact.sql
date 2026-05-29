-- ============================================================
-- ClaimsIQ — Personal Injuries Guidelines Impact Analysis
-- Introduced April 2021 — most significant reform in Irish insurance history
-- ============================================================

-- ── 1. BEFORE vs AFTER GUIDELINES — INJURY CLAIM COST IMPACT ─────────────────
WITH pre_pig AS (
    SELECT AVG(avg_injury_claim_cost_eur)   AS avg_cost_pre,
           AVG(injury_claim_freq_per_100)   AS avg_freq_pre
    FROM market_overview
    WHERE year BETWEEN 2018 AND 2020  -- 3-year pre-PIG baseline
),
post_pig AS (
    SELECT year,
           avg_injury_claim_cost_eur        AS cost_post,
           injury_claim_freq_per_100        AS freq_post
    FROM market_overview
    WHERE year >= 2021
)
SELECT p.year,
    pp.avg_cost_pre                         AS baseline_cost_pre_pig,
    p.cost_post                             AS actual_cost_post_pig,
    ROUND((p.cost_post - pp.avg_cost_pre) /
          pp.avg_cost_pre * 100, 1)         AS cost_change_pct,
    ROUND(pp.avg_cost_pre - p.cost_post, 0) AS saving_per_claim,
    pp.avg_freq_pre                         AS baseline_freq_pre_pig,
    p.freq_post                             AS actual_freq_post_pig
FROM post_pig p
CROSS JOIN pre_pig pp
ORDER BY p.year;


-- ── 2. TOTAL MARKET SAVING FROM GUIDELINES ───────────────────────────────────
WITH pre_pig_cost AS (
    SELECT AVG(avg_injury_claim_cost_eur) AS baseline
    FROM market_overview WHERE year BETWEEN 2018 AND 2020
)
SELECT m.year,
    m.avg_injury_claim_cost_eur             AS actual_cost,
    pc.baseline                             AS pre_pig_baseline,
    GREATEST(0, ROUND(pc.baseline - m.avg_injury_claim_cost_eur, 0))
                                            AS saving_per_claim,
    m.injury_claims,
    ROUND(GREATEST(0, pc.baseline - m.avg_injury_claim_cost_eur) *
          m.injury_claims / 1000000, 1)     AS total_saving_eur_m,
    SUM(ROUND(GREATEST(0, pc.baseline - m.avg_injury_claim_cost_eur) *
              m.injury_claims / 1000000, 1))
        OVER (ORDER BY m.year
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                                            AS cumulative_saving_eur_m
FROM market_overview m
CROSS JOIN pre_pig_cost pc
WHERE m.year >= 2021
ORDER BY m.year;


-- ── 3. SETTLEMENT CHANNEL SHIFT AFTER GUIDELINES ─────────────────────────────
SELECT sc.year,
    sc.channel,
    sc.pct_of_injury_claims,
    sc.avg_settlement_cost_eur,
    CASE WHEN sc.year >= 2021 THEN 'Post-Guidelines' ELSE 'Pre-Guidelines' END
                                            AS period,
    -- Change from 2020 baseline
    sc.pct_of_injury_claims -
        AVG(sc.pct_of_injury_claims) OVER (
            PARTITION BY sc.channel
            WHERE sc.year BETWEEN 2018 AND 2020
        )                                   AS pct_change_from_pre_pig
FROM settlement_channels sc
ORDER BY sc.year, sc.channel;


-- ── 4. GUIDELINES COMPLIANCE — DIRECT vs IRB vs LITIGATION ───────────────────
-- Key insight from NCID: litigation still uses Book of Quantum (73% in 2023)
SELECT
    year,
    MAX(CASE WHEN channel='Direct'     THEN pct_of_injury_claims END) AS pct_direct,
    MAX(CASE WHEN channel='IRB'        THEN pct_of_injury_claims END) AS pct_irb,
    MAX(CASE WHEN channel='Litigation' THEN pct_of_injury_claims END) AS pct_litigation,
    -- Direct + IRB = under Guidelines; Litigation largely still Book of Quantum
    MAX(CASE WHEN channel='Direct' THEN pct_of_injury_claims END) +
    MAX(CASE WHEN channel='IRB'    THEN pct_of_injury_claims END)    AS pct_under_guidelines,
    MAX(CASE WHEN channel='Litigation' THEN pct_of_injury_claims END) AS pct_book_of_quantum
FROM settlement_channels
GROUP BY year
ORDER BY year;
