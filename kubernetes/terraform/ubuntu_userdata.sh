#!/bin/bash

# Ubuntu EKS node bootstrap script (matches working infra project)
# This script configures Ubuntu 22.04 instances to join an EKS cluster

set -o xtrace

# Variables from Terraform
CLUSTER_NAME="${cluster_name}"
CLUSTER_ENDPOINT="${cluster_endpoint}"
CLUSTER_CA="${cluster_ca}"
NODE_LABELS="${node_labels}"

# Update system packages
apt-get update -y
apt-get upgrade -y

# Install required packages
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    awscli \
    jq \
    build-essential \
    dkms \
    linux-headers-aws \
    linux-modules-extra-aws

# Install NVIDIA drivers (matches working infra: driver 570+)
curl -sS "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb" -o "/tmp/cuda-keyring.deb"
apt-get install -y --no-install-recommends /tmp/cuda-keyring.deb
apt-get update -y
apt-get install -y --no-install-recommends nvidia-driver-570 nvidia-container-toolkit

# Configure Docker daemon for EKS (containerd setup)
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
systemctl enable containerd
systemctl start containerd

# Install kubectl, kubelet, kubeadm
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Get AWS region
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Bootstrap the node to join EKS cluster (Ubuntu EKS AMIs have bootstrap script)
if [ -f /etc/eks/bootstrap.sh ]; then
    /etc/eks/bootstrap.sh \
        --apiserver-endpoint "$CLUSTER_ENDPOINT" \
        --b64-cluster-ca "$CLUSTER_CA" \
        --kubelet-extra-args "--node-labels=$NODE_LABELS" \
        "$CLUSTER_NAME"
else
    echo "Warning: /etc/eks/bootstrap.sh not found, manual kubelet config needed"
    # Manual kubelet configuration would go here if needed
fi

echo "Ubuntu EKS GPU node bootstrap completed successfully"