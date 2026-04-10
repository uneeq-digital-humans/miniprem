# MiniPrem CNS Deployment Guide

Complete guide for deploying MiniPrem on NVIDIA Cloud Native Stack (CNS) for on-premises hardware.

## Table of Contents

1. [What is CNS MiniPrem?](#what-is-cns-miniprem)
2. [Setup Process](#setup-process)
3. [Configuration Reference](#configuration-reference)
4. [Sizer Tool](#sizer-tool)
5. [Testing & Validation](#testing--validation)

---

## What is CNS MiniPrem?

CNS MiniPrem is an on-premises deployment option that installs the full MiniPrem stack on NVIDIA GPU hardware you own, without requiring cloud services.

### What Gets Installed

```
┌─────────────────────────────────────────────────────────────────┐
│                    CNS MiniPrem Stack                           │
├─────────────────────────────────────────────────────────────────┤
│  Layer 1: Operating System                                      │
│    └── Ubuntu 22.04+ or RHEL 8.7+                              │
├─────────────────────────────────────────────────────────────────┤
│  Layer 2: Prerequisites (auto-installed)                        │
│    ├── snapd (for MicroK8s)                                    │
│    ├── Google Chrome (for kiosk interface)                     │
│    └── curl, wget, jq, git                                     │
├─────────────────────────────────────────────────────────────────┤
│  Layer 3: Kubernetes                                            │
│    ├── MicroK8s (recommended for single-node)                  │
│    │   └── Addons: dns, hostpath-storage, helm3, nvidia        │
│    └── OR kubeadm (for multi-node clusters)                    │
│        └── Calico CNI, containerd runtime                      │
├─────────────────────────────────────────────────────────────────┤
│  Layer 4: GPU Stack                                             │
│    ├── NVIDIA GPU Operator                                      │
│    │   ├── Device Plugin (exposes GPUs to K8s)                 │
│    │   ├── DCGM Exporter (GPU metrics)                         │
│    │   └── Container Toolkit                                    │
│    └── GPU Time-Slicing ConfigMap                              │
├─────────────────────────────────────────────────────────────────┤
│  Layer 5: MiniPrem Services                                     │
│    ├── Renny Renderer (digital human engine)                   │
│    ├── vLLM / NIM (local LLM inference)                        │
│    ├── Flowise (conversation orchestration)                    │
│    ├── Redis (session state)                                   │
│    ├── Prometheus (metrics)                                    │
│    ├── Grafana (dashboards)                                    │
│    └── Phoenix (LLM observability - optional)                  │
└─────────────────────────────────────────────────────────────────┘
```

### Cloud vs CNS Comparison

| Aspect | Cloud (EKS/AKS/GKE) | CNS (On-Premises) |
|--------|---------------------|-------------------|
| Infrastructure | Managed by cloud provider | You manage |
| GPU Availability | Pay per hour | Always available |
| Data Location | Cloud data centers | On-site |
| Internet Required | Yes | Only for initial setup |
| Autoscaling | Yes (dynamic) | No (fixed hardware) |
| Cost Model | OpEx (ongoing) | CapEx (one-time) |

---

## Setup Process

### Prerequisites

| Requirement | Details |
|-------------|---------|
| OS | Ubuntu 22.04+, Ubuntu 24.04, or RHEL 8.7+ |
| GPU | NVIDIA datacenter GPU (A100, H100, L40, T4, A10G) |
| RAM | 16GB minimum, 32GB+ recommended |
| Storage | 100GB+ SSD |
| Network | Internet for initial setup |
| Access | Root/sudo privileges |

### Step 1: Get NGC API Key

1. Visit https://ngc.nvidia.com/
2. Sign in or create account
3. Go to **Setup** → **API Key**
4. Click **Generate API Key**
5. Save the key securely

### Step 2: Run Deployment

**Option A: Interactive Deployment**
```bash
cd kubernetes/scripts
./deploy.sh

# Select: 4) NVIDIA Cloud Native Stack (CNS)
# Select: 1) Local Install (or 2 for Remote)
# Select: 1) MicroK8s (recommended)
# Enter: NGC API Key when prompted
```

**Option B: Direct Deployment**
```bash
cd kubernetes/scripts/cns

# Set environment variables
export NGC_API_KEY='your-ngc-api-key'
export CNS_K8S_TYPE=microk8s  # or kubeadm
export RENNY_REPLICAS=4

# Run
sudo -E ./deploy-local.sh
```

**Option C: Remote Deployment (over SSH)**
```bash
export CNS_REMOTE_HOST=192.168.1.100
export CNS_REMOTE_USER=ubuntu
export CNS_SSH_KEY=~/.ssh/id_rsa
export NGC_API_KEY='your-ngc-api-key'

./deploy-remote.sh
```

**Option D: Ansible Deployment**
```bash
cd kubernetes/ansible

# Configure inventory
cp inventory/hosts.yml.example inventory/hosts.yml
# Edit hosts.yml with your server details

# Run playbook
NGC_API_KEY='your-key' ansible-playbook -i inventory/hosts.yml playbooks/cns-install.yml
```

### Step 3: Verify Installation

```bash
# Check cluster status
./cns/status.sh

# Or manually:
microk8s kubectl get nodes
microk8s kubectl get pods -A
```

---

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NGC_API_KEY` | (required) | NVIDIA NGC API key for model downloads |
| `CNS_K8S_TYPE` | `microk8s` | Kubernetes distribution: `microk8s` or `kubeadm` |
| `CNS_DEPLOY_TYPE` | `local` | Deployment type: `local` or `remote` |
| `RENNY_REPLICAS` | `4` | Number of Renny instances to deploy |
| `CNS_REMOTE_HOST` | - | Remote server IP/hostname (for remote deploy) |
| `CNS_REMOTE_USER` | `ubuntu` | SSH username for remote deploy |
| `CNS_SSH_KEY` | `~/.ssh/id_rsa` | SSH private key path |

### Renny Configuration (docker-compose.env)

| Variable | Default | Description |
|----------|---------|-------------|
| `RENNY_QUALITY_LEVEL` | `miniprem` | Quality mode: `miniprem` (high) or `web` (optimized) |
| `DHOP_ADDRESS` | `wss://api.enterprise.uneeq.io/...` | UneeQ platform WebSocket URL |
| `DHOP_APIKEY` | (required) | Your DHOP API key |
| `DHOP_TENANTID` | (required) | Your DHOP tenant ID |
| `SLEEP_TIMER_SECS` | `5.0` | Seconds before entering sleep mode after session |
| `HEALTH_URL` | `http://0.0.0.0:8081/health` | Health check endpoint |

### TTS Configuration (pick one)

**Azure Speech:**
| Variable | Description |
|----------|-------------|
| `AZURE_REGION` | Azure region (e.g., `eastus`) |
| `AZURE_SPEECH_KEY` | Azure Speech API key |

**ElevenLabs:**
| Variable | Description |
|----------|-------------|
| `ELEVEN_LABS_API_KEY` | ElevenLabs API key |
| `ELEVEN_LABS_MODEL_ID` | Model: `eleven_flash_v2_5`, `eleven_turbo_v2` |
| `ELEVEN_LABS_OPTIMIZE_LATENCY_LEVEL` | `0`-`4` (lower = faster) |

**NVIDIA Riva (local):**
| Variable | Description |
|----------|-------------|
| `RIVA_URL` | Riva gRPC endpoint (e.g., `localhost:50051`) |
| `RIVA_USE_SSL` | `true` or `false` |

### Helm Values (renny-values-cns.yaml)

```yaml
# Core settings
image: "cr.uneeq.io/uneeq/renny-renderer:enterprise-latest"

deployment:
  totalReplicas: 4        # Number of Renny pods

# GPU time-slicing
gpuTimeSlicing:
  enabled: true
  replicasPerGpu: 4       # Rennys per physical GPU

# Resources per Renny
resources:
  requests:
    nvidia.com/gpu: 1
    memory: "8Gi"
    cpu: "4000m"
  limits:
    nvidia.com/gpu: 1
    memory: "8Gi"
    cpu: "4000m"

# Quality settings
env:
  - name: RENNY_QUALITY_LEVEL
    value: "miniprem"     # or "web"

# Local LLM (NIM)
nim:
  enabled: true
  endpoint: "http://localhost:8000/v1"
  model: "meta/llama-3.1-8b-instruct"

# Telemetry
telemetry:
  enabled: true
  platform: "cns"
```

### GPU Time-Slicing ConfigMap

```yaml
# Applied automatically during install
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: gpu-operator
data:
  any: |-
    version: v1
    sharing:
      timeSlicing:
        resources:
          - name: nvidia.com/gpu
            replicas: 4    # Adjust based on GPU VRAM
```

### Quality Mode Details

| Mode | `RENNY_QUALITY_LEVEL` | Use Case | GPU Usage |
|------|----------------------|----------|-----------|
| **MiniPrem** | `miniprem` | Dedicated kiosks, local hardware | Higher (best quality) |
| **Web** | `web` | Cloud streaming, bandwidth-limited | Lower (optimized) |

### Resolution Settings

Set via Renny command arguments:

| Resolution | Command Args |
|------------|--------------|
| 720p | `-ResX=1280 -ResY=720` |
| 1080p | `-ResX=1920 -ResY=1080` |
| 1440p | `-ResX=2560 -ResY=1440` |
| 4K | `-ResX=3840 -ResY=2160` |

**Note:** Resolution is typically controlled dynamically by the DHOP control panel. The command args set the maximum capability.

---

## Sizer Tool

### What It Does

The sizer tool (`kubernetes/scripts/cns/sizer.sh`) calculates how many Renny instances you can run based on your hardware configuration.

**Important:** The sizer is a **calculator only**. It does NOT:
- Restart Renny pods
- Modify configurations
- Apply changes to the cluster

It outputs recommended settings that you then apply manually or pass to the deploy script.

### Usage

```bash
cd kubernetes/scripts/cns

# Interactive mode (prompts for inputs)
./sizer.sh

# Auto-detect GPU from current system
./sizer.sh --detect

# Quick lookup by GPU model
./sizer.sh --gpu "A100 80GB"
./sizer.sh --gpu "T4"
./sizer.sh --gpu "L40"

# List known GPUs
./sizer.sh --list
```

### Output Example

```
╔═══════════════════════════════════════════════════════════════╗
║         MiniPrem CNS Deployment Sizer                         ║
╚═══════════════════════════════════════════════════════════════╝

GPU Configuration:
  Model: A100 80GB
  VRAM per GPU: 78GB
  GPU Count: 1
  Total VRAM: 78GB

┌─────────────┬──────────┬──────────────────┬──────────────────┐
│ Resolution  │ Quality  │ Rennys (no LLM)  │ Rennys (+ 7B)    │
├─────────────┼──────────┼──────────────────┼──────────────────┤
│ 1080p       │ web      │ 22 instances     │ 20 instances     │
│ 1080p       │ miniprem │ 20 instances     │ 18 instances     │
│ 4k          │ web      │ 14 instances     │ 13 instances     │
│ 4k          │ miniprem │ 12 instances     │ 11 instances     │
└─────────────┴──────────┴──────────────────┴──────────────────┘
```

### VRAM Calculation Formula

```
Per Renny VRAM = Base (2.5GB) + (Resolution Overhead × Quality Multiplier)

Resolution Overhead:
  720p  = 0.5GB
  1080p = 1.0GB
  1440p = 1.5GB
  4K    = 3.0GB

Quality Multiplier:
  web      = 1.0×
  miniprem = 1.3×

Shared Services:
  vLLM 7B  = 6GB
  vLLM 13B = 10GB
  vLLM 70B = 35GB
  Riva     = 4GB

Max Rennys = (GPU VRAM - Shared Services) / Per Renny VRAM
```

### Applying Sizer Output

After running the sizer, apply the recommended configuration:

```bash
# Option 1: Set environment variable and deploy
RENNY_REPLICAS=18 ./deploy-local.sh

# Option 2: Edit values file directly
vim kubernetes/values/renny-values-cns.yaml
# Change: deployment.totalReplicas: 18
# Change: gpuTimeSlicing.replicasPerGpu: 18

# Option 3: Helm upgrade (if already deployed)
microk8s helm3 upgrade renny ./renny \
  --namespace uneeq \
  --set deployment.totalReplicas=18
```

---

## Testing & Validation

### Sizer Tool Validation Steps

The sizer provides **estimates**. To validate on real hardware:

#### Step 1: Baseline Test (Single Renny)

```bash
# Deploy 1 Renny
RENNY_REPLICAS=1 ./deploy-local.sh

# Wait for pod to be running
microk8s kubectl get pods -n uneeq -w

# Record baseline GPU usage
nvidia-smi --query-gpu=memory.used,utilization.gpu --format=csv -l 1
```

#### Step 2: Incremental Load Test

```bash
# Create test script
cat > test-capacity.sh << 'EOF'
#!/bin/bash
for count in 2 4 6 8 10; do
    echo "Testing with $count Rennys..."

    # Scale Rennys
    microk8s kubectl scale deployment/renderer -n uneeq --replicas=$count

    # Wait for all pods ready
    microk8s kubectl wait --for=condition=ready pod -l app=renderer -n uneeq --timeout=300s

    # Record metrics for 60 seconds
    echo "Recording metrics..."
    nvidia-smi --query-gpu=timestamp,memory.used,memory.total,utilization.gpu --format=csv -l 5 | tee "metrics_${count}_rennys.csv" &
    PID=$!
    sleep 60
    kill $PID

    # Check for OOM or failures
    microk8s kubectl get pods -n uneeq | grep -E "Error|OOM|CrashLoop" && echo "FAILURE at $count" && break

    echo "Success with $count Rennys"
    echo "---"
done
EOF
chmod +x test-capacity.sh
./test-capacity.sh
```

#### Step 3: Stress Test (Concurrent Sessions)

```bash
# Install load testing tool
pip install locust

# Create locust file for Renny health endpoints
cat > locustfile.py << 'EOF'
from locust import HttpUser, task, between

class RennyUser(HttpUser):
    wait_time = between(1, 3)

    @task
    def health_check(self):
        self.client.get("/health")
EOF

# Run against each Renny instance
locust -f locustfile.py --host=http://localhost:8081 --users=10 --spawn-rate=2 --run-time=5m
```

#### Step 4: Resolution/Quality Matrix Test

```bash
# Test each configuration
for resolution in "1920x1080" "3840x2160"; do
    for quality in "web" "miniprem"; do
        echo "Testing: $resolution @ $quality"

        # Update deployment
        microk8s kubectl set env deployment/renderer -n uneeq \
            RENNY_QUALITY_LEVEL=$quality

        # Restart to apply (resolution requires pod restart with new args)
        microk8s kubectl rollout restart deployment/renderer -n uneeq
        microk8s kubectl rollout status deployment/renderer -n uneeq

        # Record GPU metrics
        nvidia-smi --query-gpu=memory.used,utilization.gpu --format=csv -l 5 | \
            head -20 > "test_${resolution}_${quality}.csv"
    done
done
```

#### Step 5: Validate Sizer Accuracy

```bash
# Compare sizer prediction vs actual
./sizer.sh --detect > sizer_prediction.txt

# Run actual test
./test-capacity.sh > actual_results.txt

# Compare
echo "Sizer predicted:"
grep "instances" sizer_prediction.txt
echo ""
echo "Actual max before failure:"
grep "Success" actual_results.txt | tail -1
```

### Monitoring During Tests

```bash
# Terminal 1: Watch GPU
watch -n 1 nvidia-smi

# Terminal 2: Watch pods
watch -n 2 'microk8s kubectl get pods -n uneeq'

# Terminal 3: Watch events
microk8s kubectl get events -n uneeq -w

# Terminal 4: Pod logs
microk8s kubectl logs -n uneeq -l app=renderer -f --tail=50
```

### Expected Results Matrix

| GPU | 1080p Web | 1080p MiniPrem | 4K Web | 4K MiniPrem |
|-----|-----------|----------------|--------|-------------|
| T4 (16GB) | 3-4 | 2-3 | 1-2 | 1 |
| A10G (24GB) | 5-6 | 4-5 | 2-3 | 2 |
| L40 (48GB) | 12-14 | 10-12 | 6-8 | 5-6 |
| A100 40GB | 10-12 | 8-10 | 5-6 | 4-5 |
| A100 80GB | 20-22 | 18-20 | 13-14 | 11-12 |

**Note:** These are estimates. Actual results vary based on:
- Thermal throttling
- Other GPU workloads
- Specific Renny version
- Scene complexity

---

## Troubleshooting

### GPU Not Detected
```bash
nvidia-smi  # Should show GPU info
lspci | grep -i nvidia  # Should show GPU device
```

### Pods Stuck Pending
```bash
microk8s kubectl describe pod -n uneeq  # Check events
microk8s kubectl get nodes -o jsonpath='{.items[*].status.allocatable}'  # Check GPU resources
```

### Out of Memory
```bash
# Reduce replicas
microk8s kubectl scale deployment/renderer -n uneeq --replicas=2

# Check which pods are using GPU memory
nvidia-smi pmon -s m
```

### Time-Slicing Not Working
```bash
# Verify configmap exists
microk8s kubectl get configmap -n gpu-operator

# Check cluster policy
microk8s kubectl get clusterpolicy -n gpu-operator -o yaml
```

---

## Quick Reference

### Common Commands

```bash
# Check status
./cns/status.sh

# Scale Rennys
./cns/scale.sh 8

# View logs
microk8s kubectl logs -n uneeq -l app=renderer -f

# Restart all Rennys
microk8s kubectl rollout restart deployment/renderer -n uneeq

# Destroy everything
./cns/destroy.sh

# Destroy including Kubernetes
PURGE_ALL=true ./cns/destroy.sh
```

### File Locations

| File | Purpose |
|------|---------|
| `kubernetes/scripts/cns/deploy-local.sh` | Main CNS installer |
| `kubernetes/scripts/cns/sizer.sh` | Capacity calculator |
| `kubernetes/values/renny-values-cns.yaml` | Helm values for CNS |
| `kubernetes/ansible/playbooks/cns-install.yml` | Ansible playbook |
| `docker/docker-compose.env` | Renny environment config |
