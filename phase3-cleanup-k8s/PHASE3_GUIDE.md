# Phase 3: Complete Guide - Kubernetes Test Resource Cleanup

## Overview

Phase 3 focuses on systematic cleanup of all test resources created during Phase 2 while preserving the core infrastructure. This phase ensures that the EKS cluster, RDS database, Kyverno, and monitoring stack remain intact for future testing or production use, while removing all temporary test resources.

## Prerequisites

Before running Phase 3, ensure:

- **Phase 2 Completed**: All scaling tests have been executed
- **Kubernetes Access**: Valid kubectl access to the EKS cluster
- **AWS Access**: Valid AWS credentials for cluster status verification
- **Test Resources Exist**: Phase 2 must have created test resources

## Configuration

The cleanup process uses the following configuration:

```bash
# Cleanup Configuration
TOTAL_NAMESPACES=200
TIMEOUT_NAMESPACE_CLEANUP=300  # 5 minutes
```

## Cleanup Process Breakdown

### Step 1: Prerequisites and Resource Assessment

#### Command Availability Check
- **What**: Verifies required tools are available
- **How**: 
  - Checks `kubectl` command availability
  - Checks `aws` CLI command availability
  - Validates PATH and installation
- **Why**: Prevents cleanup failures due to missing tools

#### Test Resource Inventory
- **What**: Scans cluster for existing test resources
- **How**: 
  - Counts test namespaces (`load-test-001` to `load-test-200`)
  - Counts ServiceAccounts (`demo-sa`)
  - Counts ConfigMaps (`cm-01`, `cm-02`)
  - Counts deployments (`test-deployment`)
  - Counts test pods
- **Why**: Provides visibility into what needs cleanup and validates cleanup completion

#### Early Exit Logic
- **What**: Exits if no test resources exist
- **How**: 
  - Checks if all resource counts are zero
  - Provides success message if nothing to clean
  - Exits gracefully without unnecessary operations
- **Why**: Avoids unnecessary cleanup operations when not needed

### Step 2: User Confirmation and Safety

#### Resource Deletion Warning
- **What**: Informs user about what will be deleted
- **How**: 
  - Lists all resources that will be removed
  - Shows exact counts (200 namespaces, 200 SAs, 400 ConfigMaps, 200 deployments)
  - Emphasizes infrastructure preservation
- **Why**: Ensures user understands the scope and impact of cleanup

#### Infrastructure Preservation Assurance
- **What**: Clarifies what will NOT be deleted
- **How**: 
  - Explicitly states EKS cluster will be preserved
  - Confirms RDS database will remain intact
  - Assures Kyverno and monitoring stack will continue running
- **Why**: Prevents user concerns about losing production infrastructure

#### Interactive Confirmation
- **What**: Requires explicit user approval before proceeding
- **How**: 
  - Prompts with "Do you want to continue with cleanup? (y/N)"
  - Defaults to "No" for safety
  - Exits gracefully if user cancels
- **Why**: Prevents accidental cleanup of test resources

### Step 3: Systematic Resource Deletion

#### Deletion Order Strategy
- **What**: Deletes resources in reverse order of creation
- **How**: 
  1. **Deployments** (depend on ConfigMaps and ServiceAccounts)
  2. **ConfigMaps** (referenced by deployments)
  3. **ServiceAccounts** (referenced by deployments)
  4. **Namespaces** (contain all other resources)
- **Why**: Prevents dependency conflicts and ensures clean removal

#### Deployment Cleanup
- **What**: Removes all test deployments across namespaces
- **How**: 
  - Iterates through all 200 namespaces
  - Deletes `test-deployment` from each namespace
  - Uses `--ignore-not-found=true` for safe deletion
  - Provides progress indicators every 50 deletions
- **Why**: Removes the primary workload resources first

#### ConfigMap Cleanup
- **What**: Removes all test ConfigMaps from namespaces
- **How**: 
  - Deletes both `cm-01` and `cm-02` from each namespace
  - Processes all 200 namespaces systematically
  - Provides progress indicators every 100 deletions
  - Uses safe deletion with ignore-not-found
- **Why**: Removes configuration resources that deployments depend on

#### ServiceAccount Cleanup
- **What**: Removes all test ServiceAccounts from namespaces
- **How**: 
  - Deletes `demo-sa` from each namespace
  - Processes all 200 namespaces systematically
  - Provides progress indicators every 50 deletions
  - Ensures clean removal of identity resources
- **Why**: Removes service account resources that deployments use

#### Namespace Cleanup
- **What**: Removes all test namespaces and their contents
- **How**: 
  - Deletes all `load-test-*` namespaces
  - Cascading deletion removes remaining resources
  - Processes all 200 namespaces systematically
  - Provides progress indicators every 50 deletions
- **Why**: Final cleanup step that removes namespace containers

### Step 4: Cleanup Verification and Monitoring

#### Namespace Deletion Monitoring
- **What**: Waits for namespace cleanup to complete
- **How**: 
  - Monitors remaining namespace count every 10 seconds
  - Sets 5-minute timeout for completion
  - Provides real-time progress updates
  - Reports remaining namespaces if timeout occurs
- **Why**: Ensures all namespaces are properly removed before proceeding

#### Policy Report Cleanup
- **What**: Handles cleanup of Kyverno-generated policy reports
- **How**: 
  - Counts remaining policy reports related to test resources
  - Reports counts for manual review
  - Notes that Kyverno typically handles cleanup automatically
  - Provides visibility into policy enforcement artifacts
- **Why**: Ensures complete cleanup of all test-related resources

#### Final Resource Verification
- **What**: Confirms all test resources have been removed
- **How**: 
  - Re-scans cluster for any remaining test resources
  - Compares actual counts with expected zero values
  - Reports any remaining resources for manual investigation
  - Provides comprehensive cleanup status
- **Why**: Validates successful completion of cleanup process

### Step 5: Infrastructure Health Verification

#### Kyverno Status Check
- **What**: Verifies Kyverno is still operational after cleanup
- **How**: 
  - Counts running Kyverno and Reports Server pods
  - Ensures at least 2 pods are running
  - Reports status for user verification
- **Why**: Confirms policy engine wasn't affected by cleanup

#### Monitoring Stack Verification
- **What**: Confirms monitoring infrastructure is still functional
- **How**: 
  - Counts running monitoring pods (Prometheus, Grafana, Alertmanager)
  - Ensures at least 3 pods are running
  - Reports monitoring stack health status
- **Why**: Verifies observability tools remain available

#### EKS Cluster Status Verification
- **What**: Confirms EKS cluster is still active and healthy
- **How**: 
  - Queries cluster status using AWS CLI
  - Verifies cluster is in `ACTIVE` state
  - Reports cluster health for user confirmation
- **Why**: Ensures infrastructure foundation remains intact

## Key Functions and Their Purposes

### Resource Management
- **Systematic Deletion**: Removes resources in dependency order
- **Progress Monitoring**: Provides real-time cleanup status
- **Safe Deletion**: Uses ignore-not-found flags to prevent errors

### Verification and Validation
- **Resource Counting**: Tracks cleanup progress and completion
- **Health Checks**: Verifies infrastructure remains operational
- **Status Reporting**: Provides comprehensive cleanup summary

### User Safety
- **Confirmation Prompts**: Prevents accidental cleanup
- **Clear Communication**: Explains what will and won't be deleted
- **Graceful Exit**: Allows users to cancel cleanup operations

## Important Considerations

### What Gets Deleted
- **Test Resources**: All resources created during Phase 2
- **Namespaces**: 200 test namespaces and their contents
- **Workloads**: Deployments, pods, ConfigMaps, ServiceAccounts
- **Policy Reports**: Test-related policy enforcement artifacts

### What Gets Preserved
- **EKS Cluster**: Core Kubernetes infrastructure
- **RDS Database**: PostgreSQL database and data
- **Kyverno**: Policy engine and configuration
- **Monitoring Stack**: Prometheus, Grafana, Alertmanager
- **Core Policies**: Kyverno policy definitions

### Cleanup Dependencies
- **Deletion Order**: Resources must be deleted in specific sequence
- **Namespace Cascading**: Deleting namespace removes contained resources
- **Policy Report Cleanup**: May require manual intervention in some cases

## Troubleshooting

### Common Issues
1. **Resource Stuck in Terminating**: Check for finalizers or dependencies
2. **Namespace Cleanup Timeout**: Investigate remaining resources manually
3. **Policy Report Cleanup**: Some reports may persist due to Kyverno design

### Debug Information
- Script provides detailed logging for each cleanup step
- Progress indicators show cleanup status
- Resource counts display before and after cleanup
- Infrastructure health checks verify system stability

## Next Steps

After successful Phase 3 completion:

1. **Infrastructure Ready**: Cluster is clean and ready for reuse
2. **Repeat Testing**: Run Phase 2 again for new scaling tests
3. **Production Use**: Infrastructure can be used for production workloads
4. **Phase 4**: Complete infrastructure destruction when no longer needed

## File Structure

```
phase3-cleanup-k8s/
├── phase3-cleanup-k8s.sh    # Main cleanup script
└── PHASE3_GUIDE.md          # This guide
```

## Cleanup Results Summary

Phase 3 provides systematic cleanup of:

- **Test Resources**: 200 namespaces, 200 SAs, 400 ConfigMaps, 200 deployments
- **Resource Dependencies**: Proper deletion order prevents conflicts
- **Infrastructure Preservation**: Core systems remain operational
- **Clean Environment**: Cluster ready for reuse or production

This phase ensures efficient resource management by removing test artifacts while maintaining a production-ready infrastructure foundation.
