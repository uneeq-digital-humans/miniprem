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
 *
 * Resilience: the kiosk keeps one WebSocket open for the whole visit, but the
 * Riva/Triton streaming sequence dies whenever audio pauses long enough to trip
 * Triton's sequence idle timeout ("Stream aborted: start chunk failed or stream
 * is no longer active"). Worse, the dead sequence is a ZOMBIE: Riva keeps
 * accepting audio writes and only surfaces the error when the stream closes, so
 * the browser keeps talking into a stream that transcribes nothing until page
 * reload (observed on-box: 47s of audio, 0s of speech, error only at close).
 * So the proxy owns recovery, two ways:
 *   1. Proactive: when audio resumes after a gap longer than GAP_RESET_S, the
 *      current stream is presumed expired and a fresh one (with the remembered
 *      config, i.e. a new Triton sequence START) is opened before writing.
 *   2. Reactive: if the active stream errors/ends while the browser is still
 *      connected, reopen it transparently (rate-limited so a down Riva doesn't
 *      cause a hot retry loop).
 */

const http = require('http');
const WebSocket = require('ws');
const grpc = require('@grpc/grpc-js');
const protoLoader = require('@grpc/proto-loader');
const path = require('path');

const RIVA_GRPC_URL = process.env.RIVA_GRPC_URL || 'localhost:50051';
const PORT = parseInt(process.env.PORT || '8000', 10);
const PROTO_DIR = process.env.PROTO_DIR || '/protos';
// Consecutive instant stream failures before we give up and surface the error
// (protects against a hot retry loop when Riva itself is down).
const MAX_RAPID_RESTARTS = parseInt(process.env.MAX_RAPID_RESTARTS || '5', 10);
const RAPID_WINDOW_MS = 2000;
// Audio gap after which the Triton sequence is presumed expired and the stream
// is proactively reopened on resume. Must be shorter than Triton's sequence
// idle timeout; 30s is comfortably below observed expiry.
const GAP_RESET_S = parseInt(process.env.GAP_RESET_S || '30', 10);

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

const encodingMap = {
  LINEAR_PCM: 1,
  FLAC: 2,
  MULAW: 3,
  MP3: 17,
  OGGOPUS: 20,
  OGGVORBIS: 23,
};

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

  // Keepalives matter when Riva is REMOTE (nemotron.enabled=false +
  // proxy.rivaGrpcUrl): NAT/LB middleboxes silently kill idle TCP connections,
  // and without pings the next utterance dies on a dead channel. Harmless for
  // the local-sidecar case.
  const rivaClient = new RivaASR(RIVA_GRPC_URL, grpc.credentials.createInsecure(), {
    'grpc.keepalive_time_ms': 30000,
    'grpc.keepalive_timeout_ms': 10000,
    'grpc.keepalive_permit_without_calls': 1,
    'grpc.http2.max_pings_without_data': 0,
  });
  let grpcCall = null;
  let streamingConfig = null; // remembered so we can restart the stream mid-session
  let closed = false;         // browser gone — stop restarting
  let restartTimes = [];      // timestamps of recent restarts (rapid-failure guard)
  let lastAudioAt = 0;        // for the proactive gap reset

  function openStream() {
    const call = rivaClient.StreamingRecognize();
    // Handlers only act while this call is still the ACTIVE one — a superseded
    // or torn-down call firing 'error'/'end' late must not restart anything.

    call.on('data', (response) => {
      if (call !== grpcCall) return;
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

    call.on('error', (err) => {
      console.error('[proxy] gRPC stream error:', err.message);
      if (call !== grpcCall) return;
      restartStream(err.message);
    });

    call.on('end', () => {
      console.log('[proxy] gRPC stream ended');
      if (call !== grpcCall) return;
      restartStream(null);
    });

    call.write({ streaming_config: streamingConfig });
    return call;
  }

  // Retire the active stream and open a fresh one (new Triton sequence, START
  // implied by the config message). The old call is ended AFTER the new one is
  // active, so its late 'error'/'end' events are ignored by the active-check.
  function reopenStream(reason) {
    console.log(`[proxy] Reopening Riva stream (${reason})`);
    const old = grpcCall;
    grpcCall = openStream();
    if (old) {
      try { old.end(); } catch (_) { /* already dead */ }
    }
  }

  function restartStream(errMsg) {
    if (closed || !streamingConfig) return;
    if (ws.readyState !== WebSocket.OPEN) return;

    // Rapid-failure guard: if streams die instantly N times in a row, Riva is
    // down — surface the error instead of spinning.
    const now = Date.now();
    restartTimes = restartTimes.filter((t) => now - t < RAPID_WINDOW_MS);
    restartTimes.push(now);
    if (restartTimes.length > MAX_RAPID_RESTARTS) {
      console.error('[proxy] Riva stream failing repeatedly, giving up on this session');
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ error: errMsg || 'Riva stream unavailable' }));
        ws.close(1011, 'Riva unavailable');
      }
      return;
    }

    reopenStream(errMsg ? `after error: ${errMsg}` : 'after server end');
  }

  ws.on('message', (data, isBinary) => {
    if (!streamingConfig) {
      // First message: JSON config
      try {
        const msg = JSON.parse(data.toString());
        const cfg = msg.config || {};
        console.log('[proxy] Config received:', cfg);
        streamingConfig = {
          config: {
            encoding: encodingMap[cfg.encoding] || 1,
            sample_rate_hertz: cfg.sample_rate_hertz || 16000,
            language_code: cfg.language_code || 'en-US',
            max_alternatives: 1,
          },
          interim_results: cfg.interim_results !== false,
        };
        grpcCall = openStream();
      } catch (err) {
        console.error('[proxy] Failed to parse config:', err.message);
        ws.close(1003, 'Invalid config');
      }
    } else if (isBinary && grpcCall) {
      // Subsequent messages: binary audio.
      // Proactive gap reset: after a long pause Triton has expired the sequence
      // but Riva won't error until close — a zombie stream that transcribes
      // nothing. Resume on a FRESH stream instead.
      const now = Date.now();
      if (lastAudioAt && now - lastAudioAt > GAP_RESET_S * 1000) {
        reopenStream(`audio resumed after ${Math.round((now - lastAudioAt) / 1000)}s gap`);
      }
      lastAudioAt = now;
      // write() can throw if the call died between the error event and here —
      // recover instead of crashing the pod.
      try {
        grpcCall.write({ audio_content: data });
      } catch (err) {
        console.error('[proxy] write to dead stream:', err.message);
        restartStream(err.message);
      }
    }
  });

  function teardown() {
    closed = true;
    if (grpcCall) {
      try { grpcCall.end(); } catch (_) { /* already gone */ }
      grpcCall = null;
    }
    try { rivaClient.close(); } catch (_) { /* channel already closed */ }
  }

  ws.on('close', () => {
    console.log('[proxy] Browser disconnected');
    teardown();
  });

  ws.on('error', (err) => {
    console.error('[proxy] WebSocket error:', err.message);
    teardown();
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[proxy] RIVA WebSocket proxy listening on port ${PORT}`);
  console.log(`[proxy] WebSocket endpoint: ws://0.0.0.0:${PORT}/api/asr/v1/stream`);
  console.log(`[proxy] Forwarding to RIVA gRPC at: ${RIVA_GRPC_URL}`);
});
