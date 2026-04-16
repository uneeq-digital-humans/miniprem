# Google Cloud GKE Deployment Guide - Complete Walkthrough

This guide walks you through deploying UneeQ MiniPrem (Renny digital humans) on Google Kubernetes Engine (GKE) from start to finish.

**Timeline**: 1-5 days (mostly waiting for GPU quota approval)
**Cost**: ~$2,280/month for 10 kiosks (8 hours/day)
**Difficulty**: Moderate (automated deployment script)

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Google Cloud Account Setup](#2-google-cloud-account-setup)
3. [GPU Quota Request (Critical)](#3-gpu-quota-request-critical)
4. [Install Required Tools](#4-install-required-tools)
5. [Configure Deployment Settings](#5-configure-deployment-settings)
6. [Run Deployment Script](#6-run-deployment-script)
7. [Verify Deployment](#7-verify-deployment)
8. [Connect Kiosks](#8-connect-kiosks)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Prerequisites

**Before You Start:**
- [ ] Credit card for Google Cloud billing
- [ ] UneeQ platform account and credentials
- [ ] Helm chart file: `renny-chart.tgz` (provided by UneeQ)
- [ ] Basic terminal/command-line knowledge
- [ ] macOS, Linux, or Windows with WSL2

**What You're Deploying:**
- Google Kubernetes Engine (GKE) cluster
- 10 GPU nodes with NVIDIA T4 GPUs (16GB VRAM each)
- 2 system nodes for Kubernetes control plane
- NVIDIA GPU Operator for driver management
- Renny digital human renderer pods

---

## 2. Google Cloud Account Setup

### Step 1: Create Google Cloud Account

1. Go to [https://cloud.google.com](https://cloud.google.com)
2. Click **"Get started for free"** or **"Sign in"**
3. Sign in with your Google account (or create new one)
4. Complete identity verification:
   - Select country
   - Accept terms of service
   - Enter billing information (credit card)
5. **New users get $300 free credits** (valid 90 days)

### Step 2: Create a GCP Project

```bash
# Install Google Cloud SDK first (see section 4)
# Then create project:

# Login to Google Cloud
gcloud auth login

# Create dedicated project for Renny
gcloud projects create renny-kubernetes-prod --name="Renny Digital Humans - Production"

# Set as default project
gcloud config set project renny-kubernetes-prod

# Verify project
gcloud config get-value project
```

**Save your project ID:**
```bash
export PROJECT_ID=$(gcloud config get-value project)
echo "Project ID: $PROJECT_ID"
```

### Step 3: Enable Billing

**Via Console (Easiest):**
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Search for **"Billing"** in top search bar
3. Click **"Link a billing account"**
4. Select your billing account
5. Click **"Set account"**

**Verify Billing Enabled:**
```bash
gcloud billing projects list --filter="projectId:$PROJECT_ID"
# Should show your project with billing account linked
```

### Step 4: Enable Required APIs

Run this command to enable all necessary APIs:

```bash
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  iamcredentials.googleapis.com
```

**Expected output:**
```
Operation "operations/..." finished successfully.
```

---

## 3. GPU Quota Request (Critical)

⚠️ **THIS IS THE MOST IMPORTANT STEP - ALLOW 1-5 BUSINESS DAYS**

### Why GPU Quota is Required

Google Cloud **blocks all GPU access by default**. Your project starts with:
- **0 GPUs allocated** (cannot deploy without approval)
- Must request quota increase before deployment
- Approval takes 1-5 business days

### What to Request

For **10 kiosks** (10 concurrent digital humans):

| Quota Name | Current | Request | Why |
|------------|---------|---------|-----|
| **GPUs (T4) in us-central1** | 0 | **10** | One T4 GPU per node |
| **Compute Engine Instances** | 10-24 | **15** | 10 GPU + 2 system + 3 buffer |

### How to Request Quota Increase

#### Option A: Google Cloud Console (Recommended)

1. **Navigate to Quotas:**
   - Go to [https://console.cloud.google.com/iam-admin/quotas](https://console.cloud.google.com/iam-admin/quotas)
   - Make sure your project is selected (top dropdown)

2. **Filter for T4 GPUs:**
   - In "Filter" box, type: `GPUs T4`
   - Or use: Service = `Compute Engine API`, Metric = `GPUs (T4)`
   - Select region: `us-central1`

3. **Request Increase:**
   - Click the checkbox next to **"GPUs (T4) for us-central1"**
   - Click **"Edit Quotas"** button at top
   - Enter **New limit: 10**
   - Click **"Next"**

4. **Add Justification:**
   ```
   Business justification:

   Deploying Renny digital human renderer on GKE for interactive kiosk applications.
   Requires GPU acceleration (NVIDIA T4) for real-time 3D graphics rendering with
   ray tracing capabilities. Production deployment serving 10 concurrent kiosk sessions.

   Use case: Digital human customer service at multiple retail locations.
   Estimated usage: 8 hours/day, 20 days/month.
   ```

5. **Submit Request:**
   - Click **"Next"**
   - Review details
   - Click **"Submit Request"**

6. **Wait for Approval:**
   - Check email for approval notification
   - Typical approval: 1-2 business days
   - Large requests (10+ GPUs): 3-5 business days

#### Option B: Check Status

```bash
# Check current GPU quota
gcloud compute regions describe us-central1 \
  --format="value(quotas[name=NVIDIA_T4_GPUS].limit)"

# List all GPU quotas
gcloud compute project-info describe \
  --format="table(quotas[].{name:name,limit:limit,usage:usage})" | grep GPU
```

### What If Request is Denied?

**Common reasons:**
- Brand new project (less than 48 hours old)
- Regional capacity constraints
- Billing verification needed

**Solutions:**
1. **Try different region**: `us-east1` or `us-west1`
2. **Start smaller**: Request 5 GPUs first, scale later
3. **Wait 24-48 hours**: New projects may have restrictions
4. **Contact support**: [https://cloud.google.com/support](https://cloud.google.com/support)

**⚠️ DO NOT PROCEED until GPU quota is approved!**

---

## 4. Install Required Tools

### Google Cloud SDK (gcloud)

**macOS:**
```bash
# Using Homebrew (recommended)
brew install --cask google-cloud-sdk

# Verify installation
gcloud version
```

**Linux (Debian/Ubuntu):**
```bash
# Add Google Cloud repository
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list

# Import key
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -

# Install
sudo apt-get update && sudo apt-get install google-cloud-sdk

# Verify
gcloud version
```

**Windows:**
```powershell
# Using winget
winget install -e --id Google.CloudSDK

# Verify (restart terminal first)
gcloud version
```

### Authenticate with Google Cloud

```bash
# Login to Google Cloud
gcloud auth login
# Browser opens - sign in and grant permissions

# Set up application credentials for Terraform
gcloud auth application-default login

# Set default project
gcloud config set project renny-kubernetes-prod

# Verify authentication
gcloud auth list
gcloud config get-value project
```

### Install kubectl

```bash
# Install kubectl via gcloud
gcloud components install kubectl

# Verify
kubectl version --client
```

### Install Terraform

**macOS:**
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Verify
terraform version
```

**Linux:**
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Verify
terraform version
```

**Windows:**
```powershell
winget install -e --id Hashicorp.Terraform

# Verify
terraform version
```

### Install Helm

```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Windows
winget install -e --id Helm.Helm

# Verify
helm version
```

---

## 5. Configure Deployment Settings

### Step 1: Navigate to MiniPrem Repository

```bash
cd /path/to/miniprem-2025/kubernetes/
```

### Step 2: Place Helm Chart

Copy the `renny-chart.tgz` file provided by UneeQ:

```bash
# Copy Helm chart to repository root
cp /path/to/renny-chart.tgz ./renny-chart.tgz

# Verify file exists
ls -lh renny-chart.tgz
# Should show: renny-chart.tgz (around 50-100MB)
```

### Step 3: Configure Terraform Variables

**Edit the file:** `kubernetes/terraform/gke/terraform.tfvars`

```bash
# Open with your editor
nano kubernetes/terraform/gke/terraform.tfvars
# OR
code kubernetes/terraform/gke/terraform.tfvars
```

**Example configuration:**

```hcl
# Google Cloud Project Configuration
project_id = "renny-kubernetes-prod"  # ← Your GCP project ID
region     = "us-central1"            # ← Where GPU quota was approved

# Cluster Configuration
cluster_name        = "renny-gke-prod"
kubernetes_version  = "1.28"

# GPU Node Pool Configuration
gpu_node_count      = 10               # ← Number of GPU nodes (= max concurrent sessions)
gpu_node_type       = "n1-standard-16" # ← 16 vCPUs, 60GB RAM per node
gpu_type            = "nvidia-tesla-t4" # ← T4 GPU (16GB VRAM)
gpu_count_per_node  = 1                # ← 1 GPU per node

# System Node Pool Configuration (non-GPU)
system_node_count   = 2                # ← Kubernetes control plane nodes
system_node_type    = "e2-standard-4"  # ← 4 vCPUs, 16GB RAM

# Networking
vpc_cidr            = "10.20.0.0/16"   # ← VPC network range

# Deployment Metadata
deployment_id       = "miniprem-gke-prod-001" # ← Unique identifier for telemetry
environment         = "production"      # ← production, staging, or development

# Tags (optional - for cost tracking)
tags = {
  Project     = "MiniPrem"
  Environment = "Production"
  ManagedBy   = "Terraform"
  Department  = "IT"
}
```

**Key Settings to Customize:**

| Setting | What to Change | Notes |
|---------|---------------|-------|
| `project_id` | Your GCP project ID | From step 2 |
| `region` | Where GPU quota approved | Usually `us-central1` |
| `cluster_name` | Unique cluster name | E.g., `renny-dps-prod` |
| `gpu_node_count` | Number of kiosks | 10 nodes = 10 concurrent sessions |
| `deployment_id` | Unique identifier | Used for telemetry tracking |

**Save the file** (Ctrl+O in nano, Ctrl+S in VS Code)

### Step 4: Configure Renny Values

**Edit the file:** `kubernetes/values/renny-values-gke.yaml`

```bash
# Open with your editor
nano kubernetes/values/renny-values-gke.yaml
# OR
code kubernetes/values/renny-values-gke.yaml
```

**Critical sections to configure:**

#### A. TTS (Text-to-Speech) Configuration

**Choose ONE provider and fill in ALL required fields:**

```yaml
tts:
  # OPTION 1: Azure Speech Services (Recommended)
  azureRegion: "eastus"                          # Your Azure region
  azureSpeechKey: "your-azure-speech-key-here"  # API key from Azure portal

  # OPTION 2: ElevenLabs
  elevenlabsApiKey: "sk_your_elevenlabs_key"    # API key (starts with sk_)
  elevenlabsModelId: "eleven_turbo_v2"           # Model ID
  elevenlabsOptimizeLatencyLevel: "1"            # Latency 0-4 (lower = faster)

  # OPTION 3: Google Cloud TTS
  gcpCredentials: ""                              # Service account JSON (single line)

  # OPTION 4: Veritone TTS
  veritoneApiKey: ""                              # Veritone API key

  # OPTION 5: Custom TTS Proxy
  proxyUrl: ""                                    # Your custom TTS endpoint
```

**Get Azure Speech Key:**
1. Go to [https://portal.azure.com](https://portal.azure.com)
2. Create "Speech Service" resource
3. Copy "Key 1" from "Keys and Endpoint"

#### B. UneeQ Platform Configuration

```yaml
# UneeQ Platform Settings
uneeq:
  personaId: "your-persona-id-here"              # From UneeQ workspace
  workspaceId: "your-workspace-id-here"          # From UneeQ workspace
  apiToken: "your-uneeq-api-token"               # From UneeQ platform settings
```

**Get UneeQ Credentials:**
1. Login to UneeQ Creator: [https://creator.us.uneeq.io](https://creator.us.uneeq.io)
2. Select your workspace
3. Go to Settings → API Tokens
4. Copy Persona ID and Workspace ID

#### C. GPU Time-Slicing (Optional)

```yaml
gpuTimeSlicing:
  replicasPerGpu: 1  # Do NOT change for GKE (use 1 pod per GPU)

deployment:
  totalReplicas: 10  # Must match gpu_node_count in terraform.tfvars
```

**⚠️ For GKE: Always use `replicasPerGpu: 1` (no time-slicing)**
GKE native GPU sharing is better than time-slicing.

#### D. Resource Limits

```yaml
resources:
  limits:
    memory: "16Gi"       # RAM per pod
    cpu: "8000m"         # CPU cores per pod (8 cores)
    nvidia.com/gpu: "1"  # GPUs per pod (always 1)
  requests:
    memory: "12Gi"       # Minimum RAM
    cpu: "4000m"         # Minimum CPU (4 cores)
    nvidia.com/gpu: "1"  # GPUs requested
```

**Save the file**

### Step 5: Verify Configuration

Run pre-deployment checks:

```bash
# Check Terraform syntax
cd kubernetes/terraform/gke/
terraform init
terraform validate

# Check if GPU quota is sufficient
gcloud compute regions describe us-central1 \
  --format="value(quotas[name=NVIDIA_T4_GPUS].limit)"
# Should show: 10 (or your requested amount)

# Verify authentication
gcloud auth list
# Should show your account with [ACTIVE]
```

---

## 6. Run Deployment Script

### Step 1: Start Deployment

```bash
# Navigate to kubernetes directory
cd /path/to/miniprem-2025/kubernetes/

# Make scripts executable
chmod +x scripts/*.sh

# Run GKE deployment script
./scripts/deploy-gcp.sh
```

### Step 2: Deployment Process

**The script will:**

1. **Validate prerequisites** (~1 min)
   - Check gcloud authentication
   - Verify project exists
   - Check GPU quota availability
   - Validate Helm chart exists

2. **Deploy infrastructure with Terraform** (~15-20 min)
   - Create VPC network
   - Create GKE cluster
   - Create GPU node pool (10 nodes)
   - Create system node pool (2 nodes)
   - Configure networking and firewall rules

3. **Install NVIDIA GPU Operator** (~5-10 min)
   - Deploy GPU device plugins
   - Install NVIDIA drivers (automatically)
   - Configure GPU monitoring

4. **Deploy Renny application** (~5-10 min)
   - Upload Helm chart
   - Apply configurations from `renny-values-gke.yaml`
   - Create Kubernetes resources
   - Start Renny pods

5. **Wait for pods to be ready** (~5-10 min)
   - Download container images (~5GB per node)
   - Initialize GPU drivers
   - Start Renny processes

**Total deployment time: ~30-50 minutes**

### Step 3: Monitor Deployment

**In a separate terminal, watch progress:**

```bash
# Watch cluster creation
watch -n 5 gcloud container clusters list

# Watch node status (after cluster created)
watch -n 5 kubectl get nodes

# Watch pod status (after Renny deployed)
watch -n 5 kubectl get pods -n uneeq-renderer

# View deployment logs
kubectl logs -n uneeq-renderer -l app=renderer -f --tail=50
```

### Step 4: Expected Output

**Successful deployment shows:**

```
✅ Terraform infrastructure deployed successfully
✅ GKE cluster created: renny-gke-prod
✅ GPU Operator installed successfully
✅ NVIDIA drivers detected: 535.129.03
✅ Renny Helm chart deployed
✅ 10/10 pods running

📊 Deployment Summary:
   Cluster: renny-gke-prod (us-central1)
   GPU Nodes: 10 (n1-standard-16 + T4)
   System Nodes: 2 (e2-standard-4)
   Renny Pods: 10/10 running

🔗 Next Steps:
   1. Configure TURN server with UneeQ platform
   2. Test digital human connectivity
   3. Scale if needed: ./scripts/scale-gcp.sh 15

💰 Estimated Cost: ~$9.50/hour ($228/day @ 24hrs, $2,280/month @ 8hrs/day)
```

---

## 7. Verify Deployment

### Check Cluster Status

```bash
# View cluster details
gcloud container clusters describe renny-gke-prod --region us-central1

# Get cluster credentials
gcloud container clusters get-credentials renny-gke-prod --region us-central1

# Verify kubectl access
kubectl cluster-info
```

### Check GPU Nodes

```bash
# List all nodes
kubectl get nodes -o wide

# Check GPU allocation
kubectl get nodes -o custom-columns=NAME:.metadata.name,GPUS:.status.allocatable."nvidia\.com/gpu"

# Should show:
# NAME                                    GPUS
# gke-renny-gke-prod-gpu-pool-xxxxx       1
# gke-renny-gke-prod-gpu-pool-xxxxx       1
# ... (10 total GPU nodes)
```

### Check Renny Pods

```bash
# List Renny pods
kubectl get pods -n uneeq-renderer

# Should show 10 pods in Running state:
# NAME                        READY   STATUS    RESTARTS   AGE
# renderer-xxxxx-xxxxx        2/2     Running   0          5m
# renderer-xxxxx-xxxxx        2/2     Running   0          5m
# ... (10 total)

# Check pod logs
kubectl logs -n uneeq-renderer renderer-xxxxx-xxxxx -c renny --tail=50

# Expected log output:
# [INFO] Renny starting...
# [INFO] GPU detected: NVIDIA Tesla T4
# [INFO] Vulkan initialized successfully
# [INFO] Ready to accept connections
```

### Test GPU Access

```bash
# Check GPU driver in one pod
kubectl exec -n uneeq-renderer renderer-xxxxx-xxxxx -c renny -- nvidia-smi

# Expected output:
# +-----------------------------------------------------------------------------+
# | NVIDIA-SMI 535.129.03   Driver Version: 535.129.03   CUDA Version: 12.2   |
# |-------------------------------+----------------------+----------------------+
# | GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
# |   0  Tesla T4            On   | 00000000:00:04.0 Off |                    0 |
# +-----------------------------------------------------------------------------+
```

### Check Deployment Status Script

```bash
# Run status check script
cd /path/to/miniprem-2025/kubernetes/
./scripts/status-gcp.sh

# Shows:
# - Cluster health
# - Node status
# - Pod readiness
# - GPU allocation
# - Cost estimates
```

---

## 8. Connect Kiosks

### Step 1: Configure UneeQ Platform

1. **Login to UneeQ Creator:**
   - Go to [https://creator.us.uneeq.io](https://creator.us.uneeq.io)
   - Select your workspace

2. **Configure TURN Server:**
   - Go to Settings → Advanced → WebRTC
   - Add TURN server details (provided by UneeQ support)
   - Save configuration

3. **Link Renny Deployment:**
   - Go to Digital Humans → Your Persona
   - Settings → Renderer Configuration
   - Select "External Renderer"
   - Enter GKE cluster endpoint (provided by deployment script)

### Step 2: Test Connection

**From deployment script output, copy the WebSocket URL:**
```
wss://renderer.example.com/ws
```

**Test with UneeQ Creator:**
1. Go to Digital Humans → Your Persona
2. Click "Test" button
3. Should connect and show digital human

### Step 3: Kiosk Setup

**Each kiosk needs:**
- Chrome/Edge browser (latest version)
- 10 Mbps download / 5 Mbps upload (minimum)
- UneeQ web widget embedded in webpage

**Example HTML for kiosk:**
```html
<!DOCTYPE html>
<html>
<head>
  <title>Digital Human Kiosk</title>
  <script src="https://widget.uneeq.io/v1/uneeq-widget.js"></script>
</head>
<body>
  <div id="uneeq-widget"></div>
  <script>
    UneeqWidget.init({
      personaId: 'your-persona-id',
      workspaceId: 'your-workspace-id',
      container: '#uneeq-widget',
      fullscreen: true
    });
  </script>
</body>
</html>
```

---

## 9. Troubleshooting

### Deployment Fails: GPU Quota Error

**Error:**
```
Error: Quota 'NVIDIA_T4_GPUS' exceeded. Limit: 0 in region us-central1.
```

**Solution:**
- GPU quota not approved yet
- Check quota status in Google Cloud Console
- Wait for approval (1-5 business days)
- Verify quota was requested for correct region

### Pods Stuck in "Pending" State

**Check:**
```bash
kubectl describe pod -n uneeq-renderer renderer-xxxxx-xxxxx
```

**Common causes:**
1. **Insufficient GPU quota** - Check events for "Insufficient nvidia.com/gpu"
2. **Node not ready** - Check `kubectl get nodes`
3. **Image pull errors** - Check ImagePullBackOff errors

**Solution:**
```bash
# Check node status
kubectl get nodes -o wide

# Check GPU device plugin
kubectl get pods -n gpu-operator -l app=nvidia-device-plugin-daemonset

# Restart GPU device plugin if needed
kubectl delete pods -n gpu-operator -l app=nvidia-device-plugin-daemonset
```

### Renny Pod Crashes: "Vulkan initialization failed"

**Check logs:**
```bash
kubectl logs -n uneeq-renderer renderer-xxxxx-xxxxx -c renny
```

**Solution:**
```bash
# Verify GPU Operator is running
kubectl get pods -n gpu-operator

# Check NVIDIA driver version
kubectl exec -n uneeq-renderer renderer-xxxxx-xxxxx -c renny -- nvidia-smi

# Driver should be 535+ or 580+
# If not, reinstall GPU Operator:
helm uninstall gpu-operator -n gpu-operator
./scripts/deploy-gcp.sh  # Re-run deployment
```

### High Costs / Unexpected Billing

**Check current cost:**
```bash
# View node count
kubectl get nodes | grep gpu

# Check if nodes are scaled down
./scripts/status-gcp.sh
```

**Reduce costs:**
```bash
# Scale down GPU nodes
./scripts/scale-gcp.sh 5  # Scale to 5 nodes

# Or destroy completely when not in use
./scripts/destroy-gcp.sh
```

### Cannot Connect to Cluster

**Error:**
```
Unable to connect to the server: dial tcp: lookup xxx: no such host
```

**Solution:**
```bash
# Re-authenticate
gcloud auth login
gcloud auth application-default login

# Get cluster credentials again
gcloud container clusters get-credentials renny-gke-prod --region us-central1

# Verify
kubectl cluster-info
```

---

## Quick Command Reference

```bash
# Check deployment status
./scripts/status-gcp.sh

# Scale GPU nodes
./scripts/scale-gcp.sh 15  # Scale to 15 nodes

# View Renny logs
kubectl logs -n uneeq-renderer -l app=renderer -f --tail=50

# Check GPU allocation
kubectl get nodes -L nvidia.com/gpu

# Test GPU in pod
kubectl exec -n uneeq-renderer POD_NAME -c renny -- nvidia-smi

# Delete and recreate pods
kubectl delete pods --all -n uneeq-renderer

# Destroy entire deployment
./scripts/destroy-gcp.sh
```

---

## Cost Management

**Daily costs (8 hours/day):**
- 10 GPU nodes: $9.50/hour × 8 hours = **$76/day**
- Monthly: $76 × 30 days = **$2,280/month**

**Cost optimization tips:**
1. **Scale down when not in use:**
   ```bash
   ./scripts/scale-gcp.sh 0  # Scale to 0 during off-hours
   ```

2. **Use committed use discounts:**
   - 1-year commitment: 25% savings
   - 3-year commitment: 52% savings

3. **Destroy cluster when not needed:**
   ```bash
   ./scripts/destroy-gcp.sh  # Complete teardown
   ```

4. **Monitor costs:**
   - Google Cloud Console → Billing → Reports
   - Set up budget alerts

---

## Support

**Issues with this guide:**
- Open issue: [GitHub Issues](https://github.com/your-repo/issues)
- Email: support@yourcompany.com

**Google Cloud Support:**
- [https://cloud.google.com/support](https://cloud.google.com/support)

**UneeQ Platform Support:**
- Email: support@uneeq.com
- Documentation: [https://docs.uneeq.io](https://docs.uneeq.io)

---

**Last Updated:** November 2025
**Version:** 1.0.0
