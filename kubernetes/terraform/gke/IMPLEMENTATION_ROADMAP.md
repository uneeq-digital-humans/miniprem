# GKE Implementation Roadmap
# MiniPrem Renny Digital Human Platform

**Status**: Architecture Design Complete ✅
**Next Phase**: Terraform File Creation
**Target Completion**: 5 phases over 2-3 weeks

---

## Quick Reference

### Architecture Summary

| Component | Specification |
|-----------|---------------|
| **Cloud Provider** | Google Cloud Platform (GKE) |
| **Cluster Type** | Regional (multi-zone HA) |
| **Kubernetes Version** | 1.31+ |
| **GPU Instance** | n1-standard-16 + NVIDIA T4 |
| **GPU Count** | 10-20 nodes (autoscaling) |
| **Cost/month** | ~$8,574 (10 nodes) |
| **Networking** | VPC-native (alias IP) |
| **Authentication** | Workload Identity |
| **GPU Drivers** | GKE-managed (auto-install) |

### Cost Comparison

| Provider | 10 Nodes | 20 Nodes | Control Plane |
|----------|----------|----------|---------------|
| **GKE** | **$8,574** | **$17,000** | **FREE** |
| AKS | $8,952 | $17,592 | FREE |
| EKS | $11,740 | $23,230 | $73/month |

**GKE Savings**: 4-27% cheaper than alternatives

---

## Phase 1: Terraform Infrastructure (Week 1)

**Objective**: Create production-ready Terraform code for GKE cluster

### Deliverables

**8 Core Terraform Files** (~830 lines total):

1. **main.tf** (75 lines)
   - Provider configuration (google, google-beta, kubernetes, helm)
   - GCS backend setup (optional)
   - Common locals and labels
   - Data sources

2. **gke.tf** (120 lines)
   - GKE cluster resource
   - VPC-native networking configuration
   - Workload Identity setup
   - Cluster addons (monitoring, logging, autoscaling)
   - Release channel (REGULAR)

3. **vpc.tf** (90 lines)
   - VPC network and subnet
   - Secondary IP ranges (pods, services)
   - Cloud NAT and Cloud Router
   - Firewall rules (internal, WebRTC, health checks)

4. **node-pools.tf** (110 lines)
   - System node pool (n1-standard-4, non-GPU)
   - GPU node pool (n1-standard-16 + T4)
   - Autoscaling configuration
   - GPU time-slicing settings
   - Node taints and labels

5. **service-accounts.tf** (95 lines)
   - Node service account with minimal permissions
   - Renny Workload Identity setup
   - Cluster autoscaler service account
   - IAM bindings and custom roles

6. **variables.tf** (150 lines)
   - All configurable parameters
   - Descriptions and validation
   - Default values matching EKS/AKS patterns

7. **outputs.tf** (80 lines)
   - Cluster connection details
   - Service account emails
   - VPC/subnet IDs
   - Usage examples in comments

8. **terraform.tfvars.example** (110 lines)
   - Example configuration with guidance
   - Comments explaining each variable
   - Security best practices

**Additional Files**:
- `.gitignore` - Ignore state files, secrets, .terraform/
- `README.md` - Full deployment guide (500+ lines)
- `QUICK_START.md` - Fast reference (100 lines)

### Validation Checklist

- [ ] Terraform fmt (auto-format all files)
- [ ] Terraform validate (syntax check)
- [ ] Variable validation rules
- [ ] Documentation completeness
- [ ] Google Cloud best practices compliance
- [ ] Security review (no hardcoded secrets)

### Success Criteria

- All files pass `terraform validate`
- Cost estimate < $9,000/month (10 nodes)
- Feature parity with EKS/AKS
- Clear documentation with examples

---

## Phase 2: Deployment Automation (Week 1-2)

**Objective**: Create deployment scripts matching EKS/AKS workflow

### Script Directory Structure

```
kubernetes/scripts/gke/
├── check-gcp-prerequisites.sh  (~200 lines)
├── check-network-usage.sh      (~150 lines)
└── README.md                   (~100 lines)
```

### Script 1: check-gcp-prerequisites.sh

**Purpose**: Pre-deployment validation

**Checks**:
- [ ] gcloud CLI installed and authenticated
- [ ] Required GCP APIs enabled:
  - container.googleapis.com (GKE)
  - compute.googleapis.com (Compute Engine)
  - iam.googleapis.com (IAM)
  - monitoring.googleapis.com (Cloud Monitoring)
  - logging.googleapis.com (Cloud Logging)
- [ ] GPU quota availability (T4 GPUs)
- [ ] IAM permissions:
  - Kubernetes Engine Admin
  - Compute Admin
  - Service Account Admin
  - IAM Security Admin
- [ ] T4 GPU availability in target region
- [ ] VPC CIDR availability (no conflicts)
- [ ] Terraform version (>= 1.0)
- [ ] kubectl version (>= 1.28)

**Output**: Detailed report with pass/fail and remediation steps

### Script 2: check-network-usage.sh

**Purpose**: Analyze VPC IP usage and quotas

**Checks**:
- [ ] Current VPC usage in project
- [ ] Available IP addresses in subnet
- [ ] Secondary range usage (pods, services)
- [ ] NAT gateway configuration
- [ ] Firewall rule conflicts
- [ ] VPC quota limits
- [ ] Recommendations for CIDR sizing

**Output**: IP usage report and scaling recommendations

### Adapt Existing Scripts

**Modify for GKE support**:
- `kubernetes/scripts/deploy.sh` - Add `--cloud gke` option
- `kubernetes/scripts/destroy.sh` - Add GKE cleanup logic
- `kubernetes/scripts/status.sh` - Add GKE health checks
- `kubernetes/scripts/scale.sh` - Add GKE node pool scaling

**Key Changes**:
```bash
# Detect cloud provider
if [ "$CLOUD_PROVIDER" = "gke" ]; then
  TERRAFORM_DIR="kubernetes/terraform/gke"
  VALUES_FILE="kubernetes/values/renny-values-gke.yaml"
  # Use gcloud commands instead of aws/az
fi
```

### Success Criteria

- Prerequisites script catches 100% of common setup issues
- Network script provides actionable recommendations
- Deployment scripts work end-to-end
- Error handling and rollback logic

---

## Phase 3: Kubernetes Manifests (Week 2)

**Objective**: Create GKE-specific Kubernetes resources

### Manifest Directory Structure

```
kubernetes/manifests/gke/
├── namespace/
│   └── uneeq-renderer.yaml
├── secrets/
│   ├── harbor-credentials-secret.yaml
│   └── dhop-credentials-secret.yaml
├── gpu-operator/ (optional)
│   ├── namespace.yaml
│   └── values.yaml
├── cluster-autoscaler/
│   ├── deployment.yaml
│   ├── service-account.yaml
│   └── configmap.yaml
└── monitoring/
    ├── service-monitor.yaml
    └── prometheus-rules.yaml
```

### Key Manifests

**1. Namespace**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: uneeq-renderer
  labels:
    name: uneeq-renderer
    workload: digital-human
```

**2. Harbor Registry Secret**
```bash
kubectl create secret docker-registry harbor-credentials \
  --docker-server=https://cr.uneeq.io \
  --docker-username=$HARBOR_USERNAME \
  --docker-password=$HARBOR_PASSWORD \
  --namespace=uneeq-renderer
```

**3. Cluster Autoscaler**
- Uses Workload Identity (no keys)
- Custom GCP IAM role
- Scoped to specific node pools

**4. GPU Operator (Optional)**
- Only if not using GKE-managed drivers
- Helm values for driver 580
- Time-slicing configuration

### Success Criteria

- All manifests apply without errors
- Secrets created from Terraform outputs
- Autoscaler scales nodes correctly
- GPU drivers installed and detected

---

## Phase 4: Helm Values (Week 2)

**Objective**: Create GKE-specific Renny Helm values

### File: kubernetes/values/renny-values-gke.yaml

**Key Sections**:

```yaml
# GKE-Specific Overrides
image: "cr.uneeq.io/uneeq/renny-renderer:0.1184-2f3b7"

# GPU Time-Slicing (GKE Native)
gpuTimeSlicing:
  enabled: true
  strategy: "GKE_NATIVE"  # vs "GPU_OPERATOR"
  replicasPerGpu: 2       # GKE gpu_sharing_config

# Deployment Scaling
deployment:
  totalReplicas: 20  # 10 nodes × 2 pods
  nodeType: renny

# Resource Requests (per pod)
resources:
  requests:
    cpu: "3600m"           # 3.6 CPUs
    memory: "7Gi"          # 7GB RAM
    nvidia.com/gpu: 1      # Request GPU
  limits:
    nvidia.com/gpu: 1      # Same as request

# Workload Identity
serviceAccount:
  create: true
  name: renny-sa
  annotations:
    iam.gke.io/gcp-service-account: "renny-sa@PROJECT_ID.iam.gserviceaccount.com"

# Node Selection
nodeSelector:
  uneeq.io/node-type: renny
  cloud.google.com/gke-accelerator: nvidia-tesla-t4

tolerations:
- key: nvidia.com/gpu
  operator: Equal
  value: "true"
  effect: NoSchedule

# GKE-Specific Annotations
podAnnotations:
  cluster-autoscaler.kubernetes.io/safe-to-evict: "false"

# Health Checks (Renny startup time)
livenessProbe:
  httpGet:
    path: /health
    port: 8081
  initialDelaySeconds: 60
  periodSeconds: 30
  timeoutSeconds: 10

readinessProbe:
  httpGet:
    path: /health
    port: 8081
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5

# Cloud Load Balancer
service:
  type: LoadBalancer
  annotations:
    cloud.google.com/load-balancer-type: "Internal"

# Monitoring (Cloud Monitoring)
monitoring:
  enabled: true
  cloudMonitoring: true
  serviceMonitor:
    enabled: true
```

### Comparison with EKS/AKS

| Feature | EKS | AKS | **GKE** |
|---------|-----|-----|---------|
| GPU Request | `nvidia.com/gpu: 1` | `nvidia.com/gpu: 1` | **`nvidia.com/gpu: 1`** |
| Service Account | IRSA annotation | Managed Identity | **Workload Identity** |
| Node Selector | `uneeq.io/node-type` | `uneeq.io/node-type` | **Same + accelerator type** |
| Load Balancer | NLB annotation | Internal LB | **Internal Cloud LB** |

### Success Criteria

- Helm install succeeds
- Pods schedule on GPU nodes
- Workload Identity works
- Health checks pass
- WebRTC traffic flows

---

## Phase 5: Testing & Documentation (Week 3)

**Objective**: Validate full deployment and finalize documentation

### Test Plan

**1. Infrastructure Tests**
- [ ] Terraform plan generates valid config
- [ ] Terraform apply completes (~15 minutes)
- [ ] Cluster accessible via kubectl
- [ ] Node pools created (system + GPU)
- [ ] GPU nodes have nvidia-tesla-t4 label
- [ ] Workload Identity enabled

**2. GPU Tests**
- [ ] GPU drivers installed (nvidia-smi works)
- [ ] GPU detected on nodes
- [ ] GPU time-slicing configured (2 pods/GPU)
- [ ] GPU memory allocated correctly
- [ ] Multiple pods share GPU

**3. Application Tests**
- [ ] Renny image pulls successfully
- [ ] Renny pods start (within 5 minutes)
- [ ] Health checks pass (port 8081)
- [ ] Pods scheduled on GPU nodes
- [ ] Tolerations respected (no system pods on GPU)

**4. Networking Tests**
- [ ] VPC-native networking working
- [ ] Pod-to-pod communication
- [ ] Pod-to-service communication
- [ ] Cloud NAT egress working
- [ ] WebRTC ports accessible (22000-23000)
- [ ] TURN ports accessible (3478, 5349)

**5. Scaling Tests**
- [ ] Cluster autoscaler scales up (add nodes)
- [ ] Cluster autoscaler scales down (remove nodes)
- [ ] Manual scaling with `scale.sh` script
- [ ] HPA scales Renny pods (if enabled)

**6. Security Tests**
- [ ] Workload Identity prevents privilege escalation
- [ ] Node SA has minimal permissions
- [ ] Firewall rules block unwanted traffic
- [ ] Binary authorization (if enabled)
- [ ] Network policies enforce isolation

**7. Operational Tests**
- [ ] `deploy.sh --cloud gke` works end-to-end
- [ ] `status.sh` reports cluster health
- [ ] `scale.sh 15` scales to 15 nodes
- [ ] `destroy.sh` cleans up all resources
- [ ] Cost tracking enabled

### Documentation Updates

**1. Main README.md** (kubernetes/terraform/gke/)
- [ ] Complete deployment guide
- [ ] Prerequisites section
- [ ] Step-by-step instructions
- [ ] Troubleshooting guide
- [ ] Cost estimates
- [ ] Architecture diagrams (optional)

**2. QUICK_START.md**
- [ ] Fast deployment reference
- [ ] Common commands
- [ ] Verification steps

**3. CLAUDE.md Updates**
- [ ] Add GKE deployment instructions
- [ ] Update port mappings
- [ ] Add GKE-specific troubleshooting

**4. Cost Analysis**
- [ ] Actual cost validation (vs estimates)
- [ ] Cost optimization recommendations
- [ ] Committed use discount guidance

### Success Criteria

- All tests pass
- Documentation complete and accurate
- Cost within 5% of estimates
- No manual intervention needed for deployment
- Troubleshooting guide covers 90% of issues

---

## Timeline Summary

| Phase | Duration | Effort | Dependencies |
|-------|----------|--------|--------------|
| **Phase 1**: Terraform | 3-4 days | 16-20 hours | None |
| **Phase 2**: Scripts | 2-3 days | 8-12 hours | Phase 1 |
| **Phase 3**: Manifests | 2-3 days | 8-12 hours | Phase 1 |
| **Phase 4**: Helm Values | 1-2 days | 4-6 hours | Phase 3 |
| **Phase 5**: Testing | 3-4 days | 12-16 hours | All phases |
| **Total** | **11-16 days** | **48-66 hours** | - |

### Parallelization Opportunities

**Week 1** (Parallel):
- Phase 1: Terraform files (main task)
- Phase 2: Script planning (secondary)

**Week 2** (Parallel):
- Phase 3: Kubernetes manifests (main)
- Phase 4: Helm values (secondary)
- Phase 2: Script implementation (tertiary)

**Week 3**:
- Phase 5: Testing and documentation (sequential)

---

## Resource Requirements

### Team

**Minimum**:
- 1 DevOps Engineer (Terraform + GCP experience)

**Optimal**:
- 1 Cloud Architect (design review)
- 1 DevOps Engineer (implementation)
- 1 QA Engineer (testing)

### GCP Resources

**Development/Testing**:
- 1 GCP project
- T4 GPU quota: 5-10 GPUs
- Budget: ~$500 for testing week

**Production**:
- 1 GCP project
- T4 GPU quota: 20-40 GPUs
- Budget: ~$8,574/month

### Tools

- Terraform >= 1.0
- gcloud CLI (latest)
- kubectl >= 1.28
- helm >= 3.0
- Git (for version control)

---

## Risk Assessment

### High Risk

1. **GPU Quota Availability**
   - **Impact**: Cannot deploy GPU nodes
   - **Mitigation**: Request quota increase 1 week before Phase 5
   - **Fallback**: Use different region with availability

2. **T4 Regional Availability**
   - **Impact**: Selected region doesn't support T4
   - **Mitigation**: Verify with `gcloud compute accelerator-types list`
   - **Fallback**: Use different region (may increase latency)

### Medium Risk

1. **Workload Identity Setup Complexity**
   - **Impact**: Authentication failures, delayed testing
   - **Mitigation**: Follow official GCP documentation exactly
   - **Fallback**: Use node SA temporarily (not recommended)

2. **GKE-Managed vs GPU Operator Decision**
   - **Impact**: Different driver installation workflows
   - **Mitigation**: Test both approaches in Phase 5
   - **Fallback**: Use GPU Operator (matches EKS/AKS)

### Low Risk

1. **Cost Overruns**
   - **Impact**: Higher than estimated costs
   - **Mitigation**: Enable budget alerts, monitor daily
   - **Fallback**: Scale down or use preemptible instances

2. **Documentation Gaps**
   - **Impact**: Slower adoption, more support needed
   - **Mitigation**: Comprehensive testing in Phase 5
   - **Fallback**: Update docs based on user feedback

---

## Next Action Items

### Immediate (This Week)

1. **Review Architecture Design**
   - [ ] System architect review
   - [ ] Security team review
   - [ ] Cost approval

2. **Request GPU Quota**
   - [ ] Submit quota increase request (20-40 T4 GPUs)
   - [ ] Target region: us-central1 (or backup)
   - [ ] Processing time: 1-3 business days

3. **Setup GCP Project**
   - [ ] Create new project or use existing
   - [ ] Enable billing
   - [ ] Enable required APIs
   - [ ] Configure IAM permissions

4. **Begin Phase 1**
   - [ ] Create `kubernetes/terraform/gke/` directory
   - [ ] Start implementing main.tf
   - [ ] Setup Terraform backend (GCS)

### Short-Term (Next Week)

1. **Complete Phase 1**
   - [ ] All Terraform files created
   - [ ] Validation passing
   - [ ] Documentation complete

2. **Start Phase 2**
   - [ ] Implement prerequisite check script
   - [ ] Adapt deployment scripts
   - [ ] Test script functionality

3. **Plan Phase 3**
   - [ ] Review Kubernetes manifest requirements
   - [ ] Decide on GPU Operator vs GKE-managed
   - [ ] Prepare Helm chart modifications

### Medium-Term (Week 3+)

1. **Complete Phases 3-4**
   - [ ] Manifests deployed
   - [ ] Helm values tested
   - [ ] Integration with scripts

2. **Execute Phase 5**
   - [ ] Full deployment test
   - [ ] Cost validation
   - [ ] Documentation finalization
   - [ ] Handoff to operations team

---

## Success Metrics

### Technical Metrics

- [ ] Deployment time < 20 minutes (excluding Terraform apply)
- [ ] GPU utilization > 70% (2 pods/GPU working)
- [ ] Pod startup time < 5 minutes
- [ ] Cluster autoscaler reaction < 5 minutes
- [ ] Zero manual intervention needed

### Cost Metrics

- [ ] 10-node cost < $9,000/month
- [ ] 4-27% cheaper than EKS/AKS
- [ ] Cost tracking enabled (GKE Cost Allocation)
- [ ] Budget alerts configured

### Operational Metrics

- [ ] Scripts work without errors
- [ ] Documentation covers 90%+ of issues
- [ ] Troubleshooting guide tested
- [ ] No undocumented manual steps

### Quality Metrics

- [ ] All Terraform files pass fmt/validate
- [ ] Code follows Google Cloud best practices
- [ ] Security review passed
- [ ] Feature parity with EKS/AKS achieved

---

## Appendix: Key Decisions

### Decision 1: GKE-Managed Drivers vs GPU Operator

**Recommendation**: **GKE-Managed Drivers**

**Rationale**:
- Simpler setup (no Helm chart)
- Automatic updates with GKE
- Google-tested and supported
- Faster driver installation (~5 min vs 10-15 min)

**Trade-off**: Less control over driver version (accept GKE default)

### Decision 2: Regional vs Zonal Cluster

**Recommendation**: **Regional Cluster**

**Rationale**:
- Multi-zone HA for control plane
- Better uptime SLA (99.95% vs 99.5%)
- Node pools spread across zones
- No cost difference for nodes

**Trade-off**: Slightly more complex networking (not significant)

### Decision 3: VPC-Native vs Routes-Based Networking

**Recommendation**: **VPC-Native (Alias IP)**

**Rationale**:
- Default and recommended by Google
- Better performance (no overlay)
- Native GCP integration
- Required for advanced features

**Trade-off**: More complex CIDR planning (already done in design)

### Decision 4: Workload Identity vs Key-Based Auth

**Recommendation**: **Workload Identity**

**Rationale**:
- No key management (automatic rotation)
- Better security (least privilege)
- Native GKE integration
- Matches AWS IRSA/Azure Managed Identity pattern

**Trade-off**: More complex setup (one-time effort, documented)

---

**Document Version**: 1.0
**Last Updated**: October 16, 2025
**Owner**: Cloud Architecture Team
**Next Review**: After Phase 1 completion
