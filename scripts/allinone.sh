#!/bin/bash
#
# scripts/allinone.sh — bridge between the MiniPrem seed/installer and the
# Kubernetes all-in-one orchestrator (kubernetes/scripts/deploy-allinone.sh).
#
# NOT run directly. Sourced by the installer; call maybe_deploy_allinone after
# the core install + seed_apply_to_vars have run. When the seed set
# MINIPREM_SEED_ALLINONE=yes, this maps the canonical install variables into
# the env the orchestrator expects and invokes it.

# Resolve a value from the environment, else from docker-compose.env, else "".
_allinone_env_or_file() {
    local key="$1" val="${2:-}"
    if [ -n "$val" ]; then printf '%s' "$val"; return 0; fi
    local envfile="${PROJECT_ROOT:-.}/docker/docker-compose.env"
    if [ -f "$envfile" ]; then
        # last matching KEY=... wins; strip surrounding quotes
        local line
        line="$(grep -E "^[[:space:]]*${key}=" "$envfile" 2>/dev/null | tail -n1 || true)"
        printf '%s' "${line#*=}" | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
    fi
}

# Returns 0 and deploys when ALLINONE=yes; otherwise no-ops (returns 0).
maybe_deploy_allinone() {
    if [ "${ALLINONE:-no}" != "yes" ]; then
        return 0
    fi

    local script_dir deploy
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    deploy="$script_dir/../kubernetes/scripts/deploy-allinone.sh"

    if [ ! -x "$deploy" ] && [ ! -f "$deploy" ]; then
        warning "ALLINONE=yes but orchestrator not found at $deploy — skipping."
        return 0
    fi

    # NGC key is mandatory for the NVIDIA stack.
    if [ -z "${NGC_API_KEY:-}" ]; then
        if declare -f seed_record_missing >/dev/null 2>&1; then
            seed_record_missing "MINIPREM_SEED_NGC_API_KEY" "required when ALLINONE=yes"
        fi
        warning "ALLINONE=yes but NGC_API_KEY is empty — skipping all-in-one deploy."
        return 0
    fi

    # Harbor creds: prefer seed-applied env, fall back to docker-compose.env.
    local harbor_user harbor_pass
    harbor_user="$(_allinone_env_or_file HARBOR_USERNAME "${HARBOR_USERNAME:-${MINIPREM_SEED_HARBOR_USERNAME:-}}")"
    harbor_pass="$(_allinone_env_or_file HARBOR_PASSWORD "${HARBOR_PASSWORD:-${MINIPREM_SEED_HARBOR_PASSWORD:-}}")"

    info "ALLINONE=yes — launching NVIDIA all-in-one deploy via $deploy"

    # Map canonical install vars -> orchestrator env, then invoke it.
    NGC_API_KEY="$NGC_API_KEY" \
    HARBOR_USERNAME="$harbor_user" \
    HARBOR_PASSWORD="$harbor_pass" \
    PLATFORM_KEY="${PLATFORM_KEY:-}" \
    TENANT_ID="${TENANT_ID:-}" \
    GEMMA_MODEL="${GEMMA_MODEL:-google/gemma-3-27b-it}" \
    GEMMA_BACKEND="${GEMMA_BACKEND:-vllm}" \
    STT_PROVIDER="${KIOSK_STT_PROVIDER:-riva}" \
    KIOSK_BRAND="${KIOSK_BRAND:-dell}" \
    RAG_ADMIN_KEY="${RAG_ADMIN_KEY:-}" \
        bash "$deploy"
}
