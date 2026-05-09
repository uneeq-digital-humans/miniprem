#!/bin/bash

# NOT TO BE RUN DIRECTLY, PLEASE RUN THE MAIN SCRIPT CALLED "install_miniprem.sh"

# Seed-file (unattended install) support.
#
# Activation:
#   --seed FILE                       Load FILE; implies --non-interactive
#   --non-interactive                 Disable all interactive prompts
#   --interactive                     Force interactive even with --seed (mixed mode)
#   --force                           Auto-confirm all "continue?" gates
#
# Conventions:
#   - Every seed key is named MINIPREM_SEED_*
#   - The seed file is sourced as plain shell (KEY=value lines, comments OK)
#   - Each prompt site checks already-set values first; missing required values
#     under --non-interactive are aggregated and reported in one shot via
#     seed_check_required.

# ---------------------------------------------------------------------------
# Mode state (globals)
# ---------------------------------------------------------------------------

INTERACTIVE_MODE="${INTERACTIVE_MODE:-yes}"
FORCE_CONFIRMATIONS="${FORCE_CONFIRMATIONS:-no}"
SEED_FILE="${SEED_FILE:-}"
SEED_LOADED="no"

# Aggregated list of (key + hint) entries missing for a non-interactive run.
MINIPREM_SEED_MISSING=()

# Canonical list of keys the seed file is allowed to define. Anything else
# elicits a typo warning at load time.
MINIPREM_SEED_KNOWN_KEYS=(
    MINIPREM_SEED_INSTALL_TYPE
    MINIPREM_SEED_INSTALL_AS_SERVICE
    MINIPREM_SEED_TELEMETRY_CONSENT
    MINIPREM_SEED_DEPLOYMENT_TARGET
    MINIPREM_SEED_REGION
    MINIPREM_SEED_TTS_PROVIDER
    MINIPREM_SEED_AZURE_REGION
    MINIPREM_SEED_AZURE_SPEECH_KEY
    MINIPREM_SEED_ELEVEN_LABS_API_KEY
    MINIPREM_SEED_RIME_API_KEY
    MINIPREM_SEED_RIME_QUAY_PASSWORD
    MINIPREM_SEED_PLATFORM_ADDRESS
    MINIPREM_SEED_PLATFORM_KEY
    MINIPREM_SEED_TENANT_ID
    MINIPREM_SEED_RENNY_IMAGE
    MINIPREM_SEED_HARBOR_USERNAME
    MINIPREM_SEED_HARBOR_PASSWORD
    MINIPREM_SEED_STT_PROVIDER
    MINIPREM_SEED_CUSTOM_SERVICES
    MINIPREM_SEED_CUSTOM_SERVICES_FILE
    MINIPREM_SEED_FORCE
)

# ---------------------------------------------------------------------------
# Loading the seed file
# ---------------------------------------------------------------------------

# Source a seed file (KEY=value lines). Variables are exported so they remain
# visible after the function returns. Implies --non-interactive.
seed_load_file() {
    local file="$1"
    if [ -z "$file" ]; then
        return 0
    fi
    if [ ! -f "$file" ]; then
        fatal "Seed file not found: $file"
    fi
    if [ ! -r "$file" ]; then
        fatal "Seed file not readable: $file"
    fi

    info "Loading seed file: $file"

    # Seed files are config, not scripts. Disable -u and -e during sourcing so
    # that values containing literal $ (e.g. Harbor robot usernames like
    # robot$customer-name) don't trip the installer's strict mode if the
    # author forgot to single-quote them.
    set -a
    set +u
    set +e
    # shellcheck disable=SC1090
    . "$file"
    local _src_rc=$?
    set -u
    set -e
    set +a
    if [ $_src_rc -ne 0 ]; then
        fatal "Failed to source seed file: $file (exit $_src_rc)"
    fi

    SEED_FILE="$file"
    SEED_LOADED="yes"
    INTERACTIVE_MODE="no"

    # Typo guard: warn on unknown MINIPREM_SEED_* keys.
    local seen_key
    while IFS= read -r seen_key; do
        local known=0
        local k
        for k in "${MINIPREM_SEED_KNOWN_KEYS[@]}"; do
            if [ "$seen_key" = "$k" ]; then
                known=1
                break
            fi
        done
        if [ $known -eq 0 ]; then
            warning "Seed file contains unknown key: $seen_key (ignored)"
        fi
    done < <(grep -oE '^[[:space:]]*MINIPREM_SEED_[A-Z_]+' "$file" | sed -e 's/^[[:space:]]*//' | sort -u)

    # Honor MINIPREM_SEED_FORCE if set in the file itself.
    if [ "${MINIPREM_SEED_FORCE:-no}" = "yes" ]; then
        FORCE_CONFIRMATIONS="yes"
    fi
}

# Apply seed values into the canonical variables that the rest of the
# installer already uses. Only sets variables that are still empty, so CLI
# flags (which run later) take precedence over seed values.
seed_apply_to_vars() {
    [ "$SEED_LOADED" = "yes" ] || return 0

    : "${INSTALL_TYPE:=${MINIPREM_SEED_INSTALL_TYPE:-}}"
    : "${INSTALL_AS_SERVICE:=${MINIPREM_SEED_INSTALL_AS_SERVICE:-}}"
    : "${DEPLOYMENT_TARGET:=${MINIPREM_SEED_DEPLOYMENT_TARGET:-}}"
    : "${UNEEQ_REGION:=${MINIPREM_SEED_REGION:-}}"
    : "${TTS_PROVIDER:=${MINIPREM_SEED_TTS_PROVIDER:-}}"
    : "${AZURE_REGION:=${MINIPREM_SEED_AZURE_REGION:-}}"
    : "${AZURE_SPEECH_KEY:=${MINIPREM_SEED_AZURE_SPEECH_KEY:-}}"
    : "${ELEVEN_LABS_API_KEY:=${MINIPREM_SEED_ELEVEN_LABS_API_KEY:-}}"
    : "${RIME_API_KEY:=${MINIPREM_SEED_RIME_API_KEY:-}}"
    : "${RIME_QUAY_PASSWORD:=${MINIPREM_SEED_RIME_QUAY_PASSWORD:-}}"
    : "${PLATFORM_ADDRESS:=${MINIPREM_SEED_PLATFORM_ADDRESS:-}}"
    : "${PLATFORM_KEY:=${MINIPREM_SEED_PLATFORM_KEY:-}}"
    : "${TENANT_ID:=${MINIPREM_SEED_TENANT_ID:-}}"
    : "${RENNY_IMAGE:=${MINIPREM_SEED_RENNY_IMAGE:-}}"
    : "${TELEMETRY_CONSENT:=${MINIPREM_SEED_TELEMETRY_CONSENT:-}}"
    : "${STT_PROVIDER:=${MINIPREM_SEED_STT_PROVIDER:-}}"
    : "${CUSTOM_SERVICES_CHOICE:=${MINIPREM_SEED_CUSTOM_SERVICES:-}}"
    : "${CUSTOM_SERVICES_FILE_SEED:=${MINIPREM_SEED_CUSTOM_SERVICES_FILE:-}}"
}

# Write Harbor credentials from the seed (if any) into docker-compose.env so
# environment.sh::ensure_harbor_credentials picks them up via its existing
# read_env_variable path. Must be called after ensure_env_file_exists.
seed_apply_harbor_creds() {
    [ "$SEED_LOADED" = "yes" ] || return 0
    if [ -n "${MINIPREM_SEED_HARBOR_USERNAME:-}" ]; then
        update_env_variable "HARBOR_USERNAME" "$MINIPREM_SEED_HARBOR_USERNAME"
        info "Applied seeded HARBOR_USERNAME"
    fi
    if [ -n "${MINIPREM_SEED_HARBOR_PASSWORD:-}" ]; then
        update_env_variable "HARBOR_PASSWORD" "$MINIPREM_SEED_HARBOR_PASSWORD"
        info "Applied seeded HARBOR_PASSWORD"
    fi
}

# ---------------------------------------------------------------------------
# Mode predicates
# ---------------------------------------------------------------------------

seed_is_interactive() {
    [ "$INTERACTIVE_MODE" = "yes" ]
}

seed_is_non_interactive() {
    [ "$INTERACTIVE_MODE" != "yes" ]
}

seed_is_forced() {
    [ "$FORCE_CONFIRMATIONS" = "yes" ]
}

# ---------------------------------------------------------------------------
# Missing-key tracking (aggregated fail-fast)
# ---------------------------------------------------------------------------

seed_record_missing() {
    local key="$1"
    local hint="${2:-}"
    local entry="$key"
    if [ -n "$hint" ]; then
        entry="$key  ($hint)"
    fi
    MINIPREM_SEED_MISSING+=("$entry")
}

# Fatal exit listing every missing required key in one pass. Call once at the
# end of input gathering, before destructive work begins.
seed_check_required() {
    if [ ${#MINIPREM_SEED_MISSING[@]} -eq 0 ]; then
        return 0
    fi
    error "Non-interactive install is missing required seed values:"
    local entry
    for entry in "${MINIPREM_SEED_MISSING[@]}"; do
        echo "  - $entry" >&2
    done
    error "Add the missing keys to your seed file, or run interactively."
    fatal "Aborting due to incomplete seed configuration."
}

# ---------------------------------------------------------------------------
# Confirmation gates ("continue?", "proceed anyway?", etc.)
# ---------------------------------------------------------------------------

# Returns 0 (yes) or 1 (no). In non-interactive mode, returns 0 iff --force
# (or MINIPREM_SEED_FORCE=yes) was set, 1 otherwise.
#
# Usage: if seed_confirm "Proceed?"; then ... fi
seed_confirm() {
    local message="$1"
    local default="${2:-no}"

    if seed_is_non_interactive; then
        if seed_is_forced; then
            info "[non-interactive --force] $message -> yes"
            return 0
        else
            info "[non-interactive] $message -> no (use --force to override)"
            return 1
        fi
    fi

    local prompt="[y/N]"
    if [ "$default" = "yes" ]; then
        prompt="[Y/n]"
    fi
    local reply
    read -p "$message $prompt: " reply
    if [ -z "$reply" ]; then
        reply="$default"
    fi
    case "${reply,,}" in
        y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

# Validate that VAR's current value is in the allowed pipe-separated set.
# No-op if VAR is unset/empty. Fatal on mismatch.
seed_validate_choice() {
    local var_name="$1"
    local allowed="$2"
    local value="${!var_name:-}"
    [ -z "$value" ] && return 0
    case "|$allowed|" in
        *"|$value|"*) return 0 ;;
        *)
            fatal "Invalid value for $var_name: '$value' (allowed: $allowed)"
            ;;
    esac
}
