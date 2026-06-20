"""
NBA Referee Analysis — Standalone Local Script
================================================
Local CSV version of the Databricks referee analysis pipeline.
Produces the same referee_summary table and three charts using
local file paths instead of Databricks Delta tables.

Source data (Kaggle NBA dataset):
  Games.csv
  TeamStatisticsExtended.csv
"""

import pandas as pd
import matplotlib.pyplot as plt
import warnings

warnings.filterwarnings("ignore")

# ─────────────────────────────────────────────
# CONFIG — update these paths for your environment
# ─────────────────────────────────────────────
GAMES_PATH = "Games.csv"
STATS_PATH = "TeamStatisticsExtended.csv"
OUTPUT_CSV = "referee_summary.csv"
CHARTS_DIR = "charts"

# ─────────────────────────────────────────────
# 1. LOAD
# ─────────────────────────────────────────────
print("Loading data...")
games = pd.read_csv(GAMES_PATH, low_memory=False)
stats = pd.read_csv(STATS_PATH, low_memory=False)

print(f"Games rows: {len(games):,}")
print(f"Stats rows: {len(stats):,}")

# ─────────────────────────────────────────────
# 2. SEASON TYPE MAPPING
# ─────────────────────────────────────────────
SEASON_TYPE_MAP = {
    "Regular Season":     "Regular Season",
    "Emirates NBA Cup":   "Regular Season",
    "NBA Cup":            "Regular Season",
    "Playoffs":           "Playoffs",
    "Play-in Tournament": "Playoffs",
}

games["season_type"] = games["gameType"].map(SEASON_TYPE_MAP)
games = games[games["season_type"].notna()].copy()

stats["season_type"] = stats["gameType"].map(SEASON_TYPE_MAP)
stats = stats[stats["season_type"].notna()].copy()

# ─────────────────────────────────────────────
# 3. BUILD PER-GAME FOUL + RESULT TABLE
# ─────────────────────────────────────────────
winning_team = (stats[stats["win"] == 1]
                [["gameId", "foulsPersonal"]]
                .rename(columns={"foulsPersonal": "winner_fouls"}))

losing_team = (stats[stats["win"] == 0]
               [["gameId", "foulsPersonal"]]
               .rename(columns={"foulsPersonal": "loser_fouls"}))

home_result = (stats[stats["home"] == 1]
               [["gameId", "win"]]
               .rename(columns={"win": "home_won"}))

foul_table = (winning_team
              .merge(losing_team, on="gameId")
              .merge(home_result, on="gameId"))

foul_table["total_fouls"]     = foul_table["winner_fouls"] + foul_table["loser_fouls"]
foul_table["winner_foul_pct"] = (foul_table["winner_fouls"] / foul_table["total_fouls"] * 100).round(1)
foul_table["loser_foul_pct"]  = (foul_table["loser_fouls"]  / foul_table["total_fouls"] * 100).round(1)

# ─────────────────────────────────────────────
# 4. EXPLODE OFFICIALS — one row per (game, referee)
# ─────────────────────────────────────────────
games["officials_list"] = games["officials"].dropna().str.split(r",\s*")
ref_rows = (games[["gameId", "season_type", "officials_list"]]
            .dropna(subset=["officials_list"])
            .explode("officials_list")
            .rename(columns={"officials_list": "referee"}))
ref_rows["referee"] = ref_rows["referee"].str.strip()
ref_rows = ref_rows[ref_rows["referee"] != ""]
ref_rows = ref_rows.merge(foul_table, on="gameId", how="inner")

# ─────────────────────────────────────────────
# 5. AGGREGATE per referee x season type
# ─────────────────────────────────────────────
def summarize(group):
    total = len(group)
    hw = group["home_won"].sum()
    return pd.Series({
        "games_officiated":         total,
        "home_team_wins":           int(hw),
        "away_team_wins":           int(total - hw),
        "home_win_pct":             round(hw / total * 100, 1),
        "away_win_pct":             round((total - hw) / total * 100, 1),
        "avg_winner_fouls":         round(group["winner_fouls"].mean(), 1),
        "avg_loser_fouls":          round(group["loser_fouls"].mean(), 1),
        "avg_total_fouls_per_game": round(group["total_fouls"].mean(), 1),
        "avg_winner_foul_pct":      round(group["winner_foul_pct"].mean(), 1),
        "avg_loser_foul_pct":       round(group["loser_foul_pct"].mean(), 1),
    })

agg = (ref_rows
       .groupby(["referee", "season_type"])
       .apply(summarize, include_groups=False)
       .reset_index())

# ─────────────────────────────────────────────
# 6. PIVOT — Regular Season & Playoffs side by side
# ─────────────────────────────────────────────
metrics = ["games_officiated", "home_team_wins", "away_team_wins",
           "home_win_pct", "away_win_pct", "avg_winner_fouls",
           "avg_loser_fouls", "avg_total_fouls_per_game",
           "avg_winner_foul_pct", "avg_loser_foul_pct"]

pivot = agg.pivot(index="referee", columns="season_type", values=metrics)
pivot.columns = [f"{s}_{m}" for m, s in pivot.columns]
pivot = pivot.reset_index()

for s in ["Regular Season", "Playoffs"]:
    col = f"{s}_games_officiated"
    if col in pivot.columns:
        pivot[col] = pivot[col].fillna(0).astype(int)

pivot["total_games_officiated"] = (
    pivot.get("Regular Season_games_officiated", 0) +
    pivot.get("Playoffs_games_officiated", 0)
)
pivot = pivot.sort_values("total_games_officiated", ascending=False).reset_index(drop=True)

print(f"\n✅ Analysis complete — {len(pivot)} referees")

# Clean column names (consistent with Delta version)
pivot.columns = (
    pivot.columns.astype(str)
        .str.replace(" ", "_", regex=False)
        .str.replace("%", "pct", regex=False)
        .str.replace("/", "_", regex=False)
        .str.replace("-", "_", regex=False)
        .str.replace("(", "", regex=False)
        .str.replace(")", "", regex=False)
)

# ─────────────────────────────────────────────
# 7. SAVE OUTPUT CSV
# ─────────────────────────────────────────────
pivot.to_csv(OUTPUT_CSV, index=False)
print(f"✅ Saved {OUTPUT_CSV}")

# ─────────────────────────────────────────────
# 8. VISUALIZATIONS
# ─────────────────────────────────────────────
import os
os.makedirs(CHARTS_DIR, exist_ok=True)

# ── Chart 1: Games Officiated — Top 20 Referees ──
top20 = pivot.head(20).copy()
x = range(len(top20))
w = 0.35

fig, ax = plt.subplots(figsize=(16, 6))
ax.bar([i - w/2 for i in x], top20["Regular_Season_games_officiated"], w,
       label="Regular Season", color="#1d428a")
ax.bar([i + w/2 for i in x], top20["Playoffs_games_officiated"], w,
       label="Playoffs", color="#c8102e")
ax.set_xticks(list(x))
ax.set_xticklabels(top20["referee"], rotation=45, ha="right", fontsize=9)
ax.set_title("Top 20 Referees — Games Officiated", fontsize=14, fontweight="bold")
ax.set_ylabel("Games")
ax.legend()
plt.tight_layout()
plt.savefig(f"{CHARTS_DIR}/games_officiated.png", dpi=150, bbox_inches="tight")
plt.show()
print(f"✅ Saved {CHARTS_DIR}/games_officiated.png")

# ── Chart 2: Home Win % by Referee (30+ Regular Season games) ──
rs = pivot[pivot["Regular_Season_games_officiated"] >= 30].copy()
rs = rs.sort_values("Regular_Season_home_win_pct", ascending=True)

colors = [
    "#c8102e" if v > 55
    else "#1d428a" if v < 45
    else "#888888"
    for v in rs["Regular_Season_home_win_pct"]
]

fig, ax = plt.subplots(figsize=(10, 12))
ax.barh(rs["referee"], rs["Regular_Season_home_win_pct"], color=colors)
ax.axvline(50, color="black", linestyle="--", linewidth=1.5, label="50% neutral line")
ax.set_title(
    "Home Win % by Referee — Regular Season\n(min. 30 games | red = above 55% | blue = below 45%)",
    fontsize=12, fontweight="bold"
)
ax.set_xlabel("Home Win %")
ax.legend()
plt.tight_layout()
plt.savefig(f"{CHARTS_DIR}/home_win_pct.png", dpi=150, bbox_inches="tight")
plt.show()
print(f"✅ Saved {CHARTS_DIR}/home_win_pct.png")

# ── Chart 3: Winner vs Loser Foul Distribution (20+ Regular Season games) ──
rs = pivot[pivot["Regular_Season_games_officiated"] >= 20].copy()

fig, ax = plt.subplots(figsize=(11, 8))
ax.scatter(
    rs["Regular_Season_avg_winner_foul_pct"],
    rs["Regular_Season_avg_loser_foul_pct"],
    s=rs["Regular_Season_games_officiated"] * 3,
    alpha=0.75, color="#1d428a", edgecolors="white", linewidth=0.6
)
for _, row in rs.iterrows():
    ax.annotate(
        row["referee"].split()[-1],
        (row["Regular_Season_avg_winner_foul_pct"], row["Regular_Season_avg_loser_foul_pct"]),
        fontsize=7.5, alpha=0.85
    )
ax.axvline(50, color="red", linestyle="--", alpha=0.4, label="50% line")
ax.axhline(50, color="red", linestyle="--", alpha=0.4)
ax.set_xlabel("Avg Winner Foul % of Total Fouls")
ax.set_ylabel("Avg Loser Foul % of Total Fouls")
ax.set_title(
    "Winner vs Loser Foul Distribution by Referee\nBubble size = games officiated",
    fontsize=12, fontweight="bold"
)
ax.legend()
plt.tight_layout()
plt.savefig(f"{CHARTS_DIR}/foul_scatter.png", dpi=150, bbox_inches="tight")
plt.show()
print(f"✅ Saved {CHARTS_DIR}/foul_scatter.png")

print("\n✅ All done. Output CSV and 3 charts saved.")
