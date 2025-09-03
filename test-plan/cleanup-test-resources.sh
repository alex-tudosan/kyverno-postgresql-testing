#!/bin/bash
# Cleanup script for test resources created during Kyverno + PostgreSQL testing
# This script removes all test resources while preserving the core infrastructure

echo "🧹 Starting cleanup of test resources..."

# Cleanup test pods
echo "📦 Cleaning up test pods..."
kubectl get pods -A | grep test-pod | awk '{print $1 " " $2}' | while read namespace name; do
    echo "  Deleting pod $name in namespace $namespace"
    kubectl delete pod "$name" -n "$namespace" --ignore-not-found=true
done

# Cleanup test ConfigMaps
echo "🗂️  Cleaning up test ConfigMaps..."
kubectl get configmaps -A | grep -E "(test-configmap|load-test-cm)" | awk '{print $1 " " $2}' | while read namespace name; do
    echo "  Deleting ConfigMap $name in namespace $namespace"
    kubectl delete configmap "$name" -n "$namespace" --ignore-not-found=true
done

# Cleanup test ServiceAccounts
echo "👤 Cleaning up test ServiceAccounts..."
kubectl get serviceaccounts -A | grep -E "(test-sa|load-test-sa)" | awk '{print $1 " " $2}' | while read namespace name; do
    echo "  Deleting ServiceAccount $name in namespace $namespace"
    kubectl delete serviceaccount "$name" -n "$namespace" --ignore-not-found=true
done

# Cleanup test namespaces (optional - uncomment if you want to remove them)
# echo "🗂️  Cleaning up test namespaces..."
# kubectl get namespaces | grep load-test | awk '{print $1}' | while read namespace; do
#     echo "  Deleting namespace $namespace"
#     kubectl delete namespace "$namespace" --ignore-not-found=true
# done

echo "✅ Test resource cleanup completed!"
echo ""
echo "📊 Remaining resources:"
echo "  Pods: $(kubectl get pods -A | grep test-pod | wc -l)"
echo "  ConfigMaps: $(kubectl get configmaps -A | grep -E "(test-configmap|load-test-cm)" | wc -l)"
echo "  ServiceAccounts: $(kubectl get serviceaccounts -A | grep -E "(test-sa|load-test-sa)" | wc -l)"
echo ""
echo "💡 Note: Test namespaces are preserved by default."
echo "   To remove them, uncomment the namespace cleanup section in this script."
