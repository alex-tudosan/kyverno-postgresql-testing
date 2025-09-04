#!/bin/bash

# Script to add Policy Reports Time-Series Panel to Grafana Dashboard
# This script will add the new panel to your existing dashboard

echo "=== ADDING POLICY REPORTS TIME-SERIES PANEL TO GRAFANA ==="

# Check if Grafana port-forward is running
if ! pgrep -f "port-forward.*grafana" > /dev/null; then
    echo "Starting Grafana port-forward..."
    kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80 &
    sleep 3
fi

# Get the current dashboard
echo "Fetching current dashboard configuration..."
DASHBOARD_JSON=$(curl -s "http://admin:prom-operator@localhost:3000/api/dashboards/uid/kyverno-testing-dashboard-fixed" 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "Error: Could not fetch dashboard. Please check:"
    echo "1. Grafana is accessible at http://localhost:3000"
    echo "2. Dashboard UID is correct"
    echo "3. Credentials are correct"
    exit 1
fi

# Extract dashboard ID and version
DASHBOARD_ID=$(echo "$DASHBOARD_JSON" | jq -r '.dashboard.id')
DASHBOARD_VERSION=$(echo "$DASHBOARD_JSON" | jq -r '.dashboard.version')

echo "Dashboard ID: $DASHBOARD_ID"
echo "Dashboard Version: $DASHBOARD_VERSION"

# Read the new panel JSON
NEW_PANEL_JSON=$(cat grafana/policy-reports-growth-panel.json)

# Add the new panel to the dashboard
echo "Adding new panel to dashboard..."
UPDATED_DASHBOARD=$(echo "$DASHBOARD_JSON" | jq --argjson newPanel "$NEW_PANEL_JSON" '.dashboard.panels += [$newPanel]')

# Update version
UPDATED_DASHBOARD=$(echo "$UPDATED_DASHBOARD" | jq '.dashboard.version = (.dashboard.version | tonumber + 1)')

# Save updated dashboard
echo "Saving updated dashboard..."
echo "$UPDATED_DASHBOARD" > grafana/updated-dashboard-with-policy-panel.json

echo "✅ Panel configuration prepared!"
echo ""
echo "To add this panel to your dashboard:"
echo "1. Open Grafana at http://localhost:3000"
echo "2. Go to your dashboard"
echo "3. Click 'Add panel' or 'Edit'"
echo "4. Copy the content from: grafana/policy-reports-growth-panel.json"
echo "5. Or use the prepared dashboard: grafana/updated-dashboard-with-policy-panel.json"
echo ""
echo "The panel will show:"
echo "- Policy Reports (Green line)"
echo "- Ephemeral Reports (Blue line)" 
echo "- Cluster Policy Reports (Orange line)"
echo "- Cluster Ephemeral Reports (Red line)"
echo ""
echo "All with absolute numbers over time!"



