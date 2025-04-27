# MiniPrem Platform

![MiniPrem Logo](docs/images/logo.png)

> A comprehensive digital human platform with LLM integration, real-time facial animation, and monitoring capabilities.

## Overview

MiniPrem is an integrated platform that combines a digital human interface (Renny) with LLM capabilities (Ollama), workflow automation (Flowise), and comprehensive monitoring tools (Prometheus + Grafana). This setup allows you to deploy and manage advanced AI interactions through a virtual human interface.

## Features

- **Digital Human Interface**: Powered by Renny, with real-time facial animation
- **LLM Integration**: Ollama running Gemma3 for natural language understanding
- **Workflow Automation**: Flowise for building and managing AI workflows
- **Metrics & Monitoring**: Prometheus and Grafana for real-time performance tracking
- **Queue Management**: Redis for reliable message processing

## Quick Start

### Prerequisites

- Docker and Docker Compose
- NVIDIA GPU with appropriate drivers
- Ubuntu Linux (recommended)
- Required credentials from UneeQ (platform address, API key, tenant ID)
- Azure Speech service credentials (region and API key)

### Installation

1. Clone this repository:
   ```bash
   git clone https://gitlab.com/tgmerritt/miniprem-2025.git
   cd miniprem
   ```

2. Run the installation script:

   ```bash
   ./install_miniprem.sh
   ```

3. The script will prompt you for the following required information:

   - **UneeQ platform address**: The base URL for your UneeQ platform
   - **UneeQ platform API key**: Authentication key provided by UneeQ
   - **Tenant ID**: Your UneeQ tenant identifier
   - **Azure region**: Region for your Azure Speech service (e.g., eastus)
   - **Azure speech key**: Authentication key for Azure Speech service
   - **Renny image name**: Docker image for the Renny digital human

   You can also provide these values directly as command-line arguments:

   ```bash
   ./install_miniprem.sh --platform-address <address> --platform-key <key> --tenant-id <id> --azure-region <region> --azure-speech-key <key> --renny-image <image>
   ```

4. The installation process will:
   - Check system prerequisites
   - Configure required files
   - Verify cloud service connectivity
   - Build and start all required Docker containers
   - Download the Gemma3 LLM model (this may take 5-15 minutes)
   - Set up the initial Flowise chatflow

## Accessing Services

Once installation is complete, you can access the following services:

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| Flowise | http://localhost:3000 | user / password |
| Grafana | http://localhost:3001 | admin / admin |
| Prometheus | http://localhost:9090 | N/A |
| Renny Health | http://localhost:8081/health | N/A |
| Log Viewer | http://localhost:8082 | N/A |

### Using Flowise

1. Access Flowise at http://localhost:3000
2. Log in with the default credentials (user / password)
3. Navigate to the pre-configured chatflow for interacting with the Ollama LLM
4. Test the chatflow by sending messages through the chat interface

### Monitoring with Grafana

1. Access Grafana at http://localhost:3001
2. Log in with the default credentials (admin / admin)
3. Navigate to Dashboards to view the pre-configured Flowise monitoring dashboard
4. Create custom dashboards as needed to monitor specific metrics

## Managing MiniPrem

Use the included `miniprem.sh` script to manage the platform:

```bash
# Start all services
./miniprem.sh start

# Check service status
./miniprem.sh status

# View logs
./miniprem.sh logs

# Stop all services
./miniprem.sh stop

# Restart all services
./miniprem.sh restart

# Run Flowise chatflow setup
./miniprem.sh setup
```

## Troubleshooting

### Docker Authentication Issues

If you encounter Docker authentication errors when pulling images:

1. Ensure you have the correct Docker credentials
2. Contact UneeQ for assistance with accessing their private image repository
3. Run `docker login quay.io` with the credentials provided by UneeQ

### Service Connectivity Issues

If services cannot connect to each other:

1. Check that all containers are running with `docker ps`
2. Verify network connectivity with `docker network inspect uneeq-miniprem_default`
3. Check container logs with `docker logs <container_name>`

### LLM Performance Issues

If the Ollama LLM is slow or unresponsive:

1. Verify GPU availability with `nvidia-smi`
2. Check Ollama logs with `docker logs ollama`
3. Ensure the Gemma3 model was properly downloaded

### Cloud Service Connection Issues

If you cannot connect to UneeQ platform services:

1. Verify your network connection
2. Ensure your API keys are correctly entered
3. Check for any IP restrictions on the UneeQ platform
4. Contact UneeQ support for assistance

## Additional Documentation

For more detailed information, refer to the following guides:

- [Flowise Configuration](docs/guides/flowise.md)
- [Monitoring with Prometheus and Grafana](docs/guides/monitoring.md)
- [Renny Integration](docs/guides/renny.md)