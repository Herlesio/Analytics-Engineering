# Architecture Documentation

## Overview

This project implements a **medallion architecture** on AWS — a layered data lake pattern where data flows from raw ingestion through curated analytical tables. The pipeline is fully serverless; no EC2 instances, EMR clusters, or running infrastructure are required outside of query execution time.

---

## Data Source

**Synthea** is an open-source synthetic patient data generator developed by MITRE Corporation. It produces realistic but entirely fictional EHR (Electronic Health Record) data that mirrors real-world healthcare datasets.

**Version used:** `synthea_sample_data_csv_nov2021`
**Format:** CSV files
**Key tables used:** `patients`, `conditions`, `observations`

Synthea data is widely used in healthcare data engineering portfolio projects because:
- It is publicly available and free
- It is safe to share publicly (no real patient data)
- It mirrors real EHR schemas (FHIR-aligned)
- It contains realistic clinical patterns including A1C lab values and condition diagnoses

---

## S3 Bucket Structure

**Bucket name:** `healthcareproject-patient-data-2025`
**Region:** `us-west-2` (Oregon)

```
healthcareproject-patient-data-2025/
│
├── raw_data/                        ← Bronze layer: original CSV files
│   ├── patients/
│   │   └── patients.csv
│   ├── conditions/
│   │   └── conditions.csv
│   └── observations/
│       └── observations.csv
│
└── Curated/                         ← Gold layer: transformed Parquet tables
    ├── a1c_metrics/
    │   └── *.parquet
    ├── diabetes_registry/
    │   └── *.parquet
    ├── patient_summary/
    │   └── *.parquet
    └── athena_results/              ← Athena query output location
```

**Why separate raw and curated?**
Following the medallion architecture pattern ensures:
- Raw data is never modified — always reprocessable
- Curated data is optimized for analytical queries
- Cost control — Parquet reduces Athena scan costs vs CSV

---

## IAM Role

**Role name:** `AWSGlueServiceRole-HealthCareProject2025`

**Policy 1 — S3 Read Access (scoped to project bucket):**
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": [
                "arn:aws:s3:::healthcareproject-patient-data-2025",
                "arn:aws:s3:::healthcareproject-patient-data-2025/*"
            ]
        }
    ]
}
```

**Policy 2 — AWS Glue Service Policy:**
Standard Glue service permissions including Glue API access, S3 bucket management for Glue temp storage, EC2 networking for Glue connections, IAM role introspection, and CloudWatch log writing.

**Security design:** Policy 1 is explicitly scoped to the project bucket only — following least-privilege IAM best practices. The Glue crawler cannot access any other S3 buckets in the account.

---

## AWS Glue

### Database
**Name:** `healthcare_project_2026_raw_data`
**S3 URI:** `s3://healthcareproject-patient-data-2025/raw_data/`

### Crawler
The Glue Crawler was configured to crawl the `raw_data/` prefix. On completion it:
- Inferred column names and data types from the CSV files
- Registered three tables in the Glue Data Catalog: `patients`, `conditions`, `observations`
- Made all three tables immediately queryable via Amazon Athena

**Why use a crawler instead of manual table definitions?**
For a dataset with 9+ columns per table, manual DDL is error-prone. The crawler handles type inference automatically and updates schemas if the source data changes.

---

## Amazon Athena

Athena uses the Glue Data Catalog as its metastore. All queries run against:
- **Database:** `healthcare_project_2026_raw_data`
- **Workgroup:** `primary`
- **Output location:** `s3://healthcareproject-patient-data-2025/Curated/athena_results/`

### View: patient_diabetes_summary

A virtual view (no physical storage) that joins all three raw tables and applies clinical classification logic. Used as the development blueprint before curated tables were built.

**CTE structure:**
```
latest_a1c          → Most recent A1C per patient from observations
condition_flags     → Diabetes/prediabetes flags from conditions
classified_patients → Full patient profile with status
Final SELECT        → Filtered to non-null diabetes_status only
```

### CTAS: Create Table As Select

All three curated tables were created using Athena's CTAS feature with:
```sql
CREATE TABLE table_name
WITH (
    format = 'PARQUET',
    external_location = 's3://...'
)
AS SELECT ...
```

This writes Parquet files directly to S3 and registers the table in the Glue Data Catalog simultaneously — no ETL job or PySpark required for this dataset size.

---

## Curated Table Dependencies

```
observations ──────────────────────────────────► a1c_metrics
                                                      │
patients ──────────────────────────────────────────► │
         +                                            │
conditions ────────────────────────► diabetes_registry│
                                            │         │
                                            └────┬────┘
                                                 │
                                                 ▼
                                          patient_summary
                                    (primary dashboard table)
```

**Run order is mandatory:**
1. `a1c_metrics` — no upstream curated dependencies
2. `diabetes_registry` — no upstream curated dependencies
3. `patient_summary` — JOINs both tables above

---

## Data Quality Implementation

Data quality is implemented at two levels:

### Level 1 — Standalone Validation Queries
10 SQL queries run manually in Athena to inspect bad records. Each query targets a specific rule and is expected to return 0 rows on clean data.

### Level 2 — Embedded Quality Columns
Each curated table contains `check_N_*` columns that label every row as `PASS` or `FAIL - [reason]`. This pattern:
- Preserves flagged records (production pipelines never silently delete)
- Enables dashboard-level quality monitoring
- Provides per-patient auditability
- Allows downstream consumers to filter by quality status

### Quality Check Results Summary

| Table | Check | Finding |
|---|---|---|
| a1c_metrics | A1C clinical range (3.0–20.0%) | 15 patients FAIL — Synthea artifact |
| a1c_metrics | Null patient IDs | 0 failures |
| a1c_metrics | Zero readings | 0 failures |
| diabetes_registry | Null patient IDs | 0 failures |
| diabetes_registry | Future birthdates | 0 failures |
| diabetes_registry | Invalid flag values | 0 failures |
| diabetes_registry | Invalid age | 0 failures |
| patient_summary | Invalid diabetes status | 0 failures |
| patient_summary | A1C category mismatch | 0 failures |
| patient_summary | Missing A1C data | 0 failures |

**Check 1 finding detail:** 15 patients had A1C readings below 3.0% — clinically impossible. This is a known artifact of Synthea's synthetic data generation. In a production environment this would trigger an upstream data investigation. Here, records are flagged and retained.

---

## Dashboards

### Amazon QuickSight
- **Connection:** Athena via Glue Data Catalog
- **Dataset:** `patient_summary` (primary), `a1c_metrics` (secondary)
- **Caching:** SPICE enabled
- **Visuals:** KPI cards, donut chart, bar charts, heat map, scatter plot

---

## Cost Estimate

For a dataset of this size (< 100MB total) all services fall within free tier or minimal cost:

| Service | Estimated Cost |
|---|---|
| S3 Storage | < $0.01/month |
| Glue Crawler | Free tier (first million objects/month) |
| Athena Queries | < $0.01 total (CSV scan on small dataset) |
| QuickSight | Free 30-day trial |

**Total estimated project cost: < $1.00**

