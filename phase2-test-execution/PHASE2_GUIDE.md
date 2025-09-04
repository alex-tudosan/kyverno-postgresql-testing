# Phase 2: Complete Guide - Scaling Testing and Performance Validation

## Overview

Phase 2 focuses on comprehensive scaling testing and performance validation of the Kyverno + PostgreSQL Reports Server deployment. This phase executes a systematic scaling test plan that validates policy enforcement under scale, tests system performance during controlled scaling operations, and verifies the integration between Kyverno and the PostgreSQL database under realistic scaling conditions.

## Prerequisites

Before running Phase 2, ensure Phase 1 has been completed successfully:

- **EKS Cluster**: Must be running and accessible
- **Kyverno**: Must be deployed and operational
- **Reports Server**: Must be connected to PostgreSQL RDS
- **Monitoring Stack**: Must be running (Prometheus, Grafana)
- **AWS Access**: Valid AWS SSO session with appropriate permissions

## Configuration

The scaling test execution uses the following configuration parameters:

```bash
# Load Testing Configuration
TOTAL_NAMESPACES=200
TOTAL_BATCHES=20
NAMESPACES_PER_BATCH=10
MAX_PODS_SIMULTANEOUS=10
```

## Scaling Test Execution Process Breakdown

### Step 0: AWS SSO Authentication

#### Authentication Check
- **What**: Verifies AWS SSO session is active and valid
- **How**: 
  - Checks current AWS identity using `aws sts get-caller-identity`
  - Attempts automatic login if session is expired
  - Uses profile `devtest-sso` for authentication
- **Why**: Ensures proper AWS permissions for cluster access and resource management

#### Session Management
- **What**: Handles AWS SSO session lifecycle
- **How**: 
  - Detects expired sessions automatically
  - Prompts for manual login if automatic login fails
  - Validates session before proceeding
- **Why**: Prevents authentication failures during resource operations

### Step 1: Infrastructure Validation

#### EKS Cluster Status Check
- **What**: Verifies EKS cluster is active and accessible
- **How**: 
  - Queries cluster status using AWS CLI
  - Checks cluster name `report-server-test` in `us-west-1` region
  - Validates cluster is in `ACTIVE` state
- **Why**: Ensures cluster is ready for test operations

#### Kyverno Health Verification
- **What**: Confirms Kyverno components are running properly
- **How**: 
  - Checks `kyverno` namespace exists
  - Verifies at least 2 pods are running (Kyverno + Reports Server)
  - Monitors pod status and health
- **Why**: Kyverno must be operational for policy enforcement testing

#### Monitoring Stack Validation
- **What**: Ensures monitoring infrastructure is functional
- **How**: 
  - Verifies `monitoring` namespace exists
  - Checks at least 3 monitoring pods are running
  - Validates Prometheus, Grafana, and Alertmanager status
- **Why**: Monitoring is essential for performance metrics and observability

#### RDS Connectivity Test
- **What**: Verifies database connection from Reports Server
- **How**: 
  - Extracts RDS endpoint from Reports Server pod environment
  - Validates database host configuration
  - Confirms connectivity parameters are set correctly
- **Why**: Database connectivity is critical for policy report storage

### Step 2: Policy Deployment

#### Policy Application
- **What**: Deploys three core Kyverno policies for testing
- **How**: 
  - Applies policies using `kubectl apply -f`
  - Deploys policies in sequence with verification
  - Validates policy activation status
- **Why**: Establishes policy framework for testing enforcement

#### Deployed Policies

**1. Namespace Label Policy (`require-ns-label-owner`)**
- **Purpose**: Ensures all namespaces have an `owner` label
- **Enforcement**: `enforce` mode - blocks non-compliant resources
- **Scope**: Applies to all namespace creation operations
- **Why**: Establishes resource ownership and accountability

**2. Privileged Container Policy (`disallow-privileged`)**
- **Purpose**: Prevents privileged containers from running
- **Enforcement**: `enforce` mode - blocks privileged containers
- **Scope**: Applies to all pod creation operations
- **Why**: Enhances security by preventing elevated privileges

**3. Resource Labels Policy (`require-labels`)**
- **Purpose**: Ensures pods have required `app` and `version` labels
- **Enforcement**: `enforce` mode - blocks non-compliant pods
- **Scope**: Applies to all pod creation operations
- **Why**: Enables proper resource management and monitoring

#### Policy Verification
- **What**: Confirms all policies are active and enforced
- **How**: 
  - Counts active cluster policies
  - Verifies expected policy count (3 policies)
  - Displays policy status and details
- **Why**: Ensures policy framework is properly established

### Step 3: Infrastructure Setup (Namespaces)

#### Test Namespace Creation
- **What**: Creates 200 test namespaces for scaling testing
- **How**: 
  - Generates namespaces with sequential numbering (`load-test-001` to `load-test-200`)
  - Applies required labels (`owner: loadtest`, `purpose: load-testing`)
  - Uses kubectl apply for each namespace
- **Why**: Provides isolated environments for testing policy enforcement

#### Labeling Strategy
- **What**: Ensures all namespaces comply with policy requirements
- **How**: 
  - Adds `owner: loadtest` label (required by namespace policy)
  - Adds `purpose: scaling-testing` for identification
  - Adds `created-by: test-plan` for tracking
  - Adds `sequence` label for ordering
- **Why**: Prevents policy violations during namespace creation

### Step 4: Object Deployment

#### ServiceAccount Creation
- **What**: Creates 200 ServiceAccounts across test namespaces
- **How**: 
  - Creates `demo-sa` ServiceAccount in each namespace
  - Applies consistent labeling (`owner: loadtest`, `purpose: scaling-testing`)
  - Processes in batches of 10 with 3-second intervals
- **Why**: Provides identity for pod operations and policy testing

#### ConfigMap Deployment
- **What**: Creates 400 ConfigMaps (2 per namespace) for scaling testing
- **How**: 
  - Creates `cm-01` and `cm-02` in each namespace
  - Applies consistent labeling and metadata
  - Processes in batches of 10 with 5-second intervals
- **Why**: Tests policy enforcement on different resource types during scaling operations

#### Deployment Creation
- **What**: Creates 200 deployments with zero replicas initially
- **How**: 
  - Creates `test-deployment` in each namespace
  - Uses nginx:alpine image with security best practices
  - Sets `replicas: 0` to prevent resource consumption
  - Applies comprehensive labeling and security context
- **Why**: Establishes deployment infrastructure for scaling testing

#### Resource Verification
- **What**: Confirms all resources were created successfully
- **How**: 
  - Counts namespaces, ServiceAccounts, ConfigMaps, and deployments
  - Compares actual counts with expected totals
  - Validates resource distribution across namespaces
- **Why**: Ensures infrastructure is ready for scaling testing

### Step 5: Scaling Testing Execution

#### Controlled Scaling Testing Strategy
- **What**: Executes systematic scaling testing with controlled resource consumption
- **How**: 
  - Processes 20 batches of 10 namespaces each
  - Each batch: Scale up → wait 30s → scale down → wait 10s
  - Maximum 10 pods running simultaneously
  - Uses background processing for scale operations
- **Why**: Tests system performance without overwhelming resources

#### Batch Processing Logic
- **What**: Manages resource scaling in controlled batches
- **How**: 
  - **Scale Up**: Sets deployment replicas to 1 for batch
  - **Wait Period**: 30 seconds for admission webhook processing
  - **Scale Down**: Sets deployment replicas to 0 for batch
  - **Batch Interval**: 10 seconds between batches
- **Why**: Provides controlled scaling testing with monitoring periods

#### Admission Webhook Testing
- **What**: Tests Kyverno admission webhook performance during scaling operations
- **How**: 
  - Triggers 400 admission events (200 scale up + 200 scale down)
  - Monitors webhook response times and success rates
  - Tracks policy enforcement across all scaling operations
- **Why**: Validates policy engine performance during scaling operations

### Step 6: System Performance Check

#### Kyverno Stability Analysis
- **What**: Evaluates Kyverno system stability during scaling testing
- **How**: 
  - Counts pod restarts and errors
  - Monitors resource consumption and performance
  - Validates policy enforcement consistency
- **Why**: Ensures system reliability under stress

#### Database Performance Verification
- **What**: Confirms PostgreSQL storage performance for policy reports
- **How**: 
  - Counts total policy reports stored
  - Analyzes report generation rates
  - Validates data persistence and retrieval
- **Why**: Verifies Reports Server integration with PostgreSQL

#### Resource Efficiency Assessment
- **What**: Evaluates resource consumption and management during scaling operations
- **How**: 
  - Monitors pod lifecycle and cleanup
  - Tracks deployment scaling operations
  - Analyzes resource utilization patterns during scaling
- **Why**: Ensures efficient resource management during scaling testing

#### Performance Metrics Calculation
- **What**: Provides comprehensive performance statistics
- **How**: 
  - Calculates test duration and throughput
  - Measures admission webhook event processing
  - Analyzes report generation rates
  - Tracks resource management efficiency
- **Why**: Provides quantitative performance data for analysis

## Database Verification

### PostgreSQL Connection Details
The script provides database verification commands to validate policy report storage:

```bash
# Connect to database and list tables
PGPASSWORD="<password>" psql -h "<rds-endpoint>" -U reportsuser -d reportsdb -c "\dt"

# Count policy reports in various tables
PGPASSWORD="<password>" psql -h "<rds-endpoint>" -U reportsuser -d reportsdb -c "SELECT COUNT(*) FROM policyreports;"
PGPASSWORD="<password>" psql -h "<rds-endpoint>" -U reportsuser -d reportsdb -c "SELECT COUNT(*) FROM clusterephemeralreports;"
PGPASSWORD="<password>" psql -h "<rds-endpoint>" -U reportsuser -d reportsdb -c "SELECT COUNT(*) FROM clusterpolicyreports;"
PGPASSWORD="<password>" psql -h "<rds-endpoint>" -U reportsuser -d reportsdb -c "SELECT COUNT(*) FROM ephemeralreports;"
```

### Expected Results
- **Total Objects Processed**: 800 (200 namespaces + 200 SAs + 400 ConfigMaps)
- **Admission Webhook Events**: 400 (200 scale up + 200 scale down)
- **Policy Reports Generated**: Varies based on policy violations and background scanning
- **Database Storage**: All reports should be persisted in PostgreSQL tables

## Key Functions and Their Purposes

### Resource Management
- **Batch Processing**: Prevents resource exhaustion during scaling testing
- **Controlled Scaling**: Manages pod lifecycle for predictable scaling testing
- **Resource Cleanup**: Ensures efficient resource utilization during scaling operations

### Performance Monitoring
- **Real-time Metrics**: Tracks system performance during scaling testing
- **Admission Webhook Analysis**: Monitors policy enforcement performance during scaling
- **Database Performance**: Validates storage and retrieval efficiency during scaling operations

### Error Handling and Validation
- **Prerequisite Checks**: Ensures all components are ready
- **Resource Verification**: Confirms successful resource creation
- **Performance Validation**: Verifies system stability during scaling operations

## Important Considerations

### Resource Management
- **Controlled Scaling Testing**: Maximum 10 pods running simultaneously
- **Batch Processing**: 20 batches with controlled intervals
- **Resource Cleanup**: Automatic scaling down after scaling testing

### Performance Expectations
- **Admission Webhooks**: Should handle 400 scaling events efficiently
- **Policy Enforcement**: Consistent enforcement across all scaling operations
- **Database Storage**: Reliable persistence of all policy reports during scaling

### Monitoring and Observability
- **Grafana Dashboards**: Real-time scaling performance metrics
- **Policy Reports**: Comprehensive policy violation tracking during scaling
- **System Health**: Continuous monitoring of all components during scaling operations

## Troubleshooting

### Common Issues
1. **AWS Authentication**: Ensure SSO session is active
2. **Resource Limits**: Check cluster capacity and quotas
3. **Policy Violations**: Verify resource labeling compliance
4. **Database Connectivity**: Confirm RDS endpoint accessibility

### Debug Information
- Script provides detailed logging for each step
- Progress indicators show operation status
- Performance metrics display system behavior
- Database verification commands for manual validation

## Next Steps

After successful Phase 2 completion:

1. **Review Performance Metrics**: Analyze Grafana dashboards for insights
2. **Validate Database Storage**: Execute database verification commands
3. **Analyze Policy Reports**: Review policy enforcement results
4. **Phase 3**: Clean up Kubernetes resources when testing is complete
5. **Performance Analysis**: Review admission webhook performance data

## File Structure

```
phase2-test-execution/
├── phase2-test-plan-execution.sh    # Main test execution script
├── PHASE2_GUIDE.md                  # This guide
├── require-labels.yaml              # Resource labeling policy
├── policy-no-privileged.yaml        # Privileged container policy
└── policy-namespace-label.yaml      # Namespace labeling policy
```

## Scaling Test Results Summary

Phase 2 provides comprehensive validation of:

- **Policy Enforcement**: All three policies active and enforced during scaling
- **System Performance**: Kyverno stability during scaling operations
- **Database Integration**: PostgreSQL storage of policy reports during scaling
- **Resource Management**: Efficient handling of 800+ objects during scaling
- **Admission Webhooks**: Processing of 400+ scaling events
- **Scaling Testing**: Controlled scaling testing with monitoring

This phase establishes confidence in the production readiness of the Kyverno + PostgreSQL Reports Server deployment by validating all components under realistic scaling conditions.
