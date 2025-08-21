#!/bin/bash

# Phase 1 Monitoring Script for PostgreSQL-based Reports Server Testing
# This script provides real-time monitoring of the system

set -e

echo "📊 Starting Phase 1 Monitoring: PostgreSQL-based Reports Server Testing"
echo "====================================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Load configuration if available
if [ -f "postgresql-testing-config.env" ]; then
    source postgresql-testing-config.env
fi

# Default values if config not available
RDS_INSTANCE_ID=${RDS_INSTANCE_ID:-"reports-server-db"}
REGION=${REGION:-"us-west-1"}
AWS_PROFILE=${AWS_PROFILE:-"devtest-sso"}

# Create monitoring log file
LOG_FILE="phase1-monitoring-$(date +%Y%m%d-%H%M%S).csv"
echo "Timestamp,Cluster_Status,Kyverno_Status,Reports_Server_Status,RDS_Status,Total_Pods,Policy_Reports,CPU_Usage,Memory_Usage,RDS_Connections,RDS_CPU,RDS_Memory" > $LOG_FILE

print_status "Monitoring log file: $LOG_FILE"
print_status "Press Ctrl+C to stop monitoring"
echo ""

# Function to get RDS metrics
get_rds_metrics() {
    local metric_name=$1
    local value=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/RDS \
        --metric-name $metric_name \
        --dimensions Name=DBInstanceIdentifier,Value=$RDS_INSTANCE_ID \
        --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
        --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
        --period 300 \
        --statistics Average \
        --query 'Datapoints[0].Average' \
        --output text \
        --profile $AWS_PROFILE 2>/dev/null || echo "N/A")
    echo $value
}

# Function to format bytes to human readable
format_bytes() {
    local bytes=$1
    if [ "$bytes" -gt 1073741824 ]; then
        echo "$(echo "scale=2; $bytes/1073741824" | bc)GB"
    elif [ "$bytes" -gt 1048576 ]; then
        echo "$(echo "scale=2; $bytes/1048576" | bc)MB"
    elif [ "$bytes" -gt 1024 ]; then
        echo "$(echo "scale=2; $bytes/1024" | bc)KB"
    else
        echo "${bytes}B"
    fi
}

# Function to format percentage
format_percentage() {
    local value=$1
    if [ "$value" != "N/A" ]; then
        echo "${value}%"
    else
        echo "N/A"
    fi
}

# Main monitoring loop
while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Cluster status
    CLUSTER_STATUS=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
    TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
    
    # Kyverno status
    KYVERNO_STATUS=$(kubectl -n kyverno-system get pods -l app=kyverno --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    
    # Reports Server status
    REPORTS_SERVER_STATUS=$(kubectl -n kyverno get pods -l app.kubernetes.io/component=reports-server --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    
    # RDS status
    RDS_STATUS=$(aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --query 'DBInstances[0].DBInstanceStatus' --output text --profile $AWS_PROFILE 2>/dev/null || echo "N/A")
    
    # Total pods
    TOTAL_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l || echo "0")
    
    # Policy reports count
    POLICY_REPORTS=$(kubectl get policyreports -A --no-headers 2>/dev/null | wc -l || echo "0")
    
    # Resource usage
    CPU_USAGE=$(kubectl top nodes --no-headers 2>/dev/null | awk '{sum+=$3} END {print sum+0}' || echo "0")
    MEMORY_USAGE=$(kubectl top nodes --no-headers 2>/dev/null | awk '{sum+=$5} END {print sum+0}' || echo "0")
    
    # RDS metrics
    RDS_CONNECTIONS=$(get_rds_metrics "DatabaseConnections")
    RDS_CPU=$(get_rds_metrics "CPUUtilization")
    RDS_MEMORY=$(get_rds_metrics "FreeableMemory")
    
    # Log to CSV
    echo "$TIMESTAMP,$CLUSTER_STATUS/$TOTAL_NODES,$KYVERNO_STATUS,$REPORTS_SERVER_STATUS,$RDS_STATUS,$TOTAL_PODS,$POLICY_REPORTS,$CPU_USAGE,$MEMORY_USAGE,$RDS_CONNECTIONS,$RDS_CPU,$RDS_MEMORY" >> $LOG_FILE
    
    # Clear screen and display current status
    clear
    echo "📊 Phase 1 Monitoring - PostgreSQL-based Reports Server Testing"
    echo "=============================================================="
    echo "Timestamp: $TIMESTAMP"
    echo "Log File: $LOG_FILE"
    echo ""
    
    # Cluster Status
    echo "🏗️  CLUSTER STATUS"
    echo "  Nodes: $CLUSTER_STATUS/$TOTAL_NODES Ready"
    if [ "$CLUSTER_STATUS" = "$TOTAL_NODES" ] && [ "$TOTAL_NODES" -gt 0 ]; then
        print_success "  Cluster is healthy"
    else
        print_error "  Cluster has issues"
    fi
    echo ""
    
    # Component Status
    echo "🔧 COMPONENT STATUS"
    echo "  Kyverno: $KYVERNO_STATUS Running"
    if [ "$KYVERNO_STATUS" -gt 0 ]; then
        print_success "  Kyverno is healthy"
    else
        print_error "  Kyverno has issues"
    fi
    
    echo "  Reports Server: $REPORTS_SERVER_STATUS Running"
    if [ "$REPORTS_SERVER_STATUS" -gt 0 ]; then
        print_success "  Reports Server is healthy"
    else
        print_error "  Reports Server has issues"
    fi
    
    echo "  RDS Status: $RDS_STATUS"
    if [ "$RDS_STATUS" = "available" ]; then
        print_success "  RDS is available"
    else
        print_error "  RDS has issues"
    fi
    echo ""
    
    # Workload Status
    echo "📦 WORKLOAD STATUS"
    echo "  Total Pods: $TOTAL_PODS"
    echo "  Policy Reports: $POLICY_REPORTS"
    echo ""
    
    # Resource Usage
    echo "💻 RESOURCE USAGE"
    echo "  CPU Usage: $(format_percentage $CPU_USAGE)"
    if [ "$CPU_USAGE" != "N/A" ] && [ "$CPU_USAGE" -gt 80 ]; then
        print_warning "  High CPU usage detected"
    fi
    
    echo "  Memory Usage: $(format_bytes $MEMORY_USAGE)"
    echo ""
    
    # RDS Metrics
    echo "🗄️  RDS METRICS"
    echo "  Connections: $RDS_CONNECTIONS"
    echo "  CPU Usage: $(format_percentage $RDS_CPU)"
    if [ "$RDS_CPU" != "N/A" ] && [ "$RDS_CPU" -gt 80 ]; then
        print_warning "  High RDS CPU usage detected"
    fi
    
    echo "  Free Memory: $(format_bytes $RDS_MEMORY)"
    echo ""
    
    # Quick Commands
    echo "🔧 QUICK COMMANDS"
    echo "  View logs: kubectl -n kyverno logs -l app.kubernetes.io/component=reports-server"
    echo "  Check RDS: aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_ID --profile $AWS_PROFILE"
    echo "  Grafana: kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80"
    echo ""
    
    # Alerts
    echo "🚨 ALERTS"
    if [ "$CLUSTER_STATUS" != "$TOTAL_NODES" ] && [ "$TOTAL_NODES" -gt 0 ]; then
        print_error "  Cluster nodes not ready"
    fi
    
    if [ "$KYVERNO_STATUS" -eq 0 ]; then
        print_error "  Kyverno not running"
    fi
    
    if [ "$REPORTS_SERVER_STATUS" -eq 0 ]; then
        print_error "  Reports Server not running"
    fi
    
    if [ "$RDS_STATUS" != "available" ]; then
        print_error "  RDS not available"
    fi
    
    if [ "$CPU_USAGE" != "N/A" ] && [ "$CPU_USAGE" -gt 90 ]; then
        print_warning "  Very high CPU usage"
    fi
    
    if [ "$RDS_CPU" != "N/A" ] && [ "$RDS_CPU" -gt 90 ]; then
        print_warning "  Very high RDS CPU usage"
    fi
    
    echo ""
    echo "Press Ctrl+C to stop monitoring..."
    
    # Wait 30 seconds before next update
    sleep 30
done
