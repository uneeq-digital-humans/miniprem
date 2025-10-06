# MiniPrem Monitor - Container & Kubernetes Monitoring

MiniPrem Monitor is a professional monitoring dashboard for Docker containers and Kubernetes pods, providing real-time visibility into your containerized workloads.

## Quick Access

**URL:** http://localhost:3001

**Prerequisites:**
- Docker Engine 20.10+ running
- kubectl configured (for Kubernetes monitoring)
- Port 3001 available on your host machine

## Overview

MiniPrem Monitor provides unified monitoring for:
- **Docker Containers**: Local container monitoring with real-time logs
- **Kubernetes Pods**: Multi-cluster pod monitoring and log streaming
- **System Health**: CPU, memory, and disk metrics
- **Service Status**: Connection health and availability

## Accessing the Monitor

### After Installation

Once you've deployed MiniPrem (any installation type), the monitor is automatically available:

```bash
# Start MiniPrem services
./miniprem.sh start

# Open your browser to:
http://localhost:3001
```

### Standalone Monitor Deployment

For monitoring Kubernetes clusters without the full MiniPrem stack:

```bash
cd docker
docker-compose -f docker-compose.monitor.yml up -d

# Access at:
http://localhost:3001
```

This standalone deployment is ideal for:
- Production EKS/AKS/GKE cluster monitoring
- Platform operations teams
- DevOps monitoring without running full AI stack

## Key Features

### 1. Real-Time Container Monitoring

- **Live Status**: See all running containers with status indicators
- **Resource Metrics**: CPU, memory, and network usage per container
- **Log Streaming**: Click any container to stream logs in real-time
- **Container Controls**: Start/stop containers directly from dashboard
- **Auto-Refresh**: WebSocket-based updates (no page refresh needed)

### 2. Kubernetes Cluster Monitoring

- **Pod Status**: Real-time pod health across all namespaces
- **Node Monitoring**: Cluster node status and resource availability
- **Multi-Cluster Support**: Switch between configured kubectl contexts
- **Live Pod Logs**: Stream logs from any pod with container selection
- **Namespace Filtering**: Filter pods by namespace for focused monitoring

### 3. Professional UI Features

- **Syntax Highlighting**: Automatic color-coding for log levels (ERROR, WARN, INFO, DEBUG)
- **Dark/Light Mode**: Theme toggle for user preference
- **Responsive Design**: Works on desktop, tablet, and mobile
- **Download Logs**: Export logs to text files for offline analysis
- **Search & Filter**: Quick filtering of containers and pods

## Architecture

### Host Network Mode

MiniPrem Monitor uses Docker's **host networking** (`network_mode: host`) for optimal performance:

**Benefits:**
- ✅ Direct Docker socket access (no bridge overhead)
- ✅ Seamless kubectl integration with host's kubeconfig
- ✅ Zero port mapping overhead
- ✅ Simplified configuration

**Port Bindings:**
- **Frontend**: Port 3001 (public access)
- **Backend**: Port 8000 (internal API, not exposed)

**Why this matters:** With host networking, the monitor binds directly to your host's ports. This eliminates network translation overhead and provides direct access to Docker and Kubernetes APIs.

### Security Features

- **Read-Only Docker Socket**: Mounted as read-only to prevent container modifications
- **Command Whitelisting**: Only approved Docker/kubectl commands are executed
- **Input Validation**: All container/pod names validated against strict regex patterns
- **No New Privileges**: Container runs with `no-new-privileges:true` security option
- **Safe Commands Only**: Limited to `ps`, `logs`, `stats`, `get`, `describe`

## Using the Dashboard

### Docker Container Monitoring

1. **View Containers**: The main dashboard shows all running containers
2. **Check Status**: Green = running, Red = stopped, Yellow = unhealthy
3. **View Logs**: Click the "View Logs" button on any container
4. **Monitor Resources**: Check CPU and memory usage in real-time
5. **Control Containers**: Use start/stop buttons (if permissions allow)

### Kubernetes Pod Monitoring

1. **Switch Context**: Use the cluster dropdown to select your kubectl context
2. **Select Namespace**: Filter pods by namespace (or view all)
3. **Check Pod Health**: Status indicators show pod health
4. **View Logs**: Click "View Logs" and select a container if multiple exist
5. **Monitor Nodes**: View node status and resource availability

### Log Streaming

**Features:**
- **Real-time streaming**: Logs update continuously
- **Syntax highlighting**: Automatic color-coding by log level
- **Download**: Export logs to text file
- **Auto-scroll**: Follow mode keeps newest logs visible
- **Search**: Quick text search within logs

**Log Controls:**
- **Pause/Resume**: Stop/start log streaming
- **Clear**: Clear current log view
- **Download**: Save logs as `.txt` file
- **Close**: Return to dashboard

## Troubleshooting

### Monitor Not Accessible

**Problem**: Cannot access http://localhost:3001

**Solutions:**
```bash
# Check if container is running
docker ps | grep miniprem-monitor

# Check container logs
docker logs miniprem-monitor

# Verify port 3001 is not in use
lsof -i :3001

# Restart the monitor
cd docker
docker-compose restart miniprem-monitor
```

### No Containers Visible

**Problem**: Dashboard shows no Docker containers

**Solutions:**
```bash
# Verify Docker socket access
docker exec miniprem-monitor ls -l /var/run/docker.sock

# Test Docker command inside container
docker exec miniprem-monitor docker ps

# Check container logs for errors
docker logs miniprem-monitor | grep -i error
```

### Kubernetes Not Working

**Problem**: Cannot see Kubernetes pods or contexts

**Solutions:**
```bash
# Verify kubectl config
docker exec miniprem-monitor kubectl config get-contexts

# Test cluster connectivity
docker exec miniprem-monitor kubectl cluster-info

# Refresh AWS credentials (for EKS)
aws sso login
aws eks update-kubeconfig --region us-east-1 --name your-cluster

# Check if kubeconfig is mounted correctly
docker exec miniprem-monitor ls -la /root/.kube/
```

### Log Streaming Not Working

**Problem**: Logs don't appear when clicking "View Logs"

**Solutions:**
```bash
# Check WebSocket connection in browser
# Open Developer Tools → Network tab → Look for WS connection

# Verify backend health
curl http://localhost:8000/health

# Check backend logs
docker logs miniprem-monitor | grep -i websocket

# Restart the monitor
docker-compose restart miniprem-monitor
```

### Port 3001 Already in Use

**Problem**: Error message "port 3001: bind: address already in use"

**Solutions:**
```bash
# Find process using port 3001
lsof -i :3001

# Kill the conflicting process (if safe)
kill <PID>

# Or change monitor port (edit docker-entrypoint.sh)
# Then rebuild: docker-compose up -d --build
```

## Network Configuration

### Host Networking Explained

The monitor uses `network_mode: host` which means:

1. **Container shares host network**: No separate network namespace
2. **Direct port binding**: Services bind to host ports (3001, 8000)
3. **No port mapping needed**: The `ports:` directive in docker-compose is ignored
4. **Direct access**: Can reach localhost services and Docker socket directly

**Comparison:**

| Feature | Host Network | Bridge Network |
|---------|--------------|----------------|
| Port mapping | Not needed | Required (3001:3001) |
| Docker socket | Direct access | Requires special config |
| kubectl | Direct access | Requires host mount |
| Performance | Optimal | Network translation overhead |
| Isolation | Less isolated | More isolated |

**Why host networking for monitor?**
- Monitoring tools need direct system access
- Eliminates network overhead for frequent API calls
- Simplifies Docker socket and kubectl integration
- Standard practice for monitoring containers

## Advanced Configuration

### Environment Variables

Configure the monitor by editing `docker-compose.monitor.yml`:

```yaml
environment:
  - MONITOR_MODE=standalone      # Deployment mode
  - LOG_LEVEL=info              # Logging level (debug/info/warn/error)
  - BACKEND_PORT=8000           # Internal backend port
  - FRONTEND_PORT=3001          # External frontend port
```

### Custom kubeconfig Location

If your kubeconfig is in a non-standard location:

```yaml
volumes:
  - /path/to/your/.kube:/root/.kube:ro
```

### Multiple Kubernetes Clusters

The monitor automatically detects all contexts in your kubeconfig:

```bash
# Add multiple clusters to kubeconfig
kubectl config use-context cluster1
kubectl config use-context cluster2

# Monitor will show all contexts in dropdown
```

### Resource Limits

Add resource limits to prevent monitor from consuming too many resources:

```yaml
deploy:
  resources:
    limits:
      cpus: '1.0'
      memory: 1G
    reservations:
      cpus: '0.5'
      memory: 512M
```

## Integration with MiniPrem

### Full Stack Deployment

When using the full MiniPrem stack, the monitor can track:
- Renny digital human containers
- vLLM inference containers
- Flowise workflow engine
- Redis queue system
- Prometheus metrics collection
- Grafana monitoring

### Complementary Monitoring

MiniPrem Monitor complements other monitoring tools:

| Tool | Purpose | Port |
|------|---------|------|
| **MiniPrem Monitor** | Container/Pod monitoring & logs | 3001 |
| Grafana | Metrics visualization | 3002 |
| Prometheus | Metrics collection | 9090 |

Use **MiniPrem Monitor** for real-time operational monitoring and log streaming.
Use **Grafana/Prometheus** for historical metrics and trends.

## Development

For contributors modifying the monitor code:

### Local Development

**Backend:**
```bash
cd miniprem-monitor/backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python run.py  # Port 8000
```

**Frontend:**
```bash
cd miniprem-monitor/frontend
npm install
npm run dev  # Port 3500
```

### Testing

**Playwright Tests:**
```bash
cd miniprem-monitor/frontend
npm run test          # All tests
npm run test:headed   # Visual mode
npm run test:ui       # Interactive UI
```

### Docker Build

```bash
cd miniprem-monitor
docker build -t miniprem-monitor:dev .
```

## Additional Resources

- **Full Documentation**: [MiniPrem Monitor README](../../miniprem-monitor/README.md)
- **Main Project README**: [MiniPrem Platform](../../README.md)
- **Kubernetes Deployment**: [Kubernetes Guide](kubernetes.md)
- **Troubleshooting**: [Troubleshooting Guide](../troubleshooting.md)

## Support

For issues or questions:
1. Check the troubleshooting sections above
2. Review container logs: `docker logs miniprem-monitor`
3. See [MiniPrem Monitor README](../../miniprem-monitor/README.md) for detailed troubleshooting
4. Contact UneeQ support with logs and error messages
