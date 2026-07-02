# NVIDIA Cloud Native Stack (CNS) Setup Guide

This guide covers deploying MiniPrem on NVIDIA Cloud Native Stack for on-premises GPU servers.

## Overview

NVIDIA Cloud Native Stack (CNS) provides a complete platform for running GPU-accelerated Kubernetes workloads on NVIDIA hardware. This is ideal for:

- On-premises deployments
- Air-gapped environments
- Dell/NVIDIA partnership deployments
- Single-server or small cluster setups

## Hardware Requirements

### Minimum Requirements

| Component | Requirement |
|-----------|-------------|
| CPU | 2+ cores |
| RAM | 8GB minimum, 16GB+ recommended |
| Storage | 100GB+ SSD |
| GPU | NVIDIA datacenter GPU (A100, H100, L40, T4, etc.) |
| Network | Internet access for initial setup |

### Supported GPUs

- NVIDIA A100 (40GB/80GB)
- NVIDIA H100
- NVIDIA L40
- NVIDIA T4
- NVIDIA A10G
- DGX systems

## Software Requirements

### Operating System

- **Ubuntu 22.04 LTS** (recommended)
- **Ubuntu 24.04 LTS**
- **RHEL 8.7+** — CNS layer only; **not validated** for the digital-human appliance (use Ubuntu)

### Prerequisites

1. **Sudo access** on target server
2. **Internet connectivity** for package downloads
3. **NGC API Key** for NVIDIA model access

> **Note:** The deployment scripts will automatically install additional dependencies including:
> - `snapd` (required for MicroK8s)
> - `Google Chrome` (required for MiniPrem kiosk interface)
> - Common tools: `curl`, `wget`, `jq`, `git`

## Getting an NGC API Key

1. Visit [https://ngc.nvidia.com/](https://ngc.nvidia.com/)
2. Sign in or create an account
3. Go to **Setup** → **API Key**
4. Click **Generate API Key**
5. Copy and save your API key

## Deployment Options

### Option 1: Local Installation

Install CNS directly on the current machine:

```bash
# Navigate to kubernetes scripts
cd kubernetes/scripts

# Run deployment
./deploy.sh
# Select: 4) NVIDIA Cloud Native Stack (CNS)
# Select: 1) Local Install
# Select: 1) MicroK8s (recommended for single-node)

# Or run directly with environment variables
sudo NGC_API_KEY='your-api-key' CNS_K8S_TYPE=microk8s ./cns/deploy-local.sh
```

### Option 2: Remote Deployment

Deploy CNS to a remote server over SSH:

```bash
# Set target server
export CNS_REMOTE_HOST=192.168.1.100
export CNS_REMOTE_USER=ubuntu
export CNS_SSH_KEY=~/.ssh/id_rsa
export NGC_API_KEY='your-api-key'

# Run deployment
./deploy.sh
# Select: 4) NVIDIA Cloud Native Stack (CNS)
# Select: 2) Remote Deploy

# Or run directly
./cns/deploy-remote.sh
```

### Option 3: Ansible Deployment

For more control, use Ansible playbooks:

```bash
# Navigate to ansible directory
cd kubernetes/ansible

# Copy and configure inventory
cp inventory/hosts.yml.example inventory/hosts.yml
# Edit inventory/hosts.yml with your server details

# Set NGC API key
export NGC_API_KEY='your-api-key'

# Run installation playbook
ansible-playbook -i inventory/hosts.yml playbooks/cns-install.yml
```

## Kubernetes Distribution Options

### MicroK8s (Recommended for Single-Node)

**Pros:**
- Easy installation via snap
- Built-in NVIDIA GPU support
- Minimal configuration
- Good for single-server deployments

**Installation:**
```bash
CNS_K8S_TYPE=microk8s ./cns/deploy-local.sh
```

### kubeadm (For Multi-Node Clusters)

**Pros:**
- Standard Kubernetes installation
- More flexible networking options
- Better for multi-node clusters

**Installation:**
```bash
CNS_K8S_TYPE=kubeadm ./cns/deploy-local.sh
```

## GPU Time-Slicing Configuration

By default, GPU time-slicing is configured to allow 4 Renny instances per GPU:

```yaml
# Configured in gpu-timeslice ConfigMap
sharing:
  timeSlicing:
    resources:
      - name: nvidia.com/gpu
        replicas: 4  # 4 Renny instances per physical GPU
```

To modify:

```bash
# For MicroK8s
microk8s kubectl edit configmap time-slicing-config -n gpu-operator

# For kubeadm
kubectl edit configmap time-slicing-config -n gpu-operator
```

## Post-Deployment

### Verify Installation

```bash
# Check cluster status
./cns/status.sh

# Or manually
microk8s kubectl get nodes
microk8s kubectl get pods -A
```

### Access MiniPrem

- **MiniPrem Monitor**: http://localhost:3001
- **Phoenix UI** (if enabled): http://localhost:6006

### Scale Renny Instances

```bash
./cns/scale.sh 4  # Scale to 4 Renny instances
```

## Troubleshooting

### MicroK8s Not Starting

```bash
# Check status
microk8s status

# View logs
sudo journalctl -u snap.microk8s.daemon-kubelite -f

# Reset MicroK8s
microk8s reset
```

### GPU Not Detected

```bash
# Check NVIDIA driver
nvidia-smi

# Check GPU operator
microk8s kubectl get pods -n gpu-operator

# Check node GPU resources
microk8s kubectl describe node | grep nvidia
```

### Renny Pods Pending

```bash
# Check pod events
microk8s kubectl describe pod -n uneeq

# Check GPU availability
microk8s kubectl get nodes -o jsonpath='{.items[*].status.allocatable.nvidia\.com/gpu}'
```

### Network Issues

```bash
# Check DNS
microk8s kubectl run test --rm -it --image=busybox -- nslookup kubernetes.default

# Check services
microk8s kubectl get svc -A
```

## Uninstallation

### Remove MiniPrem Only

```bash
./cns/destroy.sh
```

### Complete Removal (Including Kubernetes)

```bash
PURGE_ALL=true ./cns/destroy.sh
```

## Related Documentation

- [NVIDIA Cloud Native Stack](https://github.com/NVIDIA/cloud-native-stack)
- [GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [MicroK8s Documentation](https://microk8s.io/docs)
- [Phoenix Setup](../docs/PHOENIX_SETUP.md)
- [Scripts README](./scripts/cns/README.md)
- [Ansible README](./ansible/README.md)
