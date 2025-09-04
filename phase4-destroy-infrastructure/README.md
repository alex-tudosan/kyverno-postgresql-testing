# 🗑️ PHASE 4: DESTROY AWS INFRASTRUCTURE

## 📋 **Purpose**
This phase completely destroys all AWS infrastructure created during Phase 1, including EKS cluster, RDS, and all associated resources.

## 🎯 **What This Phase Does**

### **Complete Infrastructure Destruction**
- **EKS Cluster**: `report-server-test` and all node groups
- **RDS PostgreSQL**: `reports-server-db` instance
- **EC2 Instances**: All worker nodes and associated resources
- **Security Groups**: EKS and RDS security groups
- **Subnet Groups**: RDS subnet groups
- **IAM Roles**: EKS service roles and policies
- **Terraform State**: All state files and lock files

### **What Gets Destroyed**
- **Everything** created in Phase 1
- **All data** stored in PostgreSQL
- **All Kubernetes resources** (including Kyverno, monitoring)
- **All AWS resources** in the testing environment

## 📁 **Files in This Phase**

### **Core Scripts**
- `phase1-cleanup.sh` - **MAIN SCRIPT** (run this)

## 🎯 **How to Use**

### **Prerequisites**
- **Phase 1 must be completed** (infrastructure must exist)
- **Phase 2 and 3 completed** (or test resources cleaned up)
- **No critical data** to preserve
- **AWS CLI configured** with appropriate permissions

### **Run the Destruction**
```bash
# Make script executable
chmod +x phase1-cleanup.sh

# Execute the infrastructure destruction
./phase1-cleanup.sh
```

### **Expected Duration**
- **EKS cleanup**: 10-15 minutes
- **RDS cleanup**: 5-10 minutes
- **Total**: ~15-25 minutes

## ⚠️ **CRITICAL WARNINGS**

### **This Phase is DESTRUCTIVE**
- **ALL DATA WILL BE LOST** permanently
- **ALL INFRASTRUCTURE WILL BE DESTROYED**
- **ALL KUBERNETES RESOURCES WILL BE DELETED**
- **This action cannot be undone**

### **Before Running**
- **Backup any important data** from PostgreSQL
- **Export any important metrics** from Grafana
- **Ensure you're done with testing**
- **Verify you have the correct AWS account/region**

## 🔄 **Destruction Process**

### **Step 1: Resource Discovery**
- Identifies all AWS resources to be deleted
- Reports resource counts and types
- Asks for user confirmation

### **Step 2: Kubernetes Cleanup**
- Deletes all running pods
- Removes EKS node groups
- Waits for node group deletion

### **Step 3: EKS Cluster Deletion**
- Deletes the EKS cluster
- Removes associated IAM roles and policies
- Cleans up security groups and subnets

### **Step 4: RDS Cleanup**
- Deletes PostgreSQL RDS instance
- Removes RDS subnet groups
- Cleans up associated security groups

### **Step 5: Terraform Cleanup**
- Removes all Terraform state files
- Deletes `.terraform` directory
- Removes lock files

## 📊 **What Gets Destroyed**

### **AWS Resources (Completely Removed)**
- EKS cluster `report-server-test`
- EKS node groups and worker nodes
- RDS instance `reports-server-db`
- RDS subnet groups
- Security groups for EKS and RDS
- IAM roles and policies
- VPC subnets (if created by Terraform)

### **Kubernetes Resources (Completely Removed)**
- All namespaces (kyverno, monitoring, etc.)
- All pods, deployments, services
- All ConfigMaps, Secrets, ServiceAccounts
- All policy reports and Kyverno data

### **Data Loss (Permanent)**
- All PostgreSQL data
- All policy reports
- All monitoring metrics
- All test results and logs

## 🔍 **Monitoring During Destruction**

### **Check Progress**
```bash
# Monitor EKS cluster status
aws eks describe-cluster --name report-server-test --region us-west-1

# Monitor RDS instance status
aws rds describe-db-instances --db-instance-identifier reports-server-db --region us-west-1

# Monitor remaining AWS resources
aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/report-server-test,Values=owned" --region us-west-1
```

### **Check Kubernetes Status**
```bash
# Monitor remaining pods
kubectl get pods -A

# Monitor remaining namespaces
kubectl get namespaces
```

## 🚨 **Troubleshooting**

### **Common Issues**
- **EKS cluster stuck in DELETING**: May need manual intervention
- **RDS instance stuck in DELETING**: Check for dependencies
- **Resources not deleted**: Check for finalizers or dependencies

### **Manual Cleanup (if needed)**
```bash
# Force delete EKS cluster
aws eks delete-cluster --name report-server-test --region us-west-1 --force

# Force delete RDS instance
aws rds delete-db-instance --db-instance-identifier reports-server-db --region us-west-1 --skip-final-snapshot --delete-automated-backups
```

## 🧹 **After Completion**

### **Verification**
- No EKS clusters should exist
- No RDS instances should exist
- No test-related AWS resources should remain
- Clean slate for new infrastructure creation

### **Next Steps**
1. **Run Phase 1** to create new infrastructure (if needed)
2. **Start fresh** with new testing environment
3. **Verify AWS costs** are reduced

## 💡 **Best Practices**

### **When to Use Phase 4**
- **Completely done with testing**
- **Want to save AWS costs**
- **Need to start fresh**
- **Moving to different AWS account/region**

### **When NOT to Use Phase 4**
- **Still need infrastructure** for testing
- **Have important data** to preserve
- **Infrastructure is shared** with other users
- **Uncertain about future testing needs**

## 💰 **Cost Impact**

### **What You'll Save**
- **EKS cluster costs** (~$0.10/hour per node)
- **RDS instance costs** (~$0.17/hour for db.t3.micro)
- **EC2 instance costs** (~$0.0104/hour per t3.medium)
- **Data transfer costs** (if any)

### **Estimated Monthly Savings**
- **Small cluster (2 nodes)**: ~$15-20/month
- **Medium cluster (3-5 nodes)**: ~$25-40/month
- **Large cluster (5+ nodes)**: ~$40+/month
