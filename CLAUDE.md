# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Commands

### MiniPrem Management (Docker)
```bash
# Core management script
./miniprem.sh start|stop|status|restart|logs|setup

# Initial installation (interactive)
./install_miniprem.sh

# Setup chatflow after deployment  
./setup-chatflow-post-deployment.sh
```

### Kubernetes/EKS Deployment
```bash
cd kubernetes/

# One-click production deployment (~30-45 min)
./scripts/deploy.sh [--profile <aws-profile>]

# Check deployment status
./scripts/status.sh

# Scale Renny instances (10-20)
./scripts/scale.sh <number>

# Complete cleanup (~15-20 min)
./scripts/destroy.sh

# Emergency cleanup (no confirmations)
./scripts/cleanup.sh
```

### AWS Utilities
```bash
# Check AWS prerequisites and permissions
./scripts/check-aws-prerequisites.sh [--profile <profile>]

# Analyze VPC usage (critical - AWS has VPC limits)
./scripts/check-vpc-usage.sh [--region <region>] [--vpc <vpc-id>]
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
```

## Architecture Overview

MiniPrem is a multi-deployment digital human platform with two main architectures:

### Docker Architecture (Local Development)
- **Renny**: Digital human renderer with internal speech processing (UneeQ integration)
- **vLLM**: LLM inference server (Gemma3/Mistral models)
- **Flowise**: Workflow automation and LLM integration
- **Grafana/Prometheus**: Monitoring and metrics
- **Redis**: Message queuing
- **RIME**: Text-to-speech API service

**Installation Types:**
- `default`: Renny with internal speech processing (basic setup)
- `full`: All services including monitoring and AI stack

### Kubernetes Architecture (Production)
- **EKS Cluster**: Production-ready with auto-scaling
- **GPU Node Groups**: g5.4xlarge instances with NVIDIA A10G GPUs
- **GPU Operator**: Automatic NVIDIA driver installation (575+ or 580+)
- **Multi-AZ**: High availability across 3 availability zones
- **Time-Slicing**: Multiple pods per GPU for cost optimization

## Key Configuration Files

### Docker Configuration
- `docker/docker-compose.yml`: Full install services
- `docker/docker-compose.default.yml`: Default install services  
- `docker/configuration.dat`: UneeQ platform credentials (JSON format)
- `.miniprem_install_type`: Current installation type (default/full)

### Kubernetes Configuration
- `kubernetes/terraform/terraform.tfvars`: Infrastructure settings (region, credentials, scaling)
- `kubernetes/values/renny-values.yaml`: **Single source of truth** for Renny configuration, including:
  - GPU time-slicing settings (`gpuTimeSlicing.replicasPerGpu`)
  - Total replica count (`deployment.totalReplicas`)
  - Per-pod resource limits (CPU, memory, GPU)
  - All application environment variables
- `kubernetes/manifests/`: Kubernetes resource definitions

## Directory Structure

```
miniprem-2025/
├── docker/                 # Docker-based local deployment
│   ├── docker-compose.yml  # Full services stack
│   ├── docker-compose.default.yml  # Basic services
│   └── configuration.dat   # UneeQ credentials
├── kubernetes/             # Production EKS deployment
│   ├── terraform/          # Infrastructure as Code
│   ├── scripts/           # Deployment automation
│   ├── manifests/         # Kubernetes resources
│   └── values/            # Helm chart values
├── scripts/               # Utility scripts (audio, environment)
└── docs/                  # Documentation
```

## Development Workflow

### Docker Development (Local)
1. Run `./install_miniprem.sh` for interactive setup
2. Use `./miniprem.sh start` to launch services
3. Access services at configured ports (Flowise: 3000, Grafana: 3001, etc.)
4. Monitor with `./miniprem.sh logs`

### Kubernetes Development (Production)
1. Configure AWS credentials and `terraform.tfvars`
2. Configure GPU time-slicing in `kubernetes/values/renny-values.yaml`:
   ```yaml
   gpuTimeSlicing:
     replicasPerGpu: 2  # Pods per GPU
   deployment:
     totalReplicas: 4   # Total pods (must be multiple of replicasPerGpu)
   ```
3. Run `./scripts/deploy.sh` for complete deployment
4. Monitor with `./scripts/status.sh`
5. Scale with `./scripts/scale.sh <instances>`
6. Clean up with `./scripts/destroy.sh`

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

### AWS/EKS Issues
- Profile detection: Scripts auto-detect AWS profile/region
- VPC limits: Use `./scripts/check-vpc-usage.sh` before deployment  
- Region config: All scripts read region from `terraform.tfvars`
- Context management: `kubectl config current-context`

## GPU Configuration

### Docker GPU Requirements
- NVIDIA GPU with Docker GPU runtime
- Ubuntu 22.04 recommended
- NVIDIA drivers 545.xx+ 
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

### Agent Usage Policy

**🎯 DEFAULT BEHAVIOR: Use agents proactively for all non-trivial tasks**

**Always use agents for:**
- **Testing tasks**: `playwright-tdd-expert` or `api-backend-tester`
- **Python development**: `python-backend-dev` for backend code, APIs, data processing
- **React/TypeScript**: `typescript-pro` for frontend components and type safety
- **Next.js features**: `nextjs-expert` for App Router, server components, dynamic routes
- **Large searches**: `general-purpose` agent for multi-file codebase analysis
- **Architecture decisions**: `system-architect` for design and planning
- **OpenAI integration**: `chatgpt-expert` for sentiment analysis, prompt engineering
- **Markdown documentation**: `markdown-expert` for README improvements, TOC generation, formatting fixes

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

## Cost Optimization

### Kubernetes Production Costs (us-east-1)
- Base infrastructure: ~$10,840/month (10 Renny instances)
- Scales with instance count (10-20 supported)
- Consider destroying resources during off-hours
- ASG scaling available for manual shutdown/startup

### Cost-Saving Options
- Single NAT gateway vs HA (dev/test)
- Spot instances for non-critical workloads  
- Reserved instances for production
- Time-based scaling automation