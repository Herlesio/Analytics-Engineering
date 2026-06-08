-- =============================================================================
-- View: patient_diabetes_summary
-- Database: healthcare_project_2026_raw_data
-- Description: Main analytical view joining patients, conditions, and
--              observations to classify each patient as Diabetic or
--              Prediabetic based on diagnosed conditions and A1C lab values.
--
-- Clinical Thresholds (ADA Standards):
--   Diabetes:    A1C >= 6.5%
--   Prediabetes: A1C between 5.7% and 6.4%
--
-- Dependencies: patients, conditions, observations (raw tables)
-- =============================================================================

CREATE OR REPLACE VIEW patient_diabetes_summary AS

-- CTE 1: Most recent A1C reading per patient
WITH latest_a1c AS (
    SELECT
        patient,
        MAX_BY(
            CAST(value AS DOUBLE),
            from_iso8601_timestamp(date)
        ) AS latest_a1c
    FROM observations
    WHERE description = 'Hemoglobin A1c/Hemoglobin.total in Blood'
    GROUP BY patient
),

-- CTE 2: Diabetes/prediabetes flags and earliest diagnosis date per patient
condition_flags AS (
    SELECT
        patient,
        MAX(
            CASE
                WHEN lower(description) LIKE '%prediab%'
                THEN 1
                ELSE 0
            END
        ) AS prediabetes_flag,
        MAX(
            CASE
                WHEN lower(description) LIKE '%diabet%'
                     AND lower(description) NOT LIKE '%prediab%'
                THEN 1
                ELSE 0
            END
        ) AS diabetes_flag,
        MIN(
            CASE
                WHEN lower(description) LIKE '%diabet%'
                  OR lower(description) LIKE '%prediab%'
                THEN start
            END
        ) AS diagnosis_date
    FROM conditions
    GROUP BY patient
),

-- CTE 3: Full patient profile with demographics and resolved diabetes status
classified_patients AS (
    SELECT
        p.id,
        p.first,
        p.last,
        p.gender,
        CASE
            WHEN lower(p.race) = 'hawaiian'
                THEN 'Polynesian'
            ELSE p.race
        END AS race,
        p.ethnicity,
        p.city,
        p.state,
        p.birthdate,
        CASE
            WHEN year(CAST(p.birthdate AS DATE)) BETWEEN 1946 AND 1964
                THEN 'Baby Boomers'
            WHEN year(CAST(p.birthdate AS DATE)) BETWEEN 1965 AND 1980
                THEN 'Generation X'
            WHEN year(CAST(p.birthdate AS DATE)) BETWEEN 1981 AND 1996
                THEN 'Millennials (Gen Y)'
            WHEN year(CAST(p.birthdate AS DATE)) BETWEEN 1997 AND 2012
                THEN 'Generation Z'
            WHEN year(CAST(p.birthdate AS DATE)) >= 2013
                THEN 'Generation Alpha'
            ELSE 'Other'
        END AS generation,
        cf.diagnosis_date,
        COALESCE(cf.diabetes_flag, 0)    AS diabetes_flag,
        COALESCE(cf.prediabetes_flag, 0) AS prediabetes_flag,
        a.latest_a1c,
        CASE
            WHEN COALESCE(cf.diabetes_flag, 0) = 1   THEN 'Diabetes'
            WHEN a.latest_a1c >= 6.5                  THEN 'Diabetes'
            WHEN COALESCE(cf.prediabetes_flag, 0) = 1 THEN 'Prediabetes'
            WHEN a.latest_a1c BETWEEN 5.7 AND 6.4     THEN 'Prediabetes'
        END AS diabetes_status
    FROM patients p
    LEFT JOIN condition_flags cf ON p.id = cf.patient
    LEFT JOIN latest_a1c a       ON p.id = a.patient
)

SELECT
    id,
    first,
    last,
    gender,
    race,
    ethnicity,
    city,
    state,
    birthdate,
    generation,
    diagnosis_date,
    latest_a1c,
    diabetes_status
FROM classified_patients
WHERE diabetes_status IS NOT NULL;

