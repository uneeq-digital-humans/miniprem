#!/bin/bash

################################################################################
# MiniPrem CNS Upgrade Script
#
# Applies configuration changes to the running CNS deployment.
# Loads saved credentials from .cns_config to preserve authentication.
#
# Usage:
#   ./upgrade.sh                    # Apply values file changes (interactive)
#   ./upgrade.sh --restart          # Just restart pods (no helm upgrade)
#   ./upgrade.sh --replicas 5       # Change replica count
#   ./upgrade.sh --clear-secrets    # Clear TTS/LLM secrets (use Admin Portal config)
#
################################################################################

set -euo pipefail

# Script directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBERNETES_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
VALUES_FILE="$KUBERNETES_DIR/values/renny-values-cns.yaml"
CHART_DIR="$KUBERNETES_DIR/renny"
CNS_CONFIG_FILE="$SCRIPT_DIR/.cns_config"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

print_color() { echo -e "${1}${2}${NC}"; }
info() { print_color "$BLUE" "ℹ️  $*"; }
success() { print_color "$GREEN" "✅ $*"; }
warning() { print_color "$YELLOW" "⚠️  $*"; }
error() { print_color "$RED" "❌ $*"; }

################################################################################
# Detect kubectl/helm commands
################################################################################

if command -v microk8s &> /dev/null; then
    KUBECTL="microk8s kubectl"
    HELM="microk8s helm3"
else
    KUBECTL="kubectl"
    HELM="helm"
fi

################################################################################
# Load saved configuration
################################################################################

load_config() {
    if [[ -f "$CNS_CONFIG_FILE" ]]; then
        info "Loading saved configuration..."
        source "$CNS_CONFIG_FILE"
        return 0
    else
        warning "No saved configuration found at $CNS_CONFIG_FILE"
        warning "Credentials will need to be provided manually or will be empty."
        return 1
    fi
}

################################################################################
# Parse arguments
################################################################################

REPLICAS=""
RESTART_ONLY=false
CLEAR_SECRETS=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --replicas|-r)
            REPLICAS="$2"
            shift 2
            ;;
        --restart)
            RESTART_ONLY=true
            shift
            ;;
        --clear-secrets|--clear-tts)
            CLEAR_SECRETS=true
            shift
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        --help|-h)
            echo ""
            print_color "$BOLD" "MiniPrem CNS Upgrade"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --replicas, -r <N>     Set number of Renny replicas"
            echo "  --restart              Only restart pods (no helm upgrade)"
            echo "  --clear-secrets        Clear TTS/LLM API keys (use Admin Portal config)"
            echo "  --force, -f            Skip confirmation prompts"
            echo "  --help, -h             Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                     # Apply values file changes"
            echo "  $0 --replicas 5        # Scale to 5 replicas"
            echo "  $0 --restart           # Restart pods without config change"
            echo "  $0 --clear-secrets     # Remove TTS keys (use Admin Portal config)"
            echo ""
            echo "This script loads credentials from: $CNS_CONFIG_FILE"
            echo ""
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

################################################################################
# Main
################################################################################

print_color "$BOLD" "
╔═══════════════════════════════════════════════════════════════╗
║                   MiniPrem CNS Upgrade                        ║
╚═══════════════════════════════════════════════════════════════╝
"

# Check prerequisites
if [[ ! -f "$VALUES_FILE" ]]; then
    error "Values file not found: $VALUES_FILE"
    exit 1
fi

if [[ ! -d "$CHART_DIR" ]]; then
    error "Helm chart not found: $CHART_DIR"
    exit 1
fi

# Check if deployment exists
if ! $KUBECTL get deployment renny -n uneeq &>/dev/null 2>&1; then
    error "No Renny deployment found in uneeq namespace"
    echo ""
    echo "Use './miniprem.sh deploy' to deploy first."
    exit 1
fi

# Load saved configuration
load_config || true

# Get current state
info "Current deployment status:"
$KUBECTL get deployment renny -n uneeq -o wide 2>/dev/null
echo ""

CURRENT_REPLICAS=$($KUBECTL get deployment renny -n uneeq -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
info "Current replicas: $CURRENT_REPLICAS"

# Handle restart-only mode
if [[ "$RESTART_ONLY" == "true" ]]; then
    info "Restarting Renny pods..."
    $KUBECTL rollout restart deployment/renny -n uneeq

    info "Waiting for pods to be ready..."
    $KUBECTL rollout status deployment/renny -n uneeq --timeout=300s

    success "Pods restarted successfully"
    echo ""
    $KUBECTL get pods -n uneeq
    exit 0
fi

# Build helm upgrade command
HELM_ARGS=(
    upgrade renny "$CHART_DIR"
    --namespace uneeq
    --values "$VALUES_FILE"
)

# Add replica count if specified
if [[ -n "$REPLICAS" ]]; then
    HELM_ARGS+=(--set "deployment.totalReplicas=$REPLICAS")
    info "Setting replicas to: $REPLICAS"
fi

# Add credentials from saved config (if available)
if [[ -n "${DHOP_APIKEY:-}" && -n "${DHOP_TENANTID:-}" ]]; then
    info "Using saved DHOP credentials"
    HELM_ARGS+=(
        --set "renderer.dhop.apiKey=$DHOP_APIKEY"
        --set "renderer.dhop.tenantId=$DHOP_TENANTID"
    )

    # Set DHOP URL based on region
    if [[ "${UNEEQ_REGION:-us}" == "eu" ]]; then
        HELM_ARGS+=(--set "renderer.dhop.url=wss://api-eu.enterprise.uneeq.io:443/signalling-service")
    else
        HELM_ARGS+=(--set "renderer.dhop.url=wss://api.enterprise.uneeq.io:443/signalling-service")
    fi
else
    warning "No DHOP credentials found - deployment may not work correctly"
    if [[ "$FORCE" != "true" ]]; then
        read -p "Continue anyway? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 0
        fi
    fi
fi

# Handle TTS configuration
if [[ "$CLEAR_SECRETS" == "true" ]]; then
    info "Clearing TTS secrets (will use Admin Portal configuration)"
    HELM_ARGS+=(
        --set "renderer.tts.azureRegion="
        --set "renderer.tts.azureSpeechKey="
        --set "renderer.tts.elevenlabsApiKey="
        --set "renderer.tts.elevenlabsModelId="
        --set "renderer.tts.veritoneApiKey="
        --set "renderer.tts.gcpCredentials="
    )
else
    # Add TTS credentials from saved config based on provider
    case "${TTS_PROVIDER:-}" in
        azure)
            if [[ -n "${AZURE_SPEECH_KEY:-}" ]]; then
                info "Using saved Azure TTS credentials"
                HELM_ARGS+=(
                    --set "renderer.tts.azureRegion=$AZURE_REGION"
                    --set "renderer.tts.azureSpeechKey=$AZURE_SPEECH_KEY"
                )
            fi
            ;;
        elevenlabs)
            if [[ -n "${ELEVEN_LABS_API_KEY:-}" ]]; then
                info "Using saved ElevenLabs credentials"
                HELM_ARGS+=(
                    --set "renderer.tts.elevenlabsApiKey=$ELEVEN_LABS_API_KEY"
                    --set "renderer.tts.elevenlabsModelId=eleven_turbo_v2"
                )
            fi
            ;;
        rime)
            if [[ -n "${RIME_API_KEY:-}" ]]; then
                info "Using saved RIME credentials"
                # RIME uses proxy URL
            fi
            ;;
        *)
            # No TTS provider saved - TTS configured in Admin Portal
            info "No TTS provider in config - using Admin Portal configuration"
            ;;
    esac
fi

# Add quality level and other settings from config
if [[ -n "${CNS_QUALITY_LEVEL:-}" ]]; then
    HELM_ARGS+=(--set "renderer.qualityLevel=$CNS_QUALITY_LEVEL")
fi

# Show what will be changed
echo ""
print_color "$BOLD" "Upgrade Summary:"
echo "  Values file: $VALUES_FILE"
echo "  Replicas: ${REPLICAS:-from values file}"
echo "  DHOP: ${DHOP_TENANTID:+configured}${DHOP_TENANTID:-NOT CONFIGURED}"
echo "  TTS: ${TTS_PROVIDER:-Admin Portal}"
if [[ "$CLEAR_SECRETS" == "true" ]]; then
    echo "  Secrets: CLEARING (use Admin Portal)"
fi
echo ""

# Confirm unless --force
if [[ "$FORCE" != "true" ]]; then
    read -p "Apply these changes? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

# Delete existing secret to ensure clean update
# (Helm doesn't always update existing secrets correctly)
info "Preparing for upgrade..."
$KUBECTL delete secret renny -n uneeq --ignore-not-found 2>/dev/null || true

# Run helm upgrade
info "Applying configuration changes..."
if $HELM "${HELM_ARGS[@]}" --wait --timeout 10m; then
    success "Helm upgrade completed"
else
    error "Helm upgrade failed"
    exit 1
fi

# Restart pods to pick up changes
info "Restarting Renny pods to apply changes..."
$KUBECTL rollout restart deployment/renny -n uneeq

info "Waiting for pods to be ready..."
$KUBECTL rollout status deployment/renny -n uneeq --timeout=300s || {
    warning "Timeout waiting for pods - they may still be starting"
}

# Show final status
echo ""
success "Upgrade completed successfully!"
echo ""
info "Current pod status:"
$KUBECTL get pods -n uneeq -o wide

echo ""
info "Useful commands:"
echo "  ./miniprem.sh logs      # Watch pod logs"
echo "  ./miniprem.sh status    # Check deployment status"
echo "  ./miniprem.sh restart   # Restart pods again"
