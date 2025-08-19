# PostgreSQL Testing Execution Guide
## Complete Step-by-Step Commands for All Phases

### 🎯 Overview
This document contains **exact commands** and **environment variables** needed to execute all three phases of PostgreSQL testing. Follow this guide sequentially.

---

## 📋 Prerequisites Setup

### 1. Install Required Tools
```bash
# Install all tools at once
brew install awscli eksctl kubectl helm jq

# Verify installations
aws --version
eksctl version
kubectl version --client
helm version
jq --version
```

### 2. Configure AWS
```bash
# Set up AWS credentials
aws configure

# Set environment variables
export AWS_REGION=us-west-1
export AWS_DEFAULT_REGION=us-west-1

# Verify AWS setup
aws sts get-caller-identity
```

### 3. Set Project Variables
```bash
# Set project-specific variables
export PROJECT_NAME="kyverno-postgresql-testing"
export CLUSTER_NAME="reports-server-test"
export RDS_INSTANCE_ID="reports-server-db"
export DB_NAME="reportsdb"
export DB_USERNAME="reportsuser"
export DB_PASSWORD=$(openssl rand -base64 32)

# Verify variables
echo "Project: $PROJECT_NAME"
echo "Cluster: $CLUSTER_NAME"
echo "RDS: $RDS_INSTANCE_ID"
echo "DB: $DB_NAME"
echo "User: $DB_USERNAME"
```

---

## 🚀 Phase 1: Small-Scale Testing

### Phase 1 Setup
```bash
# Navigate to project directory
cd /Users/atudosan/nirmata/report-server-etcd/n4k-reportserver-saas

# Make scripts executable
chmod +x phase1-setup.sh
chmod +x phase1-test-cases.sh
chmod +x phase1-monitor.sh
chmod +x phase1-cleanup.sh

# Run Phase 1 setup (15-20 minutes)
./phase1-setup.sh
```

### Phase 1 Testing
```bash
# Run comprehensive tests (5-10 minutes)
./phase1-test-cases.sh

# Monitor system performance
./phase1-monitor.sh

# Check results
kubectl get pods -A
kubectl get policyreports -A
kubectl get clusterpolicyreports
```

### Phase 1 Verification
```bash
# Verify cluster status
kubectl get nodes
kubectl get pods -A --no-headers | grep -v "Running\|Completed" | wc -l

# Verify RDS connection
aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --query 'DBInstances[0].DBInstanceStatus'

# Verify monitoring
kubectl -n monitoring get pods
kubectl -n monitoring get servicemonitors
```

### Phase 1 Cleanup (Optional)
```bash
# Clean up Phase 1 resources
./phase1-cleanup.sh

# Verify cleanup
kubectl get nodes 2>/dev/null || echo "Cluster deleted successfully"
aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID 2>/dev/null || echo "RDS deleted successfully"
```

---

## 🔄 Phase 2: Medium-Scale Testing

### Phase 2 Setup
```bash
# Update environment variables for Phase 2
export CLUSTER_NAME="reports-server-test-phase2"
export RDS_INSTANCE_ID="reports-server-db-phase2"

# Create Phase 2 cluster configuration
cat > eks-cluster-config-phase2.yaml << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: $CLUSTER_NAME
  region: $AWS_REGION
nodeGroups:
  - name: ng-1
    instanceType: t3a.medium
    desiredCapacity: 5
    minSize: 5
    maxSize: 8
    volumeSize: 20
    privateNetworking: true
    iam:
      withAddonPolicies:
        autoScaler: true
        ebs: true
EOF

# Create Phase 2 cluster
eksctl create cluster -f eks-cluster-config-phase2.yaml

# Create RDS instance for Phase 2
aws rds create-db-instance \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --db-instance-class db.t3.small \
  --engine postgres \
  --engine-version 14.10 \
  --master-username $DB_USERNAME \
  --master-user-password "$DB_PASSWORD" \
  --allocated-storage 50 \
  --storage-type gp2 \
  --backup-retention-period 7 \
  --multi-az false \
  --auto-minor-version-upgrade \
  --publicly-accessible \
  --storage-encrypted \
  --db-name $DB_NAME

# Wait for RDS to be available
aws rds wait db-instance-available --db-instance-identifier $RDS_INSTANCE_ID

# Get RDS endpoint
export RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --query 'DBInstances[0].Endpoint.Address' --output text)

# Install monitoring stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.enabled=true \
  --set alertmanager.enabled=true

# Install Reports Server with PostgreSQL
helm repo add reports-server https://kyverno.github.io/reports-server
helm repo update
helm install reports-server reports-server/reports-server \
  --namespace kyverno \
  --create-namespace \
  --set postgresql.enabled=false \
  --set externalDatabase.host=$RDS_ENDPOINT \
  --set externalDatabase.port=5432 \
  --set externalDatabase.database=$DB_NAME \
  --set externalDatabase.username=$DB_USERNAME \
  --set externalDatabase.password=$DB_PASSWORD \
  --set externalDatabase.type=postgresql

# Install Kyverno n4k
helm repo add nirmata https://nirmata.github.io/kyverno-charts
helm repo update
helm install kyverno nirmata/kyverno \
  --namespace kyverno-system \
  --create-namespace \
  --set reportsServer.enabled=false \
  --set reportsServer.external.enabled=true \
  --set reportsServer.external.host=reports-server.kyverno.svc.cluster.local \
  --set reportsServer.external.port=8080

# Apply ServiceMonitors
kubectl apply -f kyverno-servicemonitor.yaml
kubectl apply -f reports-server-servicemonitor.yaml

# Apply baseline policies
kubectl apply -f https://raw.githubusercontent.com/kyverno/kyverno/main/config/samples/pod-security/pod-security-standards.yaml

# Create test policies
cat > baseline-policies-phase2.yaml << EOF
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

kubectl apply -f baseline-policies-phase2.yaml
```

### Phase 2 Testing
```bash
# Create test namespaces
for i in {1..50}; do
  kubectl create namespace test-phase2-$i
done

# Create test pods
for i in {1..50}; do
  kubectl run test-pod-$i --image=nginx:alpine --namespace=test-phase2-$i --labels=app=test
done

# Create some violating pods
for i in {1..10}; do
  kubectl apply -f test-violations-pod.yaml -n test-phase2-$i || true
done

# Monitor performance
kubectl get policyreports -A | wc -l
kubectl get clusterpolicyreports | wc -l

# Check RDS performance
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=$RDS_INSTANCE_ID \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

### Phase 2 Cleanup
```bash
# Delete test resources
kubectl delete namespace test-phase2-{1..50} --ignore-not-found=true

# Delete cluster
eksctl delete cluster --name=$CLUSTER_NAME --region=$AWS_REGION

# Delete RDS instance
aws rds delete-db-instance \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --skip-final-snapshot \
  --delete-automated-backups

# Clean up files
rm -f eks-cluster-config-phase2.yaml baseline-policies-phase2.yaml
```

---

## 🏭 Phase 3: Production-Scale Testing

### Phase 3 Setup
```bash
# Update environment variables for Phase 3
export CLUSTER_NAME="reports-server-test-phase3"
export RDS_INSTANCE_ID="reports-server-db-phase3"

# Create Phase 3 cluster configuration
cat > eks-cluster-config-phase3.yaml << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: $CLUSTER_NAME
  region: $AWS_REGION
nodeGroups:
  - name: ng-1
    instanceType: t3a.large
    desiredCapacity: 12
    minSize: 12
    maxSize: 20
    volumeSize: 50
    privateNetworking: true
    iam:
      withAddonPolicies:
        autoScaler: true
        ebs: true
EOF

# Create Phase 3 cluster
eksctl create cluster -f eks-cluster-config-phase3.yaml

# Create RDS instance for Phase 3
aws rds create-db-instance \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --db-instance-class db.r5.large \
  --engine postgres \
  --engine-version 14.10 \
  --master-username $DB_USERNAME \
  --master-user-password "$DB_PASSWORD" \
  --allocated-storage 200 \
  --storage-type gp2 \
  --backup-retention-period 7 \
  --multi-az true \
  --auto-minor-version-upgrade \
  --publicly-accessible \
  --storage-encrypted \
  --db-name $DB_NAME

# Wait for RDS to be available
aws rds wait db-instance-available --db-instance-identifier $RDS_INSTANCE_ID

# Get RDS endpoint
export RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --query 'DBInstances[0].Endpoint.Address' --output text)

# Install monitoring stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.enabled=true \
  --set alertmanager.enabled=true

# Install Reports Server with PostgreSQL
helm install reports-server reports-server/reports-server \
  --namespace kyverno \
  --create-namespace \
  --set postgresql.enabled=false \
  --set externalDatabase.host=$RDS_ENDPOINT \
  --set externalDatabase.port=5432 \
  --set externalDatabase.database=$DB_NAME \
  --set externalDatabase.username=$DB_USERNAME \
  --set externalDatabase.password=$DB_PASSWORD \
  --set externalDatabase.type=postgresql

# Install Kyverno n4k
helm install kyverno nirmata/kyverno \
  --namespace kyverno-system \
  --create-namespace \
  --set reportsServer.enabled=false \
  --set reportsServer.external.enabled=true \
  --set reportsServer.external.host=reports-server.kyverno.svc.cluster.local \
  --set reportsServer.external.port=8080

# Apply ServiceMonitors
kubectl apply -f kyverno-servicemonitor.yaml
kubectl apply -f reports-server-servicemonitor.yaml

# Apply baseline policies
kubectl apply -f https://raw.githubusercontent.com/kyverno/kyverno/main/config/samples/pod-security/pod-security-standards.yaml

# Create test policies
cat > baseline-policies-phase3.yaml << EOF
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

kubectl apply -f baseline-policies-phase3.yaml
```

### Phase 3 Testing
```bash
# Create 1,425 namespaces
for i in {1..1425}; do
  kubectl create namespace load-test-$i
done

# Create 12,000 pods (approximately 8-9 pods per namespace)
for i in {1..1425}; do
  for j in {1..8}; do
    kubectl run test-pod-$j --image=nginx:alpine --namespace=load-test-$i --labels=app=test --restart=Never &
  done
  # Wait every 100 namespaces to avoid overwhelming the system
  if [ $((i % 100)) -eq 0 ]; then
    wait
    echo "Created pods for $i namespaces"
  fi
done
wait

# Create some violating pods
for i in {1..100}; do
  kubectl apply -f test-violations-pod.yaml -n load-test-$i || true
done

# Monitor at scale
kubectl get pods -A | wc -l
kubectl get policyreports -A | wc -l
kubectl get clusterpolicyreports | wc -l

# Check RDS performance under load
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=$RDS_INSTANCE_ID \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# Check database connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=$RDS_INSTANCE_ID \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

### Phase 3 Cleanup
```bash
# Delete test resources
kubectl delete namespace load-test-{1..1425} --ignore-not-found=true

# Delete cluster
eksctl delete cluster --name=$CLUSTER_NAME --region=$AWS_REGION

# Delete RDS instance
aws rds delete-db-instance \
  --db-instance-identifier $RDS_INSTANCE_ID \
  --skip-final-snapshot \
  --delete-automated-backups

# Clean up files
rm -f eks-cluster-config-phase3.yaml baseline-policies-phase3.yaml
```

---

## 📊 Monitoring Commands

### Real-time Monitoring
```bash
# Monitor cluster status
watch -n 5 'kubectl get nodes && echo "---" && kubectl get pods -A --no-headers | grep -v Running | wc -l'

# Monitor policy reports
watch -n 10 'kubectl get policyreports -A | wc -l && echo "---" && kubectl get clusterpolicyreports | wc -l'

# Monitor RDS metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=$RDS_INSTANCE_ID \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average
```

### Performance Testing
```bash
# Test API response time
time kubectl get pods -A

# Test concurrent operations
for i in {1..10}; do
  kubectl get policyreports -A > /dev/null &
done
wait

# Test database connection
kubectl -n kyverno logs -l app=reports-server --tail=50 | grep -i "database\|postgres\|connection"
```

---

## 🧹 Final Cleanup

### Complete Environment Cleanup
```bash
# List all resources
eksctl get cluster --region=$AWS_REGION
aws rds describe-db-instances --query 'DBInstances[?contains(DBInstanceIdentifier, `reports-server`)].DBInstanceIdentifier' --output table

# Clean up all test clusters
eksctl delete cluster --name=reports-server-test --region=$AWS_REGION --ignore-not-found=true
eksctl delete cluster --name=reports-server-test-phase2 --region=$AWS_REGION --ignore-not-found=true
eksctl delete cluster --name=reports-server-test-phase3 --region=$AWS_REGION --ignore-not-found=true

# Clean up all test RDS instances
aws rds delete-db-instance --db-instance-identifier reports-server-db --skip-final-snapshot --delete-automated-backups --ignore-not-found=true
aws rds delete-db-instance --db-instance-identifier reports-server-db-phase2 --skip-final-snapshot --delete-automated-backups --ignore-not-found=true
aws rds delete-db-instance --db-instance-identifier reports-server-db-phase3 --skip-final-snapshot --delete-automated-backups --ignore-not-found=true

# Clean up temporary files
rm -f eks-cluster-config-*.yaml baseline-policies-*.yaml postgresql-testing-config.env

# Reset environment variables
unset CLUSTER_NAME RDS_INSTANCE_ID DB_NAME DB_USERNAME DB_PASSWORD RDS_ENDPOINT
```

---

## ⚠️ Important Notes

### Cost Management
- **Phase 1**: ~$121/month
- **Phase 2**: ~$179/month  
- **Phase 3**: ~$798/month
- **Always run cleanup scripts** to avoid ongoing charges

### Time Estimates
- **Phase 1 Setup**: 15-20 minutes
- **Phase 2 Setup**: 25-30 minutes
- **Phase 3 Setup**: 35-40 minutes
- **Testing**: 10-15 minutes per phase
- **Cleanup**: 5-10 minutes per phase

### Prerequisites
- AWS account with appropriate permissions
- Sufficient AWS credits/budget
- Stable internet connection
- Terminal with bash/zsh

### Troubleshooting
- If cluster creation fails, check AWS region and instance availability
- If RDS creation fails, check subnet groups and security groups
- If pods fail to start, check resource limits and node capacity
- Monitor AWS CloudWatch for RDS performance issues

---

## 🎯 Success Criteria

### Phase 1 Success
- ✅ 2 nodes running
- ✅ RDS instance available
- ✅ All 19 tests pass
- ✅ Policy reports generated
- ✅ Database connection working

### Phase 2 Success
- ✅ 5 nodes running
- ✅ 50+ namespaces created
- ✅ 400+ pods running
- ✅ Policy reports at scale
- ✅ RDS performance acceptable

### Phase 3 Success
- ✅ 12 nodes running
- ✅ 1,425 namespaces created
- ✅ 12,000+ pods running
- ✅ System handles production load
- ✅ RDS performance under load

---

**📝 Note: This document is in .gitignore and should not be committed to the repository.**
