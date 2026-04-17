# Docker Deployment Guide

## Overview

MiniPrem's Docker deployment provides a complete local development environment with all necessary services containerized for easy setup and management. This guide covers the Docker-specific deployment process, configuration, and management.

## Prerequisites

- Docker Desktop installed (macOS/Windows) or Docker Engine (Linux)
- Docker Compose v2.0+
- Harbor registry credentials (robot account for `cr.uneeq.io`)
- NVIDIA GPU with Docker GPU runtime (for GPU acceleration)
- Minimum 16GB RAM
- 50GB available disk space
- Network access to `cr.uneeq.io` on port 443 (HTTPS)

!> **Docker Desktop (macOS/Windows) does NOT support GPU acceleration for MiniPrem.** GPU-accelerated services (Renny, vLLM, RIVA) require native Ubuntu with Docker Engine and the NVIDIA Container Toolkit. Docker Desktop is suitable only for non-GPU services.

## Container Registry Access

### Harbor Registry Requirement

MiniPrem container images are hosted on the private Harbor registry at `cr.uneeq.io`. Before deploying MiniPrem, you must authenticate with this registry using your Harbor robot account credentials.

For detailed information about Harbor registry access, including troubleshooting steps and enterprise firewall configuration, see the [Harbor Registry Guide](harbor-registry.md).

### Quick Registry Authentication

Authenticate with the Harbor registry before starting services:

```bash
# Log in with your robot account credentials
docker login https://cr.uneeq.io --username 'robot$your-customer-name'

# When prompted, enter your Harbor password/token
```

**Expected Output**:
```
Password:
Login Succeeded
```

### Network Requirements

Ensure your firewall allows outbound connections to the Harbor registry:

- **Registry Endpoint**: `cr.uneeq.io:443`
- **Protocol**: HTTPS (TLS 1.2+)
- **Direction**: Outbound

For enterprise/corporate networks with strict firewall rules, ensure your network administrator has whitelisted `cr.uneeq.io` on port 443.

### Credential Management

Docker automatically encrypts and stores your Harbor registry credentials in `~/.docker/config.json`. For production deployments, ensure:

- Credentials are stored securely
- Credential files are not committed to version control
- Access credentials are rotated regularly

## Installation Types

MiniPrem offers three installation profiles:

### 1. Default Installation
Includes Renny digital human and MiniPrem Monitor:
```bash
./docker/scripts/install_miniprem.sh
# Select "default" when prompted
```

### 2. Full Installation
Complete AI stack with all services:
```bash
./docker/scripts/install_miniprem.sh
# Select "full" when prompted
```

Includes:
- Renny digital human renderer
- vLLM inference server
- Flowise workflow automation
- MiniPrem Monitor dashboard
- Grafana/Prometheus monitoring
- Redis message queue
- RIME text-to-speech
- Whisper speech recognition

### 3. Monitor Only
Standalone monitoring for existing deployments:
```bash
cd docker/
docker compose -f docker-compose.monitor.yml up -d
```

## Quick Start

### Harbor Authentication (Required First Step)

Before running any installation, authenticate with the Harbor registry:

```bash
# Authenticate with Harbor registry
docker login https://cr.uneeq.io --username 'robot$your-customer-name'

# Enter your Harbor password/token when prompted
```

Once authenticated, you can proceed with installation.

### Interactive Installation

The easiest way to get started:

```bash
# Run interactive installer
./docker/scripts/install_miniprem.sh

# Follow prompts to:
# 1. Choose installation type (default/full)
# 2. Configure UneeQ credentials
# 3. Set up services
```

### Manual Installation

For more control over the process:

```bash
# 1. Configure UneeQ credentials
cat > docker/configuration.dat << EOF
{
  "customerJWT": "your-jwt-token",
  "tokenIssuer": "your-issuer-url",
  "tokenIssuerPublicKey": "your-public-key"
}
EOF

# 2. Start services
./miniprem.sh start

# 3. Verify deployment
./miniprem.sh status
```

## Service Management

### Using miniprem.sh Script

The main management script provides convenient commands:

```bash
# Start all services
./miniprem.sh start

# Stop all services
./miniprem.sh stop

# Check service status
./miniprem.sh status

# View logs
./miniprem.sh logs

# Restart services
./miniprem.sh restart

# Initial setup
./miniprem.sh setup
```

### Direct Docker Compose Commands

For fine-grained control:

```bash
# Start specific service
docker compose -f docker/docker-compose.yml up -d renny

# View service logs
docker compose -f docker/docker-compose.yml logs -f flowise

# Restart service
docker compose -f docker/docker-compose.yml restart vllm

# Scale services (if supported)
docker compose -f docker/docker-compose.yml up -d --scale renny=2
```

## Configuration Files

### Key Configuration Locations

| File | Purpose |
|------|---------|
| `docker/configuration.dat` | UneeQ platform credentials |
| `docker/docker-compose.yml` | Default services definition |
| `docker/docker-compose.full.yml` | Full installation services |
| `docker/docker-compose.monitor.yml` | Monitor-only deployment |
| `.miniprem_install_type` | Current installation profile |
| `.env` | Environment variables (if exists) |

### Environment Variables

Create a `.env` file for custom configuration:

```bash
# GPU Configuration
NVIDIA_VISIBLE_DEVICES=0
CUDA_VISIBLE_DEVICES=0

# Service Ports
FLOWISE_PORT=3000
MONITOR_PORT=3001
GRAFANA_PORT=3002

# Resource Limits
RENNY_MEMORY_LIMIT=4g
VLLM_MEMORY_LIMIT=8g

# Debug Options
DEBUG_MODE=false
LOG_LEVEL=info
```

## Port Mappings

| Service | Default Port | Description |
|---------|--------------|-------------|
| Flowise UI | 3000 | Workflow automation interface |
| MiniPrem Monitor | 3001 | Container monitoring dashboard |
| Grafana | 3002 | Metrics visualization |
| vLLM API | 8000 | LLM inference endpoint |
| Renny Health | 8081 | Digital human health check |
| RIME API | 8100 | Text-to-speech service |
| Prometheus | 9090 | Metrics collection |
| Whisper API | 9000 | Speech-to-text service |
| Redis | 6379 | Message broker |

## Multiple Renny Instances

To run multiple Renny containers simultaneously, see the [Multiple Renny Setup Guide](README_SETUP_MULTIPLE.md).

Key points:
- Each instance needs unique ports
- Configure via environment variables
- Use docker-compose scaling or separate configurations

## GPU Configuration

### NVIDIA GPU Setup

1. **Install NVIDIA Docker runtime**:
```bash
# Ubuntu/Debian
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt-get update && sudo apt-get install -y nvidia-docker2
sudo systemctl restart docker
```

2. **Verify GPU access**:
```bash
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
```

?> **Driver version matters.** Not all 580.x driver sub-versions work correctly with MiniPrem. See the [NVIDIA Driver Guide](nvidia-drivers.md) for recommended versions and known issues.

3. **Configure GPU for services**:
```yaml
# In docker-compose.yml
services:
  renny:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

## Monitoring

### MiniPrem Monitor

Access the monitoring dashboard at http://localhost:3001

Features:
- Real-time container status
- CPU/Memory/Disk/Network metrics
- Container control (start/stop)
- Live performance graphs
- Automatic insights and recommendations

### Grafana Dashboard

For detailed metrics (full installation only):
- URL: http://localhost:3002
- Default credentials: admin/admin
- Pre-configured dashboards for all services

## Troubleshooting

### Common Issues

1. **Services won't start**:
```bash
# Check logs
docker compose -f docker/docker-compose.yml logs

# Verify Docker daemon
docker ps

# Check disk space
df -h
```

2. **GPU not detected**:
```bash
# Verify NVIDIA runtime
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi

# Check Docker GPU configuration
docker info | grep nvidia
```

3. **Port conflicts**:
```bash
# Find process using port
lsof -i :3000

# Change port in docker-compose.yml or .env
```

4. **Permission issues**:
```bash
# Fix Docker socket permissions
sudo chmod 666 /var/run/docker.sock

# Add user to docker group
sudo usermod -aG docker $USER
```

### Viewing Logs

```bash
# All services
docker compose -f docker/docker-compose.yml logs

# Specific service
docker logs miniprem-renny

# Follow logs
docker logs -f miniprem-monitor

# Last 100 lines
docker logs --tail 100 miniprem-flowise
```

## Updating Services

### Pull Latest Images

Before pulling updated images, ensure you are authenticated with the Harbor registry:

```bash
# Verify Harbor authentication
docker login https://cr.uneeq.io --username 'robot$your-customer-name'

# Stop services
./miniprem.sh stop

# Pull updates from Harbor registry
docker compose -f docker/docker-compose.yml pull

# Restart with new images
./miniprem.sh start
```

### Rebuild Containers
```bash
# Force rebuild
docker compose -f docker/docker-compose.yml up -d --build

# Clean rebuild
docker compose -f docker/docker-compose.yml down
docker compose -f docker/docker-compose.yml up -d --build --force-recreate
```

## Backup and Recovery

### Backup Configuration
```bash
# Backup all configuration
tar -czf miniprem-backup-$(date +%Y%m%d).tar.gz \
  docker/configuration.dat \
  .miniprem_install_type \
  .env \
  docker/docker-compose.override.yml
```

### Backup Volumes
```bash
# List volumes
docker volume ls | grep miniprem

# Backup specific volume
docker run --rm -v miniprem_flowise_data:/data \
  -v $(pwd):/backup alpine \
  tar czf /backup/flowise-data.tar.gz /data
```

## Security Considerations

1. **Harbor Registry Credentials**:
   - Store robot account credentials securely
   - Never commit Harbor credentials to version control
   - Credentials are automatically encrypted in `~/.docker/config.json`
   - Rotate credentials periodically as recommended by UneeQ
   - For production, use Kubernetes Secrets instead of local Docker credentials

2. **Credential Management**:
   - Store `configuration.dat` securely
   - Use Docker secrets for production
   - Rotate JWT tokens regularly

3. **Network Security**:
   - Whitelist `cr.uneeq.io:443` in firewalls for production environments
   - Use custom Docker networks
   - Implement firewall rules
   - Enable TLS for external access

4. **Resource Limits**:
   - Set memory/CPU limits in docker-compose.yml
   - Monitor resource usage
   - Implement rate limiting

## Next Steps

- [Configure Flowise workflows](flowise.md)
- [Set up MiniPrem Monitor](miniprem-monitor.md)
- [Deploy Multiple Renny instances](README_SETUP_MULTIPLE.md)
- [Migrate to Kubernetes](../kubernetes-overview.md)

## Support

For issues and support:
- Check [Troubleshooting Guide](../troubleshooting.md)
- Review [Harbor Registry Guide](harbor-registry.md) for container image access issues
- Review [Container Logs](../api/container-logs.md)
- Contact support@digitalhumans.com