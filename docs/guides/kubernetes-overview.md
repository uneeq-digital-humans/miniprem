<div align="center">

<img src="https://presales.services.uneeq.io/uneeq-internal/assets/logos/UneeQ+Logo+Horizontal+CMYK.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="https://presales.services.uneeq.io/uneeq-internal/assets/logos/UneeQ+Logo+Horizontal+Rev+White.png" alt="UneeQ Logo" class="logo-dark-mode" />

# Multi-Cloud Kubernetes Deployment

> Scale your MiniPrem digital humans to production with AWS EKS, Azure AKS, or Google GKE

</div>

## Table of Contents

- [Overview](#overview)
- [Cloud Provider Comparison](#cloud-provider-comparison)
- [Choosing the Right Cloud](#choosing-the-right-cloud)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Common Features](#common-features)
- [Cloud-Specific Guides](#cloud-specific-guides)
- [Multi-Cloud Management](#multi-cloud-management)
- [Cost Optimization](#cost-optimization)
- [License](#license)

## Overview

MiniPrem provides **production-ready Kubernetes deployments** across multiple cloud providers, enabling you to deploy Renny digital humans at scale with GPU acceleration, auto-scaling, and high availability.

### Supported Cloud Providers

<div class="cloud-grid">

| Cloud | Status | GPU Instance | GPU Memory | Cost (10 nodes) |
|-------|--------|-------------|------------|-----------------|
| **AWS EKS** | ✅ Production | g5.4xlarge (A10G) | 24GB | ~$8,712/month |
| **Azure AKS** | ✅ Production | NC16as_T4_v3 (T4) | 16GB | ~$10,800/month |
| **Google GKE** | 🚧 In Development | n1-standard-16 + T4 | 16GB | TBD |

</div>

### Key Benefits

- **🌐 Multi-Cloud Flexibility** - Deploy on your preferred cloud provider
- **🚀 One-Click Deployment** - Automated infrastructure provisioning (~30-50 minutes)
- **📈 Auto-Scaling** - Dynamically scale from 10-20 Renny instances
- **🎮 GPU Acceleration** - NVIDIA GPU Operator with time-slicing support
- **🔒 Production-Grade Security** - Private subnets, network policies, RBAC
- **📊 Cloud-Native Monitoring** - Integrated logging and metrics
- **💰 Cost Optimization** - GPU time-slicing, auto-scaling, spot instances

## Cloud Provider Comparison

### Feature Matrix

| Feature | AWS EKS | Azure AKS | Google GKE |
|---------|---------|-----------|------------|
| **Deployment Script** | ✅ deploy.sh | ✅ deploy.sh | 🚧 Coming Soon |
| **GPU Instance Type** | g5.4xlarge | NC16as_T4_v3 | n1-standard-16 + T4 |
| **GPU Model** | NVIDIA A10G | NVIDIA T4 | NVIDIA T4 |
| **GPU Memory** | 24GB GDDR6 | 16GB GDDR6 | 16GB GDDR6 |
| **vCPUs per Node** | 16 | 16 | 16 |
| **RAM per Node** | 64GB | 110GB | 60GB |
| **Hourly Cost (per node)** | ~$1.18 | ~$1.50 | ~$1.35 |
| **Monthly Cost (10 nodes)** | ~$8,712 | ~$10,800 | ~$9,720 |
| **Deployment Time** | 30-45 min | 35-50 min | TBD |
| **GPU Operator** | ✅ Automatic | ✅ Automatic | ✅ Native Support |
| **Time-Slicing** | ✅ 2 pods/GPU | ✅ 1 pod/GPU* | TBD |
| **Auto-Scaling** | ✅ 10-20 nodes | ✅ 10-20 nodes | TBD |
| **Multi-AZ** | ✅ 3 AZs | ✅ 3 AZs | TBD |
| **Monitoring** | CloudWatch | Azure Monitor | Stackdriver |
| **Networking** | AWS VPC CNI | Azure CNI | VPC-native |

<div class="info-box">
<strong>*Note:</strong> AKS T4 instances have 16GB VRAM (vs 24GB on EKS), so single pod per GPU is recommended for Renny workloads requiring 4-6GB per pod.
</div>

### Cost Comparison (10-Node Deployment)

| Component | AWS EKS | Azure AKS | Google GKE |
|-----------|---------|-----------|------------|
| **GPU Compute** | $8,520 | $10,800 | TBD |
| **Control Plane** | $73 | $73 | TBD |
| **Control Nodes** | $120 | $288 | TBD |
| **Networking** | $135 (NAT×3) | $25 (LB) | TBD |
| **Storage** | $50 | $75 | TBD |
| **Monitoring** | $100 | $125 | TBD |
| **Total Monthly** | **~$8,998** | **~$11,386** | TBD |

<div class="tip-box">
<strong>💡 Cost Savings:</strong>
<ul>
  <li><strong>Reserved Instances:</strong> Save 30-40% on compute costs</li>
  <li><strong>Spot Instances:</strong> Save 60-80% for dev/test environments</li>
  <li><strong>Auto-Scaling:</strong> Save ~40% during off-hours</li>
  <li><strong>Scheduled Shutdown:</strong> Save ~70% on nights/weekends</li>
</ul>
</div>

## Choosing the Right Cloud

### Decision Matrix

**Choose AWS EKS if:**
- ✅ Existing AWS infrastructure and expertise
- ✅ Prefer higher GPU memory (24GB for intensive workloads)
- ✅ Lower per-hour costs (~15% cheaper than AKS)
- ✅ Need mature ecosystem with extensive tooling
- ✅ Require AWS-specific services (S3, Lambda, etc.)
- ✅ Multi-region deployments in AWS regions

**Choose Azure AKS if:**
- ✅ Existing Azure infrastructure and expertise
- ✅ Microsoft/Azure-centric organization
- ✅ Azure AD integration requirements
- ✅ Prefer T4 GPUs (proven Unreal Engine compatibility)
- ✅ Need Azure-specific services (Cosmos DB, Functions, etc.)
- ✅ Enterprise Agreement with Microsoft

**Choose Google GKE if (Coming Soon):**
- ✅ Existing GCP infrastructure and expertise
- ✅ Prefer per-second billing (most granular)
- ✅ Native GPU support (simplest setup)
- ✅ Need GCP-specific services (BigQuery, Cloud Functions, etc.)
- ✅ Lower networking costs

### Regional Availability

#### AWS EKS (g5.4xlarge Availability)
- ✅ **us-east-1** (N. Virginia) - Primary
- ✅ **us-east-2** (Ohio) - Recommended
- ✅ **us-west-2** (Oregon)
- ✅ **eu-west-1** (Ireland)
- ✅ **ap-southeast-1** (Singapore)

#### Azure AKS (NC16as_T4_v3 Availability)
- ✅ **eastus** (East US) - Primary
- ✅ **westus2** (West US 2)
- ✅ **northeurope** (North Europe)
- ✅ **westeurope** (West Europe)
- ✅ **southeastasia** (Southeast Asia)

## Quick Start

### Prerequisites

All cloud providers require:

1. **Command-line tools:**
   - kubectl >= 1.28.0
   - Terraform >= 1.5.0
   - Helm >= 3.12.0

2. **Cloud-specific CLI:**
   - AWS: AWS CLI >= 2.3.0
   - Azure: Azure CLI >= 2.50.0
   - GCP: gcloud SDK >= 400.0

3. **Credentials:**
   - UneeQ tenant ID and API key
   - Docker Hub credentials
   - Cloud provider credentials

### Deployment Commands

The deployment script automatically detects your cloud provider or allows explicit selection:

```bash
cd kubernetes/

# Automatic cloud detection (recommended)
./scripts/deploy.sh

# Explicit cloud selection
./scripts/deploy.sh --cloud eks   # AWS EKS
./scripts/deploy.sh --cloud aks   # Azure AKS
./scripts/deploy.sh --cloud gke   # Google GKE (coming soon)

# With specific profile (AWS)
./scripts/deploy.sh --cloud eks --profile your-aws-profile
```

### Deployment Timeline

| Phase | EKS | AKS | Description |
|-------|-----|-----|-------------|
| **Prerequisites Check** | 2 min | 2 min | Verify tools and credentials |
| **Infrastructure (Terraform)** | 15-20 min | 15-20 min | VPC/VNet, cluster, node pools |
| **Node Join** | 3-5 min | 3-5 min | Nodes join cluster |
| **GPU Operator** | 5-10 min | 5-10 min | NVIDIA driver installation |
| **Renny Deployment** | 5-10 min | 5-10 min | Deploy application pods |
| **Configuration** | 3 min | 3 min | Auto-scaling, monitoring |
| **Total** | **30-45 min** | **35-50 min** | Complete deployment |

## Architecture

### Common Architecture Components

All cloud deployments share:

```
Cloud Provider
├── Virtual Network (VPC/VNet)
│   ├── Public Subnets (3 AZs)
│   │   └── NAT Gateways / Load Balancers
│   └── Private Subnets (3 AZs)
│       └── Kubernetes Cluster
│           ├── Control Plane (Managed)
│           ├── Control Node Pool
│           │   └── 2× Standard compute instances
│           └── GPU Node Pool
│               └── 10-20× GPU instances
│                   ├── NVIDIA GPU (A10G/T4)
│                   ├── GPU Operator (driver 580)
│                   └── Renny Pods (1-2 per GPU)
└── Cloud Monitoring (CloudWatch/Azure Monitor/Stackdriver)
```

### GPU Time-Slicing

GPU time-slicing allows multiple Renny pods to share a single physical GPU:

**AWS EKS (24GB A10G):**
```
g5.4xlarge Node
├── Virtual GPU 1 → Renny Pod 1 (~6GB, ~30% utilization)
└── Virtual GPU 2 → Renny Pod 2 (~6GB, ~30% utilization)
Total Utilization: ~60% (optimal cost/performance)
```

**Azure AKS (16GB T4):**
```
NC16as_T4_v3 Node
└── Full GPU → Renny Pod 1 (~4-6GB, ~40% utilization)
Reason: 16GB VRAM best used by single pod
```

### Network Architecture

All deployments use similar networking:

- **WebRTC/UDP:** Ports 22000-23000 (Pixel Streaming)
- **TURN/STUN:** Port 3478 (TCP/UDP)
- **HTTPS:** Port 443 (egress to *.uneeq.io)
- **Private Subnets:** All GPU nodes for security
- **High Availability:** Multi-AZ for resilience

## Common Features

### NVIDIA GPU Operator

All deployments use **NVIDIA GPU Operator v23.9.2** for consistent driver management:

- ✅ Automatic driver installation (driver 580)
- ✅ CUDA 12.8+ support
- ✅ GPU time-slicing configuration
- ✅ Device plugin for Kubernetes
- ✅ DCGM metrics exporter

**Driver Selection (Interactive Prompt):**
1. **Driver 580+** (Recommended) - Latest features, required for RTX 5090
2. **Driver 575+** (Stable) - Production-tested, maximum compatibility

### Auto-Scaling

All deployments support dynamic scaling:

```bash
# Scale to specific number of instances
./scripts/scale.sh 15

# Works with all cloud providers automatically
```

**Scaling Limits:**
- **Minimum:** 10 nodes (production baseline)
- **Maximum:** 20 nodes (tested capacity)
- **Scaling Time:** ~3-5 minutes per node

### Monitoring

Each cloud provider has integrated monitoring:

**AWS EKS:**
- CloudWatch Logs for application logs
- CloudWatch Container Insights for metrics
- CloudWatch Alarms for alerting

**Azure AKS:**
- Azure Monitor for container monitoring
- Log Analytics for log aggregation
- Azure Alerts for notifications

**Google GKE (Coming Soon):**
- Cloud Logging for application logs
- Cloud Monitoring for metrics
- Cloud Alerting for notifications

### Operations

Common operational commands work across all clouds:

```bash
# Check deployment status
./scripts/status.sh

# Scale instances
./scripts/scale.sh <number>

# View logs
kubectl logs -n uneeq-renderer <pod-name> -f

# Check GPU status
kubectl get nodes -L nvidia.com/gpu

# Destroy cluster
./scripts/destroy.sh
```

## Cloud-Specific Guides

### Detailed Setup Guides

- **[AWS EKS Deployment](kubernetes-eks.md)** - Complete AWS setup, VPC configuration, EKS-specific troubleshooting
- **[Azure AKS Deployment](kubernetes-aks.md)** - Azure account setup, GPU quotas, service principals, AKS configuration
- **[Multi-Cloud Comparison](kubernetes-multi-cloud.md)** - Detailed cost analysis, migration strategies, feature parity

### Quick Links

| Task | AWS EKS | Azure AKS |
|------|---------|-----------|
| **Account Setup** | [AWS Prerequisites](../../kubernetes/README.md#prerequisites) | [Azure Setup Guide](../../kubernetes/AZURE_SETUP.md) |
| **GPU Quota** | AWS Service Quotas | [Azure GPU Quotas](../../kubernetes/AZURE_SETUP.md#gpu-quota-requests) |
| **Deployment** | `./scripts/deploy.sh --cloud eks` | `./scripts/deploy.sh --cloud aks` |
| **Troubleshooting** | [EKS Troubleshooting](kubernetes-eks.md#troubleshooting) | [AKS Troubleshooting](kubernetes-aks.md#troubleshooting) |

## Multi-Cloud Management

### MiniPrem Monitor Support

The **MiniPrem Monitor** dashboard supports monitoring multiple cloud providers:

- ✅ Automatic cloud provider detection
- ✅ Multi-cluster context switching
- ✅ Unified pod and node monitoring
- ✅ Cloud-specific metrics display
- ✅ Cost tracking per provider

**Access MiniPrem Monitor:**
```bash
# Standalone monitor deployment
cd docker/
docker-compose -f docker-compose.monitor.yml up -d

# Access at http://localhost:3001
```

### Multi-Cluster kubectl Configuration

Manage multiple cloud clusters with kubectl contexts:

```bash
# List all contexts
kubectl config get-contexts

# Switch to EKS cluster
kubectl config use-context arn:aws:eks:us-east-1:123456789012:cluster/renny-prod

# Switch to AKS cluster
kubectl config use-context renny-aks-eastus

# MiniPrem Monitor automatically detects and allows switching
```

## Cost Optimization

### Cross-Cloud Cost Strategies

**1. Reserved Instances / Reserved Capacity**
- **AWS:** 1-year reserved (~30% savings), 3-year (~40% savings)
- **Azure:** 1-year reserved (~30% savings), 3-year (~40% savings)
- **Savings:** ~$3,000-4,000/month on 10-node deployment

**2. Spot / Preemptible Instances**
- **AWS:** EC2 Spot (~60-80% savings, 2-minute eviction notice)
- **Azure:** Spot VMs (~60-80% savings, 30-second eviction notice)
- **Use Case:** Dev/test environments only
- **Savings:** ~$6,000-8,000/month (non-production)

**3. Auto-Scaling During Off-Hours**
- Scale down to minimum (2-5 nodes) during nights/weekends
- **Savings:** ~40% reduction = $3,500-4,500/month

**4. Scheduled Shutdown**
- Stop entire cluster during off-hours
- **Savings:** ~70% reduction = $6,000-8,000/month
- **Caveat:** 5-10 minute startup time

**5. Right-Sizing**
- Start with 5 nodes, scale to 10 based on demand
- Monitor actual GPU utilization (target 60-70%)
- **Savings:** ~50% initial reduction

### Cost Monitoring

Track costs across all cloud providers:

```bash
# AWS
aws ce get-cost-and-usage --time-period Start=2025-10-01,End=2025-10-16 \
  --granularity DAILY --metrics BlendedCost

# Azure
az consumption usage list --start-date 2025-10-01 --end-date 2025-10-16

# GCP (coming soon)
gcloud billing accounts list
```

---

## License

This multi-cloud Kubernetes deployment is part of the MiniPrem platform, licensed under the MIT License - see the [LICENSE](../../LICENSE) file for details.

---

## Copyright

<div align="center">

**© 2025 UneeQ. All rights reserved.**

<img src="https://presales.services.uneeq.io/uneeq-internal/assets/logos/UneeQ+Logo+Horizontal+CMYK.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="https://presales.services.uneeq.io/uneeq-internal/assets/logos/UneeQ+Logo+Horizontal+Rev+White.png" alt="UneeQ Logo" class="logo-dark-mode" />

**Digital Humans. Unlimited Possibilities.**

[www.digitalhumans.com](https://www.digitalhumans.com) | [support@digitalhumans.com](mailto:support@digitalhumans.com)

</div>
