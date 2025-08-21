#!/bin/bash

# Script to create Kubernetes secrets for PostgreSQL testing
# This stores sensitive database information securely

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if config file exists
if [ -f "postgresql-testing-config.env" ]; then
    print_status "Loading configuration from postgresql-testing-config.env"
    source postgresql-testing-config.env
else
    print_warning "Configuration file not found. Using default values."
    CLUSTER_NAME="reports-server-test"
    REGION="us-west-1"
    AWS_PROFILE="devtest-sso"
    RDS_INSTANCE_ID="reports-server-db"
    DB_NAME="reports"
    DB_USERNAME="reportsuser"
    DB_PASSWORD=$(openssl rand -base64 32)
    
    # Get RDS endpoint if cluster exists
    if kubectl get nodes >/dev/null 2>&1; then
        RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --query 'DBInstances[0].Endpoint.Address' --output text --profile $AWS_PROFILE 2>/dev/null || echo "")
    else
        RDS_ENDPOINT=""
    fi
fi

# Function to create secrets
create_secrets() {
    print_status "Creating Kubernetes secrets for PostgreSQL..."
    
    # Create namespace if it doesn't exist
kubectl create namespace kyverno --dry-run=client -o yaml | kubectl apply -f -

# Create secret for database credentials
kubectl create secret generic postgresql-credentials \
    --namespace kyverno \
    --from-literal=username="$DB_USERNAME" \
    --from-literal=password="$DB_PASSWORD" \
    --from-literal=database="$DB_NAME" \
    --from-literal=host="$RDS_ENDPOINT" \
    --from-literal=port="5432" \
    --dry-run=client -o yaml | kubectl apply -f -

print_success "Database credentials secret created"

# Create secret for connection string
CONNECTION_STRING="postgresql://$DB_USERNAME:$DB_PASSWORD@$RDS_ENDPOINT:5432/$DB_NAME"
kubectl create secret generic postgresql-connection \
    --namespace kyverno \
    --from-literal=connection-string="$CONNECTION_STRING" \
    --dry-run=client -o yaml | kubectl apply -f -

print_success "Database connection string secret created"

# Create secret for Reports Server configuration
kubectl create secret generic reports-server-config \
    --namespace kyverno \
    --from-literal=db-type="postgresql" \
    --from-literal=db-host="$RDS_ENDPOINT" \
    --from-literal=db-port="5432" \
    --from-literal=db-name="$DB_NAME" \
    --from-literal=db-username="$DB_USERNAME" \
    --from-literal=db-password="$DB_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
    
    print_success "Reports Server configuration secret created"
}

# Function to list secrets
list_secrets() {
    print_status "Listing Kubernetes secrets..."
    echo ""
    echo "=== Secrets in kyverno namespace ==="
    kubectl get secrets -n kyverno
    echo ""
    echo "=== Secret Details ==="
    
    # Show database credentials (password masked)
    echo "Database Credentials:"
    kubectl get secret postgresql-credentials -n kyverno -o jsonpath='{.data.username}' | base64 -d
    echo " (username)"
    echo "******** (password - masked)"
    kubectl get secret postgresql-credentials -n kyverno -o jsonpath='{.data.database}' | base64 -d
    echo " (database)"
    kubectl get secret postgresql-credentials -n kyverno -o jsonpath='{.data.host}' | base64 -d
    echo " (host)"
    echo ""
    
    # Show connection string (password masked)
    echo "Connection String:"
    CONN_STR=$(kubectl get secret postgresql-connection -n kyverno -o jsonpath='{.data.connection-string}' | base64 -d)
    echo "$CONN_STR" | sed 's/:[^:]*@/:****@/'
    echo ""
}

# Function to delete secrets
delete_secrets() {
    print_status "Deleting Kubernetes secrets..."
    
    kubectl delete secret postgresql-credentials -n kyverno --ignore-not-found=true
    kubectl delete secret postgresql-connection -n kyverno --ignore-not-found=true
    kubectl delete secret reports-server-config -n kyverno --ignore-not-found=true
    
    print_success "Secrets deleted"
}

# Function to update Helm values to use secrets
update_helm_values() {
    print_status "Creating Helm values file that uses secrets..."
    
    cat > values-with-secrets.yaml << EOF
# Reports Server configuration using Kubernetes secrets
database:
  type: postgresql
  postgres:
    host: \${POSTGRESQL_HOST}
    port: 5432
    database: \${POSTGRESQL_DATABASE}
    username: \${POSTGRESQL_USERNAME}
    password: \${POSTGRESQL_PASSWORD}

# Environment variables from secrets
env:
  - name: POSTGRESQL_HOST
    valueFrom:
      secretKeyRef:
        name: postgresql-credentials
        key: host
  - name: POSTGRESQL_DATABASE
    valueFrom:
      secretKeyRef:
        name: postgresql-credentials
        key: database
  - name: POSTGRESQL_USERNAME
    valueFrom:
      secretKeyRef:
        name: postgresql-credentials
        key: username
  - name: POSTGRESQL_PASSWORD
    valueFrom:
      secretKeyRef:
        name: postgresql-credentials
        key: password
EOF
    
    print_success "Helm values file created: values-with-secrets.yaml"
    print_status "To use this with Helm:"
    echo "  helm install reports-server nirmata-reports-server/reports-server --version 0.2.3 -f values-with-secrets.yaml"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [create|list|delete|update-values]"
    echo ""
    echo "Commands:"
    echo "  create        - Create Kubernetes secrets for PostgreSQL"
    echo "  list          - List and show secret details (passwords masked)"
    echo "  delete        - Delete all PostgreSQL secrets"
    echo "  update-values - Create Helm values file that uses secrets"
    echo ""
    echo "Examples:"
    echo "  $0 create"
    echo "  $0 list"
    echo "  $0 delete"
    echo "  $0 update-values"
}

# Main script logic
case "${1:-}" in
    "create")
        create_secrets
        ;;
    "list")
        list_secrets
        ;;
    "delete")
        delete_secrets
        ;;
    "update-values")
        update_helm_values
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
