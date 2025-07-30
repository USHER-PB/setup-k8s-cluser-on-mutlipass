#!/bin/sh

# This is the main orchestration script to set up a Kubernetes cluster
# using Multipass VMs on your host machine.
# This version is POSIX sh compliant and includes all discussed fixes.

# --- GLOBAL SETTINGS ---
K8S_VERSION="v1.28" # Specify the Kubernetes version for the repository

# --- SCRIPT START ---
echo "--- Starting Kubernetes Cluster Setup Orchestration ---"

# 1. Detect architecture and OS (for informational purposes)
ARCH=$(uname -m)
OS=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')

echo "[INFO] Host Architecture: $ARCH"
echo "[INFO] Host Operating System: $OS"

# 2. Smartly Launch/Start Multipass VMs
echo "[STEP 1/7] Checking/Launching/Starting Multipass VMs..."

# Define VM configurations as a space-separated string (no arrays in sh)
# We will loop through these strings and parse them.
# The `\ ` at the end of lines escapes the newline, making it one logical string.
VM_CONFIG_STRINGS="k8s-master 2 3GB 20GB \
k8s-worker-1 2 2GB 10GB \
k8s-worker-2 2 2GB 10GB"

# Use 'set --' to parse the string into positional parameters for a loop
# This is a common sh-compatible way to iterate over structured data.
set -- $VM_CONFIG_STRINGS

# Loop through each set of config parameters
while [ "$#" -gt 0 ]; do
    VM_NAME="$1"
    CPUS="$2"
    MEM="$3"
    DISK="$4"
    shift 4 # Move to the next set of 4 parameters

    echo "--- Checking VM: $VM_NAME ---"
    # Get the current state of the VM
    # We check if the VM info is non-empty, and then parse the state.
    VM_INFO=$(multipass info "$VM_NAME" --format json 2>/dev/null)
    VM_STATUS=""
    if [ -n "$VM_INFO" ]; then
        # Use grep and cut for sh-compatible JSON parsing for a single field
        VM_STATUS=$(echo "$VM_INFO" | grep -o '"state": "[^"]*"' | head -1 | cut -d'"' -f4)
    fi

    # --- Refactored VM status check using if-elif-else ---
    if [ "$VM_STATUS" = "Running" ]; then
        echo "[INFO] VM '$VM_NAME' already running. Skipping launch."
    elif [ "$VM_STATUS" = "Stopped" ]; then
        echo "[INFO] VM '$VM_NAME' found but stopped. Starting it..."
        multipass start "$VM_NAME" || { echo "ERROR: Failed to start $VM_NAME. Exiting."; exit 1; }
    elif [ -z "$VM_STATUS" ]; then # VM_STATUS is empty, meaning VM does not exist or info failed
        echo "[INFO] VM '$VM_NAME' does not exist. Launching..."
        multipass launch --name "$VM_NAME" --cpus "$CPUS" --memory "$MEM" --disk "$DISK" 22.04 || { echo "ERROR: Failed to launch $VM_NAME. Exiting."; exit 1; }
    else
        # Handle any other unexpected states
        echo "ERROR: Unexpected status for VM '$VM_NAME': $VM_STATUS. Exiting."
        exit 1
    fi
    # --- End of if-elif-else refactor ---

    echo "--- Status check for $VM_NAME complete ---"
done
echo "[INFO] All VMs are launched or running."

# 3. Transfer common setup script to all VMs and execute
echo "[STEP 2/7] Transferring and executing common setup script on all VMs..."

# Transfer the common setup script to each VM
for VM in k8s-master k8s-worker-1 k8s-worker-2; do
    echo "--- Transferring 00-common-node-setup.sh to $VM ---"
    multipass transfer 00-common-node-setup.sh "$VM":/home/ubuntu/00-common-node-setup.sh || { echo "ERROR: Failed to transfer common setup script to $VM. Exiting."; exit 1; }
    multipass exec "$VM" -- chmod +x /home/ubuntu/00-common-node-setup.sh || { echo "ERROR: Failed to make common setup script executable on $VM. Exiting."; exit 1; }
    echo "--- Executing 00-common-node-setup.sh on $VM ---"
    # Execute the common setup script on the VM, explicitly exporting K8S_VERSION
    multipass exec "$VM" -- sh -c "export K8S_VERSION=\"${K8S_VERSION}\" && /home/ubuntu/00-common-node-setup.sh" || { echo "ERROR: Common setup failed on $VM. Exiting."; exit 1; }
    echo "--- Finished common setup for $VM ---"
done
echo "[INFO] Common configuration applied to all VMs."

# 4. Transfer and execute master-specific setup script
echo "[STEP 3/7] Transferring and executing master-specific setup script on k8s-master..."
multipass transfer 01-master-node-specific.sh k8s-master:/home/ubuntu/01-master-node-specific.sh || { echo "ERROR: Failed to transfer master setup script. Exiting."; exit 1; }
multipass exec k8s-master -- chmod +x /home/ubuntu/01-master-node-specific.sh || { echo "ERROR: Failed to make master setup script executable. Exiting."; exit 1; }
# Execute using 'sh -c' for POSIX compliance
multipass exec k8s-master -- sh -c "/home/ubuntu/01-master-node-specific.sh" || { echo "ERROR: Master setup failed. Exiting."; exit 1; }
echo "[INFO] Kubernetes Control Plane initialized on k8s-master."

# 5. Copy the Kubeadm Join Command from Master to Host
echo "[STEP 4/7] Copying kubeadm join command to host..."
multipass transfer k8s-master:/tmp/kubeadm_join_command.sh . || { echo "ERROR: Failed to transfer join command. Exiting."; exit 1; }
chmod +x kubeadm_join_command.sh
echo "[INFO] kubeadm_join_command.sh copied to host and made executable."

# 6. Transfer kubeadm join command to workers and execute worker-specific setup script
echo "[STEP 5/7] Joining worker nodes to the cluster..."
for WORKER_VM in k8s-worker-1 k8s-worker-2; do
    echo "--- Transferring kubeadm_join_command.sh to $WORKER_VM ---"
    multipass transfer kubeadm_join_command.sh "$WORKER_VM":/home/ubuntu/kubeadm_join_command.sh || { echo "ERROR: Failed to transfer join command to $WORKER_VM. Exiting."; exit 1; }
    multipass exec "$WORKER_VM" -- chmod +x /home/ubuntu/kubeadm_join_command.sh || { echo "ERROR: Failed to make join command executable on $WORKER_VM. Exiting."; exit 1; }

    echo "--- Executing 02-worker-node-specific.sh on $WORKER_VM ---"
    multipass transfer 02-worker-node-specific.sh "$WORKER_VM":/home/ubuntu/02-worker-node-specific.sh || { echo "ERROR: Failed to transfer worker setup script to $WORKER_VM. Exiting."; exit 1; }
    multipass exec "$WORKER_VM" -- chmod +x /home/ubuntu/02-worker-node-specific.sh || { echo "ERROR: Failed to make worker setup script executable on $WORKER_VM. Exiting."; exit 1; }
    # Execute using 'sh -c' for POSIX compliance
    multipass exec "$WORKER_VM" -- sh -c "/home/ubuntu/02-worker-node-specific.sh" || { echo "ERROR: Worker setup failed on $WORKER_VM. Exiting."; exit 1; }
    echo "--- Finished joining $WORKER_VM ---"
done
echo "[INFO] All worker nodes joined successfully."

# 7. Configure kubectl on the Host Machine
echo "[STEP 6/7] Configuring kubectl on the host machine..."

# --- INTEGRATED FIX: Forcefully remove existing .kube directory and then recreate it ---
# WARNING: This will DELETE any existing Kubernetes configurations in ~/.kube/ on your host.
# Ensure you have backed them up if they are important!
echo "[INFO] Forcefully cleaning up old ~/.kube/ directory on host..."
sudo rm -rf "$HOME/.kube" || { echo "WARNING: Failed to forcefully remove old ~/.kube/. Continuing, but permissions might still be an issue."; }
# End of integrated fix

# Ensure .kube directory exists on host (recreated after potential deletion)
mkdir -p "$HOME/.kube"
# Ensure the .kube directory and its contents are owned by the current user
# and have appropriate permissions (read/write/execute for owner, nothing for others)
# This is crucial to avoid "Permission denied" errors when copying kubeconfig.
sudo chown -R "$(id -u):$(id -g)" "$HOME/.kube"
sudo chmod -R 700 "$HOME/.kube"

# --- NEW KUBECONFIG TRANSFER METHOD TO AVOID APPARMOR CONFINEMENT ---
echo "[INFO] Copying kubeconfig from master to host using a robust method..."
# Use multipass exec to cat the file from the VM and redirect its output to a local temp file
multipass exec k8s-master -- sudo cat /etc/kubernetes/admin.conf > /tmp/kubeconfig_temp.yaml || { echo "ERROR: Failed to read kubeconfig from master VM. Exiting."; exit 1; }

# Move the temporary file to the final destination with sudo (host-side operation, not confined by Multipass's AppArmor)
sudo mv /tmp/kubeconfig_temp.yaml "$HOME/.kube/config" || { echo "ERROR: Failed to move kubeconfig to final destination. Exiting."; exit 1; }

# Set final permissions for the config file (read/write for owner only)
chmod 600 "$HOME/.kube/config"
# --- END NEW KUBECONFIG TRANSFER METHOD ---

echo "[INFO] Kubeconfig copied to host. You can now use 'kubectl' from your host."

# Set KUBECONFIG environment variable for current session
export KUBECONFIG="$HOME/.kube/config"
echo "[INFO] KUBECONFIG environment variable set for current session."
echo "[INFO] To make KUBECONFIG persistent, add 'export KUBECONFIG=\$HOME/.kube/config' to your shell's profile (e.g., ~/.bashrc or ~/.zshrc)."

# 8. Verify Cluster Status
echo "[STEP 7/7] Verifying cluster status (may take a minute for nodes to become Ready)..."
for i in $(seq 1 10); do # Try up to 10 times (approx 50 seconds)
    READY_NODES=$(kubectl get nodes | grep " Ready" | wc -l)
    if [ "$READY_NODES" -eq 3 ]; then
        echo "[SUCCESS] All 3 nodes are Ready!"
        kubectl get nodes
        break
    else
        echo "[INFO] Waiting for all nodes to become Ready... ($READY_NODES/3 ready). Retrying in 5 seconds."
        sleep 5
    fi
    if [ "$i" -eq 10 ]; then
        echo "[ERROR] Timeout: Not all nodes became Ready within the expected time."
        kubectl get nodes
        exit 1
    fi
done

echo "--- Kubernetes Cluster Setup Complete ---"

