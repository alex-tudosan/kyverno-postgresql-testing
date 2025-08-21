#!/bin/bash

# Phase 1 Configuration File
# This file contains all configuration variables for the Phase 1 setup

# AWS Configuration
export AWS_REGION="us-west-1"
export AWS_PROFILE="devtest-sso"

# Resource Naming
export TIMESTAMP=$(date +%Y%m%d-%H%M%S)
export CLUSTER_NAME="reports-server-test-${TIMESTAMP}"
export RDS_INSTANCE_ID="reports-server-db-${TIMESTAMP}"

# Database Configuration
export DB_NAME="reportsdb"
export DB_USERNAME="reportsuser"
export DB_PASSWORD=$(openssl rand -hex 32)

# EKS Configuration
export EKS_NODE_TYPE="t3a.medium"
export EKS_NODE_COUNT=2
export EKS_VOLUME_SIZE=20

# RDS Configuration
export RDS_INSTANCE_CLASS="db.t3.micro"
export RDS_ENGINE_VERSION="14.12"
export RDS_STORAGE_SIZE=20
export RDS_STORAGE_TYPE="gp2"

# Kyverno Configuration
export KYVERNO_VERSION="3.3.31"
export KYVERNO_NAMESPACE="kyverno"

# Monitoring Configuration
export MONITORING_NAMESPACE="monitoring"

# Timeouts (in minutes)
export EKS_CREATION_TIMEOUT=20
export RDS_CREATION_TIMEOUT=15
export HELM_TIMEOUT=15
export KYVERNO_TIMEOUT=20

# Validation function
validate_config() {
    local required_vars=(
        "AWS_REGION"
        "AWS_PROFILE"
        "CLUSTER_NAME"
        "RDS_INSTANCE_ID"
        "DB_NAME"
        "DB_USERNAME"
        "DB_PASSWORD"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            echo "ERROR: $var is required but not set"
            return 1
        fi
    done
    
    echo "Configuration validation passed"
    return 0
}

# Display configuration
show_config() {
    echo "=== Phase 1 Configuration ==="
    echo "AWS Region: $AWS_REGION"
    echo "AWS Profile: $AWS_PROFILE"
    echo "Cluster Name: $CLUSTER_NAME"
    echo "RDS Instance: $RDS_INSTANCE_ID"
    echo "Database: $DB_NAME"
    echo "Database User: $DB_USERNAME"
    echo "EKS Node Type: $EKS_NODE_TYPE"
    echo "EKS Node Count: $EKS_NODE_COUNT"
    echo "Kyverno Version: $KYVERNO_VERSION"
    echo "Timestamp: $TIMESTAMP"
    echo "================================"
}
