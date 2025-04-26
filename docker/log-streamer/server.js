const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const { spawn } = require('child_process');
const cors = require('cors');
const path = require('path');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// Enable CORS for all routes
app.use(cors());

// Simple health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'ok',
    version: '1.0.0',
    service: 'docker-log-streamer'
  });
});

// List available containers
app.get('/containers', (req, res) => {
  const dockerPs = spawn('docker', ['ps', '--format', '{{.Names}}']);
  let containerList = '';

  dockerPs.stdout.on('data', (data) => {
    containerList += data.toString();
  });

  dockerPs.on('close', (code) => {
    if (code !== 0) {
      return res.status(500).json({ error: 'Failed to list containers' });
    }

    const containers = containerList.trim().split('\n').filter(Boolean);
    res.json({ containers });
  });
});

// Handle WebSocket connections
wss.on('connection', function connection(ws, req) {
  // Extract container name from URL
  const container = req.url.split('/').pop();
  console.log(`New connection established for container: ${container}`);
  
  // Spawn docker logs process
  const dockerLogs = spawn('docker', ['logs', '--follow', container]);
  
  // Send logs to WebSocket client
  dockerLogs.stdout.on('data', (data) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(data.toString());
    }
  });
  
  dockerLogs.stderr.on('data', (data) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(data.toString());
    }
  });
  
  // Handle errors
  dockerLogs.on('error', (error) => {
    console.error(`Error with docker logs process: ${error.message}`);
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(`ERROR: ${error.message}`);
    }
  });
  
  // Handle client disconnection
  ws.on('close', () => {
    console.log(`Connection closed for container: ${container}`);
    dockerLogs.kill();
  });

  // Send initial connection confirmation
  ws.send(`Connected to log stream for container: ${container}`);
});

// Start the server
const PORT = process.env.PORT || 8082;
server.listen(PORT, () => {
  console.log(`Log streaming server running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
  console.log(`WebSocket endpoint: ws://localhost:${PORT}/logs/{container-name}`);
});