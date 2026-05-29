-- ============================================================
-- ClaimsIQ — Market Overview & Claim Frequency Analysis
-- ============================================================

-- ── 1. PREMIUM vs CLAIMS COST — IS THE MARKET PROFITABLE? ───────────────────
WITH metrics AS (
    SELECT year,
        avg_written_premium_eur,
        total_settled_claims_cost_eur_m * 1000000 /
            NULLIF(policies_written, 0)             AS claims_cost_per_policy,
        loss_ratio_pct
    FROM market_overview
)
SELECT *,
    avg_written_premium_eur - claims_cost_per_policy AS gross_underwriting_margin,
    LAG(loss_ratio_pct) OVER (ORDER BY year)        AS prev_year_lr,
    loss_ratio_pct - LAG(loss_ratio_pct)
        OVER (ORDER BY year)                         AS lr_change_yoy
FROM metrics
ORDER BY year;


-- ── 2. CLAIM FREQUENCY TREND — COVID IMPACT & RECOVERY ───────────────────────
WITH freq AS (
    SELECT year,
        injury_claim_freq_per_100,
        damage_claim_freq_per_100,
        injury_claim_freq_per_100 + damage_claim_freq_per_100 AS total_freq,
        -- Rolling 3-year average
        ROUND(AVG(injury_claim_freq_per_100) OVER (
            ORDER BY year ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2)                                           AS rolling_3yr_injury,
        ROUND(AVG(damage_claim_freq_per_100) OVER (
            ORDER BY year ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2)                                           AS rolling_3yr_damage
    FROM market_overview
)
SELECT *,
    -- Index vs 2019 pre-COVID baseline
    ROUND(injury_claim_freq_per_100 /
        NULLIF(FIRST_VALUE(injury_claim_freq_per_100) OVER (
            ORDER BY CASE WHEN year = 2019 THEN 0 ELSE 1 END
        ), 0) * 100, 1)                                 AS injury_index_vs_2019
FROM freq
ORDER BY year;


-- ── 3. DAMAGE OVERTAKING INJURY — STRUCTURAL SHIFT ───────────────────────────
SELECT year,
    damage_pct_of_total_cost,
    injury_pct_of_total_cost,
    CASE
        WHEN damage_pct_of_total_cost > injury_pct_of_total_cost
        THEN 'Damage Dominant'
        ELSE 'Injury Dominant'
    END                                                 AS cost_leader,
    -- Year when damage first exceeded injury
    CASE WHEN damage_pct_of_total_cost > 50 THEN 'Post-crossover' ELSE 'Pre-crossover' END AS crossover_status
FROM market_overview
ORDER BY year;


-- ── 4. MARKET SIZE — GWP GROWTH TREND ────────────────────────────────────────
SELECT year,
    policies_written,
    avg_written_premium_eur,
    gross_written_premium_eur_m,
    ROUND((gross_written_premium_eur_m -
        LAG(gross_written_premium_eur_m) OVER (ORDER BY year)) * 100.0 /
        NULLIF(LAG(gross_written_premium_eur_m) OVER (ORDER BY year), 0), 1)
                                                        AS gwp_yoy_growth_pct,
    SUM(gross_written_premium_eur_m) OVER (
        ORDER BY year ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                   AS cumulative_gwp_eur_m
FROM market_overview
ORDER BY year;


-- ── 5. COVID IMPACT QUANTIFICATION ───────────────────────────────────────────
-- How much did COVID reduce claims? What was the benefit to insurers?
WITH pre_covid AS (
    SELECT AVG(injury_claim_freq_per_100) AS avg_inj_freq,
           AVG(damage_claim_freq_per_100) AS avg_dam_freq,
           AVG(loss_ratio_pct)            AS avg_lr
    FROM market_overview
    WHERE year BETWEEN 2017 AND 2019
)
SELECT
    m.year,
    m.injury_claim_freq_per_100,
    pc.avg_inj_freq                                     AS pre_covid_inj_freq,
    ROUND((m.injury_claim_freq_per_100 - pc.avg_inj_freq) /
          pc.avg_inj_freq * 100, 1)                     AS inj_freq_vs_pre_covid_pct,
    m.loss_ratio_pct,
    pc.avg_lr                                           AS pre_covid_lr,
    m.loss_ratio_pct - pc.avg_lr                        AS lr_vs_pre_covid
FROM market_overview m
CROSS JOIN pre_covid pc
WHERE m.year >= 2018
ORDER BY m.year;
