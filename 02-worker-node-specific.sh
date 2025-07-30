#!/bin/sh

# This script performs setup steps specific to Kubernetes Worker nodes.
# It is designed to be executed inside a worker Multipass VM via 'multipass exec'.
# It expects the 'kubeadm_join_command.sh' file to be present in /home/ubuntu/.

echo "--- Starting worker node specific setup ---"

# --- NEW ADDITION: Reset Kubernetes if it was previously joined or failed ---
echo "[INFO] Running kubeadm reset to ensure a clean slate before joining..."
# 'kubeadm reset --force' removes all previous Kubernetes state on the node.
# It's idempotent and won't fail if there's nothing to reset.
sudo kubeadm reset --force || { echo 'WARNING: kubeadm reset failed or encountered minor issues. Continuing, but manual check might be needed.'; }

# Also, explicitly remove old CNI configurations to prevent conflicts
sudo rm -rf /etc/cni/net.d/* || true


# Check if the join command file exists
if [ ! -f "/home/ubuntu/kubeadm_join_command.sh" ]; then
    echo "ERROR: kubeadm_join_command.sh not found in /home/ubuntu/. Please ensure it was transferred."
    exit 1
fi

echo "[INFO] Joining node to the Kubernetes cluster..."
# Execute the kubeadm join command directly from the file.
# The 'main-cluster-setup.sh' script already ensures this file is executable.
sudo /home/ubuntu/kubeadm_join_command.sh || { echo 'ERROR: Failed to join cluster. Exiting.'; exit 1; }

echo "--- Worker node specific setup finished ---"