# 🆔 MiniPrem Telemetry Identifiers Cheatsheet

## Core Identifiers

```
┌──────────────────┬────────────────────────┬───────────────┬─────────────────┐
│ Identifier       │ Purpose                │ Scope         │ Persistence     │
├──────────────────┼────────────────────────┼───────────────┼─────────────────┤
│ installation_id  │ Track Renny instance   │ Per pod/ctnr  │ Regen on reinstall │
│ machine_id       │ Track physical GPU     │ Per GPU node  │ Survives reinstalls│
│ instance_name    │ Human-readable name    │ Per pod/ctnr  │ Changes on recreate│
│ node_name        │ K8s node identifier    │ Per K8s node  │ Persistent in cluster│
└──────────────────┴────────────────────────┴───────────────┴─────────────────┘
```

---

## 🐳 Ubuntu Docker Deployment

**Scenario:** 3 People Install MiniPrem on Their Laptops

```
Machine 1 (Tyler's Laptop)
├─ GPU: RTX 4090 (UUID: GPU-abc123...)
├─ machine_id: "8f3a9b2c..." (SHA-256 of GPU UUID)
└─ Docker Container: "renny"
   ├─ installation_id: "docker-ubuntu-1729622400-xyz789"
   ├─ instance_name: "c7f8a9b0c1d2" (container ID)
   ├─ instance_type: "docker-container"
   ├─ node_name: null
   └─ platform: "docker-ubuntu"

Machine 2 (Sarah's Desktop)
├─ GPU: RTX 3080 (UUID: GPU-def456...)
├─ machine_id: "1a2b3c4d..." (different GPU hash)
└─ Docker Container: "renny"
    └─ installation_id: "docker-ubuntu-1729622500-abc123"

Machine 3 (Mike's Workstation)
├─ GPU: RTX 4080 (UUID: GPU-ghi789...)
├─ machine_id: "9z8y7x6w..." (different GPU hash)
└─ Docker Container: "renny"
    └─ installation_id: "docker-ubuntu-1729622600-def456"
```

**Dashboard Shows:**
```
Unique Machines: 3      (3 distinct GPUs)
Active Rennys: 3        (3 Docker containers)
Active Machines: 3      (all 3 machines active)

Platform Distribution:
  docker-ubuntu: 3 total, 3 active
```

### What Happens on Reinstall?

```
Tyler reinstalls MiniPrem on his laptop

BEFORE:
├─ machine_id: "8f3a9b2c..." (GPU hash)
└─ installation_id: "docker-ubuntu-OLD"

AFTER:
├─ machine_id: "8f3a9b2c..." ← SAME (same GPU!)
└─ installation_id: "docker-ubuntu-NEW" ← NEW

Result:
  Unique Machines: Still 3 (same GPU detected)
  Active Rennys: Still 3 (new container replaces old)
  Total install events: 4 (audit trail)
```

---

## ☸️ Kubernetes EKS Deployment

**Scenario:** 2 GPU Nodes, 4 Pods Per Node (Time-Slicing)

```
EKS Cluster: production-eks
Region: us-east-1

┌─────────────────────────────────────────────────────────────┐
│ Node 1: ip-10-0-1-50.ec2.internal                           │
│ ├─ GPU: A10G (UUID: GPU-node1-uuid...)                      │
│ ├─ machine_id: "aabbccdd..." (SHA-256 hash)                 │
│ │                                                            │
│ ├─ Pod 1: renny-gpu-0-abc123                                │
│ │  ├─ installation_id: "eks-pod1-xyz"                       │
│ │  ├─ machine_id: "aabbccdd..." ← SHARED                    │
│ │  └─ node_name: "ip-10-0-1-50.ec2.internal"               │
│ │                                                            │
│ ├─ Pod 2: renny-gpu-0-def456                                │
│ │  ├─ installation_id: "eks-pod2-abc"                       │
│ │  └─ machine_id: "aabbccdd..." ← SAME GPU                  │
│ │                                                            │
│ ├─ Pod 3: renny-gpu-0-ghi789                                │
│ │  └─ machine_id: "aabbccdd..." ← SAME GPU                  │
│ │                                                            │
│ └─ Pod 4: renny-gpu-0-jkl012                                │
│    └─ machine_id: "aabbccdd..." ← SAME GPU                  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Node 2: ip-10-0-1-51.ec2.internal                           │
│ ├─ GPU: A10G (UUID: GPU-node2-uuid...) ← DIFFERENT          │
│ ├─ machine_id: "55667788..." (different hash)               │
│ │                                                            │
│ └─ Pods 5-8: All share node 2's machine_id                  │
│    └─ machine_id: "55667788..." ← SHARED                    │
└─────────────────────────────────────────────────────────────┘
```

**Dashboard Shows:**
```
Unique Machines: 2      (2 GPU nodes)
Active Rennys: 8        (8 pods total)
Active Machines: 2      (both nodes active)

Platform Distribution:
  eks: 8 total, 8 active
```

---

## 🔄 Kubernetes Pod Lifecycle

### Scale Up: 4 → 8 Pods on Node 1

```
BEFORE:
Node 1 (machine_id: "aabbccdd...")
└─ Pods 1-4: 4 pods running

AFTER (kubectl scale --replicas=8):
Node 1 (machine_id: "aabbccdd...") ← SAME
├─ Pods 1-4: Original pods (same installation_ids)
└─ Pods 5-8: NEW pods
   ├─ installation_id: "eks-new-pod5" ← NEW
   └─ machine_id: "aabbccdd..." ← SAME GPU

Result:
  Unique Machines: Still 1
  Active Rennys: 8 (4 old + 4 new)
  Total events: 8 (audit trail)
```

### Rolling Update: Delete/Recreate Pods

```
BEFORE:
Node 1
├─ Pod 1: id="eks-old-1", machine="aabbccdd..."
├─ Pod 2: id="eks-old-2", machine="aabbccdd..."
├─ Pod 3: id="eks-old-3", machine="aabbccdd..."
└─ Pod 4: id="eks-old-4", machine="aabbccdd..."

AFTER (kubectl rollout restart):
Node 1
├─ Pod 5: id="eks-new-1", machine="aabbccdd..." ← NEW POD
├─ Pod 6: id="eks-new-2", machine="aabbccdd..." ← NEW POD
├─ Pod 7: id="eks-new-3", machine="aabbccdd..." ← NEW POD
└─ Pod 8: id="eks-new-4", machine="aabbccdd..." ← NEW POD

Result:
  Unique Machines: Still 1 (SAME GPU!)
  Active Rennys: Still 4 (new pods replace old)
  Total events: 8 (4 old + 4 new = audit trail)
```

---

## 🆚 Docker vs Kubernetes Comparison

### Deployment Pattern
```
DOCKER:
  1 container = 1 machine = 1 GPU
  Ratio: 1:1 (container per GPU)

KUBERNETES:
  N pods = 1 node = 1 GPU
  Ratio: 2-4:1 (pods per GPU with time-slicing)
```

### Identifier Behavior
```
┌──────────────────┬─────────────────────┬──────────────────────┐
│                  │ Docker              │ Kubernetes           │
├──────────────────┼─────────────────────┼──────────────────────┤
│ machine_id       │ Unique per GPU      │ Shared on same node  │
│ installation_id  │ Unique per container│ Unique per pod       │
│ instance_name    │ Container ID (hex)  │ Pod name (friendly)  │
│ node_name        │ null                │ K8s node hostname    │
│ Reinstall Impact │ New install_id,     │ New pod install_ids, │
│                  │ same machine_id     │ same machine_id      │
└──────────────────┴─────────────────────┴──────────────────────┘
```

---

## 📊 Dashboard Interpretation Guide

### Example Dashboard Reading

```
Dashboard Shows:
├─ Unique Machines: 25
├─ Active Rennys: 78
├─ Active Machines: 24
└─ Platform Distribution:
    ├─ eks: 40 total, 38 active
    ├─ docker-ubuntu: 20 total, 20 active
    ├─ aks: 12 total, 12 active
    └─ gke: 6 total, 5 active
```

### What This Means

```
Unique Machines: 25
└─> 25 distinct GPU nodes across ALL platforms

Active Rennys: 78
└─> 78 pods/containers currently running

Active Machines: 24
└─> 24 of 25 GPU nodes have ≥1 active Renny
    (1 node offline)

eks: 40 total
└─> 40 Kubernetes pods in EKS clusters

docker-ubuntu: 20
└─> 20 individual Docker containers
    (usually = 20 people/machines)
```

### Calculate Time-Slicing Ratio

```
If dashboard shows:
  - eks: 40 total pods
  - Unique Machines: 25 total
  - docker-ubuntu: 20 machines

Then:
  EKS nodes ≈ 25 - 20 = 5 nodes
  Time-slicing = 40 pods / 5 nodes = 8 pods/GPU

  ⚠️  8 pods/GPU is AGGRESSIVE
  ✅  Typical: 2-4 pods/GPU
```

---

## 🔑 Identifier Generation Reference

### machine_id (GPU-based)
```bash
# Query GPU UUID
nvidia-smi --query-gpu=uuid --format=csv,noheader -i 0

# Output example:
GPU-12345678-1234-1234-1234-123456789012

# Then SHA-256 hash:
echo -n "GPU-12345678..." | shasum -a 256
8f3a9b2c1d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0
```

### installation_id (generated at install)
```python
f"{platform}-{timestamp}-{random_string}"

# Examples:
"eks-1729622400-xyz789"
"docker-ubuntu-1729622500-abc123"
```

### instance_name (from system)
```python
platform.node()  # or hostname

# Docker output:
"c7f8a9b0c1d2"  # Container ID

# Kubernetes output:
"renny-gpu-0-abc123"  # Pod name
```

### node_name (Kubernetes only)
```python
os.getenv("NODE_NAME")  # From K8s downward API

# Example:
"ip-10-0-1-50.ec2.internal"
```

---

## 💡 Key Takeaways

```
1. machine_id = Physical hardware (GPU node)
   └─> Survives reinstalls, OS updates, driver changes

2. installation_id = Software instance (pod/container)
   └─> Changes on every reinstall/recreate

3. Docker: 1 container = 1 machine = 1 GPU
   Kubernetes: N pods = 1 node = 1 GPU

4. Platform Distribution counts RENNYS (instances),
   not machines

5. Reinstalls on same hardware = same machine_id,
   new installation_id
```

---

## 🚨 Common Misunderstandings

**WRONG:** "Unique Machines = number of EKS nodes + Docker installs"
**RIGHT:** Unique Machines = total distinct GPU nodes across ALL platforms

**WRONG:** "Platform Distribution shows number of Kubernetes clusters"
**RIGHT:** Platform Distribution shows number of PODS/CONTAINERS

**WRONG:** "Active Rennys = Active Machines"
**RIGHT:** Active Rennys ≥ Active Machines (time-slicing!)

---

## 📖 See Also

- `docs/TELEMETRY.md` - Complete telemetry system documentation
- `docs/TELEMETRY_URLS.md` - Dashboard and API endpoints
- `miniprem-monitor/backend/app/services/telemetry.py` - Implementation
