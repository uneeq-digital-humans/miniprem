<div align="center">

![UneeQ Logo](https://presales.services.uneeq.io/uneeq-internal/assets/logos/UneeQ+Logo+Horizontal+CMYK.png)

# MiniPrem Monitor

> Professional monitoring dashboard for Docker containers and Kubernetes pods

**Technical Operations Tool for DevOps, SRE, and Platform Teams**

</div>

## Overview

MiniPrem Monitor is a real-time monitoring solution for technical teams managing containerized workloads. Similar to Portainer, it provides a unified dashboard for Docker and Kubernetes environments with live log streaming, resource metrics, and cluster health monitoring.

## Quick Start

### Prerequisites

- Docker Engine 20.10+
- kubectl configured (for Kubernetes monitoring)
- 2GB RAM, 1 CPU core minimum
- Linux, macOS, or Windows with Docker Desktop

### Deployment Options

#### Option 1: Full MiniPrem Stack (Recommended)

Deploy the complete digital human platform with integrated monitoring:

```bash
cd docker
docker-compose up -d
```

**Access:** http://localhost:3001
**Services:** Monitor + Renny + vLLM + Redis + Grafana + Prometheus + Flowise

#### Option 2: Standalone Monitor (Kubernetes Monitoring)

Monitor your EKS/AKS/GKE cluster along with local Docker containers:

```bash
cd docker
docker-compose -f docker-compose.monitor.yml up -d
```

**Access:** http://localhost:3001
**Services:** Monitor only
**Prerequisites:** kubectl configured with cluster access

#### Option 3: Minimal Stack (Renny + Monitor)

Digital human service with monitoring (no AI/LLM services):

```bash
cd docker
docker-compose -f docker-compose.default.yml up -d
```

**Access:** http://localhost:3001
**Services:** Monitor + Renny

## Features

### Real-Time Container Monitoring
- **Live Log Streaming**: Click any container to stream logs in real-time
- **Resource Metrics**: CPU, memory, and network usage per container
- **Container Controls**: Start/stop containers directly from dashboard
- **Auto-Refresh**: WebSocket-based updates (no page refresh needed)

### Kubernetes Cluster Monitoring
- **Pod Status**: Real-time pod health across all namespaces
- **Node Monitoring**: Cluster node status and resource availability
- **Multi-Cluster**: Switch between configured kubectl contexts
- **Live Pod Logs**: Stream logs from any pod

### Professional UI
- **Syntax Highlighting**: Automatic color-coding for log levels (ERROR, WARN, INFO, DEBUG)
- **Dark/Light Mode**: Theme toggle for user preference
- **Responsive Design**: Works on desktop, tablet, and mobile
- **Download Logs**: Export logs to text files for offline analysis

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                       Browser                            │
│                  http://localhost:3001                   │
└──────────────────────┬──────────────────────────────────┘
                       │
                       │ WebSocket + HTTP
                       │
┌──────────────────────▼──────────────────────────────────┐
│              MiniPrem Monitor Container                  │
│                  (Host Network Mode)                     │
│  ┌────────────────┐          ┌─────────────────────┐   │
│  │ Next.js        │◄────────►│ FastAPI Backend     │   │
│  │ Frontend :3001 │  Proxy   │ + WebSocket :8000   │   │
│  └────────────────┘          └─────────┬───────────┘   │
└────────────────────────────────────────┼───────────────┘
                                          │
                    ┌─────────────────────┼─────────────────────┐
                    │                     │                     │
                    ▼                     ▼                     ▼
        ┌───────────────────┐ ┌──────────────────┐ ┌──────────────────┐
        │ Docker Socket     │ │ kubectl          │ │ System Metrics   │
        │ /var/run/docker.. │ │ ~/.kube/config   │ │ CPU/RAM/Disk     │
        └───────────────────┘ └──────────────────┘ └──────────────────┘
```

### Networking Architecture

**Host Network Mode** - The monitor uses Docker's host networking (`network_mode: host`) for optimal performance and direct system access:

**Why Host Networking?**
- ✅ **Direct Docker Socket Access**: No network bridge overhead for container monitoring
- ✅ **Kubernetes Context Access**: Seamless kubectl integration with host's kubeconfig
- ✅ **Zero Port Mapping Overhead**: Services bind directly to host ports
- ✅ **Simplified Configuration**: No complex port forwarding or NAT

**Port Bindings:**
- **Frontend**: Binds directly to host port **3001** (accessible at http://localhost:3001)
- **Backend**: Binds directly to host port **8000** (internal API, not exposed externally)
- **No Port Mapping Required**: With host networking, the `ports:` directive in docker-compose is ignored

**Service Communication:**
- Frontend proxies API requests to backend on localhost:8000
- WebSocket connections established directly between browser and backend
- All services share the host's network namespace

**Security Features:**
- **Single Container**: Frontend and backend run together via supervisord
- **Read-Only Socket**: Security-hardened with read-only Docker socket mount
- **No New Privileges**: Container runs with `no-new-privileges:true` security option
- **Command Whitelisting**: Only approved Docker/kubectl commands are executed

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MONITOR_MODE` | Deployment mode (`full_stack`, `standalone`, `default`) | `full_stack` |
| `LOG_LEVEL` | Logging level (`debug`, `info`, `warn`, `error`) | `info` |
| `BACKEND_PORT` | Internal backend port | `8000` |
| `FRONTEND_PORT` | External frontend port | `3001` |

### Port Bindings (Host Network Mode)

| Service | Port | Access | Description |
|---------|------|--------|-------------|
| Frontend | 3001 | **Public** | Main dashboard - http://localhost:3001 |
| Backend | 8000 | **Internal** | API & WebSocket (proxied by frontend) |

**Note**: With host networking, services bind directly to host ports. No port mapping (e.g., `3001:3001`) is needed or used.

### Docker Socket

The monitor requires access to the Docker socket for container monitoring:

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro  # Read-only mount
```

**Security Note:** Docker socket access provides container management capabilities. The monitor uses a read-only mount and whitelists only safe commands (ps, logs, stats).

### Kubernetes Configuration

For Kubernetes monitoring, mount your kubectl config:

```yaml
volumes:
  - ~/.kube:/root/.kube:ro  # Read-only mount
```

The monitor automatically detects available clusters and allows context switching.

## Security

### Command Whitelisting
Only pre-approved Docker and kubectl commands are allowed:
- `docker ps`, `docker logs`, `docker stats`
- `kubectl get pods`, `kubectl get nodes`, `kubectl logs`

### Input Validation
All container/pod names are validated against strict regex patterns to prevent injection attacks.

### Read-Only Mounts
Both Docker socket and kubectl config are mounted read-only where possible.

### Network Architecture
Uses `host` network mode for optimal performance and direct system access:
- Direct Docker socket access without bridge overhead
- Seamless Kubernetes kubectl integration
- Services bind directly to host ports (3001, 8000)
- Maintains `no-new-privileges` security option

## Troubleshooting

### Monitor Not Starting

**Check Docker build:**
```bash
docker build -t miniprem-monitor:test miniprem-monitor/
docker images | grep miniprem-monitor
```

**Check container logs:**
```bash
docker logs miniprem-monitor
```

### No Containers Visible

**Verify Docker socket access:**
```bash
docker exec miniprem-monitor ls -l /var/run/docker.sock
```

**Test Docker command inside container:**
```bash
docker exec miniprem-monitor docker ps
```

### Kubernetes Monitoring Not Working

**Verify kubectl config:**
```bash
docker exec miniprem-monitor kubectl config get-contexts
docker exec miniprem-monitor kubectl cluster-info
```

**Check AWS credentials (for EKS):**
```bash
# On host, refresh credentials
aws sso login
aws eks update-kubeconfig --region us-east-1 --name your-cluster
```

### Log Streaming Not Working

**Check WebSocket connection:**
- Open browser Developer Tools → Network tab
- Look for WebSocket connection to `ws://localhost:8000/ws`
- Check for any connection errors

**Verify backend health:**
```bash
curl http://localhost:8000/health
```

### Port Conflicts

If port 3001 is already in use:

```bash
# Find process using port 3001
lsof -i :3001

# Stop the conflicting service or choose a different port
```

## Development (For Contributors)

If you're modifying the MiniPrem Monitor code:

### Local Development Setup

**Backend:**
```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python run.py  # Runs on port 8000
```

**Frontend:**
```bash
cd frontend
npm install
npm run dev  # Runs on port 3500
```

### Testing

**Run Playwright tests:**
```bash
cd frontend
npm run test          # All tests
npm run test:headed   # Visual mode
npm run test:ui       # Interactive UI
```

### Building Docker Image

```bash
cd miniprem-monitor
docker build -t miniprem-monitor:dev .
```

## Project Structure

```
miniprem-monitor/
├── backend/                 # FastAPI backend
│   ├── app/
│   │   ├── security/        # Command execution and validation
│   │   ├── websocket/       # WebSocket connection management
│   │   ├── models/          # Pydantic data models
│   │   ├── services/        # System monitoring services
│   │   └── main.py         # FastAPI application
│   └── requirements.txt
├── frontend/               # Next.js frontend
│   ├── src/
│   │   ├── app/            # Next.js 13+ app directory
│   │   ├── components/     # React components
│   │   ├── hooks/          # Custom React hooks
│   │   └── types/          # TypeScript type definitions
│   └── package.json
├── Dockerfile              # Multi-stage build
├── docker-entrypoint.sh    # Container startup script
├── supervisord.conf        # Process manager config
└── README.md
```

## Deployment Scenarios

### Scenario 1: Complete Platform Team
**Use Case:** Full digital human platform for customer demos
**Command:** `docker-compose up -d`
**Services:** All MiniPrem services + monitoring
**Best For:** Internal demos, development, testing

### Scenario 2: Platform Operations Team
**Use Case:** Monitor production Kubernetes cluster + local dev containers
**Command:** `docker-compose -f docker-compose.monitor.yml up -d`
**Services:** Monitor only
**Best For:** Production monitoring, SRE teams

### Scenario 3: DevOps Team
**Use Case:** Minimal footprint with just Renny and monitoring
**Command:** `docker-compose -f docker-compose.default.yml up -d`
**Services:** Renny + Monitor
**Best For:** Resource-constrained environments

## License

This monitoring dashboard is part of the MiniPrem platform.

---

## Copyright

<div align="center">

**© 2025 UneeQ. All rights reserved.**

![UneeQ Logo](https://presales.services.uneeq.io/uneeq-internal/assets/logos/UneeQ+Logo+Horizontal+CMYK.png)

**Digital Humans. Unlimited Possibilities.**

[www.digitalhumans.com](https://www.digitalhumans.com) | [support@digitalhumans.com](mailto:support@digitalhumans.com)

</div>
