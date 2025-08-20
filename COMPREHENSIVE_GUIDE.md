# Kyverno n4k + Reports Server (PostgreSQL): Comprehensive Testing Guide

## 🎯 Overview

This guide provides a **systematic, phased approach** to test Kyverno n4k with Reports Server using **AWS RDS PostgreSQL** instead of etcd. This approach is recommended for production environments as it provides better scalability, reliability, and performance.

## 🆕 Recent Improvements (Latest Version)

### **Enhanced Script Robustness**

The scripts have been significantly improved to handle real-world scenarios better:

#### **1. Smart Resource Naming**
- **Automatic timestamps** added to all resource names
- **Prevents conflicts** when running multiple tests
- **Example:** `reports-server-test-20241220-143022` instead of `reports-server-test-v3`

#### **2. Advanced Timeout Handling**
- **Progress bars** for all long-running operations
- **Configurable timeouts** (15 minutes for RDS, 20 minutes for EKS)
- **Better error messages** when timeouts occur
- **Replaces unreliable `--wait` flags** with custom timeout loops

#### **3. Robust Error Handling**
- **Automatic retry logic** with exponential backoff
- **Cleanup on failure** to prevent resource leaks
- **Better error messages** with timestamps
- **Graceful handling** of transient failures

#### **4. Enhanced Progress Tracking**
- **Real-time progress bars** for all operations
- **Timestamped log messages** for better debugging
- **Clear status indicators** (✅ Success, ⚠️ Warning, ❌ Error)
- **Estimated completion times** for long operations

#### **5. Improved Cleanup Procedures**
- **Force namespace deletion** for stuck resources
- **Better resource verification** before deletion
- **Automatic CloudFormation stack cleanup**
- **Comprehensive status reporting**

#### **6. Resource Conflict Prevention**
- **Pre-flight checks** for existing resources
- **Automatic conflict detection** before creation
- **Clear guidance** when conflicts are found
- **Safe resource naming** with timestamps

## 🎓 Lessons Learned from AWS Resource Deletion

### **Critical Insights from Real-World Testing**

#### **1. EKS Cluster Deletion Strategy**
- **❌ Don't use:** `eksctl delete cluster` (causes pod draining timeouts)
- **✅ Use instead:** `aws eks delete-cluster` (bypasses pod draining issues)
- **Why:** eksctl tries to drain pods gracefully, which can timeout or fail
- **Result:** Faster, more reliable cluster deletion

#### **2. Resource Deletion Sequence**
- **❌ Wrong order:** EKS → RDS → Subnet Group
- **✅ Correct order:** RDS → EKS → Subnet Group
- **Why:** RDS is independent, EKS depends on RDS subnet group
- **Result:** Prevents dependency conflicts during cleanup

#### **3. Security Group Dependency Resolution**
- **Problem:** VPCs can't be deleted due to security group dependencies
- **Solution:** Manually remove security group references before VPC deletion
- **Process:**
  1. Find security groups in VPC: `aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID"`
  2. Find referencing security groups: `aws ec2 describe-security-groups --filters "Name=ip-permission.group-id,Values=$SG_ID"`
  3. Remove references: `aws ec2 revoke-security-group-ingress --group-id $REF_SG --source-group $SG_ID`
  4. Delete security group: `aws ec2 delete-security-group --group-id $SG_ID`
  5. Delete VPC: `aws ec2 delete-vpc --vpc-id $VPC_ID`

#### **4. CloudFormation Stack Cleanup**
- **Problem:** Stacks get stuck in `DELETE_FAILED` state
- **Solution:** Use AWS Console with "Delete this stack but retain resources"
- **Process:**
  1. Go to CloudFormation Console
  2. Select the failed stack
  3. Click "Delete" → "Delete this stack but retain resources"
  4. Uncheck VPC to delete it with the stack
  5. Click "Delete"

#### **5. Kubernetes Namespace Cleanup**
- **Problem:** Namespaces get stuck in "Terminating" state
- **Solution:** Force deletion with grace period 0
- **Process:**
  1. Delete all resources: `kubectl delete all --all -n <namespace>`
  2. Force delete namespace: `kubectl delete namespace <namespace> --force --grace-period=0`

#### **6. Resource Naming Conflicts**
- **Problem:** Multiple test runs create conflicts with same resource names
- **Solution:** Use timestamps in resource names
- **Implementation:** `CLUSTER_NAME="reports-server-test-$(date +%Y%m%d-%H%M%S)"`

#### **7. AWS SSO Session Management**
- **Problem:** Commands fail with "InvalidGrantException"
- **Solution:** Regular re-authentication
- **Process:** `aws sso login --profile devtest-sso`

#### **8. Comprehensive Resource Verification**
- **Problem:** Incomplete cleanup leaves resources running (costing money)
- **Solution:** Verify all resource types after cleanup
- **Resources to check:**
  - EKS clusters
  - RDS instances
  - RDS subnet groups
  - CloudFormation stacks
  - Kubernetes contexts

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

**What this section is for:** If you prefer to understand and run each step manually instead of using the automated script, this section explains exactly what each command does.

**When to use manual setup:**
- You want to learn what each step does
- You need to customize the setup
- You're troubleshooting issues
- You want to understand the process better

### Phase 1: Small-Scale EKS + RDS Setup

#### 1. Create EKS Cluster

**What we're doing:** Creating a small group of nodes in Amazon's cloud to run our security testing.

**Why we need this:** We need nodes to run:
- Kyverno (the security system)
- Reports Server (the database connector)
- Monitoring tools (to see what's happening)
- Test applications (to test the security rules)

**Step 1a: Create the cluster configuration file**

```bash
# Create EKS cluster configuration
cat > postgresql-testing/eks-cluster-config-phase1.yaml << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: reports-server-test
  region: us-west-1
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
```

**What this configuration means:**
- **name: reports-server-test** - The name of your cluster
- **region: us-west-1** - Which Amazon data center to use
- **instanceType: t3a.medium** - Small, cost-effective nodes
- **desiredCapacity: 2** - Start with 2 nodes
- **minSize: 2, maxSize: 4** - Can have between 2-4 nodes
- **volumeSize: 20** - 20GB of storage per node
- **autoScaler: true** - Can automatically add/remove nodes based on load
- **ebs: true** - Can use Amazon's storage service

**Step 1b: Create the actual cluster**

```bash
# Create cluster (this takes 10-15 minutes)
eksctl create cluster -f postgresql-testing/eks-cluster-config-phase1.yaml
```

**What happens during cluster creation:**
1. Amazon creates the management computer (EKS control plane)
2. Amazon creates 2 worker nodes (where your applications run)
3. Amazon sets up networking between the nodes
4. Amazon installs Kubernetes software on all nodes
5. Amazon configures security groups and permissions

**What you'll see:**
- Progress messages showing each step
- Messages about creating nodes
- Final message saying cluster is ready

**How to verify it worked:**
```bash
# Check if cluster was created
eksctl get cluster --region us-west-1

# Check if you can connect to the cluster
kubectl get nodes
```

**Expected result:** You should see 2 nodes listed as "Ready".

#### 2. Create RDS PostgreSQL Instance

**What we're doing:** Creating a professional database in Amazon's cloud to store security reports.

**Step 2a: Create a subnet group (network configuration)**

```bash
# Create RDS subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name reports-server-subnet-group \
  --db-subnet-group-description "Subnet group for Reports Server RDS" \
  --subnet-ids $(aws ec2 describe-subnets --query 'Subnets[?MapPublicIpOnLaunch==`true`].SubnetId' --output text | tr '\t' ' ')
```

**What this does:**
- Creates a network group for the database
- Tells Amazon which network areas the database can use
- Ensures the database can communicate with your Kubernetes cluster

**Step 2b: Create the actual database**

```bash
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

**What each setting means:**
- **db-instance-identifier**: The name of your database
- **db-instance-class**: Small, cost-effective database (db.t3.micro = ~$15/month)
- **engine**: PostgreSQL database software
- **engine-version**: PostgreSQL version 14.10 (stable and secure)
- **master-username**: Database admin username
- **master-user-password**: Automatically generated secure password
- **allocated-storage**: 20GB of storage space
- **storage-type**: GP2 (good performance, reasonable cost)
- **backup-retention-period**: Keep backups for 7 days
- **multi-az**: No (single database to save money)
- **publicly-accessible**: Yes (so your cluster can reach it)
- **storage-encrypted**: Yes (data is encrypted for security)

**What happens during database creation:**
1. Amazon creates a new database server
2. Amazon installs PostgreSQL software
3. Amazon sets up the database with your settings
4. Amazon configures networking and security
5. Amazon starts the database service

**How long it takes:** 5-10 minutes

**How to verify it worked:**
```bash
# Check if database is being created
aws rds describe-db-instances --db-instance-identifier reports-server-db

# Wait for database to be ready
aws rds wait db-instance-available --db-instance-identifier reports-server-db

# Get the database connection details
aws rds describe-db-instances --db-instance-identifier reports-server-db --query 'DBInstances[0].Endpoint.Address' --output text
```

**Expected result:** You should see the database status change from "creating" to "available".

#### 3. Install Monitoring Stack

**What we're doing:** Installing tools to monitor and visualize how our system is performing.

**Why we need this:** We want to see:
- How well the system is working
- If there are any problems
- How much resources are being used
- Performance metrics over time

**What we're installing:**
- **Prometheus**: Collects performance data from all components
- **Grafana**: Creates beautiful dashboards to visualize the data
- **AlertManager**: Sends alerts when something goes wrong

**Step 3a: Add the monitoring software repository**

```bash
# Add Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

**What this does:**
- Tells Helm where to find the monitoring software
- Downloads the latest version information
- Makes the monitoring packages available for installation

**Step 3b: Install the monitoring stack**

```bash
# Install Prometheus stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.enabled=true \
  --set alertmanager.enabled=true
```

**What each setting means:**
- **monitoring**: The name of this installation
- **--namespace monitoring**: Put all monitoring tools in a group called "monitoring"
- **--create-namespace**: Create the group if it doesn't exist
- **grafana.enabled=true**: Install the dashboard tool
- **prometheus.enabled=true**: Install the data collection tool
- **alertmanager.enabled=true**: Install the alerting tool

**What happens during installation:**
1. Helm creates the monitoring namespace
2. Helm installs Prometheus (data collector)
3. Helm installs Grafana (dashboard)
4. Helm installs AlertManager (alerts)
5. Helm configures all components to work together

**How to verify it worked:**
```bash
# Check if monitoring pods are running
kubectl get pods -n monitoring

# Check if Grafana is accessible
kubectl get svc -n monitoring
```

**Expected result:** You should see several pods in the "monitoring" namespace, all showing "Running" status.

**How to access the dashboard:**
```bash
# Get the Grafana password
kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d ; echo

# Open the dashboard
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

**Then open your web browser to:** `http://localhost:3000`
- Username: `admin`
- Password: (the password from the command above)

#### 4. Install Reports Server with PostgreSQL

**What we're doing:** Installing the Reports Server that will store security reports in our PostgreSQL database instead of etcd.

**Why we need this:** The Reports Server is the key component that:
- Connects to our PostgreSQL database
- Stores policy reports and security findings
- Provides an API for other components to access the data
- Handles the transition from etcd to PostgreSQL

**Step 4a: Create a namespace for Reports Server**

```bash
# Create namespace
kubectl create namespace reports-server
```

**What this does:**
- Creates a separate group for Reports Server components
- Keeps Reports Server isolated from other applications
- Makes it easier to manage and monitor

**Step 4b: Add the Reports Server software repository**

```bash
# Add Reports Server Helm repository
helm repo add reports-server https://kyverno.github.io/reports-server
helm repo update
```

**What this does:**
- Tells Helm where to find the Reports Server software
- Downloads the latest version information
- Makes the Reports Server package available for installation

**Step 4c: Get the database connection details**

```bash
# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier reports-server-db --query 'DBInstances[0].Endpoint.Address' --output text)
```

**What this does:**
- Gets the address of our PostgreSQL database
- Stores it in a variable for use in the next step
- This is the address Reports Server will use to connect to the database

**Step 4d: Install Reports Server with PostgreSQL configuration**

```bash
# Add the nirmata reports-server repository
helm repo add nirmata-reports-server https://nirmata.github.io/reports-server

# Install Reports Server with PostgreSQL configuration (v0.2.3)
helm install reports-server nirmata-reports-server/reports-server \
  --namespace reports-server \
  --version 0.2.3 \
  --set db.host=$RDS_ENDPOINT \
  --set db.port=5432 \
  --set db.name=reports \
  --set db.user=reportsuser \
  --set db.password=$(aws rds describe-db-instances --db-instance-identifier reports-server-db --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text | xargs aws secretsmanager get-secret-value --query 'SecretString' --output text | jq -r '.password') \
  --set etcd.enabled=false \
  --set postgresql.enabled=false
```

**What each setting means:**
- **nirmata-reports-server/reports-server**: Use the nirmata fork (better PostgreSQL support)
- **--version 0.2.3**: Use the stable version with external database fixes
- **reports-server**: The name of this installation
- **--namespace reports-server**: Put Reports Server in the reports-server group
- **db.host**: The database server address (RDS endpoint)
- **db.port**: PostgreSQL port (5432 is standard)
- **db.name**: The database name ("reports")
- **db.user**: Database username ("reportsuser")
- **db.password**: Database password
- **etcd.enabled=false**: Disable internal etcd deployment
- **postgresql.enabled=false**: Disable internal PostgreSQL deployment

**Important Notes:**
- Use `db.*` parameters instead of `database.postgres.*`
- Always disable internal etcd and PostgreSQL when using external RDS
- Verify environment variables after installation

**What happens during installation:**
1. Helm creates the Reports Server deployment
2. Reports Server tries to connect to PostgreSQL
3. Reports Server creates necessary database tables
4. Reports Server starts the API service
5. Reports Server begins accepting requests

**How to verify it worked:**
```bash
# Check if Reports Server pod is running
kubectl get pods -n reports-server

# Check Reports Server logs for database connection
kubectl -n reports-server logs -l app=reports-server

# Check if Reports Server API is available
kubectl get apiservice v1alpha1.wgpolicyk8s.io
```

**Expected result:**
- Pod should show "Running" status
- Logs should show successful database connection
- API service should show "True" status

**What to look for in the logs:**
- "database connected" or "postgres connected" messages
- No error messages about connection failures
- Messages about tables being created or ready

#### 5. Install Kyverno n4k

**What we're doing:** Installing Kyverno, the security system that will check your applications and send reports to our PostgreSQL database.

**Why we need this:** Kyverno is the main security component that:
- Checks if applications follow security rules
- Generates security reports when rules are violated
- Sends reports to Reports Server (which stores them in PostgreSQL)
- Provides the security enforcement for your cluster

**Step 5a: Add the Kyverno software repository**

```bash
# Add Kyverno Helm repository
helm repo add kyverno https://kyverno.github.io/charts
helm repo update
```

**What this does:**
- Tells Helm where to find the Kyverno software
- Downloads the latest version information
- Makes the Kyverno package available for installation

**Step 5b: Install Kyverno with Reports Server integration**

```bash
# Install Kyverno
helm install kyverno kyverno/kyverno \
  --namespace kyverno-system \
  --create-namespace \
  --set reportsServer.enabled=true \
  --set reportsServer.url=http://reports-server.reports-server.svc.cluster.local:8080
```

**What each setting means:**
- **kyverno**: The name of this installation
- **--namespace kyverno-system**: Put Kyverno in the kyverno-system group
- **--create-namespace**: Create the group if it doesn't exist
- **reportsServer.enabled=true**: Tell Kyverno to use Reports Server
- **reportsServer.url**: The address where Reports Server is running

**What happens during installation:**
1. Helm creates the kyverno-system namespace
2. Helm installs Kyverno components (admission controller, background scanner, etc.)
3. Kyverno connects to Reports Server
4. Kyverno starts monitoring the cluster for policy violations
5. Kyverno begins generating reports and sending them to PostgreSQL

**How to verify it worked:**
```bash
# Check if Kyverno pods are running
kubectl get pods -n kyverno-system

# Check Kyverno logs
kubectl -n kyverno-system logs -l app=kyverno

# Check if Kyverno is working
kubectl get validatingwebhookconfigurations | grep kyverno
```

**Expected result:**
- Pods should show "Running" status
- Logs should show successful startup
- Webhook configurations should be present

**What to look for in the logs:**
- "Kyverno started" or similar startup messages
- No error messages about Reports Server connection
- Messages about policies being loaded
- Messages about webhook registration

**How Kyverno works with Reports Server:**
1. Kyverno monitors all applications in the cluster
2. When an application violates a security rule, Kyverno blocks it
3. Kyverno creates a report about the violation
4. Kyverno sends the report to Reports Server
5. Reports Server stores the report in PostgreSQL
6. You can view all reports through the API or dashboard

#### 6. Install Baseline Policies

**What we're doing:** Installing security rules that Kyverno will use to check your applications.

**Why we need this:** Without policies, Kyverno doesn't know what security rules to enforce. We're installing:
- **Pod Security Standards**: Industry-standard security rules for containers
- **Custom Test Policies**: Additional rules to test our setup

**Step 6a: Install Pod Security Standards**

```bash
# Install Pod Security Standards
kubectl apply -f https://raw.githubusercontent.com/kyverno/kyverno/main/config/samples/pod-security/pod-security-standards.yaml
```

**What this does:**
- Installs industry-standard security policies
- These policies check for common security issues like:
  - Running containers as root
  - Using privileged containers
  - Missing security contexts
  - Insecure volume mounts

**What Pod Security Standards include:**
- **Restricted**: Most secure (blocks many things)
- **Baseline**: Medium security (blocks common issues)
- **Privileged**: Least secure (allows most things)

**Step 6b: Install additional test policies**

```bash
# Install additional test policies
kubectl apply -f postgresql-testing/baseline-policies.yaml
```

**What this does:**
- Installs custom policies for testing our setup
- These policies are simpler and easier to understand
- They help us verify that the system is working correctly

**What the test policies check:**
- **require-labels**: Ensures all pods have an "app" label
- **disallow-privileged**: Prevents privileged containers from running

**How to verify policies are installed:**
```bash
# Check if policies are installed
kubectl get clusterpolicies

# Check policy details
kubectl get clusterpolicy require-labels -o yaml
kubectl get clusterpolicy disallow-privileged -o yaml
```

**Expected result:**
- You should see several policies listed
- Each policy should show "Ready" status
- Policies should have validation rules defined

**How policies work:**
1. When someone tries to create a pod, Kyverno checks it against all policies
2. If the pod violates a policy, Kyverno blocks it
3. Kyverno creates a report about the violation
4. The report is sent to Reports Server and stored in PostgreSQL
5. You can see all violations in the dashboard or API

**Testing the policies:**
```bash
# Test a good pod (should be allowed)
kubectl run test-pod --image=nginx:alpine --labels=app=test

# Test a bad pod (should be blocked)
kubectl run bad-pod --image=nginx:alpine --privileged
```

**What you should see:**
- Good pod: Created successfully
- Bad pod: Error message about policy violation

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
  eksctl delete cluster --name reports-server-test --region us-west-1
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

## 🔧 Troubleshooting

### **Common Issues and Solutions**

#### **1. Reports Server Database Connection Issues**

**Problem:** Reports Server shows connection errors to internal database instead of RDS.

**Symptoms:**
```
failed to ping dbdial tcp: lookup reports-server-postgresql.reports-server on 10.100.0.10:53: no such host
```

**Solution:**
1. **Check Helm parameters** - Ensure you're using the correct parameter path:
   ```bash
   --set config.db.host=$RDS_ENDPOINT  # NOT db.host
   --set config.db.port=5432
   --set config.db.name=$DB_NAME
   --set config.db.user=$DB_USERNAME
   --set config.db.password="$DB_PASSWORD"
   --set config.etcd.enabled=false
   --set config.postgresql.enabled=false
   ```

2. **Verify Reports Server version** - Use the correct Helm chart:
   ```bash
   helm repo add nirmata-reports-server https://nirmata.github.io/reports-server
   helm install reports-server nirmata-reports-server/reports-server --version 0.2.3
   ```

3. **Check pod environment variables:**
   ```bash
   kubectl describe pod -n reports-server -l app=reports-server | grep -A 10 "Environment:"
   ```

4. **Restart Reports Server pod if needed:**
   ```bash
   kubectl delete pod -n reports-server -l app=reports-server
   ```

#### **2. AWS SSO Credential Issues**

**Problem:** AWS commands fail with credential errors.

**Symptoms:**
```
InvalidGrantException: Invalid grant
failed to refresh cached credentials
```

**Solution:**
```bash
# Re-authenticate with AWS SSO
aws sso login --profile devtest-sso

# Verify credentials
aws sts get-caller-identity --profile devtest-sso
```

#### **3. Resource Creation Conflicts**

**Problem:** Resources already exist with the same name.

**Symptoms:**
```
AlreadyExistsException: Stack [eksctl-reports-server-test-cluster] already exists
DBInstanceAlreadyExists: DB instance already exists
```

**Solution:**
1. **Use the improved scripts** - They now include timestamps to prevent conflicts
2. **Clean up existing resources first:**
   ```bash
   ./phase1-cleanup.sh
   ```
3. **Check for lingering resources:**
   ```bash
   eksctl get cluster --region us-west-1 --profile devtest-sso
   aws rds describe-db-instances --profile devtest-sso
   ```

#### **4. EKS Cluster Creation Timeouts**

**Problem:** EKS cluster creation takes too long or fails.

**Symptoms:**
```
context deadline exceeded
timed out waiting for the condition
```

**Solution:**
1. **Use the improved timeout handling** - Scripts now have better timeout management
2. **Check AWS service limits** - Ensure you haven't hit EKS cluster limits
3. **Verify VPC configuration** - Ensure subnets are properly configured
4. **Monitor CloudFormation events** in AWS console for specific errors

#### **5. RDS Creation Failures**

**Problem:** RDS instance creation fails.

**Symptoms:**
```
InvalidParameterValue: Cannot find version 14.10 for postgres
InvalidParameterCombination: Some input subnets are invalid
```

**Solution:**
1. **Use supported PostgreSQL version:**
   ```bash
   --engine-version 14.12  # Check available versions
   ```
2. **Verify subnet configuration:**
   ```bash
   aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID"
   ```
3. **Check RDS service limits** in your AWS account

#### **6. Helm Installation Failures**

**Problem:** Helm charts fail to install or timeout.

**Symptoms:**
```
INSTALLATION FAILED: context deadline exceeded
cannot re-use a name that is still in use
```

**Solution:**
1. **Clean up failed releases:**
   ```bash
   helm list --all-namespaces
   helm uninstall <release-name> -n <namespace>
   ```
2. **Use the improved retry logic** - Scripts now retry failed installations
3. **Check cluster resources:**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

#### **7. Namespace Deletion Issues**

**Problem:** Namespaces get stuck in "Terminating" state.

**Symptoms:**
```
namespace "reports-server" is stuck in "Terminating" state
```

**Solution:**
1. **Use force deletion:**
   ```bash
   kubectl delete namespace <namespace> --force --grace-period=0
   ```
2. **Delete resources manually:**
   ```bash
   kubectl delete all --all -n <namespace>
   ```
3. **The improved cleanup script** handles this automatically

#### **8. CloudFormation Stack Deletion Failures**

**Problem:** CloudFormation stacks get stuck in DELETE_FAILED state.

**Symptoms:**
```
Stack status: DELETE_FAILED
Cannot delete VPC: dependencies exist
```

**Solution:**
1. **Use AWS Console method** (recommended):
   - Go to CloudFormation console
   - Select the failed stack
   - Choose "Delete this stack but retain resources"
   - Uncheck VPC to delete it with the stack

2. **Manual dependency resolution** (if console method fails):
   ```bash
   # Find VPC ID from stack
   VPC_ID=$(aws cloudformation describe-stack-resources --stack-name <stack-name> --query 'StackResources[?ResourceType==`AWS::EC2::VPC`].PhysicalResourceId' --output text)
   
   # Find security groups in VPC
   aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID"
   
   # Remove security group references
   aws ec2 revoke-security-group-ingress --group-id <default-sg> --source-group <eks-sg>
   
   # Delete security groups
   aws ec2 delete-security-group --group-id <eks-sg>
   
   # Delete VPC
   aws ec2 delete-vpc --vpc-id $VPC_ID
   ```

3. **Enhanced deletion sequence:**
   ```bash
   # Delete RDS first (independent resource)
   aws rds delete-db-instance --db-instance-identifier <name> --skip-final-snapshot
   
   # Delete EKS via AWS CLI (bypasses pod draining)
   aws eks delete-cluster --name <cluster-name>
   
   # Delete subnet group last
   aws rds delete-db-subnet-group --db-subnet-group-name <name>
   ```

#### **9. Monitoring and Logs**

**Useful commands for debugging:**

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -A

# Check Reports Server logs
kubectl logs -n reports-server -l app=reports-server

# Check Kyverno logs
kubectl logs -n kyverno-system -l app=kyverno

# Check RDS status
aws rds describe-db-instances --db-instance-identifier <name>

# Check EKS cluster status
eksctl get cluster --name <name> --region us-west-1
```

#### **10. Performance Issues**

**Problem:** System is slow or unresponsive.

**Solutions:**
1. **Check resource usage:**
   ```bash
   kubectl top nodes
   kubectl top pods -A
   ```
2. **Monitor RDS performance:**
   - Check CloudWatch metrics
   - Verify instance size is adequate
3. **Check network connectivity:**
   ```bash
   kubectl exec -it <pod-name> -n <namespace> -- ping <rds-endpoint>
   ```

### **Getting Help**

If you encounter issues not covered here:

1. **Check the logs** using the monitoring commands above
2. **Review AWS CloudFormation events** in the AWS console
3. **Check AWS service health** dashboard
4. **Verify your AWS account limits** and quotas
5. **Ensure you're using the latest script versions** with improvements

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

## 🧹 Enhanced Cleanup Procedures

### **Phase 1 Cleanup (Enhanced)**
```bash
./phase1-cleanup.sh
```

**Key Improvements:**
- **Smart resource naming** with timestamps to prevent conflicts
- **Correct deletion sequence** (RDS → EKS → Subnet Group)
- **AWS CLI for EKS deletion** (bypasses pod draining issues)
- **Force namespace deletion** for stuck Kubernetes resources
- **Comprehensive resource verification** and status reporting
- **Manual cleanup guidance** for CloudFormation stacks
- **Enhanced error handling** with retry logic and progress indicators

### **Phase 2 & 3 Cleanup**
```bash
./cleanup-load-test.sh
```

### **🚨 Critical: Lessons Learned from Resource Deletion**

**If the automated cleanup script fails, use this manual sequence:**

```bash
# 1. Delete RDS instance first (independent resource)
aws rds delete-db-instance \
  --db-instance-identifier reports-server-db-v2 \
  --skip-final-snapshot \
  --profile devtest-sso

# 2. Delete EKS cluster via AWS CLI (bypasses pod draining issues)
aws eks delete-cluster --name reports-server-test-v2 --profile devtest-sso

# 3. Wait for RDS deletion to complete, then delete subnet group
aws rds delete-db-subnet-group \
  --db-subnet-group-name reports-server-subnet-group-v2 \
  --profile devtest-sso

# 4. Check status of all resources
eksctl get cluster --region us-west-1 --profile devtest-sso
aws rds describe-db-instances --profile devtest-sso
aws cloudformation describe-stacks --profile devtest-sso
```

**Why this sequence matters:**
- **RDS first:** Independent resource, can be deleted immediately
- **EKS via AWS CLI:** Avoids eksctl's pod draining issues that can cause timeouts
- **Subnet group last:** Must wait for RDS deletion to complete
- **CloudFormation stacks:** Deleted automatically when EKS cluster is removed

**Common Issues:**
- **eksctl timeout:** Use `aws eks delete-cluster` instead
- **Pod eviction failures:** AWS CLI deletion bypasses this
- **Subnet group dependency:** Wait for RDS deletion before deleting subnet group

### 🖥️ AWS CloudFormation UI Method (Recommended)

**For DELETE_FAILED stacks, use the AWS Console:**

1. **Go to CloudFormation Console**
   - Navigate to: https://console.aws.amazon.com/cloudformation/
   - Select region: **us-west-1**

2. **Find the Failed Stack**
   - Change filter from "Active" to "All" or "Failed"
   - Select the stack with `DELETE_FAILED` status

3. **Use "Retry deleting this stack" Option**
   - Click **Delete** button
   - Choose **"Delete this stack but retain resources"** (recommended)
   - **Uncheck** the VPC checkbox to delete it with the stack
   - Click **Delete**

**Why this is better:**
- **No manual VPC deletion needed** - AWS handles it automatically
- **Safer than manual deletion** - AWS manages dependencies
- **Faster cleanup** - One-click solution
- **Handles complex dependencies** - AWS knows the resource relationships

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
