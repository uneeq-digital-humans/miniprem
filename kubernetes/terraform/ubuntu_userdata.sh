#!/bin/bash

# Ubuntu EKS node bootstrap script with manual kubelet configuration
# Ubuntu EKS AMIs do not include /etc/eks/bootstrap.sh - manual configuration required

set -o xtrace
set -e  # Exit on error

# Enhanced logging
exec > >(tee -a /var/log/bootstrap.log)
exec 2>&1

echo "=== Ubuntu EKS Bootstrap Started: $(date) ==="

# Variables from Terraform
CLUSTER_NAME="${cluster_name}"
CLUSTER_ENDPOINT="${cluster_endpoint}"
CLUSTER_CA="${cluster_ca}"
NODE_LABELS="${node_labels}"

# Get AWS region
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Update system packages
apt-get update -y

# Install required packages including systemd-resolved
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    unzip \
    jq \
    build-essential \
    systemd-resolved \
    awscli

# Install AWS CLI v2 (required for EKS token authentication)  
# Skip if already installed from apt package
if ! command -v aws &> /dev/null || [[ $(aws --version) != *"aws-cli/2"* ]]; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf awscliv2.zip aws/
fi

# Skip NVIDIA driver installation at boot time for fast cluster join
# GPU drivers will be installed via NVIDIA GPU Operator after cluster join
echo "Skipping NVIDIA driver installation - GPU Operator will handle this later"

# Install Kubernetes packages (kubelet, kubectl)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update -y

# Remove conflicting CNI packages first to avoid kubernetes-cni installation conflicts
apt-get remove -y cnitool-plugins || true

apt-get install -y kubelet kubectl kubernetes-cni
apt-mark hold kubelet kubectl

# Get VPC information and calculate cluster DNS IP
# Note: Using template substitution for these complex commands to avoid escaping issues
VPC_ID=$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/)/vpc-id)
VPC_CIDR=$(aws ec2 describe-vpcs --region $REGION --vpc-ids $VPC_ID --query 'Vpcs[0].CidrBlock' --output text)

# Use cluster DNS from service CIDR (calculated by Terraform)
CLUSTER_DNS="${cluster_dns_ip}"

echo "VPC CIDR: $VPC_CIDR, Cluster DNS: $CLUSTER_DNS"
echo "Configuring kubelet for EKS cluster: $CLUSTER_NAME"

# Create kubelet configuration directory
mkdir -p /etc/kubernetes/kubelet
mkdir -p /var/lib/kubelet/pki
mkdir -p /opt/cni/bin

# Create cluster CA certificate file
echo "$CLUSTER_CA" | base64 -d > /etc/kubernetes/ca.crt

# Configure containerd for EKS (GPU Operator will add NVIDIA runtime later)
mkdir -p /etc/containerd
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
default_runtime_name = "runc"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
runtime_type = "io.containerd.runc.v2"

[plugins."io.containerd.grpc.v1.cri".cni]
bin_dir = "/opt/cni/bin"
conf_dir = "/etc/cni/net.d"
EOF

# Start and enable containerd
systemctl enable containerd
systemctl restart containerd

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
  "clusterDNS": ["$CLUSTER_DNS"],
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

# Start and enable kubelet with status checks
echo "=== Starting kubelet service ==="
systemctl daemon-reload
systemctl enable kubelet

# Start kubelet and verify it's running
systemctl start kubelet

# Wait a bit and check status
sleep 5
if systemctl is-active --quiet kubelet; then
    echo "✅ Kubelet is running successfully"
    systemctl status kubelet --no-pager -l
else
    echo "❌ Kubelet failed to start"
    systemctl status kubelet --no-pager -l
    journalctl -u kubelet --no-pager -l --since "5 minutes ago"
    exit 1
fi

# Test AWS CLI authentication
echo "=== Testing AWS authentication ==="
if aws sts get-caller-identity > /dev/null; then
    echo "✅ AWS authentication working"
else
    echo "❌ AWS authentication failed"
    exit 1
fi

echo "=== Ubuntu EKS Bootstrap Completed: $(date) ==="
echo "✅ Node should now join cluster within 2-3 minutes"
echo "GPU drivers will be installed via NVIDIA GPU Operator after deployment"