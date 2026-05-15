#!/bin/bash

################################################################################
# MiniPrem CNS Local Deployment Script
#
# Interactive installation for NVIDIA Cloud Native Stack (CNS) on local hardware.
#
# Features:
#   - MicroK8s or kubeadm Kubernetes distribution
#   - NVIDIA GPU Operator with time-slicing
#   - Automatic GPU detection and replica recommendations
#   - Two installation modes: Minimal or Full Stack
#
# Installation Modes:
#   - Minimal: Renny only (uses cloud TTS/LLM)
#   - Full Stack: Renny + local NIM LLM + optional Riva TTS (air-gapped ready)
#
# Prerequisites:
#   - Ubuntu 24.04 LTS
#   - NVIDIA GPU(s) with driver installed
#   - Sudo access
#   - Internet connectivity (for pulling images)
#
# Interactive Usage (recommended):
#   sudo ./deploy-local.sh
#
# Non-Interactive Usage (for automation):
#   sudo CNS_INSTALL_MODE=minimal CNS_QUALITY_LEVEL=miniprem RENNY_REPLICAS=3 ./deploy-local.sh
#
# Environment Variables:
#   CNS_K8S_TYPE       - Kubernetes distribution: microk8s (default) or kubeadm
#   CNS_INSTALL_MODE   - Installation mode: minimal or full
#   CNS_QUALITY_LEVEL  - Renny quality: miniprem (higher quality) or web (more replicas)
#   RENNY_REPLICAS     - Number of Renny instances to deploy
#   NGC_API_KEY        - NVIDIA NGC API key (required for full stack mode)
#
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBERNETES_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
ANSIBLE_DIR="$KUBERNETES_DIR/ansible"

# Color codes
BOLD='\033[1m'
NC='\033[0m'

# Orange gradient colors for UneeQ logo

info() { echo "ℹ️  $*"; }
success() { echo "✅ $*"; }
warning() { echo "⚠️  $*"; }
error() { echo "❌ $*"; }

################################################################################
# UneeQ Logo
################################################################################

print_logo() {
    echo ""
    echo "  #     #  #    #  #######  #######  #######"
    echo "  #     #  ##   #  #        #        #     #"
    echo "  #     #  # #  #  #######  #######  #     #"
    echo "  #     #  #  # #  #        #        #     #"
    echo "  #     #  #   ##  #        #        #   # #"
    echo "   #####   #    #  #######  #######  #######"
    echo "  ################################################"
    echo "               DIGITALHUMANS.COM"
    echo ""
}

################################################################################
# Progress Spinner
################################################################################

SPINNER_PID=""

start_spinner() {
    local msg="${1:-Working...}"
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

    (
        while true; do
            for (( i=0; i<${#chars}; i++ )); do
                echo -ne "\r${chars:$i:1}${NC} $msg"
                sleep 0.1
            done
        done
    ) &
    SPINNER_PID=$!
}

stop_spinner() {
    local status="${1:-0}"
    local msg="${2:-}"

    if [[ -n "$SPINNER_PID" ]]; then
        kill $SPINNER_PID 2>/dev/null
        wait $SPINNER_PID 2>/dev/null || true
        SPINNER_PID=""
    fi

    # Clear the line
    echo -ne "\r\033[K"

    # Print result message
    if [[ -n "$msg" ]]; then
        if [[ "$status" -eq 0 ]]; then
            success "$msg"
        else
            error "$msg"
        fi
    fi
}

################################################################################
# Cleanup Handler
################################################################################

CLEANUP_STAGE=""
CLEANUP_ENABLED=true

cleanup_on_failure() {
    local exit_code=$?

    # Don't cleanup if disabled or if exit was successful
    if [[ "$CLEANUP_ENABLED" != "true" ]] || [[ $exit_code -eq 0 ]]; then
        return
    fi

    # Stop any running spinner
    stop_spinner 1

    echo ""
    error "Installation failed at stage: ${CLEANUP_STAGE:-unknown}"
    echo ""

    # Save progress for resume (uses the most recently-marked stage so the
    # next run knows where to pick up). If mark_progress has been called at
    # least once this run, CNS_PROGRESS_FILE already exists; this is a
    # safety net for paths that fail before any explicit mark_progress.
    if [[ -n "${CNS_PROGRESS_STAGE:-}" ]] && [[ ! -f "$CNS_PROGRESS_FILE" ]]; then
        mark_progress "$CNS_PROGRESS_STAGE" "exit_$exit_code"
    fi
    if [[ -f "$CNS_PROGRESS_FILE" ]]; then
        info "Progress saved to: $CNS_PROGRESS_FILE"
        info "Rerun this script and answer 'Y' to the resume prompt to continue."
        echo ""
    fi

    # Offer cleanup options
    echo "What would you like to do?"
    echo "  1) Leave partial installation (for debugging or resume)"
    echo "  2) Clean up and exit (discards partial install AND progress)"
    echo ""
    read -p "Enter choice [1-2] (default: 1): " cleanup_choice
    cleanup_choice="${cleanup_choice:-1}"

    if [[ "$cleanup_choice" == "2" ]]; then
        warning "Cleaning up partial installation..."

        local KUBECTL="kubectl"
        if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
            KUBECTL="microk8s kubectl"
        fi

        # Clean up Helm releases
        if command -v helm &>/dev/null || command -v microk8s &>/dev/null; then
            local HELM="helm"
            [[ "$CNS_K8S_TYPE" == "microk8s" ]] && HELM="microk8s helm3"
            $HELM uninstall renny -n uneeq 2>/dev/null || true
            $HELM uninstall gpu-operator -n gpu-operator 2>/dev/null || true
            $HELM uninstall digitalhuman-interface -n uneeq 2>/dev/null || true
            $HELM uninstall digitalhuman-ws-api -n uneeq 2>/dev/null || true
            $HELM uninstall digitalhuman-asr -n uneeq 2>/dev/null || true
        fi

        # Clean up namespaces
        $KUBECTL delete namespace uneeq --ignore-not-found 2>/dev/null || true

        # Discard progress so the next run starts clean.
        clear_progress 2>/dev/null || true

        success "Cleanup complete. You can re-run the installer."
    else
        info "Partial installation left in place for debugging or resume."
        echo ""
        echo "To manually inspect:"
        if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
            echo "  microk8s kubectl get pods -A"
            echo "  microk8s kubectl describe pod <pod-name> -n <namespace>"
        else
            echo "  kubectl get pods -A"
            echo "  kubectl describe pod <pod-name> -n <namespace>"
        fi
    fi

    echo ""
    exit $exit_code
}

# Install trap handler
trap cleanup_on_failure EXIT

################################################################################
# Configuration
################################################################################

CNS_K8S_TYPE="${CNS_K8S_TYPE:-kubeadm}"
NGC_API_KEY="${NGC_API_KEY:-}"
NVIDIA_DIR="${NVIDIA_DIR:-$KUBERNETES_DIR/../nvidia}"
RENNY_REPLICAS="${RENNY_REPLICAS:-4}"  # Number of Renny instances (adjust for GPU count)
GPU_TIMESLICE_REPLICAS="${GPU_TIMESLICE_REPLICAS:-8}"  # GPU time-slices per physical GPU

# Version pinning
MICROK8S_CHANNEL="1.31/stable"
GPU_OPERATOR_VERSION="v24.9.0"
NIM_OPERATOR_VERSION="3.1.0"

# Installation mode (set during interactive prompt)
CNS_INSTALL_MODE="${CNS_INSTALL_MODE:-}"  # minimal or full
CNS_QUALITY_LEVEL="${CNS_QUALITY_LEVEL:-miniprem}"  # miniprem or web

# CNS Configuration file (persists credentials between runs)
CNS_CONFIG_FILE="${CNS_CONFIG_FILE:-$SCRIPT_DIR/.cns_config}"

# CNS deploy progress file (separate from .cns_config so we can clear on success
# without losing credentials). Tracks the last completed install stage so a
# failed run can be resumed.
CNS_PROGRESS_FILE="${CNS_PROGRESS_FILE:-$SCRIPT_DIR/.cns_deploy_progress}"

# Digital Human stack opt-in flags (set by prompt_digitalhuman_stack)
DEPLOY_DH_STACK="${DEPLOY_DH_STACK:-}"
DEPLOY_DH_ASR="${DEPLOY_DH_ASR:-}"

# Resume flag (set when user opts into resuming a previous run)
CNS_RESUME="${CNS_RESUME:-false}"
CNS_PROGRESS_STAGE=""
CNS_PROGRESS_LAST_ERROR=""

# Credential variables (set during interactive prompts or from config file)
HARBOR_USERNAME="${HARBOR_USERNAME:-}"
HARBOR_PASSWORD="${HARBOR_PASSWORD:-}"
DHOP_APIKEY="${DHOP_APIKEY:-}"
DHOP_TENANTID="${DHOP_TENANTID:-}"
UNEEQ_REGION="${UNEEQ_REGION:-us}"  # us or eu
TTS_PROVIDER="${TTS_PROVIDER:-}"  # azure, elevenlabs, rime, riva, or custom

# TTS Provider-specific credentials
AZURE_REGION="${AZURE_REGION:-}"
AZURE_SPEECH_KEY="${AZURE_SPEECH_KEY:-}"
ELEVEN_LABS_API_KEY="${ELEVEN_LABS_API_KEY:-}"
RIME_API_KEY="${RIME_API_KEY:-}"

################################################################################
# Configuration Persistence
################################################################################

load_cns_config() {
    if [[ -f "$CNS_CONFIG_FILE" ]]; then
        info "Loading saved configuration from $CNS_CONFIG_FILE"
        source "$CNS_CONFIG_FILE"
        return 0
    fi
    return 1
}

# Escape a value for safe use in single quotes
# Replaces ' with '\'' (end quote, escaped quote, start quote)
escape_single_quote() {
    printf '%s' "$1" | sed "s/'/'\\\\''/g"
}

save_cns_config() {
    info "Saving configuration to $CNS_CONFIG_FILE"

    # Use single quotes for values to prevent $variable expansion when sourced
    # This handles passwords/keys containing $ and other special characters
    cat > "$CNS_CONFIG_FILE" << EOF
# CNS Configuration - Auto-generated by deploy-local.sh
# This file contains credentials for CNS deployment
# DO NOT commit this file to version control

# CNS Installation Marker (used by miniprem.sh for detection)
CNS_INSTALLED=true
CNS_K8S_TYPE='$(escape_single_quote "$CNS_K8S_TYPE")'

# Harbor Registry Credentials
HARBOR_USERNAME='$(escape_single_quote "$HARBOR_USERNAME")'
HARBOR_PASSWORD='$(escape_single_quote "$HARBOR_PASSWORD")'

# UneeQ Platform Credentials
DHOP_APIKEY='$(escape_single_quote "$DHOP_APIKEY")'
DHOP_TENANTID='$(escape_single_quote "$DHOP_TENANTID")'
UNEEQ_REGION='$(escape_single_quote "$UNEEQ_REGION")'

# TTS Provider Configuration
TTS_PROVIDER='$(escape_single_quote "$TTS_PROVIDER")'
AZURE_REGION='$(escape_single_quote "$AZURE_REGION")'
AZURE_SPEECH_KEY='$(escape_single_quote "$AZURE_SPEECH_KEY")'
ELEVEN_LABS_API_KEY='$(escape_single_quote "$ELEVEN_LABS_API_KEY")'
RIME_API_KEY='$(escape_single_quote "$RIME_API_KEY")'

# Installation Settings
CNS_INSTALL_MODE='$(escape_single_quote "$CNS_INSTALL_MODE")'
CNS_QUALITY_LEVEL='$(escape_single_quote "$CNS_QUALITY_LEVEL")'
RENNY_REPLICAS='$(escape_single_quote "$RENNY_REPLICAS")'
GPU_TIMESLICE_REPLICAS='$(escape_single_quote "$GPU_TIMESLICE_REPLICAS")'
EOF
    chmod 600 "$CNS_CONFIG_FILE"
    success "Configuration saved"
}

################################################################################
# Deploy Progress Tracking (for resume after failure)
################################################################################

# Stage order — defines what counts as "before" a given stage when checking
# whether a resumed run should skip a step.
CNS_STAGE_ORDER=(
    "prerequisites"
    "xvfb_setup"
    "vulkan_setup"
    "ngc_key"
    "kubernetes_install"
    "gpu_timeslicing"
    "renny_deploy"
    "dh_interface"
    "dh_websocket_api"
    "dh_asr"
    "verify"
)

# stage_index <stage-name> — print numeric position of stage in CNS_STAGE_ORDER,
# or -1 if not found.
stage_index() {
    local target="$1"
    local i=0
    for s in "${CNS_STAGE_ORDER[@]}"; do
        if [[ "$s" == "$target" ]]; then
            echo "$i"
            return 0
        fi
        i=$((i + 1))
    done
    echo "-1"
}

mark_progress() {
    local stage="$1"
    local last_error="${2:-}"
    CNS_PROGRESS_STAGE="$stage"
    CNS_PROGRESS_LAST_ERROR="$last_error"
    cat > "$CNS_PROGRESS_FILE" << EOF
# CNS Deploy Progress - Auto-generated by deploy-local.sh
# Tracks the in-flight install stage so a failed run can be resumed.
# Safe to delete manually if you want to force a fresh install.

CNS_PROGRESS_STAGE='$(escape_single_quote "$stage")'
CNS_PROGRESS_TIMESTAMP='$(date +%s)'
CNS_PROGRESS_LAST_ERROR='$(escape_single_quote "$last_error")'
DEPLOY_DH_STACK='$(escape_single_quote "$DEPLOY_DH_STACK")'
DEPLOY_DH_ASR='$(escape_single_quote "$DEPLOY_DH_ASR")'
EOF
    chmod 600 "$CNS_PROGRESS_FILE" 2>/dev/null || true
}

load_progress() {
    if [[ -f "$CNS_PROGRESS_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$CNS_PROGRESS_FILE"
        return 0
    fi
    return 1
}

clear_progress() {
    rm -f "$CNS_PROGRESS_FILE"
}

# should_run_stage <stage-name>
# Returns 0 (run it) if either we're not resuming, or if the resumed stage is
# at or earlier than the given stage. Returns 1 (skip it) if we already
# completed this stage in a previous run.
#
# Semantic: CNS_PROGRESS_STAGE stores the stage that was IN PROGRESS when the
# previous run died. So when resuming we want to RE-RUN that stage and
# everything after it, and SKIP everything before it.
should_run_stage() {
    local stage="$1"
    if [[ "$CNS_RESUME" != "true" ]]; then
        return 0
    fi
    local target_idx
    local current_idx
    target_idx=$(stage_index "$stage")
    current_idx=$(stage_index "$CNS_PROGRESS_STAGE")
    if [[ "$current_idx" == "-1" ]] || [[ "$target_idx" == "-1" ]]; then
        return 0  # Unknown stage — run it to be safe
    fi
    if [[ "$target_idx" -ge "$current_idx" ]]; then
        return 0  # Run this stage and everything after
    fi
    return 1  # Already done in previous run
}

################################################################################
# Harbor Registry Credentials
################################################################################

prompt_harbor_credentials() {
    echo "
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Harbor Registry Credentials                              │
└─────────────────────────────────────────────────────────────────────────────┘
"
    echo "Harbor registry credentials are required to pull Renny images from cr.uneeq.io"
    echo ""
    echo "If you don't have Harbor credentials:"
    echo "  - Contact: help@uneeq.com"
    echo "  - Or ask your UneeQ representative"
    echo ""

    # Check if we have saved credentials
    if [[ -n "$HARBOR_USERNAME" && -n "$HARBOR_PASSWORD" ]]; then
        echo "Found saved credentials for: $HARBOR_USERNAME"
        read -p "Use saved credentials? [Y/n]: " use_saved
        if [[ ! "$use_saved" =~ ^[Nn]$ ]]; then
            return 0
        fi
    fi

    read -p "Enter Harbor robot username (e.g., robot\$customer-name): " HARBOR_USERNAME
    read -s -p "Enter Harbor robot password: " HARBOR_PASSWORD
    echo ""
}

validate_harbor_credentials() {
    info "Validating Harbor credentials..."

    # Test Docker login to Harbor
    if echo "$HARBOR_PASSWORD" | docker login cr.uneeq.io -u "$HARBOR_USERNAME" --password-stdin 2>/dev/null; then
        success "Harbor authentication successful"
        return 0
    else
        error "Harbor authentication failed"
        return 1
    fi
}

ensure_harbor_credentials() {
    local max_attempts=3
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        prompt_harbor_credentials

        if validate_harbor_credentials; then
            return 0
        fi

        warning "Authentication failed. Attempt $attempt of $max_attempts"
        ((attempt++))

        if [[ $attempt -le $max_attempts ]]; then
            echo ""
            warning "Please check your credentials and try again."
            HARBOR_USERNAME=""
            HARBOR_PASSWORD=""
        fi
    done

    error "Failed to authenticate with Harbor after $max_attempts attempts"
    echo ""
    echo "Please verify your credentials with your UneeQ representative."
    exit 1
}

################################################################################
# Region Selection
################################################################################

prompt_for_region() {
    echo "
┌─────────────────────────────────────────────────────────────────────────────┐
│                     UneeQ Region Selection                                   │
└─────────────────────────────────────────────────────────────────────────────┘
"
    echo "Select your UneeQ platform region:"
    echo ""
    echo "  1) US (api.enterprise.uneeq.io)"
    echo "  2) EU (api-eu.enterprise.uneeq.io)"
    echo ""

    local choice
    while true; do
        read -p "Enter choice [1-2] (default: 1): " choice
        choice="${choice:-1}"

        case "$choice" in
            1)
                UNEEQ_REGION="us"
                DHOP_URL="wss://api.enterprise.uneeq.io:443/signalling-service"
                success "Selected: US region"
                break
                ;;
            2)
                UNEEQ_REGION="eu"
                DHOP_URL="wss://api-eu.enterprise.uneeq.io:443/signalling-service"
                success "Selected: EU region"
                break
                ;;
            *)
                warning "Invalid choice. Please enter 1 or 2."
                ;;
        esac
    done
    echo ""
}

################################################################################
# UneeQ Platform Credentials (DHOP)
################################################################################

prompt_dhop_credentials() {
    echo "
┌─────────────────────────────────────────────────────────────────────────────┐
│                     UneeQ Platform Credentials                               │
└─────────────────────────────────────────────────────────────────────────────┘
"
    echo "Enter your UneeQ platform credentials from the Admin Portal."
    echo ""
    echo "To find these values:"
    echo "  1. Log in to the UneeQ Admin Portal"
    echo "  2. Go to Settings → API Keys"
    echo "  3. Copy the API Key and Tenant ID"
    echo ""

    # Check for saved credentials
    if [[ -n "$DHOP_APIKEY" && -n "$DHOP_TENANTID" ]]; then
        echo "Found saved credentials:"
        echo "  Tenant ID: $DHOP_TENANTID"
        echo "  API Key: ${DHOP_APIKEY:0:8}..."
        read -p "Use saved credentials? [Y/n]: " use_saved
        if [[ ! "$use_saved" =~ ^[Nn]$ ]]; then
            return 0
        fi
    fi

    while [[ -z "$DHOP_TENANTID" ]]; do
        read -p "Enter your Tenant ID: " DHOP_TENANTID
        if [[ -z "$DHOP_TENANTID" ]]; then
            warning "Tenant ID is required."
        fi
    done

    while [[ -z "$DHOP_APIKEY" ]]; do
        read -p "Enter your API Key: " DHOP_APIKEY
        if [[ -z "$DHOP_APIKEY" ]]; then
            warning "API Key is required."
        fi
    done

    success "UneeQ platform credentials configured"
    echo ""
}

################################################################################
# TTS Provider Selection and Configuration
################################################################################

prompt_tts_provider() {
    echo "
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Text-to-Speech Provider Selection                        │
└─────────────────────────────────────────────────────────────────────────────┘
"
    echo "Select your text-to-speech provider:"
    echo ""
    echo "  1) Azure Speech Services"
    echo "     Microsoft Azure TTS - High quality, many voices"
    echo ""
    echo "  2) ElevenLabs"
    echo "     AI-powered voices with natural speech"
    echo ""
    echo "  3) RIME"
    echo "     UneeQ partner TTS service"
    echo ""

    if [[ "$CNS_INSTALL_MODE" == "full" ]]; then
        echo "  4) NVIDIA Riva (Local)"
        echo "     Local TTS for air-gapped deployments"
        echo ""
    fi

    local max_choice=3
    [[ "$CNS_INSTALL_MODE" == "full" ]] && max_choice=4

    local choice
    while true; do
        read -p "Enter choice [1-$max_choice]: " choice

        case "$choice" in
            1)
                TTS_PROVIDER="azure"
                success "Selected: Azure Speech Services"
                configure_azure_tts
                break
                ;;
            2)
                TTS_PROVIDER="elevenlabs"
                success "Selected: ElevenLabs"
                configure_elevenlabs_tts
                break
                ;;
            3)
                TTS_PROVIDER="rime"
                success "Selected: RIME"
                configure_rime_tts
                break
                ;;
            4)
                if [[ "$CNS_INSTALL_MODE" == "full" ]]; then
                    TTS_PROVIDER="riva"
                    success "Selected: NVIDIA Riva (Local)"
                    info "Riva will be deployed as part of the full stack installation"
                    break
                else
                    warning "Invalid choice. Please enter 1-$max_choice."
                fi
                ;;
            *)
                warning "Invalid choice. Please enter 1-$max_choice."
                ;;
        esac
    done
    echo ""
}

configure_azure_tts() {
    echo ""
    echo "Configure Azure Speech Services:"
    echo "  Get credentials from: portal.azure.com → Speech Service → Keys"
    echo ""

    if [[ -n "$AZURE_REGION" && -n "$AZURE_SPEECH_KEY" ]]; then
        echo "Found saved Azure credentials:"
        echo "  Region: $AZURE_REGION"
        echo "  Key: ${AZURE_SPEECH_KEY:0:8}..."
        read -p "Use saved credentials? [Y/n]: " use_saved
        if [[ ! "$use_saved" =~ ^[Nn]$ ]]; then
            return 0
        fi
    fi

    while [[ -z "$AZURE_REGION" ]]; do
        read -p "Enter Azure region (e.g., eastus, westus2): " AZURE_REGION
        if [[ -z "$AZURE_REGION" ]]; then
            warning "Azure region is required."
        fi
    done

    while [[ -z "$AZURE_SPEECH_KEY" ]]; do
        read -p "Enter Azure Speech Key: " AZURE_SPEECH_KEY
        if [[ -z "$AZURE_SPEECH_KEY" ]]; then
            warning "Azure Speech Key is required."
        fi
    done

    success "Azure TTS configured"
}

configure_elevenlabs_tts() {
    echo ""
    echo "Configure ElevenLabs:"
    echo "  Get API key from: elevenlabs.io → Profile → API Keys"
    echo ""

    if [[ -n "$ELEVEN_LABS_API_KEY" ]]; then
        echo "Found saved ElevenLabs API key: ${ELEVEN_LABS_API_KEY:0:8}..."
        read -p "Use saved credentials? [Y/n]: " use_saved
        if [[ ! "$use_saved" =~ ^[Nn]$ ]]; then
            return 0
        fi
    fi

    while [[ -z "$ELEVEN_LABS_API_KEY" ]]; do
        read -p "Enter ElevenLabs API Key: " ELEVEN_LABS_API_KEY
        if [[ -z "$ELEVEN_LABS_API_KEY" ]]; then
            warning "ElevenLabs API Key is required."
        fi
    done

    success "ElevenLabs TTS configured"
}

configure_rime_tts() {
    echo ""
    echo "Configure RIME:"
    echo "  Contact your UneeQ representative for RIME credentials"
    echo ""

    if [[ -n "$RIME_API_KEY" ]]; then
        echo "Found saved RIME API key: ${RIME_API_KEY:0:8}..."
        read -p "Use saved credentials? [Y/n]: " use_saved
        if [[ ! "$use_saved" =~ ^[Nn]$ ]]; then
            return 0
        fi
    fi

    while [[ -z "$RIME_API_KEY" ]]; do
        read -p "Enter RIME API Key: " RIME_API_KEY
        if [[ -z "$RIME_API_KEY" ]]; then
            warning "RIME API Key is required."
        fi
    done

    success "RIME TTS configured"
}

################################################################################
# GPU Detection and Replica Calculation
################################################################################

detect_gpu_info() {
    info "Detecting GPU configuration..."

    if ! command -v nvidia-smi &> /dev/null; then
        warning "nvidia-smi not found. Using default GPU configuration."
        GPU_NAME="Unknown"
        GPU_VRAM_MB=0
        GPU_COUNT=0
        return
    fi

    # Get GPU name (first GPU)
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | xargs)

    # Get total VRAM in MB (first GPU)
    GPU_VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | xargs)

    # Get GPU count
    GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l)

    # Calculate VRAM in GB for display
    GPU_VRAM_GB=$((GPU_VRAM_MB / 1024))

    success "Detected: $GPU_NAME with ${GPU_VRAM_GB}GB VRAM ($GPU_COUNT GPU(s))"
}

calculate_recommended_replicas() {
    # Based on tested GPU capacity table from renny-values-cns.yaml
    # This calculates recommended Renny replicas based on:
    # - GPU VRAM
    # - Quality level (miniprem vs web)
    # - Install mode (full stack reserves VRAM for LLM)

    local vram_mb="${GPU_VRAM_MB:-0}"
    local quality="${CNS_QUALITY_LEVEL:-miniprem}"
    local mode="${CNS_INSTALL_MODE:-minimal}"

    # Reserve VRAM for LLM if full stack mode
    local llm_reserve_mb=0
    if [[ "$mode" == "full" ]]; then
        llm_reserve_mb=16384  # Reserve ~16GB for local LLM
    fi

    local available_vram=$((vram_mb - llm_reserve_mb))

    # VRAM requirements per Renny instance (estimated from testing)
    # MiniPrem mode: ~9-10GB per instance (higher quality textures)
    # Web mode: ~7-8GB per instance (optimized for cloud)
    local vram_per_renny
    if [[ "$quality" == "miniprem" ]]; then
        vram_per_renny=10240  # 10GB for miniprem quality
    else
        vram_per_renny=8192   # 8GB for web quality
    fi

    # Calculate recommended replicas
    if [[ $available_vram -lt $vram_per_renny ]]; then
        RECOMMENDED_REPLICAS=1
    else
        RECOMMENDED_REPLICAS=$((available_vram / vram_per_renny))
    fi

    # Apply known GPU-specific overrides from tested capacity table
    case "$GPU_NAME" in
        *"RTX PRO 6000"*|*"Blackwell"*)
            # RTX PRO 6000 Blackwell = 96GB VRAM
            if [[ "$quality" == "miniprem" ]]; then
                RECOMMENDED_REPLICAS=6
            else
                RECOMMENDED_REPLICAS=10
            fi
            ;;
        *"RTX 6000"*|*"Ada"*|*"A6000"*)
            # RTX 6000 Ada / RTX A6000 = 48GB VRAM
            if [[ "$quality" == "miniprem" ]]; then
                RECOMMENDED_REPLICAS=3
            else
                RECOMMENDED_REPLICAS=5
            fi
            ;;
        *"A100"*"80G"*)
            if [[ "$quality" == "miniprem" ]]; then
                RECOMMENDED_REPLICAS=5
            else
                RECOMMENDED_REPLICAS=8
            fi
            ;;
        *"A100"*"40G"*|*"A100"*)
            if [[ "$quality" == "miniprem" ]]; then
                RECOMMENDED_REPLICAS=2
            else
                RECOMMENDED_REPLICAS=4
            fi
            ;;
        *"T4"*)
            if [[ "$quality" == "miniprem" ]]; then
                RECOMMENDED_REPLICAS=1
            else
                RECOMMENDED_REPLICAS=2
            fi
            ;;
        *"L4"*)
            if [[ "$quality" == "miniprem" ]]; then
                RECOMMENDED_REPLICAS=2
            else
                RECOMMENDED_REPLICAS=3
            fi
            ;;
    esac

    # Reduce by 1-2 for full stack mode (LLM needs VRAM)
    if [[ "$mode" == "full" ]] && [[ $RECOMMENDED_REPLICAS -gt 1 ]]; then
        RECOMMENDED_REPLICAS=$((RECOMMENDED_REPLICAS - 1))
    fi

    # Multiply by GPU count for multi-GPU systems
    RECOMMENDED_REPLICAS=$((RECOMMENDED_REPLICAS * GPU_COUNT))

    # Ensure at least 1 replica
    if [[ $RECOMMENDED_REPLICAS -lt 1 ]]; then
        RECOMMENDED_REPLICAS=1
    fi

    success "Recommended Renny replicas: $RECOMMENDED_REPLICAS"
}

################################################################################
# Interactive Installation Prompts
################################################################################

prompt_for_install_mode() {
    echo "
┌─────────────────────────────────────────────────────────────────────────────┐
│                     CNS Installation Mode Selection                          │
└─────────────────────────────────────────────────────────────────────────────┘
"

    echo "Choose your installation mode:"
    echo ""
    echo "  1) Minimal (Renny Only)"
    echo "     - Renny digital human renderer"
    echo "     - Uses cloud TTS (ElevenLabs, Azure, etc.)"
    echo "     - Uses cloud LLM (requires Flowise cloud connection)"
    echo "     - Best for: Internet-connected deployments"
    echo ""
    echo "  2) Full Stack (Air-Gapped Ready)"
    echo "     - Renny digital human renderer"
    echo "     - Local LLM via NIM (Llama 3.1, etc.)"
    echo "     - Optional: NVIDIA Riva TTS (local speech synthesis)"
    echo "     - Optional: Local Flowise orchestration"
    echo "     - Best for: Air-gapped/low-latency deployments"
    echo ""

    local choice
    while true; do
        read -p "Enter choice [1-2] (default: 1): " choice
        choice="${choice:-1}"

        case "$choice" in
            1)
                CNS_INSTALL_MODE="minimal"
                success "Selected: Minimal installation (Renny only)"
                break
                ;;
            2)
                CNS_INSTALL_MODE="full"
                success "Selected: Full Stack installation (Air-gapped ready)"
                break
                ;;
            *)
                warning "Invalid choice. Please enter 1 or 2."
                ;;
        esac
    done

    echo ""
}

prompt_for_quality_level() {
    echo "
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Renny Quality Level Selection                            │
└─────────────────────────────────────────────────────────────────────────────┘
"

    echo "Choose your Renny quality level:"
    echo ""
    echo "  1) MiniPrem (Higher Quality)"
    echo "     - For MiniPrem-specific character maps ONLY"
    echo "     - Higher quality textures and rendering"
    echo "     - Fewer concurrent Rennys per GPU"
    echo ""
    echo "     ⚠️  IMPORTANT: Only use MiniPrem quality with MiniPrem-specific"
    echo "        character maps. Standard digital humans should use Web quality."
    echo ""
    echo "  2) Web (Standard Quality)"
    echo "     - For standard/stock digital humans (UneeQ stock character maps)"
    echo "     - More concurrent Rennys per GPU"
    echo ""

    # Show GPU-specific recommendations
    if [[ -n "${GPU_NAME:-}" && -n "${GPU_VRAM_GB:-}" ]]; then
        echo "Recommendations for your GPU ($GPU_NAME - ${GPU_VRAM_GB}GB):"
        case "$GPU_NAME" in
            *"RTX PRO 6000"*|*"Blackwell"*)
                # RTX PRO 6000 Blackwell = 96GB
                echo "  • MiniPrem quality: 6 Rennys"
                echo "  • Web quality: 10 Rennys"
                ;;
            *"RTX 6000"*|*"Ada"*|*"A6000"*)
                # RTX 6000 Ada / RTX A6000 = 48GB
                echo "  • MiniPrem quality: 3 Rennys"
                echo "  • Web quality: 5 Rennys"
                ;;
            *"A100"*"80G"*)
                echo "  • MiniPrem quality: 5 Rennys"
                echo "  • Web quality: 8 Rennys"
                ;;
            *"A100"*|*"40G"*)
                echo "  • MiniPrem quality: 2 Rennys"
                echo "  • Web quality: 4 Rennys"
                ;;
            *"L4"*|*"RTX 4090"*)
                echo "  • MiniPrem quality: 2 Rennys"
                echo "  • Web quality: 3 Rennys"
                ;;
            *"T4"*)
                echo "  • MiniPrem quality: 1 Renny"
                echo "  • Web quality: 2 Rennys"
                ;;
        esac
        echo ""
    fi

    local choice
    while true; do
        read -p "Enter choice [1-2] (default: 2 - Web): " choice
        choice="${choice:-2}"

        case "$choice" in
            1)
                CNS_QUALITY_LEVEL="miniprem"
                echo ""
                echo "⚠️  IMPORTANT: MiniPrem quality requires MiniPrem character maps."
                echo "   Standard/stock digital humans should use Web quality instead."
                echo ""
                read -p "Do you have MiniPrem character maps? [y/N]: " confirm_miniprem
                if [[ "${confirm_miniprem,,}" != "y" ]]; then
                    CNS_QUALITY_LEVEL="web"
                    success "Changed to Web quality (for standard digital humans)"
                else
                    success "Selected: MiniPrem quality (for MiniPrem character maps)"
                fi
                break
                ;;
            2)
                CNS_QUALITY_LEVEL="web"
                success "Selected: Web quality (for standard digital humans)"
                break
                ;;
            *)
                warning "Invalid choice. Please enter 1 or 2."
                ;;
        esac
    done

    echo ""
}

prompt_for_renny_replicas() {
    echo "
┌─────────────────────────────────────────────────────────────────────────────┐
│                     Renny Instance Configuration                             │
└─────────────────────────────────────────────────────────────────────────────┘
"

    # Show GPU capacity table
    echo "GPU Capacity Reference (without local LLM):"
    echo "┌───────────────────────────┬───────┬─────────────┬──────────────────┐"
    echo "│ GPU                       │ VRAM  │ Web Mode    │ MiniPrem Mode    │"
    echo "├───────────────────────────┼───────┼─────────────┼──────────────────┤"
    echo "│ RTX PRO 6000 Blackwell    │ 96GB  │ 10 replicas │ 6 replicas       │"
    echo "│ A100 80GB                 │ 80GB  │ 8 replicas  │ 5 replicas       │"
    echo "│ RTX 6000 Ada              │ 48GB  │ 5 replicas  │ 3 replicas       │"
    echo "│ A100 40GB                 │ 40GB  │ 4 replicas  │ 2 replicas       │"
    echo "│ L4 / RTX 4090             │ 24GB  │ 3 replicas  │ 2 replicas       │"
    echo "│ T4                        │ 16GB  │ 2 replicas  │ 1 replica        │"
    echo "└───────────────────────────┴───────┴─────────────┴──────────────────┘"
    echo ""
    echo "Note: Running a local LLM (Full Stack mode) reduces available capacity."
    echo ""

    # Show detected GPU and recommendation
    echo "Detected GPU: $GPU_NAME (${GPU_VRAM_GB:-0}GB VRAM, $GPU_COUNT GPU(s))"
    echo "Quality Level: $CNS_QUALITY_LEVEL"
    echo "Install Mode: $CNS_INSTALL_MODE"
    echo "Recommended Renny replicas: $RECOMMENDED_REPLICAS"
    echo ""

    local choice
    while true; do
        read -p "Enter number of Renny instances (default: $RECOMMENDED_REPLICAS): " choice
        choice="${choice:-$RECOMMENDED_REPLICAS}"

        # Validate input is a positive number
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -gt 0 ]]; then
            RENNY_REPLICAS="$choice"

            # Warn if significantly over recommendation
            if [[ "$RENNY_REPLICAS" -gt $((RECOMMENDED_REPLICAS + 2)) ]]; then
                warning "You selected $RENNY_REPLICAS replicas (recommended: $RECOMMENDED_REPLICAS)"
                echo "  This may cause GPU memory issues. Continue? (y/N)"
                read -p "> " confirm
                if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                    continue
                fi
            fi

            success "Configured: $RENNY_REPLICAS Renny instance(s)"
            break
        else
            warning "Please enter a positive number."
        fi
    done

    # Also set GPU time-slicing replicas per GPU
    GPU_TIMESLICE_REPLICAS=$((RENNY_REPLICAS / GPU_COUNT))
    if [[ $GPU_TIMESLICE_REPLICAS -lt 1 ]]; then
        GPU_TIMESLICE_REPLICAS=1
    fi

    echo ""
}

################################################################################
# Digital Human Stack Opt-In Prompt
################################################################################

# VRAM costs for VRAM-fit validation (MB). These mirror the per-renny constants
# in calculate_recommended_replicas() so the inverse math stays consistent.
VRAM_PER_RENNY_MINIPREM_MB=10240   # 10 GB
VRAM_PER_RENNY_WEB_MB=8192         # 8 GB
VRAM_LLM_RESERVE_MB=16384          # 16 GB reserve for full-stack NIM LLM
VRAM_ASR_NEMOTRON_MB=15360         # 15 GB for Nemotron streaming ASR NIM
VRAM_GPU_OVERHEAD_MB=2048          # 2 GB headroom for driver/operator overhead

prompt_digitalhuman_stack() {
    # Dependency rule: DH stack requires Renny (miniprem). If for any reason
    # replicas got set to 0, skip the prompt.
    if [[ "${RENNY_REPLICAS:-0}" -lt 1 ]]; then
        DEPLOY_DH_STACK="false"
        DEPLOY_DH_ASR="false"
        return 0
    fi

    echo "
┌─────────────────────────────────────────────────────────────────────────────┐
│                Digital Human Stack (Optional Add-On)                         │
└─────────────────────────────────────────────────────────────────────────────┘
"
    echo "The Digital Human stack adds three components alongside Renny:"
    echo ""
    echo "  • digitalhuman-interface     — browser UI (no GPU, negligible RAM)"
    echo "  • digitalhuman-websocket-api — real-time relay (no GPU, negligible RAM)"
    echo "  • digitalhuman-asr           — NVIDIA Nemotron streaming ASR NIM"
    echo "                                 (requires NGC API key + ~15 GiB VRAM)"
    echo ""
    echo "When to install:"
    echo "  • You want a turn-key kiosk experience on this box"
    echo "  • You have VRAM headroom for ASR on top of your $RENNY_REPLICAS Renny replica(s)"
    echo ""
    echo "When to skip:"
    echo "  • You only need Renny (cloud STT via the customer's app)"
    echo "  • You are tight on VRAM"
    echo ""

    local choice
    while true; do
        read -p "Deploy the Digital Human stack? [y/N]: " choice
        choice="${choice:-n}"
        case "$choice" in
            [Yy]|[Yy][Ee][Ss])
                DEPLOY_DH_STACK="true"
                DEPLOY_DH_ASR="true"
                success "Digital Human stack will be deployed (interface + websocket-api + ASR)"
                break
                ;;
            [Nn]|[Nn][Oo])
                DEPLOY_DH_STACK="false"
                DEPLOY_DH_ASR="false"
                info "Skipping Digital Human stack"
                break
                ;;
            *)
                warning "Please answer y or n."
                ;;
        esac
    done

    echo ""
}

################################################################################
# VRAM-Fit Validation
################################################################################

# vram_per_renny — print VRAM (MB) per renny instance for current quality.
vram_per_renny() {
    if [[ "${CNS_QUALITY_LEVEL:-miniprem}" == "miniprem" ]]; then
        echo "$VRAM_PER_RENNY_MINIPREM_MB"
    else
        echo "$VRAM_PER_RENNY_WEB_MB"
    fi
}

# Compute worst-case VRAM used by the currently-selected profile, in MB.
compute_total_vram_mb() {
    local per_renny
    per_renny=$(vram_per_renny)
    local total=$((RENNY_REPLICAS * per_renny))

    if [[ "${CNS_INSTALL_MODE:-minimal}" == "full" ]]; then
        total=$((total + VRAM_LLM_RESERVE_MB))
    fi
    if [[ "${DEPLOY_DH_ASR:-false}" == "true" ]]; then
        total=$((total + VRAM_ASR_NEMOTRON_MB))
    fi
    total=$((total + VRAM_GPU_OVERHEAD_MB))
    echo "$total"
}

# Returns 0 if the selected configuration fits in detected GPU VRAM, 1 otherwise.
# If GPU VRAM is unknown (e.g. running on a host with no nvidia-smi) we
# conservatively return 0 (treat as fits) — there is no meaningful check we
# can do, and the existing prompt flow has already warned the user.
validate_vram_fit() {
    local gpu_vram="${GPU_VRAM_MB:-0}"
    if [[ "$gpu_vram" -le 0 ]]; then
        return 0
    fi

    # For multi-GPU we use the per-GPU figure, since renny pods are time-sliced
    # on a single GPU and ASR/LLM also pin to one. Cross-GPU scheduling is
    # outside scope of this check.
    local total
    total=$(compute_total_vram_mb)
    if [[ "$total" -le "$gpu_vram" ]]; then
        return 0
    fi
    return 1
}

# Print a human-readable breakdown of the VRAM math.
show_vram_breakdown() {
    local per_renny
    per_renny=$(vram_per_renny)
    local renny_total=$((RENNY_REPLICAS * per_renny))
    local gpu_vram="${GPU_VRAM_MB:-0}"
    local total
    total=$(compute_total_vram_mb)

    echo ""
    echo "VRAM budget for selected configuration:"
    echo "┌───────────────────────────────────────────────────────┬──────────────┐"
    printf "│ %-53s │ %-12s │\n" "Component" "VRAM"
    echo "├───────────────────────────────────────────────────────┼──────────────┤"
    printf "│ %-53s │ %9s MB │\n" "Renny × $RENNY_REPLICAS ($CNS_QUALITY_LEVEL @ ${per_renny}MB)" "$renny_total"
    if [[ "${CNS_INSTALL_MODE:-minimal}" == "full" ]]; then
        printf "│ %-53s │ %9s MB │\n" "Full-stack NIM LLM reserve" "$VRAM_LLM_RESERVE_MB"
    fi
    if [[ "${DEPLOY_DH_ASR:-false}" == "true" ]]; then
        printf "│ %-53s │ %9s MB │\n" "Nemotron streaming ASR NIM" "$VRAM_ASR_NEMOTRON_MB"
    fi
    printf "│ %-53s │ %9s MB │\n" "GPU/driver overhead" "$VRAM_GPU_OVERHEAD_MB"
    echo "├───────────────────────────────────────────────────────┼──────────────┤"
    printf "│ %-53s │ %9s MB │\n" "Total requested" "$total"
    printf "│ %-53s │ %9s MB │\n" "GPU available ($GPU_NAME)" "$gpu_vram"
    echo "└───────────────────────────────────────────────────────┴──────────────┘"
    echo ""
}

# compute_max_replicas_with_addons — given current install mode + quality + DH
# ASR choice, return the largest renny replica count that fits in GPU VRAM.
# Returns at least 1 (the script always deploys at least one renny).
compute_max_replicas_with_addons() {
    local per_renny
    per_renny=$(vram_per_renny)
    local gpu_vram="${GPU_VRAM_MB:-0}"
    local reserved=$VRAM_GPU_OVERHEAD_MB
    if [[ "${CNS_INSTALL_MODE:-minimal}" == "full" ]]; then
        reserved=$((reserved + VRAM_LLM_RESERVE_MB))
    fi
    if [[ "${DEPLOY_DH_ASR:-false}" == "true" ]]; then
        reserved=$((reserved + VRAM_ASR_NEMOTRON_MB))
    fi
    local available=$((gpu_vram - reserved))
    if [[ "$available" -lt "$per_renny" ]]; then
        echo "1"
        return
    fi
    echo "$((available / per_renny))"
}

################################################################################
# Install Profile Selection (mode / quality / replicas / DH stack)
################################################################################

# run_profile_prompts <force-interactive>
# Drives the existing mode → TTS → quality → replicas prompts, then the new
# Digital Human stack prompt. When force-interactive=true, environment-variable
# shortcuts are ignored (used on retry iterations of select_install_profile).
run_profile_prompts() {
    local force="${1:-false}"

    if [[ "$force" == "true" ]] || [[ -z "$CNS_INSTALL_MODE" ]]; then
        prompt_for_install_mode
    else
        info "Using install mode from environment: $CNS_INSTALL_MODE"
    fi

    if [[ "$force" == "true" ]] || [[ -z "$TTS_PROVIDER" ]]; then
        prompt_tts_provider
    else
        info "Using TTS provider from environment: $TTS_PROVIDER"
    fi

    if [[ "$force" == "true" ]] || [[ -z "$CNS_QUALITY_LEVEL" ]] || \
       [[ "$CNS_QUALITY_LEVEL" == "miniprem" && -z "${CNS_QUALITY_LEVEL_SET:-}" ]]; then
        prompt_for_quality_level
    else
        info "Using quality level from environment: $CNS_QUALITY_LEVEL"
    fi

    calculate_recommended_replicas

    if [[ "$force" == "true" ]] || [[ -z "${RENNY_REPLICAS_SET:-}" ]]; then
        prompt_for_renny_replicas
    else
        info "Using replica count from environment: $RENNY_REPLICAS"
    fi

    if [[ "$force" == "true" ]] || [[ -z "$DEPLOY_DH_STACK" ]]; then
        prompt_digitalhuman_stack
    else
        info "Using DH stack opt-in from environment: $DEPLOY_DH_STACK"
    fi
}

# select_install_profile — loop until the chosen mode/quality/replicas + DH
# stack opt-in fits in GPU VRAM. On a mismatch the user is shown a breakdown
# and a recommended replica count; they may accept the recommendation or restart
# the prompt sequence from the install-mode question.
select_install_profile() {
    local iteration=0
    while true; do
        iteration=$((iteration + 1))
        if [[ $iteration -eq 1 ]]; then
            run_profile_prompts "false"
        else
            run_profile_prompts "true"
        fi

        if validate_vram_fit; then
            return 0
        fi

        warning "Selected configuration exceeds GPU VRAM."
        show_vram_breakdown
        local recommended
        recommended=$(compute_max_replicas_with_addons)
        info "Recommended: ${recommended} Renny replica(s) with current addons."

        # Non-interactive (no TTY) — bail rather than spin forever.
        if [[ ! -t 0 ]]; then
            error "VRAM check failed and no TTY available to prompt for a fix."
            error "Reduce RENNY_REPLICAS or disable DH ASR/full-stack mode and rerun."
            exit 1
        fi

        local accept
        read -p "Accept recommended config (${recommended} replicas, keep current addons)? [Y/n]: " accept
        if [[ ! "$accept" =~ ^[Nn]$ ]]; then
            RENNY_REPLICAS="$recommended"
            # Keep GPU_TIMESLICE_REPLICAS in sync (mirrors logic in prompt_for_renny_replicas)
            GPU_TIMESLICE_REPLICAS=$((RENNY_REPLICAS / ${GPU_COUNT:-1}))
            [[ "$GPU_TIMESLICE_REPLICAS" -lt 1 ]] && GPU_TIMESLICE_REPLICAS=1
            success "Configured: $RENNY_REPLICAS Renny instance(s) (auto-adjusted)"
            return 0
        fi
        info "Restarting profile selection — answer the prompts again to pick a different mix."
        echo ""
    done
}

################################################################################
# Prerequisite Checks
################################################################################

# Detect package manager (needed by multiple functions)
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    else
        PKG_MANAGER=""
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

install_prerequisites() {
    info "Installing system prerequisites..."

    # Detect package manager
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    else
        warning "Unknown package manager. Some prerequisites may need manual installation."
        return
    fi

    # Install snapd (required for MicroK8s)
    if ! command -v snap &> /dev/null; then
        info "Installing snapd..."
        case "$PKG_MANAGER" in
            apt)
                apt-get update
                apt-get install -y snapd
                # Ensure snapd socket is running
                systemctl enable --now snapd.socket
                # Create symlink for classic snap support
                ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
                # Wait for snapd to be ready
                sleep 5
                ;;
            dnf|yum)
                $PKG_MANAGER install -y snapd
                systemctl enable --now snapd.socket
                ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
                sleep 5
                ;;
        esac
        success "snapd installed"
    else
        success "snapd already installed"
    fi

    # Install Google Chrome (required for MiniPrem kiosk interface)
    if ! command -v google-chrome &> /dev/null && ! command -v google-chrome-stable &> /dev/null; then
        info "Installing Google Chrome..."
        case "$PKG_MANAGER" in
            apt)
                # Download and install Chrome
                wget -q -O /tmp/google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
                apt-get install -y /tmp/google-chrome.deb || {
                    # If dependencies fail, fix them
                    apt-get install -f -y
                    apt-get install -y /tmp/google-chrome.deb
                }
                rm -f /tmp/google-chrome.deb
                ;;
            dnf|yum)
                # Add Chrome repo and install
                cat > /etc/yum.repos.d/google-chrome.repo << 'REPO'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
REPO
                $PKG_MANAGER install -y google-chrome-stable
                ;;
        esac
        success "Google Chrome installed"
    else
        success "Google Chrome already installed"
    fi

    # Install other common prerequisites
    # ansible-core is required: infrastructure (k8s + GPU operator + NIM
    # operator) is delegated to ansible/playbooks/cns-install.yml so the same
    # definition serves both local and remote deployments.
    info "Installing additional tools..."
    case "$PKG_MANAGER" in
        apt)
            apt-get install -y curl wget jq git ansible-core
            ;;
        dnf|yum)
            $PKG_MANAGER install -y curl wget jq git ansible-core
            ;;
    esac
    success "Prerequisites installed"
}

check_os() {
    info "Checking operating system..."

    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            ubuntu)
                if [[ "${VERSION_ID}" < "24.04" ]]; then
                    error "Ubuntu 24.04 LTS required (found $VERSION_ID)"
                    exit 1
                fi
                success "Ubuntu $VERSION_ID detected"
                ;;
            *)
                warning "Unsupported OS: $ID. Proceeding anyway..."
                ;;
        esac
    else
        warning "Could not detect OS version"
    fi
}

check_nvidia_gpu() {
    info "Checking for NVIDIA GPU..."

    if lspci | grep -qi nvidia; then
        success "NVIDIA GPU detected"
        lspci | grep -i nvidia | head -3
    else
        error "No NVIDIA GPU detected. CNS requires NVIDIA GPU hardware."
        exit 1
    fi
}

check_nvidia_driver() {
    info "Checking NVIDIA driver..."

    if command -v nvidia-smi &> /dev/null; then
        local driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
        local gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)

        success "NVIDIA driver installed: $driver_version"
        nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader

        # Validate driver version for Renny compatibility
        validate_driver_for_renny "$driver_version" "$gpu_name"
    else
        warning "NVIDIA driver not installed. Will be installed via GPU Operator."
    fi
}

validate_driver_for_renny() {
    local driver_version="$1"
    local gpu_name="$2"

    info "Validating driver version for Renny compatibility..."

    # Extract major.minor version (e.g., 580.82 from 580.82.09)
    local major_minor=$(echo "$driver_version" | cut -d. -f1,2)
    local major=$(echo "$driver_version" | cut -d. -f1)
    local minor=$(echo "$driver_version" | cut -d. -f2)

    # Known-bad: 580.126.x breaks NVENC hardware encoding on every GPU type.
    if [[ "$major_minor" == "580.126" ]]; then
        error "Driver $driver_version is INCOMPATIBLE with Renny!"
        echo ""
        echo "  Driver 580.126.x breaks NVENC hardware encoding on ALL GPU types."
        echo "  Use 580.82.x (renny-only) or 580.14x+ (renny + NIM/Triton/vLLM workloads)."
        echo ""
        echo "  To fix, install the recommended driver:"
        echo "    sudo DRIVER_VERSION=580.142 bash scripts/nvidia/install-nvidia-580.sh"
        echo ""
        read -p "Do you want to continue anyway? (y/N): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
        warning "Continuing with incompatible driver. Renny video encoding may fail."
        return
    fi

    # Allow list:
    #   580.82.x  - works for renny-only deploys. On this stack, NIM/Triton
    #               containers can hit cudaErrorInsufficientDriver because
    #               the GPU Operator's libcuda mount path resolves to an
    #               in-image compat library (see docs/troubleshooting.md).
    #   580.14x+  - tested working end-to-end on Blackwell + GPU Operator
    #               with NIM Magpie/Nemotron and vLLM. Recommended.
    if [[ "$major_minor" == "580.82" ]]; then
        success "Driver $driver_version is compatible with Renny"
        if [[ "$gpu_name" =~ "RTX 6000 Ada"|"Blackwell"|"RTX PRO 6000" ]]; then
            warning "If you plan to run NIM/Triton/vLLM containers on this host,"
            echo "  consider 580.142+ — 580.82.x has known CDI/libcuda mount"
            echo "  issues with NVIDIA NIM images that surface as CUDA error 35."
            echo "  Upgrade with: sudo bash scripts/nvidia/install-nvidia-580.sh"
        fi
        return
    fi

    if [[ "$major" -eq 580 ]] && [[ "$minor" -ge 140 ]]; then
        success "Driver $driver_version is compatible with Renny + NIM workloads"
        return
    fi

    # Too old
    if [[ "$major" -lt 550 ]]; then
        warning "Driver $driver_version may be too old for optimal Renny performance"
        echo "  Recommended: 580.142+ for renny + NIM, or 580.82.x for renny-only"
    fi

    # Newer-than-blessed: ok but flag
    if [[ "$major" -gt 580 ]] || ([[ "$major" -eq 580 ]] && [[ "$minor" -gt 142 ]] && [[ "$minor" -lt 159 ]]); then
        warning "Driver $driver_version is newer than our last-tested version (580.142)."
        echo "  Should be fine; report any NVENC/CUDA issues so we can update the allow-list."
    fi

    if [[ "$gpu_name" =~ "Blackwell" ]] || [[ "$gpu_name" =~ "RTX PRO 6000" ]] || [[ "$gpu_name" =~ "RTX 6000" ]]; then
        if [[ "$major" -ne 580 ]] || [[ "$minor" -lt 82 ]]; then
            warning "Blackwell/RTX PRO 6000 detected with driver $driver_version"
            echo ""
            echo "  Recommended: 580.142 (or 580.82.x for renny-only deploys):"
            echo "    sudo bash scripts/nvidia/install-nvidia-580.sh"
            echo ""
        fi
    fi
}

# Verify the GPU Operator's CDI spec matches the running driver.
# After a driver swap, /var/run/cdi/nvidia.yaml is pinned to the OLD driver's
# library filenames. Containers then get the in-image compat libcuda instead
# of the host driver, surfacing as `cudaErrorInsufficientDriver` (err 35).
check_cdi_spec_freshness() {
    local cdi_file=/var/run/cdi/nvidia.yaml

    if [ ! -f "$cdi_file" ]; then
        info "No CDI spec at $cdi_file (GPU Operator not yet installed — skipping check)."
        return 0
    fi

    if ! command -v nvidia-smi &>/dev/null; then
        return 0
    fi

    local host_driver
    host_driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1 | xargs)
    local cdi_driver
    cdi_driver=$(grep -oE "libcuda\.so\.[0-9.]+" "$cdi_file" | head -1 | sed 's/libcuda.so.//')

    if [ -z "$cdi_driver" ]; then
        warning "CDI spec at $cdi_file does not reference a libcuda version. Regenerating..."
        sudo nvidia-ctk cdi generate --output="$cdi_file" 2>/dev/null || true
        return 0
    fi

    if [ "$host_driver" = "$cdi_driver" ]; then
        success "CDI spec matches host driver ($host_driver)"
        return 0
    fi

    warning "CDI drift: host=$host_driver  CDI=$cdi_driver  →  regenerating spec"
    sudo nvidia-ctk cdi generate --output="$cdi_file"
    if kubectl get ds -n gpu-operator nvidia-device-plugin-daemonset &>/dev/null; then
        info "Restarting nvidia-device-plugin to pick up new CDI spec..."
        kubectl delete pod -n gpu-operator -l app=nvidia-device-plugin-daemonset --grace-period=10 || true
    fi
}

################################################################################
# Vulkan Setup for Renny (UE5 requires Vulkan rendering)
################################################################################

setup_vulkan_for_renny() {
    info "Setting up Vulkan for Renny..."

    # Install vulkan-tools for verification
    if ! command -v vulkaninfo &> /dev/null; then
        info "Installing vulkan-tools..."
        case "$PKG_MANAGER" in
            apt)
                apt-get update
                apt-get install -y vulkan-tools libvulkan1
                ;;
            dnf|yum)
                $PKG_MANAGER install -y vulkan-tools vulkan-loader
                ;;
        esac
    fi

    # Create NVIDIA Vulkan ICD file if missing
    local NVIDIA_ICD="/usr/share/vulkan/icd.d/nvidia_icd.json"
    if [[ ! -f "$NVIDIA_ICD" ]]; then
        info "Creating NVIDIA Vulkan ICD file..."
        mkdir -p /usr/share/vulkan/icd.d
        cat > "$NVIDIA_ICD" << 'EOF'
{
    "file_format_version" : "1.0.0",
    "ICD" : {
        "library_path" : "libGLX_nvidia.so.0",
        "api_version" : "1.3.275"
    }
}
EOF
        success "Created $NVIDIA_ICD"
    else
        success "NVIDIA Vulkan ICD already exists"
    fi

    # Verify Vulkan works (requires X display)
    if [[ -n "${DISPLAY:-}" ]] || [[ -S /tmp/.X11-unix/X1 ]]; then
        local test_display="${DISPLAY:-:1}"
        info "Testing Vulkan with DISPLAY=$test_display..."
        if DISPLAY="$test_display" vulkaninfo --summary 2>&1 | grep -q "NVIDIA"; then
            success "Vulkan NVIDIA driver detected and working"
        else
            warning "Vulkan test could not confirm NVIDIA driver"
        fi
    else
        warning "No X display available - skipping Vulkan verification"
    fi
}

################################################################################
# Xvfb Setup for Headless Rendering
################################################################################

setup_xvfb_for_renny() {
    info "Setting up Xvfb for headless Renny rendering..."

    # Install Xvfb if not present
    if ! command -v Xvfb &> /dev/null; then
        info "Installing Xvfb..."
        case "$PKG_MANAGER" in
            apt)
                apt-get update
                apt-get install -y xvfb x11-xserver-utils
                ;;
            dnf|yum)
                $PKG_MANAGER install -y xorg-x11-server-Xvfb
                ;;
        esac
    fi

    # Create systemd service for Xvfb persistence
    local XVFB_SERVICE="/etc/systemd/system/xvfb.service"
    if [[ ! -f "$XVFB_SERVICE" ]]; then
        info "Creating Xvfb systemd service..."
        cat > "$XVFB_SERVICE" << 'EOF'
[Unit]
Description=X Virtual Framebuffer for Renny
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/Xvfb :1 -screen 0 1920x1080x24 +extension GLX
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        success "Created Xvfb systemd service"
    fi

    # Enable and start Xvfb
    systemctl enable xvfb
    systemctl start xvfb || {
        warning "Failed to start Xvfb via systemd, starting manually..."
        pkill -9 Xvfb 2>/dev/null || true
        rm -f /tmp/.X1-lock /tmp/.X99-lock 2>/dev/null || true
        nohup Xvfb :1 -screen 0 1920x1080x24 +extension GLX &>/dev/null &
    }

    # Wait for X11 socket with retry loop (can take longer on fresh boot)
    info "Waiting for Xvfb socket to be ready..."
    local xvfb_retries=10
    while [[ $xvfb_retries -gt 0 ]]; do
        if [[ -S /tmp/.X11-unix/X1 ]]; then
            success "Xvfb running on :1"
            break
        fi
        echo "  Waiting for Xvfb socket... ($xvfb_retries attempts remaining)"
        sleep 2
        ((xvfb_retries--))
    done

    if [[ ! -S /tmp/.X11-unix/X1 ]]; then
        error "Failed to start Xvfb - /tmp/.X11-unix/X1 not found after 20 seconds"
        echo "  Try running manually: sudo Xvfb :1 -screen 0 1920x1080x24 &"
        exit 1
    fi

    # Export DISPLAY for subsequent commands
    export DISPLAY=:1
}

check_ngc_api_key() {
    # If the Digital Human ASR component is being deployed, the NGC key is
    # *required* (no skip path) and the prompt explicitly mentions the
    # Nemotron model terms.
    local require_key="false"
    if [[ "${DEPLOY_DH_ASR:-false}" == "true" ]]; then
        require_key="true"
    fi

    if [[ -z "$NGC_API_KEY" ]]; then
        warning "NGC_API_KEY not set. Required for NVIDIA model downloads."
        echo ""
        echo "To get an NGC API key:"
        echo "  1. Visit https://ngc.nvidia.com/"
        echo "  2. Sign in or create an account"
        echo "  3. Go to Setup > API Key"
        echo "  4. Generate and copy your API key"
        echo ""
        if [[ "$require_key" == "true" ]]; then
            echo "Additionally, the Nemotron streaming ASR model requires you to"
            echo "accept its terms before it can be pulled. Visit:"
            echo "  https://catalog.ngc.nvidia.com/orgs/nvidia/teams/nim/containers/nemotron-asr-streaming"
            echo "and click 'Accept Terms' while signed in to the same NGC account."
            echo ""
            while [[ -z "$NGC_API_KEY" ]]; do
                read -p "Enter NGC API Key: " NGC_API_KEY
                if [[ -z "$NGC_API_KEY" ]]; then
                    warning "An NGC API key is required when deploying the Digital Human ASR component."
                fi
            done
        else
            read -p "Enter NGC API Key (or press Enter to skip): " NGC_API_KEY
        fi
        export NGC_API_KEY
    fi

    if [[ -n "$NGC_API_KEY" ]]; then
        success "NGC API Key configured"
    else
        warning "Continuing without NGC API Key. Some features may not work."
    fi
}

################################################################################
# Infrastructure Installation (delegated to Ansible playbook)
################################################################################
#
# Why ansible: deploy-remote.sh already calls the same playbook over SSH; by
# running it locally with ansible_connection=local we share one definition for
# k8s + GPU operator + NIM operator across both deployment paths. This avoids
# the bug duplication we hit during early development (containerd version
# pinning, Calico-on-kernel-6.x quirks, iptables-nft alternative, etc.) where
# fixes had to be applied to two parallel implementations.
#
# The bash script keeps ownership of:
#   - OS-level prep for Renny rendering (Xvfb, Vulkan)
#   - Credential collection (Harbor, NGC, DHOP, TTS)
#   - Workload deployment (Renny helm + Digital Human helms)
#   - VRAM-fit validation
#   - Customer-facing prompts and progress UI
#
# Ansible owns:
#   - Kubernetes (microk8s OR kubeadm based on cns_k8s_type)
#   - Container runtime (containerd 1.7.x with CRI plugin enabled)
#   - CNI (Calico v3.29.3)
#   - GPU Operator + time-slicing configmap
#   - NIM Operator
#   - Phoenix observability
#
install_infra_via_ansible() {
    info "Installing infrastructure via ansible playbook..."

    if ! command -v ansible-playbook &> /dev/null; then
        error "ansible-playbook not found — install_prerequisites should have installed ansible-core."
        error "Re-run with --skip-resume or install manually: apt-get install -y ansible-core"
        return 1
    fi

    if [[ ! -f "$ANSIBLE_DIR/playbooks/cns-install.yml" ]]; then
        error "Ansible playbook not found at $ANSIBLE_DIR/playbooks/cns-install.yml"
        return 1
    fi

    # Use the bundled inventory at inventory/hosts.yml (not a temp file) so
    # ansible picks up the matching group_vars/cns.yml — that file defines
    # phoenix_namespace, miniprem_namespace, harbor_*, etc., which playbook
    # tasks reference. A temp inventory outside the inventory/ tree would
    # require us to re-declare every default as an extra-var.
    local inventory_file="$ANSIBLE_DIR/inventory/hosts.yml"
    if [[ ! -f "$inventory_file" ]]; then
        error "Ansible inventory not found at $inventory_file"
        return 1
    fi

    # Map deploy-local.sh state -> ansible extra vars. Anything not set here
    # falls back to defaults in inventory/hosts.yml, group_vars/cns.yml, and
    # vars/cns_versions.yml.
    local extra_vars=()
    extra_vars+=("-e" "cns_k8s_type=${CNS_K8S_TYPE:-kubeadm}")
    extra_vars+=("-e" "renny_replicas=${RENNY_REPLICAS:-2}")
    extra_vars+=("-e" "renny_namespace=${KUBE_NAMESPACE:-uneeq}")
    extra_vars+=("-e" "gpu_timeslice_replicas=${GPU_TIMESLICE_REPLICAS:-4}")

    # NGC key only needed for full-stack (LLM) or DH ASR. Always pass through
    # if set so the ansible task that creates the Secret has it.
    if [[ -n "${NGC_API_KEY:-}" ]]; then
        extra_vars+=("-e" "ngc_api_key=${NGC_API_KEY}")
    fi

    # Phoenix observability is included in full-stack mode (lots of LLM
    # telemetry to capture). For minimal mode it's unnecessary overhead.
    if [[ "${CNS_INSTALL_MODE:-minimal}" == "full" ]]; then
        extra_vars+=("-e" "phoenix_enabled=true")
    else
        extra_vars+=("-e" "phoenix_enabled=false")
    fi

    # NIM operator only needed for full-stack mode (it manages local LLM CRDs).
    if [[ "${CNS_INSTALL_MODE:-minimal}" == "full" ]]; then
        extra_vars+=("-e" "nim_operator_enabled=true")
    else
        extra_vars+=("-e" "nim_operator_enabled=false")
    fi

    info "Running: ansible-playbook playbooks/cns-install.yml (this may take 10-20 min)"
    info "Inventory: $inventory_file"
    info "Extra vars: ${extra_vars[*]}"

    # Run the playbook from the ansible/ directory so its relative paths work.
    if ! (cd "$ANSIBLE_DIR" && ansible-playbook \
            -i "$inventory_file" \
            playbooks/cns-install.yml \
            "${extra_vars[@]}"); then
        error "Ansible playbook failed. Check output above for the failed task."
        return 1
    fi

    success "Infrastructure ready (k8s + GPU operator + time-slicing)"
}

################################################################################
# MiniPrem Stack Deployment
################################################################################

deploy_miniprem_stack() {
    info "Deploying MiniPrem stack ($CNS_INSTALL_MODE mode)..."

    local KUBECTL="kubectl"
    local HELM="helm"

    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        KUBECTL="microk8s kubectl"
        HELM="microk8s helm3"
    fi

    # Set NIM_ENABLED based on install mode
    if [[ "$CNS_INSTALL_MODE" == "full" ]]; then
        NIM_ENABLED="true"
    else
        NIM_ENABLED="false"
    fi

    # Create namespaces (minimal set for minimal mode)
    local namespaces="uneeq miniprem"
    if [[ "$CNS_INSTALL_MODE" == "full" ]]; then
        namespaces="nim-operator nim-models nim-rag riva uneeq miniprem"
    fi

    for ns in $namespaces; do
        $KUBECTL create namespace "$ns" --dry-run=client -o yaml | $KUBECTL apply -f -
    done

    # Full stack mode: Install NIM Operator and LLM components
    if [[ "$CNS_INSTALL_MODE" == "full" ]]; then
        # Create NGC API secret if key is provided
        if [[ -n "$NGC_API_KEY" ]]; then
            info "Creating NGC API secret..."
            $KUBECTL create secret generic ngc-api-key \
                --from-literal=NGC_API_KEY="$NGC_API_KEY" \
                --namespace nim-operator \
                --dry-run=client -o yaml | $KUBECTL apply -f -
        fi

        # Install NIM Operator
        info "Installing NIM Operator..."
        $HELM repo add nvidia https://helm.ngc.nvidia.com/nvidia || true
        $HELM repo update

        $HELM upgrade --install nim-operator nvidia/k8s-nim-operator \
            --namespace nim-operator \
            --version "$NIM_OPERATOR_VERSION" \
            --wait --timeout 5m || warning "NIM Operator installation skipped or failed"

        # TODO: Deploy NIM LLM model (Llama 3.1, etc.)
        # TODO: Deploy NVIDIA Riva TTS (optional)
        # TODO: Deploy local Flowise instance
        info "Full stack components (NIM LLM, Riva TTS) will be deployed after Renny"
    else
        info "Minimal mode: Skipping NIM Operator and local LLM deployment"
    fi

    # Create Harbor registry secret for image pulls
    info "Creating Harbor registry secret..."
    $KUBECTL create secret docker-registry harbor-credentials \
        --docker-server=cr.uneeq.io \
        --docker-username="$HARBOR_USERNAME" \
        --docker-password="$HARBOR_PASSWORD" \
        --namespace uneeq \
        --dry-run=client -o yaml | $KUBECTL apply -f -

    # Deploy Renny via Helm
    info "Deploying Renny..."
    if [[ -f "$KUBERNETES_DIR/renny/Chart.yaml" ]]; then
        # Use CNS-specific values file
        local VALUES_FILE="$KUBERNETES_DIR/values/renny-values-cns.yaml"
        if [[ ! -f "$VALUES_FILE" ]]; then
            VALUES_FILE="$KUBERNETES_DIR/values/renny-values.yaml"
            warning "CNS values file not found, using default values"
        fi

        # Delete existing secrets to ensure clean update (renderer was renamed to renny)
        # Helm doesn't always update existing secrets during upgrade
        $KUBECTL delete secret renderer -n uneeq --ignore-not-found 2>/dev/null || true
        $KUBECTL delete secret renny -n uneeq --ignore-not-found 2>/dev/null || true

        # Build Helm command with all credentials
        local HELM_ARGS=(
            --namespace uneeq
            --values "$VALUES_FILE"
            --set deployment.totalReplicas="${RENNY_REPLICAS:-4}"
            --set deployment.nodeType=""
            --set renderer.qualityLevel="${CNS_QUALITY_LEVEL:-miniprem}"
            --set renderer.sdlAudioDriver="dummy"
            --set gpuTimeSlicing.replicasPerGpu="${GPU_TIMESLICE_REPLICAS:-4}"
            --set telemetry.platform="cns"
            # DHOP credentials (required)
            --set renderer.dhop.apiKey="$DHOP_APIKEY"
            --set renderer.dhop.tenantId="$DHOP_TENANTID"
            --set renderer.dhop.url="$DHOP_URL"
        )

        # Add TTS configuration based on selected provider
        case "$TTS_PROVIDER" in
            azure)
                HELM_ARGS+=(
                    --set renderer.tts.azureRegion="$AZURE_REGION"
                    --set renderer.tts.azureSpeechKey="$AZURE_SPEECH_KEY"
                )
                ;;
            elevenlabs)
                HELM_ARGS+=(
                    --set renderer.tts.elevenlabsApiKey="$ELEVEN_LABS_API_KEY"
                    --set renderer.tts.elevenlabsModelId="eleven_turbo_v2"
                )
                ;;
            rime)
                # RIME uses custom TTS proxy
                HELM_ARGS+=(
                    --set renderer.tts.proxyUrl="https://api.rime.ai/v1/tts"
                )
                # Note: RIME API key is typically set in persona config via Admin Portal
                ;;
            riva)
                # Riva is local - configure endpoint
                HELM_ARGS+=(
                    --set riva.enabled=true
                    --set riva.endpoint="localhost:50051"
                )
                ;;
        esac

        # Add NIM configuration for full stack mode
        if [[ "$CNS_INSTALL_MODE" == "full" ]]; then
            HELM_ARGS+=(
                --set nim.enabled=true
                --set nim.endpoint="http://localhost:8000/v1"
            )
        else
            HELM_ARGS+=(
                --set nim.enabled=false
            )
        fi

        $HELM upgrade --install renny "$KUBERNETES_DIR/renny" \
            "${HELM_ARGS[@]}" \
            --wait --timeout 10m || warning "Renny deployment skipped or failed"
    else
        warning "Renny Helm chart not found at $KUBERNETES_DIR/renny"
    fi

    success "MiniPrem stack deployment initiated"
}

################################################################################
# Digital Human Stack Deployment (additive – does not touch renny)
################################################################################

deploy_digitalhuman_stack() {
    info "Deploying Digital Human stack (interface, websocket-api, asr)..."

    local KUBECTL="kubectl"
    local HELM="helm"

    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        KUBECTL="microk8s kubectl"
        HELM="microk8s helm3"
    fi

    local NS="${KUBE_NAMESPACE:-uneeq}"
    local VALUES_DIR="$KUBERNETES_DIR/values"

    # ── Enable ingress addon if not already active ──────────────────────────
    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        microk8s enable ingress 2>/dev/null || true
    fi

    # ── Idempotent /etc/hosts entries ────────────────────────────────────────
    for host in digitalhuman digitalhuman-api digitalhuman-asr; do
        grep -q "${host}.miniprem" /etc/hosts 2>/dev/null || \
            echo "127.0.0.1 ${host}.miniprem" | sudo tee -a /etc/hosts > /dev/null
    done
    success "hostnames: digitalhuman.miniprem digitalhuman-api.miniprem digitalhuman-asr.miniprem"

    # ── NGC registry credentials (needed to pull Nemotron NIM image) ─────────
    if [[ "${DEPLOY_DH_ASR:-false}" == "true" ]] && [[ -n "${NGC_API_KEY:-}" ]]; then
        $KUBECTL create secret docker-registry ngc-registry-credentials \
            --docker-server=nvcr.io \
            --docker-username='$oauthtoken' \
            --docker-password="${NGC_API_KEY}" \
            -n "$NS" --dry-run=client -o yaml | $KUBECTL apply -f -

        $KUBECTL create secret generic nim-credentials \
            --from-literal=NGC_API_KEY="${NGC_API_KEY}" \
            -n "$NS" --dry-run=client -o yaml | $KUBECTL apply -f -

        success "NGC secrets provisioned in namespace ${NS}"
    fi

    # ── Install digitalhuman-interface ───────────────────────────────────────
    if should_run_stage "dh_interface"; then
        mark_progress "dh_interface"
        if [[ -f "$KUBERNETES_DIR/digitalhuman-interface/Chart.yaml" ]]; then
            $HELM upgrade --install digitalhuman-interface \
                "$KUBERNETES_DIR/digitalhuman-interface" \
                -f "$VALUES_DIR/digitalhuman-interface-values-cns.yaml" \
                -n "$NS" \
                --wait --timeout 5m || warning "digitalhuman-interface deployment skipped or failed"
            success "digitalhuman-interface deployed"
        fi
    else
        info "Resume: digitalhuman-interface already completed — skipping"
    fi

    # ── Install digitalhuman-websocket-api ───────────────────────────────────
    if should_run_stage "dh_websocket_api"; then
        mark_progress "dh_websocket_api"
        if [[ -f "$KUBERNETES_DIR/digitalhuman-websocket-api/Chart.yaml" ]]; then
            local WS_ARGS=()
            if [[ -n "${DH_WS_API_KEY:-}" ]]; then
                WS_ARGS+=(--set "secrets.httpServiceApiKey=${DH_WS_API_KEY}")
            fi
            if [[ -n "${DEEPGRAM_API_KEY:-}" ]]; then
                WS_ARGS+=(--set "secrets.deepgramApiKey=${DEEPGRAM_API_KEY}")
            fi

            $HELM upgrade --install digitalhuman-ws-api \
                "$KUBERNETES_DIR/digitalhuman-websocket-api" \
                -f "$VALUES_DIR/digitalhuman-websocket-api-values-cns.yaml" \
                -n "$NS" \
                "${WS_ARGS[@]}" \
                --wait --timeout 5m || warning "digitalhuman-websocket-api deployment skipped or failed"
            success "digitalhuman-websocket-api deployed"
        fi
    else
        info "Resume: digitalhuman-websocket-api already completed — skipping"
    fi

    # ── Install digitalhuman-asr (only if user opted in to ASR) ──────────────
    if [[ "${DEPLOY_DH_ASR:-false}" == "true" ]] && [[ -f "$KUBERNETES_DIR/digitalhuman-asr/Chart.yaml" ]]; then
        if should_run_stage "dh_asr"; then
            mark_progress "dh_asr"
            deploy_asr_with_terms_handling "$KUBECTL" "$HELM" "$NS" "$VALUES_DIR"
        else
            info "Resume: digitalhuman-asr already completed — skipping"
        fi
    fi

    success "Digital Human stack deployment complete"
}

# deploy_asr_with_terms_handling — installs the ASR helm chart with a fast
# initial helm timeout, then watches the pod and reacts to a likely
# "model terms not accepted" failure by pausing and asking the user to accept
# the terms before retrying. Returns when the pod is Running (success) or the
# user explicitly chose to skip ASR (recoverable failure).
deploy_asr_with_terms_handling() {
    local KUBECTL="$1"
    local HELM="$2"
    local NS="$3"
    local VALUES_DIR="$4"

    info "Installing digitalhuman-asr (Nemotron streaming NIM)..."

    # Short helm timeout so we get control back quickly; we drive readiness
    # ourselves via the pod-watch loop below.
    $HELM upgrade --install digitalhuman-asr \
        "$KUBERNETES_DIR/digitalhuman-asr" \
        -f "$VALUES_DIR/digitalhuman-asr-values-cns.yaml" \
        -n "$NS" \
        --timeout 30s 2>/dev/null || true

    local outer_deadline=$(( $(date +%s) + 900 ))   # 15 min hard ceiling
    local saw_terms_error=false

    while true; do
        if [[ $(date +%s) -ge $outer_deadline ]]; then
            warning "digitalhuman-asr did not become ready within 15 minutes."
            handle_asr_failure "$KUBECTL" "$NS" "timeout" || return 1
            return 0
        fi

        # Get the first ASR pod. Use label selector from chart.
        local pod
        pod=$($KUBECTL get pods -n "$NS" -l app=digitalhuman-asr -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [[ -z "$pod" ]]; then
            sleep 5
            continue
        fi

        local phase ready_count
        phase=$($KUBECTL get pod "$pod" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        ready_count=$($KUBECTL get pod "$pod" -n "$NS" -o jsonpath='{.status.containerStatuses[?(@.ready==true)].name}' 2>/dev/null | wc -w | tr -d ' ')

        if [[ "$phase" == "Running" ]] && [[ "$ready_count" -gt 0 ]]; then
            success "digitalhuman-asr is Running"
            return 0
        fi

        # Look for image-pull failures + terms-related reasons.
        local waiting_reason
        waiting_reason=$($KUBECTL get pod "$pod" -n "$NS" -o jsonpath='{.status.containerStatuses[*].state.waiting.reason}' 2>/dev/null || echo "")
        if [[ "$waiting_reason" == *"ImagePullBackOff"* ]] || [[ "$waiting_reason" == *"ErrImagePull"* ]]; then
            local events
            events=$($KUBECTL describe pod "$pod" -n "$NS" 2>/dev/null | tail -40)
            if echo "$events" | grep -iE '(401|403|unauthorized|forbidden|terms|EULA|agreement)' >/dev/null; then
                if [[ "$saw_terms_error" == "false" ]]; then
                    saw_terms_error=true
                    mark_progress "dh_asr" "asr_terms_pending"
                    print_asr_terms_banner
                fi
                # Block waiting for user to confirm terms acceptance.
                if [[ ! -t 0 ]]; then
                    error "Terms acceptance required, but no TTY available."
                    error "Accept terms at the URL above, then rerun the script."
                    return 1
                fi
                local reply
                read -p "Press Enter once you have accepted the terms (or type 'skip' to skip ASR): " reply
                if [[ "$reply" == "skip" ]]; then
                    warning "Skipping digitalhuman-asr at user request"
                    $HELM uninstall digitalhuman-asr -n "$NS" 2>/dev/null || true
                    return 0
                fi
                info "Retrying ASR image pull..."
                $KUBECTL delete pod "$pod" -n "$NS" --force --grace-period=0 2>/dev/null || true
                sleep 5
                continue
            else
                # Some other pull failure — present the generic resolution menu.
                warning "digitalhuman-asr image pull failed (reason: $waiting_reason)"
                echo "Recent pod events:"
                echo "$events" | tail -15
                handle_asr_failure "$KUBECTL" "$NS" "image_pull_failed" || return 1
                return 0
            fi
        fi

        sleep 10
    done
}

# Print a prominent banner explaining how to accept the NIM model terms.
print_asr_terms_banner() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════════════╗"
    echo "║              NVIDIA NIM Model Terms Acceptance Required                       ║"
    echo "╠═══════════════════════════════════════════════════════════════════════════════╣"
    echo "║                                                                               ║"
    echo "║  The Nemotron streaming ASR image pull was rejected. This is almost always   ║"
    echo "║  because the model terms have not been accepted on your NGC account.         ║"
    echo "║                                                                               ║"
    echo "║  To resolve:                                                                  ║"
    echo "║    1. In a browser, sign in to https://ngc.nvidia.com using the same         ║"
    echo "║       account whose NGC API key you supplied to this installer.              ║"
    echo "║    2. Visit the model page:                                                  ║"
    echo "║                                                                               ║"
    echo "║       https://catalog.ngc.nvidia.com/orgs/nvidia/teams/nim/containers/       ║"
    echo "║       nemotron-asr-streaming                                                  ║"
    echo "║                                                                               ║"
    echo "║    3. Click 'Accept Terms' (or 'Request Access' followed by 'Accept').       ║"
    echo "║                                                                               ║"
    echo "║  Then press Enter below to retry the pull.                                   ║"
    echo "║  Or type 'skip' (then Enter) to skip the ASR component for this install.     ║"
    echo "║                                                                               ║"
    echo "║  You can also abort with Ctrl-C; the deployment state will be saved and      ║"
    echo "║  rerunning this script will offer to resume from this step.                  ║"
    echo "║                                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
}

# handle_asr_failure — present a 3-option recovery menu for non-terms ASR
# failures. Returns 0 if the user chose retry or skip (caller continues),
# 1 if they chose to abort (caller should return 1 to bubble up).
handle_asr_failure() {
    local KUBECTL="$1"
    local NS="$2"
    local code="$3"

    if [[ ! -t 0 ]]; then
        error "ASR deployment failed ($code) and no TTY is available for recovery."
        return 1
    fi

    echo ""
    echo "Digital Human ASR deployment failed. How would you like to proceed?"
    echo "  1) Retry — delete the pod and try again"
    echo "  2) Skip ASR for this install (keeps interface + websocket-api)"
    echo "  3) Abort — save progress and exit (rerun to resume from this step)"
    echo ""
    local choice
    while true; do
        read -p "Enter choice [1-3] (default: 3): " choice
        choice="${choice:-3}"
        case "$choice" in
            1)
                local pod
                pod=$($KUBECTL get pods -n "$NS" -l app=digitalhuman-asr -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
                if [[ -n "$pod" ]]; then
                    $KUBECTL delete pod "$pod" -n "$NS" --force --grace-period=0 2>/dev/null || true
                fi
                return 0
                ;;
            2)
                warning "Skipping digitalhuman-asr at user request"
                local HELM_CMD="helm"
                [[ "$CNS_K8S_TYPE" == "microk8s" ]] && HELM_CMD="microk8s helm3"
                $HELM_CMD uninstall digitalhuman-asr -n "$NS" 2>/dev/null || true
                return 0
                ;;
            3)
                mark_progress "dh_asr" "asr_$code"
                error "Aborting at user request. Progress saved to $CNS_PROGRESS_FILE."
                error "Rerun this script to resume from the digitalhuman-asr stage."
                exit 1
                ;;
            *)
                warning "Please enter 1, 2, or 3."
                ;;
        esac
    done
}

################################################################################
# Telemetry Consent
################################################################################

prompt_for_telemetry_consent() {
    echo "
┌─────────────────────────────────────────────────────────────────────────────┐
│                          MiniPrem Telemetry Notice                           │
├─────────────────────────────────────────────────────────────────────────────┤
│ This installation sends anonymous usage data to UneeQ:                       │
│                                                                             │
│ ✓ Installation notification (one-time)                                      │
│ ✓ Heartbeat every 15 minutes to monitor uptime                              │
│                                                                             │
│ Data collected (NO personally identifiable information):                    │
│   • Anonymous installation ID (generated locally)                           │
│   • GPU hardware identifier (one-way SHA-256 hash)                          │
│   • MiniPrem version and deployment type                                    │
│   • System uptime and health status                                         │
│                                                                             │
│ We DO NOT collect:                                                          │
│   ✗ IP addresses, hostnames, or network identifiers                         │
│   ✗ UneeQ credentials, API keys, or tokens                                  │
│   ✗ Conversation data or chat history                                       │
│   ✗ Any content processed by Renny                                          │
│   ✗ Customer information                                                    │
│                                                                             │
│ Privacy: See docs/TELEMETRY.md for full details                             │
└─────────────────────────────────────────────────────────────────────────────┘
"
    echo ""
    read -p "Do you consent to anonymous telemetry? [Y/n] " telemetry_consent
    telemetry_consent="${telemetry_consent:-Y}"

    if [[ "$telemetry_consent" =~ ^[Yy]$ ]]; then
        TELEMETRY_ENABLED=true
        success "Telemetry enabled - thank you for helping improve MiniPrem!"
    else
        TELEMETRY_ENABLED=false
        warning "Telemetry disabled - continuing with installation"
    fi
    echo ""
}

################################################################################
# Verification
################################################################################

verify_deployment() {
    info "Verifying deployment..."

    local KUBECTL="kubectl"
    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        KUBECTL="microk8s kubectl"
    fi

    echo ""
    echo "=== Cluster Status ==="
    $KUBECTL get nodes

    echo ""
    echo "=== GPU Resources ==="
    $KUBECTL get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'

    echo ""
    echo "=== Namespaces ==="
    $KUBECTL get namespaces

    echo ""
    echo "=== GPU Operator Pods ==="
    $KUBECTL get pods -n gpu-operator

    echo ""
    echo "=== MiniPrem Pods ==="
    $KUBECTL get pods -n uneeq 2>/dev/null || echo "No pods in uneeq namespace yet"

    echo ""
    success "CNS deployment verification complete"
}

################################################################################
# Main
################################################################################

main() {
    # Show UneeQ logo first
    print_logo

    echo "
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║        ███╗   ███╗██╗███╗   ██╗██╗██████╗ ██████╗ ███████╗███╗   ███╗         ║
║        ████╗ ████║██║████╗  ██║██║██╔══██╗██╔══██╗██╔════╝████╗ ████║         ║
║        ██╔████╔██║██║██╔██╗ ██║██║██████╔╝██████╔╝█████╗  ██╔████╔██║         ║
║        ██║╚██╔╝██║██║██║╚██╗██║██║██╔═══╝ ██╔══██╗██╔══╝  ██║╚██╔╝██║         ║
║        ██║ ╚═╝ ██║██║██║ ╚████║██║██║     ██║  ██║███████╗██║ ╚═╝ ██║         ║
║        ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝         ║
║                                                                               ║
║               Cloud Native Stack (CNS) Installation                           ║
╚═══════════════════════════════════════════════════════════════════════════════╝
"

    # Prerequisite checks
    CLEANUP_STAGE="system checks"
    check_root
    detect_package_manager  # Needed by setup functions
    check_os
    check_nvidia_gpu
    check_nvidia_driver

    # Detect GPU configuration early (needed for replica recommendations)
    detect_gpu_info

    echo ""

    # Load saved configuration if available
    load_cns_config || true

    # =========================================================================
    # RESUME PROMPT (if a previous run left a progress file behind)
    # =========================================================================

    if load_progress; then
        echo ""
        info "A previous deployment did not complete. Last stage: ${CNS_PROGRESS_STAGE:-unknown}"
        if [[ -n "${CNS_PROGRESS_LAST_ERROR:-}" ]]; then
            info "Last error: ${CNS_PROGRESS_LAST_ERROR}"
        fi
        local resume_choice
        read -p "Resume from where it left off? [Y/n]: " resume_choice
        if [[ ! "$resume_choice" =~ ^[Nn]$ ]]; then
            CNS_RESUME=true
            success "Resuming from stage: ${CNS_PROGRESS_STAGE}"
        else
            clear_progress
            CNS_RESUME=false
        fi
        echo ""
    fi

    # =========================================================================
    # CREDENTIAL COLLECTION (like Docker install_miniprem.sh)
    # =========================================================================

    # Harbor registry credentials (required to pull Renny images)
    ensure_harbor_credentials

    # Region selection (US/EU) - affects DHOP endpoint
    if [[ -z "$UNEEQ_REGION" ]] || [[ -z "${UNEEQ_REGION_SET:-}" ]]; then
        prompt_for_region
    else
        info "Using region from environment: $UNEEQ_REGION"
        if [[ "$UNEEQ_REGION" == "eu" ]]; then
            DHOP_URL="wss://api-eu.enterprise.uneeq.io:443/signalling-service"
        else
            DHOP_URL="wss://api.enterprise.uneeq.io:443/signalling-service"
        fi
    fi

    # UneeQ platform credentials (DHOP API key and Tenant ID)
    if [[ -z "$DHOP_APIKEY" ]] || [[ -z "$DHOP_TENANTID" ]]; then
        prompt_dhop_credentials
    else
        info "Using DHOP credentials from environment/config"
    fi

    # =========================================================================
    # INSTALLATION PROFILE SELECTION (mode → quality → replicas → DH stack)
    # Wraps the existing prompts in a VRAM-fit loop so the DH stack opt-in is
    # validated against the detected GPU before installation begins.
    #
    # On resume we trust the saved config + progress and skip the profile
    # prompts entirely — the user's earlier choices are still committed.
    # =========================================================================

    if [[ "$CNS_RESUME" == "true" ]]; then
        info "Resume: keeping saved profile (mode=$CNS_INSTALL_MODE, quality=$CNS_QUALITY_LEVEL, replicas=$RENNY_REPLICAS, DH=$DEPLOY_DH_STACK)"
        # Compute recommended values that didn't get persisted (used downstream)
        calculate_recommended_replicas
    else
        select_install_profile
    fi

    # Save configuration for future runs (after the VRAM-fit loop settled)
    save_cns_config

    # =========================================================================
    # TELEMETRY CONSENT (last step before installation begins)
    # =========================================================================

    prompt_for_telemetry_consent

    # =========================================================================
    # INSTALLATION BEGINS
    # =========================================================================

    echo ""
    echo "Starting installation..."
    echo ""

    # Install prerequisites (snap, Chrome, etc.)
    if should_run_stage "prerequisites"; then
        CLEANUP_STAGE="prerequisites"
        mark_progress "prerequisites"
        start_spinner "Installing system prerequisites..."
        install_prerequisites 2>&1 | tail -20
        stop_spinner 0 "Prerequisites installed"
    else
        info "Resume: prerequisites already completed — skipping"
    fi

    echo ""

    # Setup Xvfb for headless rendering (needed before Vulkan check)
    if should_run_stage "xvfb_setup"; then
        CLEANUP_STAGE="Xvfb setup"
        mark_progress "xvfb_setup"
        start_spinner "Setting up Xvfb for headless rendering..."
        setup_xvfb_for_renny 2>&1 | tail -10
        stop_spinner 0 "Xvfb configured"
    else
        info "Resume: Xvfb setup already completed — skipping"
    fi

    # Setup Vulkan (requires NVIDIA driver and X display)
    if should_run_stage "vulkan_setup"; then
        CLEANUP_STAGE="Vulkan setup"
        mark_progress "vulkan_setup"
        start_spinner "Setting up Vulkan for Renny..."
        setup_vulkan_for_renny 2>&1 | tail -10
        stop_spinner 0 "Vulkan configured"
    else
        info "Resume: Vulkan setup already completed — skipping"
    fi

    echo ""

    # NGC API key — only needed for full-stack mode (NIM LLM) or DH ASR.
    if should_run_stage "ngc_key"; then
        mark_progress "ngc_key"
        if [[ "$CNS_INSTALL_MODE" == "full" ]] || [[ "${DEPLOY_DH_ASR:-false}" == "true" ]]; then
            check_ngc_api_key
        else
            info "Skipping NGC API key prompt (not required for this configuration)"
        fi
    else
        info "Resume: NGC key step already completed — skipping"
    fi

    echo ""
    echo "Installing Kubernetes infrastructure (via ansible playbook)..."
    echo ""

    # Single stage covers k8s + GPU operator + time-slicing + NIM operator +
    # (optionally) Phoenix. Ansible is idempotent, so resume is automatic — a
    # re-run on a healthy cluster is a no-op. We collapse the two former stages
    # (kubernetes_install, gpu_timeslicing) into one because ansible handles
    # both atomically.
    if should_run_stage "kubernetes_install"; then
        CLEANUP_STAGE="Infrastructure (ansible)"
        mark_progress "kubernetes_install"
        case "$CNS_K8S_TYPE" in
            microk8s|kubeadm)
                install_infra_via_ansible
                ;;
            *)
                error "Unknown Kubernetes type: $CNS_K8S_TYPE"
                exit 1
                ;;
        esac
        # gpu_timeslicing stage is now part of the playbook — mark complete
        # so resume logic stays consistent with the stage_index list.
        mark_progress "gpu_timeslicing"
    else
        info "Resume: Infrastructure already completed — skipping"
    fi

    # Deploy MiniPrem stack
    if should_run_stage "renny_deploy"; then
        CLEANUP_STAGE="Renny deployment"
        mark_progress "renny_deploy"
        start_spinner "Deploying Renny via Helm..."
        deploy_miniprem_stack 2>&1 | tail -20
        stop_spinner 0 "Renny deployed"
    else
        info "Resume: Renny deployment already completed — skipping"
    fi

    # Deploy Digital Human stack only when the user opted in.
    if [[ "${DEPLOY_DH_STACK:-false}" == "true" ]]; then
        CLEANUP_STAGE="Digital Human deployment"
        # Note: stage-level should_run_stage guard happens inside the function
        # at the per-component level (dh_interface, dh_websocket_api, dh_asr).
        deploy_digitalhuman_stack
    else
        info "Skipping Digital Human stack (opted out)"
    fi

    # Disable cleanup trap for successful completion
    CLEANUP_ENABLED=false

    # Verify deployment
    if should_run_stage "verify"; then
        mark_progress "verify"
        verify_deployment
    fi

    # Clear progress file on successful completion so the next run starts clean.
    clear_progress

    echo ""
    echo "
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║                      CNS Installation Complete!                               ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
"

    # Configuration summary
    echo "Configuration Summary:"
    echo "┌─────────────────────────────────────────────────────────────────────────┐"
    printf "│ %-71s │\n" "Installation Mode: $CNS_INSTALL_MODE"
    printf "│ %-71s │\n" "Quality Level: $CNS_QUALITY_LEVEL"
    printf "│ %-71s │\n" "Renny Replicas: $RENNY_REPLICAS"
    printf "│ %-71s │\n" "GPU Time-Slices per GPU: $GPU_TIMESLICE_REPLICAS"
    printf "│ %-71s │\n" "GPU: $GPU_NAME (${GPU_VRAM_GB:-0}GB VRAM)"
    printf "│ %-71s │\n" "TTS Provider: $TTS_PROVIDER"
    printf "│ %-71s │\n" "Region: $UNEEQ_REGION"
    echo "└─────────────────────────────────────────────────────────────────────────┘"

    echo ""
    echo "Access URLs:"
    echo "┌─────────────────────────────────────────────────────────────────────────┐"
    if [[ "$UNEEQ_REGION" == "eu" ]]; then
        printf "│ %-71s │\n" "DHOP Dashboard: https://dashboard-eu.enterprise.uneeq.io"
        printf "│ %-71s │\n" "Admin Portal:   https://admin-eu.enterprise.uneeq.io"
    else
        printf "│ %-71s │\n" "DHOP Dashboard: https://dashboard.enterprise.uneeq.io"
        printf "│ %-71s │\n" "Admin Portal:   https://admin.enterprise.uneeq.io"
    fi
    echo "└─────────────────────────────────────────────────────────────────────────┘"

    echo ""
    echo "Next Steps:"
    echo ""
    echo "  1. Check deployment status:"
    echo "     ./miniprem.sh status"
    echo ""
    echo "  2. View Renny pod logs:"
    echo "     ./miniprem.sh logs"
    echo ""
    echo "  3. Scale Renny instances:"
    echo "     ./miniprem.sh scale"
    echo ""
    echo "  4. Upgrade MiniPrem (pull latest):"
    echo "     ./miniprem.sh upgrade"
    echo ""

    if [[ "$CNS_INSTALL_MODE" == "full" ]]; then
        echo "Full Stack Mode Notes:"
        echo "  - NIM Operator has been installed for local LLM support"
        echo "  - Configure your NIM LLM model in the nim-models namespace"
        echo "  - NVIDIA Riva TTS can be deployed for local speech synthesis"
        echo ""
    else
        echo "Minimal Mode Notes:"
        echo "  - Renny will use cloud TTS (ElevenLabs, Azure, etc.)"
        echo "  - Flowise connection is required for conversational AI"
        echo "  - To upgrade to Full Stack: re-run with CNS_INSTALL_MODE=full"
        echo ""
    fi

    success "Installation complete! Your digital humans are ready."
    echo ""
}

main "$@"
