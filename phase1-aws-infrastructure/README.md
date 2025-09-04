# 🚀 PHASE 1: AWS INFRASTRUCTURE SETUP

## 📋 **Purpose**
This phase creates the complete AWS infrastructure needed for Kyverno + PostgreSQL testing.

## 🏗️ **What This Phase Creates**
- **EKS Cluster**: `report-server-test` via Terraform
- **RDS PostgreSQL**: Database for storing policy reports
- **Monitoring Stack**: Grafana + Prometheus for metrics
- **Kyverno**: Policy engine installation and configuration
- **Reports Server**: Connects Kyverno to PostgreSQL

## 📁 **Files in This Phase**

### **Core Scripts**
- `phase1-setup.sh` - Main setup script (run this first)
- `phase1-cleanup.sh` - Infrastructure cleanup script

### **Configuration**
- `config.sh` - Environment variables and settings
- `create-secrets.sh` - Kubernetes secrets creation

### **Terraform Configuration**
- `default-terraform-code/` - EKS cluster Terraform configuration
  - `terraform-eks/` - Main Terraform module
  - `variables.tf` - Cluster configuration variables

## 🎯 **How to Use**

### **First Time Setup**
```bash
# 1. Ensure AWS CLI is configured
aws configure list

# 2. Run the setup script
./phase1-setup.sh

# 3. Wait for completion (takes 15-20 minutes)
```

### **Prerequisites**
- AWS CLI configured with appropriate permissions
- Terraform installed
- kubectl configured
- Sufficient AWS quota for EKS and RDS

## ⚠️ **Important Notes**
- This phase takes 15-20 minutes to complete
- Creates resources that incur AWS costs
- EKS cluster name is hardcoded to `report-server-test`
- RDS instance name is `reports-server-db`

## 🔍 **Verification**
After completion, verify:
```bash
# Check EKS cluster
aws eks describe-cluster --name report-server-test --region us-west-1

# Check Kyverno pods
kubectl get pods -n kyverno

# Check monitoring
kubectl get pods -n monitoring

# Check RDS
aws rds describe-db-instances --db-instance-identifier reports-server-db --region us-west-1
```

## 🧹 **Cleanup**
When you're completely done with testing:
```bash
./phase1-cleanup.sh
```

**Warning**: This destroys ALL infrastructure and data!
