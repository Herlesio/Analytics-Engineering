"""
NBA Player Archetype Classification System
==========================================
Classifies NBA players (1996–present) by role and skill profile using
career-aggregated Regular Season and Playoff box score data.

Classification Philosophy
─────────────────────────
Minutes are the primary driver of role — they reflect how much a coaching
staff trusts and relies on a player. Points are secondary and only used
to separate Superstar from All-Star at the top tier. This intentionally
accounts for high-impact, low-scoring players like Draymond Green (Starter),
Andre Roberson (Rotation Player), and Dennis Rodman (Starter).

Role Tiers
──────────
Established (150+ career games):
  Superstar       : 27+ min, 24+ pts
  All-Star        : 27+ min, 14–24 pts
  Starter         : 22+ min
  Rotation Player : 10–22 min, 100+ games
  Bench Player    :  8–10 min, 100+ games
  End of Bench    :  <8 min,   <50 games

Developmental (under 150 games):
  Potential Starter : 27+ min  → starter usage, career interrupted or too early
  Prospect          : 10–27 min → on a trajectory, insufficient sample
  Developing        : ≤10 min  → limited role, still establishing themselves

Skill Labels (per position group, Regular Season and Playoffs independently)
─────────────────────────────────────────────────────────────────────────────
Per-36 metrics (Pts/Reb/Ast) are ranked within Guard / Forward / Center pools
so players are only compared to peers at their position.

Minimum pool thresholds:
  Regular Season : 500+ total minutes, 40+ games
  Playoffs       : 100+ total minutes, 10+ games

Percentile → Label mapping (same for Scoring, Rebounding, Playmaking):
  ≥95th  → Elite
  ≥80th  → Great
  ≥60th  → Good
  ≥30th  → Average
  <30th  → Limited

Databricks Tables
─────────────────
  players_categorization.reclassification.player_statistics_extended
  players_categorization.reclassification.players

Output
──────
  player_archetype_system.csv — one row per player per season type (RS + Playoffs)
"""

import pandas as pd
import numpy as np

# ─────────────────────────────────────────────
# CONFIG — adjust paths for your environment
# ─────────────────────────────────────────────
STATS_PATH   = "C:\\Users\\herle\\Downloads\\NBA_boxscore_1947_today\\PlayerStatisticsExtended.csv"
PLAYERS_PATH = "C:\\Users\\herle\\Downloads\\NBA_boxscore_1947_today\\Players.csv"
OUTPUT_PATH  = "C:\\Users\\herle\\Downloads\\NBA_output_pycharm\\player_archetype_system.csv"

# Minimum thresholds for percentile pool eligibility
RS_MIN_MINUTES = 500
RS_MIN_GAMES   = 40
PO_MIN_MINUTES = 100
PO_MIN_GAMES   = 10

# ─────────────────────────────────────────────
# 1. LOAD
# ─────────────────────────────────────────────
print("Loading data...")
stats        = pd.read_csv(STATS_PATH,   low_memory=False)
players_meta = pd.read_csv(PLAYERS_PATH, low_memory=False)

# ─────────────────────────────────────────────
# 2. PREP & FILTER
# ─────────────────────────────────────────────
for col in ["numMinutes", "points", "assists", "reboundsTotal"]:
    stats[col] = pd.to_numeric(stats[col], errors="coerce")

stats = stats[stats["gameType"].isin(["Regular Season", "Playoffs"])].copy()

# Canonical name per personId (most frequent name wins — handles name changes/typos)
stats["playerName"] = stats["firstName"].str.strip() + " " + stats["lastName"].str.strip()
name_map = stats.groupby("personId")["playerName"].agg(lambda x: x.mode().iloc[0])
stats["playerName"] = stats["personId"].map(name_map)

# Remove duplicate player-game records (keep first occurrence)
stats = stats.drop_duplicates(subset=["personId", "gameId"], keep="first")

# ─────────────────────────────────────────────
# 3. AGGREGATE per player per season type
# ─────────────────────────────────────────────
agg = (
    stats.groupby(["personId", "playerName", "gameType"])
    .agg(
        gamesPlayed  = ("gameId",        "nunique"),
        totalMinutes = ("numMinutes",    "sum"),
        avgMinutes   = ("numMinutes",    "mean"),
        avgPoints    = ("points",        "mean"),
        avgRebounds  = ("reboundsTotal", "mean"),
        avgAssists   = ("assists",       "mean"),
    )
    .reset_index()
)

# ─────────────────────────────────────────────
# 4. POSITION MAPPING
#    Priority: Center > Forward > Guard
#    Multi-position players inherit the "bigger" position
# ─────────────────────────────────────────────
pos_meta = players_meta[["personId", "guard", "forward", "center"]].copy()
for col in ["guard", "forward", "center"]:
    pos_meta[col] = pd.to_numeric(pos_meta[col], errors="coerce").fillna(0).astype(int)

def assign_position(row):
    if row["center"]  == 1: return "Center"
    if row["forward"] == 1: return "Forward"
    if row["guard"]   == 1: return "Guard"
    return "Unknown"

pos_meta["position"] = pos_meta.apply(assign_position, axis=1)
agg = agg.merge(pos_meta[["personId", "position"]], on="personId", how="left")
agg["position"] = agg["position"].fillna("Unknown")

# ─────────────────────────────────────────────
# 5. ROLE CLASSIFICATION  (Regular Season only)
#
#  Rule priority — first match wins (top to bottom):
#    Superstar → All-Star → Starter → Rotation → Bench →
#    End of Bench → Potential Starter → Prospect → Developing
# ─────────────────────────────────────────────
def classify_role(row):
    mins  = row["avgMinutes"]
    pts   = row["avgPoints"]
    games = row["gamesPlayed"]

    # ── Established tiers (150+ career games) ──
    if games >= 150:
        if mins >= 27 and pts >= 24: return "Superstar"       # 24+ pts threshold
        if mins >= 27 and pts >= 14: return "All-Star"         # 14+ pts threshold
        if mins >= 22:               return "Starter"

    # ── Rotation & Bench (100+ games, minutes-only — no points floor) ──
    # Defensive specialists and role players are correctly placed by minutes alone
    if 10 <= mins < 22 and games >= 100: return "Rotation Player"
    if  8 <= mins < 10 and games >= 100: return "Bench Player"

    # ── End of Bench: under 8 min, under 50 career games ──
    if mins < 8 and games < 50:          return "End of Bench"

    # ── Developmental tiers (under 150 games) ──
    # Starter-level minutes — career interrupted or player too early to commit
    if mins >= 27 and games < 150:               return "Potential Starter"

    # Rotation/near-starter minutes — on a trajectory, not enough sample yet
    # Note: Rotation Player already wins at 100–149 games (caught above)
    if 10 <= mins < 27 and games < 100:          return "Prospect"

    # 22–27 min with 100–149 games — significant sample, near threshold
    if 22 <= mins < 27 and 100 <= games < 150:   return "Prospect"

    # Everything else — limited minutes, still establishing themselves
    return "Developing"

rs_mask = agg["gameType"] == "Regular Season"
agg.loc[rs_mask, "role"] = agg[rs_mask].apply(classify_role, axis=1)

# Stamp RS role onto Playoffs rows (role identity doesn't change in playoffs)
role_map = agg[rs_mask][["personId", "role"]].rename(columns={"role": "rs_role"})
agg = agg.merge(role_map, on="personId", how="left")
agg["role"] = agg["role"].fillna(agg["rs_role"]).fillna("No Regular Season Data")
agg.drop(columns="rs_role", inplace=True)

# ─────────────────────────────────────────────
# 6. PER-36 SKILL METRICS
#    Normalizes production to a 36-minute baseline so players
#    with different minute totals can be compared fairly.
# ─────────────────────────────────────────────
agg["pts_per36"] = (agg["avgPoints"]   / agg["avgMinutes"] * 36).replace([np.inf, -np.inf], np.nan).round(2)
agg["reb_per36"] = (agg["avgRebounds"] / agg["avgMinutes"] * 36).replace([np.inf, -np.inf], np.nan).round(2)
agg["ast_per36"] = (agg["avgAssists"]  / agg["avgMinutes"] * 36).replace([np.inf, -np.inf], np.nan).round(2)

# ─────────────────────────────────────────────
# 7. PERCENTILE POOLS
#    RS and Playoffs computed independently (Option B):
#    a player is ranked against peers who also played in that context.
#    Computed within position groups — guards vs guards, etc.
# ─────────────────────────────────────────────
def compute_percentiles(df_subset, min_minutes, min_games, label):
    eligible = df_subset[
        (df_subset["totalMinutes"] >= min_minutes) &
        (df_subset["gamesPlayed"]  >= min_games) &
        (df_subset["position"]     != "Unknown")
    ].copy()

    print(f"\n{label} eligible pool: {len(eligible)} players")
    for pos in ["Guard", "Forward", "Center"]:
        print(f"  {pos}s: {(eligible['position']==pos).sum()}")

    pct_rows = []
    for position, group in eligible.groupby("position"):
        grp = group[["personId", "pts_per36", "reb_per36", "ast_per36"]].copy()
        for metric, label_col in [
            ("pts_per36", "pts_pct"),
            ("reb_per36", "reb_pct"),
            ("ast_per36", "ast_pct"),
        ]:
            valid = grp[metric].notna()
            grp.loc[valid, label_col] = grp.loc[valid, metric].rank(pct=True) * 100
        pct_rows.append(grp[["personId", "pts_pct", "reb_pct", "ast_pct"]])

    return (
        pd.concat(pct_rows, ignore_index=True)
        .drop_duplicates(subset="personId")
    )

rs_pct = compute_percentiles(
    agg[agg["gameType"] == "Regular Season"],
    min_minutes=RS_MIN_MINUTES, min_games=RS_MIN_GAMES, label="Regular Season"
)
po_pct = compute_percentiles(
    agg[agg["gameType"] == "Playoffs"],
    min_minutes=PO_MIN_MINUTES, min_games=PO_MIN_GAMES, label="Playoffs"
)

rs_pct["gameType"] = "Regular Season"
po_pct["gameType"] = "Playoffs"
all_pct = pd.concat([rs_pct, po_pct], ignore_index=True)
agg = agg.merge(all_pct, on=["personId", "gameType"], how="left")

# ─────────────────────────────────────────────
# 8. SKILL LABELS
#    Percentile → human-readable label per skill dimension
# ─────────────────────────────────────────────
def skill_label(percentile, skill):
    if pd.isna(percentile): return f"N/A {skill}"
    if percentile >= 95:    return f"Elite {skill}"
    if percentile >= 80:    return f"Great {skill}"
    if percentile >= 60:    return f"Good {skill}"
    if percentile >= 30:    return f"Average {skill}"
    return                         f"Limited {skill}"

agg["scoring_label"]    = agg["pts_pct"].apply(lambda p: skill_label(p, "Scorer"))
agg["rebounding_label"] = agg["reb_pct"].apply(lambda p: skill_label(p, "Rebounder"))
agg["playmaking_label"] = agg["ast_pct"].apply(lambda p: skill_label(p, "Playmaker"))

# ─────────────────────────────────────────────
# 9. FINAL SORT, RENAME & COLUMN ORDER
# ─────────────────────────────────────────────
agg = agg.sort_values(
    ["playerName", "gameType"],
    ascending=[True, False]   # Regular Season before Playoffs alphabetically
).reset_index(drop=True)

for col in ["avgMinutes", "avgPoints", "avgRebounds", "avgAssists"]:
    agg[col] = agg[col].round(1)
for col in ["pts_pct", "reb_pct", "ast_pct"]:
    if col in agg.columns:
        agg[col] = agg[col].round(1)

agg = agg.rename(columns={
    "gameType"          : "Season Type",
    "gamesPlayed"       : "Games Played",
    "totalMinutes"      : "Total Minutes",
    "avgMinutes"        : "Avg Minutes",
    "avgPoints"         : "Avg Points",
    "avgRebounds"       : "Avg Rebounds",
    "avgAssists"        : "Avg Assists",
    "role"              : "Role Classification",
    "position"          : "Position",
    "pts_per36"         : "Pts Per 36",
    "reb_per36"         : "Reb Per 36",
    "ast_per36"         : "Ast Per 36",
    "pts_pct"           : "Scoring Percentile",
    "reb_pct"           : "Rebounding Percentile",
    "ast_pct"           : "Playmaking Percentile",
    "scoring_label"     : "Scoring Label",
    "rebounding_label"  : "Rebounding Label",
    "playmaking_label"  : "Playmaking Label",
})

final_cols = [
    "personId", "playerName", "Position", "Season Type",
    "Games Played", "Total Minutes",
    "Avg Points", "Avg Rebounds", "Avg Assists", "Avg Minutes",
    "Pts Per 36", "Reb Per 36", "Ast Per 36",
    "Scoring Percentile", "Rebounding Percentile", "Playmaking Percentile",
    "Role Classification", "Scoring Label", "Rebounding Label", "Playmaking Label",
]
agg = agg[final_cols]

# ─────────────────────────────────────────────
# 10. SAVE
# ─────────────────────────────────────────────
agg.to_csv(OUTPUT_PATH, index=False)
print(f" Done! {len(agg):,} rows → {OUTPUT_PATH}")
print(f"   Unique players: {agg['playerName'].nunique():,}")

# ─────────────────────────────────────────────
# 11. VALIDATION SUMMARY
# ─────────────────────────────────────────────
rs = agg[agg["Season Type"] == "Regular Season"]

print("\n── Role breakdown (Regular Season) ──")
print(rs["Role Classification"].value_counts().to_string())

print("\n── Spot check: known players ──")
names = [
    "Stephen Curry", "LeBron James", "Nikola Jokic", "Luka Doncic",
    "Paolo Banchero", "Victor Wembanyama", "Cooper Flagg",
    "Josh Hart", "Draymond Green", "Andre Roberson",
    "Dennis Rodman", "Rudy Gobert",
]
cols = ["playerName", "Games Played", "Avg Points", "Avg Minutes",
        "Role Classification", "Scoring Label", "Rebounding Label", "Playmaking Label"]
spot = rs[rs["playerName"].isin(names)]
print(spot[cols].sort_values("Avg Minutes", ascending=False).to_string(index=False))
