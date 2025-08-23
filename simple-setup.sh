#!/bin/bash

# =============================================================================
# Simple Setup Script for Kyverno Reports Server
# =============================================================================
# This script creates the same infrastructure as the complex setup but with
# minimal steps and maximum reliability.
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

echo -e "${BLUE}🚀 Simple Kyverno Reports Server Setup${NC}"
echo "=================================="

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
  --managed \
  --tags DoNotDelete=true

echo -e "${GREEN}✅ EKS Cluster created successfully with DoNotDelete tag${NC}"

# Step 2: Create RDS Database
echo -e "${BLUE}Step 2/5: Creating RDS Database...${NC}"

# Get EKS VPC ID and security group from the same VPC
echo "Getting EKS VPC configuration..."
EKS_VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --profile $PROFILE --query 'cluster.resourcesVpcConfig.vpcId' --output text)
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$EKS_VPC_ID" "Name=group-name,Values=default" --region $REGION --query 'SecurityGroups[0].GroupId' --output text --profile $PROFILE)

echo "EKS VPC ID: $EKS_VPC_ID"
echo "Security Group ID: $SECURITY_GROUP_ID"

# Get public subnets from EKS VPC (those with internet gateway routes)
echo "Getting public subnets from EKS VPC..."
PUBLIC_SUBNETS=$(aws ec2 describe-subnets --region $REGION --profile $PROFILE --filters "Name=vpc-id,Values=$EKS_VPC_ID" "Name=map-public-ip-on-launch,Values=true" --query 'Subnets[].SubnetId' --output text)

# Take first two public subnets for RDS subnet group
SUBNET_1=$(echo $PUBLIC_SUBNETS | cut -d' ' -f1)
SUBNET_2=$(echo $PUBLIC_SUBNETS | cut -d' ' -f2)

echo "Using public subnets: $SUBNET_1, $SUBNET_2"

# Create RDS subnet group with public subnets
echo "Creating RDS subnet group..."
aws rds create-db-subnet-group \
  --db-subnet-group-name reports-server-subnet-group \
  --db-subnet-group-description "Subnet group for reports-server RDS" \
  --subnet-ids $SUBNET_1 $SUBNET_2 \
  --region $REGION \
  --profile $PROFILE 2>/dev/null || echo "Subnet group may already exist"

# Configure security group to allow PostgreSQL access
echo "Configuring security group for PostgreSQL access..."
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol tcp \
  --port 5432 \
  --cidr 0.0.0.0/0 \
  --region $REGION \
  --profile $PROFILE 2>/dev/null || echo "Security group rule may already exist"

# Create RDS instance with correct VPC configuration
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
  --tags Key=DoNotDelete,Value=true \
  --region $REGION \
  --profile $PROFILE

echo -e "${GREEN}✅ RDS Database creation initiated with DoNotDelete tag${NC}"

# Step 3: Install Full Monitoring Stack
echo -e "${BLUE}Step 3/5: Installing Full Monitoring Stack...${NC}"

# Add Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add nirmata https://nirmata.github.io/charts
helm repo update

# Install full Prometheus stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.enabled=true \
  --set alertmanager.enabled=true

echo -e "${GREEN}✅ Full monitoring stack installed${NC}"

# Step 4: Wait for RDS and Install Kyverno with Reports Server
echo -e "${BLUE}Step 4/5: Installing Kyverno with Reports Server...${NC}"

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

# Install Kyverno with Reports Server
helm install kyverno nirmata/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set reportsServer.enabled=true \
  --set reportsServer.postgres.host=$RDS_ENDPOINT \
  --set reportsServer.postgres.port=5432 \
  --set reportsServer.postgres.database=$DB_NAME \
  --set reportsServer.postgres.username=$DB_USERNAME \
  --set reportsServer.postgres.password=$DB_PASSWORD

echo -e "${GREEN}✅ Kyverno with Reports Server installed${NC}"

# Step 5: Apply ServiceMonitors and Policies
echo -e "${BLUE}Step 5/5: Applying ServiceMonitors and Policies...${NC}"

# Apply ServiceMonitors
kubectl apply -f reports-server-servicemonitor.yaml
kubectl apply -f kyverno-servicemonitor.yaml

# Apply baseline policies
kubectl apply -f policies/baseline/

echo -e "${GREEN}✅ ServiceMonitors and policies applied${NC}"

# Final verification
echo -e "${BLUE}🔍 Final Verification:${NC}"
echo "EKS Cluster:"
kubectl get nodes

echo -e "\nMonitoring Stack:"
kubectl get pods -n monitoring

echo -e "\nKyverno Pods:"
kubectl get pods -n kyverno

echo -e "\nRDS Database:"
aws rds describe-db-instances \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --region $REGION \
  --profile $PROFILE \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address}' \
  --output table

echo -e "\nServiceMonitors:"
kubectl get servicemonitors -A

echo -e "\nPolicies:"
kubectl get clusterpolicies

echo -e "\n${GREEN}🎉 Setup Complete!${NC}"
echo "=================================="
echo "EKS Cluster: $CLUSTER_NAME (tagged: DoNotDelete=true)"
echo "RDS Database: $RDS_INSTANCE_ID (tagged: DoNotDelete=true)"
echo "Database Endpoint: $RDS_ENDPOINT"
echo "Password saved in: .rds_password_$RDS_INSTANCE_ID"
echo ""
echo "Next steps:"
echo "1. Access Grafana: kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80"
echo "2. Access Prometheus: kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090"
echo "3. View reports: Access Reports Server through Kyverno"
echo "4. Check monitoring: kubectl get servicemonitors -A"
echo ""
echo -e "${BLUE}📊 Database Commands:${NC}"
echo "=================================="
echo "Connect & List Tables:"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h \"$RDS_ENDPOINT\" -U $DB_USERNAME -d $DB_NAME -c \"\\dt\""
echo ""
echo "Count Total Reports:"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h \"$RDS_ENDPOINT\" -U $DB_USERNAME -d $DB_NAME -c \"SELECT COUNT(*) as total_policy_reports FROM policyreports;\""
echo ""
echo "View Recent Reports:"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h \"$RDS_ENDPOINT\" -U $DB_USERNAME -d $DB_NAME -c \"SELECT name, namespace, report->>'summary' as summary FROM policyreports ORDER BY name DESC LIMIT 5;\""
echo ""
echo "View Reports by Namespace:"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h \"$RDS_ENDPOINT\" -U $DB_USERNAME -d $DB_NAME -c \"SELECT namespace, COUNT(*) as report_count FROM policyreports GROUP BY namespace ORDER BY report_count DESC;\""
echo ""
echo "View Failed Reports:"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h \"$RDS_ENDPOINT\" -U $DB_USERNAME -d $DB_NAME -c \"SELECT name, namespace, report->>'summary' as summary FROM policyreports WHERE report->>'summary' LIKE '%\\\"fail\\\":%' AND report->>'summary' NOT LIKE '%\\\"fail\\\": 0%';\""
echo ""
echo "Interactive Session:"
echo "PGPASSWORD=\"$DB_PASSWORD\" psql -h \"$RDS_ENDPOINT\" -U $DB_USERNAME -d $DB_NAME"
