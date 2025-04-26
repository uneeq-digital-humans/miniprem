# Docker Log Streamer

This service provides a WebSocket API to stream logs from Docker containers in real-time. It's designed to integrate with the MiniPrem documentation system to allow viewing container logs directly in the documentation portal.

## Features

- WebSocket API for streaming container logs
- Health check endpoint
- CORS support for browser clients
- Error handling and safe disconnection

## API

### Health Check
```
GET /health
```
Returns a simple health status response to verify the service is running.

### WebSocket Log Stream
```
WS /logs/{container_name}
```
Connect to this WebSocket endpoint to stream logs from a specific container. Replace `{container_name}` with the name of the Docker container you want to monitor (e.g., `flowise`, `ollama`, etc.).

## Integration with Documentation

The log streamer integrates with the MiniPrem documentation through custom components that connect to these WebSocket endpoints. In the documentation, you can view container logs by using the container-logs code block:

````md
```container-logs
flowise
ollama
redis
prometheus
grafana
```
````

This will render a dropdown menu allowing users to select a container and view its logs in real-time.

## Requirements

- Node.js 18+
- Docker socket access
- Express
- WebSocket (ws)

## Security Considerations

This service requires access to the Docker socket to read container logs. In production environments, consider implementing:

- Authentication for the API
- Rate limiting
- Access controls for which containers can be monitored

## Development

To run this service locally outside of Docker:

```bash
npm install
node server.js
```