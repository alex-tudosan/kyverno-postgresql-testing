# Setup Files Directory

This directory contains organized setup files for different deployment scenarios.

## Directory Structure

### `simple/` - Simple Setup
- **simple-setup.sh** - Simplified setup script for basic Kyverno + PostgreSQL testing
- **simple-cleanup.sh** - Cleanup script for simple setup
- **SIMPLE_SETUP.md** - Documentation for simple setup

### `phase1/` - Phase 1 Setup (Comprehensive)
- **phase1-setup.sh** - Comprehensive setup script with full monitoring stack
- **phase1-cleanup.sh** - Cleanup script for phase 1 setup
- **PHASE1_GUIDE.md** - Detailed guide for phase 1 setup
- **eks-cluster-config-phase1.yaml** - EKS cluster configuration for phase 1

### Root Setup Files
- **config.sh** - Configuration script for AWS and cluster setup
- **create-secrets.sh** - Script to create necessary secrets

## Usage

### For Simple Testing:
```bash
cd setup/simple
./simple-setup.sh
```

### For Comprehensive Testing:
```bash
cd setup/phase1
./phase1-setup.sh
```

### For Cleanup:
```bash
# Simple cleanup
cd setup/simple
./simple-cleanup.sh

# Phase 1 cleanup
cd setup/phase1
./phase1-cleanup.sh
```

## Notes

- All scripts are executable and ready to use
- Phase 1 setup includes Prometheus/Grafana monitoring stack
- Simple setup is minimal and focused on core functionality
- Always run cleanup scripts before switching between setups

