#!/usr/bin/env bash
# Bring up the UneeQ + NVIDIA all-in-one appliance.
#   ./up.sh           core stack (renny + gemma + riva + kiosk)
#   ./up.sh rag       + the NVIDIA RAG blueprint (document retrieval)
#   ./up.sh deepgram  + the self-hosted Deepgram stack (STT + TTS + adapter)
#   ./up.sh all       everything (rag + deepgram)
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo "Copy .env.example to .env and fill it in first."; exit 1; }
set -a; . ./.env; set +a

: "${NGC_API_KEY:?NGC_API_KEY missing in .env}"

# --- VRAM-aware Gemma NIM selection (NGC key only) --------------------------
# Pick a Gemma NIM that fits alongside Riva STT/TTS + Renny (+ RAG) on ONE GPU.
# Tags match the kubeadm installer (kubernetes/scripts/install-allinone.sh) and
# are what a STANDARD NGC key can ACTUALLY pull — verified on a live box:
#   • gemma-2-9b-it  → pullable, the sweet spot (fits with Riva+Renny+RAG)
#   • gemma-3-1b-it  → tiny; only for a very small/contended GPU
#   • gemma-3-27b-it → needs an extra NGC entitlement (pull 401s without it)
# There is NO public "gemma-4" NIM. Override with GEMMA_IMAGE/ADAPTER_LLM_MODEL in .env.
if [ -z "${GEMMA_IMAGE:-}" ]; then
  VRAM_MIB="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo 0)"
  VRAM_GB=$(( VRAM_MIB / 1024 ))
  if   [ "$VRAM_GB" -lt 16 ]; then GEMMA_IMAGE="nvcr.io/nim/google/gemma-3-1b-it:latest";  ADAPTER_LLM_MODEL="google/gemma-3-1b-it"
  elif [ "$VRAM_GB" -lt 80 ]; then GEMMA_IMAGE="nvcr.io/nim/google/gemma-2-9b-it:latest";  ADAPTER_LLM_MODEL="google/gemma-2-9b-it"
  else                             GEMMA_IMAGE="nvcr.io/nim/google/gemma-3-27b-it:latest"; ADAPTER_LLM_MODEL="google/gemma-3-27b-it"
                                   echo "!! gemma-3-27b needs an NGC entitlement — the pull 401s without it; set GEMMA_IMAGE=nvcr.io/nim/google/gemma-2-9b-it:latest in .env to fall back."; fi
  export GEMMA_IMAGE ADAPTER_LLM_MODEL
  echo "== GPU ${VRAM_GB}GB -> $GEMMA_IMAGE =="
fi

echo "== docker login (NGC + Harbor) =="
echo "$NGC_API_KEY" | docker login nvcr.io -u '$oauthtoken' --password-stdin
# Harbor (Renny + riva-ws-proxy + kiosk images). Expects prior `docker login cr.uneeq.io`
# or HARBOR_USERNAME/HARBOR_PASSWORD in the environment.
if [ -n "${HARBOR_USERNAME:-}" ] && [ -n "${HARBOR_PASSWORD:-}" ]; then
  echo "$HARBOR_PASSWORD" | docker login cr.uneeq.io -u "$HARBOR_USERNAME" --password-stdin
fi

PROFILES=()
case "${1:-}" in
  rag)
    PROFILES=(--profile rag)
    : "${RAG_COMPOSE:?Set RAG_COMPOSE in .env (path to the NVIDIA RAG blueprint compose) for the rag profile}"
    echo "== RAG profile enabled (blueprint: $RAG_COMPOSE) =="
    ;;
  deepgram)
    PROFILES=(--profile deepgram)
    : "${DEEPGRAM_API_KEY:?DEEPGRAM_API_KEY missing in .env (required for the deepgram profile)}"
    ls deepgram/models-stt/*.dg* >/dev/null 2>&1 || { echo "!! No model files in deepgram/models-stt/ — download them first (see DEEPGRAM-LOCAL.md)."; exit 1; }
    ls deepgram/models-tts/*.dgv2 >/dev/null 2>&1 || { echo "!! No TTS model in deepgram/models-tts/ — download flux-tts.f94b1bd5.dgv2 (see DEEPGRAM-LOCAL.md)."; exit 1; }
    # The engine reads its license key ONLY from [license] key in the TOML
    # (verified on t2 2026-09-01 — env var alone dies with "Missing license
    # configuration"), so render the key into the configs before boot.
    ./render-configs.sh
    echo "== Deepgram profile enabled (stem :8080, TTS adapter :8086) =="
    ;;
  all)
    PROFILES=(--profile rag --profile deepgram)
    : "${RAG_COMPOSE:?Set RAG_COMPOSE in .env (path to the NVIDIA RAG blueprint compose) for the rag profile}"
    : "${DEEPGRAM_API_KEY:?DEEPGRAM_API_KEY missing in .env (required for the deepgram profile)}"
    ./render-configs.sh   # deepgram license key -> [license] key (see deepgram branch)
    echo "== RAG + Deepgram profiles enabled =="
    ;;
  "") ;;
  *) echo "Unknown profile: $1 (expected: rag | deepgram | all)"; exit 1 ;;
esac

echo "== pulling images (NIMs are large; first run is slow) =="
docker compose -f docker-compose.allinone.yml "${PROFILES[@]}" pull --ignore-buildable || true

echo "== starting =="
docker compose -f docker-compose.allinone.yml "${PROFILES[@]}" up -d

cat <<EOF

Up. First boot loads the NIMs (several minutes). Watch:
  docker compose -f docker-compose.allinone.yml logs -f gemma riva-asr

Endpoints (localhost):
  Kiosk        http://localhost/        (Chrome kiosk opens this)
  LLM proxy    http://localhost:8085/v1/chat/completions  (adapter -> model, traced)
  Phoenix      http://localhost:6006/   (LLM traces -> project "kiosk-conversations")
  Gemma NIM    http://localhost:8000/v1/chat/completions
  Riva STT ws  ws://localhost:8009/api/asr/v1/stream
  RAG server   http://localhost:8081/v1/generate   (rag profile)
  Deepgram     ws://localhost:8080/v1/listen (STT) + :8086 TTS adapter (deepgram profile)

Set the persona ID in kiosk/config.yaml (brands.dell.personas.en.miniprem.id),
then: docker compose -f docker-compose.allinone.yml restart kiosk
EOF
