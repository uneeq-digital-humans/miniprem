/*
 * Self-hosted remote-mic relay — dependency-free.
 *
 * A drop-in, on-box replacement for UneeQ's hosted WebSocket relay. It pairs a
 * visitor's phone (the /remote page) with a kiosk by connectionId and forwards
 * messages between them. Implements ONLY the message protocol the kiosk
 * (ActionFactory) and the remote page already speak — see the AWS relay's
 * src/actions/* for the reference shapes:
 *   - client  {type:'getConnectionId'}                      -> {type:'connectionId', connectionId}
 *   - client  {type:'peerConnect', peerId, remoteInfo}      -> peer: {type:'RegisterRemote', remoteId, remoteInfo}
 *   - client  {type:'CheckPeerConnection', peerId}          -> peer: {type:'PeerChecked', Origin, Destination}
 *   - client  {type:'peerMessage', peerId, payload}         -> peer: {type:'peerMessage', data: payload}
 *   - client  {type:'closeSession'} / socket close          -> peers: {type:'PeerDisconnected'} / {type:'CloseSession'}
 *
 * No npm deps: implements the RFC 6455 handshake + text/close/ping framing with
 * Node built-ins, so it runs on a stock node:20-alpine image (mounted from a
 * ConfigMap) with nothing to build or pull from a registry.
 *
 * NOTE on reachability: a phone on the SAME Wi-Fi/LAN reaches this directly. A
 * phone on cellular needs a public HTTPS/wss tunnel to the box — that's the
 * operator's network setup (shown in the kiosk's Self-Hosted disclaimer).
 */
'use strict';
const http = require('http');
const crypto = require('crypto');

const PORT = parseInt(process.env.PORT || '8080', 10);
const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'; // RFC 6455 magic

/** connectionId -> { socket, peers:Set<connId> } */
const conns = new Map();
const newId = () => crypto.randomUUID();

function log(...a) { console.log('[relay]', new Date().toISOString(), ...a); }

// --- WebSocket frame encode (server->client, unmasked) ---------------------
function encodeFrame(str) {
  const payload = Buffer.from(str, 'utf8');
  const len = payload.length;
  let header;
  if (len < 126) {
    header = Buffer.from([0x81, len]);
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x81; header[1] = 126; header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81; header[1] = 127; header.writeBigUInt64BE(BigInt(len), 2);
  }
  return Buffer.concat([header, payload]);
}
function controlFrame(opcode) { return Buffer.from([0x80 | opcode, 0x00]); } // FIN + opcode, no payload

function sendTo(connId, obj) {
  const c = conns.get(connId);
  if (!c || c.socket.destroyed) return false;
  try { c.socket.write(encodeFrame(JSON.stringify(obj))); return true; }
  catch (e) { log('send error', e.message); return false; }
}

function pair(a, b) {
  conns.get(a)?.peers.add(b);
  conns.get(b)?.peers.add(a);
}

function handleMessage(connId, msg) {
  let m; try { m = JSON.parse(msg); } catch { return; }
  switch (m.type) {
    case 'getConnectionId':
      sendTo(connId, { type: 'connectionId', connectionId: connId });
      break;
    case 'peerConnect':
      pair(connId, m.peerId);
      sendTo(m.peerId, { type: 'RegisterRemote', remoteId: connId, remoteInfo: m.remoteInfo });
      break;
    case 'CheckPeerConnection':
      sendTo(m.peerId, { type: 'PeerChecked', Origin: connId, Destination: m.peerId });
      break;
    case 'peerMessage':
      pair(connId, m.peerId);
      sendTo(m.peerId, { type: 'peerMessage', data: m.payload });
      break;
    case 'closeSession':
      // mirror AWS: tell paired peers the session closed
      for (const p of conns.get(connId)?.peers || []) sendTo(p, { type: 'CloseSession' });
      break;
    case 'peerAudioTranscribe':
      // Not supported on-box: MiniPrem uses the kiosk's own Riva STT, not the
      // relay's Deepgram token path. Ignore quietly.
      break;
    default:
      break;
  }
}

function dropConn(connId) {
  const c = conns.get(connId);
  if (!c) return;
  for (const p of c.peers) sendTo(p, { type: 'PeerDisconnected' });
  conns.delete(connId);
  log('disconnect', connId, 'live:', conns.size);
}

// --- Per-socket frame parser (handles masking + fragmentation buffer) ------
function attachParser(connId, socket) {
  let buf = Buffer.alloc(0);
  socket.on('data', (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    while (buf.length >= 2) {
      const fin = (buf[0] & 0x80) !== 0;
      const opcode = buf[0] & 0x0f;
      const masked = (buf[1] & 0x80) !== 0;
      let len = buf[1] & 0x7f;
      let offset = 2;
      if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); offset = 4; }
      else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); offset = 10; }
      const maskLen = masked ? 4 : 0;
      if (buf.length < offset + maskLen + len) return; // wait for full frame
      const mask = masked ? buf.slice(offset, offset + maskLen) : null;
      const dataStart = offset + maskLen;
      const data = buf.slice(dataStart, dataStart + len);
      if (mask) for (let i = 0; i < data.length; i++) data[i] ^= mask[i & 3];
      buf = buf.slice(dataStart + len);

      if (opcode === 0x8) { socket.end(controlFrame(0x8)); dropConn(connId); return; } // close
      else if (opcode === 0x9) { socket.write(controlFrame(0xA)); }                    // ping -> pong
      else if (opcode === 0x1 && fin) { handleMessage(connId, data.toString('utf8')); } // text
      // (binary/continuation frames are not used by this protocol)
    }
  });
}

const server = http.createServer((req, res) => {
  // Plain HTTP health check (for k8s probes).
  if (req.url === '/health' || req.url === '/') { res.writeHead(200, { 'Content-Type': 'text/plain' }); res.end('ok'); return; }
  res.writeHead(404); res.end();
});

server.on('upgrade', (req, socket) => {
  const key = req.headers['sec-websocket-key'];
  if (!key) { socket.destroy(); return; }
  const accept = crypto.createHash('sha1').update(key + GUID).digest('base64');
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    `Sec-WebSocket-Accept: ${accept}\r\n\r\n`
  );
  socket.setNoDelay(true);
  const connId = newId();
  conns.set(connId, { socket, peers: new Set() });
  log('connect', connId, 'live:', conns.size);
  attachParser(connId, socket);
  socket.on('close', () => dropConn(connId));
  socket.on('error', () => dropConn(connId));
});

server.listen(PORT, '0.0.0.0', () => log(`remote-mic relay listening on :${PORT}`));
