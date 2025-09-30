<div align="center">

![UneeQ Logo](https://assets.uneeq.io/logos/uneeq-logo-color.svg)

# MiniPrem Monitor Backend

> Production-ready FastAPI backend for monitoring Docker containers and Kubernetes pods with real-time WebSocket updates

</div>

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [API Documentation](#api-documentation)
- [Security Features](#security-features)
- [Configuration](#configuration)
- [Development](#development)
- [Troubleshooting](#troubleshooting)
- [Performance Considerations](#performance-considerations)
- [Integration Examples](#integration-examples)
- [License](#license)
- [Copyright](#copyright)

## Features

### Core Functionality
- **REST API Endpoints**: Monitor Docker containers, images, stats, and Kubernetes resources
- **Real-time WebSocket**: Live updates every 5 seconds for all connected clients
- **Secure Command Execution**: Whitelist-based command execution with input validation
- **Error Handling**: Comprehensive error handling with detailed logging
- **Production Ready**: Built for high-availability production environments

### Docker Monitoring
- `GET /api/docker/containers` - List all containers with status information
- `GET /api/docker/images` - List all Docker images
- `GET /api/docker/stats` - Real-time resource usage statistics

### Kubernetes Monitoring
- `GET /api/kubernetes/pods` - List pods across all namespaces or filtered
- `GET /api/kubernetes/services` - List services with network information
- `GET /api/kubernetes/nodes` - List cluster nodes with status and resource info

### WebSocket Real-time Updates
- `WS /ws` - Real-time monitoring data every 5 seconds
- Automatic client connection management
- Graceful error handling for disconnected clients

## Quick Start

### Prerequisites
- Python 3.13+
- Docker (for Docker monitoring)
- kubectl configured (for Kubernetes monitoring)

### Installation

1. **Clone and navigate to backend directory:**
```bash
cd /Users/tyler/Software_Development/miniprem-2025/miniprem-monitor/backend
```

2. **Create virtual environment:**
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

3. **Install dependencies:**
```bash
pip install -r requirements.txt
```

4. **Run the server:**
```bash
# Development server
python main.py

# Or with uvicorn directly
uvicorn main:app --host 0.0.0.0 --port 8000 --reload

# Production server
uvicorn main:app --host 0.0.0.0 --port 8000 --workers 4
```

5. **Access the API:**
- API Documentation: http://localhost:8000/docs
- Health Check: http://localhost:8000/health
- WebSocket: ws://localhost:8000/ws

## API Documentation

### REST Endpoints

#### Health Check
```http
GET /health
```
Returns service health status.

#### Docker Endpoints

**Get All Containers**
```http
GET /api/docker/containers
```
Returns all Docker containers with status, ports, and metadata.

**Get Docker Images**
```http
GET /api/docker/images
```
Returns all available Docker images with size and creation info.

**Get Container Stats**
```http
GET /api/docker/stats
```
Returns real-time resource usage statistics for all containers.

#### Kubernetes Endpoints

**Get Pods**
```http
GET /api/kubernetes/pods?namespace=optional-namespace
```
Returns pods across all namespaces or filtered by namespace.

**Get Services**
```http
GET /api/kubernetes/services?namespace=optional-namespace
```
Returns services with network configuration and endpoints.

**Get Nodes**
```http
GET /api/kubernetes/nodes
```
Returns cluster nodes with status, roles, and system information.

### WebSocket Connection

Connect to `ws://localhost:8000/ws` to receive real-time updates:

```javascript
const socket = new WebSocket('ws://localhost:8000/ws');

socket.onmessage = function(event) {
    const data = JSON.parse(event.data);
    console.log('Monitoring update:', data);

    // Access different data types
    if (data.docker_containers && data.docker_containers.success) {
        console.log('Docker containers:', data.docker_containers.data);
    }

    if (data.kubernetes_pods && data.kubernetes_pods.success) {
        console.log('Kubernetes pods:', data.kubernetes_pods.data);
    }

    // Handle errors
    if (data.errors) {
        console.log('Monitoring errors:', data.errors);
    }
};

socket.onopen = function() {
    console.log('WebSocket connected');
};

socket.onclose = function() {
    console.log('WebSocket disconnected');
};
```

## Security Features

### Command Injection Prevention
- **Whitelist Commands**: Only predefined, safe commands are allowed
- **Input Validation**: All user inputs validated with regex patterns
- **No Shell Execution**: Commands executed directly without shell interpretation
- **Parameter Sanitization**: All parameters validated before execution

### Input Validation Examples
```python
# Valid namespace names (RFC 1123)
namespace_pattern = r"^[a-z0-9]([-a-z0-9]*[a-z0-9])?$"

# Valid container names
container_pattern = r"^[a-zA-Z0-9][a-zA-Z0-9_.-]*$"

# Length limits enforced
max_namespace_length = 253
max_container_name_length = 128
```

### Error Handling
- Sensitive information excluded from error messages
- Detailed logging for debugging without exposure
- Graceful degradation when services unavailable

## Configuration

### Environment Variables
```bash
# Optional environment variables
export MINIPREM_MONITOR_HOST=0.0.0.0
export MINIPREM_MONITOR_PORT=8000
export MINIPREM_MONITOR_LOG_LEVEL=INFO
export MINIPREM_MONITOR_UPDATE_INTERVAL=5  # WebSocket update interval in seconds
```

### Production Configuration
For production deployment, consider:

```python
# In main.py, modify CORS settings:
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://your-frontend-domain.com"],  # Restrict origins
    allow_credentials=True,
    allow_methods=["GET"],  # Restrict methods
    allow_headers=["*"],
)
```

## Development

### Project Structure
```
backend/
├── main.py                 # FastAPI application entry point
├── docker_monitor.py       # Docker command execution and parsing
├── kubernetes_monitor.py   # Kubernetes kubectl execution and parsing
├── websocket_handler.py    # WebSocket connection management
├── requirements.txt        # Python dependencies
└── README.md              # This file
```

### Testing

Run tests with pytest:
```bash
# Install test dependencies
pip install pytest pytest-asyncio httpx

# Run all tests
pytest

# Run with coverage
pytest --cov=. --cov-report=html
```

### Adding New Monitoring Features

1. **Add new commands to whitelist:**
```python
# In docker_monitor.py or kubernetes_monitor.py
ALLOWED_COMMANDS = {
    "new_command": ["docker", "new-subcommand", "--safe-flag"]
}
```

2. **Implement parsing method:**
```python
def _parse_new_output(self, output: str) -> List[Dict[str, Any]]:
    # Parse command output safely
    pass
```

3. **Add API endpoint:**
```python
# In main.py
@app.get("/api/docker/new-endpoint")
async def get_new_data():
    return await docker_monitor.get_new_data()
```

## Troubleshooting

### Common Issues

**Docker not available:**
```
Error: Docker is not available
```
- Verify Docker is running: `docker --version`
- Check Docker daemon status: `systemctl status docker`
- Ensure user has Docker permissions: `docker ps`

**kubectl not available:**
```
Error: kubectl is not available or cannot connect to cluster
```
- Verify kubectl is installed: `kubectl version --client`
- Check cluster connection: `kubectl cluster-info`
- Verify kubeconfig: `kubectl config current-context`

**WebSocket connection issues:**
- Check firewall rules for port 8000
- Verify WebSocket client implementation
- Monitor server logs for connection errors

### Logging

The application uses structured logging. To increase log verbosity:

```bash
# Set log level to DEBUG
export MINIPREM_MONITOR_LOG_LEVEL=DEBUG
python main.py
```

Log locations:
- Development: Console output
- Production: Configure log aggregation (e.g., ELK stack)

## Performance Considerations

### Resource Usage
- Memory: ~50-100MB baseline
- CPU: Low usage except during command execution
- Network: Minimal, only WebSocket updates

### Scaling
- **Horizontal**: Deploy multiple instances behind load balancer
- **WebSocket Load Balancing**: Use Redis for shared state
- **Database**: Add Redis/PostgreSQL for historical data

### Production Optimizations
```bash
# Use production ASGI server
gunicorn main:app -w 4 -k uvicorn.workers.UvicornWorker

# Or with higher performance
uvicorn main:app --workers 4 --loop uvloop --http httptools
```

## Integration Examples

### Frontend Integration (React)
```javascript
import { useState, useEffect } from 'react';

function MonitorDashboard() {
    const [monitorData, setMonitorData] = useState(null);
    const [socket, setSocket] = useState(null);

    useEffect(() => {
        const ws = new WebSocket('ws://localhost:8000/ws');

        ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            setMonitorData(data);
        };

        setSocket(ws);
        return () => ws.close();
    }, []);

    return (
        <div>
            {monitorData?.docker_containers && (
                <ContainerList containers={monitorData.docker_containers.data} />
            )}
            {monitorData?.kubernetes_pods && (
                <PodList pods={monitorData.kubernetes_pods.data} />
            )}
        </div>
    );
}
```

### CLI Integration
```bash
# Get containers via API
curl http://localhost:8000/api/docker/containers | jq '.data'

# Get Kubernetes pods
curl http://localhost:8000/api/kubernetes/pods | jq '.data'
```

## License

This backend is part of the MiniPrem platform, licensed under the MIT License - see the [LICENSE](../../LICENSE) file for details.

---

## Support

For issues related to this monitoring backend:
1. Check the troubleshooting section above
2. Review application logs with DEBUG level
3. Verify Docker and kubectl connectivity independently
4. Open an issue in the main MiniPrem repository

---

## Copyright

<div align="center">

**© 2025 UneeQ - A FaceMe Company. All rights reserved.**

![UneeQ Logo](https://assets.uneeq.io/logos/uneeq-logo-color.svg)

**Digital Humans. Unlimited Possibilities.**

[www.digitalhumans.com](https://www.digitalhumans.com) | [support@digitalhumans.com](mailto:support@digitalhumans.com)

</div>