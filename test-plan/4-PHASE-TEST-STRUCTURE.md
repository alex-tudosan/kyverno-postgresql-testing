# 🚀 KYVERNO + POSTGRESQL TESTING - 4-PHASE STRUCTURE

## 📋 **OVERVIEW**
This repository is organized into 4 distinct phases that can be run independently or in sequence:

## **🔄 PHASE 1: AWS INFRASTRUCTURE SETUP**
**Script**: `setup/phase1/phase1-setup.sh`

**What it does**:
- Creates EKS cluster via Terraform (`report-server-test`)
- Creates RDS PostgreSQL instance
- Deploys monitoring stack (Grafana + Prometheus)
- Installs and configures Kyverno
- Deploys Reports Server connected to PostgreSQL

**When to run**: 
- First time setup
- When infrastructure needs to be recreated
- After Phase 4 cleanup

**Prerequisites**: 
- AWS CLI configured
- Terraform installed
- kubectl configured

---

## **🧪 PHASE 2: TEST PLAN EXECUTION**
**Script**: `test-plan/phase2-test-plan-execution.sh`

**What it does**:
- **Step 1**: Validates all infrastructure components are running
- **Step 2**: Creates 200 test namespaces with proper labels
- **Step 3**: Deploys 800 objects (200 SAs + 400 ConfigMaps + 200 Deployments)
- **Step 4**: Executes controlled load testing (20 batches, 10 namespaces each)
- **Step 5**: Verifies system performance and stability

**When to run**: 
- After Phase 1 completes successfully
- When you want to run the complete test plan
- Before Phase 3 cleanup

**Prerequisites**: 
- Phase 1 must be completed
- EKS cluster must be ACTIVE
- Kyverno and monitoring must be running

---

## **🧹 PHASE 3: CLEAN K8S RESOURCES**
**Script**: `test-plan/phase3-cleanup-k8s.sh` *(to be created)*

**What it does**:
- Deletes all test namespaces (`load-test-*`)
- Removes all test objects (ServiceAccounts, ConfigMaps, Deployments)
- Cleans up policy reports generated during testing
- Leaves infrastructure intact for reuse

**When to run**: 
- After Phase 2 completes
- When you want to clean up test resources
- Before running Phase 2 again

**Prerequisites**: 
- Phase 2 must be completed
- Infrastructure should still be running

---

## **🗑️ PHASE 4: CLEAN AWS INFRASTRUCTURE**
**Script**: `setup/phase1/phase1-cleanup.sh`

**What it does**:
- Deletes EKS cluster and node groups
- Removes RDS PostgreSQL instance
- Cleans up all AWS resources created in Phase 1
- Removes Terraform state files

**When to run**: 
- When you're completely done with testing
- To save AWS costs
- Before recreating infrastructure

**Prerequisites**: 
- All testing completed
- No critical data to preserve

---

## **🔄 EXECUTION FLOW**

### **Complete Testing Cycle**:
```
Phase 1 → Phase 2 → Phase 3 → Phase 4
   ↓         ↓         ↓         ↓
Setup    Execute    Clean     Destroy
Infra    Tests     K8s       Everything
```

### **Reuse Infrastructure**:
```
Phase 1 → Phase 2 → Phase 3 → Phase 2 → Phase 3 → ... → Phase 4
   ↓         ↓         ↓         ↓         ↓              ↓
Setup    Execute    Clean     Execute    Clean         Destroy
Infra    Tests     K8s       Tests      K8s           Everything
```

---

## **📁 FILE STRUCTURE**

```
kyverno-postgresql-testing/
├── setup/
│   └── phase1/
│       ├── phase1-setup.sh          # Phase 1: Infrastructure
│       └── phase1-cleanup.sh        # Phase 4: Cleanup
├── test-plan/
│   ├── phase2-test-plan-execution.sh # Phase 2: Test execution
│   ├── phase3-cleanup-k8s.sh        # Phase 3: K8s cleanup *(to be created)*
│   └── load-testing-execution.sh    # Legacy: Phase 5 only
└── default-terraform-code/
    └── terraform-eks/               # Terraform EKS configuration
```

---

## **🎯 USAGE EXAMPLES**

### **First Time Setup**:
```bash
# 1. Create infrastructure
./setup/phase1/phase1-setup.sh

# 2. Run test plan
./test-plan/phase2-test-plan-execution.sh

# 3. Clean up test resources
./test-plan/phase3-cleanup-k8s.sh

# 4. When done, destroy infrastructure
./setup/phase1/phase1-cleanup.sh
```

### **Reuse Infrastructure for Multiple Test Runs**:
```bash
# 1. Infrastructure already exists from previous run
# 2. Run test plan again
./test-plan/phase2-test-plan-execution.sh

# 3. Clean up test resources
./test-plan/phase3-cleanup-k8s.sh

# 4. Repeat steps 2-3 as needed
# 5. When completely done, run Phase 4
./setup/phase1/phase1-cleanup.sh
```

---

## **⚠️ IMPORTANT NOTES**

1. **Phase 1 must complete successfully** before running Phase 2
2. **Phase 2 creates 800 objects** - ensure you have sufficient cluster resources
3. **Phase 3 preserves infrastructure** - use this for multiple test runs
4. **Phase 4 destroys everything** - only run when completely done
5. **Always verify infrastructure status** before running tests
6. **Monitor resource usage** during load testing

---

## **🔍 TROUBLESHOOTING**

### **Common Issues**:
- **Phase 2 fails on infrastructure check**: Run Phase 1 first
- **Load testing hangs**: Check Kyverno pod status and logs
- **Resource creation fails**: Verify cluster has sufficient capacity
- **Cleanup fails**: Check for stuck finalizers or dependencies

### **Debug Commands**:
```bash
# Check infrastructure status
kubectl get pods -A
aws eks describe-cluster --name report-server-test --region us-west-1

# Check test resources
kubectl get namespaces | grep load-test
kubectl get deployments -A | grep test-deployment

# Check Kyverno status
kubectl get pods -n kyverno
kubectl logs -n kyverno deployment/kyverno
```
