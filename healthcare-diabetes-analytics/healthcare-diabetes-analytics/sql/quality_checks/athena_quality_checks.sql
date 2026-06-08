-- =============================================================================
-- Data Quality Checks — Standalone Validation Queries
-- Database: healthcare_project_2026_raw_data
--
-- Description: 10 standalone Athena SQL queries validating data quality
--              across the three curated tables. Run these before connecting
--              dashboards to ensure data integrity.
--
-- Expected outcome: All checks return 0 rows or 0 counts except Check 1
--                   which identifies 15 Synthea data artifacts.
--
-- These checks are also embedded as dedicated columns in each curated
-- table (check_1_* through check_10_*) for ongoing per-row monitoring.
-- =============================================================================


-- =============================================================================
-- a1c_metrics — Checks 1 through 3
-- =============================================================================

-- Check 1: A1C values outside clinical range (3.0% - 20.0%)
-- Finding: 15 patients with A1C < 3.0% — Synthea synthetic data artifact
-- Action: Records flagged as FAIL and retained (not deleted)
SELECT patient_id, latest_a1c, max_a1c, min_a1c
FROM healthcare_project_2026_raw_data.a1c_metrics
WHERE latest_a1c < 3.0 OR latest_a1c > 20.0
   OR max_a1c    < 3.0 OR max_a1c    > 20.0
   OR min_a1c    < 3.0 OR min_a1c    > 20.0;


-- Check 2: Null patient IDs in a1c_metrics
-- Expected result: 0
SELECT COUNT(*) AS null_patient_ids
FROM healthcare_project_2026_raw_data.a1c_metrics
WHERE patient_id IS NULL;


-- Check 3: Zero or negative reading counts
-- Expected result: 0 rows
SELECT patient_id, total_readings
FROM healthcare_project_2026_raw_data.a1c_metrics
WHERE total_readings <= 0;


-- =============================================================================
-- diabetes_registry — Checks 4 through 7
-- =============================================================================

-- Check 4: Null patient IDs in diabetes_registry
-- Expected result: 0
SELECT COUNT(*) AS null_patient_ids
FROM healthcare_project_2026_raw_data.diabetes_registry
WHERE patient_id IS NULL;


-- Check 5: Future birthdates
-- Expected result: 0 rows
SELECT patient_id, birthdate
FROM healthcare_project_2026_raw_data.diabetes_registry
WHERE CAST(birthdate AS DATE) > current_date;


-- Check 6: Invalid flag values (must be 0 or 1 only)
-- Expected result: 0 rows
SELECT patient_id, diabetes_flag, prediabetes_flag
FROM healthcare_project_2026_raw_data.diabetes_registry
WHERE diabetes_flag    NOT IN (0, 1)
   OR prediabetes_flag NOT IN (0, 1);


-- Check 7: Negative or impossible age (valid range: 0-120)
-- Expected result: 0 rows
SELECT patient_id, age
FROM healthcare_project_2026_raw_data.diabetes_registry
WHERE age < 0 OR age > 120;


-- =============================================================================
-- patient_summary — Checks 8 through 10
-- =============================================================================

-- Check 8: Invalid diabetes_status values
-- Only 'Diabetes' or 'Prediabetes' are valid (nulls filtered in WHERE clause)
-- Expected result: 0 rows
SELECT diabetes_status, COUNT(*) AS total
FROM healthcare_project_2026_raw_data.patient_summary
WHERE diabetes_status NOT IN ('Diabetes', 'Prediabetes')
   OR diabetes_status IS NULL
GROUP BY diabetes_status;


-- Check 9: A1C value and category mismatch
-- Verifies that latest_a1c_category correctly reflects latest_a1c value
-- Expected result: 0 rows
SELECT patient_id, latest_a1c, latest_a1c_category
FROM healthcare_project_2026_raw_data.patient_summary
WHERE (latest_a1c >= 6.5       AND latest_a1c_category != 'Diabetic Range')
   OR (latest_a1c BETWEEN 5.7
       AND 6.4                 AND latest_a1c_category != 'Prediabetic Range')
   OR (latest_a1c < 5.7        AND latest_a1c_category != 'Normal Range');


-- Check 10: Patients with diabetes status but missing A1C data
-- Expected result: 0
SELECT COUNT(*) AS missing_a1c
FROM healthcare_project_2026_raw_data.patient_summary
WHERE latest_a1c IS NULL;


-- =============================================================================
-- Full Quality Summary Report — All 10 Checks in One Query
-- Run this after table creation to get a complete quality overview
-- =============================================================================

SELECT 'a1c_metrics'       AS table_name,
       'check_1_a1c_clinical_range' AS check_name,
       check_1_a1c_clinical_range   AS result,
       COUNT(*)                     AS total
FROM healthcare_project_2026_raw_data.a1c_metrics
GROUP BY check_1_a1c_clinical_range

UNION ALL

SELECT 'a1c_metrics', 'check_2_null_patient_id',
       check_2_null_patient_id, COUNT(*)
FROM healthcare_project_2026_raw_data.a1c_metrics
GROUP BY check_2_null_patient_id

UNION ALL

SELECT 'a1c_metrics', 'check_3_zero_readings',
       check_3_zero_readings, COUNT(*)
FROM healthcare_project_2026_raw_data.a1c_metrics
GROUP BY check_3_zero_readings

UNION ALL

SELECT 'diabetes_registry', 'check_4_null_patient_id',
       check_4_null_patient_id, COUNT(*)
FROM healthcare_project_2026_raw_data.diabetes_registry
GROUP BY check_4_null_patient_id

UNION ALL

SELECT 'diabetes_registry', 'check_5_future_birthdate',
       check_5_future_birthdate, COUNT(*)
FROM healthcare_project_2026_raw_data.diabetes_registry
GROUP BY check_5_future_birthdate

UNION ALL

SELECT 'diabetes_registry', 'check_6_invalid_flags',
       check_6_invalid_flags, COUNT(*)
FROM healthcare_project_2026_raw_data.diabetes_registry
GROUP BY check_6_invalid_flags

UNION ALL

SELECT 'diabetes_registry', 'check_7_invalid_age',
       check_7_invalid_age, COUNT(*)
FROM healthcare_project_2026_raw_data.diabetes_registry
GROUP BY check_7_invalid_age

UNION ALL

SELECT 'patient_summary', 'check_8_invalid_diabetes_status',
       check_8_invalid_diabetes_status, COUNT(*)
FROM healthcare_project_2026_raw_data.patient_summary
GROUP BY check_8_invalid_diabetes_status

UNION ALL

SELECT 'patient_summary', 'check_9_a1c_category_mismatch',
       check_9_a1c_category_mismatch, COUNT(*)
FROM healthcare_project_2026_raw_data.patient_summary
GROUP BY check_9_a1c_category_mismatch

UNION ALL

SELECT 'patient_summary', 'check_10_missing_a1c',
       check_10_missing_a1c, COUNT(*)
FROM healthcare_project_2026_raw_data.patient_summary
GROUP BY check_10_missing_a1c

ORDER BY table_name, check_name, result;

