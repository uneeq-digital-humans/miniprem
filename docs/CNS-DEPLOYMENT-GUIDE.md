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
│  Ubuntu 24.04 + NVIDIA Driver 580.82.x                          │
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
| GPU | NVIDIA T4 (16GB) | RTX PRO 6000 Blackwell (96GB) or A100 |

### GPU Capacity Reference

| GPU | VRAM | Web Mode* | MiniPrem Mode* |
|-----|------|-----------|----------------|
| RTX PRO 6000 Blackwell | 96GB | 10 replicas | 6 replicas |
| A100 80GB | 80GB | 8 replicas | 5 replicas |
| RTX 6000 Ada | 48GB | 5 replicas | 3 replicas |
| A100 40GB | 40GB | 4 replicas | 2 replicas |
| L4 / RTX 4090 | 24GB | 3 replicas | 2 replicas |
| T4 | 16GB | 2 replicas | 1 replica |

> **\* Quality Mode Selection:**
> - **Web Mode**: For standard/stock digital humans (UneeQ stock character maps)
> - **MiniPrem Mode**: For MiniPrem-specific character maps only
>
> Choose the quality mode that matches your character map type. See [Quality Level and Character Maps](#quality-level-and-character-maps-critical) for details.

> **Note:** Running a local LLM (Full Stack mode) reduces available Renny capacity by ~1 replica.

### Software Prerequisites (MUST be installed BEFORE running the script)

#### 1. NVIDIA Driver (Required)

The script does **NOT** install NVIDIA drivers. You must install the correct driver first.

**Recommended Driver: 580.82.x** (required for Renny video encoding)

> **See [NVIDIA-DRIVER-SETUP.md](./NVIDIA-DRIVER-SETUP.md) for detailed driver installation instructions, including Vulkan and Xvfb setup.**

Quick summary:

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

- Ubuntu 24.04 LTS

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
2. **DHOP Credentials**: API Key and Tenant ID (from UneeQ)
3. **Quality Level**:
   - **Web**: For standard/stock digital humans (UneeQ stock character maps)
   - **MiniPrem**: For MiniPrem-specific character maps only
4. **Replica Count**: Auto-recommended based on your GPU and quality level

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
# NAME                     READY   STATUS    RESTARTS   AGE
# renny-xxxxxxxxx-xxxxx    1/1     Running   0          5m
# renny-xxxxxxxxx-xxxxx    1/1     Running   0          5m
# renny-xxxxxxxxx-xxxxx    1/1     Running   0          5m

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
| `renderer.qualityLevel` | Rendering quality | `miniprem` or `web` (see below) |
| `renderer.sdlAudioDriver` | Audio driver | `dummy` (headless), `pulse` (with audio) |

#### Quality Level and Character Maps (CRITICAL)

> **⚠️ IMPORTANT:** Quality level MUST match your character map type. Using the wrong quality level causes rendering issues.

| Quality Level | Use With | Description |
|--------------|----------|-------------|
| `web` | **Standard/Stock Digital Humans** | For UneeQ stock character maps |
| `miniprem` | **MiniPrem Character Maps ONLY** | For MiniPrem-specific character maps |

**How to Choose:**
- **Do you have MiniPrem-specific character maps?** → Use `miniprem` quality
- **Are you using UneeQ stock digital humans?** → Use `web` quality
- **Not sure?** → Use `web` quality (safer default)

**Rules:**
- **NEVER** use `qualityLevel: web` with a MiniPrem character map
- **NEVER** use `qualityLevel: miniprem` with a standard/stock digital human
- The quality level is a rendering setting in Renny - it does NOT change video resolution

#### Video Resolution Configuration

> **IMPORTANT:** Video resolution is configured via the **UneeQ Admin Portal**, NOT in this values file.

The `ResX` and `ResY` parameters in the Unreal Engine args (`1920x1080`) are for the **rendering surface**, not the final video output resolution.

**To change output resolution:**
1. Log into the UneeQ Admin Portal
2. Navigate to your Digital Human configuration
3. Adjust the video resolution settings there

The CNS deployment respects whatever resolution is configured in the Admin Portal.

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

sudo microk8s kubectl rollout restart deployment/renny -n uneeq
```

---

## Scaling

### Change Replica Count

```bash
# Recommended: Use miniprem.sh from project root
cd ~/miniprem-2025
sudo ./miniprem.sh upgrade --replicas 5

# Interactive scaling (with GPU detection)
sudo ./miniprem.sh scale

# Or edit values file and apply
# Edit: deployment.totalReplicas: 5
sudo ./miniprem.sh upgrade
```

### GPU Time-Slicing Adjustment

If you change the number of replicas significantly, also update the time-slicing config:

```yaml
gpuTimeSlicing:
  replicasPerGpu: 5  # Should match or exceed totalReplicas / GPU count
```

### Sizer Tool: Plan vs. Apply

`kubernetes/scripts/cns/sizer.sh` has two modes: it can either *show you what a configuration would look like*, or it can *apply that configuration directly to the cluster* (ConfigMap + deployment scale in one shot).

```bash
# Plan-only modes (no cluster changes)
sudo ./miniprem.sh sizer                       # Interactive calculator
sudo ./kubernetes/scripts/cns/sizer.sh --detect           # Auto-detect GPU, print capacity table
sudo ./kubernetes/scripts/cns/sizer.sh --gpu "A100 80GB"  # Show capacity for a specific GPU

# Apply modes (mutate the cluster — both require kubectl access)
sudo ./kubernetes/scripts/cns/sizer.sh --apply            # Interactive, then apply after confirmation
sudo ./kubernetes/scripts/cns/sizer.sh --apply-quick      # Auto-detect GPU and apply recommended config
```

**What `--apply` / `--apply-quick` actually do** (in order, with a confirmation prompt before step 1 in `--apply` mode):

1. **Update the GPU time-slicing ConfigMap** in the GPU operator namespace (`gpu-operator` or `gpu-operator-resources` on MicroK8s) with `replicasPerGpu` from your choice.
2. **Patch the `ClusterPolicy`** to point the device plugin at the updated ConfigMap — skipped on MicroK8s where the nvidia addon doesn't use a ClusterPolicy.
3. **Scale the Renny deployment** in the `uneeq` namespace to the chosen replica count.

Use `--apply-quick` when you trust the GPU autodetection and just want the recommended config. Use `--apply` when you want to pick GPU model, quality mode, and replica count yourself before changes land.

> **Note**: `scale-quick N` (via `./miniprem.sh scale-quick N`) only changes the replica count. `sizer --apply` is the right choice when you also need to change GPU time-slicing (e.g. moving from 2 to 4 pods per GPU).


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
# Recommended: Use miniprem.sh
cd ~/miniprem-2025
sudo ./miniprem.sh logs

# Or direct kubectl:
# Follow Renny logs
sudo microk8s kubectl logs -f deployment/renny -n uneeq

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
sudo microk8s kubectl delete secret renny -n uneeq
cd ~/miniprem-2025
sudo ./miniprem.sh upgrade
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

All operations use the `./miniprem.sh` CLI which auto-detects CNS installations.

### Using miniprem.sh (Recommended)

```bash
cd ~/miniprem-2025

# Check status
sudo ./miniprem.sh status

# View logs
sudo ./miniprem.sh logs

# Restart all pods
sudo ./miniprem.sh restart

# Stop all pods
sudo ./miniprem.sh stop

# Start pods again
sudo ./miniprem.sh start

# Apply config changes (helm upgrade)
sudo ./miniprem.sh upgrade

# Clear TTS secrets (use Admin Portal config)
sudo ./miniprem.sh upgrade --clear-secrets

# Just restart pods (no helm upgrade)
sudo ./miniprem.sh upgrade --restart

# Change replica count
sudo ./miniprem.sh upgrade --replicas 5

# Interactive scaling with GPU detection
sudo ./miniprem.sh scale

# Quick scale (direct kubectl)
sudo ./miniprem.sh scale-quick 4

# GPU capacity calculator
sudo ./miniprem.sh sizer

# Full re-deploy (interactive)
sudo ./miniprem.sh deploy
```

### Direct kubectl Commands (Advanced)

If you need direct cluster access:

```bash
# Check pod status
sudo microk8s kubectl get pods -n uneeq

# View logs
sudo microk8s kubectl logs -f deployment/renny -n uneeq

# Restart pods
sudo microk8s kubectl rollout restart deployment/renny -n uneeq

# Scale to specific count
sudo microk8s kubectl scale deployment/renny -n uneeq --replicas=4
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

### Upgrade from Git

```bash
cd ~/miniprem-2025

# Easy way - preserves all config files
sudo ./miniprem.sh upgrade

# Manual way
git stash                    # Stash local changes
git pull                     # Pull latest code
git stash pop                # Restore local changes
sudo ./miniprem.sh upgrade   # Apply config changes
```

> **Note:** The `upgrade` command automatically backs up and restores your config files (`.cns_config`, `terraform.tfvars`, `renny-values-cns.yaml`, etc.) so credentials are preserved.

---

## Environment Variables Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `CNS_K8S_TYPE` | Kubernetes distribution | `microk8s` |
| `CNS_INSTALL_MODE` | Installation mode | (interactive) |
| `CNS_QUALITY_LEVEL` | Rendering quality: `web` (stock characters) or `miniprem` (MiniPrem maps) | `web` |
| `RENNY_REPLICAS` | Number of Renny pods | (auto-detected) |
| `NGC_API_KEY` | NVIDIA NGC API key | (prompted) |
| `GPU_TIMESLICE_REPLICAS` | Time-slices per GPU | 8 |
| `DHOP_APIKEY` | UneeQ DHOP API Key | (prompted) |
| `DHOP_TENANTID` | UneeQ DHOP Tenant ID | (prompted) |

---

## Support

For issues with:
- **MiniPrem/Renny**: Contact UneeQ support
- **Dell Hardware**: Contact Dell support
- **NVIDIA Drivers/GPU Operator**: Refer to NVIDIA documentation

---

## Quick Reference Card

```bash
# ═══════════════════════════════════════════════════════════════
# MiniPrem CNS Quick Reference (use from ~/miniprem-2025)
# ═══════════════════════════════════════════════════════════════

# Check status
sudo ./miniprem.sh status

# View logs
sudo ./miniprem.sh logs

# Restart pods
sudo ./miniprem.sh restart

# Stop/Start
sudo ./miniprem.sh stop
sudo ./miniprem.sh start

# Apply config changes
sudo ./miniprem.sh upgrade

# Scale replicas
sudo ./miniprem.sh upgrade --replicas 5
# OR interactive scaling:
sudo ./miniprem.sh scale

# Clear TTS secrets (use Admin Portal)
sudo ./miniprem.sh upgrade --clear-secrets

# GPU status
nvidia-smi

# Full help
sudo ./miniprem.sh --help
```
