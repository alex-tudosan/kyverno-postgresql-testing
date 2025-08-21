#!/bin/bash

# Phase 1 End-to-End Test Script
# This script tests all components of the Phase 1 setup

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test logging functions
test_log() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

test_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

test_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
}

test_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Load configuration
if [[ -f "config.sh" ]]; then
    source config.sh
else
    test_failure "Configuration file config.sh not found"
    exit 1
fi

# Test counter
PASSED=0
FAILED=0
WARNINGS=0

# Test function
run_test() {
    local test_name="$1"
    local test_command="$2"
    local test_description="$3"
    
    test_log "Running: $test_name - $test_description"
    
    if eval "$test_command" >/dev/null 2>&1; then
        test_success "$test_name passed"
        ((PASSED++))
    else
        test_failure "$test_name failed"
        ((FAILED++))
    fi
}

# Test AWS connectivity
test_aws_connectivity() {
    run_test "AWS Connectivity" \
        "aws sts get-caller-identity --profile $AWS_PROFILE" \
        "Verify AWS credentials are working"
}

# Test EKS cluster status
test_eks_cluster() {
    run_test "EKS Cluster Status" \
        "aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE --query 'cluster.status' --output text | grep -q 'ACTIVE'" \
        "Verify EKS cluster is active"
}

# Test EKS nodes
test_eks_nodes() {
    run_test "EKS Nodes Ready" \
        "kubectl get nodes --no-headers | grep -c 'Ready' | grep -q '^[1-9]'" \
        "Verify EKS nodes are ready"
}

# Test RDS instance
test_rds_instance() {
    run_test "RDS Instance Status" \
        "aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --region $AWS_REGION --profile $AWS_PROFILE --query 'DBInstances[0].DBInstanceStatus' --output text | grep -q 'available'" \
        "Verify RDS instance is available"
}

# Test database connectivity
test_database_connectivity() {
    local endpoint
    endpoint=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --region $AWS_REGION --profile $AWS_PROFILE --query 'DBInstances[0].Endpoint.Address' --output text)
    
    run_test "Database Connectivity" \
        "PGPASSWORD=$DB_PASSWORD psql -h $endpoint -U $DB_USERNAME -d $DB_NAME -c 'SELECT 1;'" \
        "Verify database connectivity"
}

# Test Kyverno pods
test_kyverno_pods() {
    run_test "Kyverno Pods Running" \
        "kubectl get pods -n kyverno --no-headers | grep -c 'Running' | grep -q '^[1-9]'" \
        "Verify Kyverno pods are running"
}

# Test Reports Server
test_reports_server() {
    run_test "Reports Server Running" \
        "kubectl get pods -n kyverno -l app.kubernetes.io/component=reports-server --no-headers | grep -q 'Running'" \
        "Verify Reports Server is running"
}

# Test Kyverno policies
test_kyverno_policies() {
    run_test "Kyverno Policies Active" \
        "kubectl get clusterpolicies --no-headers | wc -l | grep -q '^[1-9]'" \
        "Verify Kyverno policies are active"
}

# Test monitoring stack
test_monitoring_stack() {
    run_test "Monitoring Stack Running" \
        "kubectl get pods -n monitoring --no-headers | grep -c 'Running' | grep -q '^[1-9]'" \
        "Verify monitoring stack is running"
}

# Test ServiceMonitors
test_servicemonitors() {
    run_test "ServiceMonitors Applied" \
        "kubectl get servicemonitors -n monitoring | grep -E '(kyverno|reports-server)'" \
        "Verify ServiceMonitors are applied"
}

# Test Grafana access
test_grafana_access() {
    run_test "Grafana Service" \
        "kubectl get svc -n monitoring monitoring-grafana" \
        "Verify Grafana service exists"
}

# Test Prometheus access
test_prometheus_access() {
    run_test "Prometheus Service" \
        "kubectl get svc -n monitoring prometheus-operated" \
        "Verify Prometheus service exists"
}

# Test policy enforcement
test_policy_enforcement() {
    # Create a test pod that should be blocked by policies
    cat << EOF | kubectl apply -f - >/dev/null 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: test-policy-enforcement
  namespace: default
spec:
  containers:
  - name: test
    image: nginx:latest
    securityContext:
      privileged: true
EOF
    
    # Check if pod was created (should be blocked)
    if kubectl get pod test-policy-enforcement -n default >/dev/null 2>&1; then
        test_warning "Policy enforcement test - pod was created (policies may not be enforcing)"
        ((WARNINGS++))
    else
        test_success "Policy enforcement working - privileged pod was blocked"
        ((PASSED++))
    fi
    
    # Cleanup
    kubectl delete pod test-policy-enforcement -n default >/dev/null 2>&1 || true
}

# Test Reports Server logs
test_reports_server_logs() {
    local reports_pod
    reports_pod=$(kubectl get pods -n kyverno -l app.kubernetes.io/component=reports-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$reports_pod" ]]; then
        run_test "Reports Server Logs" \
            "kubectl logs -n kyverno $reports_pod --tail=10 | grep -q -E '(database|connected|ready)'" \
            "Verify Reports Server logs show database connectivity"
    else
        test_warning "Reports Server pod not found for log testing"
        ((WARNINGS++))
    fi
}

# Main test execution
main() {
    echo "🧪 Starting Phase 1 End-to-End Tests"
    echo "====================================="
    echo ""
    
    # Load kubeconfig
    if ! aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE >/dev/null 2>&1; then
        test_failure "Failed to update kubeconfig"
        exit 1
    fi
    
    # Run all tests
    test_aws_connectivity
    test_eks_cluster
    test_eks_nodes
    test_rds_instance
    test_database_connectivity
    test_kyverno_pods
    test_reports_server
    test_kyverno_policies
    test_monitoring_stack
    test_servicemonitors
    test_grafana_access
    test_prometheus_access
    test_policy_enforcement
    test_reports_server_logs
    
    # Summary
    echo ""
    echo "📊 Test Summary"
    echo "==============="
    echo "✅ Passed: $PASSED"
    echo "❌ Failed: $FAILED"
    echo "⚠️  Warnings: $WARNINGS"
    echo ""
    
    if [[ $FAILED -eq 0 ]]; then
        test_success "All critical tests passed! Phase 1 setup is working correctly."
        exit 0
    else
        test_failure "Some tests failed. Please check the setup."
        exit 1
    fi
}

# Run main function
main "$@"
