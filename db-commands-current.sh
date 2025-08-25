#!/bin/bash

# Database Commands for Current Setup
# Generated on: $(date)
# RDS Endpoint: reports-server-db-20250824-082805.cgfhp1exibuy.us-west-1.rds.amazonaws.com
# Database: reportsdb
# Username: reportsuser

# Set database connection variables
DB_HOST="reports-server-db-20250824-082805.cgfhp1exibuy.us-west-1.rds.amazonaws.com"
DB_USER="reportsuser"
DB_NAME="reportsdb"
DB_PASSWORD="8b35b61237a1e049babb9ae526f6f1e1189dd4ca246dcd441f083e737c13871d"

echo "=== Kyverno Reports Server Database Commands ==="
echo "Database: $DB_HOST"
echo "Username: $DB_USER"
echo "Database: $DB_NAME"
echo ""

# Function to run a command and show its description
run_command() {
    local description="$1"
    local command="$2"
    
    echo "=== $description ==="
    echo "Command: $command"
    echo "Result:"
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "$command"
    echo ""
}

# 1. Connect & List Tables
run_command "Connect & List Tables" "\dt"

# 2. Count Total Reports
run_command "Count Total Reports" "SELECT COUNT(*) as total_policy_reports FROM policyreports;"

# 3. View Recent Reports
run_command "View Recent Reports" "SELECT name, namespace, report->>'summary' as summary FROM policyreports ORDER BY name DESC LIMIT 5;"

# 4. View Reports by Namespace
run_command "View Reports by Namespace" "SELECT namespace, COUNT(*) as report_count FROM policyreports GROUP BY namespace ORDER BY report_count DESC;"

# 5. View Failed Reports
run_command "View Failed Reports" "SELECT name, namespace, report->>'summary' as summary FROM policyreports WHERE (report->>'summary'->>'fail')::int > 0 ORDER BY name DESC LIMIT 10;"

# 6. View All Table Counts
run_command "All Table Counts" "SELECT 'policyreports' as table_name, COUNT(*) as count FROM policyreports UNION ALL SELECT 'clusterpolicyreports' as table_name, COUNT(*) as count FROM clusterpolicyreports UNION ALL SELECT 'ephemeralreports' as table_name, COUNT(*) as count FROM ephemeralreports UNION ALL SELECT 'clusterephemeralreports' as table_name, COUNT(*) as count FROM clusterephemeralreports;"

# 7. View Policy Results Summary
run_command "Policy Results Summary" "SELECT namespace, 
    SUM((report->>'summary'->>'pass')::int) as total_pass,
    SUM((report->>'summary'->>'fail')::int) as total_fail,
    SUM((report->>'summary'->>'skip')::int) as total_skip,
    SUM((report->>'summary'->>'warn')::int) as total_warn,
    SUM((report->>'summary'->>'error')::int) as total_error
FROM policyreports 
GROUP BY namespace 
ORDER BY total_fail DESC, total_pass DESC;"

# 8. View Recent Policy Violations
run_command "Recent Policy Violations" "SELECT name, namespace, 
    report->>'summary' as summary,
    report->>'scope'->>'kind' as resource_kind,
    report->>'scope'->>'name' as resource_name
FROM policyreports 
WHERE (report->>'summary'->>'fail')::int > 0 
ORDER BY name DESC 
LIMIT 10;"

echo "=== Individual Commands (for copy-paste) ==="
echo ""
echo "# 1. Connect & List Tables"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h \"$DB_HOST\" -U $DB_USER -d $DB_NAME -c \"\\dt\""
echo ""
echo "# 2. Count Total Reports"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h \"$DB_HOST\" -U $DB_USER -d $DB_NAME -c \"SELECT COUNT(*) as total_policy_reports FROM policyreports;\""
echo ""
echo "# 3. View Recent Reports"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h \"$DB_HOST\" -U $DB_USER -d $DB_NAME -c \"SELECT name, namespace, report->>'summary' as summary FROM policyreports ORDER BY name DESC LIMIT 5;\""
echo ""
echo "# 4. View Reports by Namespace"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h \"$DB_HOST\" -U $DB_USER -d $DB_NAME -c \"SELECT namespace, COUNT(*) as report_count FROM policyreports GROUP BY namespace ORDER BY report_count DESC;\""
echo ""
echo "# 5. View Failed Reports"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h \"$DB_HOST\" -U $DB_USER -d $DB_NAME -c \"SELECT name, namespace, report->>'summary' as summary FROM policyreports WHERE (report->>'summary'->>'fail')::int > 0 ORDER BY name DESC LIMIT 10;\""
echo ""
echo "# 6. Interactive Session"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h \"$DB_HOST\" -U $DB_USER -d $DB_NAME"
echo ""
echo "# 7. View All Tables"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h \"$DB_HOST\" -U $DB_USER -d $DB_NAME -c \"\\dt\""
echo ""
echo "# 8. View Table Structure"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h \"$DB_HOST\" -U $DB_USER -d $DB_NAME -c \"\\d policyreports\""
echo ""
echo "# 9. View Policy Results Summary"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h \"$DB_HOST\" -U $DB_USER -d $DB_NAME -c \"SELECT namespace, SUM((report->>'summary'->>'pass')::int) as total_pass, SUM((report->>'summary'->>'fail')::int) as total_fail FROM policyreports GROUP BY namespace ORDER BY total_fail DESC;\""
echo ""
echo "# 10. View Recent Violations with Resource Details"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h \"$DB_HOST\" -U $DB_USER -d $DB_NAME -c \"SELECT name, namespace, report->>'scope'->>'kind' as resource_kind, report->>'scope'->>'name' as resource_name, report->>'summary' as summary FROM policyreports WHERE (report->>'summary'->>'fail')::int > 0 ORDER BY name DESC LIMIT 10;\""
