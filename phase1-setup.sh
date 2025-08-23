#!/bin/bash

# =============================================================================
# Phase 1 Setup Script for Kyverno Reports Server with PostgreSQL
# =============================================================================
#
# This script sets up a complete infrastructure for Kyverno Reports Server:
# - EKS cluster with monitoring stack (Prometheus/Grafana)
# - RDS PostgreSQL database
# - Kyverno with Reports Server integration
# - Baseline security policies
#
# Prerequisites:
# - AWS CLI configured with SSO
# - eksctl, kubectl, helm, jq installed
# - config.sh file with required variables
#
# Usage:
#   ./phase1-setup.sh                    # Run with default settings
#   ./phase1-setup.sh --help             # Show this help
#   ./phase1-setup.sh --debug            # Enable debug mode
#   ./phase1-setup.sh --no-cleanup       # Disable automatic cleanup
#   ENABLE_DEBUG=true ./phase1-setup.sh  # Environment variable method
#
# Environment Variables:
#   ENABLE_DEBUG=true          # Enable detailed debug logging
#   CLEANUP_ON_ERROR=false     # Disable automatic cleanup on failure
#   EKS_CLUSTER_TIMEOUT=20     # Custom EKS cluster timeout (minutes)
#   RDS_READY_TIMEOUT=25       # Custom RDS ready timeout (minutes)
#   EKS_INSTANCE_TYPE=t3.large # Custom EKS instance type
#   RDS_INSTANCE_CLASS=db.t3.small # Custom RDS instance class
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Configuration error
#   3 - Prerequisites not met
#   4 - AWS permissions error
#   5 - Resource creation failed
#   6 - Health check failed
#
# Files Created:
#   - eks-cluster-config-phase1.yaml (temporary)
#   - postgresql-testing-config-${TIMESTAMP}.env
#   - phase1-setup-errors-${TIMESTAMP}.log (on error)
#
# =============================================================================

# Help function
show_help() {
    cat << EOF
Phase 1 Setup Script for Kyverno Reports Server

DESCRIPTION:
    Sets up a complete infrastructure for Kyverno Reports Server including:
    - EKS cluster with monitoring stack (Prometheus/Grafana)
    - RDS PostgreSQL database
    - Kyverno with Reports Server integration
    - Baseline security policies

PREREQUISITES:
    - AWS CLI configured with SSO: aws sso login --profile <profile>
    - Required tools: eksctl, kubectl, helm, jq
    - config.sh file with required variables

USAGE:
    ./phase1-setup.sh [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -d, --debug         Enable debug mode (detailed logging)
    -n, --no-cleanup    Disable automatic cleanup on failure
    -v, --version       Show version information

ENVIRONMENT VARIABLES:
    ENABLE_DEBUG=true          Enable detailed debug logging
    CLEANUP_ON_ERROR=false     Disable automatic cleanup on failure
    EKS_CLUSTER_TIMEOUT=20     Custom EKS cluster timeout (minutes)
    RDS_READY_TIMEOUT=25       Custom RDS ready timeout (minutes)
    EKS_INSTANCE_TYPE=t3.large Custom EKS instance type
    RDS_INSTANCE_CLASS=db.t3.small Custom RDS instance class

EXAMPLES:
    # Basic setup
    ./phase1-setup.sh

    # Debug mode
    ./phase1-setup.sh --debug

    # Custom timeouts
    EKS_CLUSTER_TIMEOUT=20 RDS_READY_TIMEOUT=25 ./phase1-setup.sh

    # Production settings
    EKS_INSTANCE_TYPE=t3.large EKS_NODE_COUNT=3 RDS_INSTANCE_CLASS=db.t3.small ./phase1-setup.sh

EXIT CODES:
    0 - Success
    1 - General error
    2 - Configuration error
    3 - Prerequisites not met
    4 - AWS permissions error
    5 - Resource creation failed
    6 - Health check failed

FILES:
    Created:
    - eks-cluster-config-phase1.yaml (temporary cluster config)
    - postgresql-testing-config-${TIMESTAMP}.env (connection details)
    - phase1-setup-errors-${TIMESTAMP}.log (error log, if any)

    Required:
    - config.sh (configuration variables)
    - policies/baseline/*.yaml (baseline policies)
    - kyverno-servicemonitor.yaml (monitoring config)
    - reports-server-servicemonitor.yaml (monitoring config)

TROUBLESHOOTING:
    - Check error log: cat phase1-setup-errors-*.log
    - Run cleanup: ./phase1-cleanup.sh
    - Check AWS console for resource status
    - Verify AWS credentials: aws sts get-caller-identity --profile <profile>

SUPPORT:
    For issues, check:
    1. Error log file for detailed error information
    2. AWS console for resource status
    3. Run cleanup script to remove partial resources
    4. Verify all prerequisites are met

EOF
    exit 0
}

# Version function
show_version() {
    echo "Phase 1 Setup Script v1.0.0"
    echo "Kyverno Reports Server Infrastructure Setup"
    echo "Last updated: $(date -r $0 '+%Y-%m-%d')"
    exit 0
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                ;;
            -v|--version)
                show_version
                ;;
            -d|--debug)
                ENABLE_DEBUG=true
                shift
                ;;
            -n|--no-cleanup)
                CLEANUP_ON_ERROR=false
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Parse arguments if any
parse_arguments "$@"

# Source configuration
source config.sh

# Enhanced error handling and logging
set -euo pipefail

# Error handling and recovery variables
SCRIPT_START_TIME=$(date +%s)
CLEANUP_ON_ERROR=${CLEANUP_ON_ERROR:-true}
SKIP_CLEANUP_ON_SUCCESS=${SKIP_CLEANUP_ON_SUCCESS:-false}
ENABLE_DEBUG=${ENABLE_DEBUG:-false}
ERROR_LOG_FILE="phase1-setup-errors-$(date +%Y%m%d-%H%M%S).log"

# Debug function
debug_log() {
    if [[ "$ENABLE_DEBUG" == "true" ]]; then
        echo -e "${YELLOW}[DEBUG]${NC} $1" | tee -a "$ERROR_LOG_FILE"
    fi
}

# Function to display current configuration
show_configuration() {
    log_step "CONFIG" "Current configuration:"
    echo ""
    echo "=== Environment Configuration ==="
    echo "  AWS Region: $AWS_REGION"
    echo "  AWS Profile: $AWS_PROFILE"
    echo "  Cluster Name: $CLUSTER_NAME"
    echo "  RDS Instance ID: $RDS_INSTANCE_ID"
    echo "  Database Name: $DB_NAME"
    echo "  Database Username: $DB_USERNAME"
    echo "  Password File: $PASSWORD_FILE"
    echo ""
    echo "=== Timeout Configuration ==="
    echo "  EKS Cluster Timeout: ${EKS_CLUSTER_TIMEOUT} minutes"
    echo "  EKS Nodes Timeout: ${EKS_NODES_TIMEOUT} minutes"
    echo "  RDS Creation Timeout: ${RDS_CREATION_TIMEOUT} minutes"
    echo "  RDS Ready Timeout: ${RDS_READY_TIMEOUT} minutes"
    echo "  Helm Release Timeout: ${HELM_RELEASE_TIMEOUT} minutes"
    echo "  Pod Ready Timeout: ${POD_READY_TIMEOUT} minutes"
    echo ""
    echo "=== Resource Configuration ==="
    echo "  EKS Instance Type: $EKS_INSTANCE_TYPE"
    echo "  EKS Node Count: $EKS_NODE_COUNT"
    echo "  EKS Volume Size: ${EKS_VOLUME_SIZE} GB"
    echo "  RDS Instance Class: $RDS_INSTANCE_CLASS"
    echo "  RDS Storage Size: ${RDS_STORAGE_SIZE} GB"
    echo "  RDS Engine Version: $RDS_ENGINE_VERSION"
    echo "  RDS Backup Retention: ${RDS_BACKUP_RETENTION} days"
    echo ""
    echo "=== Behavior Configuration ==="
    echo "  Debug Mode: $ENABLE_DEBUG"
    echo "  Cleanup on Error: $CLEANUP_ON_ERROR"
    echo "  Skip Cleanup on Success: $SKIP_CLEANUP_ON_SUCCESS"
    echo ""
}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurable timeout and retry settings
# Timeouts (in minutes)
EKS_CLUSTER_TIMEOUT=${EKS_CLUSTER_TIMEOUT:-15}
EKS_NODES_TIMEOUT=${EKS_NODES_TIMEOUT:-15}
RDS_CREATION_TIMEOUT=${RDS_CREATION_TIMEOUT:-20}
RDS_READY_TIMEOUT=${RDS_READY_TIMEOUT:-20}
HELM_RELEASE_TIMEOUT=${HELM_RELEASE_TIMEOUT:-10}
POD_READY_TIMEOUT=${POD_READY_TIMEOUT:-5}
DATABASE_CONNECT_TIMEOUT=${DATABASE_CONNECT_TIMEOUT:-10}
PASSWORD_RESET_TIMEOUT=${PASSWORD_RESET_TIMEOUT:-5}

# Retry settings
EKS_CLUSTER_RETRIES=${EKS_CLUSTER_RETRIES:-3}
EKS_CLUSTER_RETRY_DELAY=${EKS_CLUSTER_RETRY_DELAY:-30}
RDS_CREATION_RETRIES=${RDS_CREATION_RETRIES:-3}
RDS_CREATION_RETRY_DELAY=${RDS_CREATION_RETRY_DELAY:-60}
HELM_INSTALL_RETRIES=${HELM_INSTALL_RETRIES:-3}
HELM_INSTALL_RETRY_DELAY=${HELM_INSTALL_RETRY_DELAY:-30}

# Sleep intervals (in seconds)
DATABASE_CHECK_INTERVAL=${DATABASE_CHECK_INTERVAL:-10}
RDS_STATUS_CHECK_INTERVAL=${RDS_STATUS_CHECK_INTERVAL:-20}
EKS_NODE_CHECK_INTERVAL=${EKS_NODE_CHECK_INTERVAL:-10}
HELM_CHECK_INTERVAL=${HELM_CHECK_INTERVAL:-10}
VERIFICATION_SLEEP=${VERIFICATION_SLEEP:-30}

# EKS cluster configuration
EKS_INSTANCE_TYPE=${EKS_INSTANCE_TYPE:-t3a.medium}
EKS_NODE_COUNT=${EKS_NODE_COUNT:-2}
EKS_VOLUME_SIZE=${EKS_VOLUME_SIZE:-20}

# RDS configuration
RDS_INSTANCE_CLASS=${RDS_INSTANCE_CLASS:-db.t3.micro}
RDS_STORAGE_SIZE=${RDS_STORAGE_SIZE:-20}
RDS_ENGINE_VERSION=${RDS_ENGINE_VERSION:-14.12}
RDS_BACKUP_RETENTION=${RDS_BACKUP_RETENTION:-7}

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

# Enhanced error handling function
handle_error() {
    local exit_code=$?
    local line_number=$1
    local command=$2
    
    # Calculate script runtime
    local runtime=$(( $(date +%s) - SCRIPT_START_TIME ))
    local runtime_minutes=$((runtime / 60))
    local runtime_seconds=$((runtime % 60))
    
    log_error "Script failed at line $line_number: $command (exit code: $exit_code)"
    log_error "Script runtime: ${runtime_minutes}m ${runtime_seconds}s"
    
    # Log error details to file
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR at line $line_number: $command (exit code: $exit_code)" >> "$ERROR_LOG_FILE"
    echo "Script runtime: ${runtime_minutes}m ${runtime_seconds}s" >> "$ERROR_LOG_FILE"
    
    # Show current state
    log_step "ERROR" "Current state at failure:"
    echo "  - Cluster: $CLUSTER_NAME"
    echo "  - RDS Instance: $RDS_INSTANCE_ID"
    echo "  - Region: $AWS_REGION"
    echo "  - Profile: $AWS_PROFILE"
    
    # Provide recovery suggestions
    log_step "RECOVERY" "Recovery options:"
    echo "  1. Check error log: cat $ERROR_LOG_FILE"
    echo "  2. Manual cleanup: ./phase1-cleanup.sh"
    echo "  3. Retry setup: ./phase1-setup.sh"
    echo "  4. Debug mode: ENABLE_DEBUG=true ./phase1-setup.sh"
    
    # Run cleanup if enabled
    if [[ "$CLEANUP_ON_ERROR" == "true" ]]; then
        log_step "CLEANUP" "Running automatic cleanup..."
        ./phase1-cleanup.sh || {
            log_warning "Automatic cleanup failed. Please run manual cleanup."
        }
    else
        log_warning "Automatic cleanup disabled. Please run: ./phase1-cleanup.sh"
    fi
    
    exit $exit_code
}

# Configuration validation
validate_config() {
    log_step "CONFIG" "Validating configuration..."
    
    # Check required variables
    required_vars=("AWS_REGION" "AWS_PROFILE" "CLUSTER_NAME" "DB_NAME" "DB_USERNAME" "PASSWORD_FILE")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "$var is required but not set"
            return 1
        fi
    done
    
    # Validate AWS region format
    if [[ ! "$AWS_REGION" =~ ^[a-z]{2}-[a-z]+-[1-9]$ ]]; then
        log_error "Invalid AWS region format: $AWS_REGION (expected format: us-west-1)"
        return 1
    fi
    
    # Validate cluster name format (alphanumeric and hyphens only)
    if [[ ! "$CLUSTER_NAME" =~ ^[a-z0-9-]+$ ]]; then
        log_error "Invalid cluster name format: $CLUSTER_NAME (only lowercase letters, numbers, and hyphens allowed)"
        return 1
    fi
    
    # Validate database name format (alphanumeric and underscores only)
    if [[ ! "$DB_NAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
        log_error "Invalid database name format: $DB_NAME (only letters, numbers, and underscores allowed)"
        return 1
    fi
    
    # Validate database username format (alphanumeric and underscores only)
    if [[ ! "$DB_USERNAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
        log_error "Invalid database username format: $DB_USERNAME (only letters, numbers, and underscores allowed)"
        return 1
    fi
    
    # Check if required files exist
    if [[ ! -f "policies/baseline/require-labels.yaml" ]]; then
        log_error "Required file not found: policies/baseline/require-labels.yaml"
        return 1
    fi
    
    if [[ ! -f "policies/baseline/disallow-privileged-containers.yaml" ]]; then
        log_error "Required file not found: policies/baseline/disallow-privileged-containers.yaml"
        return 1
    fi
    
    if [[ ! -f "kyverno-servicemonitor.yaml" ]]; then
        log_error "Required file not found: kyverno-servicemonitor.yaml"
        return 1
    fi
    
    if [[ ! -f "reports-server-servicemonitor.yaml" ]]; then
        log_error "Required file not found: reports-server-servicemonitor.yaml"
        return 1
    fi
    
    log_success "Configuration validation passed"
}

# Database connectivity test with intelligent error handling
test_database_connectivity() {
    local endpoint=$1
    local username=$2
    local password=$3
    local database=$4
    local instance_id=${5:-}
    
    log_step "DATABASE" "Testing connectivity to $endpoint"
    
    # First attempt with current password
    if PGPASSWORD="$password" psql -h "$endpoint" -U "$username" -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
        log_success "Database connectivity test passed"
        return 0
    fi
    
    # Capture the actual error to determine if it's network or authentication
    local error_output
    error_output=$(PGPASSWORD="$password" psql -h "$endpoint" -U "$username" -d postgres -c "SELECT 1;" 2>&1)
    
    # Check if it's a network connectivity issue
    if echo "$error_output" | grep -q "Operation timed out\|Connection refused\|No route to host\|Network is unreachable"; then
        log_warning "Network connectivity issue detected. Waiting for RDS to be fully ready..."
        
        # Wait longer for RDS to be fully ready
        local max_attempts=$((DATABASE_CONNECT_TIMEOUT * 60 / DATABASE_CHECK_INTERVAL))
        local attempt=1
        while [[ $attempt -le $max_attempts ]]; do
            log_step "DATABASE" "Waiting for RDS to be fully ready (attempt $attempt/$max_attempts)..."
            
            if PGPASSWORD="$password" psql -h "$endpoint" -U "$username" -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
                log_success "Database connectivity test passed after waiting"
                return 0
            fi
            
            # Check if it's still a network issue or now an auth issue
            local current_error
            current_error=$(PGPASSWORD="$password" psql -h "$endpoint" -U "$username" -d postgres -c "SELECT 1;" 2>&1)
            
            if echo "$current_error" | grep -q "FATAL.*password authentication failed"; then
                log_warning "Network issue resolved, but password authentication failed. Proceeding with password reset..."
                break
            fi
            
            sleep $DATABASE_CHECK_INTERVAL
            ((attempt++))
        done
        
        if [[ $attempt -gt $max_attempts ]]; then
            log_error "RDS did not become accessible within $DATABASE_CONNECT_TIMEOUT minutes"
            return 1
        fi
    fi
    
    # Only reset password if we have an authentication error (not network issue)
    if echo "$error_output" | grep -q "FATAL.*password authentication failed"; then
        log_warning "Password authentication failed, attempting password reset..."
        
        # If instance_id is provided, try to reset password
        if [[ -n "$instance_id" ]]; then
            local new_password
            new_password=$(openssl rand -hex 16)
            
            log_step "DATABASE" "Resetting RDS password for instance $instance_id..."
            if aws rds modify-db-instance --db-instance-identifier "$instance_id" --master-user-password "$new_password" --region "$AWS_REGION" --profile "$AWS_PROFILE" --apply-immediately &>/dev/null; then
                log_step "DATABASE" "Password reset initiated, waiting for completion..."
                
                # Wait for password change to apply
                local max_attempts=$((PASSWORD_RESET_TIMEOUT * 60 / DATABASE_CHECK_INTERVAL))
                local attempt=1
                while [[ $attempt -le $max_attempts ]]; do
                    if PGPASSWORD="$new_password" psql -h "$endpoint" -U "$username" -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
                        log_success "Database connection successful with new password"
                        # Always update password file
                        echo "$new_password" > "$PASSWORD_FILE"
                        export DB_PASSWORD="$new_password"
                        return 0
                    fi
                    log_warning "Waiting for password change to apply (attempt $attempt/$max_attempts)..."
                    sleep $DATABASE_CHECK_INTERVAL
                    ((attempt++))
                done
                
                log_error "Password reset failed after $max_attempts attempts"
                return 1
            else
                log_error "Failed to reset RDS password"
                return 1
            fi
        else
            log_error "Cannot reset password - no instance ID provided"
            return 1
        fi
    else
        log_error "Database connection failed with unknown error: $error_output"
        return 1
    fi
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
    if ! test_database_connectivity "$rds_endpoint" "$DB_USERNAME" "$DB_PASSWORD" "$DB_NAME" "$RDS_INSTANCE_ID"; then
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

# Function to show setup progress and estimated completion
show_setup_progress() {
    local current_step=$1
    local total_steps=8
    local step_name=$2
    
    # Calculate progress
    local percentage=$((current_step * 100 / total_steps))
    local completed=$((50 * current_step / total_steps))
    local remaining=$((50 - completed))
    
    # Calculate estimated time remaining
    local elapsed=$(( $(date +%s) - SCRIPT_START_TIME ))
    local avg_time_per_step=$((elapsed / current_step))
    local remaining_steps=$((total_steps - current_step))
    local estimated_remaining=$((avg_time_per_step * remaining_steps))
    local estimated_minutes=$((estimated_remaining / 60))
    local estimated_seconds=$((estimated_remaining % 60))
    
    echo ""
    echo -e "${BLUE}[SETUP PROGRESS]${NC} Step $current_step/$total_steps: $step_name"
    printf "${BLUE}[PROGRESS]${NC} ["
    printf "%${completed}s" | tr ' ' '#'
    printf "%${remaining}s" | tr ' ' '-'
    printf "] %d%%" $percentage
    
    if [[ $estimated_remaining -gt 0 ]]; then
        printf " (Est. remaining: %dm %ds)" $estimated_minutes $estimated_seconds
    fi
    echo ""
    echo ""
}

# Function to show step-by-step guide
show_step_guide() {
    log_step "GUIDE" "Setup will proceed through these steps:"
    echo ""
    echo "  1. ✅ Prerequisites check (tools, credentials, permissions)"
    echo "  2. 🔄 EKS cluster creation (${EKS_CLUSTER_TIMEOUT} minutes)"
    echo "  3. 🔄 EKS nodes readiness (${EKS_NODES_TIMEOUT} minutes)"
    echo "  4. 🔄 RDS instance creation (${RDS_CREATION_TIMEOUT} minutes)"
    echo "  5. 🔄 RDS instance readiness (${RDS_READY_TIMEOUT} minutes)"
    echo "  6. 🔄 Monitoring stack installation (${HELM_RELEASE_TIMEOUT} minutes)"
    echo "  7. 🔄 Kyverno installation (${HELM_RELEASE_TIMEOUT} minutes)"
    echo "  8. ✅ Final verification and health checks"
    echo ""
    echo "  Total estimated time: $((EKS_CLUSTER_TIMEOUT + EKS_NODES_TIMEOUT + RDS_CREATION_TIMEOUT + RDS_READY_TIMEOUT + HELM_RELEASE_TIMEOUT * 2)) minutes"
    echo ""
}

# Function to get correct subnets for RDS
get_rds_subnets() {
    local vpc_id=$1
    local region=$2
    local profile=$3
    
    log_step "SUBNETS" "Getting subnets for RDS subnet group..."
    
    # Get all subnets in the VPC
    local subnets_json
    subnets_json=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --region "$region" \
        --profile "$profile" \
        --query 'Subnets[].{SubnetId:SubnetId,AvailabilityZone:AvailabilityZone,MapPublicIpOnLaunch:MapPublicIpOnLaunch}' \
        --output json)
    
    # Try robust approach first: get one subnet from each AZ
    local subnet_ids
    subnet_ids=$(echo "$subnets_json" | jq -r 'group_by(.AvailabilityZone) | .[0:2] | .[] | .[0].SubnetId' | tr '\n' ' ' 2>/dev/null)
    
    # Fallback to simple approach if robust approach fails
    if [[ -z "$subnet_ids" ]]; then
        log_warning "Robust subnet selection failed, using simple approach..."
        subnet_ids=$(echo "$subnets_json" | jq -r '.[0:2] | .[].SubnetId' | tr '\n' ' ' 2>/dev/null)
    fi
    
    if [[ -z "$subnet_ids" ]]; then
        log_error "Failed to get subnet IDs for RDS"
        return 1
    fi
    
    echo "$subnet_ids"
    return 0
}

# Function to check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 is not installed. Please install it first."
        log_step "INSTALL" "Install command: brew install $1"
        return 1
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    log_step "AWS" "Checking AWS SSO credentials..."
    if ! aws sts get-caller-identity --profile $AWS_PROFILE &> /dev/null; then
        log_error "AWS SSO credentials not configured or expired."
        log_step "AWS" "Please run: aws sso login --profile $AWS_PROFILE"
        return 1
    fi
    log_success "AWS SSO credentials verified"
}

# Function to check AWS permissions
check_aws_permissions() {
    log_step "AWS" "Checking AWS permissions..."
    
    # Check EKS permissions
    if ! aws eks list-clusters --region $AWS_REGION --profile $AWS_PROFILE &> /dev/null; then
        log_error "Insufficient AWS permissions for EKS operations"
        log_step "AWS" "Required permissions: eks:*"
        return 1
    fi
    
    # Check RDS permissions
    if ! aws rds describe-db-instances --region $AWS_REGION --profile $AWS_PROFILE &> /dev/null; then
        log_error "Insufficient AWS permissions for RDS operations"
        log_step "AWS" "Required permissions: rds:*"
        return 1
    fi
    
    # Check EC2 permissions (for VPC, subnets, security groups)
    if ! aws ec2 describe-vpcs --region $AWS_REGION --profile $AWS_PROFILE &> /dev/null; then
        log_error "Insufficient AWS permissions for EC2 operations"
        log_step "AWS" "Required permissions: ec2:*"
        return 1
    fi
    
    log_success "AWS permissions verified"
}

# Function to check resource health and provide recovery options
check_resource_health() {
    log_step "HEALTH" "Checking resource health..."
    
    local issues_found=false
    
    # Check EKS cluster health
    if eksctl get cluster --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE &>/dev/null; then
        log_step "HEALTH" "Checking EKS cluster health..."
        
        # Get kubeconfig
        if eksctl utils write-kubeconfig --cluster=$CLUSTER_NAME --region=$AWS_REGION --profile=$AWS_PROFILE &>/dev/null; then
            # Check node health
            local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
            local ready_count=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" 2>/dev/null)
            
            if [[ "$node_count" -gt 0 ]] && [[ "$node_count" -ne "$ready_count" ]]; then
                log_warning "EKS cluster has unhealthy nodes: $ready_count/$node_count ready"
                issues_found=true
            fi
            
            # Check for cordoned nodes
            local cordoned_nodes=$(kubectl get nodes --no-headers | grep "SchedulingDisabled" | awk '{print $1}' 2>/dev/null)
            if [[ -n "$cordoned_nodes" ]]; then
                log_warning "Found cordoned nodes: $cordoned_nodes"
                log_step "RECOVERY" "To uncordon nodes: kubectl uncordon <node-name>"
                issues_found=true
            fi
        else
            log_warning "Could not get kubeconfig for cluster health check"
        fi
    fi
    
    # Check RDS instance health
    if aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --profile $AWS_PROFILE &>/dev/null; then
        log_step "HEALTH" "Checking RDS instance health..."
        
        local rds_status=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --region $AWS_REGION --query 'DBInstances[0].DBInstanceStatus' --output text --profile $AWS_PROFILE 2>/dev/null)
        
        if [[ "$rds_status" != "available" ]]; then
            log_warning "RDS instance status: $rds_status (expected: available)"
            issues_found=true
        fi
    fi
    
    if [[ "$issues_found" == "true" ]]; then
        log_step "RECOVERY" "Resource health issues detected. Consider:"
        echo "  1. Wait for resources to stabilize"
        echo "  2. Run: ./phase1-cleanup.sh && ./phase1-setup.sh"
        echo "  3. Check AWS console for resource status"
        return 1
    else
        log_success "All resources appear healthy"
        return 0
    fi
}

# Function to check if resources already exist
check_existing_resources() {
    log_step "CHECK" "Checking for existing resources..."
    
    # Check for existing EKS cluster
    if eksctl get cluster --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE &>/dev/null; then
        log_error "EKS cluster '$CLUSTER_NAME' already exists!"
        log_step "CLEANUP" "Please delete it first or use a different timestamp"
        return 1
    fi
    
    # Check for existing RDS instance
    if aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --profile $AWS_PROFILE &>/dev/null; then
        log_error "RDS instance '$RDS_INSTANCE_ID' already exists!"
        log_step "CLEANUP" "Please delete it first or use a different timestamp"
        return 1
    fi
    
    log_success "No conflicting resources found"
}

# Function to wait for RDS instance to be available with better error handling
wait_for_rds() {
    log_step "RDS" "Waiting for RDS instance to be available (timeout: $RDS_READY_TIMEOUT minutes)..."
    local max_attempts=$((RDS_READY_TIMEOUT * 60 / RDS_STATUS_CHECK_INTERVAL))
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        show_progress $attempt $max_attempts
        
        # Get RDS status
        local status
        if status=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --region $AWS_REGION --query 'DBInstances[0].DBInstanceStatus' --output text --profile $AWS_PROFILE 2>/dev/null); then
            log_step "RDS" "Attempt $attempt/$max_attempts - Current status: $status"
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
        
        sleep $RDS_STATUS_CHECK_INTERVAL
        ((attempt++))
    done
    
    echo ""  # New line after progress bar
    log_error "RDS instance did not become available within $RDS_READY_TIMEOUT minutes"
    return 1
}

# Function to wait for EKS nodes to be ready with better error handling
wait_for_eks_nodes() {
    log_step "EKS" "Waiting for EKS nodes to be ready (timeout: $EKS_NODES_TIMEOUT minutes)..."
    local max_attempts=$((EKS_NODES_TIMEOUT * 60 / EKS_NODE_CHECK_INTERVAL))
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
        
        sleep $EKS_NODE_CHECK_INTERVAL
        ((attempt++))
    done
    
    echo ""  # New line after progress bar
    log_error "EKS nodes did not become ready within $EKS_NODES_TIMEOUT minutes"
    return 1
}

# Function to wait for Helm releases to be ready
wait_for_helm_release() {
    local namespace=$1
    local release_name=$2
    local timeout_minutes=${3:-10}
    local max_attempts=$((timeout_minutes * 60 / HELM_CHECK_INTERVAL))
    
    log_step "HELM" "Waiting for $release_name in namespace $namespace (timeout: ${timeout_minutes} minutes)..."
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        show_progress $attempt $max_attempts
        
        # Check if all pods are running
        if kubectl get pods -n $namespace --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l | grep -q "^0$"; then
            echo ""  # New line after progress bar
            log_success "$release_name is ready!"
            return 0
        fi
        
        sleep $HELM_CHECK_INTERVAL
        ((attempt++))
    done
    
    echo ""  # New line after progress bar
    log_error "$release_name did not become ready within ${timeout_minutes} minutes"
    return 1
}



# Function to provide detailed recovery instructions
provide_recovery_instructions() {
    local failure_point=$1
    local error_details=$2
    
    log_step "RECOVERY" "Detailed recovery instructions for failure at: $failure_point"
    echo ""
    echo "=== Recovery Steps ==="
    
    case "$failure_point" in
        "prerequisites")
            echo "1. Install missing tools:"
            echo "   - AWS CLI: brew install awscli"
            echo "   - eksctl: brew install eksctl"
            echo "   - kubectl: brew install kubectl"
            echo "   - Helm: brew install helm"
            echo "   - jq: brew install jq"
            echo "2. Configure AWS credentials: aws sso login --profile $AWS_PROFILE"
            echo "3. Retry: ./phase1-setup.sh"
            ;;
        "configuration")
            echo "1. Check config.sh file for missing or invalid variables"
            echo "2. Ensure all required files exist in the project directory"
            echo "3. Validate AWS region and profile settings"
            echo "4. Retry: ./phase1-setup.sh"
            ;;
        "eks_cluster")
            echo "1. Check AWS console for EKS cluster status"
            echo "2. If cluster exists but is stuck:"
            echo "   - Wait for cluster to stabilize (may take 10-15 minutes)"
            echo "   - Or delete manually: eksctl delete cluster --name $CLUSTER_NAME"
            echo "3. Check for cordoned nodes: kubectl get nodes"
            echo "4. Uncordon if needed: kubectl uncordon <node-name>"
            echo "5. Retry: ./phase1-setup.sh"
            ;;
        "rds_instance")
            echo "1. Check AWS console for RDS instance status"
            echo "2. If instance exists but is stuck:"
            echo "   - Wait for instance to stabilize (may take 10-15 minutes)"
            echo "   - Or delete manually: aws rds delete-db-instance --db-instance-identifier $RDS_INSTANCE_ID"
            echo "3. Check subnet group: aws rds describe-db-subnet-groups"
            echo "4. Retry: ./phase1-setup.sh"
            ;;
        "helm_install")
            echo "1. Check Helm releases: helm list -A"
            echo "2. Check pod status: kubectl get pods -A"
            echo "3. Check pod logs: kubectl logs <pod-name> -n <namespace>"
            echo "4. If pods are stuck:"
            echo "   - Delete and retry: helm uninstall <release> && helm install <release>"
            echo "   - Or restart: kubectl delete pod <pod-name> -n <namespace>"
            echo "5. Retry: ./phase1-setup.sh"
            ;;
        "database_connection")
            echo "1. Check RDS endpoint: aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID"
            echo "2. Test connectivity: psql -h <endpoint> -U $DB_USERNAME -d postgres"
            echo "3. Check security groups allow port 5432"
            echo "4. Verify password in: $PASSWORD_FILE"
            echo "5. Reset password if needed: aws rds modify-db-instance --db-instance-identifier $RDS_INSTANCE_ID --master-user-password <new-password>"
            echo "6. Retry: ./phase1-setup.sh"
            ;;
        *)
            echo "1. Check error log: cat $ERROR_LOG_FILE"
            echo "2. Run cleanup: ./phase1-cleanup.sh"
            echo "3. Check AWS console for resource status"
            echo "4. Retry: ./phase1-setup.sh"
            ;;
    esac
    
    echo ""
    echo "=== Debug Information ==="
    echo "Error details: $error_details"
    echo "Error log file: $ERROR_LOG_FILE"
    echo "Current timestamp: $TIMESTAMP"
    echo "AWS region: $AWS_REGION"
    echo "AWS profile: $AWS_PROFILE"
}

# Function to cleanup on failure
cleanup_on_failure() {
    log_error "Setup failed! Starting cleanup..."
    
    # Function to uncordon nodes if they exist
    uncordon_nodes() {
        local cluster_name=$1
        log_step "CLEANUP" "Checking for cordoned nodes..."
        
        # Get kubeconfig for the cluster
        if eksctl utils write-kubeconfig --cluster=$cluster_name --region=$AWS_REGION --profile=$AWS_PROFILE &>/dev/null; then
            # Check if nodes are cordoned and uncordon them
            local cordoned_nodes=$(kubectl get nodes --no-headers | grep "SchedulingDisabled" | awk '{print $1}' 2>/dev/null)
            if [[ -n "$cordoned_nodes" ]]; then
                log_step "CLEANUP" "Uncordoning nodes: $cordoned_nodes"
                echo "$cordoned_nodes" | xargs -I {} kubectl uncordon {} 2>/dev/null || true
            fi
        fi
    }
    
    # Delete RDS instance if it exists
    if aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --profile $AWS_PROFILE &>/dev/null; then
        log_step "CLEANUP" "Deleting RDS instance..."
        aws rds delete-db-instance --db-instance-identifier $RDS_INSTANCE_ID --skip-final-snapshot --profile $AWS_PROFILE
    fi
    
    # Handle EKS cluster cleanup with node uncordoning
    if eksctl get cluster --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE &>/dev/null; then
        log_step "CLEANUP" "Checking cluster status before deletion..."
        
        # Try to uncordon nodes first
        uncordon_nodes "$CLUSTER_NAME"
        
        # Use aws eks delete-cluster instead of eksctl for more control
        log_step "CLEANUP" "Deleting EKS cluster using AWS CLI..."
        if aws eks delete-cluster --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE &>/dev/null; then
            log_step "CLEANUP" "EKS cluster deletion initiated..."
        else
            log_warning "Failed to delete EKS cluster via AWS CLI, trying eksctl..."
            # Fallback to eksctl but with timeout
            timeout $((EKS_CLUSTER_TIMEOUT * 60)) eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE || {
                log_warning "eksctl delete cluster timed out or failed"
                log_step "CLEANUP" "Cluster may still exist. Please check AWS console."
            }
        fi
    fi
    
    # Delete subnet group if it exists
    if aws rds describe-db-subnet-groups --db-subnet-group-name reports-server-subnet-group-${TIMESTAMP} --profile $AWS_PROFILE &>/dev/null; then
        log_step "CLEANUP" "Deleting subnet group..."
        aws rds delete-db-subnet-group --db-subnet-group-name reports-server-subnet-group-${TIMESTAMP} --profile $AWS_PROFILE
    fi
    
    log_warning "Cleanup completed. Please check AWS console for any remaining resources."
    log_step "RECOVERY" "If nodes are still cordoned, run: kubectl uncordon <node-name>"
}

# Set up enhanced error handling
trap 'handle_error ${LINENO} "$BASH_COMMAND"' ERR

# Set up signal handling for graceful interruption
cleanup_on_interrupt() {
    echo ""
    log_warning "Setup interrupted by user (Ctrl+C)"
    log_step "INTERRUPT" "Attempting graceful cleanup..."
    
    # Try to uncordon nodes if cluster exists
    if eksctl get cluster --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE &>/dev/null; then
        log_step "INTERRUPT" "Checking for cordoned nodes..."
        if eksctl utils write-kubeconfig --cluster=$CLUSTER_NAME --region=$AWS_REGION --profile=$AWS_PROFILE &>/dev/null; then
            local cordoned_nodes=$(kubectl get nodes --no-headers | grep "SchedulingDisabled" | awk '{print $1}' 2>/dev/null)
            if [[ -n "$cordoned_nodes" ]]; then
                log_step "INTERRUPT" "Uncordoning nodes: $cordoned_nodes"
                echo "$cordoned_nodes" | xargs -I {} kubectl uncordon {} 2>/dev/null || true
                log_success "Nodes uncordoned successfully"
            else
                log_step "INTERRUPT" "No cordoned nodes found"
            fi
        fi
    fi
    
    log_warning "Setup interrupted. Cluster may still exist."
    log_step "RECOVERY" "To continue setup, run: ./phase1-setup.sh"
    log_step "RECOVERY" "To clean up manually, run: ./phase1-cleanup.sh"
    exit 1
}

trap cleanup_on_interrupt SIGINT

# Display configuration and setup guide
show_configuration
show_step_guide

# Check prerequisites
log_step "PREREQ" "Checking prerequisites..."
show_setup_progress 1 "Prerequisites check"

if ! check_command "aws"; then
    exit 1
fi
if ! check_command "eksctl"; then
    exit 1
fi
if ! check_command "kubectl"; then
    exit 1
fi
if ! check_command "helm"; then
    exit 1
fi
if ! check_command "jq"; then
    exit 1
fi
if ! check_aws_credentials; then
    exit 1
fi
if ! check_aws_permissions; then
    exit 1
fi
if ! validate_config; then
    exit 1
fi
if ! check_existing_resources; then
    exit 1
fi

# AWS region and profile are already set by config.sh
log_step "CONFIG" "Using AWS region: $AWS_REGION with profile: $AWS_PROFILE"

# Create EKS cluster configuration
log_step "EKS" "Creating EKS cluster configuration..."
cat > eks-cluster-config-phase1.yaml << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: $CLUSTER_NAME
  region: $AWS_REGION
nodeGroups:
  - name: ng-1
    instanceType: $EKS_INSTANCE_TYPE
    desiredCapacity: $EKS_NODE_COUNT
    minSize: $EKS_NODE_COUNT
    maxSize: $EKS_NODE_COUNT
    volumeSize: $EKS_VOLUME_SIZE
    iam:
      withAddonPolicies:
        autoScaler: true
        ebs: true
        cloudWatch: true
EOF

# Create EKS cluster with retry
show_setup_progress 2 "EKS cluster creation"
log_step "EKS" "Creating EKS cluster (this may take ${EKS_CLUSTER_TIMEOUT} minutes)..."
if ! retry_command $EKS_CLUSTER_RETRIES $EKS_CLUSTER_RETRY_DELAY eksctl create cluster -f eks-cluster-config-phase1.yaml --profile "$AWS_PROFILE"; then
    log_error "Failed to create EKS cluster after retries"
    exit 1
fi

# Wait for cluster to be ready
show_setup_progress 3 "EKS nodes readiness"
if ! wait_for_eks_nodes; then
    log_error "EKS cluster did not become ready"
    exit 1
fi

# Get VPC and subnet information
log_step "VPC" "Getting VPC and subnet information..."
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text --profile $AWS_PROFILE)

# Get correct subnets for RDS (from different AZs)
RDS_SUBNET_IDS=$(get_rds_subnets "$VPC_ID" "$AWS_REGION" "$AWS_PROFILE")
if [[ $? -ne 0 ]]; then
    log_error "Failed to get RDS subnet IDs"
    exit 1
fi

# Create RDS subnet group
log_step "RDS" "Creating RDS subnet group..."
aws rds create-db-subnet-group \
    --db-subnet-group-name reports-server-subnet-group-${TIMESTAMP} \
    --db-subnet-group-description "Subnet group for Reports Server RDS ${TIMESTAMP}" \
    --subnet-ids $RDS_SUBNET_IDS \
    --region $AWS_REGION \
    --profile $AWS_PROFILE 2>/dev/null || log_warning "Subnet group already exists"

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

# Database password is already set by config.sh and stored in PASSWORD_FILE
# Using persistent password management system

# Create RDS instance with retry
show_setup_progress 4 "RDS instance creation"
log_step "RDS" "Creating RDS PostgreSQL instance (this may take ${RDS_CREATION_TIMEOUT} minutes)..."
if ! retry_command $RDS_CREATION_RETRIES $RDS_CREATION_RETRY_DELAY aws rds create-db-instance \
  --db-instance-identifier "$RDS_INSTANCE_ID" \
  --db-instance-class "$RDS_INSTANCE_CLASS" \
  --engine postgres \
  --engine-version "$RDS_ENGINE_VERSION" \
  --master-username "$DB_USERNAME" \
  --master-user-password "$DB_PASSWORD" \
  --allocated-storage "$RDS_STORAGE_SIZE" \
  --storage-type gp2 \
  --db-subnet-group-name "reports-server-subnet-group-${TIMESTAMP}" \
  --vpc-security-group-ids "$SECURITY_GROUP_ID" \
  --backup-retention-period "$RDS_BACKUP_RETENTION" \
  --no-multi-az \
  --auto-minor-version-upgrade \
  --publicly-accessible \
  --storage-encrypted \
  --db-name "$DB_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE"; then
    log_error "Failed to create RDS instance after retries"
    exit 1
fi

# Wait for RDS to be available
show_setup_progress 5 "RDS instance readiness"
if ! wait_for_rds; then
    log_error "RDS instance did not become available"
    exit 1
fi

# Test and verify database connectivity will be done later after getting RDS endpoint
log_step "DATABASE" "RDS instance is ready, database connectivity will be tested during Kyverno prerequisites validation"

# Add Helm repositories (handle existing repositories gracefully)
log_step "HELM" "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || log_step "HELM" "prometheus-community repository already exists"
helm repo add nirmata-reports-server https://nirmata.github.io/reports-server 2>/dev/null || log_step "HELM" "nirmata-reports-server repository already exists"
helm repo add kyverno https://kyverno.github.io/charts 2>/dev/null || log_step "HELM" "kyverno repository already exists"
helm repo update

# Install monitoring stack with retry
show_setup_progress 6 "Monitoring stack installation"
log_step "MONITORING" "Installing monitoring stack..."
if ! retry_command $HELM_INSTALL_RETRIES $HELM_INSTALL_RETRY_DELAY helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.enabled=true \
  --set alertmanager.enabled=true; then
    log_error "Failed to install monitoring stack after retries"
    exit 1
fi

# Wait for monitoring stack to be ready (increased timeout)
if ! wait_for_helm_release "monitoring" "monitoring" $HELM_RELEASE_TIMEOUT; then
    log_error "Monitoring stack did not become ready"
    exit 1
fi

# Create namespace for Kyverno with integrated Reports Server
kubectl create namespace kyverno --dry-run=client -o yaml | kubectl apply -f -

# Note: No need for separate secrets or Reports Server installation
# Everything is handled by the integrated nirmata/kyverno chart

# Validate Kyverno prerequisites before installation
log_step "VALIDATION" "Validating Kyverno prerequisites..."
if ! validate_kyverno_prerequisites; then
    log_error "Kyverno prerequisites validation failed"
    exit 1
fi

# Get the correct RDS endpoint dynamically
RDS_ENDPOINT=$(get_rds_endpoint "$RDS_INSTANCE_ID" "$AWS_REGION" "$AWS_PROFILE")
if [[ $? -ne 0 ]]; then
    log_error "Failed to get RDS endpoint"
    exit 1
fi
log_success "RDS endpoint: $RDS_ENDPOINT"

# Install Kyverno with integrated Reports Server (BETTER APPROACH)
show_setup_progress 7 "Kyverno installation"
log_step "KYVERNO" "Installing Kyverno with integrated Reports Server..."
kubectl create namespace kyverno --dry-run=client -o yaml | kubectl apply -f -

if ! retry_command $HELM_INSTALL_RETRIES $HELM_INSTALL_RETRY_DELAY helm install kyverno nirmata/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set reports-server.install=true \
  --set reports-server.config.etcd.enabled=false \
  --set reports-server.config.db.name="$DB_NAME" \
  --set reports-server.config.db.user="$DB_USERNAME" \
  --set reports-server.config.db.password="$DB_PASSWORD" \
  --set reports-server.config.db.host="$RDS_ENDPOINT" \
  --set reports-server.config.db.port=5432 \
  --version=3.3.31; then
    log_error "Failed to install Kyverno with Reports Server after retries"
    exit 1
fi

# Wait for Kyverno with Reports Server to be ready (increased timeout)
if ! wait_for_helm_release "kyverno" "kyverno" $HELM_RELEASE_TIMEOUT; then
    log_error "Kyverno with Reports Server did not become ready"
    exit 1
fi

# Install baseline policies
log_step "POLICIES" "Installing baseline policies..."
# Note: External URL may not be available, so we'll use local policies instead

# Apply local baseline policies
log_step "POLICIES" "Applying local baseline policies..."
kubectl apply -f policies/baseline/require-labels.yaml
kubectl apply -f policies/baseline/disallow-privileged-containers.yaml

# Apply ServiceMonitors for monitoring
log_step "MONITORING" "Applying ServiceMonitors for monitoring..."
kubectl apply -f kyverno-servicemonitor.yaml
kubectl apply -f reports-server-servicemonitor.yaml

# Verify ServiceMonitors were applied
log_step "MONITORING" "Verifying ServiceMonitors..."
kubectl get servicemonitors -n monitoring | grep -E "(kyverno|reports-server)" || log_warning "ServiceMonitors not found"

# Wait for all pods to be ready with timeout
log_step "WAIT" "Waiting for all components to be ready..."
kubectl wait --for=condition=ready pods --all -n monitoring --timeout=${POD_READY_TIMEOUT}m
kubectl wait --for=condition=ready pods --all -n kyverno --timeout=${POD_READY_TIMEOUT}m

# Perform health checks
show_setup_progress 8 "Final verification and health checks"
log_step "HEALTH" "Performing health checks..."
verify_component_health "kyverno" "kyverno" $((POD_READY_TIMEOUT * 60))
verify_database_connection "$RDS_ENDPOINT" "$DB_USERNAME" "$DB_PASSWORD" "$DB_NAME"
verify_policy_enforcement

# Verify Kyverno with Reports Server configuration
log_step "VERIFY" "Verifying Kyverno with Reports Server configuration..."
sleep $VERIFICATION_SLEEP

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
# WARNING: This file contains sensitive information. Delete after testing.
CLUSTER_NAME=$CLUSTER_NAME
AWS_REGION=$AWS_REGION
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
echo "  Password: ${DB_PASSWORD:0:4}**** (stored in $PASSWORD_FILE)"
echo ""
echo "Next Steps:"
echo "  1. Verify all resources are running correctly"
echo "  2. Run: ./phase1-test-cases.sh (optional - for testing)"
echo "  3. Run: ./phase1-monitor.sh (optional - for monitoring)"
echo "  4. When done: ./phase1-cleanup.sh"
echo ""
log_success "Resource provisioning completed successfully! 🎉"

# Calculate and display final statistics
local runtime=$(( $(date +%s) - SCRIPT_START_TIME ))
local runtime_minutes=$((runtime / 60))
local runtime_seconds=$((runtime % 60))

log_success "Setup completed successfully in ${runtime_minutes}m ${runtime_seconds}s!"

# Display comprehensive summary
echo ""
echo "=============================================================================="
echo "                          SETUP COMPLETED SUCCESSFULLY! 🎉"
echo "=============================================================================="
echo ""
echo "=== Infrastructure Summary ==="
echo "  ✅ EKS Cluster: $CLUSTER_NAME"
echo "  ✅ RDS Database: $RDS_INSTANCE_ID"
echo "  ✅ Monitoring Stack: Prometheus + Grafana"
echo "  ✅ Kyverno: With integrated Reports Server"
echo "  ✅ Security Policies: Baseline policies applied"
echo ""
echo "=== Access Information ==="
echo "  📊 Grafana Dashboard:"
echo "    kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80"
echo "    Password: $(kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
echo ""
echo "  🗄️  RDS Database:"
echo "    Endpoint: $RDS_ENDPOINT"
echo "    Database: $DB_NAME"
echo "    Username: $DB_USERNAME"
echo "    Password: ${DB_PASSWORD:0:4}**** (stored in $PASSWORD_FILE)"
echo ""
echo "=== Next Steps ==="
echo "  1. 🔍 Verify all resources are running correctly"
echo "  2. 🧪 Run: ./phase1-test-cases.sh (optional - for testing)"
echo "  3. 📈 Run: ./phase1-monitor.sh (optional - for monitoring)"
echo "  4. 🧹 When done: ./phase1-cleanup.sh"
echo ""
echo "=== Configuration Files ==="
echo "  📄 Cluster config: eks-cluster-config-phase1.yaml (temporary)"
echo "  📄 Connection details: postgresql-testing-config-${TIMESTAMP}.env"
echo "  📄 Password file: $PASSWORD_FILE"
echo ""
echo "=== Troubleshooting ==="
echo "  🔧 Check cluster status: kubectl get nodes"
echo "  🔧 Check pod status: kubectl get pods -A"
echo "  🔧 Check RDS status: aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID"
echo "  🔧 View logs: kubectl logs <pod-name> -n <namespace>"
echo ""
echo "=============================================================================="

# Final health check
log_step "FINAL" "Performing final health check..."
if check_resource_health; then
    log_success "All resources are healthy!"
else
    log_warning "Some resources may need attention. Check the warnings above."
fi

# Remove error trap since we succeeded
trap - ERR

# Clean up error log if everything succeeded
if [[ -f "$ERROR_LOG_FILE" ]]; then
    rm "$ERROR_LOG_FILE"
fi
