#!/bin/sh

# This script performs common setup steps required on ALL Kubernetes nodes (master and workers).
# It is designed to be executed inside a Multipass VM via 'multipass exec'.

echo "--- Starting common node setup ---"

# 1. Disable Swap
# Kubernetes (kubelet) requires swap to be disabled for predictable performance and resource management.
echo "[INFO] Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 2. Enable Kernel Modules for Kubernetes Networking
# 'overlay' for container image layering (OverlayFS).
# 'br_netfilter' for allowing iptables to filter bridged network traffic.
echo "[INFO] Loading kernel modules overlay and br_netfilter..."
sudo modprobe overlay
sudo modprobe br_netfilter

# 3. Add Kernel Parameters for Kubernetes Networking
# Crucial for kube-proxy and CNI plugins to manage network traffic correctly.
echo "[INFO] Setting kernel parameters for Kubernetes networking..."
sudo tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system # Apply the new sysctl settings immediately.

# 4. Install containerd (Container Runtime)
# Kubernetes needs a Container Runtime Interface (CRI) compatible runtime like containerd.
echo "[INFO] Installing containerd..."
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release

# --- FIX: Use the 'jammy' repository for Docker/Containerd ---
# Ubuntu 22.04 (Jammy Jellyfish) requires the 'jammy' repository for containerd.io to avoid libc6 dependency issues.
echo '[INFO] Fixing Docker/Containerd repository to use "jammy" branch.'
sudo rm -f /etc/apt/sources.list.d/docker.list # Remove old configs if any
sudo rm -f /etc/apt/keyrings/docker.gpg        # Remove old keys if any
sudo mkdir -p /etc/apt/keyrings                # Ensure keyring directory exists
# Download and dearmor Docker's GPG public key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
# Add Docker's APT repository pointing to 'jammy'
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install containerd.io
sudo apt update -y
sudo apt install -y containerd.io

# 5. Configure containerd to use systemd cgroup driver
# This is a critical requirement for Kubernetes for consistent resource management.
echo "[INFO] Configuring containerd to use systemd cgroup driver..."
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# 6. Install kubeadm, kubelet, kubectl (Kubernetes Tools)
# These are the essential tools to bootstrap, manage, and interact with your Kubernetes cluster.
echo "[INFO] Installing kubeadm, kubelet, kubectl..."
# --- IMPORTANT FIX FOR KUBERNETES REPOSITORY ---
# Kubernetes packages are now hosted on pkgs.k8s.io.
# K8S_VERSION will be passed from the main script.
sudo rm -f /etc/apt/sources.list.d/kubernetes.list # Remove old configs if any
sudo rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg # Remove old keys if any
# Download and dearmor Kubernetes GPG public key for specified version
curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
# Add Kubernetes APT repository for specified version
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

# Install kubeadm, kubelet, kubectl
sudo apt update -y
sudo apt install -y kubelet kubeadm kubectl
# Hold packages to prevent accidental upgrades that could break the cluster.
sudo apt-mark hold kubelet kubeadm kubectl

echo "--- Common node setup finished ---"
