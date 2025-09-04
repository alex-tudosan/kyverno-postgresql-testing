#!/bin/bash

set -e  # Exit on any error

echo "🚀 KYVERNO + POSTGRESQL COMPLETE TEST PLAN EXECUTION"
echo "=================================================="
echo ""

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ Error: $1 is not installed or not in PATH"
        exit 1
    fi
}

# Check prerequisites
echo "🔍 Checking prerequisites..."
check_command "kubectl"
check_command "aws"

echo "✅ Prerequisites check passed"
echo ""

# Phase 1: Infrastructure Validation
echo "📋 PHASE 1: INFRASTRUCTURE VALIDATION"
echo "====================================="

echo "🔍 Checking EKS cluster status..."
CLUSTER_STATUS=$(aws eks describe-cluster --name report-server-test --region us-west-1 --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")
if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
    echo "✅ EKS cluster is ACTIVE"
else
    echo "❌ EKS cluster is not ready. Status: $CLUSTER_STATUS"
    echo "Please run setup/phase1/phase1-setup.sh first"
    exit 1
fi

echo "🔍 Checking Kyverno pods..."
KYVERNO_PODS=$(kubectl get pods -n kyverno --no-headers 2>/dev/null | grep Running | wc -l || echo "0")
if [ "$KYVERNO_PODS" -ge 1 ]; then
    echo "✅ Kyverno is running ($KYVERNO_PODS pods)"
else
    echo "❌ Kyverno is not running. Please check the setup"
    exit 1
fi

echo "🔍 Checking Reports Server..."
REPORTS_PODS=$(kubectl get pods -n kyverno --no-headers 2>/dev/null | grep reports-server | grep Running | wc -l || echo "0")
if [ "$REPORTS_PODS" -ge 1 ]; then
    echo "✅ Reports Server is running ($REPORTS_PODS pods)"
else
    echo "❌ Reports Server is not running. Please check the setup"
    exit 1
fi

echo "🔍 Checking monitoring stack..."
MONITORING_PODS=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep Running | wc -l || echo "0")
if [ "$MONITORING_PODS" -ge 1 ]; then
    echo "✅ Monitoring stack is running ($MONITORING_PODS pods)"
else
    echo "❌ Monitoring stack is not running. Please check the setup"
    exit 1
fi

echo "✅ Phase 1 completed - Infrastructure is ready"
echo ""

# Phase 2: Create 200 Test Namespaces
echo "📋 PHASE 2: CREATING 200 TEST NAMESPACES"
echo "========================================"

echo "🚀 Creating 200 test namespaces with proper labels..."
for i in $(seq -w 1 200); do
    formatted_i=$(printf "%03d" $i)
    cat <<EOF | kubectl apply -f -
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
    
    # Progress indicator every 50 namespaces
    if [ $((i % 50)) -eq 0 ]; then
        echo "✅ Created $i namespaces..."
    fi
done

echo "✅ All 200 namespaces created"
echo ""

# Phase 3: Create 200 Deployments
echo "📋 PHASE 3: CREATING 200 DEPLOYMENTS"
echo "===================================="

echo "🚀 Creating 200 deployments with zero replicas..."
for i in $(seq -w 1 200); do
    formatted_i=$(printf "%03d" $i)
    cat <<EOF | kubectl apply -f -
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
    
    # Progress indicator every 50 deployments
    if [ $((i % 50)) -eq 0 ]; then
        echo "✅ Created $i deployments..."
    fi
done

echo "✅ All 200 deployments created"
echo ""

# Verify resources were created
echo "🔍 Verifying resources..."
NAMESPACE_COUNT=$(kubectl get namespaces | grep load-test | wc -l)
DEPLOYMENT_COUNT=$(kubectl get deployments -A | grep test-deployment | wc -l)

echo "📊 Resource Summary:"
echo "   - Test namespaces: $NAMESPACE_COUNT"
echo "   - Test deployments: $DEPLOYMENT_COUNT"
echo ""

if [ "$NAMESPACE_COUNT" -eq 200 ] && [ "$DEPLOYMENT_COUNT" -eq 200 ]; then
    echo "✅ Phase 2 & 3 completed successfully"
else
    echo "❌ Resource creation incomplete. Please check for errors above"
    exit 1
fi

echo ""

# Phase 5: Load Testing Execution
echo "📋 PHASE 5: LOAD TESTING EXECUTION"
echo "=================================="

echo "Starting controlled load testing with 20 batches..."
echo "Each batch: 10 namespaces, Scale up → wait 30s → scale down → wait 10s"
echo "Maximum pods running simultaneously: 10"
echo ""

# Record start time
START_TIME=$(date +%s)
BATCH_COUNT=0
TOTAL_SCALE_OPERATIONS=0

# Process 20 batches of 10 namespaces each
for batch_start in $(seq 1 10 200); do
    BATCH_COUNT=$((BATCH_COUNT + 1))
    batch_end=$((batch_start + 9))
    
    echo "=== BATCH $BATCH_COUNT: Processing namespaces $batch_start-$batch_end ==="
    
    # Scale up deployments in this batch (10 namespaces)
    echo "Scaling UP deployments in batch $BATCH_COUNT..."
    for i in $(seq $batch_start $batch_end); do
        formatted_i=$(printf "%03d" $i)
        kubectl scale deployment test-deployment --replicas=1 -n load-test-${formatted_i} &
        TOTAL_SCALE_OPERATIONS=$((TOTAL_SCALE_OPERATIONS + 1))
    done
    
    # Wait for all scale operations to complete
    wait
    
    echo "Batch $BATCH_COUNT: All deployments scaled UP to 1 replica"
    echo "Waiting 30 seconds for admission webhook processing..."
    sleep 30
    
    # Check current running pods
    RUNNING_PODS=$(kubectl get pods -A | grep load-test | grep Running | wc -l)
    echo "Current running pods: $RUNNING_PODS"
    
    # Scale down deployments in this batch
    echo "Scaling DOWN deployments in batch $BATCH_COUNT..."
    for i in $(seq $batch_start $batch_end); do
        formatted_i=$(printf "%03d" $i)
        kubectl scale deployment test-deployment --replicas=0 -n load-test-${formatted_i} &
        TOTAL_SCALE_OPERATIONS=$((TOTAL_SCALE_OPERATIONS + 1))
    done
    
    # Wait for all scale operations to complete
    wait
    
    echo "Batch $BATCH_COUNT: All deployments scaled DOWN to 0 replicas"
    echo "Waiting 10 seconds before next batch..."
    sleep 10
    
    echo "--- Batch $BATCH_COUNT completed ---"
    echo ""
done

# Record end time and calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

echo "=== LOAD TESTING COMPLETED ==="
echo "Total batches processed: $BATCH_COUNT"
echo "Total admission webhook events: $TOTAL_SCALE_OPERATIONS"
echo "Test duration: ${MINUTES}m ${SECONDS}s"
echo "Resource management: Maximum 10 pods running simultaneously"
echo "Controlled testing: Scale up → wait 30s → scale down → wait 10s"
echo ""

# Check final policy report counts
echo "Checking final policy report counts..."
echo "Note: This requires direct database access. Check Grafana dashboard for real-time metrics."
echo ""

echo "🎉 COMPLETE TEST PLAN EXECUTION FINISHED SUCCESSFULLY!"
echo "======================================================"
echo "What was accomplished:"
echo "✅ Phase 1: Infrastructure validation"
echo "✅ Phase 2: Created 200 test namespaces"
echo "✅ Phase 3: Created 200 test deployments"
echo "✅ Phase 5: Executed load testing with 20 batches"
echo ""
echo "Next steps:"
echo "1. Check Grafana dashboard for policy report metrics"
echo "2. Review policy report counts in the database"
echo "3. Analyze admission webhook performance"
echo ""
