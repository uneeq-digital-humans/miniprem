# UneeQ MiniPrem CNS Deployment Guide

## For Dell Technology Partners

**Document Version:** 2.0
**Last Updated:** April 2025
**Platform:** NVIDIA Cloud Native Stack (CNS) on Dell Hardware

---

## Executive Summary

This guide provides Dell ISG partners with complete instructions for deploying UneeQ's digital human platform (MiniPrem) on NVIDIA Cloud Native Stack (CNS). The automated deployment scripts simplify installation on Dell Pro Tower, PowerEdge, and Precision workstations equipped with NVIDIA GPUs.

**Key Benefits:**
- Single-command deployment with automatic hardware detection
- GPU time-slicing for maximum concurrent user capacity
- Flexible quality modes (MiniPrem vs Web) based on use case
- Production-ready Kubernetes orchestration

---

## Table of Contents

1. [Hardware Requirements](#1-hardware-requirements)
2. [Software Prerequisites](#2-software-prerequisites)
3. [Deployment Script Overview](#3-deployment-script-overview)
4. [Installation Process](#4-installation-process)
5. [Configuration Options](#5-configuration-options)
6. [Capacity Planning](#6-capacity-planning)
7. [Operations & Management](#7-operations--management)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Hardware Requirements

### Supported Dell Systems

| System | GPU Options | Recommended Use |
|--------|-------------|-----------------|
| Dell Pro Tower T2 | RTX PRO 6000 Blackwell (48GB) | Premium deployments, 3-5 concurrent users |
| Dell Precision 7920 | A100 40GB/80GB | High-capacity, 4-6 concurrent users |
| Dell PowerEdge R760xa | L40S, H100 | Data center deployments |
| Dell Precision 5820 | RTX A6000 (48GB) | Development and testing |

### Minimum Specifications

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 8 cores | 16+ cores |
| RAM | 32 GB | 64+ GB |
| Storage | 100 GB SSD | 500+ GB NVMe |
| GPU VRAM | 16 GB | 48+ GB |
| Network | 1 Gbps | 10 Gbps |

---

## 2. Software Prerequisites

### Operating System

**Required:** Ubuntu 24.04 LTS (Server or Desktop)

```bash
# Verify Ubuntu version
cat /etc/os-release | grep VERSION_ID
# Expected: VERSION_ID="24.04"
```

### NVIDIA Driver (CRITICAL)

The NVIDIA driver **MUST** be installed before running the deployment script.

**Required Version:** 580.82.x

> **WARNING:** Driver version 580.126.x is **INCOMPATIBLE** with UneeQ digital humans. It breaks NVENC hardware video encoding.

#### Driver Installation for RTX PRO 6000 Blackwell

```bash
# Download driver
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/580.82.09/NVIDIA-Linux-x86_64-580.82.09.run

# Install
chmod +x NVIDIA-Linux-x86_64-580.82.09.run
sudo ./NVIDIA-Linux-x86_64-580.82.09.run --silent --dkms

# Reboot required
sudo reboot
```

#### Driver Installation for Other GPUs (A100, L4, T4)

```bash
# Install from Ubuntu repository
sudo apt update
sudo apt install nvidia-driver-580=580.82.07-0ubuntu1
sudo reboot
```

#### Verify Driver Installation

```bash
nvidia-smi
# Expected output should show:
# - Driver Version: 580.82.xx
# - GPU name and VRAM
```

---

## 3. Deployment Script Overview

### What the Script Does

The `deploy-local.sh` script automates the complete MiniPrem CNS deployment:

```
┌─────────────────────────────────────────────────────────────────┐
│                    DEPLOYMENT WORKFLOW                          │
├─────────────────────────────────────────────────────────────────┤
│  1. System Validation                                           │
│     ├── OS check (Ubuntu 24.04)                                │
│     ├── GPU detection (nvidia-smi)                             │
│     └── Prerequisites verification                              │
├─────────────────────────────────────────────────────────────────┤
│  2. Infrastructure Setup                                        │
│     ├── MicroK8s installation                                  │
│     ├── Helm 3 package manager                                 │
│     ├── Container registry authentication                       │
│     └── Namespace creation                                      │
├─────────────────────────────────────────────────────────────────┤
│  3. GPU Configuration                                           │
│     ├── NVIDIA GPU Operator deployment                         │
│     ├── Time-slicing ConfigMap (enables multiple pods/GPU)     │
│     └── Device plugin restart                                   │
├─────────────────────────────────────────────────────────────────┤
│  4. Display & Graphics                                          │
│     ├── Xvfb (virtual framebuffer for headless rendering)      │
│     ├── Vulkan libraries (graphics API)                        │
│     └── Display environment configuration                       │
├─────────────────────────────────────────────────────────────────┤
│  5. Application Deployment                                      │
│     ├── Helm chart installation (Renny renderer)               │
│     ├── Quality mode configuration                              │
│     ├── Replica scaling                                         │
│     └── Health verification                                     │
└─────────────────────────────────────────────────────────────────┘
```

### What the Script Does NOT Do

- **Does NOT install NVIDIA drivers** (must be pre-installed)
- Does NOT configure network/firewall rules
- Does NOT provision cloud resources

---

## 4. Installation Process

### Step 1: Clone the Repository

```bash
cd ~
git clone https://gitlab.com/tgmerritt/miniprem-2025.git
cd miniprem-2025
```

### Step 2: Navigate to Scripts

```bash
cd kubernetes/scripts/cns
```

### Step 3: Run Deployment (Interactive Mode)

```bash
sudo ./deploy-local.sh
```

The script will prompt for:

1. **Installation Mode**
   - `minimal` - Renny only (uses cloud TTS/LLM)
   - `full` - Renny + local NIM LLM + Riva TTS

2. **Quality Level**
   - `miniprem` - Higher quality rendering (~8-10 GB VRAM per pod)
   - `web` - Optimized for capacity (~1.3 GB VRAM per pod)

3. **Replica Count**
   - Auto-recommended based on GPU VRAM
   - Adjustable based on expected concurrent users

### Step 4: Non-Interactive Deployment (Automation)

For automated/scripted deployments:

```bash
sudo CNS_INSTALL_MODE=minimal \
     CNS_QUALITY_LEVEL=web \
     RENNY_REPLICAS=5 \
     NGC_API_KEY="your-ngc-key" \
     ./deploy-local.sh
```

### Step 5: Verify Deployment

```bash
# Check pod status
sudo microk8s kubectl get pods -n uneeq

# Expected output (example for 4 replicas):
# NAME                        READY   STATUS    RESTARTS   AGE
# renderer-abc123-xxxxx       1/1     Running   0          5m
# renderer-abc123-xxxxx       1/1     Running   0          5m
# renderer-abc123-xxxxx       1/1     Running   0          5m
# renderer-abc123-xxxxx       1/1     Running   0          5m
```

---

## 5. Configuration Options

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CNS_K8S_TYPE` | `microk8s` | Kubernetes distribution |
| `CNS_INSTALL_MODE` | (interactive) | `minimal` or `full` |
| `CNS_QUALITY_LEVEL` | `miniprem` | `miniprem` or `web` |
| `RENNY_REPLICAS` | (auto-detected) | Number of Renny pods |
| `NGC_API_KEY` | (prompted) | NVIDIA NGC API key |
| `GPU_TIMESLICE_REPLICAS` | 8 | Time-slices per GPU |

### Quality Levels Explained

#### MiniPrem Mode
- **Use Case:** Premium kiosk deployments, trade shows, showrooms
- **VRAM Usage:** ~8-10 GB per pod
- **Features:** High-resolution textures, enhanced facial detail
- **Requirement:** Must use MiniPrem character maps

#### Web Mode
- **Use Case:** High-capacity deployments, concurrent users
- **VRAM Usage:** ~1.3 GB per pod
- **Features:** Optimized textures, efficient rendering
- **Requirement:** Must use web-optimized character maps

> **IMPORTANT:** Quality level MUST match character map type. Using mismatched combinations causes rendering issues.

### Values File Location

The main configuration file:
```
kubernetes/values/renny-values-cns.yaml
```

Key settings:
```yaml
deployment:
  totalReplicas: 4        # Number of Renny instances

gpuTimeSlicing:
  enabled: true
  replicasPerGpu: 4       # Pods sharing each GPU

renderer:
  qualityLevel: "miniprem" # or "web"
```

---

## 6. Capacity Planning

### GPU Capacity Reference

| GPU | VRAM | Web Mode Replicas | MiniPrem Replicas |
|-----|------|-------------------|-------------------|
| **RTX PRO 6000 Blackwell** | 48 GB | 5 | 3 |
| A100 80GB | 80 GB | 6 | 4 |
| A100 40GB | 40 GB | 4 | 2 |
| RTX A6000 | 48 GB | 5 | 3 |
| L40S | 48 GB | 5 | 3 |
| L4 | 24 GB | 3 | 2 |
| T4 | 16 GB | 2 | 1 |

### Capacity Calculation

**Formula:**
```
Max Replicas = GPU VRAM / VRAM per Pod

Web Mode:    VRAM per Pod ≈ 1.3 GB
MiniPrem:    VRAM per Pod ≈ 8-10 GB
```

**Example (RTX PRO 6000 Blackwell - 48 GB):**
- Web Mode: 48 GB / 1.3 GB = ~37 theoretical, **5 recommended** (accounting for overhead)
- MiniPrem: 48 GB / 10 GB = ~4, **3 recommended** (accounting for overhead)

### Concurrent User Mapping

Each Renny replica handles one active session. Plan replicas based on expected peak concurrent users plus 20% headroom.

---

## 7. Operations & Management

### Daily Operations

#### Check Status
```bash
sudo microk8s kubectl get pods -n uneeq
```

#### View Logs
```bash
# All Renny logs
sudo microk8s kubectl logs -f deployment/renderer -n uneeq

# Specific pod logs
sudo microk8s kubectl logs <pod-name> -n uneeq
```

#### GPU Utilization
```bash
nvidia-smi
```

### Scaling Operations

#### Scale Replicas
```bash
cd ~/miniprem-2025/kubernetes/scripts/cns
sudo ./cns-update.sh --replicas 5
```

#### Restart All Pods
```bash
sudo ./cns-update.sh --restart
```

#### Apply Configuration Changes
```bash
# After editing renny-values-cns.yaml
sudo ./cns-update.sh
```

### Quick Reference Commands

```bash
# Check pod status
sudo microk8s kubectl get pods -n uneeq

# Watch pods in real-time
sudo microk8s kubectl get pods -n uneeq -w

# View recent logs
sudo microk8s kubectl logs -f deployment/renderer -n uneeq --tail=100

# Scale to N replicas
sudo ./cns-update.sh --replicas N

# Restart pods
sudo microk8s kubectl rollout restart deployment/renderer -n uneeq

# GPU status
nvidia-smi
```

---

## 8. Troubleshooting

### Common Issues

#### Pods Stuck in "Pending"

**Symptom:** Pods show `Pending` status indefinitely

**Cause:** Insufficient GPU resources or scheduling issues

**Solution:**
```bash
# Check events
sudo microk8s kubectl describe pod <pod-name> -n uneeq | tail -20

# Reduce replica count if needed
sudo ./cns-update.sh --replicas 3
```

#### Pods in "CrashLoopBackOff"

**Symptom:** Pods repeatedly crash and restart

**Common Causes:**
1. Missing API keys
2. Audio driver misconfiguration
3. Display/Vulkan issues

**Solution:**
```bash
# Check logs for specific error
sudo microk8s kubectl logs <pod-name> -n uneeq --previous

# Verify configuration
sudo microk8s kubectl get secret renderer -n uneeq -o yaml
```

#### Video Encoding Errors

**Symptom:** Video stream fails, NVENC errors in logs

**Cause:** Incompatible NVIDIA driver version

**Solution:**
```bash
# Check driver version
nvidia-smi | grep "Driver Version"
# Must be 580.82.x, NOT 580.126.x

# If wrong version, reinstall correct driver
```

#### GPU Not Detected by Kubernetes

**Symptom:** Pods pending with "insufficient nvidia.com/gpu" error

**Solution:**
```bash
# Check GPU Operator status
sudo microk8s kubectl get pods -n gpu-operator

# Restart GPU device plugin
sudo microk8s kubectl delete pods -n gpu-operator -l app=nvidia-device-plugin-daemonset

# Verify GPU resources
sudo microk8s kubectl describe nodes | grep nvidia.com/gpu
```

### Support Contacts

| Issue Type | Contact |
|------------|---------|
| MiniPrem/Renny Software | UneeQ Support |
| Dell Hardware | Dell Technical Support |
| NVIDIA Drivers/GPU Operator | NVIDIA Documentation |

---

## Appendix A: Complete Deployment Example

### Fresh Installation on Dell Pro Tower T2

```bash
# 1. Verify prerequisites
nvidia-smi  # Should show 580.82.x driver
cat /etc/os-release | grep VERSION_ID  # Should show 24.04

# 2. Clone repository
cd ~
git clone https://gitlab.com/tgmerritt/miniprem-2025.git
cd miniprem-2025/kubernetes/scripts/cns

# 3. Run deployment (non-interactive)
sudo CNS_INSTALL_MODE=minimal \
     CNS_QUALITY_LEVEL=web \
     RENNY_REPLICAS=5 \
     NGC_API_KEY='your-ngc-key' \
     ./deploy-local.sh

# 4. Wait for completion (~10-15 minutes)

# 5. Verify
sudo microk8s kubectl get pods -n uneeq
# All pods should show Running status
```

---

## Appendix B: Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Dell Server Hardware                          │
│  (Pro Tower T2 / PowerEdge / Precision)                         │
├─────────────────────────────────────────────────────────────────┤
│  NVIDIA GPU (RTX PRO 6000 Blackwell / A100 / L40S)              │
│  └── Driver: 580.82.x (REQUIRED)                                │
├─────────────────────────────────────────────────────────────────┤
│  Ubuntu 24.04 LTS                                               │
│  ├── Xvfb (Virtual Display)                                     │
│  └── Vulkan Libraries                                           │
├─────────────────────────────────────────────────────────────────┤
│  MicroK8s (Kubernetes)                                          │
│  ├── GPU Operator                                               │
│  │   └── Time-Slicing ConfigMap                                 │
│  ├── Helm 3                                                     │
│  └── uneeq Namespace                                            │
│      └── Renny Deployment                                       │
│          ├── Pod 1 (GPU Slice 1)                                │
│          ├── Pod 2 (GPU Slice 2)                                │
│          ├── Pod 3 (GPU Slice 3)                                │
│          └── Pod N (GPU Slice N)                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Document History

| Version | Date | Changes |
|---------|------|---------|
| 2.0 | April 2025 | Ubuntu 24.04 requirement, updated capacity tables |
| 1.0 | March 2025 | Initial Dell ISG release |

---

*For the latest version of this document and deployment scripts, visit the GitLab repository or contact UneeQ support.*
