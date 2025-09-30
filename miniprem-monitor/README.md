<div align="center">

![UneeQ Logo](https://assets.uneeq.io/logos/uneeq-logo-color.svg)

# MiniPrem Monitor

> Real-time monitoring dashboard for Docker containers and Kubernetes pods with UneeQ branding

</div>

## Table of Contents

- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Features](#features)
- [API Endpoints](#api-endpoints)
- [Configuration](#configuration)
- [Development](#development)
- [Docker Support](#docker-support)
- [Troubleshooting](#troubleshooting)
- [Project Structure](#project-structure)
- [License](#license)
- [Copyright](#copyright)

## Architecture

- **Backend**: FastAPI with WebSocket support for real-time updates
- **Frontend**: Next.js with TypeScript, Tailwind CSS, and UneeQ brand colors
- **Security**: Command whitelisting, input sanitization, and secure subprocess execution
- **Real-time**: WebSocket subscriptions for live container/pod status updates

## Quick Start

### Prerequisites
- Python 3.8+
- Node.js 18+
- Docker (optional, for container monitoring)
- kubectl configured (optional, for Kubernetes monitoring)

### Manual Setup

#### Backend Setup

```bash
cd backend
python3 -m venv venv
source venv/bin/activate  # Linux/Mac
# or venv\Scripts\activate  # Windows
pip install -r requirements.txt
python run.py
```

The backend will start on `http://localhost:8000`

#### Frontend Setup

```bash
cd frontend
npm install
npm run dev
```

The frontend will start on `http://localhost:3500`

### Docker Engine & Kubernetes Monitoring

The application now provides enhanced host system integration:

- **Docker Engine Health**: Comprehensive monitoring of Docker daemon status, resource usage, and container statistics
- **Kubernetes Cluster Health**: Real-time cluster status, node health, and namespace information
- **Host System Integration**: Direct command execution on the host system (not containerized)
- **Cross-Platform Support**: Native operation on Mac, Linux, and Windows

## Features

### Enhanced Host System Monitoring
- **Docker Engine Health**: Complete Docker daemon monitoring, version info, resource usage, and container statistics
- **Kubernetes Cluster Health**: Cluster status, node health, namespace count, and detailed node information
- **System Health Dashboard**: Visual indicators for Docker and Kubernetes availability and health status
- **Host Command Integration**: Direct execution of docker and kubectl commands on the host system (not containerized)

### Real-time Monitoring
- **Docker Containers**: Live status, resource usage, and logs
- **Kubernetes Pods**: Pod status, namespaces, and logs
- **System Metrics**: CPU, memory, disk, and network usage
- **WebSocket Integration**: Real-time updates without page refresh
- **Service Availability Tracking**: Automatic detection of Docker and Kubernetes availability

### Development & Testing Automation
- **Puppeteer Integration**: Automated browser testing for dashboard functionality
- **E2E Test Suite**: Comprehensive end-to-end testing including WebSocket communication
- **Cross-Platform Scripts**: Automated setup, testing, and management for Mac/Linux/Windows
- **Performance Monitoring**: Response time tracking and performance metrics

### Security Features
- Command whitelisting (only safe Docker/kubectl commands)
- Input sanitization and validation
- Rate limiting and connection management
- Safe error handling without information leakage

### UI Features
- **Responsive Design**: Works on desktop, tablet, and mobile
- **Enhanced Health Panel**: Detailed system health monitoring with Docker Engine and Kubernetes cluster status
- **Dark Log Viewer**: Terminal-style log display with syntax highlighting
- **Connection Status**: Real-time WebSocket connection indicator
- **Auto-refresh**: Configurable polling and subscription intervals

## API Endpoints

### REST Endpoints
- `GET /` - Health check
- `GET /health` - Detailed health check with component status
- `GET /api/system/info` - System information (includes Docker and Kubernetes basic info)
- `GET /api/system/metrics` - Current system metrics
- `GET /api/connections/stats` - WebSocket connection statistics

### Enhanced Monitoring Endpoints
- `GET /api/docker/health` - Comprehensive Docker Engine health information
- `GET /api/kubernetes/health` - Detailed Kubernetes cluster health status
- `GET /api/services/availability` - Real-time Docker and Kubernetes availability check

### WebSocket Endpoint
- `WS /ws` - Real-time monitoring commands and subscriptions

### WebSocket Message Format

```json
{
  "type": "command|subscribe|unsubscribe",
  "target": "docker|kubernetes",
  "command": "ps|logs|stats|pods|nodes",
  "params": {"container": "name", "namespace": "default"},
  "requestId": "unique-id"
}
```

## Configuration

### Environment Variables
- `BACKEND_HOST`: Backend server host (default: 0.0.0.0)
- `BACKEND_PORT`: Backend server port (default: 8000)
- `LOG_LEVEL`: Logging level (default: info)

### Security Settings
- Max 50 concurrent WebSocket connections
- 60 requests per minute rate limiting
- 30-second command timeout
- 1MB output size limit

## Development

### Backend Development
```bash
cd backend
pip install -r requirements.txt
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Frontend Development
```bash
cd frontend
npm run dev
```

### Type Checking
```bash
cd frontend
npm run type-check
```

### Building for Production
```bash
# Backend
cd backend
pip install -r requirements.txt

# Frontend
cd frontend
npm run build
npm start
```

## Docker Support

The application automatically detects available services:
- If Docker is not available, container monitoring is disabled
- If kubectl is not configured, Kubernetes monitoring is disabled
- System metrics are always available

## Troubleshooting

### Common Issues

1. **Backend Connection Issues**
   - Ensure Python dependencies are installed
   - Check if port 8000 is available
   - Verify Docker/kubectl access if using those features

2. **Frontend WebSocket Issues**
   - Ensure backend is running on port 8000
   - Check browser console for connection errors
   - Verify CORS settings in backend

3. **Command Execution Failures**
   - Check Docker daemon status: `docker ps`
   - Verify kubectl configuration: `kubectl cluster-info`
   - Review backend logs for security violations

### Debug Mode

Enable debug logging:
```bash
cd backend
LOG_LEVEL=debug python run.py
```

## Project Structure

```
miniprem-monitor/
├── backend/                 # FastAPI backend
│   ├── app/
│   │   ├── security/        # Command execution and validation
│   │   ├── websocket/       # WebSocket connection management
│   │   ├── models/          # Pydantic data models
│   │   ├── services/        # System monitoring services
│   │   └── main.py         # FastAPI application
│   ├── requirements.txt
│   └── run.py
├── frontend/               # Next.js frontend
│   ├── src/
│   │   ├── app/            # Next.js 13+ app directory
│   │   ├── components/     # React components
│   │   ├── hooks/          # Custom React hooks
│   │   ├── types/          # TypeScript type definitions
│   │   └── styles/         # Global CSS and Tailwind config
│   ├── package.json
│   └── next.config.js
├── design-system.md        # UneeQ brand guidelines
├── architecture.md         # Security architecture documentation
└── README.md
```

## Contributing

1. Follow the established code patterns
2. Maintain security practices (no arbitrary command execution)
3. Test both Docker and Kubernetes integration paths
4. Ensure responsive design compliance
5. Follow UneeQ brand guidelines for UI changes

## License

This monitoring dashboard is part of the MiniPrem platform, licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.

---

## Copyright

<div align="center">

**© 2025 UneeQ - A FaceMe Company. All rights reserved.**

![UneeQ Logo](https://assets.uneeq.io/logos/uneeq-logo-color.svg)

**Digital Humans. Unlimited Possibilities.**

[www.digitalhumans.com](https://www.digitalhumans.com) | [support@digitalhumans.com](mailto:support@digitalhumans.com)

</div>