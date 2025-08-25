#!/bin/bash

# Database query script to run from within the cluster
# This avoids the external connection timeout issues

echo "=== Running Database Queries from within Cluster ==="
echo ""

# Function to run a query and show results
run_query() {
    local description="$1"
    local query="$2"
    
    echo "=== $description ==="
    echo "Query: $query"
    echo "Result:"
    
    kubectl run db-query --rm -i --tty --image postgres:14 -- bash -c "PGPASSWORD='8b35b61237a1e049babb9ae526f6f1e1189dd4ca246dcd441f083e737c13871d' psql -h 'reports-server-db-20250824-082805.cgfhp1exibuy.us-west-1.rds.amazonaws.com' -U reportsuser -d reportsdb -c '$query'" 2>/dev/null | grep -A 100 "Result:" | tail -n +2
    
    echo ""
    echo "---"
    echo ""
}

# 1. List Tables
run_query "List Tables" "\\dt"

# 2. Count Total Reports
run_query "Count Total Reports" "SELECT COUNT(*) as total_policy_reports FROM policyreports;"

# 3. View Recent Reports
run_query "View Recent Reports" "SELECT name, namespace, report->>'summary' as summary FROM policyreports ORDER BY name DESC LIMIT 5;"

# 4. View Reports by Namespace
run_query "View Reports by Namespace" "SELECT namespace, COUNT(*) as report_count FROM policyreports GROUP BY namespace ORDER BY report_count DESC;"

# 5. View Failed Reports
run_query "View Failed Reports" "SELECT name, namespace, report->>'summary' as summary FROM policyreports WHERE (report->>'summary'->>'fail')::int > 0 ORDER BY name DESC LIMIT 10;"

# 6. View All Table Counts
run_query "All Table Counts" "SELECT 'policyreports' as table_name, COUNT(*) as count FROM policyreports UNION ALL SELECT 'clusterpolicyreports' as table_name, COUNT(*) as count FROM clusterpolicyreports UNION ALL SELECT 'ephemeralreports' as table_name, COUNT(*) as count FROM ephemeralreports UNION ALL SELECT 'clusterephemeralreports' as table_name, COUNT(*) as count FROM clusterephemeralreports;"

echo "=== Database Query Complete ==="
