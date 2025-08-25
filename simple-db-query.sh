#!/bin/bash

echo "=== Database Query Results ==="
echo ""

# Create a temporary pod and run queries
kubectl run db-query-pod --rm -i --tty --image postgres:14 -- bash -c "
echo '=== Database Tables ==='
PGPASSWORD='8b35b61237a1e049babb9ae526f6f1e1189dd4ca246dcd441f083e737c13871d' psql -h 'reports-server-db-20250824-082805.cgfhp1exibuy.us-west-1.rds.amazonaws.com' -U reportsuser -d reportsdb -c '\dt'

echo ''
echo '=== Total Policy Reports ==='
PGPASSWORD='8b35b61237a1e049babb9ae526f6f1e1189dd4ca246dcd441f083e737c13871d' psql -h 'reports-server-db-20250824-082805.cgfhp1exibuy.us-west-1.rds.amazonaws.com' -U reportsuser -d reportsdb -c 'SELECT COUNT(*) as total_policy_reports FROM policyreports;'

echo ''
echo '=== Reports by Namespace ==='
PGPASSWORD='8b35b61237a1e049babb9ae526f6f1e1189dd4ca246dcd441f083e737c13871d' psql -h 'reports-server-db-20250824-082805.cgfhp1exibuy.us-west-1.rds.amazonaws.com' -U reportsuser -d reportsdb -c 'SELECT namespace, COUNT(*) as report_count FROM policyreports GROUP BY namespace ORDER BY report_count DESC;'

echo ''
echo '=== Recent Reports (Top 5) ==='
PGPASSWORD='8b35b61237a1e049babb9ae526f6f1e1189dd4ca246dcd441f083e737c13871d' psql -h 'reports-server-db-20250824-082805.cgfhp1exibuy.us-west-1.rds.amazonaws.com' -U reportsuser -d reportsdb -c 'SELECT name, namespace, report->>'summary' as summary FROM policyreports ORDER BY name DESC LIMIT 5;'

echo ''
echo '=== Failed Reports ==='
PGPASSWORD='8b35b61237a1e049babb9ae526f6f1e1189dd4ca246dcd441f083e737c13871d' psql -h 'reports-server-db-20250824-082805.cgfhp1exibuy.us-west-1.rds.amazonaws.com' -U reportsuser -d reportsdb -c 'SELECT name, namespace, report->>'summary' as summary FROM policyreports WHERE (report->>'summary'->>'fail')::int > 0 ORDER BY name DESC LIMIT 10;'
"
