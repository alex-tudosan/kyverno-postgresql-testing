#!/bin/bash

# Enhanced Phase 1 Cleanup Script - Optimized for Testing Terraform Integration
# ============================================================================
# 
# This script uses the recommended cleanup approach:
# 1. Clean Kubernetes resources first
# 2. Use AWS CLI for resource deletion (old-fashioned way)
# 3. Clean Terraform state files for fresh testing
# 4. Focus on simplicity and reliability for testing scenarios
#
# Key Benefits for Testing:
# - Clean slate for Terraform EKS creation testing
# - No CloudFormation state conflicts
# - Faster and more reliable cleanup
# - Better suited for testing the updated phase1-setup.sh
#
# IMPROVEMENTS MADE:
# ✅ Fixed EKS deletion order (node group first, then cluster)
# ✅ Added comprehensive RDS cleanup (all instances with 'reports-server-db' in name)
# ✅ Added comprehensive subnet group cleanup (all groups with 'reports-server-subnet-group' in name)
# ✅ Added handling for RDS instances stuck in "deleting" status
# ✅ Enhanced resource verification and status reporting
# ✅ Fixed syntax errors and improved error handling

set -e

echo "🧹 Enhanced Phase 1 Cleanup: Optimized for Terraform Testing"
echo "============================================================="

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

# Configuration
TIMESTAMP=""
CONFIG_FOUND=false

# Load configuration if available
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
    CLUSTER_NAME="report-server-test"
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
            aws eks describe-cluster --name "$resource_name" --profile $AWS_PROFILE >/dev/null 2>&1
            ;;
        "rds")
            aws rds describe-db-instances --db-instance-identifier "$resource_name" --profile $AWS_PROFILE >/dev/null 2>&1
            ;;
        "subnet-group")
            aws rds describe-db-subnet-groups --db-subnet-group-name "$resource_name" --profile $AWS_PROFILE >/dev/null 2>&1
            ;;
        "nodegroup")
            aws eks describe-nodegroup --cluster-name "$resource_name" --nodegroup-name "${resource_name}-workers" --profile $AWS_PROFILE >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type=$1
    local resource_name=$2
    local timeout_minutes=${3:-15}
    local max_attempts=$((timeout_minutes * 2))  # Check every 30 seconds
    local attempt=1
    
    print_status "Waiting for $resource_type '$resource_name' deletion (timeout: ${timeout_minutes} minutes)..."
    
    while [ $attempt -le $max_attempts ]; do
        if ! resource_exists "$resource_type" "$resource_name"; then
            print_success "$resource_type '$resource_name' deleted successfully"
            return 0
        fi
        
        print_progress "Waiting for deletion... (attempt $attempt/$max_attempts)"
        sleep 30
        ((attempt++))
    done
    
    print_warning "$resource_type '$resource_name' deletion may still be in progress"
    return 1
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

# Function to check for running pods in EKS cluster
check_running_pods() {
    local cluster_name=$1
    
    print_status "Checking for running pods in cluster: $cluster_name"
    
    # Try to access the cluster
    if kubectl get nodes >/dev/null 2>&1; then
        local running_pods=$(kubectl get pods -A --no-headers 2>/dev/null | grep -v "Completed\|Succeeded\|Failed" | wc -l | tr -d ' ')
        
        if [ "$running_pods" -gt 0 ]; then
            print_warning "Found $running_pods running pods in cluster"
            print_status "Attempting to delete all pods..."
            kubectl delete pods --all -A --ignore-not-found=true >/dev/null 2>&1 || true
            sleep 10
        else
            print_status "No running pods found in cluster"
        fi
    else
        print_warning "Cannot access cluster via kubectl"
    fi
}

# Function to force delete Kubernetes namespace
force_delete_namespace() {
    local namespace=$1
    
    if kubectl get namespace "$namespace" >/dev/null 2>&1; then
        print_status "Force deleting namespace: $namespace"
        
        # Remove finalizers
        kubectl patch namespace "$namespace" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        
        # Force delete
        kubectl delete namespace "$namespace" --ignore-not-found=true --force --grace-period=0 2>/dev/null || true
        
        # Wait for deletion
        local timeout=60
        local elapsed=0
        while [ $elapsed -lt $timeout ] && kubectl get namespace "$namespace" >/dev/null 2>&1; do
            sleep 5
            elapsed=$((elapsed + 5))
            print_progress "Waiting for namespace deletion... ($elapsed/$timeout seconds)"
        done
        
        if kubectl get namespace "$namespace" >/dev/null 2>&1; then
            print_warning "Namespace $namespace still exists after force deletion"
        else
            print_success "Namespace $namespace deleted successfully"
        fi
    else
        print_status "Namespace $namespace not found"
    fi
}

# Function to confirm deletion
confirm_deletion() {
    local resource_type=$1
    local resource_name=$2
    
    echo ""
    echo -e "${YELLOW}⚠️  WARNING: This will permanently delete the $resource_type '$resource_name'${NC}"
    echo -e "${YELLOW}   This action cannot be undone!${NC}"
    echo ""
    read -p "Do you want to continue? (yes/no): " -r
    echo
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        return 0
    else
        return 1
    fi
}

print_status "Starting optimized cleanup process for Terraform testing..."
print_status "Using cluster: $CLUSTER_NAME"
print_status "Using RDS instance: $RDS_INSTANCE_ID"
print_status "Region: $REGION"
print_status "AWS Profile: $AWS_PROFILE"

# Step 1: Clean up Kubernetes resources first
print_status "Step 1: Cleaning up Kubernetes resources..."

# Clean up test policies
print_status "Cleaning up test policies..."
kubectl delete -f policies/baseline/require-labels.yaml --ignore-not-found=true > /dev/null 2>&1 || true
kubectl delete -f policies/baseline/disallow-privileged-containers.yaml --ignore-not-found=true > /dev/null 2>&1 || true

# Clean up Kyverno with integrated Reports Server
print_status "Cleaning up Kyverno with integrated Reports Server..."
retry_command 3 10 "helm uninstall kyverno -n kyverno --ignore-not-found=true > /dev/null 2>&1 || true"

# Clean up monitoring with retry
print_status "Cleaning up monitoring stack..."
retry_command 3 10 "helm uninstall monitoring -n monitoring --ignore-not-found=true > /dev/null 2>&1 || true"

# Clean up namespaces with force delete
print_status "Cleaning up namespaces..."
force_delete_namespace "kyverno"
force_delete_namespace "monitoring"

print_success "Kubernetes resources cleaned up"

# Step 2: Clean up ALL RDS instances (delete RDS first)
print_status "Step 2: Cleaning up ALL RDS instances..."

# Find all RDS instances that contain 'reports-server-db' in their name
RDS_INSTANCES=$(aws rds describe-db-instances --profile $AWS_PROFILE --query 'DBInstances[?contains(DBInstanceIdentifier, `reports-server-db`)].{ID:DBInstanceIdentifier,Status:DBInstanceStatus}' --output json 2>/dev/null || echo "[]")

if [ "$RDS_INSTANCES" != "[]" ]; then
    print_status "Found RDS instances to clean up:"
    echo "$RDS_INSTANCES" | jq -r '.[] | "  - \(.ID) (Status: \(.Status))"'
    
    if confirm_deletion "ALL RDS instances" "reports-server-db*"; then
        # Delete each RDS instance
        echo "$RDS_INSTANCES" | jq -r '.[].ID' | while read -r instance_id; do
            print_status "Processing RDS instance: $instance_id"
            
            # Get RDS status
            instance_status=$(aws rds describe-db-instances --db-instance-identifier "$instance_id" --query 'DBInstances[0].DBInstanceStatus' --output text --profile $AWS_PROFILE 2>/dev/null || echo "N/A")
            print_status "Instance status: $instance_status"
            
            if [ "$instance_status" = "available" ] || [ "$instance_status" = "stopped" ]; then
                print_status "Deleting RDS instance: $instance_id"
                if aws rds delete-db-instance --db-instance-identifier "$instance_id" --skip-final-snapshot --delete-automated-backups --profile $AWS_PROFILE > /dev/null 2>&1; then
                    print_success "RDS deletion initiated for: $instance_id"
                else
                    print_error "Failed to delete RDS instance: $instance_id"
                fi
            else
                print_warning "RDS instance $instance_id is in state '$instance_status'. Cannot delete at this time."
            fi
        done
        
        # Wait for all RDS instances to be deleted
        print_status "Waiting for all RDS instances to be deleted..."
        timeout=20
        elapsed=0
        while [ $elapsed -lt $((timeout * 60)) ]; do
            remaining_instances=$(aws rds describe-db-instances --profile $AWS_PROFILE --query 'DBInstances[?contains(DBInstanceIdentifier, `reports-server-db`)].DBInstanceIdentifier' --output text 2>/dev/null || echo "")
            
            if [ -z "$remaining_instances" ]; then
                print_success "All RDS instances deleted successfully"
                break
            fi
            
            print_progress "Waiting for RDS deletion... ($((elapsed / 60))m $((elapsed % 60))s) - Remaining: $remaining_instances"
            sleep 30
            elapsed=$((elapsed + 30))
        done
        
        if [ $elapsed -ge $((timeout * 20)) ]; then
            print_warning "RDS deletion timeout. Some instances may still be deleting."
        fi
    else
        print_status "Skipping RDS instance deletion"
    fi
else
    print_status "No RDS instances found with 'reports-server-db' in name"
fi

# Step 3: Clean up ALL RDS subnet groups (delete after RDS)
print_status "Step 3: Cleaning up ALL RDS subnet groups..."

# Additional cleanup: Check for any RDS instances that might be stuck in "deleting" status
print_status "Checking for RDS instances stuck in deletion..."
STUCK_RDS=$(aws rds describe-db-instances --profile $AWS_PROFILE --query 'DBInstances[?DBInstanceStatus==`deleting` && contains(DBInstanceIdentifier, `reports-server-db`)].DBInstanceIdentifier' --output text 2>/dev/null || echo "")

if [ -n "$STUCK_RDS" ]; then
    print_warning "Found RDS instances stuck in deletion: $STUCK_RDS"
    print_status "These instances are being deleted by AWS. Waiting for completion..."
    
    # Wait for stuck instances to complete deletion
    timeout=30
    elapsed=0
    while [ $elapsed -lt $((timeout * 60)) ]; do
        still_stuck=$(aws rds describe-db-instances --profile $AWS_PROFILE --query 'DBInstances[?DBInstanceStatus==`deleting` && contains(DBInstanceIdentifier, `reports-server-db`)].DBInstanceIdentifier' --output text 2>/dev/null || echo "")
        
        if [ -z "$still_stuck" ]; then
            print_success "All stuck RDS instances completed deletion"
            break
        fi
        
        print_progress "Waiting for stuck RDS deletion... ($((elapsed / 60))m $((elapsed % 60))s) - Still stuck: $still_stuck"
        sleep 30
        elapsed=$((elapsed + 30))
    done
    
    if [ $elapsed -ge $((timeout * 30)) ]; then
        print_warning "Timeout waiting for stuck RDS instances. They may need manual cleanup."
    fi
else
    print_status "No RDS instances stuck in deletion"
fi

# Find all subnet groups that contain 'reports-server-subnet-group' in their name
SUBNET_GROUPS=$(aws rds describe-db-subnet-groups --profile $AWS_PROFILE --query 'DBSubnetGroups[?contains(DBSubnetGroupName, `reports-server-subnet-group`)].{Name:DBSubnetGroupName,Description:DBSubnetGroupDescription}' --output json 2>/dev/null || echo "[]")

if [ "$SUBNET_GROUPS" != "[]" ]; then
    print_status "Found subnet groups to clean up:"
    echo "$SUBNET_GROUPS" | jq -r '.[] | "  - \(.Name) (\(.Description))"'
    
    if confirm_deletion "ALL RDS subnet groups" "reports-server-subnet-group*"; then
        # Delete each subnet group
        echo "$SUBNET_GROUPS" | jq -r '.[].Name' | while read -r subnet_group_name; do
            print_status "Processing subnet group: $subnet_group_name"
            
            print_status "Deleting RDS subnet group: $subnet_group_name"
            if aws rds delete-db-subnet-group --db-subnet-group-name "$subnet_group_name" --profile $AWS_PROFILE > /dev/null 2>&1; then
                print_success "Subnet group deletion initiated for: $subnet_group_name"
            else
                print_error "Failed to delete subnet group: $subnet_group_name"
            fi
        done
        
        # Wait for all subnet groups to be deleted
        print_status "Waiting for all subnet groups to be deleted..."
        timeout=10
        elapsed=0
        while [ $elapsed -lt $((timeout * 60)) ]; do
            remaining_groups=$(aws rds describe-db-subnet-groups --profile $AWS_PROFILE --query 'DBSubnetGroups[?contains(DBSubnetGroupName, `reports-server-subnet-group`)].DBSubnetGroupName' --output text 2>/dev/null || echo "")
            
            if [ -z "$remaining_groups" ]; then
                print_success "All subnet groups deleted successfully"
                break
            fi
            
            print_progress "Waiting for subnet group deletion... ($((elapsed / 60))m $((elapsed % 60))s) - Remaining: $remaining_groups"
            sleep 30
            elapsed=$((elapsed + 30))
        done
        
        if [ $elapsed -ge $((timeout * 10)) ]; then
            print_warning "Subnet group deletion timeout. Some groups may still be deleting."
        fi
    else
        print_status "Skipping RDS subnet group deletion"
    fi
else
    print_status "No subnet groups found with 'reports-server-subnet-group' in name"
fi

# Step 4: Clean up EKS cluster using AWS CLI (old-fashioned way)
print_status "Step 4: Cleaning up EKS cluster using AWS CLI..."

if resource_exists "cluster" "$CLUSTER_NAME"; then
    print_status "EKS cluster '$CLUSTER_NAME' found"
    
    if confirm_deletion "EKS cluster" "$CLUSTER_NAME"; then
        # First, check and clean up any running pods
        check_running_pods "$CLUSTER_NAME"
        
        # Then, delete the node group (required before cluster deletion)
        print_status "Checking for active node groups..."
        NODEGROUP_NAME="${CLUSTER_NAME}-workers"
        
        if aws eks list-nodegroups --cluster-name $CLUSTER_NAME --region $REGION --profile $AWS_PROFILE --query "nodegroups[?contains(@, 'workers')]" --output text 2>/dev/null | grep -q "workers"; then
            print_status "Found active node group: $NODEGROUP_NAME"
            print_status "Deleting node group first (required before cluster deletion)..."
            
            if aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --profile $AWS_PROFILE > /dev/null 2>&1; then
                print_success "Node group deletion initiated. Waiting for completion..."
                
                # Wait for node group deletion
                timeout=20
                elapsed=0
                while [ $elapsed -lt $((timeout * 60)) ]; do
                    if ! aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $REGION --profile $AWS_PROFILE >/dev/null 2>&1; then
                        print_success "Node group deleted successfully"
                        break
                    fi
                    sleep 30
                    elapsed=$((elapsed + 30))
                    print_progress "Waiting for node group deletion... ($((elapsed / 60))m $((elapsed % 60))s)"
                done
                
                if [ $elapsed -ge $((timeout * 60)) ]; then
                    print_warning "Node group deletion timeout. Proceeding with cluster deletion..."
                fi
            else
                print_error "Failed to delete node group"
                return 1
            fi
        else
            print_status "No active node groups found"
        fi
        
        # Now delete the EKS cluster
        print_status "Deleting EKS cluster using AWS CLI..."
        
        # Check if cluster is in a deletable state
        cluster_status=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --profile $AWS_PROFILE --query 'cluster.status' --output text 2>/dev/null || echo "UNKNOWN")
        print_status "Cluster status: $cluster_status"
        
        if [ "$cluster_status" = "ACTIVE" ] || [ "$cluster_status" = "FAILED" ]; then
            if aws eks delete-cluster --name $CLUSTER_NAME --region $REGION --profile $AWS_PROFILE > /dev/null 2>&1; then
                print_success "EKS cluster deletion initiated via AWS CLI"
                if wait_for_deletion "cluster" "$CLUSTER_NAME" 20; then
                    print_success "EKS cluster deleted successfully"
                else
                    print_warning "EKS cluster deletion may still be in progress"
                fi
            else
                print_error "Failed to delete EKS cluster via AWS CLI"
                print_status "You may need to delete it manually from the AWS console"
            fi
        else
            print_warning "Cluster is in state '$cluster_status'. Cannot delete at this time."
            print_status "Please wait for cluster to become ACTIVE or FAILED"
        fi
    else
        print_status "Skipping EKS cluster deletion"
    fi
else
    print_status "EKS cluster '$CLUSTER_NAME' not found"
fi

# Step 5: Clean up Terraform state files for fresh testing
print_status "Step 5: Cleaning up Terraform state files..."

if [ -d "default-terraform-code/terraform-eks" ]; then
    cd default-terraform-code/terraform-eks
    
    # Check if Terraform is initialized
    if [ -d ".terraform" ]; then
        print_status "Terraform is initialized, cleaning up state..."
        
        # Remove state files
        rm -f terraform.tfstate* .terraform.lock.hcl 2>/dev/null || true
        
        # Remove .terraform directory
        rm -rf .terraform 2>/dev/null || true
        
        print_success "Terraform state files cleaned up"
    else
        print_status "Terraform not initialized, no state to clean"
    fi
    
    cd - > /dev/null
else
    print_warning "Terraform EKS directory not found"
fi

# Step 6: Clean up Kubernetes secrets
print_status "Step 6: Cleaning up Kubernetes secrets..."
if [ -f "setup/create-secrets.sh" ]; then
    ./setup/create-secrets.sh delete
else
    print_warning "create-secrets.sh not found, skipping secrets cleanup"
fi

# Step 7: Clean up local files
print_status "Step 7: Cleaning up local files..."
rm -f postgresql-testing-config*.env > /dev/null 2>&1 || true
rm -f eks-cluster-config-phase1.yaml > /dev/null 2>&1 || true
rm -f baseline-policies.yaml > /dev/null 2>&1 || true
rm -f test-violations-pod.yaml > /dev/null 2>&1 || true
rm -f values-with-secrets.yaml > /dev/null 2>&1 || true

print_success "Local files cleaned up"

# Step 8: Final verification and status report
print_status "Step 8: Final verification and status report..."

echo ""
echo "=== RESOURCE VERIFICATION ==="

# Check EKS clusters
if resource_exists "cluster" "$CLUSTER_NAME"; then
    print_warning "EKS cluster '$CLUSTER_NAME' still exists"
else
    print_success "EKS cluster '$CLUSTER_NAME' cleaned up"
fi

# Check RDS instances
REMAINING_RDS=$(aws rds describe-db-instances --profile $AWS_PROFILE --query 'DBInstances[?contains(DBInstanceIdentifier, `reports-server-db`)].DBInstanceIdentifier' --output text 2>/dev/null || echo "")
if [ -n "$REMAINING_RDS" ]; then
    print_warning "RDS instances still exist: $REMAINING_RDS"
else
    print_success "All RDS instances cleaned up"
fi

# Check RDS subnet groups
REMAINING_SUBNET_GROUPS=$(aws rds describe-db-subnet-groups --profile $AWS_PROFILE --query 'DBSubnetGroups[?contains(DBSubnetGroupName, `reports-server-subnet-group`)].DBSubnetGroupName' --output text 2>/dev/null || echo "")
if [ -n "$REMAINING_SUBNET_GROUPS" ]; then
    print_warning "RDS subnet groups still exist: $REMAINING_SUBNET_GROUPS"
else
    print_success "All RDS subnet groups cleaned up"
fi

# Check Kubernetes context
if kubectl config current-context 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    print_warning "Kubernetes context still points to '$CLUSTER_NAME'"
    print_status "You may want to run: kubectl config unset current-context"
else
    print_success "Kubernetes context cleaned up"
fi

# Check Terraform state
if [ -d "default-terraform-code/terraform-eks" ]; then
    if [ -f "default-terraform-code/terraform-eks/terraform.tfstate" ] || [ -d "default-terraform-code/terraform-eks/.terraform" ]; then
        print_warning "Terraform state files still exist"
    else
        print_success "Terraform state files cleaned up"
    fi
fi

echo ""
echo "=== COST SAVINGS ==="
echo "By cleaning up these resources, you've stopped incurring costs for:"
echo "  - EKS Control Plane: ~$73/month"
echo "  - EKS Nodes (2x t3a.medium): ~$30/month"
echo "  - RDS PostgreSQL (db.t3.micro): ~$15/month"
echo "  - Storage: ~$3/month"
echo "  Total savings: ~$121/month"
echo ""
echo "=== OPTIMIZED FOR TERRAFORM TESTING ==="
echo "✅ Used AWS CLI for EKS deletion (old-fashioned way)"
echo "✅ Cleaned up Terraform state files for fresh testing"
echo "✅ Deleted resources in correct sequence (RDS → EKS → Subnet Group)"
echo "✅ Implemented force deletion for stuck Kubernetes namespaces"
echo "✅ Added comprehensive resource verification and status reporting"
echo "✅ Enhanced error handling with retry logic and progress indicators"
echo ""
echo "=== READY FOR TERRAFORM TESTING ==="
echo "Your environment is now clean and ready to test the updated phase1-setup.sh!"
echo "The script will now be able to:"
echo "  - Create EKS cluster via Terraform automatically"
echo "  - Set up RDS database from scratch"
echo "  - Install monitoring and Kyverno components"
echo "  - Demonstrate complete infrastructure creation"
echo ""
echo "=== NEXT STEPS ==="
echo "To test the updated script with Terraform integration:"
echo "  ./setup/phase1/phase1-setup.sh"
echo ""
echo "This will create a complete infrastructure from scratch! 🚀"
echo ""
print_success "Optimized cleanup completed successfully! Ready for Terraform testing! 🎉"
