# UneeQ + NVIDIA RAG All-in-One — Build & Deploy Runbook

The end-to-end process for producing an ISO that stands up a complete on-box
UneeQ digital human powered by the local NVIDIA stack: **Renny → NVIDIA NIM
(Gemma) → NVIDIA Riva STT/TTS → NVIDIA RAG → Dell kiosk**, with the kiosk able
to manage the digital human's prompt and documents — no Flowise, no YAML edits
for the operator.

## Architecture

```
┌──────────────────── Dell GPU box (Ubuntu 24.04, kubeadm) ────────────────────┐
│  Dell kiosk (uneeq-kiosk, VITE_BRAND=dell)                                    │
│   ├─ mic ── Riva STT  → RivaStreamService → /api/asr/v1/stream (ws-proxy)     │
│   ├─ Settings ▸ "Brain" tab ── RagAdminPanel → adapter /admin (prompt + docs) │
│   └─ WebRTC ── Renny (renderer + TTS)                                         │
│                         │ conversation endpoint (set in UneeQ Admin Portal)   │
│                         ▼                                                      │
│  rag-adapter  /prompt/openai  ⇄  NVIDIA RAG  /v1/chat/completions             │
│   (Flowise-compatible facade, persona prompt, Redis session + prompt store)   │
│                         │                                                      │
│  NVIDIA RAG blueprint: rag-server + nv-ingest + Milvus + Elasticsearch        │
│  NVIDIA NIM: Gemma (LLM) + embedding + rerank                                 │
│  NVIDIA Riva: TTS (magpie) + STT (nemotron-asr + ws-proxy)                    │
│  Phoenix (observability) · Redis (sessions + prompt override)                 │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Component inventory (what's in the repo)

| Component | Location | Status |
|---|---|---|
| Renny renderer | `kubernetes/renny/` + `values/renny-values-cns.yaml` | existing |
| NIM Gemma (LLM) | `kubernetes/manifests/vllm-gemma4.yaml` | existing (validate NV-FP4 on Blackwell) |
| Riva TTS | `kubernetes/manifests/magpie-tts.yaml` | existing |
| Riva STT | `kubernetes/digitalhuman-asr/` (nemotron + ws-proxy) | existing |
| **NVIDIA RAG blueprint** | `kubernetes/nvidia-rag/rag-values.yaml` | **new — validate chart version live** |
| **RAG adapter (shim)** | `kubernetes/digitalhuman-rag-adapter/` | **new — tested** |
| **Phoenix** | `kubernetes/manifests/phoenix.yaml` | **new** |
| Dell kiosk | `uneeq-kiosk/` (`build:dell`) | existing + **Riva STT + Brain tab added** |
| **All-in-one orchestrator** | `kubernetes/scripts/deploy-allinone.sh` | **new** |

## The deploy process

### 1. Manual / direct deploy (on a box that already has the cluster)

```bash
export NGC_API_KEY=nvapi-...
export HARBOR_USERNAME='robot$uneeq+...'
export HARBOR_PASSWORD=...
export PLATFORM_KEY=... TENANT_ID=...
cd miniprem-2025/kubernetes
./scripts/deploy-allinone.sh        # sequences the full stack; every stage is a toggle
```

The script: creates namespaces + pull secrets (harbor + NGC) → GPU operator →
NIM (Gemma) → Riva TTS → Riva STT → NVIDIA RAG blueprint → rag-adapter (+Redis)
→ Phoenix → Renny → websocket-api + Dell kiosk. Re-runnable; set any
`DEPLOY_*=no` to skip a stage.

### 2. Point UneeQ at the local RAG

In the **UneeQ Admin Portal**, set the persona's conversation endpoint to:
```
http://rag-adapter.uneeq.svc.cluster.local:8085/prompt/openai
```
Renny pulls this per-persona from DHOP; no Helm change needed.

### 3. Operator self-service (the "secret sauce")

Open the kiosk → Settings (gear) → **Brain** tab:
- **Personality & Prompt** — rebrand the digital human (name, company, tone).
  Saved to the adapter (Redis-backed), live on the next message. The UneeQ
  emoji→animation tag rules stay baked in.
- **Knowledge Documents** — upload PDFs; ingested into NVIDIA RAG via nv-ingest.

> The kiosk reaches the adapter at `config.rag.adminUrl` (default `/rag-admin`).
> Add an ingress route `/rag-admin → rag-adapter:8085` so the browser can reach it.

## Building the ISO

Per `miniprem-autoinstall`:
```bash
cp -r customers/_example customers/<slug>
# edit customers/<slug>/customer.seed — set the all-in-one keys:
#   MINIPREM_SEED_ALLINONE=yes
#   MINIPREM_SEED_NGC_API_KEY=nvapi-...
#   MINIPREM_SEED_KIOSK_STT_PROVIDER=riva
#   MINIPREM_SEED_KIOSK_BRAND=dell
#   (+ the usual platform/harbor/tts keys)
build/build-iso.sh <slug> --write /dev/diskN
```
Firstboot stages run: `1-nvidia` (driver 580.x) → `2-anydesk` → `3-prereqs`
(Chrome kiosk) → `4-miniprem` (installs MiniPrem; on `ALLINONE=yes`, runs the
all-in-one deploy). Branded "PROVISIONING IN PROGRESS / SUCCESS / FAILED"
wallpaper flow is unchanged.

## Validation checklist (on a live box)

1. `kubectl get pods -A` — all NIM/Riva/RAG/adapter/renny/kiosk pods Ready.
2. `curl http://<adapter>:8085/health` — `redis_ok: true`, RAG reachable.
3. Kiosk conversation: "Hey Sophie, how are you" → grounded answer, TTS, gestures.
4. Session memory: "my name is Doug" → later "what's my name?" recalls Doug.
5. Brain tab: edit prompt → save → next reply reflects it; upload a PDF → ask about it.
6. Phoenix UI shows traces: `kubectl -n uneeq port-forward svc/phoenix 6006:6006`.

## Known gaps / TODO before GA

- **NVIDIA RAG blueprint chart version** — `RAG_CHART_VERSION` in
  `deploy-allinone.sh` and the keys in `nvidia-rag/rag-values.yaml` follow the
  2.2.x shape; validate against the exact NGC chart on a live box (NVIDIA
  renames values between releases).
- **Seed → deploy wiring** — DONE. `MINIPREM_SEED_ALLINONE` + friends are
  registered in `scripts/seed.sh` (known-keys + `seed_apply_to_vars`), and
  `scripts/allinone.sh::maybe_deploy_allinone` is invoked from
  `docker/scripts/install_miniprem.sh` right after the seed is applied: when
  `ALLINONE=yes` it hands off to `deploy-allinone.sh` (mapping NGC key, harbor
  creds, Gemma model, STT provider, admin key) and exits, bypassing the Docker
  stack. Verified at the logic level; run once on a real box to confirm.
- **`/rag-admin` ingress** — DONE. The rag-adapter chart ships an Ingress
  (`templates/ingress.yaml`) that routes `<kiosk-host>/rag-admin/* → adapter
  /admin/*` (rewrite strips the prefix). Set `ingress.host` to the kiosk host.
- **Gemma backend choice** — DONE. `GEMMA_BACKEND=nim` (seedable) deploys Gemma
  via the NIM operator (NV-FP4, `manifests/nim-gemma.yaml`); default `vllm` uses
  `manifests/vllm-gemma4.yaml`. Validate the NIM image tag/profile on NGC.
- **Riva-TTS gesture bug** — `<uneeq:action_*>` tags animate on ElevenLabs/Azure
  but are dropped by NVIDIA Riva TTS (Renny/Riva-side, not the adapter — proven
  by the adapter's gesture round-trip test). Escalate to UneeQ NZ platform team.
- **GPU/VRAM sizing** — Gemma + RAG + Riva + Renny on one card is tight; confirm
  time-slicing + per-NIM VRAM budget. Pin driver 580.82.09 for Blackwell.
- **Live Renny SSE check** — confirm the adapter's Flowise SSE frames render in
  a live Renny (toggle `STREAM_FORMAT=openai` if its parser differs).
```
