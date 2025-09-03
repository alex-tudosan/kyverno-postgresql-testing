# Grafana Monitoring Setup for Kyverno + PostgreSQL

## 🎯 Overview
This folder contains all Grafana-related configurations for monitoring your Kyverno + PostgreSQL RDS testing environment.

## 📁 File Structure
- `kyverno-testing-comprehensive-dashboard.json` - Main dashboard (original)
- `kyverno-testing-comprehensive-dashboard-fixed.json` - Fixed version with correct query format
- `simple-test-dashboard.json` - Simple test dashboard for basic metrics
- `debug-dashboard.json` - Debug dashboard for troubleshooting
- `postgresql-datasource-grafana.yaml` - PostgreSQL data source configuration
- `kyverno-alerts.yaml` - Prometheus alerting rules
- `kyverno-servicemonitor.yaml` - ServiceMonitor for Kyverno metrics
- `reports-server-servicemonitor.yaml` - ServiceMonitor for Reports Server metrics
- `setup-grafana-dashboard.sh` - Automated setup script

## 🔧 Recent Fixes Applied

### **Query Format Fix**
- **Problem**: Dashboard panels showed "No data" despite working API queries
- **Root Cause**: Panels used `expr` format, but PostgreSQL plugin requires `rawSql` format
- **Solution**: Updated all PostgreSQL panels to use:
  ```json
  {
    "refId": "A",
    "datasource": {"type": "grafana-postgresql-datasource", "uid": "PCC52D03280B7034C"},
    "rawQuery": true,
    "rawSql": "SELECT COUNT(*) as count FROM policyreports",
    "format": "table"
  }
  ```

### **Data Source Reference Fix**
- **Problem**: Panels referenced `"datasource": "PostgreSQL"`
- **Solution**: Use proper UID reference: `"datasource": {"type": "grafana-postgresql-datasource", "uid": "PCC52D03280B7034C"}`

### **Load Test Namespaces Query Fix**
- **Problem**: `LIKE '%load-test-%'` returned 0 results
- **Solution**: Changed to `LIKE 'load-test-%'` (removed leading wildcard)

## 🚀 Setup Instructions

### **1. Import the Fixed Dashboard**
```bash
# Import the fixed comprehensive dashboard
curl -X POST -H "Content-Type: application/json" \
  -d @kyverno-testing-comprehensive-dashboard-fixed.json \
  -u "admin:${GRAFANA_PASSWORD}" \
  "http://localhost:3000/api/dashboards/import"
```

### **2. Verify Data Source**
```bash
# Check PostgreSQL data source health
curl -u "admin:${GRAFANA_PASSWORD}" \
  "http://localhost:3000/api/datasources/3/health"
```

### **3. Test Queries**
```bash
# Test basic query
curl -X POST -H "Content-Type: application/json" \
  -d '{"queries":[{"refId":"A","datasource":{"type":"grafana-postgresql-datasource","uid":"PCC52D03280B7034C"},"rawQuery":true,"rawSql":"SELECT COUNT(*) as count FROM clusterpolicyreports","format":"table"}]}' \
  -u "admin:${GRAFANA_PASSWORD}" \
  "http://localhost:3000/api/ds/query"
```

## 📊 Expected Results

**After applying fixes, you should see:**
- **Policy Reports Count**: 48
- **Cluster Policy Reports**: 57
- **Load Test Namespaces**: 50
- **Database Performance**: Actual database size
- **Policy Violations**: Count of failed policies

## 🔍 Troubleshooting

### **"No data" in PostgreSQL Panels**
1. Verify data source health: `/api/datasources/{id}/health`
2. Check query format uses `rawSql`, not `expr`
3. Ensure proper data source UID reference
4. Test query via API first: `/api/ds/query`

### **Load Test Namespaces Shows 0**
1. Verify namespaces exist: `kubectl get clusterpolicyreports | grep load-test`
2. Use exact query: `LIKE 'load-test-%'` (no leading wildcard)
3. Check database table structure

## 📈 Next Steps
1. Import the fixed comprehensive dashboard
2. Verify all panels show data
3. Run test plan to generate monitoring data
4. Monitor progress in real-time via Grafana

---
*Last Updated: 2025-09-02 - Applied query format fixes*
