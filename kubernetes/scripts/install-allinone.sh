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

# --- 2) LLM: the Dell-standard Gemma NIM ------------------------------------
# STANDARD (and the ONLY supported Gemma) = google/gemma-4-26B-A4B-it: a
# Mixture-of-Experts (~4B active of 26B total) served NV-FP4, ~25 GB VRAM — fits
# alongside Riva STT + Riva TTS + Renny + RAG on one Blackwell / RTX 6000-class
# card. Do NOT substitute another Gemma (gemma-2/gemma-3, or a dense gemma-4 like
# 31B): the whole stack is aligned on this one id (nim-gemma chart, rag-adapter,
# RAG blueprint, kiosk). `llama` is the only non-Gemma fallback — for a small/
# contended GPU or a box whose NGC key can't pull the gemma-4 NIM.
if   [ "$VRAM_GB" -lt 32 ]; then REC=llama     # 26B-A4B needs ~25GB + headroom; too big here
else                              REC=standard; fi
echo
echo "  LLM templates (via NVIDIA NIM — NGC key only):"
echo "    standard  → google/gemma-4-26B-A4B-it  (RECOMMENDED; NV-FP4 MoE, fits with Riva+Renny+RAG on a big GPU)"
echo "    llama     → meta/llama-3.1-8b-instruct (non-Gemma fallback; always available, fits small GPUs)"
echo
T="$(ask "Template (recommended: $REC)" "$REC")"

case "$T" in
  standard) GEMMA_BACKEND=nim; NIM_LLM_IMAGE="nvcr.io/nim/google/gemma-4-26b-a4b-it:1.7.0-variant"; GEMMA_MODEL="google/gemma-4-26B-A4B-it" ;;
  llama)    GEMMA_BACKEND=nim; NIM_LLM_IMAGE="nvcr.io/nim/meta/llama-3.1-8b-instruct:latest";       GEMMA_MODEL="meta/llama-3.1-8b-instruct" ;;
  *) echo "Unknown template '$T' (supported: standard | llama)"; exit 1 ;;
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
