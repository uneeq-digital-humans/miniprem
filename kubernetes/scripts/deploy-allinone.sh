#!/usr/bin/env bash
#
# deploy-allinone.sh — UneeQ + NVIDIA RAG all-in-one Kubernetes deployment.
#
# Sequences the full on-box stack onto a kubeadm/MicroK8s cluster:
#
#   GPU operator + NIM operator
#     -> NVIDIA NIM:   Gemma (LLM) + embedding + rerank
#     -> NVIDIA Riva:  TTS (magpie) + STT (digitalhuman-asr / nemotron + ws-proxy)
#     -> NVIDIA RAG:   blueprint (rag-server + nv-ingest + Milvus + Elasticsearch)
#     -> RAG adapter:  UneeQ<->RAG middleware + Redis (session memory + prompt store)
#     -> Phoenix:      LLM/RAG observability
#     -> Renny:        digital-human renderer (+ TTS)
#     -> websocket-api + Dell kiosk (digitalhuman-interface, Riva STT)
#
# Every component is a toggle (env var) so this also re-converges a partial box.
# Designed to be invoked by miniprem.sh (CNS path) or run standalone.
#
# Configuration comes from the environment (mapped from the MiniPrem seed by
# the caller). Required: NGC_API_KEY, HARBOR_USERNAME, HARBOR_PASSWORD,
# PLATFORM_KEY, TENANT_ID. See seed.example.env for the full contract.
#
# NOTE: The NVIDIA RAG blueprint Helm chart is pulled from NGC at deploy time
# and is version-sensitive. Pin RAG_CHART_VERSION and validate on a live box.
set -euo pipefail

# --------------------------------------------------------------------------- #
# Config (env-driven; sane defaults for an on-box single-GPU MiniPrem)
# --------------------------------------------------------------------------- #
NAMESPACE="${NAMESPACE:-uneeq}"
RAG_NAMESPACE="${RAG_NAMESPACE:-advanced-rag}"
NIM_NAMESPACE="${NIM_NAMESPACE:-nim-models}"

KUBECTL="${KUBECTL:-kubectl}"
HELM="${HELM:-helm}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Component toggles (set to "no" to skip a stage on a re-run)
DEPLOY_GPU_OPERATOR="${DEPLOY_GPU_OPERATOR:-yes}"
DEPLOY_NIM="${DEPLOY_NIM:-yes}"
DEPLOY_RIVA_TTS="${DEPLOY_RIVA_TTS:-yes}"
DEPLOY_RIVA_STT="${DEPLOY_RIVA_STT:-yes}"
DEPLOY_RAG="${DEPLOY_RAG:-yes}"
DEPLOY_RAG_ADAPTER="${DEPLOY_RAG_ADAPTER:-yes}"
DEPLOY_PHOENIX="${DEPLOY_PHOENIX:-yes}"
DEPLOY_RENNY="${DEPLOY_RENNY:-yes}"
DEPLOY_KIOSK="${DEPLOY_KIOSK:-yes}"

# Models / images
GEMMA_MODEL="${GEMMA_MODEL:-google/gemma-4-26B-A4B-it}"  # served model name (kiosk sends this; adapter also auto-discovers). MoE ~4B active + NV-FP4 — fits the shared GPU. Do NOT default to a dense 31B/27B: too big to co-reside with Renny+Riva.
GEMMA_BACKEND="${GEMMA_BACKEND:-nim}"             # nim (NIM operator, NV-FP4 — Dell default) | vllm
# vLLM template knobs (set by the VRAM-based template in install-allinone.sh).
GEMMA_SERVED_NAME="${GEMMA_SERVED_NAME:-$GEMMA_MODEL}"  # vLLM --served-model-name (adapter sends this)
VLLM_GPU_UTIL="${VLLM_GPU_UTIL:-0.85}"            # 0.85 alone; lower (~0.27) when co-resident w/ Riva+Renny
VLLM_MAX_LEN="${VLLM_MAX_LEN:-16384}"
# The NIM LLM image to deploy. Seed-driven so Dell can run ANY NVIDIA NIM model
# (a different Gemma, Llama, Nemotron, …) without editing manifests — the adapter
# auto-discovers the served model and Phoenix tracks whatever it is.
NIM_LLM_IMAGE="${NIM_LLM_IMAGE:-nvcr.io/nim/google/gemma-4-26b-a4b-it:1.7.0-variant}"
RAG_CHART_VERSION="${RAG_CHART_VERSION:-2.3.2}"   # 2.3.2 = entitled 1B embed/rerank + we point LLM at the local gemma. (v2.6.0 defaults to a 120B agentic LLM + nemotron NIMs the NGC key isn't entitled to / box can't run.)
STT_PROVIDER="${STT_PROVIDER:-riva}"               # kiosk STT: riva | deepgram
RAG_ADMIN_KEY="${RAG_ADMIN_KEY:-}"                 # optional /admin/* shared secret
KIOSK_BRAND="${KIOSK_BRAND:-dell}"                 # kiosk brand variant (baked at build)
# LAN HTTPS so a LAN browser is a secure context (mic + audio device selection).
# self-signed (appliance default) | real (expect a pre-created kiosk-tls secret) | off
KIOSK_TLS="${KIOSK_TLS:-self-signed}"

# LLM service the rag-adapter conversation proxy targets + traces. Defaults track
# GEMMA_BACKEND (NIM operator service 'gemma' vs the vLLM service), override-able.
NIM_GEMMA_URL="http://gemma.${NIM_NAMESPACE}.svc.cluster.local:8000"
VLLM_GEMMA_URL="http://vllm-gemma4.${NIM_NAMESPACE}.svc.cluster.local:8000"
ADAPTER_LLM_URL="${ADAPTER_LLM_URL:-$([ "$GEMMA_BACKEND" = nim ] && echo "$NIM_GEMMA_URL" || echo "$VLLM_GEMMA_URL")}"
# rag-adapter image: override to a locally-built image (e.g. on a kubeadm box that
# can't pull from cr.uneeq.io) — set RAG_ADAPTER_IMAGE=rag-adapter:local.
RAG_ADAPTER_IMAGE="${RAG_ADAPTER_IMAGE:-}"
PHOENIX_OTLP_ENDPOINT="${PHOENIX_OTLP_ENDPOINT:-http://phoenix.${NAMESPACE}.svc.cluster.local:6006/v1/traces}"
PHOENIX_PROJECT="${PHOENIX_PROJECT:-kiosk-conversations}"

# Required secrets/credentials (validated below)
NGC_API_KEY="${NGC_API_KEY:-}"
HARBOR_USERNAME="${HARBOR_USERNAME:-}"
HARBOR_PASSWORD="${HARBOR_PASSWORD:-}"
# UneeQ DHOP platform creds — Renny authenticates to the UneeQ signalling service
# with these (seed PLATFORM_KEY/TENANT_ID). Without them Renny can't start
# (CreateContainerConfigError: missing dhop-api-key in the renny secret).
PLATFORM_KEY="${PLATFORM_KEY:-}"
TENANT_ID="${TENANT_ID:-}"

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
log()   { printf '\033[1;36m[allinone]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[allinone] WARN:\033[0m %s\n' "$*" >&2; }
fatal() { printf '\033[1;31m[allinone] FATAL:\033[0m %s\n' "$*" >&2; exit 1; }

require() {
  local missing=()
  for v in "$@"; do [ -n "${!v:-}" ] || missing+=("$v"); done
  [ ${#missing[@]} -eq 0 ] || fatal "Missing required env: ${missing[*]}"
}

ensure_ns() {
  $KUBECTL get namespace "$1" >/dev/null 2>&1 || $KUBECTL create namespace "$1"
}

# Create a docker-registry pull secret idempotently.
ensure_pull_secret() {
  local name="$1" ns="$2" server="$3" user="$4" pass="$5"
  ensure_ns "$ns"
  $KUBECTL -n "$ns" delete secret "$name" >/dev/null 2>&1 || true
  $KUBECTL -n "$ns" create secret docker-registry "$name" \
    --docker-server="$server" \
    --docker-username="$user" \
    --docker-password="$pass"
}

helm_install() {  # helm_install <release> <ns> <chart> [extra args...]
  local rel="$1" ns="$2" chart="$3"; shift 3
  log "helm upgrade --install $rel ($chart) -> ns/$ns"
  $HELM upgrade --install "$rel" "$chart" --namespace "$ns" --create-namespace "$@"
}

# --------------------------------------------------------------------------- #
# Stages
# --------------------------------------------------------------------------- #
preflight() {
  command -v "$KUBECTL" >/dev/null || fatal "kubectl not found"
  command -v "$HELM"    >/dev/null || fatal "helm not found"
  require NGC_API_KEY HARBOR_USERNAME HARBOR_PASSWORD
  [ "$DEPLOY_RENNY" = yes ] && require PLATFORM_KEY TENANT_ID   # Renny needs the DHOP creds
  log "Preflight OK. Cluster: $($KUBECTL config current-context 2>/dev/null || echo '?')"

  # Namespaces + shared secrets every stage relies on.
  for ns in "$NAMESPACE" "$RAG_NAMESPACE" "$NIM_NAMESPACE" gpu-operator; do ensure_ns "$ns"; done
  for ns in "$NAMESPACE" "$RAG_NAMESPACE" "$NIM_NAMESPACE"; do
    ensure_pull_secret harbor-credentials       "$ns" cr.uneeq.io  "$HARBOR_USERNAME" "$HARBOR_PASSWORD"
    ensure_pull_secret ngc-registry-credentials "$ns" nvcr.io      '$oauthtoken'      "$NGC_API_KEY"
    $KUBECTL -n "$ns" delete secret nim-credentials >/dev/null 2>&1 || true
    $KUBECTL -n "$ns" create secret generic nim-credentials --from-literal=NGC_API_KEY="$NGC_API_KEY"
  done
}

stage_gpu_operator() {
  [ "$DEPLOY_GPU_OPERATOR" = yes ] || { log "skip gpu-operator"; return; }
  $HELM repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null 2>&1 || true
  $HELM repo update >/dev/null 2>&1 || true
  helm_install gpu-operator gpu-operator nvidia/gpu-operator \
    --set operator.defaultRuntime=containerd \
    --set driver.enabled=false   # driver installed on host by miniprem nvidia scripts
  # Time-slicing so Renny + NIM + Riva can share one physical GPU.
  $KUBECTL apply -f "$K8S_DIR/manifests/gpu-operator.yaml" 2>/dev/null || true
}

stage_nim() {
  [ "$DEPLOY_NIM" = yes ] || { log "skip NIM"; return; }
  # Gemma LLM. GEMMA_BACKEND=nim uses the NIM operator (NV-FP4, preferred on
  # Blackwell); otherwise the vLLM manifest. Embedding + rerank NIMs are
  # deployed by the RAG blueprint (rag-values.yaml: embeddings/ranking.deploy).
  if [ "$GEMMA_BACKEND" = "nim" ]; then
    log "Deploying LLM via NIM operator (image: $NIM_LLM_IMAGE)"
    # Substitute the seed-chosen NIM image so any NVIDIA NIM model can be used.
    # Anchor on the YAML keys (modelPuller/repository/tag) rather than a literal
    # image value: the manifest's placeholder image can change without silently
    # breaking this substitution (the old literal no longer matched, so the seed
    # image was ignored and only the bare `tag:` got rewritten onto the wrong repo).
    local _repo="${NIM_LLM_IMAGE%:*}" _tag="${NIM_LLM_IMAGE##*:}"
    if [ "$_repo" = "$NIM_LLM_IMAGE" ] || [ -z "$_tag" ]; then _repo="$NIM_LLM_IMAGE"; _tag="latest"; fi
    sed -e "s#^\([[:space:]]*\)modelPuller: .*#\1modelPuller: ${_repo}:${_tag}#" \
        -e "s#^\([[:space:]]*\)repository: .*#\1repository: ${_repo}#" \
        -e "s#^\([[:space:]]*\)tag: .*#\1tag: ${_tag}#" \
        "$K8S_DIR/manifests/nim-gemma.yaml" | $KUBECTL apply -n "$NIM_NAMESPACE" -f -
  else
    log "Deploying Gemma via vLLM (model=$GEMMA_MODEL gpu-util=$VLLM_GPU_UTIL max-len=$VLLM_MAX_LEN)"
    GEMMA_MODEL="$GEMMA_MODEL" GEMMA_SERVED_NAME="$GEMMA_SERVED_NAME" \
    VLLM_GPU_UTIL="$VLLM_GPU_UTIL" VLLM_MAX_LEN="$VLLM_MAX_LEN" \
      envsubst '${GEMMA_MODEL} ${GEMMA_SERVED_NAME} ${VLLM_GPU_UTIL} ${VLLM_MAX_LEN}' \
        < "$K8S_DIR/manifests/vllm-gemma4.yaml" | $KUBECTL apply -n "$NIM_NAMESPACE" -f -
  fi
}

stage_riva_tts() {
  [ "$DEPLOY_RIVA_TTS" = yes ] || { log "skip Riva TTS"; return; }
  log "Deploying Riva TTS (magpie multilingual)"
  $KUBECTL apply -n "$NIM_NAMESPACE" -f "$K8S_DIR/manifests/magpie-tts.yaml"
}

stage_riva_stt() {
  [ "$DEPLOY_RIVA_STT" = yes ] || { log "skip Riva STT"; return; }
  log "Deploying Riva STT (nemotron-asr + ws-proxy)"
  local vals="$K8S_DIR/values/digitalhuman-asr-values-cns.yaml"
  helm_install digitalhuman-asr "$NAMESPACE" "$K8S_DIR/digitalhuman-asr" \
    ${vals:+-f "$vals"}
}

stage_rag() {
  [ "$DEPLOY_RAG" = yes ] || { log "skip NVIDIA RAG blueprint"; return; }
  log "Deploying NVIDIA RAG blueprint v$RAG_CHART_VERSION (rag-server + nv-ingest + Milvus + Elasticsearch)"
  # PREREQUISITE: the blueprint's Elasticsearch needs the ECK operator + CRDs
  # (elasticsearch.k8s.elastic.co/v1). Without it the install fails "no matches for
  # kind Elasticsearch". Idempotent — safe to re-run.
  $KUBECTL create -f "${ECK_CRDS_URL:-https://download.elastic.co/downloads/eck/2.16.1/crds.yaml}" 2>/dev/null || true
  $KUBECTL apply  -f "${ECK_OPERATOR_URL:-https://download.elastic.co/downloads/eck/2.16.1/operator.yaml}" 2>/dev/null || true
  $KUBECTL -n elastic-system rollout status statefulset/elastic-operator --timeout=180s 2>/dev/null || true
  # NIM image pull: the blueprint references an 'ngc-secret' imagePullSecret but
  # doesn't reliably create it (pods then pull anonymously → 403, even on entitled
  # NIMs). Pre-create it + attach to the namespace default SA so ALL NIM pods pull
  # with NGC creds.
  $KUBECTL get ns "$RAG_NAMESPACE" >/dev/null 2>&1 || $KUBECTL create ns "$RAG_NAMESPACE"
  $KUBECTL -n "$RAG_NAMESPACE" create secret docker-registry ngc-secret \
    --docker-server=nvcr.io --docker-username='$oauthtoken' --docker-password="$NGC_API_KEY" \
    --dry-run=client -o yaml | $KUBECTL apply -f - >/dev/null 2>&1 || true
  $KUBECTL -n "$RAG_NAMESPACE" patch serviceaccount default -p '{"imagePullSecrets":[{"name":"ngc-secret"}]}' >/dev/null 2>&1 || true
  # The NIMs ALSO read NGC_API_KEY from a secret named 'ngc-api' at RUNTIME to
  # download model weights — and `--set ngcApiKey` does NOT reliably populate it
  # (ends up empty → "Authentication Error" model download → CrashLoopBackOff).
  # Create it explicitly.
  $KUBECTL -n "$RAG_NAMESPACE" create secret generic ngc-api --from-literal=NGC_API_KEY="$NGC_API_KEY" \
    --dry-run=client -o yaml | $KUBECTL apply -f - >/dev/null 2>&1 || true
  $HELM repo add nvidia-blueprint https://helm.ngc.nvidia.com/nvidia/blueprint >/dev/null 2>&1 || true
  $HELM repo update >/dev/null 2>&1 || true
  # NGC chart name/version is version-sensitive — validate on a live box.
  # Point the blueprint's generation LLM at whatever LLM this deploy stood up
  # (backend-aware: nim -> gemma svc, vllm -> vllm-gemma4 svc) and the served model.
  helm_install rag "$RAG_NAMESPACE" nvidia-blueprint/nvidia-blueprint-rag \
    --version "$RAG_CHART_VERSION" \
    -f "$K8S_DIR/nvidia-rag/rag-values.yaml" \
    --set ngcApiKey="$NGC_API_KEY" \
    --set imagePullSecret.password="$NGC_API_KEY" \
    --set nim-llm.enabled=false \
    --set llm.serverUrl="${ADAPTER_LLM_URL}/v1" \
    --set llm.modelName="$GEMMA_MODEL"
}

stage_rag_adapter() {
  [ "$DEPLOY_RAG_ADAPTER" = yes ] || { log "skip RAG adapter"; return; }
  log "Deploying UneeQ<->RAG adapter (+ Redis session memory + prompt store)"
  helm_install rag-adapter "$NAMESPACE" "$K8S_DIR/digitalhuman-rag-adapter/chart" \
    --set rag.baseUrl="http://rag-server.${RAG_NAMESPACE}.svc.cluster.local:8081" \
    --set rag.model="$GEMMA_MODEL" \
    --set nvIngest.url="http://nv-ingest.${RAG_NAMESPACE}.svc.cluster.local:7670" \
    --set llm.url="$ADAPTER_LLM_URL" \
    --set llm.model="$GEMMA_MODEL" \
    --set phoenix.enabled="$([ "$DEPLOY_PHOENIX" = yes ] && echo true || echo false)" \
    --set phoenix.otlpEndpoint="$PHOENIX_OTLP_ENDPOINT" \
    --set phoenix.project="$PHOENIX_PROJECT" \
    --set ingress.host="${KIOSK_INGRESS_HOST:-digitalhuman.miniprem}" \
    ${RAG_ADAPTER_IMAGE:+--set image.repository="${RAG_ADAPTER_IMAGE%%:*}" --set image.tag="${RAG_ADAPTER_IMAGE##*:}" --set image.pullPolicy=IfNotPresent} \
    ${RAG_ADMIN_KEY:+--set admin.apiKey="$RAG_ADMIN_KEY"}
}

stage_phoenix() {
  [ "$DEPLOY_PHOENIX" = yes ] || { log "skip Phoenix"; return; }
  log "Deploying Phoenix (observability)"
  $KUBECTL apply -n "$NAMESPACE" -f "$K8S_DIR/manifests/phoenix.yaml"
}

stage_renny() {
  [ "$DEPLOY_RENNY" = yes ] || { log "skip Renny"; return; }
  log "Deploying Renny renderer"
  # Pass the DHOP platform creds (seed PLATFORM_KEY/TENANT_ID) so the renny secret
  # gets a real dhop-api-key + the deployment a real tenantId — otherwise Renny
  # fails with CreateContainerConfigError (missing dhop-api-key).
  helm_install renny "$NAMESPACE" "$K8S_DIR/renny" \
    -f "$K8S_DIR/values/renny-values-cns.yaml" \
    --set renderer.dhop.apiKey="$PLATFORM_KEY" \
    --set renderer.dhop.tenantId="$TENANT_ID"
}

stage_kiosk() {
  [ "$DEPLOY_KIOSK" = yes ] || { log "skip kiosk"; return; }
  log "Deploying websocket-api + Dell kiosk (STT provider: $STT_PROVIDER)"
  helm_install digitalhuman-websocket-api "$NAMESPACE" "$K8S_DIR/digitalhuman-websocket-api" \
    -f "$K8S_DIR/values/digitalhuman-websocket-api-values-cns.yaml"
  # The kiosk's stt.provider/rivaUrl come from its values (config.stt.*),
  # rendered into the runtime config.yaml ConfigMap the SPA fetches.
  helm_install digitalhuman-interface "$NAMESPACE" "$K8S_DIR/digitalhuman-interface" \
    -f "$K8S_DIR/values/digitalhuman-interface-values-cns.yaml" \
    --set config.stt.provider="$STT_PROVIDER"
}

summary() {
  log "Deploy sequence complete. Pods:"
  $KUBECTL get pods -A | grep -Ei 'rag|nim|riva|renny|kiosk|interface|asr|phoenix|redis|gemma|magpie' || true
  cat <<EOF

Conversation + tracing:
  The kiosk talks to the LLM via the rag-adapter (config.conversation.nim.endpoint
  = /v1/chat/completions, routed to rag-adapter:8085 by its ingress on the kiosk
  host). The adapter proxies to ${ADAPTER_LLM_URL} and exports OpenInference spans
  to Phoenix -> project "${PHOENIX_PROJECT}".

Next steps:
  1. Open the kiosk; use Settings to set the persona prompt and upload documents.
  2. Phoenix UI: kubectl -n ${NAMESPACE} port-forward svc/phoenix 6006:6006
     -> http://localhost:6006 -> project "${PHOENIX_PROJECT}" -> Traces.
EOF
}

stage_host_helper() {
  [ "${DEPLOY_HOST_HELPER:-yes}" = yes ] || { log "skip host-helper"; return; }
  log "Deploying host-helper (GPU stats + audio devices + monitors + Renny control)"
  $KUBECTL apply -f "$K8S_DIR/digitalhuman-host-helper/k8s-deploy.yaml" || warn "host-helper apply failed (image pushed to Harbor?)"
}

stage_tls() {
  case "$KIOSK_TLS" in
    self-signed)
      log "Self-signed TLS for LAN (secure context → mic + audio device selection over LAN)"
      KIOSK_HOST="${KIOSK_INGRESS_HOST:-digitalhuman.miniprem}" bash "$SCRIPT_DIR/setup-kiosk-tls.sh" || warn "TLS setup failed (non-fatal)"
      ;;
    real) log "KIOSK_TLS=real — expecting a pre-created kiosk-tls secret from your CA cert; skipping self-signed gen." ;;
    *)    log "KIOSK_TLS=off — HTTPS not configured (LAN mic/audio control unavailable)." ;;
  esac
}

main() {
  preflight
  stage_gpu_operator
  stage_nim
  stage_riva_tts
  stage_riva_stt
  stage_rag
  stage_rag_adapter
  stage_phoenix
  stage_renny
  stage_kiosk
  stage_host_helper
  stage_tls
  summary
}

main "$@"
