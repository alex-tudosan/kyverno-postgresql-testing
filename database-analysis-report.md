# Database Analysis Report - Kyverno Reports Server PostgreSQL

**Date**: 2025-08-24  
**Database**: reports-server-db-20250824-082805  
**Endpoint**: reports-server-db-20250824-082805.cgfhp1exibuy.us-west-1.rds.amazonaws.com

## Database Tables Created

The Reports Server has successfully created 4 tables in the PostgreSQL database:

1. **`policyreports`** - Main table for policy reports
2. **`clusterpolicyreports`** - Cluster-level policy reports  
3. **`ephemeralreports`** - Ephemeral policy reports
4. **`clusterephemeralreports`** - Cluster-level ephemeral reports

## Table Structure

### `policyreports` Table Schema
```sql
Table "public.policyreports"
  Column   |       Type        | Collation | Nullable | Default 
-----------+-------------------+-----------+----------+---------
 name      | character varying |           | not null | 
 namespace | character varying |           | not null | 
 clusterid | character varying |           | not null | 
 report    | jsonb             |           | not null | 

Indexes:
    "policyreports_pkey" PRIMARY KEY, btree (name, namespace, clusterid)
    "policyreportcluster" btree (clusterid)
    "policyreportnamespace" btree (namespace)
```

### Report JSON Structure
Each report contains:
- **`scope`** - Resource scope information
- **`results`** - Policy evaluation results
- **`summary`** - Summary statistics (pass, fail, skip, warn, error counts)

## Data Analysis

### Current Report Counts
- **Policy Reports**: 48 records
- **Cluster Policy Reports**: 0 records  
- **Ephemeral Reports**: 142 records
- **Cluster Ephemeral Reports**: 0 records

### Sample Policy Report Summary
```json
{
  "fail": 2,
  "pass": 0, 
  "skip": 0,
  "warn": 0,
  "error": 0
}
```

## Key Findings

✅ **Database Connection**: Reports Server successfully connected to PostgreSQL  
✅ **Table Creation**: All required tables created with proper schema  
✅ **Data Storage**: Policy reports are being stored with full JSON data  
✅ **Indexing**: Proper indexes on clusterid and namespace for performance  
✅ **Data Integrity**: Primary key constraints ensure data uniqueness  

## Sample Queries

### Count Total Policy Reports
```sql
SELECT COUNT(*) as total_policy_reports FROM policyreports;
```

### View Recent Reports with Summary
```sql
SELECT name, namespace, report->'summary' as summary 
FROM policyreports 
ORDER BY name DESC LIMIT 5;
```

### Reports by Namespace
```sql
SELECT namespace, COUNT(*) as report_count 
FROM policyreports 
GROUP BY namespace;
```

### Failed Policy Results
```sql
SELECT name, namespace, report->'summary'->>'fail' as failures
FROM policyreports 
WHERE (report->'summary'->>'fail')::int > 0;
```

## Conclusion

The Kyverno Reports Server is successfully:
- Storing policy reports in PostgreSQL
- Maintaining proper database schema
- Indexing data for efficient queries
- Preserving full policy evaluation details in JSON format

The setup is working correctly and policy reports are being generated and stored as expected.
