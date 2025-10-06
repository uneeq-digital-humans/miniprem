# Container Logs

View real-time logs from Docker containers and Kubernetes pods in the MiniPrem stack using the integrated MiniPrem Monitor.

## Accessing Logs

The MiniPrem Monitor provides a centralized monitoring dashboard with real-time log streaming capabilities:

1. **Access MiniPrem Monitor** at `http://localhost:3001`
2. **Docker Containers**: Click the "View Logs" button (eye icon) next to any container
3. **Kubernetes Pods**: Click the "View Logs" button next to any pod (if Kubernetes monitoring is enabled)

## Features

- **Real-Time Streaming**: Logs are streamed live as they are generated
- **Syntax Highlighting**: Automatic color coding for log levels (ERROR, WARN, INFO, DEBUG)
- **Auto-Scroll**: Automatically scrolls to show latest logs (can be toggled)
- **Download Logs**: Save logs to a text file for offline analysis
- **Historical Logs**: View last 100 lines of logs by default
- **WebSocket Connection**: Efficient real-time updates via WebSocket

## How It Works

The MiniPrem Monitor uses a FastAPI backend with WebSocket support to stream Docker container logs in real-time:

1. Frontend connects to `ws://localhost:8000/ws`
2. Sends a log streaming command: `{"type": "command", "target": "docker", "command": "logs:stream", "params": {"container": "container-name"}}`
3. Backend executes `docker logs --follow --tail 100 --timestamps container-name`
4. Log lines are streamed to the browser as they are generated
5. Connection is maintained until the log viewer is closed

## Security

- **Command Validation**: Only whitelisted Docker commands are allowed
- **Input Sanitization**: Container names are validated against regex patterns
- **Authentication**: Supports sudo authentication for Docker access when required
- **Rate Limiting**: WebSocket connections are rate-limited to prevent abuse

## Troubleshooting

If logs don't appear:

1. **Check MiniPrem Monitor** is running:
   ```bash
   docker ps | grep miniprem-monitor
   ```

2. **Check Docker access**:
   ```bash
   docker ps
   ```

3. **Verify WebSocket connection** in browser developer tools (Network tab)

4. **Check browser console** for any connection errors

For more details on the monitoring system, see the [MiniPrem Monitor README](../../miniprem-monitor/README.md).
