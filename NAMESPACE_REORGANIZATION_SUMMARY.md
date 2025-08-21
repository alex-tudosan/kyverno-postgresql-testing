# Namespace Reorganization Summary

## Overview
Updated Phase 1 setup to install both Reports Server and Kyverno in the same `kyverno` namespace instead of separate namespaces. This provides better architectural organization and simplifies management.

## Changes Made

### 1. **phase1-setup.sh**
- **Namespace Creation**: Changed from creating separate `reports-server` and `kyverno-system` namespaces to single `kyverno` namespace
- **Installation Order**: 
  - First: Install Reports Server in `kyverno` namespace
  - Second: Install Kyverno in same `kyverno` namespace
- **Service URL**: Updated Kyverno Reports Server URL to `http://reports-server.kyverno.svc.cluster.local:8080`
- **Verification**: Updated all pod checks to use `kyverno` namespace

### 2. **create-secrets.sh**
- **Namespace**: All secrets now created in `kyverno` namespace
- **Secret Management**: Updated all secret operations (create, list, delete) to use `kyverno` namespace
- **Configuration**: Reports Server configuration secrets stored in unified namespace

### 3. **phase1-cleanup.sh**
- **Helm Uninstall**: Updated to uninstall both components from `kyverno` namespace
- **Namespace Cleanup**: Removed separate namespace cleanup for `reports-server` and `kyverno-system`
- **Force Delete**: Updated to force delete only `kyverno` and `monitoring` namespaces

### 4. **phase1-test-cases.sh**
- **Log Checks**: Updated Reports Server log checks to use `kyverno` namespace
- **Pod Operations**: Updated pod deletion and recovery tests to use `kyverno` namespace
- **Debugging**: Updated log viewing commands to use correct namespace

### 5. **phase1-monitor.sh**
- **Status Checks**: Updated Reports Server status monitoring to use `kyverno` namespace
- **Log Access**: Updated log viewing commands to use correct namespace

### 6. **reports-server-servicemonitor.yaml**
- **Namespace Selector**: Already correctly configured to monitor `kyverno` namespace

## Benefits of This Approach

### ✅ **Simplified Architecture**
- Single namespace for all policy-related components
- Easier to manage and monitor
- Reduced complexity in service discovery

### ✅ **Better Integration**
- Kyverno and Reports Server are tightly coupled
- Logical grouping of related components
- Improved service communication

### ✅ **Cleaner Organization**
- All policy enforcement components in one place
- Easier to apply RBAC and security policies
- Simplified backup and restore procedures

### ✅ **Reduced Resource Overhead**
- Fewer namespaces to manage
- Simplified network policies
- Better resource utilization

## Installation Sequence

```bash
# 1. Create single namespace
kubectl create namespace kyverno

# 2. Install Reports Server FIRST
helm install reports-server nirmata-reports-server/reports-server \
  --namespace kyverno \
  --version 0.2.3 \
  --set config.db.host=$RDS_ENDPOINT \
  --set config.db.port=5432 \
  --set config.db.name=$DB_NAME \
  --set config.db.user=$DB_USERNAME \
  --set config.db.password="$DB_PASSWORD" \
  --set config.etcd.enabled=false \
  --set config.postgresql.enabled=false

# 3. Wait for Reports Server to be ready
kubectl wait --for=condition=ready pods --all -n kyverno --timeout=300s

# 4. Install Kyverno SECOND
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --set reportsServer.enabled=true \
  --set reportsServer.url=http://reports-server.kyverno.svc.cluster.local:8080
```

## Service Discovery

### Internal Service URLs
- **Reports Server**: `http://reports-server.kyverno.svc.cluster.local:8080`
- **Kyverno**: `http://kyverno.kyverno.svc.cluster.local:8080`

### External Access
- **Grafana**: `kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80`
- **RDS Database**: Direct connection via AWS RDS endpoint

## Monitoring Configuration

### ServiceMonitors
- **Reports Server**: Monitors `kyverno` namespace
- **Kyverno**: Monitors `kyverno` namespace
- **Prometheus**: Collects metrics from both services

### Log Access
```bash
# Reports Server logs
kubectl -n kyverno logs -l app=reports-server

# Kyverno logs  
kubectl -n kyverno logs -l app=kyverno

# All logs in namespace
kubectl -n kyverno logs --all-containers=true
```

## Testing Commands

### Health Checks
```bash
# Check all pods in kyverno namespace
kubectl get pods -n kyverno

# Check Reports Server status
kubectl get pods -n kyverno -l app=reports-server

# Check Kyverno status
kubectl get pods -n kyverno -l app=kyverno
```

### Policy Testing
```bash
# Test policy enforcement
kubectl apply -f test-violations-pod.yaml

# Check policy reports
kubectl get policyreports -n kyverno
```

## Migration Notes

### From Previous Setup
If migrating from the old separate namespace setup:

1. **Backup existing data** (if any)
2. **Uninstall old components**:
   ```bash
   helm uninstall reports-server -n reports-server
   helm uninstall kyverno -n kyverno-system
   ```
3. **Delete old namespaces**:
   ```bash
   kubectl delete namespace reports-server
   kubectl delete namespace kyverno-system
   ```
4. **Run new setup** with unified namespace approach

### Verification
After migration, verify:
- Both components running in `kyverno` namespace
- Reports Server accessible to Kyverno
- All monitoring and logging working correctly
- Policy enforcement functioning as expected

## Conclusion

This namespace reorganization provides a cleaner, more maintainable architecture that better reflects the tight integration between Kyverno and the Reports Server. The unified approach simplifies management while improving the overall system design.
