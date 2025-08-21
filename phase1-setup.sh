#!/bin/bash

# Phase 1 Setup Script for PostgreSQL-based Reports Server Testing
# This script creates a small-scale EKS cluster with RDS PostgreSQL for testing
# FOCUS: Resource provisioning only - testing is optional and separate

set -e

# Add timestamp to resource names to avoid conflicts
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
CLUSTER_NAME="reports-server-test-${TIMESTAMP}"
REGION="us-west-1"
AWS_PROFILE="devtest-sso"
RDS_INSTANCE_ID="reports-server-db-${TIMESTAMP}"
DB_NAME="reports"
DB_USERNAME="reportsuser"

echo "🚀 Starting Phase 1 Resource Provisioning: PostgreSQL-based Reports Server"
echo "========================================================================"
echo "📅 Timestamp: $TIMESTAMP"
echo "🏷️  Cluster Name: $CLUSTER_NAME"
echo "🏷️  RDS Instance: $RDS_INSTANCE_ID"
echo ""

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

# Function to check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 is not installed. Please install it first."
        print_status "Install command: brew install $1"
        exit 1
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    print_status "Checking AWS SSO credentials..."
    if ! aws sts get-caller-identity --profile $AWS_PROFILE &> /dev/null; then
        print_error "AWS SSO credentials not configured or expired."
        print_status "Please run: aws sso login --profile $AWS_PROFILE"
        exit 1
    fi
    print_success "AWS SSO credentials verified"
}

# Function to check if resources already exist
check_existing_resources() {
    print_status "Checking for existing resources..."
    
    # Check for existing EKS cluster
    if eksctl get cluster --name $CLUSTER_NAME --region $REGION --profile $AWS_PROFILE &>/dev/null; then
        print_error "EKS cluster '$CLUSTER_NAME' already exists!"
        print_status "Please delete it first or use a different timestamp"
        exit 1
    fi
    
    # Check for existing RDS instance
    if aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --profile $AWS_PROFILE &>/dev/null; then
        print_error "RDS instance '$RDS_INSTANCE_ID' already exists!"
        print_status "Please delete it first or use a different timestamp"
        exit 1
    fi
    
    print_success "No conflicting resources found"
}

# Function to wait for RDS instance to be available with better error handling
wait_for_rds() {
    print_status "Waiting for RDS instance to be available (timeout: 15 minutes)..."
    local max_attempts=90  # 15 minutes with 10-second intervals
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        show_progress $attempt $max_attempts
        
        # Get RDS status
        local status
        if status=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --query 'DBInstances[0].DBInstanceStatus' --output text --profile $AWS_PROFILE 2>/dev/null); then
            case $status in
                "available")
                    echo ""  # New line after progress bar
                    print_success "RDS instance is available!"
                    return 0
                    ;;
                "failed"|"deleted"|"deleting")
                    echo ""  # New line after progress bar
                    print_error "RDS instance creation failed or was deleted!"
                    return 1
                    ;;
                "creating"|"backing-up"|"modifying"|"rebooting"|"resetting-master-credentials")
                    # Continue waiting
                    ;;
                *)
                    print_warning "Unknown RDS status: $status"
                    ;;
            esac
        else
            print_warning "Could not get RDS status (attempt $attempt/$max_attempts)"
        fi
        
        sleep 10
        ((attempt++))
    done
    
    echo ""  # New line after progress bar
    print_error "RDS instance did not become available within 15 minutes"
    return 1
}

# Function to wait for EKS nodes to be ready with better error handling
wait_for_eks_nodes() {
    print_status "Waiting for EKS nodes to be ready (timeout: 15 minutes)..."
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
                    print_success "All $node_count nodes are ready!"
                    return 0
                fi
            fi
        fi
        
        sleep 10
        ((attempt++))
    done
    
    echo ""  # New line after progress bar
    print_error "EKS nodes did not become ready within 15 minutes"
    return 1
}

# Function to wait for Helm releases to be ready
wait_for_helm_release() {
    local namespace=$1
    local release_name=$2
    local timeout_minutes=${3:-10}
    local max_attempts=$((timeout_minutes * 6))  # Check every 10 seconds
    
    print_status "Waiting for $release_name in namespace $namespace (timeout: ${timeout_minutes} minutes)..."
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        show_progress $attempt $max_attempts
        
        # Check if all pods are running
        if kubectl get pods -n $namespace --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l | grep -q "^0$"; then
            echo ""  # New line after progress bar
            print_success "$release_name is ready!"
            return 0
        fi
        
        sleep 10
        ((attempt++))
    done
    
    echo ""  # New line after progress bar
    print_error "$release_name did not become ready within ${timeout_minutes} minutes"
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

# Function to cleanup on failure
cleanup_on_failure() {
    print_error "Setup failed! Starting cleanup..."
    
    # Delete RDS instance if it exists
    if aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --profile $AWS_PROFILE &>/dev/null; then
        print_status "Deleting RDS instance..."
        aws rds delete-db-instance --db-instance-identifier $RDS_INSTANCE_ID --skip-final-snapshot --profile $AWS_PROFILE
    fi
    
    # Delete EKS cluster if it exists
    if eksctl get cluster --name $CLUSTER_NAME --region $REGION --profile $AWS_PROFILE &>/dev/null; then
        print_status "Deleting EKS cluster..."
        eksctl delete cluster --name $CLUSTER_NAME --region $REGION --profile $AWS_PROFILE
    fi
    
    # Delete subnet group if it exists
    if aws rds describe-db-subnet-groups --db-subnet-group-name reports-server-subnet-group-${TIMESTAMP} --profile $AWS_PROFILE &>/dev/null; then
        print_status "Deleting subnet group..."
        aws rds delete-db-subnet-group --db-subnet-group-name reports-server-subnet-group-${TIMESTAMP} --profile $AWS_PROFILE
    fi
    
    print_warning "Cleanup completed. Please check AWS console for any remaining resources."
}

# Set up error handling
trap cleanup_on_failure ERR

# Check prerequisites
print_status "Checking prerequisites..."
check_command "aws"
check_command "eksctl"
check_command "kubectl"
check_command "helm"
check_command "jq"
check_aws_credentials
check_existing_resources

# Set AWS region and profile
export AWS_REGION=$REGION
export AWS_PROFILE=$AWS_PROFILE
print_status "Using AWS region: $REGION with profile: $AWS_PROFILE"

# Create EKS cluster configuration
print_status "Creating EKS cluster configuration..."
cat > eks-cluster-config-phase1.yaml << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: $CLUSTER_NAME
  region: $REGION
nodeGroups:
  - name: ng-1
    instanceType: t3a.medium
    desiredCapacity: 2
    minSize: 2
    maxSize: 4
    volumeSize: 20
    iam:
      withAddonPolicies:
        autoScaler: true
        ebs: true
        cloudWatch: true
EOF

# Create EKS cluster with retry
print_status "Creating EKS cluster (this may take 15-20 minutes)..."
if ! retry_command 3 30 "eksctl create cluster -f eks-cluster-config-phase1.yaml --profile $AWS_PROFILE"; then
    print_error "Failed to create EKS cluster after retries"
    exit 1
fi

# Wait for cluster to be ready
if ! wait_for_eks_nodes; then
    print_error "EKS cluster did not become ready"
    exit 1
fi

# Get VPC and subnet information
print_status "Getting VPC and subnet information..."
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.resourcesVpcConfig.vpcId' --output text --profile $AWS_PROFILE)
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[?MapPublicIpOnLaunch==`true`].SubnetId' --output text --profile $AWS_PROFILE | tr '\t' ' ')

# Create RDS subnet group
print_status "Creating RDS subnet group..."
aws rds create-db-subnet-group \
    --db-subnet-group-name reports-server-subnet-group-${TIMESTAMP} \
    --db-subnet-group-description "Subnet group for Reports Server RDS ${TIMESTAMP}" \
    --subnet-ids $SUBNET_IDS \
    --profile $AWS_PROFILE 2>/dev/null || print_warning "Subnet group already exists"

# Get default security group
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text --profile $AWS_PROFILE)

# Generate database password (AWS RDS compatible - no special characters)
DB_PASSWORD=$(openssl rand -hex 32 | tr -d '\n')

# Create RDS instance with retry
print_status "Creating RDS PostgreSQL instance (this may take 10-15 minutes)..."
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
  --profile $AWS_PROFILE"; then
    print_error "Failed to create RDS instance after retries"
    exit 1
fi

# Wait for RDS to be available
if ! wait_for_rds; then
    print_error "RDS instance did not become available"
    exit 1
fi

# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --query 'DBInstances[0].Endpoint.Address' --output text --profile $AWS_PROFILE)
print_success "RDS endpoint: $RDS_ENDPOINT"

# Add Helm repositories (handle existing repositories gracefully)
print_status "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || print_status "prometheus-community repository already exists"
helm repo add nirmata-reports-server https://nirmata.github.io/reports-server 2>/dev/null || print_status "nirmata-reports-server repository already exists"
helm repo add kyverno https://kyverno.github.io/charts 2>/dev/null || print_status "kyverno repository already exists"
helm repo update

# Install monitoring stack with retry
print_status "Installing monitoring stack..."
if ! retry_command 3 30 "helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.enabled=true \
  --set alertmanager.enabled=true"; then
    print_error "Failed to install monitoring stack after retries"
    exit 1
fi

# Wait for monitoring stack to be ready
if ! wait_for_helm_release "monitoring" "monitoring" 10; then
    print_error "Monitoring stack did not become ready"
    exit 1
fi

# Create namespace for both Reports Server and Kyverno
kubectl create namespace kyverno --dry-run=client -o yaml | kubectl apply -f -

# Create Kubernetes secrets for PostgreSQL
print_status "Creating Kubernetes secrets for PostgreSQL..."
./create-secrets.sh create

# Install Reports Server FIRST with PostgreSQL configuration and retry
print_status "Installing Reports Server with PostgreSQL (v0.2.3)..."
if ! retry_command 3 30 "helm install reports-server nirmata-reports-server/reports-server \
  --namespace kyverno \
  --version 0.2.3 \
  --set config.db.host=$RDS_ENDPOINT \
  --set config.db.port=5432 \
  --set config.db.name=$DB_NAME \
  --set config.db.user=$DB_USERNAME \
  --set config.db.password=\"$DB_PASSWORD\" \
  --set config.etcd.enabled=false \
  --set config.postgresql.enabled=false"; then
    print_error "Failed to install Reports Server after retries"
    exit 1
fi

# Wait for Reports Server to be ready
if ! wait_for_helm_release "kyverno" "reports-server" 10; then
    print_error "Reports Server did not become ready"
    exit 1
fi

# Install Kyverno SECOND in the same namespace
print_status "Installing Kyverno n4k..."
if ! retry_command 3 30 "helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --set reportsServer.enabled=true \
  --set reportsServer.url=http://reports-server.kyverno.svc.cluster.local:8080"; then
    print_error "Failed to install Kyverno after retries"
    exit 1
fi

# Wait for Kyverno to be ready
if ! wait_for_helm_release "kyverno" "kyverno" 10; then
    print_error "Kyverno did not become ready"
    exit 1
fi

# Install baseline policies
print_status "Installing baseline policies..."
kubectl apply -f https://raw.githubusercontent.com/kyverno/kyverno/main/config/samples/pod-security/pod-security-standards.yaml

# Create baseline policies for testing
cat > baseline-policies.yaml << EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: enforce
  rules:
  - name: check-for-labels
    match:
      resources:
        kinds:
        - Pod
    validate:
      message: "label 'app' is required"
      pattern:
        metadata:
          labels:
            app: "?*"
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged
spec:
  validationFailureAction: enforce
  rules:
  - name: check-privileged
    match:
      resources:
        kinds:
        - Pod
    validate:
      message: "Privileged containers are not allowed"
      pattern:
        spec:
          containers:
          - name: "*"
            securityContext:
              privileged: false
EOF

kubectl apply -f baseline-policies.yaml

# Apply ServiceMonitors for monitoring
print_status "Applying ServiceMonitors for monitoring..."
kubectl apply -f kyverno-servicemonitor.yaml
kubectl apply -f reports-server-servicemonitor.yaml

# Wait for all pods to be ready with timeout
print_status "Waiting for all components to be ready..."
kubectl wait --for=condition=ready pods --all -n monitoring --timeout=300s
kubectl wait --for=condition=ready pods --all -n kyverno --timeout=300s

# Verify Reports Server configuration
print_status "Verifying Reports Server configuration..."
sleep 30
REPORTS_POD=$(kubectl get pods -n kyverno -l app=reports-server -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod -n kyverno $REPORTS_POD | grep -A 10 "Environment:" | grep "DB_HOST"
if kubectl describe pod -n kyverno $REPORTS_POD | grep -q "reports-server-cluster-rw"; then
    print_warning "Reports Server still using internal database. Attempting to restart pod..."
    kubectl delete pod -n kyverno $REPORTS_POD
    sleep 30
    kubectl wait --for=condition=ready pod -n kyverno -l app=reports-server --timeout=300s
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

print_success "Configuration saved to postgresql-testing-config-${TIMESTAMP}.env"

# Display status
print_status "Checking final status..."
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
print_success "Phase 1 Setup Complete!"
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
print_success "Resource provisioning completed successfully! 🎉"

# Remove error trap since we succeeded
trap - ERR
