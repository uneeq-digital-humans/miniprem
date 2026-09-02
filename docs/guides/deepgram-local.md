# Deepgram (Self-Hosted) — STT & TTS for MiniPrem

Self-hosted Deepgram brings both **speech-to-text** (Nova-3 streaming) and
**text-to-speech** (Flux) onto the MiniPrem box — no audio or transcripts leave
the appliance. It runs alongside the existing NVIDIA Riva stack; you switch per
deployment, no rebuild.

## What's included

| Capability | Service | How it's used |
|---|---|---|
| STT (Nova-3 streaming) | Deepgram "stem" + STT engine | kiosk → Settings → STT provider **Deepgram (local)** |
| TTS (Flux) | TTS engine + TTS adapter | UneeQ Admin Portal → persona TTS provider **Deepgram (Self-Hosted)** |
| STT cloud fallback | — | unchanged: STT provider **Deepgram** (cloud API) still works |

The TTS adapter is a small sidecar that translates the portal's "custom TTS"
contract to the Deepgram stem's WebSocket — Renny itself needs no code change.

## Prerequisites

- GPU with ≥ ~14 GB free (engines share card 0 with Riva/Gemma/Renny).
- Outbound HTTPS from the box to `license.deepgram.com` (license) and the
  model S3 bucket (one-time model download).
- MiniPrem with the Deepgram images available in your registry
  (`api-uneeq`, `engine-uneeq` under the `deepgram` project) + the model files
  and TOML configs (see the deployment kit — `uneeq-kit`).

## Setup

### 1. Get a self-hosted API key

Existing Deepgram project keys predate self-hosted access and will NOT license
the stack. Create a **new** key in the Deepgram Console (project → Settings →
API Keys → Create). The same key is used by:

1. the stack's license handshake,
2. the kiosk's STT (Settings),
3. the persona's TTS API Key (portal).

### 2. Place models + configs

Filenames must match exactly (links come with the deployment kit):

```
config/api.toml
config/engine-stt.toml
config/engine-tts.toml
models-stt/nova-3-general.en.streaming.40bd3654.dg
models-stt/flux-general-en.caf79279.dg
models-tts/flux-tts.f94b1bd5.dgv2
```

- **Docker all-in-one box:** files under `miniprem/docker/allinone/deepgram/`,
  key in `.env` as `DEEPGRAM_API_KEY`.
- **Kubernetes box:** files under `/opt/deepgram/{config,models-stt,models-tts}`,
  then run `kubernetes/scripts/t2-deploy-deepgram.sh "$DEEPGRAM_API_KEY"`.

### 3. Start

```sh
# Docker all-in-one:
./up.sh deepgram        # (or ./up.sh all with RAG)

# Kubernetes (on the box, robot creds in env):
./kubernetes/scripts/t2-deploy-deepgram.sh "$DEEPGRAM_API_KEY"
```

First boot decrypts and warms the models — allow 1–2 minutes.

| | Docker all-in-one | Kubernetes |
|---|---|---|
| stem (STT WS + TTS WS) | `http://localhost:8080` | `http://<box-ip>:30080` |
| TTS adapter (custom TTS) | `http://<box-ip>:8086` | `http://<box-ip>:30086` |

Health checks:

```sh
curl "localhost:8080/v1/models?tts=true"     # k8s: localhost:30080
curl -s localhost:8086/health                # k8s: localhost:30086
```

## Configure the kiosk (STT)

1. **Settings (⚙) → Advanced → Speech to Text (STT)**
2. Provider: **Deepgram (local · self-hosted)**
3. **Endpoint:** leave **blank** (default) — the kiosk's built-in `/api/dg`
   proxy carries the mic to the stem on the same box. Only set a URL (e.g.
   `http://<box-ip>:30080`) if the stem runs on a different server, in which
   case it must serve TLS.
4. **Self-Hosted API Key:** the new key → **Verify Key**
5. **Apply & restart**

Transcripts now stream from the box. Test in **Settings → Audio → Test Voice
Transcription**. Switching back to **NVIDIA Riva STT** is the same panel — the
choice persists, no rebuild.

## Configure the persona (TTS) — UneeQ Admin Portal

Persona → Voice / TTS:

| Field | Value |
|---|---|
| Provider | **Deepgram (Self-Hosted)** |
| Voice Name | `flux-hannah-en` (or any Flux voice loaded — see `/v1/models?tts=true`) |
| TTS URL | the TTS adapter: `http://<box-ip>:8086` (all-in-one) / `http://<box-ip>:30086` (k8s) |
| TTS API Key | the same self-hosted key |

Press **Test Speech** to audition before saving — it hits the real adapter.

Runtime flow: portal → session-service (forwards URL+key; the renderer sees the
BYO contract) → Renny → adapter → stem `/v2/speak` → PCM 16 kHz back to the
renderer.

## Verifying the full loop

1. `curl <stem>/v1/models?tts=true` → Flux voices listed
2. Kiosk: Settings → Audio → Test Voice Transcription → live transcript
3. Portal: persona → Test Speech → audible Flux audio
4. Talk to the kiosk: you get a transcript in and a Flux-voiced reply from Renny

## Troubleshooting

| Symptom | First check |
|---|---|
| Engine pods/containers crash-looping | License: is the key a NEW key created after self-hosted access was enabled? |
| Kiosk STT "could not start" | Is the stem reachable at the configured URL? `curl <url>/v1/models` |
| Verify Key fails | Same URL/key mismatch; check the stem logs for `401` |
| Renny silent (TTS) | Renny's logs: is it given the adapter URL (not the stem)? adapter logs: does it see POSTs? A 502 means the stem rejected the key or the voice isn't loaded |
| VRAM OOM | `nvidia-smi` — stop Riva STT/TTS while testing, or free other workloads |
| First boot very slow | Models decrypt on first start; 1–2 min is normal |

## Ports recap

Docker all-in-one: 80 kiosk · 8000 gemma · 8009 Riva STT · **8080 Deepgram
stem** · 8085 rag-adapter · **8086 Deepgram TTS adapter** · 8081 RAG (rag
profile) · 9000/50051 Riva TTS · 6006 Phoenix.

Kubernetes: stem NodePort **30080**, adapter NodePort **30086**.
