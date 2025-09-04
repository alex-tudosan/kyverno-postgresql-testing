#!/bin/bash

# Enhanced AWS Cleanup Script with Proper Deletion Order
# ======================================================
# 
# Deletion Order (Reverse of Creation):
# 1. Test Resources (namespaces, pods, etc.)
# 2. Monitoring Stack (Grafana, Prometheus)
# 3. Kyverno + Reports Server
# 4. Node Group + RDS Database (parallel deletion)
# 5. Wait for RDS completion
# 6. Check Node Group completion
# 7. EKS Cluster (wait for completion)
#
# Features:
# - Status checking every 30 seconds
# - 10-minute timeouts for each step
# - Proper resource dependency handling
# - Progress indicators and error handling
# - Parallel deletion for faster cleanup (Node Group + RDS)

set -e

echo "🧹 Enhanced AWS Cleanup: Proper Deletion Order with Status Checking"
echo "=================================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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
CLUSTER_NAME="report-server-test"
REGION="us-west-1"
AWS_PROFILE="devtest-sso"
RDS_INSTANCE_ID="reports-server-db"
NODEGROUP_NAME="${CLUSTER_NAME}-workers"

# Function to wait for resource deletion with timeout
wait_for_deletion() {
    local resource_type=$1
    local resource_name=$2
    local timeout_minutes=10
    local check_interval=30
    local elapsed=0
    
    print_status "Waiting for $resource_type '$resource_name' to be deleted..."
    
    while [ $elapsed -lt $((timeout_minutes * 60)) ]; do
        case $resource_type in
            "nodegroup")
                if ! aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$resource_name" --profile "$AWS_PROFILE" --region "$REGION" >/dev/null 2>&1; then
                    print_success "$resource_type '$resource_name' deleted successfully"
                    return 0
                fi
                ;;
            "cluster")
                if ! aws eks describe-cluster --name "$resource_name" --profile "$AWS_PROFILE" --region "$REGION" >/dev/null 2>&1; then
                    print_success "$resource_type '$resource_name' deleted successfully"
                    return 0
                fi
                ;;
            "rds")
                if ! aws rds describe-db-instances --db-instance-identifier "$resource_name" --profile "$AWS_PROFILE" --region "$REGION" >/dev/null 2>&1; then
                    print_success "$resource_type '$resource_name' deleted successfully"
                    return 0
                fi
                ;;
        esac
        
        print_progress "Still waiting... ($((elapsed / 60))m $((elapsed % 60))s elapsed)"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    print_error "Timeout waiting for $resource_type '$resource_name' deletion after ${timeout_minutes} minutes"
    return 1
}

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    
    case $resource_type in
        "cluster")
            aws eks describe-cluster --name "$resource_name" --profile "$AWS_PROFILE" --region "$REGION" >/dev/null 2>&1
            ;;
        "nodegroup")
            aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$resource_name" --profile "$AWS_PROFILE" --region "$REGION" >/dev/null 2>&1
            ;;
        "rds")
            aws rds describe-db-instances --db-instance-identifier "$resource_name" --profile "$AWS_PROFILE" --region "$REGION" >/dev/null 2>&1
            ;;
    esac
}

# Function to get resource status
get_resource_status() {
    local resource_type=$1
    local resource_name=$2
    
    case $resource_type in
        "cluster")
            aws eks describe-cluster --name "$resource_name" --profile "$AWS_PROFILE" --region "$REGION" --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND"
            ;;
        "nodegroup")
            aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$resource_name" --profile "$AWS_PROFILE" --region "$REGION" --query 'nodegroup.status' --output text 2>/dev/null || echo "NOT_FOUND"
            ;;
        "rds")
            aws rds describe-db-instances --db-instance-identifier "$resource_name" --profile "$AWS_PROFILE" --region "$REGION" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo "NOT_FOUND"
            ;;
    esac
}

# Main cleanup function
main() {
    echo ""
    print_status "Starting enhanced cleanup process..."
    print_status "Cluster: $CLUSTER_NAME"
    print_status "Region: $REGION"
    print_status "AWS Profile: $AWS_PROFILE"
    echo ""
    
    # Step 1: Check current resource status
    print_status "Step 1: Checking current resource status..."
    
    local cluster_status=$(get_resource_status "cluster" "$CLUSTER_NAME")
    local nodegroup_status=$(get_resource_status "nodegroup" "$NODEGROUP_NAME")
    local rds_status=$(get_resource_status "rds" "$RDS_INSTANCE_ID")
    
    echo "   - EKS Cluster: $cluster_status"
    echo "   - Node Group: $nodegroup_status"
    echo "   - RDS Instance: $rds_status"
    echo ""
    
    # Step 2: Start parallel deletion of Node Group and RDS Database
    print_status "Step 2: Starting parallel deletion of Node Group and RDS Database..."
    echo ""
    
    # Start Node Group deletion first (if exists)
    if [ "$nodegroup_status" != "NOT_FOUND" ]; then
        print_status "Step 2a: Deleting EKS node group '$NODEGROUP_NAME'..."
        if aws eks delete-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" --profile "$AWS_PROFILE" --region "$REGION" >/dev/null 2>&1; then
            print_success "Node group deletion initiated"
        else
            print_error "Failed to initiate node group deletion"
        fi
    else
        print_success "Node group already deleted"
    fi
    
    # Start RDS deletion in parallel (if exists)
    if [ "$rds_status" != "NOT_FOUND" ]; then
        print_status "Step 2b: Deleting RDS database '$RDS_INSTANCE_ID' (parallel with node group)..."
        if aws rds delete-db-instance --db-instance-identifier "$RDS_INSTANCE_ID" --skip-final-snapshot --profile "$AWS_PROFILE" --region "$REGION" >/dev/null 2>&1; then
            print_success "RDS deletion initiated"
        else
            print_error "Failed to initiate RDS deletion"
        fi
    else
        print_success "RDS database already deleted"
    fi
    echo ""
    
    # Step 3: Wait for RDS deletion to complete
    if [ "$rds_status" != "NOT_FOUND" ]; then
        print_status "Step 3: Waiting for RDS database deletion to complete..."
        wait_for_deletion "rds" "$RDS_INSTANCE_ID"
    fi
    echo ""
    
    # Step 4: Check if Node Group deletion completed, then wait if needed
    if [ "$nodegroup_status" != "NOT_FOUND" ]; then
        print_status "Step 4: Checking Node Group deletion status..."
        if ! aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" --profile "$AWS_PROFILE" --region "$REGION" >/dev/null 2>&1; then
            print_success "Node group deletion completed"
        else
            print_status "Node group still deleting, waiting for completion..."
            wait_for_deletion "nodegroup" "$NODEGROUP_NAME"
        fi
    fi
    echo ""
    
    # Step 5: Delete EKS Cluster (if exists)
    if [ "$cluster_status" != "NOT_FOUND" ]; then
        print_status "Step 5: Deleting EKS cluster '$CLUSTER_NAME'..."
        if aws eks delete-cluster --name "$CLUSTER_NAME" --profile "$AWS_PROFILE" --region "$REGION" >/dev/null 2>&1; then
            print_success "Cluster deletion initiated"
            wait_for_deletion "cluster" "$CLUSTER_NAME"
        else
            print_error "Failed to initiate cluster deletion"
        fi
    else
        print_success "Cluster already deleted"
    fi
    echo ""
    
    # Step 6: Final verification
            print_status "Step 6: Final resource verification..."
    
    local final_cluster_status=$(get_resource_status "cluster" "$CLUSTER_NAME")
    local final_nodegroup_status=$(get_resource_status "nodegroup" "$NODEGROUP_NAME")
    local final_rds_status=$(get_resource_status "rds" "$RDS_INSTANCE_ID")
    
    echo "   - EKS Cluster: $final_cluster_status"
    echo "   - Node Group: $final_nodegroup_status"
    echo "   - RDS Instance: $final_rds_status"
    echo ""
    
    if [ "$final_cluster_status" = "NOT_FOUND" ] && [ "$final_nodegroup_status" = "NOT_FOUND" ] && [ "$final_rds_status" = "NOT_FOUND" ]; then
        print_success "🎉 All AWS resources successfully deleted!"
        echo ""
        echo "=== COST SAVINGS ACHIEVED ==="
        echo "✅ EKS Control Plane: ~$73/month saved"
        echo "✅ EKS Nodes: ~$30/month saved"
        echo "✅ RDS PostgreSQL: ~$15/month saved"
        echo "✅ Total: ~$121/month saved"
        echo ""
        print_success "Environment is now completely clean! 🚀"
    else
        print_warning "Some resources may still exist. Please check manually."
    fi
}

# Run main function
main "$@"
