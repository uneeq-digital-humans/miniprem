/**
 * RIVA ASR WebSocket-to-gRPC Proxy
 *
 * Bridges the RivaASRService (browser WebSocket) to RIVA's gRPC StreamingRecognize API.
 *
 * Protocol:
 *   Browser → WS → this proxy → gRPC → RIVA speech server
 *
 * WebSocket messages from browser:
 *   1. First message: JSON { config: { encoding, sample_rate_hertz, language_code, interim_results } }
 *   2. Subsequent messages: binary audio chunks (ArrayBuffer)
 *
 * WebSocket messages to browser:
 *   JSON { results: [{ alternatives: [{ transcript: "..." }], is_final: true|false }] }
 */

const http = require('http');
const WebSocket = require('ws');
const grpc = require('@grpc/grpc-js');
const protoLoader = require('@grpc/proto-loader');
const path = require('path');
const fs = require('fs');

const RIVA_GRPC_URL = process.env.RIVA_GRPC_URL || 'localhost:50051';
const PORT = parseInt(process.env.PORT || '8000', 10);
const PROTO_DIR = process.env.PROTO_DIR || '/protos';

// Load RIVA ASR proto
const PROTO_PATH = path.join(PROTO_DIR, 'riva_asr.proto');
const AUDIO_PROTO_PATH = path.join(PROTO_DIR, 'riva_audio.proto');

let RivaASR;
try {
  const packageDef = protoLoader.loadSync([PROTO_PATH, AUDIO_PROTO_PATH], {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
    includeDirs: [PROTO_DIR],
  });
  const proto = grpc.loadPackageDefinition(packageDef);
  RivaASR = proto.nvidia?.riva?.asr?.RivaSpeechRecognition;
  if (!RivaASR) throw new Error('RivaSpeechRecognition service not found in proto');
  console.log('[proxy] RIVA proto loaded successfully');
} catch (err) {
  console.error('[proxy] Failed to load RIVA proto:', err.message);
  process.exit(1);
}

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200);
    res.end('ok');
  } else {
    res.writeHead(404);
    res.end();
  }
});

const wss = new WebSocket.Server({ server, path: '/api/asr/v1/stream' });

wss.on('connection', (ws, req) => {
  console.log('[proxy] Browser connected from', req.socket.remoteAddress);

  const rivaClient = new RivaASR(RIVA_GRPC_URL, grpc.credentials.createInsecure());
  let grpcCall = null;
  let configReceived = false;

  ws.on('message', (data, isBinary) => {
    if (!configReceived) {
      // First message: JSON config
      try {
        const msg = JSON.parse(data.toString());
        const cfg = msg.config || {};
        console.log('[proxy] Config received:', cfg);

        grpcCall = rivaClient.StreamingRecognize();

        grpcCall.on('data', (response) => {
          if (!response.results || response.results.length === 0) return;
          const result = response.results[0];
          if (!result.alternatives || result.alternatives.length === 0) return;
          const out = {
            results: [{
              alternatives: [{ transcript: result.alternatives[0].transcript || '' }],
              is_final: result.is_final || false,
            }],
          };
          if (ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify(out));
          }
        });

        grpcCall.on('error', (err) => {
          console.error('[proxy] gRPC stream error:', err.message);
          if (ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({ error: err.message }));
          }
        });

        grpcCall.on('end', () => {
          console.log('[proxy] gRPC stream ended');
        });

        // Send initial config message to RIVA
        const encodingMap = {
          LINEAR_PCM: 1,
          FLAC: 2,
          MULAW: 3,
          MP3: 17,
          OGGOPUS: 20,
          OGGVORBIS: 23,
        };
        grpcCall.write({
          streaming_config: {
            config: {
              encoding: encodingMap[cfg.encoding] || 1,
              sample_rate_hertz: cfg.sample_rate_hertz || 16000,
              language_code: cfg.language_code || 'en-US',
              max_alternatives: 1,
            },
            interim_results: cfg.interim_results !== false,
          },
        });

        configReceived = true;
      } catch (err) {
        console.error('[proxy] Failed to parse config:', err.message);
        ws.close(1003, 'Invalid config');
      }
    } else if (isBinary && grpcCall) {
      // Subsequent messages: binary audio
      grpcCall.write({ audio_content: data });
    }
  });

  ws.on('close', () => {
    console.log('[proxy] Browser disconnected');
    if (grpcCall) grpcCall.end();
  });

  ws.on('error', (err) => {
    console.error('[proxy] WebSocket error:', err.message);
    if (grpcCall) grpcCall.end();
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[proxy] RIVA WebSocket proxy listening on port ${PORT}`);
  console.log(`[proxy] WebSocket endpoint: ws://0.0.0.0:${PORT}/api/asr/v1/stream`);
  console.log(`[proxy] Forwarding to RIVA gRPC at: ${RIVA_GRPC_URL}`);
});
