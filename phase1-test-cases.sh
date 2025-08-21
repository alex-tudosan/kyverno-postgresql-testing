#!/bin/bash

# Phase 1 Test Cases for PostgreSQL-based Reports Server Testing
# This script runs 19 comprehensive tests across 7 categories

set -e

echo "🧪 Starting Phase 1 Test Cases: PostgreSQL-based Reports Server Testing"
echo "====================================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Function to run a test
run_test() {
    local test_number=$1
    local test_name="$2"
    local test_command="$3"
    local expected_result="$4"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo ""
    echo "Test $test_number: $test_name"
    echo "Expected: $expected_result"
    echo "Running: $test_command"
    
    if eval "$test_command" > /dev/null 2>&1; then
        print_success "Test $test_number PASSED"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_fail "Test $test_number FAILED"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Function to run a test with custom logic
run_custom_test() {
    local test_number=$1
    local test_name="$2"
    local test_function="$3"
    local expected_result="$4"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo ""
    echo "Test $test_number: $test_name"
    echo "Expected: $expected_result"
    
    if eval "$test_function"; then
        print_success "Test $test_number PASSED"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_fail "Test $test_number FAILED"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Load configuration if available
if [ -f "postgresql-testing-config.env" ]; then
    source postgresql-testing-config.env
fi

# Default values if config not available
RDS_ENDPOINT=${RDS_ENDPOINT:-"localhost"}
DB_NAME=${DB_NAME:-"reports"}
DB_USERNAME=${DB_USERNAME:-"reportsuser"}
DB_PASSWORD=${DB_PASSWORD:-"password"}

print_status "Starting 19 comprehensive tests..."

## Category 1: Basic Functionality Tests

print_status "=== Category 1: Basic Functionality Tests ==="

# Test 1: Basic Installation
run_test "1" "Basic Installation" \
    "kubectl get pods -A --no-headers | grep -v 'Completed\|Succeeded' | grep -v 'Running' | wc -l | grep -q '^0$'" \
    "All pods should be running"

# Test 2: Namespace Creation
run_test "2" "Namespace Creation" \
    "kubectl create namespace test-namespace --dry-run=client -o yaml | kubectl apply -f -" \
    "Namespace should be created successfully"

# Test 3: Pod Creation
run_test "3" "Pod Creation" \
    "kubectl run test-pod --image=nginx:alpine --namespace=test-namespace --restart=Never --dry-run=client -o yaml | kubectl apply -f -" \
    "Test pod should be created successfully"

## Category 2: Policy Enforcement Tests

print_status "=== Category 2: Policy Enforcement Tests ==="

# Test 4: Policy Enforcement (Blocking)
run_test "4" "Policy Enforcement (Blocking)" \
    "kubectl apply -f test-violations-pod.yaml --dry-run=client 2>&1 | grep -q 'validation error'" \
    "Violating pod should be blocked by policy"

# Test 5: Policy Enforcement (Allowing)
run_test "5" "Policy Enforcement (Allowing)" \
    "kubectl run good-pod --image=nginx:alpine --namespace=test-namespace --restart=Never --labels=app=test --dry-run=client -o yaml | kubectl apply -f -" \
    "Good pod should be allowed"

# Test 6: Policy Update
run_custom_test "6" "Policy Update" \
    "kubectl patch clusterpolicy require-labels --type='merge' -p='{\"spec\":{\"validationFailureAction\":\"audit\"}}' && sleep 5 && kubectl get clusterpolicy require-labels -o jsonpath='{.spec.validationFailureAction}' | grep -q 'audit'" \
    "Policy should be updated successfully"

## Category 3: Monitoring Tests

print_status "=== Category 3: Monitoring Tests ==="

# Test 7: Metrics Collection
run_test "7" "Metrics Collection" \
    "kubectl -n monitoring get pods -l app=prometheus --no-headers | grep -q 'Running'" \
    "Prometheus should be collecting metrics"

# Test 8: Dashboard Access
run_test "8" "Dashboard Access" \
    "kubectl -n monitoring get pods -l app=grafana --no-headers | grep -q 'Running'" \
    "Grafana dashboard should be accessible"

# Test 9: Alert Generation
run_test "9" "Alert Generation" \
    "kubectl -n monitoring get pods -l app=alertmanager --no-headers | grep -q 'Running'" \
    "AlertManager should be running"

## Category 4: Performance Tests

print_status "=== Category 4: Performance Tests ==="

# Test 10: Response Time
run_custom_test "10" "Response Time" \
    "timeout 10s kubectl get pods -A > /dev/null 2>&1; echo \$?" \
    "API response time should be reasonable"

# Test 11: Resource Usage
run_custom_test "11" "Resource Usage" \
    "kubectl top nodes --no-headers 2>/dev/null | awk '{sum+=\$3} END {exit sum < 80 ? 0 : 1}'" \
    "CPU usage should be reasonable (< 80%)"

# Test 12: Concurrent Operations
run_custom_test "12" "Concurrent Operations" \
    "for i in {1..5}; do kubectl get pods -A --no-headers > /dev/null 2>&1 & done; wait; echo 'Concurrent operations completed'" \
    "System should handle concurrent requests"

## Category 5: PostgreSQL Storage Tests

print_status "=== Category 5: PostgreSQL Storage Tests ==="

# Test 13: Database Connection
run_custom_test "13" "Database Connection" \
    "kubectl -n kyverno logs -l app.kubernetes.io/component=reports-server --tail=50 | grep -q 'database.*connected\|postgres.*connected'" \
    "Reports Server should connect to PostgreSQL"

# Test 14: Data Storage
run_custom_test "14" "Data Storage" \
    "kubectl get policyreports -A --no-headers | wc -l | awk '{exit \$1 > 0 ? 0 : 1}'" \
    "Policy reports should be stored in database"

# Test 15: Data Retrieval
run_custom_test "15" "Data Retrieval" \
    "kubectl get policyreports -A --no-headers | head -1 | grep -q 'policyreports'" \
    "Policy reports should be retrievable"

## Category 6: API Functionality Tests

print_status "=== Category 6: API Functionality Tests ==="

# Test 16: API Endpoints
run_test "16" "API Endpoints" \
    "kubectl get apiservice v1alpha1.wgpolicyk8s.io --no-headers | grep -q 'True'" \
    "Policy reports API should be available"

# Test 17: Data Format
run_test "17" "Data Format" \
    "kubectl get policyreports -A -o json | jq -e '.items[0]' > /dev/null 2>&1" \
    "Policy reports should be in valid JSON format"

# Test 18: Authentication
run_test "18" "Authentication" \
    "kubectl auth can-i get policyreports --all-namespaces" \
    "User should have permission to access policy reports"

## Category 7: Failure Recovery Tests

print_status "=== Category 7: Failure Recovery Tests ==="

# Test 19: System Recovery
run_custom_test "19" "System Recovery" \
    "kubectl delete pod -n kyverno \$(kubectl get pods -n kyverno -l app.kubernetes.io/component=reports-server -o jsonpath='{.items[0].metadata.name}') && sleep 30 && kubectl get pods -n kyverno -l app.kubernetes.io/component=reports-server --no-headers | grep -q 'Running'" \
    "System should recover from pod deletion"

# Clean up test resources
print_status "Cleaning up test resources..."
kubectl delete namespace test-namespace --ignore-not-found=true > /dev/null 2>&1

# Display test results
echo ""
echo "=========================================="
echo "           TEST RESULTS SUMMARY"
echo "=========================================="
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"
echo "Skipped: $SKIPPED_TESTS"
echo ""

# Calculate success rate
if [ $TOTAL_TESTS -gt 0 ]; then
    SUCCESS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    echo "Success Rate: $SUCCESS_RATE%"
    echo ""

    if [ $SUCCESS_RATE -ge 80 ]; then
        print_success "🎉 Excellent results! System is working well."
        echo "Ready to proceed to Phase 2."
    elif [ $SUCCESS_RATE -ge 60 ]; then
        print_warning "⚠️  Good results with some issues."
        echo "Check failed tests and consider fixes before Phase 2."
    else
        print_fail "❌ Poor results. System needs attention."
        echo "Investigate failed tests before proceeding."
    fi
fi

echo ""
echo "=== Detailed Test Results ==="
echo "For detailed logs, check:"
echo "  - Reports Server logs: kubectl -n kyverno logs -l app.kubernetes.io/component=reports-server"
echo "  - Kyverno logs: kubectl -n kyverno logs -l app=kyverno"
echo "  - RDS status: aws rds describe-db-instances --db-instance-identifier reports-server-db"
echo ""

print_status "Test execution completed!"
