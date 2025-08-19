#!/bin/bash

# Phase 1 Cleanup Script for PostgreSQL-based Reports Server Testing
# This script removes all resources created during Phase 1 testing

set -e

echo "🧹 Starting Phase 1 Cleanup: PostgreSQL-based Reports Server Testing"
echo "=================================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Load configuration if available
if [ -f "postgresql-testing-config.env" ]; then
    source postgresql-testing-config.env
    print_status "Loaded configuration from postgresql-testing-config.env"
else
    print_warning "Configuration file not found. Using default values."
    CLUSTER_NAME="reports-server-test"
    REGION="us-west-1"
    AWS_PROFILE="devtest-sso"
    RDS_INSTANCE_ID="reports-server-db"
fi

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    
    case $resource_type in
        "cluster")
            eksctl get cluster --name $resource_name --region $REGION > /dev/null 2>&1
            ;;
        "rds")
            aws rds describe-db-instances --db-instance-identifier $resource_name --profile $AWS_PROFILE > /dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to confirm deletion
confirm_deletion() {
    local resource_type=$1
    local resource_name=$2
    
    echo ""
    read -p "Do you want to delete the $resource_type '$resource_name'? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

print_status "Starting cleanup process..."

# Clean up Kubernetes resources
print_status "Cleaning up Kubernetes resources..."

# Delete test namespaces
print_status "Deleting test namespaces..."
kubectl delete namespace test-namespace --ignore-not-found=true > /dev/null 2>&1 || true

# Delete baseline policies
print_status "Deleting baseline policies..."
kubectl delete -f baseline-policies.yaml --ignore-not-found=true > /dev/null 2>&1 || true

# Clean up Reports Server and Kyverno
print_status "Cleaning up Reports Server and Kyverno..."
helm uninstall reports-server -n reports-server --ignore-not-found=true > /dev/null 2>&1 || true
helm uninstall kyverno -n kyverno-system --ignore-not-found=true > /dev/null 2>&1 || true

# Clean up monitoring
print_status "Cleaning up monitoring stack..."
helm uninstall monitoring -n monitoring --ignore-not-found=true > /dev/null 2>&1 || true

# Clean up namespaces
print_status "Cleaning up namespaces..."
kubectl delete namespace reports-server --ignore-not-found=true > /dev/null 2>&1 || true
kubectl delete namespace kyverno-system --ignore-not-found=true > /dev/null 2>&1 || true
kubectl delete namespace monitoring --ignore-not-found=true > /dev/null 2>&1 || true

print_success "Kubernetes resources cleaned up"

# Clean up RDS instance
print_status "Checking RDS instance status..."
if resource_exists "rds" "$RDS_INSTANCE_ID"; then
    print_status "RDS instance '$RDS_INSTANCE_ID' found"
    
    if confirm_deletion "RDS instance" "$RDS_INSTANCE_ID"; then
        print_status "Deleting RDS instance '$RDS_INSTANCE_ID'..."
        
        # Check if RDS is in a deletable state
        RDS_STATUS=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --query 'DBInstances[0].DBInstanceStatus' --output text --profile $AWS_PROFILE 2>/dev/null || echo "N/A")
        
        if [ "$RDS_STATUS" = "available" ] || [ "$RDS_STATUS" = "stopped" ]; then
            aws rds delete-db-instance \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --skip-final-snapshot \
  --delete-automated-backups \
  --profile $AWS_PROFILE
            
            print_status "Waiting for RDS instance to be deleted..."
            aws rds wait db-instance-deleted --db-instance-identifier $RDS_INSTANCE_ID --profile $AWS_PROFILE
            print_success "RDS instance deleted successfully"
        else
            print_warning "RDS instance is in state '$RDS_STATUS'. Cannot delete at this time."
            print_status "You may need to delete it manually from the AWS console."
        fi
    else
        print_status "Skipping RDS deletion"
    fi
else
    print_status "RDS instance '$RDS_INSTANCE_ID' not found"
fi

# Clean up RDS subnet group
print_status "Checking RDS subnet group..."
if aws rds describe-db-subnet-groups --db-subnet-group-name reports-server-subnet-group --profile $AWS_PROFILE > /dev/null 2>&1; then
    print_status "RDS subnet group 'reports-server-subnet-group' found"
    
    if confirm_deletion "RDS subnet group" "reports-server-subnet-group"; then
        print_status "Deleting RDS subnet group..."
        aws rds delete-db-subnet-group --db-subnet-group-name reports-server-subnet-group --profile $AWS_PROFILE
        print_success "RDS subnet group deleted successfully"
    else
        print_status "Skipping RDS subnet group deletion"
    fi
else
    print_status "RDS subnet group 'reports-server-subnet-group' not found"
fi

# Clean up EKS cluster
print_status "Checking EKS cluster status..."
if resource_exists "cluster" "$CLUSTER_NAME"; then
    print_status "EKS cluster '$CLUSTER_NAME' found"
    
    if confirm_deletion "EKS cluster" "$CLUSTER_NAME"; then
        print_status "Deleting EKS cluster '$CLUSTER_NAME'..."
        eksctl delete cluster --name $CLUSTER_NAME --region $REGION --profile $AWS_PROFILE
        print_success "EKS cluster deleted successfully"
    else
        print_status "Skipping EKS cluster deletion"
    fi
else
    print_status "EKS cluster '$CLUSTER_NAME' not found"
fi

# Clean up local files
print_status "Cleaning up local files..."
rm -f postgresql-testing-config.env > /dev/null 2>&1 || true
rm -f eks-cluster-config-phase1.yaml > /dev/null 2>&1 || true
rm -f baseline-policies.yaml > /dev/null 2>&1 || true
rm -f test-violations-pod.yaml > /dev/null 2>&1 || true
rm -f phase1-monitoring-*.csv > /dev/null 2>&1 || true

print_success "Local files cleaned up"

# Final status check
echo ""
echo "=========================================="
echo "           CLEANUP SUMMARY"
echo "=========================================="

# Check what's left
echo "Checking remaining resources..."

# Check EKS clusters
if eksctl get cluster --region $REGION 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    print_warning "EKS cluster '$CLUSTER_NAME' still exists"
else
    print_success "EKS cluster '$CLUSTER_NAME' cleaned up"
fi

# Check RDS instances
if aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --profile $AWS_PROFILE > /dev/null 2>&1; then
    print_warning "RDS instance '$RDS_INSTANCE_ID' still exists"
else
    print_success "RDS instance '$RDS_INSTANCE_ID' cleaned up"
fi

# Check RDS subnet groups
if aws rds describe-db-subnet-groups --db-subnet-group-name reports-server-subnet-group --profile $AWS_PROFILE > /dev/null 2>&1; then
    print_warning "RDS subnet group 'reports-server-subnet-group' still exists"
else
    print_success "RDS subnet group 'reports-server-subnet-group' cleaned up"
fi

# Check Kubernetes context
if kubectl config current-context 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    print_warning "Kubernetes context still points to '$CLUSTER_NAME'"
    echo "  You may want to switch to a different context:"
    echo "  kubectl config use-context <your-default-context>"
else
    print_success "Kubernetes context cleaned up"
fi

echo ""
print_success "Phase 1 cleanup completed!"
echo ""
echo "=== Cost Savings ==="
echo "By cleaning up these resources, you've stopped incurring costs for:"
echo "  - EKS Control Plane: ~$73/month"
echo "  - EKS Nodes (2x t3a.medium): ~$30/month"
echo "  - RDS PostgreSQL (db.t3.micro): ~$15/month"
echo "  - Storage: ~$3/month"
echo "  Total savings: ~$121/month"
echo ""
echo "=== Next Steps ==="
echo "If you want to run Phase 1 again:"
echo "  ./postgresql-testing/phase1-setup.sh"
echo ""
echo "If you want to proceed to Phase 2:"
echo "  ./postgresql-testing/phase2-setup.sh"
echo ""
print_success "Cleanup completed successfully! 🎉"
