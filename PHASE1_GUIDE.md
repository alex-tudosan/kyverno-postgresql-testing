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
