-- ═══════════════════════════════════════════════════════════
-- NBA Player Archetype System — Analysis Queries
-- ═══════════════════════════════════════════════════════════
-- Run these in the Databricks SQL Editor against the output table:
-- players_categorization.reclassification.player_archetype_system
--
-- Note: column names are snake_case (e.g. avg_points, role_classification)
-- since the script cleans column names before saving to Delta.

-- ── 1. Role breakdown ──
-- After running: click "+" below results → Bar Chart
-- X: role_classification | Y: COUNT(*)
SELECT role_classification, COUNT(*) AS player_count
FROM players_categorization.reclassification.player_archetype_system
WHERE season_type = 'Regular Season'
GROUP BY role_classification
ORDER BY player_count DESC;


-- ── 2. Superstars ranked by points ──
SELECT player_name, position, avg_points, avg_minutes, games_played,
       scoring_label, rebounding_label, playmaking_label
FROM players_categorization.reclassification.player_archetype_system
WHERE role_classification = 'Superstar'
  AND season_type = 'Regular Season'
ORDER BY avg_points DESC;


-- ── 3. Players who elevated most in the playoffs (scoring) ──
-- Shows big-game performers vs players who shrank under pressure
SELECT
    rs.player_name,
    rs.role_classification,
    rs.position,
    ROUND(rs.scoring_percentile, 1)  AS rs_scoring_pct,
    ROUND(po.scoring_percentile, 1)  AS po_scoring_pct,
    ROUND(po.scoring_percentile - rs.scoring_percentile, 1) AS scoring_delta
FROM players_categorization.reclassification.player_archetype_system rs
JOIN players_categorization.reclassification.player_archetype_system po
    ON rs.person_id = po.person_id
WHERE rs.season_type = 'Regular Season'
  AND po.season_type = 'Playoffs'
  AND po.scoring_percentile IS NOT NULL
ORDER BY scoring_delta DESC
LIMIT 20;


-- ── 4. Best playmakers by position ──
-- After running: click "+" → Bar Chart → X: player_name, Y: ast_per_36, Group: position
SELECT player_name, position, role_classification,
       ast_per_36, playmaking_percentile, playmaking_label
FROM players_categorization.reclassification.player_archetype_system
WHERE season_type = 'Regular Season'
  AND playmaking_label IN ('Elite Playmaker', 'Great Playmaker')
ORDER BY playmaking_percentile DESC
LIMIT 30;


-- ── 5. High-minute, low-scoring starters (defensive anchors) ──
-- Reveals players like Draymond Green and Andre Roberson —
-- high role importance (minutes) without high point totals
SELECT player_name, position, avg_minutes, avg_points,
       role_classification, scoring_label, rebounding_label, playmaking_label
FROM players_categorization.reclassification.player_archetype_system
WHERE season_type = 'Regular Season'
  AND role_classification IN ('Starter', 'All-Star', 'Superstar')
  AND avg_points < 10
ORDER BY avg_minutes DESC;


-- ── 6. Players who declined most in the playoffs (scoring) ──
-- The inverse of query 3 — reveals who shrinks under playoff pressure
SELECT
    rs.player_name,
    rs.role_classification,
    rs.position,
    ROUND(rs.scoring_percentile, 1)  AS rs_scoring_pct,
    ROUND(po.scoring_percentile, 1)  AS po_scoring_pct,
    ROUND(po.scoring_percentile - rs.scoring_percentile, 1) AS scoring_delta
FROM players_categorization.reclassification.player_archetype_system rs
JOIN players_categorization.reclassification.player_archetype_system po
    ON rs.person_id = po.person_id
WHERE rs.season_type = 'Regular Season'
  AND po.season_type = 'Playoffs'
  AND po.scoring_percentile IS NOT NULL
ORDER BY scoring_delta ASC
LIMIT 20;
