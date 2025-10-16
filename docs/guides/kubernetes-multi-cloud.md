<div align="center">

<img src="https://presales.services.uneeq.io/uneeq-internal/assets/logos/UneeQ+Logo+Horizontal+CMYK.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="https://presales.services.uneeq.io/uneeq-internal/assets/logos/UneeQ+Logo+Horizontal+Rev+White.png" alt="UneeQ Logo" class="logo-dark-mode" />

# Multi-Cloud Comparison Guide

> Choose the right cloud provider for your Renny deployment

</div>

## Table of Contents

- [Overview](#overview)
- [Quick Comparison](#quick-comparison)
- [Detailed Cost Analysis](#detailed-cost-analysis)
- [Technical Comparison](#technical-comparison)
- [Decision Framework](#decision-framework)
- [Migration Strategies](#migration-strategies)
- [License](#license)

## Overview

This guide helps you choose between AWS EKS, Azure AKS, and Google GKE (coming soon) for deploying Renny digital humans at scale. Each cloud provider has unique strengths, and the best choice depends on your specific requirements.

## Quick Comparison

### At a Glance

| Factor | AWS EKS | Azure AKS | Winner |
|--------|---------|-----------|--------|
| **Monthly Cost (10 nodes)** | $8,712 | $10,800 | 🏆 AWS (-19%) |
| **GPU Memory** | 24GB | 16GB | 🏆 AWS (+50%) |
| **Deployment Time** | 30-45 min | 35-50 min | 🏆 AWS |
| **Pods per GPU** | 2 (time-slicing) | 1 | 🏆 AWS |
| **System RAM** | 64GB | 110GB | 🏆 Azure (+72%) |
| **Ecosystem Maturity** | Mature (2018) | Mature (2018) | 🤝 Tie |
| **Ease of Setup** | Moderate | Moderate | 🤝 Tie |

### Recommendation Summary

<div class="success-box">
<strong>💰 Best Value:</strong> AWS EKS - 19% lower cost, better GPU utilization
</div>

<div class="info-box">
<strong>🏢 Best for Enterprise:</strong> Choose based on existing cloud infrastructure
</div>

## Detailed Cost Analysis

### 10-Node Deployment Breakdown

#### AWS EKS Monthly Costs

| Component | Specification | Quantity | Unit Cost | Monthly Cost |
|-----------|--------------|----------|-----------|--------------|
| GPU Compute | g5.4xlarge | 10 nodes | $1.18/hr | $8,496 |
| EKS Control Plane | Managed | 1 cluster | $0.10/hr | $73 |
| Control Nodes | t3.large | 2 nodes | $0.08/hr | $115 |
| NAT Gateways | High Availability | 3× | $0.045/hr | $97 |
| Public IPs | Elastic IPs | 3× | $3.60/mo | $11 |
| EBS Volumes | gp3 | 500GB | $0.08/GB | $40 |
| Data Transfer | Outbound | 500GB | $0.09/GB | $45 |
| CloudWatch | Logs + Metrics | 50GB | $2/GB | $100 |
| **Total** | | | | **$8,977/month** |

#### Azure AKS Monthly Costs

| Component | Specification | Quantity | Unit Cost | Monthly Cost |
|-----------|--------------|----------|-----------|--------------|
| GPU Compute | NC16as_T4_v3 | 10 nodes | $1.50/hr | $10,800 |
| AKS Control Plane | Managed | 1 cluster | $0.10/hr | $73 |
| System Nodes | Standard_D4s_v3 | 2 nodes | $0.20/hr | $288 |
| Load Balancer | Standard SKU | 1× | ~$25/mo | $25 |
| Public IPs | Standard SKU | 3× | $4/mo | $12 |
| Managed Disks | Premium SSD | 500GB | $0.15/GB | $75 |
| Data Transfer | Outbound | 500GB | $0.05/GB | $25 |
| Azure Monitor | Log Analytics | 50GB | $2.50/GB | $125 |
| **Total** | | | | **$11,423/month** |

### Cost Difference Analysis

**Monthly Savings with AWS EKS:** $2,446 (21.4%)
**Annual Savings with AWS EKS:** $29,352

**Primary Cost Drivers:**
1. **GPU Compute:** AWS g5.4xlarge is $0.32/hour cheaper than Azure NC16as_T4_v3
2. **Control Nodes:** AWS t3.large vs Azure Standard_D4s_v3 (Azure 2.5× more expensive)
3. **Networking:** Azure Load Balancer cheaper than AWS NAT Gateways, but offset by higher compute

### Cost at Different Scales

| Scale | AWS EKS | Azure AKS | AWS Savings |
|-------|---------|-----------|-------------|
| **5 nodes** | ~$4,712/mo | ~$5,925/mo | $1,213/mo (20%) |
| **10 nodes** | ~$8,977/mo | ~$11,423/mo | $2,446/mo (21%) |
| **15 nodes** | ~$13,242/mo | ~$17,173/mo | $3,931/mo (23%) |
| **20 nodes** | ~$17,507/mo | ~$22,923/mo | $5,416/mo (24%) |

<div class="tip-box">
<strong>💡 Insight:</strong> AWS EKS cost advantage increases with scale due to better GPU utilization (2 pods per GPU vs 1).
</div>

### 3-Year Total Cost of Ownership (TCO)

| Cost Factor | AWS EKS | Azure AKS |
|-------------|---------|-----------|
| **Compute (Pay-As-You-Go)** | $323,172 | $411,228 |
| **Compute (1-Yr Reserved, -30%)** | $226,220 | $287,860 |
| **Compute (3-Yr Reserved, -40%)** | $193,903 | $246,737 |
| **Infrastructure** | $17,388 | $21,396 |
| **Data Transfer** | $1,620 | $900 |
| **Monitoring** | $3,600 | $4,500 |
| **Support (5% of compute)** | $11,610 | $14,594 |
| **3-Year TCO (Reserved)** | **$228,121** | **$288,127** |
| **Savings with AWS** | - | **$59,006 (21%)** |

## Technical Comparison

### GPU Specifications

#### AWS g5.4xlarge (NVIDIA A10G)

| Spec | Value | Use Case |
|------|-------|----------|
| **Architecture** | Ampere (2nd gen RT cores) | Latest GPU architecture |
| **CUDA Cores** | 9,216 | High compute throughput |
| **Tensor Cores** | 288 | AI/ML acceleration |
| **RT Cores** | 72 | Hardware ray tracing |
| **GPU Memory** | 24GB GDDR6 | 🏆 Supports 2 Renny pods per GPU |
| **Memory Bandwidth** | 600 GB/s | High-bandwidth workloads |
| **TDP** | 150W | Power efficient |
| **Driver Support** | Standard NVIDIA | GPU Operator compatible |

#### Azure NC16as_T4_v3 (NVIDIA T4)

| Spec | Value | Use Case |
|------|-------|----------|
| **Architecture** | Turing (1st gen RT cores) | Proven architecture |
| **CUDA Cores** | 2,560 | Balanced compute |
| **Tensor Cores** | 320 | AI inference |
| **RT Cores** | 40 | Ray tracing capable |
| **GPU Memory** | 16GB GDDR6 | Best for 1 Renny pod per GPU |
| **Memory Bandwidth** | 320 GB/s | Standard bandwidth |
| **TDP** | 70W | Very power efficient |
| **Driver Support** | Standard NVIDIA | GPU Operator compatible |

### GPU Time-Slicing Comparison

**AWS EKS (2 pods per GPU):**
```
g5.4xlarge (24GB A10G)
├── Virtual GPU 1 → Renny Pod 1 (~6GB, 30% util)
└── Virtual GPU 2 → Renny Pod 2 (~6GB, 30% util)
Total: ~60% utilization, $0.59/pod/hour
```

**Azure AKS (1 pod per GPU):**
```
NC16as_T4_v3 (16GB T4)
└── Full GPU → Renny Pod 1 (~4-6GB, 40% util)
Total: ~40% utilization, $1.50/pod/hour
```

**Cost per Pod:**
- AWS: $0.59/hour per pod
- Azure: $1.50/hour per pod
- **AWS is 2.5× cheaper per pod**

### Network Performance

| Feature | AWS EKS | Azure AKS |
|---------|---------|-----------|
| **Network Plugin** | AWS VPC CNI | Azure CNI |
| **Max Pods per Node** | 110 | 250 |
| **Network Bandwidth** | Up to 25 Gbps | Up to 32 Gbps |
| **Latency** | ~0.1-0.3ms intra-AZ | ~0.1-0.3ms intra-region |
| **IPv6 Support** | ✅ Yes | ✅ Yes |
| **Network Policies** | Calico/Cilium | Calico/Azure NPM |

### Storage Performance

| Feature | AWS EKS | Azure AKS |
|---------|---------|-----------|
| **Default Storage** | EBS gp3 | Azure Premium SSD |
| **IOPS (per disk)** | 3,000-16,000 | 120-20,000 |
| **Throughput** | 125-1,000 MB/s | 25-900 MB/s |
| **Snapshot Support** | ✅ EBS Snapshots | ✅ Azure Snapshots |
| **Cost (1TB)** | $80/month (gp3) | $135/month (Premium) |

## Decision Framework

### Choose AWS EKS If:

<div class="success-box">

**🏆 Best Overall Value**

✅ **Cost is a priority** - 21% cheaper than Azure
✅ **Maximum GPU utilization** - 2 pods per GPU saves money
✅ **Higher GPU memory needs** - 24GB vs 16GB for future growth
✅ **Existing AWS infrastructure** - S3, Lambda, RDS, etc.
✅ **AWS expertise in team** - Faster deployment and troubleshooting
✅ **Mature ecosystem** - More community support and tooling
✅ **Multi-region requirements** - AWS has more regions with GPU availability

</div>

### Choose Azure AKS If:

<div class="info-box">

**🏢 Best for Azure-First Organizations**

✅ **Existing Azure infrastructure** - Cosmos DB, Functions, etc.
✅ **Microsoft-centric organization** - Office 365, Azure AD integration
✅ **Enterprise Agreement with Microsoft** - Existing volume discounts
✅ **Azure expertise in team** - Faster deployment and troubleshooting
✅ **Simpler GPU configuration** - 1 pod per GPU is easier to manage
✅ **More system RAM** - 110GB vs 64GB per node
✅ **Regional requirements** - Better availability in specific regions

</div>

### Choose Google GKE If (Coming Soon):

<div class="tip-box">

**🚀 Best for GCP Ecosystem**

✅ **Existing GCP infrastructure** - BigQuery, Cloud Functions, etc.
✅ **Per-second billing** - Most granular cost control
✅ **Native GPU support** - Simplest GPU setup
✅ **GCP expertise in team** - Faster deployment
✅ **Kubernetes-first approach** - GKE pioneered managed Kubernetes

</div>

### Decision Tree

```
Start
  │
  ├─ Do you have existing cloud infrastructure?
  │   ├─ Yes → Use that cloud (avoid migration costs)
  │   └─ No → Continue
  │
  ├─ Is cost the primary concern?
  │   ├─ Yes → AWS EKS (21% cheaper)
  │   └─ No → Continue
  │
  ├─ Do you need maximum GPU memory?
  │   ├─ Yes → AWS EKS (24GB vs 16GB)
  │   └─ No → Continue
  │
  ├─ Are you a Microsoft shop?
  │   ├─ Yes → Azure AKS (Azure AD integration)
  │   └─ No → AWS EKS (default choice)
```

## Migration Strategies

### Moving from EKS to AKS

**Preparation (1-2 weeks):**
1. Request Azure GPU quotas (160+ vCPUs)
2. Create Azure service principal
3. Test AKS deployment in non-production
4. Validate application compatibility

**Migration Steps (1 day):**
1. Deploy AKS cluster parallel to EKS
2. Update DNS to point to AKS load balancer
3. Monitor for 24-48 hours
4. Destroy EKS cluster once stable

**Key Differences to Handle:**
- GPU time-slicing: 2 pods/GPU → 1 pod/GPU (adjust replica count)
- Networking: VPC CNI → Azure CNI (different IP allocation)
- Storage: EBS → Azure Disks (re-provision volumes)
- Monitoring: CloudWatch → Azure Monitor (update dashboards)

### Moving from AKS to EKS

**Preparation (1-2 weeks):**
1. Request AWS Service Quotas (GPU instances)
2. Configure AWS CLI and credentials
3. Test EKS deployment in non-production
4. Adjust time-slicing configuration (1 → 2 pods/GPU)

**Migration Steps (1 day):**
1. Deploy EKS cluster parallel to AKS
2. Enable GPU time-slicing (double pods per node)
3. Update DNS to point to EKS load balancer
4. Monitor for 24-48 hours
5. Destroy AKS cluster once stable

**Key Differences to Handle:**
- GPU time-slicing: 1 pod/GPU → 2 pods/GPU (adjust replica count)
- Networking: Azure CNI → VPC CNI (different pod IP allocation)
- Storage: Azure Disks → EBS (re-provision volumes)
- Monitoring: Azure Monitor → CloudWatch (update dashboards)

### Multi-Cloud Strategy

**Active-Active (High Availability):**
- Deploy on both AWS and Azure
- Global load balancer distributes traffic
- **Cost:** 2× infrastructure costs
- **Benefit:** Zero downtime, geographic redundancy

**Active-Passive (Disaster Recovery):**
- Primary on one cloud, standby on another
- Switch during outages or maintenance
- **Cost:** 1× primary + minimal standby costs
- **Benefit:** Business continuity insurance

---

## License

This multi-cloud guide is part of the MiniPrem platform, licensed under the MIT License - see the [LICENSE](../../LICENSE) file for details.

---

## Copyright

<div align="center">

**© 2025 UneeQ. All rights reserved.**

<img src="https://presales.services.uneeq.io/uneeq-internal/assets/logos/UneeQ+Logo+Horizontal+CMYK.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="https://presales.services.uneeq.io/uneeq-internal/assets/logos/UneeQ+Logo+Horizontal+Rev+White.png" alt="UneeQ Logo" class="logo-dark-mode" />

**Digital Humans. Unlimited Possibilities.**

[www.digitalhumans.com](https://www.digitalhumans.com) | [support@digitalhumans.com](mailto:support@digitalhumans.com)

</div>
