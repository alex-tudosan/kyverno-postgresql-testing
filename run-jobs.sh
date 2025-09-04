#!/bin/bash

# =============================================================================
# KYVERNO + POSTGRESQL TESTING - MAIN JOB RUNNER
# =============================================================================
# This script provides 4 main jobs for the testing repository:
# 1. Create AWS Infrastructure (EKS + RDS)
# 2. Run Complete Test Plan
# 3. Clean Kubernetes Test Resources
# 4. Clean/Remove AWS Infrastructure
# =============================================================================

set -e

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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if aws CLI is available
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check if we're connected to a cluster
    if ! kubectl cluster-info &> /dev/null; then
        print_warning "Not connected to any Kubernetes cluster"
    fi
    
    print_success "Prerequisites check completed"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [JOB_NUMBER]"
    echo ""
    echo "Available Jobs:"
    echo "  1  - Create AWS Infrastructure (EKS + RDS)"
    echo "  2  - Run Complete Test Plan"
    echo "  3  - Clean Kubernetes Test Resources"
    echo "  4  - Clean/Remove AWS Infrastructure"
    echo ""
    echo "Examples:"
    echo "  $0 1    # Create AWS infrastructure"
    echo "  $0 2    # Run test plan"
    echo "  $0 3    # Clean K8s resources"
    echo "  $0 4    # Clean AWS infrastructure"
    echo ""
    echo "Or run without arguments to see this help"
}

# Job 1: Create AWS Infrastructure
job_1_create_aws_infra() {
    print_status "Starting Job 1: Create AWS Infrastructure"
    echo "This will create:"
    echo "- EKS Cluster (alex-qa-reports-server)"
    echo "- RDS PostgreSQL Instance"
    echo "- Monitoring Stack (Prometheus + Grafana)"
    echo "- Kyverno + Reports Server"
    echo ""
    
    read -p "Do you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Job 1 cancelled by user"
        return
    fi
    
    print_status "Running Phase 1 setup..."
    cd setup/phase1
    ./phase1-setup.sh
    cd ../..
    
    print_success "Job 1 completed: AWS infrastructure created"
}

# Job 2: Run Complete Test Plan
job_2_run_test_plan() {
    print_status "Starting Job 2: Run Complete Test Plan"
    echo "This will execute:"
    echo "- Phase 1: Infrastructure Validation"
    echo "- Phase 2: Object Deployment (200 namespaces, 800 objects)"
    echo "- Phase 3: Controlled Load Testing (20 batches, 400 events)"
    echo ""
    
    read -p "Do you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Job 2 cancelled by user"
        return
    fi
    
    print_status "Executing test plan..."
    
    # Phase 1: Infrastructure Validation
    print_status "Phase 1: Infrastructure Validation"
    kubectl get nodes
    kubectl get pods -n kyverno
    kubectl get pods -n reports-server
    kubectl get pods -n monitoring
    
    # Phase 2: Object Deployment
    print_status "Phase 2: Object Deployment"
    cd test-plan
    ./create-compliant-namespaces.sh
    ./create-deployments.sh
    cd ..
    
    # Phase 3: Load Testing
    print_status "Phase 3: Load Testing Execution"
    cd test-plan
    ./load-testing-execution.sh
    cd ..
    
    print_success "Job 2 completed: Test plan executed successfully"
}

# Job 3: Clean Kubernetes Test Resources
job_3_clean_k8s_resources() {
    print_status "Starting Job 3: Clean Kubernetes Test Resources"
    echo "This will clean:"
    echo "- 200 load-test namespaces and their resources"
    echo "- Test resources in default namespace"
    echo "- Kyverno policy reports (but keep policies)"
    echo ""
    
    read -p "Do you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Job 3 cancelled by user"
        return
    fi
    
    print_status "Cleaning Kubernetes test resources..."
    cd test-plan
    ./cleanup-test-resources.sh
    cd ..
    
    print_success "Job 3 completed: Kubernetes test resources cleaned"
}

# Job 4: Clean/Remove AWS Infrastructure
job_4_clean_aws_infra() {
    print_status "Starting Job 4: Clean/Remove AWS Infrastructure"
    echo "⚠️  WARNING: This will permanently delete:"
    echo "- EKS Cluster and all workloads"
    echo "- RDS PostgreSQL Instance and all data"
    echo "- All AWS resources created by the setup"
    echo ""
    
    read -p "Are you absolutely sure? Type 'DELETE' to confirm: " -r
    if [[ ! $REPLY =~ ^DELETE$ ]]; then
        print_warning "Job 4 cancelled by user"
        return
    fi
    
    print_status "Cleaning AWS infrastructure..."
    cd setup/phase1
    ./phase1-cleanup.sh
    cd ../..
    
    print_success "Job 4 completed: AWS infrastructure removed"
}

# Main execution logic
main() {
    echo "============================================================================="
    echo "KYVERNO + POSTGRESQL TESTING - MAIN JOB RUNNER"
    echo "============================================================================="
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # If no arguments provided, show usage
    if [ $# -eq 0 ]; then
        show_usage
        exit 0
    fi
    
    # Parse job number
    case $1 in
        1)
            job_1_create_aws_infra
            ;;
        2)
            job_2_run_test_plan
            ;;
        3)
            job_3_clean_k8s_resources
            ;;
        4)
            job_4_clean_aws_infra
            ;;
        *)
            print_error "Invalid job number: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"



