# Kyverno + PostgreSQL Reports Server - Comprehensive Test Plan

## 🎯 Executive Summary

This test plan validates the end-to-end functionality of Kyverno policy enforcement with PostgreSQL-based Reports Server storage. The goal is to prove that policy results are correctly generated, collected, stored, and maintained under realistic load conditions.

## 📋 Test Objectives

1. **Functional Validation**: Ensure PolicyReports are correctly generated and stored
2. **Data Consistency**: Verify Kubernetes PolicyReports match PostgreSQL records
3. **Performance Testing**: Validate system behavior under load
4. **Scalability Testing**: Test system limits and performance degradation points
5. **Reliability Testing**: Ensure system stability during continuous operation

---

## 🧪 Phase 1: Foundation Setup

### Test Step 1.1: Policy Creation and Deployment

**What We're Doing:**
```bash
# Apply baseline policies
kubectl apply -f policies/baseline/require-labels.yaml
kubectl apply -f policies/baseline/disallow-privileged-containers.yaml
```

**Why We're Doing This:**
- Establish baseline policy rules that will generate PolicyReports
- Create predictable test conditions for validation
- Ensure policies are active before generating test data

**Why It's Important:**
- Without active policies, no PolicyReports will be generated
- Baseline policies provide consistent test scenarios
- Validates that Kyverno can load and enforce policies correctly

**Expected Outcome:**
- Policies should be active and visible in `kubectl get clusterpolicies`
- No errors in Kyverno logs during policy loading

### Test Step 1.2: System Health Validation

**What We're Doing:**
```bash
# Check Kyverno status
kubectl get pods -n kyverno
kubectl get pods -n reports-server

# Verify database connectivity
kubectl logs -n reports-server reports-server-7fdc7fdc49-5d9wj --tail=20
```

**Why We're Doing This:**
- Ensure all components are healthy before testing
- Verify database connectivity is established
- Confirm Reports Server is processing data correctly

**Why It's Important:**
- Prevents false test failures due to infrastructure issues
- Establishes baseline system state for comparison
- Validates that the monitoring setup is working

**Expected Outcome:**
- All Kyverno pods in Running state
- Reports Server pod healthy and connected to PostgreSQL
- No connection errors in logs

---

## 🏗️ Phase 2: Test Data Generation

### Test Step 2.1: Namespace Creation (Scale Preparation)

**What We're Doing:**
```bash
# Create test namespaces in batches
for i in $(seq -w 1 200); do 
  kubectl create ns load-$i
done
```

**Why We're Doing This:**
- Create many namespaces to test Kyverno's background scanning capability
- Generate PolicyReports without requiring running pods
- Prepare infrastructure for scale testing

**Why It's Important:**
- Kyverno's background controller scans all resources in all namespaces
- More namespaces = more objects to scan = more PolicyReports generated
- Tests the system's ability to handle large numbers of resources efficiently

**Expected Outcome:**
- 200 namespaces created successfully
- PolicyReports generated for each namespace (label policy violations)
- No significant performance degradation

### Test Step 2.2: Static Object Deployment

**What We're Doing:**
```bash
# Create objects.yaml with static resources
cat > objects.yaml <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata: { name: demo-sa }
---
apiVersion: v1
kind: ConfigMap
metadata: { name: cm-01 }
data: { k: v }
---
apiVersion: v1
kind: ConfigMap
metadata: { name: cm-02 }
data: { k: v }
YAML

# Deploy to all namespaces
for i in $(seq -w 1 200); do 
  kubectl -n load-$i apply -f objects.yaml
done
```

**Why We're Doing This:**
- Create objects that Kyverno will scan in background mode
- Generate PolicyReports without consuming significant resources
- Test background scanning performance at scale

**Why It's Important:**
- Background scanning is a key Kyverno feature that processes existing resources
- Tests the Reports Server's ability to handle many concurrent report updates
- Validates that PostgreSQL can handle the write load from multiple namespaces

**Expected Outcome:**
- 600 objects created (3 per namespace × 200 namespaces)
- Background PolicyReports generated for each namespace
- Database shows increased report counts

### Test Step 2.3: Deployment Preparation (Zero Replicas)

**What We're Doing:**
```bash
# Create deploy-zero.yaml
cat > deploy-zero.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata: { name: pause, labels: { app: pause } }
spec:
  replicas: 0
  selector: { matchLabels: { app: pause } }
  template:
    metadata: { labels: { app: pause } }
    spec:
      containers:
      - name: pause
        image: registry.k8s.io/pause:3.9
        resources:
          requests: { cpu: "5m", memory: "16Mi" }
          limits:   { cpu: "30m", memory: "64Mi" }
YAML

# Deploy to all namespaces
for i in $(seq -w 1 200); do 
  kubectl -n load-$i apply -f deploy-zero.yaml
done
```

**Why We're Doing This:**
- Prepare deployments that can be quickly scaled up/down for admission testing
- Use minimal resource containers to stay within cluster capacity
- Create infrastructure for admission webhook testing

**Why It's Important:**
- Admission webhooks are triggered when resources are created/updated
- Zero-replica deployments allow testing admission without consuming resources
- Tests both admission and background scanning paths

**Expected Outcome:**
- 200 deployments created (0 replicas each)
- No pods running (0 total resource consumption)
- Deployments ready for admission testing

---

## 🔄 Phase 3: Admission Testing (Batch Processing)

### Test Step 3.1: Batch Admission Testing

**What We're Doing:**
```bash
BATCH=10
for start in $(seq 1 $BATCH 200); do
  end=$((start+BATCH-1))
  
  # Scale up (trigger admission)
  for i in $(seq -w $start $end); do
    kubectl -n load-$i scale deploy/pause --replicas=1
  done
  
  # Wait for pods to be ready
  sleep 30
  
  # Scale down (free resources)
  for i in $(seq -w $start $end); do
    kubectl -n load-$i scale deploy/pause --replicas=0
  done
  
  # Wait for cleanup
  sleep 30
done
```

**Why We're Doing This:**
- Test admission webhook performance under controlled load
- Generate admission PolicyReports in batches
- Stay within cluster resource limits (~30 pods max)

**Why It's Important:**
- Admission webhooks are the primary enforcement mechanism
- Tests real-time policy evaluation performance
- Validates that Reports Server can handle admission report bursts
- Simulates realistic workload patterns

**Expected Outcome:**
- 20 batches processed (200 namespaces ÷ 10 per batch)
- Admission PolicyReports generated for each scale-up
- No admission webhook timeouts or failures
- Consistent performance across batches

### Test Step 3.2: Resource Churn Testing

**What We're Doing:**
```bash
# Add labels to trigger re-evaluation
for i in $(seq -w 1 200); do
  kubectl -n load-$i get pods -l app=pause -o name | \
    xargs -I{} -P 10 kubectl -n load-$i label {} touched=$(date +%s) --overwrite
done
```

**Why We're Doing This:**
- Force Kyverno to re-evaluate existing resources
- Test background scanning performance under load
- Generate additional PolicyReport updates

**Why It's Important:**
- Tests the system's ability to handle resource updates
- Validates that PolicyReports are updated correctly
- Ensures data consistency during churn

**Expected Outcome:**
- PolicyReports updated with new timestamps
- No performance degradation during churn
- Database shows updated report records

---

## 📊 Phase 4: Data Validation

### Test Step 4.1: Kubernetes PolicyReport Validation

**What We're Doing:**
```bash
# Count PolicyReports
kubectl get policyreport -A | wc -l
kubectl get clusterpolicyreport | wc -l

# Check specific reports
kubectl get policyreport -n load-001 -o yaml
```

**Why We're Doing This:**
- Verify that PolicyReports are generated in Kubernetes
- Validate report structure and content
- Ensure policy violations are correctly recorded

**Why It's Important:**
- Kubernetes PolicyReports are the source of truth
- Validates that Kyverno is working correctly
- Provides baseline for PostgreSQL comparison

**Expected Outcome:**
- PolicyReports exist for each namespace
- Report content matches expected policy violations
- Timestamps are recent and accurate

### Test Step 4.2: PostgreSQL Data Validation

**What We're Doing:**
```bash
# Connect to PostgreSQL and query reports
kubectl run postgres-client --rm -i --restart=Never --image=postgres:15 -- \
  psql -h reports-server-db-20250825-173521.cgfhp1exibuy.us-west-1.rds.amazonaws.com \
  -U reportsuser -d reportsdb -c "
  SELECT 
    (SELECT count(*) FROM policyreports) as policy_reports,
    (SELECT count(*) FROM ephemeralreports) as ephemeral_reports,
    (SELECT count(*) FROM clusterpolicyreports) as cluster_policy_reports,
    (SELECT count(*) FROM clusterephemeralreports) as cluster_ephemeral_reports;
  "
```

**Why We're Doing This:**
- Verify that Reports Server has stored PolicyReports in PostgreSQL
- Validate data consistency between Kubernetes and PostgreSQL
- Check report counts and distribution

**Why It's Important:**
- PostgreSQL is the persistent storage layer
- Validates end-to-end data flow
- Ensures no data loss between Kubernetes and Reports Server

**Expected Outcome:**
- PostgreSQL contains PolicyReports matching Kubernetes counts
- All report types are present (policy, ephemeral, cluster)
- Data timestamps are consistent

### Test Step 4.3: Data Consistency Validation

**What We're Doing:**
```bash
# Compare Kubernetes vs PostgreSQL counts
K8S_COUNT=$(kubectl get policyreport -A --no-headers | wc -l)
DB_COUNT=$(kubectl run postgres-client --rm -i --restart=Never --image=postgres:15 -- \
  psql -h reports-server-db-20250825-173521.cgfhp1exibuy.us-west-1.rds.amazonaws.com \
  -U reportsuser -d reportsdb -t -c "SELECT count(*) FROM policyreports;")

echo "Kubernetes PolicyReports: $K8S_COUNT"
echo "PostgreSQL PolicyReports: $DB_COUNT"
```

**Why We're Doing This:**
- Ensure data consistency between Kubernetes and PostgreSQL
- Validate that Reports Server is not losing data
- Check for any synchronization issues

**Why It's Important:**
- Data consistency is critical for reliable reporting
- Identifies any data loss or duplication issues
- Validates Reports Server reliability

**Expected Outcome:**
- Kubernetes and PostgreSQL counts should match
- No significant discrepancies
- Consistent data across both systems

---

## 📈 Phase 5: Performance Monitoring

### Test Step 5.1: System Metrics Collection

**What We're Doing:**
```bash
# Monitor Kyverno resource usage
kubectl top pods -n kyverno

# Check Reports Server resource usage
kubectl top pods -n reports-server

# Monitor database connections
kubectl logs -n reports-server reports-server-7fdc7fdc49-5d9wj --tail=50 | grep -i connection
```

**Why We're Doing This:**
- Monitor system performance during testing
- Identify resource bottlenecks
- Track performance trends

**Why It's Important:**
- Performance monitoring helps identify issues before they become problems
- Validates that the system can handle the load
- Provides data for capacity planning

**Expected Outcome:**
- Resource usage within acceptable limits
- No memory leaks or excessive CPU usage
- Stable database connection counts

### Test Step 5.2: Latency Measurement

**What We're Doing:**
```bash
# Measure admission webhook latency
kubectl logs -n kyverno kyverno-admission-controller-5bcbdff469-85ng7 --tail=100 | \
  grep "admission request" | tail -10

# Check Reports Server processing time
kubectl logs -n reports-server reports-server-7fdc7fdc49-5d9wj --tail=100 | \
  grep "processing" | tail -10
```

**Why We're Doing This:**
- Measure system responsiveness
- Identify performance bottlenecks
- Validate that latency stays within acceptable limits

**Why It's Important:**
- Latency affects user experience
- High latency can indicate system problems
- Performance data helps with optimization

**Expected Outcome:**
- Admission webhook latency < 1 second
- Reports Server processing time < 5 seconds
- Consistent performance throughout testing

---

## 🔄 Phase 6: Scale Testing

### Test Step 6.1: Gradual Scale Testing

**What We're Doing:**
```bash
# Test with different namespace counts
for SCALE in 50 100 200; do
  echo "Testing with $SCALE namespaces..."
  
  # Create namespaces
  for i in $(seq -w 1 $SCALE); do
    kubectl create ns scale-test-$i
  done
  
  # Apply objects
  for i in $(seq -w 1 $SCALE); do
    kubectl -n scale-test-$i apply -f objects.yaml
  done
  
  # Measure performance
  kubectl top pods -n kyverno
  kubectl get policyreport -A | wc -l
  
  # Cleanup
  for i in $(seq -w 1 $SCALE); do
    kubectl delete ns scale-test-$i
  done
done
```

**Why We're Doing This:**
- Test system behavior at different scales
- Identify performance degradation points
- Determine practical system limits

**Why It's Important:**
- Helps understand system capacity
- Identifies when performance starts to degrade
- Provides data for capacity planning

**Expected Outcome:**
- System performs well up to 200 namespaces
- Performance degradation is gradual, not sudden
- Resource usage scales linearly

### Test Step 6.2: Load Testing

**What We're Doing:**
```bash
# Generate sustained load
for ROUND in {1..10}; do
  echo "Load test round $ROUND"
  
  # Scale up/down in batches
  for start in $(seq 1 10 200); do
    end=$((start+9))
    for i in $(seq -w $start $end); do
      kubectl -n load-$i scale deploy/pause --replicas=1 &
    done
    wait
    
    sleep 10
    
    for i in $(seq -w $start $end); do
      kubectl -n load-$i scale deploy/pause --replicas=0 &
    done
    wait
    
    sleep 10
  done
done
```

**Why We're Doing This:**
- Test system stability under sustained load
- Validate that performance doesn't degrade over time
- Test error handling and recovery

**Why It's Important:**
- Real-world usage involves sustained load
- Tests system stability and reliability
- Identifies any memory leaks or resource exhaustion

**Expected Outcome:**
- System remains stable throughout testing
- No performance degradation over time
- No errors or failures

---

## 🔍 Phase 7: Error Handling and Recovery

### Test Step 7.1: Component Failure Testing

**What We're Doing:**
```bash
# Simulate Reports Server restart
kubectl delete pod -n reports-server reports-server-7fdc7fdc49-5d9wj

# Monitor recovery
kubectl get pods -n reports-server -w

# Verify data consistency after recovery
kubectl get policyreport -A | wc -l
```

**Why We're Doing This:**
- Test system behavior during component failures
- Validate recovery mechanisms
- Ensure data consistency after failures

**Why It's Important:**
- Real-world systems experience failures
- Validates that the system can recover gracefully
- Ensures no data loss during failures

**Expected Outcome:**
- Reports Server restarts successfully
- No data loss during restart
- System continues to function normally

### Test Step 7.2: Database Connection Testing

**What We're Doing:**
```bash
# Test database connectivity
kubectl run postgres-client --rm -i --restart=Never --image=postgres:15 -- \
  psql -h reports-server-db-20250825-173521.cgfhp1exibuy.us-west-1.rds.amazonaws.com \
  -U reportsuser -d reportsdb -c "SELECT 1;"

# Check connection pooling
kubectl logs -n reports-server reports-server-7fdc7fdc49-5d9wj --tail=100 | \
  grep -i "connection\|pool"
```

**Why We're Doing This:**
- Validate database connectivity
- Test connection pooling behavior
- Ensure stable database connections

**Why It's Important:**
- Database connectivity is critical for Reports Server
- Connection issues can cause data loss
- Validates infrastructure reliability

**Expected Outcome:**
- Database connections are stable
- Connection pooling is working correctly
- No connection errors or timeouts

---

## 📊 Phase 8: Final Validation and Reporting

### Test Step 8.1: Comprehensive Data Validation

**What We're Doing:**
```bash
# Final count validation
echo "=== Final Validation ==="
echo "Kubernetes PolicyReports: $(kubectl get policyreport -A --no-headers | wc -l)"
echo "Kubernetes ClusterPolicyReports: $(kubectl get clusterpolicyreport --no-headers | wc -l)"

# Database validation
kubectl run postgres-client --rm -i --restart=Never --image=postgres:15 -- \
  psql -h reports-server-db-20250825-173521.cgfhp1exibuy.us-west-1.rds.amazonaws.com \
  -U reportsuser -d reportsdb -c "
  SELECT 
    'Policy Reports' as type, count(*) as count FROM policyreports
  UNION ALL
  SELECT 'Ephemeral Reports' as type, count(*) as count FROM ephemeralreports
  UNION ALL
  SELECT 'Cluster Policy Reports' as type, count(*) as count FROM clusterpolicyreports
  UNION ALL
  SELECT 'Cluster Ephemeral Reports' as type, count(*) as count FROM clusterephemeralreports;
  "
```

**Why We're Doing This:**
- Provide final validation of all test results
- Generate comprehensive test report
- Document system state after testing

**Why It's Important:**
- Validates that all testing was successful
- Provides baseline for future testing
- Documents system performance and capacity

**Expected Outcome:**
- All data is consistent between Kubernetes and PostgreSQL
- System performance meets requirements
- No errors or issues identified

### Test Step 8.2: Performance Summary

**What We're Doing:**
```bash
# Generate performance summary
echo "=== Performance Summary ==="
echo "Total namespaces tested: 200"
echo "Total objects created: 600"
echo "Total admission tests: 20 batches"
echo "System uptime: $(uptime)"
echo "Database size: $(kubectl run postgres-client --rm -i --restart=Never --image=postgres:15 -- \
  psql -h reports-server-db-20250825-173521.cgfhp1exibuy.us-west-1.rds.amazonaws.com \
  -U reportsuser -d reportsdb -t -c "SELECT pg_size_pretty(pg_database_size('reportsdb'));")"
```

**Why We're Doing This:**
- Document system performance metrics
- Provide data for capacity planning
- Create baseline for future comparisons

**Why It's Important:**
- Performance data helps with system optimization
- Provides metrics for monitoring and alerting
- Documents system capabilities for stakeholders

**Expected Outcome:**
- Comprehensive performance summary
- All metrics within acceptable ranges
- Clear documentation of system capabilities

---

## ✅ Success Criteria

### Functional Requirements
- [ ] All PolicyReports generated in Kubernetes are stored in PostgreSQL
- [ ] Data consistency maintained between Kubernetes and PostgreSQL
- [ ] No data loss during component failures or restarts
- [ ] System recovers gracefully from failures

### Performance Requirements
- [ ] Admission webhook latency < 1 second
- [ ] Reports Server processing time < 5 seconds
- [ ] System handles 200+ namespaces without degradation
- [ ] Resource usage stays within acceptable limits

### Reliability Requirements
- [ ] System remains stable during sustained load testing
- [ ] No memory leaks or resource exhaustion
- [ ] Database connections remain stable
- [ ] Error handling works correctly

### Scalability Requirements
- [ ] Performance scales linearly with load
- [ ] System can handle burst loads
- [ ] No hard limits reached during testing
- [ ] Capacity planning data available

---

## 📋 Test Execution Checklist

### Pre-Test Setup
- [ ] All components healthy and running
- [ ] Database connectivity verified
- [ ] Policies deployed and active
- [ ] Monitoring tools configured

### During Testing
- [ ] Monitor system resources continuously
- [ ] Track PolicyReport generation rates
- [ ] Validate data consistency regularly
- [ ] Document any issues or anomalies

### Post-Test Validation
- [ ] Verify all data is consistent
- [ ] Check system health and performance
- [ ] Generate comprehensive test report
- [ ] Document lessons learned and recommendations

---

## 🚨 Troubleshooting Guide

### Common Issues and Solutions

**Issue: PolicyReports not generating**
- Check that policies are active: `kubectl get clusterpolicies`
- Verify Kyverno pods are running: `kubectl get pods -n kyverno`
- Check Kyverno logs for errors: `kubectl logs -n kyverno kyverno-admission-controller-xxx`

**Issue: Reports Server not storing data**
- Verify database connectivity: Check Reports Server logs
- Check database credentials and permissions
- Validate PostgreSQL is accessible from cluster

**Issue: Performance degradation**
- Monitor resource usage: `kubectl top pods -n kyverno`
- Check for memory leaks or high CPU usage
- Validate database connection pooling

**Issue: Data inconsistency**
- Compare Kubernetes vs PostgreSQL counts
- Check Reports Server logs for errors
- Validate that all components are healthy

---

## 📈 Monitoring and Metrics

### Key Metrics to Track
- PolicyReport generation rate
- Admission webhook latency
- Reports Server processing time
- Database connection count
- System resource usage (CPU, memory)
- Error rates and types

### Alerting Thresholds
- Admission webhook latency > 2 seconds
- Reports Server processing time > 10 seconds
- Database connection count > 80% of limit
- System resource usage > 80%
- Error rate > 5%

---

This comprehensive test plan ensures thorough validation of the Kyverno + PostgreSQL Reports Server system, providing confidence in its reliability, performance, and scalability for production use.
