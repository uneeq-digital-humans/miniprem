# MiniPrem Monitor Demo Script - All Hands Presentation

## Overview

**Target Audience**: Technical and non-technical stakeholders
**Duration**: 5-10 minutes
**Key Message**: MiniPrem Monitor provides a complete visual interface for managing Digital Human deployments - bridging the gap between command-line experts and GUI-preferring users.

---

## Opening Hook (30 seconds)

> "There are people who are comfortable with the command line, and people who prefer a GUI. MiniPrem Monitor bridges that gap - giving everyone visibility into Renny's health and system resources through a visual interface that updates in real-time."

---

## Demo Flow

### 1. MiniPrem Monitor Dashboard (http://localhost:3001)

**What to show:**
- Real-time container status with color-coded health indicators
- System metrics cards at the top (CPU, Memory, Disk, GPU)
- Live WebSocket updates (no page refresh needed)

**Key talking points:**
- "This is the MiniPrem Monitor - our operational dashboard for Digital Human deployments"
- "Every MiniPrem installation includes this automatically - it's bundled with everything"
- "Watch the metrics update in real-time as the system runs"

**Live Data Available:**
| Metric | Current Value | Notes |
|--------|---------------|-------|
| Renny Status | Running 24+ hours | Healthy, green indicator |
| Sessions Total | 9 | Real user interactions |
| Frames Rendered | 77,072 | Shows Renny activity |
| GPU Utilization | ~55% | A10G with 17GB/23GB VRAM |
| System Memory | 3.8GB / 31GB | Healthy headroom |
| Disk Usage | 78GB / 247GB (32%) | Plenty of space |

**Demo Actions:**
1. Click on CPU metric card → Shows detailed CPU breakdown per core
2. Click on Memory card → Shows memory consumers and trends
3. Filter containers by Running/Stopped tabs
4. Hover over Renny container → Show extended metrics

---

### 2. Grafana Dashboards (http://localhost:3002)

**Login**: admin / admin

**What to show:**
- Pre-configured dashboards for metrics visualization
- Time-series graphs showing historical data
- Prometheus as the data source

**Key talking points:**
- "For deeper analysis, Grafana provides time-series visualization"
- "This connects to Prometheus which collects metrics every 15 seconds"
- "You can build custom dashboards for specific use cases"

---

### 3. Prometheus Metrics (http://localhost:9090)

**What to show:**
- Navigate to Status → Targets to show what's being monitored
- Show a simple query: `process_cpu_seconds_total`

**Key talking points:**
- "Prometheus is our metrics database - it stores time-series data"
- "This enables alerting and historical analysis"
- "NLP metrics and custom application metrics can be added here"

---

## Value Proposition Slide

### More Than Just a Digital Human

> "MiniPrem is more than just a digital human - it's the whole experience:
> - **Self-service monitoring**: No need to SSH into servers
> - **Self-service troubleshooting**: See what's running, what's stopped, and why
> - **Visual operations**: Start, stop, and inspect containers with one click
> - **Real-time insights**: WebSocket-powered live updates"

---

## Key Differentiators for Customer Demos

### For GitLab/Shepherd Users
- "This integrates with your existing infrastructure"
- "MiniPrem Monitor can show Kubernetes pods when connected to EKS/AKS clusters"
- "Container logs accessible through the Terminal button"

### For Self-Service Teams
- "Reduces support tickets by giving operators direct visibility"
- "No command-line knowledge required for basic operations"
- "Health checks are automatic - green means healthy"

---

## Screenshot Opportunities

### 1. MiniPrem Monitor Main Dashboard
- Shows all containers with health status
- System metrics visible at top
- UneeQ branding prominent

### 2. Detailed Metrics Modal (Click CPU or Memory card)
- Per-core CPU visualization
- 5-minute rolling graphs
- Automatic insights and recommendations

### 3. Grafana Dashboard
- Time-series graphs
- Multiple panels showing different metrics

### 4. Renny Container Details
- Session count: 9
- Frames rendered: 77,072
- Uptime: 24+ hours

---

## Closing Statement

> "Every MiniPrem deployment - whether Docker-based local install or Kubernetes in the cloud - includes this monitoring stack. It's bundled with everything, requires zero additional setup, and gives both command-line experts and GUI users the visibility they need."

---

## Technical Details (If Asked)

### Architecture
- **MiniPrem Monitor**: Next.js frontend + FastAPI backend in single container
- **Prometheus**: Time-series database (15s scrape interval)
- **Grafana**: Visualization layer (connects to Prometheus)
- **WebSocket**: Real-time updates (2-second polling internally)

### Current EC2 Test Instance
- **Instance**: Dell MiniPrem Test (AWS EC2)
- **IP**: 98.83.107.14
- **GPU**: NVIDIA A10G (24GB VRAM)
- **OS**: Ubuntu 22.04
- **Tunnels**: 3001 (Monitor), 3002 (Grafana), 9090 (Prometheus)

### Access Commands (For Reference)
```bash
# SSH Tunnel Setup
ssh -i ~/uneeq-code/ssh-miniprem2.pem -f -N -L 3001:localhost:3001 ubuntu@98.83.107.14
ssh -i ~/uneeq-code/ssh-miniprem2.pem -f -N -L 3002:localhost:3002 ubuntu@98.83.107.14
ssh -i ~/uneeq-code/ssh-miniprem2.pem -f -N -L 9090:localhost:9090 ubuntu@98.83.107.14

# Direct SSH Access
ssh -i ~/uneeq-code/ssh-miniprem2.pem ubuntu@98.83.107.14

# Check Container Status
sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Check GPU Status
nvidia-smi
```

---

## Troubleshooting During Demo

### If MiniPrem Monitor Shows "Error" Connection
- The WebSocket is working (data is flowing)
- This is a known UI bug being fixed
- Refresh the page or show the WebSocket data directly

### If Grafana Login Fails
- Default credentials: admin / admin
- May prompt for password change on first login

### If vLLM Shows "health: starting" Constantly
- vLLM is crashing due to GPU memory conflict with Renny
- This is expected when Renny is using most of the GPU
- Focus demo on Renny monitoring instead
