# Getting Started

This guide will help you install and configure the MiniPrem platform on your system.

## Prerequisites

Before you begin, ensure you have the following:

- **Hardware Requirements**:
  - NVIDIA GPU with at least 8GB VRAM (16GB+ recommended)
  - 16GB+ RAM
  - 50GB+ free disk space

- **Software Requirements**:
  - Ubuntu 20.04 LTS or newer
  - NVIDIA drivers (minimum version 470.xx)
  - Docker and Docker Compose
  - NVIDIA Container Toolkit

## Installation

### 1. Clone the Repository

```bash
git clone https://gitlab.com/tgmerritt/miniprem-2025.git
cd miniprem
```

### 2. Run the Installation Script

```bash
./install_miniprem.sh
```

The script will:
- Check for required software and dependencies
- Install any missing prerequisites
- Prompt for configuration values
- Set up the Docker containers
- Configure the system

### 3. Configuration Values

You'll need the following information during installation:

| Configuration         | Description                                 | Example                                      |
|-----------------------|---------------------------------------------|----------------------------------------------|
| UneeQ Platform Address | Address of the UneeQ signaling service      | api.uneeq.io                                 |
| UneeQ Platform API Key | API key for UneeQ platform                  | your_uneeq_api_key_here                      |
| Tenant ID             | Your UneeQ tenant identifier                | your_tenant_id_here                          |
| Azure Region          | Azure region for speech services            | your_azure_region                            |
| Azure Speech Key      | Azure speech service API key                | your_azure_speech_key_here                   |
| Renny Image           | Docker image for Renny digital human        | facemeproduction/renny:latest                |

### 4. Verify Installation

After installation completes, verify that all services are running:

```bash
./miniprem.sh status
```

You should see all containers running and healthy.

## Managing the Platform

### Starting Services

```bash
./miniprem.sh start
```

### Stopping Services

```bash
./miniprem.sh stop
```

### Viewing Logs

```bash
./miniprem.sh logs
```

You can also view logs for a specific service:

```bash
./miniprem.sh logs renny
./miniprem.sh logs flowise
./miniprem.sh logs vllm
```

### Restarting Services

```bash
./miniprem.sh restart
```

## Next Steps

Once your MiniPrem platform is up and running, proceed to:

1. [Configure Flowise](flowise.md) to set up your conversation flows
2. [Monitor Performance](monitoring.md) using Grafana dashboards
3. [Customize Renny](renny.md) for your specific use case