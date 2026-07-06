# UneeQ Digital-Human Kiosk — Helm Charts (plug-and-play)

Every component ships as its **own standalone Helm chart**. You can deploy the
whole stack on one box (all-in-one), or `helm install` only the pieces you need
into an **existing cluster** and point the rest at services you already run —
RAG, LLM, Riva STT/TTS, Redis, Phoenix. There is no required umbrella: each chart
installs on its own and every cross-service endpoint is a value you override.

> **Secrets are never baked into a chart.** Image pulls expect a pre-created
> `harbor-credentials` (and `ngc-registry-credentials` / `nim-credentials` for
> NVIDIA NIMs) secret in the target namespace. Create those out-of-band.

---

## Chart inventory

| Chart | Path | Deploys | GPU | Standalone install |
|---|---|---|:--:|---|
| **digitalhuman-interface** | `digitalhuman-interface/` | Kiosk SPA (nginx) + runtime config | – | `helm install dh-ui ./digitalhuman-interface -n uneeq` |
| **kiosk-ui** | `kiosk-ui/` | Front-door ingress/router to the on-box services | – | `helm install kiosk-ui ./kiosk-ui -n uneeq` |
| **renny** | `renny/` | Digital-human renderer (Vulkan/UE5) | ✅ | Appliance/Dell: `helm install renny ./renny -f values/renny-values-cns.yaml -n uneeq`³ |
| **digitalhuman-asr** | `digitalhuman-asr/` | Riva STT NIM **+** browser WS proxy (local **or** external mode) | ✅¹ | `helm install asr ./digitalhuman-asr -n uneeq` |
| **riva-tts** | `riva-tts/` | Magpie TTS NIM (Riva) | ✅ | `helm install tts ./riva-tts -n uneeq` |
| **nim-gemma** | `nim-gemma/` | Gemma LLM (NVIDIA NIM) | ✅ | `helm install gemma ./nim-gemma -n nim-models` |
| **digitalhuman-rag-adapter** | `digitalhuman-rag-adapter/chart/` | UneeQ↔NVIDIA RAG middleware (+optional Redis) | – | `helm install rag-adapter ./digitalhuman-rag-adapter/chart -n uneeq` |
| **host-helper** | `host-helper/` | Privileged on-box agent (GPU/audio/display/NIM-pull) | ✅² | `helm install host-helper ./host-helper -n uneeq` |
| **remote-mic-relay** | `remote-mic-relay/` | Phone↔kiosk WebSocket relay (no image build) | – | `helm install relay ./remote-mic-relay -n uneeq` |
| **miniprem-monitor** | `miniprem-monitor/chart/` | Cluster/GPU health UI | – | `helm install monitor ./miniprem-monitor/chart -n uneeq` |
| **phoenix** | `phoenix/` | LLM/RAG tracing UI (observability) | – | `helm install phoenix ./phoenix -n uneeq` |

¹ `digitalhuman-asr` needs a GPU **only in local mode**; in external mode it runs
just the WS proxy (no GPU). ² `host-helper` requests a GPU so `nvidia-smi` works
directly; not required if you don't need per-process VRAM stats. ³ `renny`
ships its full default set as an install-time overlay — **always install with `-f`** plus
DHOP/TTS creds (`--set renderer.dhop.url=… renderer.dhop.apiKey=…`). **Pick the overlay by
profile — this sets render quality:**
- **Appliance / Dell kiosk (dedicated GPU): `values/renny-values-cns.yaml`** → `qualityLevel:
  miniprem` (higher quality for on-box hardware), no node selector (single server).
- Cloud EKS/AKS (shared/time-sliced GPUs): `values/renny-values.yaml` / `-aks.yaml` →
  `web` quality (balanced for cloud).

The chart template defaults `RENNY_QUALITY_LEVEL` to `web`, so an appliance MUST use the
`-cns` overlay (or `--set renderer.qualityLevel=miniprem`) or it will render at web quality.

---

## Endpoint substitution map (Bring-Your-Own services)

Each consumer chart reaches its dependencies through these value keys. Override
the key to point at an existing service, and **skip installing** the matching
producer chart.

| Consumer chart | Value key | Points at | Default (local) | Producer chart to skip if external |
|---|---|---|---|---|
| digitalhuman-rag-adapter | `rag.baseUrl` | RAG retrieve/generate | `http://rag-server.advanced-rag…:8081` | NVIDIA RAG blueprint |
| digitalhuman-rag-adapter | `llm.url` | LLM (OpenAI-compatible) | `http://gemma.nim-models…:8000` | `nim-gemma` |
| digitalhuman-rag-adapter | `nvIngest.url` | Document ingestion | `http://nv-ingest.advanced-rag…:7670` | NVIDIA RAG blueprint |
| digitalhuman-rag-adapter | `phoenix.otlpEndpoint` | Tracing | `http://phoenix.uneeq…:6006/v1/traces` | `phoenix` |
| digitalhuman-rag-adapter | `redis.url` (+`redis.enabled=false`) | Session memory | built-in Redis | (built-in) |
| digitalhuman-asr | `nemotron.enabled=false` + `proxy.rivaGrpcUrl` | **Riva STT (separate cluster)** | `localhost:50051` sidecar | runs NIM-less; no GPU |
| renny | `renderer.tts.rivaServerAddr` | **Riva TTS gRPC** | `""` → localhost | `riva-tts` |
| renny | `renderer.dhop.url` | UneeQ DHOP platform | (required) | n/a (always external) |
| digitalhuman-interface | `config.stt.rivaUrl` | STT WS endpoint | `http://digitalhuman-asr.miniprem` | – |
| digitalhuman-interface | `config.conversation.rag.endpoint` / `.searchEndpoint` | RAG (kiosk-owned call) | `http://localhost:8081/v1/*` | – |
| digitalhuman-interface | `config.conversation.nim.endpoint` | LLM (kiosk-owned call) | `http://localhost:8000/v1/chat/completions` | – |
| digitalhuman-interface | `config.backend.endpoints.ws/http` | WebSocket API | `ws://digitalhuman-api.miniprem/ws` | – |
| kiosk-ui | `ingress.upstreams.{ragAdapter,hostHelper,monitor,asrProxy}` | proxied upstreams | in-cluster service names | – |

---

## Recipes

### A. All-in-one (single GPU box) — deploy everything
Use `scripts/deploy-allinone.sh` (sequences every chart with on-box defaults), or
`helm install` each chart with its stock values. Nothing to override — every
endpoint defaults to the local service.

### B. Kiosk into your existing cluster — BYO RAG + LLM
Deploy the kiosk-facing pieces; point the adapter at your services; skip the
NVIDIA RAG blueprint and `nim-gemma`.
```bash
helm install dh-ui  ./digitalhuman-interface -n uneeq
helm install renny  ./renny -f values/renny-values-cns.yaml -n uneeq --set renderer.dhop.url=wss://…  # miniprem quality
helm install rag-adapter ./digitalhuman-rag-adapter/chart -n uneeq \
  --set rag.baseUrl=https://rag.internal.example \
  --set llm.url=https://llm.internal.example/v1 \
  --set nvIngest.url=https://ingest.internal.example
```

### C. Point Riva STT/TTS at a SEPARATE Riva cluster
No local Riva GPUs; the kiosk consumes Riva hosted elsewhere.
```bash
# STT: run only the browser WS proxy, dial the remote Riva gRPC
helm install asr ./digitalhuman-asr -n uneeq \
  --set nemotron.enabled=false \
  --set proxy.rivaGrpcUrl=riva.datacenter.example:50051

# TTS: tell the renderer to dial the remote Riva
helm upgrade renny ./renny -n uneeq \
  --set renderer.tts.rivaServerAddr=riva.datacenter.example:50051
# → do NOT install riva-tts locally
```
> Cross-cluster Riva gRPC must be network-reachable and should be TLS/mTLS-secured
> (plain `:50051` is not encrypted). Embedding dim/model must match the kiosk's.

### D. Self-hosted remote-mic relay only
```bash
helm install relay ./remote-mic-relay -n uneeq        # NodePort 30808 by default
# then set the kiosk's remote-mic websocketUrl to ws://<nodeIP>:30808
```

---

## Pointing the kiosk at external RAG / LLM / STT / TTS (3 ways)

The kiosk does not have to be all-in-one. Each backend endpoint can be set in
**three** places, in increasing precedence:

1. **Helm values** (deploy-time) — see the substitution map above.
2. **Kiosk server conf file** (hand-editable, survives image pulls):
   `/data/kiosk-defaults.json` on the rag-adapter PVC. A generic dict deep-merged
   UNDER the UI overrides — set any config key by hand. Example:
   ```json
   {
     "conversation": {
       "rag":  { "searchEndpoint": "https://rag.dc.example/v1/search",
                 "llmEndpoint":    "https://rag.dc.example/v1/generate",
                 "embeddingEndpoint": "https://embed.dc.example/v1",
                 "rerankerEndpoint":  "https://rerank.dc.example/v1",
                 "vdbEndpoint":       "https://milvus.dc.example:19530" },
       "nim":  { "endpoint": "https://llm.dc.example/v1/chat/completions",
                 "model": "google/gemma-4-26b-a4b-it" }
     },
     "stt": { "provider": "riva", "rivaUrl": "https://asr.dc.example" }
   }
   ```
3. **Kiosk Settings UI** (runtime, highest precedence) — Advanced ▸ *Advanced
   endpoints* (RAG retriever, NIM generate, embedding, reranker, VDB, RAG-LLM) and
   Advanced ▸ *Speech to Text* (Riva endpoint / Deepgram). Persisted to
   `/data/kiosk-config.json` on the box.

**STT** (`stt.rivaUrl`) is consumed by the browser (RivaStreamService → the
`/api/asr` WS proxy), so it's a true kiosk setting — empty = same-origin proxy;
set it to a remote `digitalhuman-asr` proxy to use Riva STT elsewhere.

**TTS is different:** the **renderer (Renny) dials Riva TTS**, not the browser — so
there is no live kiosk-UI knob for it. Point TTS at an external Riva via the renny
Helm value `renderer.tts.rivaServerAddr` (or Renny's `RIVA_SERVER_ADDR` env). A
kiosk-settings field for it would require host-helper to patch+restart the Renny
deployment (possible follow-up; not wired today).

## Notes
- **Namespace** is taken from `-n <ns>` / `--namespace`; charts use
  `.Release.Namespace`, so install into whatever namespace you like.
- **`digitalhuman-rag-adapter`** and **`miniprem-monitor`** keep their chart in a
  `chart/` subdirectory (the dir root also holds app source); all others have the
  chart at the directory root.
- Run `helm lint <chart>` / `helm template <chart>` before installing to confirm
  your overrides render as expected.
