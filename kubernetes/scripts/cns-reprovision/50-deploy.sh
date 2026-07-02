#!/usr/bin/env bash
# Phase 5 — install the NVIDIA NIM Operator (provides the NIMCache/NIMService CRDs
# that manifests/nim-gemma.yaml needs) then run deploy-allinone.sh for the full
# UneeQ + NVIDIA stack with Phoenix tracing, NIM NV-FP4 Gemma.
#
# REQUIRES creds in /home/admin/migration/creds.conf:
#   NGC_API_KEY, HARBOR_USERNAME, HARBOR_PASSWORD, PLATFORM_KEY, TENANT_ID
# (Not auto-harvested — populate it first.)
set -euo pipefail
log() { printf '\033[1;36m[deploy]\033[0m %s\n' "$*"; }
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
MIG=/home/admin/migration
REPO="${REPO:-/home/admin/miniprem-2025}"   # repo synced to the box

[ -f "$MIG/creds.conf" ] || { echo "FATAL: $MIG/creds.conf missing"; exit 1; }
set -a; . "$MIG/creds.conf"; set +a
: "${NGC_API_KEY:?}"; : "${HARBOR_USERNAME:?}"; : "${HARBOR_PASSWORD:?}"

# --- NVIDIA NIM Operator (CRDs: NIMCache / NIMService) ---
if ! kubectl get crd nimservices.apps.nvidia.com >/dev/null 2>&1; then
  log "Installing NVIDIA NIM Operator"
  helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true
  helm upgrade --install nim-operator nvidia/k8s-nim-operator \
    --namespace nim-operator --create-namespace
  log "Waiting for NIMService CRD…"
  for i in $(seq 1 30); do kubectl get crd nimservices.apps.nvidia.com >/dev/null 2>&1 && break; sleep 4; done
fi

# --- Full stack (GPU operator already installed in Phase 3 -> skip it) ---
# DEPLOY_RAG defaults to "no" for the first pass: get NIM + adapter + Phoenix +
# renny + kiosk + tracing working (conversation via the NIM, traced), THEN re-run
# with DEPLOY_RAG=yes to layer the NVIDIA RAG blueprint (heaviest/most fragile —
# NGC chart version is validate-live). The /v1/chat/completions tracing proxy does
# not need the RAG server, so this still gives a fully traced talking kiosk.
log "Running deploy-allinone.sh (GEMMA_BACKEND=nim, Phoenix on, RAG=${DEPLOY_RAG:-no})"
export GEMMA_BACKEND=nim
export RAG_ADAPTER_IMAGE=rag-adapter:local
export DEPLOY_GPU_OPERATOR=no
export DEPLOY_RAG="${DEPLOY_RAG:-no}"
export KIOSK_INGRESS_HOST=digitalhuman.miniprem
bash "$REPO/kubernetes/scripts/deploy-allinone.sh"
