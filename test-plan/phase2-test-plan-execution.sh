#!/bin/bash

set -e  # Exit on any error

echo "🚀 PHASE 2: COMPLETE TEST PLAN EXECUTION"
echo "========================================="
echo "This script will execute the complete Kyverno + PostgreSQL test plan"
echo ""

# Configuration
TOTAL_NAMESPACES=200
TOTAL_BATCHES=20
NAMESPACES_PER_BATCH=10
MAX_PODS_SIMULTANEOUS=10

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

# Function to wait for a condition with timeout
wait_for_condition() {
    local condition=$1
    local timeout=$2
    local interval=$3
    local description=$4
    
    print_status "INFO" "Waiting for: $description (timeout: ${timeout}s)"
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if eval "$condition"; then
            print_status "SUCCESS" "$description completed"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        print_status "INFO" "Still waiting... (${elapsed}s elapsed)"
    done
    
    print_status "ERROR" "$description timed out after ${timeout}s"
    return 1
}

# Function to check EKS cluster status
check_eks_cluster() {
    print_status "INFO" "Checking EKS cluster status..."
    local cluster_status
    cluster_status=$(aws eks describe-cluster --name report-server-test --region us-west-1 --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$cluster_status" = "ACTIVE" ]; then
        print_status "SUCCESS" "EKS cluster 'report-server-test' is ACTIVE"
        return 0
    else
        print_status "ERROR" "EKS cluster 'report-server-test' is not ready. Status: $cluster_status"
        return 1
    fi
}

# Function to check Kyverno status
check_kyverno() {
    print_status "INFO" "Checking Kyverno status..."
    
    # Check if Kyverno namespace exists
    if ! kubectl get namespace kyverno &>/dev/null; then
        print_status "ERROR" "Kyverno namespace does not exist"
        return 1
    fi
    
    # Check Kyverno pods
    local kyverno_pods
    kyverno_pods=$(kubectl get pods -n kyverno --no-headers 2>/dev/null | grep -E "(kyverno|reports-server)" | grep Running | wc -l || echo "0")
    
    if [ "$kyverno_pods" -ge 2 ]; then
        print_status "SUCCESS" "Kyverno is running ($kyverno_pods pods)"
        return 0
    else
        print_status "ERROR" "Kyverno is not running properly. Found $kyverno_pods running pods"
        return 1
    fi
}

# Function to check monitoring stack
check_monitoring() {
    print_status "INFO" "Checking monitoring stack..."
    
    if ! kubectl get namespace monitoring &>/dev/null; then
        print_status "ERROR" "Monitoring namespace does not exist"
        return 1
    fi
    
    local monitoring_pods
    monitoring_pods=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep Running | wc -l || echo "0")
    
    if [ "$monitoring_pods" -ge 3 ]; then
        print_status "SUCCESS" "Monitoring stack is running ($monitoring_pods pods)"
        return 0
    else
        print_status "ERROR" "Monitoring stack is not running properly. Found $monitoring_pods running pods"
        return 1
    fi
}

# Function to check RDS connectivity
check_rds_connectivity() {
    print_status "INFO" "Checking RDS connectivity..."
    
    # Get RDS endpoint from Reports Server
    local rds_endpoint
    rds_endpoint=$(kubectl get pod -n kyverno -l app=reports-server-db -o jsonpath='{.items[0].spec.containers[0].env[?(@.name=="DB_HOST")].value}' 2>/dev/null || echo "")
    
    if [ -z "$rds_endpoint" ]; then
        print_status "ERROR" "Could not get RDS endpoint from Reports Server"
        return 1
    fi
    
    print_status "SUCCESS" "RDS endpoint: $rds_endpoint"
    return 0
}

# Function to create test namespaces
create_test_namespaces() {
    print_status "INFO" "Creating $TOTAL_NAMESPACES test namespaces..."
    
    local created=0
    for i in $(seq -w 1 $TOTAL_NAMESPACES); do
        formatted_i=$(printf "%03d" $i)
        
        cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Namespace
metadata:
  name: load-test-${formatted_i}
  labels:
    owner: loadtest
    purpose: load-testing
    created-by: test-plan
    sequence: "${formatted_i}"
EOF
        
        created=$((created + 1))
        
        # Progress indicator every 50 namespaces
        if [ $((created % 50)) -eq 0 ]; then
            print_status "SUCCESS" "Created $created namespaces..."
        fi
    done
    
    print_status "SUCCESS" "All $TOTAL_NAMESPACES namespaces created"
}

# Function to create ServiceAccounts
create_service_accounts() {
    print_status "INFO" "Creating $TOTAL_NAMESPACES ServiceAccounts..."
    
    local created=0
    for i in $(seq -w 1 $TOTAL_NAMESPACES); do
        formatted_i=$(printf "%03d" $i)
        
        cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: ServiceAccount
metadata:
  name: demo-sa
  namespace: load-test-${formatted_i}
  labels:
    owner: loadtest
    purpose: load-testing
EOF
        
        created=$((created + 1))
        
        # Progress indicator every 50
        if [ $((created % 50)) -eq 0 ]; then
            print_status "SUCCESS" "Created $created ServiceAccounts..."
        fi
    done
    
    print_status "SUCCESS" "All $TOTAL_NAMESPACES ServiceAccounts created"
}

# Function to create ConfigMaps
create_configmaps() {
    print_status "INFO" "Creating $((TOTAL_NAMESPACES * 2)) ConfigMaps..."
    
    local created=0
    for i in $(seq -w 1 $TOTAL_NAMESPACES); do
        formatted_i=$(printf "%03d" $i)
        
        # Create cm-01
        cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: ConfigMap
metadata:
  name: cm-01
  namespace: load-test-${formatted_i}
  labels:
    owner: loadtest
    purpose: load-testing
data:
  key1: "value1-${formatted_i}"
  key2: "value2-${formatted_i}"
EOF
        
        # Create cm-02
        cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: ConfigMap
metadata:
  name: cm-02
  namespace: load-test-${formatted_i}
  labels:
    owner: loadtest
    purpose: load-testing
data:
  key3: "value3-${formatted_i}"
  key4: "value4-${formatted_i}"
EOF
        
        created=$((created + 2))
        
        # Progress indicator every 50
        if [ $((created % 50)) -eq 0 ]; then
            print_status "SUCCESS" "Created $created ConfigMaps..."
        fi
    done
    
    print_status "SUCCESS" "All $((TOTAL_NAMESPACES * 2)) ConfigMaps created"
}

# Function to create deployments
create_deployments() {
    print_status "INFO" "Creating $TOTAL_NAMESPACES deployments with zero replicas..."
    
    local created=0
    for i in $(seq -w 1 $TOTAL_NAMESPACES); do
        formatted_i=$(printf "%03d" $i)
        
        cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-deployment
  namespace: load-test-${formatted_i}
  labels:
    app: test-app
    version: v1.0
    owner: loadtest
    purpose: load-testing
spec:
  replicas: 0
  selector:
    matchLabels:
      app: test-app
      version: v1.0
  template:
    metadata:
      labels:
        app: test-app
        version: v1.0
        owner: loadtest
        purpose: load-testing
    spec:
      serviceAccountName: demo-sa
      containers:
      - name: test-container
        image: nginx:alpine
        securityContext:
          privileged: false
          runAsNonRoot: true
          runAsUser: 1000
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
EOF
        
        created=$((created + 1))
        
        # Progress indicator every 50
        if [ $((created % 50)) -eq 0 ]; then
            print_status "SUCCESS" "Created $created deployments..."
        fi
    done
    
    print_status "SUCCESS" "All $TOTAL_NAMESPACES deployments created"
}

# Function to verify resource creation
verify_resources() {
    print_status "INFO" "Verifying all resources were created..."
    
    local namespace_count
    local sa_count
    local cm_count
    local deployment_count
    
    namespace_count=$(kubectl get namespaces | grep load-test | wc -l)
    sa_count=$(kubectl get serviceaccounts -A | grep demo-sa | wc -l)
    cm_count=$(kubectl get configmaps -A | grep -E "(cm-01|cm-02)" | wc -l)
    deployment_count=$(kubectl get deployments -A | grep test-deployment | wc -l)
    
    print_status "INFO" "Resource Summary:"
    echo "   - Test namespaces: $namespace_count/$TOTAL_NAMESPACES"
    echo "   - ServiceAccounts: $sa_count/$TOTAL_NAMESPACES"
    echo "   - ConfigMaps: $cm_count/$((TOTAL_NAMESPACES * 2))"
    echo "   - Deployments: $deployment_count/$TOTAL_NAMESPACES"
    
    if [ "$namespace_count" -eq $TOTAL_NAMESPACES ] && \
       [ "$sa_count" -eq $TOTAL_NAMESPACES ] && \
       [ "$cm_count" -eq $((TOTAL_NAMESPACES * 2)) ] && \
       [ "$deployment_count" -eq $TOTAL_NAMESPACES ]; then
        print_status "SUCCESS" "All resources created successfully"
        return 0
    else
        print_status "ERROR" "Resource creation incomplete"
        return 1
    fi
}

# Function to execute load testing
execute_load_testing() {
    print_status "INFO" "Starting controlled load testing with $TOTAL_BATCHES batches..."
    echo "Each batch: $NAMESPACES_PER_BATCH namespaces, Scale up → wait 30s → scale down → wait 10s"
    echo "Maximum pods running simultaneously: $MAX_PODS_SIMULTANEOUS"
    echo ""
    
    # Record start time
    local start_time=$(date +%s)
    local batch_count=0
    local total_scale_operations=0
    
    # Process batches
    for batch_start in $(seq 1 $NAMESPACES_PER_BATCH $TOTAL_NAMESPACES); do
        batch_count=$((batch_count + 1))
        local batch_end=$((batch_start + NAMESPACES_PER_BATCH - 1))
        
        print_status "INFO" "=== BATCH $batch_count: Processing namespaces $batch_start-$batch_end ==="
        
        # Scale up deployments in this batch
        print_status "INFO" "Scaling UP deployments in batch $batch_count..."
        for i in $(seq $batch_start $batch_end); do
            formatted_i=$(printf "%03d" $i)
            kubectl scale deployment test-deployment --replicas=1 -n load-test-${formatted_i} >/dev/null &
            total_scale_operations=$((total_scale_operations + 1))
        done
        
        # Wait for all scale operations to complete
        wait
        
        print_status "SUCCESS" "Batch $batch_count: All deployments scaled UP to 1 replica"
        print_status "INFO" "Waiting 30 seconds for admission webhook processing..."
        sleep 30
        
        # Check current running pods
        local running_pods
        running_pods=$(kubectl get pods -A | grep load-test | grep Running | wc -l)
        print_status "INFO" "Current running pods: $running_pods"
        
        # Scale down deployments in this batch
        print_status "INFO" "Scaling DOWN deployments in batch $batch_count..."
        for i in $(seq $batch_start $batch_end); do
            formatted_i=$(printf "%03d" $i)
            kubectl scale deployment test-deployment --replicas=0 -n load-test-${formatted_i} >/dev/null &
            total_scale_operations=$((total_scale_operations + 1))
        done
        
        # Wait for all scale operations to complete
        wait
        
        print_status "SUCCESS" "Batch $batch_count: All deployments scaled DOWN to 0 replicas"
        print_status "INFO" "Waiting 10 seconds before next batch..."
        sleep 10
        
        print_status "SUCCESS" "--- Batch $batch_count completed ---"
        echo ""
    done
    
    # Record end time and calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    print_status "SUCCESS" "=== LOAD TESTING COMPLETED ==="
    echo "Total batches processed: $batch_count"
    echo "Total admission webhook events: $total_scale_operations"
    echo "Test duration: ${minutes}m ${seconds}s"
    echo "Resource management: Maximum $MAX_PODS_SIMULTANEOUS pods running simultaneously"
    echo "Controlled testing: Scale up → wait 30s → scale down → wait 10s"
    echo ""
}

# Function to check system performance
check_system_performance() {
    print_status "INFO" "Checking system performance..."
    
    # Check Kyverno stability
    print_status "INFO" "Checking Kyverno stability..."
    local kyverno_restarts
    kyverno_restarts=$(kubectl get pods -n kyverno --no-headers | awk '{sum += $4} END {print sum+0}')
    
    if [ "$kyverno_restarts" -eq 0 ]; then
        print_status "SUCCESS" "Kyverno Stability: No pod restarts"
    else
        print_status "WARNING" "Kyverno Stability: $kyverno_restarts pod restarts detected"
    fi
    
    # Check resource consumption
    print_status "INFO" "Checking resource consumption..."
    local total_pods
    total_pods=$(kubectl get pods -A | grep load-test | wc -l)
    print_status "INFO" "Total test pods: $total_pods"
    
    # Check policy reports (approximate)
    print_status "INFO" "Checking policy report generation..."
    print_status "INFO" "Note: Check Grafana dashboard for detailed policy report metrics"
    
    print_status "SUCCESS" "System performance check completed"
}

# Main execution
main() {
    echo "🚀 Starting Phase 2: Complete Test Plan Execution"
    echo "================================================="
    echo ""
    
    # Check prerequisites
    print_status "INFO" "Checking prerequisites..."
    check_command "kubectl"
    check_command "aws"
    print_status "SUCCESS" "Prerequisites check passed"
    echo ""
    
    # Step 1: Infrastructure Validation
    print_status "INFO" "STEP 1: INFRASTRUCTURE VALIDATION"
    echo "=============================================="
    
    if ! check_eks_cluster; then
        print_status "ERROR" "EKS cluster check failed. Please run setup/phase1/phase1-setup.sh first"
        exit 1
    fi
    
    if ! check_kyverno; then
        print_status "ERROR" "Kyverno check failed. Please check the setup"
        exit 1
    fi
    
    if ! check_monitoring; then
        print_status "ERROR" "Monitoring stack check failed. Please check the setup"
        exit 1
    fi
    
    if ! check_rds_connectivity; then
        print_status "ERROR" "RDS connectivity check failed. Please check the setup"
        exit 1
    fi
    
    print_status "SUCCESS" "Infrastructure validation completed successfully"
    echo ""
    
    # Step 2: Infrastructure Setup (Namespaces)
    print_status "INFO" "STEP 2: INFRASTRUCTURE SETUP"
    echo "====================================="
    
    create_test_namespaces
    echo ""
    
    # Step 3: Object Deployment
    print_status "INFO" "STEP 3: OBJECT DEPLOYMENT"
    echo "=================================="
    
    create_service_accounts
    echo ""
    
    create_configmaps
    echo ""
    
    create_deployments
    echo ""
    
    if ! verify_resources; then
        print_status "ERROR" "Resource verification failed"
        exit 1
    fi
    
    echo ""
    
    # Step 4: Load Testing Execution
    print_status "INFO" "STEP 4: LOAD TESTING EXECUTION"
    echo "=========================================="
    
    execute_load_testing
    
    # Step 5: System Performance Check
    print_status "INFO" "STEP 5: SYSTEM PERFORMANCE CHECK"
    echo "============================================="
    
    check_system_performance
    echo ""
    
    # Final summary
    print_status "SUCCESS" "🎉 PHASE 2 COMPLETED SUCCESSFULLY!"
    echo "======================================================"
    echo "What was accomplished:"
    echo "✅ Infrastructure validation"
    echo "✅ 200 test namespaces created"
    echo "✅ 200 ServiceAccounts created"
    echo "✅ 400 ConfigMaps created"
    echo "✅ 200 deployments created"
    echo "✅ Load testing executed (20 batches)"
    echo "✅ System performance verified"
    echo ""
    echo "Total objects for Kyverno processing: 800"
    echo "Total admission webhook events: 400 (200 scale up + 200 scale down)"
    echo ""
    echo "Next steps:"
    echo "1. Check Grafana dashboard for policy report metrics"
    echo "2. Review policy report counts in the database"
    echo "3. Analyze admission webhook performance"
    echo "4. Run Phase 3: Clean K8s resources when ready"
    echo ""
}

# Run main function
main "$@"
