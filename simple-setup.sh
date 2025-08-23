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
echo -e "${BLUE}Step 1/3: Creating EKS Cluster...${NC}"
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

# Step 2: Create RDS Database
echo -e "${BLUE}Step 2/3: Creating RDS Database...${NC}"

# Get default security group
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=default" \
  --query 'SecurityGroups[0].GroupId' \
  --output text \
  --region $REGION \
  --profile $PROFILE)

aws rds create-db-instance \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 14.12 \
  --master-username $DB_USERNAME \
  --master-user-password $DB_PASSWORD \
  --allocated-storage 20 \
  --storage-type gp2 \
  --db-subnet-group-name default \
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

# Step 3: Wait for RDS and Install Kyverno
echo -e "${BLUE}Step 3/3: Installing Kyverno with Reports Server...${NC}"

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
helm repo add nirmata https://nirmata.github.io/charts
helm repo update

helm install kyverno nirmata/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set reportsServer.enabled=true \
  --set reportsServer.postgres.host=$RDS_ENDPOINT \
  --set reportsServer.postgres.port=5432 \
  --set reportsServer.postgres.database=$DB_NAME \
  --set reportsServer.postgres.username=$DB_USERNAME \
  --set reportsServer.postgres.password=$DB_PASSWORD \
  --set monitoring.enabled=true

echo -e "${GREEN}✅ Kyverno with Reports Server installed${NC}"

# Final verification
echo -e "${BLUE}🔍 Final Verification:${NC}"
echo "EKS Cluster:"
kubectl get nodes

echo -e "\nKyverno Pods:"
kubectl get pods -n kyverno

echo -e "\nRDS Database:"
aws rds describe-db-instances \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --region $REGION \
  --profile $PROFILE \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address}' \
  --output table

echo -e "\n${GREEN}🎉 Setup Complete!${NC}"
echo "=================================="
echo "EKS Cluster: $CLUSTER_NAME"
echo "RDS Database: $RDS_INSTANCE_ID"
echo "Database Endpoint: $RDS_ENDPOINT"
echo "Password saved in: .rds_password_$RDS_INSTANCE_ID"
echo ""
echo "Next steps:"
echo "1. Access Grafana: kubectl port-forward -n kyverno svc/kyverno-grafana 3000:80"
echo "2. Test policies: kubectl apply -f policies/baseline/"
echo "3. View reports: Access Reports Server through Kyverno"
