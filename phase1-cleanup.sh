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
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output with timestamps
print_status() {
    echo -e "${BLUE}[$(date +%H:%M:%S)] [INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[$(date +%H:%M:%S)] [SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[$(date +%H:%M:%S)] [WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[$(date +%H:%M:%S)] [ERROR]${NC} $1"
}

print_progress() {
    echo -e "${PURPLE}[$(date +%H:%M:%S)] [PROGRESS]${NC} $1"
}

# Function to show progress bar
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))
    
    printf "\r${CYAN}[PROGRESS]${NC} ["
    printf "%${completed}s" | tr ' ' '#'
    printf "%${remaining}s" | tr ' ' '-'
    printf "] %d%%" $percentage
}

# Function to retry commands with exponential backoff
retry_command() {
    local max_attempts=$1
    local delay=$2
    local command="$3"
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if eval "$command"; then
            return 0
        else
            if [ $attempt -eq $max_attempts ]; then
                print_error "Command failed after $max_attempts attempts: $command"
                return 1
            fi
            print_warning "Command failed (attempt $attempt/$max_attempts), retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))  # Exponential backoff
            ((attempt++))
        fi
    done
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type=$1
    local resource_name=$2
    local timeout_minutes=${3:-10}
    local max_attempts=$((timeout_minutes * 6))  # Check every 10 seconds
    
    print_status "Waiting for $resource_type '$resource_name' to be deleted (timeout: ${timeout_minutes} minutes)..."
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        show_progress $attempt $max_attempts
        
        # Check if resource still exists
        case $resource_type in
            "cluster")
                if ! eksctl get cluster --name $resource_name --region $REGION --profile $AWS_PROFILE &>/dev/null; then
                    echo ""  # New line after progress bar
                    print_success "$resource_type '$resource_name' deleted successfully!"
                    return 0
                fi
                ;;
            "rds")
                if ! aws rds describe-db-instances --db-instance-identifier $resource_name --profile $AWS_PROFILE &>/dev/null; then
                    echo ""  # New line after progress bar
                    print_success "$resource_type '$resource_name' deleted successfully!"
                    return 0
                fi
                ;;
            "subnet-group")
                if ! aws rds describe-db-subnet-groups --db-subnet-group-name $resource_name --profile $AWS_PROFILE &>/dev/null; then
                    echo ""  # New line after progress bar
                    print_success "$resource_type '$resource_name' deleted successfully!"
                    return 0
                fi
                ;;
        esac
        
        sleep 10
        ((attempt++))
    done
    
    echo ""  # New line after progress bar
    print_error "$resource_type '$resource_name' did not get deleted within ${timeout_minutes} minutes"
    return 1
}

# Load configuration if available
CONFIG_FOUND=false
for config_file in postgresql-testing-config-*.env postgresql-testing-config.env; do
    if [ -f "$config_file" ]; then
        source "$config_file"
        print_status "Loaded configuration from $config_file"
        CONFIG_FOUND=true
        break
    fi
done

if [ "$CONFIG_FOUND" = false ]; then
    print_warning "No configuration file found. Using default values."
    CLUSTER_NAME="reports-server-test"
    REGION="us-west-1"
    AWS_PROFILE="devtest-sso"
    RDS_INSTANCE_ID="reports-server-db"
    TIMESTAMP=""
fi

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    
    case $resource_type in
        "cluster")
            eksctl get cluster --name $resource_name --region $REGION --profile $AWS_PROFILE > /dev/null 2>&1
            ;;
        "rds")
            aws rds describe-db-instances --db-instance-identifier $resource_name --profile $AWS_PROFILE > /dev/null 2>&1
            ;;
        "subnet-group")
            aws rds describe-db-subnet-groups --db-subnet-group-name $resource_name --profile $AWS_PROFILE > /dev/null 2>&1
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

# Function to force delete namespace
force_delete_namespace() {
    local namespace=$1
    print_status "Force deleting namespace '$namespace'..."
    
    # Delete all resources in namespace
    kubectl delete all --all -n $namespace --ignore-not-found=true > /dev/null 2>&1 || true
    
    # Force delete the namespace
    kubectl delete namespace $namespace --force --grace-period=0 --ignore-not-found=true > /dev/null 2>&1 || true
    
    # Wait for namespace deletion
    local attempt=1
    while [ $attempt -le 30 ]; do
        if ! kubectl get namespace $namespace &>/dev/null; then
            print_success "Namespace '$namespace' deleted successfully"
            return 0
        fi
        sleep 2
        ((attempt++))
    done
    
    print_warning "Namespace '$namespace' may still exist. You may need to delete it manually."
    return 1
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

# Clean up Reports Server and Kyverno with retry
print_status "Cleaning up Reports Server and Kyverno..."
retry_command 3 10 "helm uninstall reports-server -n reports-server --ignore-not-found=true > /dev/null 2>&1 || true"
retry_command 3 10 "helm uninstall kyverno -n kyverno-system --ignore-not-found=true > /dev/null 2>&1 || true"

# Clean up monitoring with retry
print_status "Cleaning up monitoring stack..."
retry_command 3 10 "helm uninstall monitoring -n monitoring --ignore-not-found=true > /dev/null 2>&1 || true"

# Clean up namespaces with force delete
print_status "Cleaning up namespaces..."
force_delete_namespace "reports-server"
force_delete_namespace "kyverno-system"
force_delete_namespace "monitoring"

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
            if retry_command 3 30 "aws rds delete-db-instance --db-instance-identifier $RDS_INSTANCE_ID --skip-final-snapshot --delete-automated-backups --profile $AWS_PROFILE"; then
                print_status "RDS deletion initiated. Waiting for completion..."
                if wait_for_deletion "rds" "$RDS_INSTANCE_ID" 15; then
                    print_success "RDS instance deleted successfully"
                else
                    print_warning "RDS instance deletion may still be in progress"
                fi
            else
                print_error "Failed to delete RDS instance"
            fi
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
SUBNET_GROUP_NAME="reports-server-subnet-group"
if [ -n "$TIMESTAMP" ]; then
    SUBNET_GROUP_NAME="reports-server-subnet-group-${TIMESTAMP}"
fi

if resource_exists "subnet-group" "$SUBNET_GROUP_NAME"; then
    print_status "RDS subnet group '$SUBNET_GROUP_NAME' found"
    
    if confirm_deletion "RDS subnet group" "$SUBNET_GROUP_NAME"; then
        print_status "Deleting RDS subnet group..."
        if retry_command 3 30 "aws rds delete-db-subnet-group --db-subnet-group-name $SUBNET_GROUP_NAME --profile $AWS_PROFILE"; then
            if wait_for_deletion "subnet-group" "$SUBNET_GROUP_NAME" 5; then
                print_success "RDS subnet group deleted successfully"
            else
                print_warning "RDS subnet group deletion may still be in progress"
            fi
        else
            print_error "Failed to delete RDS subnet group"
        fi
    else
        print_status "Skipping RDS subnet group deletion"
    fi
else
    print_status "RDS subnet group '$SUBNET_GROUP_NAME' not found"
fi

# Clean up EKS cluster
print_status "Checking EKS cluster status..."
if resource_exists "cluster" "$CLUSTER_NAME"; then
    print_status "EKS cluster '$CLUSTER_NAME' found"
    
    if confirm_deletion "EKS cluster" "$CLUSTER_NAME"; then
        print_status "Deleting EKS cluster '$CLUSTER_NAME'..."
        if retry_command 3 60 "eksctl delete cluster --name $CLUSTER_NAME --region $REGION --profile $AWS_PROFILE"; then
            print_status "EKS cluster deletion initiated. Waiting for completion..."
            if wait_for_deletion "cluster" "$CLUSTER_NAME" 20; then
                print_success "EKS cluster deleted successfully"
            else
                print_warning "EKS cluster deletion may still be in progress"
            fi
        else
            print_error "Failed to delete EKS cluster"
            print_status "You may need to delete it manually from the AWS console"
        fi
    else
        print_status "Skipping EKS cluster deletion"
    fi
else
    print_status "EKS cluster '$CLUSTER_NAME' not found"
fi

# Clean up Kubernetes secrets
print_status "Cleaning up Kubernetes secrets..."
if [ -f "create-secrets.sh" ]; then
    ./create-secrets.sh delete
else
    print_warning "create-secrets.sh not found, skipping secrets cleanup"
fi

# Clean up local files
print_status "Cleaning up local files..."
rm -f postgresql-testing-config*.env > /dev/null 2>&1 || true
rm -f eks-cluster-config-phase1.yaml > /dev/null 2>&1 || true
rm -f baseline-policies.yaml > /dev/null 2>&1 || true
rm -f test-violations-pod.yaml > /dev/null 2>&1 || true
rm -f phase1-monitoring-*.csv > /dev/null 2>&1 || true
rm -f values-with-secrets.yaml > /dev/null 2>&1 || true

print_success "Local files cleaned up"

# Final status check
echo ""
echo "=========================================="
echo "           CLEANUP SUMMARY"
echo "=========================================="

# Check what's left
echo "Checking remaining resources..."

# Check EKS clusters
if eksctl get cluster --region $REGION --profile $AWS_PROFILE 2>/dev/null | grep -q "$CLUSTER_NAME"; then
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
if aws rds describe-db-subnet-groups --db-subnet-group-name $SUBNET_GROUP_NAME --profile $AWS_PROFILE > /dev/null 2>&1; then
    print_warning "RDS subnet group '$SUBNET_GROUP_NAME' still exists"
else
    print_success "RDS subnet group '$SUBNET_GROUP_NAME' cleaned up"
fi

# Check Kubernetes context
if kubectl config current-context 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    print_warning "Kubernetes context still points to '$CLUSTER_NAME'"
    echo "  You may want to switch to a different context:"
    echo "  kubectl config use-context <your-default-context>"
else
    print_success "Kubernetes context cleaned up"
fi

# Check for any remaining CloudFormation stacks
print_status "Checking for remaining CloudFormation stacks..."
REMAINING_STACKS=$(aws cloudformation describe-stacks --query "Stacks[?contains(StackName, 'reports-server') && StackStatus!='DELETE_COMPLETE'].{Name:StackName,Status:StackStatus}" --output table --profile $AWS_PROFILE 2>/dev/null || echo "No stacks found")
if [ "$REMAINING_STACKS" != "No stacks found" ]; then
    print_warning "Remaining CloudFormation stacks:"
    echo "$REMAINING_STACKS"
else
    print_success "All CloudFormation stacks cleaned up"
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
echo "  ./phase1-setup.sh"
echo ""
echo "If you want to proceed to Phase 2:"
echo "  ./phase2-setup.sh"
echo ""
print_success "Cleanup completed successfully! 🎉"
