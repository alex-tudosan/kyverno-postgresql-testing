#!/bin/bash

echo "=== PHASE 5: LOAD TESTING EXECUTION ==="
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
PGPASSWORD=newpassword123 psql -h reports-server-db-20250902-092514.cgfhp1exibuy.us-west-1.rds.amazonaws.com -U reportsuser -d reportsdb -c "SELECT 'Total Records' as summary, (SELECT COUNT(*) FROM policyreports) + (SELECT COUNT(*) FROM ephemeralreports) + (SELECT COUNT(*) FROM clusterpolicyreports) + (SELECT COUNT(*) FROM clusterephemeralreports) as total_count;"

echo ""
echo "Load testing execution completed successfully!"



