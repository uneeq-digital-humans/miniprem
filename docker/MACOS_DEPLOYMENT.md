<div align="center">

![UneeQ Logo](https://presales.services.uneeq.io/uneeq-internal/assets/logos/UneeQ+Logo+Horizontal+CMYK.png)

# MiniPrem Monitor - macOS Deployment Guide

> Professional monitoring dashboard for Docker containers and Kubernetes clusters on macOS

**Tested on macOS Sonoma 14.x+ | Docker Desktop 4.25+**

</div>

---

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Step-by-Step Installation](#step-by-step-installation)
- [What Works on macOS](#what-works-on-macos)
- [Kubernetes Integration](#kubernetes-integration)
- [Accessing the Application](#accessing-the-application)
- [Troubleshooting](#troubleshooting)
- [macOS-Specific Considerations](#macos-specific-considerations)
- [Performance Optimization](#performance-optimization)
- [Updating the Application](#updating-the-application)
- [Uninstallation](#uninstallation)
- [Known Limitations](#known-limitations)
- [Support & Resources](#support--resources)

---

## Introduction

### What is MiniPrem Monitor?

MiniPrem Monitor is a real-time monitoring solution designed for technical teams managing containerized workloads. It provides a unified dashboard similar to Portainer or Kubernetes Dashboard, offering:

- **Real-time Docker container monitoring** with live log streaming
- **Multi-cluster Kubernetes monitoring** (EKS, AKS, GKE)
- **System resource metrics** (CPU, memory, disk, network I/O)
- **Container lifecycle management** (start/stop controls)
- **Professional UI** with dark/light mode and responsive design

### Why Use It on macOS?

**Perfect for macOS development workflows:**

- Monitor local Docker containers alongside remote Kubernetes clusters
- Unified dashboard eliminates context switching between terminal and browser
- No installation required beyond Docker Desktop
- Seamless integration with macOS developer tools (kubectl, AWS CLI, Azure CLI)
- Lightweight footprint (runs as single Docker container)

### Key Features on macOS

✅ **Fully Functional:**
- Docker container listing and monitoring
- Real-time log streaming via WebSocket
- System metrics dashboard (CPU, RAM, disk, network)
- Container start/stop controls
- Multi-cluster Kubernetes support (with proper configuration)

⚠️ **Requires Configuration:**
- AWS EKS monitoring (requires AWS SSO login)
- Azure AKS monitoring (requires Azure CLI authentication)
- GCP GKE monitoring (requires gcloud authentication - coming soon)

❌ **Not Available on macOS:**
- GPU-accelerated services (Renny, vLLM) - requires Linux + NVIDIA GPU
- Docker host network mode - macOS limitation

---

## Prerequisites

### Required Software

#### 1. Docker Desktop for Mac

**Minimum Version:** Docker Desktop 4.25.0 or later

**Download:** https://www.docker.com/products/docker-desktop

**Installation:**
```bash
# Verify Docker Desktop is installed and running
docker --version
# Expected output: Docker version 24.0.7 or later

# Test Docker Engine
docker ps
# Should list running containers (may be empty)
```

**Important Docker Desktop Settings:**

1. Open Docker Desktop → Settings (⚙️ icon)
2. **Resources** tab:
   - **CPUs:** 4+ recommended (minimum 2)
   - **Memory:** 8GB recommended (minimum 4GB)
   - **Disk:** 20GB free space minimum
3. **General** tab:
   - ✅ Enable "Use Virtualization framework"
   - ✅ Enable "Use containerd for pulling and storing images"

#### 2. macOS Version

**Minimum:** macOS Monterey 12.0 or later
**Recommended:** macOS Sonoma 14.0+
**Tested On:** macOS Sonoma 14.5, macOS Sequoia 15.0

#### 3. Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **RAM** | 8 GB | 16 GB+ |
| **Disk Space** | 10 GB free | 20 GB+ free |
| **CPU** | Intel/Apple Silicon (M1/M2/M3) | Apple Silicon M2+ |
| **Network** | Stable internet (for Kubernetes) | High-speed (for log streaming) |

### Optional Software (for Kubernetes Monitoring)

#### kubectl (Kubernetes CLI)

**Installation via Homebrew:**
```bash
brew install kubectl

# Verify installation
kubectl version --client
# Expected: Client Version: v1.28.0 or later
```

**Manual Installation:**
```bash
# Intel Mac (x86_64)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"

# Apple Silicon (arm64)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/arm64/kubectl"

# Install
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl
```

#### AWS CLI v2 (for EKS Monitoring)

**Installation:**
```bash
# Download AWS CLI installer
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"

# Install
sudo installer -pkg AWSCLIV2.pkg -target /

# Verify
aws --version
# Expected: aws-cli/2.31.9 or later
```

**Configure AWS SSO:**
```bash
# Login to AWS SSO
aws sso login --profile uneeq-admin

# Update kubeconfig for EKS access
aws eks update-kubeconfig --region us-east-1 --name your-cluster-name --profile uneeq-admin
```

#### Azure CLI (for AKS Monitoring)

**Installation via Homebrew:**
```bash
brew install azure-cli

# Verify
az --version
# Expected: azure-cli 2.50.0 or later
```

**Login to Azure:**
```bash
az login

# Get AKS credentials
az aks get-credentials --resource-group your-rg --name your-cluster-name
```

#### Google Cloud SDK (for GKE Monitoring - Coming Soon)

**Installation via Homebrew:**
```bash
brew install --cask google-cloud-sdk

# Initialize gcloud
gcloud init

# Authenticate
gcloud auth login
```

---

## Quick Start

**5-Minute Deployment** (assuming Docker Desktop is already running)

```bash
# 1. Clone repository (if not already cloned)
git clone https://github.com/your-org/miniprem-2025.git
cd miniprem-2025

# 2. Build the container (first-time only, ~5-10 minutes)
cd docker
docker compose -f docker-compose.monitor.yml build --no-cache --pull miniprem-monitor

# 3. Start the monitor
docker compose -f docker-compose.monitor.yml up -d

# 4. Verify deployment
docker ps | grep miniprem-monitor
# Should show: miniprem-monitor container with status "Up"

# 5. Access the dashboard
open http://localhost:3001
```

**Expected Results:**
- ✅ Container builds successfully (~2.88 GB image)
- ✅ Container starts and shows "healthy" status
- ✅ Dashboard accessible at http://localhost:3001
- ✅ Docker containers visible in dashboard
- ✅ System metrics displayed

**Total Time:** ~5-10 minutes (depending on internet speed)

---

## Step-by-Step Installation

### Step 1: Verify Docker Desktop is Running

Before starting, ensure Docker Desktop is running:

```bash
# Check Docker status
docker info

# Expected output should include:
# Server Version: 24.0.7 or later
# Operating System: Docker Desktop
# OSType: linux
# Architecture: aarch64 (Apple Silicon) or x86_64 (Intel)
```

**If Docker is not running:**
1. Open **Docker Desktop** from Applications
2. Wait for the Docker icon in menu bar to show "Docker Desktop is running"
3. Re-run `docker info` to verify

### Step 2: Clone the Repository

```bash
# Navigate to your projects directory
cd ~/projects  # or your preferred location

# Clone repository
git clone https://github.com/your-org/miniprem-2025.git
cd miniprem-2025

# Verify repository structure
ls -la docker/docker-compose.monitor.yml
# Should show the compose file exists
```

### Step 3: Configure Environment (Optional)

**For Kubernetes Monitoring:**

If you want to monitor Kubernetes clusters, ensure your kubeconfig is set up:

```bash
# Verify kubectl configuration exists
ls -la ~/.kube/config
# Should show your kubeconfig file

# Test kubectl access
kubectl config get-contexts
# Should list available clusters

# Switch to desired cluster context
kubectl config use-context your-cluster-name

# Verify connectivity
kubectl cluster-info
```

**For AWS EKS Monitoring:**

```bash
# Login to AWS SSO (required before starting container)
aws sso login --profile uneeq-admin

# Update kubeconfig with EKS cluster credentials
aws eks update-kubeconfig \
  --region us-east-1 \
  --name your-eks-cluster \
  --profile uneeq-admin

# Verify EKS access
kubectl get nodes
```

**For Azure AKS Monitoring:**

```bash
# Login to Azure
az login

# Get AKS credentials
az aks get-credentials \
  --resource-group your-resource-group \
  --name your-aks-cluster

# Verify AKS access
kubectl get nodes
```

### Step 4: Build the Container

**Important:** Always use `--no-cache --pull` for clean builds.

```bash
# Navigate to docker directory
cd /path/to/miniprem-2025/docker

# Build the monitor container
docker compose -f docker-compose.monitor.yml build --no-cache --pull miniprem-monitor
```

**Build Process:**
1. Downloads base images (Python 3.11, Node.js 18)
2. Installs system dependencies (curl, wget, etc.)
3. Installs Docker CLI (v24.0.7)
4. Installs kubectl (v1.28.0)
5. Installs AWS CLI v2
6. Builds Next.js frontend
7. Installs Python backend dependencies
8. Configures supervisord process manager

**Build Time:**
- **First build:** 5-10 minutes (downloads all dependencies)
- **Subsequent builds:** 3-5 minutes (uses Docker layer caching)

**Expected Output:**
```
[+] Building 302.5s (34/34) FINISHED
 => [frontend-builder 1/6] FROM docker.io/library/node:18-alpine
 => [stage-2 1/15] FROM docker.io/library/python:3.11-slim
 => [stage-2 15/15] COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
 => => exporting to image
 => => naming to docker.io/library/miniprem-monitor:latest
```

**Verify Build:**
```bash
# Check image size
docker images | grep miniprem-monitor
# Expected: ~2.88 GB

# Inspect image
docker inspect miniprem-monitor:latest | grep Architecture
# Expected: arm64 (Apple Silicon) or amd64 (Intel)
```

### Step 5: Deploy the Container

```bash
# Start container in detached mode
docker compose -f docker-compose.monitor.yml up -d

# Alternative: Start with logs visible (useful for troubleshooting)
docker compose -f docker-compose.monitor.yml up
```

**Startup Process:**
1. Container initializes (5-10 seconds)
2. Supervisord starts backend (FastAPI on port 8000)
3. Supervisord starts frontend (Next.js on port 3001)
4. Health check endpoint becomes available
5. Container status changes to "healthy"

**Monitor Startup:**
```bash
# Follow container logs
docker compose -f docker-compose.monitor.yml logs -f miniprem-monitor

# Expected log output:
# [INFO] Starting supervisord...
# [INFO] FastAPI backend started on port 8000
# [INFO] Next.js frontend started on port 3001
# [INFO] MiniPrem Monitor ready
```

### Step 6: Verify Deployment

**Check Container Status:**
```bash
# List running containers
docker ps | grep miniprem-monitor

# Expected output:
# CONTAINER ID   IMAGE              STATUS          PORTS
# abc123def456   miniprem-monitor   Up 30 seconds   0.0.0.0:3001->3001/tcp
```

**Check Container Health:**
```bash
# Inspect health status
docker inspect miniprem-monitor | grep -A 10 Health

# Expected: "Status": "healthy"
```

**Test Backend API:**
```bash
# Health check endpoint
curl http://localhost:8000/health

# Expected response:
# {"status":"healthy","timestamp":"2025-01-20T10:30:00Z"}

# Docker containers endpoint
curl http://localhost:8000/api/docker/containers

# Expected: JSON array of Docker containers
```

**Test Frontend:**
```bash
# Access frontend (opens in default browser)
open http://localhost:3001

# Or use curl to verify
curl -I http://localhost:3001

# Expected: HTTP/1.1 200 OK
```

---

## What Works on macOS

### ✅ Fully Functional Features

#### 1. Docker Container Monitoring

**Status:** **Production Ready**

**Features:**
- Real-time container listing (all Docker containers on host)
- Container status indicators (green=running, gray=stopped)
- Live container counts (All/Running/Stopped tabs)
- System resource usage per container (CPU, memory, network I/O)
- Log streaming with syntax highlighting (ERROR, WARN, INFO, DEBUG)
- Container lifecycle management (Start/Stop buttons)

**How It Works:**
- MiniPrem Monitor accesses Docker via mounted socket (`/var/run/docker.sock`)
- Uses Docker CLI (v24.0.7 static binary) for cross-platform compatibility
- WebSocket connection provides real-time updates (no polling)

**Test Docker Monitoring:**
```bash
# Start a test container
docker run -d --name test-nginx nginx:alpine

# View in MiniPrem Monitor
open http://localhost:3001
# Should show "test-nginx" container in dashboard

# Stop test container from dashboard
# Click "Stop" button next to test-nginx

# Verify from terminal
docker ps -a | grep test-nginx
# Should show "Exited" status

# Cleanup
docker rm test-nginx
```

#### 2. System Metrics Dashboard

**Status:** **Production Ready**

**Metrics Displayed:**
- **CPU Usage:** Overall system CPU utilization (%)
- **Memory Usage:** Total/Used/Available RAM (GB)
- **Disk I/O:** Read/Write throughput (MB/s)
- **Network I/O:** Incoming/Outgoing traffic (MB/s)

**Update Frequency:** Real-time (1-second intervals via WebSocket)

**Test System Metrics:**
```bash
# Generate CPU load
yes > /dev/null &
PID=$!

# Open dashboard and observe CPU spike
open http://localhost:3001

# Stop CPU load
kill $PID
```

#### 3. Real-Time WebSocket Updates

**Status:** **Production Ready**

**Features:**
- Automatic reconnection on network interruption
- Connection status indicator (green=connected, red=disconnected)
- Zero-latency updates (no page refresh required)
- Efficient binary protocol (minimal bandwidth)

**Test WebSocket:**
```bash
# Open browser DevTools → Network tab → WS filter
open http://localhost:3001

# Expected: WebSocket connection to ws://localhost:8000/ws
# Status: 101 Switching Protocols

# Start/stop containers and observe instant updates
docker run -d --name test-container alpine sleep 3600
# Dashboard updates immediately without refresh
```

#### 4. Container Lifecycle Management

**Status:** **Production Ready**

**Operations:**
- **Start Container:** Click green "Start" button
- **Stop Container:** Click red "Stop" button
- **View Logs:** Click "Logs" button for live log streaming
- **Download Logs:** Export logs to `.txt` file

**Security:**
- Docker socket mounted read-only (`:ro`)
- Command whitelisting (only safe commands allowed)
- Input validation (prevents injection attacks)

#### 5. Filter Tabs & Search

**Status:** **Production Ready**

**Filter Options:**
- **All Containers:** Shows all containers (running + stopped)
- **Running:** Shows only running containers
- **Stopped:** Shows only stopped containers

**Live Counts:**
- Tab badges update in real-time
- Example: "Running (5)" shows 5 running containers

**Search:**
- Filter containers by name (case-insensitive)
- Instant results as you type

### ⚠️ Requires Configuration

#### 1. Kubernetes Cluster Monitoring

**Status:** **Functional with Setup**

**Requirements:**
1. kubectl installed and configured
2. Valid kubeconfig at `~/.kube/config`
3. Active cluster context selected
4. Network access to cluster API server

**Setup Steps:**

```bash
# 1. Verify kubectl configuration
kubectl config get-contexts
kubectl config use-context your-cluster-name

# 2. Test cluster connectivity
kubectl cluster-info
kubectl get nodes

# 3. Restart monitor container to pick up kubeconfig
cd /path/to/miniprem-2025/docker
docker compose -f docker-compose.monitor.yml restart miniprem-monitor

# 4. Verify Kubernetes monitoring in dashboard
open http://localhost:3001
# Navigate to "Kubernetes" tab → Should show cluster nodes/pods
```

**Supported Kubernetes Platforms:**
- AWS EKS (with AWS SSO authentication)
- Azure AKS (with Azure CLI authentication)
- GCP GKE (coming soon - requires gcloud auth)
- Self-managed clusters (with direct kubeconfig access)

**Test Kubernetes Monitoring:**
```bash
# Create test pod
kubectl run test-pod --image=nginx --restart=Never

# View in dashboard
open http://localhost:3001
# Navigate to Kubernetes → Pods → Should show "test-pod"

# Cleanup
kubectl delete pod test-pod
```

#### 2. AWS EKS Monitoring

**Status:** **Functional with AWS SSO**

**Requirements:**
- AWS CLI v2 installed
- AWS SSO configured (`~/.aws/config`)
- Active SSO session (requires periodic re-authentication)
- EKS cluster in same AWS account

**Setup Steps:**

```bash
# 1. Configure AWS SSO profile
cat > ~/.aws/config <<EOF
[profile uneeq-admin]
sso_start_url = https://your-org.awsapps.com/start
sso_region = us-east-1
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = us-east-1
output = json
EOF

# 2. Login to AWS SSO (required before starting monitor)
aws sso login --profile uneeq-admin

# 3. Update kubeconfig with EKS credentials
aws eks update-kubeconfig \
  --region us-east-1 \
  --name your-eks-cluster \
  --profile uneeq-admin

# 4. Verify EKS access
kubectl get nodes

# 5. Start/restart monitor
cd /path/to/miniprem-2025/docker
docker compose -f docker-compose.monitor.yml up -d

# 6. Check EKS cluster detection
docker exec miniprem-monitor kubectl config get-contexts
# Should list EKS cluster contexts
```

**Important Notes:**
- **AWS SSO sessions expire** (typically after 8-12 hours)
- **Re-authentication required:** Run `aws sso login` when session expires
- **Monitor container does NOT auto-refresh credentials** - restart required after re-login
- **AWS credentials mounted read-only:** `~/.aws:/root/.aws:ro`

**Troubleshooting EKS Authentication:**

```bash
# Check if SSO session is active
aws sts get-caller-identity --profile uneeq-admin

# If expired, re-login
aws sso login --profile uneeq-admin

# Restart monitor to pick up new credentials
docker compose -f docker-compose.monitor.yml restart miniprem-monitor

# Verify EKS access from inside container
docker exec miniprem-monitor kubectl get nodes
```

#### 3. Azure AKS Monitoring

**Status:** **Functional with Azure CLI**

**Requirements:**
- Azure CLI installed (`az`)
- Active Azure login session
- AKS cluster in same subscription
- Network access to AKS API server

**Setup Steps:**

```bash
# 1. Login to Azure
az login
# Opens browser for interactive authentication

# 2. Set subscription (if you have multiple)
az account set --subscription "your-subscription-name"

# 3. Get AKS credentials
az aks get-credentials \
  --resource-group your-resource-group \
  --name your-aks-cluster

# 4. Verify AKS access
kubectl get nodes

# 5. Start/restart monitor
cd /path/to/miniprem-2025/docker
docker compose -f docker-compose.monitor.yml up -d

# 6. Check AKS cluster detection
docker exec miniprem-monitor kubectl config get-contexts
# Should list AKS cluster contexts
```

**Important Notes:**
- **Azure CLI tokens expire** (typically after 1-2 hours)
- **Re-authentication required:** Run `az login` when token expires
- **Azure credentials mounted read-only:** `~/.azure:/root/.azure:ro` (if needed in future)

**Troubleshooting AKS Authentication:**

```bash
# Check Azure login status
az account show

# If expired, re-login
az login

# Refresh AKS credentials
az aks get-credentials \
  --resource-group your-resource-group \
  --name your-aks-cluster \
  --overwrite-existing

# Restart monitor
docker compose -f docker-compose.monitor.yml restart miniprem-monitor

# Verify AKS access from inside container
docker exec miniprem-monitor kubectl get nodes
```

### ❌ Not Available on macOS

#### 1. GPU-Accelerated Services

**Why Not Available:**
- macOS does not support NVIDIA CUDA
- Docker Desktop for Mac does not pass through GPU devices
- Renny (digital human renderer) requires NVIDIA GPU with Vulkan
- vLLM (LLM inference) requires CUDA 12.4+

**Affected Services:**
- Renny digital human renderer
- vLLM inference server
- GPU-accelerated speech processing

**Alternative:**
- Use MiniPrem Monitor to monitor remote Linux clusters with GPU nodes
- Deploy full MiniPrem stack on Ubuntu 22.04 with NVIDIA GPU

#### 2. Docker Host Network Mode

**Why Not Available:**
- macOS Docker Desktop runs Linux VM (virtualization layer)
- Host networking only works on native Linux
- Docker Compose `network_mode: host` is ignored on macOS

**Impact:**
- MiniPrem Monitor uses **bridge mode** on macOS
- Port mapping required: `0.0.0.0:3001->3001/tcp`
- Slightly higher network latency compared to host mode on Linux

**Current Configuration:**
```yaml
# docker-compose.monitor.yml
services:
  miniprem-monitor:
    ports:
      - "3001:3001"  # Frontend access
    # network_mode: host  # Not supported on macOS
```

**Workaround:**
- Bridge mode is fully functional on macOS
- No action required (automatically configured)

---

## Kubernetes Integration

### Overview

MiniPrem Monitor can monitor multiple Kubernetes clusters simultaneously by leveraging your local `~/.kube/config` file. The container mounts your kubeconfig read-only and uses `kubectl` CLI for cluster operations.

### Supported Cloud Providers

| Provider | Status | Authentication Method | Notes |
|----------|--------|----------------------|-------|
| **AWS EKS** | ✅ Production Ready | AWS SSO + AWS CLI v2 | Requires active SSO session |
| **Azure AKS** | ✅ Production Ready | Azure CLI + `az login` | Requires active Azure token |
| **GCP GKE** | ⏳ Coming Soon | gcloud CLI + `gcloud auth` | In development |
| **Self-Managed** | ✅ Production Ready | Direct kubeconfig | Works with any standard kubeconfig |

### AWS EKS Setup (Detailed)

#### Prerequisites

1. **AWS CLI v2 installed** (see [Prerequisites](#prerequisites) section)
2. **AWS SSO configured** in `~/.aws/config`
3. **IAM permissions:** `eks:DescribeCluster`, `eks:ListClusters`
4. **Network access** to EKS API server

#### Step-by-Step EKS Configuration

**1. Configure AWS SSO Profile**

Create or edit `~/.aws/config`:

```bash
[profile uneeq-admin]
sso_start_url = https://your-org.awsapps.com/start
sso_region = us-east-1
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = us-east-1
output = json
```

**2. Login to AWS SSO**

```bash
# Initiate SSO login (opens browser)
aws sso login --profile uneeq-admin

# Verify authentication
aws sts get-caller-identity --profile uneeq-admin

# Expected output:
# {
#     "UserId": "AIDAXXXXXXXXXXXXX",
#     "Account": "123456789012",
#     "Arn": "arn:aws:sts::123456789012:assumed-role/AdministratorAccess/user@example.com"
# }
```

**3. Update kubeconfig with EKS Credentials**

```bash
# List available EKS clusters
aws eks list-clusters --region us-east-1 --profile uneeq-admin

# Update kubeconfig for your cluster
aws eks update-kubeconfig \
  --region us-east-1 \
  --name your-eks-cluster-name \
  --profile uneeq-admin

# Verify kubeconfig updated
kubectl config get-contexts | grep your-eks-cluster

# Test cluster access
kubectl get nodes
```

**4. Start MiniPrem Monitor**

```bash
cd /path/to/miniprem-2025/docker

# Start monitor (mounts ~/.kube and ~/.aws)
docker compose -f docker-compose.monitor.yml up -d

# Verify EKS cluster detection
docker exec miniprem-monitor kubectl config get-contexts

# Test EKS access from container
docker exec miniprem-monitor kubectl get nodes
```

**5. Access Dashboard**

```bash
open http://localhost:3001

# Navigate to "Kubernetes" tab
# Select EKS cluster from dropdown
# View nodes, pods, namespaces
```

#### EKS Authentication Lifecycle

**Session Duration:**
- AWS SSO sessions typically last **8-12 hours**
- After expiration, you'll see authentication errors in logs

**Re-Authentication Process:**

```bash
# 1. Check if session is expired
aws sts get-caller-identity --profile uneeq-admin
# Error: "Token has expired"

# 2. Re-login to AWS SSO
aws sso login --profile uneeq-admin

# 3. Restart monitor container
docker compose -f docker-compose.monitor.yml restart miniprem-monitor

# 4. Verify EKS access restored
docker exec miniprem-monitor kubectl get nodes
```

**Automation Tip:**

Add alias to `~/.zshrc` or `~/.bashrc`:

```bash
alias refresh-eks='aws sso login --profile uneeq-admin && docker compose -f /path/to/miniprem-2025/docker/docker-compose.monitor.yml restart miniprem-monitor'
```

Usage:
```bash
refresh-eks  # One command to refresh credentials and restart monitor
```

#### Monitoring Multiple EKS Clusters

```bash
# Add multiple EKS clusters to kubeconfig
aws eks update-kubeconfig --region us-east-1 --name cluster-1 --profile uneeq-admin
aws eks update-kubeconfig --region us-west-2 --name cluster-2 --profile uneeq-admin

# List all contexts
kubectl config get-contexts

# Restart monitor to detect new clusters
docker compose -f docker-compose.monitor.yml restart miniprem-monitor

# Switch between clusters in dashboard
# Dashboard → Kubernetes → Cluster dropdown → Select cluster-1 or cluster-2
```

### Azure AKS Setup (Detailed)

#### Prerequisites

1. **Azure CLI installed** (see [Prerequisites](#prerequisites) section)
2. **Azure subscription** with AKS cluster
3. **IAM permissions:** `Azure Kubernetes Service Cluster User Role`
4. **Network access** to AKS API server

#### Step-by-Step AKS Configuration

**1. Login to Azure**

```bash
# Interactive browser-based login
az login

# If you have multiple subscriptions, list them
az account list --output table

# Set active subscription
az account set --subscription "Your Subscription Name"

# Verify active subscription
az account show
```

**2. List AKS Clusters**

```bash
# List all AKS clusters in subscription
az aks list --output table

# Get specific cluster details
az aks show \
  --resource-group your-resource-group \
  --name your-aks-cluster
```

**3. Get AKS Credentials**

```bash
# Update kubeconfig with AKS credentials
az aks get-credentials \
  --resource-group your-resource-group \
  --name your-aks-cluster

# Verify kubeconfig updated
kubectl config get-contexts | grep your-aks-cluster

# Test cluster access
kubectl get nodes
```

**4. Start MiniPrem Monitor**

```bash
cd /path/to/miniprem-2025/docker

# Start monitor (mounts ~/.kube)
docker compose -f docker-compose.monitor.yml up -d

# Verify AKS cluster detection
docker exec miniprem-monitor kubectl config get-contexts

# Test AKS access from container
docker exec miniprem-monitor kubectl get nodes
```

**5. Access Dashboard**

```bash
open http://localhost:3001

# Navigate to "Kubernetes" tab
# Select AKS cluster from dropdown
# View nodes, pods, namespaces
```

#### AKS Authentication Lifecycle

**Session Duration:**
- Azure CLI tokens typically last **1-2 hours**
- After expiration, you'll see authentication errors in logs

**Re-Authentication Process:**

```bash
# 1. Check if session is expired
az account show
# Error: "Please run 'az login' to setup account."

# 2. Re-login to Azure
az login

# 3. Refresh AKS credentials
az aks get-credentials \
  --resource-group your-resource-group \
  --name your-aks-cluster \
  --overwrite-existing

# 4. Restart monitor container
docker compose -f docker-compose.monitor.yml restart miniprem-monitor

# 5. Verify AKS access restored
docker exec miniprem-monitor kubectl get nodes
```

#### Monitoring Multiple AKS Clusters

```bash
# Add multiple AKS clusters to kubeconfig
az aks get-credentials --resource-group rg1 --name cluster-1
az aks get-credentials --resource-group rg2 --name cluster-2

# List all contexts
kubectl config get-contexts

# Restart monitor to detect new clusters
docker compose -f docker-compose.monitor.yml restart miniprem-monitor

# Switch between clusters in dashboard
# Dashboard → Kubernetes → Cluster dropdown → Select cluster-1 or cluster-2
```

### GCP GKE Setup (Coming Soon)

**Status:** ⏳ In Development

**Planned Features:**
- gcloud CLI integration
- `gcloud auth login` authentication
- Multi-project support
- Regional/zonal cluster detection

**Current Workaround:**
- Export kubeconfig manually from GKE
- Use self-managed cluster configuration (see below)

### Self-Managed Kubernetes Setup

For non-cloud Kubernetes clusters (Minikube, k3s, Rancher, etc.):

```bash
# Ensure kubeconfig is properly configured
export KUBECONFIG=~/.kube/config

# Test cluster access
kubectl cluster-info
kubectl get nodes

# Start MiniPrem Monitor
cd /path/to/miniprem-2025/docker
docker compose -f docker-compose.monitor.yml up -d

# Verify cluster detection
docker exec miniprem-monitor kubectl config get-contexts

# Access dashboard
open http://localhost:3001
```

**Supported Self-Managed Platforms:**
- Minikube
- k3s / k3d
- MicroK8s
- Rancher
- OpenShift (with kubeconfig export)
- Kind (Kubernetes in Docker)

---

## Accessing the Application

### Dashboard URL

**Primary Access:** http://localhost:3001

**Alternative Access (if port conflict):**
- Edit `docker-compose.monitor.yml` → Change `3001:3001` to `3005:3001`
- Restart container: `docker compose -f docker-compose.monitor.yml restart`
- Access: http://localhost:3005

### First Load Experience

When you first access http://localhost:3001, you'll see:

#### 1. Dashboard Overview Page

**Top Navigation Bar:**
- **MiniPrem Monitor** logo (left)
- **Dark/Light Mode Toggle** (top right)
- **Connection Status Indicator** (top right)
  - 🟢 Green dot = WebSocket connected
  - 🔴 Red dot = WebSocket disconnected

**Main Content Area:**
- **System Metrics Cards** (top row):
  - CPU Usage (%)
  - Memory Usage (GB)
  - Disk I/O (MB/s)
  - Network I/O (MB/s)
- **Docker Containers Table** (main area):
  - Container Name
  - Image
  - Status (🟢 Running / ⚫ Stopped)
  - CPU Usage (%)
  - Memory Usage (MB)
  - Actions (Start/Stop/Logs buttons)

**Filter Tabs:**
- **All Containers (N)** - Shows all containers
- **Running (N)** - Shows only running containers
- **Stopped (N)** - Shows only stopped containers

**Search Bar:**
- Filter containers by name in real-time

#### 2. Kubernetes Tab (if configured)

**Navigation:** Click "Kubernetes" in top navigation

**Content:**
- **Cluster Selector** (dropdown) - Switch between configured clusters
- **Namespace Selector** (dropdown) - Filter pods by namespace
- **Pods Table**:
  - Pod Name
  - Namespace
  - Status (Running/Pending/Failed)
  - Node Name
  - Restart Count
  - Age
  - Actions (Logs/Describe buttons)
- **Nodes Table**:
  - Node Name
  - Status (Ready/NotReady)
  - Roles (control-plane/worker)
  - Version
  - CPU/Memory Allocatable

#### 3. What You Should See

**On First Load (Successful):**

✅ **Docker Containers:**
- At minimum: `miniprem-monitor` container itself
- Any other running Docker containers on your Mac
- Example: If Docker Desktop Kubernetes is enabled, you'll see `k8s_*` containers

✅ **System Metrics:**
- CPU: Current system CPU usage (e.g., 15%)
- Memory: Used/Total RAM (e.g., 8.2 GB / 16 GB)
- Disk I/O: Read/write throughput
- Network I/O: Incoming/outgoing traffic

✅ **Connection Status:**
- Green dot with "Connected" tooltip
- WebSocket connection established to backend

**Troubleshooting First Load:**

❌ **No Containers Showing:**
- Check Docker socket access: `docker exec miniprem-monitor docker ps`
- Check backend logs: `docker logs miniprem-monitor | grep ERROR`

❌ **Red Dot (Disconnected):**
- Check backend is running: `curl http://localhost:8000/health`
- Check WebSocket in browser DevTools → Network → WS tab
- See [Troubleshooting - WebSocket Disconnected](#troubleshooting) section

❌ **No Kubernetes Tab:**
- Kubernetes monitoring requires kubeconfig
- If you haven't configured kubectl, this is expected
- See [Kubernetes Integration](#kubernetes-integration) section

### Navigating the Interface

#### Docker Container Management

**View Container Logs:**
1. Locate container in table
2. Click **"Logs"** button
3. Log viewer opens in modal
4. **Features:**
   - Syntax highlighting (ERROR=red, WARN=orange, INFO=blue)
   - Auto-scroll (toggle on/off)
   - Download logs to `.txt` file
   - Close modal to return to dashboard

**Start Container:**
1. Locate stopped container (⚫ gray status)
2. Click **"Start"** button
3. Container status updates to 🟢 green instantly
4. Confirm in terminal: `docker ps | grep container-name`

**Stop Container:**
1. Locate running container (🟢 green status)
2. Click **"Stop"** button
3. Confirmation dialog appears: "Are you sure?"
4. Click "Yes" to confirm
5. Container status updates to ⚫ gray instantly

**Filter Containers:**
1. Click filter tabs: **All** / **Running** / **Stopped**
2. Badge shows live count (e.g., "Running (5)")
3. Table updates instantly

**Search Containers:**
1. Type container name in search box (top right)
2. Results filter as you type (case-insensitive)
3. Clear search to show all containers

#### Kubernetes Cluster Management

**Switch Cluster:**
1. Navigate to **Kubernetes** tab
2. Click **Cluster** dropdown
3. Select cluster from list (shows context name)
4. Dashboard updates with selected cluster's resources

**Filter by Namespace:**
1. Click **Namespace** dropdown
2. Select namespace (or "All Namespaces")
3. Pods table updates to show filtered results

**View Pod Logs:**
1. Locate pod in Pods table
2. Click **"Logs"** button
3. Log viewer opens (same as Docker logs)
4. Select container if pod has multiple containers

**Describe Pod:**
1. Locate pod in Pods table
2. Click **"Describe"** button
3. YAML viewer opens showing full pod spec
4. Includes events, conditions, and resource usage

#### Dark/Light Mode

**Toggle Theme:**
1. Click **theme toggle icon** (top right navigation bar)
2. Dashboard switches instantly (no page reload)
3. Preference saved in browser localStorage
4. Persists across sessions

**Keyboard Shortcut:**
- macOS: `Cmd + Shift + L` (if implemented)

### Performance Expectations

**Load Time:**
- Initial page load: **257-430ms** (based on Playwright tests)
- Dashboard becomes interactive: **< 1 second**
- WebSocket connection established: **< 500ms**

**Update Frequency:**
- Docker container status: **Real-time** (WebSocket push)
- System metrics: **1-second intervals**
- Kubernetes resources: **5-second intervals** (configurable)

**Resource Usage:**
- Browser memory: **~150-250 MB**
- CPU usage: **< 5%** (idle), **< 15%** (active log streaming)
- Network bandwidth: **< 100 KB/s** (steady state)

---

## Troubleshooting

### Common Issues & Solutions

#### Issue 1: Docker Desktop Not Running

**Symptoms:**
- `docker ps` fails with error: "Cannot connect to the Docker daemon"
- Container fails to start

**Solution:**
```bash
# Start Docker Desktop from Applications
open /Applications/Docker.app

# Wait for Docker to fully start (~30 seconds)
# Menu bar icon should show "Docker Desktop is running"

# Verify Docker is running
docker info

# Retry deployment
cd /path/to/miniprem-2025/docker
docker compose -f docker-compose.monitor.yml up -d
```

#### Issue 2: Port 3001 Already in Use

**Symptoms:**
- Container fails to start with error: "bind: address already in use"
- `docker ps` shows container in "Exited" state

**Solution:**

**Option A: Find and Stop Conflicting Process**
```bash
# Find process using port 3001
lsof -i :3001

# Example output:
# COMMAND   PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
# node    12345  user   20u  IPv4  ...            TCP *:3001 (LISTEN)

# Kill the process
kill -9 12345  # Replace with actual PID

# Retry deployment
docker compose -f docker-compose.monitor.yml up -d
```

**Option B: Change Port Mapping**

Edit `docker-compose.monitor.yml`:
```yaml
services:
  miniprem-monitor:
    ports:
      - "3005:3001"  # Changed from 3001:3001
```

Restart:
```bash
docker compose -f docker-compose.monitor.yml down
docker compose -f docker-compose.monitor.yml up -d

# Access at new port
open http://localhost:3005
```

#### Issue 3: Container Fails to Start

**Symptoms:**
- `docker ps` shows no `miniprem-monitor` container
- `docker compose up` exits immediately with error

**Diagnosis:**
```bash
# Check container logs
docker logs miniprem-monitor

# Check compose logs
docker compose -f docker-compose.monitor.yml logs

# Check container status
docker ps -a | grep miniprem-monitor
```

**Common Causes & Solutions:**

**Cause: Image Not Built**
```bash
# Rebuild image
docker compose -f docker-compose.monitor.yml build --no-cache --pull

# Start again
docker compose -f docker-compose.monitor.yml up -d
```

**Cause: Volume Mount Permission Error**
```bash
# Check Docker socket permissions
ls -la /var/run/docker.sock

# Expected: srw-rw---- (socket file)
# If missing, Docker Desktop may not be running properly

# Restart Docker Desktop
osascript -e 'quit app "Docker"'
open /Applications/Docker.app
```

**Cause: Corrupted Container State**
```bash
# Remove container
docker rm -f miniprem-monitor

# Remove volumes (if any)
docker volume prune

# Rebuild and start
docker compose -f docker-compose.monitor.yml build --no-cache
docker compose -f docker-compose.monitor.yml up -d
```

#### Issue 4: Volume Mount Permissions

**Symptoms:**
- Container starts but shows errors: "Permission denied: /root/.kube/config"
- Kubernetes monitoring not working

**Solution:**

**Check File Permissions:**
```bash
# Verify kubeconfig is readable
ls -la ~/.kube/config

# Expected: -rw------- (read/write for owner only)
# If different, fix permissions:
chmod 600 ~/.kube/config

# Verify AWS credentials (if using EKS)
ls -la ~/.aws/config
chmod 600 ~/.aws/config
```

**Restart Container:**
```bash
docker compose -f docker-compose.monitor.yml restart miniprem-monitor

# Verify volume mounts inside container
docker exec miniprem-monitor ls -la /root/.kube/config
# Should show file exists and is readable
```

#### Issue 5: WebSocket Disconnected

**Symptoms:**
- Red dot in top right of dashboard
- Tooltip shows "Disconnected"
- Real-time updates not working
- Browser console shows WebSocket errors

**Diagnosis:**

```bash
# Check backend is running
curl http://localhost:8000/health

# Expected: {"status":"healthy",...}
# If fails: Backend is down

# Check backend logs
docker exec miniprem-monitor tail -50 /var/log/supervisor/backend.err.log

# Check frontend logs
docker exec miniprem-monitor tail -50 /var/log/supervisor/frontend.err.log
```

**Solutions:**

**Solution A: Restart Backend**
```bash
# Restart entire container
docker compose -f docker-compose.monitor.yml restart miniprem-monitor

# Wait 10 seconds for services to start
sleep 10

# Test WebSocket connection
curl -i -N \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  http://localhost:8000/ws

# Reload browser
open http://localhost:3001
```

**Solution B: Check Browser Console**

1. Open browser DevTools (Cmd+Option+I)
2. Go to **Network** tab
3. Filter: **WS** (WebSocket)
4. Look for connection to `ws://localhost:8000/ws`
5. Check status:
   - **101 Switching Protocols** = Connected ✅
   - **Failed to connect** = Backend issue ❌
   - **Connection refused** = Port blocked ❌

**Solution C: Clear Browser Cache**
```bash
# Hard refresh in browser
# Chrome: Cmd+Shift+R
# Safari: Cmd+Option+E (then Cmd+R)

# Or clear all browser data:
# Chrome → Settings → Privacy → Clear browsing data → Cached images and files
```

**Known Issue (From Testing):**
- **Status:** Backend connectivity issue noted in Playwright tests
- **Impact:** WebSocket may disconnect intermittently
- **Workaround:** Refresh browser page or restart container
- **Fix:** Under investigation - likely related to supervisord process management

#### Issue 6: Backend API Not Responding

**Symptoms:**
- Frontend loads but shows no data
- Browser console shows 502/504 errors
- `curl http://localhost:8000/health` fails

**Diagnosis:**
```bash
# Check if backend process is running
docker exec miniprem-monitor ps aux | grep python

# Expected: /usr/local/bin/python backend/run.py
# If missing: Backend process crashed

# Check backend logs
docker exec miniprem-monitor tail -100 /var/log/supervisor/backend.err.log

# Look for Python exceptions or import errors
```

**Solution:**
```bash
# Restart supervisord (restarts all processes)
docker exec miniprem-monitor supervisorctl restart all

# Wait 5 seconds
sleep 5

# Verify backend is responding
curl http://localhost:8000/health

# If still failing, rebuild container
docker compose -f docker-compose.monitor.yml down
docker compose -f docker-compose.monitor.yml build --no-cache
docker compose -f docker-compose.monitor.yml up -d
```

#### Issue 7: Kubernetes Authentication Failed

**Symptoms:**
- Dashboard shows "Authentication failed" for Kubernetes
- Container logs show: "Unauthorized" or "Forbidden"
- Kubernetes tab is empty

**Diagnosis:**
```bash
# Test kubectl from inside container
docker exec miniprem-monitor kubectl cluster-info

# Expected: Kubernetes master is running at https://...
# If error: Authentication issue

# Check kubeconfig validity
docker exec miniprem-monitor kubectl config view
```

**Solution (AWS EKS):**
```bash
# Re-login to AWS SSO
aws sso login --profile uneeq-admin

# Update kubeconfig
aws eks update-kubeconfig \
  --region us-east-1 \
  --name your-cluster \
  --profile uneeq-admin

# Restart container
docker compose -f docker-compose.monitor.yml restart miniprem-monitor

# Test again
docker exec miniprem-monitor kubectl get nodes
```

**Solution (Azure AKS):**
```bash
# Re-login to Azure
az login

# Refresh credentials
az aks get-credentials \
  --resource-group your-rg \
  --name your-cluster \
  --overwrite-existing

# Restart container
docker compose -f docker-compose.monitor.yml restart miniprem-monitor

# Test again
docker exec miniprem-monitor kubectl get nodes
```

#### Issue 8: High Memory Usage

**Symptoms:**
- Docker Desktop shows high memory consumption
- Mac becomes slow when monitor is running
- Docker Desktop warning: "Docker is using XGB of memory"

**Solution:**

**Adjust Docker Desktop Resource Limits:**
1. Open Docker Desktop → Settings
2. Go to **Resources** tab
3. Adjust **Memory** slider:
   - **Recommended:** 8 GB (if you have 16GB+ Mac)
   - **Minimum:** 4 GB
4. Click **Apply & Restart**

**Optimize Monitor Container:**
```bash
# Stop container
docker compose -f docker-compose.monitor.yml down

# Prune Docker system (removes unused images/volumes)
docker system prune -a

# Restart with resource limits
# Edit docker-compose.monitor.yml, add:
services:
  miniprem-monitor:
    deploy:
      resources:
        limits:
          memory: 2G  # Limit container to 2GB
        reservations:
          memory: 1G

# Restart
docker compose -f docker-compose.monitor.yml up -d
```

#### Issue 9: Build Fails with Network Timeout

**Symptoms:**
- `docker compose build` fails with "timeout" error
- Error downloading Node.js modules or Python packages

**Solution:**
```bash
# Check internet connectivity
ping -c 3 google.com

# Retry build with increased timeout
DOCKER_BUILDKIT=1 docker compose -f docker-compose.monitor.yml build \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  --progress=plain \
  --no-cache \
  miniprem-monitor

# If still failing, try without BuildKit
DOCKER_BUILDKIT=0 docker compose -f docker-compose.monitor.yml build \
  --no-cache \
  miniprem-monitor
```

#### Issue 10: Container Exits Immediately After Start

**Symptoms:**
- `docker compose up -d` succeeds
- `docker ps` shows no `miniprem-monitor` container
- `docker ps -a` shows container with "Exited (1)" status

**Diagnosis:**
```bash
# Check container exit logs
docker logs miniprem-monitor

# Common exit reasons:
# - Entrypoint script error
# - Missing environment variable
# - Port already in use
# - Volume mount failure
```

**Solution:**
```bash
# Run container interactively to see errors
docker run -it --rm \
  -p 3001:3001 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v ~/.kube:/root/.kube:ro \
  miniprem-monitor:latest

# Look for errors in output

# If entrypoint script issue:
docker run -it --rm --entrypoint /bin/bash miniprem-monitor:latest
# Then manually run commands to debug
```

### Debug Mode

Enable verbose logging for troubleshooting:

**Edit docker-compose.monitor.yml:**
```yaml
services:
  miniprem-monitor:
    environment:
      - LOG_LEVEL=debug  # Changed from 'info'
```

**Restart container:**
```bash
docker compose -f docker-compose.monitor.yml down
docker compose -f docker-compose.monitor.yml up -d

# View detailed logs
docker compose -f docker-compose.monitor.yml logs -f
```

**View specific log files:**
```bash
# Backend errors
docker exec miniprem-monitor tail -f /var/log/supervisor/backend.err.log

# Backend stdout
docker exec miniprem-monitor tail -f /var/log/supervisor/backend.out.log

# Frontend errors
docker exec miniprem-monitor tail -f /var/log/supervisor/frontend.err.log

# Supervisord master log
docker exec miniprem-monitor tail -f /var/log/supervisor/supervisord.log
```

---

## macOS-Specific Considerations

### Docker Desktop Settings

**Optimal Configuration for MiniPrem Monitor:**

1. Open Docker Desktop → **Settings** (⚙️)
2. **General** Tab:
   - ✅ Enable "Use Virtualization framework" (required for Apple Silicon)
   - ✅ Enable "Use containerd for pulling and storing images" (faster builds)
   - ✅ Enable "Use Docker Compose V2" (modern compose)
3. **Resources** Tab:
   - **CPUs:** 4 cores (recommended for monitoring multiple clusters)
   - **Memory:** 8 GB (minimum 4GB)
   - **Swap:** 2 GB (default)
   - **Disk image size:** 100 GB+ (or as needed)
4. **Docker Engine** Tab:
   - Keep default settings (no changes needed)
5. **Kubernetes** Tab (optional):
   - If you want to monitor local Kubernetes:
     - ✅ Enable "Enable Kubernetes"
     - Click "Apply & Restart"

**Performance Tips:**
- Allocate **50%** of your Mac's total RAM to Docker Desktop
- Example: 16GB Mac → 8GB for Docker
- Monitor resource usage: Docker Desktop → 📊 Dashboard

### Volume Mount Paths

**macOS Volume Mount Differences:**

| Volume | macOS Path | Linux Path | Notes |
|--------|-----------|------------|-------|
| Docker Socket | `/var/run/docker.sock` | `/var/run/docker.sock` | ✅ Same path |
| Kubeconfig | `~/.kube` | `~/.kube` | ✅ Same path |
| AWS Credentials | `~/.aws` | `~/.aws` | ✅ Same path |
| Azure Credentials | `~/.azure` | `~/.azure` | ✅ Same path (if needed) |

**Important Notes:**
- **Tilde expansion (`~`) works** in Docker Compose on macOS
- **Absolute paths recommended** for consistency:
  ```yaml
  volumes:
    - /Users/your-username/.kube:/root/.kube:ro  # Absolute path
    # vs
    - ~/.kube:/root/.kube:ro  # Relative path (also works)
  ```
- **Symlinks may not work** across Docker VM boundary
- **File permissions preserved** on mount (read-only `:ro` flag respected)

**Troubleshooting Volume Mounts:**
```bash
# Verify host file exists
ls -la ~/.kube/config

# Verify file is accessible inside container
docker exec miniprem-monitor ls -la /root/.kube/config

# Check mount points
docker inspect miniprem-monitor | grep -A 10 Mounts
```

### Bridge Networking vs Host Networking

**Why Bridge Mode on macOS:**

| Feature | Linux Host Mode | macOS Bridge Mode |
|---------|----------------|-------------------|
| **Network Mode** | `network_mode: host` | `ports: - "3001:3001"` |
| **Performance** | Fastest (no NAT) | Slightly slower (NAT overhead) |
| **Port Mapping** | Direct to host ports | Requires explicit mapping |
| **Service Discovery** | Direct localhost access | Via port forwarding |
| **macOS Support** | ❌ Not supported | ✅ Fully supported |

**Current Configuration (docker-compose.monitor.yml):**
```yaml
services:
  miniprem-monitor:
    # network_mode: host  # Not supported on macOS
    ports:
      - "3001:3001"  # Frontend (external access)
      # Backend port 8000 not exposed (internal only)
```

**Why Backend Port 8000 Not Exposed:**
- Frontend runs on port **3001** (externally accessible)
- Backend runs on port **8000** (internal to container)
- Frontend proxies API requests to backend internally
- **Security benefit:** Backend not exposed to host network
- **Simplicity:** Single port to remember (3001)

**Port Mapping Visualization:**
```
Browser (http://localhost:3001)
        ↓
    Host Port 3001
        ↓
Docker Bridge Network (NAT)
        ↓
Container Port 3001 (Next.js Frontend)
        ↓ (Internal HTTP proxy)
Container Port 8000 (FastAPI Backend)
```

**Performance Impact:**
- **Latency:** +1-2ms compared to host networking
- **Throughput:** Negligible difference for monitoring workload
- **CPU Overhead:** < 1% for NAT translation

**Workaround for Host-Like Networking (Advanced):**

If you need direct host network access:
```bash
# Use Docker Desktop's host.docker.internal
# This resolves to host machine's IP from inside container

# Example: Access host service from container
docker exec miniprem-monitor curl http://host.docker.internal:8080
```

### Docker Socket Access

**How Docker Socket Works on macOS:**

1. **Docker Desktop** runs Linux VM (invisible to user)
2. **Docker socket** (`/var/run/docker.sock`) is Unix domain socket
3. **Socket forwarded** from VM to macOS host at same path
4. **MiniPrem Monitor** accesses socket inside Linux container
5. **Commands executed** in Docker Desktop's Linux VM

**Volume Mount:**
```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro  # Read-only mount
```

**Security Implications:**
- **Read-only mount** prevents container from creating/deleting other containers
- **Command whitelisting** in backend prevents dangerous operations
- **No privilege escalation** with `security_opt: - no-new-privileges:true`

**What MiniPrem Monitor Can Do:**
- ✅ List Docker containers (`docker ps`)
- ✅ View container logs (`docker logs`)
- ✅ Get container stats (`docker stats`)
- ✅ Start containers (`docker start`)
- ✅ Stop containers (`docker stop`)

**What MiniPrem Monitor Cannot Do:**
- ❌ Delete containers (`docker rm`) - blocked by code
- ❌ Create containers (`docker run`) - blocked by code
- ❌ Pull images (`docker pull`) - blocked by code
- ❌ Modify Docker daemon settings

**Testing Docker Socket Access:**
```bash
# From host
docker ps

# From inside container
docker exec miniprem-monitor docker ps

# Both should show identical output
```

### File Permissions on Mounted Volumes

**Default Permissions:**

When you mount volumes from macOS to container:
- **Owner:** Files appear as `root:root` inside container
- **Permissions:** Original macOS permissions preserved
- **Read-only (`:ro`):** Enforced by Docker, prevents writes

**Example:**

**Host (macOS):**
```bash
ls -la ~/.kube/config
# -rw-------  1 youruser  staff  5678 Jan 20 10:00 /Users/youruser/.kube/config
```

**Container (Linux):**
```bash
docker exec miniprem-monitor ls -la /root/.kube/config
# -rw-------  1 root  root  5678 Jan 20 18:00 /root/.kube/config
```

**Troubleshooting Permission Denied:**

If you see "Permission denied" errors:
```bash
# Verify file is readable on host
cat ~/.kube/config  # Should display content

# Verify file is readable in container
docker exec miniprem-monitor cat /root/.kube/config  # Should display content

# If fails, check file permissions
chmod 600 ~/.kube/config  # Make file readable only by owner
```

**Special Case: AWS/Azure Credentials:**

Cloud provider CLIs create credential files with strict permissions:
```bash
# AWS credentials
chmod 600 ~/.aws/config
chmod 600 ~/.aws/credentials

# Azure credentials (created by az login, usually correct permissions)
ls -la ~/.azure
```

---

## Performance Optimization

### Docker Desktop Resource Allocation

**Balancing Performance vs Battery Life:**

| Use Case | CPUs | Memory | Performance |
|----------|------|--------|-------------|
| **Light monitoring** (1-2 clusters) | 2 cores | 4 GB | Good |
| **Standard monitoring** (3-5 clusters) | 4 cores | 8 GB | Excellent ✅ |
| **Heavy monitoring** (6+ clusters) | 6 cores | 12 GB | Maximum |

**Recommended Settings (16GB Mac):**
```
Docker Desktop → Settings → Resources:
- CPUs: 4
- Memory: 8 GB
- Swap: 2 GB
- Disk: 100 GB+
```

**Power Efficiency Tips:**
- Lower CPU allocation when on battery (2 cores)
- Pause Docker Desktop when not using containers
- Stop monitor when not actively monitoring:
  ```bash
  docker compose -f docker-compose.monitor.yml stop
  # To resume:
  docker compose -f docker-compose.monitor.yml start
  ```

### Container Resource Limits

**Apply Resource Constraints to Monitor:**

Edit `docker-compose.monitor.yml`:
```yaml
services:
  miniprem-monitor:
    deploy:
      resources:
        limits:
          cpus: '2.0'      # Max 2 CPU cores
          memory: 2G       # Max 2 GB RAM
        reservations:
          cpus: '0.5'      # Minimum 0.5 cores
          memory: 512M     # Minimum 512 MB
```

**Restart to apply:**
```bash
docker compose -f docker-compose.monitor.yml down
docker compose -f docker-compose.monitor.yml up -d

# Verify limits
docker stats miniprem-monitor
```

**Expected Resource Usage:**
- **Idle:** ~200-400 MB RAM, ~1-3% CPU
- **Active monitoring:** ~600-800 MB RAM, ~5-10% CPU
- **Log streaming:** ~800-1200 MB RAM, ~10-20% CPU

### Best Practices for macOS

#### 1. Use BuildKit for Faster Builds

**Enable BuildKit (default in Docker Desktop 4.x+):**
```bash
# Verify BuildKit is enabled
docker buildx version

# Build with BuildKit (automatic on Docker Desktop 4.x)
docker compose -f docker-compose.monitor.yml build --no-cache --pull
```

**Benefits:**
- 2-3x faster builds
- Better layer caching
- Parallel stage execution
- Reduced disk usage

#### 2. Prune Unused Resources Regularly

**Free Up Disk Space:**
```bash
# Remove stopped containers
docker container prune

# Remove unused images
docker image prune -a

# Remove unused volumes
docker volume prune

# Nuclear option: Remove everything unused
docker system prune -a --volumes

# Check disk usage
docker system df
```

**Automate Pruning (add to cron):**
```bash
# Edit crontab
crontab -e

# Add daily pruning at 3 AM
0 3 * * * /usr/local/bin/docker system prune -f >> /var/log/docker-prune.log 2>&1
```

#### 3. Enable Docker Content Trust (Optional)

**For Production Deployments:**
```bash
# Enable image signature verification
export DOCKER_CONTENT_TRUST=1

# Pull only signed images
docker pull miniprem-monitor:latest
```

#### 4. Monitor Docker Desktop Health

**Check Docker Desktop Status:**
```bash
# View Docker Desktop logs
open ~/Library/Containers/com.docker.docker/Data/log

# Check VM resource usage
docker info | grep -A 5 "Server Version"

# Monitor Docker Desktop with Activity Monitor
# Open Activity Monitor → Search "Docker Desktop"
# Watch: com.docker.backend, com.docker.vpnkit
```

#### 5. Use Docker Desktop Dashboard

**Visual Monitoring:**
1. Open Docker Desktop
2. Click **Dashboard** icon (📊)
3. **Features:**
   - Container list with CPU/Memory usage
   - Quick start/stop/logs access
   - Image management
   - Volume browser
   - Dev Environments

**Integrates with MiniPrem Monitor:**
- Use Docker Desktop for quick container management
- Use MiniPrem Monitor for advanced Kubernetes monitoring

#### 6. Optimize Network Performance

**For Remote Kubernetes Monitoring:**

```bash
# Use VPN split tunneling (if applicable)
# Route only cluster traffic through VPN

# Increase DNS cache
# Edit /etc/resolver/kubernetes
sudo mkdir -p /etc/resolver
echo "nameserver 8.8.8.8" | sudo tee /etc/resolver/kubernetes

# Test latency to cluster
kubectl get nodes --v=6  # Shows API call latency
```

---

## Updating the Application

### Check for Updates

**View Current Version:**
```bash
# Check git tags
cd /path/to/miniprem-2025
git describe --tags

# View image creation date
docker inspect miniprem-monitor:latest | grep Created
```

### Pull Latest Changes

```bash
# Navigate to repository
cd /path/to/miniprem-2025

# Fetch latest code
git fetch origin

# View available updates
git log HEAD..origin/main --oneline

# Pull updates (assuming you're on main branch)
git pull origin main
```

### Rebuild Container

```bash
# Stop current container
cd docker
docker compose -f docker-compose.monitor.yml down

# Rebuild with no cache (ensures fresh build)
docker compose -f docker-compose.monitor.yml build --no-cache --pull miniprem-monitor

# Start updated container
docker compose -f docker-compose.monitor.yml up -d

# Verify new version
docker logs miniprem-monitor | head -20
# Look for version number in startup logs
```

### Update Without Data Loss

**MiniPrem Monitor is Stateless:**
- No persistent data stored
- Configuration read from mounted volumes
- Safe to rebuild/restart anytime

**Update Process (Zero Downtime):**
```bash
# 1. Build new image with different tag
docker compose -f docker-compose.monitor.yml build miniprem-monitor

# 2. Stop old container
docker stop miniprem-monitor

# 3. Start new container
docker compose -f docker-compose.monitor.yml up -d

# Total downtime: ~5-10 seconds
```

### Rollback to Previous Version

**If Update Causes Issues:**

```bash
# 1. Find previous working image
docker images | grep miniprem-monitor

# Example output:
# miniprem-monitor    latest    abc123def456    2 days ago    2.88GB
# miniprem-monitor    backup    def456abc789    1 week ago    2.85GB

# 2. Tag old image as latest
docker tag def456abc789 miniprem-monitor:latest

# 3. Restart container
docker compose -f docker-compose.monitor.yml down
docker compose -f docker-compose.monitor.yml up -d

# Or edit docker-compose.monitor.yml to use specific image:
services:
  miniprem-monitor:
    image: miniprem-monitor:backup  # Use specific tag
```

### Automated Updates (Advanced)

**Create Update Script:**

```bash
#!/bin/bash
# ~/bin/update-miniprem-monitor.sh

set -e

echo "Updating MiniPrem Monitor..."

# Navigate to repository
cd /path/to/miniprem-2025

# Pull latest code
git pull origin main

# Rebuild container
cd docker
docker compose -f docker-compose.monitor.yml build --no-cache --pull miniprem-monitor

# Restart container
docker compose -f docker-compose.monitor.yml down
docker compose -f docker-compose.monitor.yml up -d

echo "Update complete!"
echo "Access: http://localhost:3001"
```

**Make executable:**
```bash
chmod +x ~/bin/update-miniprem-monitor.sh

# Run update
~/bin/update-miniprem-monitor.sh
```

---

## Uninstallation

### Quick Uninstall

**Stop and Remove Container:**
```bash
cd /path/to/miniprem-2025/docker

# Stop and remove container
docker compose -f docker-compose.monitor.yml down

# Verify removed
docker ps -a | grep miniprem-monitor
# Should show no results
```

**Container is stopped but image remains (can restart later).**

### Complete Uninstall

**Remove Container, Image, and All Related Resources:**

```bash
# 1. Stop and remove container
cd /path/to/miniprem-2025/docker
docker compose -f docker-compose.monitor.yml down

# 2. Remove Docker image
docker rmi miniprem-monitor:latest

# 3. Remove unused images (optional)
docker image prune -a

# 4. Remove repository (if desired)
cd ..
rm -rf /path/to/miniprem-2025

# 5. Clean up Docker system
docker system prune -a --volumes
```

**Verify Removal:**
```bash
# Check no containers
docker ps -a | grep miniprem

# Check no images
docker images | grep miniprem

# Check no volumes
docker volume ls | grep miniprem
```

### Uninstall Without Removing Repository

**Keep code but remove Docker artifacts:**
```bash
# Remove container
cd /path/to/miniprem-2025/docker
docker compose -f docker-compose.monitor.yml down

# Remove image
docker rmi miniprem-monitor:latest

# Keep repository for future use
# To reinstall later:
# docker compose -f docker-compose.monitor.yml build
# docker compose -f docker-compose.monitor.yml up -d
```

### Clean Up Docker Desktop

**After uninstalling, optimize Docker Desktop:**
```bash
# Remove all unused resources
docker system prune -a --volumes

# Check reclaimed space
docker system df

# Expected: Significant reduction in "Build Cache" and "Images"
```

**Before:**
```
TYPE            TOTAL     ACTIVE    SIZE
Images          15        2         5.2GB
Containers      8         1         450MB
Local Volumes   3         1         120MB
Build Cache     25        0         3.8GB
```

**After Pruning:**
```
TYPE            TOTAL     ACTIVE    SIZE
Images          3         1         1.1GB
Containers      1         1         150MB
Local Volumes   1         1         20MB
Build Cache     2         0         350MB
```

---

## Known Limitations

### 1. No GPU Support on macOS

**Limitation:**
- macOS does not support NVIDIA CUDA
- Docker Desktop for Mac cannot access GPU devices
- GPU-accelerated services (Renny, vLLM) require Linux + NVIDIA GPU

**Impact:**
- Cannot run full MiniPrem stack with digital human renderer
- Cannot run local LLM inference with vLLM
- Can only monitor Docker containers and Kubernetes clusters

**Workaround:**
- Use MiniPrem Monitor to monitor remote Linux clusters with GPU nodes
- Deploy full MiniPrem stack on Ubuntu 22.04 with NVIDIA GPU (see main README)
- Use cloud GPU instances (AWS g5.xlarge, Azure NC-series, GCP A100)

### 2. Backend Connectivity Issue (Intermittent)

**Limitation:**
- WebSocket connection may disconnect intermittently
- Backend API occasionally unresponsive (noted in Playwright tests)
- Affects real-time updates and log streaming

**Impact:**
- Dashboard shows red "Disconnected" indicator
- Manual page refresh required to restore connection
- Annoyance factor (does not prevent core functionality)

**Current Status:**
- Under investigation
- Likely related to supervisord process management
- Does not affect production use (workaround: refresh page)

**Workaround:**
```bash
# If WebSocket disconnects frequently:
# 1. Refresh browser page (Cmd+R)
# 2. Restart container if persistent:
docker compose -f docker-compose.monitor.yml restart miniprem-monitor
```

**Tracking:**
- GitHub Issue: [Link to issue if exists]
- Expected fix: Next release

### 3. Docker Host Network Mode Not Supported

**Limitation:**
- macOS Docker Desktop runs in Linux VM
- `network_mode: host` is ignored on macOS
- Must use bridge mode with port mapping

**Impact:**
- Slightly higher network latency (~1-2ms)
- Cannot bind services directly to host ports
- Backend port 8000 not directly accessible (by design)

**Workaround:**
- Bridge mode is fully functional (default configuration)
- Use `host.docker.internal` to access host services from container
- No action required (already configured correctly)

### 4. Cloud Provider Authentication Expiry

**Limitation:**
- AWS SSO sessions expire after 8-12 hours
- Azure CLI tokens expire after 1-2 hours
- Container does not auto-refresh credentials

**Impact:**
- Kubernetes monitoring stops working after expiry
- Manual re-authentication required
- Dashboard shows "Unauthorized" errors

**Workaround:**
```bash
# AWS EKS:
aws sso login --profile uneeq-admin
docker compose -f docker-compose.monitor.yml restart

# Azure AKS:
az login
az aks get-credentials --resource-group rg --name cluster --overwrite-existing
docker compose -f docker-compose.monitor.yml restart
```

**Future Enhancement:**
- Implement auto-refresh for cloud credentials
- Add authentication status indicator in dashboard
- Prompt user to re-authenticate when session expires

### 5. No Multi-Architecture Image (Yet)

**Limitation:**
- Docker image must be built locally (no pre-built image on Docker Hub)
- Different build time for Intel vs Apple Silicon Macs
- Cannot `docker pull` pre-built image

**Impact:**
- First-time build takes 5-10 minutes
- Subsequent builds are faster (layer caching)

**Workaround:**
- Build image locally using provided `docker-compose.monitor.yml`
- Follow [Quick Start](#quick-start) section

**Future Enhancement:**
- Publish multi-arch image to Docker Hub (amd64 + arm64)
- Enable `docker pull uneeq/miniprem-monitor:latest`
- Skip build step entirely

### 6. Limited Container Actions

**Limitation:**
- Can only Start/Stop containers (no Restart, Pause, etc.)
- Cannot delete containers from dashboard
- Cannot create new containers

**Impact:**
- Must use Docker Desktop or terminal for advanced operations
- Dashboard focused on monitoring, not full lifecycle management

**Rationale:**
- Security: Read-only Docker socket prevents dangerous operations
- Scope: Monitor is for monitoring, not orchestration
- Use Docker Compose or Kubernetes for container lifecycle

**Workaround:**
- Use Docker Desktop Dashboard for container management
- Use terminal: `docker restart`, `docker rm`, etc.

### 7. No GKE Support (Yet)

**Limitation:**
- Google Cloud GKE monitoring not yet implemented
- gcloud CLI integration in progress
- Cannot auto-detect GKE clusters

**Impact:**
- Must use self-managed cluster configuration for GKE
- No automatic credential refresh for GKE

**Workaround:**
- Manually export kubeconfig from GKE:
  ```bash
  gcloud container clusters get-credentials cluster-name --region us-central1
  # Then restart monitor
  docker compose -f docker-compose.monitor.yml restart
  ```

**Future Enhancement:**
- Full GKE support planned for next release
- gcloud CLI integration for auto-discovery
- Automatic credential refresh

### 8. Performance Limitations on Older Macs

**Limitation:**
- Monitoring 5+ Kubernetes clusters on Intel Macs may be slow
- WebSocket updates may lag on low-spec Macs (< 8GB RAM)
- Log streaming performance depends on Mac CPU

**Recommended Minimum:**
- **Mac:** MacBook Pro 2019+ or MacBook Air M1+
- **RAM:** 8 GB (16 GB recommended)
- **Disk:** SSD with 20GB+ free space

**Workaround:**
- Reduce number of monitored clusters
- Lower Docker Desktop resource allocation
- Close other resource-intensive apps

---

## Support & Resources

### Official Documentation

- **Main README:** `/Users/mbpro/uneeq/miniprem-2025/README.md`
- **MiniPrem Monitor README:** `/Users/mbpro/uneeq/miniprem-2025/miniprem-monitor/README.md`
- **CLAUDE.md (Developer Guide):** `/Users/mbpro/uneeq/miniprem-2025/CLAUDE.md`

### Quick Links

| Resource | Location |
|----------|----------|
| **Docker Compose File** | `/Users/mbpro/uneeq/miniprem-2025/docker/docker-compose.monitor.yml` |
| **Dockerfile** | `/Users/mbpro/uneeq/miniprem-2025/miniprem-monitor/Dockerfile` |
| **Backend Source** | `/Users/mbpro/uneeq/miniprem-2025/miniprem-monitor/backend/` |
| **Frontend Source** | `/Users/mbpro/uneeq/miniprem-2025/miniprem-monitor/frontend/` |
| **Playwright Tests** | `/Users/mbpro/uneeq/miniprem-2025/miniprem-monitor/frontend/tests/` |

### Getting Help

#### 1. Check Logs

**Container Logs:**
```bash
docker logs miniprem-monitor

# Follow logs in real-time
docker logs -f miniprem-monitor

# Last 100 lines
docker logs --tail 100 miniprem-monitor
```

**Backend Logs:**
```bash
docker exec miniprem-monitor tail -50 /var/log/supervisor/backend.err.log
```

**Frontend Logs:**
```bash
docker exec miniprem-monitor tail -50 /var/log/supervisor/frontend.err.log
```

#### 2. Search Documentation

**Use grep to search all docs:**
```bash
cd /Users/mbpro/uneeq/miniprem-2025
grep -r "your-search-term" docs/ *.md
```

#### 3. GitHub Issues

**Report a Bug:**
1. Check existing issues: [GitHub Issues](https://github.com/your-org/miniprem-2025/issues)
2. Create new issue if not found
3. **Include:**
   - macOS version (`sw_vers`)
   - Docker Desktop version (`docker --version`)
   - MiniPrem Monitor version (from logs)
   - Error messages (from logs)
   - Steps to reproduce

**Template:**
```markdown
## Bug Report

**Environment:**
- macOS Version: Sonoma 14.5
- Docker Desktop Version: 4.25.0
- MiniPrem Monitor Version: 1.0.0

**Issue:**
[Describe the issue]

**Steps to Reproduce:**
1. [First step]
2. [Second step]
3. [Error occurs]

**Expected Behavior:**
[What should happen]

**Actual Behavior:**
[What actually happens]

**Logs:**
```
[Paste relevant logs]
```
```

#### 4. Community Resources

**UneeQ Digital Humans:**
- **Website:** https://www.digitalhumans.com
- **Support Email:** support@digitalhumans.com
- **Documentation:** https://docs.digitalhumans.com

**Docker Desktop for Mac:**
- **Documentation:** https://docs.docker.com/desktop/mac/
- **Troubleshooting:** https://docs.docker.com/desktop/troubleshoot/overview/
- **Community Forums:** https://forums.docker.com/

**Kubernetes:**
- **kubectl Docs:** https://kubernetes.io/docs/reference/kubectl/
- **EKS Docs:** https://docs.aws.amazon.com/eks/
- **AKS Docs:** https://learn.microsoft.com/en-us/azure/aks/

### Testing the Application

**Run Playwright Tests (Local Development):**
```bash
cd /Users/mbpro/uneeq/miniprem-2025/miniprem-monitor/frontend

# Install dependencies (first time only)
npm install

# Run all tests
npm run test

# Run tests in headed mode (opens browser)
npm run test:headed

# Run tests in UI mode (interactive)
npm run test:ui

# View test report
npm run test:report
```

**Expected Test Results:**
- **31/36 tests passing** (as of last test run)
- Outstanding visual design scores
- Excellent responsive behavior
- Minor WebSocket connectivity issues (known limitation)

### Useful Commands Reference

```bash
# ========================================
# Container Management
# ========================================

# Start monitor
docker compose -f docker-compose.monitor.yml up -d

# Stop monitor
docker compose -f docker-compose.monitor.yml stop

# Restart monitor
docker compose -f docker-compose.monitor.yml restart

# Remove monitor
docker compose -f docker-compose.monitor.yml down

# View logs
docker logs miniprem-monitor

# Follow logs
docker logs -f miniprem-monitor

# Execute command in container
docker exec miniprem-monitor <command>

# ========================================
# Docker Management
# ========================================

# List all containers
docker ps -a

# List images
docker images

# Remove container
docker rm -f miniprem-monitor

# Remove image
docker rmi miniprem-monitor:latest

# Prune unused resources
docker system prune -a

# Check Docker disk usage
docker system df

# ========================================
# Kubernetes Management
# ========================================

# List contexts
kubectl config get-contexts

# Switch context
kubectl config use-context <context-name>

# Test connectivity
kubectl cluster-info

# Get nodes
kubectl get nodes

# Get pods (all namespaces)
kubectl get pods -A

# ========================================
# AWS EKS Management
# ========================================

# Login to AWS SSO
aws sso login --profile uneeq-admin

# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name <cluster>

# List clusters
aws eks list-clusters --region us-east-1

# ========================================
# Azure AKS Management
# ========================================

# Login to Azure
az login

# Get AKS credentials
az aks get-credentials --resource-group <rg> --name <cluster>

# List clusters
az aks list --output table

# ========================================
# Debugging
# ========================================

# Check backend health
curl http://localhost:8000/health

# Test Docker socket access
docker exec miniprem-monitor docker ps

# Test kubectl access
docker exec miniprem-monitor kubectl version --client

# View backend errors
docker exec miniprem-monitor tail -50 /var/log/supervisor/backend.err.log

# View frontend errors
docker exec miniprem-monitor tail -50 /var/log/supervisor/frontend.err.log

# Inspect container
docker inspect miniprem-monitor

# Check container resources
docker stats miniprem-monitor
```

---

## Appendix: Advanced Topics

### A. Custom Environment Variables

**Override default settings:**

Edit `docker-compose.monitor.yml`:
```yaml
services:
  miniprem-monitor:
    environment:
      - MONITOR_MODE=standalone
      - LOG_LEVEL=debug  # info, warn, error
      - BACKEND_PORT=8000  # Don't change (internal)
      - FRONTEND_PORT=3001  # Don't change (internal)
      - WEBSOCKET_PING_INTERVAL=10  # Seconds
      - CONTAINER_REFRESH_INTERVAL=5  # Seconds
```

**Apply changes:**
```bash
docker compose -f docker-compose.monitor.yml down
docker compose -f docker-compose.monitor.yml up -d
```

### B. SSL/TLS Configuration (HTTPS)

**For production deployments with SSL:**

**Option 1: Nginx Reverse Proxy**

Create `nginx.conf`:
```nginx
server {
    listen 443 ssl;
    server_name monitor.example.com;

    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;

    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /ws {
        proxy_pass http://localhost:8000/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

**Run Nginx:**
```bash
# Install Nginx
brew install nginx

# Copy config
sudo cp nginx.conf /usr/local/etc/nginx/servers/miniprem-monitor.conf

# Restart Nginx
sudo nginx -s reload

# Access via HTTPS
open https://monitor.example.com
```

**Option 2: Cloudflare Tunnel**

```bash
# Install cloudflared
brew install cloudflare/cloudflare/cloudflared

# Authenticate
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create miniprem-monitor

# Configure tunnel
cat > ~/.cloudflared/config.yml <<EOF
tunnel: miniprem-monitor
credentials-file: /Users/youruser/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: monitor.example.com
    service: http://localhost:3001
  - service: http_status:404
EOF

# Run tunnel
cloudflared tunnel run miniprem-monitor

# Access via HTTPS
open https://monitor.example.com
```

### C. macOS System Logs

**View macOS Docker logs:**
```bash
# Docker Desktop logs
log stream --predicate 'eventMessage contains "Docker"' --info

# Specific Docker errors
log show --predicate 'eventMessage contains "Docker"' --last 1h | grep error

# Docker Desktop crash reports
ls -la ~/Library/Logs/DiagnosticReports/Docker*
```

### D. Performance Profiling

**Profile container performance:**
```bash
# Real-time stats
docker stats miniprem-monitor

# Export stats to file
docker stats --no-stream miniprem-monitor > monitor-stats.txt

# Analyze with ctop (Container Top)
brew install ctop
ctop
```

**Profile backend performance:**
```bash
# Install py-spy
pip install py-spy

# Profile Python backend
docker exec miniprem-monitor py-spy record -o profile.svg -- python backend/run.py

# View profile.svg in browser
open profile.svg
```

---

<div align="center">

## You're All Set!

MiniPrem Monitor is now running on your Mac.

**Access Dashboard:** http://localhost:3001

**Need Help?** See [Troubleshooting](#troubleshooting) section.

---

**© 2025 UneeQ. All rights reserved.**

![UneeQ Logo](https://presales.services.uneeq.io/uneeq-internal/assets/logos/UneeQ+Logo+Horizontal+CMYK.png)

**Digital Humans. Unlimited Possibilities.**

[www.digitalhumans.com](https://www.digitalhumans.com) | [support@digitalhumans.com](mailto:support@digitalhumans.com)

</div>
