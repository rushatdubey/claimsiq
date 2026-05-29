-- ============================================================
-- ClaimsIQ — PostgreSQL Schema
-- Irish Motor Insurance Claims Analytics
-- ============================================================

CREATE TABLE market_overview (
    year                          SMALLINT PRIMARY KEY,
    policies_written              INT,
    avg_written_premium_eur       NUMERIC(8,2),
    gross_written_premium_eur_m   NUMERIC(8,1),
    pct_comprehensive             NUMERIC(5,1),
    injury_claim_freq_per_100     NUMERIC(5,2),
    damage_claim_freq_per_100     NUMERIC(5,2),
    injury_claims                 INT,
    damage_claims                 INT,
    avg_injury_claim_cost_eur     NUMERIC(10,2),
    avg_damage_claim_cost_eur     NUMERIC(10,2),
    total_settled_claims_cost_eur_m NUMERIC(8,1),
    loss_ratio_pct                NUMERIC(5,1),
    damage_pct_of_total_cost      NUMERIC(5,1),
    injury_pct_of_total_cost      NUMERIC(5,1)
);

CREATE TABLE settlement_channels (
    id                            SERIAL PRIMARY KEY,
    year                          SMALLINT,
    channel                       VARCHAR(20),
    claims                        INT,
    pct_of_injury_claims          NUMERIC(5,1),
    avg_settlement_cost_eur       NUMERIC(10,2),
    total_settlement_cost_eur_m   NUMERIC(8,2)
);

CREATE TABLE driver_profiles (
    id                            SERIAL PRIMARY KEY,
    year                          SMALLINT,
    age_band                      VARCHAR(10),
    policies                      INT,
    avg_premium_eur               NUMERIC(8,2),
    injury_freq_per_100           NUMERIC(5,2),
    damage_freq_per_100           NUMERIC(5,2),
    claims_cost_per_policy_eur    NUMERIC(10,2),
    premium_adequacy_ratio        NUMERIC(6,3)
);

CREATE TABLE county_risk (
    county                        VARCHAR(30) PRIMARY KEY,
    year                          SMALLINT,
    estimated_policies            INT,
    avg_premium_eur               NUMERIC(8,2),
    premium_index                 NUMERIC(6,1),
    injury_freq_per_100           NUMERIC(5,2),
    damage_freq_per_100           NUMERIC(5,2),
    total_claims_cost_eur_m       NUMERIC(8,2),
    total_premium_eur_m           NUMERIC(8,2),
    loss_ratio_pct                NUMERIC(5,1),
    risk_index                    NUMERIC(6,1),
    risk_tier                     VARCHAR(20)
);

CREATE INDEX idx_settlement_year    ON settlement_channels(year);
CREATE INDEX idx_driver_year_band   ON driver_profiles(year, age_band);
CREATE INDEX idx_county_risk_tier   ON county_risk(risk_tier);
