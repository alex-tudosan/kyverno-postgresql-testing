#!/bin/bash

# Phase 1 Setup Script for PostgreSQL-based Reports Server Testing
# This script creates a small-scale EKS cluster with RDS PostgreSQL for testing

set -e

echo "🚀 Starting Phase 1 Setup: PostgreSQL-based Reports Server Testing"
echo "================================================================"

# Configuration
CLUSTER_NAME="reports-server-test"
REGION="us-west-1"
RDS_INSTANCE_ID="reports-server-db"
DB_NAME="reports"
DB_USERNAME="reportsuser"

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

# Function to check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 is not installed. Please install it first."
        exit 1
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    print_success "AWS credentials verified"
}

# Function to wait for RDS instance to be available
wait_for_rds() {
    print_status "Waiting for RDS instance to be available..."
    aws rds wait db-instance-available --db-instance-identifier $RDS_INSTANCE_ID
    print_success "RDS instance is available"
}

# Check prerequisites
print_status "Checking prerequisites..."
check_command "aws"
check_command "eksctl"
check_command "kubectl"
check_command "helm"
check_command "jq"
check_aws_credentials

# Set AWS region
export AWS_REGION=$REGION
print_status "Using AWS region: $REGION"

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

# Create EKS cluster
print_status "Creating EKS cluster (this may take 10-15 minutes)..."
eksctl create cluster -f eks-cluster-config-phase1.yaml

# Wait for cluster to be ready
print_status "Waiting for cluster to be ready..."
kubectl wait --for=condition=ready nodes --all --timeout=300s
print_success "EKS cluster is ready"

# Get VPC and subnet information
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.resourcesVpcConfig.vpcId' --output text)
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[?MapPublicIpOnLaunch==`true`].SubnetId' --output text | tr '\t' ' ')

# Create RDS subnet group
print_status "Creating RDS subnet group..."
aws rds create-db-subnet-group \
  --db-subnet-group-name reports-server-subnet-group \
  --db-subnet-group-description "Subnet group for Reports Server RDS" \
  --subnet-ids $SUBNET_IDS 2>/dev/null || print_warning "Subnet group already exists"

# Get default security group
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text)

# Generate database password
DB_PASSWORD=$(openssl rand -base64 32)

# Create RDS instance
print_status "Creating RDS PostgreSQL instance (this may take 5-10 minutes)..."
aws rds create-db-instance \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 14.10 \
  --master-username $DB_USERNAME \
  --master-user-password "$DB_PASSWORD" \
  --allocated-storage 20 \
  --storage-type gp2 \
  --db-subnet-group-name reports-server-subnet-group \
  --vpc-security-group-ids $SECURITY_GROUP_ID \
  --backup-retention-period 7 \
  --multi-az false \
  --auto-minor-version-upgrade \
  --publicly-accessible \
  --storage-encrypted \
  --db-name $DB_NAME

# Wait for RDS to be available
wait_for_rds

# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --query 'DBInstances[0].Endpoint.Address' --output text)
print_success "RDS endpoint: $RDS_ENDPOINT"

# Add Helm repositories
print_status "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add reports-server https://kyverno.github.io/reports-server
helm repo add kyverno https://kyverno.github.io/charts
helm repo update

# Install monitoring stack
print_status "Installing monitoring stack..."
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.enabled=true \
  --set alertmanager.enabled=true \
  --wait

# Create namespace for Reports Server
kubectl create namespace reports-server --dry-run=client -o yaml | kubectl apply -f -

# Install Reports Server with PostgreSQL configuration
print_status "Installing Reports Server with PostgreSQL..."
helm install reports-server reports-server/reports-server \
  --namespace reports-server \
  --set database.type=postgres \
  --set database.postgres.host=$RDS_ENDPOINT \
  --set database.postgres.port=5432 \
  --set database.postgres.database=$DB_NAME \
  --set database.postgres.username=$DB_USERNAME \
  --set database.postgres.password="$DB_PASSWORD" \
  --wait

# Install Kyverno
print_status "Installing Kyverno n4k..."
kubectl create namespace kyverno-system --dry-run=client -o yaml | kubectl apply -f -

helm install kyverno kyverno/kyverno \
  --namespace kyverno-system \
  --set reportsServer.enabled=true \
  --set reportsServer.url=http://reports-server.reports-server.svc.cluster.local:8080 \
  --wait

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

# Wait for all pods to be ready
print_status "Waiting for all components to be ready..."
kubectl wait --for=condition=ready pods --all -n monitoring --timeout=300s
kubectl wait --for=condition=ready pods --all -n reports-server --timeout=300s
kubectl wait --for=condition=ready pods --all -n kyverno-system --timeout=300s

# Save configuration for later use
cat > postgresql-testing-config.env << EOF
# PostgreSQL Testing Configuration
CLUSTER_NAME=$CLUSTER_NAME
REGION=$REGION
RDS_INSTANCE_ID=$RDS_INSTANCE_ID
RDS_ENDPOINT=$RDS_ENDPOINT
DB_NAME=$DB_NAME
DB_USERNAME=$DB_USERNAME
DB_PASSWORD=$DB_PASSWORD
EOF

print_success "Configuration saved to postgresql-testing-config.env"

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
aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,Port:Endpoint.Port}' --output table

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
echo "  1. Run: ./postgresql-testing/phase1-test-cases.sh"
echo "  2. Run: ./postgresql-testing/phase1-monitor.sh"
echo "  3. When done: ./postgresql-testing/phase1-cleanup.sh"
echo ""
print_success "Setup completed successfully! 🎉"
