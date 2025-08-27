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
    unzip \
    jq \
    build-essential \
    dkms \
    linux-headers-aws \
    linux-modules-extra-aws

# Install AWS CLI v2 (required for EKS token authentication)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

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

# Get VPC information and calculate cluster DNS IP
VPC_ID=$$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/)/vpc-id)
VPC_CIDR=$$(aws ec2 describe-vpcs --region $$REGION --vpc-ids $$VPC_ID --query 'Vpcs[0].CidrBlock' --output text)

# Calculate cluster DNS IP (VPC base + 10)
# For example: 10.0.0.0/16 -> 10.0.0.10, 172.31.0.0/16 -> 172.31.0.10
VPC_BASE=$$(echo $$VPC_CIDR | cut -d'/' -f1 | cut -d'.' -f1-2)
CLUSTER_DNS="$${VPC_BASE}.0.10"

echo "VPC CIDR: $$VPC_CIDR, Cluster DNS: $$CLUSTER_DNS"

# Configure kubelet for EKS cluster (Ubuntu requires manual configuration)
echo "Configuring kubelet for EKS cluster: $CLUSTER_NAME"

# Create kubelet configuration directory
mkdir -p /etc/kubernetes/kubelet
mkdir -p /var/lib/kubelet
mkdir -p /opt/cni/bin

# Install AWS EKS CNI plugin
curl -L "https://github.com/aws/amazon-vpc-cni-k8s/releases/download/v1.15.4/aws-k8s-cni-v1.15.4.tar.gz" | tar -xz -C /opt/cni/bin/

# Create cluster CA certificate file
echo "$CLUSTER_CA" | base64 -d > /etc/kubernetes/ca.crt

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
PRIVATE_DNS=$(curl -s http://169.254.169.254/latest/meta-data/local-hostname)
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

# Create kubelet configuration
cat > /etc/kubernetes/kubelet/kubelet-config.json <<EOF
{
  "kind": "KubeletConfiguration",
  "apiVersion": "kubelet.config.k8s.io/v1beta1",
  "address": "0.0.0.0",
  "port": 10250,
  "readOnlyPort": 0,
  "authentication": {
    "anonymous": {
      "enabled": false
    },
    "webhook": {
      "enabled": true,
      "cacheTTL": "2m0s"
    },
    "x509": {
      "clientCAFile": "/etc/kubernetes/ca.crt"
    }
  },
  "authorization": {
    "mode": "Webhook",
    "webhook": {
      "cacheAuthorizedTTL": "5m0s",
      "cacheUnauthorizedTTL": "30s"
    }
  },
  "clusterDomain": "cluster.local",
  "clusterDNS": ["$$CLUSTER_DNS"],
  "resolvConf": "/run/systemd/resolve/resolv.conf",
  "runtimeRequestTimeout": "15m",
  "tlsCertFile": "/var/lib/kubelet/pki/kubelet.crt",
  "tlsPrivateKeyFile": "/var/lib/kubelet/pki/kubelet.key",
  "cgroupDriver": "systemd",
  "nodeStatusUpdateFrequency": "10s",
  "nodeStatusReportFrequency": "5m",
  "imageMinimumGCAge": "2m",
  "imageGCHighThresholdPercent": 85,
  "imageGCLowThresholdPercent": 80,
  "volumeStatsAggPeriod": "1m",
  "kubeletCgroups": "/systemd/system.slice",
  "systemCgroups": "/systemd/system.slice",
  "cgroupRoot": "/",
  "maxPods": 110,
  "staticPodPath": "/etc/kubernetes/manifests",
  "containerRuntimeEndpoint": "unix:///run/containerd/containerd.sock"
}
EOF

# Create kubelet service
cat > /etc/systemd/system/kubelet.service <<EOF
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=https://kubernetes.io/docs/home/
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/bin/kubelet \\
  --config=/etc/kubernetes/kubelet/kubelet-config.json \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --container-runtime-endpoint=unix:///run/containerd/containerd.sock \\
  --node-labels=$NODE_LABELS \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create kubeconfig for kubelet
cat > /var/lib/kubelet/kubeconfig <<EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority: /etc/kubernetes/ca.crt
    server: $CLUSTER_ENDPOINT
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: kubelet
  name: kubelet
current-context: kubelet
kind: Config
users:
- name: kubelet
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: /usr/local/bin/aws
      args:
        - --region
        - $REGION
        - eks
        - get-token
        - --cluster-name
        - $CLUSTER_NAME
EOF

# Configure containerd for EKS
cat > /etc/containerd/config.toml <<EOF
version = 2
root = "/var/lib/containerd"
state = "/run/containerd"
oom_score = 0

[grpc]
address = "/run/containerd/containerd.sock"
uid = 0
gid = 0

[plugins."io.containerd.grpc.v1.cri"]
enable_selinux = false
sandbox_image = "602401143452.dkr.ecr.$REGION.amazonaws.com/eks/pause:3.5"

[plugins."io.containerd.grpc.v1.cri".containerd]
snapshotter = "overlayfs"
default_runtime_name = "nvidia"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
runtime_type = "io.containerd.runc.v2"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
BinaryName = "/usr/bin/nvidia-container-runtime"

[plugins."io.containerd.grpc.v1.cri".cni]
bin_dir = "/opt/cni/bin"
conf_dir = "/etc/cni/net.d"
EOF

# Start and enable services
systemctl daemon-reload
systemctl restart containerd
systemctl enable kubelet
systemctl start kubelet

echo "Ubuntu EKS GPU node bootstrap completed successfully"