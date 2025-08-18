# Kyverno n4k + Reports Server (PostgreSQL): Comprehensive Testing Guide

## 🎯 Overview

This guide provides a **systematic, phased approach** to test Kyverno n4k with Reports Server using **AWS RDS PostgreSQL** instead of etcd. This approach is recommended for production environments as it provides better scalability, reliability, and performance.

## 📋 Testing Strategy

### **Why PostgreSQL Instead of etcd?**

Based on the [Reports Server documentation](https://kyverno.github.io/reports-server/), PostgreSQL offers several advantages:

- **Better Scalability**: Handles large volumes of policy reports without etcd limitations
- **Production Ready**: AWS RDS provides managed database with high availability
- **Query Performance**: SQL queries are more efficient than etcd key-value lookups
- **Data Analytics**: Better support for complex queries and reporting
- **Cost Efficiency**: More predictable costs for large-scale deployments

### **Phased Approach (Recommended)**

| Phase | Purpose | RDS Instance | EKS Cluster | Estimated Cost/Month |
|-------|---------|--------------|-------------|---------------------|
| **Phase 1** | Requirements gathering & validation | db.t3.micro | 2 nodes (t3a.medium) | ~$150 |
| **Phase 2** | Performance validation | db.t3.small | 5 nodes (t3a.medium) | ~$460 |
| **Phase 3** | Production-scale testing | db.r5.large | 12 nodes (t3a.large) | ~$2,800 |

## 🚀 Quick Start (Phase 1)

### Prerequisites

```bash
# Install required tools
brew install awscli eksctl kubectl helm jq

# Configure AWS
aws configure
export AWS_REGION=us-west-2
```

### One-Command Setup

```bash
# Run Phase 1 setup (includes RDS creation)
./postgresql-testing/phase1-setup.sh

# Run test cases
./postgresql-testing/phase1-test-cases.sh

# Monitor results
./postgresql-testing/phase1-monitor.sh

# Cleanup when done
./postgresql-testing/phase1-cleanup.sh
```

### Access & Verification

```bash
# Check RDS status
aws rds describe-db-instances --db-instance-identifier reports-server-db

# Check Reports Server connection
kubectl -n reports-server logs -l app=reports-server

# Access Grafana dashboard
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

## 📊 Phase 1 Test Results

### Test Categories (19 Total Tests)

| Category | Tests | Purpose | Success Criteria |
|----------|-------|---------|------------------|
| **Basic Functionality** | 1-3 | Verify installation and basic operations | All components running |
| **Policy Enforcement** | 4-6 | Test policy blocking/allowing | Correct policy behavior |
| **Monitoring** | 7-9 | Verify metrics collection | Dashboard shows data |
| **Performance** | 10-12 | Measure response times | < 2 seconds average |
| **PostgreSQL Storage** | 13-15 | Test database operations | Data persists correctly |
| **API Functionality** | 16-18 | Test API endpoints | All endpoints respond |
| **Failure Recovery** | 19 | Test system resilience | System recovers |

### Success Criteria

- ✅ **All basic functionality tests pass**
- ✅ **RDS connection stable** (no connection errors)
- ✅ **Reports stored in PostgreSQL** (verified via database queries)
- ✅ **Performance acceptable** (< 2 seconds response time)
- ✅ **Monitoring data available** (Grafana dashboard populated)

## 🔧 Manual Setup (Alternative to Scripts)

### Phase 1: Small-Scale EKS + RDS Setup

#### 1. Create EKS Cluster

```bash
# Create EKS cluster configuration
cat > postgresql-testing/eks-cluster-config-phase1.yaml << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: reports-server-test
  region: us-west-2
nodeGroups:
  - name: ng-1
    instanceType: t3a.medium
    desiredCapacity: 2
    minSize: 2
    maxSize: 4
    volumeSize: 20
    iam:
      withAddonPolicies:
        autoScaler: true
        ebs: true
EOF

# Create cluster
eksctl create cluster -f postgresql-testing/eks-cluster-config-phase1.yaml
```

#### 2. Create RDS PostgreSQL Instance

```bash
# Create RDS subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name reports-server-subnet-group \
  --db-subnet-group-description "Subnet group for Reports Server RDS" \
  --subnet-ids $(aws ec2 describe-subnets --query 'Subnets[?MapPublicIpOnLaunch==`true`].SubnetId' --output text | tr '\t' ' ')

# Create RDS instance
aws rds create-db-instance \
  --db-instance-identifier reports-server-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 14.10 \
  --master-username reportsuser \
  --master-user-password $(openssl rand -base64 32) \
  --allocated-storage 20 \
  --storage-type gp2 \
  --db-subnet-group-name reports-server-subnet-group \
  --vpc-security-group-ids $(aws ec2 describe-security-groups --query 'SecurityGroups[?GroupName==`default`].GroupId' --output text) \
  --backup-retention-period 7 \
  --multi-az false \
  --auto-minor-version-upgrade \
  --publicly-accessible \
  --storage-encrypted
```

#### 3. Install Monitoring Stack

```bash
# Add Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.enabled=true \
  --set alertmanager.enabled=true
```

#### 4. Install Reports Server with PostgreSQL

```bash
# Create namespace
kubectl create namespace reports-server

# Add Reports Server Helm repository
helm repo add reports-server https://kyverno.github.io/reports-server
helm repo update

# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier reports-server-db --query 'DBInstances[0].Endpoint.Address' --output text)

# Install Reports Server with PostgreSQL configuration
helm install reports-server reports-server/reports-server \
  --namespace reports-server \
  --set database.type=postgres \
  --set database.postgres.host=$RDS_ENDPOINT \
  --set database.postgres.port=5432 \
  --set database.postgres.database=reports \
  --set database.postgres.username=reportsuser \
  --set database.postgres.password=$(aws rds describe-db-instances --db-instance-identifier reports-server-db --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text | xargs aws secretsmanager get-secret-value --query 'SecretString' --output text | jq -r '.password')
```

#### 5. Install Kyverno n4k

```bash
# Add Kyverno Helm repository
helm repo add kyverno https://kyverno.github.io/charts
helm repo update

# Install Kyverno
helm install kyverno kyverno/kyverno \
  --namespace kyverno-system \
  --create-namespace \
  --set reportsServer.enabled=true \
  --set reportsServer.url=http://reports-server.reports-server.svc.cluster.local:8080
```

#### 6. Install Baseline Policies

```bash
# Install Pod Security Standards
kubectl apply -f https://raw.githubusercontent.com/kyverno/kyverno/main/config/samples/pod-security/pod-security-standards.yaml

# Install additional test policies
kubectl apply -f postgresql-testing/baseline-policies.yaml
```

## 📈 Phase 2: Medium-Scale Testing

### Cluster Specifications

- **EKS Cluster**: 5 nodes (t3a.medium)
- **RDS Instance**: db.t3.small
- **Expected Load**: ~800 applications
- **Estimated Cost**: ~$460/month

### Resource Calculations

| Component | Specification | Monthly Cost |
|-----------|---------------|--------------|
| EKS Control Plane | Standard | ~$73 |
| EKS Nodes (5x t3a.medium) | 5 × $15 | ~$75 |
| RDS PostgreSQL (db.t3.small) | 1 vCPU, 2GB RAM | ~$25 |
| Storage (20GB GP2) | EBS + RDS | ~$5 |
| **Total** | | **~$178** |

### Installation Steps

```bash
# Use Phase 2 configuration
./postgresql-testing/phase2-setup.sh
./postgresql-testing/phase2-test-cases.sh
./postgresql-testing/phase2-monitor.sh
```

## 🏭 Phase 3: Production-Scale Testing

### Cluster Specifications

- **EKS Cluster**: 12 nodes (t3a.large)
- **RDS Instance**: db.r5.large
- **Expected Load**: 12,000 pods across 1,425 namespaces
- **Estimated Cost**: ~$2,800/month

### Resource Calculations

| Component | Specification | Monthly Cost |
|-----------|---------------|--------------|
| EKS Control Plane | Standard | ~$73 |
| EKS Nodes (12x t3a.large) | 12 × $30 | ~$360 |
| RDS PostgreSQL (db.r5.large) | 2 vCPU, 16GB RAM | ~$350 |
| Storage (100GB GP2) | EBS + RDS | ~$15 |
| **Total** | | **~$798** |

### Load Testing Scripts

#### Create Namespaces

```bash
#!/bin/bash
# postgresql-testing/create-namespaces.sh

echo "Creating 1,425 namespaces..."

for i in $(seq 1 1425); do
  kubectl create namespace scale-test-$i
  if [ $((i % 100)) -eq 0 ]; then
    echo "Created $i namespaces"
  fi
done

echo "All namespaces created!"
```

#### Create Pods

```bash
#!/bin/bash
# postgresql-testing/create-pods.sh

echo "Creating 12,000 pods across 1,425 namespaces..."

pods_per_namespace=8
extra_pods=12000

for i in $(seq 1 1425); do
  namespace="scale-test-$i"
  
  # Create base pods for this namespace
  for j in $(seq 1 $pods_per_namespace); do
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-$j
  namespace: $namespace
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
    resources:
      requests:
        memory: "64Mi"
        cpu: "50m"
      limits:
        memory: "128Mi"
        cpu: "100m"
  restartPolicy: Never
EOF
  done
  
  # Create some violating pods for policy testing
  if [ $((i % 10)) -eq 0 ]; then
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: violating-pod
  namespace: $namespace
spec:
  hostPID: true
  containers:
  - name: nginx
    image: nginx:alpine
    securityContext:
      privileged: true
EOF
  fi
  
  if [ $((i % 100)) -eq 0 ]; then
    echo "Created pods in $i namespaces"
  fi
done

echo "All pods created!"
```

#### Monitor Load Test

```bash
#!/bin/bash
# postgresql-testing/monitor-load-test.sh

echo "Monitoring large-scale load test..."

# Create monitoring log file
LOG_FILE="load-test-monitoring-$(date +%Y%m%d-%H%M%S).csv"
echo "Timestamp,Cluster_Status,Kyverno_Status,Reports_Server_Status,RDS_Status,Total_Pods,Policy_Reports,CPU_Usage,Memory_Usage,RDS_Connections" > $LOG_FILE

while true; do
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  
  # Cluster status
  CLUSTER_STATUS=$(kubectl get nodes --no-headers | grep -c "Ready")
  
  # Kyverno status
  KYVERNO_STATUS=$(kubectl -n kyverno-system get pods -l app=kyverno --no-headers | grep -c "Running")
  
  # Reports Server status
  REPORTS_SERVER_STATUS=$(kubectl -n reports-server get pods -l app=reports-server --no-headers | grep -c "Running")
  
  # RDS status
  RDS_STATUS=$(aws rds describe-db-instances --db-instance-identifier reports-server-db --query 'DBInstances[0].DBInstanceStatus' --output text)
  
  # Total pods
  TOTAL_PODS=$(kubectl get pods -A --no-headers | wc -l)
  
  # Policy reports count
  POLICY_REPORTS=$(kubectl get policyreports -A --no-headers | wc -l)
  
  # Resource usage
  CPU_USAGE=$(kubectl top nodes --no-headers | awk '{sum+=$3} END {print sum}')
  MEMORY_USAGE=$(kubectl top nodes --no-headers | awk '{sum+=$5} END {print sum}')
  
  # RDS connections (via CloudWatch)
  RDS_CONNECTIONS=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBInstanceIdentifier,Value=reports-server-db \
    --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average \
    --query 'Datapoints[0].Average' \
    --output text 2>/dev/null || echo "N/A")
  
  # Log to CSV
  echo "$TIMESTAMP,$CLUSTER_STATUS,$KYVERNO_STATUS,$REPORTS_SERVER_STATUS,$RDS_STATUS,$TOTAL_PODS,$POLICY_REPORTS,$CPU_USAGE,$MEMORY_USAGE,$RDS_CONNECTIONS" >> $LOG_FILE
  
  # Display current status
  echo "=== Load Test Monitoring - $TIMESTAMP ==="
  echo "Cluster Nodes: $CLUSTER_STATUS/12 Ready"
  echo "Kyverno Pods: $KYVERNO_STATUS Running"
  echo "Reports Server: $REPORTS_SERVER_STATUS Running"
  echo "RDS Status: $RDS_STATUS"
  echo "Total Pods: $TOTAL_PODS"
  echo "Policy Reports: $POLICY_REPORTS"
  echo "CPU Usage: $CPU_USAGE"
  echo "Memory Usage: $MEMORY_USAGE"
  echo "RDS Connections: $RDS_CONNECTIONS"
  echo "=========================================="
  
  sleep 30
done
```

#### Cleanup Load Test

```bash
#!/bin/bash
# postgresql-testing/cleanup-load-test.sh

echo "Cleaning up large-scale load test..."

# Delete test namespaces
echo "Deleting test namespaces..."
for i in $(seq 1 1425); do
  kubectl delete namespace scale-test-$i --ignore-not-found=true
  if [ $((i % 100)) -eq 0 ]; then
    echo "Deleted $i namespaces"
  fi
done

# Clean up Reports Server and Kyverno
echo "Cleaning up Reports Server and Kyverno..."
helm uninstall reports-server -n reports-server
helm uninstall kyverno -n kyverno-system

# Clean up monitoring
echo "Cleaning up monitoring stack..."
helm uninstall monitoring -n monitoring

# Ask about RDS cleanup
read -p "Do you want to delete the RDS instance? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Deleting RDS instance..."
  aws rds delete-db-instance \
    --db-instance-identifier reports-server-db \
    --skip-final-snapshot \
    --delete-automated-backups
fi

# Ask about EKS cluster cleanup
read -p "Do you want to delete the EKS cluster? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Deleting EKS cluster..."
  eksctl delete cluster --name reports-server-test --region us-west-2
fi

echo "Cleanup completed!"
```

## 🔍 Monitoring & Metrics

### RDS Monitoring (Based on AWS Documentation)

Following [AWS RDS monitoring best practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Monitoring.html), we monitor:

#### Key RDS Metrics

| Metric | Description | Threshold | Action |
|--------|-------------|-----------|--------|
| **CPU Utilization** | Database CPU usage | > 80% | Consider scaling up |
| **Database Connections** | Active connections | > 80% of max | Check connection pooling |
| **Free Storage Space** | Available storage | < 20% | Add storage |
| **Read/Write IOPS** | Database I/O operations | > 80% of provisioned | Optimize queries |
| **Network Throughput** | Data transfer rate | Monitor trends | Check application patterns |

#### Grafana Dashboard

```json
{
  "dashboard": {
    "title": "Reports Server PostgreSQL Monitoring",
    "panels": [
      {
        "title": "RDS CPU Utilization",
        "targets": [
          {
            "expr": "aws_rds_cpuutilization_average",
            "legendFormat": "CPU %"
          }
        ]
      },
      {
        "title": "Database Connections",
        "targets": [
          {
            "expr": "aws_rds_database_connections_average",
            "legendFormat": "Connections"
          }
        ]
      },
      {
        "title": "Storage Usage",
        "targets": [
          {
            "expr": "aws_rds_free_storage_space_average",
            "legendFormat": "Free Space (GB)"
          }
        ]
      }
    ]
  }
}
```

### Key Metrics to Monitor

#### Reports Server Metrics
- Report generation rate
- Database operation latency
- Connection pool usage
- Error rates

#### PostgreSQL Metrics
- Query performance
- Connection count
- Storage growth
- Backup status

#### Overall System Metrics
- End-to-end report processing time
- Policy enforcement latency
- System resource utilization

### Prometheus Queries

```bash
# Reports Server database operations
rate(reports_server_db_operations_total[5m])

# PostgreSQL connection count
aws_rds_database_connections_average

# Policy report generation rate
rate(kyverno_policy_report_generation_total[5m])

# Database query latency
histogram_quantile(0.95, rate(reports_server_db_query_duration_seconds_bucket[5m]))
```

## 🛠️ Troubleshooting

### Common Issues

#### RDS Connection Issues
```bash
# Check RDS status
aws rds describe-db-instances --db-instance-identifier reports-server-db

# Check security groups
aws ec2 describe-security-groups --group-ids $(aws rds describe-db-instances --db-instance-identifier reports-server-db --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' --output text)

# Test database connectivity
kubectl run test-db-connection --rm -i --tty --image postgres:14 -- psql -h $RDS_ENDPOINT -U reportsuser -d reports
```

#### Reports Server Issues
```bash
# Check Reports Server logs
kubectl -n reports-server logs -l app=reports-server

# Check database configuration
kubectl -n reports-server get configmap reports-server-config -o yaml

# Verify API service
kubectl get apiservice v1alpha1.wgpolicyk8s.io
```

#### Performance Issues
```bash
# Check RDS performance insights
aws rds describe-db-instances --db-instance-identifier reports-server-db --query 'DBInstances[0].PerformanceInsightsEnabled'

# Monitor slow queries
aws rds describe-db-instances --db-instance-identifier reports-server-db --query 'DBInstances[0].PerformanceInsightsRetentionPeriod'
```

### Verification Commands

```bash
# Verify Reports Server is using PostgreSQL
kubectl -n reports-server logs -l app=reports-server | grep "database"

# Check policy reports are being stored
kubectl get policyreports -A | head -10

# Verify RDS connectivity
kubectl -n reports-server exec -it $(kubectl -n reports-server get pods -l app=reports-server -o jsonpath='{.items[0].metadata.name}') -- pg_isready -h $RDS_ENDPOINT
```

## 💰 Cost Estimation

### Phase 1: Small-Scale Testing
- **EKS Control Plane**: ~$73/month
- **EKS Nodes (2x t3a.medium)**: ~$30/month
- **RDS PostgreSQL (db.t3.micro)**: ~$15/month
- **Storage (20GB)**: ~$3/month
- **Total**: ~$121/month

### Phase 2: Medium-Scale Testing
- **EKS Control Plane**: ~$73/month
- **EKS Nodes (5x t3a.medium)**: ~$75/month
- **RDS PostgreSQL (db.t3.small)**: ~$25/month
- **Storage (50GB)**: ~$6/month
- **Total**: ~$179/month

### Phase 3: Production-Scale Testing
- **EKS Control Plane**: ~$73/month
- **EKS Nodes (12x t3a.large)**: ~$360/month
- **RDS PostgreSQL (db.r5.large)**: ~$350/month
- **Storage (100GB)**: ~$15/month
- **Total**: ~$798/month

### Cost Optimization Tips

1. **Use Spot Instances**: Can save 50-70% on EKS nodes
2. **RDS Reserved Instances**: 1-3 year commitments save 30-60%
3. **Storage Optimization**: Use GP3 instead of GP2 for better performance/cost
4. **Auto Scaling**: Scale down during off-hours
5. **Cleanup**: Always clean up resources after testing

## 🧹 Cleanup

### Phase 1 Cleanup
```bash
./postgresql-testing/phase1-cleanup.sh
```

### Phase 2 & 3 Cleanup
```bash
./postgresql-testing/cleanup-load-test.sh
```

## 📚 Additional Resources

### Repository Contents

```
postgresql-testing/
├── COMPREHENSIVE_GUIDE.md          # This file
├── SIMPLE_GUIDE.md                 # Plain language guide
├── README.md                       # Quick overview
├── eks-cluster-config-phase1.yaml  # Phase 1 EKS config
├── eks-cluster-config-phase2.yaml  # Phase 2 EKS config
├── eks-cluster-config-phase3.yaml  # Phase 3 EKS config
├── phase1-setup.sh                 # Phase 1 automation
├── phase1-test-cases.sh            # Phase 1 testing
├── phase1-monitor.sh               # Phase 1 monitoring
├── phase1-cleanup.sh               # Phase 1 cleanup
├── create-namespaces.sh            # Load testing
├── create-pods.sh                  # Load testing
├── monitor-load-test.sh            # Load monitoring
├── cleanup-load-test.sh            # Load cleanup
├── baseline-policies.yaml          # Test policies
├── rds-monitoring.yaml             # RDS monitoring config
└── grafana-dashboard.json          # Custom dashboard
```

### References

- [Reports Server Documentation](https://kyverno.github.io/reports-server/)
- [AWS RDS Monitoring](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Monitoring.html)
- [Kyverno Documentation](https://kyverno.io/docs/)
- [EKS Best Practices](https://docs.aws.amazon.com/eks/latest/userguide/best-practices.html)

## 🎯 Summary

This PostgreSQL-based testing approach provides:

- ✅ **Production-ready architecture** with AWS RDS
- ✅ **Better scalability** than etcd-based solutions
- ✅ **Comprehensive monitoring** with AWS CloudWatch integration
- ✅ **Cost-effective testing** with phased approach
- ✅ **Real-world validation** for enterprise deployments

The systematic approach ensures successful testing of Kyverno n4k + Reports Server with PostgreSQL, providing confidence for production deployments.
