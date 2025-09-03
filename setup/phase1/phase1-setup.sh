#!/bin/bash

# Enhanced error handling and logging
set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Enhanced logging functions
log_step() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] STEP $1:${NC} $2"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Configuration validation
validate_config() {
    log_step "CONFIG" "Validating configuration..."
    
    required_vars=("AWS_REGION" "AWS_PROFILE" "CLUSTER_NAME" "DB_NAME" "DB_USERNAME")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "$var is required but not set"
            exit 1
        fi
    done
    
    log_success "Configuration validation passed"
}

# Database connectivity test
test_database_connectivity() {
    local endpoint=$1
    local username=$2
    local password=$3
    local database=$4
    
    log_step "DATABASE" "Testing connectivity to $endpoint"
    
    if ! PGPASSWORD="$password" psql -h "$endpoint" -U "$username" -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
        log_error "Cannot connect to database at $endpoint"
        return 1
    fi
    
    log_success "Database connectivity test passed"
    return 0
}

# Database verification
create_database() {
    local endpoint=$1
    local username=$2
    local password=$3
    local database=$4
    
    log_step "DATABASE" "Verifying database $database exists and is accessible"
    
    # PostgreSQL doesn't have IF NOT EXISTS for CREATE DATABASE, so we check first
    if PGPASSWORD="$password" psql -h "$endpoint" -U "$username" -d postgres -c "SELECT 1 FROM pg_database WHERE datname='$database';" -t | grep -q 1; then
        log_success "Database $database already exists"
        return 0
    fi
    
    if ! PGPASSWORD="$password" psql -h "$endpoint" -U "$username" -d postgres -c "CREATE DATABASE $database;" >/dev/null 2>&1; then
        log_error "Failed to create database $database"
        return 1
    fi
    
    log_success "Database $database created successfully"
    return 0
}

# Dynamic RDS endpoint resolution
get_rds_endpoint() {
    local instance_id=$1
    local region=$2
    local profile=$3
    
    log_step "RDS" "Resolving endpoint for instance $instance_id"
    
    local endpoint
    endpoint=$(aws rds describe-db-instances \
        --db-instance-identifier "$instance_id" \
        --region "$region" \
        --profile "$profile" \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text 2>/dev/null)
    
    if [[ -z "$endpoint" || "$endpoint" == "None" ]]; then
        log_error "Failed to resolve RDS endpoint for instance $instance_id"
        return 1
    fi
    
    log_success "RDS endpoint resolved: $endpoint"
    echo "$endpoint"
    return 0
}

# Security group validation
validate_security_group() {
    local security_group_id=$1
    local region=$2
    local profile=$3
    
    log_step "SECURITY" "Validating security group $security_group_id"
    
    local rule_count
    rule_count=$(aws ec2 describe-security-group-rules \
        --filters "Name=group-id,Values=$security_group_id" \
        --region "$region" \
        --profile "$profile" \
        --query 'length(SecurityGroupRules[?IpProtocol==`tcp` && FromPort==`5432`])' \
        --output text 2>/dev/null || echo "0")
    
    if [[ "$rule_count" == "0" ]]; then
        log_warning "No PostgreSQL rule found in security group $security_group_id"
        return 1
    fi
    
    log_success "Security group validation passed"
    return 0
}

# Pre-installation validation
validate_kyverno_prerequisites() {
    log_step "VALIDATION" "Validating Kyverno prerequisites..."
    
    # Check if PostgreSQL client is available
    if ! command -v psql &> /dev/null; then
        log_warning "PostgreSQL client not found, installing..."
        if ! brew install postgresql >/dev/null 2>&1; then
            log_error "Failed to install PostgreSQL client"
            return 1
        fi
    fi
    
    # Get RDS endpoint dynamically
    local rds_endpoint
    rds_endpoint=$(get_rds_endpoint "$RDS_INSTANCE_ID" "$AWS_REGION" "$AWS_PROFILE")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Test database connectivity
    if ! test_database_connectivity "$rds_endpoint" "$DB_USERNAME" "$DB_PASSWORD" "$DB_NAME"; then
        return 1
    fi
    
    # Create database if needed
    if ! create_database "$rds_endpoint" "$DB_USERNAME" "$DB_PASSWORD" "$DB_NAME"; then
        return 1
    fi
    
    # Validate security group
    local security_group_id
    security_group_id=$(aws rds describe-db-instances \
        --db-instance-identifier "$RDS_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
        --output text)
    
    validate_security_group "$security_group_id" "$AWS_REGION" "$AWS_PROFILE"
    
    log_success "All Kyverno prerequisites validated"
    return 0
}

# Enhanced retry function with better error handling
retry_command() {
    local max_attempts=$1
    local delay=$2
    shift 2
    local cmd=("$@")
    
    log_step "RETRY" "Executing: ${cmd[*]}"
    
    for ((i=1; i<=max_attempts; i++)); do
        if "${cmd[@]}" >/dev/null 2>&1; then
            log_success "Command succeeded on attempt $i"
            return 0
        else
            if [[ $i -lt $max_attempts ]]; then
                log_warning "Command failed on attempt $i, retrying in ${delay}s..."
                sleep "$delay"
            else
                log_error "Command failed after $max_attempts attempts"
                return 1
            fi
        fi
    done
}

# Enhanced wait function with better feedback
wait_for_helm_release() {
    local release_name=$1
    local namespace=$2
    local timeout=${3:-15}
    
    log_step "HELM" "Waiting for Helm release $release_name in namespace $namespace (timeout: ${timeout}m)"
    
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout * 60))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        if kubectl get pods -n "$namespace" -l app.kubernetes.io/instance="$release_name" --no-headers 2>/dev/null | grep -q "Running"; then
            log_success "Helm release $release_name is ready"
            return 0
        fi
        
        log_warning "Helm release $release_name not ready yet, waiting..."
        sleep 30
    done
    
    log_error "Helm release $release_name did not become ready within ${timeout} minutes"
    return 1
}

# Health check functions
verify_component_health() {
    local component=$1
    local namespace=$2
    local timeout=${3:-300}
    
    log_step "HEALTH" "Verifying health of $component in namespace $namespace"
    
    if ! kubectl wait --for=condition=ready pod -l app.kubernetes.io/name="$component" -n "$namespace" --timeout="${timeout}s" 2>/dev/null; then
        log_error "Component $component is not healthy"
        return 1
    fi
    
    log_success "Component $component is healthy"
    return 0
}

verify_database_connection() {
    local endpoint=$1
    local username=$2
    local password=$3
    local database=$4
    
    log_step "HEALTH" "Verifying database connection to $database"
    
    if ! PGPASSWORD="$password" psql -h "$endpoint" -U "$username" -d "$database" -c "SELECT 1;" >/dev/null 2>&1; then
        log_error "Database connection failed"
        return 1
    fi
    
    log_success "Database connection verified"
    return 0
}

verify_policy_enforcement() {
    log_step "HEALTH" "Verifying policy enforcement"
    
    local policy_count
    policy_count=$(kubectl get clusterpolicies --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [[ "$policy_count" -eq 0 ]]; then
        log_warning "No policies found"
        return 1
    fi
    
    log_success "Found $policy_count active policies"
    return 0
}

# Function to show progress bar
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))
    
    printf "\r${BLUE}[PROGRESS]${NC} ["
    printf "%${completed}s" | tr ' ' '#'
    printf "%${remaining}s" | tr ' ' '-'
    printf "] %d%%" $percentage
}

# Function to get correct subnets for RDS
get_rds_subnets() {
    local vpc_id=$1
    local region=$2
    local profile=$3
    
    # Get all subnets in the VPC - simpler approach
    local subnet_ids
    subnet_ids=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --region "$region" \
        --profile "$profile" \
        --query 'Subnets[].SubnetId' \
        --output text 2>/dev/null)
    
    if [[ -z "$subnet_ids" ]]; then
        log_error "Failed to get subnet IDs for RDS"
        return 1
    fi
    
    # Clean up the subnet IDs - remove tabs and extra whitespace
    subnet_ids=$(echo "$subnet_ids" | tr '\t' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')
    
    # Return only the subnet IDs (no logging in this function)
    echo "$subnet_ids"
    return 0
}

# Function to check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 is not installed. Please install it first."
        log_step "INSTALL" "Install command: brew install $1"
        exit 1
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    log_step "AWS" "Checking AWS SSO credentials..."
    if ! aws sts get-caller-identity --profile $AWS_PROFILE &> /dev/null; then
        log_error "AWS SSO credentials not configured or expired."
        log_step "AWS" "Please run: aws sso login --profile $AWS_PROFILE"
        exit 1
    fi
    log_success "AWS SSO credentials verified"
}

# Function to check if resources already exist
check_existing_resources() {
    log_step "CHECK" "Checking for existing resources..."
    
    # Check for existing EKS cluster using AWS CLI (allow existing cluster)
    if aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE &>/dev/null; then
        log_warning "EKS cluster '$CLUSTER_NAME' already exists - will use existing cluster"
    else
        log_error "EKS cluster '$CLUSTER_NAME' not found!"
        log_step "SETUP" "Please create the cluster first or check the cluster name"
        exit 1
    fi
    
    # Check for existing RDS instance
    if aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --profile $AWS_PROFILE &>/dev/null; then
        log_error "RDS instance '$RDS_INSTANCE_ID' already exists!"
        log_step "CLEANUP" "Please delete it first or use a different timestamp"
        exit 1
    fi
    
    log_success "No conflicting resources found"
}

# Function to wait for RDS instance to be available with better error handling
wait_for_rds() {
    log_step "RDS" "Waiting for RDS instance to be available (timeout: 15 minutes)..."
    local max_attempts=90  # 15 minutes with 10-second intervals
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        show_progress $attempt $max_attempts
        
        # Get RDS status
        local status
        if status=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --region $AWS_REGION --query 'DBInstances[0].DBInstanceStatus' --output text --profile $AWS_PROFILE 2>/dev/null); then
            case $status in
                "available")
                    echo ""  # New line after progress bar
                    log_success "RDS instance is available!"
                    return 0
                    ;;
                "failed"|"deleted"|"deleting")
                    echo ""  # New line after progress bar
                    log_error "RDS instance creation failed or was deleted!"
                    return 1
                    ;;
                "creating"|"backing-up"|"modifying"|"rebooting"|"resetting-master-credentials")
                    # Continue waiting
                    ;;
                *)
                    log_warning "Unknown RDS status: $status"
                    ;;
            esac
        else
            log_warning "Could not get RDS status (attempt $attempt/$max_attempts)"
        fi
        
        sleep 10
        ((attempt++))
    done
    
    echo ""  # New line after progress bar
    log_error "RDS instance did not become available within 15 minutes"
    return 1
}

# Function to wait for EKS nodes to be ready with better error handling
wait_for_eks_nodes() {
    log_step "EKS" "Waiting for EKS nodes to be ready (timeout: 15 minutes)..."
    local max_attempts=90  # 15 minutes with 10-second intervals
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        show_progress $attempt $max_attempts
        
        # Get node status
        local node_count ready_count
        if node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' '); then
            if ready_count=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" 2>/dev/null); then
                if [ "$node_count" -gt 0 ] && [ "$node_count" -eq "$ready_count" ]; then
                    echo ""  # New line after progress bar
                    log_success "All $node_count nodes are ready!"
                    return 0
                fi
            fi
        fi
        
        sleep 10
        ((attempt++))
    done
    
    echo ""  # New line after progress bar
    log_error "EKS nodes did not become ready within 15 minutes"
    return 1
}

# Function to wait for Helm releases to be ready
wait_for_helm_release() {
    local namespace=$1
    local release_name=$2
    local timeout_minutes=${3:-10}
    local max_attempts=$((timeout_minutes * 6))  # Check every 10 seconds
    
    log_step "HELM" "Waiting for $release_name in namespace $namespace (timeout: ${timeout_minutes} minutes)..."
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        show_progress $attempt $max_attempts
        
        # Get pod statuses
        local total_pods=$(kubectl get pods -n $namespace --no-headers 2>/dev/null | wc -l | tr -d ' ')
        local running_pods=$(kubectl get pods -n $namespace --no-headers 2>/dev/null | grep -c "Running\|Completed" 2>/dev/null || echo "0")
        local failed_pods=$(kubectl get pods -n $namespace --no-headers 2>/dev/null | grep -c "Failed\|Error\|CrashLoopBackOff" 2>/dev/null || echo "0")
        
        # Consider ready if most pods are running and no critical failures
        if [ "$total_pods" -gt 0 ] && [ "$failed_pods" -eq 0 ] && [ "$running_pods" -gt 0 ]; then
            # For monitoring stack, be more lenient - allow some pending pods
            if [ "$release_name" = "monitoring" ]; then
                local pending_pods=$(kubectl get pods -n $namespace --no-headers 2>/dev/null | grep -c "Pending" 2>/dev/null || echo "0")
                if [ "$pending_pods" -lt 3 ]; then  # Allow up to 2 pending pods for monitoring
                    echo ""  # New line after progress bar
                    log_success "$release_name is ready! ($running_pods/$total_pods pods running)"
                    return 0
                fi
            else
                echo ""  # New line after progress bar
                log_success "$release_name is ready! ($running_pods/$total_pods pods running)"
                return 0
            fi
        fi
        
        sleep 10
        ((attempt++))
    done
    
    echo ""  # New line after progress bar
    log_error "$release_name did not become ready within ${timeout_minutes} minutes"
    return 1
}

# Function to retry commands with exponential backoff (legacy)
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
                log_error "Command failed after $max_attempts attempts: $command"
                return 1
            fi
            log_warning "Command failed (attempt $attempt/$max_attempts), retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))  # Exponential backoff
            ((attempt++))
        fi
    done
}

# Function to cleanup on failure
cleanup_on_failure() {
    log_error "Setup failed! Starting cleanup..."
    
    # Delete RDS instance if it exists
    if aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --profile $AWS_PROFILE &>/dev/null; then
        log_step "CLEANUP" "Deleting RDS instance..."
        aws rds delete-db-instance --db-instance-identifier $RDS_INSTANCE_ID --skip-final-snapshot --profile $AWS_PROFILE
    fi
    
    # Skip EKS cluster deletion since we're using an existing cluster
    log_step "CLEANUP" "Skipping EKS cluster deletion (using existing cluster: $CLUSTER_NAME)"
    
    # Delete subnet group if it exists
    if aws rds describe-db-subnet-groups --db-subnet-group-name reports-server-subnet-group-${TIMESTAMP} --profile $AWS_PROFILE &>/dev/null; then
        log_step "CLEANUP" "Deleting subnet group..."
        aws rds delete-db-subnet-group --db-subnet-group-name reports-server-subnet-group-${TIMESTAMP} --profile $AWS_PROFILE
    fi
    
    log_warning "Cleanup completed. Please check AWS console for any remaining resources."
}

# Set up error handling
trap cleanup_on_failure ERR

# Check prerequisites
log_step "PREREQ" "Checking prerequisites..."
check_command "aws"
check_command "kubectl"
check_command "helm"
check_command "jq"
check_aws_credentials
check_existing_resources

# Set AWS region and profile
export AWS_REGION=$AWS_REGION
export AWS_PROFILE=$AWS_PROFILE
log_step "CONFIG" "Using AWS region: $AWS_REGION with profile: $AWS_PROFILE"

# Using existing EKS cluster created by Terraform - skipping cluster creation
log_step "EKS" "Using existing EKS cluster created by Terraform: $CLUSTER_NAME"

# Verify the cluster exists and is accessible
log_step "EKS" "Verifying existing EKS cluster..."
if ! aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE &>/dev/null; then
    log_error "EKS cluster '$CLUSTER_NAME' not found or not accessible"
    exit 1
fi

# Get cluster status
CLUSTER_STATUS=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE --query 'cluster.status' --output text)
log_step "EKS" "Cluster status: $CLUSTER_STATUS"

# Wait for cluster to be active if it's still creating
if [[ "$CLUSTER_STATUS" == "CREATING" ]]; then
    log_step "EKS" "Waiting for existing cluster to become active..."
    if ! retry_command 30 30 "aws eks wait cluster-active --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE"; then
        log_error "EKS cluster did not become active within timeout"
        exit 1
    fi
fi

# Update kubeconfig to access the cluster
log_step "EKS" "Updating kubeconfig for cluster access..."
if ! aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE; then
    log_error "Failed to update kubeconfig"
    exit 1
fi

# Wait for cluster to be ready
if ! wait_for_eks_nodes; then
    log_error "EKS cluster did not become ready"
    exit 1
fi

# Get VPC and subnet information
log_step "VPC" "Getting VPC and subnet information..."
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text --profile $AWS_PROFILE)

# Get correct subnets for RDS (from different AZs)
log_step "SUBNETS" "Getting subnets for RDS subnet group..."
RDS_SUBNET_IDS=$(get_rds_subnets "$VPC_ID" "$AWS_REGION" "$AWS_PROFILE")
if [[ $? -ne 0 ]]; then
    log_error "Failed to get RDS subnet IDs"
    exit 1
fi
log_step "SUBNETS" "Found subnets: '$RDS_SUBNET_IDS'"

# Create RDS subnet group
log_step "RDS" "Creating RDS subnet group..."
log_step "DEBUG" "Subnet IDs being used: '$RDS_SUBNET_IDS'"
log_step "DEBUG" "Subnet group name: reports-server-subnet-group-${TIMESTAMP}"

if ! aws rds create-db-subnet-group \
    --db-subnet-group-name reports-server-subnet-group-${TIMESTAMP} \
    --db-subnet-group-description "Subnet group for Reports Server RDS ${TIMESTAMP}" \
    --subnet-ids $RDS_SUBNET_IDS \
    --region $AWS_REGION \
    --profile $AWS_PROFILE; then
    log_error "Failed to create RDS subnet group"
    exit 1
fi

# Verify subnet group was created
log_step "RDS" "Verifying subnet group creation..."
if ! aws rds describe-db-subnet-groups --db-subnet-group-name reports-server-subnet-group-${TIMESTAMP} --region $AWS_REGION --profile $AWS_PROFILE &>/dev/null; then
    log_error "Subnet group verification failed"
    exit 1
fi
log_success "RDS subnet group created successfully"

# Get default security group
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" --region $AWS_REGION --query 'SecurityGroups[0].GroupId' --output text --profile $AWS_PROFILE)

# Configure security group to allow PostgreSQL access
log_step "SECURITY" "Configuring security group for PostgreSQL access..."
aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 5432 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION \
    --profile $AWS_PROFILE 2>/dev/null || log_warning "Security group rule may already exist"

log_success "Security group configured for PostgreSQL access on port 5432"

# Generate database password (AWS RDS compatible - no special characters)
DB_PASSWORD=$(openssl rand -hex 32 | tr -d '\n')

# Create RDS instance with retry
log_step "RDS" "Creating RDS PostgreSQL instance (this may take 10-15 minutes)..."
if ! retry_command 3 60 "aws rds create-db-instance \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 14.12 \
  --master-username $DB_USERNAME \
  --master-user-password \"$DB_PASSWORD\" \
  --allocated-storage 20 \
  --storage-type gp2 \
  --db-subnet-group-name reports-server-subnet-group-${TIMESTAMP} \
  --vpc-security-group-ids $SECURITY_GROUP_ID \
  --backup-retention-period 7 \
  --no-multi-az \
  --auto-minor-version-upgrade \
  --publicly-accessible \
  --storage-encrypted \
  --db-name $DB_NAME \
  --region $AWS_REGION \
  --profile $AWS_PROFILE"; then
    log_error "Failed to create RDS instance after retries"
    exit 1
fi

# Wait for RDS to be available
if ! wait_for_rds; then
    log_error "RDS instance did not become available"
    exit 1
fi

# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --region $AWS_REGION --query 'DBInstances[0].Endpoint.Address' --output text --profile $AWS_PROFILE)
log_success "RDS endpoint: $RDS_ENDPOINT"

# Test and verify database connectivity
log_step "DATABASE" "Testing and verifying database connectivity..."
if ! test_database_connectivity "$RDS_ENDPOINT" "$DB_USERNAME" "$DB_PASSWORD" "postgres"; then
    log_warning "Database connectivity failed, resetting password..."
    
    # Reset RDS password
    NEW_PASSWORD=$(openssl rand -hex 16)
    aws rds modify-db-instance \
        --db-instance-identifier $RDS_INSTANCE_ID \
        --master-user-password "$NEW_PASSWORD" \
        --region $AWS_REGION \
        --profile $AWS_PROFILE \
        --apply-immediately
    
    # Wait for password update
    log_step "DATABASE" "Waiting for password update to complete..."
    sleep 60
    
    # Update the password variable
    DB_PASSWORD="$NEW_PASSWORD"
    
    # Test connectivity again
    if ! test_database_connectivity "$RDS_ENDPOINT" "$DB_USERNAME" "$DB_PASSWORD" "postgres"; then
        log_error "Database connectivity still failed after password reset"
        exit 1
    fi
fi

# Verify database exists and is ready
if ! create_database "$RDS_ENDPOINT" "$DB_USERNAME" "$DB_PASSWORD" "$DB_NAME"; then
    log_error "Failed to verify database $DB_NAME"
    exit 1
fi

# Add Helm repositories (handle existing repositories gracefully)
log_step "HELM" "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || log_step "HELM" "prometheus-community repository already exists"
helm repo add nirmata-reports-server https://nirmata.github.io/reports-server 2>/dev/null || log_step "HELM" "nirmata-reports-server repository already exists"
helm repo add kyverno https://kyverno.github.io/charts 2>/dev/null || log_step "HELM" "kyverno repository already exists"
helm repo update

# Install monitoring stack with retry
log_step "MONITORING" "Installing monitoring stack..."
if ! retry_command 3 30 "helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.enabled=true \
  --set alertmanager.enabled=true"; then
    log_error "Failed to install monitoring stack after retries"
    exit 1
fi

# Wait for monitoring stack to be ready (increased timeout)
if ! wait_for_helm_release "monitoring" "monitoring" 15; then
    log_error "Monitoring stack did not become ready"
    exit 1
fi

# Create namespace for Kyverno
log_step "KYVERNO" "Creating Kyverno namespace..."
kubectl create namespace kyverno --dry-run=client -o yaml | kubectl apply -f -

# Install Kyverno (separate from Reports Server)
log_step "KYVERNO" "Installing Kyverno..."
if ! retry_command 3 30 "helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --version=3.5.1"; then
    log_error "Failed to install Kyverno after retries"
    exit 1
fi

# Wait for Kyverno to be ready
if ! wait_for_helm_release "kyverno" "kyverno" 20; then
    log_error "Kyverno did not become ready"
    exit 1
fi

# Install Reports Server separately (connected to PostgreSQL)
log_step "REPORTS-SERVER" "Installing Reports Server..."
if ! retry_command 3 30 "helm install reports-server-db nirmata/reports-server \
  --namespace kyverno \
  --set config.etcd.enabled=false \
  --set config.db.name=$DB_NAME \
  --set config.db.user=$DB_USERNAME \
  --set config.db.password=\"$DB_PASSWORD\" \
  --set config.db.host=$RDS_ENDPOINT \
  --set config.db.port=5432 \
  --set apiServicesManagement.installApiServices.enabled=false"; then
    log_error "Failed to install Reports Server after retries"
    exit 1
fi

# Wait for Reports Server to be ready
if ! wait_for_helm_release "kyverno" "reports-server-db" 15; then
    log_error "Reports Server did not become ready"
    exit 1
fi

# Install baseline policies
log_step "POLICIES" "Installing baseline policies..."
# Note: External URL may not be available, so we'll use local policies instead

# Apply local baseline policies
log_step "POLICIES" "Applying local baseline policies..."
kubectl apply -f policies/baseline/require-labels.yaml
kubectl apply -f policies/baseline/disallow-privileged-containers.yaml

# Note: ServiceMonitors are optional and can be added later if needed
log_step "MONITORING" "ServiceMonitors can be added later for enhanced monitoring"

# Wait for all pods to be ready with timeout
log_step "WAIT" "Waiting for all components to be ready..."
kubectl wait --for=condition=ready pods --all -n monitoring --timeout=300s
kubectl wait --for=condition=ready pods --all -n kyverno --timeout=300s

# Perform health checks
log_step "HEALTH" "Performing health checks..."
verify_component_health "kyverno" "kyverno" 300
verify_database_connection "$RDS_ENDPOINT" "$DB_USERNAME" "$DB_PASSWORD" "$DB_NAME"
verify_policy_enforcement

# Verify Kyverno with Reports Server configuration
log_step "VERIFY" "Verifying Kyverno with Reports Server configuration..."
sleep 30

# Check for Reports Server pod in the integrated installation
REPORTS_POD=$(kubectl get pods -n kyverno -l app.kubernetes.io/component=reports-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$REPORTS_POD" ]; then
    log_success "Found Reports Server pod: $REPORTS_POD"
    kubectl describe pod -n kyverno $REPORTS_POD | grep -A 10 "Environment:" | grep "DB_HOST" || log_warning "Database host not found in environment"
else
    log_warning "Reports Server pod not found with expected label"
    log_step "DEBUG" "Checking all pods in kyverno namespace:"
    kubectl get pods -n kyverno
fi

# Save configuration for later use
cat > postgresql-testing-config-${TIMESTAMP}.env << EOF
# PostgreSQL Testing Configuration - Generated on $(date)
CLUSTER_NAME=$CLUSTER_NAME
REGION=$REGION
RDS_INSTANCE_ID=$RDS_INSTANCE_ID
RDS_ENDPOINT=$RDS_ENDPOINT
DB_NAME=$DB_NAME
DB_USERNAME=$DB_USERNAME
DB_PASSWORD=$DB_PASSWORD
TIMESTAMP=$TIMESTAMP
EOF

log_success "Configuration saved to postgresql-testing-config-${TIMESTAMP}.env"

# Display status
log_step "STATUS" "Checking final status..."
echo ""
echo "=== Cluster Status ==="
kubectl get nodes
echo ""
echo "=== Pod Status ==="
kubectl get pods -A
echo ""
echo "=== RDS Status ==="
aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,Port:Endpoint.Port}' --output table --profile $AWS_PROFILE

# Display access information
echo ""
log_success "Phase 1 Setup Complete!"
echo ""
echo "=== Access Information ==="
echo "Grafana Dashboard:"
echo "  kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80"
echo "  Password: $(kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
echo ""
echo "RDS Database:"
echo "  Endpoint: $RDS_ENDPOINT"
echo "  Database: $DB_NAME"
echo "  Username: $DB_USERNAME"
echo "  Password: $DB_PASSWORD"
echo ""
echo "Next Steps:"
echo "  1. Verify all resources are running correctly"
echo "  2. Run: ./phase1-test-cases.sh (optional - for testing)"
echo "  3. Run: ./phase1-monitor.sh (optional - for monitoring)"
echo "  4. When done: ./phase1-cleanup.sh"
echo ""
log_success "Resource provisioning completed successfully! 🎉"

# Remove error trap since we succeeded
trap - ERR

# For load testing with many namespaces, use test-plan/create-compliant-namespaces.sh
# =============================================================================

# =============================================================================
# COMPLIANT NAMESPACE CREATION
# =============================================================================
# This function creates namespaces that comply with the 'require-ns-label-owner' policy.
# Use this function when creating namespaces that need to satisfy policy requirements.
#
# Usage:
#   create_compliant_namespace "namespace-name" "owner-label"
#   create_compliant_namespace "test-ns" "test-user"
#
# For load testing with many namespaces, use test-plan/create-compliant-namespaces.sh
# =============================================================================

# Function to create compliant namespaces
create_compliant_namespace() {
    local namespace=$1
    local owner_label=${2:-"kyverno-admin"}
    
    log_step "NAMESPACE" "Creating compliant namespace: $namespace"
    
    # Check if namespace already exists
    if kubectl get namespace "$namespace" &>/dev/null; then
        log_warning "Namespace $namespace already exists, skipping creation."
        return 0
    fi
    
    # Create namespace with required labels using YAML approach
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $namespace
  labels:
    owner: $owner_label
    app.kubernetes.io/managed-by: kyverno
    app.kubernetes.io/name: $namespace
    app.kubernetes.io/instance: $namespace
    app.kubernetes.io/version: "1.0.0"
    app.kubernetes.io/component: reports-server
    app.kubernetes.io/part-of: kyverno-reports-server
    app.kubernetes.io/created-by: kyverno-setup-script
EOF
    
    if [[ $? -eq 0 ]]; then
        log_success "Namespace $namespace created successfully with required labels."
        return 0
    else
        log_error "Failed to create compliant namespace $namespace"
        return 1
    fi
}
