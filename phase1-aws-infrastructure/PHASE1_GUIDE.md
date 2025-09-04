# Phase 1: Complete Guide - Kyverno n4k with PostgreSQL Reports Server

## Overview

This guide provides a comprehensive walkthrough of Phase 1 setup for deploying Kyverno with a PostgreSQL-based Reports Server on AWS EKS. The setup script (`phase1-setup.sh`) automates the entire infrastructure provisioning and application deployment process.

## Prerequisites

Before running the setup script, ensure you have the following tools installed:

- **AWS CLI** - For AWS resource management
- **kubectl** - For Kubernetes cluster interaction
- **Helm** - For package management
- **Terraform** - For infrastructure as code
- **PostgreSQL client** - For database connectivity testing
- **jq** - For JSON processing

## Configuration

The setup uses `config.sh` to define all configuration variables:

```bash
# AWS Configuration
export AWS_REGION="us-west-1"
export AWS_PROFILE="default"

# Resource Naming
export CLUSTER_NAME="report-server-test"
export RDS_INSTANCE_ID="reports-server-db"

# Database Configuration
export DB_NAME="reportsdb"
export DB_USERNAME="reportsuser"
```

## Setup Process Breakdown

### 1. Initialization and Validation

#### Configuration Loading
- **What**: Loads environment variables from `config.sh`
- **How**: Sources the configuration file and validates required variables
- **Why**: Ensures all necessary configuration is available before proceeding

#### Prerequisites Check
- **What**: Verifies all required tools are installed
- **How**: Uses `check_command()` function to test each tool
- **Why**: Prevents setup failures due to missing dependencies

#### AWS Credentials Validation
- **What**: Confirms AWS SSO credentials are valid and not expired
- **How**: Calls `aws sts get-caller-identity` with the specified profile
- **Why**: Ensures proper AWS authentication for resource creation

### 2. EKS Cluster Setup

#### Cluster Existence Check
- **What**: Determines if the EKS cluster already exists
- **How**: Uses `aws eks describe-cluster` to check cluster status
- **Why**: Avoids duplicate cluster creation and handles existing infrastructure

#### Terraform Cluster Creation (if needed)
- **What**: Creates EKS cluster using Terraform when none exists
- **How**: 
  - Updates cluster name in `variables.tf` from default "report-server-test" to the value from `config.sh`
  - Runs `terraform init`, `plan`, and `apply`
  - Restores original configuration files after deployment
- **Why**: Provides infrastructure as code approach for reproducible cluster creation while allowing dynamic cluster naming

#### Cluster Access Configuration
- **What**: Updates kubeconfig to access the EKS cluster
- **How**: Uses `aws eks update-kubeconfig` to configure kubectl
- **Why**: Enables local kubectl commands to interact with the cluster

#### Node Readiness Wait
- **What**: Waits for EKS worker nodes to become ready
- **How**: Monitors node status with progress bar and timeout
- **Why**: Ensures cluster is fully operational before proceeding

### 3. VPC and Networking Setup

#### VPC Information Retrieval
- **What**: Gets VPC ID and subnet information from the EKS cluster
- **How**: Queries cluster configuration for VPC details
- **Why**: Required for RDS placement and security group configuration

#### Subnet Group Creation
- **What**: Creates RDS subnet group for database placement
- **How**: 
  - Identifies subnets in different availability zones
  - Creates subnet group with descriptive name
  - Verifies successful creation
- **Why**: RDS requires subnet group for multi-AZ deployment

#### Security Group Configuration
- **What**: Configures security group to allow PostgreSQL access
- **How**: Adds ingress rule for TCP port 5432 from any source
- **Why**: Enables database connectivity from EKS cluster

### 4. RDS Database Setup

#### Instance Creation
- **What**: Creates PostgreSQL RDS instance for Reports Server
- **How**: 
  - Generates secure random password
  - Creates instance with specified configuration
  - Uses retry mechanism for reliability
- **Why**: Provides persistent, managed database for policy reports

#### Database Verification
- **What**: Tests database connectivity and creates required database
- **How**: 
  - Tests connection with generated credentials
  - Creates database if it doesn't exist
  - Handles password reset if needed
- **Why**: Ensures database is accessible and properly configured

#### Instance Status Monitoring
- **What**: Waits for RDS instance to become available
- **How**: Monitors instance status with progress bar and timeout
- **Why**: RDS creation takes 10-15 minutes; waiting prevents premature operations

### 5. Monitoring Stack Installation

#### Helm Repository Setup
- **What**: Adds required Helm repositories for monitoring components
- **How**: Uses `helm repo add` for prometheus-community and other charts
- **Why**: Provides access to monitoring and observability tools

#### Kube-Prometheus-Stack Deployment
- **What**: Installs comprehensive monitoring solution
- **How**: 
  - Deploys Prometheus, Grafana, and Alertmanager
  - Creates monitoring namespace
  - Waits for components to be ready
- **Why**: Provides metrics collection, visualization, and alerting

#### Component Health Verification
- **What**: Ensures monitoring stack is fully operational
- **How**: Waits for pods to reach Running state with timeout
- **Why**: Monitoring must be ready before deploying applications

### 6. Kyverno Installation

#### Namespace Creation
- **What**: Creates dedicated namespace for Kyverno components
- **How**: Uses kubectl to create namespace with proper labels
- **Why**: Provides isolation and organization for Kyverno resources

#### Core Kyverno Deployment
- **What**: Installs Kyverno policy engine
- **How**: 
  - Uses Helm to deploy Kyverno chart
  - Specifies version 3.5.1 for stability
  - Waits for deployment to be ready
- **Why**: Core policy enforcement engine for Kubernetes

#### Reports Server Integration
- **What**: Deploys Reports Server connected to PostgreSQL
- **How**: 
  - Installs Reports Server with database configuration
  - Disables embedded etcd (using PostgreSQL instead)
  - Configures database connection parameters
- **Why**: Stores and retrieves policy reports with persistent storage

### 7. Policy Deployment

#### Baseline Policies
- **What**: Applies fundamental security and compliance policies
- **How**: 
  - Deploys require-labels policy
  - Applies disallow-privileged-containers policy
  - Uses kubectl apply for policy deployment
- **Why**: Establishes basic security posture and compliance requirements

#### Policy Verification
- **What**: Confirms policies are active and enforced
- **How**: Checks for active cluster policies and their status
- **Why**: Ensures policy engine is working correctly

### 8. Health Checks and Validation

#### Component Health Verification
- **What**: Verifies all deployed components are healthy
- **How**: 
  - Checks pod readiness conditions
  - Monitors component status with timeouts
  - Performs database connectivity tests
- **Why**: Confirms successful deployment and operation

#### Final Status Display
- **What**: Shows comprehensive status of all resources
- **How**: 
  - Displays cluster, pod, and RDS status
  - Shows access information for tools
  - Provides next steps and cleanup instructions
- **Why**: Gives users complete visibility into deployment status

## Key Functions and Their Purposes

### Dynamic Terraform Configuration
- **Cluster Name Synchronization**: The script dynamically updates the Terraform `variables.tf` file to match the cluster name from `config.sh`
- **Why This is Necessary**: 
  - `variables.tf` has a hardcoded default: `default = "report-server-test"`
  - `config.sh` allows users to customize: `export CLUSTER_NAME="report-server-test"`
  - The script ensures both are synchronized before Terraform execution
- **How It Works**:
  ```bash
  # Before: variables.tf contains default = "report-server-test"
  # Script runs: sed -i.bak "s/default = \"[^\"]*\"/default = \"$cluster_name\"/" variables.tf
  # After: variables.tf contains default = "report-server_test" (or custom name)
  # After deployment: Original variables.tf is restored from .bak file
  ```
- **Benefits**: 
  - Allows users to customize cluster names without editing Terraform files
  - Maintains Terraform files as templates
  - Prevents configuration drift between script and Terraform

### Error Handling and Logging
- **Enhanced Logging**: Color-coded output with timestamps for better visibility
- **Error Trapping**: Automatic cleanup on failure to prevent resource leaks
- **Retry Mechanisms**: Exponential backoff for transient failures

### Resource Management
- **Existence Checks**: Prevents duplicate resource creation
- **Graceful Degradation**: Handles existing resources appropriately
- **Cleanup Functions**: Automatic resource cleanup on failure

### Progress Monitoring
- **Progress Bars**: Visual feedback for long-running operations
- **Timeout Handling**: Prevents indefinite waiting
- **Status Verification**: Confirms successful completion

## Important Considerations

### Security
- **Database Passwords**: Generated randomly and securely
- **Network Access**: Limited to necessary ports and sources
- **IAM Roles**: Uses existing AWS profile for authentication

### Reliability
- **Retry Mechanisms**: Handles transient AWS API failures
- **Health Checks**: Verifies component readiness before proceeding
- **Timeout Configuration**: Prevents hanging on failed operations

### Resource Management
- **Tagging**: Resources are properly tagged for cost tracking
- **Cleanup**: Automatic cleanup on failure prevents cost accumulation
- **Monitoring**: Comprehensive monitoring stack for operational visibility

## Troubleshooting

### Common Issues
1. **AWS Credentials**: Ensure SSO login is current
2. **Resource Limits**: Check AWS service quotas
3. **Network Issues**: Verify VPC and subnet configuration
4. **Timeout Errors**: Increase timeout values for slow operations

### Debug Information
- Script provides detailed logging for each step
- Progress bars show operation status
- Error messages include specific failure details
- Configuration validation prevents common mistakes

## Next Steps

After successful Phase 1 completion:

1. **Verify Deployment**: Check all components are running correctly
2. **Test Policies**: Validate policy enforcement is working
3. **Monitor Performance**: Use Grafana dashboards for insights
4. **Phase 2**: Execute test cases and policy validation
5. **Cleanup**: Use cleanup scripts when testing is complete

## File Structure

```
phase1-aws-infrastructure/
├── config.sh                 # Configuration variables
├── phase1-setup.sh          # Main setup script
├── PHASE1_GUIDE.md          # This guide
└── policies/                # Policy definitions
    ├── baseline/
    │   ├── require-labels.yaml
    │   └── disallow-privileged-containers.yaml
    └── ...
```

This setup provides a robust, production-ready Kyverno deployment with PostgreSQL-based reporting, comprehensive monitoring, and automated infrastructure management.
