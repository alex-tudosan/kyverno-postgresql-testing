#!/bin/bash

echo "=== CREATING 200 DEPLOYMENTS WITH PROPER LABELS (FIXED) ==="

# Create deployments in batches to avoid overwhelming the system
for i in $(seq 1 200); do
    # Format with leading zeros for display, but use regular number for namespace
    formatted_i=$(printf "%03d" $i)
    echo "Creating deployment for namespace load-test-${formatted_i}"
    
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-deployment
  namespace: load-test-${formatted_i}
  labels:
    app: test-app
    version: v1.0
    owner: loadtest
    purpose: load-testing
spec:
  replicas: 0
  selector:
    matchLabels:
      app: test-app
      version: v1.0
  template:
    metadata:
      labels:
        app: test-app
        version: v1.0
        owner: loadtest
        purpose: load-testing
    spec:
      containers:
      - name: test-container
        image: nginx:alpine
        securityContext:
          privileged: false
          runAsNonRoot: true
          runAsUser: 1000
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
EOF

    # Add a small delay every 50 deployments to avoid overwhelming the API server
    if [ $((i % 50)) -eq 0 ]; then
        echo "Created $i deployments, pausing for 5 seconds..."
        sleep 5
    fi
done

echo "=== ALL 200 DEPLOYMENTS CREATED ==="
echo "Total objects for Kyverno processing: 800"
echo "- 200 namespaces"
echo "- 200 ServiceAccounts"
echo "- 400 ConfigMaps"
echo "- 200 Deployments"



