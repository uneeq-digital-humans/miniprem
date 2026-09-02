# Deepgram (local) — self-hosted STT + TTS for the all-in-one appliance

Brings the self-hosted Deepgram stack (uneeq-kit) onto the all-in-one box and
wires it into both the kiosk (STT) and Renny (TTS). Runs as the `deepgram`
compose profile alongside the default Riva stack — Riva stays up and switchable.

## What you get

| Piece | Service | Port | Used by |
|---|---|---|---|
| Deepgram stem (api) | `deepgram-api` | 8080 | kiosk STT (`/v1/listen` Nova-3), adapter TTS (`/v2/speak` Flux) |
| STT engine (GPU) | `deepgram-engine-stt` | (internal) | stem |
| TTS engine (GPU) | `deepgram-engine-tts` | (internal) | stem |
| TTS adapter (BYO) | `deepgram-tts-adapter` | 8086 | Renny (via DHOP "Custom TTS") |

Both engines share GPU 0 (validated co-resident on an RTX PRO 6000 by the
kit). With Gemma + Riva + Renny already on the card, watch VRAM — if it's tight,
stop `riva-asr`/`riva-tts` while running the Deepgram profile.

## 1. Prerequisites

- NVIDIA driver >= 595.x, Docker with the `nvidia` runtime (already required
  for the default stack).
- Outbound HTTPS to `license.deepgram.com` (license validation) and
  `deepgram-self-hosted.s3.us-east-2.amazonaws.com` (one-time model download).
- The UneeQ Deepgram images in Harbor (`cr.uneeq.io/deepgram/*`) — pulled with
  the same Harbor robot account used for Renny/kiosk images.

## 2. Get the self-hosted API key

Existing Deepgram project keys were created BEFORE self-hosted access was
enabled, so they will NOT license the stack.

1. Deepgram Console → the UneeQ project → **Settings → API Keys → Create Key**.
2. New keys pick up the project's self-hosted entitlements at creation time.
3. Put it in `.env` as `DEEPGRAM_API_KEY`.

> The same key is used by (a) the stack's license handshake, (b) kiosk STT
> (sent as the WS `token` subprotocol in Settings), and (c) Renny TTS
> (stored in the DHOP persona as the BYO `apiKey`). One key, three roles.

**CRITICAL — the key goes in the TOML, not (only) the env var.** Verified on
t2 2026-09-01 by booting the real engine container three ways:

| `[license] key` in TOML | env var set | Result |
|---|---|---|
| absent | yes | exits `Error: Missing license configuration.` |
| present (dummy) | no | mTLS handshake completes → `401 Unauthorized` (expected with a dummy) |
| present (real) | — | licenses, decrypts models, serves |

The engine reads the key **only** from `[license] key`; the env var alone does
not count (matches the official Deepgram self-hosted docs: "Replace the value
at `[license.key]` with your API key secret"). The repo ships
`deepgram/config/*.toml.template` (with a `{DEEPGRAM_API_KEY}` placeholder) +
`render-configs.sh`:

```sh
cd <repo>/docker/allinone
# compose: in-place render (writes deepgram/config/*.toml, 0600) — up.sh does
# this automatically for the deepgram/all profiles:
./render-configs.sh
# k8s node (t2): render locally, scp the 3 files to /opt/deepgram/config/
./render-configs.sh --to /tmp/dgconfig
scp /tmp/dgconfig/*.toml admin@t2:/tmp/ && ssh admin@t2 'sudo cp /tmp/*.toml /opt/deepgram/config/'
```

`t2-deploy-deepgram.sh` refuses to run until all three node configs carry a
key (prints the exact render+scp steps if not).

## 3. Download the model files

Links come from `uneeq-kit/deployment_files/uneeq.deployment.<date>.txt`
(stable; re-download any time). **Verified 2026-08-31 from both the Mac and
t2 (10.0.2.81): every URL returns 200/206 directly** — the bucket allows
both IPs. The only 403s ever seen came from mistyped model hashes, not IP
blocks. **Filenames must not be changed** (the engine resolves models by
hash, README §3).

Only **3 files are required** (README: everything else — diarizer/entity/
batch — is optional and each loaded model costs VRAM):

| File | Goes in |
|---|---|
| `nova-3-general.en.streaming.40bd3654.dg` | `models-stt/` |
| `flux-general-en.caf79279.dg` | `models-stt/` |
| `flux-tts.f94b1bd5.dgv2` | `models-tts/` |

Download **directly on the box** (~13.3 GB total):

```sh
B="https://deepgram-self-hosted.s3.us-east-2.amazonaws.com/<project-uuid>"
mkdir -p ~/deepgram/models-stt ~/deepgram/models-tts && cd ~/deepgram
curl -fSL --retry 3 -o models-stt/nova-3-general.en.streaming.40bd3654.dg "$B/models/nova-3-general.en.streaming.40bd3654.dg" &
curl -fSL --retry 3 -o models-stt/flux-general-en.caf79279.dg       "$B/models/flux-general-en.caf79279.dg" &
curl -fSL --retry 3 -o models-tts/flux-tts.f94b1bd5.dgv2             "$B/models-v2/flux-tts.f94b1bd5.dgv2" &
wait
```

If a link ever 403s again: the URLs are scoped to the project UUID in the
path — re-request from Conner Hughes (support@deepgram.com, ref "self-hosted
access").

Known TLS quirk (checked 2026-08-31, EXPECTED — official Deepgram docs
confirm it): `license.deepgram.com` uses **mTLS** and serves a private-CA
chain. Plain `curl`/openssl against it fail (incomplete chain, spurious
errors) — "This is expected, correct behavior and does not indicate a problem
with the service itself" (developers.deepgram.com). The containers carry the
mTLS client cert and license fine (verified on t2: the engine completes the
handshake and returns a proper `401 Unauthorized` for a dummy key, then
licenses on the real key). Only act on it if the engines log TLS/cert errors
at first boot.

## 4. Start the stack — compose all-in-one

```sh
cd miniprem/docker/allinone
cp .env.example .env     # first time; then fill DEEPGRAM_API_KEY (+ tags if mirrored)
./up.sh deepgram         # or: ./up.sh all  (with rag)
```

First boot decrypts the models against the key and warms the engines — allow
1–2 minutes.

```sh
docker compose -f docker-compose.allinone.yml logs -f deepgram-engine-tts
# expect: "Engine successfully configured to serve Aura-3 traffic"
docker compose -f docker-compose.allinone.yml logs -f deepgram-engine-stt
```

### 4b. Kubernetes boxes (t2 / Dell test box)

The box runs the miniprem **k8s** stack (renny + gemma NIM pods) instead of
the compose harness — same Deepgram services, deployed as pods:

```sh
# on the box (as admin):
export HARBOR_USERNAME='robot$charlie_uneeq_test' HARBOR_PASSWORD='<from Harbor>'
./kubernetes/scripts/t2-deploy-deepgram.sh "$DEEPGRAM_API_KEY"
```

The script: logs the Harbor robot in, pulls the two stem images, imports them
into containerd (k8s.io ns — docker's store is invisible to kubelet), builds
the adapter image locally, creates the `deepgram` namespace + secrets, and
applies `kubernetes/manifests/deepgram.yaml` (stem NodePort 30080, adapter
NodePort 30086, both engines on GPU 0).

Models/configs live at `/opt/deepgram/{config,models-stt,models-tts}` on the
node (same files as §3). Port mapping differs from compose:

| | compose all-in-one | k8s (t2) |
|---|---|---|
| stem | `http://localhost:8080` | `http://<box>:30080` |
| TTS adapter | `http://<box>:8086` | `http://<box>:30086` |

GPU note: the box already runs renny + gemma (≈64 GB of 98 GB used). The two
Deepgram engines add ~10–14 GB — watch `nvidia-smi` during first model load.

Smoke test (on the box):

```sh
curl "localhost:30080/v1/models?tts=true"
curl -s localhost:30086/health
sudo kubectl -n deepgram get pods     # 4/4 Running
```

Smoke test (compose, on the box):

```sh
curl "localhost:8080/v1/models?tts=true"                       # loaded models
curl -s localhost:8086/health                                  # TTS adapter
```

## 5. Kiosk STT — Deepgram (local)

1. Settings (⚙) → Advanced → **Speech to Text (STT)**.
2. Provider: **Deepgram (local · self-hosted)**.
3. **Deepgram (local) endpoint**: leave **blank** — the default. The kiosk's
   own nginx already serves the kiosk and proxies a built-in `/api/dg/` route
   to the stem, so the mic streams same-origin
   (`wss://<kiosk-host>/api/dg/v1/listen`) over the secure context the mic
   needs. Only fill this in when the stem lives on ANOTHER box (full base URL,
   e.g. `http://10.0.2.81:30080`), which must then serve TLS to be reachable
   from the https kiosk.
4. **Deepgram Self-Hosted API Key**: the key from step 2 → **Verify Key**.
5. **Apply & restart** (~10–20 s).

The kiosk now streams the mic to `wss://<kiosk-host>/api/dg/v1/listen?model=nova-3…`
(Nova-3 streaming, 16 kHz linear16) via the built-in proxy → the stem. Live
transcripts show in Settings → Audio → "Test Voice Transcription", and in the
conversation loop.

Switching back to Riva: same panel → provider **NVIDIA Riva STT (GPU)** →
Apply. (The choice is stored in the kiosk's config overrides and, on MiniPrem,
persisted to the box's kiosk-config.)

Remote (QR phone) mic: uses the same provider/key as the on-kiosk mic — no
separate config.

## 6. Renny TTS — Deepgram (Flux) via DHOP

Renny's TTS synthesis lives in the conversation layer and already speaks the
**Custom (BYO) TTS** contract. The `deepgram-tts-adapter` translates BYO v1
HTTP → the stem's `/v2/speak` WebSocket (Flux TTS, linear16 16 kHz out).
No Renny code change; the persona just points at the adapter.

### In the UneeQ Admin Portal (DHOP) — what to set

Persona → Voice / TTS settings:

| Field | Value |
|---|---|
| **TTS Provider** | **Custom** (BYO) |
| **TTS URL** (`tts_url`) | `http://<kiosk-box-ip>:8086` — HTTP, the adapter's v1 endpoint. Must be reachable from the Renny container (same docker network: use `http://host.docker.internal:8086` if Renny runs elsewhere, or the box's LAN IP). |
| **TTS API Key** (`tts_api_key`) | the same `DEEPGRAM_API_KEY` (any non-empty value passes through to the stem) |
| **Voice** (`tts_voice` / preset) | `flux-hannah-en` — any Flux TTS voice loaded by the TTS engine (see `curl localhost:8080/v1/models?tts=true`) |

Then **Test Speech** in the portal to audition (the preview endpoint hits the
BYO URL with the live form values — for Custom/BYO it performs the real
handshake, so a working adapter returns audible audio).

Runtime flow: session start → session-service forwards the persona's
`tts_url` + `tts_api_key` to Renny → Renny's tts-proxy POSTs
`{"text","preset","apiKey"}` → adapter → stem `/v2/speak` → PCM back.

> Note: the persona-level BYO `tts_url`/`tts_api_key` are forwarded whenever
> set, independent of `tts_source` — so no workspace TTS config is needed for
> this to work on a private-pool/mini-prem box.

### Adapter knobs (env on `deepgram-tts-adapter`)

| Var | Default | Meaning |
|---|---|---|
| `DEEPGRAM_STEM_URL` | `http://deepgram-api:8080` | stem base URL (compose-internal) |
| `DEEPGRAM_TTS_MODEL` | `flux-hannah-en` | fallback voice when the persona sets none |
| `DEEPGRAM_TTS_SR` | `16000` | output sample rate — must match what the conversation layer expects for BYO PCM |
| `DEEPGRAM_TIMEOUT` | `30` | seconds to wait for `SpeechMetadata` |

## 7. Verifying end-to-end (Dell test box)

```sh
# 1. stack
docker compose -f docker-compose.allinone.yml ps        # 4 deepgram services healthy
curl localhost:8080/v1/models?tts=true
# 2. kiosk STT: Settings → Advanced → STT → Deepgram (local) → Test in Audio tab
# 3. Renny TTS: Portal → persona → Test Speech (Custom TTS) — should be audible
# 4. full loop: talk to the kiosk; transcript in kiosk, Renny replies with Flux voice
```

If Renny is SILENT: check the Renny container's logs for the TTS URL it was
given (it must be the adapter, not the stem), and confirm the adapter sees the
POSTs (`docker compose logs deepgram-tts-adapter`). A 502 from the adapter
means the stem rejected the key or the voice is unloaded.

## Ports recap (no conflicts with the default stack)

80 kiosk · 8000 gemma · 8009 riva STT · 8080 **Deepgram stem** · 8081 rag
(rag profile) · 8085 rag-adapter · **8086 Deepgram TTS adapter** · 9000/50051
riva TTS · 6006 phoenix.
