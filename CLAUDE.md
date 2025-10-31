# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CRITICAL EFFICIENCY RULES

- Before reading any file: Check if already read in last 10 messages. If yes, use buffer memory.
- Before executing any plan item: Evaluate if actually needed. If code already satisfies goal, propose skip.
- Choose most direct implementation: MultiEdit batch operations, no temp scripts for simple tasks.
- Concise by default: No preambles, no postambles, minimal explanation unless asked.

## File Read Optimization Protocol

Before ANY Read Tool Call:
- Check conversation buffer: "Have I read this file in last 10 messages?"
- If YES and no user edits mentioned: Use cached memory, do NOT re-read
- If uncertain about file state: Check git status or ask user

Exception: User explicitly says "check file again"

## Quick Commands

### MiniPrem Management (Docker)
```bash
# Core management script
./miniprem.sh start|stop|status|restart|logs|setup

# Initial installation (interactive)
./docker/scripts/install_miniprem.sh

# Setup chatflow after deployment
./setup-chatflow-post-deployment.sh
```

### Kubernetes Multi-Cloud Deployment
```bash
cd kubernetes/

# Multi-cloud deployment with interactive platform selection
# Supports: AWS (EKS), Azure (AKS), Google Cloud (GKE - planned)
./scripts/deploy.sh
# → Prompts for platform → validates CLI/auth → deploys infrastructure

# Platform-specific direct deployment (optional)
./scripts/deploy-aws.sh     # AWS EKS deployment (~30-45 min)
./scripts/deploy-azure.sh   # Azure AKS deployment (~35-50 min)

# Check deployment status (multi-cloud aware)
./scripts/status.sh
./scripts/scale.sh <number>
./scripts/destroy.sh
```

**Google GKE:**
```bash
cd kubernetes/terraform/gke/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan -out=tfplan
terraform apply tfplan  # ~15-20 min
gcloud container clusters get-credentials <cluster-name> --region <region>
```

**Azure AKS:**
```bash
# AKS deployment scripts (see kubernetes/terraform/aks/)
```

### Cloud Platform Utilities
```bash
# AWS-specific utilities
./scripts/eks/check-aws-prerequisites.sh [--profile <profile>]
./scripts/eks/check-vpc-usage.sh [--region <region>] [--vpc <vpc-id>]

# Multi-cloud deployment uses:
# - AWS CLI (aws) for EKS deployments
# - Azure CLI (az) for AKS deployments
# - Google Cloud CLI (gcloud) for GKE deployments (planned)
```

### Common Development Tasks
```bash
# View Docker logs
docker logs <container_name>
docker-compose logs  # All services

# Kubernetes monitoring
kubectl get pods -A                    # All pods across namespaces
kubectl get pods -n uneeq-renderer     # Application pods
kubectl logs <pod-name> -n uneeq-renderer -f  # Follow logs

# Check GPU status (after deployment)
kubectl get nodes -L nvidia.com/gpu,uneeq.io/node-type
kubectl exec -n gpu-operator $(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset -o name | head -1) -- nvidia-smi

# MiniPrem Monitor Testing (Playwright TDD)
cd miniprem-monitor/frontend/
npm run test                    # Run all Playwright tests
npm run test:headed            # Visual testing (browser opens)
npm run test:ui                # Interactive test UI
npm run test:debug             # Debug mode with step-by-step execution
npm run test:report            # View test results report
npm run test:chromium          # Chrome-specific tests
npm run test:firefox           # Firefox-specific tests
npm run test:mobile            # Mobile responsive tests

# MiniPrem Monitor Development
cd docker/
docker compose -f docker-compose.monitor.yml build --no-cache --pull miniprem-monitor
docker compose -f docker-compose.monitor.yml up -d miniprem-monitor
docker compose -f docker-compose.monitor.yml logs -f miniprem-monitor
docker exec miniprem-monitor tail -50 /var/log/supervisor/backend.err.log  # Backend errors
docker exec miniprem-monitor docker ps --format json  # Test Docker CLI access
docker exec miniprem-monitor kubectl version --client  # Test kubectl access
```

## MiniPrem Monitor - Current Working State

**Status**: Docker container monitoring fully operational (January 2025)

### What's Working ✅
- Docker container listing via CLI (subprocess-based)
- Real-time WebSocket updates for container status changes
- System metrics: CPU, Memory, Disk, Network I/O
- **Clickable metrics cards** with detailed drill-down views (CPU, Memory, Disk, Network)
- **Live 5-minute rolling graphs** for all system metrics with real-time updates
- **Per-core CPU visualization** to verify multi-threading behavior
- **Top consumers lists** for CPU, Memory, and Network resources
- **Automatic insights engine** with intelligent pattern detection
- **Color-coded recommendations** for actionable guidance
- Container status indicators (running/stopped with color coding)
- Filter tabs (All/Running/Stopped) with live counts
- Start/Stop container control buttons
- Per-container network statistics (TX/RX bytes)

### Technical Implementation Details
- **Architecture**: CLI-based approach using subprocess (not Python SDKs)
- **Reason for CLI**: Docker SDK urllib3>=2.0 conflicts with Kubernetes SDK urllib3<2.0
- **CLI Tools**: docker-24.0.7 (static binary), kubectl-1.28.0 (static binary)
- **Networking**: Bridge mode (macOS/Windows compatible, Linux can use host)
- **Docker Socket**: `/var/run/docker.sock` mounted read-only
- **Kubeconfig**: `~/.kube` mounted read-only for cluster access
- **Metrics Collection**: 2-second polling interval, 5-minute rolling history (150 data points)
- **Network Stats**: SI 1000-based unit conversion (Docker NetIO field parsing)

### Detailed Metrics Modal System 📊

**Overview**: Click any of the four top metrics cards (CPU, Memory, Disk, Network) to open an interactive modal with live graphs, detailed breakdowns, and automatic insights.

**CPU Detail View** (`SystemMetricsModal.tsx` → `CpuDetailView.tsx`):
- **Live 5-minute rolling graph**: Displays CPU usage percentage over time with real-time updates
- **Current metrics**: Overall CPU usage with color-coded status indicators
  - Green: 0-60% (healthy)
  - Yellow: 60-80% (moderate)
  - Red: 80-100% (critical)
- **Per-core CPU visualization**: Horizontal bars showing individual core usage
  - Verifies multi-threading behavior for containerized applications
  - Useful for identifying single-threaded bottlenecks
  - Color-coded per core: green (0-60%), yellow (60-80%), red (80-100%)
- **Top CPU consumers**: Sortable list of containers by CPU usage percentage
  - Shows container name and CPU percentage
  - Helps identify resource-intensive containers
- **Automatic insights**:
  - Multi-threading efficiency: Detects balanced workload distribution (std dev < 15%)
  - Core imbalance warnings: Identifies uneven core usage patterns
  - Single-threaded bottlenecks: Detects when one core is maxed while others idle
  - Critical CPU alerts: Warns when system CPU > 90%
  - Resource monopoly detection: Identifies containers consuming > 70% CPU
- **Color-coded recommendations**: Green (success), Yellow (warning), Red (error), Blue (info)

**Memory Detail View** (`MemoryDetailView.tsx`):
- **Live 5-minute rolling graph**: Memory usage percentage with time-series visualization
- **Current metrics**: Memory used (GB), available (GB), and percentage
- **Memory breakdown**: Total system memory vs. consumed memory
- **Top memory consumers**: Sortable list by memory usage
  - Shows container name, memory in MB, and percentage of total
- **Automatic insights**:
  - Critical/high memory alerts: Warnings at 90% and 80% thresholds
  - Memory trend detection: Identifies increasing usage patterns (requires 50+ data points)
  - Memory leak detection: Analyzes sustained growth over time (requires 100+ data points)
  - Memory concentration warnings: Flags when top consumer uses > 40%
  - Healthy memory status: Confirms when usage is below 60%
- **Statistical analysis**: Calculates trends and growth patterns from historical data

**Network Detail View** (`NetworkDetailView.tsx`):
- **Live dual-line graph**: Upload (blue) and download (purple) rates over 5 minutes
- **Transfer statistics**:
  - Current upload/download rates in MB/s or KB/s
  - Peak rates during the monitoring window
  - Average rates for sustained traffic analysis
- **Top network consumers**: Sortable list by total bytes transferred
  - Shows TX (transmit) and RX (receive) bytes per container
  - Total combined network usage
- **Automatic insights**:
  - High bandwidth detection: Warns when peak exceeds 100 MB/s
  - Traffic imbalance analysis: Detects upload/download ratio > 5x
  - Sustained traffic patterns: Identifies continuous high usage
  - Low activity confirmation: Healthy state when < 10 MB/s
  - Top consumer impact: Flags containers using > 1 GB or > 80% bandwidth
- **Network rate calculations**: Derives per-second rates from cumulative byte counters

**Disk Detail View** (built-in, existing):
- Live disk usage graph with percentage over time
- Current disk space breakdown
- Used/free space statistics

**Common Modal Features**:
- **Framer Motion animations**: Smooth entrance/exit with backdrop fade
- **Dark mode support**: Full Tailwind dark: classes for all components
- **Real-time updates**: Live data via WebSocket subscriptions (2-second interval)
- **Historical data management**: FIFO cleanup maintains 5-minute window (150 points max)
- **Responsive design**: Mobile-friendly layouts with proper spacing
- **Tab navigation**: Switch between different metric details within modal
- **Close button**: ESC key or X button to dismiss modal
- **Data-testid attributes**: Full Playwright test coverage support

**Usage for Multi-Threading Verification**:
1. Start a container that should utilize all CPU cores
2. Click the CPU metrics card to open CPU Detail View
3. Scroll to "Per-Core CPU Usage" section
4. Verify that all cores show balanced usage (variance should be low)
5. Check automatic insights for "Excellent Multi-Threading" confirmation
6. If only one core is active, check Docker Compose CPU settings

**File Structure**:
```
miniprem-monitor/frontend/src/components/
├── SystemMetricsModal.tsx           # Main modal container
├── metrics-detail/
│   ├── index.ts                     # Module exports
│   ├── MetricsChart.tsx            # Recharts line chart component
│   ├── CpuDetailView.tsx           # CPU metrics + insights
│   ├── MemoryDetailView.tsx        # Memory metrics + insights
│   ├── NetworkDetailView.tsx       # Network metrics + insights
│   └── DiskDetailView.tsx          # Disk metrics (basic)
```

**Backend Enhancements**:
- `backend/app/models/schemas.py`: Added network_tx_bytes/network_rx_bytes to ContainerStatus
- `backend/app/security/command_executor.py`: Enhanced Docker stats parser
  - Parses NetIO field: "130kB / 385kB" → (rx_bytes, tx_bytes)
  - Converts all Docker size units: B, kB, MB, GB, TB, PB (SI 1000-based)
  - Returns per-container network statistics in real-time

### Known Limitations ⚠️
- Kubernetes EKS authentication requires active AWS SSO session
- Run `aws sso login --profile uneeq-admin` on host before starting container
- AWS CLI v2 installed and working (aws-cli/2.31.9)

### Dockerfile CLI Installation Pattern
```dockerfile
# Install Docker CLI (static binary for cross-platform)
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then ARCH="x86_64"; elif [ "$ARCH" = "aarch64" ]; then ARCH="aarch64"; fi && \
    curl -fsSL "https://download.docker.com/linux/static/stable/${ARCH}/docker-24.0.7.tgz" -o docker.tgz && \
    tar xzf docker.tgz && \
    mv docker/docker /usr/local/bin/ && \
    rm -rf docker docker.tgz && \
    chmod +x /usr/local/bin/docker

# Install kubectl (static binary)
RUN ARCH=$(dpkg --print-architecture) && \
    curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/${ARCH}/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Install AWS CLI v2 (required for EKS authentication)
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then ARCH="x86_64"; elif [ "$ARCH" = "arm64" ]; then ARCH="aarch64"; fi && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip
```

### Build Best Practices
Always use `--no-cache --pull` for clean rebuilds:
```bash
docker compose -f docker-compose.monitor.yml build --no-cache --pull miniprem-monitor
```

### Prerequisites for EKS Monitoring
Before starting the monitor container for EKS cluster access:
```bash
# Refresh AWS SSO session (required for EKS authentication)
aws sso login --profile uneeq-admin

# Start the monitor
cd docker/
docker compose -f docker-compose.monitor.yml up -d
```

## Architecture Overview

MiniPrem is a multi-deployment digital human platform with two main architectures:

### Docker Architecture (Local Development)
- **MiniPrem Monitor**: Real-time container and Kubernetes monitoring dashboard (port 3001)
- **Renny**: Digital human renderer with internal speech processing (UneeQ integration)
- **vLLM**: LLM inference server (Gemma3/Mistral models)
- **Flowise**: Workflow automation and LLM integration
- **Grafana/Prometheus**: Monitoring and metrics (Grafana on port 3002)
- **Redis**: Message queuing
- **RIME**: Text-to-speech API service

**Installation Types:**
- `default`: Renny + MiniPrem Monitor (basic setup with monitoring)
- `full`: All services including AI stack, metrics, and monitoring
- `monitor-only`: Standalone MiniPrem Monitor for Kubernetes cluster monitoring

### Kubernetes Architecture (Production - Multi-Cloud)

**AWS EKS:**
- **EKS Cluster**: Production-ready with auto-scaling
- **GPU Node Groups**: g5.4xlarge instances with NVIDIA A10G GPUs (24GB VRAM)
- **GPU Operator**: Automatic NVIDIA driver installation (575+ or 580+)
- **Multi-AZ**: High availability across 3 availability zones
- **Time-Slicing**: Multiple pods per GPU for cost optimization
- **Cost**: ~$1.20/hour per node

**Azure AKS:**
- **AKS Cluster**: Managed Kubernetes with auto-scaling
- **GPU Node Pools**: Standard_NC16as_T4_v3 with NVIDIA T4 GPUs (16GB VRAM)
- **GPU Operator**: Automatic NVIDIA driver installation (580+)
- **Multi-Zone**: High availability across availability zones
- **Time-Slicing**: Multiple pods per GPU for cost optimization
- **Cost**: ~$1.50/hour per node

**Google Cloud GKE** (Planned):
- GKE cluster with GPU node pools
- T4 or A100 GPU instances
- Full feature parity with AWS/Azure

## Key Configuration Files

### Docker Configuration
- `docker/docker-compose.full.yml`: Full install services (all services including monitor)
- `docker/docker-compose.yml`: Default install services (Renny + monitor)
- `docker/docker-compose.monitor.yml`: Standalone monitor for Kubernetes monitoring
- `docker/configuration.dat`: UneeQ platform credentials (JSON format)
- `.miniprem_install_type`: Current installation type (default/full)
- `miniprem-monitor/`: Complete monitoring application (Next.js + FastAPI in single Docker image)

### Kubernetes Configuration (Multi-Cloud)

**AWS EKS:**
- `kubernetes/terraform/eks/terraform.tfvars`: AWS infrastructure settings (region, credentials, scaling)
- AWS-specific: VPC configuration, IAM roles, EKS cluster settings

**Azure AKS:**
- `kubernetes/terraform/aks/terraform.tfvars`: Azure infrastructure settings (region, credentials, scaling)
- Azure-specific: VNet configuration, service principal, AKS cluster settings

**Shared Configuration:**
- `kubernetes/values/renny-values.yaml`: **Single source of truth** for Renny configuration (all platforms):
  - GPU time-slicing settings (`gpuTimeSlicing.replicasPerGpu`)
  - Total replica count (`deployment.totalReplicas`)
  - Per-pod resource limits (CPU, memory, GPU)
  - All application environment variables
- `kubernetes/manifests/`: Kubernetes resource definitions (platform-agnostic)
- `kubernetes/scripts/`: Multi-cloud deployment automation

## Directory Structure

```
miniprem-2025/
├── docker/                 # Docker-based local deployment
│   ├── docker-compose.full.yml  # Full services stack
│   ├── docker-compose.yml  # Basic services
│   ├── docker-compose.monitor.yml  # Standalone monitor
│   └── configuration.dat   # UneeQ credentials
├── miniprem-monitor/       # Monitoring application
│   ├── backend/           # FastAPI backend
│   ├── frontend/          # Next.js frontend
│   ├── Dockerfile         # Multi-stage build
│   └── docker-entrypoint.sh
├── kubernetes/             # Production multi-cloud Kubernetes deployment
│   ├── terraform/          # Infrastructure as Code (per-platform)
│   │   ├── eks/           # AWS EKS Terraform configuration
│   │   ├── aks/           # Azure AKS Terraform configuration
│   │   └── gke/           # Google Cloud GKE (planned)
│   ├── scripts/           # Multi-cloud deployment automation
│   │   ├── deploy.sh      # Main router (prompts for platform)
│   │   ├── deploy-aws.sh  # AWS EKS deployment
│   │   ├── deploy-azure.sh # Azure AKS deployment
│   │   ├── destroy.sh     # Multi-cloud router
│   │   ├── status.sh      # Multi-cloud router
│   │   └── scale.sh       # Multi-cloud router
│   ├── manifests/         # Kubernetes resources (platform-agnostic)
│   └── values/            # Helm chart values (shared)
├── scripts/               # Utility scripts (audio, environment)
└── docs/                  # Documentation
```

## Port Mappings

### Docker Services (Local)
| Service | Port | Description |
|---------|------|-------------|
| **MiniPrem Monitor** | **3001** | Primary monitoring dashboard (frontend + backend) |
| Flowise | 3000 | Workflow automation UI |
| Grafana | 3002 | Metrics dashboard (moved from 3001) |
| Prometheus | 9090 | Metrics collection |
| vLLM API | 8000 | LLM inference API |
| Renny Health | 8081 | Digital human health check |
| RIME API | 8100 | Text-to-speech API |
| Redis | 6379 | Message queue |
| Whisper | 9000 | Speech-to-text API |

**Note:** MiniPrem Monitor uses host network mode for direct Docker socket access. The backend runs internally on port 8000, but this is not exposed externally when using host networking.

## Development Workflow

### Docker Development (Local)
1. Run `./docker/scripts/install_miniprem.sh` for interactive setup
2. Use `./miniprem.sh start` to launch services
3. Access services at configured ports (Monitor: 3001, Flowise: 3000, Grafana: 3002, etc.)
4. Monitor with MiniPrem Monitor at http://localhost:3001 or `./miniprem.sh logs`

**Standalone Monitor Deployment (Kubernetes monitoring):**
```bash
cd docker
docker-compose -f docker-compose.monitor.yml up -d
# Access at http://localhost:3001
```

### Kubernetes Development (Production - Multi-Cloud)

**Step 1: Choose Your Cloud Platform**
```bash
cd kubernetes/
./scripts/deploy.sh
# Interactive menu prompts for: AWS, Azure, or GCP
```

**Step 2: Platform-Specific Configuration**

**For AWS EKS:**
1. Configure AWS credentials: `aws sso login --profile <profile>` or `aws configure`
2. Edit `kubernetes/terraform/eks/terraform.tfvars`:
   - Set AWS region, VPC settings
   - Configure node group sizes
3. The script validates: AWS CLI installed, authentication active

**For Azure AKS:**
1. Configure Azure credentials: `az login`
2. Edit `kubernetes/terraform/aks/terraform.tfvars`:
   - Set Azure subscription ID, tenant ID, service principal
   - Configure resource group, VNet settings
   - Set node pool sizes
3. The script validates: Azure CLI installed, authentication active

**Step 3: Configure GPU Time-Slicing (All Platforms)**
Edit `kubernetes/values/renny-values.yaml`:
```yaml
gpuTimeSlicing:
  replicasPerGpu: 2  # Pods per GPU (2-4 recommended)
deployment:
  totalReplicas: 4   # Total pods (must be multiple of replicasPerGpu)
```

**Step 4: Deploy**
```bash
./scripts/deploy.sh
# OR use platform-specific scripts:
./scripts/deploy-aws.sh      # AWS EKS (~30-45 min)
./scripts/deploy-azure.sh    # Azure AKS (~35-50 min)
```

**Step 5: Monitor and Manage**
```bash
./scripts/status.sh    # Check deployment status (multi-cloud aware)
./scripts/scale.sh 15  # Scale Renny instances
./scripts/destroy.sh   # Complete cleanup
```

**Changing GPU Time-Slicing After Deployment:**
```bash
# Edit kubernetes/values/renny-values.yaml, then:
cd kubernetes/
./scripts/deploy.sh  # Automatically updates ConfigMap and restarts GPU device plugins

# OR manually update:
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: renny-time-slicing-config
  namespace: gpu-operator
data:
  renny: |-
    version: v1
    flags:
      migStrategy: none
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: 4  # Match gpuTimeSlicing.replicasPerGpu
EOF
kubectl delete pods -n gpu-operator -l app=nvidia-device-plugin-daemonset
```

## Telemetry System

### Overview
MiniPrem includes a telemetry system that tracks deployment health and usage across Docker and Kubernetes environments. The telemetry backend is deployed at https://renny.services.uneeq.io and stores data in DynamoDB.

### Key Concepts
- **Installation ID**: Unique identifier per pod/container instance (e.g., `eks-1761285734-14a65718b9c3c36e`)
- **Machine ID**: SHA-256 hash representing the physical machine/node
  - **Kubernetes**: Hash of NODE_NAME (ensures pods on same node report same machine_id)
  - **Docker with GPU**: Hash of GPU UUID from nvidia-smi
  - **Docker fallback**: Hash of hostname
- **Deployment ID**: Fixed identifier grouping all instances of a deployment
- **Event Types**: `installation` (startup) and `heartbeat` (every 5 minutes)

### Telemetry Client Script
Location: `kubernetes/renny/scripts/renny-telemetry-client.sh`

**Critical Fix (October 2024)**: The `get_machine_id()` function was fixed to prioritize Kubernetes NODE_NAME over pod hostname. This ensures multiple pods on the same physical node correctly report as one machine.

**Machine ID Priority (Kubernetes)**:
1. **NODE_NAME** (env var from `spec.nodeName`) → SHA-256 hash
2. GPU UUID from nvidia-smi → SHA-256 hash
3. Hostname fallback → SHA-256 hash

**Example Log Output (Correct)**:
```
[2025-10-24 06:02:14] INFO: Machine ID from Kubernetes node: ip-10-17-2-248.ec.internal
[2025-10-24 06:02:14] INFO: Machine ID: 9e49480eab3b03dc...
```

### Dashboard Metrics
The telemetry dashboard (https://renny.services.uneeq.io) displays:
- **MiniPrem Deployments**: Count of unique deployment_ids
- **Active Machines**: Count of unique machine_ids (physical nodes)
- **Active Rennys**: Count of unique installation_ids (running pods)

**Expected Behavior for 2 pods on 1 node**:
- 1 Machine (same machine_id)
- 2 Active Rennys (different installation_ids)

### Troubleshooting Telemetry

**Check telemetry logs**:
```bash
kubectl logs <pod-name> -c telemetry -n uneeq-renderer --tail=50
```

**Verify machine_id matches across pods**:
```bash
# Both pods on same node should show identical machine_id
kubectl logs renderer-abc123-pod1 -c telemetry -n uneeq-renderer | grep "Machine ID"
kubectl logs renderer-abc123-pod2 -c telemetry -n uneeq-renderer | grep "Machine ID"
```

**Query DynamoDB directly**:
```bash
aws dynamodb scan --table-name miniprem-telemetry --region us-east-1 \
  --filter-expression "deployment_id = :did" \
  --expression-attribute-values '{":did":{"S":"YOUR_DEPLOYMENT_ID"}}'
```

**Common Issues**:
- **Multiple machines for pods on same node**: Old bug where hostname was used instead of NODE_NAME. Fixed in renny-telemetry-client.sh:get_machine_id()
- **Stale heartbeats after pod restart**: Delete old entries from DynamoDB using installation_id + timestamp keys
- **No telemetry data**: Check that telemetry.enabled=true in renny-values.yaml and ConfigMap is up to date

### Updating Telemetry Script
```bash
# 1. Edit the script
vim kubernetes/renny/scripts/renny-telemetry-client.sh

# 2. Update ConfigMap in cluster
kubectl create configmap renny-telemetry -n uneeq-renderer \
  --from-file=telemetry-client.sh=renny/scripts/renny-telemetry-client.sh \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Restart pods to apply changes
kubectl delete pods --all -n uneeq-renderer
```

## Troubleshooting

### Docker Issues
- Check container health: `docker ps -a`
- View specific logs: `docker logs <container>`
- Verify GPU: `nvidia-smi`
- Check UneeQ config: `cat docker/configuration.dat`

### Kubernetes Issues
- Check pod status: `kubectl get pods -n uneeq-renderer`
- View detailed events: `kubectl describe pod <pod-name> -n uneeq-renderer`
- GPU operator status: `kubectl get pods -n gpu-operator`
- Node resources: `kubectl describe nodes -l uneeq.io/node-type=renny`

### Multi-Cloud Platform Issues

**AWS/EKS:**
- Profile detection: Scripts auto-detect AWS profile/region from environment
- VPC limits: Use `./scripts/eks/check-vpc-usage.sh` before deployment
- Region config: Scripts read region from `kubernetes/terraform/eks/terraform.tfvars`
- Authentication: `aws sts get-caller-identity` must succeed
- IAM permissions: Ensure EKS/EC2/VPC permissions configured

**Azure/AKS:**
- Subscription detection: Scripts check `AZURE_SUBSCRIPTION_ID` environment variable
- Resource quotas: Request GPU quota increase before deployment (160 vCPUs for NC16as_T4_v3)
- Region config: Scripts read from `kubernetes/terraform/aks/terraform.tfvars`
- Authentication: `az account show` must succeed (use `az login`)
- Service principal: Ensure client ID/secret configured in terraform.tfvars

**All Platforms:**
- Context management: `kubectl config current-context`
- Kubeconfig: Auto-configured by deployment scripts
- CLI validation: Scripts check for required CLI tools (aws/az/gcloud)

## GPU Configuration

### Docker GPU Requirements
- NVIDIA GPU with Docker GPU runtime
- Ubuntu 22.04 recommended
- NVIDIA drivers 580+ (latest recommended)
- CUDA 12.4+ support

### Kubernetes GPU Management
- **GPU Operator**: Handles automatic driver installation
- **Driver Selection**: 575+ (production tested) or 580+ (latest + required for 5xxx GPUs)
- **Time-Slicing Configuration**: All settings in `kubernetes/values/renny-values.yaml`
  - `gpuTimeSlicing.replicasPerGpu`: How many pods share 1 GPU (default: 2)
  - `deployment.totalReplicas`: Total pods to deploy (must be multiple of replicasPerGpu)
  - ConfigMap automatically generated by deploy.sh from renny-values.yaml
  - **No separate gpu-time-slicing-config.yaml needed**
- **Ubuntu EKS AMIs**: Optimized for Vulkan/graphics workloads

## Monitoring and Logging

### Docker Monitoring
- Grafana: http://localhost:3001 (admin/admin)
- Prometheus: http://localhost:9090
- Container logs via `./miniprem.sh logs`

### Kubernetes Monitoring
- **CloudWatch Logs**: Automatic application log aggregation
- **kubectl**: Real-time pod and resource monitoring  
- **GPU Operator**: NVIDIA driver and utilization monitoring
- **EKS Console**: Cluster health and node status

## Security Notes

- All GPU nodes deployed in private subnets
- Network policies configured for WebRTC/TURN traffic
- Kubernetes secrets for credential management
- IRSA for pod-level AWS permissions
- Docker registry authentication required for UneeQ images

## Workflow Modes: Plan vs Build

### Default Mode: PLAN MODE 📋

**You start every conversation in PLAN MODE** unless explicitly told otherwise. In plan mode:

- **Use Sonnet 4.5** (main session) for strategic thinking, architecture, and analysis
- **Focus on understanding** requirements, exploring options, and designing solutions
- **Use agents sparingly** - only for specialized planning tasks (system-architect, prd-writer)
- **Don't implement** until the plan is approved

### Switching to BUILD MODE 🔨

When user says `/build-mode` or "let's build this", switch to build mode:

1. **You become the orchestrator** (Sonnet 4.5) coordinating Haiku agents
2. **All implementation work** goes to Haiku 4.5 specialist agents
3. **Delegate aggressively** - spawn multiple agents in parallel for:
   - Code writing (Python, TypeScript, React, etc.)
   - Testing (Playwright, pytest, API testing)
   - UI design and component creation
   - Backend development and APIs
   - Documentation updates

4. **Your orchestrator responsibilities**:
   - Break down tasks for parallel execution
   - Launch multiple Haiku agents simultaneously
   - Review outputs and coordinate integration
   - Handle complex reasoning yourself (Sonnet)
   - Use TodoWrite to track all agent tasks

5. **Stay in build mode** until user says `/plan-mode` or "done building"

### Model Assignment by Agent Type

**Sonnet 4.5 (Strategic/Coordination):**
- Main session planning and architecture
- Orchestrator coordination in build mode
- Research agents: system-architect, nextjs-expert, chatgpt-expert, shadcn-expert
- Context-manager coordination

**Haiku 4.5 (Implementation/Execution):**
- All implementation agents in `.claude/agents/implementation/`
- python-backend-dev, playwright-tdd-expert, react-typescript-specialist
- api-backend-tester, api-frontend-tester, bash-validator
- ui-designer, ui-visual-validator, prd-writer

### Quick Commands

- `/build-mode` - Enter build mode, delegate all tasks to Haiku agents
- `/plan-mode` - Return to planning mode, use Sonnet for strategy

## Testing Methodology & Agents

### Test-Driven Development with Playwright

**Primary Testing Framework**: Playwright MCP integration for visual, browser-based testing
- **Frontend Testing**: Use `playwright-tdd-expert` agent for all React/Next.js component and e2e testing
- **API Testing**: Use `api-frontend-tester` agent for direct backend API validation with curl
- **Testing Hierarchy**: Playwright (primary) → curl-based testing (secondary)

### MiniPrem Monitor Testing Workflow

**TDD Process**:
1. **RED**: Write failing Playwright tests describing desired functionality
2. **GREEN**: Implement minimal code to make tests pass
3. **REFACTOR**: Improve code quality while maintaining test success
4. **VISUAL**: Use `npm run test:headed` for interactive debugging

**Test Categories**:
- **Component Tests**: Individual React component functionality with data-testid selectors
- **Visual Regression**: Screenshot comparison for UI consistency (`npm run test:visual`)
- **Performance Tests**: Core Web Vitals and load time benchmarks
- **Integration Tests**: API integration and WebSocket connections
- **E2E Tests**: Full user journey validation
- **Responsive Tests**: Mobile and cross-browser compatibility

**Visual Testing Key Lessons**:
- First run requires `npm run test:visual-update` to create baselines
- Mask dynamic content: `[data-testid="connection-id"]`, animations
- Threshold 0.3 handles minor rendering differences
- Wait for layout stabilization before screenshots

**Threshold for agent use: If a task has 3+ steps or spans multiple files, use an agent.**

**When to work directly (without agents):**
- Single-line edits to files already in context
- Running single bash commands (git, docker, kubectl)
- Reading individual files
- Trivial changes that don't require research or analysis

### Specific Agent Guidelines

**Use `playwright-tdd-expert` PROACTIVELY for**:
- Frontend component testing and validation
- Browser automation and user interaction testing
- Visual debugging and screenshot capture
- TDD workflow implementation
- Cross-browser and responsive testing

**Use `api-frontend-tester` for**:
- Direct backend API endpoint testing
- Performance and load testing with curl
- API contract validation
- Network and security header testing

**Use `python-backend-dev` for**:
- FastAPI backend development
- Data processing pipelines
- Python testing with pytest
- Type-safe Python implementations with Google-style docs

**Configuration**:
- Frontend runs on port 3001 (avoid conflicts with port 3000)
- Playwright config automatically handles server startup
- Visual mode available for debugging and demonstration

# Using Gemini CLI for Large Codebase Analysis

**See**: `.claude/agents/shared/gemini-cli-reference.md` for complete Gemini CLI usage patterns and examples.

All agents must use Gemini CLI proactively for large research tasks that exceed context limits or involve analyzing entire codebases.