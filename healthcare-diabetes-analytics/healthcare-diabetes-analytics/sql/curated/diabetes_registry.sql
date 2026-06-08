-- =============================================================================
-- Curated Table: diabetes_registry
-- Database: healthcare_project_2026_raw_data
-- Location: s3://healthcareproject-patient-data-2025/Curated/diabetes_registry/
-- Format: Parquet
--
-- Description: Patient demographics enriched with diabetes/prediabetes flags
--              derived from the conditions table. Includes generational cohort
--              classification, age calculation, race normalization, and
--              earliest diagnosis date.
--
-- Data Quality Checks Embedded:
--   check_4_null_patient_id  : Patient ID must not be null
--   check_5_future_birthdate : Birthdate must not be in the future
--   check_6_invalid_flags    : Diabetes/prediabetes flags must be 0 or 1
--   check_7_invalid_age      : Age must be between 0 and 120
--
-- Source Tables: patients, conditions
-- Run Order: 2 of 3
-- =============================================================================

CREATE TABLE healthcare_project_2026_raw_data.diabetes_registry
WITH (
    format = 'PARQUET',
    external_location = 's3://healthcareproject-patient-data-2025/Curated/diabetes_registry/'
)
AS
SELECT
    p.id                                               AS patient_id,
    p.first,
    p.last,
    p.gender,
    p.birthdate,
    date_diff('year',
        CAST(p.birthdate AS DATE),
        current_date)                                  AS age,
    CASE
        WHEN LOWER(p.race) = 'hawaiian' THEN 'Polynesian'
        ELSE p.race
    END                                                AS race,
    p.ethnicity,
    p.city,
    p.state,
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
    END                                                AS generation,
    MIN(
        CASE
            WHEN LOWER(c.description) LIKE '%diabet%'
              OR LOWER(c.description) LIKE '%prediab%'
            THEN c.start
        END
    )                                                  AS diagnosis_date,
    MAX(
        CASE
            WHEN LOWER(c.description) LIKE '%prediab%'
            THEN 1 ELSE 0
        END
    )                                                  AS prediabetes_flag,
    MAX(
        CASE
            WHEN LOWER(c.description) LIKE '%diabet%'
             AND LOWER(c.description) NOT LIKE '%prediab%'
            THEN 1 ELSE 0
        END
    )                                                  AS diabetes_flag,
    -- Check 4: Null patient IDs
    CASE
        WHEN p.id IS NULL
            THEN 'FAIL - Null patient ID'
        ELSE 'PASS'
    END                                                AS check_4_null_patient_id,
    -- Check 5: Future birthdates
    CASE
        WHEN CAST(p.birthdate AS DATE) > current_date
            THEN 'FAIL - Future birthdate'
        ELSE 'PASS'
    END                                                AS check_5_future_birthdate,
    -- Check 6: Invalid flag values (must be 0 or 1)
    CASE
        WHEN MAX(
                CASE WHEN LOWER(c.description) LIKE '%diabet%'
                      AND LOWER(c.description) NOT LIKE '%prediab%'
                     THEN 1 ELSE 0 END
             ) NOT IN (0, 1)
          OR MAX(
                CASE WHEN LOWER(c.description) LIKE '%prediab%'
                     THEN 1 ELSE 0 END
             ) NOT IN (0, 1)
            THEN 'FAIL - Invalid flag value'
        ELSE 'PASS'
    END                                                AS check_6_invalid_flags,
    -- Check 7: Negative or impossible age
    CASE
        WHEN date_diff('year', CAST(p.birthdate AS DATE), current_date) < 0
          OR date_diff('year', CAST(p.birthdate AS DATE), current_date) > 120
            THEN 'FAIL - Invalid age'
        ELSE 'PASS'
    END                                                AS check_7_invalid_age
FROM healthcare_project_2026_raw_data.patients p
LEFT JOIN healthcare_project_2026_raw_data.conditions c
    ON p.id = c.patient
GROUP BY
    p.id, p.first, p.last, p.gender, p.birthdate,
    p.race, p.ethnicity, p.city, p.state;

