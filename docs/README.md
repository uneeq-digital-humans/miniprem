<div align="center">

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

# MiniPrem Platform Documentation

> Comprehensive documentation for the MiniPrem digital human platform

</div>

## Table of Contents

- [Getting Started](#getting-started)
- [CLI Reference](#cli-reference)
- [Guides](#guides)
- [API Documentation](#api-documentation)
- [Troubleshooting](#troubleshooting)

## Getting Started

New to MiniPrem? Choose your deployment option:

### Deployment Options

MiniPrem supports two deployment architectures to match your needs:

| Deployment | Best For | Setup Time | Scale | Cost |
|-----------|----------|------------|-------|------|
| **[Docker (Local)](guides/getting-started.md)** | Development, demos, testing | 5-10 minutes | 1-5 instances | $100-500/mo |
| **[Kubernetes/EKS](guides/kubernetes.md)** | Production, enterprise | 30-45 minutes | 10-20+ instances | $9,000+/mo |

**Start Here:**
- **[Getting Started Guide](guides/getting-started.md)** - Docker installation and initial setup
- **[Kubernetes/EKS Deployment](guides/kubernetes.md)** - Production-ready infrastructure with auto-scaling
- **[CNS Deployment Guide](CNS-DEPLOYMENT-GUIDE.md)** - On-premises NVIDIA GPU deployment
- **[Services Overview](guides/services.md)** - Understanding MiniPrem architecture

## CLI Reference

The `./miniprem.sh` script is the primary management tool for MiniPrem. It automatically detects whether you have a Docker or CNS (Kubernetes) installation and provides appropriate commands.

### Common Commands (All Deployments)

| Command | Description |
|---------|-------------|
| `./miniprem.sh start` | Start MiniPrem services |
| `./miniprem.sh stop` | Stop MiniPrem services |
| `./miniprem.sh restart` | Restart MiniPrem services |
| `./miniprem.sh status` | Check service status |
| `./miniprem.sh logs` | View service logs |
| `./miniprem.sh upgrade` | Full upgrade (git pull + image pull + rebuild) |
| `./miniprem.sh --help` | Show all available commands |

### Docker-Specific Commands

For Docker (local) installations:

```bash
# Full upgrade - pulls latest code and images
./miniprem.sh upgrade

# Git pull only (no docker pull)
./miniprem.sh pull

# Setup Flowise chatflow
./miniprem.sh setup

# Custom services management
./miniprem.sh custom list
./miniprem.sh custom add postgres
```

### CNS (Kubernetes) Commands

For CNS on-premises installations:

```bash
# Apply configuration changes from values file
sudo ./miniprem.sh upgrade

# Just restart pods (no config change)
sudo ./miniprem.sh upgrade --restart

# Clear TTS secrets (use Admin Portal config instead)
sudo ./miniprem.sh upgrade --clear-secrets

# Change replica count
sudo ./miniprem.sh upgrade --replicas 5

# Interactive GPU-aware scaling
sudo ./miniprem.sh scale

# Quick scale (just kubectl scale)
sudo ./miniprem.sh scale-quick 4

# GPU capacity calculator
sudo ./miniprem.sh sizer
```

> **Note:** CNS commands require `sudo` or membership in the `microk8s` group.

### Upgrade Details

The `upgrade` command works differently based on your deployment type:

**Docker Upgrade:**
1. Backs up config files (credentials, terraform vars, etc.)
2. Pulls latest code from git
3. Restores config files (preserves your credentials)
4. Pulls latest Renny image from Harbor
5. Rebuilds MiniPrem Monitor locally
6. Tells you to restart manually

**CNS Upgrade:**
1. Loads saved credentials from `.cns_config`
2. Runs `helm upgrade` with your values file
3. Restarts pods to apply changes

## Guides

Detailed guides for each component:

- **[Renny Integration](guides/renny.md)** - Digital human configuration and management
- **[Flowise Configuration](guides/flowise.md)** - Workflow automation setup
- **[vLLM Integration](guides/vllm.md)** - Large language model configuration
- **[Monitoring Guide](guides/monitoring.md)** - Prometheus and Grafana setup
- **[RIME Guide](guides/rime.md)** - Text-to-speech API integration
- **[Whisper Guide](guides/whisper.md)** - Speech recognition configuration

## API Documentation

Technical API references:

- **[Health Check API](api/health.md)** - Service health monitoring endpoints
- **[Container Logs API](api/container-logs.md)** - Docker container log access

## Troubleshooting

Having issues? Check our troubleshooting resources:

- **[Troubleshooting Guide](troubleshooting.md)** - Common problems and solutions
- **Docker Issues**: Check container logs with `docker logs <container_name>`
- **GPU Issues**: Verify GPU with `nvidia-smi`
- **Service Issues**: Run `./miniprem.sh status` for service health

## Additional Resources

- **[Main README](../README.md)** - Project overview and quick start
- **[Kubernetes Deployment](../kubernetes/README.md)** - Production EKS deployment guide
- **[MiniPrem Monitor](../miniprem-monitor/README.md)** - Real-time monitoring dashboard

## Contributing

For documentation improvements:
1. Follow existing markdown formatting
2. Include code examples where relevant
3. Keep explanations concise and clear
4. Test all commands before documenting

---

## License

This documentation is part of the MiniPrem platform, licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.

---

## Copyright

<div align="center">

**© 2025 UneeQ. All rights reserved.**

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

**Digital Humans. Unlimited Possibilities.**

[www.digitalhumans.com](https://www.digitalhumans.com) | [support@digitalhumans.com](mailto:support@digitalhumans.com)

</div>
