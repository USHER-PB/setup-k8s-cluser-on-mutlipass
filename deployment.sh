#!/bin/sh

echo "--- Starting Application Deployment ---"

# Define the Deployment YAML content
DEPLOYMENT_YAML=$(cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kubernetes-cluster-setup-presentation
  labels:
    app: kubernetes-cluster-setup-presentation # FIXED: Added space after 'app:'
spec:
  replicas: 1 # Desired number of Pod instances
  selector:
    matchLabels:
      app: kubernetes-cluster-setup-presentation
  template:
    metadata:
      labels:
        app: kubernetes-cluster-setup-presentation # Pods created by this Deployment will have this label
    spec:
      containers:
      - name: presentation
        image: ghcr.io/chojuninengu/kubernetes-cluster-setup:latest # FIXED: Added space after 'image:'
        ports:
        - containerPort: 8000 # FIXED: Changed to 8000 to match application's actual listening port
EOF
)

# Define the Service YAML content
SERVICE_YAML=$(cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-cluster-setup-presentation-service # FIXED: Added space after 'name:'
spec:
  selector:
    app: kubernetes-cluster-setup-presentation # FIXED: Service selector MUST match Deployment's Pod label
  type: NodePort
  ports:
    - protocol: TCP
      port: 80       # Port the Service listens on (internal to cluster)
      targetPort: 8000 # FIXED: Changed to 8000 to match application's actual listening port
      nodePort: 30090 # NodePort set to 30088
EOF
)

echo "[INFO] Creating Kubernetes YAML files..."
echo "${DEPLOYMENT_YAML}" > kubernetes_deployment.yaml || { echo "ERROR: Failed to create deployment YAML. Exiting."; exit 1; }
echo "${SERVICE_YAML}" > kubernetes_service.yaml || { echo "ERROR: Failed to create service YAML. Exiting."; exit 1; } # FIXED: Changed .yml to .yaml for consistency
echo "[INFO] YAML files 'kubernetes_deployment.yaml' and 'kubernetes_service.yaml' created."

echo "[INFO] Applying Deployment..."
kubectl apply -f kubernetes_deployment.yaml || { echo "ERROR: Failed to apply Deployment. Exiting."; exit 1; }
echo "[INFO] Deployment 'kubernetes-cluster-setup-presentation' applied successfully."

echo "[INFO] Applying Service..."
kubectl apply -f kubernetes_service.yaml || { echo "ERROR: Failed to apply Service. Exiting."; exit 1; } # FIXED: Changed .yml to .yaml
echo "[INFO] Service 'kubernetes-cluster-setup-presentation-service' applied successfully." # FIXED: Used actual Service name for clarity

echo "[INFO] Verifying Deployment status (waiting for Pods to be Ready)..."
for i in $(seq 1 20); do # Increased attempts for robustness
    READY_REPLICAS=$(kubectl get deployment kubernetes-cluster-setup-presentation -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    READY_REPLICAS=${READY_REPLICAS:-0} # Ensure READY_REPLICAS is 0 if jsonpath returns empty

    if [ "$READY_REPLICAS" -ge 1 ]; then # FIXED: Check for 1 replica as per Deployment spec (replicas: 1)
        echo "[SUCCESS] Deployment 'kubernetes-cluster-setup-presentation' is ready!"
        kubectl get deployments kubernetes-cluster-setup-presentation
        kubectl get pods -l app=kubernetes-cluster-setup-presentation -o wide # FIXED: Corrected label selector
        break
    else
        echo "[INFO] Waiting for Deployment to be ready... (${READY_REPLICAS}/1 replica ready). Retrying in 5 seconds." # FIXED: Info message
        sleep 5
    fi
    if [ "$i" -eq 20 ]; then # FIXED: Adjusted timeout limit
        echo "[ERROR] Timeout: Deployment 'kubernetes-cluster-setup-presentation' did not become ready within the expected time."
        kubectl get deployments kubernetes-cluster-setup-presentation
        kubectl get pods -l app=kubernetes-cluster-setup-presentation -o wide
        exit 1
    fi
done

echo "[INFO] Verifying Service status..."
kubectl get service kubernetes-cluster-setup-presentation-service || { echo "ERROR: Service 'kubernetes-cluster-setup-presentation-service' not found. Exiting."; exit 1; } # FIXED: Used actual Service name

echo "[INFO] Getting a Node IP to access the application..."
# Get the IP of the master node (any node can be used for NodePort access)
# Using 'multipass list' to get the IP for Multipass VMs
NODE_IP=$(multipass list | grep "^k8s-master" | awk '{print $3}' || true) # Added || true to prevent pipefail if grep finds nothing

if [ -z "$NODE_IP" ]; then
    echo "WARNING: Could not automatically retrieve Node IP. Please ensure 'k8s-master' VM is running and 'multipass list' works."
    echo "You can try accessing the app via: http://<NODE_IP>:30090"
else
    echo "[INFO] Application should be accessible via: http://${NODE_IP}:30090"
    echo "[INFO] Attempting to curl the application..."
    CURL_STATUS=0
    curl_output=$(curl -s -m 10 "http://${NODE_IP}:30090" || CURL_STATUS=$?)

    if [ "$CURL_STATUS" -eq 0 ]; then
        echo "[SUCCESS] Application responded correctly (connection established)!"
        echo "Response: ${curl_output}"
    else
        echo "WARNING: Could not reach the application or got an unexpected response (curl exit code: ${CURL_STATUS})."
        echo "Please verify firewall rules (if any on your host or VM), service status, and ensure the application inside the Pod is running and listening."
        echo "Manual curl attempt: curl http://${NODE_IP}:30090"
    fi
fi

echo "--- Application Deployment Complete ---"
