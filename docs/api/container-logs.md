# Container Logs

View real-time logs from containers running in the MiniPrem stack. This feature allows you to monitor services directly from the documentation.

## Available Containers

Select a container from the dropdown to view its logs:

```container-logs
flowise
vllm
redis
prometheus
grafana
renny
log-streamer
```

## How It Works

This feature connects to the Log Streamer service running on port 8082, which provides a WebSocket interface to the Docker logs. When you select a container, a WebSocket connection is established to:

```
ws://localhost:8082/logs/{container-name}
```

The log streamer service then connects to Docker and streams logs in real-time to your browser.

## Troubleshooting

If you don't see logs appearing:

1. Make sure the log-streamer service is running:
   ```bash
   docker ps | grep log-streamer
   ```

2. Check the log-streamer service logs:
   ```bash
   docker logs log-streamer
   ```

3. Ensure your browser supports WebSockets and has access to localhost:8082

4. If logs still don't appear, the service will automatically fall back to simulated logs for demonstration purposes.