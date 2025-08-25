#!/bin/bash

# =============================================================================
# Improved Simple Setup Script for Kyverno Reports Server
# =============================================================================
# This script creates the same infrastructure as the complex setup but with
# modifications to ensure policy reports are stored in PostgreSQL database.
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CLUSTER_NAME="reports-server-test"
REGION="us-west-1"
PROFILE="devtest-sso"
RDS_INSTANCE_ID="reports-server-db"
DB_NAME="reportsdb"
DB_USERNAME="reportsuser"

# Generate password
DB_PASSWORD=$(openssl rand -hex 16)
echo "$DB_PASSWORD" > .rds_password_$RDS_INSTANCE_ID
chmod 600 .rds_password_$RDS_INSTANCE_ID

echo -e "${BLUE}🚀 Improved Simple Kyverno Reports Server Setup${NC}"
echo "=================================================="

# Step 1: Create EKS Cluster
echo -e "${BLUE}Step 1/5: Creating EKS Cluster...${NC}"
eksctl create cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --profile $PROFILE \
  --nodegroup-name workers \
  --node-type t3a.medium \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 2 \
  --managed

echo -e "${GREEN}✅ EKS Cluster created successfully${NC}"

# Step 2: Create RDS Database with proper VPC configuration
echo -e "${BLUE}Step 2/5: Creating RDS Database...${NC}"

# Get VPC ID from EKS cluster
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --profile $PROFILE --query 'cluster.resourcesVpcConfig.vpcId' --output text)

# Get subnets for RDS subnet group
RDS_SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --profile $PROFILE --query 'Subnets[0:2].SubnetId' --output text | tr '\t' ' ')

# Create RDS subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name reports-server-subnet-group \
  --db-subnet-group-description "Subnet group for Reports Server RDS" \
  --subnet-ids $RDS_SUBNET_IDS \
  --region $REGION \
  --profile $PROFILE 2>/dev/null || echo "Subnet group may already exist"

# Get default security group
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" \
  --query 'SecurityGroups[0].GroupId' \
  --output text \
  --region $REGION \
  --profile $PROFILE)

# Configure security group for PostgreSQL access
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol tcp \
  --port 5432 \
  --cidr 0.0.0.0/0 \
  --region $REGION \
  --profile $PROFILE 2>/dev/null || echo "Security group rule may already exist"

# Create RDS instance
aws rds create-db-instance \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 14.12 \
  --master-username $DB_USERNAME \
  --master-user-password $DB_PASSWORD \
  --allocated-storage 20 \
  --storage-type gp2 \
  --db-subnet-group-name reports-server-subnet-group \
  --vpc-security-group-ids $SECURITY_GROUP_ID \
  --backup-retention-period 7 \
  --no-multi-az \
  --auto-minor-version-upgrade \
  --publicly-accessible \
  --storage-encrypted \
  --db-name $DB_NAME \
  --region $REGION \
  --profile $PROFILE

echo -e "${GREEN}✅ RDS Database creation initiated${NC}"

# Step 3: Wait for RDS and Install Reports Server FIRST
echo -e "${BLUE}Step 3/5: Installing Reports Server (before Kyverno)...${NC}"

echo "Waiting for RDS to be ready..."
while true; do
  STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier $RDS_INSTANCE_ID \
    --region $REGION \
    --profile $PROFILE \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text 2>/dev/null || echo "creating")
  
  if [[ "$STATUS" == "available" ]]; then
    break
  fi
  
  echo "RDS status: $STATUS (waiting...)"
  sleep 30
done

# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --region $REGION \
  --profile $PROFILE \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo "RDS endpoint: $RDS_ENDPOINT"

# Add Helm repositories
helm repo add nirmata https://nirmata.github.io/charts
helm repo add nirmata-reports-server https://nirmata.github.io/reports-server
helm repo add kyverno https://kyverno.github.io/charts
helm repo update

# Install Reports Server FIRST (before any policies exist)
echo "Installing Reports Server..."
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

# Wait for Reports Server to be ready
echo "Waiting for Reports Server to be ready..."
kubectl wait --for=condition=ready pods --all -n reports-server --timeout=5m

echo -e "${GREEN}✅ Reports Server installed successfully${NC}"

# Step 4: Install Kyverno (without policies first)
echo -e "${BLUE}Step 4/5: Installing Kyverno...${NC}"

echo "Installing Kyverno..."
helm install kyverno nirmata/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set monitoring.enabled=true

# Wait for Kyverno to be ready
echo "Waiting for Kyverno to be ready..."
kubectl wait --for=condition=ready pods --all -n kyverno --timeout=5m

echo -e "${GREEN}✅ Kyverno installed successfully${NC}"

# Step 5: Install baseline policies to generate reports
echo -e "${BLUE}Step 5/5: Installing baseline policies...${NC}"

# Apply baseline policies (this generates the policy reports)
kubectl apply -f policies/baseline/require-labels.yaml
kubectl apply -f policies/baseline/disallow-privileged-containers.yaml

echo -e "${GREEN}✅ Baseline policies applied${NC}"

# Create some test resources to generate policy reports
echo "Creating test resources to generate policy reports..."
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
---
apiVersion: v1
kind: Pod
metadata:
  name: compliant-pod-2
  labels:
    app: web-app
    version: v2.1.0
spec:
  containers:
  - name: web
    image: httpd:latest
    securityContext:
      privileged: false
EOF

echo -e "${GREEN}✅ Test resources created${NC}"

# Wait a moment for reports to be generated
echo "Waiting for policy reports to be generated..."
sleep 30

# Final verification
echo -e "${BLUE}🔍 Final Verification:${NC}"
echo "EKS Cluster:"
kubectl get nodes

echo -e "\nKyverno Pods:"
kubectl get pods -n kyverno

echo -e "\nReports Server Pods:"
kubectl get pods -n reports-server

echo -e "\nPolicy Reports:"
kubectl get policyreports -A

echo -e "\nRDS Database:"
aws rds describe-db-instances \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --region $REGION \
  --profile $PROFILE \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address}' \
  --output table

# Test database connection and show results
echo -e "\n${BLUE}📊 Database Query Results:${NC}"
echo "Testing database connection and showing policy reports..."

# Create a temporary pod to query the database
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

echo -e "\n${GREEN}🎉 Setup Complete!${NC}"
echo "=================================================="
echo "EKS Cluster: $CLUSTER_NAME"
echo "RDS Database: $RDS_INSTANCE_ID"
echo "Database Endpoint: $RDS_ENDPOINT"
echo "Password saved in: .rds_password_$RDS_INSTANCE_ID"
echo ""
echo "✅ Policy reports are now being stored in PostgreSQL!"
echo ""
echo "Next steps:"
echo "1. Query database: Use the commands in database-commands.txt"
echo "2. Access Grafana: kubectl port-forward -n kyverno svc/kyverno-grafana 3000:80"
echo "3. Create more test resources to generate additional reports"
echo "4. When done: ./simple-cleanup.sh"
