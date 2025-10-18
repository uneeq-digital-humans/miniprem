# Google Kubernetes Engine (GKE) Deployment
# MiniPrem Renny Digital Human Platform

**Status**: Architecture Design Phase
**Documentation Version**: 1.0
**Last Updated**: October 16, 2025

---

## Quick Links

- **[GKE Architecture Design](./GKE_ARCHITECTURE_DESIGN.md)** - Complete technical design (2000+ lines)
- **[Implementation Roadmap](./IMPLEMENTATION_ROADMAP.md)** - 5-phase implementation plan
- **[Multi-Cloud Comparison](./COMPARISON_SUMMARY.md)** - EKS vs AKS vs GKE analysis

---

## What is This?

This directory contains the **complete architectural design** for deploying MiniPrem Renny on Google Kubernetes Engine (GKE), providing feature parity with existing AWS EKS and Azure AKS implementations.

### Key Features

- **GPU Instances**: n1-standard-16 with NVIDIA T4 (16GB VRAM)
- **Auto-Scaling**: 10-20 GPU nodes with cluster autoscaler
- **Cost**: ~$8,574/month (10 nodes) - **4-27% cheaper than EKS/AKS**
- **Networking**: VPC-native with private nodes
- **Authentication**: Workload Identity (GKE's IAM integration)
- **GPU Drivers**: GKE-managed (automatic installation and updates)
- **Deployment Time**: 20-30 minutes (faster than EKS/AKS)

---

## Current Status

### ✅ Completed (Architecture Phase)

- [x] Complete architectural design document
- [x] Multi-cloud comparison analysis
- [x] Cost analysis and optimization strategies
- [x] Implementation roadmap (5 phases)
- [x] Terraform resource structure defined
- [x] Security and networking design
- [x] GPU configuration strategy

### ⏳ In Progress (Implementation Phase 1)

- [ ] Terraform file creation (8 core files, ~830 lines)
- [ ] Variables and outputs definition
- [ ] Documentation and examples

### 📋 Planned (Future Phases)

- [ ] Phase 2: Deployment automation scripts
- [ ] Phase 3: Kubernetes manifests
- [ ] Phase 4: Helm values for Renny
- [ ] Phase 5: Testing and validation

---

## Architecture Overview

### Infrastructure Components

```
GKE Cluster (Regional)
├── Control Plane (GCP-managed, FREE)
├── VPC Network
│   ├── Node Subnet (10.17.0.0/22)
│   ├── Pod Subnet (10.18.0.0/16)
│   └── Service Subnet (10.117.0.0/16)
├── Cloud NAT (outbound internet)
├── Node Pools
│   ├── System Pool: 2x n1-standard-4 (non-GPU)
│   └── GPU Pool: 10-20x n1-standard-16 + T4
└── Workload Identity (IAM integration)
```

### GPU Configuration

**Instance Type**: n1-standard-16 + NVIDIA T4
- **vCPUs**: 16
- **Memory**: 60GB RAM
- **GPU**: NVIDIA T4 (16GB VRAM)
- **Cost**: ~$1.11/hour (~$800/month per node)
- **Pods per GPU**: 2-4 (GKE native time-slicing)

**Driver Management**:
- GKE auto-installs drivers (5-10 minutes)
- Automatic updates with Kubernetes upgrades
- No GPU Operator required (optional for parity)

---

## Cost Analysis

### Monthly Costs (us-central1, 24/7)

| Configuration | GPU Nodes | System Nodes | Networking | Total |
|---------------|-----------|--------------|------------|-------|
| **Minimum (10 nodes)** | $8,000 | $274 | $100 | **$8,574** |
| **Maximum (20 nodes)** | $16,000 | $274 | $100 | **$17,000** |

### Cost Comparison (10 nodes)

| Provider | Cost/month | vs GKE |
|----------|------------|--------|
| **GCP GKE** | **$8,574** | - |
| Azure AKS | $8,952 | +4% |
| AWS EKS | $11,740 | +27% |

**GKE Advantages**:
- No control plane charges (EKS: $73/month)
- Cheaper GPU instances
- Free Managed Prometheus
- Lower networking costs

### Cost Optimization

**1. Committed Use Discounts (CUDs)**
- 1-year: 25% discount → Save $2,143/month
- 3-year: 52% discount → Save $4,458/month

**2. Autoscaling (Off-Peak)**
- Scale to 2 nodes during nights/weekends
- Save ~$4,800/month (60% time at minimum)

**3. Preemptible Instances (Dev/Test)**
- 80% discount for development environments
- Save ~$6,400/month for non-production

**4. Total Savings Potential**
- With all optimizations: ~$30,000/year (73% reduction)

---

## File Structure (Planned)

```
kubernetes/terraform/gke/
├── main.tf                      # Provider, backend, locals (75 lines)
├── gke.tf                       # GKE cluster resource (120 lines)
├── vpc.tf                       # VPC and networking (90 lines)
├── node-pools.tf                # System and GPU node pools (110 lines)
├── service-accounts.tf          # Workload Identity, IAM (95 lines)
├── variables.tf                 # All variables (150 lines)
├── outputs.tf                   # Terraform outputs (80 lines)
├── terraform.tfvars.example     # Example config (110 lines)
├── .gitignore                   # Ignore state files
├── README.md                    # This file
├── GKE_ARCHITECTURE_DESIGN.md   # Complete technical design
├── IMPLEMENTATION_ROADMAP.md    # 5-phase roadmap
└── COMPARISON_SUMMARY.md        # Multi-cloud comparison

Total: ~830 lines of Terraform code
```

---

## Prerequisites (Future Deployment)

### Required Tools

- **gcloud CLI** (latest) - [Install Guide](https://cloud.google.com/sdk/docs/install)
- **Terraform** (>= 1.0) - [Download](https://www.terraform.io/downloads)
- **kubectl** (>= 1.28) - [Install Guide](https://kubernetes.io/docs/tasks/tools/)
- **helm** (>= 3.0) - [Install Guide](https://helm.sh/docs/intro/install/)

### GCP Requirements

- **GCP Project** with billing enabled
- **Owner or Editor** role
- **T4 GPU Quota**: 20-40 GPUs approved (request 1 week before deployment)
- **APIs Enabled**:
  - container.googleapis.com (GKE)
  - compute.googleapis.com (Compute Engine)
  - iam.googleapis.com (IAM)
  - monitoring.googleapis.com (Cloud Monitoring)
  - logging.googleapis.com (Cloud Logging)

### Credentials

- UneeQ DHOP credentials (tenant ID, API key)
- Docker Hub credentials (for Renny image)
- Azure Speech API key (for TTS)
- ElevenLabs API key (optional)

---

## Deployment Workflow (Future)

### Phase 1: Pre-Deployment

```bash
# 1. Authenticate with GCP
gcloud auth login
gcloud config set project PROJECT_ID

# 2. Request T4 GPU quota (via Cloud Console)
# Navigation: IAM & Admin → Quotas → Filter: "T4" → Request increase
# Request: 20-40 T4 GPUs
# Processing: 1-3 business days

# 3. Enable required APIs
gcloud services enable container.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com

# 4. Verify T4 availability in region
gcloud compute accelerator-types list \
  --filter="name:nvidia-tesla-t4 AND zone:us-central1"
```

### Phase 2: Infrastructure Deployment

```bash
# 1. Clone repository
cd kubernetes/terraform/gke

# 2. Configure variables
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Update project_id, credentials, region

# 3. Initialize Terraform
terraform init

# 4. Review deployment plan
terraform plan -var-file=terraform.tfvars

# 5. Deploy infrastructure (~12-15 minutes)
terraform apply -var-file=terraform.tfvars

# 6. Configure kubectl
gcloud container clusters get-credentials \
  $(terraform output -raw cluster_name) \
  --region $(terraform output -raw region) \
  --project $(terraform output -raw project_id)

# 7. Verify cluster
kubectl get nodes
kubectl get nodes -L nvidia.com/gpu,uneeq.io/node-type
```

### Phase 3: GPU Verification

```bash
# Wait for GPU drivers (5-10 minutes)
watch kubectl get daemonset -n kube-system | grep nvidia

# Verify GPU on node
gcloud compute ssh NODE_NAME --zone=ZONE
nvidia-smi  # Should show T4 GPU

# Exit SSH
exit
```

### Phase 4: Application Deployment

```bash
# Deploy Renny (using deployment scripts)
cd ../../scripts/
./deploy.sh --cloud gke

# Verify Renny pods
kubectl get pods -n uneeq-renderer
kubectl get pods -n uneeq-renderer -o wide  # Show node placement

# Check logs
kubectl logs -f RENNY_POD_NAME -n uneeq-renderer
```

---

## Key Differences from EKS/AKS

### Advantages ✅

1. **Lower Cost**: 4-27% cheaper than alternatives
2. **Simpler GPU Management**: GKE auto-installs drivers (no GPU Operator)
3. **Faster Deployment**: 20-30 minutes vs 30-50 minutes
4. **Free Control Plane**: Save $73/month vs EKS
5. **Free Managed Prometheus**: Included with GKE
6. **Native Time-Slicing**: Built into node pool config (no ConfigMap)
7. **Automatic Upgrades**: K8s and drivers upgrade together

### Considerations ⚠️

1. **GPU Quota**: Default is 0, must request increase (1-3 days)
2. **Regional Availability**: Not all regions support T4 GPUs
3. **Learning Curve**: Different CLI (`gcloud` vs `aws`/`az`)
4. **Ecosystem**: Fewer third-party integrations than AWS

### Feature Parity ✅

- ✅ VPC-native networking (better than EKS overlay)
- ✅ Workload Identity (equivalent to IRSA/Managed Identity)
- ✅ Cluster autoscaler (same functionality)
- ✅ Multi-zone HA (regional cluster)
- ✅ Private nodes with NAT gateway
- ✅ GPU time-slicing (native support)
- ✅ Network policies (Calico/GKE native)

---

## Implementation Roadmap

### Phase 1: Terraform Infrastructure (Week 1)
- Create 8 Terraform files (~830 lines)
- Define variables and outputs
- Documentation and examples
- **Deliverable**: Production-ready Terraform code

### Phase 2: Deployment Automation (Week 1-2)
- `check-gcp-prerequisites.sh` script
- `check-network-usage.sh` script
- Adapt `deploy.sh`, `destroy.sh`, `status.sh`, `scale.sh`
- **Deliverable**: Automated deployment workflow

### Phase 3: Kubernetes Manifests (Week 2)
- Namespace and secrets
- GPU Operator (optional)
- Cluster autoscaler
- Monitoring integration
- **Deliverable**: K8s resources for GKE

### Phase 4: Helm Values (Week 2)
- GKE-specific Renny configuration
- Workload Identity integration
- Resource requests/limits
- **Deliverable**: `renny-values-gke.yaml`

### Phase 5: Testing & Documentation (Week 3)
- Full deployment test
- Cost validation
- Performance testing
- Documentation updates
- **Deliverable**: Production-ready deployment

**Total Timeline**: 2-3 weeks (48-66 hours)

---

## Security Best Practices

### Network Security

- ✅ Private nodes (no public IPs)
- ✅ Cloud NAT for outbound only
- ✅ VPC firewall rules (explicit allow)
- ✅ Network policies for pod isolation
- ✅ Control plane private endpoint (optional)

### IAM Security

- ✅ Workload Identity (no service account keys)
- ✅ Custom node service accounts (minimal permissions)
- ✅ Least privilege IAM policies
- ✅ Automatic credential rotation

### Cluster Security

- ✅ Node auto-repair and auto-upgrade
- ✅ Shielded GKE nodes
- ✅ Binary authorization (optional)
- ✅ Pod Security Standards
- ✅ RBAC enforcement

---

## Monitoring & Operations

### Built-In Monitoring

**Cloud Logging** (automatic):
- System component logs
- Application logs (stdout/stderr)
- Audit logs

**Cloud Monitoring** (automatic):
- Cluster metrics (CPU, memory, disk)
- Node metrics
- Pod metrics
- Custom metrics

**Managed Prometheus** (free):
- Prometheus-compatible metrics
- Pre-configured dashboards
- No extra cost

### Key Metrics to Monitor

**Cluster Health**:
- Node status (Ready/NotReady)
- Pod status (Running/Pending/Failed)
- API server latency

**GPU Utilization**:
- GPU memory usage per node
- GPU compute utilization (%)
- GPU temperature

**Cost Metrics**:
- GPU node hours (billable time)
- Egress bandwidth
- Per-namespace resource usage

### Alerting

**Critical Alerts**:
- GPU node NotReady > 5 minutes
- Renny pod CrashLoopBackOff
- Cluster autoscaler errors

**Warning Alerts**:
- GPU utilization < 20%
- High pod eviction rate
- API server latency > 500ms

---

## Troubleshooting Guide

### GPU Nodes Not Ready

**Symptom**: GPU nodes show NotReady

**Diagnosis**:
```bash
kubectl describe node GPU_NODE_NAME
kubectl get daemonset -n kube-system | grep nvidia
```

**Common Causes**:
1. GPU drivers still installing (wait 5-10 min)
2. Driver installation failed
3. GPU not detected

**Fix**:
```bash
# Restart node if drivers failed
kubectl drain GPU_NODE_NAME --ignore-daemonsets
gcloud compute instances reset GPU_NODE_NAME --zone=ZONE
kubectl uncordon GPU_NODE_NAME
```

### Pods Stuck in Pending

**Symptom**: Renny pods show Pending status

**Diagnosis**:
```bash
kubectl describe pod RENNY_POD_NAME -n uneeq-renderer
```

**Common Causes**:
1. No GPU nodes available (autoscaler scaling up)
2. GPU already allocated
3. Node taint/toleration mismatch

**Fix**:
```bash
# Check GPU capacity
kubectl describe nodes -l uneeq.io/node-type=renny | grep "nvidia.com/gpu"

# Force autoscaler scale-up
kubectl scale deployment renny --replicas=20 -n uneeq-renderer
```

### Workload Identity Not Working

**Symptom**: Pods can't access GCP APIs (403 Forbidden)

**Diagnosis**:
```bash
# From inside pod
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email
# Should return GCP SA email, not node SA
```

**Fix**:
```bash
# Verify K8s SA annotation
kubectl get sa renny-sa -n uneeq-renderer -o yaml

# Verify Workload Identity binding
gcloud iam service-accounts get-iam-policy \
  renny-sa@PROJECT_ID.iam.gserviceaccount.com

# Recreate pod
kubectl delete pod RENNY_POD_NAME -n uneeq-renderer
```

---

## FAQ

### Q: Why GKE over EKS/AKS?

**A**: GKE offers:
- **4-27% lower cost** than alternatives
- **Simpler GPU management** (auto-installed drivers)
- **Free control plane** (EKS charges $73/month)
- **Free Managed Prometheus**
- **Faster deployments** (20-30 minutes)

See [COMPARISON_SUMMARY.md](./COMPARISON_SUMMARY.md) for detailed analysis.

### Q: What is the deployment time?

**A**: 20-30 minutes total:
- Control plane: 5-7 minutes
- Node pools: 8-10 minutes
- GPU drivers: 5-10 minutes (auto-installed)
- Application: 5-8 minutes

### Q: Can I use GPU Operator instead of GKE-managed drivers?

**A**: Yes, for feature parity with EKS/AKS:
1. Set `gpu_driver_version = "LATEST"` (don't auto-install)
2. Deploy GPU Operator via Helm
3. Configure time-slicing via ConfigMap

**Trade-off**: 10-15 minutes longer deployment, manual driver upgrades.

### Q: What about T4 GPU availability?

**A**: T4 GPUs available in most GCP regions:
- **US**: us-central1, us-west1, us-east1, us-east4
- **Europe**: europe-west1, europe-west4
- **Asia**: asia-southeast1, asia-east1

Verify: `gcloud compute accelerator-types list --filter="name:nvidia-tesla-t4"`

### Q: How do I request GPU quota?

**A**: Via Cloud Console:
1. Navigate: IAM & Admin → Quotas
2. Filter: "nvidia-tesla-t4"
3. Select quota, click "Edit Quotas"
4. Request 20-40 GPUs
5. Processing: 1-3 business days

### Q: What is the cost breakdown?

**A**: For 10 nodes (24/7):
- GPU nodes: $8,000/month (10 × n1-standard-16 + T4)
- System nodes: $274/month (2 × n1-standard-4)
- Networking: $100/month (Cloud NAT + egress)
- Control plane: **FREE** (vs $73 on EKS)
- **Total: $8,574/month**

### Q: Can I migrate from EKS/AKS?

**A**: Yes, migration is straightforward:
- **From EKS**: 1-2 weeks, ~40% Terraform changes
- **From AKS**: 3-5 days, ~30% Terraform changes
- **No data migration needed** (Renny is stateless)

See [COMPARISON_SUMMARY.md](./COMPARISON_SUMMARY.md) Section 9 for migration guide.

---

## Support & Resources

### Documentation

- [GKE Architecture Design](./GKE_ARCHITECTURE_DESIGN.md) - Complete technical design
- [Implementation Roadmap](./IMPLEMENTATION_ROADMAP.md) - 5-phase implementation plan
- [Multi-Cloud Comparison](./COMPARISON_SUMMARY.md) - EKS vs AKS vs GKE

### External Resources

- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [GKE GPU Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/gpus)
- [Workload Identity Guide](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [VPC-Native Networking](https://cloud.google.com/kubernetes-engine/docs/how-to/alias-ips)
- [GKE Best Practices](https://cloud.google.com/kubernetes-engine/docs/best-practices)

### Community

- [Google Cloud Community](https://www.googlecloudcommunity.com/)
- [Stack Overflow: google-kubernetes-engine](https://stackoverflow.com/questions/tagged/google-kubernetes-engine)
- [GKE GitHub Issues](https://github.com/GoogleCloudPlatform/kubernetes-engine-samples/issues)

---

## License & Attribution

**MiniPrem Project**: Copyright 2025
**Architecture Design**: System Architecture Team
**Implementation**: DevOps Engineering Team

This deployment follows the established patterns from EKS and AKS implementations, adapted for GKE-specific features and best practices.

---

## Changelog

### Version 1.0 (October 16, 2025)
- Initial architecture design complete
- Multi-cloud comparison analysis
- Cost analysis and optimization strategies
- 5-phase implementation roadmap
- Comprehensive documentation (2000+ lines)
- Ready for Phase 1 implementation

### Upcoming (Phase 1 - Week 1)
- Terraform file implementation
- Variables and outputs
- Example configuration
- Validation and testing

---

**For Questions**: Contact Cloud Architecture Team
**For Updates**: Check this README and linked documents
**Status**: Ready for implementation (Phase 1)
