# MinipRem Platform

> A comprehensive digital human platform with LLM integration, real-time facial animation, and monitoring capabilities.

## Overview

MinipRem is an integrated platform that combines a digital human interface (Renny) with LLM capabilities (vLLM), workflow automation (Flowise), and comprehensive monitoring tools (Prometheus + Grafana). This setup allows you to deploy and manage advanced AI interactions through a virtual human interface.

## Features

- **Digital Human Interface**: Powered by Renny, with real-time facial animation
- **LLM Integration**: vLLM running Gemma3 for natural language understanding
- **Workflow Automation**: Flowise for building and managing AI workflows
- **Metrics & Monitoring**: Prometheus and Grafana for real-time performance tracking
- **Queue Management**: Redis for reliable message processing

## Quick Start

### Prerequisites

- Docker and Docker Compose
- NVIDIA GPU with appropriate drivers
- Ubuntu Linux (recommended)

### Installation

1. Clone this repository:
   ```bash
   git clone https://gitlab.com/tgmerritt/miniprem-2025.git
   cd miniprem-2025
   ```
