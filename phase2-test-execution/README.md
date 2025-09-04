# 🧪 PHASE 2: TEST PLAN EXECUTION

## 📋 **Purpose**
This phase executes the complete Kyverno + PostgreSQL test plan, creating test resources and running load testing.

## 🎯 **What This Phase Does**

### **Step 1: Infrastructure Validation**
- Verifies EKS cluster is ACTIVE
- Confirms Kyverno is running
- Checks monitoring stack status
- Validates RDS connectivity

### **Step 2: Infrastructure Setup**
- Creates 200 test namespaces with `owner=loadtest` labels
- Verifies Kyverno policy enforcement

### **Step 3: Object Deployment**
- **200 ServiceAccounts** (`demo-sa`)
- **400 ConfigMaps** (`cm-01`, `cm-02`)
- **200 Deployments** with zero replicas
- **Total: 800 objects** for Kyverno processing

### **Step 4: Load Testing Execution**
- **20 batches** (10 namespaces per batch)
- **Scale up → wait 30s → scale down → wait 10s**
- **Maximum 10 pods** running simultaneously
- **Total: 400 admission webhook events**

### **Step 5: System Performance Check**
- Kyverno stability verification
- Resource consumption monitoring
- Policy report generation tracking

## 📁 **Files in This Phase**

### **Core Scripts**
- `phase2-test-plan-execution.sh` - **MAIN SCRIPT** (run this)
- `create-deployments.sh` - Legacy deployment creation script
- `create-deployments-fixed.sh` - Fixed version of deployment script

### **Templates**
- `load-test-deployment-template.yaml` - Deployment template
- `pod-template-compliant.yaml` - Compliant pod template
- `simple-compliant-pod.yaml` - Simple compliant pod
- `fully-compliant-test-pod.yaml` - Fully compliant test pod
- `good-deploy.yaml` - Good deployment example
- `bad-pod.yaml` - Non-compliant pod example
- `test-configmap.yaml` - Test ConfigMap template

## 🎯 **How to Use**

### **Prerequisites**
- Phase 1 must be completed successfully
- EKS cluster must be ACTIVE
- Kyverno and monitoring must be running

### **Run the Test Plan**
```bash
# Make script executable
chmod +x phase2-test-plan-execution.sh

# Execute the complete test plan
./phase2-test-plan-execution.sh
```

### **Expected Duration**
- **Resource Creation**: 5-10 minutes
- **Load Testing**: 20-25 minutes
- **Total**: ~30-35 minutes

## 📊 **Expected Results**

### **Resources Created**
- 200 test namespaces
- 200 ServiceAccounts
- 400 ConfigMaps
- 200 deployments
- 800 total objects

### **Load Testing Metrics**
- 20 batches processed
- 400 admission webhook events
- Maximum 10 pods running simultaneously
- Controlled resource consumption

## 🔍 **Monitoring During Execution**

### **Check Progress**
```bash
# Monitor namespace creation
kubectl get namespaces | grep load-test | wc -l

# Monitor deployment creation
kubectl get deployments -A | grep test-deployment | wc -l

# Monitor running pods during load testing
kubectl get pods -A | grep load-test | grep Running | wc -l
```

### **Check Kyverno Status**
```bash
# Monitor Kyverno pods
kubectl get pods -n kyverno

# Check Kyverno logs
kubectl logs -n kyverno deployment/kyverno
```

## ⚠️ **Important Notes**
- This phase creates 800 objects - ensure sufficient cluster capacity
- Load testing generates significant policy report data
- Monitor cluster resources during execution
- Check Grafana dashboard for real-time metrics

## 🧹 **After Completion**
When Phase 2 completes:
1. Check Grafana dashboard for policy report metrics
2. Review policy report counts in the database
3. Analyze admission webhook performance
4. Run Phase 3 to clean up test resources (optional)
5. Run Phase 4 when completely done with testing
