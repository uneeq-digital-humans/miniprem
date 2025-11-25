<div align="center">

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

# Azure AKS Production Deployment

> Deploy Renny digital humans on Azure AKS with NVIDIA T4 GPU acceleration

</div>

<div class="info-box">
<strong>ℹ️ Multi-Cloud Support:</strong> This guide is specific to Azure AKS. For other cloud providers, see:
<ul>
  <li><a href="kubernetes-overview.md">Multi-Cloud Overview</a> - Compare all cloud providers</li>
  <li><a href="kubernetes-eks.md">AWS EKS Deployment</a> - Deploy on AWS</li>
  <li><a href="kubernetes-multi-cloud.md">Multi-Cloud Guide</a> - Cost comparison and migration</li>
</ul>
</div>

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Azure Account Setup](#azure-account-setup)
- [GPU Instance Selection](#gpu-instance-selection)
- [GPU Quota Requests](#gpu-quota-requests)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Operations](#operations)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Cost Management](#cost-management)
- [License](#license)

## Overview

The Azure AKS deployment provides a **production-ready, auto-scaling infrastructure** for Renny digital humans with NVIDIA GPU support. This deployment is ideal for:

- **Production workloads** requiring high availability
- **Enterprise deployments** with 10-20+ concurrent digital humans
- **Auto-scaling** based on demand
- **GPU-accelerated rendering** with NVIDIA T4 GPUs
- **Azure-native integrations** with Azure services

### Key Features

- ✅ **One-click deployment** (~35-50 minutes)
- ✅ **Auto-scaling** (10-20 Renny instances)
- ✅ **NVIDIA T4 GPUs** with 16GB VRAM
- ✅ **Standard NVIDIA drivers** (580+) via GPU Operator
- ✅ **Automatic GPU driver installation**
- ✅ **Azure Monitor integration** for centralized logging
- ✅ **High availability** across 3 availability zones
- ✅ **Infrastructure as Code** with Terraform

### AKS vs EKS Comparison

| Feature | Azure AKS | AWS EKS |
|---------|-----------|---------|
| **GPU Instance** | NC16as_T4_v3 | g5.4xlarge |
| **GPU Model** | NVIDIA T4 | NVIDIA A10G |
| **GPU Memory** | 16GB | 24GB |
| **vCPUs** | 16 | 16 |
| **RAM** | 110GB | 64GB |
| **Cost (per node/hour)** | ~$1.50 | ~$1.18 |
| **Monthly Cost (10 nodes)** | ~$10,800 | ~$8,712 |
| **Deployment Time** | 35-50 min | 30-45 min |
| **GPU Time-Slicing** | 1 pod/GPU* | 2 pods/GPU |

<div class="tip-box">
<strong>*Note:</strong> T4 with 16GB VRAM works best with 1 Renny pod per GPU (4-6GB per pod). A10G with 24GB supports 2 pods per GPU with time-slicing.
</div>

## Architecture

### Infrastructure Overview

```
Azure Cloud (East US)
├── Virtual Network (10.17.0.0/16)
│   ├── Public Subnet
│   │   └── NAT Gateway
│   └── Private Subnets (3 AZs)
│       └── AKS Cluster (renny-production-aks)
│           ├── Control Plane (Managed by Azure)
│           ├── System Node Pool
│           │   └── 2× Standard_D4s_v3 instances
│           └── GPU Node Pool (rennygpu)
│               └── 10-20× NC16as_T4_v3 instances
│                   ├── NVIDIA T4 GPU (16GB VRAM)
│                   ├── GPU Operator (driver 580)
│                   └── Renny Pods (1 per GPU)
└── Azure Monitor (centralized monitoring)
```

### Network Architecture

- **WebRTC/UDP:** Ports 22000-23000 (Pixel Streaming)
- **TURN/STUN:** Port 3478 (TCP/UDP)
- **HTTPS:** Port 443 (egress to *.uneeq.io)
- **Harbor Registry:** HTTPS port 443 to cr.uneeq.io (required for image pulls)
- **Private Subnets:** All GPU nodes for security
- **Azure CNI Networking:** Native Azure networking

### Harbor Registry Access

All Renny container images are hosted in the UneeQ Harbor registry. Ensure your network allows:

- **Harbor URL**: https://cr.uneeq.io
- **Port**: 443 (HTTPS)
- **Access**: Required for initial image pull and any image updates

If your network uses a firewall or proxy, whitelist `cr.uneeq.io` to allow the AKS nodes to pull images during deployment and scaling.

## Prerequisites

### Required Tools

1. **Azure Account** with active subscription
2. **Azure CLI** >= 2.50.0 configured with credentials
3. **Terraform** >= 1.5.0
4. **kubectl** >= 1.28.0 (Kubernetes CLI)
5. **Helm** >= 3.12.0 (Kubernetes package manager)
6. **UneeQ Harbor registry access** (robot account credentials)
   - Contact help@uneeq.com for credentials
   - Registry URL: https://cr.uneeq.io
7. **Renny Helm chart** (renny-chart.tgz file)

### Installation Commands

**Azure CLI:**
```bash
# macOS
brew install azure-cli

# Linux
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Windows
winget install -e --id Microsoft.AzureCLI
```

**Other Tools:**
```bash
# Terraform
# macOS: brew install terraform
# Linux: https://www.terraform.io/downloads

# kubectl
# macOS: brew install kubectl
# Linux: sudo snap install kubectl --classic

# Helm
# macOS: brew install helm
# Linux: sudo snap install helm --classic
```

### Verify Installations

```bash
az --version        # Azure CLI version (>= 2.50.0)
terraform version   # Terraform version (>= 1.5.0)
kubectl version     # Kubernetes CLI
helm version        # Helm package manager
```

## Azure Account Setup

### Step 1: Create Azure Account

If you don't have an Azure account:

1. Visit [https://azure.microsoft.com/free/](https://azure.microsoft.com/free/)
2. Click "Start free" - Get $200 free credit for 30 days
3. Sign in with Microsoft account
4. Complete identity verification (phone + credit card)

**Free Trial Benefits:**
- $200 credit valid for 30 days
- 12 months of free services
- 25+ always-free services

### Step 2: Login to Azure CLI

```bash
# Interactive browser-based login
az login

# Verify login successful
az account show --output table
```

**Output Example:**
```
Name                 CloudName    SubscriptionId                        State
-------------------  -----------  ------------------------------------  -------
Pay-As-You-Go        AzureCloud   12345678-1234-1234-1234-123456789012  Enabled
```

### Step 3: Set Default Subscription

If you have multiple subscriptions:

```bash
# List all subscriptions
az account list --output table

# Set default subscription
az account set --subscription "12345678-1234-1234-1234-123456789012"

# Verify active subscription
az account show --query '[name,id]' --output table
```

### Step 4: Register Resource Providers

Azure requires resource providers to be registered:

```bash
# Register required providers
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.Storage

# Check registration status (takes 2-5 minutes)
az provider show -n Microsoft.Compute --query "registrationState"
az provider show -n Microsoft.ContainerService --query "registrationState"
# All should show: "Registered"
```

## GPU Instance Selection

### Recommended: NC16as_T4_v3

<div class="success-box">
<strong>✅ NC16as_T4_v3 is the Recommended Choice</strong>
</div>

**Why NC16as_T4_v3 Works for Renny:**

| Feature | NC16as_T4_v3 | Benefit |
|---------|--------------|---------|
| **GPU** | NVIDIA T4 (16GB) | Turing architecture with RT cores |
| **vCPUs** | 16 AMD EPYC | Excellent CPU performance |
| **RAM** | 110GB | Ample memory for Renny |
| **Driver Type** | **Standard NVIDIA** | GPU Operator compatible |
| **Cost** | ~$1.50/hour | Cost-effective |
| **CUDA Support** | 12.4+ | Modern CUDA toolkit |
| **RT Cores** | 40 | Hardware ray tracing |
| **Tensor Cores** | 320 | AI acceleration |

**Proven Compatibility:**
- ✅ Standard NVIDIA drivers (not vGPU)
- ✅ GPU Operator automatic driver installation
- ✅ 16GB VRAM sufficient for 4 Renny pods per node
- ✅ Unreal Engine Pixel Streaming validated
- ✅ AMD EPYC processors provide excellent performance

### AVOID: NVads_A10_v5

<div class="warning-box">
<strong>⚠️ Do NOT Use NVads_A10_v5</strong>
</div>

**Why NVads_A10_v5 is NOT Recommended:**

| Issue | Description |
|-------|-------------|
| **vGPU/GRID Drivers Required** | Cannot use standard NVIDIA drivers |
| **GPU Operator Incompatible** | Requires manual driver management |
| **Untested with Renny** | No validation with Unreal Engine |
| **Higher Cost** | 2× more expensive (~$3.06/hour) |
| **Complex Setup** | Requires NVIDIA AI Enterprise license |

### Regional Availability

Check if NC16as_T4_v3 is available in your target region:

```bash
# Check availability in East US
az vm list-skus --location eastus --size Standard_NC --all --output table | grep NC16as_T4_v3

# Check availability in West US 2
az vm list-skus --location westus2 --size Standard_NC --all --output table | grep NC16as_T4_v3
```

**Confirmed Available Regions:**
- ✅ East US
- ✅ West US 2
- ✅ North Europe
- ✅ West Europe
- ✅ Southeast Asia
- ✅ Australia East

## GPU Quota Requests

<div class="warning-box">
<strong>⚠️ Critical:</strong> Azure enforces strict GPU quotas. You MUST request quota increases before deployment.
</div>

### Required Quotas for 10-Node Deployment

| Resource | Default | Required | How to Request |
|----------|---------|----------|----------------|
| **Standard NCASv3_T4 Family vCPUs** | 0 | 160 | Support ticket |
| **Total Regional vCPUs** | 20 | 200+ | Support ticket |
| **Public IP Addresses** | 10 | 20 | Support ticket (optional) |

**Calculation:**
- 10 nodes × 16 vCPUs per NC16as_T4_v3 = 160 vCPUs
- Add control plane and overhead = ~200 total vCPUs

### Check Current Quotas

```bash
# Check NC-series quota in East US
az vm list-usage --location eastus --query "[?contains(name.value, 'standardNCASFamily')]" --output table

# Check total regional vCPU quota
az vm list-usage --location eastus --query "[?contains(name.value, 'cores')]" --output table
```

### Request Quota Increase

**Method 1: Azure Portal (Recommended)**

1. Go to [Azure Portal](https://portal.azure.com)
2. Search for "Quotas" → Select "Compute"
3. Filter by: Location = eastus (your target region)
4. Search for "Standard NCASv3_T4 Family vCPUs"
5. Click quota row → "Request increase"
6. Enter new limit: **160** (for 10 nodes)
7. Business justification: "Deploying Renny digital humans on AKS with GPU support"
8. Click "Submit"

**Method 2: Azure CLI**

```bash
# Create support ticket for quota increase
az support tickets create \
  --ticket-name "Renny-GPU-Quota-Request" \
  --title "Quota increase for Standard NCASv3_T4 Family vCPUs" \
  --severity minimal \
  --description "Requesting 160 vCPUs for NC16as_T4_v3 instances in East US region for Renny digital human deployment"
```

### Quota Request Timeline

**Expected Processing Time:**
- Standard Request: 1-3 business days
- Large Request (200+ vCPUs): 3-5 business days
- Free Trial Accounts: 5-7 business days
- Urgent Request: 1 business day (requires Premier Support)

**Tips for Faster Approval:**
- Provide detailed business justification
- Specify exact instance types (NC16as_T4_v3)
- Mention expected usage duration
- Be specific about location and quantity

## Quick Start

### Step 1: Create Service Principal

Terraform needs a Service Principal to authenticate with Azure:

```bash
# Create service principal and assign Contributor role
az ad sp create-for-rbac \
  --name "renny-aks-deployer" \
  --role Contributor \
  --scopes /subscriptions/$(az account show --query id -o tsv) \
  --output json

# Save the output - you'll need these values:
{
  "appId": "12345678-1234-1234-1234-123456789012",      # CLIENT_ID
  "password": "super-secret-password-here",              # CLIENT_SECRET
  "tenant": "87654321-4321-4321-4321-210987654321"      # TENANT_ID
}
```

<div class="warning-box">
<strong>⚠️ Important:</strong> Save the <code>password</code> immediately - Azure will never show it again!
</div>

### Step 2: Configure Credentials

Create `kubernetes/terraform/aks/terraform.tfvars`:

```hcl
# Azure authentication
subscription_id = "your-subscription-id"
tenant_id       = "your-tenant-id"
client_id       = "your-client-id"
client_secret   = "your-client-secret"

# Required Renny credentials
dhop_tenant_id   = "your-uneeq-tenant-id"
dhop_api_key     = "your-uneeq-api-key"

# Harbor registry credentials (robot account)
# Contact help@uneeq.com or your UneeQ representative to obtain credentials
harbor_username  = "robot$your-customer-name"
harbor_password  = "your-robot-password"

# Optional: Override defaults
azure_region = "eastus"  # Change to your preferred region
cluster_name = "renny-production-aks"
```

### Step 3: Place Helm Chart

Place your `renny-chart.tgz` file in the `kubernetes/` directory.

### Step 4: Run Pre-Deployment Checks

```bash
cd kubernetes/scripts/aks/

# Verify Azure setup and prerequisites
./check-azure-prerequisites.sh

# Check VNet availability (Azure has limits)
./check-vnet-usage.sh
```

### Step 5: Deploy

Run the one-click deployment:

```bash
cd kubernetes/

# Deploy to Azure AKS
./scripts/deploy.sh --cloud aks

# Or let it auto-detect
./scripts/deploy.sh
```

### Deployment Process

The deployment script will:

1. ✅ **Check prerequisites** (Azure credentials, tools) ~2 min
2. 🏗️ **Deploy VNet and AKS cluster** via Terraform ~15-20 min
3. 🚀 **Configure node pools** and join to cluster ~3-5 min
4. 🎮 **Install NVIDIA GPU Operator** ~5-10 min
5. 🤖 **Deploy Renny** with internal speech processing ~5-10 min
6. ⚖️ **Configure autoscaling** (10-20 instances) ~3 min

**Total deployment time: ~35-50 minutes**

## Configuration

### GPU Configuration

GPU settings are managed in `kubernetes/values/renny-values-aks.yaml`:

```yaml
# GPU configuration for AKS T4 instances
gpuTimeSlicing:
  enabled: false  # T4 16GB works best with 1 pod per GPU
  replicasPerGpu: 1

deployment:
  nodeType: renny
  totalReplicas: 40  # 10 nodes × 4 pods = 40 total pods

resources:
  limits:
    nvidia.com/gpu: 1  # Each pod gets full GPU
    memory: "6Gi"      # Per-pod memory
    cpu: "3"           # Per-pod CPU (3 cores)
```

### NVIDIA Driver Selection

During deployment, choose between:

**Driver 580+ (Recommended)**
- ✅ Latest features and optimizations
- ✅ REQUIRED for NVIDIA 5xxx series GPUs
- ✅ CUDA 12.8+ support
- ✅ Full T4 compatibility

**Driver 575+ (Stable Alternative)**
- ✅ Production-tested and validated
- ✅ Maximum stability
- ✅ CUDA 12.6+ support

### Text-to-Speech Configuration

Configure TTS providers in `kubernetes/values/renny-values-aks.yaml`:

```yaml
# Azure Speech Services (recommended for AKS)
tts:
  azureRegion: "eastus"
  azureSpeechKey: "your-azure-api-key"
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

# Verify GPU availability
kubectl get nodes -l kubernetes.azure.com/agentpool=rennygpu

# Test GPU functionality
POD=$(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset -o name | head -1)
kubectl exec -n gpu-operator $POD -- nvidia-smi
```

### Check kubectl Context

After deployment, kubectl automatically connects to your AKS cluster:

```bash
# Verify connection
kubectl config current-context

# Reconnect if needed
az aks get-credentials --resource-group renny-production-rg --name renny-production-aks
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

# View logs
kubectl logs <pod-name> -n uneeq-renderer -f
```

### Azure Monitor Integration

All Renny logs are automatically sent to Azure Monitor for centralized monitoring.

**Log Analytics Workspace:**
- Cluster logs: Container insights
- Application logs: Log Analytics

**Example Kusto Query (Log Analytics):**

Find recent errors:
```kql
ContainerLog
| where LogEntry contains "error"
| where Namespace == "uneeq-renderer"
| order by TimeGenerated desc
| limit 50
```

Monitor speech processing:
```kql
ContainerLog
| where LogEntry contains "speech" or LogEntry contains "NEW_SPEECH_OVERRIDE"
| where Namespace == "uneeq-renderer"
| order by TimeGenerated desc
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
kubectl get nodes -l kubernetes.azure.com/agentpool=rennygpu
```

### Cleanup

To destroy all resources (~15-20 minutes):

```bash
./scripts/destroy.sh
```

## Cost Management

### Estimated Monthly Costs (East US)

| Component | Specification | Quantity | Monthly Cost |
|-----------|--------------|----------|--------------|
| **GPU Compute** | NC16as_T4_v3 | 10 nodes | $10,800 |
| **AKS Control Plane** | Managed service | 1 cluster | $73 |
| **System Nodes** | Standard_D4s_v3 | 2 nodes | $288 |
| **Load Balancer** | Standard SKU | 1 LB | $25 |
| **Public IPs** | Standard SKU | 3 IPs | $12 |
| **Managed Disks** | Premium SSD | ~500GB | $75 |
| **Azure Monitor** | Log Analytics | ~50GB | $125 |
| **Total** | | | **~$11,398/month** |

### Cost Saving Strategies

**1. Reserved Instances (30-40% savings)**
```bash
# 1-year reserved: ~$1.05/hour = ~$7,560/month (save $3,240/month)
# 3-year reserved: ~$0.90/hour = ~$6,480/month (save $4,320/month)
```

**2. Spot Instances (60-80% savings for dev/test)**
```bash
# Spot pricing: ~$0.30-0.60/hour (vs $1.50 regular)
# Savings: ~$8,640/month on 10-node cluster
# Caveat: Can be evicted with 30-second notice
```

**3. Auto-Scaling During Off-Hours**
```bash
# Scale down to 2-5 nodes during nights/weekends
# Savings: ~40% reduction = ~$4,320/month
```

**4. Scheduled Shutdown**
```bash
# Stop cluster at night and weekends
az aks stop --name renny-production-aks --resource-group renny-production-rg
az aks start --name renny-production-aks --resource-group renny-production-rg

# Savings: ~70% = ~$7,560/month
```

### Cost Monitoring

```bash
# Check current month spending
az consumption usage list --start-date 2025-10-01 --end-date 2025-10-16

# Set up budget alerts
az consumption budget create \
  --budget-name renny-monthly-budget \
  --amount 12000 \
  --time-grain Monthly
```

---

## License

This Azure AKS deployment is part of the MiniPrem platform, licensed under the MIT License - see the [LICENSE](../../LICENSE) file for details.

---

## Copyright

<div align="center">

**© 2025 UneeQ. All rights reserved.**

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

**Digital Humans. Unlimited Possibilities.**

[www.digitalhumans.com](https://www.digitalhumans.com) | [support@digitalhumans.com](mailto:support@digitalhumans.com)

</div>
