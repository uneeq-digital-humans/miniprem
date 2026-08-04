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
│    └── Ubuntu 22.04+ (validated appliance OS)                              │
├─────────────────────────────────────────────────────────────────┤
│  Layer 2: Prerequisites (auto-installed)                        │
│    ├── curl, gpg (for apt key imports)                         │
│    ├── Google Chrome (for kiosk interface)                     │
│    └── curl, wget, jq, git                                     │
├─────────────────────────────────────────────────────────────────┤
│  Layer 3: Kubernetes                                            │
│    ├── kubeadm (default — NVIDIA Cloud Native Stack aligned)   │
│    │   └── containerd.io, Calico CNI, NVIDIA CTK               │
│    └── OR MicroK8s (legacy option, not recommended for prod)   │
│        └── Addons: dns, hostpath-storage, helm3, nvidia        │
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
| OS | **Ubuntu 22.04+ / 24.04 (validated)** — RHEL is CNS-compatible but not validated for the appliance (renny, kiosk audio/display controls) |
| GPU | NVIDIA datacenter/workstation GPU (RTX PRO 6000 Blackwell, A100, H100, L40, T4, A10G) |
| NVIDIA driver | 580+ required; **595.84 recommended** (measurably better stability under multi-session VRAM pressure, +5-13% on ray-traced rendering). **Blackwell GPUs require the open kernel modules** (`nvidia-driver-XXX-open` / the `-open` flavor) — the proprietary module fails with `RmInitAdapter failed`. If a previous driver was installed via NVIDIA's `.run` installer, remove `/etc/apt/preferences.d/nvidia-pin-runfile` before installing via apt (it pins NVIDIA packages to priority -1). |
| RAM | 32GB minimum, 64GB+ recommended when running local LLM/ASR alongside renderers |
| Storage | 300GB+ SSD (the renny image alone is ~16GB; NIM/LLM model caches add tens of GB) |
| Network | Internet for initial setup |
| Access | Root/sudo privileges |

### Known Conflicts

**MicroK8s** must not be installed when using the kubeadm path. Both use the same Kubernetes ports (10250, 10257, 10259) and the deployment will fail at cluster initialization with cryptic port-in-use errors.

If MicroK8s is present, remove it before running the playbook:

```bash
sudo snap remove microk8s --purge
```

The playbook will detect MicroK8s and fail with a clear message if it finds it running.

---

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
# Select: 1) kubeadm (recommended)
# Enter: NGC API Key when prompted
```

**Option B: Direct Deployment**
```bash
cd kubernetes/scripts/cns

# Set environment variables
export NGC_API_KEY='your-ngc-api-key'
export CNS_K8S_TYPE=kubeadm  # default; use microk8s only for dev/test
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
kubectl get nodes
kubectl get pods -A
```

---

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NGC_API_KEY` | (required) | NVIDIA NGC API key for model downloads |
| `CNS_K8S_TYPE` | `kubeadm` | Kubernetes distribution: `kubeadm` (default) or `microk8s` (dev/test) |
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
| `HEALTH_URL` | `http://0.0.0.0:8082/health` | Health check endpoint (the Kubernetes chart probes port **8082**) |

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

On Kubernetes these come from the `renny` secret (key `tts-elevenlabs-api-key` etc.) and
are injected at container start — **after changing a key, roll the renny pods**
(`kubectl -n uneeq rollout restart deployment/renny`) or sessions fail at TTS
initialization ("Failed to create a new provider"). A present-but-invalid key fails with
HTTP 401 on ElevenLabs' voices API at session start.

**NVIDIA Riva (local):**
| Variable | Description |
|----------|-------------|
| `RIVA_URL` | Riva gRPC endpoint (e.g., `localhost:50051`) |
| `RIVA_USE_SSL` | `true` or `false` |

### Helm Values (renny-values-cns.yaml)

```yaml
# Core settings — ALWAYS pin an exact version (never a moving tag like enterprise-latest;
# verify what a tag resolves to against the registry before recording results against it)
image: "cr.uneeq.io/uneeq/renny-renderer:0.1332-decd6"   # UE 5.6 line (chart default)
# UE 5.8 line (0.1378-8910a and later, e.g. 0.1400-8ce39): read the
# "Renny UE 5.8 line — operational changes" section below BEFORE bumping.

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

### Renny UE 5.8 line — operational changes (0.1378-8910a and later)

Verified July 2026 on RTX PRO 6000 Blackwell hardware. If you run a 5.8-line image,
these apply:

1. **Health probes must be relaxed** (the chart in this repo now ships these): the 5.8
   engine boots slower than the old 60-second startup budget, and scene loading at
   session start stalls `/health` past the old 1-second liveness timeout. With the old
   settings, kubelet kills renderers mid-session-start and the pool crash-loops — the
   client-side symptom is `"session already in queue"` errors. Required: startup budget
   ≥300s (`failureThreshold: 30`), liveness `timeoutSeconds: 5`, `failureThreshold: 6`.
2. **Renderers wait 60 seconds before accepting sessions** — after boot AND after every
   session ends. Plan queueing/capacity around a renderer being unavailable for ~1 minute
   after each session. Renderer readiness shows in logs as `Waiting for session`.
3. **First session per renderer process is slow (~50-60s)**: the 5.8 build compiles
   shaders on demand (no precompiled PSO cache), so the first session loads the scene and
   stutters briefly until the in-process cache warms. Warm each renderer with one
   throwaway session before user traffic.
4. **VRAM footprints are larger than 5.6**: ~5.7 GiB idle per renderer pod (was ~2.6),
   roughly 10 GiB per live 4K MiniPrem session, and scene allocations are retained after
   sessions end. Many simultaneous cold scene-loads can exhaust the card (Vulkan
   out-of-memory → renderer crash) — stagger session starts and size standing pools to
   expected load.
5. **Rendering cost differs by quality path**: measured on identical hardware, the
   web-quality path got cheaper in 5.8 (higher concurrency than 5.6) while the ray-traced
   MiniPrem path cost roughly 2× more per session than 5.6 for some scenes. Re-measure
   your capacity when changing renny versions — see Testing & Validation.

### Quality Mode Details

| Mode | `RENNY_QUALITY_LEVEL` | Use Case |
|------|----------------------|----------|
| **MiniPrem** | `miniprem` | Dedicated kiosks, local hardware |
| **Web** | `web` | Cloud streaming, bandwidth-limited |

**Important — what actually controls session quality:** the per-session rendering profile
(resolution, character scene, ray-tracing settings, FPS cap) is **delivered by the
persona configuration in the UneeQ portal via DHOP at session start** — verified A/B on
0.1332 and 0.1400. `RENNY_QUALITY_LEVEL` sets the renderer pool's mode; it does not
override what a persona delivers per session. Configure resolution and quality on the
persona, and allow ~10 minutes for portal changes to propagate to session delivery.

### Resolution Settings

| Resolution | Persona setting (UneeQ portal) |
|------------|--------------------------------|
| 720p | 1280×720 |
| 1080p | 1920×1080 |
| 1440p | 2560×1440 |
| 4K | 3840×2160 |

**Note:** the legacy `-ResX/-ResY` command arguments do **not** change per-session
resolution on current builds — sessions render at the persona-configured resolution.
Verify what a session actually rendered from the renderer log line
`Quality applied [session-start]: ... ScreenRes=...`.

---

## Sizer Tool

### What It Does

The sizer tool (`kubernetes/scripts/cns/sizer.sh`) calculates how many Renny instances you can run based on your hardware configuration.

**Two modes:**

| Mode | Flags | Behavior |
|------|-------|----------|
| Calculator | `--detect`, `--gpu`, (default) | Shows capacity table only - **no changes** |
| Apply | `--apply`, `--apply-quick` | Calculates AND applies config to cluster |

**Calculator mode outputs** recommended settings that you can apply manually.
**Apply mode** actually modifies the cluster (time-slicing, replicas, quality mode).

### Usage

```bash
cd kubernetes/scripts/cns

# Interactive mode (calculator only - no changes made)
./sizer.sh

# Auto-detect GPU from current system
./sizer.sh --detect

# Quick lookup by GPU model
./sizer.sh --gpu "A100 80GB"
./sizer.sh --gpu "T4"
./sizer.sh --gpu "L40"

# List known GPUs
./sizer.sh --list

# === APPLY MODE (makes changes to cluster) ===

# Interactive apply - prompts for settings, then applies to cluster
./sizer.sh --apply

# Quick apply - auto-detect GPU, use recommended settings, apply immediately
./sizer.sh --apply-quick
```

### Apply Mode

The `--apply` and `--apply-quick` flags actually modify your cluster:

| Flag | What it does |
|------|--------------|
| `--apply` | Interactive prompts → confirms → applies config |
| `--apply-quick` | Auto-detect GPU → use defaults (1080p, miniprem, 7B LLM) → applies |

**What gets changed:**
1. GPU time-slicing ConfigMap (replicas per GPU)
2. GPU Operator cluster policy
3. Renny deployment replica count
4. Renny quality mode environment variable

**Example apply session:**
```
$ ./sizer.sh --apply

Detected: NVIDIA A100-SXM4-80GB (78GB) × 2

Resolution (1080p/4k) [1080p]: 1080p
Quality mode (web/miniprem) [miniprem]: miniprem
Include local LLM? (y/n) [y]: y

Maximum Renny instances: 36
How many Rennys to deploy? [36]: 32

Apply this configuration? [y/N]: y

Step 1/4: Updating GPU time-slicing ConfigMap...
  ✓ Time-slicing ConfigMap updated
Step 2/4: Patching GPU Operator cluster policy...
  ✓ Cluster policy patched
Step 3/4: Scaling Renny deployment to 32 replicas...
  ✓ Scaled deployment/renny to 32 replicas
Step 4/4: Updating quality mode to 'miniprem'...
  ✓ Quality mode set to 'miniprem'

Configuration applied!
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

**Note:** this formula was calibrated on the UE 5.6 line. Measured 5.8-line footprints
are substantially larger (~5.7 GiB idle per pod; ~10 GiB per live 4K MiniPrem session,
retained after session end) — and compute, not VRAM, is typically the real ceiling.
Always validate with real sessions.

### Manual Apply (Alternative to --apply)

If you prefer to apply settings manually instead of using `--apply`:

```bash
# Option 1: Use --apply flag (recommended)
./sizer.sh --apply

# Option 2: Set environment variable and deploy fresh
RENNY_REPLICAS=18 ./deploy-local.sh

# Option 3: Edit values file directly
vim kubernetes/values/renny-values-cns.yaml
# Change: deployment.totalReplicas: 18
# Change: gpuTimeSlicing.replicasPerGpu: 18

# Option 4: Helm upgrade (if already deployed)
helm upgrade renny ./renny \
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
kubectl get pods -n uneeq -w

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
    kubectl scale deployment/renny -n uneeq --replicas=$count

    # Wait for all pods ready
    kubectl wait --for=condition=ready pod -l app=renny -n uneeq --timeout=300s

    # Record metrics for 60 seconds
    echo "Recording metrics..."
    nvidia-smi --query-gpu=timestamp,memory.used,memory.total,utilization.gpu --format=csv -l 5 | tee "metrics_${count}_rennys.csv" &
    PID=$!
    sleep 60
    kill $PID

    # Check for OOM or failures
    kubectl get pods -n uneeq | grep -E "Error|OOM|CrashLoop" && echo "FAILURE at $count" && break

    echo "Success with $count Rennys"
    echo "---"
done
EOF
chmod +x test-capacity.sh
./test-capacity.sh
```

#### Step 3: Stress Test (Concurrent Sessions)

Health-endpoint load (e.g. locust against `:8082/health`) does **not** exercise session
capacity — it measures an HTTP handler, not rendering. Test real concurrency with real
sessions:

- **Tool**: [multirender-tester](https://github.com/uneeq-digital-humans/multirender-tester)
  drives N concurrent real sessions (session brokering, WebRTC, TTS, rendering) with
  randomized speech, headless or interactive.
- **Full methodology** (delivery gates, per-session FPS, descending concurrency ladders,
  10-minute stability holds, branded PDF report): the `renny-density-report` skill in the
  UneeQ Claude Code marketplace packages the complete procedure used for the July 2026
  RTX PRO 6000 capacity report.
- Measure at a defined FPS floor (30 FPS is UneeQ's lip-sync quality bar; report 20 FPS
  numbers alongside if comparing against older tests), on warmed renderers, and count a
  configuration as stable only if a sustained hold completes without renderer restarts.

#### Step 4: Resolution/Quality Matrix Test

```bash
# Test each configuration
for resolution in "1920x1080" "3840x2160"; do
    for quality in "web" "miniprem"; do
        echo "Testing: $resolution @ $quality"

        # Update deployment
        kubectl set env deployment/renny -n uneeq \
            RENNY_QUALITY_LEVEL=$quality

        # Restart to apply (resolution requires pod restart with new args)
        kubectl rollout restart deployment/renny -n uneeq
        kubectl rollout status deployment/renny -n uneeq

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
watch -n 2 'kubectl get pods -n uneeq'

# Terminal 3: Watch events
kubectl get events -n uneeq -w

# Terminal 4: Pod logs
kubectl logs -n uneeq -l app=renny -f --tail=50
```

### Expected Results Matrix

**Measured** (July 2026, RTX PRO 6000 Blackwell 96GB, Renny 0.1400-8ce39 / UE 5.8,
driver 595.84, continuously speaking sessions, 20 FPS floor):

| Resolution | Web quality | MiniPrem quality (ray-traced) |
|------------|-------------|-------------------------------|
| 480p | 8 | 4 |
| 720p | 8 | 4 |
| 1080p | 8 | 3 |
| 1440p | 7 | 2 |
| 4K | 5 | 1 |

At UneeQ's 30 FPS lip-sync bar the numbers are lower (e.g. 1080p: 5 web / 2 miniprem).

**Estimates** (unvalidated, VRAM-model only — see caution below):

| GPU | 1080p Web | 1080p MiniPrem | 4K Web | 4K MiniPrem |
|-----|-----------|----------------|--------|-------------|
| T4 (16GB) | 3-4 | 2-3 | 1-2 | 1 |
| A10G (24GB) | 5-6 | 4-5 | 2-3 | 2 |
| L40 (48GB) | 12-14 | 10-12 | 6-8 | 5-6 |
| A100 40GB | 10-12 | 8-10 | 5-6 | 4-5 |
| A100 80GB | 20-22 | 18-20 | 13-14 | 11-12 |

**Caution — the sizer models VRAM only, but GPU compute is usually the binding
constraint.** On measured hardware the card ran out of rendering throughput long before
VRAM at MiniPrem quality (e.g. VRAM would fit ~9 4K sessions; compute sustained 1-2 at
quality floors). Treat VRAM-model estimates as upper bounds and validate with real
sessions (Step 3). Results also vary with thermal throttling, other GPU workloads, the
specific renny version (5.6 vs 5.8 differ significantly by quality path), and scene
complexity.

---

## Troubleshooting

### GPU Not Detected
```bash
nvidia-smi  # Should show GPU info
lspci | grep -i nvidia  # Should show GPU device
```

### Pods Stuck Pending
```bash
kubectl describe pod -n uneeq  # Check events
kubectl get nodes -o jsonpath='{.items[*].status.allocatable}'  # Check GPU resources
```

### Out of Memory
```bash
# Reduce replicas
kubectl scale deployment/renny -n uneeq --replicas=2

# Check which pods are using GPU memory
nvidia-smi pmon -s m
```

### Time-Slicing Not Working
```bash
# Verify configmap exists
kubectl get configmap -n gpu-operator

# Check cluster policy
kubectl get clusterpolicy -n gpu-operator -o yaml
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
kubectl logs -n uneeq -l app=renny -f

# Restart all Rennys
kubectl rollout restart deployment/renny -n uneeq

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

---

## Digital Human Stack (Dell Deployment)

Three additional pods installed **additively** alongside the existing renny/vLLM/Flowise stack.
No existing manifests are modified.

### Pods

| Pod | Image | GPU? | VRAM | Port |
|-----|-------|------|------|------|
| `digitalhuman-interface` | `cr.uneeq.io/uneeq/digitalhuman-interface:latest` | No | 0 | 80 |
| `digitalhuman-websocket-api` | `cr.uneeq.io/uneeq/digitalhuman-websocket-api:latest` | No | 0 | 3000 (HTTP), 3001 (WS) |
| `digitalhuman-asr` | `nvcr.io/nim/nvidia/nemotron-asr-streaming:latest` + `cr.uneeq.io/uneeq/riva-ws-proxy:latest` | Yes | ~15 GiB | 8000 (WS proxy) |

**Pin versions for production**: `:latest` is acceptable for lab bring-up only. For any
deployment whose behavior you need to reproduce (or support), pin exact tags and record
the resolved image digests.

### VRAM Budget (RTX Pro 6000, 96 GiB)

| Pod | VRAM |
|-----|------|
| renny ×4 (time-sliced) | ~48 GiB |
| digitalhuman-asr (Nemotron NIM) | ~15 GiB |
| vLLM/NIM (optional) | up to 30 GiB |
| **Total worst-case** | ~93 GiB — fits within 96 GiB |

### Browser Hostnames

Added to `/etc/hosts` by the installer:

```
127.0.0.1 digitalhuman.miniprem
127.0.0.1 digitalhuman-api.miniprem
127.0.0.1 digitalhuman-asr.miniprem
```

### Required Secrets

| Secret | How to provide |
|--------|---------------|
| `NGC_API_KEY` | Set env var `NGC_API_KEY` before running `deploy-local.sh` |
| `DH_WS_API_KEY` | Optional – set env var; used as `HTTP_SERVICE_API_KEY` in the WS API pod |
| Harbor credentials | Entered interactively (same as renny) |

### Build Images

```bash
cd kubernetes/scripts
./build-digitalhuman-images.sh          # builds and pushes :latest
./build-digitalhuman-images.sh v1.2.3   # also tags :v1.2.3
```

Sources:
- Interface → `../../dell-kiosk-application/interface/`
- WS API → `../../../websocket-api/`
- RIVA WS Proxy → `../digitalhuman-asr/ws-proxy-src/`

### Verify After Deployment

```bash
kubectl get pods -n uneeq -l 'app in (digitalhuman-interface,digitalhuman-websocket-api,digitalhuman-asr)'
kubectl get ingress -n uneeq
curl -I http://digitalhuman.miniprem
curl http://digitalhuman-api.miniprem/health
# Browser: http://digitalhuman.miniprem → click avatar → speak → digital human responds
```

### Debug

```bash
# Interface
kubectl logs -n uneeq -l app=digitalhuman-interface -f

# WS API
kubectl logs -n uneeq -l app=digitalhuman-websocket-api -f

# Nemotron NIM (model download progress)
kubectl logs -n uneeq -l app=digitalhuman-asr -c nemotron-asr -f

# RIVA WS proxy
kubectl logs -n uneeq -l app=digitalhuman-asr -c riva-ws-proxy -f

# Port-forward proxy for local testing
kubectl port-forward -n uneeq svc/digitalhuman-asr 8000:8000
```
