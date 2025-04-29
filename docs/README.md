# MiniPrem Platform

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

## Quick Start

### Prerequisites

- Docker and Docker Compose
- NVIDIA GPU with appropriate drivers
- Ubuntu Linux (recommended)
- Required credentials from UneeQ (platform address, API key, tenant ID)
- Azure Speech service credentials (region and API key)

### Installation

For complete installation instructions, see our [Getting Started Guide](guides/getting-started.md).

## Platform Components

MiniPrem includes the following components:

- **Renny**: Digital human interface with real-time facial animation
- **vLLM**: Large Language Model serving with Gemma3
- **Flowise**: Visual workflow builder for AI applications
- **Prometheus & Grafana**: Real-time monitoring and dashboards
- **Redis**: Message queue for reliable processing
- **RIME**: High-quality text-to-speech engine

## Next Steps

- [Getting Started](guides/getting-started.md): Installation and basic setup
- [Services Overview](guides/services.md): Details on each component
- [Troubleshooting](troubleshooting.md): Solutions to common issues
