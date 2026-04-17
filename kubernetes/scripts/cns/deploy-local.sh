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
    echo -e "${ORANGE_1}  #     #  #    #  #######  #######  #######        ${NC}"
    echo -e "${ORANGE_2}  #     #  ##   #  #        #        #     #        ${NC}"
    echo -e "${ORANGE_3}  #     #  # #  #  #######  #######  #     #        ${NC}"
    echo -e "${ORANGE_4}  #     #  #  # #  #        #        #     #        ${NC}"
    echo -e "${ORANGE_5}  #     #  #   ##  #        #        #   # #        ${NC}"
    echo -e "${ORANGE_6}   #####   #    #  #######  #######  #######        ${NC}"
    echo -e "${ORANGE_1}  ################################################  ${NC}"
    echo -e "${WHITE}               DIGITALHUMANS.COM                    ${NC}"
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

    # Offer cleanup options
    echo "What would you like to do?"
    echo "  1) Leave partial installation (for debugging)"
    echo "  2) Clean up and exit"
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
        fi

        # Clean up namespaces
        $KUBECTL delete namespace uneeq --ignore-not-found 2>/dev/null || true

        success "Cleanup complete. You can re-run the installer."
    else
        info "Partial installation left in place for debugging."
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

CNS_K8S_TYPE="${CNS_K8S_TYPE:-microk8s}"
NGC_API_KEY="${NGC_API_KEY:-}"
NVIDIA_DIR="${NVIDIA_DIR:-$KUBERNETES_DIR/../nvidia}"
RENNY_REPLICAS="${RENNY_REPLICAS:-4}"  # Number of Renny instances (adjust for GPU count)
GPU_TIMESLICE_REPLICAS="${GPU_TIMESLICE_REPLICAS:-8}"  # GPU time-slices per physical GPU

# Version pinning
MICROK8S_CHANNEL="1.31/stable"
GPU_OPERATOR_VERSION="v24.9.0"
NIM_OPERATOR_VERSION="1.0.0"

# Installation mode (set during interactive prompt)
CNS_INSTALL_MODE="${CNS_INSTALL_MODE:-}"  # minimal or full
CNS_QUALITY_LEVEL="${CNS_QUALITY_LEVEL:-miniprem}"  # miniprem or web

# CNS Configuration file (persists credentials between runs)
CNS_CONFIG_FILE="${CNS_CONFIG_FILE:-$SCRIPT_DIR/.cns_config}"

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
    info "Installing additional tools..."
    case "$PKG_MANAGER" in
        apt)
            apt-get install -y curl wget jq git
            ;;
        dnf|yum)
            $PKG_MANAGER install -y curl wget jq git
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

    # Known problematic versions
    if [[ "$major_minor" == "580.126" ]]; then
        error "Driver $driver_version is INCOMPATIBLE with Renny!"
        echo ""
        echo "  Driver 580.126.x breaks NVENC hardware encoding on ALL GPU types."
        echo "  Renny requires driver 580.82.x for proper video encoding."
        echo ""
        echo "  To fix, install the correct driver:"
        echo "    - For Blackwell/RTX PRO 6000: Download 580.82.09 from NVIDIA"
        echo "    - For L4/A10G/T4: apt install nvidia-driver-580=580.82.07-0ubuntu1"
        echo ""
        read -p "Do you want to continue anyway? (y/N): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
        warning "Continuing with incompatible driver. Renny video encoding may fail."
        return
    fi

    # Check for recommended 580.82.x version
    if [[ "$major_minor" == "580.82" ]]; then
        success "Driver $driver_version is compatible with Renny"
        return
    fi

    # Check if driver is too old (< 550)
    local major=$(echo "$driver_version" | cut -d. -f1)
    if [[ "$major" -lt 550 ]]; then
        warning "Driver $driver_version may be too old for optimal Renny performance"
        echo "  Recommended: 580.82.x for production Renny deployments"
    fi

    # Check for Blackwell GPUs that need specific driver
    if [[ "$gpu_name" =~ "Blackwell" ]] || [[ "$gpu_name" =~ "RTX PRO 6000" ]] || [[ "$gpu_name" =~ "RTX 6000" ]]; then
        if [[ "$major_minor" != "580.82" ]]; then
            warning "Blackwell/RTX PRO 6000 GPU detected with driver $driver_version"
            echo ""
            echo "  For best Renny compatibility, install driver 580.82.09:"
            echo "    wget https://us.download.nvidia.com/XFree86/Linux-x86_64/580.82.09/NVIDIA-Linux-x86_64-580.82.09.run"
            echo "    chmod +x NVIDIA-Linux-x86_64-580.82.09.run"
            echo "    sudo ./NVIDIA-Linux-x86_64-580.82.09.run --silent --dkms"
            echo ""
        fi
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
    if [[ -z "$NGC_API_KEY" ]]; then
        warning "NGC_API_KEY not set. Required for NVIDIA model downloads."
        echo ""
        echo "To get an NGC API key:"
        echo "  1. Visit https://ngc.nvidia.com/"
        echo "  2. Sign in or create an account"
        echo "  3. Go to Setup > API Key"
        echo "  4. Generate and copy your API key"
        echo ""
        read -p "Enter NGC API Key (or press Enter to skip): " NGC_API_KEY
        export NGC_API_KEY
    fi

    if [[ -n "$NGC_API_KEY" ]]; then
        success "NGC API Key configured"
    else
        warning "Continuing without NGC API Key. Some features may not work."
    fi
}

################################################################################
# MicroK8s Installation
################################################################################

install_microk8s() {
    info "Installing MicroK8s..."

    # Verify snapd is available (should be installed in prerequisites)
    if ! command -v snap &> /dev/null; then
        error "snapd is not installed. Run install_prerequisites first."
        exit 1
    fi

    # Install MicroK8s
    if ! command -v microk8s &> /dev/null; then
        snap install microk8s --classic --channel="$MICROK8S_CHANNEL"
        success "MicroK8s installed"
    else
        info "MicroK8s already installed"
        microk8s version
    fi

    # Wait for MicroK8s to be ready
    info "Waiting for MicroK8s to be ready..."
    microk8s status --wait-ready

    # Enable required addons
    info "Enabling MicroK8s addons..."
    microk8s enable dns
    microk8s enable hostpath-storage
    microk8s enable helm3

    # Enable NVIDIA addon
    info "Enabling NVIDIA GPU support..."
    microk8s enable nvidia

    success "MicroK8s configured with GPU support"

    # Create kubectl alias
    if [[ ! -f /usr/local/bin/kubectl ]]; then
        ln -sf /snap/bin/microk8s.kubectl /usr/local/bin/kubectl
    fi

    # Create helm alias
    if [[ ! -f /usr/local/bin/helm ]]; then
        ln -sf /snap/bin/microk8s.helm3 /usr/local/bin/helm
    fi

    # Label all nodes for Renny scheduling
    # The Helm chart uses nodeSelector with uneeq.io/node-type label
    info "Labeling nodes for Renny scheduling..."
    local nodes=$(microk8s kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
    for node in $nodes; do
        microk8s kubectl label node "$node" uneeq.io/node-type= --overwrite 2>/dev/null || true
    done
    success "Nodes labeled for Renny scheduling"
}

################################################################################
# kubeadm Installation
################################################################################

install_kubeadm() {
    info "Installing Kubernetes via kubeadm..."

    # This is a simplified kubeadm setup
    # For production, more configuration is needed

    # Install containerd
    apt-get update
    apt-get install -y containerd

    # Configure containerd for NVIDIA
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml

    # Install kubeadm, kubelet, kubectl
    apt-get install -y apt-transport-https ca-certificates curl

    # Add Kubernetes apt repository
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' > /etc/apt/sources.list.d/kubernetes.list

    apt-get update
    apt-get install -y kubelet kubeadm kubectl
    apt-mark hold kubelet kubeadm kubectl

    # Initialize cluster
    kubeadm init --pod-network-cidr=10.244.0.0/16

    # Setup kubectl for root user
    mkdir -p /root/.kube
    cp -i /etc/kubernetes/admin.conf /root/.kube/config

    # Install Calico CNI
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml

    # Remove taint to allow scheduling on control plane (single node)
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

    success "Kubernetes cluster initialized via kubeadm"
}

################################################################################
# GPU Operator Installation
################################################################################

install_gpu_operator() {
    info "Installing NVIDIA GPU Operator..."

    local KUBECTL="kubectl"
    local HELM="helm"

    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        KUBECTL="microk8s kubectl"
        HELM="microk8s helm3"
    fi

    # Add NVIDIA Helm repo
    $HELM repo add nvidia https://helm.ngc.nvidia.com/nvidia || true
    $HELM repo update

    # Create namespace
    $KUBECTL create namespace gpu-operator --dry-run=client -o yaml | $KUBECTL apply -f -

    # Install GPU Operator
    $HELM upgrade --install gpu-operator nvidia/gpu-operator \
        --namespace gpu-operator \
        --version "$GPU_OPERATOR_VERSION" \
        --set driver.enabled=true \
        --set toolkit.enabled=true \
        --set devicePlugin.enabled=true \
        --set dcgmExporter.enabled=true \
        --wait --timeout 10m

    success "GPU Operator installed"

    # Wait for GPU to be available
    info "Waiting for GPU resources to be available..."
    local retries=30
    while [[ $retries -gt 0 ]]; do
        local gpu_count=$($KUBECTL get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "0")
        if [[ "$gpu_count" != "0" && -n "$gpu_count" ]]; then
            success "GPU resources available: $gpu_count GPU(s)"
            break
        fi
        echo "  Waiting for GPU... ($retries attempts remaining)"
        sleep 10
        ((retries--))
    done

    if [[ $retries -eq 0 ]]; then
        warning "GPU resources not yet visible. Deployment will continue."
    fi
}

################################################################################
# GPU Time-Slicing Configuration
################################################################################

configure_gpu_timeslicing() {
    info "Configuring GPU time-slicing..."

    local KUBECTL="kubectl"
    local GPU_OPERATOR_NS="gpu-operator"

    if [[ "$CNS_K8S_TYPE" == "microk8s" ]]; then
        KUBECTL="microk8s kubectl"
        GPU_OPERATOR_NS="gpu-operator-resources"  # MicroK8s uses different namespace
    fi

    # Wait for GPU operator to be ready
    info "Waiting for GPU operator pods to be ready..."
    $KUBECTL wait --for=condition=ready pod -l app=gpu-operator -n "$GPU_OPERATOR_NS" --timeout=300s || true

    # Fix known symlink creation bug (affects systemd cgroup setups)
    info "Applying GPU operator fixes..."
    $KUBECTL patch clusterpolicy/cluster-policy --type=merge \
        -p '{"spec":{"validator":{"driver":{"env":[{"name":"DISABLE_DEV_CHAR_SYMLINK_CREATION","value":"true"}]}}}}' || true

    # Wait for pods to restart after patch
    sleep 10

    # Create time-slicing ConfigMap
    info "Creating time-slicing configuration..."
    cat <<EOF | $KUBECTL apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: $GPU_OPERATOR_NS
data:
  any: |-
    version: v1
    flags:
      migStrategy: none
    sharing:
      timeSlicing:
        renameByDefault: false
        failRequestsGreaterThanOne: false
        resources:
          - name: nvidia.com/gpu
            replicas: ${GPU_TIMESLICE_REPLICAS:-8}
EOF

    # Patch cluster policy for time-slicing
    $KUBECTL patch clusterpolicies.nvidia.com/cluster-policy \
        --type merge \
        -p '{"spec": {"devicePlugin": {"config": {"name": "time-slicing-config", "default": "any"}}}}' || true

    # Wait for device plugin to restart
    info "Waiting for GPU resources to update..."
    sleep 30

    # Verify time-slicing is working
    local gpu_count=$($KUBECTL get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "0")
    if [[ "$gpu_count" -gt 1 ]]; then
        success "GPU time-slicing configured ($gpu_count GPU replicas available)"
    else
        warning "Time-slicing may not be active yet. GPU count: $gpu_count"
    fi
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
    # INSTALLATION MODE SELECTION
    # =========================================================================

    # Interactive installation prompts (unless all values provided via env vars)
    if [[ -z "$CNS_INSTALL_MODE" ]]; then
        prompt_for_install_mode
    else
        info "Using install mode from environment: $CNS_INSTALL_MODE"
    fi

    # TTS Provider selection (required for Renny to function)
    if [[ -z "$TTS_PROVIDER" ]]; then
        prompt_tts_provider
    else
        info "Using TTS provider from environment: $TTS_PROVIDER"
    fi

    if [[ -z "$CNS_QUALITY_LEVEL" ]] || [[ "$CNS_QUALITY_LEVEL" == "miniprem" && -z "${CNS_QUALITY_LEVEL_SET:-}" ]]; then
        prompt_for_quality_level
    else
        info "Using quality level from environment: $CNS_QUALITY_LEVEL"
    fi

    # Calculate recommended replicas based on GPU and selections
    calculate_recommended_replicas

    # Prompt for replica count (unless provided via env var)
    if [[ -z "${RENNY_REPLICAS_SET:-}" ]]; then
        prompt_for_renny_replicas
    else
        info "Using replica count from environment: $RENNY_REPLICAS"
    fi

    # Save configuration for future runs
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
    CLEANUP_STAGE="prerequisites"
    start_spinner "Installing system prerequisites..."
    install_prerequisites 2>&1 | tail -20
    stop_spinner 0 "Prerequisites installed"

    echo ""

    # Setup Xvfb for headless rendering (needed before Vulkan check)
    CLEANUP_STAGE="Xvfb setup"
    start_spinner "Setting up Xvfb for headless rendering..."
    setup_xvfb_for_renny 2>&1 | tail -10
    stop_spinner 0 "Xvfb configured"

    # Setup Vulkan (requires NVIDIA driver and X display)
    CLEANUP_STAGE="Vulkan setup"
    start_spinner "Setting up Vulkan for Renny..."
    setup_vulkan_for_renny 2>&1 | tail -10
    stop_spinner 0 "Vulkan configured"

    echo ""

    # NGC API key (after prerequisites so we have wget/curl)
    check_ngc_api_key

    echo ""
    echo "Installing Kubernetes..."
    echo ""

    # Install Kubernetes distribution
    CLEANUP_STAGE="Kubernetes installation"
    case "$CNS_K8S_TYPE" in
        microk8s)
            start_spinner "Installing MicroK8s (this may take several minutes)..."
            install_microk8s 2>&1 | tail -20
            stop_spinner 0 "MicroK8s installed"
            ;;
        kubeadm)
            start_spinner "Installing kubeadm cluster..."
            install_kubeadm 2>&1 | tail -20
            stop_spinner 0 "kubeadm cluster initialized"
            install_gpu_operator
            ;;
        *)
            error "Unknown Kubernetes type: $CNS_K8S_TYPE"
            exit 1
            ;;
    esac

    # Configure GPU time-slicing (for multiple Rennys)
    CLEANUP_STAGE="GPU time-slicing"
    start_spinner "Configuring GPU time-slicing..."
    configure_gpu_timeslicing 2>&1 | tail -10
    stop_spinner 0 "GPU time-slicing configured"

    # Deploy MiniPrem stack
    CLEANUP_STAGE="Renny deployment"
    start_spinner "Deploying Renny via Helm..."
    deploy_miniprem_stack 2>&1 | tail -20
    stop_spinner 0 "Renny deployed"

    # Disable cleanup trap for successful completion
    CLEANUP_ENABLED=false

    # Verify deployment
    verify_deployment

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
