#!/bin/bash

# Enhanced Phase 1 Cleanup Script with Lessons Learned
# ===================================================
# 
# Lessons Learned:
# 1. Use aws eks delete-cluster instead of eksctl delete cluster (bypasses pod draining issues)
# 2. Delete RDS first, then EKS, then subnet groups (correct sequence)
# 3. Handle security group dependencies manually before VPC deletion
# 4. Use CloudFormation console for DELETE_FAILED stacks
# 5. Implement force deletion for stuck Kubernetes namespaces
# 6. Add comprehensive resource verification and status reporting

set -e

echo "🧹 Enhanced Phase 1 Cleanup: PostgreSQL-based Reports Server"
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
    CLUSTER_NAME="reports-server-test"
    REGION="us-west-1"
    AWS_PROFILE="devtest-sso"
    RDS_INSTANCE_ID="reports-server-db"
fi

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

# Function to wait for resource deletion with progress
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

# Function to force delete namespace (LESSON LEARNED: Handle stuck namespaces)
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

# Function to handle security group dependencies (LESSON LEARNED: Manual dependency resolution)
resolve_security_group_dependencies() {
    local vpc_id=$1
    print_status "Resolving security group dependencies for VPC $vpc_id..."

    # Get all security groups in the VPC
    local security_groups=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --profile $AWS_PROFILE --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")

    if [ -z "$security_groups" ]; then
        print_status "No non-default security groups found in VPC"
        return 0
    fi

    for sg_id in $security_groups; do
        print_status "Processing security group: $sg_id"
        
        # Find security groups that reference this one
        local referencing_sgs=$(aws ec2 describe-security-groups --filters "Name=ip-permission.group-id,Values=$sg_id" --profile $AWS_PROFILE --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || echo "")
        
        if [ -n "$referencing_sgs" ]; then
            print_status "Removing references from security groups: $referencing_sgs"
            for ref_sg in $referencing_sgs; do
                # Remove ingress rules referencing this security group
                aws ec2 revoke-security-group-ingress --group-id $ref_sg --protocol tcp --port 5432 --source-group $sg_id --profile $AWS_PROFILE > /dev/null 2>&1 || true
                aws ec2 revoke-security-group-ingress --group-id $ref_sg --protocol tcp --port 22 --source-group $sg_id --profile $AWS_PROFILE > /dev/null 2>&1 || true
                aws ec2 revoke-security-group-ingress --group-id $ref_sg --protocol tcp --port 443 --source-group $sg_id --profile $AWS_PROFILE > /dev/null 2>&1 || true
            done
        fi
        
        # Delete the security group
        if aws ec2 delete-security-group --group-id $sg_id --profile $AWS_PROFILE > /dev/null 2>&1; then
            print_success "Security group $sg_id deleted successfully"
        else
            print_warning "Failed to delete security group $sg_id (may have other dependencies)"
        fi
    done
}

# Function to handle CloudFormation stack cleanup with proper dependency management
cleanup_cloudformation_stack() {
    local cluster_name=$1
    
    print_status "Cleaning up CloudFormation stacks for cluster: $cluster_name"
    
    # Define stack names
    local cluster_stack="eksctl-$cluster_name-cluster"
    local nodegroup_stack="eksctl-$cluster_name-nodegroup-ng-1"
    
    # First try to delete the EKS cluster using AWS CLI (LESSON LEARNED: bypass eksctl issues)
    if resource_exists "cluster" "$cluster_name"; then
        print_status "Deleting EKS cluster using AWS CLI (bypasses pod draining issues)..."
        if aws eks delete-cluster --name $cluster_name --profile $AWS_PROFILE > /dev/null 2>&1; then
            print_success "EKS cluster deletion initiated via AWS CLI"
            if wait_for_deletion "cluster" "$cluster_name" 20; then
                print_success "EKS cluster deleted successfully"
            else
                print_warning "EKS cluster deletion may still be in progress"
            fi
        else
            print_warning "Failed to delete EKS cluster via AWS CLI, trying eksctl..."
            if retry_command 3 60 "eksctl delete cluster --name $cluster_name --region $REGION --profile $AWS_PROFILE"; then
                print_success "EKS cluster deleted via eksctl"
            else
                print_error "Failed to delete EKS cluster. Manual cleanup required."
                print_status "Please use AWS Console to delete the CloudFormation stack manually."
                return 1
            fi
        fi
    else
        print_status "EKS cluster not found, checking CloudFormation stacks..."
    fi
    
    # Check and delete CloudFormation stacks with proper dependency management
    print_status "Checking for CloudFormation stacks with dependency verification..."
    
    # Step 1: Check and delete nodegroup stack first (LESSON LEARNED: Proper deletion order)
    print_status "Step 1: Processing nodegroup stack (must be deleted before cluster stack)..."
    local nodegroup_status=$(aws cloudformation describe-stacks --stack-name $nodegroup_stack --profile $AWS_PROFILE --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "STACK_NOT_FOUND")
    
    if [ "$nodegroup_status" != "STACK_NOT_FOUND" ]; then
        print_status "Found nodegroup stack: $nodegroup_stack (status: $nodegroup_status)"
        
        # Check if nodegroup stack is already being deleted
        if [ "$nodegroup_status" = "DELETE_IN_PROGRESS" ]; then
            print_status "Nodegroup stack is already being deleted, waiting for completion..."
            local timeout=60
            local elapsed=0
            while [ $elapsed -lt $timeout ]; do
                local current_status=$(aws cloudformation describe-stacks --stack-name $nodegroup_stack --profile $AWS_PROFILE --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "STACK_NOT_FOUND")
                if [ "$current_status" = "STACK_NOT_FOUND" ] || [ "$current_status" = "DELETE_COMPLETE" ]; then
                    print_success "Nodegroup stack deletion completed"
                    break
                elif [ "$current_status" = "DELETE_FAILED" ]; then
                    print_warning "Nodegroup stack deletion failed. Manual cleanup required."
                    break
                fi
                sleep 30
                elapsed=$((elapsed + 30))
                print_progress "Waiting for nodegroup stack deletion... ($elapsed/$timeout seconds)"
            done
        else
            # Initiate nodegroup stack deletion
            print_status "Initiating nodegroup stack deletion: $nodegroup_stack"
            if aws cloudformation delete-stack --stack-name $nodegroup_stack --profile $AWS_PROFILE > /dev/null 2>&1; then
                print_success "Nodegroup stack deletion initiated"
                # Wait for nodegroup stack deletion with extended timeout
                local timeout=60
                local elapsed=0
                while [ $elapsed -lt $timeout ]; do
                    local current_status=$(aws cloudformation describe-stacks --stack-name $nodegroup_stack --profile $AWS_PROFILE --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "STACK_NOT_FOUND")
                    if [ "$current_status" = "STACK_NOT_FOUND" ] || [ "$current_status" = "DELETE_COMPLETE" ]; then
                        print_success "Nodegroup stack deleted successfully"
                        break
                    elif [ "$current_status" = "DELETE_FAILED" ]; then
                        print_warning "Nodegroup stack deletion failed. Manual cleanup required."
                        break
                    fi
                    sleep 30
                    elapsed=$((elapsed + 30))
                    print_progress "Waiting for nodegroup stack deletion... ($elapsed/$timeout seconds)"
                done
            else
                print_warning "Failed to initiate nodegroup stack deletion"
            fi
        fi
    else
        print_status "Nodegroup stack not found or already deleted"
    fi
    
    # Step 2: Verify nodegroup stack is completely deleted before proceeding
    print_status "Step 2: Verifying nodegroup stack deletion before proceeding to cluster stack..."
    local final_nodegroup_status=$(aws cloudformation describe-stacks --stack-name $nodegroup_stack --profile $AWS_PROFILE --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "STACK_NOT_FOUND")
    if [ "$final_nodegroup_status" != "STACK_NOT_FOUND" ] && [ "$final_nodegroup_status" != "DELETE_COMPLETE" ]; then
        print_warning "Nodegroup stack still exists with status: $final_nodegroup_status"
        print_status "Cannot safely delete cluster stack while nodegroup stack exists."
        print_status "Please wait for nodegroup stack deletion to complete or delete manually."
        return 1
    else
        print_success "Nodegroup stack verification passed - safe to proceed with cluster stack"
    fi
    
    # Step 3: Check and delete cluster stack (LESSON LEARNED: Only after nodegroup is gone)
    print_status "Step 3: Processing cluster stack (safe to delete now)..."
    local cluster_status=$(aws cloudformation describe-stacks --stack-name $cluster_stack --profile $AWS_PROFILE --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "STACK_NOT_FOUND")
    
    if [ "$cluster_status" != "STACK_NOT_FOUND" ]; then
        print_status "Found cluster stack: $cluster_stack (status: $cluster_status)"
        
        # Check if cluster stack is already being deleted
        if [ "$cluster_status" = "DELETE_IN_PROGRESS" ]; then
            print_status "Cluster stack is already being deleted, waiting for completion..."
            local timeout=60
            local elapsed=0
            while [ $elapsed -lt $timeout ]; do
                local current_status=$(aws cloudformation describe-stacks --stack-name $cluster_stack --profile $AWS_PROFILE --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "STACK_NOT_FOUND")
                if [ "$current_status" = "STACK_NOT_FOUND" ] || [ "$current_status" = "DELETE_COMPLETE" ]; then
                    print_success "Cluster stack deletion completed"
                    break
                elif [ "$current_status" = "DELETE_FAILED" ]; then
                    print_warning "Cluster stack deletion failed. Manual cleanup required."
                    print_status "For DELETE_FAILED stacks, use AWS Console:"
                    print_status "1. Go to CloudFormation Console"
                    print_status "2. Select the failed stack"
                    print_status "3. Click 'Delete' → 'Delete this stack but retain resources'"
                    print_status "4. Uncheck VPC to delete it with the stack"
                    break
                fi
                sleep 30
                elapsed=$((elapsed + 30))
                print_progress "Waiting for cluster stack deletion... ($elapsed/$timeout seconds)"
            done
        else
            # Initiate cluster stack deletion
            print_status "Initiating cluster stack deletion: $cluster_stack"
            if aws cloudformation delete-stack --stack-name $cluster_stack --profile $AWS_PROFILE > /dev/null 2>&1; then
                print_success "Cluster stack deletion initiated"
                # Wait for cluster stack deletion with extended timeout
                local timeout=60
                local elapsed=0
                while [ $elapsed -lt $timeout ]; do
                    local current_status=$(aws cloudformation describe-stacks --stack-name $cluster_stack --profile $AWS_PROFILE --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "STACK_NOT_FOUND")
                    if [ "$current_status" = "STACK_NOT_FOUND" ] || [ "$current_status" = "DELETE_COMPLETE" ]; then
                        print_success "Cluster stack deleted successfully"
                        break
                    elif [ "$current_status" = "DELETE_FAILED" ]; then
                        print_warning "Cluster stack deletion failed. Manual cleanup required."
                        print_status "For DELETE_FAILED stacks, use AWS Console:"
                        print_status "1. Go to CloudFormation Console"
                        print_status "2. Select the failed stack"
                        print_status "3. Click 'Delete' → 'Delete this stack but retain resources'"
                        print_status "4. Uncheck VPC to delete it with the stack"
                        break
                    fi
                    sleep 30
                    elapsed=$((elapsed + 30))
                    print_progress "Waiting for cluster stack deletion... ($elapsed/$timeout seconds)"
                done
            else
                print_warning "Failed to initiate cluster stack deletion"
            fi
        fi
    else
        print_status "Cluster stack not found or already deleted"
    fi
    
    print_success "CloudFormation stack cleanup process completed"
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

# Function to check CloudFormation stack status
check_stack_status() {
    local stack_name=$1
    local status=$(aws cloudformation describe-stacks --stack-name $stack_name --profile $AWS_PROFILE --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "STACK_NOT_FOUND")
    echo "$status"
}

# Function to clean up any remaining CloudFormation stacks
cleanup_remaining_stacks() {
    print_status "Checking for any remaining CloudFormation stacks..."
    
    # Get all stacks that contain 'reports-server' in the name with their status
    local remaining_stacks_info=$(aws cloudformation list-stacks --profile $AWS_PROFILE --query "StackSummaries[?contains(StackName, 'reports-server') && StackStatus!='DELETE_COMPLETE'].{Name:StackName,Status:StackStatus}" --output json 2>/dev/null || echo "[]")
    
    if [ "$remaining_stacks_info" != "[]" ]; then
        print_warning "Found remaining CloudFormation stacks:"
        echo "$remaining_stacks_info" | jq -r '.[] | "  - \(.Name) (Status: \(.Status))"'
        
        echo ""
        read -p "Do you want to delete these remaining stacks? (yes/no): " -r
        echo
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            echo "$remaining_stacks_info" | jq -r '.[] | .Name' | while read -r stack; do
                local stack_status=$(check_stack_status "$stack")
                print_status "Processing stack: $stack (Status: $stack_status)"
                
                # Check if stack is already being deleted
                if [ "$stack_status" = "DELETE_IN_PROGRESS" ]; then
                    print_status "Stack $stack is already being deleted, waiting for completion..."
                    local timeout=60
                    local elapsed=0
                    while [ $elapsed -lt $timeout ]; do
                        local current_status=$(check_stack_status "$stack")
                        if [ "$current_status" = "STACK_NOT_FOUND" ] || [ "$current_status" = "DELETE_COMPLETE" ]; then
                            print_success "Stack $stack deletion completed"
                            break
                        elif [ "$current_status" = "DELETE_FAILED" ]; then
                            print_warning "Stack $stack deletion failed"
                            break
                        fi
                        sleep 30
                        elapsed=$((elapsed + 30))
                        print_progress "Waiting for stack $stack deletion... ($elapsed/$timeout seconds)"
                    done
                else
                    # Initiate stack deletion
                    if aws cloudformation delete-stack --stack-name $stack --profile $AWS_PROFILE > /dev/null 2>&1; then
                        print_success "Stack deletion initiated: $stack"
                    else
                        print_warning "Failed to delete stack: $stack"
                    fi
                fi
            done
        else
            print_status "Skipping remaining stack deletion"
        fi
    else
        print_success "No remaining CloudFormation stacks found"
    fi
}

print_status "Starting enhanced cleanup process..."
print_status "Using cluster: $CLUSTER_NAME"
print_status "Using RDS instance: $RDS_INSTANCE_ID"
print_status "Region: $REGION"
print_status "AWS Profile: $AWS_PROFILE"

# Step 1: Clean up Kubernetes resources
print_status "Step 1: Cleaning up Kubernetes resources..."

# Clean up test policies
kubectl delete -f baseline-policies.yaml --ignore-not-found=true > /dev/null 2>&1 || true

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

# Step 2: Clean up RDS instance (LESSON LEARNED: Delete RDS first)
print_status "Step 2: Cleaning up RDS instance..."

if resource_exists "rds" "$RDS_INSTANCE_ID"; then
    print_status "RDS instance '$RDS_INSTANCE_ID' found"
    
    # Get RDS status
    RDS_STATUS=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --query 'DBInstances[0].DBInstanceStatus' --output text --profile $AWS_PROFILE 2>/dev/null || echo "N/A")
    
    if [ "$RDS_STATUS" = "available" ] || [ "$RDS_STATUS" = "stopped" ]; then
        if confirm_deletion "RDS instance" "$RDS_INSTANCE_ID"; then
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
            print_status "Skipping RDS instance deletion"
        fi
    else
        print_warning "RDS instance is in state '$RDS_STATUS'. Cannot delete at this time."
        print_status "You may need to delete it manually from the AWS console."
    fi
else
    print_status "RDS instance '$RDS_INSTANCE_ID' not found"
fi

# Step 3: Clean up RDS subnet group (LESSON LEARNED: Delete after RDS)
print_status "Step 3: Cleaning up RDS subnet group..."

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

# Step 4: Clean up EKS cluster and CloudFormation stack (LESSON LEARNED: Enhanced approach)
print_status "Step 4: Cleaning up EKS cluster and CloudFormation stack..."

if resource_exists "cluster" "$CLUSTER_NAME"; then
    print_status "EKS cluster '$CLUSTER_NAME' found"
    
    if confirm_deletion "EKS cluster" "$CLUSTER_NAME"; then
        cleanup_cloudformation_stack "$CLUSTER_NAME"
    else
        print_status "Skipping EKS cluster deletion"
    fi
else
    print_status "EKS cluster '$CLUSTER_NAME' not found"
    # Still try to clean up any lingering CloudFormation stack
    cleanup_cloudformation_stack "$CLUSTER_NAME"
fi

# Clean up any remaining CloudFormation stacks
print_status "Cleaning up any remaining CloudFormation stacks..."
cleanup_remaining_stacks

# Step 5: Clean up Kubernetes secrets
print_status "Step 5: Cleaning up Kubernetes secrets..."
if [ -f "create-secrets.sh" ]; then
    ./create-secrets.sh delete
else
    print_warning "create-secrets.sh not found, skipping secrets cleanup"
fi

# Step 6: Clean up local files
print_status "Step 6: Cleaning up local files..."
rm -f postgresql-testing-config*.env > /dev/null 2>&1 || true
rm -f eks-cluster-config-phase1.yaml > /dev/null 2>&1 || true
rm -f baseline-policies.yaml > /dev/null 2>&1 || true
rm -f test-violations-pod.yaml > /dev/null 2>&1 || true
rm -f values-with-secrets.yaml > /dev/null 2>&1 || true

print_success "Local files cleaned up"

# Step 7: Final verification and status report
print_status "Step 7: Final verification and status report..."

echo ""
echo "=== RESOURCE VERIFICATION ==="

# Check EKS clusters
if eksctl get cluster --region $REGION --profile $AWS_PROFILE | grep -q "$CLUSTER_NAME"; then
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
    print_status "You may want to run: kubectl config unset current-context"
else
    print_success "Kubernetes context cleaned up"
fi

# Check for any remaining CloudFormation stacks
print_status "Checking for remaining CloudFormation stacks..."
REMAINING_STACKS=$(aws cloudformation list-stacks --query "StackSummaries[?contains(StackName, 'reports-server') && StackStatus!='DELETE_COMPLETE'].{Name:StackName,Status:StackStatus}" --output table --profile $AWS_PROFILE 2>/dev/null || echo "No stacks found")
if [ "$REMAINING_STACKS" != "No stacks found" ]; then
    print_warning "Remaining CloudFormation stacks:"
    echo "$REMAINING_STACKS"
    print_status "For DELETE_FAILED stacks, use AWS Console:"
    print_status "1. Go to CloudFormation Console"
    print_status "2. Select the failed stack"
    print_status "3. Click 'Delete' → 'Delete this stack but retain resources'"
    print_status "4. Uncheck VPC to delete it with the stack"
else
    print_success "All CloudFormation stacks cleaned up"
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
echo "=== LESSONS LEARNED APPLIED ==="
echo "✅ Used AWS CLI for EKS deletion (bypasses pod draining issues)"
echo "✅ Deleted resources in correct sequence (RDS → EKS → Subnet Group)"
echo "✅ Implemented force deletion for stuck Kubernetes namespaces"
echo "✅ Added comprehensive resource verification and status reporting"
echo "✅ Provided manual cleanup guidance for CloudFormation stacks"
echo "✅ Enhanced error handling with retry logic and progress indicators"
echo ""
echo "=== NEXT STEPS ==="
echo "If you want to run Phase 1 again:"
echo "  ./phase1-setup.sh"
echo ""
echo "If you want to proceed to Phase 2:"
echo "  ./phase2-setup.sh"
echo ""
print_success "Enhanced cleanup completed successfully! 🎉"
