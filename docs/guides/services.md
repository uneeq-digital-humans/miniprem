# MiniPrem Services Overview

The MiniPrem platform consists of several integrated services that work together to provide a comprehensive digital human experience. This guide provides an overview of these services and how they interact.

## Core Services

| Service | Purpose | Port | Documentation |
|---------|---------|------|---------------|
| Renny | Digital human avatar | 8081 | [Renny Guide](renny.md) |
| vLLM | Large language model | 8000 | [vLLM Guide](vllm.md) |
| Flowise | Workflow automation | 3000 | [Flowise Guide](flowise.md) |
| Redis | Queue management | 6379 | - |
| Prometheus | Metrics collection | 9090 | [Monitoring Guide](monitoring.md) |
| Grafana | Metrics visualization | 3001 | [Monitoring Guide](monitoring.md) |
| Audio2Face | Facial animation | 50000, 52000 | [Renny Guide](renny.md) |

## Service Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│    Renny    │◄────┤ Audio2Face  │     │   Flowise   │
│Digital Human│     │ Animation   │     │ Workflow    │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       │                   │                   │
       ▼                   ▼                   ▼
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
  - Audio2Face services for facial animation
  - Azure Speech Services for text-to-speech (external)
  - UneeQ platform for avatar rendering (external)

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
  - `A2F_ADDRESS`: Audio2Face service address
  - `AZURE_REGION` & `AZURE_SPEECH`: Speech service credentials

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