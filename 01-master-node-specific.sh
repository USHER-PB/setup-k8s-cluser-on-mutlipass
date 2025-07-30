#!/bin/sh

# This script performs setup steps specific to the Kubernetes Master node.
# It is designed to be executed inside the 'k8s-master' Multipass VM via 'multipass exec'.

echo "--- Starting master node specific setup ---"

# --- NEW ADDITION: Reset Kubernetes if it was previously initialized or failed ---
echo "[INFO] Running kubeadm reset to ensure a clean slate before initialization..."
# 'kubeadm reset --force' removes all previous Kubernetes state on the node.
# It's idempotent and won't fail if there's nothing to reset.
sudo kubeadm reset --force || { echo 'WARNING: kubeadm reset failed or encountered minor issues. Continuing, but manual check might be needed.'; }

# Also, explicitly remove old CNI configurations to prevent conflicts
sudo rm -rf /etc/cni/net.d/* || true

# Get the IP address of the master node for kubeadm init
# This command is run inside the VM, so hostname -I will give its internal IP
MASTER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$MASTER_IP" ]; then
    echo "ERROR: Could not determine master IP. Exiting."
    exit 1
fi

echo "[INFO] Initializing kubeadm control plane..."
# Initialize kubeadm with the Pod network CIDR (Flannel's default) and master's advertise address.
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=${MASTER_IP} || { echo 'ERROR: kubeadm init failed. Exiting.'; exit 1; }

echo "[INFO] Configuring kubectl for ubuntu user..."
# Configure kubectl for the default 'ubuntu' user on the master node.
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "[INFO] Deploying Flannel CNI (Container Network Interface)..."
# Deploy Flannel CNI for Pod networking. This must be deployed after kubeadm init.
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml || { echo 'ERROR: Flannel deployment failed. Exiting.'; exit 1; }

echo "[INFO] Generating kubeadm join command..."
# Generate the join command for worker nodes and save it to a temporary file.
# This file will be copied to the host, and then used by worker nodes.
sudo kubeadm token create --print-join-command > /tmp/kubeadm_join_command.sh || { echo 'ERROR: Failed to create join token. Exiting.'; exit 1; }

echo "--- Master node specific setup finished ---"