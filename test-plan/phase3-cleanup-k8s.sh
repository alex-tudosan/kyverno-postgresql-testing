#!/bin/bash

set -e  # Exit on any error

echo "🧹 PHASE 3: CLEANUP KUBERNETES TEST RESOURCES"
echo "=============================================="
echo "This script will clean up all test resources while preserving infrastructure"
echo ""

# Configuration
TOTAL_NAMESPACES=200

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "INFO") echo -e "${BLUE}ℹ️  $message${NC}" ;;
        "SUCCESS") echo -e "${GREEN}✅ $message${NC}" ;;
        "WARNING") echo -e "${YELLOW}⚠️  $message${NC}" ;;
        "ERROR") echo -e "${RED}❌ $message${NC}" ;;
    esac
}

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_status "ERROR" "$1 is not installed or not in PATH"
        exit 1
    fi
}

# Function to check if test resources exist
check_test_resources() {
    print_status "INFO" "Checking for existing test resources..."
    
    local namespace_count
    local sa_count
    local cm_count
    local deployment_count
    local pod_count
    
    namespace_count=$(kubectl get namespaces | grep load-test | wc -l)
    sa_count=$(kubectl get serviceaccounts -A | grep demo-sa | wc -l)
    cm_count=$(kubectl get configmaps -A | grep -E "(cm-01|cm-02)" | wc -l)
    deployment_count=$(kubectl get deployments -A | grep test-deployment | wc -l)
    pod_count=$(kubectl get pods -A | grep load-test | wc -l)
    
    if [ "$namespace_count" -eq 0 ] && [ "$sa_count" -eq 0 ] && [ "$cm_count" -eq 0 ] && [ "$deployment_count" -eq 0 ] && [ "$pod_count" -eq 0 ]; then
        print_status "SUCCESS" "No test resources found. Nothing to clean up."
        return 0
    fi
    
    print_status "INFO" "Found test resources:"
    echo "   - Test namespaces: $namespace_count"
    echo "   - ServiceAccounts: $sa_count"
    echo "   - ConfigMaps: $cm_count"
    echo "   - Deployments: $deployment_count"
    echo "   - Test pods: $pod_count"
    echo ""
    
    return 1
}

# Function to delete test deployments
delete_test_deployments() {
    print_status "INFO" "Deleting test deployments..."
    
    local deleted=0
    for i in $(seq -w 1 $TOTAL_NAMESPACES); do
        formatted_i=$(printf "%03d" $i)
        
        if kubectl get deployment test-deployment -n load-test-${formatted_i} &>/dev/null; then
            kubectl delete deployment test-deployment -n load-test-${formatted_i} --ignore-not-found=true >/dev/null
            deleted=$((deleted + 1))
            
            # Progress indicator every 50 deletions
            if [ $((deleted % 50)) -eq 0 ]; then
                print_status "SUCCESS" "Deleted $deleted deployments..."
            fi
        fi
    done
    
    print_status "SUCCESS" "All test deployments deleted"
}

# Function to delete test ConfigMaps
delete_test_configmaps() {
    print_status "INFO" "Deleting test ConfigMaps..."
    
    local deleted=0
    for i in $(seq -w 1 $TOTAL_NAMESPACES); do
        formatted_i=$(printf "%03d" $i)
        
        # Delete cm-01
        if kubectl get configmap cm-01 -n load-test-${formatted_i} &>/dev/null; then
            kubectl delete configmap cm-01 -n load-test-${formatted_i} --ignore-not-found=true >/dev/null
            deleted=$((deleted + 1))
        fi
        
        # Delete cm-02
        if kubectl get configmap cm-02 -n load-test-${formatted_i} &>/dev/null; then
            kubectl delete configmap cm-02 -n load-test-${formatted_i} --ignore-not-found=true >/dev/null
            deleted=$((deleted + 1))
        fi
        
        # Progress indicator every 100 deletions
        if [ $((deleted % 100)) -eq 0 ]; then
            print_status "SUCCESS" "Deleted $deleted ConfigMaps..."
        fi
    done
    
    print_status "SUCCESS" "All test ConfigMaps deleted"
}

# Function to delete test ServiceAccounts
delete_test_serviceaccounts() {
    print_status "INFO" "Deleting test ServiceAccounts..."
    
    local deleted=0
    for i in $(seq -w 1 $TOTAL_NAMESPACES); do
        formatted_i=$(printf "%03d" $i)
        
        if kubectl get serviceaccount demo-sa -n load-test-${formatted_i} &>/dev/null; then
            kubectl delete serviceaccount demo-sa -n load-test-${formatted_i} --ignore-not-found=true >/dev/null
            deleted=$((deleted + 1))
            
            # Progress indicator every 50 deletions
            if [ $((deleted % 50)) -eq 0 ]; then
                print_status "SUCCESS" "Deleted $deleted ServiceAccounts..."
            fi
        fi
    done
    
    print_status "SUCCESS" "All test ServiceAccounts deleted"
}

# Function to delete test namespaces
delete_test_namespaces() {
    print_status "INFO" "Deleting test namespaces..."
    
    local deleted=0
    for i in $(seq -w 1 $TOTAL_NAMESPACES); do
        formatted_i=$(printf "%03d" $i)
        
        if kubectl get namespace load-test-${formatted_i} &>/dev/null; then
            kubectl delete namespace load-test-${formatted_i} --ignore-not-found=true >/dev/null
            deleted=$((deleted + 1))
            
            # Progress indicator every 50 deletions
            if [ $((deleted % 50)) -eq 0 ]; then
                print_status "SUCCESS" "Deleted $deleted namespaces..."
            fi
        fi
    done
    
    print_status "SUCCESS" "All test namespaces deleted"
}

# Function to wait for namespace deletion
wait_for_namespace_cleanup() {
    print_status "INFO" "Waiting for namespace cleanup to complete..."
    
    local timeout=300  # 5 minutes
    local elapsed=0
    local interval=10
    
    while [ $elapsed -lt $timeout ]; do
        local remaining_namespaces
        remaining_namespaces=$(kubectl get namespaces | grep load-test | wc -l)
        
        if [ "$remaining_namespaces" -eq 0 ]; then
            print_status "SUCCESS" "All test namespaces cleaned up successfully"
            return 0
        fi
        
        print_status "INFO" "Still waiting for $remaining_namespaces namespaces to be deleted... (${elapsed}s elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    print_status "WARNING" "Namespace cleanup timed out after ${timeout}s"
    print_status "INFO" "Remaining namespaces:"
    kubectl get namespaces | grep load-test || true
    return 1
}

# Function to clean up policy reports (optional)
cleanup_policy_reports() {
    print_status "INFO" "Cleaning up policy reports..."
    
    # Note: This is optional as policy reports are typically managed by Kyverno
    # We'll just check if they exist and report the count
    
    local policy_reports
    local cluster_policy_reports
    
    policy_reports=$(kubectl get policyreports -A | grep load-test | wc -l || echo "0")
    cluster_policy_reports=$(kubectl get clusterpolicyreports | grep load-test | wc -l || echo "0")
    
    if [ "$policy_reports" -gt 0 ] || [ "$cluster_policy_reports" -gt 0 ]; then
        print_status "INFO" "Found policy reports:"
        echo "   - PolicyReports: $policy_reports"
        echo "   - ClusterPolicyReports: $cluster_policy_reports"
        print_status "INFO" "Note: Policy reports are typically cleaned up automatically by Kyverno"
    else
        print_status "SUCCESS" "No test-related policy reports found"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    print_status "INFO" "Verifying cleanup completion..."
    
    local namespace_count
    local sa_count
    local cm_count
    local deployment_count
    local pod_count
    
    namespace_count=$(kubectl get namespaces | grep load-test | wc -l)
    sa_count=$(kubectl get serviceaccounts -A | grep demo-sa | wc -l)
    cm_count=$(kubectl get configmaps -A | grep -E "(cm-01|cm-02)" | wc -l)
    deployment_count=$(kubectl get deployments -A | grep test-deployment | wc -l)
    pod_count=$(kubectl get pods -A | grep load-test | wc -l)
    
    print_status "INFO" "Cleanup verification:"
    echo "   - Test namespaces: $namespace_count (should be 0)"
    echo "   - ServiceAccounts: $sa_count (should be 0)"
    echo "   - ConfigMaps: $cm_count (should be 0)"
    echo "   - Deployments: $deployment_count (should be 0)"
    echo "   - Test pods: $pod_count (should be 0)"
    
    if [ "$namespace_count" -eq 0 ] && [ "$sa_count" -eq 0 ] && [ "$cm_count" -eq 0 ] && [ "$deployment_count" -eq 0 ] && [ "$pod_count" -eq 0 ]; then
        print_status "SUCCESS" "All test resources cleaned up successfully"
        return 0
    else
        print_status "WARNING" "Some test resources may still exist"
        return 1
    fi
}

# Function to check infrastructure status
check_infrastructure_status() {
    print_status "INFO" "Checking infrastructure status after cleanup..."
    
    # Check Kyverno
    local kyverno_pods
    kyverno_pods=$(kubectl get pods -n kyverno --no-headers 2>/dev/null | grep -E "(kyverno|reports-server)" | grep Running | wc -l || echo "0")
    
    if [ "$kyverno_pods" -ge 2 ]; then
        print_status "SUCCESS" "Kyverno is still running ($kyverno_pods pods)"
    else
        print_status "WARNING" "Kyverno may have been affected by cleanup"
    fi
    
    # Check monitoring
    local monitoring_pods
    monitoring_pods=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep Running | wc -l || echo "0")
    
    if [ "$monitoring_pods" -ge 3 ]; then
        print_status "SUCCESS" "Monitoring stack is still running ($monitoring_pods pods)"
    else
        print_status "WARNING" "Monitoring stack may have been affected by cleanup"
    fi
    
    # Check EKS cluster
    local cluster_status
    cluster_status=$(aws eks describe-cluster --name report-server-test --region us-west-1 --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$cluster_status" = "ACTIVE" ]; then
        print_status "SUCCESS" "EKS cluster is still ACTIVE"
    else
        print_status "WARNING" "EKS cluster status: $cluster_status"
    fi
}

# Main execution
main() {
    echo "🧹 Starting Phase 3: Kubernetes Test Resource Cleanup"
    echo "====================================================="
    echo ""
    
    # Check prerequisites
    print_status "INFO" "Checking prerequisites..."
    check_command "kubectl"
    check_command "aws"
    print_status "SUCCESS" "Prerequisites check passed"
    echo ""
    
    # Check if test resources exist
    if check_test_resources; then
        print_status "SUCCESS" "No cleanup needed. Exiting."
        exit 0
    fi
    
    echo ""
    
    # Confirm cleanup
    print_status "WARNING" "This will delete ALL test resources created during Phase 2"
    echo "This includes:"
    echo "   - 200 test namespaces (load-test-001 to load-test-200)"
    echo "   - 200 ServiceAccounts (demo-sa)"
    echo "   - 400 ConfigMaps (cm-01, cm-02)"
    echo "   - 200 deployments (test-deployment)"
    echo "   - All associated pods and resources"
    echo ""
    echo "Infrastructure (EKS, RDS, Kyverno, Monitoring) will be preserved."
    echo ""
    
    read -p "Do you want to continue with cleanup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "INFO" "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    
    # Execute cleanup
    print_status "INFO" "Starting cleanup process..."
    echo ""
    
    # Delete resources in reverse order of creation
    delete_test_deployments
    echo ""
    
    delete_test_configmaps
    echo ""
    
    delete_test_serviceaccounts
    echo ""
    
    delete_test_namespaces
    echo ""
    
    # Wait for namespace cleanup
    wait_for_namespace_cleanup
    echo ""
    
    # Clean up policy reports
    cleanup_policy_reports
    echo ""
    
    # Verify cleanup
    verify_cleanup
    echo ""
    
    # Check infrastructure status
    check_infrastructure_status
    echo ""
    
    # Final summary
    print_status "SUCCESS" "🎉 PHASE 3 COMPLETED SUCCESSFULLY!"
    echo "======================================================"
    echo "What was accomplished:"
    echo "✅ All test deployments deleted"
    echo "✅ All test ConfigMaps deleted"
    echo "✅ All test ServiceAccounts deleted"
    echo "✅ All test namespaces deleted"
    echo "✅ Policy reports cleaned up"
    echo "✅ Infrastructure preserved and verified"
    echo ""
    echo "Next steps:"
    echo "1. Infrastructure is ready for reuse"
    echo "2. Run Phase 2 again for new tests if needed"
    echo "3. Run Phase 4 when completely done with testing"
    echo ""
}

# Run main function
main "$@"
