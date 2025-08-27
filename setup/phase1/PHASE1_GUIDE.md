# Phase 1: Complete Guide - Kyverno n4k with PostgreSQL Reports Server

## 📋 Overview

This guide covers the complete setup of a production-ready Kyverno n4k environment with PostgreSQL-based Reports Server for policy management and reporting.

## 🎯 What We're Building

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   EKS Cluster   │    │   AWS RDS       │    │   Monitoring    │
│                 │    │   PostgreSQL    │    │                 │
│ ┌─────────────┐ │    │                 │    │ ┌─────────────┐ │
│ │   Kyverno   │ │◄──►│   Database      │    │ │ Prometheus  │ │
│ │   n4k       │ │    │   (External)    │    │ │ + Grafana   │ │
│ └─────────────┘ │    └─────────────────┘    │ └─────────────┘ │
│ ┌─────────────┐ │                           └─────────────────┘
│ │   Reports   │ │
│ │   Server    │ │
│ └─────────────┘ │
└─────────────────┘
```

## 🚀 Quick Start

```bash
# 1. Setup (15-20 minutes)
./phase1-setup.sh

# 2. Test (5 minutes)
./test-phase1.sh

# 3. Cleanup when done
./phase1-cleanup.sh
```

---

## 📋 Prerequisites

### Required Tools
```bash
brew install awscli eksctl kubectl helm jq postgresql
```

### AWS Configuration
```bash
aws sso login --profile devtest-sso
```

---

## 🔧 Step-by-Step Process

### **Step 1: Configuration & Validation**

**What happens:**
- Loads configuration from `config.sh`
- Validates AWS credentials and permissions
- Checks for existing resources to avoid conflicts
- Generates unique timestamped resource names

**Why needed:**
- Ensures clean environment before starting
- Prevents resource naming conflicts
- Validates prerequisites are met

**Resources created:** None (validation only)

**Commands executed:**
```bash
# Load configuration
source config.sh

# Validate AWS credentials
aws sts get-caller-identity --profile devtest-sso

# Check for existing EKS cluster
eksctl get cluster --name $CLUSTER_NAME --region $AWS_REGION --profile $AWS_PROFILE

# Check for existing RDS instance
aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --profile $AWS_PROFILE
```

---

### **Step 2: EKS Cluster Creation**

**What happens:**
- Creates EKS cluster configuration file
- Deploys EKS cluster with 2 t3a.medium nodes
- Waits for cluster to be ready (15-20 minutes)

**Why needed:**
- Provides Kubernetes environment for Kyverno
- Creates networking infrastructure (VPC, subnets, security groups)
- Establishes foundation for all other components

**Resources created:**
- **EKS Cluster**: `reports-server-test-{timestamp}`
- **VPC**: `vpc-{id}` with public/private subnets
- **Security Groups**: Cluster and node security groups
- **IAM Roles**: EKS service and node roles
- **CloudFormation Stack**: `eksctl-reports-server-test-{timestamp}-cluster`

**How it works:**
- Uses `eksctl` to create cluster via CloudFormation
- Creates VPC with public subnets for internet access
- Sets up security groups for cluster communication

**Commands executed:**
```bash
# Create EKS cluster configuration
cat > eks-cluster-config-phase1.yaml << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: $CLUSTER_NAME
  region: $AWS_REGION
nodeGroups:
  - name: ng-1
    instanceType: t3a.medium
    desiredCapacity: 2
    minSize: 2
    maxSize: 2
    volumeSize: 20
    iam:
      withAddonPolicies:
        autoScaler: true
        ebs: true
        cloudWatch: true
EOF

# Create EKS cluster
eksctl create cluster -f eks-cluster-config-phase1.yaml --profile $AWS_PROFILE

# Wait for nodes to be ready
kubectl wait --for=condition=ready nodes --all --timeout=900s
```

---

### **Step 3: RDS Subnet Group Creation**

**What happens:**
- Gets VPC and subnet information from EKS cluster
- Creates RDS subnet group using EKS subnets

**Why needed:**
- RDS instances must be placed in specific subnets
- Uses same VPC as EKS for network connectivity
- Enables RDS to communicate with EKS cluster

**Resources created:**
- **RDS Subnet Group**: `reports-server-subnet-group-{timestamp}`

**How it works:**
- Queries EKS cluster for VPC and subnet IDs
- Creates subnet group pointing to EKS subnets
- Enables RDS to be deployed in same VPC as EKS

**Commands executed:**
```bash
# Get VPC ID from EKS cluster
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text --profile $AWS_PROFILE)

# Get subnets from different AZs for RDS
RDS_SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region $AWS_REGION --query 'Subnets[].{SubnetId:SubnetId,AvailabilityZone:AvailabilityZone}' --output json | jq -r 'group_by(.AvailabilityZone) | .[0:2] | .[].SubnetId' | tr '\n' ' ')

# Create RDS subnet group
aws rds create-db-subnet-group \
    --db-subnet-group-name reports-server-subnet-group-${TIMESTAMP} \
    --db-subnet-group-description "Subnet group for Reports Server RDS ${TIMESTAMP}" \
    --subnet-ids $RDS_SUBNET_IDS \
    --region $AWS_REGION \
    --profile $AWS_PROFILE
```

---

### **Step 4: Security Group Configuration**

**What happens:**
- Gets default security group from VPC
- Adds PostgreSQL port 5432 rule to security group

**Why needed:**
- Allows EKS pods to connect to RDS PostgreSQL
- Enables Reports Server database connectivity
- Required for Kyverno to store policy reports

**Resources created:**
- **Security Group Rule**: TCP port 5432 ingress rule

**How it works:**
- Modifies existing VPC security group
- Adds rule allowing traffic from anywhere to port 5432
- Enables database connectivity from EKS cluster

**Commands executed:**
```bash
# Get default security group
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" --region $AWS_REGION --query 'SecurityGroups[0].GroupId' --output text --profile $AWS_PROFILE)

# Configure security group for PostgreSQL access
aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 5432 \
    --cidr 0.0.0.0/0 \
    --region $AWS_REGION \
    --profile $AWS_PROFILE
```

---

### **Step 5: RDS PostgreSQL Instance Creation**

**What happens:**
- Creates PostgreSQL 14.12 instance (db.t3.micro)
- Configures database with generated credentials
- Waits for instance to be available (10-15 minutes)

**Why needed:**
- Provides persistent storage for Reports Server
- Stores policy reports, violations, and audit data
- Enables production-ready reporting capabilities

**Resources created:**
- **RDS Instance**: `reports-server-db-{timestamp}`
- **Database**: `reportsdb`
- **User**: `reportsuser` with generated password

**How it works:**
- Creates PostgreSQL instance in EKS VPC
- Uses subnet group for placement
- Configures security group for connectivity
- Generates secure random password

**Commands executed:**
```bash
# Generate database password
DB_PASSWORD=$(openssl rand -hex 32)

# Create RDS PostgreSQL instance
aws rds create-db-instance \
    --db-instance-identifier $RDS_INSTANCE_ID \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --engine-version 14.12 \
    --master-username $DB_USERNAME \
    --master-user-password "$DB_PASSWORD" \
    --allocated-storage 20 \
    --storage-type gp2 \
    --db-subnet-group-name reports-server-subnet-group-${TIMESTAMP} \
    --vpc-security-group-ids $SECURITY_GROUP_ID \
    --backup-retention-period 7 \
    --no-multi-az \
    --auto-minor-version-upgrade \
    --publicly-accessible \
    --storage-encrypted \
    --db-name $DB_NAME \
    --region $AWS_REGION \
    --profile $AWS_PROFILE

# Wait for RDS to be available
while true; do
    rds_status=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --region $AWS_REGION --query 'DBInstances[0].DBInstanceStatus' --output text --profile $AWS_PROFILE)
    if [[ "$rds_status" == "available" ]]; then
        break
    fi
    sleep 30
done

# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --region $AWS_REGION --query 'DBInstances[0].Endpoint.Address' --output text --profile $AWS_PROFILE)
```

---

### **Step 6: Database Validation & Verification**

**What happens:**
- Tests database connectivity to RDS instance
- Verifies `reportsdb` database exists and is accessible
- Validates database is ready for Reports Server

**Why needed:**
- Ensures database is accessible before Kyverno installation
- Confirms RDS setup is working correctly
- Prevents Kyverno installation failures due to database issues

**Resources verified:**
- **Database**: `reportsdb` (created in Step 5, verified here)

**How it works:**
- Connects to PostgreSQL using psql client
- Checks if `reportsdb` database exists (should exist from RDS creation)
- Validates connectivity and permissions
- Only creates database if missing (edge case handling)

**Commands executed:**
```bash
# Test database connectivity
PGPASSWORD="$DB_PASSWORD" psql -h "$RDS_ENDPOINT" -U "$DB_USERNAME" -d postgres -c "SELECT 1;"

# If connectivity fails, reset password
if [[ $? -ne 0 ]]; then
    NEW_PASSWORD=$(openssl rand -hex 16)
    aws rds modify-db-instance --db-instance-identifier $RDS_INSTANCE_ID --master-user-password "$NEW_PASSWORD" --region $AWS_REGION --profile $AWS_PROFILE --apply-immediately
    DB_PASSWORD="$NEW_PASSWORD"
fi

# Verify database exists
PGPASSWORD="$DB_PASSWORD" psql -h "$RDS_ENDPOINT" -U "$DB_USERNAME" -d postgres -c "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';"

# Create database if missing (edge case)
if [[ $? -ne 0 ]]; then
    PGPASSWORD="$DB_PASSWORD" psql -h "$RDS_ENDPOINT" -U "$DB_USERNAME" -d postgres -c "CREATE DATABASE $DB_NAME;"
fi
```

---

### **Step 7: Helm Repository Setup**

**What happens:**
- Adds required Helm repositories
- Updates repository cache

**Why needed:**
- Provides access to Kyverno and monitoring charts
- Enables Helm installations

**Resources created:**
- **Helm Repositories**: prometheus-community, nirmata, kyverno

**How it works:**
- Adds remote Helm chart repositories
- Downloads chart metadata for installations

**Commands executed:**
```bash
# Add Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add nirmata https://nirmata.github.io/reports-server
helm repo add kyverno https://kyverno.github.io/charts

# Update repository cache
helm repo update
```

---

### **Step 8: Monitoring Stack Installation**

**What happens:**
- Installs Prometheus + Grafana monitoring stack
- Waits for monitoring components to be ready

**Why needed:**
- Provides observability for Kyverno and Reports Server
- Enables metrics collection and visualization
- Allows monitoring of policy enforcement

**Resources created:**
- **Namespace**: `monitoring`
- **Prometheus**: Metrics collection and storage
- **Grafana**: Metrics visualization and dashboards
- **Alertmanager**: Alert management

**How it works:**
- Installs kube-prometheus-stack via Helm
- Creates monitoring namespace and components
- Configures ServiceMonitors for automatic discovery

**Commands executed:**
```bash
# Install monitoring stack
helm install monitoring prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --set grafana.enabled=true \
    --set prometheus.enabled=true \
    --set alertmanager.enabled=true

# Wait for monitoring stack to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=900s
```

---

### **Step 9: Kyverno Installation**

**What happens:**
- Installs Kyverno with integrated Reports Server
- Configures Reports Server to use PostgreSQL
- Waits for all Kyverno components to be ready

**Why needed:**
- Provides policy enforcement engine
- Enables policy reporting and audit capabilities
- Integrates with PostgreSQL for data persistence

**Resources created:**
- **Namespace**: `kyverno`
- **Kyverno Pods**: 5 pods (admission, background, cleanup, reports controller, reports server)
- **Services**: Kyverno and Reports Server services
- **CRDs**: Custom Resource Definitions for policies

**How it works:**
- Uses `nirmata/kyverno` Helm chart
- Configures Reports Server with PostgreSQL connection
- Deploys all Kyverno components in single namespace
- Integrates Reports Server directly with Kyverno

**Commands executed:**
```bash
# Create kyverno namespace
kubectl create namespace kyverno --dry-run=client -o yaml | kubectl apply -f -

# Install Kyverno with integrated Reports Server
helm install kyverno nirmata/kyverno \
    --namespace kyverno \
    --create-namespace \
    --set reports-server.install=true \
    --set reports-server.config.etcd.enabled=false \
    --set reports-server.config.db.name=$DB_NAME \
    --set reports-server.config.db.user=$DB_USERNAME \
    --set reports-server.config.db.password="$DB_PASSWORD" \
    --set reports-server.config.db.host=$RDS_ENDPOINT \
    --set reports-server.config.db.port=5432 \
    --version=3.3.31

# Wait for Kyverno to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kyverno -n kyverno --timeout=1200s
```

---

### **Step 10: Baseline Policies Installation**

**What happens:**
- Installs local baseline security policies
- Configures policy enforcement rules

**Why needed:**
- Provides basic security policies for testing
- Demonstrates policy enforcement capabilities
- Validates Kyverno functionality

**Resources created:**
- **ClusterPolicy**: `require-labels` - Enforces app and version labels
- **ClusterPolicy**: `disallow-privileged-containers` - Prevents privileged containers

**How it works:**
- Applies local policy YAML files via kubectl
- Policies are enforced at admission time
- Violations are logged and reported

**Commands executed:**
```bash
# Apply baseline policies
kubectl apply -f policies/baseline/require-labels.yaml
kubectl apply -f policies/baseline/disallow-privileged-containers.yaml

# Verify policies are ready
kubectl get clusterpolicies
```

---

### **Step 11: ServiceMonitor Configuration**

**What happens:**
- Applies ServiceMonitors for Kyverno and Reports Server
- Configures Prometheus to scrape metrics

**Why needed:**
- Enables metrics collection for Kyverno components
- Provides monitoring dashboards
- Allows performance monitoring

**Resources created:**
- **ServiceMonitor**: `kyverno-servicemonitor`
- **ServiceMonitor**: `reports-server-servicemonitor`

**How it works:**
- ServiceMonitors tell Prometheus what to monitor
- Prometheus automatically discovers and scrapes metrics
- Metrics are available in Grafana dashboards

**Commands executed:**
```bash
# Apply ServiceMonitors
kubectl apply -f kyverno-servicemonitor.yaml
kubectl apply -f reports-server-servicemonitor.yaml

# Verify ServiceMonitors are created
kubectl get servicemonitors -n monitoring
```

---

### **Step 12: Health Verification**

**What happens:**
- Verifies all components are healthy
- Tests database connectivity
- Validates policy enforcement

**Why needed:**
- Ensures setup completed successfully
- Identifies any issues before testing
- Provides confidence in deployment

**Resources created:** None (verification only)

**How it works:**
- Checks pod readiness and health
- Tests database connections
- Validates policy enforcement is working

**Commands executed:**
```bash
# Check all pods are running
kubectl get pods -n kyverno
kubectl get pods -n monitoring

# Verify policies are active
kubectl get clusterpolicies

# Check ServiceMonitors
kubectl get servicemonitors -n monitoring

# Test Reports Server logs
kubectl logs -n kyverno -l app.kubernetes.io/name=reports-server --tail=20

# Verify database connectivity
PGPASSWORD="$DB_PASSWORD" psql -h "$RDS_ENDPOINT" -U "$DB_USERNAME" -d reportsdb -c "SELECT version();"
```

---

## 🔗 Resource Interactions

### **Network Communication**
```
EKS Pods ←→ RDS PostgreSQL (Port 5432)
EKS Pods ←→ Prometheus (Metrics scraping)
Grafana ←→ Prometheus (Dashboard data)
```

### **Data Flow**
```
1. Kubernetes API → Kyverno Admission Controller
2. Kyverno → Reports Controller → Reports Server
3. Reports Server → PostgreSQL Database
4. Prometheus → Kyverno/Reports Server (Metrics)
5. Grafana → Prometheus (Visualization)
```

### **Policy Enforcement Flow**
```
1. User creates/modifies resource
2. Kubernetes API receives request
3. Kyverno Admission Controller validates against policies
4. If valid: Resource is created/modified
5. If invalid: Request is rejected
6. PolicyReport is generated and stored in PostgreSQL
7. Metrics are collected by Prometheus
8. Data is visualized in Grafana
```

---

## 📊 Resource Summary

### **AWS Resources**
| Resource | Name | Purpose |
|----------|------|---------|
| EKS Cluster | `reports-server-test-{timestamp}` | Kubernetes environment |
| RDS Instance | `reports-server-db-{timestamp}` | PostgreSQL database |
| VPC | `vpc-{id}` | Network isolation |
| Security Groups | Multiple | Network security |
| CloudFormation Stacks | 2 stacks | Infrastructure management |

### **Kubernetes Resources**
| Resource | Count | Purpose |
|----------|-------|---------|
| Namespaces | 2 | Resource isolation |
| Pods | 12+ | Application containers |
| Services | 5+ | Network access |
| Policies | 2 | Security enforcement |
| ServiceMonitors | 2 | Metrics collection |

---

## 🧪 Testing

### **Automated Testing**
```bash
./test-phase1.sh
```

**Tests performed:**
- AWS connectivity
- EKS cluster health
- RDS database connectivity
- Kyverno pod health
- Reports Server functionality
- Policy enforcement
- Monitoring stack health
- ServiceMonitor validation

### **Manual Testing**
```bash
# Check all pods
kubectl get pods -A

# Test database connection
PGPASSWORD=$DB_PASSWORD psql -h $RDS_ENDPOINT -U $DB_USERNAME -d $DB_NAME

# Access Grafana
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
```

---

## 🧹 Cleanup

### **Automated Cleanup**
```bash
./phase1-cleanup.sh
```

**Cleanup order:**
1. Kubernetes resources (pods, services, policies)
2. Helm releases
3. RDS instance
4. RDS subnet group
5. EKS cluster
6. CloudFormation stacks

### **Manual Cleanup (if needed)**
```bash
# Delete RDS
aws rds delete-db-instance --db-instance-identifier $RDS_INSTANCE_ID --skip-final-snapshot

# Delete EKS
aws eks delete-cluster --name $CLUSTER_NAME

# Delete CloudFormation stacks
aws cloudformation delete-stack --stack-name $STACK_NAME
```

---

## 🔧 Troubleshooting

### **Common Issues**

1. **Database Connection Failed**
   - Check security group rules
   - Verify RDS endpoint
   - Test connectivity manually

2. **EKS Cluster Not Ready**
   - Check node status
   - Verify IAM permissions
   - Check CloudFormation stack status

3. **Kyverno Pods Not Starting**
   - Check pod events
   - Verify database connectivity
   - Check resource limits

4. **Policies Not Enforcing**
   - Check policy status
   - Verify admission controller
   - Test policy manually

### **Useful Commands**
```bash
# Check resource status
kubectl get pods -A
aws eks describe-cluster --name $CLUSTER_NAME
aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID

# Check logs
kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno
kubectl logs -n kyverno -l app.kubernetes.io/component=reports-server

# Test connectivity
PGPASSWORD=$DB_PASSWORD psql -h $RDS_ENDPOINT -U $DB_USERNAME -d $DB_NAME -c "SELECT 1;"
```

---

## 💰 Cost Estimation

### **Monthly Costs (us-west-1)**
- **EKS Cluster**: ~$73/month (2 t3a.medium nodes)
- **RDS PostgreSQL**: ~$15/month (db.t3.micro)
- **Data Transfer**: ~$5/month
- **Total**: ~$93/month

### **Cost Optimization**
- Use spot instances for nodes (50% savings)
- Schedule cluster shutdown during off-hours
- Use smaller RDS instance for testing

---

## 🎯 Next Steps

After Phase 1 is complete and tested:

1. **Phase 2**: Scale to 5 nodes for performance testing
2. **Phase 3**: Scale to 12 nodes for production simulation
3. **Customization**: Add custom policies and dashboards
4. **Integration**: Connect to existing monitoring systems

---

## 📞 Support

For issues not covered in this guide:
1. Check the logs using `kubectl logs`
2. Run the test script: `./test-phase1.sh`
3. Review AWS console for resource status
4. Check configuration in `config.sh`
