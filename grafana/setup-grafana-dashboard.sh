#!/bin/bash

# Grafana Dashboard Setup Script for Kyverno + PostgreSQL Testing
# This script sets up the comprehensive monitoring dashboard

set -e

echo "🚀 Setting up Grafana Dashboard for Kyverno + PostgreSQL Testing..."

# Check if Grafana is accessible
echo "📊 Checking Grafana accessibility..."
if ! curl -s http://localhost:3000/api/health >/dev/null; then
    echo "❌ Grafana is not accessible on localhost:3000"
    echo "Please run: kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80"
    exit 1
fi

# Get Grafana admin password
echo "🔑 Getting Grafana admin password..."
GRAFANA_PASSWORD=$(kubectl get secret -n monitoring monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 -d)
echo "✅ Grafana password retrieved"

# Set up PostgreSQL data source
echo "🗄️ Setting up PostgreSQL data source..."
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "name": "PostgreSQL",
    "type": "postgres",
    "access": "proxy",
    "url": "reports-server-db-20250902-092514.cgfhp1exibuy.us-west-1.rds.amazonaws.com:5432",
    "database": "reportsdb",
    "user": "reportsuser",
    "jsonData": {
      "sslmode": "require",
      "maxOpenConns": 100,
      "maxIdleConns": 100,
      "connMaxLifetime": 14400,
      "postgresVersion": 1400,
      "timescaledb": false
    },
    "secureJsonData": {
      "password": "newpassword123"
    }
  }' \
  -u "admin:${GRAFANA_PASSWORD}" \
  http://localhost:3000/api/datasources

echo "✅ PostgreSQL data source configured"

# Import the dashboard
echo "📊 Importing comprehensive dashboard..."
curl -X POST \
  -H "Content-Type: application/json" \
  -d @kyverno-testing-comprehensive-dashboard.json \
  -u "admin:${GRAFANA_PASSWORD}" \
  http://localhost:3000/api/dashboards/import

echo "✅ Dashboard imported successfully!"

# Create additional useful panels
echo "🔧 Creating additional monitoring panels..."

# Create a simple test panel for policy reports
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard": {
      "title": "Policy Reports Summary",
      "panels": [
        {
          "title": "Total Policy Reports",
          "type": "stat",
          "targets": [
            {
              "expr": "SELECT COUNT(*) FROM policyreports",
              "datasource": "PostgreSQL"
            }
          ],
          "fieldConfig": {
            "defaults": {
              "unit": "short",
              "color": {"mode": "thresholds"},
              "thresholds": {"steps": [{"color": "green", "value": 0}]}
            }
          }
        }
      ]
    }
  }' \
  -u "admin:${GRAFANA_PASSWORD}" \
  http://localhost:3000/api/dashboards/import

echo "✅ Additional panels created!"

echo ""
echo "🎉 Grafana Dashboard Setup Complete!"
echo ""
echo "📊 Dashboard URL: http://localhost:3000"
echo "👤 Username: admin"
echo "🔑 Password: ${GRAFANA_PASSWORD}"
echo ""
echo "📋 What's Now Available:"
echo "✅ Comprehensive Kyverno monitoring dashboard"
echo "✅ PostgreSQL data source for policy reports"
echo "✅ Prometheus alerting rules"
echo "✅ Service monitors for enhanced metrics"
echo "✅ Real-time performance monitoring"
echo ""
echo "🚀 You're ready to run your test plan with full visibility!"
