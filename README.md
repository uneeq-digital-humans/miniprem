# MiniPrem Platform

![MiniPrem Logo](docs/images/logo.png)

> A comprehensive digital human platform with LLM integration, real-time facial animation, and monitoring capabilities.

## Overview

MiniPrem is an integrated platform that combines a digital human interface (Renny) with LLM capabilities (vLLM), workflow automation (Flowise), and comprehensive monitoring tools (Prometheus + Grafana). This setup allows you to deploy and manage advanced AI interactions through a virtual human interface.

## Features

- **Digital Human Interface**: Powered by Renny, with real-time facial animation
- **LLM Integration**: vLLM running Gemma3 for natural language understanding
- **Workflow Automation**: Flowise for building and managing AI workflows
- **Metrics & Monitoring**: Prometheus and Grafana for real-time performance tracking
- **Queue Management**: Redis for reliable message processing
- **RIME AI**: High-quality text-to-speech via a simple API
- **Whisper**: OpenAI's speech recognition for accurate audio transcription

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
   cd miniprem-2025
   ```

2. Run the installation script:

   ```bash
   ./install_miniprem.sh
   ```

   The installer will prompt you to select either a **Default Install** (Renny + Audio2Face only) or a **Full Install** (all services: Renny, Audio2Face, Flowise, vLLM, Grafana, Prometheus, RIME, etc.).

   You can re-run the installer at any time to upgrade from Default to Full, or to change your selection.

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
| vLLM API | http://localhost:8000 | N/A |
| Renny Health | http://localhost:8081/health | N/A |
| Log Viewer | http://localhost:8082 | N/A |
| RIME API | http://localhost:8100 | Requires API Key |

### Using Flowise

1. Access Flowise at http://localhost:3000
2. Log in with the default credentials (user / password)
3. Navigate to the pre-configured chatflow for interacting with the vLLM LLM
4. Test the chatflow by sending messages through the chat interface

### Testing vLLM API with cURL

You can test the vLLM API directly with a cURL command:

```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gemma-3-4b",
    "messages": [
      { "role": "user", "content": "Hello!" }
    ]
  }'
```

### Monitoring with Grafana

1. Access Grafana at http://localhost:3001
2. Log in with the default credentials (admin / admin)
3. Navigate to Dashboards to view the pre-configured Flowise monitoring dashboard
4. Create custom dashboards as needed to monitor specific metrics

### Using RIME AI (Text-to-Speech)

RIME provides high-quality text-to-speech via a simple API. You must supply your RIME API key in the Authorization header.

**Example: JSON response**
```bash
curl -X POST "http://localhost:8100" \
  -H "Authorization: Bearer <API KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "I would love to have a conversation with you. The new model is out.",
    "speaker": "joy",
    "modelId": "mist"
  }' -o result_mist.txt
```

**Example: MP3 response**
```bash
curl -X POST "http://localhost:8100" \
  -H "Authorization: Bearer <API KEY>" \
  -H "Content-Type: application/json" \
  -H "Accept: audio/mp3" \
  -d '{
    "text": "I would love to have a conversation with you.",
    "speaker": "joy",
    "modelId": "mist"
  }' -o result.mp3
```

**Example: PCM response**
```bash
curl -X POST "http://localhost:8100" \
  -H "Authorization: Bearer <API KEY>" \
  -H "Content-Type: application/json" \
  -H "Accept: audio/pcm" \
  -d '{
    "text": "I would love to have a conversation with you.",
    "speaker": "joy",
    "modelId": "mist"
  }' -o result.pcm
```

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

# Run Flowise chatflow setup (only available in Full Install)
./miniprem.sh setup
```

The services started will depend on your installation type (Default or Full) as specified during installation. The installation type is saved in the `.miniprem_install_type` file. To switch between installation types, simply run the installer again and select a different option.

### Default Install Services
* Renny (Digital Human)
* Audio2Face (Facial Animation)

### Full Install Services
* All services in Default Install, plus:
* Flowise (Workflow Automation) 
* vLLM (LLM Inference)
* Prometheus (Metrics Collection)
* Grafana (Monitoring Dashboard)
* Redis (Queue Management)
* RIME (Text-to-Speech API)
* Log Streamer (Container Log Viewer)

## Docker Configuration

MiniPrem uses two main Docker Compose files:

* `docker/docker-compose.default.yml` - Used for Default Install (Renny + Audio2Face only)
* `docker/docker-compose.yml` - Used for Full Install (all services)

The appropriate file is automatically selected based on your installation type.

## Docker Basics

This section covers essential Docker commands that will help you manage and monitor your MiniPrem installation.

### Checking Docker Status

Verify that Docker is running:
```bash
docker info
```

### Managing Containers

List all running containers:
```bash
docker ps
```

List all containers (including stopped ones):
```bash
docker ps -a
```

View container logs:
```bash
docker logs <container_name>
```

For example, to view Flowise logs:
```bash
docker logs flowise
```

### Managing Images

List all Docker images:
```bash
docker images
```

Remove unused images:
```bash
docker image prune
```

### Container Health Checks

Check container health:
```bash
docker inspect --format='{{.State.Health.Status}}' <container_name>
```

For example, to check Flowise health:
```bash
docker inspect --format='{{.State.Health.Status}}' flowise
```

### Resource Usage

View container resource usage:
```bash
docker stats
```

### Common Issues

If you encounter issues:

1. Check container status:
   ```bash
   docker ps -a
   ```

2. View container logs:
   ```bash
   docker logs <container_name>
   ```

3. Restart a specific container:
   ```bash
   docker restart <container_name>
   ```

4. Check container health:
   ```bash
   docker inspect <container_name>
   ```

### Useful Tips

- Use `docker-compose` commands in the project directory to manage all services together:
  ```bash
  docker-compose ps    # View all services
  docker-compose logs  # View all logs
  ```

- To view real-time logs with timestamps:
  ```bash
  docker logs -f --timestamps <container_name>
  ```

- To clean up unused resources:
  ```bash
  docker system prune
  ```

Remember that all MiniPrem services are managed through Docker, so these commands will help you monitor and troubleshoot your installation effectively.

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

If the vLLM LLM is slow or unresponsive:

1. Verify GPU availability with `nvidia-smi`
2. Check vLLM logs with `docker logs vllm`
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
- [vLLM Integration](docs/guides/vllm.md)
- [vLLM Official Documentation](https://vllm.readthedocs.io/en/latest/)