# Deploying the Digital Human Kiosk against YOUR endpoints (BYO)

Reference-architecture validation flow: you already run **NVIDIA RAG** and/or
**Riva** on your own clusters. Deploy **our components** from this repo's
charts and plug in **your endpoints** — every NVIDIA touchpoint (NIM LLM, RAG,
Riva STT, Riva TTS) is a substitutable endpoint. For the full per-chart
reference see [CHARTS.md](CHARTS.md).

The agreed reference model: **Gemma 4 26B (NIM-certified, NVFP4)** —
`nvcr.io/nim/google/gemma-4-26b-a4b-it` — the kiosk's default.

## 0. Source + access

```bash
git clone https://github.com/uneeq-digital-humans/miniprem
cd miniprem/kubernetes
```

All image versions are **pinned in each chart's values** — no image flags
needed anywhere below. Two Harbor credentials (provided by UneeQ):
**robot A** pulls the kiosk-stack images (`dell-isg-containers` project);
**robot B** pulls the renderer image (separate UneeQ project). The
miniprem-monitor image is public (anonymous pull).

```bash
kubectl create ns uneeq
kubectl -n uneeq create secret docker-registry harbor-credentials \
  --docker-server=cr.uneeq.io --docker-username='robot$<robot-a>' --docker-password='<token-a>'
kubectl -n uneeq create secret docker-registry renny-credentials \
  --docker-server=cr.uneeq.io --docker-username='robot$<robot-b>' --docker-password='<token-b>'
```

## 1. Fresh node? (optional) — Ansible CNS install

`../ansible/` stands up NVIDIA Cloud Native Stack (driver → containerd →
kubeadm → GPU operator) on a bare Ubuntu box. Skip if you have a cluster.

## 2. Renderer (Renny) — pointed at YOUR Riva TTS

```bash
helm install renny ./renny -n uneeq \
  --set renderer.tts.rivaServerAddr="<your-riva-tts-host>:50051"
# defaults: PINNED renderer build + the renny-credentials secret (robot B)
# leave rivaServerAddr empty to use the local riva-tts (magpie) chart instead
```
Single-GPU node: add `--set deployment.replicas=1` (default is appliance
sizing). UneeQ platform credentials go in its values (secret), never in git.

## 3. Speech-to-text — proxy-only mode against YOUR Riva ASR

```bash
helm install digitalhuman-asr ./digitalhuman-asr -n uneeq \
  --set nemotron.enabled=false \
  --set proxy.rivaGrpcUrl="<your-riva-asr-host>:50051"
```
`nemotron.enabled=false` deploys ONLY the WebSocket proxy (no GPU, no model).
Set `enabled=true` to run the ASR NIM in-pod instead. NOTE: the kiosk streams
`en-US` by default — your Riva must serve a streaming model for the kiosk's
configured language.

## 4. Conversation backend (rag-adapter) — pointed at YOUR RAG / LLM

```bash
helm install rag-adapter ./digitalhuman-rag-adapter/chart -n uneeq \
  --set settingsPassword="<pick-a-settings-password>" \
  --set llm.url="http://<your-gemma-nim-host>:8000" \
  --set llm.model="google/gemma-4-26B-A4B-it" \
  --set ragMode="blueprint" \
  --set rag.baseUrl="http://<your-rag-server>:8081" \
  --set nvIngest.url="http://<your-nv-ingest>:7670"

# Shared document store + blueprint ingest pipeline (two-way documents):
kubectl -n uneeq set env deploy/rag-adapter \
  MILVUS_DB_PATH="http://<your-blueprint-milvus>:19530" \
  INGESTOR_URL="http://<your-ingestor-server>:8082"
```
- `llm.model` must EXACTLY match the id your NIM serves at `/v1/models`.
- `settingsPassword` gates the kiosk Settings UI. Unset = factory default
  `digitalhuman` — fine for lab validation, change for anything customer-facing.
- **Image/OCR facts**: if your blueprint captions through an OpenAI-style NIM
  (Gemma), point `APP_NVINGEST_CAPTIONENDPOINTURL` at the adapter's
  `/caption/v1/chat/completions` shim (nv-ingest's native `<img>` caption
  dialect is not OpenAI-compatible). `scripts/apply-rag-integration.sh`
  applies this plus the multimodal-extraction envs in one pass.

## 5. Host agent (host-helper)

```bash
helm install host-helper ./host-helper -n uneeq
```
No customization needed. The appliance-only host mounts (audio/display
control, on-node model pulls) are **opt-in** (`hostIntegration.enabled`,
default off) — the pod starts on any cluster with no host prerequisites.
GPU/VRAM readouts and service health work out of the box; appliance-only
features report unavailable. Appliances enable full integration with
`-f ../values/host-helper-values-cns.yaml`.

## 6. Kiosk UI

```bash
helm install digitalhuman-interface ./digitalhuman-interface -n uneeq \
  --set env.KIOSK_RAG_URL="http://<your-rag-server>:8081"   # BYO RAG (omit for on-box blueprint)
```
The image's nginx proxies (`/v1`, `/rag-admin`, `/host-admin`, `/api/asr`,
`/rag`) resolve sibling services by short name in the release namespace;
override any of them via the chart's `env:` map (`KIOSK_ADAPTER_URL`,
`KIOSK_HOST_HELPER_URL`, `KIOSK_ASR_URL`, `KIOSK_RAG_URL`). A missing or
not-yet-installed upstream 502s its own route — it never prevents the kiosk
from starting. Persona IDs, prompts, endpoints, theme: all set at runtime in
**Settings** (gear icon) or the on-box seed file; nothing is baked in.

## 7. Remote mic (QR) — two options

| Option | How | Notes |
|---|---|---|
| **UneeQ-hosted** (default) | enable in Settings | plug-and-play; 1:1 session mapping |
| **Self-hosted** | `helm install remote-mic-relay ./remote-mic-relay -n uneeq` | ConfigMap-sourced (no image); bring your own ingress/FQDN; API-key securable |

## 8. Validate

1. Kiosk loads; status row (hover shows per-service truth).
2. Start a conversation → speech in (your Riva ASR) → answer (your Gemma NIM)
   → voice out (your Riva TTS).
3. Settings ▸ Test chat → confirms the LLM/RAG path without speaking.
4. Upload a scanned/table PDF → appears in YOUR RAG collections → ask about it.
5. Scan the QR from a phone → talk → background the phone ~10 s → kiosk
   returns to idle+QR.

## Runtime support note

The in-kiosk **LLM download/switch** controls require kubeadm + the NVIDIA NIM
Operator (they drive NIMCache/NIMService CRDs); elsewhere they disable
themselves with a hint. Everything in THIS guide works on any conformant
cluster — the kiosk only needs HTTP/gRPC reachability to your services.
