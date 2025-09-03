#!/bin/bash
# Create multiple compliant namespaces for load testing

echo "🚀 Creating 50 compliant namespaces for load testing..."

for i in $(seq -w 1 50); do
    cat > "load-test-${i}.yaml" << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: load-test-${i}
  labels:
    owner: test-user
    purpose: load-testing
    created-by: test-plan
    sequence: "${i}"
EOF
    
    echo "Created load-test-${i}.yaml"
done

echo "📝 Applying all namespace YAML files..."
for i in $(seq -w 1 50); do
    kubectl apply -f "load-test-${i}.yaml"
    echo "Applied load-test-${i}"
done

echo "🧹 Cleaning up YAML files..."
rm -f load-test-*.yaml

echo "✅ Done! Created 50 compliant namespaces."
echo "📊 Current namespace count:"
kubectl get ns | grep load-test | wc -l
