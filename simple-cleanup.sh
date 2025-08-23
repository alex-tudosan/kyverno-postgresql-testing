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

# Step 3: Clean up local files
echo -e "${BLUE}Step 3/3: Cleaning up local files...${NC}"
rm -f .rds_password_$RDS_INSTANCE_ID

echo -e "${GREEN}✅ Local files cleaned up${NC}"

echo -e "\n${GREEN}🎉 Cleanup Complete!${NC}"
echo "=============================================="
echo "Note: EKS and RDS deletion may take 10-15 minutes to complete"
echo "You can check status in AWS Console"
