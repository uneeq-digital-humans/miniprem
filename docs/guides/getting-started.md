<div align="center">

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

# Getting Started with MiniPrem

> Quick installation and configuration guide for the MiniPrem platform

</div>

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Managing the Platform](#managing-the-platform)
- [Next Steps](#next-steps)
- [License](#license)
- [Copyright](#copyright)

## Prerequisites

Before you begin, ensure you have the following:

- **Hardware Requirements**:
  - NVIDIA GPU with at least 8GB VRAM (16GB+ recommended)
  - 16GB+ RAM
  - 128GB+ free disk space

- **Software Requirements**:
  - Ubuntu 24.04 LTS or newer
  - NVIDIA drivers (version 580+ recommended)
  - Docker and Docker Compose
  - NVIDIA Container Toolkit

- **UneeQ Harbor Registry Access**:
  - Robot account credentials (contact help@uneeq.com)
  - Network access to cr.uneeq.io (port 443)
  - See [Harbor Registry Guide](harbor-registry.md) for detailed setup

## Installation

### 1. Clone the Repository

```bash
git clone https://gitlab.com/tgmerritt/miniprem-2025.git
cd miniprem-2025
```

### 2. Run the Installation Script

```bash
./docker/scripts/install_miniprem.sh
```

The installer will prompt you to select either a **Default Install** (Renny with internal speech processing) or a **Full Install** (all services: Renny, Flowise, vLLM, Grafana, Prometheus, RIME, etc.).
You can re-run the installer at any time to upgrade from Default to Full, or to change your selection.

### 3. Configuration Values

You'll need the following information during installation:

| Configuration         | Description                                 | Example                                      |
|-----------------------|---------------------------------------------|----------------------------------------------|
| UneeQ Platform Address | Address of the UneeQ signaling service      | api.enterprise.uneeq.io                                 |
| UneeQ Platform API Key | API key for UneeQ platform                  | your_uneeq_api_key_here                      |
| Tenant ID             | Your UneeQ tenant identifier                | your_tenant_id_here                          |
| Azure Region          | Azure region for speech services            | your_azure_region                            |
| Azure Speech Key      | Azure speech service API key                | your_azure_speech_key_here                   |
| Renny Image           | Docker image for Renny digital human        | cr.uneeq.io/uneeq/renny-renderer:latest      |
| RIME API Key          | Docker image for RIME text-to-speech        | your_rime_api_key                            |
| Huggingface Token     | Token for access to Huggingface             | your_huggingface_token                       |
| Harbor Robot Username | Robot account username for Harbor registry  | robot$customer-name                          |
| Harbor Robot Password | Robot account password for Harbor registry  | your_robot_password_here                     |

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

1. [Configure Flowise](https://miniprem-2025-6da807.gitlab.io/#/guides/flowise) to set up your conversation flows
2. [Monitor Performance](https://miniprem-2025-6da807.gitlab.io/#/guides/monitoring) using Grafana dashboards
3. [Customize Renny](https://miniprem-2025-6da807.gitlab.io/#/guides/renny) for your specific use case

---

## License

This guide is part of the MiniPrem platform, licensed under the MIT License - see the [LICENSE](../../LICENSE) file for details.

---

## Copyright

<div align="center">

**© 2025 UneeQ. All rights reserved.**

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

**Digital Humans. Unlimited Possibilities.**

[www.digitalhumans.com](https://www.digitalhumans.com) | [support@digitalhumans.com](mailto:support@digitalhumans.com)

</div>