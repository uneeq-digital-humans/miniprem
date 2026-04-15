# MiniPrem CNS Deployment Guide

## For Dell Technology Partners

This guide covers the complete installation, configuration, and management of UneeQ MiniPrem on NVIDIA Cloud Native Stack (CNS) deployments.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Configuration Reference](#configuration-reference)
5. [Making Changes](#making-changes)
6. [Scaling](#scaling)
7. [Monitoring & Troubleshooting](#monitoring--troubleshooting)
8. [Common Operations](#common-operations)

---

## Overview

### What is CNS?

NVIDIA Cloud Native Stack (CNS) is a reference architecture for deploying GPU-accelerated Kubernetes workloads on-premises. MiniPrem CNS deploys the UneeQ digital human platform (Renny) on your local NVIDIA GPU hardware.

### Installation Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| **Minimal** | Renny only, uses cloud TTS/LLM | Internet-connected deployments |
| **Full Stack** | Renny + local NIM LLM + Riva TTS | Air-gapped/low-latency deployments |

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Dell Server Hardware                        │
├─────────────────────────────────────────────────────────────────┤
│  NVIDIA GPU (RTX PRO 6000 / A100 / L4 / T4)                     │
├─────────────────────────────────────────────────────────────────┤
│  Ubuntu 22.04 + NVIDIA Driver 580.82.x                          │
├─────────────────────────────────────────────────────────────────┤
│  MicroK8s (Kubernetes)                                          │
│  ├── GPU Operator (time-slicing)                                │
│  ├── Renny Pods (1-6 replicas)                                  │
│  └── [Full Stack] NIM LLM + Riva TTS                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 8 cores | 16+ cores |
| RAM | 32 GB | 64+ GB |
| Storage | 100 GB SSD | 500+ GB NVMe |
| GPU | NVIDIA T4 (16GB) | RTX PRO 6000 (48GB) or A100 |

### GPU Capacity Reference

| GPU | VRAM | Web Mode | MiniPrem Mode |
|-----|------|----------|---------------|
| RTX PRO 6000 Blackwell | 48GB | 5 replicas | 3 replicas |
| A100 80GB | 80GB | 6 replicas | 4 replicas |
| A100 40GB | 40GB | 4 replicas | 2 replicas |
| L4 | 24GB | 3 replicas | 2 replicas |
| T4 | 16GB | 2 replicas | 1 replica |

> **Note:** Running a local LLM (Full Stack mode) reduces available Renny capacity by ~1 replica.

### Software Prerequisites (MUST be installed BEFORE running the script)

#### 1. NVIDIA Driver (Required)

The script does **NOT** install NVIDIA drivers. You must install the correct driver first.

**Recommended Driver: 580.82.x** (required for Renny video encoding)

```bash
# Check current driver
nvidia-smi

# For RTX PRO 6000 Blackwell - install from NVIDIA directly:
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/580.82.09/NVIDIA-Linux-x86_64-580.82.09.run
chmod +x NVIDIA-Linux-x86_64-580.82.09.run
sudo ./NVIDIA-Linux-x86_64-580.82.09.run --silent --dkms

# For other GPUs (A100, L4, T4) on Ubuntu:
sudo apt install nvidia-driver-580=580.82.07-0ubuntu1
sudo reboot
```

> **WARNING:** Driver version 580.126.x is **INCOMPATIBLE** with Renny. It breaks NVENC hardware encoding.

#### 2. Operating System

- Ubuntu 22.04 LTS (recommended)
- RHEL 8.7+ / Rocky Linux 8.7+

```bash
# Verify Ubuntu version
cat /etc/os-release
```

#### 3. Internet Connectivity

Required during installation to:
- Download container images from UneeQ registry
- Install MicroK8s and Helm charts
- (Optional) Pull NIM models from NVIDIA NGC

### What the Script DOES Install

The `deploy-local.sh` script automatically installs:

- MicroK8s (Kubernetes distribution)
- Helm 3 (package manager)
- NVIDIA GPU Operator
- GPU time-slicing configuration
- Xvfb (virtual display for headless rendering)
- Vulkan libraries
- Google Chrome (for kiosk interface)
- snapd (if not present)

---

## Installation

### Step 1: Clone the Repository

```bash
cd ~
git clone https://gitlab.com/tgmerritt/miniprem-2025.git
cd miniprem-2025
```

### Step 2: Verify Prerequisites

```bash
# Check NVIDIA driver
nvidia-smi

# Expected output should show:
# - Driver Version: 580.82.xx (NOT 580.126.xx)
# - GPU name and VRAM
```

### Step 3: Run the Installation Script

#### Interactive Mode (Recommended)

```bash
cd kubernetes/scripts/cns
sudo ./deploy-local.sh
```

The script will prompt you for:

1. **Installation Mode**: Minimal or Full Stack
2. **Quality Level**: MiniPrem (higher quality) or Web (more replicas)
3. **Replica Count**: Auto-recommended based on your GPU

#### Non-Interactive Mode (Automation)

```bash
sudo CNS_INSTALL_MODE=minimal \
     CNS_QUALITY_LEVEL=miniprem \
     RENNY_REPLICAS=3 \
     NGC_API_KEY="your-ngc-key" \
     ./deploy-local.sh
```

### Step 4: Verify Installation

```bash
# Check pod status
sudo microk8s kubectl get pods -n uneeq

# Expected output:
# NAME                        READY   STATUS    RESTARTS   AGE
# renderer-xxxxxxxxx-xxxxx    1/1     Running   0          5m
# renderer-xxxxxxxxx-xxxxx    1/1     Running   0          5m
# renderer-xxxxxxxxx-xxxxx    1/1     Running   0          5m

# Check GPU allocation
sudo microk8s kubectl describe nodes | grep -A5 "Allocated resources"
```

### Remote Installation (From Another Machine)

```bash
# SSH into the target server and run
ssh user@dell-server "cd ~/miniprem-2025/kubernetes/scripts/cns && sudo ./deploy-local.sh"
```

---

## Configuration Reference

### Values File Location

```
kubernetes/values/renny-values-cns.yaml
```

### Key Configuration Options

#### Deployment Settings

```yaml
deployment:
  nodeType: ""           # Leave empty for single-server deployments
  totalReplicas: 4       # Number of Renny instances

gpuTimeSlicing:
  enabled: true
  replicasPerGpu: 4      # How many Rennys share 1 GPU
```

| Setting | Description | Default |
|---------|-------------|---------|
| `deployment.totalReplicas` | Total Renny pods to run | 4 |
| `gpuTimeSlicing.replicasPerGpu` | GPU time-slices per physical GPU | 4 |

#### Renderer Settings

```yaml
renderer:
  qualityLevel: "miniprem"    # "miniprem" or "web"
  sdlAudioDriver: "dummy"     # Required for headless operation

  # Audio2Face (lip-sync)
  a2f:
    url: "http://localhost:52000"

  # Conversation Platform
  cp:
    flowiseUrl: "http://localhost:3000"
    flowiseApiKey: ""
```

| Setting | Description | Values |
|---------|-------------|--------|
| `renderer.qualityLevel` | Rendering quality | `miniprem` (higher quality), `web` (optimized) |
| `renderer.sdlAudioDriver` | Audio driver | `dummy` (headless), `pulse` (with audio) |

#### TTS (Text-to-Speech) Settings

```yaml
renderer:
  tts:
    # ElevenLabs (cloud)
    elevenlabsApiKey: "sk_xxx..."
    elevenlabsModelId: "eleven_turbo_v2"

    # Azure Speech (cloud)
    azureRegion: ""
    azureSpeechKey: ""

    # NVIDIA Riva (local - Full Stack only)
    # rivaUrl: "localhost:50051"
    # rivaUseSsl: false
```

#### DHOP Connection (UneeQ Platform)

```yaml
renderer:
  dhop:
    apiKey: "your-dhop-api-key"
    tenantId: "your-tenant-id"
    url: "wss://api.enterprise.uneeq.io:443/signalling-service"
```

> **Important:** These credentials are provided by UneeQ. Do not change the URL unless instructed.

#### Resource Limits

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
    memory: "8Gi"
    cpu: "4000m"
  requests:
    nvidia.com/gpu: 1
    memory: "8Gi"
    cpu: "4000m"
```

#### Local LLM (Full Stack Mode)

```yaml
nim:
  enabled: true
  endpoint: "http://localhost:8000/v1"
  model: "meta/llama-3.1-8b-instruct"
```

#### Telemetry

```yaml
telemetry:
  enabled: true
  backendUrl: "https://renny.services.uneeq.io"
  platform: "cns"
```

---

## Making Changes

### Editing Configuration

1. Edit the values file:
```bash
nano ~/miniprem-2025/kubernetes/values/renny-values-cns.yaml
```

2. Apply changes:
```bash
cd ~/miniprem-2025/kubernetes/scripts/cns
sudo ./cns-update.sh
```

### Quick Commands

```bash
# Apply config changes
sudo ./cns-update.sh

# Scale to specific replica count
sudo ./cns-update.sh --replicas 5

# Just restart pods (no config change)
sudo ./cns-update.sh --restart
```

### Manual Helm Upgrade

```bash
sudo microk8s helm3 upgrade renny ../../renny \
  --namespace uneeq \
  --values ../../values/renny-values-cns.yaml \
  --wait

sudo microk8s kubectl rollout restart deployment/renderer -n uneeq
```

---

## Scaling

### Change Replica Count

```bash
# Using the update script
sudo ./cns-update.sh --replicas 5

# Or edit values file and apply
# Edit: deployment.totalReplicas: 5
sudo ./cns-update.sh
```

### GPU Time-Slicing Adjustment

If you change the number of replicas significantly, also update the time-slicing config:

```yaml
gpuTimeSlicing:
  replicasPerGpu: 5  # Should match or exceed totalReplicas / GPU count
```

---

## Monitoring & Troubleshooting

### Check Pod Status

```bash
# All pods in uneeq namespace
sudo microk8s kubectl get pods -n uneeq

# Watch pods in real-time
sudo microk8s kubectl get pods -n uneeq -w

# Detailed pod info
sudo microk8s kubectl describe pod <pod-name> -n uneeq
```

### View Logs

```bash
# Follow Renny logs
sudo microk8s kubectl logs -f deployment/renderer -n uneeq

# Logs from specific pod
sudo microk8s kubectl logs <pod-name> -n uneeq

# Previous container logs (after crash)
sudo microk8s kubectl logs <pod-name> -n uneeq --previous
```

### Check GPU Status

```bash
# GPU utilization
nvidia-smi

# GPU resources in Kubernetes
sudo microk8s kubectl describe nodes | grep -A10 "nvidia.com/gpu"

# Time-slicing status
sudo microk8s kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}'
```

### Common Issues

#### Pods Stuck in Pending

```bash
# Check events
sudo microk8s kubectl describe pod <pod-name> -n uneeq | tail -20

# Common causes:
# - Not enough GPU resources (reduce replicas)
# - Node selector mismatch (check node labels)
```

**Fix:**
```bash
# Label nodes for scheduling
sudo microk8s kubectl label node $(hostname) uneeq.io/node-type= --overwrite
```

#### Pods Stuck in ContainerCreating

```bash
# Check for secret/volume issues
sudo microk8s kubectl describe pod <pod-name> -n uneeq | grep -A5 "Events"
```

**Fix:**
```bash
# Recreate secrets
sudo microk8s kubectl delete secret renderer -n uneeq
sudo ./cns-update.sh
```

#### Renny Crash with SIGSEGV

Usually audio driver issue. Ensure:
```yaml
renderer:
  sdlAudioDriver: "dummy"
```

#### Video Encoding Errors

Check NVIDIA driver version:
```bash
nvidia-smi | grep "Driver Version"
# Must be 580.82.x, NOT 580.126.x
```

---

## Common Operations

### Restart All Renny Pods

```bash
sudo microk8s kubectl rollout restart deployment/renderer -n uneeq
```

### Stop All Renny Pods

```bash
sudo microk8s kubectl scale deployment/renderer -n uneeq --replicas=0
```

### Start Renny Pods

```bash
sudo microk8s kubectl scale deployment/renderer -n uneeq --replicas=4
```

### Complete Uninstall

```bash
# Remove Renny deployment
sudo microk8s helm3 uninstall renny -n uneeq

# Remove namespaces
sudo microk8s kubectl delete namespace uneeq

# (Optional) Remove MicroK8s entirely
sudo snap remove microk8s
```

### Update from Git

```bash
cd ~/miniprem-2025
git pull origin feature/cns-phoenix-support

# Apply any new changes
cd kubernetes/scripts/cns
sudo ./cns-update.sh
```

---

## Environment Variables Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `CNS_K8S_TYPE` | Kubernetes distribution | `microk8s` |
| `CNS_INSTALL_MODE` | Installation mode | (interactive) |
| `CNS_QUALITY_LEVEL` | Rendering quality | `miniprem` |
| `RENNY_REPLICAS` | Number of Renny pods | (auto-detected) |
| `NGC_API_KEY` | NVIDIA NGC API key | (prompted) |
| `GPU_TIMESLICE_REPLICAS` | Time-slices per GPU | 8 |

---

## Support

For issues with:
- **MiniPrem/Renny**: Contact UneeQ support
- **Dell Hardware**: Contact Dell support
- **NVIDIA Drivers/GPU Operator**: Refer to NVIDIA documentation

---

## Quick Reference Card

```bash
# Check status
sudo microk8s kubectl get pods -n uneeq

# View logs
sudo microk8s kubectl logs -f deployment/renderer -n uneeq

# Apply config changes
sudo ./cns-update.sh

# Scale replicas
sudo ./cns-update.sh --replicas 5

# Restart pods
sudo ./cns-update.sh --restart

# GPU status
nvidia-smi
```
