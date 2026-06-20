-- ═══════════════════════════════════════════════════════════
-- NBA Player Archetype System — Table Setup
-- ═══════════════════════════════════════════════════════════
-- Run this once before running player_archetype_system.py
-- in your Databricks notebook.

-- Create catalog and schema
CREATE CATALOG IF NOT EXISTS players_categorization;
CREATE SCHEMA IF NOT EXISTS players_categorization.reclassification;

-- The source tables (player_statistics_extended, players) and the
-- output table (player_archetype_system) are created by running
-- player_archetype_system.py — not by this SQL file.

-- Verify all tables exist after running the script:
SHOW TABLES IN players_categorization.reclassification;
