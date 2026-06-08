-- =============================================================================
-- Curated Table: patient_summary
-- Database: healthcare_project_2026_raw_data
-- Location: s3://healthcareproject-patient-data-2025/Curated/patient_summary/
-- Format: Parquet
--
-- Description: Master analytics table — the primary table used for dashboard
--              reporting in QuickSight and Tableau. Joins diabetes_registry
--              and a1c_metrics to produce a single complete patient record
--              with resolved diabetes status and A1C metrics.
--
-- Diabetes Status Resolution Order:
--   1. Diagnosed Diabetes  (diabetes_flag = 1)             → 'Diabetes'
--   2. A1C Diabetes        (latest_a1c >= 6.5%)            → 'Diabetes'
--   3. Diagnosed Prediab   (prediabetes_flag = 1)          → 'Prediabetes'
--   4. A1C Prediabetes     (5.7% <= latest_a1c <= 6.4%)    → 'Prediabetes'
--
-- Data Quality Checks Embedded:
--   check_8_invalid_diabetes_status : Status must be Diabetes or Prediabetes
--   check_9_a1c_category_mismatch   : A1C value must match category label
--   check_10_missing_a1c            : No missing A1C data for flagged patients
--
-- Dependencies: diabetes_registry, a1c_metrics (curated tables)
-- Run Order: 3 of 3
-- =============================================================================

CREATE TABLE healthcare_project_2026_raw_data.patient_summary
WITH (
    format = 'PARQUET',
    external_location = 's3://healthcareproject-patient-data-2025/Curated/patient_summary/'
)
AS
SELECT
    dr.patient_id,
    dr.first,
    dr.last,
    dr.gender,
    dr.age,
    dr.generation,
    dr.race,
    dr.ethnicity,
    dr.city,
    dr.state,
    dr.diagnosis_date,
    dr.diabetes_flag,
    dr.prediabetes_flag,
    am.latest_a1c,
    am.average_a1c,
    am.max_a1c,
    am.total_readings                                  AS total_a1c_readings,
    am.latest_reading_date                             AS last_a1c_date,
    am.latest_a1c_category,
    CASE
        WHEN dr.diabetes_flag = 1               THEN 'Diabetes'
        WHEN am.latest_a1c >= 6.5               THEN 'Diabetes'
        WHEN dr.prediabetes_flag = 1            THEN 'Prediabetes'
        WHEN am.latest_a1c BETWEEN 5.7 AND 6.4  THEN 'Prediabetes'
    END                                                AS diabetes_status,
    -- Check 8: Invalid diabetes_status values
    CASE
        WHEN CASE
                WHEN dr.diabetes_flag = 1               THEN 'Diabetes'
                WHEN am.latest_a1c >= 6.5               THEN 'Diabetes'
                WHEN dr.prediabetes_flag = 1            THEN 'Prediabetes'
                WHEN am.latest_a1c BETWEEN 5.7 AND 6.4  THEN 'Prediabetes'
             END NOT IN ('Diabetes', 'Prediabetes')
            THEN 'FAIL - Invalid diabetes status'
        ELSE 'PASS'
    END                                                AS check_8_invalid_diabetes_status,
    -- Check 9: A1C value must match A1C category label
    CASE
        WHEN am.latest_a1c >= 6.5
             AND am.latest_a1c_category != 'Diabetic Range'
            THEN 'FAIL - A1C category mismatch'
        WHEN am.latest_a1c BETWEEN 5.7 AND 6.4
             AND am.latest_a1c_category != 'Prediabetic Range'
            THEN 'FAIL - A1C category mismatch'
        WHEN am.latest_a1c < 5.7
             AND am.latest_a1c_category != 'Normal Range'
            THEN 'FAIL - A1C category mismatch'
        ELSE 'PASS'
    END                                                AS check_9_a1c_category_mismatch,
    -- Check 10: Patients with diabetes status but no A1C data
    CASE
        WHEN am.latest_a1c IS NULL
            THEN 'FAIL - Missing A1C data'
        ELSE 'PASS'
    END                                                AS check_10_missing_a1c
FROM healthcare_project_2026_raw_data.diabetes_registry dr
LEFT JOIN healthcare_project_2026_raw_data.a1c_metrics am
    ON dr.patient_id = am.patient_id
WHERE dr.diabetes_flag = 1
   OR dr.prediabetes_flag = 1
   OR am.latest_a1c >= 5.7;

