# NVIDIA Cloud Native Stack (CNS) Deployment Scripts

This folder contains scripts for deploying MiniPrem on NVIDIA Cloud Native Stack (CNS), designed for on-premises GPU servers.

## Overview

CNS provides a complete platform for running GPU-accelerated Kubernetes workloads on NVIDIA hardware. These scripts automate the deployment of:

- **Kubernetes**: MicroK8s (recommended for single-node) or kubeadm
- **NVIDIA GPU Operator**: Manages GPU drivers and container runtime
- **GPU Time-Slicing**: Allows multiple Renny instances per GPU
- **MiniPrem Stack**: Renny, NIM Operator, Riva, and supporting services

## Scripts

| Script | Purpose |
|--------|---------|
| `deploy.sh` | Main router - delegates to local or remote deployment |
| `deploy-local.sh` | Installs CNS on the current machine |
| `deploy-remote.sh` | Deploys CNS to a remote server via SSH/Ansible |
| `destroy.sh` | Removes MiniPrem components (optionally purges K8s) |
| `scale.sh` | Scales Renny replica count |
| `status.sh` | Shows deployment status and health |

## Quick Start

### Local Installation

```bash
# From the kubernetes/scripts directory
./deploy.sh
# Select: 4) NVIDIA Cloud Native Stack (CNS)
# Select: 1) Local Install
# Select: 1) MicroK8s (recommended)
```

Or directly:

```bash
sudo CNS_K8S_TYPE=microk8s ./cns/deploy-local.sh
```

### Remote Deployment

```bash
# Set target server
export CNS_REMOTE_HOST=192.168.1.100
export CNS_REMOTE_USER=ubuntu
export CNS_SSH_KEY=~/.ssh/id_rsa

# Deploy
./deploy.sh
# Select: 4) NVIDIA Cloud Native Stack (CNS)
# Select: 2) Remote Deploy
```

Or directly:

```bash
CNS_REMOTE_HOST=192.168.1.100 ./cns/deploy-remote.sh
```

## Prerequisites

### Hardware Requirements

- NVIDIA GPU (datacenter GPUs recommended: A100, H100, L40, T4, etc.)
- 2+ CPU cores
- 8GB+ RAM (16GB+ recommended)
- 100GB+ storage

### Software Requirements

- Ubuntu 24.04 LTS
- Internet connectivity
- Sudo access

### For Remote Deployment

- SSH access to target server
- SSH key authentication configured
- (Optional) Ansible installed locally

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CNS_K8S_TYPE` | `microk8s` | Kubernetes distribution (`microk8s` or `kubeadm`) |
| `CNS_REMOTE_HOST` | - | Target server for remote deployment |
| `CNS_REMOTE_USER` | `ubuntu` | SSH username |
| `CNS_SSH_KEY` | `~/.ssh/id_rsa` | Path to SSH private key |
| `NGC_API_KEY` | - | NVIDIA NGC API key for model downloads |
| `PURGE_ALL` | `false` | Set to `true` to completely remove Kubernetes |

## NGC API Key

An NGC API key is required to download NVIDIA models (NIM, Riva, etc.):

1. Visit https://ngc.nvidia.com/
2. Sign in or create an account
3. Go to Setup > API Key
4. Generate and copy your API key
5. Set it before deployment:
   ```bash
   export NGC_API_KEY='your-api-key'
   ```

## GPU Time-Slicing

By default, GPU time-slicing is configured to allow 4 Renny instances per GPU. This can be adjusted in the time-slicing ConfigMap:

```bash
# View current config
kubectl get configmap time-slicing-config -n gpu-operator -o yaml

# Adjust replicas (default: 4)
kubectl edit configmap time-slicing-config -n gpu-operator
```

## Scaling

```bash
# Scale to 4 Renny instances
./scale.sh 4

# Check status
./status.sh
```

## Troubleshooting

### MicroK8s not starting

```bash
# Check status
microk8s status

# View logs
sudo journalctl -u snap.microk8s.daemon-kubelite -f
```

### GPU not detected

```bash
# Check NVIDIA driver
nvidia-smi

# Check GPU Operator pods
kubectl get pods -n gpu-operator

# Check GPU resources
kubectl describe node | grep nvidia
```

### Renny pods pending

```bash
# Check events
kubectl describe pod -n uneeq

# Check GPU availability
kubectl get nodes -o jsonpath='{.items[*].status.allocatable.nvidia\.com/gpu}'
```

## Related Documentation

- [NVIDIA Cloud Native Stack](https://github.com/NVIDIA/cloud-native-stack)
- [GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- [MicroK8s Documentation](https://microk8s.io/docs)
