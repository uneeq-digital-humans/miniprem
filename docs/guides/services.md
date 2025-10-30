<div align="center">

<img src="images/logos/logo-horizontal-color.png" alt="UneeQ Logo" class="logo-light-mode" />
<img src="images/logos/logo-white.png" alt="UneeQ Logo" class="logo-dark-mode" />

# MiniPrem Services Overview

> Understanding the architecture and integration of MiniPrem platform services

</div>

## Table of Contents

- [Core Services](#core-services)
- [Service Architecture](#service-architecture)
- [Service Dependencies](#service-dependencies)
- [Environment Variables](#environment-variables)
- [Volumes](#volumes)
- [Network Configuration](#network-configuration)
- [Service Health Checks](#service-health-checks)
- [License](#license)
- [Copyright](#copyright)

## Core Services

| Service | Purpose | Port | Documentation |
|---------|---------|------|---------------|
| Renny | Digital human avatar | 8081 | [Renny Guide](renny.md) |
| vLLM | Large language model | 8000 | [vLLM Guide](vllm.md) |
| Flowise | Workflow automation | 3000 | [Flowise Guide](flowise.md) |
| Redis | Queue management | 6379 | - |
| Prometheus | Metrics collection | 9090 | [Monitoring Guide](monitoring.md) |
| Grafana | Metrics visualization | 3001 | [Monitoring Guide](monitoring.md) |
| RIME | Text-to-speech API | 8100 | [RIME Guide](rime.md) |
| Whisper | Speech recognition | 9000 | [Whisper Guide](whisper.md) |

## Service Architecture

```
┌─────────────────────────────┐     ┌─────────────┐
│          Renny              │     │   Flowise   │
│   Digital Human with        │     │ Workflow    │
│ Internal Speech Processing  │     │             │
└──────────┬──────────────────┘     └──────┬──────┘
           │                               │
           │                               │
           ▼                               ▼
┌─────────────────────────────────────────────────────┐
│                 Docker Network                      │
└─────────────┬─────────────┬─────────────┬───────────┘
              │             │             │
              ▼             ▼             ▼
    ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
    │   vLLM      │ │    Redis    │ │ Prometheus  │
    │  LLM Engine │ │   Queue     │ │   Metrics   │
    └─────────────┘ └─────────────┘ └──────┬──────┘
                                           │
                                           ▼
                                    ┌─────────────┐
                                    │   Grafana   │
                                    │ Dashboards  │
                                    └─────────────┘
```

## Service Dependencies

- **Renny** depends on:
  - Internal speech processing system (built-in)
  - UneeQ platform for avatar rendering (external)
  - NEW_SPEECH_OVERRIDE environment variable for enhanced speech

- **Flowise** depends on:
  - vLLM for language model capabilities
  - Redis for queue management
  - SQLite for database storage (embedded)

- **Monitoring** depends on:
  - Prometheus for metrics collection
  - Grafana for visualization

## Environment Variables

Each service is configured via environment variables in the Docker Compose file. Key environment variables include:

- **Renny**:
  - `DHOP_ADDRESS`: UneeQ platform address
  - `NEW_SPEECH_OVERRIDE`: Enable internal speech processing (set to 1)
  - `AZURE_REGION` & `AZURE_SPEECH`: Speech service credentials (optional fallback)

- **Flowise**:
  - `DATABASE_TYPE`: Set to SQLite for local database
  - `FLOWISE_USERNAME` & `FLOWISE_PASSWORD`: Authentication credentials
  - `REDIS_HOST` & `REDIS_PORT`: Redis connection details

- **vLLM**:
  - `NVIDIA_VISIBLE_DEVICES`: GPU allocation for model inference

## Volumes

Persistent data is stored in Docker volumes:

- **vllm_data**: Stores downloaded language models
- **flowise_data**: Stores Flowise configurations and database
- **redis_data**: Stores Redis queue data
- **prometheus_data**: Stores metrics history
- **grafana_data**: Stores dashboard configurations

## Network Configuration

Most services use the default Docker network for communication, with these exceptions:

- **Renny** uses `network_mode: "host"` for optimal performance
- Services reference each other by container name (e.g., `http://vllm:8000`) within the Docker network

## Service Health Checks

All services include health checks to ensure they're functioning properly:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:PORT/health"]
  interval: 10s
  timeout: 5s
  retries: 3
```

These health checks are used to coordinate service startup dependencies.

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