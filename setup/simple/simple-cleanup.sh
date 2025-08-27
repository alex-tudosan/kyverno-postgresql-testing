#!/bin/bash

# =============================================================================
# Simple Cleanup Script for Kyverno Reports Server
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CLUSTER_NAME="reports-server-test"
REGION="us-west-1"
PROFILE="devtest-sso"
RDS_INSTANCE_ID="reports-server-db"

echo -e "${BLUE}🧹 Simple Cleanup for Kyverno Reports Server${NC}"
echo "=============================================="

# Step 1: Delete EKS Cluster
echo -e "${BLUE}Step 1/3: Deleting EKS Cluster...${NC}"
eksctl delete cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --profile $PROFILE

echo -e "${GREEN}✅ EKS Cluster deletion initiated${NC}"

# Step 2: Delete RDS Database
echo -e "${BLUE}Step 2/3: Deleting RDS Database...${NC}"
aws rds delete-db-instance \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --skip-final-snapshot \
  --delete-automated-backups \
  --region $REGION \
  --profile $PROFILE

echo -e "${GREEN}✅ RDS Database deletion initiated${NC}"

# Wait for RDS deletion to complete before deleting subnet group
echo "Waiting for RDS deletion to complete..."
while true; do
  STATUS=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --region $REGION --profile $PROFILE --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo "deleted")

  if [[ "$STATUS" == "deleted" ]]; then
    break
  fi
  echo "RDS status: $STATUS (waiting for deletion...)"
  sleep 30
done

# Delete RDS subnet group
echo "Deleting RDS subnet group..."
aws rds delete-db-subnet-group --db-subnet-group-name reports-server-subnet-group --region $REGION --profile $PROFILE 2>/dev/null || echo "Subnet group may already be deleted"

# Step 3: Clean up local files
echo -e "${BLUE}Step 3/4: Cleaning up local files...${NC}"
rm -f .rds_password_$RDS_INSTANCE_ID

echo -e "${GREEN}✅ Local files cleaned up${NC}"

# Step 4: Final verification
echo -e "${BLUE}Step 4/4: Final verification...${NC}"
echo "Checking for any remaining resources..."

# Check for any remaining RDS instances
REMAINING_RDS=$(aws rds describe-db-instances --region $REGION --profile $PROFILE --query 'DBInstances[?contains(DBInstanceIdentifier, `reports-server`)].DBInstanceIdentifier' --output text 2>/dev/null || echo "")

if [[ -n "$REMAINING_RDS" ]]; then
  echo "⚠️  Warning: Remaining RDS instances: $REMAINING_RDS"
else
  echo "✅ No remaining RDS instances"
fi

# Check for any remaining subnet groups
REMAINING_SUBNET_GROUPS=$(aws rds describe-db-subnet-groups --region $REGION --profile $PROFILE --query 'DBSubnetGroups[?contains(DBSubnetGroupName, `reports-server`)].DBSubnetGroupName' --output text 2>/dev/null || echo "")

if [[ -n "$REMAINING_SUBNET_GROUPS" ]]; then
  echo "⚠️  Warning: Remaining subnet groups: $REMAINING_SUBNET_GROUPS"
else
  echo "✅ No remaining subnet groups"
fi

echo -e "\n${GREEN}🎉 Cleanup Complete!${NC}"
echo "=============================================="
echo "Note: EKS and RDS deletion may take 10-15 minutes to complete"
echo "You can check status in AWS Console"
