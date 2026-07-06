#!/usr/bin/env bash
# Interactive Dell all-in-one installer (MANUAL installs).
#
# Detects GPU VRAM, recommends a model TEMPLATE (pushing gemma4 over llama),
# collects the required credentials, then hands everything to deploy-allinone.sh.
# The ISO autoinstall does NOT use this — it calls deploy-allinone.sh directly
# with everything pre-filled from the customer seed.
#
# Run on the box:  bash install-allinone.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log()  { printf '\033[1;36m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install] %s\033[0m\n' "$*"; }
ask()  { local p="$1" d="${2:-}" a; read -r -p "$p${d:+ [$d]}: " a; printf '%s' "${a:-$d}"; }
asks() { local p="$1" a; read -r -s -p "$p: " a; echo >&2; printf '%s' "$a"; }   # secret (no echo)

# --- 1) Detect GPU VRAM -----------------------------------------------------
VRAM_MIB="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo 0)"
VRAM_GB=$(( VRAM_MIB / 1024 ))
log "Detected GPU VRAM: ${VRAM_GB} GB"

# --- 2) Recommend an LLM (gemma via NVIDIA NIM) -----------------------------
# Recommendation = what a standard NGC key can ACTUALLY pull (verified on a live
# box) AND what fits alongside Riva STT + Riva TTS + Renny + RAG on ONE GPU.
# Pullable gemma NIMs with a standard key: gemma-2-9b-it and gemma-3-1b-it. The
# larger gemmas (gemma-2-27b, gemma-3-4b/12b/27b) 401 without an extra NGC
# entitlement, and there is NO public "gemma-4" NIM. gemma-2-9b is the sweet spot
# (good quality, ~10–18GB — leaves ample room on a 24GB+ card for the rest).
if   [ "$VRAM_GB" -lt 16 ]; then REC=lean
else                              REC=standard; fi
echo
echo "  LLM templates (gemma via NVIDIA NIM — NGC key only, no HF token):"
echo "    standard  → google/gemma-2-9b-it      (RECOMMENDED; pullable, fits with Riva+Renny+RAG)"
echo "    lean      → google/gemma-3-1b-it      (tiny; only for a very small/contended GPU)"
echo "    big       → google/gemma-3-27b-it     (needs an extra NGC entitlement — pull 401s without it)"
echo "    llama     → meta/llama-3.1-8b-instruct (NIM fallback; always available)"
echo
T="$(ask "Template (recommended: $REC)" "$REC")"

case "$T" in
  standard) GEMMA_BACKEND=nim; NIM_LLM_IMAGE="nvcr.io/nim/google/gemma-2-9b-it:latest";       GEMMA_MODEL="google/gemma-2-9b-it" ;;
  lean)     GEMMA_BACKEND=nim; NIM_LLM_IMAGE="nvcr.io/nim/google/gemma-3-1b-it:latest";       GEMMA_MODEL="google/gemma-3-1b-it"
            warn "Lean: gemma-3-1b is small — modest quality; use only on a tight GPU." ;;
  big)      GEMMA_BACKEND=nim; NIM_LLM_IMAGE="nvcr.io/nim/google/gemma-3-27b-it:latest";      GEMMA_MODEL="google/gemma-3-27b-it"
            warn "gemma-3-27b requires an NGC entitlement — the pull 401s without it." ;;
  llama)    GEMMA_BACKEND=nim; NIM_LLM_IMAGE="nvcr.io/nim/meta/llama-3.1-8b-instruct:latest"; GEMMA_MODEL="meta/llama-3.1-8b-instruct" ;;
  *) echo "Unknown template '$T'"; exit 1 ;;
esac
GEMMA_MODEL="$(ask "  LLM model" "$GEMMA_MODEL")"
GEMMA_SERVED_NAME="$GEMMA_MODEL"

# --- 3) Credentials (prompt if not already in env) --------------------------
NGC_API_KEY="${NGC_API_KEY:-$(ask 'NVIDIA NGC API key (nvapi-…)')}"
HARBOR_USERNAME="${HARBOR_USERNAME:-$(ask 'Harbor robot username')}"
HARBOR_PASSWORD="${HARBOR_PASSWORD:-$(asks 'Harbor robot password')}"
PLATFORM_KEY="${PLATFORM_KEY:-$(asks 'UneeQ DHOP API key (PLATFORM_KEY)')}"
TENANT_ID="${TENANT_ID:-$(ask 'UneeQ DHOP tenant id')}"
HF_TOKEN="${HF_TOKEN:-}"
if [ "$GEMMA_BACKEND" = vllm ]; then
  HF_TOKEN="${HF_TOKEN:-$(asks 'HuggingFace token (gemma4 is a gated model)')}"
fi

# --- 4) hf-token secret for the gated gemma4 vLLM model ---------------------
if [ "$GEMMA_BACKEND" = vllm ] && [ -n "$HF_TOKEN" ]; then
  kubectl get ns nim-models >/dev/null 2>&1 || kubectl create ns nim-models
  kubectl -n nim-models create secret generic hf-token \
    --from-literal=HF_TOKEN="$HF_TOKEN" --dry-run=client -o yaml | kubectl apply -f -
  log "hf-token secret created in nim-models"
fi

# --- 5) Hand off to the env-driven deployer ---------------------------------
echo
log "Deploying: template=$T backend=$GEMMA_BACKEND model=$GEMMA_MODEL (VRAM ${VRAM_GB}GB)"
export GEMMA_BACKEND GEMMA_MODEL GEMMA_SERVED_NAME VLLM_GPU_UTIL VLLM_MAX_LEN \
       NGC_API_KEY HARBOR_USERNAME HARBOR_PASSWORD PLATFORM_KEY TENANT_ID ${NIM_LLM_IMAGE:+NIM_LLM_IMAGE}
bash "$SCRIPT_DIR/deploy-allinone.sh"
