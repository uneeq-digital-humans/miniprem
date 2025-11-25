<div align="center">

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

# AWS EKS Production Deployment

> Deploy Renny digital humans on AWS EKS with NVIDIA A10G GPU acceleration

</div>

<div class="info-box">
<strong>ℹ️ Multi-Cloud Support:</strong> This guide is specific to AWS EKS. For other cloud providers, see:
<ul>
  <li><a href="kubernetes-overview.md">Multi-Cloud Overview</a> - Compare all cloud providers</li>
  <li><a href="kubernetes-aks.md">Azure AKS Deployment</a> - Deploy on Azure</li>
  <li><a href="kubernetes-multi-cloud.md">Multi-Cloud Guide</a> - Cost comparison and migration</li>
</ul>
</div>

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Operations](#operations)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Cost Management](#cost-management)
- [License](#license)
- [Copyright](#copyright)

## Overview

The Kubernetes deployment provides a **production-ready, auto-scaling infrastructure** for Renny digital humans on AWS EKS with NVIDIA GPU support. This deployment is ideal for:

- **Production workloads** requiring high availability
- **Enterprise deployments** with 10-20+ concurrent digital humans
- **Auto-scaling** based on demand
- **GPU-accelerated rendering** with NVIDIA A10G GPUs
- **Multi-region deployments** with infrastructure as code

### Key Features

- ✅ **One-click deployment** (~30-45 minutes)
- ✅ **Auto-scaling** (10-20 Renny instances)
- ✅ **GPU time-slicing** for cost optimization
- ✅ **Ubuntu 22.04 EKS AMIs** for Vulkan/Unreal Engine compatibility
- ✅ **Automatic GPU driver installation** via NVIDIA GPU Operator
- ✅ **CloudWatch integration** for centralized logging
- ✅ **High availability** across 3 availability zones
- ✅ **Infrastructure as Code** with Terraform

### Architecture Comparison

| Feature | Docker (Local) | Kubernetes (Production) |
|---------|---------------|------------------------|
| **Deployment** | Single machine | Multi-node cluster |
| **Scalability** | 1-5 instances | 10-20+ instances |
| **High Availability** | No | Yes (multi-AZ) |
| **Auto-scaling** | Manual | Automatic |
| **GPU Support** | Single GPU | Multiple GPUs with time-slicing |
| **Cost** | ~$100-500/month | ~$10,000/month |
| **Setup Time** | 5-10 minutes | 30-45 minutes |
| **Use Case** | Development/Demo | Production/Enterprise |

## Architecture

### Infrastructure Overview

```
AWS Cloud (us-east-2)
├── VPC (10.0.0.0/16)
│   ├── Public Subnets (3 AZs)
│   │   ├── NAT Gateway 1
│   │   ├── NAT Gateway 2
│   │   └── NAT Gateway 3
│   └── Private Subnets (3 AZs)
│       └── EKS Cluster (renny-production)
│           ├── Control Plane (Managed by AWS)
│           ├── Control Node Group
│           │   └── 2x t3.large instances
│           └── Renny GPU Node Group
│               └── 10-20x g5.4xlarge instances
│                   └── NVIDIA A10G GPUs (24GB VRAM each)
└── CloudWatch Logs (centralized monitoring)
```

### GPU Time-Slicing

GPU time-slicing allows multiple Renny pods to share a single physical GPU:

```
g5.4xlarge Node (NVIDIA A10G 24GB)
├── Virtual GPU 1 → Renny Pod 1 (~30% utilization)
└── Virtual GPU 2 → Renny Pod 2 (~30% utilization)
Total GPU Utilization: ~60% (optimal cost/performance)
```

### Network Architecture

- **WebRTC/UDP**: Ports 22000-23000 (PixelStreaming)
- **TURN/STUN**: Port 3478 (TCP/UDP)
- **HTTPS**: Port 443 (egress to *.uneeq.io)
- **Harbor Registry**: HTTPS port 443 to cr.uneeq.io (required for image pulls)
- **Private Subnets**: All GPU nodes for security
- **NAT Gateways**: Highly available outbound connectivity

### Harbor Registry Access

All Renny container images are hosted in the UneeQ Harbor registry. Ensure your network allows:

- **Harbor URL**: https://cr.uneeq.io
- **Port**: 443 (HTTPS)
- **Access**: Required for initial image pull and any image updates

If your network uses a firewall or proxy, whitelist `cr.uneeq.io` to allow the EKS nodes to pull images during deployment and scaling.

## Prerequisites

### Required Tools

1. **AWS Account** with appropriate permissions
2. **AWS CLI** >= 2.3.0 configured with credentials
3. **Terraform** >= 1.0
4. **kubectl** (Kubernetes CLI)
5. **Helm** >= 3.0 (Kubernetes package manager)
6. **UneeQ Harbor registry access** (robot account credentials)
   - Contact help@uneeq.com for credentials
   - Registry URL: https://cr.uneeq.io
7. **Renny Helm chart** (renny-chart.tgz file)

### macOS-Specific Requirement

```bash
# Install coreutils for deployment timeouts
brew install coreutils
```

### Installation Commands

**Terraform:**
```bash
# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Linux (Ubuntu/Debian)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

**Other Tools:**
```bash
# AWS CLI
# macOS: brew install awscli
# Linux: pip install awscli

# kubectl
# macOS: brew install kubectl
# Linux: sudo snap install kubectl --classic

# Helm
# macOS: brew install helm
# Linux: sudo snap install helm --classic
```

### Verify Installations

```bash
terraform version  # Should show v1.6.6 or higher
aws --version      # AWS CLI version
kubectl version    # Kubernetes CLI
helm version       # Helm package manager
gtimeout --version # macOS only - GNU coreutils
```

## Quick Start

### Step 1: Setup AWS Credentials

The deployment script is **profile-aware** and detects your AWS configuration automatically.

**Option 1: AWS SSO (Recommended)**
```bash
# Login to your SSO profile
aws sso login --profile your-org-profile

# Run deployment with profile
cd kubernetes/
./scripts/deploy.sh --profile your-org-profile
```

**Option 2: IAM User**
```bash
aws configure
# Enter Access Key ID and Secret Access Key
# Region: us-east-2 (or your preferred region)
```

**Verify AWS setup:**
```bash
./scripts/check-aws-prerequisites.sh
```

**Check VPC availability:**
```bash
./scripts/check-vpc-usage.sh
# AWS has a default limit of 5 VPCs per region
# This script helps identify unused VPCs
```

### Step 2: Configure Credentials

Create `kubernetes/terraform/terraform.tfvars`:

```hcl
# Required credentials
dhop_tenant_id   = "your-tenant-id"
dhop_api_key     = "your-api-key"  # Plain text API key

# Harbor registry credentials (robot account)
# Contact help@uneeq.com or your UneeQ representative to obtain credentials
harbor_username  = "robot$your-customer-name"
harbor_password  = "your-robot-password"

# Optional: Override defaults
aws_region = "us-east-2"  # Change to your preferred region
```

### Step 3: Place Helm Chart

Place your `renny-chart.tgz` file in the `kubernetes/` directory.

### Step 4: Deploy

Run the one-click deployment:

```bash
cd kubernetes
chmod +x scripts/*.sh

# Basic deployment
./scripts/deploy.sh

# With specific AWS profile
./scripts/deploy.sh --profile your-profile-name

# Get help
./scripts/deploy.sh --help
```

### Deployment Process

The deployment script will:

1. ✅ **Check prerequisites** (AWS credentials, tools)
2. 🏗️ **Deploy VPC and EKS cluster** via Terraform (~15-20 minutes)
3. 🚀 **Fast cluster join** for Ubuntu nodes (~3-5 minutes)
4. 🎮 **Install NVIDIA GPU Operator** (~5-10 minutes)
5. 🤖 **Deploy Renny** with internal speech processing (~5-10 minutes)
6. ⚖️ **Configure autoscaling** (10-20 instances)

**Total deployment time: ~30-45 minutes**

## Configuration

### GPU Time-Slicing Configuration

All GPU time-slicing configuration is managed in `kubernetes/values/renny-values.yaml`:

```yaml
# GPU time-slicing configuration
gpuTimeSlicing:
  enabled: true
  replicasPerGpu: 2  # How many pods share one GPU

deployment:
  nodeType: renny
  totalReplicas: 4   # Total number of Renny pods
  # Note: totalReplicas must be a multiple of replicasPerGpu

resources:
  limits:
    nvidia.com/gpu: 1  # Each pod requests 1 GPU share
    memory: "7Gi"       # Per-pod memory
    cpu: "3600m"        # Per-pod CPU (3.6 cores)
```

**To modify:**
1. Edit `kubernetes/values/renny-values.yaml`
2. Run `./scripts/deploy.sh` to apply changes

### NVIDIA Driver Selection

During deployment, choose between:

**Driver 575+ (Production Tested)**
- ✅ Production-ready and extensively validated
- ✅ Unreal Engine 5.6+ compatibility
- ✅ Full graphics capabilities
- ✅ CUDA 12.6+ support

**Driver 580+ (Latest Release)**
- ✅ REQUIRED for NVIDIA 5xxx series GPUs
- ✅ Latest features and optimizations
- ✅ CUDA 12.8+ support
- ⚠️ Newest release - monitor carefully

### Text-to-Speech Configuration

Configure TTS providers in `kubernetes/values/renny-values.yaml`:

```yaml
# Azure Speech Services
tts:
  azureRegion: "eastus"
  azureSpeechKey: "your-azure-api-key"  # Plain text

# ElevenLabs
tts:
  elevenlabsApiKey: "sk_your-elevenlabs-api-key"

# Google Cloud TTS
tts:
  gcpCredentials: "{\"type\": \"service_account\", ...}"
```

**Apply changes:**
```bash
helm upgrade renny ./renny-chart.tgz -n uneeq-renderer -f values/renny-values.yaml
```

## Operations

### Scaling Renny Instances

Scale between 10-20 instances:

```bash
./scripts/scale.sh 15  # Scale to 15 instances
```

### Check Deployment Status

Get comprehensive status report:

```bash
./scripts/status.sh
```

### Verify GPU Drivers

```bash
# Check GPU operator pods
kubectl get pods -n gpu-operator

# Verify GPU drivers on nodes
kubectl get nodes -l nvidia.com/gpu.present=true

# Test GPU functionality
kubectl run gpu-test --image=nvidia/cuda:12.4-runtime-ubuntu22.04 --rm -it --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"uneeq.io/node-type":"renny"},"tolerations":[{"key":"nvidia.com/gpu","operator":"Equal","value":"true","effect":"NoSchedule"}]}}' \
  -- nvidia-smi
```

### Check kubectl Context

After deployment, kubectl automatically connects to your EKS cluster:

```bash
# Verify connection
kubectl config current-context

# Reconnect if needed
aws eks update-kubeconfig --region us-east-2 --name renny-production
```

## Monitoring

### Pod Health Monitoring

```bash
# Check all pods
kubectl get pods -A

# Check Renny pods
kubectl get pods -n uneeq-renderer

# Watch pods in real-time
kubectl get pods -n uneeq-renderer -w

# Check pod details
kubectl describe pod <pod-name> -n uneeq-renderer

# View logs
kubectl logs <pod-name> -n uneeq-renderer -f
```

### Node Resource Monitoring

```bash
# Check node status
kubectl get nodes -o wide

# Check GPU availability
kubectl get nodes -L nvidia.com/gpu,uneeq.io/node-type

# Check node resources
kubectl describe nodes | grep -A10 "Allocated resources"
```

### CloudWatch Logs

All Renny logs are automatically sent to CloudWatch for centralized monitoring.

**Log Group Locations:**
- EKS cluster logs: `/aws/eks/[cluster-name]/cluster`
- Application logs: `/aws/containerinsights/[cluster-name]/application`

**CloudWatch Insights Query Examples:**

Find recent errors:
```sql
fields @timestamp, service, renderer_id, message
| filter service = "renderer"
| filter log_level = "error"
| sort @timestamp desc
| limit 50
```

Monitor speech processing:
```sql
fields @timestamp, message, client_session_id
| filter service = "renderer"
| filter message like /speech.*failed|NEW_SPEECH_OVERRIDE/
| sort @timestamp desc
```

## Troubleshooting

### Common Issues

**Pods stuck in Pending:**
```bash
# Check why pod isn't scheduled
kubectl describe pod <pod-name> -n uneeq-renderer

# Common causes:
# - "Insufficient nvidia.com/gpu" = No GPU nodes available
# - "Insufficient cpu/memory" = Resource limits exceeded
```

**Image Pull Failures:**
```bash
# Check Harbor registry secret
kubectl get secret harbor-registry -n uneeq-renderer

# Verify secret contents
kubectl get secret harbor-registry -n uneeq-renderer -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d

# Recreate if needed (run deploy script again or):
# kubectl create secret docker-registry harbor-registry \
#   --docker-server=cr.uneeq.io \
#   --docker-username=your-robot-account \
#   --docker-password=your-robot-password \
#   -n uneeq-renderer
```

**GPU Driver Issues:**
```bash
# Check GPU operator installation
kubectl get pods -n gpu-operator

# Check driver installation logs
kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset --tail=100

# Verify GPU resources
kubectl get nodes -L nvidia.com/gpu
```

**kubectl Connection Issues:**
```bash
# Verify context
kubectl config current-context

# Test connectivity
kubectl get nodes

# Reconnect to EKS
aws eks update-kubeconfig --region us-east-2 --name renny-production
```

### Debugging Commands

```bash
# Check all events
kubectl get events -n uneeq-renderer --sort-by='.lastTimestamp'

# Interactive pod debugging
kubectl exec -it <pod-name> -n uneeq-renderer -- /bin/bash

# Check GPU utilization
kubectl exec -n gpu-operator $(kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter -o name | head -1) -- nvidia-smi
```

### Cleanup

To destroy all resources (~15-20 minutes):

```bash
./scripts/destroy.sh
```

For emergency cleanup without confirmations:
```bash
./scripts/cleanup.sh  # USE WITH CAUTION
```

## Cost Management

### Estimated Monthly Costs (us-east-1)

- **EKS Control Plane**: ~$73/month
- **NAT Gateways** (3x): ~$135/month
- **Control Nodes** (2x t3.large): ~$120/month
- **Renny Nodes** (10x g5.4xlarge): ~$8,760/month
- **Total Base**: ~$9,088/month

*Costs scale with the number of Renny instances (10-20)*

### Cost Saving Tips

1. **Destroy when not in use** - Hourly cost: ~$15-20
2. **Single NAT gateway** for dev/test
3. **Scale down during off-hours** using ASG commands
4. **Spot instances** for non-critical workloads
5. **Reserved Instances** for production

### Manual Scaling with ASG

Scale down to save costs during off-hours:

```bash
# Get ASG names
aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[?contains(AutoScalingGroupName, 'renny-production')].AutoScalingGroupName" \
  --output text

# Scale down to 0
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name eks-renny-production-renny-gpu-v4-XXXXXXXXXX \
  --desired-capacity 0 --min-size 0

# Scale back up
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name eks-renny-production-renny-gpu-v4-XXXXXXXXXX \
  --desired-capacity 2 --min-size 2
```

## Security Considerations

- ✅ All GPU nodes deployed in **private subnets**
- ✅ Security groups configured for **WebRTC/TURN traffic**
- ✅ **IRSA** enabled for pod-level AWS permissions
- ✅ Secrets managed via **Kubernetes secrets**
- ✅ Network policies can be added as needed

---

## License

This Kubernetes deployment is part of the MiniPrem platform, licensed under the MIT License - see the [LICENSE](../../LICENSE) file for details.

---

## Copyright

<div align="center">

**© 2025 UneeQ. All rights reserved.**

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

**Digital Humans. Unlimited Possibilities.**

[www.digitalhumans.com](https://www.digitalhumans.com) | [support@digitalhumans.com](mailto:support@digitalhumans.com)

</div>
