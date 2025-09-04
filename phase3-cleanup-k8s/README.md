# 🧹 PHASE 3: CLEANUP KUBERNETES TEST RESOURCES

## 📋 **Purpose**
This phase cleans up all Kubernetes resources created during Phase 2 testing while preserving the AWS infrastructure.

## 🎯 **What This Phase Does**

### **Resource Cleanup**
- **200 test namespaces** (`load-test-001` to `load-test-200`)
- **200 ServiceAccounts** (`demo-sa`)
- **400 ConfigMaps** (`cm-01`, `cm-02`)
- **200 deployments** (`test-deployment`)
- **All associated pods** and resources
- **Policy reports** generated during testing

### **Infrastructure Preservation**
- **EKS cluster** remains intact
- **RDS PostgreSQL** instance preserved
- **Kyverno** continues running
- **Monitoring stack** remains operational
- **Terraform state** preserved

## 📁 **Files in This Phase**

### **Core Scripts**
- `phase3-cleanup-k8s.sh` - **MAIN SCRIPT** (run this)
- `cleanup-test-resources.sh` - Legacy cleanup script

## 🎯 **How to Use**

### **Prerequisites**
- Phase 2 must be completed successfully
- Test resources must exist (namespaces, deployments, etc.)
- Infrastructure should still be running

### **Run the Cleanup**
```bash
# Make script executable
chmod +x phase3-cleanup-k8s.sh

# Execute the cleanup
./phase3-cleanup-k8s.sh
```

### **Expected Duration**
- **Resource Deletion**: 5-10 minutes
- **Namespace Cleanup**: 2-5 minutes
- **Total**: ~10-15 minutes

## 🔄 **Cleanup Process**

### **Step 1: Resource Discovery**
- Checks for existing test resources
- Reports counts of resources found
- Asks for user confirmation

### **Step 2: Resource Deletion (Reverse Order)**
1. **Deployments** - Delete first (dependencies)
2. **ConfigMaps** - Delete configuration objects
3. **ServiceAccounts** - Delete service accounts
4. **Namespaces** - Delete last (contains everything)

### **Step 3: Verification**
- Waits for namespace cleanup to complete
- Verifies all resources are deleted
- Checks infrastructure status

## 📊 **What Gets Cleaned Up**

### **Test Resources (Deleted)**
- All `load-test-*` namespaces
- All `demo-sa` ServiceAccounts
- All `cm-01` and `cm-02` ConfigMaps
- All `test-deployment` deployments
- All test pods and associated resources

### **Infrastructure (Preserved)**
- EKS cluster `report-server-test`
- RDS instance `reports-server-db`
- Kyverno namespace and pods
- Monitoring namespace and pods
- All AWS resources

## ⚠️ **Important Notes**

### **Before Running**
- **Backup any important data** from test resources
- **Ensure Phase 2 completed** successfully
- **Verify infrastructure is stable** before cleanup

### **During Cleanup**
- Script will ask for confirmation
- Progress indicators show deletion status
- Can be interrupted with Ctrl+C (cleanup will be partial)

### **After Cleanup**
- Infrastructure is ready for reuse
- Can run Phase 2 again for new tests
- No test data remains in the cluster

## 🔍 **Monitoring During Cleanup**

### **Check Progress**
```bash
# Monitor remaining namespaces
kubectl get namespaces | grep load-test | wc -l

# Monitor remaining deployments
kubectl get deployments -A | grep test-deployment | wc -l

# Monitor remaining pods
kubectl get pods -A | grep load-test | wc -l
```

### **Check Infrastructure Status**
```bash
# Verify Kyverno is still running
kubectl get pods -n kyverno

# Verify monitoring is still running
kubectl get pods -n monitoring

# Verify EKS cluster is still active
aws eks describe-cluster --name report-server-test --region us-west-1
```

## 🚨 **Troubleshooting**

### **Common Issues**
- **Namespace stuck in Terminating**: May need manual intervention
- **Resources not deleted**: Check for finalizers or dependencies
- **Infrastructure affected**: Verify Kyverno and monitoring status

### **Manual Cleanup (if needed)**
```bash
# Force delete stuck namespaces
kubectl delete namespace load-test-XXX --force --grace-period=0

# Check for finalizers
kubectl get namespace load-test-XXX -o yaml | grep finalizers
```

## 🧹 **After Completion**

### **Verification**
- All test resources should be deleted
- Infrastructure should remain intact
- Ready for new test runs

### **Next Steps**
1. **Run Phase 2 again** for new tests (if needed)
2. **Run Phase 4** when completely done with testing
3. **Monitor infrastructure** for any issues

## 💡 **Best Practices**

### **When to Use Phase 3**
- After completing Phase 2 testing
- Before running new tests
- When you want to clean up test data
- When preserving infrastructure for reuse

### **When NOT to Use Phase 3**
- If you want to destroy everything (use Phase 4 instead)
- If infrastructure is unstable
- If you need to preserve test data
