# Kyverno Policy Reporting Test Plan

## Goal
Prove that policy results are generated, collected by the Report Server, stored in Postgres, and stay correct under a bit of load.

## Test Steps

### 1. Create Simple Policies
- Require namespace label (owner)
- Disallow privileged containers

### 2. Generate Test Data
- Create namespaces (some with labels, some without)
- Create deployments (some compliant, some non-compliant)
- Verify PolicyReports are generated

### 3. Verify End-to-End Flow
- Check Kubernetes PolicyReports
- Check Report Server (Postgres) records
- Verify data consistency

### 4. Test Updates and Churn
- Make changes to resources
- Verify reports update correctly

### 5. Scale Testing
- Add more namespaces/workloads in batches
- Stay under ~30 pods total

### 6. Soak Testing
- Run steady changes for 1-2 hours
- Monitor stability and performance

## Success Criteria
- Every test case creates PolicyReport entries in K8s and matching records in Report Server
- Updates reflected within 1-2 minutes
- No persistent errors in Kyverno or Report Server logs

