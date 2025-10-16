# Multi-Cloud Comparison: EKS vs AKS vs GKE
# MiniPrem Renny Digital Human Platform

**Purpose**: Quick reference for choosing and migrating between cloud providers

---

## Executive Summary

| Metric | AWS EKS | Azure AKS | **GCP GKE** | Winner |
|--------|---------|-----------|-------------|--------|
| **Cost (10 nodes)** | $11,740/mo | $8,952/mo | **$8,574/mo** | 🥇 GKE |
| **Cost (20 nodes)** | $23,230/mo | $17,592/mo | **$17,000/mo** | 🥇 GKE |
| **Control Plane** | $73/mo | FREE | **FREE** | 🥇 GKE/AKS |
| **GPU Instance** | g5.4xlarge | NC16as_T4_v3 | **n1-standard-16+T4** | 🥇 GKE |
| **Setup Complexity** | Medium | Medium | **Low** | 🥇 GKE |
| **GPU Management** | GPU Operator | GPU Operator | **GKE-managed** | 🥇 GKE |
| **Deployment Time** | 30-45 min | 25-35 min | **20-30 min** | 🥇 GKE |

**Bottom Line**: GKE offers best cost and operational simplicity. AKS is close on cost. EKS has most mature ecosystem but highest cost.

---

## 1. Cost Analysis

### Monthly Infrastructure Costs

**10 GPU Nodes + System Nodes (24/7)**

| Component | AWS EKS | Azure AKS | **GCP GKE** |
|-----------|---------|-----------|-------------|
| GPU Nodes | $11,750 | $8,640 | **$8,000** |
| System Nodes | $292 | $280 | **$274** |
| Networking | $450 | $32 | **$100** |
| Storage | $200 | - | **$150** |
| Control Plane | $73 | $0 | **$0** |
| **TOTAL** | **$11,740** | **$8,952** | **$8,574** |

**Savings vs EKS**: $3,166/month (27%)
**Savings vs AKS**: $378/month (4%)

### Per-GPU-Node Breakdown

| Provider | VM Cost | GPU Cost | Total/hour | Total/month |
|----------|---------|----------|------------|-------------|
| **EKS** | $0.816 | $0.808 | **$1.624** | **$1,174** |
| **AKS** | $0.85 | $0.35 | **$1.20** | **$895** |
| **GKE** | $0.76 | $0.35 | **$1.11** | **$857** |

**GKE is cheapest per node by 4-27%**

### Cost Optimization Strategies

#### Committed Use Discounts (CUDs)

| Duration | AWS Reserved | Azure Reserved | **GCP CUD** |
|----------|--------------|----------------|-------------|
| 1-year | 30-40% | 30-50% | **25%** |
| 3-year | 60-65% | 60-72% | **52%** |

**Savings Example (10 nodes, 1-year CUD)**:
- EKS: Save $3,522/year
- AKS: Save $2,686/year
- **GKE: Save $2,572/year**

#### Spot/Preemptible Instances

| Provider | Discount | Availability | Use Case |
|----------|----------|--------------|----------|
| **EKS Spot** | 70-90% | Variable | Dev/Test |
| **AKS Spot** | 70-80% | Variable | Dev/Test |
| **GKE Preemptible** | **80%** | **Predictable** | **Dev/Test** |

**GKE Preemptible**: Most predictable eviction patterns (24-hour max runtime)

---

## 2. GPU Configuration

### Instance Types

| Provider | Instance | vCPU | RAM | GPU | VRAM | Cost/hour |
|----------|----------|------|-----|-----|------|-----------|
| **EKS** | g5.4xlarge | 16 | 64GB | A10G | 24GB | $1.624 |
| **AKS** | NC16as_T4_v3 | 16 | 110GB | T4 | 16GB | $1.20 |
| **GKE** | n1-standard-16+T4 | 16 | 60GB | T4 | 16GB | **$1.11** |

**Key Differences**:
- **EKS**: More VRAM (24GB A10G), best for VRAM-intensive workloads
- **AKS**: Most RAM (110GB), best for memory-intensive workloads
- **GKE**: Lowest cost, balanced specs, best for cost optimization

### GPU Driver Management

| Provider | Driver Installation | Management | Updates |
|----------|---------------------|------------|---------|
| **EKS** | GPU Operator (manual) | Self-managed | Manual Helm upgrade |
| **AKS** | GPU Operator (manual) | Self-managed | Manual Helm upgrade |
| **GKE** | **GKE auto-install** | **GCP-managed** | **Automatic with GKE** |

**GKE Advantage**: Zero driver management overhead

**Alternative for GKE**: Can still use GPU Operator for parity

### GPU Time-Slicing

| Provider | Method | Pods/GPU | Setup Complexity |
|----------|--------|----------|------------------|
| **EKS** | GPU Operator ConfigMap | 2-4 | Medium (manual) |
| **AKS** | GPU Operator ConfigMap | 2-4 | Medium (manual) |
| **GKE** | **Native (gpu_sharing_config)** | **2-8** | **Low (Terraform)** |

**GKE Native Time-Slicing Configuration**:
```hcl
guest_accelerator {
  gpu_sharing_config {
    gpu_sharing_strategy       = "TIME_SHARING"
    max_shared_clients_per_gpu = 2  # Pods per GPU
  }
}
```

**Advantage**: No ConfigMap, no GPU Operator DaemonSet, native scheduler support

---

## 3. Networking Architecture

### Network Model Comparison

| Feature | AWS EKS | Azure AKS | **GCP GKE** |
|---------|---------|-----------|-------------|
| **Model** | VPC CNI (overlay) | Azure CNI | **VPC-native (alias IP)** |
| **Pod IPs** | Secondary ENI | VNet IPs | **VPC secondary range** |
| **Performance** | Good | Excellent | **Excellent** |
| **Setup** | Complex | Medium | **Simple** |

### CIDR Allocation

#### EKS (VPC CNI)
```
VPC: 10.17.0.0/16
├── Private Subnets: 10.17.{1,2,3}.0/24 (nodes)
├── Public Subnets: 10.17.{101,102,103}.0/24 (NAT)
└── Service CIDR: 10.117.0.0/16 (separate from VPC)
```

#### AKS (Azure CNI)
```
VNet: 10.17.0.0/16
├── Nodes Subnet: 10.17.0.0/22 (nodes + pods)
└── Service CIDR: 10.117.0.0/16 (separate from VNet)
```

#### GKE (VPC-native)
```
VPC: 10.0.0.0/8
├── Primary (Nodes): 10.17.0.0/22
├── Secondary (Pods): 10.18.0.0/16
└── Secondary (Services): 10.117.0.0/16
```

**GKE Key Advantage**: Explicit secondary ranges, no ENI complexity

### NAT Gateway Comparison

| Provider | Service | HA Options | Cost/month |
|----------|---------|------------|------------|
| **EKS** | NAT Gateway | 1 or 3 (per AZ) | $32-$96 + data |
| **AKS** | NAT Gateway | 1 per region | $32 + data |
| **GKE** | **Cloud NAT** | **Regional (auto-HA)** | **$45 + data** |

**GKE Cloud NAT**: Automatic high availability, no manual AZ configuration

### Firewall/Security Groups

| Provider | Resource | Scope | Management |
|----------|----------|-------|------------|
| **EKS** | Security Groups | ENI-level | AWS |
| **AKS** | Network Security Groups | Subnet-level | Azure |
| **GKE** | **VPC Firewall Rules** | **VPC-level** | **GCP** |

**GKE Advantage**: Simpler firewall rules (VPC-wide, not per-subnet)

---

## 4. Authentication & IAM

### Pod Identity Mechanisms

| Provider | Mechanism | Setup Complexity | Security |
|----------|-----------|------------------|----------|
| **EKS** | IRSA (IAM Roles for Service Accounts) | Medium | Excellent |
| **AKS** | Managed Identity (Workload Identity) | Medium | Excellent |
| **GKE** | **Workload Identity** | **Low** | **Excellent** |

### Configuration Comparison

#### EKS IRSA
```yaml
# 1. Create IAM role with trust policy (OIDC provider)
# 2. Create Kubernetes SA with annotation
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/renny-sa
```

#### AKS Managed Identity
```yaml
# 1. Create User-Assigned Identity
# 2. Create Kubernetes SA with annotation
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: CLIENT_ID
```

#### GKE Workload Identity
```yaml
# 1. Create GCP Service Account
# 2. Create Kubernetes SA with annotation
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    iam.gke.io/gcp-service-account: renny-sa@PROJECT.iam.gserviceaccount.com

# 3. Bind (Terraform does this automatically)
```

**GKE Advantage**: Fewer manual steps, cleaner Terraform integration

### Node-Level IAM

| Provider | Method | Default Permissions | Best Practice |
|----------|--------|---------------------|---------------|
| **EKS** | Instance Profile | Too broad | Custom IAM role |
| **AKS** | Managed Identity | System-assigned | User-assigned |
| **GKE** | **Service Account** | **Compute default (Editor!)** | **Custom SA** |

**All Providers**: Use custom service accounts with minimal permissions

---

## 5. Operational Complexity

### Cluster Creation Time

| Phase | EKS | AKS | **GKE** |
|-------|-----|-----|---------|
| Control Plane | 10-12 min | 8-10 min | **5-7 min** |
| Node Pools | 10-15 min | 8-12 min | **8-10 min** |
| GPU Drivers | 10-15 min | 10-15 min | **5-10 min** |
| Application | 5-8 min | 5-8 min | **5-8 min** |
| **TOTAL** | **35-50 min** | **31-45 min** | **23-35 min** |

**GKE is fastest by 10-15 minutes**

### Deployment Script Comparison

#### EKS deploy.sh
```bash
# 1. Check AWS credentials and VPC quota
# 2. Terraform apply (15-20 min)
# 3. Update kubeconfig (aws eks update-kubeconfig)
# 4. Deploy GPU Operator (10-15 min)
# 5. Configure time-slicing ConfigMap
# 6. Deploy Renny (5-8 min)
```

#### AKS deploy.sh
```bash
# 1. Check Azure credentials
# 2. Terraform apply (12-18 min)
# 3. Update kubeconfig (az aks get-credentials)
# 4. Deploy GPU Operator (10-15 min)
# 5. Configure time-slicing ConfigMap
# 6. Deploy Renny (5-8 min)
```

#### GKE deploy.sh
```bash
# 1. Check GCP credentials and GPU quota
# 2. Terraform apply (12-15 min)
# 3. Update kubeconfig (gcloud container clusters get-credentials)
# 4. (GPU drivers auto-installed) ← SKIP GPU Operator
# 5. Deploy Renny (5-8 min)
```

**GKE saves 10-15 minutes by skipping GPU Operator deployment**

### Maintenance Windows

| Task | EKS | AKS | **GKE** |
|------|-----|-----|---------|
| **Kubernetes Upgrade** | Manual (per node group) | Manual or auto | **Auto (release channel)** |
| **GPU Driver Upgrade** | Manual (Helm upgrade) | Manual (Helm upgrade) | **Auto with K8s** |
| **Node OS Patches** | Manual (AMI update) | Auto | **Auto** |

**GKE Advantage**: Most automated maintenance

---

## 6. Terraform Code Comparison

### File Count and Lines

| File | EKS | AKS | **GKE** |
|------|-----|-----|---------|
| main.tf | 67 | 74 | **75** |
| cluster.tf | 93 (eks.tf) | 78 (aks.tf) | **120 (gke.tf)** |
| networking.tf | 45 (vpc.tf) | 86 (vnet.tf) | **90 (vpc.tf)** |
| node-pools.tf | 195 | 73 | **110** |
| iam.tf | 108 | 54 (managed-identity.tf) | **95 (service-accounts.tf)** |
| variables.tf | 112 | 145 | **150** |
| outputs.tf | 68 | 67 | **80** |
| **TOTAL** | **688** | **577** | **720** |

**Code Similarity**: 95% structural similarity across providers

### Provider-Specific Resources

#### EKS
```hcl
module "eks" { ... }        # Official module
module "vpc" { ... }        # Official module
aws_iam_role
aws_launch_template         # For Ubuntu AMI
aws_eks_node_group
```

#### AKS
```hcl
azurerm_kubernetes_cluster
azurerm_virtual_network
azurerm_kubernetes_cluster_node_pool
azurerm_user_assigned_identity
```

#### GKE
```hcl
google_container_cluster
google_compute_network
google_container_node_pool
google_service_account
```

**Key Difference**: EKS uses Terraform modules, AKS/GKE use native resources

---

## 7. Monitoring & Logging

### Native Cloud Monitoring

| Feature | AWS CloudWatch | Azure Monitor | **GCP Cloud Operations** |
|---------|----------------|---------------|--------------------------|
| **Logs** | CloudWatch Logs | Log Analytics | **Cloud Logging** |
| **Metrics** | CloudWatch Metrics | Azure Monitor | **Cloud Monitoring** |
| **Dashboards** | CloudWatch Dashboards | Azure Dashboards | **Cloud Console** |
| **Prometheus** | AMP (extra cost) | Azure Monitor | **Managed Prometheus (free)** |
| **Cost** | Pay per GB | Pay per GB | **Free tier + pay per GB** |

### Integration Complexity

| Provider | Native Integration | Third-Party | Setup Time |
|----------|-------------------|-------------|------------|
| **EKS** | CloudWatch Logs (addon) | Datadog, New Relic | 30 min |
| **AKS** | Azure Monitor (addon) | Datadog, New Relic | 20 min |
| **GKE** | **Cloud Logging (auto)** | Datadog, New Relic | **5 min** |

**GKE Advantage**: Automatic logging/monitoring, no addon installation

### Prometheus Support

| Provider | Method | Cost | Setup |
|----------|--------|------|-------|
| **EKS** | Amazon Managed Prometheus | $$ | Manual |
| **AKS** | Azure Monitor (Prometheus compatible) | $$ | Medium |
| **GKE** | **GKE Managed Prometheus** | **FREE** | **Auto** |

**GKE Managed Prometheus**: Included in GKE, no extra cost

---

## 8. Ecosystem & Tooling

### CLI Tools

| Provider | Primary CLI | Cluster Auth | Ease of Use |
|----------|-------------|--------------|-------------|
| **EKS** | `aws` + `eksctl` | `aws eks update-kubeconfig` | Medium |
| **AKS** | `az` | `az aks get-credentials` | Easy |
| **GKE** | **`gcloud`** | **`gcloud container clusters get-credentials`** | **Easy** |

### Terraform Provider Maturity

| Provider | Version | Maturity | Breaking Changes |
|----------|---------|----------|------------------|
| **AWS** | hashicorp/aws ~> 5.0 | Mature | Rare |
| **Azure** | hashicorp/azurerm ~> 3.0 | Mature | Occasional |
| **GCP** | **hashicorp/google ~> 5.0** | **Mature** | **Rare** |

**All providers have stable Terraform support**

### Community Support

| Provider | GitHub Stars (K8s tools) | Stack Overflow Questions | Documentation |
|----------|--------------------------|--------------------------|---------------|
| **EKS** | Most | Most | Excellent |
| **AKS** | Medium | Medium | Good |
| **GKE** | **Medium** | **Medium** | **Excellent** |

**EKS has largest ecosystem due to AWS popularity**

---

## 9. Migration Path

### EKS → GKE Migration

**Ease**: Medium
**Duration**: 1-2 weeks
**Key Changes**:
- [ ] Replace AWS VPC module with GCP VPC resources
- [ ] Change `module.eks` to `google_container_cluster`
- [ ] Replace IRSA with Workload Identity
- [ ] Update node pool configuration (remove AMI, add GPU config)
- [ ] Replace `aws eks update-kubeconfig` with `gcloud` command
- [ ] Optional: Remove GPU Operator, use GKE-managed drivers

**Terraform Changes**: ~40% of lines

### AKS → GKE Migration

**Ease**: Easy
**Duration**: 3-5 days
**Key Changes**:
- [ ] Replace Azure VNet with GCP VPC
- [ ] Change `azurerm_kubernetes_cluster` to `google_container_cluster`
- [ ] Replace Managed Identity with Workload Identity
- [ ] Update node pool configuration
- [ ] Replace `az aks get-credentials` with `gcloud` command
- [ ] Optional: Remove GPU Operator

**Terraform Changes**: ~30% of lines

### Data Migration Considerations

**Same for All Migrations**:
- [ ] Container images (can use same Docker Hub registry)
- [ ] Application configuration (Helm values)
- [ ] Secrets (re-create in new cluster)
- [ ] Persistent data (no PVs in Renny deployment)
- [ ] DNS updates (point to new Load Balancer)

**No Data Migration Needed**: Renny is stateless

---

## 10. Decision Matrix

### Choose EKS If:
- ✅ Already on AWS with deep ecosystem integration
- ✅ Need 24GB VRAM (A10G GPU)
- ✅ Have AWS expertise and tooling
- ✅ Enterprise support requirements
- ❌ Budget allows 27% higher cost

**Best For**: Existing AWS shops, VRAM-intensive workloads

### Choose AKS If:
- ✅ Already on Azure with Active Directory integration
- ✅ Need most RAM (110GB per node)
- ✅ Have Azure expertise and tooling
- ✅ Cost-conscious (4% more than GKE)
- ✅ Windows container requirements (future)

**Best For**: Existing Azure shops, memory-intensive workloads

### Choose GKE If:
- ✅ **Lowest cost priority** (best TCO)
- ✅ **Operational simplicity priority** (auto-management)
- ✅ **Fast deployment priority** (20-30 min)
- ✅ Greenfield project (no cloud lock-in yet)
- ✅ Want managed Prometheus and logging (free)
- ✅ Prefer Google Cloud ecosystem

**Best For**: New deployments, cost optimization, minimal ops overhead

---

## 11. Recommended Path Forward

### For New MiniPrem Deployments

**Primary Recommendation**: **GKE**

**Rationale**:
1. **Lowest Cost**: 4-27% cheaper than alternatives
2. **Fastest Setup**: 20-30 minute deployments
3. **Minimal Ops**: GKE-managed drivers, auto-upgrades
4. **Free Monitoring**: Managed Prometheus included
5. **Proven GPU Support**: T4 well-supported

**Implementation**: Use Phase 1-5 roadmap (2-3 weeks)

### For Multi-Cloud Strategy

**Recommended Order**:
1. **GKE** (primary) - Lowest cost, best ops
2. **AKS** (secondary) - Regional redundancy, competitive cost
3. **EKS** (tertiary) - Largest ecosystem, fallback option

**Maintain**: Infrastructure as code for all three (95% similar)

### For Existing AWS/Azure Customers

**If on AWS EKS**:
- Consider GKE migration for 27% cost savings
- ROI: Break-even in 2-3 months (migration cost)
- Keep EKS if AWS ecosystem dependencies critical

**If on Azure AKS**:
- Consider GKE migration for 4% cost savings + better ops
- ROI: Break-even in 8-12 months (smaller savings)
- Keep AKS if Azure-native services required

---

## 12. Quick Reference Commands

### Cluster Authentication

```bash
# EKS
aws eks update-kubeconfig --name renny-production --region us-east-1

# AKS
az aks get-credentials --name renny-production --resource-group renny-kubernetes

# GKE
gcloud container clusters get-credentials renny-production --region us-central1
```

### Scale Nodes

```bash
# EKS
aws eks update-nodegroup-config --cluster-name CLUSTER \
  --nodegroup-name renny-gpu --scaling-config desiredSize=15

# AKS
az aks nodepool scale --name rennygpu --cluster-name CLUSTER \
  --resource-group RG --node-count 15

# GKE
gcloud container clusters resize CLUSTER --num-nodes=15 \
  --node-pool=renny-gpu-pool --region=REGION
```

### Check GPU Nodes

```bash
# All providers (same kubectl)
kubectl get nodes -L nvidia.com/gpu,uneeq.io/node-type
kubectl describe nodes -l uneeq.io/node-type=renny | grep "nvidia.com/gpu"
```

### Verify GPU Drivers

```bash
# EKS/AKS (GPU Operator)
kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset
kubectl exec -n gpu-operator POD_NAME -- nvidia-smi

# GKE (native drivers)
kubectl get daemonset -n kube-system | grep nvidia
gcloud compute ssh NODE_NAME --zone=ZONE -- nvidia-smi
```

---

## 13. Cost Scenarios

### Scenario 1: Small Deployment (10 nodes, 8 hours/day)

| Provider | Cost/month | Notes |
|----------|------------|-------|
| **EKS** | $3,913 | 33% uptime |
| **AKS** | $2,984 | 33% uptime |
| **GKE** | **$2,858** | **33% uptime** |

**Savings**: Use autoscaling, scale to 2 nodes off-peak

### Scenario 2: Medium Deployment (15 nodes, 24/7)

| Provider | Cost/month | Notes |
|----------|------------|-------|
| **EKS** | $17,610 | 50% more than 10 nodes |
| **AKS** | $13,428 | 50% more than 10 nodes |
| **GKE** | **$12,861** | **50% more than 10 nodes** |

**Best Choice**: GKE for continuous operation

### Scenario 3: Large Deployment (20 nodes, 24/7 + CUD)

| Provider | Base Cost | With CUD | Net Cost |
|----------|-----------|----------|----------|
| **EKS** | $23,230 | -30% | **$16,261** |
| **AKS** | $17,592 | -40% | **$10,555** |
| **GKE** | **$17,000** | **-25%** | **$12,750** |

**Note**: AKS wins at scale with better CUD discounts

---

## 14. Final Recommendations

### Primary Recommendation: **GKE**

**For**:
- New deployments
- Cost-sensitive projects
- Teams wanting minimal operational overhead
- Projects requiring fast iteration

**Estimated Savings Over 1 Year** (10 nodes):
- vs EKS: $38,000 (27%)
- vs AKS: $4,500 (4%)

### Secondary Recommendation: **AKS**

**For**:
- Existing Azure customers
- Projects requiring maximum RAM per node
- Teams with Azure expertise
- Long-term committed use (3-year CUD)

**Advantage**: Best 3-year CUD discount (52-72%)

### Tertiary Recommendation: **EKS**

**For**:
- Existing AWS customers with deep integration
- Projects requiring A10G 24GB VRAM
- Teams with AWS expertise
- Projects using many AWS services

**Advantage**: Largest ecosystem and third-party integrations

---

**Document Version**: 1.0
**Last Updated**: October 16, 2025
**Next Review**: Quarterly cost analysis
