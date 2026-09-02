#!/usr/bin/env python3
"""
Deepgram TTS Adapter — bridges the DHOP BYO v1 HTTP contract to the
self-hosted Deepgram stem's /v2/speak WebSocket (Flux TTS).

WHY THIS EXISTS
---------------
Renny's conversation repo (tts-proxy) already speaks the BYO v1 contract:
    POST {tts_url}
    Body: {"text": "...", "preset": "<voice>", "apiKey": "<tts_api_key>"}
    Response: raw 16 kHz mono 16-bit PCM (audio body)

The self-hosted Deepgram stem (uneeq-kit) speaks the Deepgram v2 speak
WebSocket protocol on /v2/speak.  This adapter sits between the two so
that Renny can be pointed at the stem via the existing BYO TTS config in
the DHOP Admin Portal — no Renny code change needed.

SETUP (on the kiosk box)
-------------------------
1. Install the Python dependency:
       pip3 install websocket-client
2. Point the adapter at the stem (default http://localhost:8080):
       export DEEPGRAM_STEM_URL=http://localhost:8080
3. Run:
       python3 deepgram_tts_adapter.py --port 8081
4. In the DHOP Admin Portal, set the persona's TTS:
       Provider : Custom (BYO)
       TTS URL  : http://<kiosk-ip>:8081
       API Key  : (any non-empty string; passed through to the stem)
       Voice    : flux-hannah-en   (or any other loaded Flux TTS voice)

PROTOCOL
--------
  inbound  (Renny → adapter, BYO v1):
      POST /   {"text":"Hello","preset":"flux-hannah-en","apiKey":"***"}

  outbound (adapter → stem, Deepgram v2 speak WS):
      WS  ws://<stem>/v2/speak?model=flux-hannah-en&encoding=linear16&sample_rate=16000
      →  {"type":"Speak","text":"Hello"}
      →  {"type":"Flush"}
      ←  binary audio frames  +  JSON {type:"SpeechMetadata"} (done)

  response (adapter → Renny):
      HTTP 200  Content-Type: application/octet-stream
      Body: raw 16 kHz mono s16le PCM

ENV VARS
--------
  DEEPGRAM_STEM_URL   Base URL of the self-hosted stem (default http://localhost:8080)
  DEEPGRAM_TTS_MODEL  Fallback model name if "preset" is empty (default flux-hannah-en)
  DEEPGRAM_TTS_SR     Output sample rate (default 16000; must match what Renny expects)
  DEEPGRAM_TIMEOUT    Seconds to wait for SpeechMetadata (default 30)
"""

import argparse
import json
import logging
import os
import sys
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, urlunparse

try:
    import websocket  # websocket-client (pip3 install websocket-client)
except ImportError:
    sys.stderr.write(
        "ERROR: websocket-client is required.\n"
        "  pip3 install websocket-client\n"
    )
    sys.exit(1)

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("dg-tts-adapter")

STEM_URL    = os.environ.get("DEEPGRAM_STEM_URL", "http://localhost:8080").rstrip("/")
FALLBACK_MODEL = os.environ.get("DEEPGRAM_TTS_MODEL", "flux-hannah-en")
SAMPLE_RATE = int(os.environ.get("DEEPGRAM_TTS_SR", "16000"))
TIMEOUT_S   = float(os.environ.get("DEEPGRAM_TIMEOUT", "30"))


def stem_ws_url(model: str, sample_rate: int = 0) -> str:
    """Convert the stem HTTP base URL to a ws(s) /v2/speak URL."""
    p = urlparse(STEM_URL)
    scheme = "wss" if p.scheme == "https" else "ws"
    return f"{scheme}://{p.netloc}/v2/speak?model={model}&encoding=linear16&sample_rate={sample_rate or SAMPLE_RATE}"


def synthesize(text: str, voice: str, api_key: str, sample_rate: int = 0) -> bytes:
    """
    Call the self-hosted Deepgram stem's /v2/speak WebSocket and return
    raw 16-bit PCM audio bytes.

    Protocol (from uneeq-kit README "Smoke test"):
      1. Open WS to /v2/speak?model=<voice>&encoding=linear16&sample_rate=<sr>
         with the API key as the `token` subprotocol.
      2. Send {"type":"Speak","text":"..."}
      3. Send {"type":"Flush"}
      4. Collect binary frames (audio) until a JSON frame with
         type=="SpeechMetadata" arrives.
    """
    ws_url = stem_ws_url(voice, sample_rate)
    log.info("synthesizing %d chars, voice=%s, ws=%s", len(text), voice, ws_url)

    subprotocols = ["token", api_key] if api_key else None
    ws = websocket.create_connection(
        ws_url,
        subprotocols=subprotocols,
        timeout=TIMEOUT_S,
    )
    try:
        ws.send(json.dumps({"type": "Speak", "text": text}))
        ws.send(json.dumps({"type": "Flush"}))

        chunks: list[bytes] = []
        deadline = time.monotonic() + TIMEOUT_S
        while time.monotonic() < deadline:
            ws.settimeout(max(1.0, deadline - time.monotonic()))
            raw = ws.recv()
            if isinstance(raw, bytes):
                chunks.append(raw)
            else:
                # JSON control frame — check for completion.
                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                mtype = msg.get("type", "")
                if mtype == "SpeechMetadata":
                    log.info("SpeechMetadata received, %d audio bytes", sum(len(c) for c in chunks))
                    break
                if mtype == "Error":
                    raise RuntimeError(f"Deepgram TTS error: {msg}")
                # Mark / WordsTimestamped / other — skip.
        else:
            raise TimeoutError(f"timed out after {TIMEOUT_S}s waiting for SpeechMetadata")

        return b"".join(chunks)
    finally:
        try:
            ws.close()
        except Exception:
            pass



class AdapterHandler(BaseHTTPRequestHandler):
    """Minimal HTTP handler implementing the BYO v1 contract."""

    def do_POST(self):
        # Only accept the root path (BYO v1: POST {tts_url} with no path).
        if self.path not in ("", "/"):
            self._json(404, {"error": "not found"})
            return

        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
        except (json.JSONDecodeError, ValueError):
            self._json(400, {"error": "invalid JSON body"})
            return

        text  = body.get("text", "")
        voice = body.get("preset", "") or FALLBACK_MODEL
        key   = body.get("apiKey", "")

        if not text.strip():
            self._json(400, {"error": "'text' is required"})
            return

        # Optional high-quality mode: a caller (the kiosk tester / kiosk-managed
        # voice) may ask for a specific rate; the response is then a WAV container
        # so consumers read the rate from the header. WITHOUT it the contract is
        # unchanged: raw 16 kHz s16le PCM (what Renny's BYO v1 path expects).
        try:
            req_sr = int(body.get("sample_rate") or 0)
        except (TypeError, ValueError):
            req_sr = 0
        if req_sr and not (8000 <= req_sr <= 48000):
            self._json(400, {"error": "sample_rate must be 8000-48000"})
            return

        log.info("request: %d chars, voice=%s, sr=%s", len(text), voice, req_sr or SAMPLE_RATE)
        t0 = time.monotonic()
        try:
            pcm = synthesize(text, voice, key, req_sr)
        except Exception as e:
            log.exception("synthesis failed")
            self._json(502, {"error": str(e)})
            return
        dt = time.monotonic() - t0
        log.info("done in %.2fs, %d bytes of PCM", dt, len(pcm))

        if req_sr:
            import struct
            hdr = (b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVEfmt "
                   + struct.pack("<IHHIIHH", 16, 1, 1, req_sr, req_sr * 2, 2, 16)
                   + b"data" + struct.pack("<I", len(pcm)))
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(hdr) + len(pcm)))
            self.end_headers()
            self.wfile.write(hdr + pcm)
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(pcm)))
        self.end_headers()
        self.wfile.write(pcm)

    def do_GET(self):
        # Health-check endpoint.
        if self.path in ("/health", "/"):
            self._json(200, {"status": "ok", "stem": STEM_URL, "model": FALLBACK_MODEL})
        else:
            self._json(404, {"error": "not found"})

    def _json(self, code: int, obj: dict):
        payload = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format, *args):  # noqa: A002  (matches BaseHTTPRequestHandler)
        # Suppress default stderr logging; use the logger instead.
        pass


def main():
    parser = argparse.ArgumentParser(description="Deepgram TTS adapter (BYO v1 → /v2/speak)")
    parser.add_argument("--port", type=int, default=int(os.environ.get("ADAPTER_PORT", 8081)),
                        help="HTTP port to listen on (default 8081)")
    parser.add_argument("--host", default="0.0.0.0", help="Bind address (default 0.0.0.0)")
    args = parser.parse_args()

    log.info("Deepgram TTS adapter starting")
    log.info("  stem URL     : %s", STEM_URL)
    log.info("  fallback model: %s", FALLBACK_MODEL)
    log.info("  sample rate  : %d Hz", SAMPLE_RATE)
    log.info("  listening on : %s:%d", args.host, args.port)

    server = HTTPServer((args.host, args.port), AdapterHandler)
    # Allow multiple concurrent requests (Renny may pipeline).
    server.daemon_threads = True  # type: ignore[attr-defined]
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("shutting down")
        server.server_close()


if __name__ == "__main__":
    main()
