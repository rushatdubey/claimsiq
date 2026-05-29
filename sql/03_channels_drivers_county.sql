-- ============================================================
-- ClaimsIQ — Settlement Channels, Driver Risk & County Analysis
-- ============================================================

-- ── 1. LITIGATION COST MULTIPLE — WHAT DOES GOING TO COURT COST? ─────────────
WITH channel_costs AS (
    SELECT year, channel, avg_settlement_cost_eur,
        FIRST_VALUE(avg_settlement_cost_eur) OVER (
            PARTITION BY year
            ORDER BY CASE channel WHEN 'Direct' THEN 0 WHEN 'IRB' THEN 1 ELSE 2 END
        )                                               AS direct_cost
    FROM settlement_channels
)
SELECT year, channel,
    avg_settlement_cost_eur,
    direct_cost,
    ROUND(avg_settlement_cost_eur::NUMERIC /
          NULLIF(direct_cost, 0), 2)                    AS multiple_vs_direct,
    RANK() OVER (PARTITION BY year ORDER BY avg_settlement_cost_eur DESC) AS cost_rank
FROM channel_costs
ORDER BY year, cost_rank;


-- ── 2. CHANNEL MIX SHIFT — MORE DIRECT = BETTER FOR INSURERS ─────────────────
SELECT year,
    MAX(CASE WHEN channel='Direct'    THEN pct_of_injury_claims END) AS pct_direct,
    MAX(CASE WHEN channel='IRB'       THEN pct_of_injury_claims END) AS pct_irb,
    MAX(CASE WHEN channel='Litigation'THEN pct_of_injury_claims END) AS pct_litigation,
    -- Weighted avg cost
    SUM(avg_settlement_cost_eur * pct_of_injury_claims / 100)        AS weighted_avg_cost,
    -- Change in litigation share
    MAX(CASE WHEN channel='Litigation' THEN pct_of_injury_claims END) -
    LAG(MAX(CASE WHEN channel='Litigation' THEN pct_of_injury_claims END))
        OVER (ORDER BY year)                            AS litigation_pct_change
FROM settlement_channels
GROUP BY year
ORDER BY year;


-- ── 3. DRIVER RISK PROFILE — WHO COSTS MOST PER POLICY? ──────────────────────
SELECT dp.year,
    dp.age_band,
    dp.avg_premium_eur,
    dp.injury_freq_per_100,
    dp.damage_freq_per_100,
    dp.claims_cost_per_policy_eur,
    dp.premium_adequacy_ratio,
    CASE
        WHEN dp.premium_adequacy_ratio > 1.15 THEN 'Over-priced'
        WHEN dp.premium_adequacy_ratio > 0.95 THEN 'Adequate'
        ELSE 'Under-priced'
    END                                                 AS pricing_status,
    RANK() OVER (
        PARTITION BY dp.year
        ORDER BY dp.claims_cost_per_policy_eur DESC
    )                                                   AS cost_rank
FROM driver_profiles dp
WHERE dp.year = 2023
ORDER BY dp.claims_cost_per_policy_eur DESC;


-- ── 4. YOUNG DRIVER PREMIUM JUSTIFICATION ────────────────────────────────────
-- Are 17-24 premiums high enough given claim costs?
WITH young AS (
    SELECT year, age_band, avg_premium_eur,
           claims_cost_per_policy_eur, premium_adequacy_ratio
    FROM driver_profiles
    WHERE age_band IN ('17-24', '35-44')  -- compare young vs baseline
),
pivoted AS (
    SELECT year,
        MAX(CASE WHEN age_band='17-24' THEN avg_premium_eur END)         AS young_premium,
        MAX(CASE WHEN age_band='35-44' THEN avg_premium_eur END)         AS base_premium,
        MAX(CASE WHEN age_band='17-24' THEN claims_cost_per_policy_eur END) AS young_cost,
        MAX(CASE WHEN age_band='35-44' THEN claims_cost_per_policy_eur END) AS base_cost
    FROM young
    GROUP BY year
)
SELECT *,
    ROUND(young_premium / NULLIF(base_premium, 0), 2)  AS premium_multiple,
    ROUND(young_cost    / NULLIF(base_cost, 0), 2)     AS cost_multiple,
    ROUND(young_premium / NULLIF(young_cost, 0), 2)    AS young_adequacy_ratio
FROM pivoted
ORDER BY year;


-- ── 5. COUNTY LOSS RATIO RANKING ─────────────────────────────────────────────
SELECT
    county,
    avg_premium_eur,
    loss_ratio_pct,
    risk_tier,
    risk_index,
    total_claims_cost_eur_m,
    total_premium_eur_m,
    -- How much above/below national average
    ROUND(loss_ratio_pct - AVG(loss_ratio_pct) OVER (), 1) AS lr_vs_national,
    CASE
        WHEN loss_ratio_pct - AVG(loss_ratio_pct) OVER () > 5
        THEN 'Underpriced — premium increase warranted'
        WHEN loss_ratio_pct - AVG(loss_ratio_pct) OVER () < -5
        THEN 'Overpriced — competitive opportunity'
        ELSE 'Adequately priced'
    END                                                 AS pricing_signal,
    RANK() OVER (ORDER BY loss_ratio_pct DESC)          AS risk_rank
FROM county_risk
ORDER BY loss_ratio_pct DESC;


-- ── 6. PREMIUM ADEQUACY — IS IRELAND UNDERINSURING? ──────────────────────────
SELECT mo.year,
    mo.avg_written_premium_eur,
    mo.loss_ratio_pct,
    -- Required premium at 70% target loss ratio
    ROUND((mo.total_settled_claims_cost_eur_m * 1000000 /
           mo.policies_written) / 0.70, 2)              AS required_premium,
    mo.avg_written_premium_eur -
    ROUND((mo.total_settled_claims_cost_eur_m * 1000000 /
           mo.policies_written) / 0.70, 2)              AS adequacy_gap,
    CASE
        WHEN mo.loss_ratio_pct < 60 THEN 'Healthy'
        WHEN mo.loss_ratio_pct < 70 THEN 'Adequate'
        WHEN mo.loss_ratio_pct < 80 THEN 'Watch'
        ELSE 'Under Stress'
    END                                                 AS market_health
FROM market_overview mo
ORDER BY mo.year;
