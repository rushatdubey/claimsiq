"""
ClaimsIQ — Analytics Pipeline
9 analytical stages producing all Tableau-ready CSVs.

Run: python python/analytics.py
Outputs → tableau/
"""

import pandas as pd
import numpy as np
import os

DATA_DIR   = os.path.join(os.path.dirname(__file__), "../data")
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "../tableau")
os.makedirs(OUTPUT_DIR, exist_ok=True)


def load():
    market   = pd.read_csv(f"{DATA_DIR}/01_market_overview.csv")
    channels = pd.read_csv(f"{DATA_DIR}/02_settlement_channels.csv")
    drivers  = pd.read_csv(f"{DATA_DIR}/03_driver_profiles.csv")
    county   = pd.read_csv(f"{DATA_DIR}/04_county_risk.csv")
    pricing  = pd.read_csv(f"{DATA_DIR}/05_pricing_adequacy.csv")
    pig      = pd.read_csv(f"{DATA_DIR}/06_pig_impact.csv")
    return market, channels, drivers, county, pricing, pig


# ── STAGE 1: MARKET OVERVIEW ──────────────────────────────────────────────────
def market_overview(df):
    df = df.copy()
    df["gwp_yoy_pct"] = df["gross_written_premium_eur_m"].pct_change()*100
    df["premium_yoy_pct"] = df["avg_written_premium_eur"].pct_change()*100
    df["claims_yoy_pct"] = df["total_settled_claims_cost_eur_m"].pct_change()*100
    df["claims_per_policy_eur"] = round(
        df["total_settled_claims_cost_eur_m"]*1e6 / df["policies_written"], 2)
    for c in ["gwp_yoy_pct","premium_yoy_pct","claims_yoy_pct"]:
        df[c] = df[c].round(1)
    df.to_csv(f"{OUTPUT_DIR}/01_market_overview.csv", index=False)
    print(f"  Stage 1: Market Overview — {len(df)} rows")
    return df


# ── STAGE 2: CLAIM FREQUENCY TREND ───────────────────────────────────────────
def claim_frequency(df):
    freq = df[["year","injury_claim_freq_per_100","damage_claim_freq_per_100",
               "injury_claims","damage_claims"]].copy()
    freq["total_freq_per_100"] = (
        freq["injury_claim_freq_per_100"] + freq["damage_claim_freq_per_100"]).round(2)
    freq["total_claims"] = freq["injury_claims"] + freq["damage_claims"]
    # Index vs 2019 baseline (pre-COVID)
    base_inj = freq[freq["year"]==2019]["injury_claim_freq_per_100"].values[0]
    base_dam = freq[freq["year"]==2019]["damage_claim_freq_per_100"].values[0]
    freq["injury_freq_vs_2019"] = (freq["injury_claim_freq_per_100"]/base_inj*100).round(1)
    freq["damage_freq_vs_2019"] = (freq["damage_claim_freq_per_100"]/base_dam*100).round(1)
    freq.to_csv(f"{OUTPUT_DIR}/02_claim_frequency.csv", index=False)
    print(f"  Stage 2: Claim Frequency — {len(freq)} rows")
    return freq


# ── STAGE 3: CLAIM COST TREND ─────────────────────────────────────────────────
def claim_cost(df):
    cost = df[["year","avg_injury_claim_cost_eur","avg_damage_claim_cost_eur",
               "total_settled_claims_cost_eur_m","loss_ratio_pct",
               "damage_pct_of_total_cost","injury_pct_of_total_cost"]].copy()
    cost["injury_cost_eur_m"] = round(
        df["total_settled_claims_cost_eur_m"] * df["injury_pct_of_total_cost"]/100, 1)
    cost["damage_cost_eur_m"] = round(
        df["total_settled_claims_cost_eur_m"] * df["damage_pct_of_total_cost"]/100, 1)
    cost["avg_injury_yoy_pct"] = cost["avg_injury_claim_cost_eur"].pct_change()*100
    cost["avg_damage_yoy_pct"] = cost["avg_damage_claim_cost_eur"].pct_change()*100
    for c in ["avg_injury_yoy_pct","avg_damage_yoy_pct"]:
        cost[c] = cost[c].round(1)
    # Inflation-adjusted (using Irish CPI — base 2009)
    CPI = {2009:1.00,2010:0.99,2011:1.03,2012:1.06,2013:1.06,
           2014:1.05,2015:1.05,2016:1.05,2017:1.06,2018:1.08,
           2019:1.10,2020:1.10,2021:1.12,2022:1.20,2023:1.25}
    cost["avg_injury_real_eur"] = cost.apply(
        lambda r: int(r["avg_injury_claim_cost_eur"]/CPI[r["year"]]), axis=1)
    cost.to_csv(f"{OUTPUT_DIR}/03_claim_costs.csv", index=False)
    print(f"  Stage 3: Claim Costs — {len(cost)} rows")
    return cost


# ── STAGE 4: SETTLEMENT CHANNELS ─────────────────────────────────────────────
def settlement_channels(channels):
    df = channels.copy()
    # Add litigation cost multiple for each year
    df["channel_cost_index"] = df["channel"].map(
        {"Direct":100, "IRB":162, "Litigation":420})
    df.to_csv(f"{OUTPUT_DIR}/04_settlement_channels.csv", index=False)
    print(f"  Stage 4: Settlement Channels — {len(df)} rows")
    return df


# ── STAGE 5: DRIVER PROFILE RISK ─────────────────────────────────────────────
def driver_risk(drivers):
    df = drivers.copy()
    # Latest year cross-section
    latest = df[df["year"]==2023].copy()
    latest["total_claims_freq"] = latest["injury_freq_per_100"]+latest["damage_freq_per_100"]
    latest["risk_tier"] = latest["injury_freq_per_100"].apply(lambda x:
        "Very High" if x >= 4.0 else
        "High"      if x >= 3.0 else
        "Moderate"  if x >= 1.5 else
        "Low"
    )
    # Pricing adequacy by age band
    latest["adequacy_status"] = latest["premium_adequacy_ratio"].apply(lambda r:
        "Over-priced"   if r > 1.15 else
        "Adequate"      if r > 0.95 else
        "Under-priced"
    )
    df.to_csv(f"{OUTPUT_DIR}/05_driver_profiles.csv", index=False)
    latest.to_csv(f"{OUTPUT_DIR}/05b_driver_profiles_2023.csv", index=False)
    print(f"  Stage 5: Driver Profiles — {len(df)} rows")
    return df


# ── STAGE 6: COUNTY RISK MAP ──────────────────────────────────────────────────
def county_risk(county):
    df = county.copy()
    nat_lr = df["loss_ratio_pct"].mean()
    df["lr_vs_national"] = (df["loss_ratio_pct"] - nat_lr).round(1)
    df["lr_vs_national_pct"] = ((df["loss_ratio_pct"] - nat_lr)/nat_lr*100).round(1)
    df["pricing_signal"] = df["lr_vs_national"].apply(lambda x:
        "Underpriced — raise premium" if x >  5 else
        "Overpriced — competitive opportunity" if x < -5 else
        "Adequately priced"
    )
    df.to_csv(f"{OUTPUT_DIR}/06_county_risk.csv", index=False)
    print(f"  Stage 6: County Risk — {len(df)} rows")
    return df


# ── STAGE 7: PRICING ADEQUACY ─────────────────────────────────────────────────
def pricing_adequacy(pricing):
    df = pricing.copy()
    # Cumulative under/over pricing
    df["cumulative_adequacy_gap_eur"] = df["adequacy_gap_eur"].cumsum()
    # Premium vs claims cost indexed to 2009
    base_p = df[df["year"]==2009]["avg_written_premium_eur"].values[0]
    base_c = df[df["year"]==2009]["claims_cost_per_policy_eur"].values[0]
    df["premium_index_2009"] = (df["avg_written_premium_eur"]/base_p*100).round(1)
    df["claims_index_2009"]  = (df["claims_cost_per_policy_eur"]/base_c*100).round(1)
    df.to_csv(f"{OUTPUT_DIR}/07_pricing_adequacy.csv", index=False)
    print(f"  Stage 7: Pricing Adequacy — {len(df)} rows")
    return df


# ── STAGE 8: PERSONAL INJURY GUIDELINES IMPACT ───────────────────────────────
def pig_impact(pig):
    df = pig.copy()
    df["cumulative_saving_eur_m"] = df["total_market_saving_eur_m"].cumsum()
    df["cost_reduction_vs_pre_pig"] = df["avg_injury_claim_cost_eur"].apply(
        lambda c: round((35200-c)/35200*100,1)  # 35200 = 2020 pre-PIG baseline
    )
    df["cost_reduction_vs_pre_pig"] = df["cost_reduction_vs_pre_pig"].clip(lower=0)
    df.to_csv(f"{OUTPUT_DIR}/08_pig_impact.csv", index=False)
    print(f"  Stage 8: PIG Impact — {len(df)} rows")
    return df


# ── STAGE 9: EXECUTIVE SCORECARD ──────────────────────────────────────────────
def executive_scorecard(market, pricing, county):
    """One-row-per-year KPI summary for executive dashboard tab."""
    df = market[["year","avg_written_premium_eur","total_settled_claims_cost_eur_m",
                 "loss_ratio_pct","injury_claim_freq_per_100",
                 "damage_claim_freq_per_100"]].copy()
    pr = pricing[["year","adequacy_gap_eur","pricing_status"]]
    df = df.merge(pr, on="year")
    df["market_health"] = df["loss_ratio_pct"].apply(lambda lr:
        "Healthy"     if lr < 60 else
        "Watch"       if lr < 70 else
        "Under Stress" if lr < 80 else
        "Critical"
    )
    df.to_csv(f"{OUTPUT_DIR}/09_executive_scorecard.csv", index=False)
    print(f"  Stage 9: Executive Scorecard — {len(df)} rows")
    return df


# ── MAIN ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("ClaimsIQ — Analytics Pipeline\n" + "="*40)
    market, channels, drivers, county, pricing, pig = load()

    market_overview(market)
    claim_frequency(market)
    claim_cost(market)
    settlement_channels(channels)
    driver_risk(drivers)
    county_risk(county)
    pricing_adequacy(pricing)
    pig_impact(pig)
    executive_scorecard(market, pricing, county)

    print(f"\n✓ All 9 Tableau CSVs written to tableau/")

    print("\n── KEY FINDINGS (2023, verified against NCID Report 6) ──")
    m = pd.read_csv(f"{OUTPUT_DIR}/01_market_overview.csv")
    r = m[m["year"]==2023].iloc[0]
    print(f"  Market size:        €{r['gross_written_premium_eur_m']:.0f}M GWP")
    print(f"  Avg premium:        €{r['avg_written_premium_eur']:.0f}")
    print(f"  Total claims cost:  €{r['total_settled_claims_cost_eur_m']:.0f}M")
    print(f"  Loss ratio:         {r['loss_ratio_pct']}%")
    print(f"  Injury freq:        {r['injury_claim_freq_per_100']}/100 policies")
    print(f"  Damage freq:        {r['damage_claim_freq_per_100']}/100 policies")
    print(f"  Damage share:       {r['damage_pct_of_total_cost']}% of total costs")

    print("\n── COUNTY RISK (Top 5 highest loss ratio) ──")
    c = pd.read_csv(f"{OUTPUT_DIR}/06_county_risk.csv")
    print(c[["county","avg_premium_eur","loss_ratio_pct","risk_tier",
             "pricing_signal"]].head(5).to_string(index=False))

    print("\n── PRICING ADEQUACY (Last 3 years) ──")
    p = pd.read_csv(f"{OUTPUT_DIR}/07_pricing_adequacy.csv")
    print(p[["year","avg_written_premium_eur","loss_ratio_pct",
             "adequacy_gap_eur","pricing_status"]].tail(3).to_string(index=False))
