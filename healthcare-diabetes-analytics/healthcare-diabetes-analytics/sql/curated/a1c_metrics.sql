-- =============================================================================
-- Curated Table: a1c_metrics
-- Database: healthcare_project_2026_raw_data
-- Location: s3://healthcareproject-patient-data-2025/Curated/a1c_metrics/
-- Format: Parquet
--
-- Description: Aggregated A1C lab metrics per patient. Contains latest,
--              first, average, max, and min A1C values with reading counts,
--              date ranges, and risk category classification.
--
-- Data Quality Checks Embedded:
--   check_1_a1c_clinical_range : A1C must be between 3.0 and 20.0%
--   check_2_null_patient_id    : Patient ID must not be null
--   check_3_zero_readings      : Total readings must be > 0
--
-- Source Table: observations
-- Run Order: 1 of 3
-- =============================================================================

CREATE TABLE healthcare_project_2026_raw_data.a1c_metrics
WITH (
    format = 'PARQUET',
    external_location = 's3://healthcareproject-patient-data-2025/Curated/a1c_metrics/'
)
AS
WITH a1c_data AS (
    SELECT
        patient,
        CAST(value AS DOUBLE)        AS a1c_value,
        from_iso8601_timestamp(date) AS reading_date
    FROM healthcare_project_2026_raw_data.observations
    WHERE description = 'Hemoglobin A1c/Hemoglobin.total in Blood'
      AND value IS NOT NULL
)
SELECT
    patient                                             AS patient_id,
    ROUND(MAX_BY(a1c_value, reading_date), 2)          AS latest_a1c,
    ROUND(MIN_BY(a1c_value, reading_date), 2)          AS first_a1c,
    ROUND(AVG(a1c_value), 2)                           AS average_a1c,
    ROUND(MAX(a1c_value), 2)                           AS max_a1c,
    ROUND(MIN(a1c_value), 2)                           AS min_a1c,
    COUNT(*)                                           AS total_readings,
    CAST(MAX(reading_date) AS VARCHAR)                 AS latest_reading_date,
    CAST(MIN(reading_date) AS VARCHAR)                 AS first_reading_date,
    CASE
        WHEN MAX_BY(a1c_value, reading_date) >= 6.5
            THEN 'Diabetic Range'
        WHEN MAX_BY(a1c_value, reading_date) BETWEEN 5.7 AND 6.4
            THEN 'Prediabetic Range'
        ELSE 'Normal Range'
    END                                                AS latest_a1c_category,
    -- Check 1: A1C values outside clinical range (3.0 - 20.0%)
    CASE
        WHEN MIN(a1c_value) < 3.0 OR MAX(a1c_value) > 20.0
            THEN 'FAIL - A1C outside clinical range (3.0-20.0)'
        ELSE 'PASS'
    END                                                AS check_1_a1c_clinical_range,
    -- Check 2: Null patient IDs
    CASE
        WHEN patient IS NULL
            THEN 'FAIL - Null patient ID'
        ELSE 'PASS'
    END                                                AS check_2_null_patient_id,
    -- Check 3: Zero or negative readings
    CASE
        WHEN COUNT(*) <= 0
            THEN 'FAIL - Zero or negative readings'
        ELSE 'PASS'
    END                                                AS check_3_zero_readings
FROM a1c_data
GROUP BY patient;

