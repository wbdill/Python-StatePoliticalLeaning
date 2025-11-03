-- state_political_leaning.duckdb
-- ================================================================================
-- Ingestion
-- ================================================================================
CREATE TABLE raw_ec_votes AS
SELECT * FROM read_csv_auto("C:\Github\Python-StatePoliticalLeaning\data\electoral_college_votes_by_state_year.csv");

CREATE TABLE raw_potus_state AS
SELECT * FROM read_csv_auto("C:\Github\Python-StatePoliticalLeaning\data\potus_votes_bystate.csv");

CREATE TABLE raw_potus_nation AS
SELECT * FROM read_csv_auto("C:\Github\Python-StatePoliticalLeaning\data\potus_votes_national.csv");

-- ================================================================================
-- spot check
SELECT * FROM ec_votes
where state_po = 'TN' ORDER BY YEAR

SELECT * FROM potus_state;
select year, count(*) AS N FROM potus_state GROUP BY ALL;
SELECT * FROM potus_nation;
SELECT * FROM raw_ec_votes;
SELECT * FROM raw_ec_votes WHERE state = 'Total';


-- ================================================================================
/*
| Step                                                   | Concept                      | What the SQL does                                   | Why it matters                                                                                                                                                                                               |
| ------------------------------------------------------ | ---------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **1. Compute state vs. national deviation (`dr_dev`)** | Difference in D–R margin     | `(dem_pct - rep_pct) - (nat_dem_pct - nat_rep_pct)` | Measures how much more Democratic or Republican a state is than the national result that year.                                                                                                               |
| **2. Standardize via z-scores**                        | Normalize within each year   | `(dr_dev - AVG(dr_dev)) / STDDEV_POP(dr_dev)`       | Converts raw point differences into “how many standard deviations from average.” Enables comparison across years.                                                                                            |
| **3. Use robust z-scores with MAD**                    | Median-based standardization | `(dr_dev - MEDIAN(dr_dev)) / MAD(dr_dev)`           | Replaces mean and standard deviation (which are distorted by extreme states like DC/WY) with **median** and **median absolute deviation (MAD)**, giving a **robust z-score** that’s stable against outliers. |
| **4. Apply `tanh()` transform**                        | Softly limit extreme values  | `100 * tanh(dr_z_robust / 2)` → `pli_score`         | The **hyperbolic tangent** smoothly compresses large z-scores into a bounded −100 ↔ +100 range, preventing outliers from dominating while keeping the middle range expressive.                               |
| **5. Assign lean direction**                           | Categorical interpretation   | `CASE WHEN dr_z_robust > 0 THEN 'D' ELSE 'R'`       | Labels each state as leaning Democratic or Republican for quick grouping.                                                                                                                                    |

| Column                            | Meaning                                                                  |
| --------------------------------- | ------------------------------------------------------------------------ |
| `dr_dev`                          | State’s D–R margin deviation from national                               |
| `dr_z`, `dr_z_robust`             | Standard and robust z-scores                                             |
| `pli_score`                       | Final normalized **Partisan Lean Index** (−100 = most R → +100 = most D) |
| `lean_party`, `lean_party_robust` | Direction of lean                                                        |

The query measures each state’s partisan tilt relative to the nation,
then uses robust z-scores (median + MAD) to reduce the influence of extreme cases,
and finally applies tanh() to “compress” those extremes into a smooth, interpretable scale.

The outcome is a stable, comparable State Partisan Lean Index across elections — analytically rigorous yet intuitive to interpret.
**/


CREATE OR REPLACE TABLE potus_state AS
WITH base AS (
    SELECT
        s.year,
        s.state,
        s.state_po,
        s.state_fips,
        s.dem_pct,
        s.rep_pct,
        s.other_pct,
        s.dem_pct - s.rep_pct AS d_r_diff,
        n.dem_pct AS nat_dem_pct,
        n.rep_pct AS nat_rep_pct,
        n.other_pct AS nat_other_pct,
        n.dem_pct - n.rep_pct AS nat_d_r_diff
    FROM raw_potus_state s
    JOIN raw_potus_nation n USING (year)
),
with_dev AS (
    SELECT
        *,
        (dem_pct - rep_pct) - (nat_dem_pct - nat_rep_pct) AS dr_dev
    FROM base
),
with_z AS (
    SELECT
        *,
        (dr_dev - AVG(dr_dev) OVER w) / NULLIF(STDDEV_POP(dr_dev) OVER w, 0) AS dr_z,
        (dr_dev - MEDIAN(dr_dev) OVER w) / NULLIF(MAD(dr_dev) OVER w, 0) AS dr_z_robust
    FROM with_dev
    WINDOW w AS (PARTITION BY year)
),
with_index AS (
    SELECT
        *,
        -- Continuous Partisan Lean Index scaled to ±100
        100 * tanh(dr_z_robust / 2.0) AS pli_score
    FROM with_z
)
SELECT
    year,
    state,
    state_po,
    state_fips,
    dem_pct,
    rep_pct,
    other_pct,
    d_r_diff,
    nat_dem_pct,
    nat_rep_pct,
    nat_other_pct,
    nat_d_r_diff,
    dr_dev,
    dr_z,
    dr_z_robust,
    pli_score,
    CASE WHEN dr_dev > 0 THEN 'D' ELSE 'R' END AS lean_party,
    CASE WHEN dr_z_robust > 0 THEN 'D' ELSE 'R' END AS lean_party_robust
FROM with_index
ORDER BY year, state;

