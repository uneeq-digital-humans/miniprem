<div align="center">

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

# MiniPrem Platform Documentation

> Comprehensive documentation for the MiniPrem digital human platform

</div>

## Table of Contents

- [Getting Started](#getting-started)
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
- **[Services Overview](guides/services.md)** - Understanding MiniPrem architecture

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
