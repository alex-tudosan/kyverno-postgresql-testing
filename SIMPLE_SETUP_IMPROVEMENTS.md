# 🔧 Simple Setup Improvements for Policy Reports in PostgreSQL

## 🎯 **Goal**
Modify `simple-setup.sh` to achieve the same results as our successful phase1 setup: **policy reports stored in PostgreSQL database**.

## 🔑 **Key Changes Required**

### **1. 🚨 CRITICAL: Installation Order and Policy Management**

**Original (simple-setup.sh):**
```bash
helm install kyverno nirmata/kyverno \
  --set reportsServer.enabled=true \
  --set reportsServer.postgres.host=$RDS_ENDPOINT \
  --set reportsServer.postgres.database=$DB_NAME \
  --set reportsServer.postgres.username=$DB_USERNAME \
  --set reportsServer.postgres.password=$DB_PASSWORD
```

**Improved (CORRECT ORDER):**
```bash
# Step 1: Install Reports Server FIRST (before any policies exist)
helm install reports-server nirmata-reports-server/reports-server \
  --namespace reports-server \
  --create-namespace \
  --set db.host=$RDS_ENDPOINT \
  --set db.port=5432 \
  --set db.name=$DB_NAME \
  --set db.user=$DB_USERNAME \
  --set db.password=$DB_PASSWORD \
  --set config.etcd.enabled=false \
  --set apiServicesManagement.installApiServices.enabled=false

# Step 2: Install Kyverno (without policies first)
helm install kyverno nirmata/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set monitoring.enabled=true

# Step 3: Apply policies AFTER both are installed
kubectl apply -f policies/baseline/require-labels.yaml
kubectl apply -f policies/baseline/disallow-privileged-containers.yaml
```

**Why this order is CRITICAL:**
- **Reports Server installation is blocked by Kyverno policies** (require-labels, disallow-privileged-containers)
- **Install Reports Server first** when no policies exist
- **Then install Kyverno** 
- **Finally apply policies** to generate reports

### **2. Separate Reports Server Installation (CRITICAL)**

**Original (simple-setup.sh):**
```bash
helm install kyverno nirmata/kyverno \
  --set reportsServer.enabled=true \
  --set reportsServer.postgres.host=$RDS_ENDPOINT \
  --set reportsServer.postgres.database=$DB_NAME \
  --set reportsServer.postgres.username=$DB_USERNAME \
  --set reportsServer.postgres.password=$DB_PASSWORD
```

**Improved:**
```bash
# Install Kyverno without Reports Server
helm install kyverno nirmata/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set monitoring.enabled=true

# Install SEPARATE Reports Server
helm install reports-server nirmata-reports-server/reports-server \
  --namespace reports-server \
  --create-namespace \
  --set db.host=$RDS_ENDPOINT \
  --set db.port=5432 \
  --set db.name=$DB_NAME \
  --set db.user=$DB_USERNAME \
  --set db.password=$DB_PASSWORD \
  --set config.etcd.enabled=false \
  --set apiServicesManagement.installApiServices.enabled=false
```

**Why this change is critical:**
- The integrated Reports Server in `nirmata/kyverno` chart doesn't reliably connect to PostgreSQL
- The separate `nirmata-reports-server/reports-server` chart is specifically designed for PostgreSQL
- This ensures proper database table creation and data storage

### **3. Proper VPC Configuration**

**Original:**
```bash
--db-subnet-group-name default \
--vpc-security-group-ids $SECURITY_GROUP_ID
```

**Improved:**
```bash
# Get VPC ID from EKS cluster
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --profile $PROFILE --query 'cluster.resourcesVpcConfig.vpcId' --output text)

# Get subnets for RDS subnet group
RDS_SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --profile $PROFILE --query 'Subnets[0:2].SubnetId' --output text | tr '\t' ' ')

# Create RDS subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name reports-server-subnet-group \
  --subnet-ids $RDS_SUBNET_IDS

# Use the custom subnet group
--db-subnet-group-name reports-server-subnet-group \
--vpc-security-group-ids $SECURITY_GROUP_ID
```

**Why this change is important:**
- Ensures RDS is in the same VPC as EKS cluster
- Prevents VPC mismatch errors
- Enables proper network connectivity

### **4. Baseline Policies Installation**

**Original:** No policies installed

**Improved:**
```bash
# Apply baseline policies (this generates the policy reports)
kubectl apply -f policies/baseline/require-labels.yaml
kubectl apply -f policies/baseline/disallow-privileged-containers.yaml

# Create test resources to generate reports
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Pod
metadata:
  name: compliant-pod
  labels:
    app: test-app
    version: v1.0.0
spec:
  containers:
  - name: nginx
    image: nginx:latest
    securityContext:
      privileged: false
EOF
```

**Why this change is essential:**
- **No policies = No policy evaluations = No reports to store**
- Baseline policies generate the actual policy reports
- Test resources trigger policy evaluations

### **5. Database Verification**

**Original:** No database verification

**Improved:**
```bash
# Test database connection and show results
kubectl run db-test --rm -i --tty --image postgres:14 -- bash -c "
echo '=== Database Tables ==='
PGPASSWORD='$DB_PASSWORD' psql -h '$RDS_ENDPOINT' -U $DB_USERNAME -d $DB_NAME -c '\dt'

echo ''
echo '=== Total Policy Reports ==='
PGPASSWORD='$DB_PASSWORD' psql -h '$RDS_ENDPOINT' -U $DB_USERNAME -d $DB_NAME -c 'SELECT COUNT(*) as total_policy_reports FROM policyreports;'

echo ''
echo '=== Reports by Namespace ==='
PGPASSWORD='$DB_PASSWORD' psql -h '$RDS_ENDPOINT' -U $DB_USERNAME -d $DB_NAME -c 'SELECT namespace, COUNT(*) as report_count FROM policyreports GROUP BY namespace ORDER BY report_count DESC;'
"
```

**Why this change is valuable:**
- Verifies that setup actually worked
- Shows policy reports are being stored
- Provides immediate feedback on success

## 📊 **Expected Results Comparison**

### **Original simple-setup.sh:**
- ✅ EKS cluster created
- ✅ RDS database created
- ✅ Kyverno installed
- ❌ **No policy reports in database** (or very limited)
- ❌ **No baseline policies applied**
- ❌ **Reports Server may not connect to PostgreSQL**

### **Improved simple-setup.sh:**
- ✅ EKS cluster created
- ✅ RDS database created
- ✅ Kyverno installed
- ✅ **Reports Server properly connected to PostgreSQL**
- ✅ **Policy reports stored in database**
- ✅ **Baseline policies applied and working**
- ✅ **Database verification included**

## 🎯 **Root Cause Analysis**

The main issue with the original `simple-setup.sh` was:

1. **Integrated Reports Server unreliability**: The `reportsServer.enabled=true` in the `nirmata/kyverno` chart doesn't reliably connect to external PostgreSQL databases
2. **Installation order problem**: Reports Server installation is blocked by Kyverno policies
3. **No policy enforcement**: Without baseline policies, there are no policy evaluations to report
4. **No verification**: No way to confirm if the setup actually worked

## 🚀 **Implementation**

The improved version (`simple-setup-improved.sh`) addresses all these issues by:

1. **Installing Reports Server FIRST** (before any policies exist)
2. **Then installing Kyverno** (without policies)
3. **Finally applying policies** to generate reports
4. **Creating test resources** to trigger policy evaluations
5. **Verifying database connectivity** and showing results
6. **Proper VPC configuration** to ensure network connectivity

## 🚨 **Critical Installation Order**

```
1. EKS Cluster
2. RDS Database  
3. Reports Server (BEFORE policies)
4. Kyverno (without policies)
5. Baseline Policies (AFTER both are installed)
```

This approach mirrors what we successfully implemented in our phase1 setup and should produce the same results: **policy reports stored in PostgreSQL database**.
